//! Resumable chunked uploads.
//!
//! 1. `POST /api/media/upload` – declare file (name, size, optional SHA-256).
//!    Returns an upload id, the server's recommended chunk size and the
//!    number of bytes already received (non-zero when resuming).
//! 2. `PUT /api/uploads/{id}?offset=N` – raw chunk bytes, streamed straight
//!    to a temp file. Optional `X-Chunk-SHA256` header is verified.
//! 3. `POST /api/uploads/{id}/complete` – the server hashes the whole file,
//!    verifies SHA-256, sniffs the real type, deduplicates, and only then
//!    moves the file into the gallery.
//!
//! Partially uploaded files never appear in the gallery.

use super::media::{media_json_one, spawn_thumbnail};
use crate::auth::Auth;
use crate::db::{self, MediaRow, UploadRow};
use crate::error::{ApiError, ApiResult};
use crate::sniff;
use crate::state::{AppState, SharedState};
use crate::storage;
use crate::util::{extension_of, is_sha256_hex, new_id, now_ms, sanitize_filename};
use axum::body::Body;
use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::Json;
use futures_util::StreamExt;
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::io::Read;
use tokio::io::{AsyncSeekExt, AsyncWriteExt};

#[derive(Deserialize)]
pub struct CreateReq {
    pub filename: String,
    pub size: u64,
    pub sha256: Option<String>,
}

async fn ensure_can_upload(st: &AppState, a: &Auth) -> ApiResult<()> {
    if a.is_host() {
        return Ok(());
    }
    let perm = st.db.call(|c| Ok(db::get_session(c)?.upload_permission)).await?;
    if perm == "host_only" {
        return Err(ApiError::forbidden("uploads_disabled", "The host has disabled uploads for participants"));
    }
    Ok(())
}

fn upload_json(st: &AppState, u: &UploadRow) -> Value {
    json!({
        "upload_id": u.id,
        "filename": u.filename,
        "size": u.size,
        "received": u.received,
        "kind": u.kind,
        "chunk_size": st.cfg.chunk_size,
        "max_chunk_size": st.cfg.max_chunk_size,
        "complete": u.received == u.size,
    })
}

/// Brings the DB offset and the temp file back in sync (after a crash or an
/// interrupted chunk). The file is the source of truth only up to the
/// recorded offset: bytes past it were never acknowledged.
fn reconcile(st: &AppState, c: &rusqlite::Connection, mut u: UploadRow) -> ApiResult<UploadRow> {
    let path = st.paths.upload_part(&u.id);
    let len = match std::fs::metadata(&path) {
        Ok(m) => m.len(),
        Err(_) => {
            std::fs::File::create(&path)?;
            0
        }
    };
    if len != u.received {
        let good = len.min(u.received);
        let f = std::fs::OpenOptions::new().write(true).open(&path)?;
        f.set_len(good)?;
        f.sync_all()?;
        u.received = good;
        db::set_upload_received(c, &u.id, good, now_ms())?;
    }
    Ok(u)
}

