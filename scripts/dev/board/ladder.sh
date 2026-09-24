#!/usr/bin/env bash
# ladder.sh — the Release Manager's environment ladder, driven entirely by
# deploy.environments in .claude/agent-lanes.json (ordered: first rung first).
#
#   ladder.sh envs                                  list rungs and which commands are configured
#   ladder.sh health (<env> | --all) [--json]       running SHA by CONTENT, vs origin/<defaultBranch>
#   ladder.sh deploy <env> --sha <sha> [--print]    run the deploy command, then verify by health
#   ladder.sh rollback <env> --to <sha> [--print]   run the rollback command, then verify by health
#
# Rules this tool enforces rather than documents:
#   - A deploy counts only when health afterwards reports the deployed SHA.
#     A green deploy command with a different running SHA exits 1 (MISMATCH).
#   - --print shows the exact substituted command and runs NOTHING. Never
#     dry-run a make target with `make -n`: make still executes $(MAKE)
#     recipe lines under -n. `lanes-config.sh check` rejects such commands.
#   - The SHA is resolved to a full 40-char commit before substitution, so a
#     placeholder is only ever replaced with validated hex, never free text.
#   - There is deliberately no `logs` subcommand: raw logs go only to
#     log-triage.py, which redacts them in code. No model reads raw logs.
#
# Exit codes: 0 ok, 1 verification failed / unhealthy, 2 usage or config error.
# Portability: macOS bash 3.2 + Linux.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"


command -v jq >/dev/null 2>&1 || die "'jq' not found on PATH"
[ -f "$LANES_CONFIG" ] || die "config missing: $LANES_CONFIG"

DEFAULT_BRANCH="$(lanes_cfg '.defaultBranch' main)"

env_names() { jq -r '(.deploy.environments // [])[].name' "$LANES_CONFIG"; }

env_field() {
  # env_field <env> <field>
  jq -r --arg e "$1" --arg f "$2" \
    '((.deploy.environments // [])[] | select(.name == $e) | .[$f]) // empty' "$LANES_CONFIG"
}

require_env() {
  env_names | grep -qxF "$1" || die "unknown environment '$1' — configured: $(env_names | tr '\n' ' ')"
}

resolve_sha() {
  local sha="$1" full
  printf '%s' "$sha" | grep -Eq '^[0-9a-fA-F]{7,40}$' || die "'$sha' is not a commit SHA (7-40 hex chars)"
  full="$(git -C "$LANES_REPO_ROOT" rev-parse --verify -q "${sha}^{commit}" 2>/dev/null)" \
    || die "commit $sha not in local history — git fetch first"
  printf '%s' "$full"
}

substitute() {
  # substitute <cmd> <env> <sha>
  local cmd="$1"
  cmd="${cmd//\{env\}/$2}"
  cmd="${cmd//\{sha\}/$3}"
  printf '%s' "$cmd"
}

# running_sha <env> — prints the SHA the health command reports, or nothing.
running_sha() {
  local cmd out sha
  cmd="$(env_field "$1" health)"
  [ -n "$cmd" ] || return 2
  cmd="$(substitute "$cmd" "$1" "")"
  out="$(cd "$LANES_REPO_ROOT" && bash -c "$cmd" 2>/dev/null)" || return 1
  sha="$(printf '%s' "$out" | jq -r '.git_commit // .sha // .commit // empty' 2>/dev/null)"
  [ -n "$sha" ] || sha="$(printf '%s' "$out" | grep -Eo '\b[0-9a-f]{40}\b' | head -1)"
  printf '%s' "$sha"
}

cmd_envs() {
  local name f line
  for name in $(env_names); do
    line="$name"
    for f in deploy health logs rollback; do
      if [ -n "$(env_field "$name" "$f")" ]; then line="$line  $f=ok"; else line="$line  $f=UNSET"; fi
    done
    echo "$line"
  done
}

