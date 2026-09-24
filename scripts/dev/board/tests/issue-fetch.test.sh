#!/usr/bin/env bash
# issue-fetch.test.sh — unit tests for scripts/dev/board/issue-fetch.sh
# against FAKE `gh` and `curl` on PATH. No network calls.
#
# Fixture shape follows GitHub's documented attachment-URL scheme: a private
# repo's `user-attachments/assets/<uuid>` links 404 to an API token (they
# resolve only inside a browser session cookie), while the same asset's
# rendered `bodyHTML` carries a short-lived JWT-signed
# `private-user-images.githubusercontent.com` URL that downloads fine
# unauthenticated:
#   body (markdown): <img width="442" height="179" alt="Image"
#     src="https://github.com/user-attachments/assets/d478cd21-dca1-4d0a-8961-18635bd8629c" />
#     (also seen as: ![image](https://github.com/user-attachments/assets/<uuid>))
#   bodyHTML: <a ... href="https://private-user-images.githubusercontent.com/
#     117705/657661499-d478cd21-dca1-4d0a-8961-18635bd8629c.png?jwt=...">
#     <img ... src="https://private-user-images.githubusercontent.com/117705/
#     657661499-d478cd21-dca1-4d0a-8961-18635bd8629c.png?jwt=..." ...>
#     (query string HTML-escaped: `&amp;` for `&`)
# The fixtures below use a FICTIONAL uuid/user-id/issue-number/repo (no real
# content, no PII) but the exact URL/attribute shape above.
#
# Run: bash scripts/dev/board/tests/issue-fetch.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BOARD_DIR="$(cd "$TESTS_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BOARD_DIR/../../.." && pwd)"
ISSUE_FETCH="$BOARD_DIR/issue-fetch.sh"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

WORK="$(cd "$(mktemp -d)" && pwd -P)"
BIN="$WORK/bin"
mkdir -p "$BIN"
trap 'rm -rf "$WORK"' EXIT

# issue-fetch.sh sources lib.sh (and, transitively, lanes-config.sh) by its
# own dirname. Direct invocations of $ISSUE_FETCH below find the real copy
# automatically, but the one mutant built further down (dirname == $WORK)
# needs both sitting next to it, or it crashes at source-time before any of
# the logic under test ever runs. A disposable config fixture keeps this
# independent of the repo's real .claude/agent-lanes.json.
cp "$BOARD_DIR/lib.sh" "$WORK/lib.sh"
cp "$BOARD_DIR/lanes-config.sh" "$WORK/lanes-config.sh"
LANES_FIXTURE="$WORK/agent-lanes.json"
printf '{}' > "$LANES_FIXTURE"
export LANES_CONFIG="$LANES_FIXTURE"
export LANES_REPO_ROOT="$REPO_ROOT"

echo ""
echo "=== issue-fetch.sh unit tests ==="

# ---------------------------------------------------------------------------
# Fake gh — `api graphql` prints the file at $FAKE_GH_RESPONSE_FILE (a JSON
# fixture built per case below); `repo view` is unused (tests always pass
# --repo). FAKE_GH_FAIL=1 simulates a total gh failure (case e).
# ---------------------------------------------------------------------------
cat > "$BIN/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -uo pipefail
if [ "${FAKE_GH_FAIL:-0}" = "1" ]; then
  echo "fake gh: simulated auth/network failure" >&2
  exit 1
fi
if [ "${1:-}" = "api" ] && [ "${2:-}" = "graphql" ]; then
  if [ -z "${FAKE_GH_RESPONSE_FILE:-}" ] || [ ! -f "${FAKE_GH_RESPONSE_FILE:-}" ]; then
    echo "fake gh: no response fixture set" >&2
    exit 1
  fi
  cat "$FAKE_GH_RESPONSE_FILE"
  exit 0
fi
echo "fake gh: unhandled: $*" >&2
exit 1
FAKE_GH
chmod +x "$BIN/gh"

# ---------------------------------------------------------------------------
# Fake curl — dispatches on the uuid embedded in the URL path (before any
# `?`). Per-uuid fixtures (env vars, uuid upcased with `-` -> `_`):
#   FAKE_CURL_<UUID>_CODE  (default 200)
#   FAKE_CURL_<UUID>_TYPE  (default image/png)
#   FAKE_CURL_<UUID>_BODY  (default FAKEIMGDATA)
# Logs every invoked URL (including the query string) to $CURL_LOG so a test
# can assert curl received an UNESCAPED `&` (case c) — this is a test-only
# artifact in a tmp dir, never something the real tool prints to stdout.
# ---------------------------------------------------------------------------
cat > "$BIN/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -uo pipefail
outfile=""
prev=""
for a in "$@"; do
  case "$prev" in -o) outfile="$a" ;; esac
  prev="$a"
