//! End-to-end tests: a real engine on a TCP socket, driven over HTTP and WebSocket.

mod common;
use common::*;
use futures_util::StreamExt;
use reqwest::StatusCode;
use serde_json::{json, Value};
use std::io::Read;
use std::time::Duration;

#[tokio::test]
async fn session_creation_and_info() {
    let s = TestServer::start().await;
    assert_eq!(s.pin.len(), 6);
    assert_eq!(s.host_token.len(), 64);
    let h: Value = s.http.get(s.url("/api/health")).send().await.unwrap().json().await.unwrap();
    assert_eq!(h["ok"], true);
    assert_eq!(h["session_id"], s.session_id);

    // Public info never contains the PIN.
    let public: Value = s.http.get(s.url("/api/session/info")).send().await.unwrap().json().await.unwrap();
    assert_eq!(public["name"], "Manali Trip 2026");
    assert_eq!(public["host_name"], "Aarav");
    assert!(public.get("pin").is_none());
    assert_eq!(public["encrypted"], false);

    let host: Value = s.get(&s.host_token, "/api/session/info").await.json().await.unwrap();
    assert_eq!(host["pin"], s.pin);
    assert!(s.dir.path().join("sessions").join(&s.session_id).join("session.db").exists());
    assert!(s.dir.path().join("sessions").join(&s.session_id).join("media").is_dir());
}

#[tokio::test]
async fn authentication_and_pin_lockout() {
    let s = TestServer::start().await;
    // No token.
    assert_eq!(s.http.get(s.url("/api/media")).send().await.unwrap().status(), StatusCode::UNAUTHORIZED);
    // Garbage token.
    assert_eq!(s.get(&"a".repeat(64), "/api/media").await.status(), StatusCode::UNAUTHORIZED);

    let wrong = if s.pin == "000000" { "111111" } else { "000000" };
    for _ in 0..5 {
        let r = s.http.post(s.url("/api/session/join")).json(&json!({ "name": "Eve", "pin": wrong })).send().await.unwrap();
        assert_eq!(r.status(), StatusCode::UNAUTHORIZED);
    }
    // Locked out even with the correct PIN.
    let r = s.http.post(s.url("/api/session/join")).json(&json!({ "name": "Eve", "pin": s.pin })).send().await.unwrap();
    assert_eq!(r.status(), StatusCode::TOO_MANY_REQUESTS);
    assert!(r.headers().contains_key("retry-after"));
}

#[tokio::test]
async fn join_sets_cookie_and_cookie_authenticates() {
    let s = TestServer::start().await;
    let r = s
        .http
        .post(s.url("/api/session/join"))
        .json(&json!({ "name": "  Riya  ", "pin": s.pin, "device_id": "dev-riya" }))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::OK);
    let cookie = r.headers().get("set-cookie").unwrap().to_str().unwrap().to_string();
    assert!(cookie.contains("HttpOnly") && cookie.contains("SameSite=Strict"));
    let v: Value = r.json().await.unwrap();
    assert_eq!(v["participant"]["name"], "Riya");
    assert_eq!(v["status"], "active");
    assert!(v["session"].get("pin").is_none());
    let pair = cookie.split(';').next().unwrap().to_string();
    let r = s.http.get(s.url("/api/session/me")).header("cookie", pair).send().await.unwrap();
    assert_eq!(r.status(), StatusCode::OK);

    let list: Value = s.get(&s.host_token, "/api/session/participants").await.json().await.unwrap();
    assert_eq!(list["participants"].as_array().unwrap().len(), 2);
}

