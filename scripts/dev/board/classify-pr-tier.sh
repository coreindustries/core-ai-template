#!/usr/bin/env bash
# classify-pr-tier.sh <pr-number> — classifies a pull request into an
# auto-merge tier for .github/workflows/auto-merge.yml.
#
# Prints exactly one line, `tier=<0-3>`, to stdout, and NEVER exits non-zero
# for an ordinary classification outcome — every failure mode (missing
# input, a `gh`/API error) fails CLOSED to tier=3 (needs-review, never
# auto-merges) rather than crashing the calling step or falling back to a
# title-only guess made from data we could not fully verify.
#
# Inputs (env):
#   GH_REPO   "owner/repo" — REQUIRED. This step runs with no checkout of
#             the PR's own repo content by default (see auto-merge.yml's
#             anti-tamper base-commit checkout, which is unrelated content),
#             so `gh` cannot reliably infer the repo from a git remote.
#   GH_TOKEN  a token with pull-requests:read — required for the changed-
#             files lookup.
#   PR_TITLE  the PR title. Read from the webhook payload
#             (github.event.pull_request.title) by the caller, not
#             re-fetched here — the workflow already has it for free, and
#             re-fetching would be one more call that can itself fail.
#   LABELS    JSON array of label names
#             (toJSON(github.event.pull_request.labels.*.name)). Same
#             reasoning as PR_TITLE.
#
# Usage: classify-pr-tier.sh <pr-number>
#
# Tier 3 — prd/ sensitive path (see PRD_SENSITIVE_PATTERN below), OR a
#          protected area label (auth/billing/database/infra), OR any
#          classification failure (fail-closed default).
# Tier 0 — chore/docs/style commit-title prefix.
# Tier 1 — fix commit-title prefix.
# Tier 2 — feat, or anything else (unknown prefix).
#
# Portability: macOS bash 3.2 + Linux (matches scripts/dev/board/board.sh —
# no `declare -A`, no GNU-only date/sed flags).
set -uo pipefail

PR_NUMBER="${1:-}"

# fail_closed <reason> — always tier 3, always exit 0. This script IS the
# classifier; a crash here must never leave the calling workflow step in an
# undefined state, and every failure must be treated at least as
# conservatively as the highest-risk classification.
fail_closed() {
  echo "::warning title=Auto-merge classifier fail-closed::${1}" >&2
  echo "tier=3"
  exit 0
}

[ -n "$PR_NUMBER" ] || fail_closed "usage: classify-pr-tier.sh <pr-number> — no PR number given"
[ -n "${GH_REPO:-}" ] || fail_closed "GH_REPO is not set — cannot look up PR #${PR_NUMBER}'s changed files"
command -v gh >/dev/null 2>&1 || fail_closed "gh CLI not found on PATH"

# prd/ is sensitive for a different reason than the area labels below: a
# "grooming-only" PRD PR can still change scope under the hood — flipping a
# PRD's frontmatter `status` to Superseded/Deprecated hides its FRs from
# `board.sh prd-scan` (which skips deprecated/superseded/dropped/cancelled
# PRDs), and adding FR ids to a previously-unnumbered PRD creates real
# FEATURES-lane work. The prd-manager skill's own commit-prefix convention
# (📝 docs(prd): vs ✨ feat(prd):) is a hint for reviewers, not a merge-path
# decision, so this reads the actual changed files rather than trusting the
# prefix — and it can't depend on the labeler workflow's area/agent label
# either: that workflow races this one on the same PR events and area/agent
# covers more than just prd/ anyway (`.claude/**`, `docs/decisions/**`, ...).
#
# PRD_SENSITIVE_PATTERN's directory is the PRD root this template uses
# (`prd/`, see `.claude/agent-lanes.json`'s `prd.glob`) — hardcoded here
# because this script has no jq/config reader wired to it; keep the two in
# sync if the PRD directory ever moves. Pinned by
# scripts/dev/board/tests/classify-pr-tier.test.sh.
PRD_SENSITIVE_PATTERN='^prd/'

