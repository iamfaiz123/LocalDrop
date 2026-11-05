//! Real-time events over WebSocket. Presence (online/offline) is derived
//! from open sockets; a heartbeat detects silently dropped clients.

use crate::auth::Auth;
use crate::db::{self, Participant};
use crate::state::SharedState;
use crate::util::now_ms;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::response::Response;
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::time::{Duration, Instant};
use tokio::sync::broadcast::error::RecvError;

pub async fn handler(State(st): State<SharedState>, a: Auth, ws: WebSocketUpgrade) -> Response {
    ws.on_upgrade(move |socket| run(st, a.0, socket))
}

fn presence_change(st: &SharedState, id: &str, delta: isize) -> bool {
    let mut map = st.presence.lock().unwrap_or_else(|e| e.into_inner());
    let n = map.entry(id.to_string()).or_insert(0);
    let before = *n;
    *n = (*n as isize + delta).max(0) as usize;
    let after = *n;
    if after == 0 {
        map.remove(id);
    }
    (before == 0) != (after == 0)
}

async fn run(st: SharedState, p: Participant, socket: WebSocket) {
    let mut events = st.events.subscribe();
    if presence_change(&st, &p.id, 1) {
        st.emit("participant_status", json!({ "id": p.id, "name": p.name, "online": true }));
    }
    let (mut tx, mut rx) = socket.split();
    let hello = json!({ "type": "hello", "ts": now_ms(), "data": { "participant_id": p.id, "session_id": st.session_id } });
    let _ = tx.send(Message::Text(hello.to_string().into())).await;

    let mut heartbeat = tokio::time::interval(Duration::from_secs(15));
    let mut last_seen = Instant::now();
    loop {
        tokio::select! {
            _ = st.shutdown.cancelled() => {
                let _ = tx.send(Message::Close(None)).await;
                break;
            }
            ev = events.recv() => match ev {
                Ok(ev) => {
                    if let Some(target) = &ev.only_for {
                        if target != &p.id && !p.is_host() {
                            continue;
                        }
                    }
                    let text = match serde_json::to_string(&ev) { Ok(t) => t, Err(_) => continue };
                    if tx.send(Message::Text(text.into())).await.is_err() {
                        break;
                    }
                    let kicked = ev.kind == "participant_removed" && ev.data["id"].as_str() == Some(p.id.as_str());
                    if kicked || ev.kind == "session_ended" {
                        let _ = tx.send(Message::Close(None)).await;
                        break;
                    }
                }
                Err(RecvError::Lagged(_)) => {
                    // Client fell behind: tell it to refetch state.
                    let msg = json!({ "type": "resync", "ts": now_ms(), "data": {} });
                    if tx.send(Message::Text(msg.to_string().into())).await.is_err() {
                        break;
                    }
                }
                Err(RecvError::Closed) => break,
            },
            msg = rx.next() => match msg {
                Some(Ok(Message::Close(_))) | None | Some(Err(_)) => break,
                Some(Ok(Message::Text(t))) => {
                    last_seen = Instant::now();
                    if t.as_str() == "ping" && tx.send(Message::Text("pong".into())).await.is_err() {
                        break;
                    }
                }
                Some(Ok(_)) => last_seen = Instant::now(),
            },
            _ = heartbeat.tick() => {
                if last_seen.elapsed() > Duration::from_secs(45) {
                    tracing::debug!("participant {} timed out", p.id);
                    break;
                }
                if tx.send(Message::Ping(Default::default())).await.is_err() {
                    break;
                }
            }
        }
    }
    if presence_change(&st, &p.id, -1) {
        st.emit("participant_status", json!({ "id": p.id, "name": p.name, "online": false }));
    }
    let id = p.id.clone();
    let now = now_ms();
    let _ = st.db.call(move |c| db::touch_participant(c, &id, now)).await;
}
