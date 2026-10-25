#!/bin/bash
# Maintainers: re-measure the built-in display table (Sources/swiftshot/BuiltInDisplays.swift)
# on this Mac's Xcode. Boots device types in a throwaway device set and calibration cache, so users
# never have to boot anything to get exact values.
#
#   bench/update-device-table.sh
#   EMIT=0 bench/update-device-table.sh         # only measure (CI merges several images' results)
#   FORCE=1 bench/update-device-table.sh        # every device type, not only those the table lacks
#
# Display data doesn't depend on the runtime, so by default only device types missing from the
# table are measured, once each, on the newest runtime that supports them: a new Xcode costs a few
# boots, not hundreds.
set -eu
cd "$(dirname "$0")/.."
ROOT=$PWD
WORK=${WORK:-$(mktemp -d "${TMPDIR:-/tmp}/swiftshot-table.XXXXXX").noindex}
mkdir -p "$WORK"
# "<runtime>\t<device types>" lines: each device type of these families the given table in
# BuiltInDisplays.swift lacks (every one with FORCE=1), under the newest runtime that supports it.
plan() { xcrun simctl list runtimes -j | python3 -c '
import json, re, sys
platform, families, table, force = sys.argv[1], sys.argv[2].split(","), sys.argv[3], sys.argv[4] == "1"
src = open("Sources/swiftshot/BuiltInDisplays.swift").read()
block = src.split("static let " + table + ":", 1)[1].split("\n    ]", 1)[0]
known = set(re.findall(r"^        \"([^\"]+)\":", block, re.M))
runtimes = sorted((r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == platform and r["isAvailable"]),
                  key=lambda r: [int(x) for x in r["version"].split(".")], reverse=True)
groups, seen = {}, set()
for r in runtimes:
    for t in r.get("supportedDeviceTypes", []):
        if t.get("productFamily") in families and t["name"] not in seen and (force or t["name"] not in known):
            seen.add(t["name"]); groups.setdefault(r["version"], []).append(t["name"])
for version, names in groups.items(): print(version + "\t" + ",".join(names))' "$1" "$2" "$3" "${FORCE:-0}"; }
IOS_PLAN=$(plan iOS iPhone,iPad table)
WATCH_PLAN=$(plan watchOS "Apple Watch" watchSafeArea)
echo "to measure:"; printf '%s\n' "${IOS_PLAN:-  no iOS device types missing}" "${WATCH_PLAN:-  no watch device types missing}"
# Calibration boots simulators: the no-boot libraries aren't needed (and older SDKs, like macos-15's
# Xcode 26.3 watchOS simulator SDK, lack the headers they build against).
make -s bin/swiftshot bin/SwiftshotAgent.dylib bin/SwiftshotAgent-watchOS.dylib
cd Example/DemoApp
[ -f "$WORK/calibration.json" ] || echo "{}" > "$WORK/calibration.json"
# Watches: default text size per case size; same cache, so the table gets both.
while IFS=$'\t' read -r runtime devices; do
    [ -n "$devices" ] || continue
    SWIFTSHOT_CALIBRATION_CACHE="$WORK/calibration.json" "$ROOT/bin/swiftshot" calibrate \
        --devices "$devices" --ios "$runtime" \
        --device-set "$WORK/devices.noindex" --derived-data "$WORK/DerivedData" \
        $([ "${EMIT:-1}" = 1 ] && echo --emit-table "$ROOT/Sources/swiftshot/BuiltInDisplays.swift")
done <<< "$IOS_PLAN"
while IFS=$'\t' read -r runtime devices; do
    [ -n "$devices" ] || continue
    SWIFTSHOT_CALIBRATION_CACHE="$WORK/calibration.json" "$ROOT/bin/swiftshot" calibrate \
        --devices "$devices" --watchos "$runtime" --watch-scheme DemoWatch \
        --device-set "$WORK/devices.noindex" --derived-data "$WORK/DerivedData" \
        $([ "${EMIT:-1}" = 1 ] && echo --emit-table "$ROOT/Sources/swiftshot/BuiltInDisplays.swift")
done <<< "$WATCH_PLAN"
echo "calibration: $WORK/calibration.json"
cd "$ROOT" && git --no-pager diff --stat Sources/swiftshot/BuiltInDisplays.swift || true