pub async fn create(State(st): State<SharedState>, a: Auth, Json(req): Json<CreateReq>) -> ApiResult<(StatusCode, Json<Value>)> {
    ensure_can_upload(&st, &a).await?;
    let filename = sanitize_filename(&req.filename);
    let ext = extension_of(&filename)
        .filter(|e| sniff::is_allowed_extension(e))
        .ok_or_else(|| ApiError::new(StatusCode::UNSUPPORTED_MEDIA_TYPE, "unsupported_type", "Only photos and videos can be shared"))?;
    if req.size == 0 {
        return Err(ApiError::bad_request("The file is empty"));
    }
    if req.size > st.cfg.max_file_size {
        return Err(ApiError::new(StatusCode::PAYLOAD_TOO_LARGE, "file_too_large", "This file is larger than the session allows")
            .with_extra(json!({ "max_file_size": st.cfg.max_file_size })));
    }
    let sha = match req.sha256.map(|s| s.to_ascii_lowercase()) {
        Some(s) if is_sha256_hex(&s) => Some(s),
        Some(_) => return Err(ApiError::bad_request("sha256 must be 64 hex characters")),
        None => None,
    };
    if let Some(sha) = sha.clone() {
        if let Some(existing) = st.db.call(move |c| db::media_by_sha(c, &sha)).await? {
            let media = media_json_one(&st, &existing, a.id()).await?;
            return Ok((StatusCode::OK, Json(json!({ "duplicate": true, "media": media }))));
        }
    }

    // Resume an interrupted upload of the same file by the same participant.
    let pid = a.id().to_string();
    let st2 = st.clone();
    let (f2, s2) = (filename.clone(), sha.clone());
    let resumed = st
        .db
        .call(move |c| match db::find_resumable_upload(c, &pid, &f2, req.size, s2.as_deref())? {
            Some(u) => Ok(Some(reconcile(&st2, c, u)?)),
            None => Ok(None),
        })
        .await?;
    if let Some(u) = resumed {
        let mut v = upload_json(&st, &u);
        v["resumed"] = true.into();
        return Ok((StatusCode::OK, Json(v)));
    }

    // Storage capacity check: this file + all other unfinished uploads + reserve.
    if let Some(space) = storage::disk_space(&st.paths.root) {
        let pending = st.db.call(|c| db::pending_upload_bytes(c)).await?;
        let needed = req.size.saturating_add(pending).saturating_add(st.cfg.min_free_space);
        if space.free_bytes < needed {
            return Err(ApiError::insufficient_storage("Not enough free space on the host device for this file")
                .with_extra(json!({ "free_bytes": space.free_bytes, "needed_bytes": needed })));
        }
    }

    let now = now_ms();
    let u = UploadRow {
        id: new_id(),
        participant_id: a.id().to_string(),
        kind: sniff::kind_for_extension(&ext).as_str().to_string(),
        filename,
        ext,
        size: req.size,
        received: 0,
        expected_sha256: sha,
        created_at: now,
        updated_at: now,
    };
    tokio::fs::File::create(st.paths.upload_part(&u.id)).await?;
    let row = u.clone();
    st.db.call(move |c| db::insert_upload(c, &row)).await?;
    st.emit(
        "upload_started",
        json!({ "upload_id": u.id, "participant_id": u.participant_id, "participant_name": a.0.name,
                "filename": u.filename, "size": u.size, "kind": u.kind }),
    );
    Ok((StatusCode::CREATED, Json(upload_json(&st, &u))))
}

async fn load_owned(st: &SharedState, a: &Auth, id: &str, allow_host: bool) -> ApiResult<UploadRow> {
    if id.len() != 32 || !id.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(ApiError::not_found("Upload"));
    }
    let id = id.to_string();
    let u = st.db.call(move |c| db::get_upload(c, &id)).await?.ok_or_else(|| ApiError::not_found("Upload"))?;
    if u.participant_id != a.id() && !(allow_host && a.is_host()) {
        return Err(ApiError::not_found("Upload"));
    }
    Ok(u)
}

pub async fn status(State(st): State<SharedState>, a: Auth, Path(id): Path<String>) -> ApiResult<Json<Value>> {
    let u = load_owned(&st, &a, &id, true).await?;
    let lock = st.upload_lock(&u.id);
    let _g = lock.try_lock_owned().map_err(|_| ApiError::conflict("upload_busy", "A chunk is being written"))?;
    let st2 = st.clone();
    let u = st.db.call(move |c| reconcile(&st2, c, u)).await?;
    Ok(Json(upload_json(&st, &u)))
}

pub async fn list(State(st): State<SharedState>, a: Auth) -> ApiResult<Json<Value>> {
    let who = if a.is_host() { None } else { Some(a.id().to_string()) };
    let ups = st.db.call(move |c| db::list_uploads(c, who.as_deref())).await?;
    Ok(Json(json!({ "uploads": ups.iter().map(|u| upload_json(&st, u)).collect::<Vec<_>>() })))
}

#[derive(Deserialize)]
pub struct ChunkQuery {
    pub offset: u64,
}

