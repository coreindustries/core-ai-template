#!/usr/bin/env bash
# agent-hooks-codex.test.sh — unit tests for .claude/hooks/agent-role-codex.sh,
# the Codex UserPromptSubmit adapter wired from .codex/hooks.json.
#
# The adapter's whole job is: export AGENT_HOOK_RUNTIME=codex, then exec the
# SAME agent-role.sh Claude Code uses, resolved relative to its own location.
# It must not reimplement any matching logic (single source of truth for the
# role regexes lives in agent-role.sh / lib/agent-state.sh — see
# agent-hooks.test.sh for those). These tests only cover the adapter's own
# input handling and forwarding:
#
#   1. it forwards a Codex-shaped payload (extra fields agent-role.sh doesn't
#      use: turn_id, cwd, hook_event_name, model, permission_mode) and still
#      produces the same role/name as calling agent-role.sh directly with the
#      same session_id/prompt — proving the extra fields are harmless;
#   2. it actually exports AGENT_HOOK_RUNTIME=codex into the process it execs
#      (mutation-checked against a stub agent-role.sh that just echoes the
#      variable back);
#   3. it resolves agent-role.sh relative to ITS OWN location (BASH_SOURCE),
#      not a hardcoded path, so a checkout at any path still works;
#   4. malformed/empty stdin and a payload missing session_id still exit 0
#      (the "never blocks a prompt" contract carries through the adapter).
#
# Uses DISPOSABLE temp project roots, never this repo's own .git — same
# discipline as agent-hooks.test.sh.
#
# Run: bash scripts/dev/board/tests/agent-hooks-codex.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BOARD_DIR/../../.." && pwd)"
REAL_HOOKS_DIR="$REPO_ROOT/.claude/hooks"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

WORK="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# copy_codex_hooks_into <project-root> — installs agent-role.sh,
# agent-role-codex.sh and lib/agent-state.sh into a disposable project root,
# in the same relative layout as the real repo.
copy_codex_hooks_into() {
  local root="$1"
  mkdir -p "$root/.claude/hooks/lib"
  cp "$REAL_HOOKS_DIR/agent-role.sh" "$root/.claude/hooks/agent-role.sh"
  cp "$REAL_HOOKS_DIR/agent-role-codex.sh" "$root/.claude/hooks/agent-role-codex.sh"
  cp "$REAL_HOOKS_DIR/lib/agent-state.sh" "$root/.claude/hooks/lib/agent-state.sh"
  chmod +x "$root/.claude/hooks/agent-role.sh" "$root/.claude/hooks/agent-role-codex.sh"
}

FAKE_PROJECT="$WORK/fake-project"
mkdir -p "$FAKE_PROJECT"
git init -q "$FAKE_PROJECT"
copy_codex_hooks_into "$FAKE_PROJECT"
CODEX_HOOK="$FAKE_PROJECT/.claude/hooks/agent-role-codex.sh"
ROLE_HOOK="$FAKE_PROJECT/.claude/hooks/agent-role.sh"
STATE_DIR="$FAKE_PROJECT/.git/claude-agent-roles"

# codex_payload <session-id> <prompt> — a full Codex UserPromptSubmit stdin
# payload: the fields agent-role.sh reads (session_id, prompt) PLUS the
# Codex-only fields it must ignore harmlessly (turn_id, cwd, hook_event_name,
# model, permission_mode) — see docs/codex.md "UserPromptSubmit hook".
codex_payload() {
  python3 -c '
import json, sys
print(json.dumps({
    "session_id": sys.argv[1],
    "turn_id": "turn-fixture-1",
    "cwd": sys.argv[3],
    "hook_event_name": "UserPromptSubmit",
    "model": "fixture-model",
    "permission_mode": "auto",
    "prompt": sys.argv[2],
}))
' "$1" "$2" "$FAKE_PROJECT"
}

role_of() {
  local session_id="$1"
  [ -f "$STATE_DIR/$session_id.json" ] || { echo ""; return; }
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("role",""))' "$STATE_DIR/$session_id.json" 2>/dev/null
}
name_of() {
  local session_id="$1"
  [ -f "$STATE_DIR/$session_id.json" ] || { echo ""; return; }
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("name",""))' "$STATE_DIR/$session_id.json" 2>/dev/null
}

echo ""
echo "=== agent-role-codex.sh unit tests ==="

# ── 1. Codex-shaped payload with extra fields still matches, same as agent-role.sh directly ──
rm -rf "$STATE_DIR"
codex_payload "sess-codex-prd" "You are the PRD manager" > "$WORK/payload.json"
out="$("$CODEX_HOOK" < "$WORK/payload.json")"
rc=$?
[ "$rc" -eq 0 ] && pass "codex-payload-exits-0" || fail "codex-payload-exits-0 (rc=$rc)"
[ "$(role_of sess-codex-prd)" = "prd" ] && pass "codex-payload-extra-fields-dont-block-role-match" \
  || fail "codex-payload-extra-fields-dont-block-role-match (got role='$(role_of sess-codex-prd)')"
[ "$(name_of sess-codex-prd)" = "C-PRD" ] && pass "codex-payload-name-is-c-prd" \
  || fail "codex-payload-name-is-c-prd (got '$(name_of sess-codex-prd)')"
printf '%s' "$out" | grep -q "Agent role recorded: C-PRD" && pass "codex-payload-prints-role-recorded-message" \
  || fail "codex-payload-prints-role-recorded-message (got: $out)"

