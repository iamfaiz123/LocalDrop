//! Original-quality downloads (with HTTP Range for resume + video seeking)
//! and ZIP exports of multiple items.

use super::media::load;
use crate::auth::Auth;
use crate::db;
use crate::error::{ApiError, ApiResult};
use crate::state::{Export, ExportEntry, SharedState};
use crate::util::{new_id, sanitize_filename};
use crate::zip::{self, ZipInput};
use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::Response;
use axum::Json;
use percent_encoding::{utf8_percent_encode, NON_ALPHANUMERIC};
use serde::Deserialize;
use serde_json::{json, Value};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncSeekExt};
use tokio_util::io::ReaderStream;

#[derive(Debug, PartialEq, Eq)]
pub enum ByteRange {
    Full,
    Partial(u64, u64),
    Unsatisfiable,
}

/// Parses a single `Range: bytes=…` header. Multi-range requests are served in full.
pub fn parse_range(h: Option<&str>, len: u64) -> ByteRange {
    let Some(spec) = h.and_then(|v| v.trim().strip_prefix("bytes=")) else { return ByteRange::Full };
    if spec.contains(',') {
        return ByteRange::Full;
    }
    let Some((a, b)) = spec.split_once('-') else { return ByteRange::Full };
    let (a, b) = (a.trim(), b.trim());
    if len == 0 {
        return ByteRange::Unsatisfiable;
    }
    if a.is_empty() {
        let Ok(n) = b.parse::<u64>() else { return ByteRange::Full };
        if n == 0 {
            return ByteRange::Unsatisfiable;
        }
        return ByteRange::Partial(len.saturating_sub(n), len - 1);
    }
    let Ok(start) = a.parse::<u64>() else { return ByteRange::Full };
    if start >= len {
        return ByteRange::Unsatisfiable;
    }
    let end = if b.is_empty() { len - 1 } else { b.parse::<u64>().map(|e| e.min(len - 1)).unwrap_or(len - 1) };
    if end < start {
        return ByteRange::Unsatisfiable;
    }
    ByteRange::Partial(start, end)
}

pub fn content_disposition(kind: &str, filename: &str) -> HeaderValue {
    let ascii: String = filename.chars().map(|c| if c.is_ascii_graphic() && c != '"' && c != '\\' || c == ' ' { c } else { '_' }).collect();
    let encoded = utf8_percent_encode(filename, NON_ALPHANUMERIC).to_string();
    HeaderValue::from_str(&format!("{kind}; filename=\"{ascii}\"; filename*=UTF-8''{encoded}"))
        .unwrap_or_else(|_| HeaderValue::from_static("attachment"))
}

async fn ensure_can_download(st: &SharedState, a: &Auth) -> ApiResult<()> {
    if a.is_host() {
        return Ok(());
    }
    let perm = st.db.call(|c| Ok(db::get_session(c)?.download_permission)).await?;
    if perm == "host_only" {
        return Err(ApiError::forbidden("downloads_disabled", "The host has disabled downloads for participants"));
    }
    Ok(())
}

fn range_headers(resp: &mut Response, range: &ByteRange, total: u64, start: u64, end: u64) {
    let h = resp.headers_mut();
    h.insert(header::ACCEPT_RANGES, HeaderValue::from_static("bytes"));
    let len = if total == 0 { 0 } else { end - start + 1 };
    h.insert(header::CONTENT_LENGTH, HeaderValue::from(len));
    if let ByteRange::Partial(..) = range {
        if let Ok(v) = HeaderValue::from_str(&format!("bytes {start}-{end}/{total}")) {
            h.insert(header::CONTENT_RANGE, v);
        }
        *resp.status_mut() = StatusCode::PARTIAL_CONTENT;
    }
}

fn unsatisfiable(total: u64) -> Response {
    let mut r = Response::new(Body::empty());
    *r.status_mut() = StatusCode::RANGE_NOT_SATISFIABLE;
    if let Ok(v) = HeaderValue::from_str(&format!("bytes */{total}")) {
        r.headers_mut().insert(header::CONTENT_RANGE, v);
    }
    r
}

