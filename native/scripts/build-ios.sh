#!/usr/bin/env bash
# Builds LocalDropEngine.xcframework (dynamic) for iOS devices and simulators.
# Run on macOS with Xcode:
#   rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
#   native/scripts/build-ios.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
crate="$here/../engine"
out="$here/../../packages/localdrop_engine/ios/Frameworks"
name=LocalDropEngine
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export IPHONEOS_DEPLOYMENT_TARGET=15.0
for t in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  RUSTFLAGS="-C link-arg=-Wl,-install_name,@rpath/$name.framework/$name" \
    cargo build --manifest-path "$crate/Cargo.toml" --lib --release --target "$t"
done

make_framework() { # <dylib> <dest dir> <platform>
  local fw="$2/$name.framework"
  mkdir -p "$fw"
  cp "$1" "$fw/$name"
  install_name_tool -id "@rpath/$name.framework/$name" "$fw/$name"
  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>app.localdrop.engine</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>15.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$3</string></array>
</dict></plist>
PLIST
}

target="$crate/target"
make_framework "$target/aarch64-apple-ios/release/liblocaldrop_engine.dylib" "$work/device" iPhoneOS
lipo -create \
  "$target/aarch64-apple-ios-sim/release/liblocaldrop_engine.dylib" \
  "$target/x86_64-apple-ios/release/liblocaldrop_engine.dylib" \
  -output "$work/sim.dylib"
make_framework "$work/sim.dylib" "$work/sim" iPhoneSimulator

rm -rf "$out/$name.xcframework"
mkdir -p "$out"
xcodebuild -create-xcframework \
  -framework "$work/device/$name.framework" \
  -framework "$work/sim/$name.framework" \
  -output "$out/$name.xcframework"
echo "Built $out/$name.xcframework"
