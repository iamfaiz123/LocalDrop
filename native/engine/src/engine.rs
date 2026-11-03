//! Session lifecycle: create or resume a session, bind the server, run
//! background maintenance, and stop gracefully.

use crate::api;
use crate::auth;
use crate::config::EngineConfig;
use crate::db::{self, Db, Participant, SessionRow};
use crate::net::{self, InterfaceInfo};
use crate::state::{AppState, Paths, SharedState};
use crate::util::{clean_display_name, new_id, now_ms, random_pin, random_token};
use serde::Serialize;
use serde_json::json;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;
use tokio::net::TcpListener;
use tokio::task::JoinHandle;

#[derive(Debug, Clone, Serialize)]
pub struct StartedSession {
    pub session_id: String,
    pub session_name: String,
    pub host_name: String,
    pub pin: String,
    /// Bearer token for the host's own API calls. Never shown to users.
    pub host_token: String,
    pub host_participant_id: String,
    pub port: u16,
    pub local_url: String,
    pub urls: Vec<String>,
    pub join_url: Option<String>,
    pub addresses: Vec<InterfaceInfo>,
    /// False when no interface usable by hotspot/Wi-Fi clients was found.
    pub network_ok: bool,
    pub session_dir: PathBuf,
    pub resumed: bool,
}

pub struct RunningEngine {
    pub state: SharedState,
    pub info: StartedSession,
    server: JoinHandle<()>,
    janitor: JoinHandle<()>,
}

impl RunningEngine {
    pub fn is_running(&self) -> bool {
        !self.server.is_finished()
    }

    /// Stops the server. In-flight transfers get a short grace period.
    pub async fn stop(self) {
        self.state.shutdown.cancel();
        self.janitor.abort();
        let abort = self.server.abort_handle();
        if tokio::time::timeout(Duration::from_secs(4), self.server).await.is_err() {
            abort.abort();
        }
    }

    pub fn status_json(&self) -> serde_json::Value {
        json!({
            "running": self.is_running(),
            "ended": self.state.is_ended(),
            "session_id": self.info.session_id,
            "port": self.info.port,
            "local_url": self.info.local_url,
            "urls": self.state.urls(),
            "join_url": self.state.join_url(),
            "addresses": self.state.addresses(),
            "network_ok": net::primary(&self.state.addresses()).is_some(),
            // Lets a re-launched UI (same process) re-attach as host.
            "session": StartedSession {
                urls: self.state.urls(),
                join_url: self.state.join_url(),
                addresses: self.state.addresses(),
                ..self.info.clone()
            },
        })
    }
}

pub fn session_dir(data_dir: &Path, id: &str) -> PathBuf {
    data_dir.join("sessions").join(id)
}

async fn bind(cfg: &EngineConfig) -> Result<TcpListener, String> {
    let ip: IpAddr = match &cfg.bind_address {
        Some(a) => a.parse().map_err(|_| format!("invalid bind_address '{a}'"))?,
        None => IpAddr::V4(Ipv4Addr::UNSPECIFIED),
    };
    if cfg.port != 0 {
        for port in cfg.port..cfg.port.saturating_add(10) {
            match TcpListener::bind(SocketAddr::new(ip, port)).await {
                Ok(l) => return Ok(l),
                Err(e) if e.kind() == std::io::ErrorKind::AddrInUse => continue,
                Err(e) => return Err(format!("could not start server on port {port}: {e}")),
            }
        }
    }
    TcpListener::bind(SocketAddr::new(ip, 0)).await.map_err(|e| format!("could not start server: {e}"))
}

