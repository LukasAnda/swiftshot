#!/bin/bash
# The Flutter check (CI on Linux, or a Mac): renders the @Previews of Example/FlutterDemo on an
# iPhone and a Pixel in five languages (one right to left, one CJK) and both appearances, then
# checks the count, sizes, that a second run is byte-for-byte identical and the report.
#   Android/ci/flutter.sh [out-dir]       (a JDK 21+ and a Flutter SDK: FLUTTER_ROOT or flutter on the PATH;
#                                          on a Mac with Xcode, after make, iOS renders on Flutter's iOS engine)
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${1:-${RUNNER_TEMP:-/tmp}/swiftshot-flutter}
rm -rf "$out" && mkdir -p "$out"
fail=0
( cd Android && ./gradlew --no-daemon -q :cli:jar :worker:jar :desktop-worker:jar )
cp Android/swiftshot-android Android/cli/build/libs/
run() {
  (cd Example/FlutterDemo && ../../Android/cli/build/libs/swiftshot-android run \
    --devices "iPhone 17 Pro Max,Pixel 10 Pro" --languages "en-US,de,ar,ja,sk" --appearances light,dark \
    --output "$1" 2>&1) | tee "$1.log"
}
t0=$(date +%s); run "$out/a"; t1=$(date +%s); run "$out/b"; t2=$(date +%s)
# 11 screen and component previews × 2 appearances, the light/dark pair, the pinned Arabic one:
# 204 for 2 devices and 5 languages.
expected=204
count=$(find "$out/a" -name '*.png' | wc -l | tr -d ' ')
echo "screenshots: $count"
grep -q '"errors": \[\]' "$out/a/swiftshot-report.json" || { echo "FAIL: errors in the report"; grep -A10 '"errors"' "$out/a/swiftshot-report.json"; fail=1; }
if diff -rq "$out/a" "$out/b" | grep -v 'screenshots.html\|swiftshot-report.json'; then echo "FAIL: the second run differs"; fail=1; else echo "deterministic: yes"; fi
size() { python3 -c "import struct,sys; d=open(sys.argv[1],'rb').read(24); print('%dx%d' % struct.unpack('>II', d[16:24]))" "$1"; }
check() { local s; s=$(size "$out/a/$1"); [ "$s" = "$2" ] && echo "size ok: $1 $s" || { echo "FAIL: $1 is $s, not $2"; fail=1; }; }
check "en-US/iPhone 17 Pro Max-Root-light.png" 1320x2868
check "ar/Pixel 10 Pro-Stats-dark.png" 1280x2856
check "ja/iPhone 17 Pro Max-Habit card-light.png" 1200x360
grep -q "boxes" "$out/a.log" && { echo "FAIL: a language has no font"; fail=1; }
# On a Mac with Xcode, iPhones render on Flutter's iOS engine (no simulator booted).
if [ "$(uname -s)" = Darwin ]; then
  grep -q "Flutter's iOS engine" "$out/a.log" && echo "iOS: Flutter's iOS engine" || { echo "FAIL: iOS was not rendered on Flutter's iOS engine"; fail=1; }
  xcrun simctl list devices booted | grep -q Booted && { echo "FAIL: a simulator was booted"; fail=1; }
fi
echo "time: first $((t1 - t0))s, second $((t2 - t1))s"

# The options: screens rules, font scales, frames, the fastlane layout and full length.
(cd Example/FlutterDemo && ../../Android/cli/build/libs/swiftshot-android run \
  --devices "iPhone 17 Pro Max,Pixel 10 Pro" --languages "en-US,de" --font-scales 1,1.3 --frame plain --accept-bezel-license \
  --layout fastlane --screen "Stats: devices=Pixel* languages=de" --screen "History: full_length=true" \
  --previews "Root,Stats,History,Habit card" --output "$out/o" 2>&1) > "$out/o.log" || { echo "FAIL: the options run"; tail -20 "$out/o.log"; fail=1; }
want() { [ -f "$out/$1" ] && echo "ok: $1" || { echo "FAIL: no $1"; fail=1; }; }
nope() { [ ! -e "$out/$1" ] && echo "ok: no $1" || { echo "FAIL: $1 should not exist"; fail=1; }; }
want "o/de/images/phoneScreenshots/Pixel 10 Pro-Stats-1.3x.png"
nope "o/en-US/images/phoneScreenshots/Pixel 10 Pro-Stats-1x.png"
nope "o/de/iPhone 17 Pro Max-Stats-1x.png"
want "o/en-US/iPhone 17 Pro Max-Habit card-1.3x.png"
want "o-framed/en-US/images/phoneScreenshots/Pixel 10 Pro-Root-1x_framed.png"
nope "o-framed/en-US/images/phoneScreenshots/Pixel 10 Pro-Habit card-1x_framed.png"
if [ "$(uname -s)" = Darwin ]; then want "o-framed/en-US/iPhone 17 Pro Max-Root-1x_framed.png"; fi
tall=$(size "$out/o/en-US/images/phoneScreenshots/Pixel 10 Pro-History-1x.png" | cut -dx -f2)
[ "$tall" -gt 4000 ] && echo "full length ok: $tall px" || { echo "FAIL: History is $tall px high, not full length"; fail=1; }
[ "$count" -eq "$expected" ] || { echo "FAIL: $count screenshots, expected $expected"; fail=1; }
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### Flutter"; echo "| | |"; echo "|---|---:|"; echo "| screenshots | $count |"; echo "| first run | $((t1 - t0)) s |"; echo "| second run | $((t2 - t1)) s |"; } >> "$GITHUB_STEP_SUMMARY"
fi
exit $fail
