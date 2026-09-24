#!/usr/bin/env bash
# pr-watch.sh — deterministic PR babysitting for Claude Code agent sessions.
#
# Purpose: an agent that opened a PR must notice — WITHOUT a human telling
# it — when that PR gets a failed check, a merge conflict, falls behind
# main, becomes ready for review, or merges. This script polls `gh` for
# that state and prints AT MOST a few short lines only when something
# changed that the agent needs to act on; it never dumps raw JSON or logs
# (the whole point is keeping the calling agent's/orchestrator's context
# tiny — token volume, not call count, is the thing that matters).
#
# Usage:
#   pr-watch.sh (--agent NAME | <pr>...) [--interval SEC=120] [--max-wait SEC=3300] [--once]
#
#   --agent NAME   Discover PRs via `gh pr list --label agent:NAME --state
#                  open`, re-read every poll. A PR that disappears from that
#                  open list (merged or closed) between polls is individually
#                  re-checked and reported once.
#   <pr>...        Explicit PR numbers instead of agent-based discovery.
#                  Mutually exclusive with --agent.
#   --interval     Seconds between polls in loop mode (default 120).
#   --max-wait     Give up and exit 0 (IDLE) after this many seconds with no
#                  actionable event (default 3300 = 55min, comfortably under
#                  most agent turn/tool timeouts).
#   --once         Poll exactly once instead of looping, then exit.
#
# Exit codes:
#   0   OK (nothing actionable this poll) or IDLE (max-wait reached)
#   2   ERROR — every `gh` call in a poll failed (see the WARN lines on
#       stderr for the individual causes); arg-validation errors also exit 2
#   10  ACTION — at least one PR has a new actionable event; the event
#       lines are on stdout, one per PR
#
# Designed to be run by an agent via Claude Code's Monitor tool (loop mode,
# streamed) or `run_in_background` (poll, read the notification, re-arm by
# invoking again) — NOT by a human tailing a terminal. After an ACTION exit,
# the caller acts on it, then re-invokes pr-watch.sh to keep watching; state
# is persisted to disk (see "Dedup" below), so re-arming a fresh process
# picks up exactly where the last one left off instead of re-reporting an
# event the agent already handled.
#
# Event classification (one per PR per poll), by precedence:
#   merged        state == MERGED
#   closed        state == CLOSED (and not merged)
#   conflict      mergeable == CONFLICTING, or mergeStateStatus == DIRTY
#   check-failed  a statusCheckRollup entry is failing. statusCheckRollup
#                 mixes two GraphQL shapes and each is judged by ITS OWN
#                 field, never the other's:
#                   CheckRun      (__typename CheckRun, or no "context" key)
#                                 — conclusion in FAILURE, TIMED_OUT,
#                                 ACTION_REQUIRED, STARTUP_FAILURE. CANCELLED
#                                 is not a failure — but it is not a pass
#                                 either: see check-cancelled below.
#                   StatusContext (has a "context" key)
#                                 — state in FAILURE, ERROR
#                 the reported name is (.name // .context) — a StatusContext
#                 entry has no .name, only .context; reading .name alone
#                 makes every StatusContext failure classify as empty/absent.
#   behind        mergeStateStatus == BEHIND
#   pending       a check is still running/queued, OR the rollup is
#                 EMPTY/NULL (no checks reported yet, e.g. seconds after a
#                 push, before CI has started) — not actionable, never
#                 printed, never advances the dedup state. Per-shape:
#                   CheckRun      status != COMPLETED
#                   StatusContext state in PENDING, EXPECTED
#   check-cancelled
#                 a CheckRun name (per workflowName+name) has a CANCELLED run
#                 and NO SUCCESS/NEUTRAL run on this head. A body edit
#                 re-triggers body-reading gates and cancels the superseded
#                 run; if nothing re-ran, that gate never passed on this head.
#                 Names in checks.cancelledOk (.claude/agent-lanes.json) are
#                 exempt — jobs that cancel themselves by design.
#   ready         not draft, no failing/pending/cancelled checks, not behind/
#                 conflicting, at least one check reported — awaiting
#                 review/merge
#   draft-green   same as ready but isDraft == true
#
# Dedup: the (headRefOid, event) pair last REPORTED for a PR is persisted to
# ${TMPDIR:-/tmp}/pr-watch-<id>/pr-<n>.state (<id> = the --agent name or the
# explicit PR-number list, so re-invoking with the same target resumes the
# same dedup state). A PR sitting `ready` for hours reports once, not every
# poll; a new push (new headRefOid) with the same event re-reports, since
# that is new information (e.g. "still ready after your fix").
#
# gh failures: logged as `WARN pr-watch: gh failed for pr=<n>: <stderr line>`
# and the poll continues with the remaining PRs (per error-handling.md — no
# silent skip). If EVERY gh call in a poll failed, the poll is untrustworthy
# as a whole and the script exits 2 rather than reporting a false OK/IDLE.
#
# Portability: macOS bash 3.2 (no `declare -A`, no GNU-only date/sed/grep
# flags, no `timeout` binary) + Linux.
#
# Field values relied on (`gh pr view|list --json number,state,isDraft,
# mergeable,mergeStateStatus,reviewDecision,headRefOid,statusCheckRollup`):
# mergeable is MERGEABLE/CONFLICTING/UNKNOWN; mergeStateStatus is
# UNKNOWN/CLEAN/DIRTY/BEHIND/... — UNKNOWN appears for a few seconds while
# GitHub computes mergeability and is treated as "not conflicting", like CLEAN.
# statusCheckRollup[] mixes CheckRun {__typename,name,status,conclusion,
# workflowName} and StatusContext {__typename,context,state} (commit-status
# integrations); a StatusContext has no "name", so entries are told apart by
# the presence of "context".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
# gh-checks.sh owns the EXIT trap (cleans up GH_CHECKS_MODE_FILE) — if this
# script ever adds its own EXIT trap, chain `rm -f "$GH_CHECKS_MODE_FILE"`
# into it instead of replacing it.
. "$SCRIPT_DIR/gh-checks.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

