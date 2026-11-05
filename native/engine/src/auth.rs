//! Authentication. Every participant (including the host) holds a random
//! 256-bit bearer token; only its SHA-256 hash is stored. Browsers receive
//! the token in an HttpOnly, SameSite=Strict cookie, apps send it in the
//! `Authorization: Bearer` header.

use crate::db::{self, Participant};
use crate::error::{ApiError, ApiResult};
use crate::state::SharedState;
use crate::util::{now_ms, sha256_hex};
use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use axum::http::{header, HeaderMap};

pub const COOKIE_NAME: &str = "ld_token";

pub fn hash_token(token: &str) -> String {
    sha256_hex(token.as_bytes())
}

pub fn token_from_headers(headers: &HeaderMap) -> Option<String> {
    if let Some(v) = headers.get(header::AUTHORIZATION).and_then(|v| v.to_str().ok()) {
        if let Some(t) = v.strip_prefix("Bearer ") {
            return Some(t.trim().to_string());
        }
    }
    let cookies = headers.get_all(header::COOKIE);
    for c in cookies.iter().filter_map(|v| v.to_str().ok()) {
        for part in c.split(';') {
            if let Some((k, v)) = part.trim().split_once('=') {
                if k == COOKIE_NAME && !v.is_empty() {
                    return Some(v.to_string());
                }
            }
        }
    }
    None
}

fn token_from_parts(parts: &Parts) -> Option<String> {
    if let Some(t) = token_from_headers(&parts.headers) {
        return Some(t);
    }
    // WebSocket clients cannot always set headers; accept a query token there only.
    if parts.uri.path() == "/api/ws" {
        if let Some(q) = parts.uri.query() {
            for pair in q.split('&') {
                if let Some(t) = pair.strip_prefix("token=") {
                    return Some(t.to_string());
                }
            }
        }
    }
    None
}

async fn resolve(parts: &Parts, state: &SharedState) -> ApiResult<Participant> {
    if state.is_ended() {
        return Err(ApiError::session_ended());
    }
    let token = token_from_parts(parts).ok_or_else(ApiError::unauthorized)?;
    if token.len() != 64 || !token.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(ApiError::unauthorized());
    }
    let hash = hash_token(&token);
    let p = state.db.call(move |c| db::participant_by_token_hash(c, &hash)).await?.ok_or_else(ApiError::unauthorized)?;
    let now = now_ms();
    if now - p.last_seen > 15_000 {
        let id = p.id.clone();
        let _ = state.db.call(move |c| db::touch_participant(c, &id, now)).await;
    }
    Ok(p)
}

/// An authenticated, approved participant.
pub struct Auth(pub Participant);

impl Auth {
    pub fn is_host(&self) -> bool {
        self.0.is_host()
    }
    pub fn id(&self) -> &str {
        &self.0.id
    }
    pub fn require_host(&self) -> ApiResult<()> {
        if self.is_host() {
            Ok(())
        } else {
            Err(ApiError::forbidden("host_only", "Only the session host can do this"))
        }
    }
}

fn check_status(p: &Participant, allow_pending: bool) -> ApiResult<()> {
    match p.status.as_str() {
        "active" => Ok(()),
        "pending" if allow_pending => Ok(()),
        "pending" => Err(ApiError::forbidden("pending_approval", "Waiting for the host to approve you")),
        "blocked" => Err(ApiError::forbidden("blocked", "You were blocked from this session")),
        "removed" => Err(ApiError::forbidden("removed", "You were removed from this session")),
        _ => Err(ApiError::unauthorized()),
    }
}

impl FromRequestParts<SharedState> for Auth {
    type Rejection = ApiError;
    async fn from_request_parts(parts: &mut Parts, state: &SharedState) -> Result<Self, Self::Rejection> {
        let p = resolve(parts, state).await?;
        check_status(&p, false)?;
        Ok(Auth(p))
    }
}

/// Like [`Auth`] but also admits participants waiting for approval, and
/// reports removed/blocked state instead of failing (used by `/me`).
pub struct AnyAuth(pub Participant);

impl FromRequestParts<SharedState> for AnyAuth {
    type Rejection = ApiError;
    async fn from_request_parts(parts: &mut Parts, state: &SharedState) -> Result<Self, Self::Rejection> {
        Ok(AnyAuth(resolve(parts, state).await?))
    }
}

/// Optional authentication (public endpoints that reveal more when signed in).
pub struct MaybeAuth(pub Option<Participant>);

impl FromRequestParts<SharedState> for MaybeAuth {
    type Rejection = ApiError;
    async fn from_request_parts(parts: &mut Parts, state: &SharedState) -> Result<Self, Self::Rejection> {
        match resolve(parts, state).await {
            Ok(p) if p.status == "active" => Ok(MaybeAuth(Some(p))),
            Ok(_) => Ok(MaybeAuth(None)),
            Err(e) if e.code == "session_ended" => Err(e),
            Err(_) => Ok(MaybeAuth(None)),
        }
    }
}

pub fn session_cookie(token: &str) -> String {
    format!("{COOKIE_NAME}={token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=2592000")
}

pub fn clear_cookie() -> String {
    format!("{COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0")
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::HeaderValue;

    #[test]
    fn reads_bearer_and_cookie() {
        let mut h = HeaderMap::new();
        h.insert(header::AUTHORIZATION, HeaderValue::from_static("Bearer abc"));
        assert_eq!(token_from_headers(&h).as_deref(), Some("abc"));
        let mut h = HeaderMap::new();
        h.insert(header::COOKIE, HeaderValue::from_static("x=1; ld_token=def; y=2"));
        assert_eq!(token_from_headers(&h).as_deref(), Some("def"));
        assert!(token_from_headers(&HeaderMap::new()).is_none());
    }
}
