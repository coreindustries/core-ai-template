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
# exact names, so a slug that merely contains "template" is still checked.
ID_DIRS='^(prd|docs/decisions)/[^/]+\.md$'
NOT_AN_ID='^(prd/(_[^/]*|00_index\.md|00_technology\.md)|docs/decisions/(_[^/]*|index\.md|README\.md|adr-template\.md))$'
DATE_SLUG='/[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])-[a-z0-9][a-z0-9-]*\.md$'

# --no-renames: a rename shows up as an addition of its new name.
# core.quotePath=false: non-ASCII names come through unquoted, so the
# directory match sees them.
added="$(git -c core.quotePath=false diff --no-renames --diff-filter=A --name-only "${BASE}...${HEAD}")" || {
  echo "assert-doc-ids: cannot diff ${BASE}...${HEAD} — is the base fetched?" >&2
  exit 2
}

bad=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  printf '%s\n' "$f" | grep -qiE "$ID_DIRS" || continue
  printf '%s\n' "$f" | grep -qE "$NOT_AN_ID" && continue
  printf '%s\n' "$f" | grep -qE "$DATE_SLUG" && continue
  dir="$(dirname "$f")"
  echo "::error file=${f},title=Doc ID::${f} is not named by date+slug. Rename it to ${dir}/YYYY-MM-DD-<kebab-slug>.md (e.g. ${dir}/$(date -u +%F)-my-change.md). Sequential numbers collide when agents work in parallel." >&2
  bad=$((bad + 1))
done <<EOF
$added
EOF

if [ "$bad" -gt 0 ]; then
  echo "assert-doc-ids: ${bad} new doc(s) use a sequential ID." >&2
  exit 1
fi
echo "OK: new PRD/ADR files use date+slug IDs."