CANCELLED_OK_JSON="$(lanes_cfg '(.checks.cancelledOk // []) | tojson' '[]')"

BOARD_JSON_FIELDS="number,state,isDraft,mergeable,mergeStateStatus,reviewDecision,headRefOid,statusCheckRollup"




usage() {
  cat <<'EOF'
pr-watch.sh (--agent NAME | <pr>...) [--interval SEC=120] [--max-wait SEC=3300] [--once]

Exit codes: 0 ok/idle, 2 error, 10 action (event lines on stdout).
See the header comment in this file for the full event/dedup contract.
EOF
}


# ---------------------------------------------------------------------------
# fetch_pr_json <n> — `gh pr view` for one PR. Prints JSON on stdout and
# returns 0, or prints a WARN to stderr and returns 1 on gh failure. Never
# aborts the caller's poll.
# ---------------------------------------------------------------------------
fetch_pr_json() {
  local n="$1" out err_file first_line
  err_file="$(mktemp)"
  if out="$(gh_checks pr view "$n" --json "$BOARD_JSON_FIELDS" 2>"$err_file")"; then
    # gh_checks's NOTE (active credential can't read checks, fell back to
    # the keyring login) prints to this err_file on success too — forward it
    # so it reaches the caller instead of being silently discarded.
    grep '^NOTE gh-checks:' "$err_file" >&2 || true
    rm -f "$err_file"
    printf '%s' "$out"
    return 0
  fi
  first_line="$(head -1 "$err_file")"
  rm -f "$err_file"
  echo "WARN pr-watch: gh failed for pr=${n}: ${first_line}" >&2
  return 1
}

