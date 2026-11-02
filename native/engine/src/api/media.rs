use crate::auth::Auth;
use crate::db::{self, MediaQuery, MediaRow};
use crate::error::{ApiError, ApiResult};
use crate::state::SharedState;
use crate::thumbs;
use axum::body::Bytes;
use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

pub fn valid_id(id: &str) -> ApiResult<()> {
    if id.len() == 32 && id.bytes().all(|b| b.is_ascii_hexdigit()) {
        Ok(())
    } else {
        Err(ApiError::not_found("Media"))
    }
}

/// Adds uploader info and the viewer's favourite flag to media rows.
pub async fn media_json(st: &SharedState, rows: Vec<MediaRow>, viewer: &str) -> ApiResult<Vec<Value>> {
    let viewer = viewer.to_string();
    let ids: Vec<String> = rows.iter().map(|m| m.id.clone()).collect();
    let (people, favs) = st
        .db
        .call(move |c| Ok((db::list_participants(c)?, db::favorite_ids(c, &viewer, &ids)?)))
        .await?;
    let people: HashMap<_, _> = people.into_iter().map(|p| (p.id.clone(), p)).collect();
    let favs: HashSet<String> = favs.into_iter().collect();
    Ok(rows
        .into_iter()
        .map(|m| {
            let mut v = serde_json::to_value(&m).unwrap_or_default();
            let up = people.get(&m.participant_id);
            v["uploader"] = json!({
                "id": m.participant_id,
                "name": up.map(|p| p.name.clone()).unwrap_or_else(|| "Unknown".into()),
                "initials": up.map(|p| super::initials(&p.name)).unwrap_or_default(),
                "avatar_color": up.map(|p| p.avatar_color),
            });
            v["favorite"] = favs.contains(&m.id).into();
            v["file_url"] = format!("/api/media/{}/file", m.id).into();
            v["thumbnail_url"] = format!("/api/media/{}/thumbnail", m.id).into();
            v
        })
        .collect())
}

pub async fn media_json_one(st: &SharedState, m: &MediaRow, viewer: &str) -> ApiResult<Value> {
    Ok(media_json(st, vec![m.clone()], viewer).await?.pop().unwrap_or_default())
}

pub async fn load(st: &SharedState, id: &str) -> ApiResult<MediaRow> {
    valid_id(id)?;
    let id = id.to_string();
    st.db.call(move |c| db::get_media(c, &id)).await?.ok_or_else(|| ApiError::not_found("Media"))
}

/// Generates a server-side thumbnail in the background (bounded concurrency).
pub fn spawn_thumbnail(st: SharedState, media: MediaRow) {
    tokio::spawn(async move {
        let Ok(_permit) = st.thumb_sem.clone().acquire_owned().await else { return };
        let src = st.paths.media_file(&media.id, &media.ext);
        let dst = st.paths.thumb_file(&media.id);
        match tokio::task::spawn_blocking(move || thumbs::generate_from_file(&src, &dst)).await {
            Ok(Ok((w, h))) => {
                let id = media.id.clone();
                if st
                    .db
                    .call(move |c| {
                        db::set_media_thumbnail(c, &id)?;
                        db::set_media_dimensions(c, &id, w, h)
                    })
                    .await
                    .is_ok()
                {
                    let id = media.id.clone();
                    if let Ok(Some(m)) = st.db.call(move |c| db::get_media(c, &id)).await {
                        if let Ok(v) = media_json_one(&st, &m, "").await {
                            st.emit("media_updated", v);
                        }
                    }
                }
            }
            Ok(Err(e)) => tracing::warn!("thumbnail for {} failed: {e}", media.id),
            Err(e) => tracing::warn!("thumbnail task for {} panicked: {e}", media.id),
        }
    });
}

#[derive(Deserialize)]
pub struct ListQuery {
    pub offset: Option<u64>,
    pub limit: Option<u64>,
    pub kind: Option<String>,
    pub uploader: Option<String>,
    pub favorites: Option<bool>,
    pub order: Option<String>,
}

pub async fn list(State(st): State<SharedState>, a: Auth, Query(q): Query<ListQuery>) -> ApiResult<Json<Value>> {
    let kind = match q.kind.as_deref() {
        None | Some("") | Some("all") => None,
        Some(k @ ("photo" | "video")) => Some(k.to_string()),
        Some(_) => return Err(ApiError::bad_request("kind must be photo, video or all")),
    };
    let query = MediaQuery {
        kind,
        uploader: q.uploader.filter(|u| !u.is_empty()),
        favorites_of: q.favorites.unwrap_or(false).then(|| a.id().to_string()),
        ascending: q.order.as_deref() == Some("asc"),
        offset: q.offset.unwrap_or(0),
        limit: q.limit.unwrap_or(60).clamp(1, 200),
    };
    let (rows, total) = {
        let query = query.clone();
        st.db.call(move |c| db::list_media(c, &query)).await?
    };
    let count = rows.len() as u64;
    let items = media_json(&st, rows, a.id()).await?;
    let next = query.offset + count;
    Ok(Json(json!({ "items": items, "total": total, "offset": query.offset, "next_offset": if next < total { Some(next) } else { None } })))
}

