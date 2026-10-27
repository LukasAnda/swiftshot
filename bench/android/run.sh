#!/bin/bash
# Android benchmark: swiftshot vs Paparazzi vs Roborazzi rendering the same :app @Previews of
# Example/AndroidDemo with the same device × language × appearance matrix (bench/android/bench.json).
#
#   bench/android/run.sh [swiftshot] [paparazzi] [roborazzi]     # default: all three, in that order
#
# For every tool, sequentially on the same machine:
#   warm-up (untimed)  a throwaway copy renders one or two screenshots, so every dependency is
#                      downloaded (Maven artifacts, layoutlib, Robolectric's android-all jar) and
#                      Gradle's artifact transforms and swiftshot's layoutlib unpack are cached:
#                      what a CI cache restore gives you
#   cold               a fresh copy of the project (no build outputs, Gradle build cache off), new
#                      Gradle and Kotlin daemons: compiles the app and renders everything (Paparazzi
#                      and Roborazzi compile their tests too, swiftshot runs swiftshotPrepare)
#   warm               the same copy again with no change; Gradle tools rerun their test task
#                      (--rerun) so they really render; outputs are deleted first so the count is real
#
# Environment:
#   BENCH_DIR          work directory (default .bench-android.noindex)
#   BENCH_PARALLEL     renderer processes / test forks for every tool (default: swiftshot's own
#                      choice, min(cores/2, RAM/2 GB, 8))
#   BENCH_GRADLE_ARGS  extra Gradle arguments for every tool, e.g. "--no-daemon --max-workers=2"
#   BENCH_NICE         command prefix, e.g. "nice -n 19"
#   BENCH_STOP_DAEMONS 1: stop Gradle and Kotlin daemons before each cold run (CI; it kills every
#                      Kotlin daemon of the user)
#   BENCH_DEVICES, BENCH_LANGUAGES, BENCH_APPEARANCES   override the matrix (comma separated)
#   BENCH_SCENARIOS    which steps to run (default "warmup cold warm"; "cold" for a quick check)
#
# Results: $BENCH_DIR/results.tsv (scenario, seconds, screenshots, exit), results.json, per-run logs.
set -u
here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/../.." && pwd)
BENCH_DIR=${BENCH_DIR:-$ROOT/.bench-android.noindex}
mkdir -p "$BENCH_DIR"; BENCH_DIR=$(cd "$BENCH_DIR" && pwd)
JAR=${SWIFTSHOT_ANDROID_JAR:-$ROOT/Android/cli/build/libs/swiftshot-android.jar}
CONFIG=$here/bench.json
RESULTS=$BENCH_DIR/results.tsv
printf 'scenario\tseconds\tscreenshots\texit\n' > "$RESULTS"
: > "$BENCH_DIR/sizes.tsv"
export SWIFTSHOT_CACHE=$BENCH_DIR/swiftshot-cache
read -r -a NICE <<< "${BENCH_NICE:-}"
read -r -a GRADLE_ARGS <<< "${BENCH_GRADLE_ARGS:-}"

cfg() { python3 -c 'import json,sys; print(",".join(json.load(open(sys.argv[1]))[sys.argv[2]]))' "$CONFIG" "$1"; }
DEVICES=${BENCH_DEVICES:-$(cfg devices)}
LANGUAGES=${BENCH_LANGUAGES:-$(cfg languages)}
APPEARANCES=${BENCH_APPEARANCES:-$(cfg appearances)}

cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)
mem_gb=$( (grep MemTotal /proc/meminfo 2>/dev/null | awk '{print int($2/1048576)}') || true)
[ -n "$mem_gb" ] || mem_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
# swiftshot's default: one renderer per core, at most one per 1.5 GB and 8 in all.
auto=$cores
[ $(( mem_gb * 2 / 3 )) -lt $auto ] && auto=$(( mem_gb * 2 / 3 )); [ $auto -ge 1 ] || auto=1
[ $auto -gt 8 ] && auto=8
PARALLEL=${BENCH_PARALLEL:-$auto}
echo "machine: $cores cores, $mem_gb GB; $PARALLEL renderer processes / test forks per tool"
echo "matrix: devices=$DEVICES languages=$LANGUAGES appearances=$APPEARANCES"

[ -f "$JAR" ] || { echo "error: $JAR is missing; build it with: cd Android && ./gradlew :cli:jar :worker:jar" >&2; exit 2; }

