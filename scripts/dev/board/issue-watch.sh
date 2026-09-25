#!/usr/bin/env bash
# issue-watch.sh — deterministic GitHub Issues watcher for a lane agent.
#
# Purpose: today a lane agent only learns about new work when it finishes a
# ticket and runs `board.sh next`. An operator-filed issue with no `lane:*`
# label (e.g. a P0 filed from a phone screenshot) is invisible to
# `board.sh next` (it requires `lane:bug`/`lane:feature`) and nobody notices
# until someone happens to look. This script polls `gh api` for that state
# and prints AT MOST a few short lines only when something changed that the
# agent needs to act on — it never dumps raw JSON.
#
# This watches ISSUES only. PR/CI watching is `pr-watch.sh` — do not
# duplicate that here.
#
# Usage:
#   issue-watch.sh --agent <NAME> [--lane bug|feature|prd] [--interval SEC=60]
#                   [--once] [--state-dir DIR]
#
#   --agent NAME    This agent's name, e.g. C-BUGFIX-136d. Selects the
#                    `agent:<NAME>` label for the ISSUE-EVENT scan.
#   --lane bug|feature|prd
#                    Enables the QUEUE scan for `lane:<LANE>` issues. Omit to
#                    skip QUEUE entirely (NEW-ISSUE and ISSUE-EVENT still run).
#                    Must mirror board.sh's VALID_LANES minus release (which
#                    doesn't watch the issue queue) — every lane agent that
#                    does runs `watch --lane <l>` (agent-protocol.md).
#   --interval SEC   Seconds between polls in loop mode (default 60, floor 15
#                    — a smaller value hot-loops gh api calls).
#   --once           Poll exactly once instead of looping, then exit 0.
#   --state-dir DIR  Use DIR verbatim instead of the default
#                    ${BOARD_WATCH_DIR:-${TMPDIR:-/tmp}/board-issue-watch}/<agent>.
#
# Designed to run under Claude Code's Monitor tool: every stdout line is an
# event the calling agent should read; keep stdout to actionable lines only.
# Re-arm on expiry by invoking again — state is persisted to disk under
# STATE_DIR, so a fresh process resumes exactly where the last one left off.
#
# Event formats (stable, grep-able — document any change here):
#
#   NEW-ISSUE #<n> [<labels-csv-or-"no labels">] <title≤90>
#     An open, non-PR issue created in the last 48h with NO `lane:*` label
#     (labels in intake.excludeLabels excluded). Emitted once per issue number, ever
#     (dedup file, never re-armed). ACTION: intake it — adopt into a lane per
#     that lane's SKILL.md §2 (add lane:*/P<n>/state:backlog, or close dead).
#
#   QUEUE #<n> P<x> <title≤90>
#   QUEUE-P0 #<n> P0 <title≤90>
#     A new open, unclaimed (no `agent:*` label) issue in `lane:<LANE>` that
#     was not present at baseline. Only scanned when --lane is given. P<x> is
#     the issue's P0-P3 label if present, else "?". P0 uses the QUEUE-P0
#     prefix so it greps separately from routine queue growth. ACTION: note
#     it; take it via `board.sh next` once the current ticket is done — a P0
#     preempts the current ticket immediately (see the lane's SKILL.md).
#
#   ISSUE-EVENT #<n> <change>[; <change>...]
#     For issues labeled `agent:<NAME>` (this agent's own claimed issues).
#     <change> is one or more of, joined with "; ":
#       closed                        state open -> closed
#       (a reopened issue is not reported: closed claims leave the open-only
#        scan, so a reopen is a fresh first sighting, silently baselined)
#       +<k> comment(s) from <login>  comments count rose by <k>; <login> is
#                                      the last comment's author (never the
#                                      comment body/text — a watcher's output
#                                      must not carry user-written content)
#       labels +<a>,<b> -<c>          label set changed; +added, -removed,
#                                      either side omitted if empty
#       unclaimed (agent:<NAME> removed)
#                                      this issue vanished from the claimed
#                                      scan (fetch_claimed only returns OPEN
#                                      agent:<NAME>-labeled issues, so both a
#                                      close and a label removal make an issue
#                                      vanish from it the same way) and an
#                                      individual lookup (`gh api
#                                      repos/<repo>/issues/<n>`) confirmed it
#                                      is still open — so the label is what
#                                      changed, not the state. Diffed against
#                                      stored state, not against a row in the
#                                      current fetch (there isn't one). The
#                                      issue's stored state is deleted right
#                                      after so a future reclaim starts a
#                                      fresh baseline instead of diffing
#                                      against stale pre-removal state.
#       closed                        (also reachable this way) the same
#                                      vanished-from-scan case, but the
#                                      individual lookup found it CLOSED
#                                      instead of unclaimed — reported as
#                                      plain `closed`, identically to the
#                                      in-band open->closed transition above,
#                                      and its stored state is deleted the
#                                      same way. This is now the ONLY path
#                                      that reports a claimed issue closing:
#                                      since fetch_claimed only ever returns
#                                      state=open rows, the in-band
#                                      state-field comparison above can no
#                                      longer observe a close directly.
#     Reported only for an issue this watch has already seen at least once
#     (a brand-new agent:<NAME> label appearing after baseline is recorded
#     silently on first sight — there's no prior state to diff against, so
#     nothing is invented). ACTION: read it (screenshots included via
#     `issue-fetch.sh <n>`).
#
#   WATCH-ARMED agent=<A> lane=<L|none> claimed=<n> untriaged=<n> queue=<n>
#     Printed once per STATE_DIR, the first time EVERY enabled scan succeeds
#     in the same poll. Nothing else is printed on that poll — this is the
#     baseline. `queue` is always 0 when --lane was not given.
#
#   WATCH-ERROR <what> failed: <first stderr line>
#     A `gh api` call in this poll failed. Printed to STDOUT (not stderr) so
#     the calling agent's Monitor session actually sees it — unlike
#     pr-watch.sh's WARN lines, which go to stderr. The poll NEVER exits on
#     this: the failing scan is simply skipped for this poll and retried next
#     interval (or, under --once, the process still exits 0). If this
#     happened during baseline, WATCH-ARMED is withheld until a poll where
#     every enabled scan succeeds together. While the first full baseline is
#     incomplete (some scan still failing on every poll so far), any item
#     that scan's peers see is baselined silently, not announced, exactly
#     like ordinary first-poll baselining — this is a narrow window that only
#     opens when a scan is failing at startup, and it closes as soon as every
#     scan succeeds together and WATCH-ARMED fires.
#
#   WATCH-ERROR issue #<n> lookup failed: <first stderr line>
#     A claimed issue #<n> vanished from the (open-only) claimed scan and the
#     individual `gh api repos/<repo>/issues/<n>` lookup used to tell
#     `closed` apart from `unclaimed` (see both above) itself failed. The
#     issue's stored state file is KEPT (not deleted) so this is retried on
#     the next poll — never guessed as either outcome.
#
# Dedup / state (all under STATE_DIR, one directory per --agent):
#   .armed              baseline-complete marker (see WATCH-ARMED above)
#   new-<n>             NEW-ISSUE #<n> already handled (baseline or reported)
#   queue-<n>           QUEUE #<n> already handled (baseline or reported)
#   issue-<n>.state     last-seen "state=<open|closed> comments=<c> labels=<csv>"
#                        for a claimed issue, used to diff ISSUE-EVENT; deleted
#                        when the issue drops out of the claimed scan entirely
#                        and the individual lookup resolves it (`closed` or
#                        `unclaimed` above); KEPT if that lookup itself fails
#                        (`WATCH-ERROR issue #<n> lookup failed` above)
#
# REPO defaults to `gh repo view --json nameWithOwner --jq .nameWithOwner`
# (this checkout's own remote); override with BOARD_REPO=owner/repo (used by
# the test harness, and available as a manual escape hatch).
#
# REST shapes this relies on (GitHub issues API):
#   gh api repos/<owner>/<repo>/issues
#     -> [{"number":1,"title":"...","state":"open","created_at":"...","comments":0,
#          "labels":[{"name":"...", ...}], ...}]   (pull_request key ABSENT on an issue)
#   on a PR the same endpoint returns "pull_request": {...} — an OBJECT, not a
#   boolean, so this script only ever tests `.pull_request == null`.
#
# Portability: macOS bash 3.2 (no `declare -A`, no GNU-only flags, no
# `timeout` binary) + Linux.
set -uo pipefail

