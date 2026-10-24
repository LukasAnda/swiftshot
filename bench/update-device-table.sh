#!/bin/bash
# Maintainers: re-measure the built-in display table (Sources/swiftshot/BuiltInDisplays.swift)
# on this Mac's Xcode. Boots every iOS device type once per installed iOS runtime in a throwaway
# device set and calibration cache, so users never have to boot anything to get exact values.
#
#   bench/update-device-table.sh                # all installed iOS runtimes
#   RUNTIMES="26.5,27.0" bench/update-device-table.sh
#   EMIT=0 bench/update-device-table.sh         # only measure (CI merges several images' results)
set -eu
cd "$(dirname "$0")/.."
ROOT=$PWD
WORK=${WORK:-$(mktemp -d "${TMPDIR:-/tmp}/swiftshot-table.XXXXXX").noindex}
mkdir -p "$WORK"
RUNTIMES=${RUNTIMES:-$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(",".join(r["version"] for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]))')}
WATCH_RUNTIMES=${WATCH_RUNTIMES:-$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(",".join(r["version"] for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "watchOS" and r["isAvailable"]))')}
DEVICES=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
types = json.load(sys.stdin)["devicetypes"]
print(",".join(t["name"] for t in types if t.get("productFamily") in ("iPhone", "iPad")))')
WATCHES=$(xcrun simctl list devicetypes -j | python3 -c '
import json, sys
print(",".join(t["name"] for t in json.load(sys.stdin)["devicetypes"] if t.get("productFamily") == "Apple Watch"))')
echo "runtimes: $RUNTIMES"
echo "devices:  $DEVICES"
# Calibration boots simulators: the no-boot libraries aren't needed (and older SDKs, like macos-15's
# Xcode 26.3 watchOS simulator SDK, lack the headers they build against).
make -s bin/swiftshot bin/SwiftshotAgent.dylib bin/SwiftshotAgent-watchOS.dylib
cd Example/DemoApp
SWIFTSHOT_CALIBRATION_CACHE="$WORK/calibration.json" "$ROOT/bin/swiftshot" calibrate \
    --devices "$DEVICES" --ios "$RUNTIMES" \
    --device-set "$WORK/devices.noindex" --derived-data "$WORK/DerivedData" \
    $([ "${EMIT:-1}" = 1 ] && echo --emit-table "$ROOT/Sources/swiftshot/BuiltInDisplays.swift")
# Watches (default text size per case size); same cache, so the table gets both.
if [ -n "$WATCH_RUNTIMES" ] && [ -n "$WATCHES" ]; then
    SWIFTSHOT_CALIBRATION_CACHE="$WORK/calibration.json" "$ROOT/bin/swiftshot" calibrate \
        --devices "$WATCHES" --watchos "$WATCH_RUNTIMES" --watch-scheme DemoWatch \
        --device-set "$WORK/devices.noindex" --derived-data "$WORK/DerivedData" \
        $([ "${EMIT:-1}" = 1 ] && echo --emit-table "$ROOT/Sources/swiftshot/BuiltInDisplays.swift")
fi
echo "calibration: $WORK/calibration.json"
cd "$ROOT" && git --no-pager diff --stat Sources/swiftshot/BuiltInDisplays.swift || true