now() { python3 -c 'import time; print("%.3f" % time.time())'; }
notice() { if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::notice title=$1::$2"; else echo "   $2"; fi; }

FAILED=0
failed() {  # scenario log
    FAILED=1
    sed 's/\x1b\[[0-9;]*m//g' "$2" | grep -E 'FAILED|rror:|Exception|failed|✘' | tail -8 | while IFS= read -r line; do
        if [ -n "${GITHUB_ACTIONS:-}" ]; then echo "::error title=$1::${line}"; else echo "   $line"; fi
    done
}

count_pngs() { find "$1" -name '*.png' 2>/dev/null | wc -l | tr -d ' '; }

# Distinct image sizes and how many screenshots have each: "1280x2856:200 2560x1600:200 …".
sizes() {
    python3 - "$1" <<'PY'
import collections, os, struct, sys
c = collections.Counter()
for d, _, files in os.walk(sys.argv[1]):
    for f in files:
        if f.endswith('.png'):
            with open(os.path.join(d, f), 'rb') as h: w, hh = struct.unpack('>II', h.read(24)[16:24])
            c['%dx%d' % (w, hh)] += 1
print(' '.join('%s:%d' % kv for kv in sorted(c.items(), key=lambda kv: -kv[1])))
PY
}

stop_daemons() {  # project
    [ "${BENCH_STOP_DAEMONS:-0}" = 1 ] || return 0
    (cd "$1" && ./gradlew --stop -q >/dev/null 2>&1) || true
    pkill -f KotlinCompileDaemon 2>/dev/null || true
    sleep 2
}

# Runs one tool once.  run_tool tool project outdir warm(0/1) devices languages appearances [limit]
run_tool() {
    local tool=$1 project=$2 out=$3 warm=$4 devices=$5 languages=$6 appearances=$7 limit=${8:-}
    case $tool in
    swiftshot)
        local cmd=(java -jar "$JAR" run --project-dir "$project" --modules :app
            --devices "$devices" --languages "$languages" --appearances "$appearances"
            --parallel "$PARALLEL" --output "$out") a
        [ -n "$limit" ] && cmd+=(--previews Welcome)
        for a in ${GRADLE_ARGS[@]+"${GRADLE_ARGS[@]}"}; do cmd+=("--gradle-arg=$a"); done
        ${NICE[@]+"${NICE[@]}"} "${cmd[@]}"
        ;;
    paparazzi|roborazzi)
        local cmd=(./gradlew)
        if [ "$tool" = paparazzi ]; then cmd+=(:app:recordPaparazziDebug); else cmd+=(:app:recordRoborazziDebug); fi
        # Warm: the test task has nothing new to do, so it is rerun explicitly.
        [ "$warm" = 1 ] && cmd+=(:app:testDebugUnitTest --rerun)
        cmd+=(--console=plain "-Pbench.devices=$devices" "-Pbench.languages=$languages" "-Pbench.appearances=$appearances")
        [ -n "$limit" ] && cmd+=("-Pbench.limit=$limit")
        cmd+=(${GRADLE_ARGS[@]+"${GRADLE_ARGS[@]}"})
        (cd "$project" && ${NICE[@]+"${NICE[@]}"} "${cmd[@]}")
        ;;
    esac
}

output_dir() {  # tool project swiftshot-out
    case $1 in
    swiftshot) echo "$3" ;;
    paparazzi) echo "$2/app/src/test/snapshots/images" ;;
    roborazzi) echo "$2/app/build/outputs/roborazzi" ;;
    esac
}

clean_outputs() {  # tool project
    case $1 in
    paparazzi) rm -rf "$2/app/src/test/snapshots" "$2/app/build/reports/paparazzi" ;;
    roborazzi) rm -rf "$2/app/build/outputs/roborazzi" "$2/app/build/reports/roborazzi" "$2/app/build/test-results/roborazzi" ;;
    esac
}

