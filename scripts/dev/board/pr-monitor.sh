#!/usr/bin/env bash
# pr-monitor.sh - standing, deterministic watch over EVERY open PR (no LLM in the loop).
#
# Usage: pr-monitor.sh [--once] [--interval SEC=180]
#
# Re-lists the open PRs each cycle and runs pr-watch.sh --once on each. pr-watch.sh
# persists what it already reported, so an `ACTION ...` line (any pr-watch.sh event)
# appears once per change. The only other output is a WARN when gh cannot list PRs.
#
# Run it with Claude Code's Monitor tool (each stdout line becomes a notification):
#   Monitor({command: "bash scripts/dev/board/pr-monitor.sh", timeout_ms: 1800000})
# A Monitor run expires at 30 min; re-arm on each expiry notice. GitHub webhooks reach
# only cloud sessions, not a local one, so polling is the local mechanism.
set -u -o pipefail
ONCE=0
INTERVAL=180
while [ $# -gt 0 ]; do
  case "$1" in
    --once) ONCE=1 ;;
    --interval) shift; INTERVAL="${1:?--interval needs seconds}" ;;
    *) echo "pr-monitor: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

HERE="$(cd "$(dirname "$0")" && pwd)"
while true; do
  if prs=$(gh pr list --state open --limit 100 --json number -q '.[].number' | tr '\n' ' '); then
    # One pr-watch call per PR: pr-watch keys its dedup state on the exact PR list it
    # is given, so passing the whole list re-reported every PR whenever one opened or
    # closed. A per-PR key stays stable across cycles.
    for pr in $prs; do
      bash "$HERE/pr-watch.sh" "$pr" --once | grep --line-buffered '^ACTION' || true
    done
  else
    # stdout, not stderr: Monitor notifies on stdout lines, so a dead gh must not go quiet.
    echo "pr-monitor: WARN could not list open PRs this cycle; retrying in ${INTERVAL}s"
  fi
  [ "$ONCE" = 1 ] && break
  sleep "$INTERVAL"
done
