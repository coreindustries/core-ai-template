#!/usr/bin/env bash
# test-helpers.sh — Shared pass/fail/summary helpers for infra test scripts.
#
# Usage:
#   source "$(dirname "$0")/../lib/test-helpers.sh"   # from scripts/infra/tests/
#   source "$(dirname "$0")/lib/test-helpers.sh"      # from scripts/infra/

PASSED=0
FAILED=0
ERRORS=()

pass() { PASSED=$((PASSED + 1)); echo "  ✅ $1"; }
fail() { FAILED=$((FAILED + 1)); ERRORS+=("$1"); echo "  ❌ $1"; }
skip() { echo "  ⏭️  $1 (skipped)"; }

print_summary() {
  local label="${1:-All tests}"
  echo ""
  echo "─── Summary ─────────────────────────────────────────────────────"
  echo "  Passed: $PASSED"
  echo "  Failed: $FAILED"
  if [ "${#ERRORS[@]}" -gt 0 ]; then
    echo ""
    echo "  Failures:"
    for err in "${ERRORS[@]}"; do echo "    • $err"; done
  fi
  echo ""
  if [ "$FAILED" -eq 0 ]; then
    echo "  ✅ $label passed"
    return 0
  else
    echo "  ❌ $FAILED test(s) failed"
    return 1
  fi
}
