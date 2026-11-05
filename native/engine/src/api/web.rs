//! The browser client, compiled into the binary so it works fully offline.

use axum::http::{header, HeaderValue};
use axum::response::{IntoResponse, Response};

const INDEX: &str = include_str!("../../web/index.html");
const JS: &str = include_str!("../../web/app.js");
const CSS: &str = include_str!("../../web/app.css");
const ICON: &str = include_str!("../../web/icon.svg");

const CSP: &str = "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' blob: data:; \
media-src 'self' blob:; connect-src 'self' ws: wss:; manifest-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";

fn asset(body: &'static str, ctype: &'static str) -> Response {
    let mut r = body.into_response();
    let h = r.headers_mut();
    h.insert(header::CONTENT_TYPE, HeaderValue::from_static(ctype));
    h.insert(header::CACHE_CONTROL, HeaderValue::from_static("no-cache"));
    r
}

pub async fn index() -> Response {
    let mut r = asset(INDEX, "text/html; charset=utf-8");
    r.headers_mut().insert(header::CONTENT_SECURITY_POLICY, HeaderValue::from_static(CSP));
    r
}

pub async fn js() -> Response {
    asset(JS, "text/javascript; charset=utf-8")
}

pub async fn css() -> Response {
    asset(CSS, "text/css; charset=utf-8")
}

pub async fn icon() -> Response {
    asset(ICON, "image/svg+xml")
}
