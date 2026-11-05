#!/usr/bin/env bash
# Installs the release APK on the emulator, launches it and fails if the app
# is not alive 25 s later. Saves logcat + a screenshot either way.
set -uo pipefail
pkg=app.localdrop.localdrop
mkdir -p smoke
adb install -r app-release.apk
adb logcat -c
adb shell am start -W -n "$pkg/.MainActivity"
sleep 25
adb logcat -d > smoke/logcat.txt
adb exec-out screencap -p > smoke/screen.png || true
grep -nE "FATAL EXCEPTION|Fatal signal|AndroidRuntime|E flutter|Abort message|backtrace|#[0-9]{2} pc" -A25 smoke/logcat.txt | head -300 > smoke/crash.txt || true
if ! adb shell pidof "$pkg" >/dev/null; then
  echo "::error::LocalDrop is not running 25 s after launch (crashed)"
  cat smoke/crash.txt
  exit 1
fi
if grep -qE "FATAL EXCEPTION|Fatal signal" smoke/logcat.txt; then
  echo "::error::Crash found in logcat"
  cat smoke/crash.txt
  exit 1
fi
echo "LocalDrop launched and is still running."
