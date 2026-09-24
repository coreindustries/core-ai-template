#!/usr/bin/env bash
# assert-doc-ids.sh — a PRD or ADR added on this branch must be named by date
# and slug (YYYY-MM-DD-<slug>.md), never by "the next number".
#
# Why: "read the highest number, add one" races when agents work in parallel.
# Two of them pick the same number, and nobody finds out until both merge.
# A date plus a slug needs no shared counter. Numbered docs already on the base
# are grandfathered: only files this branch ADDS are checked. A rename counts
# as adding its new name, because renumbering is how the counter comes back.
#
# Usage: scripts/assert-doc-ids.sh [base-ref [head-ref]]
#        (default: origin/main HEAD — compares the merge base to head)
# Used by .github/workflows/doc-id-lint.yml and `make pr-check`.
set -euo pipefail

BASE="${1:-origin/main}"
HEAD="${2:-HEAD}"

# Top-level markdown in these directories carries an ID (any case of .md, so
# `.MD` cannot slip past). Subdirectories (prd/tasks/) do not. Exemptions are
# exact names or `_*template*.md`, so a slug that merely contains "template",
# or merely starts with `_` or `00_`, is still checked.
# Known limitation: day-of-month is range-checked (01-31), not calendar-checked,
# so 2026-02-31 passes. A bad date cannot cause a collision, which is the point.
ID_DIRS='^(prd|docs/decisions)/[^/]+\.md$'
NOT_AN_ID='^(prd/(_[^/]*[Tt][Ee][Mm][Pp][Ll][Aa][Tt][Ee][^/]*\.md|00_index\.md|00_technology\.md)|docs/decisions/(index\.md|README\.md|adr-template\.md))$'
DATE_SLUG='/[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])-[a-z0-9][a-z0-9-]*\.md$'

# --no-renames: a rename shows up as an addition of its new name.
# -z: names arrive NUL-separated and unquoted, so a tab, quote, newline or
# non-ASCII character cannot hide a name. Matching uses [[ =~ ]] on the whole
# name, never line-oriented grep.
list="$(mktemp)"
trap 'rm -f "$list"' EXIT
git diff -z --no-renames --diff-filter=A --name-only "${BASE}...${HEAD}" > "$list" || {
  echo "assert-doc-ids: cannot diff ${BASE}...${HEAD} — is the base fetched?" >&2
  exit 2
}

bad=0
while IFS= read -r -d '' f; do
  [ -n "$f" ] || continue
  shopt -s nocasematch
  in_dir=1
  [[ "$f" =~ $ID_DIRS ]] && in_dir=0
  shopt -u nocasematch
  [ "$in_dir" -eq 0 ] || continue
  [[ "$f" =~ $NOT_AN_ID ]] && continue
  [[ "$f" =~ $DATE_SLUG ]] && continue
  shown="$(printf '%q' "$f")"
  dir="$(dirname "$f")"
  echo "::error title=Doc ID::${shown} is not named by date+slug (renames count as additions). Rename it to ${dir}/YYYY-MM-DD-<kebab-slug>.md (e.g. ${dir}/$(date -u +%F)-my-change.md). Sequential numbers collide when agents work in parallel." >&2
  bad=$((bad + 1))
done < "$list"

if [ "$bad" -gt 0 ]; then
  echo "assert-doc-ids: ${bad} new doc(s) use a sequential ID." >&2
  exit 1
fi
echo "OK: new PRD/ADR files use date+slug IDs."
