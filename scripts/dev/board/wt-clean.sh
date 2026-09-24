#!/usr/bin/env bash
# wt-clean.sh — deterministically remove an agent's git worktrees once their
# PR has MERGED, safely. Companion to board.sh (same `gh`-shelling, no
# hand-rolled REST client, macOS bash 3.2 + Linux portable: no `declare -A`,
# no GNU-only flags, no `timeout`).
#
# Usage:
#   wt-clean.sh --pr <n> [<n>...]   [--dry-run]
#   wt-clean.sh --agent <NAME>      [--dry-run]
#   wt-clean.sh --all-merged        [--dry-run]
#
#   --pr <n>...    Consider only the worktree(s) whose branch maps to PR <n>
#                  (one or more PR numbers after a single --pr).
#   --agent <NAME> Consider merged PRs labeled agent:<NAME>
#                  (`gh pr list --state merged --label agent:<NAME>`).
#   --all-merged   Consider every non-main worktree whose branch maps to a
#                  MERGED PR.
#   --dry-run      Print what would happen; no worktree/branch is touched.
#
# Safety rules (all mandatory, all enforced in code — not just documented):
#   - The main checkout (resolved via `git rev-parse --git-common-dir`'s
#     parent) is NEVER considered, NEVER printed, NEVER touched.
#   - A `locked` worktree (per `git worktree list --porcelain`) is always
#     SKIPped — it belongs to a live session.
#   - PRs here are SQUASH-merged, so ancestry to origin/main is never used to
#     judge SAFETY of removal. Safe iff PR state is MERGED AND (worktree HEAD
#     == PR headRefOid, OR HEAD is an ancestor of the fetched PR head). A
#     missing PR-head object (`git fetch origin refs/pull/<n>/head` fails)
#     is reported as SKIP pr-head-unavailable, never silently treated as
#     "not an ancestor".
#   - --pr/--agent MATCHING (deciding which worktrees belong to a given PR at
#     all, before any of the safety checks above run) considers EVERY
#     non-main worktree, not just the first one found by branch name — this
#     is what lets a subagent's own throwaway-named worktree be discovered,
#     as long as it is genuinely ON the PR: a worktree's HEAD is removed only
#     when it is EXACTLY the merged PR head, or the worktree is ON the PR's
#     own branch. Concretely, a worktree matches a PR iff (a) its branch
#     (local name, or its upstream's remote branch name) equals the PR's
#     head branch, or (b) its HEAD == the PR's headRefOid exactly (this is
#     also how a detached-HEAD worktree can match — see the exact-HEAD rule
#     below, which applies to matching, not just safety). A worktree matched
#     by neither rule is simply not considered for that PR — no output for
#     it in --pr mode.
#       There is deliberately NO ancestry match ("HEAD is an ancestor of the
#     PR head"): ancestry cannot tell "this worktree IS the PR" from "this
#     worktree is another, still-open branch that was merged INTO this PR"
#     (a stacked PR's base), and matching it would `branch -D` a live branch.
#     A deleting tool matches only on exact evidence — branch identity or
#     exact HEAD equality — never a genealogy guess.
#   - A worktree with tracked modifications or untracked non-ignored files
#     (`git status --porcelain` non-empty) is SKIPped as dirty. Dirty paths
#     under deploy.journalDir (.claude/agent-lanes.json) get an extra warning:
#     release worktrees hold un-committed deploy journals.
#   - `git worktree remove` is NEVER called with `--force`.
#   - The local branch is deleted with `git branch -D <branch>` only when
#     its current tip equals the worktree HEAD already verified safe above
#     (protects against a branch that moved/is shared since enumeration).
#   - Detached-HEAD worktrees match a candidate PR only by exact
#     HEAD == PR headRefOid; otherwise SKIP detached.
#   - No silent failures: every skip/keep/error names its reason on stdout
#     (SKIP/KEEP/REMOVED/WOULD-REMOVE lines) or stderr (ERROR/note lines).
#
# Output (one line per considered worktree, plus a final summary):
#   REMOVED <path> (#<n>, branch <b>)
#   WOULD-REMOVE <path> (#<n>, branch <b>)      [--dry-run only]
#   SKIP <reason> <path>                        reason in:
#     locked | detached | dirty (<k> files) | pr-head-unavailable |
#     ahead-of-pr | no-pr | closed-unmerged
#   KEEP open-pr #<n> <path>
#   SUMMARY removed=<a> skipped=<b> kept=<c>
#
# Exit codes:
#   0  ran to completion (individual SKIP/KEEP outcomes are not failures)
#   2  usage error, or a gh/git hard failure (named on stderr as an ERROR
#      line) — e.g. `gh` not on PATH, `gh pr view` erroring, `git worktree
#      remove` failing
#
# Deliberately NOT `set -e`: this script's control flow depends heavily on
# gh/git calls that are *expected* to fail in normal operation (no upstream
# configured, PR head ref pruned after merge, etc.) and their exit codes are
# checked explicitly — see board.test.sh's own note on this same tradeoff
# for a script of comparable shape.
set -uo pipefail