SCRIPT_NAME="issue-watch.sh"
# shellcheck disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# Labels that mark an issue as not-work (locks, meta issues); never announced as NEW-ISSUE.
INTAKE_EXCLUDE_JSON="$(lanes_cfg '(.intake.excludeLabels // []) | tojson' '[]')"

usage() {
  cat <<'EOF'
issue-watch.sh --agent <NAME> [--lane bug|feature|prd] [--interval SEC=60] [--once] [--state-dir DIR]

See the header comment in this file for the full event/dedup contract.
EOF
}



resolve_repo() {
  if [ -n "${BOARD_REPO:-}" ]; then
    REPO="$BOARD_REPO"
    return 0
  fi
  REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)"
  [ -n "$REPO" ] || die "could not resolve this repo's owner/name via 'gh repo view' — set BOARD_REPO=owner/repo to override"
}

# ---------------------------------------------------------------------------
# fetch_fresh — open, non-PR issues created in the last 48h with no lane:*
# label and none of intake.excludeLabels. TSV: number, labels-csv (literal "none" when
# empty — bash's `read -r` with IFS=<tab> squeezes consecutive tab
# delimiters the same as spaces, since tab is IFS whitespace regardless of
# what else is in IFS; an empty middle field would silently shift every
# field after it, the same reason wt-clean.sh's worktree_tsv never emits an
# empty branch field either), title.
# ---------------------------------------------------------------------------
fetch_fresh() {
  # `gh api --jq` takes no --arg, so the exclusion list is embedded as a JSON
  # literal produced by jq's own tojson (every string escaped).
  gh api -X GET "repos/${REPO}/issues" -f state=open -f per_page=100 \
    -f sort=created -f direction=desc \
    --jq '.[] | select(.pull_request == null) | select(.created_at > (now - 172800 | todate)) | select([.labels[].name | startswith("lane:")] | any | not) | select([.labels[].name] | any(. as $n | '"$INTAKE_EXCLUDE_JSON"' | index($n)) | not) | (([.labels[].name]|join(",")) as $l | if $l == "" then "none" else $l end) as $labels | "\(.number)\t\($labels)\t\(.title[0:90])"'
}