#[tokio::test]
async fn chunked_upload_gallery_thumbnail_and_download() {
    let s = TestServer::start().await;
    let (riya, _) = s.join("Riya", "dev-r").await;
    let data = jpeg(1, 640, 480);
    let (st, v) = s.upload(&riya, "IMG_4829.JPG", &data, 7_000).await;
    assert_eq!(st, StatusCode::CREATED, "{v}");
    assert_eq!(v["duplicate"], false);
    let m = &v["media"];
    assert_eq!(m["kind"], "photo");
    assert_eq!(m["mime"], "image/jpeg");
    assert_eq!(m["size"], data.len());
    assert_eq!(m["sha256"], sha(&data));
    assert_eq!(m["uploader"]["name"], "Riya");
    assert_eq!(v["needs_client_thumbnail"], false);
    let id = m["id"].as_str().unwrap().to_string();

    // Gallery lists it for everyone.
    let g = s.media(&s.host_token, "").await;
    assert_eq!(g["total"], 1);

    // Original bytes, byte-for-byte.
    let r = s.get(&riya, &format!("/api/media/{id}/file?download=1")).await;
    assert_eq!(r.status(), StatusCode::OK);
    assert!(r.headers()["content-disposition"].to_str().unwrap().starts_with("attachment"));
    assert_eq!(r.bytes().await.unwrap().as_ref(), data.as_slice());

    // Range (resume / video seek).
    let r = s
        .http
        .get(s.url(&format!("/api/media/{id}/file")))
        .bearer_auth(&riya)
        .header("range", "bytes=100-199")
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::PARTIAL_CONTENT);
    assert_eq!(r.headers()["content-range"].to_str().unwrap(), format!("bytes 100-199/{}", data.len()));
    assert_eq!(r.bytes().await.unwrap().as_ref(), &data[100..200]);
    let r = s
        .http
        .get(s.url(&format!("/api/media/{id}/file")))
        .bearer_auth(&riya)
        .header("range", format!("bytes={}-", data.len()))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::RANGE_NOT_SATISFIABLE);

    // Thumbnail is generated in the background and is a small JPEG.
    let mut thumb = None;
    for _ in 0..50 {
        let r = s.get(&riya, &format!("/api/media/{id}/thumbnail")).await;
        if r.status() == StatusCode::OK {
            thumb = Some(r.bytes().await.unwrap());
            break;
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    let thumb = thumb.expect("thumbnail generated");
    let img = image::load_from_memory(&thumb).unwrap();
    assert!(img.width() <= 480 && img.height() <= 480);
    let meta: Value = s.get(&riya, &format!("/api/media/{id}")).await.json().await.unwrap();
    assert_eq!(meta["width"], 640);
    assert_eq!(meta["height"], 480);
    assert_eq!(meta["has_thumbnail"], true);
}

#[tokio::test]
async fn partial_upload_is_hidden_and_resumable() {
    let s = TestServer::start().await;
    let (t, _) = s.join("Karan", "dev-k").await;
    let data = mp4(3, 300_000);
    let create = json!({ "filename": "VID_0193.MP4", "size": data.len(), "sha256": sha(&data) });
    let v: Value = s.post(&t, "/api/media/upload", create.clone()).await.json().await.unwrap();
    let id = v["upload_id"].as_str().unwrap().to_string();
    assert_eq!(v["received"], 0);

    assert_eq!(s.put_chunk(&t, &id, 0, &data[..100_000], true).await.status(), StatusCode::OK);
    // Not in the gallery while incomplete.
    assert_eq!(s.media(&t, "").await["total"], 0);
    // Completing early is refused.
    let r = s.post(&t, &format!("/api/uploads/{id}/complete"), json!({})).await;
    assert_eq!(r.status(), StatusCode::CONFLICT);

    // Wrong offset → 409 with the server's offset.
    let r = s.put_chunk(&t, &id, 50_000, &data[50_000..60_000], false).await;
    assert_eq!(r.status(), StatusCode::CONFLICT);
    let e: Value = r.json().await.unwrap();
    assert_eq!(e["error"]["received"], 100_000);

    // Corrupted chunk → rejected, offset unchanged.
    let mut bad = data[100_000..150_000].to_vec();
    let good_hash = sha(&bad);
    bad[10] ^= 0xFF;
    let r = s
        .http
        .put(s.url(&format!("/api/uploads/{id}?offset=100000")))
        .bearer_auth(&t)
        .header("x-chunk-sha256", good_hash)
        .body(bad)
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::UNPROCESSABLE_ENTITY);

    // Client restarts: re-declaring the same file resumes at the stored offset.
    let v: Value = s.post(&t, "/api/media/upload", create).await.json().await.unwrap();
    assert_eq!(v["upload_id"], id);
    assert_eq!(v["resumed"], true);
    assert_eq!(v["received"], 100_000);
    let st: Value = s.get(&t, &format!("/api/uploads/{id}")).await.json().await.unwrap();
    assert_eq!(st["received"], 100_000);

    assert_eq!(s.put_chunk(&t, &id, 100_000, &data[100_000..], true).await.status(), StatusCode::OK);
    let r = s.post(&t, &format!("/api/uploads/{id}/complete"), json!({})).await;
    assert_eq!(r.status(), StatusCode::CREATED);
    let v: Value = r.json().await.unwrap();
    assert_eq!(v["media"]["kind"], "video");
    assert_eq!(v["needs_client_thumbnail"], true);
    // Upload record is gone; the temp file was moved, not copied.
    assert_eq!(s.get(&t, &format!("/api/uploads/{id}")).await.status(), StatusCode::NOT_FOUND);
    let tmp = s.dir.path().join("sessions").join(&s.session_id).join("tmp");
    assert_eq!(std::fs::read_dir(tmp).unwrap().count(), 0);
}