pub async fn put_chunk(
    State(st): State<SharedState>,
    a: Auth,
    Path(id): Path<String>,
    Query(q): Query<ChunkQuery>,
    headers: HeaderMap,
    body: Body,
) -> ApiResult<Json<Value>> {
    ensure_can_upload(&st, &a).await?;
    let u = load_owned(&st, &a, &id, false).await?;
    let lock = st.upload_lock(&u.id);
    let _guard = lock.try_lock_owned().map_err(|_| ApiError::conflict("upload_busy", "Another chunk for this upload is in progress"))?;
    // Re-read under the lock.
    let u = load_owned(&st, &a, &id, false).await?;

    let len: u64 = headers
        .get(header::CONTENT_LENGTH)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.parse().ok())
        .ok_or_else(|| ApiError::new(StatusCode::LENGTH_REQUIRED, "length_required", "Content-Length is required"))?;
    if len == 0 {
        return Err(ApiError::bad_request("Empty chunk"));
    }
    if len > st.cfg.max_chunk_size {
        return Err(ApiError::new(StatusCode::PAYLOAD_TOO_LARGE, "chunk_too_large", "Chunk exceeds the maximum chunk size")
            .with_extra(json!({ "max_chunk_size": st.cfg.max_chunk_size })));
    }
    if q.offset != u.received {
        return Err(ApiError::conflict("offset_mismatch", "Upload offset does not match the server")
            .with_extra(json!({ "received": u.received })));
    }
    if q.offset + len > u.size {
        return Err(ApiError::bad_request("Chunk extends past the declared file size"));
    }
    let expected_chunk_sha = match headers.get("x-chunk-sha256").and_then(|v| v.to_str().ok()) {
        Some(s) if is_sha256_hex(s) => Some(s.to_ascii_lowercase()),
        Some(_) => return Err(ApiError::bad_request("Invalid X-Chunk-SHA256 header")),
        None => None,
    };

    let _permit = st.upload_sem.clone().acquire_owned().await.map_err(|_| ApiError::session_ended())?;
    let path = st.paths.upload_part(&u.id);
    let file = tokio::fs::OpenOptions::new().write(true).create(true).truncate(false).open(&path).await?;
    file.set_len(q.offset).await?;
    let mut file = file;
    file.seek(std::io::SeekFrom::Start(q.offset)).await?;
    let mut writer = tokio::io::BufWriter::with_capacity(512 * 1024, file);
    let mut hasher = expected_chunk_sha.as_ref().map(|_| Sha256::new());
    let mut stream = body.into_data_stream();
    let mut written = 0u64;

    let result: ApiResult<()> = async {
        while let Some(frame) = stream.next().await {
            if st.shutdown.is_cancelled() || st.is_ended() {
                return Err(ApiError::session_ended());
            }
            let bytes = frame.map_err(|e| ApiError::bad_request(format!("Upload interrupted: {e}")))?;
            written += bytes.len() as u64;
            if written > len {
                return Err(ApiError::bad_request("Body is longer than Content-Length"));
            }
            if let Some(h) = hasher.as_mut() {
                h.update(&bytes);
            }
            writer.write_all(&bytes).await?;
        }
        if written != len {
            return Err(ApiError::bad_request("Upload interrupted before the chunk was complete"));
        }
        if let (Some(h), Some(expected)) = (hasher.take(), expected_chunk_sha.as_ref()) {
            if hex::encode(h.finalize()) != *expected {
                return Err(ApiError::new(StatusCode::UNPROCESSABLE_ENTITY, "chunk_integrity_failed", "Chunk checksum mismatch, resend it"));
            }
        }
        writer.flush().await?;
        writer.get_ref().sync_data().await?;
        Ok(())
    }
    .await;

    if let Err(e) = result {
        drop(writer);
        // Roll back to the last acknowledged offset.
        if let Ok(f) = tokio::fs::OpenOptions::new().write(true).open(&path).await {
            let _ = f.set_len(q.offset).await;
        }
        return Err(e);
    }
    drop(writer);

    let received = q.offset + len;
    let uid = u.id.clone();
    st.db.call(move |c| db::set_upload_received(c, &uid, received, now_ms())).await?;
    st.emit(
        "upload_progress",
        json!({ "upload_id": u.id, "participant_id": u.participant_id, "filename": u.filename, "received": received, "size": u.size }),
    );
    Ok(Json(json!({ "upload_id": u.id, "received": received, "size": u.size, "complete": received == u.size })))
}

#[derive(Deserialize, Default)]
pub struct CompleteReq {
    pub sha256: Option<String>,
}

