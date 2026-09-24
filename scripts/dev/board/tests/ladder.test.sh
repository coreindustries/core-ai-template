#!/usr/bin/env bash
# ladder.test.sh — unit tests for scripts/dev/board/ladder.sh (the Release
# Manager's environment ladder) against a REAL disposable temp git repo (for
# SHA resolution) and a temp config whose deploy/health/rollback commands are
# small shell snippets that write/read a temp state file — no network calls,
# no real deploy/health infrastructure.
#
# Run: bash scripts/dev/board/tests/ladder.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="$(cd "$TESTS_DIR/.." && pwd)"
LADDER="$BOARD_DIR/ladder.sh"
LANES_CONFIG_SH="$BOARD_DIR/lanes-config.sh"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo ""
echo "=== ladder.sh unit tests ==="

# ---------------------------------------------------------------------------
# A real disposable git repo — ladder.sh resolves a --sha argument to a full
# 40-char commit via `git rev-parse --verify` against LANES_REPO_ROOT, so the
# fixture SHAs used below must actually exist in a real repo's history.
# ---------------------------------------------------------------------------
export GIT_AUTHOR_NAME="ladder-test" GIT_AUTHOR_EMAIL="ladder-test@example.invalid"
export GIT_COMMITTER_NAME="ladder-test" GIT_COMMITTER_EMAIL="ladder-test@example.invalid"

REPO="$WORK/repo"
git init -q "$REPO"
git -C "$REPO" symbolic-ref HEAD refs/heads/main
echo "one" > "$REPO/f.txt"
git -C "$REPO" add f.txt
git -C "$REPO" commit -q -m "commit one"
COMMIT1="$(git -C "$REPO" rev-parse HEAD)"
echo "two" > "$REPO/f.txt"
git -C "$REPO" add f.txt
git -C "$REPO" commit -q -m "commit two"
COMMIT2="$(git -C "$REPO" rev-parse HEAD)"

export LANES_REPO_ROOT="$REPO"

# ---------------------------------------------------------------------------
# Config fixture. Four environments, each proving a different rung of the
# ladder's contract:
#   staging     — JSON health form ({"git_commit": "..."}), full round trip
#   production  — bare 40-hex-char health form, rollback left UNSET on purpose
#                 (exercises the envs listing's UNSET column)
#   mismatch    — deploy command ALWAYS writes a fixed, wrong SHA regardless
#                 of what was requested -> the deploy succeeds but health
#                 disagrees -> MISMATCH
#   failenv     — deploy command always exits non-zero
# ---------------------------------------------------------------------------
STATE_STAGING="$WORK/state-staging.json"
STATE_PRODUCTION="$WORK/state-production.txt"
STATE_MISMATCH="$WORK/state-mismatch.json"
WRONG_SHA="ffffffffffffffffffffffffffffffffffffff00"
WRONG_SHA="${WRONG_SHA:0:40}"

# "slow" rung: rollout completes only on the 3rd health poll after deploy.
SLOW_TARGET="$WORK/slow-target"
SLOW_COUNT="$WORK/slow-count"
cat > "$WORK/slow-health.sh" <<SLOW
#!/usr/bin/env bash
n=\$(cat '$SLOW_COUNT' 2>/dev/null || echo 0); n=\$((n + 1)); echo "\$n" > '$SLOW_COUNT'
if [ "\$n" -ge 3 ]; then printf '%s' "\$(cat '$SLOW_TARGET')"; else echo '{}'; fi
SLOW
chmod +x "$WORK/slow-health.sh"

LANES_CONFIG="$WORK/agent-lanes.json"
cat > "$LANES_CONFIG" <<CFG
{
  "namePrefix": "C",
  "defaultBranch": "main",
  "deploy": {
    "environments": [
      {
        "name": "staging",
        "deploy": "echo '{\\"git_commit\\":\\"{sha}\\"}' > '$STATE_STAGING'",
        "health": "cat '$STATE_STAGING' 2>/dev/null || echo '{}'",
        "rollback": "echo '{\\"git_commit\\":\\"{sha}\\"}' > '$STATE_STAGING'"
      },
      {
        "name": "production",
        "deploy": "printf '%s' '{sha}' > '$STATE_PRODUCTION'",
        "health": "cat '$STATE_PRODUCTION' 2>/dev/null || printf ''",
        "rollback": ""
      },
      {
        "name": "mismatch",
        "deploy": "echo '{\\"git_commit\\":\\"$WRONG_SHA\\"}' > '$STATE_MISMATCH'",
        "health": "cat '$STATE_MISMATCH' 2>/dev/null || echo '{}'",
        "rollback": ""
      },
      {
        "name": "slow",
        "deploy": "printf '%s' '{sha}' > '$SLOW_TARGET'; echo 0 > '$SLOW_COUNT'",
        "health": "'$WORK/slow-health.sh'",
        "rollback": "",
        "verifyTimeoutSeconds": 5,
        "verifyIntervalSeconds": 1
      },
      {
        "name": "slownowait",
        "deploy": "printf '%s' '{sha}' > '$SLOW_TARGET'; echo 0 > '$SLOW_COUNT'",
        "health": "'$WORK/slow-health.sh'",
        "rollback": ""
      },
      {
        "name": "failenv",
        "deploy": "exit 3",
        "health": "echo '{}'",
        "rollback": ""
      }
    ]
  }
}
CFG
export LANES_CONFIG

