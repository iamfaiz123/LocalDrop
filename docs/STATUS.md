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

## Drop to pool
* Swipe deck over the phone's own library (`photo_manager`): right = queue the original for upload,
  left = skip; undo; decisions remembered per session; Select mode for many at once; "In pool" marks.
* Originals are read untouched (`originFile`; Android requests ACCESS_MEDIA_LOCATION so GPS EXIF is not
  stripped). iCloud-only items that are not on the phone are reported instead of uploaded.
* Verified by unit + widget tests (drag gestures, buttons, undo, select, permission denied).
  Not yet exercised against a real photo library on a device.

## Trip planner
* Itinerary by day/time with place and notes; majority vote confirms/drops items; per-activity
  "I'm in"; organiser sets destination and dates; invitees can preview the plan before joining.
  Same signed ledger and `.ldtrip` sharing as expenses.
* Verified by unit tests (majority rules, vote changes, RSVP, withdrawal, organiser-only details,
  invalid dates, WhatsApp itinerary text) and widget tests (preview → join → vote → I'm in,
  add item on a trip day and share).

## Trip expenses
* Signed (Ed25519), content-addressed ledger; expenses count only when the payer and everyone in
  the split approve; removals and repayments need approval too; deterministic balances and
  fewest-payments settle-up. Sync via `.ldtrip` file / `LD1:` code shared through WhatsApp.
* Verified by unit tests simulating 4 phones (gossip convergence, tampering, forged approvals,
  out-of-order arrival) and widget tests (create, invite → join, approve, add expense).
* Opening `.ldtrip` from WhatsApp (Android intent filters, iOS document type) compiles in CI but is
  not yet exercised on devices. See docs/EXPENSES.md for limits.

## Build status
* `.github/workflows/build.yml` builds a release APK (Rust engine for arm64/armv7/x86_64 + Kotlin) on
  Linux and the iOS app (`--no-codesign`, Rust xcframework + Swift) on macOS, and runs all tests.

## Ads
* **Off by default** (later phase). AdMob banners/interstitial and UMP consent are wired with Google **test IDs**; real IDs must be supplied
  (docs/ADS.md). Verified by tests: no layout space and no SDK calls when ads are unavailable, interstitial
  only at the session-end break. Real ad loading has not been seen on a device (no Android/iOS build here).

## Session lifetime (one session per device)
* A device belongs to at most one session. While it does, Home shows that session instead of
  Create/Join, and `SessionController` refuses to create or join another (`already_in_session`).
* **Host:** the session runs until the host taps *End Session*. Closing or swiping away the app does not
  stop it: the Rust server runs in the app process, kept alive by an Android foreground service
  (`connectedDevice` type, no time limit, Wi-Fi + wake locks). Reopening the app re-attaches to the
  running server. If Android kills the process, the service (START_STICKY) restarts the server natively
  via JNI with the same session, PIN and media; if that is not possible the app restarts it automatically
  on next launch. If even that fails, Home shows the session with *Reconnect* / *End session*.
* **Participant:** stays a member until *Leave*. Reopening reconnects automatically; if the host is
  unreachable Home shows *Reconnect* / *Leave session*. Unfinished uploads resume after reconnecting.
* Verified by FFI integration tests (reopen, simulated process kill, lock, leave/end unlock). The Android
  service/JNI restart path is unverified until the app is built and run on a device. Some vendors
  (Xiaomi, Huawei, Samsung "sleeping apps") kill background apps aggressively; users may need to exempt
  LocalDrop from battery optimisation.
* **iOS cannot keep a server running after the app is closed.** On iPhone the session is kept and
  restarted automatically when the app is opened again, but participants cannot reach the host while it
  is closed.

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
