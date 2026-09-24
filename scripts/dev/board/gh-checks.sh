#!/usr/bin/env bash
# gh-checks.sh — sourced by board.sh and pr-watch.sh. Defines gh_checks(),
# a drop-in replacement for any `gh` invocation that reads PR CHECK RUNS
# (a --json field list including statusCheckRollup).
#
# Why: fine-grained PATs cannot be granted the Checks permission. An agent
# whose GH_TOKEN is a fine-grained PAT cannot read PR check runs:
#   gh pr view <n> --json statusCheckRollup            (GH_TOKEN = fine-grained PAT)
#     -> exit 1, stderr: "GraphQL: Resource not accessible by personal
#        access token (repository.pullRequest.statusCheckRollup.nodes.0.
#        commit.statusCheckRollup.contexts.nodes.0), ..."
#   GH_TOKEN= gh pr view <n> --json statusCheckRollup  (keyring OAuth login)
#     -> exit 0, {"statusCheckRollup":[{"__typename":"CheckRun","conclusion":
#        "...","name":"...","status":"COMPLETED","workflowName":"..."}, ...]}
# Without this fallback the agent loses CI visibility, and the workaround
# people reach for by hand (reading a draft PR's partial rollup) reads as a
# false green.
#
# gh_checks <gh args...>:
#   0. SCOPE GUARD: gh_checks exists ONLY to read PR
#      check rollups, but a blanket retry-under-the-keyring-login of ANY gh
#      argv would silently run a MUTATING gh command (e.g. `pr merge`) under
#      a different, more-privileged credential than the caller intended.
#      Refuse anything that is not `pr view ...`/`pr list ...` with a --json
#      field list containing "statusCheckRollup" (`--json X` or `--json=X`)
#      — ERROR + return 2, before gh runs at all.
#   1. BOARD_CHECKS_TOKEN set and non-empty -> run with that token
#      explicitly (GH_TOKEN="$BOARD_CHECKS_TOKEN" gh "$@"), no probing.
#      GITHUB_TOKEN is unset for this call too, so it can't override the
#      token gh actually picks.
#   2. Neither GH_TOKEN nor GITHUB_TOKEN set/non-empty -> nothing to work
#      around; run `gh "$@"` unchanged (gh reads whichever ambient credential
#      it normally would, e.g. the keyring login).
#   3. This process already learned the active credential can't read checks
#      (memoized) -> go straight to the keyring login, no re-probe.
#   4. Otherwise: try `gh "$@"` with the active GH_TOKEN/GITHUB_TOKEN. On the
#      specific "Resource not accessible by personal access token" failure,
#      retry once with the keyring login (GH_TOKEN and GITHUB_TOKEN both
#      unset for that one call — gh also honors GITHUB_TOKEN, so unsetting
#      only GH_TOKEN would leave the retry using the same broken PAT).
#      Retry success -> memoize for the rest of this process and print the
#      NOTE once. Retry failure -> ERROR naming both credentials, non-zero
#      return, no stdout — never a silent empty/success-shaped result (an
#      empty check rollup reads as "pending forever" to every caller here).
#   Any OTHER failure (case 4, an error that isn't the PAT-checks one): no
#   retry, original stderr passed through unchanged, original exit code
#   returned.
#
# Portability: macOS bash 3.2 (no `declare -A`, no `${x,,}`) — memoization
# is a plain sentinel FILE, not an in-shell variable or associative array.
# It has to be a file: every real caller here (fetch_pr_json/fetch_agent_list
# in pr-watch.sh, cmd_pr_status/cmd_my_prs in board.sh) invokes gh_checks
# inside `$(...)` command substitution to capture its stdout, and command
# substitution forks a SUBSHELL — a variable assignment made inside gh_checks
# during that call (e.g. a plain `GH_CHECKS_MODE=keyring`) is lost the moment
# the subshell exits and never reaches the next call. The file survives
# across those subshells because it's the same real path each time.
set -uo pipefail

GH_CHECKS_MODE_FILE="$(mktemp)"
rm -f "$GH_CHECKS_MODE_FILE"   # unique path reserved; starts absent (undecided)
# This trap owns process EXIT cleanup for GH_CHECKS_MODE_FILE. A caller that
# sources this file (board.sh, pr-watch.sh) and adds its OWN EXIT trap must
# chain `rm -f "$GH_CHECKS_MODE_FILE"` into it, or this trap is silently
# replaced and the sentinel file leaks.
trap 'rm -f "$GH_CHECKS_MODE_FILE"' EXIT

# _gh_checks_allowed <gh args...> — true only for `pr view`/`pr list` with a
# --json value containing "statusCheckRollup" (handles both `--json X` and
# `--json=X`). gh_checks is a check-rollup reader, not a general gh proxy;
# anything else (e.g. `pr merge`) must go through plain `gh` directly, under
# the caller's own ambient credential, never the retried/keyring one.
_gh_checks_allowed() {
  if [ "${1:-}" != "pr" ]; then
    return 1
  fi
  if [ "${2:-}" != "view" ] && [ "${2:-}" != "list" ]; then
    return 1
  fi
  shift 2
  local arg
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --json)
        shift
        case "${1:-}" in *statusCheckRollup*) return 0 ;; esac
        ;;
      --json=*)
        case "$arg" in *statusCheckRollup*) return 0 ;; esac
        ;;
    esac
    shift
  done
  return 1
}

gh_checks() {
  local err_file rc line

  if ! _gh_checks_allowed "$@"; then
    echo "ERROR gh-checks: refusing $* — gh_checks only reads PR check rollups (pr view|list --json …statusCheckRollup…)" >&2
    return 2
  fi

  if [ -n "${BOARD_CHECKS_TOKEN:-}" ]; then
    env -u GITHUB_TOKEN GH_TOKEN="$BOARD_CHECKS_TOKEN" gh "$@"
    return $?
  fi

  if [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ]; then
    gh "$@"
    return $?
  fi

  if [ -f "$GH_CHECKS_MODE_FILE" ]; then
    env -u GH_TOKEN -u GITHUB_TOKEN gh "$@"
    return $?
  fi

  err_file="$(mktemp)"
  # NOT `if gh ...; then ...; fi; rc=$?` — when the condition is false and
  # there is no `else`, bash resets `$?` to 0 for the whole construct, so a
  # `rc=$?` read after a bare `fi` silently captures success even though gh
  # failed. Capture it inside an explicit `else` instead.
  if gh "$@" 2>"$err_file"; then
    cat "$err_file" >&2
    rm -f "$err_file"
    return 0
  else
    rc=$?
  fi

  if grep -q 'Resource not accessible by personal access token' "$err_file"; then
    rm -f "$err_file"
    err_file="$(mktemp)"
    if env -u GH_TOKEN -u GITHUB_TOKEN gh "$@" 2>"$err_file"; then
      : > "$GH_CHECKS_MODE_FILE"
      echo "NOTE gh-checks: active GH_TOKEN cannot read check runs (fine-grained PAT); using the gh keyring login for check reads — set BOARD_CHECKS_TOKEN to choose explicitly" >&2
      cat "$err_file" >&2
      rm -f "$err_file"
      return 0
    fi
    line="$(head -1 "$err_file")"
    rm -f "$err_file"
    echo "ERROR gh-checks: cannot read PR check runs — GH_TOKEN (fine-grained PAT) lacks Checks and the keyring login failed: ${line}" >&2
    return 1
  fi

  cat "$err_file" >&2
  rm -f "$err_file"
  return "$rc"
}
