use super::participant_json;
use crate::auth::{self, AnyAuth, Auth, MaybeAuth};
use crate::db::{self, Participant};
use crate::error::{ApiError, ApiResult};
use crate::state::SharedState;
use crate::storage;
use crate::util::{clean_display_name, constant_time_eq, new_id, now_ms, random_token};
use axum::extract::{ConnectInfo, Path, State};
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::net::SocketAddr;

const AVATAR_COLORS: [i64; 8] = [0xFFEDE8FF, 0xFFDDF5FF, 0xFFFFE9C8, 0xFFF1DFFF, 0xFFDDF7EA, 0xFFFFE0E3, 0xFFE3ECFF, 0xFFFFF4CC];

pub fn avatar_color(seed: &str) -> i64 {
    let h = seed.bytes().fold(0u32, |a, b| a.wrapping_mul(31).wrapping_add(b as u32));
    AVATAR_COLORS[(h as usize) % AVATAR_COLORS.len()]
}

pub async fn session_json(st: &SharedState, viewer: Option<&Participant>) -> ApiResult<Value> {
    let (s, count, host) = st
        .db
        .call(|c| {
            let s = db::get_session(c)?;
            let count = db::list_participants(c)?.iter().filter(|p| p.status == "active").count();
            Ok((s, count, db::host_participant(c)?))
        })
        .await?;
    let mut v = json!({
        "id": s.id,
        "name": s.name,
        "host_name": s.host_name,
        "host_id": host.id,
        "created_at": s.created_at,
        "ended": s.ended_at.is_some() || st.is_ended(),
        "require_approval": s.require_approval,
        "pin_length": s.pin.len(),
        "participant_count": count,
        "version": env!("CARGO_PKG_VERSION"),
        "transport": "http",
        "encrypted": false,
    });
    if let Some(p) = viewer {
        v["upload_permission"] = s.upload_permission.clone().into();
        v["download_permission"] = s.download_permission.clone().into();
        v["keep_media"] = s.keep_media.into();
        v["urls"] = json!(st.urls());
        v["join_url"] = json!(st.join_url());
        v["chunk_size"] = st.cfg.chunk_size.into();
        v["max_chunk_size"] = st.cfg.max_chunk_size.into();
        v["max_file_size"] = st.cfg.max_file_size.into();
        v["started_at"] = st.started_at.into();
        if p.is_host() {
            v["pin"] = s.pin.into();
            v["addresses"] = json!(st.addresses());
            v["port"] = st.port.into();
            v["data_dir"] = st.paths.root.display().to_string().into();
        }
    }
    Ok(v)
}

pub async fn health(State(st): State<SharedState>) -> Json<Value> {
    Json(json!({ "ok": !st.is_ended(), "session_id": st.session_id, "time": now_ms(), "version": env!("CARGO_PKG_VERSION") }))
}

pub async fn info(State(st): State<SharedState>, MaybeAuth(p): MaybeAuth) -> ApiResult<Json<Value>> {
    Ok(Json(session_json(&st, p.as_ref()).await?))
}

#[derive(Deserialize)]
pub struct JoinReq {
    pub name: String,
    pub pin: String,
    pub device_id: Option<String>,
}

