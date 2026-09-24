#!/usr/bin/env bash
# issue-fetch.sh — fetch a GitHub issue (body + comments) as readable
# markdown, with screenshot attachments downloaded to disk so an agent can
# `Read` them.
#
# The problem this solves: agent lane sessions need to read
# issues whose key evidence is a screenshot, but private-repo attachment
# URLs (`https://github.com/user-attachments/assets/<uuid>`, the ones that
# appear in the RAW markdown body/comments) return 404 to an API token —
# they only resolve inside a browser session cookie. GitHub's rendered
# `bodyHTML` (available from the GraphQL API, same call, no extra auth)
# instead carries short-lived JWT-signed `private-user-images.
# githubusercontent.com` URLs for the same assets, and THOSE download fine
# with a plain unauthenticated `curl`. The asset uuid appears in both the
# markdown reference and the signed URL's filename, which is how the two
# are matched up.
#
# Shape relied on (jwt redacted):
#   body (markdown):
#     <img width="442" height="179" alt="Image"
#          src="https://github.com/user-attachments/assets/d478cd21-dca1-4d0a-8961-18635bd8629c" />
#     (also seen as: ![image](https://github.com/user-attachments/assets/<uuid>))
#   bodyHTML:
#     <a ... href="https://private-user-images.githubusercontent.com/117705/
#          657661499-d478cd21-dca1-4d0a-8961-18635bd8629c.png?jwt=...">
#       <img ... src="https://private-user-images.githubusercontent.com/117705/
#          657661499-d478cd21-dca1-4d0a-8961-18635bd8629c.png?jwt=..." ...>
#     (query string may be HTML-escaped: `&amp;` for `&`)
#
# Usage:
#   issue-fetch.sh <issue-number> [--repo owner/name] [--out DIR] [--no-comments]
#
#   <issue-number>  Required, numeric.
#   --repo          owner/name. Default: $BOARD_REPO, else
#                   `gh repo view --json nameWithOwner`.
#   --out DIR       Output directory (created if missing). Default:
#                   ${BOARD_ISSUE_DIR:-${TMPDIR:-/tmp}/board-issues}/<repo-slug>-<n>/
#   --no-comments   Fetch is still one GraphQL call (comments included), but
#                   comments are omitted from the printed/written document
#                   and no comment images are downloaded.
#
# Behavior:
#   1. One `gh api graphql` call fetches number/title/state/url/author/
#      createdAt/labels/body/bodyHTML for the issue plus the same for its
#      first 100 comments.
#   2. For the body and each comment: private-user-images URLs are pulled
#      out of bodyHTML (with `&amp;` unescaped back to `&` BEFORE curl ever
#      sees the URL — an escaped `&` truncates the jwt query string), each
#      is downloaded once (`curl -fsSL --max-time 30`, deduped by uuid
#      across the whole issue), and named
#      `<source>-<k>-<uuid8>.<ext>` (source = body|comment<N>, ext from the
#      response Content-Type).
#   3. A single markdown document is written to stdout AND to
#      `<out>/issue.md`: header (title, #, state, labels, url, author,
#      created), the body, then each comment. Every user-attachments asset
#      reference (`![...](url)` or `<img ... src="url" ...>`) whose uuid was
#      downloaded is rewritten to `![image](<absolute local path>)`.
#   4. Stdout ends with an `IMAGES:` section (one absolute path per line,
#      successful downloads only) and a summary line:
#      `issue-fetch: <n> images downloaded, <m> failed`.
#   5. Failure is loud, never silent:
#        - a download that fails prints `ERROR issue-fetch: image <uuid>
#          from <source> failed (HTTP <code>)` to stderr, leaves the
#          original (unsigned) URL in the markdown, and the script exits 3
#          at the end (after finishing everything else).
#        - `gh` failing (auth, network, no such issue) prints a clear error
#          to stderr and exits 2 immediately.
#        - an asset referenced in the markdown with NO matching signed URL
#          in bodyHTML prints `WARN issue-fetch: asset <uuid> referenced in
#          <source> has no matching signed URL ...` to stderr (not silent)
#          and leaves the reference untouched; this alone does not force a
#          non-zero exit.
#        - the GraphQL query fetches only the first 100 comments
#          (`comments(first: 100)`); an issue with more prints `WARN
#          issue-fetch: issue #<n> has more than 100 comments — only the
#          first 100 are included (pagination not implemented)` to stderr
#          (read from `comments.pageInfo.hasNextPage`) and still exits 0 for
#          this reason alone — the document is a truncated-but-labeled
#          partial, not a silent one.
#      The jwt query string is never written to stdout — only uuids, http
#      codes, source names and local file paths ever appear in script
#      output.
#
# Portability: bash 3.2 (macOS) + Linux. No `declare -A`, no `mapfile`, no
# GNU-only sed/date flags — BSD sed's `-E` (also accepted by modern GNU sed)
# and small scratch files stand in for associative arrays.
#
# No `set -e`: this script's normal control flow includes commands that are
# EXPECTED to fail sometimes (grep finding nothing, a signed URL 404ing) and
# must be handled inline rather than aborting the whole run — see
# board.sh's tighter `set -euo pipefail` for contrast; that script's control
# flow doesn't have this shape.
set -uo pipefail

