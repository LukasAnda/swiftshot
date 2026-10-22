#!/bin/bash
# Renders bench/run.sh results as a Markdown table (for $GITHUB_STEP_SUMMARY).
#   bench/summary.sh <results.tsv> <title>
[ -f "$1" ] || { echo "No results ($1 missing)"; exit 0; }
echo "### ${2:-benchmark}"
echo
echo "| run | seconds | screenshots | s / screenshot | exit |"
echo "|---|---:|---:|---:|---:|"
tail -n +2 "$1" | while IFS=$'\t' read -r name secs shots code; do
    per=$( [ "${shots:-0}" -gt 0 ] 2>/dev/null && awk "BEGIN {printf \"%.2f\", $secs / $shots}" || echo -)
    echo "| $name | $secs | $shots | $per | $code |"
done
