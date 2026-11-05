//! HTTP + WebSocket API (Axum). See `docs/API.md` for the full reference.

pub mod download;
pub mod media;
pub mod session;
pub mod upload;
pub mod web;
pub mod ws;

use crate::error::ApiError;
use crate::state::SharedState;
use axum::extract::{ConnectInfo, DefaultBodyLimit, Request, State};
use axum::http::{header, HeaderValue, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, patch, post};
use axum::Router;
use std::net::SocketAddr;
use tower::ServiceBuilder;

pub fn router(state: SharedState) -> Router {
    Router::new()
        // session & participants
        .route("/api/health", get(session::health))
        .route("/api/session/info", get(session::info))
        .route("/api/session/join", post(session::join))
        .route("/api/session/me", get(session::me))
        .route("/api/session/participants", get(session::participants))
        .route("/api/session/leave", post(session::leave))
        .route("/api/session/end", post(session::end))
        .route("/api/session/settings", patch(session::update_settings))
        .route("/api/session/stats", get(session::stats))
        .route("/api/participants/{id}/approve", post(session::approve))
        .route("/api/participants/{id}/reject", post(session::reject))
        .route("/api/participants/{id}/remove", post(session::remove))
        .route("/api/participants/{id}/block", post(session::block))
        .route("/api/storage/info", get(session::storage_info))
        // media
        .route("/api/media", get(media::list))
        .route("/api/media/upload", post(upload::create))
        .route("/api/media/download", post(download::create_export))
        .route("/api/media/{id}", get(media::get).delete(media::delete))
        .route("/api/media/{id}/file", get(download::file))
        .route(
            "/api/media/{id}/thumbnail",
            get(media::thumbnail).put(media::put_thumbnail).layer(DefaultBodyLimit::max(4 * 1024 * 1024)),
        )
        .route("/api/media/{id}/favorite", post(media::favorite).delete(media::unfavorite))
        // resumable uploads
        .route("/api/uploads", get(upload::list))
        .route("/api/uploads/{id}", get(upload::status).put(upload::put_chunk).delete(upload::cancel))
        .route("/api/uploads/{id}/complete", post(upload::complete))
        // exports
        .route("/api/exports/{id}", get(download::export))
        // realtime
        .route("/api/ws", get(ws::handler))
        // bundled browser client
        .route("/", get(web::index))
        .route("/app.js", get(web::js))
        .route("/app.css", get(web::css))
        .route("/icon.svg", get(web::icon))
        .fallback(fallback)
        .layer(
            ServiceBuilder::new()
                .layer(middleware::from_fn(security_headers))
                .layer(middleware::from_fn_with_state(state.clone(), rate_limit))
                .layer(DefaultBodyLimit::max(256 * 1024)),
        )
        .with_state(state)
}

async fn fallback() -> ApiError {
    ApiError::new(StatusCode::NOT_FOUND, "not_found", "No such endpoint")
}

async fn rate_limit(State(st): State<SharedState>, req: Request, next: Next) -> Response {
    if let Some(ConnectInfo(addr)) = req.extensions().get::<ConnectInfo<SocketAddr>>() {
        if !addr.ip().is_loopback() {
            if let Err(wait) = st.limiter.check(addr.ip()) {
                return ApiError::new(StatusCode::TOO_MANY_REQUESTS, "rate_limited", "Too many requests, slow down")
                    .with_retry_after(wait)
                    .into_response();
            }
        }
    }
    next.run(req).await
}

async fn security_headers(req: Request, next: Next) -> Response {
    let is_api = req.uri().path().starts_with("/api/");
    let mut resp = next.run(req).await;
    let h = resp.headers_mut();
    h.insert("x-content-type-options", HeaderValue::from_static("nosniff"));
    h.insert("referrer-policy", HeaderValue::from_static("no-referrer"));
    h.insert("x-frame-options", HeaderValue::from_static("DENY"));
    if is_api && !h.contains_key(header::CACHE_CONTROL) {
        h.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    }
    resp
}

/// Public JSON view of a participant with live/derived fields.
pub fn participant_json(
    p: &crate::db::Participant,
    online: bool,
    stats: Option<&crate::db::ParticipantStats>,
) -> serde_json::Value {
    let mut v = serde_json::to_value(p).unwrap_or_default();
    v["online"] = online.into();
    v["initials"] = initials(&p.name).into();
    let s = stats.cloned().unwrap_or_default();
    v["photos"] = s.photos.into();
    v["videos"] = s.videos.into();
    v["bytes"] = s.bytes.into();
    v
}

pub fn initials(name: &str) -> String {
    name.split_whitespace().filter_map(|w| w.chars().next()).take(2).flat_map(|c| c.to_uppercase()).collect()
}