SCRIPT_NAME="wt-clean.sh"
# shellcheck disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"


usage() {
  echo "Usage: ${SCRIPT_NAME} (--pr <n>... | --agent <NAME> | --all-merged) [--dry-run]" >&2
}



require_git() {
  command -v git >/dev/null 2>&1 || die "'git' not found on PATH"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
}

# worktree_tsv — one line per worktree from `git worktree list --porcelain`:
#   <path>\t<head-sha>\t<branch-or-DETACHED>\t<locked:0|1>
worktree_tsv() {
  git -C "$MAIN_CHECKOUT" worktree list --porcelain | awk '
    function emit() {
      if (path != "") {
        br = (branch == "") ? "DETACHED" : branch
        printf "%s\t%s\t%s\t%s\n", path, head, br, locked
      }
    }
    BEGIN { path = ""; head = ""; branch = ""; locked = 0 }
    /^worktree / { emit(); path = $0; sub(/^worktree /, "", path); head = ""; branch = ""; locked = 0; next }
    /^HEAD /     { head = $0; sub(/^HEAD /, "", head); next }
    /^branch /   { branch = $0; sub(/^branch refs\/heads\//, "", branch); next }
    /^detached/  { branch = ""; next }
    /^locked/    { locked = 1; next }
    END { emit() }
  '
}

# find_all_worktrees_for_pr <pr-num> <pr-state> <pr-branch> <pr-head-sha> —
# scans EVERY non-main worktree (locked ones INCLUDED, so a locked match
# still reports SKIP locked rather than being silently invisible) and prints
# one "<path>\t<head>\t<branch>\t<locked>" line per worktree that matches, by
# either of:
#   (a) branch (local name, or its upstream's remote branch name) ==
#       <pr-branch>
#   (b) HEAD == <pr-head-sha> exactly — this is also how a detached-HEAD
#       worktree can match (process_worktree's own detached-HEAD safety rule
#       requires this same exact equality, so a detached worktree can never
#       be removed on anything looser).
# <pr-num> and <pr-state> are accepted for call-site symmetry with the other
# per-PR helpers but are not used for matching. A worktree whose HEAD is
# merely an ANCESTOR of <pr-head-sha>, on some other branch, is deliberately
# NOT matched (see "no ancestry match" in the header). A worktree matched by
# neither rule here is simply not considered for this PR at all.
find_all_worktrees_for_pr() {
  local pr_num="$1" pr_state="$2" target_branch="$3" target_sha="$4"
  local wpath whead wbranch wlocked upstream_full upstream_branch matched

  while IFS=$'\t' read -r wpath whead wbranch wlocked; do
    [ -z "$wpath" ] && continue
    [ "$wpath" = "$MAIN_CHECKOUT" ] && continue

    matched=0

    if [ "$wbranch" != "DETACHED" ]; then
      if [ "$wbranch" = "$target_branch" ]; then
        matched=1
      else
        upstream_full="$(git -C "$wpath" rev-parse --abbrev-ref "${wbranch}@{upstream}" 2>/dev/null)"
        if [ -n "$upstream_full" ]; then
          upstream_branch="${upstream_full#*/}"
          [ "$upstream_branch" = "$target_branch" ] && matched=1
        fi
      fi
    fi

    if [ "$matched" != "1" ] && [ "$whead" = "$target_sha" ]; then
      matched=1
    fi

    [ "$matched" = "1" ] && printf '%s\t%s\t%s\t%s\n' "$wpath" "$whead" "$wbranch" "$wlocked"
  done < <(worktree_tsv)
}

# process_worktree <path> <head> <branch|DETACHED> <locked:0|1> <pr-num>
#                   <pr-state> <pr-head-sha>
# Applies every safety rule above and either removes the worktree (+ branch,
# + prune) or prints a SKIP/KEEP reason. Mutates the global removed/skipped/
# kept/overall_exit counters directly (no return-value plumbing needed).
process_worktree() {
  local wpath="$1" whead="$2" wbranch="$3" wlocked="$4"
  local pr_num="$5" pr_state="$6" pr_head="$7"
  local detached=0
  [ "$wbranch" = "DETACHED" ] && detached=1

  if [ "$wlocked" = "1" ]; then
    echo "SKIP locked $wpath"
    skipped=$((skipped + 1))
    return
  fi

  if [ "$pr_state" = "OPEN" ]; then
    echo "KEEP open-pr #${pr_num} $wpath"
    kept=$((kept + 1))
    return
  fi

  if [ "$pr_state" != "MERGED" ]; then
    echo "SKIP closed-unmerged $wpath"
    skipped=$((skipped + 1))
    return
  fi

  local safe=0
  if [ "$whead" = "$pr_head" ]; then
    safe=1
  elif [ "$detached" = "0" ]; then
    local fetch_rc
    git -C "$wpath" fetch origin "refs/pull/${pr_num}/head" >"$ERRFILE" 2>&1
    fetch_rc=$?
    if [ "$fetch_rc" -ne 0 ]; then
      echo "SKIP pr-head-unavailable $wpath"
      skipped=$((skipped + 1))
      return
    fi
    local fetched_sha
    fetched_sha="$(git -C "$wpath" rev-parse FETCH_HEAD 2>/dev/null)"
    if [ -n "$fetched_sha" ] && git -C "$wpath" merge-base --is-ancestor "$whead" "$fetched_sha" 2>/dev/null; then
      safe=1
    fi
  fi
  # detached + whead != pr_head: safe stays 0 — this branch should be
  # unreachable in practice since find_all_worktrees_for_pr only ever matches
  # a detached worktree on exact head equality, but the check stays explicit
  # so this function never removes a detached worktree by accident.

  if [ "$safe" != "1" ]; then
    echo "SKIP ahead-of-pr $wpath"
    skipped=$((skipped + 1))
    return
  fi

  local dirty_lines dcount
  # --untracked-files=all: without it, an entirely-untracked directory (e.g.
  # a fresh journal directory) collapses to one "?? docs/" line and the
  # journal-path check below never sees the actual nested path.
  dirty_lines="$(git -C "$wpath" status --porcelain --untracked-files=all 2>/dev/null)"
  if [ -n "$dirty_lines" ]; then
    dcount="$(printf '%s\n' "$dirty_lines" | wc -l | tr -d '[:space:]')"
    echo "SKIP dirty (${dcount} files) $wpath"
    printf '%s\n' "$dirty_lines" | head -5 | while IFS= read -r dl; do
      echo "  $dl"
    done
    if printf '%s\n' "$dirty_lines" | grep -qF "${JOURNAL_DIR%/}/"; then
      echo "  NOTE: contains deploy journals, copy them to the main checkout before removing"
    fi
    skipped=$((skipped + 1))
    return
  fi

  if [ "$DRY_RUN" = "1" ]; then
    echo "WOULD-REMOVE $wpath (#${pr_num}, branch ${wbranch})"
    removed=$((removed + 1))
    return
  fi

  local remove_rc
  git -C "$MAIN_CHECKOUT" worktree remove "$wpath" 2>"$ERRFILE"
  remove_rc=$?
  if [ "$remove_rc" -ne 0 ]; then
    echo "ERROR git worktree remove $wpath failed: $(cat "$ERRFILE")" >&2
    overall_exit=2
    return
  fi
  echo "REMOVED $wpath (#${pr_num}, branch ${wbranch})"
  removed=$((removed + 1))

  if [ "$detached" = "0" ]; then
    local branch_tip branch_rc
    branch_tip="$(git -C "$MAIN_CHECKOUT" rev-parse "refs/heads/${wbranch}" 2>/dev/null)"
    if [ "$branch_tip" = "$whead" ]; then
      git -C "$MAIN_CHECKOUT" branch -D "$wbranch" >"$ERRFILE" 2>&1
      branch_rc=$?
      if [ "$branch_rc" -ne 0 ]; then
        echo "ERROR git branch -D $wbranch failed: $(cat "$ERRFILE")" >&2
        overall_exit=2
      fi
    fi
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
MODE=""
DRY_RUN=0
AGENT_NAME=""
REQ_PRS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)
      if [ -n "$MODE" ] && [ "$MODE" != "pr" ]; then
        usage
        die "--pr cannot be combined with --agent/--all-merged"
      fi
      MODE="pr"
      shift
      while [ $# -gt 0 ] && printf '%s' "$1" | grep -Eq '^[0-9]+$'; do
        REQ_PRS+=("$1")
        shift
      done
      [ "${#REQ_PRS[@]}" -gt 0 ] || { usage; die "--pr requires at least one PR number"; }
      ;;
    --agent)
      if [ -n "$MODE" ] && [ "$MODE" != "agent" ]; then
        usage
        die "--agent cannot be combined with --pr/--all-merged"
      fi
      MODE="agent"
      AGENT_NAME="${2:-}"
      [ -n "$AGENT_NAME" ] || { usage; die "--agent requires a NAME"; }
      shift 2
      ;;
    --all-merged)
      if [ -n "$MODE" ] && [ "$MODE" != "all-merged" ]; then
        usage
        die "--all-merged cannot be combined with --pr/--agent"
      fi
      MODE="all-merged"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    *)
      usage
      die "unknown argument: $1"
      ;;
  esac