done
url="${!#}"
printf '%s\n' "$url" >> "${CURL_LOG:-/dev/null}"

path="${url%%\?*}"
uuid="$(printf '%s' "$path" | grep -oE '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')"
safe="$(printf '%s' "$uuid" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"

code_var="FAKE_CURL_${safe}_CODE"
type_var="FAKE_CURL_${safe}_TYPE"
body_var="FAKE_CURL_${safe}_BODY"
code="$(eval "printf '%s' \"\${${code_var}:-200}\"")"
type="$(eval "printf '%s' \"\${${type_var}:-image/png}\"")"
body="$(eval "printf '%s' \"\${${body_var}:-FAKEIMGDATA}\"")"

[ -n "$outfile" ] && printf '%s' "$body" > "$outfile"
printf '%s\t%s' "$code" "$type"
case "$code" in
  2??) exit 0 ;;
  *) exit 22 ;;
esac
FAKE_CURL
chmod +x "$BIN/curl"

export PATH="$BIN:$PATH"

UUID1="a1b2c3d4-e5f6-47a8-9abc-def012345678"
UUID2="11112222-3333-4444-5555-666677778888"
UUID3="99998888-7777-6666-5555-444433332222"
UUID1_SAFE="$(printf '%s' "$UUID1" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
UUID2_SAFE="$(printf '%s' "$UUID2" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"

# ===========================================================================
# Case (a): body image + comment image both download, markdown rewritten to
# LOCAL paths, IMAGES list correct, exit 0.
# ===========================================================================
RESP_A="$WORK/resp-a.json"
cat > "$RESP_A" <<EOF
{"data":{"repository":{"issue":{
  "number":9001,"title":"Screenshot repro","state":"OPEN",
  "url":"https://github.com/example-org/example-repo/issues/9001",
  "author":{"login":"fictional-user"},"createdAt":"2026-09-01T00:00:00Z",
  "labels":{"nodes":[{"name":"bug"}]},
  "body":"See screenshot:\n\n<img width=\"442\" height=\"179\" alt=\"Image\" src=\"https://github.com/user-attachments/assets/${UUID1}\" />\n",
  "bodyHTML":"<p>See screenshot:</p><a target=\"_blank\" href=\"https://private-user-images.githubusercontent.com/117705/657661499-${UUID1}.png?jwt=XYZ&amp;abc=1\"><img src=\"https://private-user-images.githubusercontent.com/117705/657661499-${UUID1}.png?jwt=XYZ&amp;abc=1\"/></a>",
  "comments":{"nodes":[
    {"author":{"login":"fictional-reporter"},"createdAt":"2026-09-02T00:00:00Z",
     "body":"here too: ![image](https://github.com/user-attachments/assets/${UUID2})",
     "bodyHTML":"<p>here too:</p><img src=\"https://private-user-images.githubusercontent.com/117705/999-${UUID2}.jpg?jwt=ABC\"/>"}
  ]}
}}}}
EOF

OUT_A="$WORK/out-a"
export FAKE_GH_RESPONSE_FILE="$RESP_A"
unset FAKE_GH_FAIL
export CURL_LOG="$WORK/curl-a.log"
: > "$CURL_LOG"
# comment's asset is served as image/jpeg — exercises Content-Type -> .jpg
export "FAKE_CURL_${UUID2_SAFE}_TYPE=image/jpeg"

stdout_a="$("$ISSUE_FETCH" 9001 --repo example-org/example-repo --out "$OUT_A" 2>"$WORK/stderr-a.log")"
rc_a=$?

if [ "$rc_a" = "0" ] \
   && [ -f "$OUT_A/body-1-${UUID1%%-*}.png" ] \
   && [ -f "$OUT_A/comment1-1-${UUID2%%-*}.jpg" ] \
   && printf '%s' "$stdout_a" | grep -qF "![image]($OUT_A/body-1-${UUID1%%-*}.png)" \
   && printf '%s' "$stdout_a" | grep -qF "![image]($OUT_A/comment1-1-${UUID2%%-*}.jpg)" \
   && ! printf '%s' "$stdout_a" | grep -q "user-attachments/assets/${UUID1}" \
   && ! printf '%s' "$stdout_a" | grep -q "user-attachments/assets/${UUID2}" \
   && printf '%s' "$stdout_a" | grep -qF "IMAGES:" \
   && printf '%s' "$stdout_a" | grep -qF "$OUT_A/body-1-${UUID1%%-*}.png" \
   && printf '%s' "$stdout_a" | grep -qF "$OUT_A/comment1-1-${UUID2%%-*}.jpg" \
   && printf '%s' "$stdout_a" | grep -qF "issue-fetch.sh: 2 images downloaded, 0 failed" \
   && [ -f "$OUT_A/issue.md" ] \
   && ! grep -q "jwt=" "$WORK/stderr-a.log" 2>/dev/null \
   && ! printf '%s' "$stdout_a" | grep -q "jwt=" \
   && ! grep -q "jwt=" "$OUT_A/issue.md" 2>/dev/null; then
  pass "(a) body + comment images download, rewritten to local paths, IMAGES + summary correct, exit 0, no jwt= leaked to stdout or issue.md"