# ===========================================================================
# 1. envs — lists every configured rung and which commands are set.
# ===========================================================================
out="$("$LADDER" envs 2>"$WORK/envs.err")"
rc=$?
if [ "$rc" = "0" ] \
   && printf '%s' "$out" | grep -qE '^staging +deploy=ok +health=ok +logs=UNSET +rollback=ok$' \
   && printf '%s' "$out" | grep -qE '^production +deploy=ok +health=ok +logs=UNSET +rollback=UNSET$'; then
  pass "envs: lists every configured rung with per-field ok/UNSET status"
else
  fail "envs: listing (rc=$rc out=[$out] err=[$(cat "$WORK/envs.err")])"
fi

# ===========================================================================
# 2. deploy --print runs nothing — no state file is written, the exact
# substituted command is shown.
# ===========================================================================
[ ! -f "$STATE_STAGING" ] || fail "setup: STATE_STAGING should not exist yet"
out="$("$LADDER" deploy staging --sha "$COMMIT1" --print 2>"$WORK/print.err")"
rc=$?
if [ "$rc" = "0" ] && [ ! -f "$STATE_STAGING" ] \
   && printf '%s' "$out" | grep -qF "WOULD-RUN (staging deploy): echo '{\"git_commit\":\"$COMMIT1\"}'"; then
  pass "deploy --print: shows the exact substituted command, runs nothing (no state file written)"
else
  fail "deploy --print (rc=$rc out=[$out] err=[$(cat "$WORK/print.err")] state-exists=$([ -f "$STATE_STAGING" ] && echo yes || echo no))"
fi

# ===========================================================================
# 3. deploy success + VERIFIED — the deploy command runs for real, health
# afterward reports the same SHA it deployed.
# ===========================================================================
out="$("$LADDER" deploy staging --sha "$COMMIT1" 2>"$WORK/deploy1.err")"
rc=$?
if [ "$rc" = "0" ] && [ -f "$STATE_STAGING" ] \
   && printf '%s' "$out" | grep -qF "VERIFIED staging running ${COMMIT1:0:8}"; then
  pass "deploy: runs the deploy command, verifies by health, prints VERIFIED"
else
  fail "deploy success (rc=$rc out=[$out] err=[$(cat "$WORK/deploy1.err")])"
fi

# ===========================================================================
# 4. health by content — JSON git_commit form (staging) and bare-40-hex form
# (production, after its own deploy).
# ===========================================================================
out="$("$LADDER" health staging 2>"$WORK/health-staging.err")"
rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -qE "^staging +ok +${COMMIT1:0:8} "; then
  pass "health: JSON {git_commit:...} form is read correctly (staging)"
else
  fail "health: JSON form (rc=$rc out=[$out] err=[$(cat "$WORK/health-staging.err")])"
fi

"$LADDER" deploy production --sha "$COMMIT2" >/dev/null 2>"$WORK/deploy-prod.err"
out_json="$("$LADDER" health production --json 2>"$WORK/health-prod.err")"
rc=$?
sha_reported="$(printf '%s' "$out_json" | jq -r '.[0].sha')"
if [ "$rc" = "0" ] && [ "$sha_reported" = "$COMMIT2" ]; then
  pass "health: bare 40-hex-char form is read correctly (production, via --json)"
else
  fail "health: bare-sha form (rc=$rc sha=[$sha_reported] out=[$out_json] err=[$(cat "$WORK/health-prod.err")])"
fi

# --all combines both rungs in one call.
out_all="$("$LADDER" health --all --json 2>/dev/null)"
n_ok="$(printf '%s' "$out_all" | jq '[.[] | select(.status=="ok")] | length')"
if [ "$n_ok" -ge 2 ]; then
  pass "health --all: reports every configured rung in one call"
else
  fail "health --all (n_ok=$n_ok out=[$out_all])"
fi

# ===========================================================================
# 5. deploy where health reports a DIFFERENT sha -> MISMATCH, exit 1. The
# deploy command itself succeeds (rc 0) but wrote the wrong content.
# ===========================================================================
out="$("$LADDER" deploy mismatch --sha "$COMMIT1" 2>&1)"
rc=$?
if [ "$rc" = "1" ] && printf '%s' "$out" | grep -qF "MISMATCH mismatch: health reports ${WRONG_SHA}, expected ${COMMIT1}"; then
  pass "deploy: a deploy command that runs green but leaves the wrong SHA running -> MISMATCH, exit 1"
else
  fail "deploy: mismatch (rc=$rc out=[$out])"
fi