# ---------------------------------------------------------------------------
# fetch_queue <lane> — open, non-PR, unclaimed (no agent:*) issues in
# lane:<lane>. TSV: number, priority (P0-P3 or "?"), title.
# ---------------------------------------------------------------------------
fetch_queue() {
  local lane="$1"
  gh api -X GET "repos/${REPO}/issues" -f state=open -f "labels=lane:${lane}" -f per_page=100 \
    --jq '.[] | select(.pull_request == null) | select([.labels[].name | startswith("agent:")] | any | not) | "\(.number)\t\(([.labels[].name | select(test("^P[0-9]$"))] | first) // "?")\t\(.title[0:90])"'
}

# ---------------------------------------------------------------------------
# fetch_claimed <agent> — every OPEN non-PR issue labeled agent:<agent>. TSV:
# number, state, comments, labels-csv (sorted), title.
#
# state=open, not state=all: `gh api`'s issues list has no cursor/since
# param, so "all" pages back through this agent's ENTIRE lifetime claim
# history in `created`-descending order — past 100 lifetime claims the
# oldest still-open ones fall off the (unpaginated) first page and read as
# "gone", which the caller's diff against stored issue-<n>.state files would
# misreport as `unclaimed` for an issue that never changed at all. Restricting
# to state=open removes closed issues from the page entirely (they don't
# need to compete for page-1 space with genuinely live claims), and
# `--paginate` follows every page so >100 *open* claims still all come back.
# A closed or unlabeled issue that drops out of THIS scan is diagnosed by
# looking it up individually (see the stale-state-file loop below) rather
# than inferred from its absence here.
# ---------------------------------------------------------------------------
fetch_claimed() {
  local agent="$1"
  gh api -X GET "repos/${REPO}/issues" --paginate -f state=open -f "labels=agent:${agent}" -f per_page=100 \
    --jq '.[] | select(.pull_request == null) | "\(.number)\t\(.state)\t\(.comments)\t\([.labels[].name]|sort|join(","))\t\(.title[0:90])"'
}