struct Hashed {
    sha256: String,
    crc32: u32,
    head: Vec<u8>,
    len: u64,
}

fn hash_file(path: &std::path::Path) -> std::io::Result<Hashed> {
    let mut f = std::fs::File::open(path)?;
    let mut sha = Sha256::new();
    let mut crc = crc32fast::Hasher::new();
    let mut buf = vec![0u8; 1024 * 1024];
    let mut head = Vec::with_capacity(64);
    let mut len = 0u64;
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        if head.len() < 64 {
            let take = (64 - head.len()).min(n);
            head.extend_from_slice(&buf[..take]);
        }
        sha.update(&buf[..n]);
        crc.update(&buf[..n]);
        len += n as u64;
    }
    Ok(Hashed { sha256: hex::encode(sha.finalize()), crc32: crc.finalize(), head, len })
}

async fn fail_upload(st: &SharedState, u: &UploadRow, err: ApiError) -> ApiError {
    let id = u.id.clone();
    let _ = st.db.call(move |c| db::delete_upload(c, &id)).await;
    let _ = tokio::fs::remove_file(st.paths.upload_part(&u.id)).await;
    st.drop_upload_lock(&u.id);
    st.emit(
        "upload_failed",
        json!({ "upload_id": u.id, "participant_id": u.participant_id, "filename": u.filename, "reason": err.code, "message": err.message }),
    );
    st.log("upload_failed", Some(u.participant_id.clone()), format!("{} failed: {}", u.filename, err.message)).await;
    err
}

pub async fn complete(
    State(st): State<SharedState>,
    a: Auth,
    Path(id): Path<String>,
    body: Option<Json<CompleteReq>>,
) -> ApiResult<(StatusCode, Json<Value>)> {
    let req = body.map(|Json(b)| b).unwrap_or_default();
    let u = load_owned(&st, &a, &id, false).await?;
    let lock = st.upload_lock(&u.id);
    let _guard = lock.try_lock_owned().map_err(|_| ApiError::conflict("upload_busy", "A chunk is still being written"))?;
    let u = load_owned(&st, &a, &id, false).await?;
    if u.received != u.size {
        return Err(ApiError::conflict("upload_incomplete", "Not all bytes have been received")
            .with_extra(json!({ "received": u.received, "size": u.size })));
    }
    let client_sha = match req.sha256.map(|s| s.to_ascii_lowercase()) {
        Some(s) if is_sha256_hex(&s) => Some(s),
        Some(_) => return Err(ApiError::bad_request("sha256 must be 64 hex characters")),
        None => None,
    };
    if let (Some(a1), Some(b1)) = (&client_sha, &u.expected_sha256) {
        if a1 != b1 {
            return Err(fail_upload(&st, &u, ApiError::bad_request("Checksum differs from the one declared at start")).await);
        }
    }
    let expected = client_sha.or(u.expected_sha256.clone());

    let part = st.paths.upload_part(&u.id);
    let hashed = tokio::task::spawn_blocking(move || hash_file(&part))
        .await
        .map_err(|e| ApiError::internal(e.to_string()))??;
    if hashed.len != u.size {
        return Err(fail_upload(&st, &u, ApiError::internal("Stored file size does not match")).await);
    }
    if let Some(exp) = &expected {
        if *exp != hashed.sha256 {
            return Err(fail_upload(
                &st,
                &u,
                ApiError::new(StatusCode::UNPROCESSABLE_ENTITY, "integrity_failed", "File checksum mismatch — the file was corrupted in transit"),
            )
            .await);
        }
    }
    let Some(mt) = sniff::sniff(&hashed.head, &u.ext) else {
        return Err(fail_upload(
            &st,
            &u,
            ApiError::new(StatusCode::UNSUPPORTED_MEDIA_TYPE, "unsupported_content", "The file content is not a supported photo or video"),
        )
        .await);
    };

    let media = MediaRow {
        id: new_id(),
        participant_id: u.participant_id.clone(),
        // Keep the user's name but make the extension match the real content.
        filename: if sniff::same_family(&u.ext, mt.ext) {
            u.filename.clone()
        } else {
            let stem = u.filename.rsplit_once('.').map(|(s, _)| s).unwrap_or(&u.filename);
            format!("{stem}.{}", mt.ext)
        },
        mime: mt.mime.to_string(),
        kind: mt.kind.as_str().to_string(),
        ext: mt.ext.to_string(),
        size: hashed.len,
        sha256: hashed.sha256.clone(),
        crc32: hashed.crc32,
        created_at: now_ms(),
        has_thumbnail: false,
        width: None,
        height: None,
    };
    let part = st.paths.upload_part(&u.id);
    let dest = st.paths.media_file(&media.id, &media.ext);
    let (m2, uid) = (media.clone(), u.id.clone());
    // Dedup + move + insert happen atomically under the DB lock.
    let outcome = st
        .db
        .call(move |c| {
            if let Some(existing) = db::media_by_sha(c, &m2.sha256)? {
                db::delete_upload(c, &uid)?;
                let _ = std::fs::remove_file(&part);
                return Ok(Err(existing));
            }
            std::fs::rename(&part, &dest)?;
            let tx = c.transaction()?;
            if let Err(e) = db::insert_media(&tx, &m2) {
                let _ = std::fs::rename(&dest, &part);
                return Err(e.into());
            }
            db::delete_upload(&tx, &uid)?;
            tx.commit()?;
            Ok(Ok(()))
        })
        .await?;
    st.drop_upload_lock(&u.id);

    match outcome {
        Err(existing) => {
            let mj = media_json_one(&st, &existing, a.id()).await?;
            st.emit(
                "upload_completed",
                json!({ "upload_id": u.id, "participant_id": u.participant_id, "media_id": existing.id, "duplicate": true }),
            );
            Ok((StatusCode::OK, Json(json!({ "duplicate": true, "media": mj }))))
        }
        Ok(()) => {
            let mj = media_json_one(&st, &media, a.id()).await?;
            st.emit(
                "upload_completed",
                json!({ "upload_id": u.id, "participant_id": u.participant_id, "media_id": media.id, "duplicate": false }),
            );
            st.emit("media_uploaded", mj.clone());
            st.log("media_uploaded", Some(u.participant_id.clone()), format!("{} shared {}", a.0.name, media.filename)).await;
            let server_thumb = sniff::server_can_thumbnail(&media.mime);
            if server_thumb {
                spawn_thumbnail(st.clone(), media.clone());
            }
            Ok((StatusCode::CREATED, Json(json!({ "duplicate": false, "media": mj, "needs_client_thumbnail": !server_thumb }))))
        }
    }
}

