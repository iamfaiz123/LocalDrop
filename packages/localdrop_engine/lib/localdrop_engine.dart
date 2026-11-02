/// Binary-only plugin: bundles the native LocalDrop engine.
///
/// The Dart bindings live in the app (`lib/services/engine_service.dart`).
/// Library names per platform:
/// * Android: `liblocaldrop_engine.so` (jniLibs, built with cargo-ndk)
/// * iOS: `LocalDropEngine.framework/LocalDropEngine` (dynamic xcframework)
library;

const androidLibrary = 'liblocaldrop_engine.so';
const iosLibrary = 'LocalDropEngine.framework/LocalDropEngine';
