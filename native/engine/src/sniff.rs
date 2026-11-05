//! Content sniffing. The server never trusts the client's filename or MIME
//! type: the final media type is derived from the file's magic bytes.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Photo,
    Video,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Photo => "photo",
            Kind::Video => "video",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MediaType {
    pub kind: Kind,
    pub mime: &'static str,
    pub ext: &'static str,
}

const fn mt(kind: Kind, mime: &'static str, ext: &'static str) -> MediaType {
    MediaType { kind, mime, ext }
}

/// Extensions accepted at upload creation (before content is available).
pub const ALLOWED_EXTENSIONS: &[&str] = &[
    "jpg", "jpeg", "png", "gif", "webp", "heic", "heif", "avif", "mp4", "m4v", "mov", "3gp", "3g2", "webm", "mkv", "avi",
];

pub fn is_allowed_extension(ext: &str) -> bool {
    ALLOWED_EXTENSIONS.contains(&ext)
}

/// Kind implied by an (allowed) extension — used for display before upload completes.
pub fn kind_for_extension(ext: &str) -> Kind {
    match ext {
        "mp4" | "m4v" | "mov" | "3gp" | "3g2" | "webm" | "mkv" | "avi" => Kind::Video,
        _ => Kind::Photo,
    }
}

/// Detects the media type from the first bytes of the file.
/// `client_ext` (already lower-cased) is used only to choose between
/// equivalent containers (e.g. `.mov` vs `.mp4` for ISO-BMFF files).
pub fn sniff(head: &[u8], client_ext: &str) -> Option<MediaType> {
    if head.starts_with(&[0xFF, 0xD8, 0xFF]) {
        return Some(mt(Kind::Photo, "image/jpeg", "jpg"));
    }
    if head.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Some(mt(Kind::Photo, "image/png", "png"));
    }
    if head.starts_with(b"GIF87a") || head.starts_with(b"GIF89a") {
        return Some(mt(Kind::Photo, "image/gif", "gif"));
    }
    if head.len() >= 12 && &head[0..4] == b"RIFF" {
        match &head[8..12] {
            b"WEBP" => return Some(mt(Kind::Photo, "image/webp", "webp")),
            b"AVI " => return Some(mt(Kind::Video, "video/x-msvideo", "avi")),
            _ => return None,
        }
    }
    if head.starts_with(&[0x1A, 0x45, 0xDF, 0xA3]) {
        let is_webm = client_ext == "webm" || contains(head, b"webm");
        return Some(if is_webm {
            mt(Kind::Video, "video/webm", "webm")
        } else {
            mt(Kind::Video, "video/x-matroska", "mkv")
        });
    }
    if head.len() >= 12 && &head[4..8] == b"ftyp" {
        let box_len = u32::from_be_bytes([head[0], head[1], head[2], head[3]]) as usize;
        let end = box_len.clamp(12, head.len());
        let mut brands: Vec<&[u8]> = vec![&head[8..12]];
        let mut i = 16;
        while i + 4 <= end {
            brands.push(&head[i..i + 4]);
            i += 4;
        }
        let major = brands[0];
        let has = |b: &[u8]| brands.contains(&b);
        if matches!(major, b"heic" | b"heix" | b"hevc" | b"hevx" | b"heim" | b"heis") {
            return Some(mt(Kind::Photo, "image/heic", "heic"));
        }
        if matches!(major, b"avif" | b"avis") {
            return Some(mt(Kind::Photo, "image/avif", "avif"));
        }
        if matches!(major, b"mif1" | b"msf1") {
            if has(b"avif") {
                return Some(mt(Kind::Photo, "image/avif", "avif"));
            }
            return Some(mt(Kind::Photo, "image/heif", "heif"));
        }
        if major == b"qt  " {
            return Some(mt(Kind::Video, "video/quicktime", "mov"));
        }
        if major.starts_with(b"3g2") {
            return Some(mt(Kind::Video, "video/3gpp2", "3g2"));
        }
        if major.starts_with(b"3gp") || major.starts_with(b"3ge") || major.starts_with(b"3gs") {
            return Some(mt(Kind::Video, "video/3gpp", "3gp"));
        }
        return Some(match client_ext {
            "mov" => mt(Kind::Video, "video/quicktime", "mov"),
            "m4v" => mt(Kind::Video, "video/mp4", "m4v"),
            "3gp" => mt(Kind::Video, "video/3gpp", "3gp"),
            _ => mt(Kind::Video, "video/mp4", "mp4"),
        });
    }
    // Older QuickTime files may start directly with a top-level atom.
    if head.len() >= 8
        && matches!(&head[4..8], b"moov" | b"mdat" | b"wide" | b"free" | b"skip" | b"pnot")
        && matches!(client_ext, "mov" | "mp4" | "m4v")
    {
        return Some(mt(Kind::Video, "video/quicktime", "mov"));
    }
    None
}

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w == needle)
}