pub async fn cancel(State(st): State<SharedState>, a: Auth, Path(id): Path<String>) -> ApiResult<Json<Value>> {
    let u = load_owned(&st, &a, &id, true).await?;
    let lock = st.upload_lock(&u.id);
    let _guard = lock.try_lock_owned().map_err(|_| ApiError::conflict("upload_busy", "Stop sending data before cancelling"))?;
    let uid = u.id.clone();
    st.db.call(move |c| db::delete_upload(c, &uid)).await?;
    let _ = tokio::fs::remove_file(st.paths.upload_part(&u.id)).await;
    st.drop_upload_lock(&u.id);
    st.emit(
        "upload_failed",
        json!({ "upload_id": u.id, "participant_id": u.participant_id, "filename": u.filename, "reason": "cancelled" }),
    );
    Ok(Json(json!({ "cancelled": true })))
}

/// Removes uploads that have been idle for too long (janitor task).
pub async fn expire_stale(st: &SharedState) {
    let cutoff = now_ms() - (st.cfg.stale_upload_hours as i64) * 3_600_000;
    let stale = match st.db.call(move |c| db::stale_uploads(c, cutoff)).await {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!("stale upload scan failed: {e}");
            return;
        }
    };
    for u in stale {
        let lock = st.upload_lock(&u.id);
        let Ok(_g) = lock.try_lock_owned() else { continue };
        let id = u.id.clone();
        if st.db.call(move |c| db::delete_upload(c, &id)).await.is_ok() {
            let _ = tokio::fs::remove_file(st.paths.upload_part(&u.id)).await;
            st.emit("upload_failed", json!({ "upload_id": u.id, "participant_id": u.participant_id, "reason": "expired" }));
        }
        st.drop_upload_lock(&u.id);
    }
}
