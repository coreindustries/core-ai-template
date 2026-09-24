#!/usr/bin/env bash
# lanes-config.sh — reads .claude/agent-lanes.json, the single project config for
# the agent lanes. Sourced by the board scripts (defines lanes_cfg) or run directly:
#
#   lanes-config.sh get '<jq expr>' [default]   print a value (default if null/missing)
#   lanes-config.sh check                        validate the config; exit 1 on a problem
#
# LANES_CONFIG overrides the path (the test harness uses it).
# Portability: macOS bash 3.2 + Linux.

LANES_REPO_ROOT="${LANES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
LANES_CONFIG="${LANES_CONFIG:-$LANES_REPO_ROOT/.claude/agent-lanes.json}"

# lanes_cfg <jq expr> [default] — prints the value as raw text. A missing config
# file is not an error for reads: every caller has a sane default, and a fresh
# template must still run `board.sh help`.
lanes_cfg() {
  local expr="$1" def="${2:-}" out
  if [ ! -f "$LANES_CONFIG" ]; then
    printf '%s' "$def"
    return 0
  fi
  out="$(jq -r "($expr) // empty" "$LANES_CONFIG" 2>/dev/null)" || {
    echo "lanes-config: cannot read '$expr' from $LANES_CONFIG (invalid JSON?)" >&2
    return 2
  }
  if [ -z "$out" ]; then printf '%s' "$def"; else printf '%s' "$out"; fi
}

lanes_check() {
  local problems=0
  command -v jq >/dev/null 2>&1 || { echo "FAIL jq not on PATH"; return 1; }
  [ -f "$LANES_CONFIG" ] || { echo "FAIL config missing: $LANES_CONFIG"; return 1; }
  jq -e . "$LANES_CONFIG" >/dev/null 2>&1 || { echo "FAIL $LANES_CONFIG is not valid JSON"; return 1; }

  local prefix
  prefix="$(lanes_cfg '.namePrefix' C)"
  if ! printf '%s' "$prefix" | grep -Eq '^[A-Za-z][A-Za-z0-9]{0,11}$'; then
    echo "FAIL namePrefix '$prefix' must be 1-12 letters/digits"; problems=$((problems + 1))
  fi

  # claims.ttlHours / claims.keepLabel — stale-claim reclaim (board.sh
  # list --stale / reclaim). Both have defaults, so a config that omits
  # "claims" entirely is valid; only an explicit bad value fails.
  local ttl_hours
  ttl_hours="$(lanes_cfg '.claims.ttlHours' 24)"
  case "$ttl_hours" in
    ''|*[!0-9]*) echo "FAIL claims.ttlHours '$ttl_hours' must be a non-negative integer (0 disables reclaim)"; problems=$((problems + 1)) ;;
  esac

  # lanes_cfg falls back to the default for an empty string too (matching
  # every other key read through it), so a genuinely blank keepLabel can
  # never reach here — the check that IS reachable, and worth catching, is
  # a label containing whitespace: GitHub label names may not contain it.
  local keep_label
  keep_label="$(lanes_cfg '.claims.keepLabel' wip-keep)"
  case "$keep_label" in
    *[[:space:]]*) echo "FAIL claims.keepLabel '$keep_label' must not contain whitespace (it is a GitHub label name)"; problems=$((problems + 1)) ;;
  esac

  local n i name cmd field
  n="$(jq '(.deploy.environments // []) | length' "$LANES_CONFIG")"
  [ "$n" -gt 0 ] || { echo "WARN deploy.environments is empty — the Release Manager has no ladder"; }
  i=0
  while [ "$i" -lt "$n" ]; do
    name="$(jq -r ".deploy.environments[$i].name // \"\"" "$LANES_CONFIG")"
    if ! printf '%s' "$name" | grep -Eq '^[a-z0-9][a-z0-9-]*$'; then
      echo "FAIL environments[$i].name '$name' must be lowercase letters, digits, dashes"; problems=$((problems + 1))
    fi
    for field in deploy health logs rollback; do
      cmd="$(jq -r ".deploy.environments[$i].$field // \"\"" "$LANES_CONFIG")"
      if [ -z "$cmd" ]; then
        echo "WARN $name.$field is empty — fill it before the Release Manager runs this rung"
        continue
      fi
      case "$field" in
        deploy|rollback)
          # make -n still runs $(MAKE) recipe lines — a dry run that deploys.
          if printf '%s' "$cmd" | grep -Eq '(^|[[:space:];&|/])g?make([[:space:]].*)?[[:space:]](-[A-Za-z]*n[A-Za-z]*|--dry-run|--just-print|--recon)([[:space:]]|$)|MAKEFLAGS=["'"'"']?-?[A-Za-z]*n'; then
            echo "FAIL $name.$field uses a make dry-run flag; make still executes \$(MAKE) lines under -n"
            problems=$((problems + 1))
          fi
          ;;
      esac
    done
    i=$((i + 1))
  done

  if [ "$problems" -gt 0 ]; then
    echo "lanes-config: $problems problem(s) in $LANES_CONFIG"
    return 1
  fi
  echo "OK $LANES_CONFIG"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  case "${1:-}" in
    get) shift; lanes_cfg "$@"; echo ;;
    check) lanes_check ;;
    *) echo "usage: lanes-config.sh get '<jq expr>' [default] | check" >&2; exit 2 ;;
  esac
fi
