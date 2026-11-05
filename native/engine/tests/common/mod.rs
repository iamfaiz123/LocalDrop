#![allow(dead_code)]
use localdrop_engine::{engine, EngineConfig, RunningEngine};
use reqwest::{Client, Response, StatusCode};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

pub struct TestServer {
    pub engine: Option<RunningEngine>,
    pub base: String,
    pub host_token: String,
    pub pin: String,
    pub session_id: String,
    pub dir: tempfile::TempDir,
    pub http: Client,
}

pub fn config(dir: &std::path::Path) -> EngineConfig {
    EngineConfig {
        data_dir: dir.to_path_buf(),
        session_name: "Manali Trip 2026".into(),
        host_name: "Aarav".into(),
        port: 0,
        bind_address: Some("127.0.0.1".into()),
        chunk_size: 64 * 1024,
        min_free_space: 1024 * 1024,
        ..Default::default()
    }
}

impl TestServer {
    pub async fn start() -> Self {
        Self::start_with(|_| {}).await
    }

    pub async fn start_with(f: impl FnOnce(&mut EngineConfig)) -> Self {
        let dir = tempfile::tempdir().unwrap();
        let mut cfg = config(dir.path());
        f(&mut cfg);
        let engine = engine::start(cfg).await.expect("engine start");
        let info = engine.info.clone();
        TestServer {
            base: info.local_url.clone(),
            host_token: info.host_token.clone(),
            pin: info.pin.clone(),
            session_id: info.session_id.clone(),
            engine: Some(engine),
            dir,
            http: Client::new(),
        }
    }

    pub fn url(&self, path: &str) -> String {
        format!("{}{}", self.base, path)
    }

    pub async fn get(&self, token: &str, path: &str) -> Response {
        self.http.get(self.url(path)).bearer_auth(token).send().await.unwrap()
    }

    pub async fn post(&self, token: &str, path: &str, body: Value) -> Response {
        self.http.post(self.url(path)).bearer_auth(token).json(&body).send().await.unwrap()
    }

    pub async fn join(&self, name: &str, device: &str) -> (String, Value) {
        let r = self
            .http
            .post(self.url("/api/session/join"))
            .json(&json!({ "name": name, "pin": self.pin, "device_id": device }))
            .send()
            .await
            .unwrap();
        assert_eq!(r.status(), StatusCode::OK, "join failed");
        let v: Value = r.json().await.unwrap();
        (v["token"].as_str().unwrap().to_string(), v)
    }

    /// Full chunked upload. Returns the `complete` response.
    pub async fn upload(&self, token: &str, filename: &str, data: &[u8], chunk: usize) -> (StatusCode, Value) {
        let r = self
            .post(token, "/api/media/upload", json!({ "filename": filename, "size": data.len() }))
            .await;
        let status = r.status();
        let v: Value = r.json().await.unwrap();
        if v["duplicate"] == true || !status.is_success() {
            return (status, v);
        }
        let id = v["upload_id"].as_str().unwrap().to_string();
        let mut off = v["received"].as_u64().unwrap() as usize;
        while off < data.len() {
            let end = (off + chunk).min(data.len());
            let r = self.put_chunk(token, &id, off, &data[off..end], true).await;
            assert_eq!(r.status(), StatusCode::OK, "chunk at {off}: {:?}", r.text().await);
            off = end;
        }
        let r = self.post(token, &format!("/api/uploads/{id}/complete"), json!({ "sha256": sha(data) })).await;
        let s = r.status();
        (s, r.json().await.unwrap())
    }

    pub async fn put_chunk(&self, token: &str, id: &str, offset: usize, bytes: &[u8], with_hash: bool) -> Response {
        let mut req = self
            .http
            .put(self.url(&format!("/api/uploads/{id}?offset={offset}")))
            .bearer_auth(token)
            .body(bytes.to_vec());
        if with_hash {
            req = req.header("x-chunk-sha256", sha(bytes));
        }
        req.send().await.unwrap()
    }

    pub async fn media(&self, token: &str, query: &str) -> Value {
        self.get(token, &format!("/api/media{query}")).await.json().await.unwrap()
    }
}

pub fn sha(data: &[u8]) -> String {
    hex::encode(Sha256::digest(data))
}

/// A real JPEG with pseudo-random content (so every seed is unique).
pub fn jpeg(seed: u32, w: u32, h: u32) -> Vec<u8> {
    let img = image::RgbImage::from_fn(w, h, |x, y| {
        let v = x.wrapping_mul(31).wrapping_add(y.wrapping_mul(17)).wrapping_add(seed.wrapping_mul(7919));
        image::Rgb([(v % 251) as u8, ((v / 7) % 253) as u8, ((v / 13) % 255) as u8])
    });
    let mut out = Vec::new();
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 90).encode_image(&img).unwrap();
    out
}

/// A synthetic MP4-like file (valid `ftyp` header + random payload).
pub fn mp4(seed: u8, len: usize) -> Vec<u8> {
    let mut v = vec![0, 0, 0, 0x18];
    v.extend_from_slice(b"ftypisom\0\0\x02\0isommp42");
    let mut x: u32 = 0x9E37_79B9 ^ seed as u32;
    while v.len() < len {
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        v.push((x & 0xFF) as u8);
    }
    v
}
