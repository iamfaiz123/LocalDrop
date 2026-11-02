//! LocalDrop engine.
//!
//! A self-contained local-network media sharing server. The host device runs
//! this engine; participants connect to it over the local network with either
//! the LocalDrop app or any modern mobile browser (a web client is bundled).
//!
//! Layers:
//! * [`engine`]  – start/stop lifecycle, used by the FFI layer and the CLI.
//! * [`api`]     – Axum HTTP + WebSocket API.
//! * [`db`]      – SQLite persistence (one database per session).
//! * [`zip`]     – streaming, seekable ZIP (store) export.
//! * [`ffi`]     – C ABI consumed by Flutter through `dart:ffi`.

pub mod api;
pub mod auth;
pub mod config;
pub mod db;
pub mod engine;
pub mod error;
pub mod ffi;
pub mod net;
pub mod ratelimit;
pub mod sniff;
pub mod state;
pub mod storage;
pub mod thumbs;
pub mod util;
pub mod zip;

pub use config::EngineConfig;
pub use engine::{start, RunningEngine, StartedSession};