# ===========================================================================
# 6. deploy command itself failing -> exit 1, never claims verification.
# ===========================================================================
out="$("$LADDER" deploy failenv --sha "$COMMIT1" 2>&1)"
rc=$?
if [ "$rc" = "1" ] && printf '%s' "$out" | grep -q "failenv deploy command exited 3" \
   && ! printf '%s' "$out" | grep -q "VERIFIED"; then
  pass "deploy: a failing deploy command exits 1 and never prints VERIFIED"
else
  fail "deploy: command failure (rc=$rc out=[$out])"
fi

# ===========================================================================
# 7. unknown environment -> exit 2 (usage/config error), names what is
# configured.
# ===========================================================================
out="$("$LADDER" deploy not-a-real-env --sha "$COMMIT1" 2>&1)"
rc=$?
if [ "$rc" = "2" ] && printf '%s' "$out" | grep -q "unknown environment 'not-a-real-env'"; then
  pass "deploy: unknown environment -> exit 2, names what's configured"
else
  fail "deploy: unknown env (rc=$rc out=[$out])"
fi

out="$("$LADDER" health not-a-real-env 2>&1)"
rc=$?
[ "$rc" = "2" ] && pass "health: unknown environment -> exit 2" \
  || fail "health: unknown env (rc=$rc out=[$out])"

# ===========================================================================
# 8. non-hex / malformed sha -> exit 2, never reaches git or the deploy
# command.
# ===========================================================================
before_mtime="no-file"
[ -f "$STATE_STAGING" ] && before_mtime="$(cat "$STATE_STAGING")"
out="$("$LADDER" deploy staging --sha "not-a-sha" 2>&1)"
rc=$?
after_mtime="no-file"
[ -f "$STATE_STAGING" ] && after_mtime="$(cat "$STATE_STAGING")"
if [ "$rc" = "2" ] && printf '%s' "$out" | grep -q "is not a commit SHA" && [ "$before_mtime" = "$after_mtime" ]; then
  pass "deploy: a non-hex sha is rejected before touching git or the deploy command, exit 2"
else
  fail "deploy: non-hex sha (rc=$rc out=[$out])"
fi

# A well-formed but unknown-to-this-repo SHA is also rejected (commit not in
# local history), distinctly from the malformed-string case above.
out="$("$LADDER" deploy staging --sha "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" 2>&1)"
rc=$?
if [ "$rc" = "2" ] && printf '%s' "$out" | grep -q "not in local history"; then
  pass "deploy: a well-formed but unresolvable sha is rejected, exit 2"
else
  fail "deploy: unresolvable sha (rc=$rc out=[$out])"
fi

# ===========================================================================
# 9. lanes-config.sh check rejects a deploy/rollback command containing a
# `make -n` dry-run flag — make still executes $(MAKE) recipe lines under -n,
# so this is a real footgun, not a style nit.
# ===========================================================================
BAD_CONFIG="$WORK/bad-agent-lanes.json"
cat > "$BAD_CONFIG" <<'BADCFG'
{
  "namePrefix": "C",
  "deploy": {
    "environments": [
      { "name": "staging", "deploy": "make -n build", "health": "echo ok", "rollback": "" }
    ]
  }
}
BADCFG
out="$(LANES_CONFIG="$BAD_CONFIG" bash "$LANES_CONFIG_SH" check 2>&1)"
rc=$?
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -qF "FAIL staging.deploy uses a make dry-run flag"; then
  pass "lanes-config.sh check: rejects a deploy command containing 'make -n' (make still runs \$(MAKE) lines under -n)"
else
  fail "lanes-config.sh check: make -n rejection (rc=$rc out=[$out])"
fi

# A clean config (this test's own fixture) passes the same check.
out="$(LANES_CONFIG="$LANES_CONFIG" bash "$LANES_CONFIG_SH" check 2>&1)"
rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q "^OK "; then
  pass "lanes-config.sh check: this test's own fixture config passes"
else
  fail "lanes-config.sh check: clean fixture (rc=$rc out=[$out])"
fi

# Rollout that finishes after the deploy command returns: with a verify
# window, health is polled until it reports the SHA; without one, a single
# check reports MISMATCH (the old behavior, kept as the default).
out="$("$LADDER" deploy slow --sha "$COMMIT1" 2>&1)"; rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -qF "VERIFIED slow running ${COMMIT1:0:8}" \
   && [ "$(cat "$SLOW_COUNT")" = "3" ]; then
  pass "deploy: polls health through verifyTimeoutSeconds until the rollout reports the SHA"
else
  fail "deploy slow rollout (rc=$rc out=[$out] polls=$(cat "$SLOW_COUNT" 2>/dev/null))"
fi

out="$("$LADDER" deploy slownowait --sha "$COMMIT1" 2>&1)"; rc=$?
if [ "$rc" = "1" ] && printf '%s' "$out" | grep -q "MISMATCH slownowait"; then
  pass "deploy: with no verify window a not-yet-rolled-out deploy is MISMATCH"
else
  fail "deploy slownowait (rc=$rc out=[$out])"
fi

print_summary "ladder.sh"
