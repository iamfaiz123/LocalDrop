# LocalDrop

Offline, original-quality photo and video sharing over a local Wi-Fi network or phone hotspot.
No internet, cloud, accounts or compression. The app is ad-supported: ads load only when the device
happens to have internet and never affect sharing ([docs/ADS.md](docs/ADS.md)).

One person **hosts** a session on their phone. Friends join their hotspot, scan the QR code
(or type the address / PIN) and everyone can upload, browse and download originals. Participants
can use the LocalDrop app **or any mobile browser**: the host serves a bundled web client.

## Architecture

```
┌──────────── Host phone ──────────────────────────────┐        ┌─ Participant ─────────────┐
│ Flutter UI ──dart:ffi──▶ Rust engine (in-process)     │  LAN   │ LocalDrop app  or         │
│   (lib/)                  native/engine               │◀──────▶│ browser (bundled web UI)  │
│                           • Axum HTTP + WebSocket     │  HTTP  └───────────────────────────┘
│ Host UI uses the same     • SQLite per session        │  + WS
│ HTTP API on 127.0.0.1     • media/, thumbs/, tmp/     │
└──────────────────────────────────────────────────────┘
```

* **Rust engine** (`native/engine`): Tokio, Axum, Tower, Serde, rusqlite (SQLite), SHA-256.
  Sessions, PIN auth, participants, resumable chunked uploads, content sniffing, dedup,
  thumbnails, Range downloads, streaming seekable ZIP export, WebSocket events, rate limiting.
* **FFI**: a small C ABI (`ld_engine_start/stop/status`, `ld_network_interfaces`, …) called
  with `dart:ffi` on a background isolate. Only lifecycle crosses FFI; all data flows over the
  engine's HTTP API, so the host app and remote participants share one code path.
  (`flutter_rust_bridge` was evaluated; a 6-function JSON C ABI was simpler and needs no codegen.)
* **Flutter app** (`lib/`): `models/`, `services/` (API, realtime, engine, uploads, downloads),
  `providers/` (session + gallery state), `screens/`, `widgets/`, `platform/` (Kotlin/Swift bridge).
* **Engine packaging** (`packages/localdrop_engine`): FFI plugin that bundles `liblocaldrop_engine.so`
  (Android) / `LocalDropEngine.xcframework` (iOS).

## Docs
* [docs/API.md](docs/API.md) – HTTP/WebSocket API
* [docs/BUILD.md](docs/BUILD.md) – building, running and testing
* [docs/STATUS.md](docs/STATUS.md) – what is implemented, what is verified, known limitations
* [docs/SECURITY.md](docs/SECURITY.md) – security model and boundaries
* [docs/ADS.md](docs/ADS.md) – ad placements, consent and switching to real AdMob IDs

## Quick start (development)
```bash
cargo test --manifest-path native/engine/Cargo.toml        # engine tests
cargo build --manifest-path native/engine/Cargo.toml       # needed by Flutter integration tests
flutter test                                               # unit, widget and FFI integration tests
cargo run --manifest-path native/engine/Cargo.toml --bin localdrop-server -- --name "Trip" --host "Me"
```
The CLI host lets any laptop host a session; open the printed address on a phone.
