#!/usr/bin/env bash
# run-all.sh — runs every scripts/dev/board/tests/*.test.sh (and
# test_log_triage.py, if present) and prints one PASS/FAIL line per suite.
# Exits non-zero if any suite failed.
#
# Run: bash scripts/dev/board/tests/run-all.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

overall_failed=0

echo "=== scripts/dev/board test suites ==="
echo ""

for t in "$TESTS_DIR"/*.test.sh; do
  [ -e "$t" ] || continue
  name="$(basename "$t")"
  out="$("$t" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    status="PASS"
  else
    status="FAIL"
    overall_failed=1
  fi
  printf '%-28s %s\n' "$name" "$status"
  if [ "$status" = "FAIL" ]; then
    printf '%s\n' "$out" | sed 's/^/    /'
  fi
done

if [ -f "$TESTS_DIR/test_log_triage.py" ]; then
  if command -v python3 >/dev/null 2>&1; then
    out="$(cd "$TESTS_DIR" && python3 test_log_triage.py 2>&1)"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      status="PASS"
    else
      status="FAIL"
      overall_failed=1
    fi
    printf '%-28s %s\n' "test_log_triage.py" "$status"
    if [ "$status" = "FAIL" ]; then
      printf '%s\n' "$out" | sed 's/^/    /'
    fi
  else
    printf '%-28s %s\n' "test_log_triage.py" "SKIP (python3 not found)"
  fi
fi

echo ""
if [ "$overall_failed" -eq 0 ]; then
  echo "ALL SUITES PASSED"
else
  echo "ONE OR MORE SUITES FAILED"
fi
exit "$overall_failed"
