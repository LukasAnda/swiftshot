#!/bin/bash
# The Compose Multiplatform check (CI, or a Mac): renders the shared @Previews of
# Example/MultiplatformDemo for the given targets in two languages (one of them RTL), then checks
# that every expected screenshot exists with the device's size and that the report has no errors.
#   Android/ci/multiplatform.sh android,desktop [out-dir]    (any OS with a JDK 21+ and the Android SDK)
#   Android/ci/multiplatform.sh ios [out-dir]                (a Mac with Xcode, after make)
set -euo pipefail
cd "$(dirname "$0")/../.."
platforms=${1:?platforms, e.g. android,desktop or ios}
out=${2:-${RUNNER_TEMP:-/tmp}/swiftshot-multiplatform-$(echo "$platforms" | tr , -)}
rm -rf "$out" && mkdir -p "$out"
( cd Android && ./gradlew --no-daemon -q :cli:jar :worker:jar :desktop-worker:jar )
jar=Android/cli/build/libs/swiftshot-android.jar
previews=("Welcome" "Root" "Habit list" "Stats" "History" "Settings" "Add habit sheet" "Delete dialog" "Habit card")
languages=(en-US ar)
android=("Pixel 10 Pro" "Pixel Tablet")
desktop=("Desktop 1440×900 @2x")
ios=("iPhone 17 Pro Max" "iPad Pro 13-inch (M5)")
join() { local IFS=,; echo "$*"; }

start=$(date +%s)
java -jar "$jar" run --project-dir Example/MultiplatformDemo --platforms "$platforms" \
  --devices "$(join "${android[@]}")" --desktop-devices "$(join "${desktop[@]}")" --ios-devices "$(join "${ios[@]}")" \
  --languages "$(join "${languages[@]}")" --output "$out" -v 2>&1 | grep -v "^    \[w" | tee "$out.log"
seconds=$(( $(date +%s) - start ))

devices=()
for p in ${platforms//,/ }; do
  case $p in
    android) devices+=("${android[@]}") ;;
    desktop) devices+=("${desktop[@]}") ;;
    ios) devices+=("${ios[@]}") ;;
    *) echo "unknown platform $p"; exit 2 ;;
  esac
done

fail=0
expected=$(( ${#previews[@]} * ${#devices[@]} * ${#languages[@]} ))
count=$(find "$out" -name '*.png' | wc -l | tr -d ' ')
echo "screenshots: $count (expected $expected)"
[ "$count" -eq "$expected" ] || { echo "FAIL: expected $expected screenshots, got $count"; fail=1; }
missing=0
for l in "${languages[@]}"; do for d in "${devices[@]}"; do for p in "${previews[@]}"; do
  [ -s "$out/$l/$d-$p.png" ] || { echo "FAIL: missing $l/$d-$p.png"; missing=$((missing + 1)); fail=1; }
done; done; done
[ "$missing" -eq 0 ] && echo "files ok: every preview on every device in every language"
grep -q '"errors": \[\]' "$out/swiftshot-report.json" || { echo "FAIL: errors in the report"; grep -A20 '"errors"' "$out/swiftshot-report.json" | head -30; fail=1; }

# Sizes: full-screen previews are the device's own size.
size() { python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(24); print("%dx%d" % struct.unpack(">II", d[16:24]))' "$1"; }
check() { local s; s=$(size "$out/$1"); [ "$s" = "$2" ] && echo "size ok: $1 $s" || { echo "FAIL: $1 is $s, expected $2"; fail=1; }; }
case ",$platforms," in *,android,*) check "en-US/Pixel 10 Pro-Root.png" 1280x2856; check "ar/Pixel Tablet-Stats.png" 2560x1600 ;; esac
case ",$platforms," in *,desktop,*) check "en-US/Desktop 1440×900 @2x-Root.png" 2880x1800; check "ar/Desktop 1440×900 @2x-Stats.png" 2880x1800 ;; esac
case ",$platforms," in *,ios,*) check "en-US/iPhone 17 Pro Max-Root.png" 1320x2868; check "ar/iPad Pro 13-inch (M5)-Stats.png" 2064x2752 ;; esac

# iOS renders without a simulator: none may be left booted.
if [ "$(uname)" = Darwin ] && xcrun simctl list devices booted 2>/dev/null | grep -q "(Booted)"; then
  echo "FAIL: a simulator is booted"; xcrun simctl list devices booted; fail=1
fi

echo "time: ${seconds}s"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### Compose Multiplatform ($platforms)"; echo "| | |"; echo "|---|---:|"; echo "| screenshots | $count of $expected |"; echo "| run (builds, renders) | ${seconds} s |"; } >> "$GITHUB_STEP_SUMMARY"
fi
exit $fail
