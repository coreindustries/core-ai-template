#!/usr/bin/env bash
# release-prs.sh — list merged PRs in a SHA range with a deploy-bound
# classification and each PR body's verbatim `## Real Proof` section, so the
# Release Manager builds its per-PR proof checklist deterministically instead
# of re-reading PR bodies by hand.
#
# Usage: release-prs.sh <from-sha> <to-sha> [--json]
#
# Parses `(#NNNN)` off squash-merge subjects via `git log`, then asks `gh`
# for each PR's files + body. Requires local git history for the range.
# "Deploy-bound" = touches a prefix in deploy.boundPaths (.claude/agent-lanes.json).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage: release-prs.sh <from-sha> <to-sha> [--json]
EOF
}

from="${1:-}"
to="${2:-}"
[ -n "$from" ] && [ -n "$to" ] || { usage >&2; exit 2; }
shift 2 || true

as_json=0
for a in "$@"; do [ "$a" = "--json" ] && as_json=1; done

command -v gh >/dev/null 2>&1 || { echo "release-prs.sh: 'gh' not found on PATH" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "release-prs.sh: 'jq' not found on PATH" >&2; exit 2; }

BOUND_PREFIXES="$(lanes_cfg '(.deploy.boundPaths // []) | join("\n")' '')"

pr_numbers="$(git log --pretty=%s "${from}..${to}" | grep -Eo '\(#[0-9]+\)$' | grep -Eo '[0-9]+' | sort -un || true)"

if [ -z "$pr_numbers" ]; then
  echo "release-prs.sh: no merged-PR subjects found in ${from}..${to}" >&2
fi

results="[]"
for n in $pr_numbers; do
  view="$(gh pr view "$n" --json number,title,mergeCommit,body,files 2>&1)" \
    || { echo "release-prs.sh SKIPPED #${n}: gh pr view failed — $(printf '%s' "$view" | head -1)" >&2; continue; }

  printf '%s' "$view" | jq -e . >/dev/null 2>&1 \
    || { echo "release-prs.sh SKIPPED #${n}: gh pr view returned non-JSON" >&2; continue; }

  deploy_bound="false"
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    while IFS= read -r prefix; do
      [ -z "$prefix" ] && continue
      case "$path" in
        "$prefix"*) deploy_bound="true" ;;
      esac
    done <<EOF
$BOUND_PREFIXES
EOF
  done <<EOF
$(printf '%s' "$view" | jq -r '(.files // [])[].path')
EOF

  real_proof="$(printf '%s' "$view" | jq -r '.body // ""' | awk '
    /^##[[:space:]]+Real Proof/ { capture=1; next }
    /^##[[:space:]]/ { if (capture) exit }
    capture { print }
  ' | awk 'BEGIN{started=0} { if (!started && $0 == "") next; started=1; print }')"

  entry="$(jq -nc --argjson v "$view" --argjson deploy_bound "$deploy_bound" --arg proof "$real_proof" \
    '{number: $v.number, title: $v.title, mergeSha: ($v.mergeCommit.oid // null),
      deployBound: $deploy_bound, realProof: $proof}')"
  results="$(printf '%s' "$results" | jq -c --argjson e "$entry" '. + [$e]')"
done

if [ "$as_json" = "1" ]; then
  printf '%s\n' "$results"
  exit 0
fi

printf '%s' "$results" | jq -r '.[] | "#\(.number)  deployBound=\(.deployBound)  \(.title)\n\(if .realProof == "" then "NO-PROOF: body has no ## Real Proof section" else .realProof end)\n"'