/// Whether two extensions name the same container family (no rename needed).
pub fn same_family(a: &str, b: &str) -> bool {
    const FAMILIES: &[&[&str]] = &[&["jpg", "jpeg"], &["heic", "heif"], &["mp4", "m4v"], &["3gp", "3g2"], &["mkv", "webm"]];
    a == b || FAMILIES.iter().any(|f| f.contains(&a) && f.contains(&b))
}

/// Whether the server can decode this type itself to build a thumbnail.
pub fn server_can_thumbnail(mime: &str) -> bool {
    matches!(mime, "image/jpeg" | "image/png" | "image/gif" | "image/webp")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ftyp(brand: &[u8; 4], compat: &[&[u8; 4]]) -> Vec<u8> {
        let mut v = Vec::new();
        let len = 16 + compat.len() * 4;
        v.extend_from_slice(&(len as u32).to_be_bytes());
        v.extend_from_slice(b"ftyp");
        v.extend_from_slice(brand);
        v.extend_from_slice(&[0, 0, 0, 0]);
        for c in compat {
            v.extend_from_slice(*c);
        }
        v
    }

    #[test]
    fn detects_images() {
        assert_eq!(sniff(&[0xFF, 0xD8, 0xFF, 0xE0, 0, 0], "png").unwrap().mime, "image/jpeg");
        assert_eq!(sniff(b"\x89PNG\r\n\x1a\n....", "jpg").unwrap().ext, "png");
        assert_eq!(sniff(b"RIFF\0\0\0\0WEBPVP8 ", "webp").unwrap().mime, "image/webp");
        assert_eq!(sniff(&ftyp(b"heic", &[b"mif1"]), "heic").unwrap().kind, Kind::Photo);
        assert_eq!(sniff(&ftyp(b"mif1", &[b"avif"]), "avif").unwrap().ext, "avif");
    }

    #[test]
    fn detects_videos() {
        let mov = sniff(&ftyp(b"qt  ", &[]), "mov").unwrap();
        assert_eq!((mov.kind, mov.ext), (Kind::Video, "mov"));
        let mp4 = sniff(&ftyp(b"isom", &[b"mp42"]), "mp4").unwrap();
        assert_eq!(mp4.mime, "video/mp4");
        assert_eq!(sniff(&ftyp(b"3gp4", &[]), "mp4").unwrap().ext, "3gp");
        assert_eq!(sniff(&[0x1A, 0x45, 0xDF, 0xA3, 0x9F, 0x42, 0x82, 0x84, b'w', b'e', b'b', b'm'], "x").unwrap().ext, "webm");
    }

    #[test]
    fn rejects_unknown_content() {
        assert!(sniff(b"<html><script>alert(1)</script>", "jpg").is_none());
        assert!(sniff(b"PK\x03\x04", "mp4").is_none());
        assert!(sniff(b"", "jpg").is_none());
    }
}