done

[ -n "$MODE" ] || { usage; die "one of --pr/--agent/--all-merged is required"; }

require_git
require_gh
require_jq

ERRFILE="$(mktemp)"
trap 'rm -f "$ERRFILE"' EXIT
JOURNAL_DIR="$(lanes_cfg '.deploy.journalDir' docs/deployments)"

MAIN_GIT_DIR="$(git rev-parse --path-format=absolute --git-common-dir)"
MAIN_CHECKOUT="$(dirname "$MAIN_GIT_DIR")"

removed=0
skipped=0
kept=0
overall_exit=0

# ---------------------------------------------------------------------------
# Mode dispatch
# ---------------------------------------------------------------------------
if [ "$MODE" = "pr" ]; then
  for prnum in "${REQ_PRS[@]}"; do
    json="$(gh pr view "$prnum" --json number,state,headRefOid,headRefName 2>"$ERRFILE")"
    rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "ERROR gh pr view $prnum failed: $(cat "$ERRFILE")" >&2
      overall_exit=2
      continue
    fi
    pr_state="$(printf '%s' "$json" | jq -r '.state')"
    pr_head="$(printf '%s' "$json" | jq -r '.headRefOid')"
    pr_branch="$(printf '%s' "$json" | jq -r '.headRefName')"

    matches="$(find_all_worktrees_for_pr "$prnum" "$pr_state" "$pr_branch" "$pr_head")"
    if [ -z "$matches" ]; then
      echo "note: no worktree found for PR #$prnum" >&2
      continue
    fi
    while IFS=$'\t' read -r m_path m_head m_branch m_locked; do
      [ -z "$m_path" ] && continue
      process_worktree "$m_path" "$m_head" "$m_branch" "$m_locked" "$prnum" "$pr_state" "$pr_head"
    done <<< "$matches"
  done