# ---------------------------------------------------------------------------
# label_diff <old_csv> <new_csv> — sets ADDED/REMOVED (sorted comma lists,
# empty string if none). Not `local`-scoped in ADDED/REMOVED: plain function
# call, caller reads the globals directly.
# ---------------------------------------------------------------------------
label_diff() {
  local old="$1" new="$2"
  ADDED="$(comm -13 <(printf '%s' "$old" | tr ',' '\n' | sort -u) <(printf '%s' "$new" | tr ',' '\n' | sort -u) | sed '/^$/d' | paste -sd, -)"
  REMOVED="$(comm -23 <(printf '%s' "$old" | tr ',' '\n' | sort -u) <(printf '%s' "$new" | tr ',' '\n' | sort -u) | sed '/^$/d' | paste -sd, -)"
}

# ---------------------------------------------------------------------------
# run_poll — one full poll cycle. Appends to the global EVENTS accumulator
# (already-newline-terminated lines). Reads/writes STATE_DIR.
# ---------------------------------------------------------------------------
run_poll() {
  EVENTS=""

  local fresh_ok=1 queue_ok=1 claimed_ok=1
  local fresh_raw="" queue_raw="" claimed_raw=""
  local fresh_count=0 queue_count=0 claimed_count=0
  local errfile msg

  errfile="$(mktemp)"
  if fresh_raw="$(fetch_fresh 2>"$errfile")"; then
    :
  else
    fresh_ok=0
    msg="$(head -1 "$errfile")"
    EVENTS="${EVENTS}WATCH-ERROR fresh-issue scan failed: ${msg}
"
  fi
  rm -f "$errfile"

  if [ -n "$LANE" ]; then
    errfile="$(mktemp)"
    if queue_raw="$(fetch_queue "$LANE" 2>"$errfile")"; then
      :
    else
      queue_ok=0
      msg="$(head -1 "$errfile")"
      EVENTS="${EVENTS}WATCH-ERROR queue scan (lane:${LANE}) failed: ${msg}
"
    fi
    rm -f "$errfile"
  fi

  errfile="$(mktemp)"
  if claimed_raw="$(fetch_claimed "$AGENT" 2>"$errfile")"; then
    :
  else
    claimed_ok=0
    msg="$(head -1 "$errfile")"
    EVENTS="${EVENTS}WATCH-ERROR claimed-issue scan failed: ${msg}
"
  fi
  rm -f "$errfile"

  local first=0
  [ -f "$ARMED_FILE" ] || first=1

  # all_ok gates WATCH-ARMED below: the baseline only arms on a poll where
  # every enabled scan succeeds together (see WATCH-ERROR in the header).
  local all_ok=1
  [ "$fresh_ok" = "1" ] || all_ok=0
  if [ -n "$LANE" ]; then [ "$queue_ok" = "1" ] || all_ok=0; fi
  [ "$claimed_ok" = "1" ] || all_ok=0

  if [ "$fresh_ok" = "1" ]; then
    local n labels title marker
    while IFS=$'\t' read -r n labels title; do
      [ -z "$n" ] && continue
      fresh_count=$((fresh_count + 1))
      marker="$STATE_DIR/new-${n}"
      [ -e "$marker" ] && continue
      : > "$marker"
      [ "$first" = "1" ] && continue
      [ "$labels" = "none" ] && labels=""
      EVENTS="${EVENTS}NEW-ISSUE #${n} [${labels:-no labels}] ${title}
"
    done <<EOF
$fresh_raw
EOF
  fi

  if [ -n "$LANE" ] && [ "$queue_ok" = "1" ]; then
    local n prio title marker
    while IFS=$'\t' read -r n prio title; do
      [ -z "$n" ] && continue
      queue_count=$((queue_count + 1))
      marker="$STATE_DIR/queue-${n}"
      [ -e "$marker" ] && continue
      : > "$marker"
      [ "$first" = "1" ] && continue
      if [ "$prio" = "P0" ]; then
        EVENTS="${EVENTS}QUEUE-P0 #${n} P0 ${title}
"
      else
        EVENTS="${EVENTS}QUEUE #${n} ${prio} ${title}
"
      fi
    done <<EOF
$queue_raw
EOF
  fi

  if [ "$claimed_ok" = "1" ]; then
    local n state comments labels title state_file prev
    local prev_state prev_comments prev_labels changes delta last_login
    while IFS=$'\t' read -r n state comments labels title; do
      [ -z "$n" ] && continue
      claimed_count=$((claimed_count + 1))
      state_file="$STATE_DIR/issue-${n}.state"
      prev=""
      [ -f "$state_file" ] && prev="$(cat "$state_file")"
      printf '%s' "state=${state} comments=${comments} labels=${labels}" > "$state_file"

      [ "$first" = "1" ] && continue
      [ -z "$prev" ] && continue

      prev_state="$(printf '%s' "$prev" | sed -n 's/^state=\([^ ]*\) .*/\1/p')"
      prev_comments="$(printf '%s' "$prev" | sed -n 's/.*comments=\([0-9]*\) .*/\1/p')"
      prev_labels="$(printf '%s' "$prev" | sed -n 's/.*labels=\(.*\)$/\1/p')"

      changes=""
      if [ "$prev_state" = "open" ] && [ "$state" = "closed" ]; then
        changes="${changes}closed; "
      elif [ "$prev_state" = "closed" ] && [ "$state" = "open" ]; then
        changes="${changes}reopened; "
      fi

      if [ -n "$prev_comments" ] && [ "$comments" -gt "$prev_comments" ] 2>/dev/null; then
        delta=$((comments - prev_comments))
        # The issues comments endpoint has no sort param and defaults to a
        # 30-item page, so `.[-1]` of the default page is wrong once an issue
        # has more than 30 comments — it silently returns the last comment of
        # PAGE ONE, not the last comment overall. Fetch the Nth comment
        # directly instead: page=$comments (the issue's CURRENT comment
        # count) with per_page=1 lands exactly on the newest comment.
        last_login="$(gh api "repos/${REPO}/issues/${n}/comments?per_page=1&page=${comments}" --jq '.[0].user.login // "unknown"' 2>/dev/null)"
        [ -z "$last_login" ] && last_login="unknown"
        changes="${changes}+${delta} comment(s) from ${last_login}; "
      fi

      if [ "$labels" != "$prev_labels" ]; then
        label_diff "$prev_labels" "$labels"
        local ldesc=""
        [ -n "$ADDED" ] && ldesc="+${ADDED}"
        if [ -n "$REMOVED" ]; then
          if [ -n "$ldesc" ]; then ldesc="${ldesc} -${REMOVED}"; else ldesc="-${REMOVED}"; fi
        fi
        [ -n "$ldesc" ] && changes="${changes}labels ${ldesc}; "
      fi

      changes="${changes%; }"
      if [ -n "$changes" ]; then
        EVENTS="${EVENTS}ISSUE-EVENT #${n} ${changes}
"
      fi
    done <<EOF
$claimed_raw
EOF

    # Diff stored issue-<n>.state files against the just-fetched OPEN claimed
    # set: fetch_claimed only returns OPEN issues CURRENTLY labeled
    # agent:${AGENT} (see its header), so BOTH a close and an agent:<NAME>
    # label removal make an issue vanish from claimed_raw the same way — it
    # never reaches the loop above at all. Never guess which one happened:
    # look the issue up individually. Only runs when the claimed scan itself
    # succeeded (claimed_ok=1, checked by the caller of this block) — a
    # FAILED gh call must never be read as "everything unclaimed".
    local current_nums="$STATE_DIR/.current-claimed"
    printf '%s\n' "$claimed_raw" | awk -F'\t' 'NF{print $1}' > "$current_nums"
    local sf stale_n lookup lstate lerrfile lmsg
    for sf in "$STATE_DIR"/issue-*.state; do
      [ -e "$sf" ] || continue
      stale_n="$(basename "$sf")"
      stale_n="${stale_n#issue-}"
      stale_n="${stale_n%.state}"
      grep -qxF "$stale_n" "$current_nums" 2>/dev/null && continue

      lerrfile="$(mktemp)"
      lookup="$(gh api "repos/${REPO}/issues/${stale_n}" --jq '"\(.state)\t\([.labels[].name]|sort|join(","))"' 2>"$lerrfile")"
      if [ -z "$lookup" ]; then
        lmsg="$(head -1 "$lerrfile")"
        rm -f "$lerrfile"
        # A deleted/transferred issue 404s forever; report it once and stop
        # tracking it instead of emitting a WATCH-ERROR on every poll.
        case "$lmsg" in
          *"Not Found"*|*"HTTP 404"*|*"HTTP 410"*)
            [ "$first" != "1" ] && EVENTS="${EVENTS}ISSUE-EVENT #${stale_n} gone (${lmsg})
