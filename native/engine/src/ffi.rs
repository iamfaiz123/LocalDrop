//! C ABI used by the Flutter app through `dart:ffi`.
//!
//! Every function takes/returns UTF-8 JSON strings. Returned strings are
//! owned by Rust and must be released with [`ld_string_free`]. Results are
//! `{"ok": true, ...}` or `{"ok": false, "error": "message"}`.
//!
//! Only lifecycle operations cross the FFI boundary. All session data is
//! exchanged over the engine's HTTP/WebSocket API (on 127.0.0.1 for the
//! host), which keeps the host app and remote participants on one code path.

use crate::config::EngineConfig;
use crate::engine::{self, RunningEngine};
use serde_json::{json, Value};
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
static ENGINE: Mutex<Option<RunningEngine>> = Mutex::new(None);

fn runtime() -> &'static tokio::runtime::Runtime {
    RUNTIME.get_or_init(|| {
        let _ = tracing_subscriber::fmt().with_env_filter("localdrop_engine=info").try_init();
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(4)
            .thread_name("localdrop-engine")
            .enable_all()
            .build()
            .expect("failed to build tokio runtime")
    })
}

fn out(v: Value) -> *mut c_char {
    CString::new(v.to_string()).unwrap_or_else(|_| CString::new("{\"ok\":false}").unwrap()).into_raw()
}

fn err(msg: impl std::fmt::Display) -> *mut c_char {
    out(json!({ "ok": false, "error": msg.to_string() }))
}

/// # Safety
/// `p` must be NULL or a valid NUL-terminated string.
unsafe fn arg(p: *const c_char) -> Result<String, String> {
    if p.is_null() {
        return Err("null argument".into());
    }
    CStr::from_ptr(p).to_str().map(str::to_owned).map_err(|_| "argument is not UTF-8".into())
}

fn guarded(f: impl FnOnce() -> *mut c_char) -> *mut c_char {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|_| err("internal panic in engine"))
}

/// Starts a session. `config_json` follows [`EngineConfig`].
///
/// # Safety
/// `config_json` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn ld_engine_start(config_json: *const c_char) -> *mut c_char {
    guarded(|| {
        let raw = match arg(config_json) {
            Ok(s) => s,
            Err(e) => return err(e),
        };
        let cfg: EngineConfig = match serde_json::from_str(&raw) {
            Ok(c) => c,
            Err(e) => return err(format!("invalid config: {e}")),
        };
        let mut slot = ENGINE.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(running) = slot.take() {
            if running.is_running() && !running.state.is_ended() {
                let info = running.info.clone();
                *slot = Some(running);
                return out(json!({ "ok": false, "error": "a session is already running", "session_id": info.session_id }));
            }
        }
        match runtime().block_on(engine::start(cfg)) {
            Ok(running) => {
                let info = serde_json::to_value(&running.info).unwrap_or_default();
                *slot = Some(running);
                out(json!({ "ok": true, "session": info }))
            }
            Err(e) => err(e),
        }
    })
}

/// Stops the running server (does not end/delete the session; it can be
/// resumed later with `resume_session_id`).
#[no_mangle]
pub extern "C" fn ld_engine_stop() -> *mut c_char {
    guarded(|| {
        let running = ENGINE.lock().unwrap_or_else(|e| e.into_inner()).take();
        match running {
            Some(r) => {
                runtime().block_on(r.stop());
                out(json!({ "ok": true }))
            }
            None => out(json!({ "ok": true, "was_running": false })),
        }
    })
}

#[no_mangle]
pub extern "C" fn ld_engine_status() -> *mut c_char {
    guarded(|| {
        let slot = ENGINE.lock().unwrap_or_else(|e| e.into_inner());
        match slot.as_ref() {
            Some(r) => {
                let mut v = r.status_json();
                v["ok"] = true.into();
                out(v)
            }
            None => out(json!({ "ok": true, "running": false })),
        }
    })
}

#[no_mangle]
pub extern "C" fn ld_network_interfaces() -> *mut c_char {
    guarded(|| {
        let list = crate::net::list_interfaces();
        let primary = crate::net::primary(&list).cloned();
        out(json!({ "ok": true, "interfaces": list, "primary": primary }))
    })
}

/// # Safety
/// `data_dir` must be a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn ld_list_sessions(data_dir: *const c_char) -> *mut c_char {
    guarded(|| match arg(data_dir) {
        Ok(d) => out(json!({ "ok": true, "sessions": engine::list_sessions(&PathBuf::from(d)) })),
        Err(e) => err(e),
    })
}

/// # Safety
/// Both arguments must be valid NUL-terminated UTF-8 strings.
#[no_mangle]
pub unsafe extern "C" fn ld_delete_session(data_dir: *const c_char, session_id: *const c_char) -> *mut c_char {
    guarded(|| {
        let (d, id) = match (arg(data_dir), arg(session_id)) {
            (Ok(d), Ok(id)) => (d, id),
            (Err(e), _) | (_, Err(e)) => return err(e),
        };
        let slot = ENGINE.lock().unwrap_or_else(|e| e.into_inner());
        if slot.as_ref().is_some_and(|r| r.info.session_id == id && r.is_running()) {
            return err("stop the session before deleting its data");
        }
        match engine::delete_session_data(&PathBuf::from(d), &id) {
            Ok(()) => out(json!({ "ok": true })),
            Err(e) => err(e),
        }
    })
}

/// Releases a string returned by any `ld_*` function.
///
/// # Safety
/// `p` must come from this library and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn ld_string_free(p: *mut c_char) {
    if !p.is_null() {
        drop(CString::from_raw(p));
    }
}