#[tokio::test]
async fn integrity_failure_is_rejected() {
    let s = TestServer::start().await;
    let data = jpeg(9, 64, 64);
    let v: Value = s
        .post(&s.host_token, "/api/media/upload", json!({ "filename": "a.jpg", "size": data.len() }))
        .await
        .json()
        .await
        .unwrap();
    let id = v["upload_id"].as_str().unwrap();
    s.put_chunk(&s.host_token, id, 0, &data, false).await;
    let r = s.post(&s.host_token, &format!("/api/uploads/{id}/complete"), json!({ "sha256": "0".repeat(64) })).await;
    assert_eq!(r.status(), StatusCode::UNPROCESSABLE_ENTITY);
    let e: Value = r.json().await.unwrap();
    assert_eq!(e["error"]["code"], "integrity_failed");
    assert_eq!(s.media(&s.host_token, "").await["total"], 0);
}

#[tokio::test]
async fn duplicates_are_detected() {
    let s = TestServer::start().await;
    let (a, _) = s.join("A", "dev-a").await;
    let (b, _) = s.join("B", "dev-b").await;
    let data = jpeg(5, 100, 80);
    let (st, first) = s.upload(&a, "x.jpg", &data, 100_000).await;
    assert_eq!(st, StatusCode::CREATED);
    // Same content from someone else, without a pre-declared hash → detected at completion.
    let (st, dup) = s.upload(&b, "copy.jpg", &data, 100_000).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(dup["duplicate"], true);
    assert_eq!(dup["media"]["id"], first["media"]["id"]);
    // With a declared hash → detected before any bytes are sent.
    let r = s.post(&b, "/api/media/upload", json!({ "filename": "y.jpg", "size": data.len(), "sha256": sha(&data) })).await;
    let v: Value = r.json().await.unwrap();
    assert_eq!(v["duplicate"], true);
    assert_eq!(s.media(&a, "").await["total"], 1);
}

#[tokio::test]
async fn file_type_and_size_validation() {
    let s = TestServer::start().await;
    let t = s.host_token.clone();
    let r = s.post(&t, "/api/media/upload", json!({ "filename": "notes.txt", "size": 10 })).await;
    assert_eq!(r.status(), StatusCode::UNSUPPORTED_MEDIA_TYPE);
    let r = s.post(&t, "/api/media/upload", json!({ "filename": "../../x.jpg", "size": 0 })).await;
    assert_eq!(r.status(), StatusCode::BAD_REQUEST);
    let r = s.post(&t, "/api/media/upload", json!({ "filename": "big.mp4", "size": u64::MAX / 2 })).await;
    assert_eq!(r.status(), StatusCode::PAYLOAD_TOO_LARGE);
    // Disguised content: an HTML file named .jpg is rejected after sniffing.
    let html = b"<html><script>alert(1)</script></html>".repeat(10);
    let (st, v) = s.upload(&t, "../evil.jpg", &html, 1000).await;
    assert_eq!(st, StatusCode::UNSUPPORTED_MEDIA_TYPE, "{v}");
    assert_eq!(s.media(&t, "").await["total"], 0);
    // Client filename is sanitized and never used on disk.
    let data = jpeg(2, 32, 32);
    let (_, v) = s.upload(&t, "../../etc/IMG.jpg", &data, 100_000).await;
    assert_eq!(v["media"]["filename"], "IMG.jpg");
    let id = v["media"]["id"].as_str().unwrap();
    let on_disk = s.dir.path().join("sessions").join(&s.session_id).join("media").join(format!("{id}.jpg"));
    assert_eq!(std::fs::read(on_disk).unwrap(), data);
    // Mismatched extension is corrected to the real type.
    let (_, v) = s.upload(&t, "photo.png", &jpeg(3, 16, 16), 100_000).await;
    assert_eq!(v["media"]["filename"], "photo.jpg");
}

