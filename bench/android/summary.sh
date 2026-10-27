#!/bin/bash
# Renders bench/android/run.sh results as Markdown (for $GITHUB_STEP_SUMMARY).
#   bench/android/summary.sh <results.json> [title]
[ -f "$1" ] || { echo "No results ($1 missing)"; exit 0; }
python3 - "$1" "${2:-Android benchmark}" <<'PY'
import json, os, sys
r = json.load(open(sys.argv[1]))
m, mx = r["machine"], r["matrix"]
print(f"### {sys.argv[2]}\n")
print(f"{mx['module']} previews × {len(mx['devices'])} devices ({', '.join(mx['devices'])}) × {len(mx['languages'])} languages "
      f"({', '.join(mx['languages'])}) × {', '.join(mx['appearances'])}; {m['cores']} cores, {m['memory_gb']} GB, "
      f"{r['parallel']} renderer processes / test forks per tool.\n")
tools = []
for row in r["results"]:
    if row["tool"] not in tools: tools.append(row["tool"])
by = {(x["tool"], x["scenario"]): x for x in r["results"]}
print("| tool | cold (s) | warm (s) | screenshots (cold / warm) | warm s / screenshot | exit (cold / warm) |")
print("|---|---:|---:|---:|---:|---:|")
for t in tools:
    c, w = by.get((t, "cold")), by.get((t, "warm"))
    sec = lambda x: f"{x['seconds']:.1f}" if x else "-"
    n = lambda x: str(x["screenshots"]) if x else "-"
    per = f"{w['seconds'] / w['screenshots']:.2f}" if w and w["screenshots"] else "-"
    code = lambda x: str(x["exit"]) if x else "-"
    print(f"| {t} | {sec(c)} | {sec(w)} | {n(c)} / {n(w)} | {per} | {code(c)} / {code(w)} |")
counts = {x["screenshots"] for x in r["results"]}
if len(counts) > 1:
    print(f"\n**Screenshot counts differ** between runs: {sorted(counts)}.")
print("\n<details><summary>Image sizes (size: count)</summary>\n")
for x in r["results"]:
    print(f"- {x['tool']} {x['scenario']}: {x['sizes'] or '-'}")
print("\n</details>")
v = r["versions"]
print("\n" + ", ".join(f"{k} {val}" for k, val in v.items()))
if os.environ.get("GITHUB_ACTIONS"):
    for x in r["results"]:
        print(f"::notice title={x['tool']} {x['scenario']}::{x['seconds']} s, {x['screenshots']} screenshots, exit {x['exit']}", file=sys.stderr)
PY
