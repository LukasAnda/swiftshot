#!/bin/bash
# Screenshot testing end to end on Example/AndroidDemo (a copy in its own git repository):
# record, verify passes, one colour changed (Welcome's glow) makes verify fail with exactly the
# Welcome screenshots, accept applies the report, verify passes again, and a report from an older
# commit is refused. Then a GitHub pull request: verify on the merge-commit checkout records the head sha, accept on the
# detached head pushes to the pull request's branch in a bare remote, and the next verify passes. Also: the comparison takes under 5 % of the render time (the run's own timings).
#   Android/ci/baseline.sh [work-dir]
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
work=${1:-${RUNNER_TEMP:-/tmp}/swiftshot-baseline-it}
rm -rf "$work" && mkdir -p "$work"
proj=$work/project
mkdir -p "$proj"
(cd Example/AndroidDemo && tar cf - --exclude=./build --exclude='./*/build' --exclude=./.gradle --exclude=./.kotlin --exclude=./local.properties .) | (cd "$proj" && tar xf -)
[ -f Example/AndroidDemo/local.properties ] && cp Example/AndroidDemo/local.properties "$proj/"

( cd Android && ./gradlew --no-daemon -q ${GRADLE_FLAGS:-} :cli:jar :worker:jar )
jar=$root/Android/cli/build/libs/swiftshot-android.jar

# Real git, not SWIFTSHOT_COMMIT: accept checks the report's commit against HEAD. The CI this runs on is not the
# subject until the pull request section below.
unset SWIFTSHOT_COMMIT SWIFTSHOT_BRANCH
export SWIFTSHOT_CI=false
git_() { git -C "$proj" -c user.name=swiftshot-test -c user.email=test@example.com -c commit.gpgsign=false "$@"; }
git_ init -q -b main
git_ add -A && git_ commit -q -m "Demo app"

fail=0
bad() { echo "FAIL: $*"; fail=1; }
baseline=$proj/screenshots-baseline
out=$work/out
# Runs the CLI, its output filtered to the console and a log; the exit code in $rc.
cli() {  # log-name args...
  local log=$work/$1.log; shift
  { c=0; java -jar "$jar" "$@" || c=$?; echo "$c" > "$work/rc"; } 2>&1 | { grep -v "^    \[w" || true; } | tee -a "$log"
  rc=$(cat "$work/rc")
}
# One device, language and appearance keep it quick; the comparison covers Welcome and Settings.
swiftshot() {  # command report-dir
  cli "$1" "$1" --project-dir "$proj" --devices "Pixel 10 Pro" --languages en-US --appearances light \
    --previews "Welcome,Settings" --output "$out" --baseline-directory "$baseline" --report-directory "$2"
}
json() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$@"; }
# The comparison's share of the render time: timings.json in the report, totalSeconds in the run's report.
overhead() {  # report-dir label
  python3 - "$1/timings.json" "$out/swiftshot-report.json" "$2" <<'PY' || bad "the comparison took 5 % or more of the render time ($2)"
import json, sys
compare = json.load(open(sys.argv[1]))["compareSeconds"]
render = json.load(open(sys.argv[2]))["totalSeconds"]
print("overhead (%s): compare %.3f s of render %.1f s = %.2f %%" % (sys.argv[3], compare, render, 100 * compare / render))
sys.exit(0 if compare < 0.05 * render else 1)
PY
}

echo "::group::record"
swiftshot record "$work/unused"; [ "$rc" = 0 ] || bad "record exited $rc"
echo "::endgroup::"
count=$(find "$baseline" -name '*.png' | wc -l | tr -d ' ')
echo "baseline: $count screenshots"
[ "$count" -eq 2 ] || bad "expected 2 baseline screenshots, got $count"
git_ add -A && git_ commit -q -m "Baseline"

echo "::group::verify (unchanged)"
swiftshot verify "$work/report-same"; [ "$rc" = 0 ] || bad "verify on the recorded state exited $rc, expected 0"
echo "::endgroup::"
[ "$(json "$work/report-same/result.json" 'd["status"]')" = passed ] || bad "result.json status is not passed"
overhead "$work/report-same" unchanged

# One colour in the copy: Welcome's second glow becomes blue.
file=$proj/app/src/main/java/com/swiftshot/demo/ui/welcome/WelcomeScreen.kt
grep -q 'listOf(glow.copy(alpha = 0.55f)' "$file" || bad "the colour to change is not in WelcomeScreen.kt"
sed -i.orig 's/listOf(glow.copy(alpha = 0.55f)/listOf(Color(0xFF2E6BFF).copy(alpha = 0.55f)/' "$file" && rm "$file.orig"
git_ commit -q -am "Blue glow"
want=$(json "$work/report-same/result.json" '"\n".join(s["id"] for s in d["screenshots"] if s["preview"] == "Welcome")')