SCRIPT_NAME="issue-fetch.sh"
# shellcheck disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

usage() {
  cat <<'EOF'
Usage: issue-fetch.sh <issue-number> [--repo owner/name] [--out DIR] [--no-comments]
EOF
}


ISSUE_NUM=""
REPO=""
OUT_DIR=""
NO_COMMENTS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      [ $# -ge 2 ] || die "--repo requires a value"
      REPO="$2"; shift 2 ;;
    --out)
      [ $# -ge 2 ] || die "--out requires a value"
      OUT_DIR="$2"; shift 2 ;;
    --no-comments)
      NO_COMMENTS=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    -*)
      usage >&2
      die "unknown option: $1" ;;
    *)
      if [ -n "$ISSUE_NUM" ]; then
        usage >&2
        die "unexpected argument: $1"
      fi
      ISSUE_NUM="$1"; shift ;;
  esac
done

[ -n "$ISSUE_NUM" ] || { usage >&2; die "missing <issue-number>"; }
case "$ISSUE_NUM" in
  ''|*[!0-9]*) die "issue number must be numeric: $ISSUE_NUM" ;;
esac

if [ -z "$REPO" ]; then
  REPO="${BOARD_REPO:-}"
fi
if [ -z "$REPO" ]; then
  REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
fi
[ -n "$REPO" ] || die "could not resolve repo — pass --repo owner/name, set BOARD_REPO, or run inside a repo gh can identify"

OWNER="${REPO%%/*}"
NAME="${REPO#*/}"
[ -n "$OWNER" ] && [ -n "$NAME" ] && [ "$OWNER" != "$REPO" ] || die "--repo must be owner/name, got: $REPO"

REPO_SLUG="$(printf '%s' "$REPO" | tr '/' '-')"
if [ -z "$OUT_DIR" ]; then
  BASE="${BOARD_ISSUE_DIR:-${TMPDIR:-/tmp}/board-issues}"
  OUT_DIR="${BASE%/}/${REPO_SLUG}-${ISSUE_NUM}"
fi
mkdir -p "$OUT_DIR" || die "could not create output dir: $OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/issue-fetch.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# 1. One GraphQL call.
# ---------------------------------------------------------------------------
QUERY='query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      number
      title
      state
      url
      author { login }
      createdAt
      labels(first: 20) { nodes { name } }
      body
      bodyHTML
      comments(first: 100) {
        pageInfo { hasNextPage }
        nodes {
          author { login }
          createdAt
          body
          bodyHTML
        }
      }
    }
  }
}'

RESP="$WORK/resp.json"
if ! gh api graphql -f query="$QUERY" -f owner="$OWNER" -f name="$NAME" -F number="$ISSUE_NUM" \
    > "$RESP" 2>"$WORK/gh.err"; then
  die "gh api graphql failed for ${OWNER}/${NAME}#${ISSUE_NUM}: $(tr '\n' ' ' < "$WORK/gh.err")"
fi

if [ "$(jq -r '.data.repository.issue // empty' "$RESP" 2>/dev/null)" = "" ]; then
  die "issue #${ISSUE_NUM} not found in ${OWNER}/${NAME}, or the response had no data"
fi

if [ "$(jq -r '.data.repository.issue.comments.pageInfo.hasNextPage // false' "$RESP" 2>/dev/null)" = "true" ]; then
  echo "WARN ${SCRIPT_NAME}: issue #${ISSUE_NUM} has more than 100 comments — only the first 100 are included (pagination not implemented)" >&2
fi

TITLE="$(jq -r '.data.repository.issue.title // ""' "$RESP")"
STATE="$(jq -r '.data.repository.issue.state // ""' "$RESP")"
ISSUE_URL="$(jq -r '.data.repository.issue.url // ""' "$RESP")"
ISSUE_AUTHOR="$(jq -r '.data.repository.issue.author.login // "unknown"' "$RESP")"
CREATED_AT="$(jq -r '.data.repository.issue.createdAt // ""' "$RESP")"
LABELS="$(jq -r '[.data.repository.issue.labels.nodes[]?.name] | join(", ")' "$RESP")"