#[derive(Deserialize)]
pub struct FileQuery {
    pub download: Option<u8>,
}

pub async fn file(
    State(st): State<SharedState>,
    a: Auth,
    Path(id): Path<String>,
    Query(q): Query<FileQuery>,
    headers: HeaderMap,
) -> ApiResult<Response> {
    let attachment = q.download.unwrap_or(0) == 1;
    if attachment {
        ensure_can_download(&st, &a).await?;
    }
    let m = load(&st, &id).await?;
    let path = st.paths.media_file(&m.id, &m.ext);
    let mut f = tokio::fs::File::open(&path).await.map_err(|_| ApiError::not_found("Media file"))?;
    let total = f.metadata().await?.len();
    let etag = format!("\"{}\"", m.sha256);
    let range = match headers.get(header::IF_RANGE).and_then(|v| v.to_str().ok()) {
        Some(ir) if ir != etag => ByteRange::Full,
        _ => parse_range(headers.get(header::RANGE).and_then(|v| v.to_str().ok()), total),
    };
    let (start, end) = match range {
        ByteRange::Unsatisfiable => return Ok(unsatisfiable(total)),
        ByteRange::Partial(s, e) => (s, e),
        ByteRange::Full => (0, total.saturating_sub(1)),
    };
    if start > 0 {
        f.seek(std::io::SeekFrom::Start(start)).await?;
    }
    let len = if total == 0 { 0 } else { end - start + 1 };
    let stream = ReaderStream::with_capacity(f.take(len), 256 * 1024);
    let mut resp = Response::new(Body::from_stream(stream));
    range_headers(&mut resp, &range, total, start, end);
    let h = resp.headers_mut();
    if let Ok(v) = HeaderValue::from_str(&m.mime) {
        h.insert(header::CONTENT_TYPE, v);
    }
    h.insert(header::CONTENT_DISPOSITION, content_disposition(if attachment { "attachment" } else { "inline" }, &m.filename));
    if let Ok(v) = HeaderValue::from_str(&etag) {
        h.insert(header::ETAG, v);
    }
    h.insert(header::CACHE_CONTROL, HeaderValue::from_static("private, max-age=3600"));
    Ok(resp)
}

#[derive(Deserialize)]
pub struct ExportReq {
    pub ids: Vec<String>,
}

pub async fn create_export(State(st): State<SharedState>, a: Auth, Json(req): Json<ExportReq>) -> ApiResult<Json<Value>> {
    ensure_can_download(&st, &a).await?;
    if req.ids.is_empty() {
        return Err(ApiError::bad_request("Select at least one item"));
    }
    if req.ids.len() > 10_000 {
        return Err(ApiError::bad_request("Too many items in one export"));
    }
    for id in &req.ids {
        super::media::valid_id(id)?;
    }
    let ids = req.ids.clone();
    let rows = st.db.call(move |c| db::media_by_ids(c, &ids)).await?;
    if rows.is_empty() {
        return Err(ApiError::not_found("Media"));
    }
    let missing: Vec<&String> = req.ids.iter().filter(|id| !rows.iter().any(|m| &m.id == *id)).collect();
    let names = zip::unique_names(&rows.iter().map(|m| m.filename.clone()).collect::<Vec<_>>());
    let entries: Vec<ExportEntry> = rows
        .iter()
        .zip(names)
        .map(|(m, name)| ExportEntry {
            name,
            path: st.paths.media_file(&m.id, &m.ext),
            size: m.size,
            crc32: m.crc32,
            mtime_ms: m.created_at,
        })
        .collect();
    let size = zip::total_len(&zip::build(&to_inputs(&entries)));
    let session_name = st.db.call(|c| Ok(db::get_session(c)?.name)).await?;
    let filename = sanitize_filename(&format!("{session_name} ({} items).zip", entries.len()));
    let export_id = new_id();
    let count = entries.len();
    st.exports.lock().unwrap_or_else(|e| e.into_inner()).insert(
        export_id.clone(),
        Export { participant_id: a.id().to_string(), entries: Arc::new(entries), created: std::time::Instant::now(), filename: filename.clone() },
    );
    Ok(Json(json!({
        "export_id": export_id,
        "url": format!("/api/exports/{export_id}"),
        "size": size,
        "count": count,
        "filename": filename,
        "missing": missing,
    })))
}

