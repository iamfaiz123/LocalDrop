//! SQLite persistence. One database per session, stored next to the
//! session's media. All access goes through [`Db::call`], which runs the
//! closure on Tokio's blocking pool so the async runtime is never stalled.

use crate::error::{ApiError, ApiResult};
use rusqlite::{params, Connection, OptionalExtension, Row};
use serde::Serialize;
use std::path::Path;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
pub struct Db {
    conn: Arc<Mutex<Connection>>,
}

const SCHEMA: &str = r#"
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS session (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    host_name TEXT NOT NULL,
    pin TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    ended_at INTEGER,
    upload_permission TEXT NOT NULL DEFAULT 'everyone',
    download_permission TEXT NOT NULL DEFAULT 'everyone',
    require_approval INTEGER NOT NULL DEFAULT 0,
    keep_media INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS participants (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    status TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    device_id TEXT,
    avatar_color INTEGER NOT NULL,
    joined_at INTEGER NOT NULL,
    last_seen INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS blocked_devices (
    device_id TEXT PRIMARY KEY,
    participant_id TEXT,
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS uploads (
    id TEXT PRIMARY KEY,
    participant_id TEXT NOT NULL,
    filename TEXT NOT NULL,
    ext TEXT NOT NULL,
    kind TEXT NOT NULL,
    size INTEGER NOT NULL,
    received INTEGER NOT NULL DEFAULT 0,
    expected_sha256 TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS media (
    id TEXT PRIMARY KEY,
    participant_id TEXT NOT NULL,
    filename TEXT NOT NULL,
    mime TEXT NOT NULL,
    kind TEXT NOT NULL,
    ext TEXT NOT NULL,
    size INTEGER NOT NULL,
    sha256 TEXT NOT NULL UNIQUE,
    crc32 INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    has_thumbnail INTEGER NOT NULL DEFAULT 0,
    width INTEGER,
    height INTEGER
);
CREATE INDEX IF NOT EXISTS media_created ON media(created_at);
CREATE INDEX IF NOT EXISTS media_participant ON media(participant_id);
CREATE TABLE IF NOT EXISTS favorites (
    participant_id TEXT NOT NULL,
    media_id TEXT NOT NULL REFERENCES media(id) ON DELETE CASCADE,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (participant_id, media_id)
);
CREATE TABLE IF NOT EXISTS activity (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,
    kind TEXT NOT NULL,
    participant_id TEXT,
    detail TEXT NOT NULL
);
"#;

impl Db {
    pub fn open(path: &Path) -> ApiResult<Self> {
        let conn = Connection::open(path)?;
        conn.busy_timeout(std::time::Duration::from_secs(5))?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self { conn: Arc::new(Mutex::new(conn)) })
    }

    /// Runs `f` with exclusive access to the connection on the blocking pool.
    pub async fn call<F, R>(&self, f: F) -> ApiResult<R>
    where
        F: FnOnce(&mut Connection) -> ApiResult<R> + Send + 'static,
        R: Send + 'static,
    {
        let conn = self.conn.clone();
        tokio::task::spawn_blocking(move || {
            let mut guard = conn.lock().unwrap_or_else(|e| e.into_inner());
            f(&mut guard)
        })
        .await
        .map_err(|e| ApiError::internal(format!("database task failed: {e}")))?
    }

    /// Synchronous access (start-up / tests only).
    pub fn with<R>(&self, f: impl FnOnce(&mut Connection) -> ApiResult<R>) -> ApiResult<R> {
        let mut guard = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        f(&mut guard)
    }
}

// ---------------------------------------------------------------- rows

#[derive(Debug, Clone, Serialize)]
pub struct SessionRow {
    pub id: String,
    pub name: String,
    pub host_name: String,
    #[serde(skip)]
    pub pin: String,
    pub created_at: i64,
    pub ended_at: Option<i64>,
    pub upload_permission: String,
    pub download_permission: String,
    pub require_approval: bool,
    pub keep_media: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct Participant {
    pub id: String,
    pub name: String,
    pub role: String,
    pub status: String,
    #[serde(skip)]
    pub device_id: Option<String>,
    pub avatar_color: i64,
    pub joined_at: i64,
    pub last_seen: i64,
}

impl Participant {
    pub fn is_host(&self) -> bool {
        self.role == "host"
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct UploadRow {
    pub id: String,
    pub participant_id: String,
    pub filename: String,
    pub ext: String,
    pub kind: String,
    pub size: u64,
    pub received: u64,
    pub expected_sha256: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct MediaRow {
    pub id: String,
    pub participant_id: String,
    pub filename: String,
    pub mime: String,
    pub kind: String,
    pub ext: String,
    pub size: u64,
    pub sha256: String,
    #[serde(skip)]
    pub crc32: u32,
    pub created_at: i64,
    pub has_thumbnail: bool,
    pub width: Option<i64>,
    pub height: Option<i64>,
}

fn session_from(r: &Row) -> rusqlite::Result<SessionRow> {
    Ok(SessionRow {
        id: r.get(0)?,
        name: r.get(1)?,
        host_name: r.get(2)?,
        pin: r.get(3)?,
        created_at: r.get(4)?,
        ended_at: r.get(5)?,
        upload_permission: r.get(6)?,
        download_permission: r.get(7)?,
        require_approval: r.get::<_, i64>(8)? != 0,
        keep_media: r.get::<_, i64>(9)? != 0,
    })
}
const SESSION_COLS: &str =
    "id, name, host_name, pin, created_at, ended_at, upload_permission, download_permission, require_approval, keep_media";

fn participant_from(r: &Row) -> rusqlite::Result<Participant> {
    Ok(Participant {
        id: r.get(0)?,
        name: r.get(1)?,
        role: r.get(2)?,
        status: r.get(3)?,
        device_id: r.get(4)?,
        avatar_color: r.get(5)?,
        joined_at: r.get(6)?,
        last_seen: r.get(7)?,
    })
}
const PARTICIPANT_COLS: &str = "id, name, role, status, device_id, avatar_color, joined_at, last_seen";

fn upload_from(r: &Row) -> rusqlite::Result<UploadRow> {
    Ok(UploadRow {
        id: r.get(0)?,
        participant_id: r.get(1)?,
        filename: r.get(2)?,
        ext: r.get(3)?,
        kind: r.get(4)?,
        size: r.get::<_, i64>(5)? as u64,
        received: r.get::<_, i64>(6)? as u64,
        expected_sha256: r.get(7)?,
        created_at: r.get(8)?,
        updated_at: r.get(9)?,
    })
}
const UPLOAD_COLS: &str = "id, participant_id, filename, ext, kind, size, received, expected_sha256, created_at, updated_at";

fn media_from(r: &Row) -> rusqlite::Result<MediaRow> {
    Ok(MediaRow {
        id: r.get(0)?,
        participant_id: r.get(1)?,
        filename: r.get(2)?,
        mime: r.get(3)?,
        kind: r.get(4)?,
        ext: r.get(5)?,
        size: r.get::<_, i64>(6)? as u64,
        sha256: r.get(7)?,
        crc32: r.get::<_, i64>(8)? as u32,
        created_at: r.get(9)?,
        has_thumbnail: r.get::<_, i64>(10)? != 0,
        width: r.get(11)?,
        height: r.get(12)?,
    })
}
pub const MEDIA_COLS: &str =
    "id, participant_id, filename, mime, kind, ext, size, sha256, crc32, created_at, has_thumbnail, width, height";

// ---------------------------------------------------------------- session

pub fn insert_session(c: &Connection, s: &SessionRow) -> ApiResult<()> {
    c.execute(
        &format!("INSERT INTO session ({SESSION_COLS}) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)"),
        params![
            s.id,
            s.name,
            s.host_name,
            s.pin,
            s.created_at,
            s.ended_at,
            s.upload_permission,
            s.download_permission,
            s.require_approval as i64,
            s.keep_media as i64
        ],
    )?;
    Ok(())
}

pub fn get_session(c: &Connection) -> ApiResult<SessionRow> {
    c.query_row(&format!("SELECT {SESSION_COLS} FROM session LIMIT 1"), [], session_from)
        .optional()?
        .ok_or_else(|| ApiError::internal("session row missing"))
}

pub fn update_session_settings(
    c: &Connection,
    name: Option<&str>,
    upload_permission: Option<&str>,
    download_permission: Option<&str>,
    require_approval: Option<bool>,
    keep_media: Option<bool>,
) -> ApiResult<()> {
    if let Some(v) = name {
        c.execute("UPDATE session SET name = ?1", [v])?;
    }
    if let Some(v) = upload_permission {
        c.execute("UPDATE session SET upload_permission = ?1", [v])?;
    }
    if let Some(v) = download_permission {
        c.execute("UPDATE session SET download_permission = ?1", [v])?;
    }
    if let Some(v) = require_approval {
        c.execute("UPDATE session SET require_approval = ?1", [v as i64])?;
    }
    if let Some(v) = keep_media {
        c.execute("UPDATE session SET keep_media = ?1", [v as i64])?;
    }
    Ok(())
}

pub fn end_session(c: &Connection, ts: i64) -> ApiResult<()> {
    c.execute("UPDATE session SET ended_at = ?1 WHERE ended_at IS NULL", [ts])?;
    Ok(())
}

// ---------------------------------------------------------------- participants

pub fn insert_participant(c: &Connection, p: &Participant, token_hash: &str) -> ApiResult<()> {
    c.execute(
        "INSERT INTO participants (id, name, role, status, token_hash, device_id, avatar_color, joined_at, last_seen)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
        params![p.id, p.name, p.role, p.status, token_hash, p.device_id, p.avatar_color, p.joined_at, p.last_seen],
    )?;
    Ok(())
}

pub fn participant_by_token_hash(c: &Connection, hash: &str) -> ApiResult<Option<Participant>> {
    Ok(c
        .query_row(&format!("SELECT {PARTICIPANT_COLS} FROM participants WHERE token_hash = ?1"), [hash], participant_from)
        .optional()?)
}

pub fn participant_by_id(c: &Connection, id: &str) -> ApiResult<Option<Participant>> {
    Ok(c.query_row(&format!("SELECT {PARTICIPANT_COLS} FROM participants WHERE id = ?1"), [id], participant_from).optional()?)
}

pub fn host_participant(c: &Connection) -> ApiResult<Participant> {
    c.query_row(&format!("SELECT {PARTICIPANT_COLS} FROM participants WHERE role = 'host' LIMIT 1"), [], participant_from)
        .optional()?
        .ok_or_else(|| ApiError::internal("host participant missing"))
}

pub fn list_participants(c: &Connection) -> ApiResult<Vec<Participant>> {
    let mut st = c.prepare(&format!(
        "SELECT {PARTICIPANT_COLS} FROM participants ORDER BY (role = 'host') DESC, joined_at ASC"
    ))?;
    let rows = st.query_map([], participant_from)?.collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

pub fn set_participant_status(c: &Connection, id: &str, status: &str) -> ApiResult<bool> {
    Ok(c.execute("UPDATE participants SET status = ?1 WHERE id = ?2 AND role != 'host'", params![status, id])? > 0)
}

pub fn set_participant_token(c: &Connection, id: &str, token_hash: &str) -> ApiResult<()> {
    c.execute("UPDATE participants SET token_hash = ?1 WHERE id = ?2", params![token_hash, id])?;
    Ok(())
}

pub fn touch_participant(c: &Connection, id: &str, ts: i64) -> ApiResult<()> {
    c.execute("UPDATE participants SET last_seen = ?1 WHERE id = ?2", params![ts, id])?;
    Ok(())
}

pub fn active_participant_by_device(c: &Connection, device_id: &str) -> ApiResult<Option<Participant>> {
    Ok(c
        .query_row(
            &format!(
                "SELECT {PARTICIPANT_COLS} FROM participants WHERE device_id = ?1 AND role != 'host'
                 AND status IN ('active', 'pending', 'left') ORDER BY joined_at DESC LIMIT 1"
            ),
            [device_id],
            participant_from,
        )
        .optional()?)
}

pub fn block_device(c: &Connection, device_id: &str, participant_id: &str, ts: i64) -> ApiResult<()> {
    c.execute(
        "INSERT OR REPLACE INTO blocked_devices (device_id, participant_id, created_at) VALUES (?1, ?2, ?3)",
        params![device_id, participant_id, ts],
    )?;
    Ok(())
}

pub fn is_device_blocked(c: &Connection, device_id: &str) -> ApiResult<bool> {
    Ok(c.query_row("SELECT 1 FROM blocked_devices WHERE device_id = ?1", [device_id], |_| Ok(())).optional()?.is_some())
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ParticipantStats {
    pub participant_id: String,
    pub photos: u64,
    pub videos: u64,
    pub bytes: u64,
}

pub fn participant_stats(c: &Connection) -> ApiResult<Vec<ParticipantStats>> {
    let mut st = c.prepare(
        "SELECT participant_id,
                SUM(CASE WHEN kind = 'photo' THEN 1 ELSE 0 END),
                SUM(CASE WHEN kind = 'video' THEN 1 ELSE 0 END),
                SUM(size)
         FROM media GROUP BY participant_id",
    )?;
    let rows = st
        .query_map([], |r| {
            Ok(ParticipantStats {
                participant_id: r.get(0)?,
                photos: r.get::<_, i64>(1)? as u64,
                videos: r.get::<_, i64>(2)? as u64,
                bytes: r.get::<_, i64>(3)? as u64,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

// ---------------------------------------------------------------- uploads

pub fn insert_upload(c: &Connection, u: &UploadRow) -> ApiResult<()> {
    c.execute(
        &format!("INSERT INTO uploads ({UPLOAD_COLS}) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)"),
        params![
            u.id,
            u.participant_id,
            u.filename,
            u.ext,
            u.kind,
            u.size as i64,
            u.received as i64,
            u.expected_sha256,
            u.created_at,
            u.updated_at
        ],
    )?;
    Ok(())
}

pub fn get_upload(c: &Connection, id: &str) -> ApiResult<Option<UploadRow>> {
    Ok(c.query_row(&format!("SELECT {UPLOAD_COLS} FROM uploads WHERE id = ?1"), [id], upload_from).optional()?)
}

pub fn find_resumable_upload(
    c: &Connection,
    participant_id: &str,
    filename: &str,
    size: u64,
    sha256: Option<&str>,
) -> ApiResult<Option<UploadRow>> {
    Ok(c
        .query_row(
            &format!(
                "SELECT {UPLOAD_COLS} FROM uploads WHERE participant_id = ?1 AND filename = ?2 AND size = ?3
                 AND expected_sha256 IS ?4 ORDER BY updated_at DESC LIMIT 1"
            ),
            params![participant_id, filename, size as i64, sha256],
            upload_from,
        )
        .optional()?)
}

pub fn list_uploads(c: &Connection, participant_id: Option<&str>) -> ApiResult<Vec<UploadRow>> {
    let mut st = c.prepare(&format!(
        "SELECT {UPLOAD_COLS} FROM uploads WHERE (?1 IS NULL OR participant_id = ?1) ORDER BY created_at ASC"
    ))?;
    let rows = st.query_map([participant_id], upload_from)?.collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

pub fn set_upload_received(c: &Connection, id: &str, received: u64, ts: i64) -> ApiResult<()> {
    c.execute("UPDATE uploads SET received = ?1, updated_at = ?2 WHERE id = ?3", params![received as i64, ts, id])?;
    Ok(())
}

pub fn delete_upload(c: &Connection, id: &str) -> ApiResult<()> {
    c.execute("DELETE FROM uploads WHERE id = ?1", [id])?;
    Ok(())
}

pub fn pending_upload_bytes(c: &Connection) -> ApiResult<u64> {
    let v: i64 = c.query_row("SELECT COALESCE(SUM(size - received), 0) FROM uploads", [], |r| r.get(0))?;
    Ok(v.max(0) as u64)
}

pub fn stale_uploads(c: &Connection, older_than: i64) -> ApiResult<Vec<UploadRow>> {
    let mut st = c.prepare(&format!("SELECT {UPLOAD_COLS} FROM uploads WHERE updated_at < ?1"))?;
    let rows = st.query_map([older_than], upload_from)?.collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

// ---------------------------------------------------------------- media

pub fn insert_media(c: &Connection, m: &MediaRow) -> rusqlite::Result<()> {
    c.execute(
        &format!("INSERT INTO media ({MEDIA_COLS}) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)"),
        params![
            m.id,
            m.participant_id,
            m.filename,
            m.mime,
            m.kind,
            m.ext,
            m.size as i64,
            m.sha256,
            m.crc32 as i64,
            m.created_at,
            m.has_thumbnail as i64,
            m.width,
            m.height
        ],
    )?;
    Ok(())
}

pub fn get_media(c: &Connection, id: &str) -> ApiResult<Option<MediaRow>> {
    Ok(c.query_row(&format!("SELECT {MEDIA_COLS} FROM media WHERE id = ?1"), [id], media_from).optional()?)
}

pub fn media_by_sha(c: &Connection, sha: &str) -> ApiResult<Option<MediaRow>> {
    Ok(c.query_row(&format!("SELECT {MEDIA_COLS} FROM media WHERE sha256 = ?1"), [sha], media_from).optional()?)
}

#[derive(Debug, Clone, Default)]
pub struct MediaQuery {
    pub kind: Option<String>,
    pub uploader: Option<String>,
    pub favorites_of: Option<String>,
    pub ascending: bool,
    pub offset: u64,
    pub limit: u64,
}

pub fn list_media(c: &Connection, q: &MediaQuery) -> ApiResult<(Vec<MediaRow>, u64)> {
    let filter = "WHERE (?1 IS NULL OR kind = ?1) AND (?2 IS NULL OR participant_id = ?2)
                  AND (?3 IS NULL OR id IN (SELECT media_id FROM favorites WHERE participant_id = ?3))";
    let order = if q.ascending { "ASC" } else { "DESC" };
    let total: i64 = c.query_row(
        &format!("SELECT COUNT(*) FROM media {filter}"),
        params![q.kind, q.uploader, q.favorites_of],
        |r| r.get(0),
    )?;
    let mut st = c.prepare(&format!(
        "SELECT {MEDIA_COLS} FROM media {filter} ORDER BY created_at {order}, id {order} LIMIT ?4 OFFSET ?5"
    ))?;
    let rows = st
        .query_map(params![q.kind, q.uploader, q.favorites_of, q.limit as i64, q.offset as i64], media_from)?
        .collect::<Result<Vec<_>, _>>()?;
    Ok((rows, total as u64))
}

pub fn media_by_ids(c: &Connection, ids: &[String]) -> ApiResult<Vec<MediaRow>> {
    let mut out = Vec::with_capacity(ids.len());
    let mut st = c.prepare(&format!("SELECT {MEDIA_COLS} FROM media WHERE id = ?1"))?;
    for id in ids {
        if let Some(m) = st.query_row([id], media_from).optional()? {
            out.push(m);
        }
    }
    Ok(out)
}

pub fn delete_media(c: &Connection, id: &str) -> ApiResult<bool> {
    Ok(c.execute("DELETE FROM media WHERE id = ?1", [id])? > 0)
}

pub fn set_media_thumbnail(c: &Connection, id: &str) -> ApiResult<()> {
    c.execute("UPDATE media SET has_thumbnail = 1 WHERE id = ?1", [id])?;
    Ok(())
}

pub fn set_media_dimensions(c: &Connection, id: &str, w: u32, h: u32) -> ApiResult<()> {
    c.execute("UPDATE media SET width = ?1, height = ?2 WHERE id = ?3", params![w as i64, h as i64, id])?;
    Ok(())
}

pub fn favorite_ids(c: &Connection, participant_id: &str, ids: &[String]) -> ApiResult<Vec<String>> {
    let mut st = c.prepare("SELECT 1 FROM favorites WHERE participant_id = ?1 AND media_id = ?2")?;
    let mut out = Vec::new();
    for id in ids {
        if st.query_row(params![participant_id, id], |_| Ok(())).optional()?.is_some() {
            out.push(id.clone());
        }
    }
    Ok(out)
}

pub fn set_favorite(c: &Connection, participant_id: &str, media_id: &str, fav: bool, ts: i64) -> ApiResult<()> {
    if fav {
        c.execute(
            "INSERT OR IGNORE INTO favorites (participant_id, media_id, created_at) VALUES (?1, ?2, ?3)",
            params![participant_id, media_id, ts],
        )?;
    } else {
        c.execute("DELETE FROM favorites WHERE participant_id = ?1 AND media_id = ?2", params![participant_id, media_id])?;
    }
    Ok(())
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct Totals {
    pub photos: u64,
    pub videos: u64,
    pub bytes: u64,
}

pub fn media_totals(c: &Connection) -> ApiResult<Totals> {
    Ok(c.query_row(
        "SELECT COALESCE(SUM(kind = 'photo'), 0), COALESCE(SUM(kind = 'video'), 0), COALESCE(SUM(size), 0) FROM media",
        [],
        |r| {
            Ok(Totals {
                photos: r.get::<_, i64>(0)? as u64,
                videos: r.get::<_, i64>(1)? as u64,
                bytes: r.get::<_, i64>(2)? as u64,
            })
        },
    )?)
}

// ---------------------------------------------------------------- activity

#[derive(Debug, Clone, Serialize)]
pub struct Activity {
    pub id: i64,
    pub ts: i64,
    pub kind: String,
    pub participant_id: Option<String>,
    pub detail: String,
}

pub fn log_activity(c: &Connection, kind: &str, participant_id: Option<&str>, detail: &str, ts: i64) -> ApiResult<()> {
    c.execute(
        "INSERT INTO activity (ts, kind, participant_id, detail) VALUES (?1, ?2, ?3, ?4)",
        params![ts, kind, participant_id, detail],
    )?;
    Ok(())
}

pub fn recent_activity(c: &Connection, limit: u64) -> ApiResult<Vec<Activity>> {
    let mut st = c.prepare("SELECT id, ts, kind, participant_id, detail FROM activity ORDER BY id DESC LIMIT ?1")?;
    let rows = st
        .query_map([limit as i64], |r| {
            Ok(Activity { id: r.get(0)?, ts: r.get(1)?, kind: r.get(2)?, participant_id: r.get(3)?, detail: r.get(4)? })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}