# ---------------------------------------------------------------------------
# fetch_agent_list <NAME> — `gh pr list --label agent:NAME --state open`.
# Same success/failure contract as fetch_pr_json.
# ---------------------------------------------------------------------------
fetch_agent_list() {
  local agent="$1" out err_file first_line
  err_file="$(mktemp)"
  if out="$(gh_checks pr list --label "agent:${agent}" --state open --limit 200 \
      --json "$BOARD_JSON_FIELDS" 2>"$err_file")"; then
    # See fetch_pr_json — forward gh_checks's success-path NOTE rather than
    # discarding it with the rest of this call's captured stderr.
    grep '^NOTE gh-checks:' "$err_file" >&2 || true
    rm -f "$err_file"
    printf '%s' "$out"
    return 0
  fi
  first_line="$(head -1 "$err_file")"
  rm -f "$err_file"
  echo "WARN pr-watch: gh failed for agent=${agent} pr-list: ${first_line}" >&2
  return 1
}

# ---------------------------------------------------------------------------
# classify_pr_json <json> — sets globals EVENT, HEAD_SHA, CHECK_NAMES.
# Deliberately not `local`-scoped in EVENT/HEAD_SHA/CHECK_NAMES: this is a
# plain (non-subshell) function call, so callers read the globals directly.
# ---------------------------------------------------------------------------
classify_pr_json() {
  local json="$1"
  local state is_draft mergeable merge_state failing pending_count total_checks

  state="$(printf '%s' "$json" | jq -r '.state')"
  is_draft="$(printf '%s' "$json" | jq -r '.isDraft')"
  mergeable="$(printf '%s' "$json" | jq -r '.mergeable')"
  merge_state="$(printf '%s' "$json" | jq -r '.mergeStateStatus')"
  HEAD_SHA="$(printf '%s' "$json" | jq -r '.headRefOid')"
  CHECK_NAMES=""

  if [ "$state" = "MERGED" ]; then
    EVENT="merged"; return 0
  fi
  if [ "$state" = "CLOSED" ]; then
    EVENT="closed"; return 0
  fi

  if [ "$mergeable" = "CONFLICTING" ] || [ "$merge_state" = "DIRTY" ]; then
    EVENT="conflict"; return 0
  fi

  # statusCheckRollup mixes CheckRun {name,status,conclusion} and
  # StatusContext {context,state} entries; each is judged by its own field
  # (a StatusContext has no .conclusion or .name — falling back to
  # .name alone silently drops every StatusContext failure). Distinguish by
  # the presence of "context", which only StatusContext entries have.
  failing="$(printf '%s' "$json" | jq -r '
    [ (.statusCheckRollup // [])[]
      | . as $e
      | ($e.name // $e.context // "unknown") as $nm
      | ($e | has("context")) as $is_status
      | (if $is_status then ($e.state // "") else ($e.conclusion // $e.state // "") end) as $val
      | (if $is_status then ["FAILURE","ERROR"]
         else ["FAILURE","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE"] end) as $failset
      | select($failset | index($val))
      | $nm
    ] | join(",")
  ')"
  if [ -n "$failing" ]; then
    EVENT="check-failed"; CHECK_NAMES="$failing"; return 0
  fi

  if [ "$merge_state" = "BEHIND" ]; then
    EVENT="behind"; return 0
  fi

  pending_count="$(printf '%s' "$json" | jq -r '
    [ (.statusCheckRollup // [])[]
      | . as $e
      | ($e | has("context")) as $is_status
      | if $is_status
        then select((($e.state // "") as $s | ["PENDING","EXPECTED"] | index($s)))
        else select((($e.status // "COMPLETED") != "COMPLETED")
          or (($e.conclusion // $e.state // "") == ""))
        end
    ] | length
  ')"
  total_checks="$(printf '%s' "$json" | jq -r '(.statusCheckRollup // []) | length')"
  # A push resets statusCheckRollup to empty/null for a few seconds before
  # any check registers. Treating that window as "ready"/"draft-green" would
  # dedup-lock the PR on a stale-green verdict forever — no check has run.
  if [ "$pending_count" -gt 0 ] || [ "$total_checks" -eq 0 ]; then
    EVENT="pending"; return 0
  fi

  local cancelled
  cancelled="$(printf '%s' "$json" | jq -r --argjson ok "$CANCELLED_OK_JSON" '
    [ (.statusCheckRollup // [])[] | select(has("context") | not)
      | {k: ((.workflowName // "") + "/" + (.name // "unknown")), name: (.name // "unknown"),
         c: (.conclusion // "")} ]
    | group_by(.k)
    | map(select((map(.c) | index("CANCELLED")) != null
                 and ([.[] | select(.c == "SUCCESS" or .c == "NEUTRAL")] | length) == 0))
    | map(.[0].name)
    | map(select(. as $n | ($ok | index($n)) == null))
    | unique | join(",")
  ')"
  if [ -n "$cancelled" ]; then
    EVENT="check-cancelled"; CHECK_NAMES="$cancelled"; return 0
  fi

  if [ "$is_draft" = "true" ]; then
    EVENT="draft-green"; return 0
  fi

  EVENT="ready"
}

# ---------------------------------------------------------------------------
# process_pr <n> <json> — classify, dedup against the state file, and (on a
# new actionable event) append to the shared ACTIONS accumulator. Updates
# TOTAL_PRS/PENDING_COUNT/ACTION_COUNT.
# ---------------------------------------------------------------------------
process_pr() {
  local n="$1" json="$2"
  classify_pr_json "$json"
  TOTAL_PRS=$((TOTAL_PRS + 1))

  if [ "$EVENT" = "pending" ]; then
    PENDING_COUNT=$((PENDING_COUNT + 1))
    return 0
  fi

  local state_file="$STATE_DIR/pr-${n}.state" last new_state
  last=""
  [ -f "$state_file" ] && last="$(cat "$state_file")"
  new_state="${HEAD_SHA} ${EVENT}"

  if [ "$new_state" = "$last" ]; then
    return 0
  fi

  printf '%s' "$new_state" > "$state_file"

  local short_head line
  short_head="${HEAD_SHA:0:8}"
  if [ "$EVENT" = "check-failed" ] || [ "$EVENT" = "check-cancelled" ]; then
    line="ACTION pr=${n} event=${EVENT} checks=\"${CHECK_NAMES}\" head=${short_head}"
  else
    line="ACTION pr=${n} event=${EVENT} head=${short_head}"
  fi
  ACTIONS="${ACTIONS}${line}
"
  ACTION_COUNT=$((ACTION_COUNT + 1))
}

# ---------------------------------------------------------------------------
# run_poll — one full poll cycle. Populates ACTIONS/ACTION_COUNT/
# PENDING_COUNT/TOTAL_PRS/TOTAL_CALLS/FAILED_CALLS (all globals, reset at
# the top of each call).
# ---------------------------------------------------------------------------
run_poll() {
  ACTIONS=""
  ACTION_COUNT=0
  PENDING_COUNT=0
  TOTAL_PRS=0
  TOTAL_CALLS=0
  FAILED_CALLS=0

  local pr_json n

  if [ -n "$AGENT" ]; then
    local list_json="" list_ok=1
    TOTAL_CALLS=$((TOTAL_CALLS + 1))
    if ! list_json="$(fetch_agent_list "$AGENT")"; then
      FAILED_CALLS=$((FAILED_CALLS + 1))
      list_ok=0
    fi

    if [ "$list_ok" = "1" ]; then
      local current_numbers known
      current_numbers="$(printf '%s' "$list_json" | jq -r '.[].number' | sort -n)"

      while IFS= read -r n; do
        [ -z "$n" ] && continue
        pr_json="$(printf '%s' "$list_json" | jq -c --argjson n "$n" '.[] | select(.number == $n)')"
        process_pr "$n" "$pr_json"
      done <<EOF
$current_numbers
EOF

      known=""
      [ -f "$KNOWN_FILE" ] && known="$(cat "$KNOWN_FILE")"
      # A vanished-PR `gh pr view` failure (rate limit, transient network,
      # GitHub-side lag) must NOT drop the number from known-prs — otherwise
      # its terminal event (merged/closed) is lost for good instead of being
      # retried on the next poll.
      local still_missing=""
      if [ -n "$known" ]; then
        while IFS= read -r n; do
          [ -z "$n" ] && continue
          if ! printf '%s\n' "$current_numbers" | grep -qx "$n"; then
            TOTAL_CALLS=$((TOTAL_CALLS + 1))
            if pr_json="$(fetch_pr_json "$n")"; then
              process_pr "$n" "$pr_json"
            else
              FAILED_CALLS=$((FAILED_CALLS + 1))
              still_missing="${still_missing}${n}
"
            fi
          fi
        done <<EOF
$known
EOF
      fi

      # sed, not `grep -v`, to drop blank lines: grep exits 1 (via
      # pipefail, that would abort the whole poll under `set -e`) when every
      # PR is accounted for and current_numbers/still_missing are both
      # empty — a normal, expected steady state, not a failure.
      { printf '%s\n' "$current_numbers"; printf '%s' "$still_missing"; } \
        | sed '/^$/d' | sort -nu > "$KNOWN_FILE"
    fi
  else
    for n in "${PRS[@]}"; do
      TOTAL_CALLS=$((TOTAL_CALLS + 1))
      if pr_json="$(fetch_pr_json "$n")"; then
        process_pr "$n" "$pr_json"
      else
        FAILED_CALLS=$((FAILED_CALLS + 1))
      fi
    done
  fi
}

# ---------------------------------------------------------------------------
main() {
  require_gh; require_jq

  AGENT=""
  PRS=()
  INTERVAL=120
  MAX_WAIT=3300
  ONCE=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) AGENT="$2"; shift 2 ;;
      --interval) INTERVAL="$2"; shift 2 ;;
      --max-wait) MAX_WAIT="$2"; shift 2 ;;
      --once) ONCE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; while [ $# -gt 0 ]; do PRS+=("$1"); shift; done ;;
      -*) die "unknown flag $1" ;;
      *) PRS+=("$1"); shift ;;
    esac
  done

  if [ -n "$AGENT" ] && [ "${#PRS[@]}" -gt 0 ]; then
    die "pass either --agent NAME or explicit PR numbers, not both"
  fi
  if [ -z "$AGENT" ] && [ "${#PRS[@]}" -eq 0 ]; then
    usage >&2
    die "pass either --agent NAME or at least one PR number"
  fi

  local watch_id joined
  if [ -n "$AGENT" ]; then
    watch_id="agent-$(sanitize_id "$AGENT")"
  else
    joined="$(printf '%s' "${PRS[*]}" | tr ' ' '-')"
    watch_id="prs-$(sanitize_id "$joined")"
  fi
  STATE_DIR="${TMPDIR:-/tmp}/pr-watch-${watch_id}"
  KNOWN_FILE="$STATE_DIR/known-prs"
  mkdir -p "$STATE_DIR"

  local start_ts elapsed
  start_ts="$(date +%s)"

  while :; do
    run_poll

    if [ "$TOTAL_CALLS" -gt 0 ] && [ "$FAILED_CALLS" -eq "$TOTAL_CALLS" ]; then
      echo "ERROR pr-watch: all ${TOTAL_CALLS} gh call(s) failed this poll — see WARN lines above" >&2
      exit 2
    fi

    if [ "$ACTION_COUNT" -gt 0 ]; then
      printf '%s' "$ACTIONS"
      exit 10
    fi

    if [ "$ONCE" = "1" ]; then
      echo "OK ${TOTAL_PRS} PRs, none need action (pending=${PENDING_COUNT})"
      exit 0
    fi

    elapsed=$(( $(date +%s) - start_ts ))
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
      echo "IDLE pr-watch: no actionable events after ${elapsed}s (max-wait=${MAX_WAIT}s), ${TOTAL_PRS} PRs polled"
      exit 0
    fi

    sleep "$INTERVAL"
  done
}

# Allow sourcing (e.g. from the test harness) without executing main.
if [ "${PR_WATCH_SH_SOURCED:-0}" != "1" ]; then
  main "$@"
fi
