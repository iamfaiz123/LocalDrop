use axum::http::{header, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use serde_json::json;
use std::fmt;

/// Error returned by every API handler. Serialised as
/// `{"error": {"code": "...", "message": "..."}}` with an HTTP status code.
#[derive(Debug)]
pub struct ApiError {
    pub status: StatusCode,
    pub code: &'static str,
    pub message: String,
    pub extra: Option<serde_json::Value>,
    pub retry_after: Option<u64>,
}

impl ApiError {
    pub fn new(status: StatusCode, code: &'static str, message: impl Into<String>) -> Self {
        Self { status, code, message: message.into(), extra: None, retry_after: None }
    }
    pub fn with_extra(mut self, extra: serde_json::Value) -> Self {
        self.extra = Some(extra);
        self
    }
    pub fn with_retry_after(mut self, secs: u64) -> Self {
        self.retry_after = Some(secs);
        self
    }
    pub fn bad_request(msg: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, "bad_request", msg)
    }
    pub fn unauthorized() -> Self {
        Self::new(StatusCode::UNAUTHORIZED, "unauthorized", "Missing or invalid session credentials")
    }
    pub fn forbidden(code: &'static str, msg: impl Into<String>) -> Self {
        Self::new(StatusCode::FORBIDDEN, code, msg)
    }
    pub fn not_found(what: &str) -> Self {
        Self::new(StatusCode::NOT_FOUND, "not_found", format!("{what} not found"))
    }
    pub fn conflict(code: &'static str, msg: impl Into<String>) -> Self {
        Self::new(StatusCode::CONFLICT, code, msg)
    }
    pub fn internal(msg: impl Into<String>) -> Self {
        let msg = msg.into();
        tracing::error!("internal error: {msg}");
        Self::new(StatusCode::INTERNAL_SERVER_ERROR, "internal", msg)
    }
    pub fn session_ended() -> Self {
        Self::new(StatusCode::GONE, "session_ended", "This session has ended")
    }
    pub fn insufficient_storage(msg: impl Into<String>) -> Self {
        Self::new(StatusCode::INSUFFICIENT_STORAGE, "insufficient_storage", msg)
    }
}

impl fmt::Display for ApiError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} ({}): {}", self.code, self.status, self.message)
    }
}

impl std::error::Error for ApiError {}

impl From<rusqlite::Error> for ApiError {
    fn from(e: rusqlite::Error) -> Self {
        ApiError::internal(format!("database error: {e}"))
    }
}

impl From<std::io::Error> for ApiError {
    fn from(e: std::io::Error) -> Self {
        if crate::storage::is_out_of_space(&e) {
            return ApiError::insufficient_storage("The host device ran out of storage space");
        }
        ApiError::internal(format!("I/O error: {e}"))
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let mut body = json!({ "error": { "code": self.code, "message": self.message } });
        if let Some(extra) = self.extra {
            if let (Some(obj), Some(extra)) = (body["error"].as_object_mut(), extra.as_object()) {
                for (k, v) in extra {
                    obj.insert(k.clone(), v.clone());
                }
            }
        }
        let mut resp = (self.status, axum::Json(body)).into_response();
        if let Some(secs) = self.retry_after {
            if let Ok(v) = HeaderValue::from_str(&secs.to_string()) {
                resp.headers_mut().insert(header::RETRY_AFTER, v);
            }
        }
        resp
    }
}

pub type ApiResult<T> = Result<T, ApiError>;
