#!/bin/bash
# Swiftshot benchmark on the demo app: cold / cached-template / warm runs, optionally fastlane.
#
#   bench/run.sh swiftshot      # booted (--boot): cold, then new simulators with cached templates, then warm
#   bench/run.sh noboot         # the default: iOS rendered without any simulator
#   bench/run.sh fastlane       # fastlane snapshot on the same iOS devices and languages, new simulators
#
# The cold run starts from an empty DerivedData (fastlane's build is cold on a fresh runner too).
# Every run uses brand-new simulators (a private device set for swiftshot, freshly created
# "FL …" devices for fastlane), so "cold" means what it means on a fresh CI machine.
# Results: $BENCH_DIR/results.tsv (scenario, seconds, screenshots, exit code) and per-run logs.
set -u
cd "$(dirname "$0")/.."
ROOT=$PWD
BENCH_DIR=${BENCH_DIR:-$ROOT/.bench.noindex}
SWIFTSHOT=${SWIFTSHOT:-$ROOT/bin/swiftshot}
mkdir -p "$BENCH_DIR"
RESULTS=$BENCH_DIR/results.tsv
[ -f "$RESULTS" ] || printf 'scenario\tseconds\tscreenshots\texit\n' > "$RESULTS"

# Drop the watch from the matrix when the machine has no watchOS runtime.
CONFIG=$BENCH_DIR/bench.json
if xcrun simctl list runtimes | grep -q '^watchOS'; then
    cp bench/bench.json "$CONFIG"
else
    echo "No watchOS runtime installed: benchmarking iOS only"
    python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); c["devices"]=[d for d in c["devices"] if "Watch" not in d]; c.pop("watch_scheme",None); json.dump(c,open(sys.argv[2],"w"))' bench/bench.json "$CONFIG"
fi

record() {  # scenario seconds outdir exit
    local n; n=$(find "$3" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$n" "$4" >> "$RESULTS"
    echo "== $1: $2 s, $n screenshots, exit $4"
}

FAILED=0
failed() {  # scenario log: surface the error lines (also as GitHub annotations)
    FAILED=1
    sed 's/\x1b\[[0-9;]*m//g' "$2" | grep -E '!|✘|error|rror:|failed' | tail -8 | while IFS= read -r line; do
        [ -n "${GITHUB_ACTIONS:-}" ] && echo "::error title=$1::${line}" || echo "   $line"
    done
}

swiftshot_run() {  # scenario device-set template-dir [extra args…]
    local name=$1 set=$2 templates=$3; shift 3
    local out=$BENCH_DIR/$name
    rm -rf "$out"; mkdir -p "$out"
    local start; start=$(date +%s)
    # Peak load average and swap use during the run (small CI VMs run out of both).
    ( while true; do echo "$(sysctl -n vm.loadavg | awk '{print $2}') $(sysctl -n vm.swapusage | awk '{print $6}' | tr -d M)"; sleep 5; done ) > "$out/resources.txt" &
    local sampler=$!
    (cd Example/DemoApp && "$SWIFTSHOT" --config "$CONFIG" --device-set "$set" --template-cache "$templates" \
        --derived-data "$BENCH_DIR/DerivedData" \
        -o "$out/screenshots" "$@") 2>&1 | tee "$out/log.txt"
    local code=${PIPESTATUS[0]}
    kill $sampler 2>/dev/null
    local peak; peak=$(sort -n -k1 "$out/resources.txt" | tail -1 | cut -d' ' -f1)/$(sort -n -k2 "$out/resources.txt" | tail -1 | cut -d' ' -f2)
    if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::notice title=$name resources::peak load ${peak%/*}, peak swap used ${peak#*/} MB"; else echo "   peak load ${peak%/*}, swap ${peak#*/} MB"; fi
    record "$name" $(( $(date +%s) - start )) "$out/screenshots" "$code"
    [ "$code" = 0 ] || failed "$name" "$out/log.txt"
    [ -f "$out/screenshots/swiftshot-report.json" ] && python3 -c '
import json, os, sys
r = json.load(open(sys.argv[1]))
stages = "; ".join(f"{k} {v:.0f}s" for k, v in sorted(r["timings"].items(), key=lambda kv: -kv[1]))
print(f"::notice title={sys.argv[2]} stages::{stages}" if os.environ.get("GITHUB_ACTIONS") else "   stages: " + stages)
for e in r.get("errors", [])[:5]:
    print(f"::warning title={sys.argv[2]} error::{e}" if os.environ.get("GITHUB_ACTIONS") else "   error: " + e)
' "$out/screenshots/swiftshot-report.json" "$name"
    [ -n "${GITHUB_ACTIONS:-}" ] && sed 's/\x1b\[[0-9;]*m//g' "$out/log.txt" | grep -E '^ *[0-9.]+s (▸ (First boot|Template|Ready)|✔ Built|!)' | tr '\n' '|' | sed 's/^/::notice title='"$name"' timeline::/; s/$/\n/' 
}

case "${1:-swiftshot}" in
swiftshot)
    T=$BENCH_DIR/templates.noindex
    rm -rf "${T:?}"
    # Fresh set paths every invocation: CoreSimulator keeps a loaded set's state, so reusing a
    # deleted set's path can confuse it.
    RUN=$(date +%s)
    rm -rf "$BENCH_DIR/DerivedData"   # cold means cold: the first run also compiles from scratch
    swiftshot_run cold   "$BENCH_DIR/set-$RUN-cold.noindex"   "$T" --boot --shutdown
    swiftshot_run cached "$BENCH_DIR/set-$RUN-cached.noindex" "$T" --boot
    swiftshot_run warm   "$BENCH_DIR/set-$RUN-cached.noindex" "$T" --boot --shutdown
    ;;