/// Creates (or resumes) a session and starts serving it.
pub async fn start(cfg: EngineConfig) -> Result<RunningEngine, String> {
    cfg.validate()?;
    std::fs::create_dir_all(cfg.data_dir.join("sessions")).map_err(|e| format!("cannot create data directory: {e}"))?;

    let host_token = random_token(32);
    let (session_id, resumed) = match &cfg.resume_session_id {
        Some(id) => {
            if id.len() != 32 || !id.bytes().all(|b| b.is_ascii_hexdigit()) {
                return Err("invalid session id".into());
            }
            (id.clone(), true)
        }
        None => (new_id(), false),
    };
    let paths = Paths::new(session_dir(&cfg.data_dir, &session_id));
    if resumed && !paths.root.join("session.db").exists() {
        return Err("that session no longer exists on this device".into());
    }
    paths.create_all().map_err(|e| format!("cannot create session directory: {e}"))?;
    let db = Db::open(&paths.root.join("session.db")).map_err(|e| e.to_string())?;

    let (session, host) = if resumed {
        db.with(|c| {
            let s = db::get_session(c)?;
            let host = db::host_participant(c)?;
            db::set_participant_token(c, &host.id, &auth::hash_token(&host_token))?;
            Ok((s, host))
        })
        .map_err(|e| e.to_string())?
    } else {
        let name = clean_display_name(&cfg.session_name, 60).ok_or("Session name must be 1–60 characters")?;
        let host_name = clean_display_name(&cfg.host_name, 40).ok_or("Your name must be 1–40 characters")?;
        let now = now_ms();
        let s = SessionRow {
            id: session_id.clone(),
            name,
            host_name: host_name.clone(),
            pin: random_pin(cfg.pin_length),
            created_at: now,
            ended_at: None,
            upload_permission: "everyone".into(),
            download_permission: "everyone".into(),
            require_approval: cfg.require_approval,
            keep_media: cfg.keep_media_on_end,
        };
        let pid = new_id();
        let host = Participant {
            avatar_color: api::session::avatar_color(&pid),
            id: pid,
            name: host_name,
            role: "host".into(),
            status: "active".into(),
            device_id: None,
            joined_at: now,
            last_seen: now,
        };
        db.with(|c| {
            db::insert_session(c, &s)?;
            db::insert_participant(c, &host, &auth::hash_token(&host_token))?;
            db::log_activity(c, "session_started", Some(&host.id), &format!("{} started the session", host.name), now)
        })
        .map_err(|e| e.to_string())?;
        (s, host)
    };
    if session.ended_at.is_some() {
        return Err("that session has already ended".into());
    }

    let listener = bind(&cfg).await?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let addresses = net::list_interfaces();
    let network_ok = net::primary(&addresses).is_some();
    if !network_ok {
        tracing::warn!("no hotspot/Wi-Fi interface found; participants will not be able to connect yet");
    }

    let state: SharedState = Arc::new(AppState::new(cfg, db, paths, session_id.clone(), port, addresses.clone()));
    if resumed {
        // Drop leftover bytes past each upload's acknowledged offset.
        let st = state.clone();
        let _ = state
            .db
            .call(move |c| {
                for u in db::list_uploads(c, None)? {
                    let path = st.paths.upload_part(&u.id);
                    let len = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
                    if len != u.received {
                        let good = len.min(u.received);
                        if let Ok(f) = std::fs::OpenOptions::new().write(true).create(true).truncate(false).open(&path) {
                            let _ = f.set_len(good);
                        }
                        db::set_upload_received(c, &u.id, good, now_ms())?;
                    }
                }
                Ok(())
            })
            .await;
    }

    let app = api::router(state.clone());
    let token = state.shutdown.clone();
    let server = tokio::spawn(async move {
        let res = axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>())
            .with_graceful_shutdown(async move { token.cancelled().await })
            .await;
        if let Err(e) = res {
            tracing::error!("server error: {e}");
        }
    });
    let janitor = tokio::spawn(janitor(state.clone()));

    let info = StartedSession {
        session_id,
        session_name: session.name,
        host_name: session.host_name,
        pin: session.pin,
        host_token,
        host_participant_id: host.id,
        port,
        local_url: format!("http://127.0.0.1:{port}"),
        urls: state.urls(),
        join_url: state.join_url(),
        addresses,
        network_ok,
        session_dir: state.paths.root.clone(),
        resumed,
    };
    tracing::info!("LocalDrop session '{}' listening on port {port}", info.session_name);
    Ok(RunningEngine { state, info, server, janitor })
}