jq -r '.data.repository.issue.body // ""' "$RESP" > "$WORK/body.md"
jq -r '.data.repository.issue.bodyHTML // ""' "$RESP" > "$WORK/body.html"

NCOMMENTS="$(jq -r '.data.repository.issue.comments.nodes | length' "$RESP" 2>/dev/null || echo 0)"
case "$NCOMMENTS" in ''|*[!0-9]*) NCOMMENTS=0 ;; esac

i=0
while [ "$i" -lt "$NCOMMENTS" ]; do
  n=$((i + 1))
  jq -r ".data.repository.issue.comments.nodes[$i].body // \"\"" "$RESP" > "$WORK/comment${n}.md"
  jq -r ".data.repository.issue.comments.nodes[$i].bodyHTML // \"\"" "$RESP" > "$WORK/comment${n}.html"
  jq -r ".data.repository.issue.comments.nodes[$i].author.login // \"unknown\"" "$RESP" > "$WORK/comment${n}.author"
  jq -r ".data.repository.issue.comments.nodes[$i].createdAt // \"\"" "$RESP" > "$WORK/comment${n}.created"
  i=$n
done

# ---------------------------------------------------------------------------
# 2. Attachment extraction / download / dedupe.
# ---------------------------------------------------------------------------
UUID_RE='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
REGISTRY="$WORK/registry.tsv"
: > "$REGISTRY"
IMAGES_OK=0
IMAGES_FAIL=0

# Replace every markdown/html reference to user-attachments asset $uuid in
# $file with a local image link to $path (absolute). sed delimiter is `|`
# (not expected in our own generated paths); ampersand/backslash/pipe in the
# replacement are escaped defensively anyway.
apply_replacement() {
  local file="$1" uuid="$2" path="$3" esc_path
  esc_path="$(printf '%s' "$path" | sed -e 's/[\&|]/\\&/g')"
  sed -E \
    -e "s|!\[[^]]*\]\(https://github\.com/user-attachments/assets/${uuid}\)|![image](${esc_path})|g" \
    -e "s|<img[^>]*src=\"https://github\.com/user-attachments/assets/${uuid}\"[^>]*/?>|![image](${esc_path})|g" \
    "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Build (into $WORK/<source>.urlmap, TSV uuid\turl) the map of asset uuid ->
# signed private-user-images URL found in this source's bodyHTML, then walk
# every user-attachments reference found in this source's raw markdown and
# download/replace/warn as appropriate. Global dedupe (across sources) is
# via $REGISTRY.
process_source() {
  local source="$1" md_file="$2" html_file="$3"
  local seen_file="$WORK/${source}.seen"
  local urlmap="$WORK/${source}.urlmap"
  local k=0

  : > "$seen_file"
  : > "$urlmap"

  # Unescape &amp; -> & BEFORE extracting URLs — an escaped & truncates the
  # jwt query string at the first param and curl gets a mangled/expired URL.
  sed 's/&amp;/\&/g' "$html_file" > "$WORK/${source}.html.unesc" 2>/dev/null || \
    cp "$html_file" "$WORK/${source}.html.unesc"

  grep -oE 'https://private-user-images\.githubusercontent\.com/[^"'"'"'<> ]+' \
    "$WORK/${source}.html.unesc" 2>/dev/null > "$WORK/${source}.urls.raw" || : > "$WORK/${source}.urls.raw"

  while IFS= read -r url; do
    [ -n "$url" ] || continue
    local path uuid
    path="${url%%\?*}"
    uuid="$(printf '%s' "$path" | grep -oE "$UUID_RE" | tail -n1 | tr '[:upper:]' '[:lower:]')"
    [ -n "$uuid" ] || continue
    if ! awk -F'\t' -v u="$uuid" '$1==u{f=1} END{exit !f}' "$urlmap" 2>/dev/null; then
      printf '%s\t%s\n' "$uuid" "$url" >> "$urlmap"
    fi
  done < "$WORK/${source}.urls.raw"

  grep -oE "user-attachments/assets/${UUID_RE}" "$md_file" 2>/dev/null \
    | sed -e 's#user-attachments/assets/##' \
    | tr '[:upper:]' '[:lower:]' \
    > "$WORK/${source}.refs.raw" || : > "$WORK/${source}.refs.raw"

  while IFS= read -r uuid; do
    [ -n "$uuid" ] || continue
    grep -qxF "$uuid" "$seen_file" 2>/dev/null && continue
    echo "$uuid" >> "$seen_file"

    local signed_url
    signed_url="$(awk -F'\t' -v u="$uuid" '$1==u{print $2; exit}' "$urlmap" 2>/dev/null)"
    if [ -z "$signed_url" ]; then
      echo "WARN ${SCRIPT_NAME}: asset ${uuid} referenced in ${source} has no matching signed URL in bodyHTML — left as-is" >&2
      continue
    fi

    local reg_line
    reg_line="$(awk -F'\t' -v u="$uuid" '$1==u{print; exit}' "$REGISTRY" 2>/dev/null)"
    if [ -n "$reg_line" ]; then
      local status path
      status="$(printf '%s' "$reg_line" | awk -F'\t' '{print $2}')"
      path="$(printf '%s' "$reg_line" | awk -F'\t' '{print $3}')"
      [ "$status" = "ok" ] && apply_replacement "$md_file" "$uuid" "$path"
      continue
    fi

    k=$((k + 1))
    local uuid8 tmpfile out_line http_code content_type ok ext finalpath
    uuid8="${uuid%%-*}"
    tmpfile="$WORK/dl.${source}.${k}"
    out_line="$(curl -fsSL --max-time 30 -o "$tmpfile" -w '%{http_code}\t%{content_type}' "$signed_url" 2>/dev/null)"
    rc=$?
    http_code="${out_line%%$'\t'*}"
    content_type="${out_line#*$'\t'}"
    [ -n "$http_code" ] || http_code="000"

    ok=0
    case "$http_code" in 2??) ok=1 ;; esac

    if [ "$rc" -eq 0 ] && [ "$ok" -eq 1 ]; then
      ext="bin"
      case "$content_type" in
        image/png*) ext="png" ;;
        image/jpeg*|image/jpg*) ext="jpg" ;;
        image/gif*) ext="gif" ;;
        image/webp*) ext="webp" ;;
      esac
      finalpath="$OUT_DIR/${source}-${k}-${uuid8}.${ext}"
      mv "$tmpfile" "$finalpath"
      printf '%s\tok\t%s\n' "$uuid" "$finalpath" >> "$REGISTRY"
      apply_replacement "$md_file" "$uuid" "$finalpath"
      IMAGES_OK=$((IMAGES_OK + 1))
    else
      echo "ERROR ${SCRIPT_NAME}: image ${uuid} from ${source} failed (HTTP ${http_code})" >&2
      printf '%s\tfail\t%s\n' "$uuid" "$http_code" >> "$REGISTRY"
      IMAGES_FAIL=$((IMAGES_FAIL + 1))
      rm -f "$tmpfile"
    fi
  done < "$WORK/${source}.refs.raw"
}