pub async fn get(State(st): State<SharedState>, a: Auth, Path(id): Path<String>) -> ApiResult<Json<Value>> {
    let m = load(&st, &id).await?;
    Ok(Json(media_json_one(&st, &m, a.id()).await?))
}

pub async fn delete(State(st): State<SharedState>, a: Auth, Path(id): Path<String>) -> ApiResult<Json<Value>> {
    let m = load(&st, &id).await?;
    if m.participant_id != a.id() && !a.is_host() {
        return Err(ApiError::forbidden("not_owner", "Only the uploader or the host can delete this"));
    }
    let mid = m.id.clone();
    st.db.call(move |c| db::delete_media(c, &mid)).await?;
    let _ = tokio::fs::remove_file(st.paths.media_file(&m.id, &m.ext)).await;
    let _ = tokio::fs::remove_file(st.paths.thumb_file(&m.id)).await;
    st.emit("media_deleted", json!({ "id": m.id, "deleted_by": a.id() }));
    st.log("media_deleted", Some(a.id().to_string()), format!("{} deleted {}", a.0.name, m.filename)).await;
    Ok(Json(json!({ "deleted": true })))
}

pub async fn thumbnail(State(st): State<SharedState>, _a: Auth, Path(id): Path<String>, headers: HeaderMap) -> ApiResult<Response> {
    let m = load(&st, &id).await?;
    if !m.has_thumbnail {
        return Err(ApiError::new(StatusCode::NOT_FOUND, "no_thumbnail", "Thumbnail not available"));
    }
    let etag = format!("\"t-{}\"", &m.sha256[..16]);
    if headers.get(header::IF_NONE_MATCH).and_then(|v| v.to_str().ok()) == Some(etag.as_str()) {
        return Ok(StatusCode::NOT_MODIFIED.into_response());
    }
    let bytes = tokio::fs::read(st.paths.thumb_file(&m.id)).await.map_err(|_| ApiError::not_found("Thumbnail"))?;
    let mut resp = bytes.into_response();
    let h = resp.headers_mut();
    h.insert(header::CONTENT_TYPE, HeaderValue::from_static("image/jpeg"));
    h.insert(header::CACHE_CONTROL, HeaderValue::from_static("private, max-age=86400"));
    if let Ok(v) = HeaderValue::from_str(&etag) {
        h.insert(header::ETAG, v);
    }
    Ok(resp)
}

pub async fn put_thumbnail(State(st): State<SharedState>, a: Auth, Path(id): Path<String>, body: Bytes) -> ApiResult<Json<Value>> {
    let m = load(&st, &id).await?;
    if m.participant_id != a.id() && !a.is_host() {
        return Err(ApiError::forbidden("not_owner", "Only the uploader can set the thumbnail"));
    }
    if body.is_empty() {
        return Err(ApiError::bad_request("Empty thumbnail"));
    }
    let _permit = st.thumb_sem.clone().acquire_owned().await.map_err(|_| ApiError::session_ended())?;
    let dst = st.paths.thumb_file(&m.id);
    tokio::task::spawn_blocking(move || thumbs::store_client_thumbnail(&body, &dst))
        .await
        .map_err(|e| ApiError::internal(e.to_string()))?
        .map_err(|e| ApiError::new(StatusCode::UNPROCESSABLE_ENTITY, "invalid_thumbnail", e))?;
    let mid = m.id.clone();
    st.db.call(move |c| db::set_media_thumbnail(c, &mid)).await?;
    let updated = load(&st, &m.id).await?;
    let v = media_json_one(&st, &updated, a.id()).await?;
    st.emit("media_updated", v.clone());
    Ok(Json(v))
}

async fn set_fav(st: SharedState, a: Auth, id: String, fav: bool) -> ApiResult<Json<Value>> {
    let m = load(&st, &id).await?;
    let pid = a.id().to_string();
    st.db.call(move |c| db::set_favorite(c, &pid, &m.id, fav, crate::util::now_ms())).await?;
    Ok(Json(json!({ "id": id, "favorite": fav })))
}

pub async fn favorite(State(st): State<SharedState>, a: Auth, Path(id): Path<String>) -> ApiResult<Json<Value>> {
    set_fav(st, a, id, true).await
}

pub async fn unfavorite(State(st): State<SharedState>, a: Auth, Path(id): Path<String>) -> ApiResult<Json<Value>> {
    set_fav(st, a, id, false).await
}