# ── Parity: same session/prompt through the Claude hook directly must match ──
rm -rf "$STATE_DIR"
python3 -c '
import json, sys
print(json.dumps({"session_id": sys.argv[1], "prompt": sys.argv[2]}))
' "sess-parity" "You are the Feature manager" > "$WORK/claude-payload.json"
CLAUDE_PROJECT_DIR="$FAKE_PROJECT" "$ROLE_HOOK" < "$WORK/claude-payload.json" >/dev/null
claude_role="$(role_of sess-parity)"
claude_name="$(name_of sess-parity)"
rm -rf "$STATE_DIR"
codex_payload "sess-parity" "You are the Feature manager" > "$WORK/payload.json"
"$CODEX_HOOK" < "$WORK/payload.json" >/dev/null
[ "$(role_of sess-parity)" = "$claude_role" ] && [ "$(name_of sess-parity)" = "$claude_name" ] \
  && pass "codex-adapter-matches-claude-hook-for-same-session-and-prompt (role=$claude_role name=$claude_name)" \
  || fail "codex-adapter-matches-claude-hook-for-same-session-and-prompt (claude: $claude_role/$claude_name, codex: $(role_of sess-parity)/$(name_of sess-parity))"

# ── 2. AGENT_HOOK_RUNTIME=codex is actually exported into the execed process ──
# MUTATION CHECK: swap in a stub agent-role.sh that only echoes the variable,
# proving the adapter's `export` line is load-bearing rather than the test
# passing vacuously because agent-role.sh happens not to care.
STUB_DIR="$WORK/stub-runtime-dir"
mkdir -p "$STUB_DIR/.claude/hooks"
cp "$REAL_HOOKS_DIR/agent-role-codex.sh" "$STUB_DIR/.claude/hooks/agent-role-codex.sh"
chmod +x "$STUB_DIR/.claude/hooks/agent-role-codex.sh"
cat > "$STUB_DIR/.claude/hooks/agent-role.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null   # drain stdin, matching the real hook's contract
printf 'RUNTIME=%s\n' "${AGENT_HOOK_RUNTIME:-<unset>}"
exit 0
EOF
chmod +x "$STUB_DIR/.claude/hooks/agent-role.sh"
stub_out="$(printf '{}' | "$STUB_DIR/.claude/hooks/agent-role-codex.sh")"
[ "$stub_out" = "RUNTIME=codex" ] && pass "MUTATION CHECK: adapter exports AGENT_HOOK_RUNTIME=codex into the execed process (stub confirms; unset would read '<unset>')" \
  || fail "MUTATION CHECK: adapter should export AGENT_HOOK_RUNTIME=codex (got '$stub_out')"

# ── 3. Adapter resolves agent-role.sh relative to ITS OWN location, not a hardcoded path ──
# Copy the pair (adapter + real agent-role.sh + lib/) to a DIFFERENT absolute
# path than FAKE_PROJECT and confirm it still works — proving BASH_SOURCE
# resolution, not an absolute path baked in at some earlier step.
RELOCATED="$WORK/some/other/absolute/path-$$"
mkdir -p "$RELOCATED/.claude/hooks/lib"
git init -q "$RELOCATED"
cp "$REAL_HOOKS_DIR/agent-role.sh" "$RELOCATED/.claude/hooks/agent-role.sh"
cp "$REAL_HOOKS_DIR/agent-role-codex.sh" "$RELOCATED/.claude/hooks/agent-role-codex.sh"
cp "$REAL_HOOKS_DIR/lib/agent-state.sh" "$RELOCATED/.claude/hooks/lib/agent-state.sh"
chmod +x "$RELOCATED/.claude/hooks/agent-role.sh" "$RELOCATED/.claude/hooks/agent-role-codex.sh"
RELOCATED_STATE_DIR="$RELOCATED/.git/claude-agent-roles"
codex_payload "sess-relocated" "You are the Release Manager" > "$WORK/relocated-payload.json"
"$RELOCATED/.claude/hooks/agent-role-codex.sh" < "$WORK/relocated-payload.json" >/dev/null
relocated_role="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("role",""))' "$RELOCATED_STATE_DIR/sess-relocated.json" 2>/dev/null || echo "")"
[ "$relocated_role" = "release" ] && pass "adapter-resolves-agent-role.sh-relative-to-its-own-location-not-a-hardcoded-path" \
  || fail "adapter-resolves-agent-role.sh-relative-to-its-own-location-not-a-hardcoded-path (got role='$relocated_role')"

# ── 4. Never blocks: malformed/empty stdin and a missing session_id still exit 0 ──
rm -rf "$STATE_DIR"
out_empty="$(printf '' | "$CODEX_HOOK")"
rc_empty=$?
[ "$rc_empty" -eq 0 ] && pass "codex-hook-empty-stdin-exits-0" || fail "codex-hook-empty-stdin-exits-0 (rc=$rc_empty)"

rc_malformed=0
printf 'not json at all {{{' | "$CODEX_HOOK" >/dev/null 2>&1 || rc_malformed=$?
[ "$rc_malformed" -eq 0 ] && pass "codex-hook-malformed-json-exits-0" || fail "codex-hook-malformed-json-exits-0 (rc=$rc_malformed)"

python3 -c '
import json, sys
print(json.dumps({"prompt": "You are the PRD manager", "cwd": "/tmp"}))
' > "$WORK/no-session-id.json"
rc_no_session=0
printf '%s' "$(cat "$WORK/no-session-id.json")" | "$CODEX_HOOK" >/dev/null 2>&1 || rc_no_session=$?
[ "$rc_no_session" -eq 0 ] && pass "codex-hook-missing-session-id-exits-0" || fail "codex-hook-missing-session-id-exits-0 (rc=$rc_no_session)"

print_summary "agent-role-codex.sh"