pub async fn join(
    State(st): State<SharedState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(req): Json<JoinReq>,
) -> ApiResult<Response> {
    if st.is_ended() {
        return Err(ApiError::session_ended());
    }
    let ip = addr.ip();
    if let Err(wait) = st.pin_guard.check(ip) {
        return Err(ApiError::new(
            StatusCode::TOO_MANY_REQUESTS,
            "too_many_attempts",
            format!("Too many wrong PINs. Try again in {wait} s."),
        )
        .with_retry_after(wait));
    }
    let name = clean_display_name(&req.name, 40).ok_or_else(|| ApiError::bad_request("Enter a name (1–40 characters)"))?;
    let device_id = match req.device_id.as_deref().map(str::trim).filter(|d| !d.is_empty()) {
        Some(d) if d.len() <= 64 && d.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_') => Some(d.to_string()),
        Some(_) => return Err(ApiError::bad_request("Invalid device id")),
        None => None,
    };
    let session = st.db.call(|c| db::get_session(c)).await?;
    if let Some(d) = device_id.clone() {
        if st.db.call(move |c| db::is_device_blocked(c, &d)).await? {
            return Err(ApiError::forbidden("blocked", "You were blocked from this session"));
        }
    }
    let pin = req.pin.trim().replace(' ', "");
    if !constant_time_eq(pin.as_bytes(), session.pin.as_bytes()) {
        st.pin_guard.record_failure(ip);
        return Err(ApiError::new(StatusCode::UNAUTHORIZED, "invalid_pin", "Incorrect session PIN"));
    }
    st.pin_guard.record_success(ip);

    let token = random_token(32);
    let token_hash = auth::hash_token(&token);
    let now = now_ms();
    let require_approval = session.require_approval;
    let name2 = name.clone();
    // Reconnect: the same device gets its previous identity back.
    let (participant, reconnected) = st
        .db
        .call(move |c| {
            if let Some(d) = device_id.as_deref() {
                if let Some(mut existing) = db::active_participant_by_device(c, d)? {
                    db::set_participant_token(c, &existing.id, &token_hash)?;
                    let status = match existing.status.as_str() {
                        "left" if require_approval => "pending",
                        "left" => "active",
                        s => s,
                    }
                    .to_string();
                    c.execute(
                        "UPDATE participants SET name = ?1, status = ?2, last_seen = ?3 WHERE id = ?4",
                        rusqlite::params![name2, status, now, existing.id],
                    )?;
                    existing.name = name2;
                    existing.status = status;
                    existing.last_seen = now;
                    return Ok((existing, true));
                }
            }
            let id = new_id();
            let p = Participant {
                avatar_color: avatar_color(&id),
                id,
                name: name2,
                role: "participant".into(),
                status: if require_approval { "pending".into() } else { "active".into() },
                device_id,
                joined_at: now,
                last_seen: now,
            };
            db::insert_participant(c, &p, &token_hash)?;
            Ok((p, false))
        })
        .await?;

    let pj = participant_json(&participant, false, None);
    if participant.status == "pending" {
        let host_id = st.db.call(|c| db::host_participant(c)).await?.id;
        st.emit_to(&host_id, "join_request", pj.clone());
    } else {
        st.emit("participant_joined", json!({ "participant": pj, "reconnected": reconnected }));
    }
    st.log(
        if reconnected { "participant_reconnected" } else { "participant_joined" },
        Some(participant.id.clone()),
        format!("{} {}", participant.name, if reconnected { "reconnected" } else { "joined" }),
    )
    .await;

    let body = json!({
        "token": token,
        "participant": pj,
        "status": participant.status,
        "session": session_json(&st, Some(&participant)).await?,
    });
    Ok(([(header::SET_COOKIE, auth::session_cookie(&token))], Json(body)).into_response())
}

pub async fn me(State(st): State<SharedState>, AnyAuth(p): AnyAuth) -> ApiResult<Json<Value>> {
    let session = if p.status == "active" { session_json(&st, Some(&p)).await? } else { session_json(&st, None).await? };
    Ok(Json(json!({ "participant": participant_json(&p, st.is_online(&p.id), None), "session": session })))
}

pub async fn participants(State(st): State<SharedState>, a: Auth) -> ApiResult<Json<Value>> {
    let is_host = a.is_host();
    let (list, stats) = st.db.call(|c| Ok((db::list_participants(c)?, db::participant_stats(c)?))).await?;
    let stats: HashMap<_, _> = stats.into_iter().map(|s| (s.participant_id.clone(), s)).collect();
    let items: Vec<Value> = list
        .iter()
        .filter(|p| is_host || p.status == "active")
        .map(|p| participant_json(p, st.is_online(&p.id), stats.get(&p.id)))
        .collect();
    Ok(Json(json!({ "participants": items })))
}

pub async fn leave(State(st): State<SharedState>, AnyAuth(p): AnyAuth) -> ApiResult<Response> {
    if p.is_host() {
        return Err(ApiError::bad_request("The host ends the session instead of leaving"));
    }
    let id = p.id.clone();
    st.db.call(move |c| db::set_participant_status(c, &id, "left")).await?;
    st.emit("participant_left", json!({ "id": p.id, "name": p.name }));
    st.emit("participant_removed", json!({ "id": p.id, "reason": "left" }));
    st.log("participant_left", Some(p.id.clone()), format!("{} left", p.name)).await;
    Ok(([(header::SET_COOKIE, auth::clear_cookie())], Json(json!({ "ok": true }))).into_response())
}

#[derive(Deserialize, Default)]
pub struct EndReq {
    pub delete_media: Option<bool>,
}

pub async fn end(State(st): State<SharedState>, a: Auth, body: Option<Json<EndReq>>) -> ApiResult<Json<Value>> {
    a.require_host()?;
    let req = body.map(|Json(b)| b).unwrap_or_default();
    let keep = st.db.call(|c| db::get_session(c)).await?.keep_media;
    let delete_media = req.delete_media.unwrap_or(!keep);
    let summary = end_session(&st, delete_media).await?;
    Ok(Json(summary))
}

