# Implementation status

## Verified in this repository (automated)
| Area | How it was verified |
|---|---|
| Rust engine: sessions, PIN auth + lockout, cookie/bearer auth, approval, remove/block/reconnect, permissions | `native/engine/tests/api.rs` (real server over TCP) |
| Chunked resumable uploads, offset mismatch, chunk + file SHA-256, hidden partial uploads, dedup, type/size validation, path-safe storage | same |
| Thumbnails (server + client-supplied), Range downloads, ZIP export (+ Range resume, verified by `zip` crate), favorites, pagination, filters | same |
| WebSocket events + presence, session end, restart with resume (token rotation, crash-left bytes truncated), 3×24 MiB concurrent uploads | same |
| Browser client (Chromium/Playwright): join, wrong PIN, multi-upload, live updates across 2 participants, client video thumbnail, duplicate, video playback via Range, viewer, favorites, multi-select ZIP (byte-identical), delete propagation | `native/engine/tests/browser/run.sh` |
| Flutter services against the real engine via `dart:ffi` (Linux): lifecycle, join, uploads, pause/resume, recovery after "app kill", verified downloads, ZIP, host+participant `SessionController` incl. approval and session end | `test/integration/engine_ffi_test.dart` |
| Flutter UI states: create/join validation, network warning, start failure, gallery/empty/error/disabled, navigation, host controls, upload/download states, viewer, ended | `test/widgets/screens_test.dart` |

## Implemented but NOT yet verified
* **Android and iOS builds were not compiled here** (no Android SDK/NDK or macOS available in the
  build environment). Kotlin (foreground service, Wi-Fi/wake locks, thumbnails), Swift (thumbnails,
  background task), Gradle/cargo-ndk integration, the iOS xcframework script and podspec need a first
  build on real toolchains.
* **No physical-device testing has been done.** Per the project rules, no platform is claimed as
  supported yet. Required matrix: Android host + Android/iPhone clients, iPhone host + Android/iPhone
  clients, backgrounding, app termination, reconnection, large 4K videos.
* `image_picker` is assumed to return original bytes when no resize/quality options are passed;
  confirm byte-identity (SHA-256) on devices, especially iOS HEIC and Android videos.

## Known limitations
* **iOS hosting**: iOS suspends apps in the background; the server only runs while LocalDrop is in the
  foreground (plus a short background grace period). iOS hosting must be validated before it is offered.
  Android hosting uses a foreground service.
* Some hotspots isolate clients from each other. Hosting from the phone that provides the hotspot
  avoids this; the app shows a diagnostic when the host cannot be reached.
* Android `image_picker` copies picked files to the cache before upload (temporary extra space);
  copies are deleted after a successful upload.
* Transport is unencrypted (see SECURITY.md).
* Browser participants save downloads through the browser; saving videos to the iOS Photos app from
  Safari requires the share sheet.