fn to_inputs(entries: &[ExportEntry]) -> Vec<ZipInput> {
    entries
        .iter()
        .map(|e| ZipInput { name: e.name.clone(), path: e.path.clone(), size: e.size, crc32: e.crc32, mtime_ms: e.mtime_ms })
        .collect()
}

pub const EXPORT_TTL: std::time::Duration = std::time::Duration::from_secs(6 * 3600);

pub async fn export(State(st): State<SharedState>, a: Auth, Path(id): Path<String>, headers: HeaderMap) -> ApiResult<Response> {
    let (entries, filename) = {
        let map = st.exports.lock().unwrap_or_else(|e| e.into_inner());
        let e = map.get(&id).filter(|e| e.participant_id == a.id() && e.created.elapsed() < EXPORT_TTL);
        let e = e.ok_or_else(|| ApiError::not_found("Export"))?;
        (e.entries.clone(), e.filename.clone())
    };
    // Verify sources still exist with the expected size before streaming.
    for e in entries.iter() {
        let ok = tokio::fs::metadata(&e.path).await.map(|m| m.len() == e.size).unwrap_or(false);
        if !ok {
            return Err(ApiError::conflict("media_changed", format!("{} is no longer available; create a new export", e.name)));
        }
    }
    let segs = zip::build(&to_inputs(&entries));
    let total = zip::total_len(&segs);
    let range = parse_range(headers.get(header::RANGE).and_then(|v| v.to_str().ok()), total);
    let (start, end) = match range {
        ByteRange::Unsatisfiable => return Ok(unsatisfiable(total)),
        ByteRange::Partial(s, e) => (s, e),
        ByteRange::Full => (0, total - 1),
    };
    let (mut w, r) = tokio::io::duplex(256 * 1024);
    let shutdown = st.shutdown.clone();
    tokio::spawn(async move {
        tokio::select! {
            res = zip::write_range(&segs, start, end, &mut w) => {
                if let Err(e) = res {
                    tracing::debug!("zip export stream ended early: {e}");
                }
            }
            _ = shutdown.cancelled() => {}
        }
    });
    let mut resp = Response::new(Body::from_stream(ReaderStream::with_capacity(r, 256 * 1024)));
    range_headers(&mut resp, &range, total, start, end);
    let h = resp.headers_mut();
    h.insert(header::CONTENT_TYPE, HeaderValue::from_static("application/zip"));
    h.insert(header::CONTENT_DISPOSITION, content_disposition("attachment", &filename));
    Ok(resp)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ranges() {
        assert_eq!(parse_range(None, 100), ByteRange::Full);
        assert_eq!(parse_range(Some("bytes=0-9"), 100), ByteRange::Partial(0, 9));
        assert_eq!(parse_range(Some("bytes=90-"), 100), ByteRange::Partial(90, 99));
        assert_eq!(parse_range(Some("bytes=-10"), 100), ByteRange::Partial(90, 99));
        assert_eq!(parse_range(Some("bytes=50-1000"), 100), ByteRange::Partial(50, 99));
        assert_eq!(parse_range(Some("bytes=100-"), 100), ByteRange::Unsatisfiable);
        assert_eq!(parse_range(Some("bytes=0-1,5-6"), 100), ByteRange::Full);
        assert_eq!(parse_range(Some("items=0-1"), 100), ByteRange::Full);
    }

    #[test]
    fn disposition_is_safe() {
        let v = content_disposition("attachment", "naïve \"x\".jpg");
        let s = v.to_str().unwrap();
        assert!(s.starts_with("attachment; filename=\"na_ve _x_.jpg\""));
        assert!(s.contains("filename*=UTF-8''na%C3%AFve%20%22x%22%2Ejpg"));
    }
}