/// Ends the session: notifies clients, removes temporary upload data,
/// optionally deletes media, then stops the server.
pub async fn end_session(st: &SharedState, delete_media: bool) -> ApiResult<Value> {
    if st.ended.swap(true, std::sync::atomic::Ordering::SeqCst) {
        return Ok(json!({ "ended": true, "already": true }));
    }
    let now = now_ms();
    let uploads = st.db.call(move |c| {
        db::end_session(c, now)?;
        let ups = db::list_uploads(c, None)?;
        for u in &ups {
            db::delete_upload(c, &u.id)?;
        }
        db::log_activity(c, "session_ended", None, "Session ended", now)?;
        Ok(ups)
    })
    .await?;
    for u in &uploads {
        let _ = std::fs::remove_file(st.paths.upload_part(&u.id));
    }
    let _ = std::fs::remove_dir_all(&st.paths.tmp);
    let mut deleted = 0u64;
    if delete_media {
        deleted = st
            .db
            .call(|c| {
                let n: i64 = c.query_row("SELECT COUNT(*) FROM media", [], |r| r.get(0))?;
                c.execute("DELETE FROM media", [])?;
                Ok(n as u64)
            })
            .await?;
        let _ = std::fs::remove_dir_all(&st.paths.media);
        let _ = std::fs::remove_dir_all(&st.paths.thumbs);
    }
    st.emit("session_ended", json!({ "media_deleted": delete_media }));
    let token = st.shutdown.clone();
    tokio::spawn(async move {
        // Give WebSocket clients a moment to receive `session_ended`.
        tokio::time::sleep(std::time::Duration::from_millis(400)).await;
        token.cancel();
    });
    Ok(json!({ "ended": true, "media_deleted": delete_media, "deleted_items": deleted, "cancelled_uploads": uploads.len() }))
}

#[derive(Deserialize)]
pub struct SettingsReq {
    pub name: Option<String>,
    pub upload_permission: Option<String>,
    pub download_permission: Option<String>,
    pub require_approval: Option<bool>,
    pub keep_media: Option<bool>,
}

fn valid_permission(v: &Option<String>) -> ApiResult<()> {
    match v.as_deref() {
        None | Some("everyone") | Some("host_only") => Ok(()),
        _ => Err(ApiError::bad_request("Permission must be 'everyone' or 'host_only'")),
    }
}

pub async fn update_settings(State(st): State<SharedState>, a: Auth, Json(req): Json<SettingsReq>) -> ApiResult<Json<Value>> {
    a.require_host()?;
    valid_permission(&req.upload_permission)?;
    valid_permission(&req.download_permission)?;
    let name = match &req.name {
        Some(n) => Some(clean_display_name(n, 60).ok_or_else(|| ApiError::bad_request("Session name must be 1–60 characters"))?),
        None => None,
    };
    st.db
        .call(move |c| {
            db::update_session_settings(
                c,
                name.as_deref(),
                req.upload_permission.as_deref(),
                req.download_permission.as_deref(),
                req.require_approval,
                req.keep_media,
            )
        })
        .await?;
    let public = session_json(&st, None).await?;
    let mut full = session_json(&st, Some(&a.0)).await?;
    st.emit("session_updated", {
        let mut p = public.clone();
        p["upload_permission"] = full["upload_permission"].clone();
        p["download_permission"] = full["download_permission"].clone();
        p
    });
    full["ok"] = true.into();
    Ok(Json(full))
}

async fn set_status(st: &SharedState, id: String, status: &'static str, block: bool) -> ApiResult<Participant> {
    let ts = now_ms();
    st.db
        .call(move |c| {
            let p = db::participant_by_id(c, &id)?.ok_or_else(|| ApiError::not_found("Participant"))?;
            if p.is_host() {
                return Err(ApiError::bad_request("The host cannot be changed"));
            }
            db::set_participant_status(c, &id, status)?;
            if status != "active" {
                // Revoke credentials immediately.
                db::set_participant_token(c, &id, &auth::hash_token(&random_token(32)))?;
            }
            if block {
                if let Some(d) = &p.device_id {
                    db::block_device(c, d, &id, ts)?;
                }
            }
            Ok(Participant { status: status.to_string(), ..p })
        })
        .await
}

pub async fn approve(State(st): State<SharedState>, a: Auth, Path(id): Path<String>) -> ApiResult<Json<Value>> {
    a.require_host()?;
    let current = {
        let id = id.clone();
        st.db.call(move |c| db::participant_by_id(c, &id)).await?.ok_or_else(|| ApiError::not_found("Participant"))?
    };
    if current.status != "pending" {
        return Err(ApiError::conflict("not_pending", "This participant is not waiting for approval"));
    }
    let p = set_status(&st, id, "active", false).await?;
    let pj = participant_json(&p, st.is_online(&p.id), None);
    st.emit_to(&p.id, "join_approved", pj.clone());
    st.emit("participant_joined", json!({ "participant": pj, "reconnected": false }));
    st.log("participant_approved", Some(p.id.clone()), format!("{} was approved", p.name)).await;
    Ok(Json(json!({ "participant": pj })))
}

