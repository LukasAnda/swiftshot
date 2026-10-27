#!/bin/bash
# Linux as a full host: the Linux release archive installed with Homebrew (as the docs say), then
# what a user runs there: devices, init, list and run on an Android and a Compose Multiplatform
# project (iOS skipped, with a note), and the messages for an iOS project and --platform ios.
#   Android/ci/linux-host.sh [out-dir]     (Linux with a JDK 21+, the Android SDK and Homebrew)
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
out=${1:-${RUNNER_TEMP:-/tmp}/swiftshot-linux-host}
rm -rf "$out" && mkdir -p "$out"
fail() { echo "FAIL: $*"; exit 1; }
v=0.0.0

make android dist-linux-archive VERSION=$v
linux=$(cut -d' ' -f1 dist/swiftshot-android.tar.gz.sha256)
if [ "$(uname -s)" = Linux ] && command -v brew >/dev/null; then
  # The release formula, pointed at this archive, in a local tap.
  brew tap-new --no-git swiftshot/local >/dev/null 2>&1 || true
  packaging/homebrew/render.sh $v "file://$root/dist" "$(printf '0%.0s' $(seq 64))" "$linux" \
    > "$(brew --repository swiftshot/local)/Formula/swiftshot.rb"
  HOMEBREW_NO_AUTO_UPDATE=1 brew install swiftshot/local/swiftshot
  ss=$(brew --prefix)/bin/swiftshot
else
  mkdir -p "$out/pkg" && tar -xzf dist/swiftshot-android.tar.gz -C "$out/pkg"
  ss=$out/pkg/swiftshot/bin/swiftshot
fi
echo "using $ss"
"$ss" --version | grep -q "swiftshot $v" || fail "version: $("$ss" --version)"
"$ss" devices | grep -q "Pixel 10 Pro" || fail "devices"

copy() { rm -rf "$out/$2" && mkdir -p "$out/$2" && (cd "Example/$1" && tar --exclude=./build --exclude=./.gradle --exclude=./local.properties --exclude='*/build' -cf - .) | tar -xf - -C "$out/$2"; rm -f "$out/$2/swiftshot.json"; }

# Android: init writes the config, list finds the previews, run renders them.
copy AndroidDemo android
(cd "$out/android" && "$ss" init >/dev/null && grep -q '":app"' swiftshot.json) || fail "init (Android)"
(cd "$out/android" && "$ss" list > list.txt) || fail "list (Android)"
grep -q "^  " "$out/android/list.txt" || fail "list found no previews"
(cd "$out/android" && "$ss" run --devices "Pixel 10 Pro" --languages en-US,ar --appearances light --watch-devices "Wear OS Large Round" --output shots 2>&1 | tee run.log) || fail "run (Android)"
n=$(find "$out/android/shots" -name '*.png' | wc -l); [ "$n" -gt 0 ] || fail "no Android screenshots"
grep -q '"errors": \[\]' "$out/android/shots/swiftshot-report.json" || fail "errors in the Android report"
echo "android ok: $n screenshots"

# Compose Multiplatform: Android and desktop rendered, iOS skipped with a note.
copy MultiplatformDemo kmp
(cd "$out/kmp" && "$ss" init >/dev/null && grep -q '"desktop_devices"' swiftshot.json) || fail "init (Compose Multiplatform)"
(cd "$out/kmp" && "$ss" run --languages en-US --output shots 2>&1 | tee run.log) || fail "run (Compose Multiplatform)"
ls "$out/kmp/shots/en-US" | grep -q "^Desktop" || fail "no desktop screenshots"
ls "$out/kmp/shots/en-US" | grep -q "^Pixel" || fail "no Android screenshots for the shared module"
if [ "$(uname -s)" = Linux ]; then
  grep -q "iOS targets need a Mac" "$out/kmp/run.log" || fail "no iOS note"
  if ls "$out/kmp/shots/en-US" | grep -q "^iP"; then fail "iOS screenshots on Linux"; fi
fi
(cd "$out/kmp" && "$ss" --platform android list >/dev/null) || fail "--platform android"
echo "multiplatform ok: $(ls "$out/kmp/shots/en-US" | grep -c png) screenshots"

# iOS: a clear message, not a stack of Gradle errors.
if (cd Example/DemoApp && "$ss" run > "$out/ios.log" 2>&1); then fail "an iOS project ran"; fi
grep -q "iOS project" "$out/ios.log" || fail "iOS project message: $(cat "$out/ios.log")"
if (cd "$out/kmp" && "$ss" --platform ios list > "$out/ios2.log" 2>&1); then fail "--platform ios ran"; fi
grep -q "Mac" "$out/ios2.log" || fail "--platform ios message"
echo "ios messages ok"