else
  fail "(a) body+comment download (rc=$rc_a stdout=[$stdout_a] stderr=[$(cat "$WORK/stderr-a.log")] ls=[$(ls -la "$OUT_A" 2>&1)])"
fi

if ! grep -q '&amp;' "$CURL_LOG" && grep -q '&abc=1' "$CURL_LOG"; then
  pass "(c) &amp; unescaped to & before curl saw the URL"
else
  fail "(c) &amp; unescape (curl.log=[$(cat "$CURL_LOG")])"
fi

# ===========================================================================
# Case (b): one download fails (404) -> ERROR line, original URL kept,
# exit 3. Reuses UUID1(ok)/UUID2(fails) style but as a fresh scenario so
# exit code isn't muddied by case (a)'s success.
# ===========================================================================
RESP_B="$WORK/resp-b.json"
cat > "$RESP_B" <<EOF
{"data":{"repository":{"issue":{
  "number":9002,"title":"One broken image","state":"OPEN",
  "url":"https://github.com/example-org/example-repo/issues/9002",
  "author":{"login":"fictional-user"},"createdAt":"2026-09-01T00:00:00Z",
  "labels":{"nodes":[]},
  "body":"<img src=\"https://github.com/user-attachments/assets/${UUID3}\" />",
  "bodyHTML":"<img src=\"https://private-user-images.githubusercontent.com/117705/1-${UUID3}.png?jwt=DEAD\"/>",
  "comments":{"nodes":[]}
}}}}
EOF

UUID3_SAFE="$(printf '%s' "$UUID3" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
export "FAKE_CURL_${UUID3_SAFE}_CODE=404"

OUT_B="$WORK/out-b"
export FAKE_GH_RESPONSE_FILE="$RESP_B"
stdout_b="$("$ISSUE_FETCH" 9002 --repo example-org/example-repo --out "$OUT_B" 2>"$WORK/stderr-b.log")"
rc_b=$?

if [ "$rc_b" = "3" ] \
   && grep -q "ERROR issue-fetch.sh: image ${UUID3} from body failed (HTTP 404)" "$WORK/stderr-b.log" \
   && printf '%s' "$stdout_b" | grep -qF "user-attachments/assets/${UUID3}" \
   && printf '%s' "$stdout_b" | grep -qF "issue-fetch.sh: 0 images downloaded, 1 failed"; then
  pass "(b) failed download: ERROR on stderr, original URL kept, exit 3"
else
  fail "(b) failed download (rc=$rc_b stdout=[$stdout_b] stderr=[$(cat "$WORK/stderr-b.log")])"
fi
unset "FAKE_CURL_${UUID3_SAFE}_CODE"

# ===========================================================================
# Case (d): asset referenced in markdown but bodyHTML has NO matching signed
# URL for it -> WARN, left as-is, exit 0 (no download attempted at all).
# ===========================================================================
UUID_ORPHAN="deadbeef-0000-1111-2222-333344445555"
RESP_D="$WORK/resp-d.json"
cat > "$RESP_D" <<EOF
{"data":{"repository":{"issue":{
  "number":9003,"title":"Orphan reference","state":"OPEN",
  "url":"https://github.com/example-org/example-repo/issues/9003",
  "author":{"login":"fictional-user"},"createdAt":"2026-09-01T00:00:00Z",
  "labels":{"nodes":[]},
  "body":"![image](https://github.com/user-attachments/assets/${UUID_ORPHAN})",
  "bodyHTML":"<p>no matching signed url here</p>",
  "comments":{"nodes":[]}
}}}}
EOF

OUT_D="$WORK/out-d"
export FAKE_GH_RESPONSE_FILE="$RESP_D"
stdout_d="$("$ISSUE_FETCH" 9003 --repo example-org/example-repo --out "$OUT_D" 2>"$WORK/stderr-d.log")"
rc_d=$?

if [ "$rc_d" = "0" ] \
   && grep -q "WARN issue-fetch.sh: asset ${UUID_ORPHAN} referenced in body has no matching signed URL" "$WORK/stderr-d.log" \
   && printf '%s' "$stdout_d" | grep -qF "user-attachments/assets/${UUID_ORPHAN}" \
   && printf '%s' "$stdout_d" | grep -qF "issue-fetch.sh: 0 images downloaded, 0 failed"; then
  pass "(d) orphan asset reference: WARN, left as-is, exit 0"