elif [ "$MODE" = "agent" ]; then
  json="$(gh pr list --state merged --label "agent:${AGENT_NAME}" --limit 50 \
    --json number,headRefName,headRefOid,state 2>"$ERRFILE")"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ERROR gh pr list --label agent:${AGENT_NAME} failed: $(cat "$ERRFILE")" >&2
    exit 2
  fi
  cnt="$(printf '%s' "$json" | jq 'length')"
  i=0
  while [ "$i" -lt "$cnt" ]; do
    pr_num="$(printf '%s' "$json" | jq -r ".[$i].number")"
    pr_state="$(printf '%s' "$json" | jq -r ".[$i].state")"
    pr_head="$(printf '%s' "$json" | jq -r ".[$i].headRefOid")"
    pr_branch="$(printf '%s' "$json" | jq -r ".[$i].headRefName")"

    matches="$(find_all_worktrees_for_pr "$pr_num" "$pr_state" "$pr_branch" "$pr_head")"
    if [ -z "$matches" ]; then
      echo "note: no worktree found for PR #$pr_num" >&2
      i=$((i + 1))
      continue
    fi
    while IFS=$'\t' read -r m_path m_head m_branch m_locked; do
      [ -z "$m_path" ] && continue
      process_worktree "$m_path" "$m_head" "$m_branch" "$m_locked" "$pr_num" "$pr_state" "$pr_head"
    done <<< "$matches"
    i=$((i + 1))
  done

