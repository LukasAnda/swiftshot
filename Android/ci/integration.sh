#!/bin/bash
# The Android integration suite (CI on a free Linux runner, or a Mac): renders Example/AndroidDemo
# for phones, a foldable (both states), a tablet and Wear OS in five languages and both
# appearances, then checks that every screenshot exists with the device's size, that a second run
# is byte-for-byte identical, that full-length screens grow, and the time budget.
#   Android/ci/integration.sh [out-dir]
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${1:-${RUNNER_TEMP:-/tmp}/swiftshot-android-it}
# The free Linux runners differ by machine: the same warm run took 58–93 s in October 2026.
budget=${SWIFTSHOT_ANDROID_BUDGET:-120}
rm -rf "$out" && mkdir -p "$out"
( cd Android && ./gradlew --no-daemon -q :cli:jar :worker:jar )
jar=Android/cli/build/libs/swiftshot-android.jar
run() {
  java -jar "$jar" run --project-dir Example/AndroidDemo \
    --devices "Pixel 10 Pro,Pixel 9 Pro Fold,Pixel 9 Pro Fold (folded),Pixel Tablet" \
    --languages "en-US,de-DE,sk,ar,ja" --appearances light,dark \
    --screen "Stats long: full_length=true" --output "$1" -v 2>&1 | grep -v "^    \[w" | tee "$1.log"
}

echo "::group::First run (builds, renders)"
start=$(date +%s); run "$out/a"; first=$(( $(date +%s) - start ))
echo "::endgroup::"
echo "::group::Second run (warm)"
start=$(date +%s); run "$out/b"; second=$(( $(date +%s) - start ))
echo "::endgroup::"

fail=0
count=$(find "$out/a" -name '*.png' | wc -l | tr -d ' ')
echo "screenshots: $count"
[ "$count" -ge 900 ] || { echo "FAIL: expected at least 900 screenshots, got $count"; fail=1; }
grep -q '"errors": \[\]' "$out/a/swiftshot-report.json" || { echo "FAIL: errors in the report"; grep -A20 '"errors"' "$out/a/swiftshot-report.json" | head -30; fail=1; }

# Deterministic: the same input renders the same bytes.
if diff -rq --exclude='*.json' --exclude='*.html' "$out/a" "$out/b" >/dev/null; then echo "deterministic: yes"
else echo "FAIL: the second run differs"; diff -rq --exclude='*.json' --exclude='*.html' "$out/a" "$out/b" | head; fail=1; fi

# Sizes: each screen is the device's own size, watch screens square, full length taller.
size() { python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(24); print("%dx%d" % struct.unpack(">II", d[16:24]))' "$1"; }
check() { local s; s=$(size "$out/a/$1"); [ "$s" = "$2" ] && echo "size ok: $1 $s" || { echo "FAIL: $1 is $s, expected $2"; fail=1; }; }
check "en-US/Pixel 10 Pro-Welcome-light.png" 1280x2856
check "de-DE/Pixel 9 Pro Fold-Root-dark.png" 2076x2152
check "ar/Pixel 9 Pro Fold (folded)-Root-light.png" 1080x2424
check "ja/Pixel Tablet-Stats-light.png" 2560x1600
check "en-US/Wear OS Large Round-Watch list.png" 454x454
long=$(size "$out/a/en-US/Pixel 10 Pro-Stats long-light.png"); h=${long#*x}
[ "$h" -gt 2856 ] && echo "full length ok: $long" || { echo "FAIL: full length is $long"; fail=1; }

echo "time: first ${first}s, warm ${second}s (budget ${budget}s)"
[ "$second" -le "$budget" ] || { echo "FAIL: warm run took ${second}s, over the ${budget}s budget"; fail=1; }
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### Android"; echo "| | |"; echo "|---|---:|"; echo "| screenshots | $count |"; echo "| first run | ${first} s |"; echo "| warm run | ${second} s |"; } >> "$GITHUB_STEP_SUMMARY"
fi
exit $fail
