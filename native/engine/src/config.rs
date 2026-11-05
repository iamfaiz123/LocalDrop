use serde::Deserialize;
use std::path::PathBuf;

const MIB: u64 = 1024 * 1024;
const GIB: u64 = 1024 * MIB;

/// Engine configuration. All fields have defaults so callers (FFI JSON, CLI)
/// only need to provide what they want to change.
#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct EngineConfig {
    /// Root directory for all session data (databases, media, temp files).
    pub data_dir: PathBuf,
    pub session_name: String,
    pub host_name: String,
    /// Preferred TCP port. If busy, the next ports are tried, then an OS port.
    /// `0` asks the OS for a free port.
    pub port: u16,
    /// Address to bind. Defaults to all IPv4 interfaces so the server keeps
    /// working when the hotspot/Wi-Fi interface changes.
    pub bind_address: Option<String>,
    /// Number of PIN digits (4–6).
    pub pin_length: usize,
    /// Recommended chunk size handed to clients.
    pub chunk_size: u64,
    /// Largest chunk the server accepts in a single request.
    pub max_chunk_size: u64,
    /// Largest single file accepted.
    pub max_file_size: u64,
    /// Space that must remain free on the host after accepting an upload.
    pub min_free_space: u64,
    /// Maximum chunk writes processed at the same time (all participants).
    pub max_concurrent_uploads: usize,
    /// Maximum thumbnail decodes at the same time (RAM bound).
    pub max_concurrent_thumbnails: usize,
    /// New participants wait for host approval.
    pub require_approval: bool,
    /// Keep media on disk when the session ends.
    pub keep_media_on_end: bool,
    /// Resume an existing (not ended) session instead of creating one.
    pub resume_session_id: Option<String>,
    /// Hours before an idle unfinished upload is discarded.
    pub stale_upload_hours: u64,
}

impl Default for EngineConfig {
    fn default() -> Self {
        Self {
            data_dir: std::env::temp_dir().join("localdrop"),
            session_name: "LocalDrop session".into(),
            host_name: "Host".into(),
            port: 8080,
            bind_address: None,
            pin_length: 6,
            chunk_size: 8 * MIB,
            max_chunk_size: 64 * MIB,
            max_file_size: 64 * GIB,
            min_free_space: 512 * MIB,
            max_concurrent_uploads: 6,
            max_concurrent_thumbnails: 1,
            require_approval: false,
            keep_media_on_end: true,
            resume_session_id: None,
            stale_upload_hours: 48,
        }
    }
}

impl EngineConfig {
    pub fn validate(&self) -> Result<(), String> {
        if !(4..=6).contains(&self.pin_length) {
            return Err("pin_length must be between 4 and 6".into());
        }
        if self.chunk_size < 64 * 1024 || self.chunk_size > self.max_chunk_size {
            return Err("chunk_size must be >= 64 KiB and <= max_chunk_size".into());
        }
        if self.max_chunk_size > 512 * MIB {
            return Err("max_chunk_size must be <= 512 MiB".into());
        }
        if self.max_concurrent_uploads == 0 || self.max_concurrent_thumbnails == 0 {
            return Err("concurrency limits must be at least 1".into());
        }
        if self.max_file_size == 0 {
            return Err("max_file_size must be > 0".into());
        }
        Ok(())
    }
}