cmd_health() {
  local target="" as_json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) target="--all"; shift ;;
      --json) as_json=1; shift ;;
      -*) die "health: unknown flag $1" ;;
      *) target="$1"; shift ;;
    esac
  done
  [ -n "$target" ] || die "health: usage: health (<env> | --all) [--json]"

  git -C "$LANES_REPO_ROOT" fetch -q origin "$DEFAULT_BRANCH" 2>/dev/null \
    || echo "ladder.sh: git fetch origin ${DEFAULT_BRANCH} failed — behind counts may be stale" >&2
  local main_sha
  main_sha="$(git -C "$LANES_REPO_ROOT" rev-parse -q --verify "origin/${DEFAULT_BRANCH}" 2>/dev/null || true)"

  local envs results="[]" name sha rc behind status entry unhealthy=0
  if [ "$target" = "--all" ]; then envs="$(env_names)"; else require_env "$target"; envs="$target"; fi
  for name in $envs; do
    sha="$(running_sha "$name")"; rc=$?
    behind="null"; status="ok"
    if [ "$rc" = "2" ]; then status="health-unset"; unhealthy=1
    elif [ "$rc" != "0" ]; then status="unreachable"; unhealthy=1
    elif [ -z "$sha" ]; then status="no-sha-in-output"; unhealthy=1
    elif [ -n "$main_sha" ] && git -C "$LANES_REPO_ROOT" cat-file -e "${sha}^{commit}" 2>/dev/null; then
      behind="$(git -C "$LANES_REPO_ROOT" rev-list --count "${sha}..${main_sha}")"
    fi
    entry="$(jq -nc --arg env "$name" --arg status "$status" --arg sha "$sha" --arg behind "$behind" \
      '{env:$env, status:$status, sha:(if $sha == "" then null else $sha end),
        behindMain:(if $behind == "null" then null else ($behind|tonumber) end)}')"
    results="$(printf '%s' "$results" | jq -c --argjson e "$entry" '. + [$e]')"
  done

  if [ "$as_json" = "1" ]; then
    printf '%s\n' "$results"
  else
    printf '%s' "$results" | jq -r '.[] | [.env, .status, ((.sha // "-") | .[0:8]),
      ("behind=" + ((.behindMain // "?") | tostring))] | @tsv' | awk -F'\t' '{printf "%-14s %-18s %-9s %s\n", $1, $2, $3, $4}'
  fi
  [ "$unhealthy" = "0" ] || exit 1
}

# run_and_verify <env> <field> <sha> <print>
run_and_verify() {
  local name="$1" field="$2" sha="$3" print_only="$4" cmd
  cmd="$(env_field "$name" "$field")"
  [ -n "$cmd" ] || die "${name}.${field} is not configured in $LANES_CONFIG"
  lanes_check >/dev/null || die "config check failed — run scripts/dev/board/lanes-config.sh check"
  cmd="$(substitute "$cmd" "$name" "$sha")"

  if [ "$print_only" = "1" ]; then
    echo "WOULD-RUN ($name $field): $cmd"
    return 0
  fi

  echo "RUN ($name $field ${sha:0:8}): $cmd"
  (cd "$LANES_REPO_ROOT" && bash -c "$cmd")
  local rc=$?
  [ "$rc" = "0" ] || die "${name} ${field} command exited ${rc}" 1

  # Deploy commands can return before rollout finishes, so poll health until
  # it reports the SHA or the window closes. The window is per environment:
  # verifyTimeoutSeconds (default 0 = a single check), verifyIntervalSeconds (10).
  local window interval waited=0 running="" hrc=0
  window="$(env_field "$name" verifyTimeoutSeconds)"; window="${window:-0}"
  interval="$(env_field "$name" verifyIntervalSeconds)"; interval="${interval:-10}"
  case "$window$interval" in *[!0-9]*) die "${name}: verifyTimeoutSeconds / verifyIntervalSeconds must be whole numbers" ;; esac
  [ "$interval" -gt 0 ] || interval=10
  while :; do
    running="$(running_sha "$name")"; hrc=$?
    [ "$hrc" = "0" ] && [ "$running" = "$sha" ] && break
    [ "$waited" -ge "$window" ] && break
    sleep "$interval"
    waited=$((waited + interval))
  done
  if [ "$hrc" != "0" ]; then
    die "${name}: health check failed after ${field} (waited ${waited}s) — deploy NOT verified" 1
  fi
  if [ "$running" != "$sha" ]; then
    echo "MISMATCH ${name}: health reports ${running:-nothing}, expected ${sha} (waited ${waited}s)" >&2
    exit 1
  fi
  echo "VERIFIED ${name} running ${sha:0:8}"
}

cmd_deploy() {
  local name="${1:-}"; shift || true
  local sha="" print_only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --sha) sha="${2:-}"; shift 2 ;;
      --print) print_only=1; shift ;;
      *) die "deploy: unknown arg $1" ;;
    esac
  done
  [ -n "$name" ] && [ -n "$sha" ] || die "deploy: usage: deploy <env> --sha <sha> [--print]"
  require_env "$name"
  # NOT `run_and_verify ... "$(resolve_sha "$sha")" ...` inline: resolve_sha's
  # `die` calls `exit` from inside this $(...) subshell, which only ends the
  # subshell — the parent script would otherwise sail on with an EMPTY sha
  # silently substituted into the deploy command. Assign first so `||` can
  # see and forward the real exit status.
  local sha_full
  sha_full="$(resolve_sha "$sha")" || exit $?
  run_and_verify "$name" deploy "$sha_full" "$print_only"
}

cmd_rollback() {
  local name="${1:-}"; shift || true
  local sha="" print_only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --to) sha="${2:-}"; shift 2 ;;
      --print) print_only=1; shift ;;
      *) die "rollback: unknown arg $1" ;;
    esac
  done
  [ -n "$name" ] && [ -n "$sha" ] || die "rollback: usage: rollback <env> --to <sha> [--print]"
  require_env "$name"
  # See cmd_deploy's comment above: resolve_sha's `die` only kills this
  # $(...) subshell, so the exit status must be captured and forwarded
  # explicitly rather than trusting the substitution to abort the script.
  local sha_full
  sha_full="$(resolve_sha "$sha")" || exit $?
  run_and_verify "$name" rollback "$sha_full" "$print_only"
}

case "${1:-}" in
  envs) shift; cmd_envs "$@" ;;
  health) shift; cmd_health "$@" ;;
  deploy) shift; cmd_deploy "$@" ;;
  rollback) shift; cmd_rollback "$@" ;;
  help|-h|--help|"") sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown subcommand '$1' — run 'ladder.sh help'" ;;
esac