noboot)
    # The default: iOS without any simulator. noboot-ios-* match fastlane's matrix (same devices
    # and languages, no watch); noboot-all adds the Apple Watch (which still boots).
    T=$BENCH_DIR/templates.noindex
    rm -rf "${T:?}" "$BENCH_DIR/DerivedData"
    RUN=$(date +%s)
    python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); c["devices"]=[d for d in c["devices"] if "Watch" not in d]; c.pop("watch_scheme",None); json.dump(c,open(sys.argv[2],"w"))' "$CONFIG" "$BENCH_DIR/ios.json"
    CONFIG=$BENCH_DIR/ios.json swiftshot_run noboot-ios-cold "$BENCH_DIR/set-$RUN-nb.noindex" "$T"
    CONFIG=$BENCH_DIR/ios.json swiftshot_run noboot-ios-warm "$BENCH_DIR/set-$RUN-nb.noindex" "$T"
    swiftshot_run noboot-all "$BENCH_DIR/set-$RUN-nb.noindex" "$T" --shutdown
    ;;
fastlane)
    DEVICES=$(python3 -c 'import json,sys; print("\n".join(d for d in json.load(open(sys.argv[1]))["devices"] if "Watch" not in d))' "$CONFIG")
    LANGS=$(python3 -c 'import json,sys; print(",".join(json.load(open(sys.argv[1]))["languages"]))' "$CONFIG")
    # Newest iOS runtime that supports every benchmark device (what swiftshot picks by default).
    read -r RUNTIME VERSION < <(xcrun simctl list runtimes -j | python3 -c '
import json, sys
want = set(sys.argv[1].splitlines())
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r.get("isAvailable")]
rts.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
ok = [r for r in rts if want <= {t["name"] for t in r.get("supportedDeviceTypes", [])}] or rts
print(ok[-1]["identifier"], ok[-1]["version"])' "$DEVICES")
    echo "fastlane on iOS $VERSION"
    FL_NAMES=()
    while IFS= read -r d; do
        xcrun simctl create "FL $d" "$d" "$RUNTIME" >/dev/null && FL_NAMES+=("FL $d")
    done <<< "$DEVICES"
    out=$BENCH_DIR/fastlane; rm -rf "$out"; mkdir -p "$out"
    start=$(date +%s)
    (cd Example/DemoApp && FL_OUT="$out/screenshots" fastlane snapshot \
        --devices "$(IFS=,; echo "${FL_NAMES[*]}")" --languages "$LANGS" --ios_version "$VERSION" \
        --output_directory "$out/screenshots") 2>&1 | tee "$out/log.txt"
    code=${PIPESTATUS[0]}
    record fastlane $(( $(date +%s) - start )) "$out/screenshots" "$code"
    [ "$code" = 0 ] || failed fastlane "$out/log.txt"
    for n in "${FL_NAMES[@]}"; do xcrun simctl delete "$n" 2>/dev/null; done
    ;;
*) echo "usage: $0 swiftshot|noboot|fastlane"; exit 2 ;;
esac
column -t -s $'\t' "$RESULTS"
exit $FAILED
