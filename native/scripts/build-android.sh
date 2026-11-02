#!/usr/bin/env bash
# Builds liblocaldrop_engine.so for Android ABIs with cargo-ndk.
#   build-android.sh [debug|release] [output jniLibs dir]
# Requirements: rustup targets (aarch64-linux-android armv7-linux-androideabi
# x86_64-linux-android), `cargo install cargo-ndk`, and ANDROID_NDK_HOME.
set -euo pipefail
profile="${1:-release}"
here="$(cd "$(dirname "$0")" && pwd)"
crate="$here/../engine"
out="${2:-$here/../../packages/localdrop_engine/android/src/main/jniLibs}"

if ! command -v cargo >/dev/null || ! cargo ndk --version >/dev/null 2>&1; then
  if ls "$out"/*/liblocaldrop_engine.so >/dev/null 2>&1; then
    echo "warning: cargo-ndk not found; using existing prebuilt engine libraries in $out" >&2
    exit 0
  fi
  echo "error: the LocalDrop engine must be built with cargo-ndk." >&2
  echo "  rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android" >&2
  echo "  cargo install cargo-ndk" >&2
  exit 1
fi

args=(build --lib)
[ "$profile" = "release" ] && args+=(--release)
cd "$crate"
# API 24 matches the app's minSdk (getifaddrs is available from API 24).
cargo ndk --platform 24 -t arm64-v8a -t armeabi-v7a -t x86_64 -o "$out" "${args[@]}"
echo "Engine libraries written to $out"
