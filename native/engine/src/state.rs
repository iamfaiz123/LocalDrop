use crate::config::EngineConfig;
use crate::db::{self, Db};
use crate::net::InterfaceInfo;
use crate::ratelimit::{PinGuard, RateLimiter};
use crate::util::now_ms;
use serde::Serialize;
use serde_json::Value;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, RwLock};
use std::time::Duration;
use tokio::sync::{broadcast, Semaphore};
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone)]
pub struct Paths {
    pub root: PathBuf,
    pub media: PathBuf,
    pub thumbs: PathBuf,
    pub tmp: PathBuf,
}

impl Paths {
    pub fn new(root: PathBuf) -> Self {
        Self { media: root.join("media"), thumbs: root.join("thumbs"), tmp: root.join("tmp"), root }
    }
    pub fn create_all(&self) -> std::io::Result<()> {
        for d in [&self.root, &self.media, &self.thumbs, &self.tmp] {
            std::fs::create_dir_all(d)?;
        }
        Ok(())
    }
    /// Paths are always built from server-generated hex IDs and sniffed
    /// extensions; client input never reaches the filesystem.
    pub fn media_file(&self, id: &str, ext: &str) -> PathBuf {
        debug_assert!(id.bytes().all(|b| b.is_ascii_hexdigit()));
        self.media.join(format!("{id}.{ext}"))
    }
    pub fn thumb_file(&self, id: &str) -> PathBuf {
        self.thumbs.join(format!("{id}.jpg"))
    }
    pub fn upload_part(&self, id: &str) -> PathBuf {
        self.tmp.join(format!("{id}.part"))
    }
}

/// Real-time event delivered over WebSocket.
#[derive(Debug, Clone, Serialize)]
pub struct Event {
    #[serde(rename = "type")]
    pub kind: &'static str,
    pub data: Value,
    pub ts: i64,
    /// When set, only this participant (and the host) receives the event.
    #[serde(skip)]
    pub only_for: Option<String>,
}

pub struct ExportEntry {
    pub name: String,
    pub path: PathBuf,
    pub size: u64,
    pub crc32: u32,
    pub mtime_ms: i64,
}

pub struct Export {
    pub participant_id: String,
    pub entries: Arc<Vec<ExportEntry>>,
    pub created: std::time::Instant,
    pub filename: String,
}

pub struct AppState {
    pub cfg: EngineConfig,
    pub db: Db,
    pub paths: Paths,
    pub session_id: String,
    pub started_at: i64,
    pub port: u16,
    pub events: broadcast::Sender<Event>,
    pub presence: Mutex<HashMap<String, usize>>,
    pub upload_locks: Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>>,
    pub upload_sem: Arc<Semaphore>,
    pub thumb_sem: Arc<Semaphore>,
    pub limiter: RateLimiter,
    pub pin_guard: PinGuard,
    pub exports: Mutex<HashMap<String, Export>>,
    pub addresses: RwLock<Vec<InterfaceInfo>>,
    pub shutdown: CancellationToken,
    pub ended: std::sync::atomic::AtomicBool,
}

impl AppState {
    pub fn new(cfg: EngineConfig, db: Db, paths: Paths, session_id: String, port: u16, addresses: Vec<InterfaceInfo>) -> Self {
        let (events, _) = broadcast::channel(1024);
        Self {
            upload_sem: Arc::new(Semaphore::new(cfg.max_concurrent_uploads)),
            thumb_sem: Arc::new(Semaphore::new(cfg.max_concurrent_thumbnails)),
            cfg,
            db,
            paths,
            session_id,
            started_at: now_ms(),
            port,
            events,
            presence: Mutex::new(HashMap::new()),
            upload_locks: Mutex::new(HashMap::new()),
            limiter: RateLimiter::new(600, 200),
            pin_guard: PinGuard::new(Duration::from_secs(300), 5, 30),
            exports: Mutex::new(HashMap::new()),
            addresses: RwLock::new(addresses),
            shutdown: CancellationToken::new(),
            ended: std::sync::atomic::AtomicBool::new(false),
        }
    }

    pub fn emit(&self, kind: &'static str, data: Value) {
        let _ = self.events.send(Event { kind, data, ts: now_ms(), only_for: None });
    }

    pub fn emit_to(&self, participant_id: &str, kind: &'static str, data: Value) {
        let _ = self.events.send(Event { kind, data, ts: now_ms(), only_for: Some(participant_id.to_string()) });
    }

    pub fn is_online(&self, participant_id: &str) -> bool {
        self.presence.lock().unwrap_or_else(|e| e.into_inner()).get(participant_id).copied().unwrap_or(0) > 0
    }

    pub fn is_ended(&self) -> bool {
        self.ended.load(std::sync::atomic::Ordering::SeqCst)
    }

    pub fn upload_lock(&self, upload_id: &str) -> Arc<tokio::sync::Mutex<()>> {
        let mut map = self.upload_locks.lock().unwrap_or_else(|e| e.into_inner());
        map.entry(upload_id.to_string()).or_default().clone()
    }

    pub fn drop_upload_lock(&self, upload_id: &str) {
        self.upload_locks.lock().unwrap_or_else(|e| e.into_inner()).remove(upload_id);
    }

    pub fn addresses(&self) -> Vec<InterfaceInfo> {
        self.addresses.read().unwrap_or_else(|e| e.into_inner()).clone()
    }

    /// URLs participants can use, best first.
    pub fn urls(&self) -> Vec<String> {
        self.addresses().iter().filter(|a| a.usable).map(|a| format!("http://{}:{}", a.ip, self.port)).collect()
    }

    pub fn join_url(&self) -> Option<String> {
        self.urls().first().map(|u| format!("{u}/?sid={}", self.session_id))
    }

    pub async fn log(&self, kind: &'static str, participant_id: Option<String>, detail: String) {
        let ts = now_ms();
        let res = self
            .db
            .call(move |c| db::log_activity(c, kind, participant_id.as_deref(), &detail, ts))
            .await;
        if let Err(e) = res {
            tracing::warn!("failed to record activity: {e}");
        }
    }
}

pub type SharedState = Arc<AppState>;