process_source "body" "$WORK/body.md" "$WORK/body.html"

if [ "$NO_COMMENTS" -eq 0 ]; then
  i=1
  while [ "$i" -le "$NCOMMENTS" ]; do
    process_source "comment${i}" "$WORK/comment${i}.md" "$WORK/comment${i}.html"
    i=$((i + 1))
  done
fi

# ---------------------------------------------------------------------------
# 3. Assemble the document.
# ---------------------------------------------------------------------------
DOC="$OUT_DIR/issue.md"
{
  echo "# ${TITLE} (#${ISSUE_NUM})"
  echo ""
  echo "- State: ${STATE}"
  echo "- Labels: ${LABELS:-none}"
  echo "- URL: ${ISSUE_URL}"
  echo "- Author: ${ISSUE_AUTHOR}"
  echo "- Created: ${CREATED_AT}"
  echo ""
  echo "## Body"
  echo ""
  cat "$WORK/body.md"
  echo ""
  if [ "$NO_COMMENTS" -eq 0 ] && [ "$NCOMMENTS" -gt 0 ]; then
    echo "## Comments"
    i=1
    while [ "$i" -le "$NCOMMENTS" ]; do
      cauthor="$(cat "$WORK/comment${i}.author" 2>/dev/null || echo unknown)"
      ccreated="$(cat "$WORK/comment${i}.created" 2>/dev/null || echo "")"
      echo ""
      echo "### Comment by ${cauthor} (${ccreated})"
      echo ""
      cat "$WORK/comment${i}.md"
      i=$((i + 1))
    done
  fi
} > "$DOC"

cat "$DOC"

# ---------------------------------------------------------------------------
# 4. IMAGES + summary (never the jwt-bearing signed URL — paths only).
# ---------------------------------------------------------------------------
echo ""
echo "IMAGES:"
awk -F'\t' '$2=="ok"{print $3}' "$REGISTRY"

echo ""
echo "${SCRIPT_NAME}: ${IMAGES_OK} images downloaded, ${IMAGES_FAIL} failed"

if [ "$IMAGES_FAIL" -gt 0 ]; then
  exit 3
fi
exit 0
