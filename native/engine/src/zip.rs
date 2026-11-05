//! Streaming ZIP export (stored, no compression — media is never
//! re-encoded and photos/videos do not compress anyway).
//!
//! CRC-32 values are computed once when an upload completes, so the full
//! archive layout — and therefore its exact length — is known before the
//! first byte is sent. That allows `Content-Length`, progress reporting and
//! HTTP `Range` requests (resumable ZIP downloads) without temp files.
//! ZIP64 records are emitted only when sizes/offsets require them.

use std::collections::HashSet;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub enum Segment {
    Bytes(Vec<u8>),
    File { path: PathBuf, len: u64 },
}

impl Segment {
    pub fn len(&self) -> u64 {
        match self {
            Segment::Bytes(b) => b.len() as u64,
            Segment::File { len, .. } => *len,
        }
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

pub struct ZipInput {
    pub name: String,
    pub path: PathBuf,
    pub size: u64,
    pub crc32: u32,
    pub mtime_ms: i64,
}

const U32_MAX: u64 = 0xFFFF_FFFF;

fn dos_datetime(ms: i64) -> (u16, u16) {
    // Civil-from-days (UTC). DOS time has no zone; UTC is a reasonable choice.
    let secs = ms.div_euclid(1000);
    let days = secs.div_euclid(86_400);
    let sod = secs.rem_euclid(86_400);
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    if y < 1980 {
        return (0, (1 << 5) | 1);
    }
    let time = ((sod / 3600) << 11) | (((sod % 3600) / 60) << 5) | ((sod % 60) / 2);
    let date = ((y - 1980).min(127) << 9) | (m << 5) | d;
    (time as u16, date as u16)
}

/// Makes entry names unique: `a.jpg`, `a (2).jpg`, …
pub fn unique_names(names: &[String]) -> Vec<String> {
    let mut seen = HashSet::new();
    names
        .iter()
        .map(|n| {
            let mut candidate = n.clone();
            let (stem, ext) = match n.rsplit_once('.') {
                Some((s, e)) if !s.is_empty() => (s.to_string(), format!(".{e}")),
                _ => (n.clone(), String::new()),
            };
            let mut i = 2;
            while !seen.insert(candidate.to_lowercase()) {
                candidate = format!("{stem} ({i}){ext}");
                i += 1;
            }
            candidate
        })
        .collect()
}

/// Builds the archive as a list of segments.
pub fn build(entries: &[ZipInput]) -> Vec<Segment> {
    let mut segs = Vec::with_capacity(entries.len() * 2 + 1);
    let mut central = Vec::new();
    let mut offset: u64 = 0;

    for e in entries {
        let name = e.name.as_bytes();
        let (time, date) = dos_datetime(e.mtime_ms);
        let zip64 = e.size >= U32_MAX;
        let mut local = Vec::with_capacity(30 + name.len() + 20);
        local.extend_from_slice(&0x0403_4b50u32.to_le_bytes());
        local.extend_from_slice(&(if zip64 { 45u16 } else { 20u16 }).to_le_bytes());
        local.extend_from_slice(&0x0800u16.to_le_bytes()); // UTF-8 names
        local.extend_from_slice(&0u16.to_le_bytes()); // stored
        local.extend_from_slice(&time.to_le_bytes());
        local.extend_from_slice(&date.to_le_bytes());
        local.extend_from_slice(&e.crc32.to_le_bytes());
        let sz32 = if zip64 { U32_MAX as u32 } else { e.size as u32 };
        local.extend_from_slice(&sz32.to_le_bytes());
        local.extend_from_slice(&sz32.to_le_bytes());
        local.extend_from_slice(&(name.len() as u16).to_le_bytes());
        local.extend_from_slice(&(if zip64 { 20u16 } else { 0u16 }).to_le_bytes());
        local.extend_from_slice(name);
        if zip64 {
            local.extend_from_slice(&1u16.to_le_bytes());
            local.extend_from_slice(&16u16.to_le_bytes());
            local.extend_from_slice(&e.size.to_le_bytes());
            local.extend_from_slice(&e.size.to_le_bytes());
        }
        let header_offset = offset;
        offset += local.len() as u64 + e.size;
        segs.push(Segment::Bytes(local));
        segs.push(Segment::File { path: e.path.clone(), len: e.size });

        // Central directory record.
        let offset64 = header_offset >= U32_MAX;
        let mut extra = Vec::new();
        if zip64 {
            extra.extend_from_slice(&e.size.to_le_bytes());
            extra.extend_from_slice(&e.size.to_le_bytes());
        }
        if offset64 {
            extra.extend_from_slice(&header_offset.to_le_bytes());
        }
        let needs64 = zip64 || offset64;
        central.extend_from_slice(&0x0201_4b50u32.to_le_bytes());
        central.extend_from_slice(&(if needs64 { 45u16 } else { 20u16 }).to_le_bytes());
        central.extend_from_slice(&(if needs64 { 45u16 } else { 20u16 }).to_le_bytes());
        central.extend_from_slice(&0x0800u16.to_le_bytes());
        central.extend_from_slice(&0u16.to_le_bytes());
        central.extend_from_slice(&time.to_le_bytes());
        central.extend_from_slice(&date.to_le_bytes());
        central.extend_from_slice(&e.crc32.to_le_bytes());
        central.extend_from_slice(&sz32.to_le_bytes());
        central.extend_from_slice(&sz32.to_le_bytes());
        central.extend_from_slice(&(name.len() as u16).to_le_bytes());
        let extra_len = if extra.is_empty() { 0 } else { extra.len() + 4 };
        central.extend_from_slice(&(extra_len as u16).to_le_bytes());
        central.extend_from_slice(&0u16.to_le_bytes()); // comment
        central.extend_from_slice(&0u16.to_le_bytes()); // disk
        central.extend_from_slice(&0u16.to_le_bytes()); // internal attrs
        central.extend_from_slice(&0u32.to_le_bytes()); // external attrs
        let off32 = if offset64 { U32_MAX as u32 } else { header_offset as u32 };
        central.extend_from_slice(&off32.to_le_bytes());
        central.extend_from_slice(name);
        if !extra.is_empty() {
            central.extend_from_slice(&1u16.to_le_bytes());
            central.extend_from_slice(&(extra.len() as u16).to_le_bytes());
            central.extend_from_slice(&extra);
        }
    }

    let cd_offset = offset;
    let cd_size = central.len() as u64;
    let count = entries.len() as u64;
    let mut tail = central;
    let needs64 = count >= 0xFFFF || cd_offset >= U32_MAX || cd_size >= U32_MAX;
    if needs64 {
        let eocd64_offset = cd_offset + cd_size;
        tail.extend_from_slice(&0x0606_4b50u32.to_le_bytes());
        tail.extend_from_slice(&44u64.to_le_bytes());
        tail.extend_from_slice(&45u16.to_le_bytes());
        tail.extend_from_slice(&45u16.to_le_bytes());
        tail.extend_from_slice(&0u32.to_le_bytes());
        tail.extend_from_slice(&0u32.to_le_bytes());
        tail.extend_from_slice(&count.to_le_bytes());
        tail.extend_from_slice(&count.to_le_bytes());
        tail.extend_from_slice(&cd_size.to_le_bytes());
        tail.extend_from_slice(&cd_offset.to_le_bytes());
        tail.extend_from_slice(&0x0706_4b50u32.to_le_bytes());
        tail.extend_from_slice(&0u32.to_le_bytes());
        tail.extend_from_slice(&eocd64_offset.to_le_bytes());
        tail.extend_from_slice(&1u32.to_le_bytes());
    }
    tail.extend_from_slice(&0x0605_4b50u32.to_le_bytes());
    tail.extend_from_slice(&0u16.to_le_bytes());
    tail.extend_from_slice(&0u16.to_le_bytes());
    let c16 = if count >= 0xFFFF { 0xFFFF } else { count as u16 };
    tail.extend_from_slice(&c16.to_le_bytes());
    tail.extend_from_slice(&c16.to_le_bytes());
    tail.extend_from_slice(&(if cd_size >= U32_MAX { U32_MAX as u32 } else { cd_size as u32 }).to_le_bytes());
    tail.extend_from_slice(&(if cd_offset >= U32_MAX { U32_MAX as u32 } else { cd_offset as u32 }).to_le_bytes());
    tail.extend_from_slice(&0u16.to_le_bytes());
    segs.push(Segment::Bytes(tail));
    segs
}

pub fn total_len(segs: &[Segment]) -> u64 {
    segs.iter().map(|s| s.len()).sum()
}

/// Writes `segs[start..=end]` (byte range, inclusive) to `w`.
pub async fn write_range<W>(segs: &[Segment], start: u64, end: u64, w: &mut W) -> std::io::Result<()>
where
    W: tokio::io::AsyncWrite + Unpin,
{
    use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};
    let mut pos = 0u64;
    for seg in segs {
        let seg_len = seg.len();
        let seg_start = pos;
        let seg_end = pos + seg_len; // exclusive
        pos = seg_end;
        if seg_end <= start || seg_len == 0 {
            continue;
        }
        if seg_start > end {
            break;
        }
        let from = start.saturating_sub(seg_start);
        let to = (end + 1).min(seg_end) - seg_start; // exclusive within segment
        match seg {
            Segment::Bytes(b) => w.write_all(&b[from as usize..to as usize]).await?,
            Segment::File { path, .. } => {
                let mut f = tokio::fs::File::open(path).await?;
                f.seek(std::io::SeekFrom::Start(from)).await?;
                let mut remaining = to - from;
                let mut buf = vec![0u8; 256 * 1024];
                while remaining > 0 {
                    let want = remaining.min(buf.len() as u64) as usize;
                    let n = f.read(&mut buf[..want]).await?;
                    if n == 0 {
                        return Err(std::io::Error::new(std::io::ErrorKind::UnexpectedEof, "media file shrank during export"));
                    }
                    w.write_all(&buf[..n]).await?;
                    remaining -= n as u64;
                }
            }
        }
    }
    w.flush().await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dos_time_known_value() {
        // 2024-03-15 13:45:30 UTC
        let (t, d) = dos_datetime(1_710_510_330_000);
        assert_eq!(d, ((2024 - 1980) << 9) | (3 << 5) | 15);
        assert_eq!(t, (13 << 11) | (45 << 5) | 15);
    }

    #[test]
    fn unique() {
        let v = unique_names(&["a.jpg".into(), "A.jpg".into(), "a.jpg".into(), "b".into(), "b".into()]);
        assert_eq!(v, vec!["a.jpg", "A (2).jpg", "a (3).jpg", "b", "b (2)"]);
    }
}