"
            rm -f "$sf"
            continue ;;
        esac
        EVENTS="${EVENTS}WATCH-ERROR issue #${stale_n} lookup failed: ${lmsg}
"
        continue
      fi
      rm -f "$lerrfile"
      lstate="${lookup%%$'\t'*}"

      if [ "$lstate" = "closed" ]; then
        if [ "$first" != "1" ]; then
          EVENTS="${EVENTS}ISSUE-EVENT #${stale_n} closed
"
        fi
      else
        if [ "$first" != "1" ]; then
          EVENTS="${EVENTS}ISSUE-EVENT #${stale_n} unclaimed (agent:${AGENT} removed)
"
        fi
      fi
      rm -f "$sf"
    done
    rm -f "$current_nums"
  fi

  if [ "$first" = "1" ] && [ "$all_ok" = "1" ]; then
    : > "$ARMED_FILE"
    EVENTS="${EVENTS}WATCH-ARMED agent=${AGENT} lane=${LANE:-none} claimed=${claimed_count} untriaged=${fresh_count} queue=${queue_count}
"
  fi
}

# ---------------------------------------------------------------------------
main() {
  require_gh
  require_jq

  AGENT=""
  LANE=""
  INTERVAL=60
  ONCE=0
  STATE_DIR_OVERRIDE=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) AGENT="${2:-}"; shift 2 ;;
      --lane) LANE="${2:-}"; shift 2 ;;
      --interval) INTERVAL="${2:-}"; shift 2 ;;
      --once) ONCE=1; shift ;;
      --state-dir) STATE_DIR_OVERRIDE="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "unknown argument: $1" ;;
    esac
  done

  [ -n "$AGENT" ] || { usage >&2; die "--agent NAME is required"; }
  # Mirrors board.sh's VALID_LANES ("bug feature release prd") for the lanes
  # that actually run `watch --lane <l>` — release doesn't (it works off
  # `deploy-queue`, not the issue queue), so it stays out of this list too.
  case "$LANE" in
    ''|bug|feature|prd) ;;
    *)
      usage >&2
      die "--lane must be one of: bug feature prd — got: ${LANE}"
      ;;
  esac
  case "$INTERVAL" in
    ''|*[!0-9]*) usage >&2; die "--interval must be a positive integer, got: ${INTERVAL}" ;;
  esac
  if [ "$INTERVAL" -lt 15 ]; then
    usage >&2
    die "--interval must be at least 15 seconds, got: ${INTERVAL} — a smaller value hot-loops gh api calls"
  fi

  resolve_repo

  if [ -n "$STATE_DIR_OVERRIDE" ]; then
    STATE_DIR="$STATE_DIR_OVERRIDE"
  else
    STATE_DIR="${BOARD_WATCH_DIR:-${TMPDIR:-/tmp}/board-issue-watch}/${AGENT}"
  fi
  mkdir -p "$STATE_DIR"
  ARMED_FILE="$STATE_DIR/.armed"

  while :; do
    run_poll

    if [ -n "$EVENTS" ]; then
      printf '%s' "$EVENTS"
    fi

    if [ "$ONCE" = "1" ]; then
      exit 0
    fi

    sleep "$INTERVAL"
  done
}

# Allow sourcing (e.g. from the test harness) without executing main.
if [ "${ISSUE_WATCH_SH_SOURCED:-0}" != "1" ]; then
  main "$@"
fi