async fn remove_like(st: SharedState, a: Auth, id: String, status: &'static str, block: bool) -> ApiResult<Json<Value>> {
    a.require_host()?;
    let p = set_status(&st, id, status, block).await?;
    st.emit("participant_removed", json!({ "id": p.id, "name": p.name, "reason": status }));
    st.emit("participant_left", json!({ "id": p.id, "name": p.name }));
    st.log("participant_removed", Some(p.id.clone()), format!("{} was {}", p.name, status)).await;
    Ok(Json(json!({ "participant": participant_json(&p, false, None) })))
}

pub async fn reject(State(st): State<SharedState>, a: Auth, Path(id): Path<String>) -> ApiResult<Json<Value>> {
    remove_like(st, a, id, "removed", false).await
}

pub async fn remove(State(st): State<SharedState>, a: Auth, Path(id): Path<String>) -> ApiResult<Json<Value>> {
    remove_like(st, a, id, "removed", false).await
}

pub async fn block(State(st): State<SharedState>, a: Auth, Path(id): Path<String>) -> ApiResult<Json<Value>> {
    remove_like(st, a, id, "blocked", true).await
}

pub async fn storage_json(st: &SharedState) -> ApiResult<Value> {
    let totals = st.db.call(|c| db::media_totals(c)).await?;
    let tmp_bytes = storage::dir_size(&st.paths.tmp);
    let space = storage::disk_space(&st.paths.root);
    let free = space.map(|s| s.free_bytes);
    Ok(json!({
        "session_bytes": totals.bytes + tmp_bytes,
        "media_bytes": totals.bytes,
        "temp_bytes": tmp_bytes,
        "free_bytes": free,
        "total_bytes": space.map(|s| s.total_bytes),
        "min_free_bytes": st.cfg.min_free_space,
        "low_storage": free.is_some_and(|f| f < st.cfg.min_free_space.saturating_mul(2)),
        "max_file_size": st.cfg.max_file_size,
    }))
}

pub async fn storage_info(State(st): State<SharedState>, _a: Auth) -> ApiResult<Json<Value>> {
    Ok(Json(storage_json(&st).await?))
}

pub async fn stats(State(st): State<SharedState>, a: Auth) -> ApiResult<Json<Value>> {
    let viewer = a.0.clone();
    let (totals, people, pstats, uploads, activity) = st
        .db
        .call(|c| {
            Ok((
                db::media_totals(c)?,
                db::list_participants(c)?,
                db::participant_stats(c)?,
                db::list_uploads(c, None)?,
                db::recent_activity(c, 30)?,
            ))
        })
        .await?;
    let names: HashMap<_, _> = people.iter().map(|p| (p.id.clone(), p.name.clone())).collect();
    let pmap: HashMap<_, _> = pstats.iter().map(|s| (s.participant_id.clone(), s)).collect();
    let participants: Vec<Value> = people
        .iter()
        .filter(|p| viewer.is_host() || p.status == "active")
        .map(|p| participant_json(p, st.is_online(&p.id), pmap.get(&p.id).copied()))
        .collect();
    let active_uploads: Vec<Value> = uploads
        .iter()
        .map(|u| {
            json!({
                "upload_id": u.id, "participant_id": u.participant_id,
                "participant_name": names.get(&u.participant_id), "filename": u.filename,
                "kind": u.kind, "size": u.size, "received": u.received, "updated_at": u.updated_at,
            })
        })
        .collect();
    let activity: Vec<Value> = activity
        .iter()
        .map(|e| {
            let mut v = serde_json::to_value(e).unwrap_or_default();
            v["participant_name"] = json!(e.participant_id.as_ref().and_then(|id| names.get(id)));
            v
        })
        .collect();
    let in_progress: u64 = uploads.iter().map(|u| u.received).sum();
    Ok(Json(json!({
        "photos": totals.photos,
        "videos": totals.videos,
        "media_bytes": totals.bytes,
        "uploaded_bytes": totals.bytes + in_progress,
        "participants": participants,
        "online_count": people.iter().filter(|p| p.status == "active" && st.is_online(&p.id)).count(),
        "active_uploads": active_uploads,
        "recent_activity": activity,
        "started_at": st.started_at,
        "duration_ms": now_ms() - st.started_at,
        "storage": storage_json(&st).await?,
    })))
}