echo "::group::verify (changed colour)"
swiftshot verify "$work/report-changed"; [ "$rc" = 1 ] || bad "verify after the colour change exited $rc, expected 1"
echo "::endgroup::"
got=$(json "$work/report-changed/result.json" '"\n".join(s["id"] for s in d["screenshots"] if s["status"] != "unchanged")')
echo "changed: $got"
[ -n "$want" ] && [ "$got" = "$want" ] || bad "expected exactly the Welcome screenshots to change ($want), got: $got"
[ "$(json "$work/report-changed/result.json" 'sorted(set(s["status"] for s in d["screenshots"] if s["status"] != "unchanged"))')" = "['changed']" ] || bad "differences other than changed"
[ "$(json "$work/report-changed/manifest.json" '"\n".join(d["ids"]["changed"])')" = "$want" ] || bad "manifest.json does not list exactly the changed ids"
overhead "$work/report-changed" changed

echo "::group::accept"
cli accept accept --from "$work/report-changed" --baseline-directory "$baseline"; [ "$rc" = 0 ] || bad "accept exited $rc, expected 0"
echo "::endgroup::"
while IFS= read -r id; do cmp -s "$baseline/$id.png" "$work/report-changed/images/new/$id.png" || bad "accept did not copy $id"; done <<< "$want"
git_ add -A && git_ commit -q -m "Accept the blue glow"

echo "::group::verify (accepted)"
swiftshot verify "$work/report-accepted"; [ "$rc" = 0 ] || bad "verify after accept exited $rc, expected 0"
echo "::endgroup::"

# A report from an older commit: an unrelated commit since, so accept refuses it and changes nothing.
echo "unrelated" > "$proj/NOTES.txt"; git_ add NOTES.txt; git_ commit -q -m "Unrelated"
before=$(git_ status --porcelain)
cli stale accept --from "$work/report-changed" --baseline-directory "$baseline"
[ "$rc" = 1 ] || bad "accept of a stale report exited $rc, expected 1"
[ "$(git_ status --porcelain)" = "$before" ] || bad "the refused accept changed files"
grep -q "commit" "$work/stale.log" || bad "the refusal does not name the commit"

# A GitHub pull request. The runner checks out a merge commit (GITHUB_SHA); the event file has the head.
echo "::group::pull request"
remote=$work/remote.git
git init -q --bare -b main "$remote"
git_ remote add origin "$remote"; git_ push -q origin main
git_ checkout -q -b feature/pr
sed -i.orig 's/Color(0xFF2E6BFF).copy(alpha = 0.55f)/Color(0xFFFF2E2E).copy(alpha = 0.55f)/' "$file" && rm "$file.orig"
git_ commit -q -am "Red glow"
prhead=$(git_ rev-parse HEAD)
git_ checkout -q --detach main && git_ merge -q --no-ff -m "Merge pull request" feature/pr
event() {  # head sha
  printf '{"pull_request":{"number":7,"head":{"sha":"%s","ref":"feature/pr","repo":{"full_name":"acme/app"}},"base":{"repo":{"full_name":"acme/app"}}}}\n' "$1" > "$work/event.json"
}
githubenv() {  # GITHUB_SHA
  export SWIFTSHOT_CI=true GITHUB_ACTIONS=true GITHUB_EVENT_PATH=$work/event.json GITHUB_REPOSITORY=acme/app GITHUB_HEAD_REF=feature/pr GITHUB_SHA=$1
}
event "$prhead"; githubenv "$(git_ rev-parse HEAD)"
swiftshot verify "$work/report-pr"; [ "$rc" = 1 ] || bad "verify on the merge checkout exited $rc, expected 1"
[ "$(json "$work/report-pr/result.json" 'd["commit"]')" = "$prhead" ] || bad "result.json commit is not the pull request head $prhead"
[ "$(json "$work/report-pr/result.json" 'd["ci"]["pullRequest"]')" = 7 ] || bad "result.json does not name pull request 7"
# The recipes check out the head, not the merge: accept there pushes to the pull request's branch.
git_ checkout -q --detach "$prhead"
cli accept-pr accept --from "$work/report-pr" --baseline-directory "$baseline" --push; [ "$rc" = 0 ] || bad "accept --push on the pull request exited $rc, expected 0"
echo "::endgroup::"
pushed=$(git --git-dir "$remote" rev-parse feature/pr 2>/dev/null || true)
[ -n "$pushed" ] && [ "$pushed" = "$(git_ rev-parse HEAD)" ] || bad "the pull request branch in the remote is not the accept commit"
[ "$(git_ rev-parse HEAD^)" = "$prhead" ] || bad "the accept commit does not follow the pull request head"
[ "$(git --git-dir "$remote" rev-parse main)" = "$(git_ rev-parse main)" ] || bad "accept pushed to main"

echo "::group::verify (pull request accepted)"
event "$(git_ rev-parse HEAD)"; githubenv "$(git_ rev-parse HEAD)"
swiftshot verify "$work/report-pr-accepted"; [ "$rc" = 0 ] || bad "verify after the pull request accept exited $rc, expected 0"
echo "::endgroup::"
unset GITHUB_ACTIONS GITHUB_EVENT_PATH GITHUB_REPOSITORY GITHUB_HEAD_REF GITHUB_SHA; export SWIFTSHOT_CI=false

[ "$fail" = 0 ] && echo "baseline end to end: ok"
exit $fail
