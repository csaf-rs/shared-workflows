#!/bin/bash
# Generate coverage report in markdown format from cargo-llvm-cov JSON output.
# Reads cargo-llvm-cov JSON output from stdin and outputs markdown to stdout
# Usage: cargo llvm-cov --json ... | ./scripts/coverage/coverage_report.sh


set -euo pipefail

echo "### Test Coverage Report"
echo ""

# Overall coverage summary
jq -r '
  .data[0].totals |
  "| Metric | Covered | Total | Coverage |",
  "| ------ | ------: | ----: | -------: |",
  "| Lines | \(.lines.covered) | \(.lines.count) | \(.lines.percent * 100 | round / 100)% |",
  "| Functions | \(.functions.covered) | \(.functions.count) | \(.functions.percent * 100 | round / 100)% |",
  "| Regions | \(.regions.covered) | \(.regions.count) | \(.regions.percent * 100 | round / 100)% |",
  "| Instantiations | \(.instantiations.covered) | \(.instantiations.count) | \(.instantiations.percent * 100 | round / 100)% |"
'

echo ""
echo "<details><summary>Per-file coverage</summary>"
echo ""

# Per-file coverage table
jq -r '
  "| File | Lines | Functions | Regions | Line Coverage |",
  "| ---- | ----: | --------: | ------: | -----------: |",
  (.data[0].files | sort_by(-.summary.lines.percent) | .[] |
    .filename as $f |
    .summary |
    "| \($f | split("/") | .[-3:] | join("/")) | \(.lines.covered)/\(.lines.count) | \(.functions.covered)/\(.functions.count) | \(.regions.covered)/\(.regions.count) | \(.lines.percent * 100 | round / 100)% |"
  )
'

echo ""
echo "</details>"
