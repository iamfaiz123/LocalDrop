# Building and testing

## Prerequisites
* Flutter 3.47+ (Dart 3.x), Rust stable (1.80+)
* Android: Android SDK + NDK, `cargo install cargo-ndk`,
  `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`
* iOS (macOS only): Xcode 26+ (current plugins need the Swift 6.2 toolchain), `rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios`

## Android
```bash
flutter build apk --release
```
Gradle runs `native/scripts/build-android.sh` (cargo-ndk) before `preBuild` and packages the
`.so` files from `packages/localdrop_engine/android/src/main/jniLibs`. Pass
`-Plocaldrop.skipRustBuild` to use prebuilt libraries. Release signing: create
`android/key.properties` with `storeFile, storePassword, keyAlias, keyPassword`.

## iOS
```bash
native/scripts/build-ios.sh          # builds LocalDropEngine.xcframework (dynamic)
flutter build ios --release
```
The `localdrop_engine` pod vendors the xcframework; Dart opens `LocalDropEngine.framework/LocalDropEngine`.

## Tests
```bash
cargo test --manifest-path native/engine/Cargo.toml   # 17 unit + 19 end-to-end HTTP/WS tests
cargo build --manifest-path native/engine/Cargo.toml  # Linux .so for the Flutter FFI tests
flutter test                                          # unit, widget, real-engine FFI integration
NODE_PATH=$(npm root -g) native/engine/tests/browser/run.sh   # Playwright E2E of the browser client
```
`test/integration/engine_ffi_test.dart` loads the real engine via `dart:ffi` and runs
host + participant `SessionController`s, uploads (pause/resume/restart recovery), downloads,
ZIP export and realtime events. It is skipped if the library has not been built.

## Configuration
`EngineConfig` (Rust / `lib/services/engine_service.dart`): port, PIN length (4–6), chunk size,
max chunk size, max file size, reserved free space, upload concurrency, thumbnail concurrency,
approval, keep-media-on-end, stale-upload expiry. Client upload/download parallelism:
`UploadManager.maxParallel`, `DownloadManager.maxParallel` (default 2).