#[tokio::test]
async fn zip_export_with_range() {
    let s = TestServer::start().await;
    let (t, _) = s.join("Meera", "dev-m").await;
    let files = [jpeg(10, 50, 50), jpeg(11, 60, 40), mp4(12, 70_000)];
    let mut ids = vec![];
    for (i, f) in files.iter().enumerate() {
        let name = if i == 2 { "clip.mp4" } else { "same.jpg" };
        let (_, v) = s.upload(&t, name, f, 30_000).await;
        ids.push(v["media"]["id"].as_str().unwrap().to_string());
    }
    let v: Value = s.post(&t, "/api/media/download", json!({ "ids": ids })).await.json().await.unwrap();
    assert_eq!(v["count"], 3);
    let size = v["size"].as_u64().unwrap();
    let url = v["url"].as_str().unwrap().to_string();
    let r = s.get(&t, &url).await;
    assert_eq!(r.status(), StatusCode::OK);
    assert_eq!(r.headers()["content-length"].to_str().unwrap(), size.to_string());
    let body = r.bytes().await.unwrap();
    assert_eq!(body.len() as u64, size);

    let mut z = zip::ZipArchive::new(std::io::Cursor::new(body.to_vec())).unwrap();
    assert_eq!(z.len(), 3);
    let mut names = vec![];
    for i in 0..z.len() {
        let mut f = z.by_index(i).unwrap();
        names.push(f.name().to_string());
        let mut buf = vec![];
        f.read_to_end(&mut buf).unwrap(); // verifies CRC-32
        assert!(files.contains(&buf));
    }
    names.sort();
    assert_eq!(names, vec!["clip.mp4", "same (2).jpg", "same.jpg"]);

    // Resume a ZIP download from the middle.
    let r = s.http.get(s.url(&url)).bearer_auth(&t).header("range", "bytes=1000-").send().await.unwrap();
    assert_eq!(r.status(), StatusCode::PARTIAL_CONTENT);
    assert_eq!(r.bytes().await.unwrap().as_ref(), &body[1000..]);

    // Another participant cannot use someone else's export.
    let (other, _) = s.join("Other", "dev-o").await;
    assert_eq!(s.get(&other, &url).await.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn gallery_filters_pagination_and_favorites() {
    let s = TestServer::start().await;
    let (a, va) = s.join("A", "dev-a").await;
    let (b, _) = s.join("B", "dev-b").await;
    for i in 0..5 {
        s.upload(&a, &format!("a{i}.jpg"), &jpeg(100 + i, 20, 20), 100_000).await;
    }
    for i in 0..3 {
        s.upload(&b, &format!("b{i}.mp4"), &mp4(i as u8, 5000), 100_000).await;
    }
    let all = s.media(&a, "?limit=4").await;
    assert_eq!(all["total"], 8);
    assert_eq!(all["items"].as_array().unwrap().len(), 4);
    assert_eq!(all["next_offset"], 4);
    let last = s.media(&a, "?limit=4&offset=4").await;
    assert!(last["next_offset"].is_null());
    assert_eq!(s.media(&a, "?kind=video").await["total"], 3);
    assert_eq!(s.media(&a, "?kind=photo").await["total"], 5);
    let aid = va["participant"]["id"].as_str().unwrap();
    assert_eq!(s.media(&b, &format!("?uploader={aid}")).await["total"], 5);
    // Newest first by default, oldest first on request.
    let desc = s.media(&a, "").await;
    let asc = s.media(&a, "?order=asc").await;
    assert_eq!(desc["items"][0]["id"], asc["items"][7]["id"]);

    let id = desc["items"][0]["id"].as_str().unwrap();
    assert_eq!(s.post(&b, &format!("/api/media/{id}/favorite"), json!({})).await.status(), StatusCode::OK);
    let favs = s.media(&b, "?favorites=true").await;
    assert_eq!(favs["total"], 1);
    assert_eq!(favs["items"][0]["favorite"], true);
    assert_eq!(s.media(&a, "?favorites=true").await["total"], 0);
}

#[tokio::test]
async fn delete_permissions() {
    let s = TestServer::start().await;
    let (a, _) = s.join("A", "dev-a").await;
    let (b, _) = s.join("B", "dev-b").await;
    let (_, v) = s.upload(&a, "a.jpg", &jpeg(1, 10, 10), 100_000).await;
    let id = v["media"]["id"].as_str().unwrap().to_string();
    let r = s.http.delete(s.url(&format!("/api/media/{id}"))).bearer_auth(&b).send().await.unwrap();
    assert_eq!(r.status(), StatusCode::FORBIDDEN);
    let r = s.http.delete(s.url(&format!("/api/media/{id}"))).bearer_auth(&a).send().await.unwrap();
    assert_eq!(r.status(), StatusCode::OK);
    assert_eq!(s.media(&a, "").await["total"], 0);
    // Path traversal through ids is impossible: ids must be 32 hex chars.
    assert_eq!(s.get(&a, "/api/media/..%2F..%2Fsession.db/file").await.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn participant_removal_block_and_reconnect() {
    let s = TestServer::start().await;
    let (t1, v1) = s.join("Riya", "device-1").await;
    let pid = v1["participant"]["id"].as_str().unwrap().to_string();

    // Reconnecting from the same device keeps the identity and issues a new token.
    let (t2, v2) = s.join("Riya", "device-1").await;
    assert_eq!(v2["participant"]["id"], pid);
    assert_ne!(t1, t2);

    // Only the host can remove.
    let (other, _) = s.join("Karan", "device-2").await;
    assert_eq!(s.post(&other, &format!("/api/participants/{pid}/remove"), json!({})).await.status(), StatusCode::FORBIDDEN);

    assert_eq!(s.post(&s.host_token, &format!("/api/participants/{pid}/block"), json!({})).await.status(), StatusCode::OK);
    assert_eq!(s.get(&t2, "/api/media").await.status(), StatusCode::UNAUTHORIZED);
    let r = s
        .http
        .post(s.url("/api/session/join"))
        .json(&json!({ "name": "Riya again", "pin": s.pin, "device_id": "device-1" }))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::FORBIDDEN);
    let list: Value = s.get(&s.host_token, "/api/session/participants").await.json().await.unwrap();
    let riya = list["participants"].as_array().unwrap().iter().find(|p| p["id"] == pid.as_str()).unwrap().clone();
    assert_eq!(riya["status"], "blocked");
    // Participants don't see blocked people.
    let list: Value = s.get(&other, "/api/session/participants").await.json().await.unwrap();
    assert!(list["participants"].as_array().unwrap().iter().all(|p| p["id"] != pid.as_str()));
}

#[tokio::test]
async fn host_approval_flow_and_permissions() {
    let s = TestServer::start().await;
    let r = s
        .http
        .patch(s.url("/api/session/settings"))
        .bearer_auth(&s.host_token)
        .json(&json!({ "require_approval": true, "upload_permission": "host_only", "name": "Goa" }))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::OK);

    let (t, v) = s.join("Meera", "dev-m").await;
    assert_eq!(v["status"], "pending");
    let pid = v["participant"]["id"].as_str().unwrap().to_string();
    let r = s.get(&t, "/api/media").await;
    assert_eq!(r.status(), StatusCode::FORBIDDEN);
    let me: Value = s.get(&t, "/api/session/me").await.json().await.unwrap();
    assert_eq!(me["participant"]["status"], "pending");

    assert_eq!(s.post(&s.host_token, &format!("/api/participants/{pid}/approve"), json!({})).await.status(), StatusCode::OK);
    assert_eq!(s.get(&t, "/api/media").await.status(), StatusCode::OK);
    let info: Value = s.get(&t, "/api/session/info").await.json().await.unwrap();
    assert_eq!(info["name"], "Goa");

    // Uploads are host-only now.
    let r = s.post(&t, "/api/media/upload", json!({ "filename": "a.jpg", "size": 10 })).await;
    assert_eq!(r.status(), StatusCode::FORBIDDEN);
    let r = s.post(&s.host_token, "/api/media/upload", json!({ "filename": "a.jpg", "size": 10 })).await;
    assert_eq!(r.status(), StatusCode::CREATED);
    // Settings are host-only.
    let r = s.http.patch(s.url("/api/session/settings")).bearer_auth(&t).json(&json!({ "name": "X" })).send().await.unwrap();
    assert_eq!(r.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn websocket_events_and_presence() {
    let s = TestServer::start().await;
    let (t, v) = s.join("Riya", "dev-r").await;
    let pid = v["participant"]["id"].as_str().unwrap().to_string();
    let ws_url = format!("{}/api/ws?token={}", s.base.replace("http://", "ws://"), s.host_token);
    let (mut ws, _) = tokio_tungstenite::connect_async(ws_url).await.unwrap();

    let p_url = format!("{}/api/ws?token={}", s.base.replace("http://", "ws://"), t);
    let (p_ws, _) = tokio_tungstenite::connect_async(p_url).await.unwrap();

    let data = jpeg(77, 30, 30);
    s.upload(&t, "live.jpg", &data, 100_000).await;

    let mut seen = std::collections::HashSet::new();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    while tokio::time::Instant::now() < deadline && !(seen.contains("media_uploaded") && seen.contains("participant_status")) {
        let Ok(Some(Ok(msg))) = tokio::time::timeout(Duration::from_secs(5), ws.next()).await else { break };
        if let tokio_tungstenite::tungstenite::Message::Text(txt) = msg {
            let ev: Value = serde_json::from_str(&txt).unwrap();
            seen.insert(ev["type"].as_str().unwrap().to_string());
        }
    }
    for e in ["hello", "participant_status", "upload_started", "upload_completed", "media_uploaded"] {
        assert!(seen.contains(e), "missing event {e}; got {seen:?}");
    }
    let list: Value = s.get(&s.host_token, "/api/session/participants").await.json().await.unwrap();
    let me = list["participants"].as_array().unwrap().iter().find(|p| p["id"] == pid.as_str()).unwrap().clone();
    assert_eq!(me["online"], true);
    assert_eq!(me["photos"], 1);

    // Disconnect → offline.
    drop(p_ws);
    let mut offline = false;
    let deadline = tokio::time::Instant::now() + Duration::from_secs(5);
    while tokio::time::Instant::now() < deadline {
        let Ok(Some(Ok(msg))) = tokio::time::timeout(Duration::from_secs(5), ws.next()).await else { break };
        if let tokio_tungstenite::tungstenite::Message::Text(txt) = msg {
            let ev: Value = serde_json::from_str(&txt).unwrap();
            if ev["type"] == "participant_status" && ev["data"]["online"] == false {
                offline = true;
                break;
            }
        }
    }
    assert!(offline, "participant went offline");
}

#[tokio::test]
async fn ending_session_notifies_and_keeps_media() {
    let mut s = TestServer::start().await;
    let (t, _) = s.join("Riya", "dev-r").await;
    let data = jpeg(4, 20, 20);
    s.upload(&t, "keep.jpg", &data, 100_000).await;
    // An unfinished upload's temp data is cleaned up.
    s.post(&t, "/api/media/upload", json!({ "filename": "half.mp4", "size": 1000 })).await;

    let ws_url = format!("{}/api/ws?token={}", s.base.replace("http://", "ws://"), t);
    let (mut ws, _) = tokio_tungstenite::connect_async(ws_url).await.unwrap();

    // Participants cannot end the session.
    assert_eq!(s.post(&t, "/api/session/end", json!({})).await.status(), StatusCode::FORBIDDEN);
    let r = s.post(&s.host_token, "/api/session/end", json!({ "delete_media": false })).await;
    assert_eq!(r.status(), StatusCode::OK);
    let v: Value = r.json().await.unwrap();
    assert_eq!(v["cancelled_uploads"], 1);

    let mut ended = false;
    while let Ok(Some(Ok(msg))) = tokio::time::timeout(Duration::from_secs(3), ws.next()).await {
        if let tokio_tungstenite::tungstenite::Message::Text(txt) = msg {
            if txt.contains("\"session_ended\"") {
                ended = true;
                break;
            }
        }
    }
    assert!(ended);
    let engine = s.engine.take().unwrap();
    tokio::time::timeout(Duration::from_secs(5), engine.stop()).await.unwrap();

    let root = s.dir.path().join("sessions").join(&s.session_id);
    assert_eq!(std::fs::read_dir(root.join("media")).unwrap().count(), 1);
    assert!(!root.join("tmp").exists());
    let sessions = localdrop_engine::engine::list_sessions(s.dir.path());
    assert_eq!(sessions.len(), 1);
    assert!(sessions[0].ended_at.is_some());
    assert_eq!(sessions[0].photos, 1);
}

#[tokio::test]
async fn resume_after_host_restart() {
    let dir = tempfile::tempdir().unwrap();
    let cfg = config(dir.path());
    let engine = localdrop_engine::engine::start(cfg.clone()).await.unwrap();
    let base = engine.info.local_url.clone();
    let sid = engine.info.session_id.clone();
    let old_host = engine.info.host_token.clone();
    let pin = engine.info.pin.clone();
    let http = reqwest::Client::new();
    let v: Value = http
        .post(format!("{base}/api/session/join"))
        .json(&json!({ "name": "Riya", "pin": pin, "device_id": "d1" }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let t = v["token"].as_str().unwrap().to_string();
    let data = mp4(8, 200_000);
    let v: Value = http
        .post(format!("{base}/api/media/upload"))
        .bearer_auth(&t)
        .json(&json!({ "filename": "v.mp4", "size": data.len() }))
        .send()
        .await
        .unwrap()
        .json()
        .await
        .unwrap();
    let uid = v["upload_id"].as_str().unwrap().to_string();
    http.put(format!("{base}/api/uploads/{uid}?offset=0")).bearer_auth(&t).body(data[..120_000].to_vec()).send().await.unwrap();
    // An open WebSocket writes "last seen" while closing; stop() must wait for it.
    let ws_url = format!("{}/api/ws?token={}", base.replace("http://", "ws://"), t);
    let (_ws, _) = tokio_tungstenite::connect_async(ws_url).await.unwrap();
    tokio::time::sleep(Duration::from_millis(100)).await;
    engine.stop().await;
    // Simulate a crash that left unacknowledged bytes in the temp file.
    let part = dir.path().join("sessions").join(&sid).join("tmp").join(format!("{uid}.part"));
    let mut f = std::fs::OpenOptions::new().append(true).open(&part).unwrap();
    std::io::Write::write_all(&mut f, b"garbage").unwrap();
    drop(f);

    let engine = localdrop_engine::engine::start(EngineConfig2::resume(cfg, &sid)).await.unwrap();
    assert!(engine.info.resumed);
    assert_eq!(engine.info.pin, pin);
    let base = engine.info.local_url.clone();
    // Old host token is rotated; participant tokens survive.
    let r = http.get(format!("{base}/api/session/stats")).bearer_auth(&old_host).send().await.unwrap();
    assert_eq!(r.status(), StatusCode::UNAUTHORIZED);
    let st: Value = http.get(format!("{base}/api/uploads/{uid}")).bearer_auth(&t).send().await.unwrap().json().await.unwrap();
    assert_eq!(st["received"], 120_000);
    let r = http.put(format!("{base}/api/uploads/{uid}?offset=120000")).bearer_auth(&t).body(data[120_000..].to_vec()).send().await.unwrap();
    assert_eq!(r.status(), StatusCode::OK);
    let r = http
        .post(format!("{base}/api/uploads/{uid}/complete"))
        .bearer_auth(&t)
        .json(&json!({ "sha256": sha(&data) }))
        .send()
        .await
        .unwrap();
    assert_eq!(r.status(), StatusCode::CREATED);
    engine.stop().await;
}

struct EngineConfig2;
impl EngineConfig2 {
    fn resume(mut cfg: localdrop_engine::EngineConfig, id: &str) -> localdrop_engine::EngineConfig {
        cfg.resume_session_id = Some(id.to_string());
        cfg
    }
}

#[tokio::test]
async fn large_streamed_upload_and_concurrency() {
    let s = TestServer::start_with(|c| {
        c.chunk_size = 4 * 1024 * 1024;
        c.max_concurrent_uploads = 2;
    })
    .await;
    let (t, _) = s.join("Big", "dev-big").await;
    // 24 MiB in 4 MiB chunks, 3 files uploading concurrently.
    let files: Vec<Vec<u8>> = (0..3).map(|i| mp4(50 + i, 24 * 1024 * 1024)).collect();
    let futs = files.iter().enumerate().map(|(i, f)| {
        let s = &s;
        let t = t.clone();
        async move { s.upload(&t, &format!("big{i}.mp4"), f, 4 * 1024 * 1024).await }
    });
    let results = futures_util::future::join_all(futs).await;
    for (st, v) in results {
        assert_eq!(st, StatusCode::CREATED, "{v}");
    }
    let g = s.media(&t, "").await;
    assert_eq!(g["total"], 3);
    let stats: Value = s.get(&s.host_token, "/api/session/stats").await.json().await.unwrap();
    assert_eq!(stats["videos"], 3);
    assert_eq!(stats["media_bytes"], 3 * 24 * 1024 * 1024);
    let storage: Value = s.get(&t, "/api/storage/info").await.json().await.unwrap();
    assert!(storage["free_bytes"].as_u64().unwrap() > 0);
}

#[tokio::test]
async fn client_thumbnail_for_video() {
    let s = TestServer::start().await;
    let (t, _) = s.join("V", "dev-v").await;
    let (other, _) = s.join("W", "dev-w").await;
    let (_, v) = s.upload(&t, "clip.mov", &mp4(1, 4000), 100_000).await;
    let id = v["media"]["id"].as_str().unwrap().to_string();
    assert_eq!(s.get(&t, &format!("/api/media/{id}/thumbnail")).await.status(), StatusCode::NOT_FOUND);
    let thumb = jpeg(1, 800, 600);
    let put = |tok: &str, body: Vec<u8>| s.http.put(s.url(&format!("/api/media/{id}/thumbnail"))).bearer_auth(tok.to_string()).body(body).send();
    assert_eq!(put(&other, thumb.clone()).await.unwrap().status(), StatusCode::FORBIDDEN);
    assert_eq!(put(&t, b"not an image".to_vec()).await.unwrap().status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(put(&t, thumb).await.unwrap().status(), StatusCode::OK);
    let r = s.get(&other, &format!("/api/media/{id}/thumbnail")).await;
    assert_eq!(r.status(), StatusCode::OK);
    let img = image::load_from_memory(&r.bytes().await.unwrap()).unwrap();
    assert_eq!((img.width(), img.height()), (480, 360));
}

#[tokio::test]
async fn web_client_is_served_with_csp() {
    let s = TestServer::start().await;
    let r = s.http.get(s.url("/")).send().await.unwrap();
    assert_eq!(r.status(), StatusCode::OK);
    assert!(r.headers()["content-security-policy"].to_str().unwrap().contains("default-src 'none'"));
    assert!(r.text().await.unwrap().contains("app.js"));
    assert_eq!(s.http.get(s.url("/app.js")).send().await.unwrap().status(), StatusCode::OK);
    assert_eq!(s.http.get(s.url("/nope")).send().await.unwrap().status(), StatusCode::NOT_FOUND);
}