else
  fail "(d) orphan reference (rc=$rc_d stdout=[$stdout_d] stderr=[$(cat "$WORK/stderr-d.log")])"
fi

# ===========================================================================
# Case (e): gh failure -> clear error, exit 2.
# ===========================================================================
export FAKE_GH_FAIL=1
stdout_e="$("$ISSUE_FETCH" 9999 --repo example-org/example-repo --out "$WORK/out-e" 2>"$WORK/stderr-e.log")"
rc_e=$?
unset FAKE_GH_FAIL

if [ "$rc_e" = "2" ] && grep -q "gh api graphql failed" "$WORK/stderr-e.log"; then
  pass "(e) gh failure: clear error on stderr, exit 2"
else
  fail "(e) gh failure (rc=$rc_e stdout=[$stdout_e] stderr=[$(cat "$WORK/stderr-e.log")])"
fi

# ===========================================================================
# Case (f): comments.pageInfo.hasNextPage true (>100 comments) -> WARN on
# stderr naming the truncation, still exit 0 for this reason alone.
# ===========================================================================
RESP_F="$WORK/resp-f.json"
cat > "$RESP_F" <<EOF
{"data":{"repository":{"issue":{
  "number":9004,"title":"Very chatty issue","state":"OPEN",
  "url":"https://github.com/example-org/example-repo/issues/9004",
  "author":{"login":"fictional-user"},"createdAt":"2026-09-01T00:00:00Z",
  "labels":{"nodes":[]},
  "body":"no images here",
  "bodyHTML":"<p>no images here</p>",
  "comments":{"pageInfo":{"hasNextPage":true},"nodes":[
    {"author":{"login":"fictional-reporter"},"createdAt":"2026-09-02T00:00:00Z",
     "body":"comment 1","bodyHTML":"<p>comment 1</p>"}
  ]}
}}}}
EOF

export FAKE_GH_RESPONSE_FILE="$RESP_F"
stdout_f="$("$ISSUE_FETCH" 9004 --repo example-org/example-repo --out "$WORK/out-f" 2>"$WORK/stderr-f.log")"
rc_f=$?
if [ "$rc_f" = "0" ] \
   && grep -q "WARN issue-fetch.sh: issue #9004 has more than 100 comments" "$WORK/stderr-f.log"; then
  pass "(f) comments.pageInfo.hasNextPage=true: WARN on stderr naming the truncation, exit 0"
else
  fail "(f) comment truncation WARN (rc=$rc_f stdout=[$stdout_f] stderr=[$(cat "$WORK/stderr-f.log")])"
fi

# ===========================================================================
# Mutation check: disable the rewrite (apply_replacement becomes a no-op)
# and confirm case (a) now FAILS — proves the test isn't vacuous. The mutant
# is a separate copy dropped in $WORK; the tracked issue-fetch.sh is never
# overwritten (matches issue-watch.test.sh's mutation-check pattern), so
# there is nothing to restore afterward and no window where a mid-test crash
# leaves the tracked script mutated on disk.
# ===========================================================================
echo ""
echo "--- mutation check: breaking apply_replacement ---"
MUTANT="$WORK/issue-fetch.no-rewrite-mutant.sh"

# Neuter the function body so it never rewrites the markdown.
awk '
  /^apply_replacement\(\) \{$/ { print; print "  return 0"; skipping=1; next }
  skipping && /^\}$/ { print; skipping=0; next }
  skipping { next }
  { print }
' "$ISSUE_FETCH" > "$MUTANT"
chmod +x "$MUTANT"

export FAKE_GH_RESPONSE_FILE="$RESP_A"
OUT_MUT="$WORK/out-mut"
stdout_mut="$("$MUTANT" 9001 --repo example-org/example-repo --out "$OUT_MUT" 2>"$WORK/stderr-mut.log")"
if printf '%s' "$stdout_mut" | grep -q "user-attachments/assets/${UUID1}"; then
  echo "  mutation check CONFIRMED: with the rewrite disabled, case (a)'s assertion (no raw user-attachments URL in output) now fails as expected"
  MUTATION_OK=1
else
  echo "  mutation check FAILED TO PROVE ANYTHING: output still had no raw user-attachments URL even with the rewrite disabled"
  MUTATION_OK=0
fi

if [ "$MUTATION_OK" = "1" ]; then
  pass "mutation check: disabling apply_replacement makes case (a)'s rewrite assertion fail"
else
  fail "mutation check: disabling apply_replacement did NOT make case (a) fail — test may be vacuous"
fi

print_summary "issue-fetch.sh tests"