timed() {  # scenario tool project warm
    local name=$1 tool=$2 project=$3 warm=$4
    local dir=$BENCH_DIR/$name
    rm -rf "$dir"; mkdir -p "$dir"
    clean_outputs "$tool" "$project"
    ( while true; do
        if [ -r /proc/loadavg ]; then cut -d' ' -f1 /proc/loadavg; else sysctl -n vm.loadavg | awk '{print $2}'; fi
        sleep 5
      done ) > "$dir/load.txt" &
    local sampler=$!
    local start; start=$(now)
    run_tool "$tool" "$project" "$dir/screenshots" "$warm" "$DEVICES" "$LANGUAGES" "$APPEARANCES" > "$dir/log.txt" 2>&1
    local code=$?
    local secs; secs=$(python3 -c "print(round($(now) - $start, 1))")
    kill $sampler 2>/dev/null; wait $sampler 2>/dev/null
    local out; out=$(output_dir "$tool" "$project" "$dir/screenshots")
    local n; n=$(count_pngs "$out")
    printf '%s\t%s\t%s\t%s\n' "$name" "$secs" "$n" "$code" >> "$RESULTS"
    printf '%s\t%s\n' "$name" "$(sizes "$out")" >> "$BENCH_DIR/sizes.tsv"
    echo "== $name: $secs s, $n screenshots, exit $code"
    notice "$name resources" "peak load $(sort -n "$dir/load.txt" | tail -1)"
    notice "$name sizes" "$(sizes "$out")"
    # A few samples for the artifact (Welcome and Root, first language).
    mkdir -p "$dir/samples"
    find "$out" -name '*.png' 2>/dev/null | grep -i -- "${LANGUAGES%%,*}" | grep -iE 'welcome|root' | head -8 | while IFS= read -r f; do cp "$f" "$dir/samples/"; done
    [ "$code" = 0 ] || failed "$name" "$dir/log.txt"
}

TOOLS=("$@"); [ ${#TOOLS[@]} -gt 0 ] || TOOLS=(swiftshot paparazzi roborazzi)

SCENARIOS=" ${BENCH_SCENARIOS:-warmup cold warm} "
has() { [[ $SCENARIOS == *" $1 "* ]]; }

# 1. Warm-up: download everything every tool needs (not timed).
first_device=${DEVICES%%,*} first_language=${LANGUAGES%%,*} first_appearance=${APPEARANCES%%,*}
for tool in "${TOOLS[@]}"; do
    has warmup || break
    echo "== $tool: warm-up (dependencies, not timed)"
    prep=$BENCH_DIR/$tool-warmup
    "$here/setup.sh" "$tool" "$prep" "$PARALLEL" >/dev/null || { FAILED=1; continue; }
    if ! run_tool "$tool" "$prep" "$BENCH_DIR/$tool-warmup-out" 0 "$first_device" "$first_language" "$first_appearance" 2 > "$BENCH_DIR/$tool-warmup.log" 2>&1; then
        echo "   warm-up failed (log: $BENCH_DIR/$tool-warmup.log)"; failed "$tool warm-up" "$BENCH_DIR/$tool-warmup.log"
    fi
    stop_daemons "$prep"
    rm -rf "$prep" "$BENCH_DIR/$tool-warmup-out"
done

# 2. Cold and warm, one tool at a time.
for tool in "${TOOLS[@]}"; do
    project=$BENCH_DIR/$tool-project
    "$here/setup.sh" "$tool" "$project" "$PARALLEL" >/dev/null || { FAILED=1; continue; }
    stop_daemons "$project"
    has cold && timed "$tool-cold" "$tool" "$project" 0
    has warm && timed "$tool-warm" "$tool" "$project" 1
    stop_daemons "$project"
    # Hosted runners have little disk: the copy (build outputs, Paparazzi's goldens) is not needed any more.
    [ -n "${GITHUB_ACTIONS:-}" ] && rm -rf "$project" "$BENCH_DIR/$tool-cold/screenshots" "$BENCH_DIR/$tool-warm/screenshots"
done

python3 - "$RESULTS" "$BENCH_DIR/sizes.tsv" "$CONFIG" "$BENCH_DIR/results.json" "$PARALLEL" "$cores" "$mem_gb" "$DEVICES" "$LANGUAGES" "$APPEARANCES" <<'PY'
import csv, json, platform, sys
results, sizes, config, out, parallel, cores, mem, devices, languages, appearances = sys.argv[1:11]
size = dict(line.rstrip('\n').split('\t', 1) for line in open(sizes) if '\t' in line)
rows = []
for r in csv.DictReader(open(results), delimiter='\t'):
    tool, scenario = r['scenario'].rsplit('-', 1)
    rows.append({"tool": tool, "scenario": scenario, "seconds": float(r['seconds']), "screenshots": int(r['screenshots']),
                 "exit": int(r['exit']), "sizes": size.get(r['scenario'], "")})
cfg = json.load(open(config))
json.dump({
    "machine": {"os": platform.platform(), "cores": int(cores), "memory_gb": int(mem)},
    "parallel": int(parallel),
    "matrix": {"module": cfg["module"], "devices": devices.split(','), "languages": languages.split(','), "appearances": appearances.split(',')},
    "versions": cfg["versions"],
    "results": rows,
}, open(out, 'w'), indent=2)
PY
column -t -s $'\t' "$RESULTS"
exit $FAILED