else # all-merged
  while IFS=$'\t' read -r wpath whead wbranch wlocked; do
    [ -z "$wpath" ] && continue
    [ "$wpath" = "$MAIN_CHECKOUT" ] && continue

    if [ "$wbranch" = "DETACHED" ]; then
      echo "SKIP detached $wpath"
      skipped=$((skipped + 1))
      continue
    fi

    upstream_full="$(git -C "$wpath" rev-parse --abbrev-ref "${wbranch}@{upstream}" 2>/dev/null)"
    upstream_branch=""
    if [ -n "$upstream_full" ]; then
      upstream_branch="${upstream_full#*/}"
      [ "$upstream_branch" = "$wbranch" ] && upstream_branch=""
    fi

    pr_num=""
    pr_state=""
    pr_head=""
    for cand_branch in "$wbranch" "$upstream_branch"; do
      [ -z "$cand_branch" ] && continue
      json="$(gh pr list --state all --head "$cand_branch" \
        --json number,state,headRefOid,headRefName --limit 5 2>"$ERRFILE")"
      rc=$?
      if [ "$rc" -ne 0 ]; then
        echo "ERROR gh pr list --head $cand_branch failed: $(cat "$ERRFILE")" >&2
        overall_exit=2
        continue
      fi
      cnt="$(printf '%s' "$json" | jq 'length')"
      if [ "$cnt" -gt 0 ]; then
        pr_num="$(printf '%s' "$json" | jq -r '.[0].number')"
        pr_state="$(printf '%s' "$json" | jq -r '.[0].state')"
        pr_head="$(printf '%s' "$json" | jq -r '.[0].headRefOid')"
        break
      fi
    done

    if [ -z "$pr_num" ]; then
      echo "SKIP no-pr $wpath"
      skipped=$((skipped + 1))
      continue
    fi

    process_worktree "$wpath" "$whead" "$wbranch" "$wlocked" "$pr_num" "$pr_state" "$pr_head"
  done < <(worktree_tsv)
fi

if [ "$DRY_RUN" != "1" ]; then
  git -C "$MAIN_CHECKOUT" worktree prune >/dev/null 2>"$ERRFILE" || \
    echo "note: git worktree prune failed: $(cat "$ERRFILE")" >&2
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "SUMMARY would_remove=${removed} skipped=${skipped} kept=${kept} (dry run — nothing removed)"
else
  echo "SUMMARY removed=${removed} skipped=${skipped} kept=${kept}"
fi
exit "$overall_exit"