# --paginate + previous_filename: `gh pr view --json files` caps at one REST
# page (100 files), and its GraphQL-backed `files` field has no rename-source
# information at all — a PR that moves a file OUT of prd/ (renamed to
# somewhere else) would be entirely invisible to a current-filename-only
# check. This hits the REST `pulls/<n>/files` endpoint directly with
# `--paginate` (all pages) and the `--jq` emits BOTH the current filename and
# (when the entry is a rename) the pre-rename name on its own line, so a
# rename either into or out of prd/ still produces a prd/ line here.
#
# One call feeds both the prd/ guard and the completeness count below, so a
# truncated listing can't pass the count check while the guard reads a
# different response. Each line is tagged: `F\t<filename>` (counted) or
# `P\t<previous_filename>` (rename source, not counted in changed_files).
# stderr goes to a file so gh warnings never corrupt the listing.
ERR_FILE="$(mktemp)"
trap 'rm -f "$ERR_FILE"' EXIT
TAGGED="$(gh api --paginate "repos/${GH_REPO}/pulls/${PR_NUMBER}/files" \
  --jq '.[] | "F\t\(.filename)", (.previous_filename // empty | "P\t\(.)")' 2>"$ERR_FILE")"
rc=$?
if [ "$rc" -ne 0 ]; then
  fail_closed "gh api repos/${GH_REPO}/pulls/${PR_NUMBER}/files failed (exit ${rc}): $(head -1 "$ERR_FILE")"
fi
# cut, not sed '\t': BSD sed does not reliably read \t, and a tag left on
# every line would make the ^prd/ guard never match (fail open).
CHANGED_FILES="$(cut -f2- <<<"$TAGGED")"
LISTED_COUNT="$(cut -f1 <<<"$TAGGED" | grep -c '^F$' || true)"

# The listing must be complete, or an unseen file could be under prd/. The
# REST files endpoint stops at 3000 files even with --paginate, so compare
# against the PR's own changed_files count and fail closed on any shortfall.
EXPECTED_COUNT="$(gh api "repos/${GH_REPO}/pulls/${PR_NUMBER}" --jq '.changed_files' 2>"$ERR_FILE")"
rc=$?
if [ "$rc" -ne 0 ] || ! [[ "$EXPECTED_COUNT" =~ ^[0-9]+$ ]]; then
  fail_closed "could not read changed_files for PR #${PR_NUMBER} (exit ${rc}): $(head -1 "$ERR_FILE")"
fi
if [ "$EXPECTED_COUNT" -ge 3000 ]; then
  fail_closed "PR #${PR_NUMBER} changes ${EXPECTED_COUNT} files — the files API lists at most 3000, so prd/ cannot be ruled out"
fi
if [ "${LISTED_COUNT:-0}" -lt "$EXPECTED_COUNT" ]; then
  fail_closed "the files API listed ${LISTED_COUNT:-0} of ${EXPECTED_COUNT} changed files for PR #${PR_NUMBER} — prd/ cannot be ruled out"
fi

# Here-strings, never `printf … | grep -q`: under pipefail, grep -q exiting on
# an early match makes printf die of SIGPIPE once the input exceeds the pipe
# buffer (~64KB), the pipeline returns 141, and a matching guard reads as
# "no match" — the PR would then fall through to its title tier.
if grep -qE "$PRD_SENSITIVE_PATTERN" <<<"$CHANGED_FILES"; then
  echo "tier=3"
  exit 0
fi

# Tier 3: protected areas set by labeler.yml
if grep -qE '"area/(auth|billing|database|infra)"' <<<"${LABELS:-}"; then
  echo "tier=3"
  exit 0
fi

TITLE="${PR_TITLE:-}"

# Tier 0: chore, docs, style (with or without gitmoji prefix)
if grep -qiE '^(🔧 chore|📝 docs|🎨 style|chore|docs|style):' <<<"$TITLE"; then
  echo "tier=0"
  exit 0
fi

# Tier 1: fix (with or without gitmoji prefix)
if grep -qiE '^(🐛 fix|fix):' <<<"$TITLE"; then
  echo "tier=1"
  exit 0
fi

# Tier 2: feat, or anything else (unknown prefix)
echo "tier=2"