/// Periodic maintenance: network changes, stale uploads, expired exports,
/// low-storage warnings.
async fn janitor(st: SharedState) {
    let mut tick = tokio::time::interval(Duration::from_secs(10));
    let mut n: u64 = 0;
    let mut warned_low = false;
    loop {
        tokio::select! {
            _ = st.shutdown.cancelled() => break,
            _ = tick.tick() => {}
        }
        n += 1;
        let current = tokio::task::spawn_blocking(net::list_interfaces).await.unwrap_or_default();
        let changed = { *st.addresses.read().unwrap_or_else(|e| e.into_inner()) != current };
        if changed {
            *st.addresses.write().unwrap_or_else(|e| e.into_inner()) = current.clone();
            tracing::info!("network interfaces changed");
            st.emit(
                "network_changed",
                json!({ "addresses": current, "urls": st.urls(), "join_url": st.join_url(), "network_ok": net::primary(&current).is_some() }),
            );
        }
        if n % 6 == 0 {
            api::upload::expire_stale(&st).await;
            st.exports
                .lock()
                .unwrap_or_else(|e| e.into_inner())
                .retain(|_, e| e.created.elapsed() < api::download::EXPORT_TTL);
            if let Some(space) = crate::storage::disk_space(&st.paths.root) {
                let low = space.free_bytes < st.cfg.min_free_space.saturating_mul(2);
                if low && !warned_low {
                    st.emit("storage_warning", json!({ "free_bytes": space.free_bytes, "total_bytes": space.total_bytes }));
                }
                warned_low = low;
            }
        }
    }
}

#[derive(Debug, Serialize)]
pub struct SessionSummary {
    pub id: String,
    pub name: String,
    pub host_name: String,
    pub created_at: i64,
    pub ended_at: Option<i64>,
    pub photos: u64,
    pub videos: u64,
    pub bytes: u64,
    pub pending_uploads: u64,
}

/// Sessions stored under `data_dir` (newest first). Used to resume after
/// the app was killed and to manage stored session data.
pub fn list_sessions(data_dir: &Path) -> Vec<SessionSummary> {
    let mut out = Vec::new();
    let Ok(rd) = std::fs::read_dir(data_dir.join("sessions")) else { return out };
    for e in rd.flatten() {
        let dbp = e.path().join("session.db");
        if !dbp.exists() {
            continue;
        }
        let Ok(db) = Db::open(&dbp) else { continue };
        let r = db.with(|c| {
            let s = db::get_session(c)?;
            let t = db::media_totals(c)?;
            let pending: i64 = c.query_row("SELECT COUNT(*) FROM uploads", [], |r| r.get(0))?;
            Ok(SessionSummary {
                id: s.id,
                name: s.name,
                host_name: s.host_name,
                created_at: s.created_at,
                ended_at: s.ended_at,
                photos: t.photos,
                videos: t.videos,
                bytes: t.bytes,
                pending_uploads: pending as u64,
            })
        });
        if let Ok(s) = r {
            out.push(s);
        }
    }
    out.sort_by_key(|s| std::cmp::Reverse(s.created_at));
    out
}

/// Permanently deletes a stored session (database, media, thumbnails).
pub fn delete_session_data(data_dir: &Path, id: &str) -> Result<(), String> {
    if id.len() != 32 || !id.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("invalid session id".into());
    }
    let dir = session_dir(data_dir, id);
    if !dir.exists() {
        return Err("session not found".into());
    }
    std::fs::remove_dir_all(dir).map_err(|e| e.to_string())
}
