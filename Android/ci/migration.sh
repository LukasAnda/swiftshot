#!/bin/bash
# `swiftshot init` on a Paparazzi project renders exactly the tested previews on the tests' devices.
# Copies Example/AndroidDemo, adds Paparazzi (as bench/android/setup.sh does) and a test file with
# static configs (Paparazzi itself never runs), then checks init's report and what `run` renders:
# two screens, each at its test device's pixel size, and nothing else.
#   Android/ci/migration.sh [work-dir]
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
work=${1:-${RUNNER_TEMP:-/tmp}/swiftshot-migration-it}
paparazzi=$(python3 -c 'import json; print(json.load(open("bench/android/bench.json"))["versions"]["paparazzi"])')
rm -rf "$work" && mkdir -p "$work"
proj=$work/project
mkdir -p "$proj"
(cd Example/AndroidDemo && tar cf - --exclude=./build --exclude='./*/build' --exclude=./.gradle --exclude=./.kotlin --exclude=./local.properties .) | (cd "$proj" && tar xf -)
[ -f Example/AndroidDemo/local.properties ] && cp Example/AndroidDemo/local.properties "$proj/"

# The Paparazzi plugin in :app, and tests that configure it statically.
python3 - "$proj/app/build.gradle.kts" "$paparazzi" <<'PY'
import sys
path, version = sys.argv[1:3]
s = open(path).read()
open(path, "w").write(s.replace("plugins {\n", 'plugins {\n    id("app.cash.paparazzi") version "%s"\n' % version, 1))
PY
tests=$proj/app/src/test/java/com/swiftshot/demo
mkdir -p "$tests"
# Three test classes in one file, each with its own rule.
cat > "$tests/ScreenshotTests.kt" <<'KT'
package com.swiftshot.demo

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import com.android.resources.Density
import com.android.resources.NightMode
import com.swiftshot.demo.ui.RootPreview
import com.swiftshot.demo.ui.StatsPreview
import org.junit.Rule
import org.junit.Test

class PhoneTest {
    @get:Rule val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5)
    @Test fun root() { paparazzi.snapshot { RootPreview() } }
}

class TabletTest {
    @get:Rule val paparazzi = Paparazzi(
        deviceConfig = DeviceConfig(screenWidth = 1600, screenHeight = 2560, density = Density.XXHIGH, nightMode = NightMode.NIGHT),
    )
    @Test fun stats() { paparazzi.snapshot { StatsPreview() } }
}

class NoPreviewTest {
    @get:Rule val paparazzi = Paparazzi()
    @Test fun unpreviewed() { paparazzi.snapshot { UnpreviewedScreen(state) } }
}
KT

( cd Android && ./gradlew --no-daemon -q ${GRADLE_FLAGS:-} :cli:jar :worker:jar )
jar=$root/Android/cli/build/libs/swiftshot-android.jar

fail=0
bad() { echo "FAIL: $*"; fail=1; }

echo "::group::init"
java -jar "$jar" init --project-dir "$proj" --force
echo "::endgroup::"
echo "--- swiftshot.json"; cat "$proj/swiftshot.json"
echo "--- swiftshot-migration.md"; cat "$proj/swiftshot-migration.md"
grep -q "2 of 3 snapshot tests are covered by previews; 1 isn't" "$proj/swiftshot-migration.md" || bad "init's report does not say 2 of 3 are covered"
grep -q "UnpreviewedScreen" "$proj/swiftshot-migration.md" || bad "the report does not list the snapshot without a preview"

echo "::group::run"
out=$work/out
java -jar "$jar" run --project-dir "$proj" --output "$out" -v 2>&1 | grep -v "^    \[w" | tee "$work/run.log"
echo "::endgroup::"

# Sizes: Pixel 5 is 1080x2340; the test's own tablet is 1600x2560.
size() { python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(24); print("%dx%d" % struct.unpack(">II", d[16:24]))' "$1"; }
pixel5=$(python3 -c 'import json; d=json.load(open("Android/cli/src/main/resources/paparazzi-devices.json"))["paparazzi"]["presets"]["PIXEL_5"]; print("%dx%d" % (d["width"], d["height"]))')
count=$(find "$out" -name '*.png' | wc -l | tr -d ' ')
echo "screenshots: $count"
[ "$count" -eq 2 ] || { bad "expected exactly 2 screenshots, got $count"; find "$out" -name '*.png'; }
grep -q '"errors": \[\]' "$out/swiftshot-report.json" || bad "errors in the report"
expect() {  # name-fragment size
  local f; f=$(find "$out" -name "*$1*.png")
  [ -n "$f" ] && [ "$(echo "$f" | wc -l)" -eq 1 ] || { bad "expected one screenshot of $1, found: ${f:-none}"; return; }
  local s; s=$(size "$f"); [ "$s" = "$2" ] && echo "size ok: $(basename "$f") $s" || bad "$(basename "$f") is $s, expected $2"
}
expect Root "$pixel5"
expect Stats 1600x2560
case $(find "$out" -name '*Stats*.png') in *dark*) echo "dark ok";; *) bad "the tablet screen is not dark";; esac
exit $fail
