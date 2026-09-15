#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# audit-dependencies.sh
# -----------------------------------------------------------------------------
# Vulnerability audit across every lockfile / requirements file in the repo.
#
# Three deliberate design choices:
#
#   * Discovery runs at runtime via `find`, never from a hand-maintained list
#     of directories. A package directory added six months from now is picked
#     up automatically instead of being silently skipped.
#
#   * Registry transport errors are retried with backoff and kept strictly
#     distinct from real vulnerability findings. A flaky registry must not
#     turn the build red, and a real finding must never be swallowed.
#
#   * --changed-only audits just the manifests the current branch touched, so
#     a docs-only PR costs nothing while a lockfile bump is still gated.
#
# Usage:
#   scripts/audit-dependencies.sh                  # audit every manifest
#   scripts/audit-dependencies.sh --changed-only   # only what this branch changed
#
# Env:
#   BASE_REF     base ref for --changed-only (default: origin/main)
#   AUDIT_LEVEL  npm audit severity threshold (default: critical)
#   MAX_ATTEMPTS transient-error retry attempts (default: 3)
#
# Complements scripts/assert-dependency-age.sh, which enforces the 24h cooldown
# (.claude/rules/dependency-security.md Rule 2). This script enforces Rule 3's
# "no known vulnerabilities" half.
# -----------------------------------------------------------------------------
set -euo pipefail

CHANGED_ONLY=0
[[ "${1:-}" == "--changed-only" ]] && CHANGED_ONLY=1

BASE_REF=${BASE_REF:-origin/main}
AUDIT_LEVEL=${AUDIT_LEVEL:-critical}
MAX_ATTEMPTS=${MAX_ATTEMPTS:-3}

RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
GREEN=$'\033[0;32m'
RESET=$'\033[0m'

# Errors that mean "the registry hiccuped", not "your dependencies are unsafe".
TRANSIENT='audit endpoint returned an error|ENOTFOUND|ETIMEDOUT|ECONNRESET|EAI_AGAIN|socket hang up|503 Service Unavailable|Temporary failure|Connection aborted|ReadTimeout|Max retries exceeded'

FAILURES=()
AUDITED=0

# -- helpers ------------------------------------------------------------------

_changed_files() {
  git diff --name-only "$BASE_REF"...HEAD 2>/dev/null || true
}

_was_changed() {
  # $1 = path relative to repo root (as `find` emits it, with leading ./)
  local needle="${1#./}"
  grep -Fxq "$needle" <<< "$CHANGED_LIST"
}

_run_with_retry() {
  # $1 = human label, rest = command to run.
  # Returns 0 on clean audit, 1 on a real finding. Retries only transport errors.
  local label=$1; shift
  local attempt=1 out rc

  while :; do
    set +e
    out=$("$@" 2>&1)
    rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
      if [[ $attempt -gt 1 ]]; then
        echo "::warning title=Audit retried::${label} passed on attempt ${attempt} after a transient registry error"
      fi
      return 0
    fi

    if [[ $attempt -lt $MAX_ATTEMPTS ]] && grep -qiE "$TRANSIENT" <<< "$out"; then
      echo "${YELLOW}·${RESET} ${label}: transient registry error on attempt ${attempt}, retrying"
      attempt=$((attempt + 1))
      sleep $((attempt * 5))
      continue
    fi

    # A real finding (or a non-transient failure we should surface).
    printf '%s\n' "$out"
    return 1
  done
}

# -- npm ----------------------------------------------------------------------

_audit_npm() {
  command -v npm >/dev/null 2>&1 || return 0

  local lockfile dir
  while IFS= read -r lockfile; do
    [[ -z "$lockfile" ]] && continue
    if [[ $CHANGED_ONLY -eq 1 ]] && ! _was_changed "$lockfile"; then
      continue
    fi
    dir=$(dirname "$lockfile")
    echo "→ npm audit (${AUDIT_LEVEL}): ${dir}"
    AUDITED=$((AUDITED + 1))
    # --package-lock-only avoids a full `npm ci` just to audit.
    if ! _run_with_retry "npm:${dir}" \
        npm audit --prefix "$dir" --package-lock-only --audit-level="$AUDIT_LEVEL"; then
      FAILURES+=("npm: ${dir}")
    fi
  done < <(find . -name package-lock.json -not -path '*/node_modules/*' \
             -not -path '*/.git/*' 2>/dev/null | sort)
}

# -- python -------------------------------------------------------------------

_pip_audit_cmd() {
  if command -v pip-audit >/dev/null 2>&1; then
    echo "pip-audit"
  elif command -v uv >/dev/null 2>&1 && [[ -f pyproject.toml ]]; then
    echo "uv run pip-audit"
  else
    echo ""
  fi
}

_audit_python() {
  local runner
  runner=$(_pip_audit_cmd)
  if [[ -z "$runner" ]]; then
    echo "${YELLOW}·${RESET} pip-audit unavailable — skipping Python audit"
    return 0
  fi

  local req
  while IFS= read -r req; do
    [[ -z "$req" ]] && continue
    if [[ $CHANGED_ONLY -eq 1 ]] && ! _was_changed "$req"; then
      continue
    fi
    echo "→ pip-audit: ${req}"
    AUDITED=$((AUDITED + 1))
    # shellcheck disable=SC2086
    if ! _run_with_retry "pip:${req}" $runner --requirement "$req" --desc; then
      FAILURES+=("pip: ${req}")
    fi
  done < <(find . -name 'requirements*.txt' -not -path '*/.venv/*' \
             -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | sort)

  # Project-level audit (uv.lock / pyproject.toml) when nothing is pinned via
  # requirements files, or when the project manifest itself changed.
  if [[ -f pyproject.toml ]]; then
    if [[ $CHANGED_ONLY -eq 1 ]] \
       && ! _was_changed "pyproject.toml" && ! _was_changed "uv.lock"; then
      return 0
    fi
    echo "→ pip-audit: project environment"
    AUDITED=$((AUDITED + 1))
    # shellcheck disable=SC2086
    if ! _run_with_retry "pip:project" $runner --desc; then
      FAILURES+=("pip: project environment")
    fi
  fi
}

# -- run ----------------------------------------------------------------------

CHANGED_LIST=""
if [[ $CHANGED_ONLY -eq 1 ]]; then
  if ! git rev-parse "$BASE_REF" >/dev/null 2>&1; then
    echo "${YELLOW}WARN:${RESET} base ref $BASE_REF not found — auditing everything instead."
    CHANGED_ONLY=0
  else
    CHANGED_LIST=$(_changed_files)
    if [[ -z "$CHANGED_LIST" ]]; then
      echo "${GREEN}OK:${RESET} no files changed against ${BASE_REF}."
      exit 0
    fi
  fi
fi

_audit_npm
_audit_python

if [[ ${#FAILURES[@]} -gt 0 ]]; then
  echo ""
  echo "${RED}ERROR:${RESET} dependency audit found vulnerabilities in:"
  for f in "${FAILURES[@]}"; do
    echo "  ${YELLOW}✗${RESET} $f"
  done
  echo ""
  echo "See .claude/rules/dependency-security.md Rule 3."
  echo "Fix by upgrading the affected package, or document a waiver in the PR."
  exit 1
fi

if [[ $AUDITED -eq 0 ]]; then
  echo "${GREEN}OK:${RESET} no manifests to audit."
else
  echo "${GREEN}OK:${RESET} ${AUDITED} manifest(s) audited, no vulnerabilities at or above ${AUDIT_LEVEL}."
fi
exit 0
