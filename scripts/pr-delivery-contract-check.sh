#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# pr-delivery-contract-check.sh
# -----------------------------------------------------------------------------
# Requires an evidence section in the PR body when a PR touches a high-risk
# surface — the places where a silent failure ships and nobody notices for a
# week: model/prompt changes, infra and deploy, database writers, scheduled
# jobs, cost-bearing API calls, and user-visible UI.
#
# Low-risk PRs (docs, tests, comments) are exempt and cost nothing.
#
# The PR body arrives on stdin. The changed-file list is derived from BASE_REF,
# or supplied via CHANGED_FILES for testing.
#
# Usage:
#   printf '%s' "$PR_BODY" | scripts/pr-delivery-contract-check.sh
#
# Env:
#   BASE_REF       base to diff against (default: origin/main)
#   CHANGED_FILES  newline-separated override for the diff (testing)
#   MODE           enforce (default) | warn — warn never exits non-zero
#
# See .claude/rules/delivery-contract.md
# -----------------------------------------------------------------------------
set -euo pipefail

MODE=${MODE:-enforce}
BASE_REF=${BASE_REF:-origin/main}

RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
GREEN=$'\033[0;32m'
RESET=$'\033[0m'

BODY=$(cat || true)

if [[ -n "${CHANGED_FILES:-}" ]]; then
  CHANGED="$CHANGED_FILES"
elif git rev-parse "$BASE_REF" >/dev/null 2>&1; then
  CHANGED=$(git diff --name-only "$BASE_REF"...HEAD 2>/dev/null || true)
else
  echo "${YELLOW}WARN:${RESET} base ref $BASE_REF not found — skipping."
  exit 0
fi

if [[ -z "$CHANGED" ]]; then
  echo "${GREEN}OK:${RESET} no changed files."
  exit 0
fi

# -- risk classification ------------------------------------------------------
# Each class is a description plus an extended regex over changed paths. Tune
# these per project; the defaults assume this template's layout.

RISK_NAMES=(
  "LLM / prompt / agent behavior"
  "Infra, CI, or deploy"
  "Database schema or writers"
  "Scheduled / background jobs"
  "Cost-bearing API surface"
  "User-visible UI"
)

RISK_PATTERNS=(
  '(^|/)(prompts?|llm|agents?|inference)/|(claude|anthropic|openai|gemini|bedrock)[^/]*\.(py|ts|tsx|js|mjs|go|rb)$|^\.claude/(agents|skills)/'
  '(^|/)Dockerfile|docker-compose|^\.github/workflows/|^(terraform|infra|k8s|helm|deploy)/|^Makefile$|^\.github/dependabot\.yml$'
  '^supabase/migrations/|(^|/)migrations/|(^|/)prisma/|(^|/)db/'
  '(^|/)(cron|jobs?|scheduler|worker|queue)/|(^|/).*cron.*\.(ya?ml|py|ts|js)$'
  '(^|/)(api|routes|handlers|endpoints)/'
  '\.(html|css|scss|tsx|jsx|vue|svelte)$|(^|/)(components|pages|views|ui)/'
)

MATCHED=()
for i in "${!RISK_PATTERNS[@]}"; do
  if grep -qE "${RISK_PATTERNS[$i]}" <<< "$CHANGED"; then
    MATCHED+=("${RISK_NAMES[$i]}")
  fi
done

if [[ ${#MATCHED[@]} -eq 0 ]]; then
  echo "${GREEN}OK:${RESET} no high-risk surfaces touched — delivery contract not required."
  exit 0
fi

# -- required sections --------------------------------------------------------

REQUIRED=("## Delivery Contract" "## Real Proof" "## Risk Class")

_section_has_content() {
  # True when the named heading exists AND is followed by at least one line of
  # real content before the next heading — an untouched template stanza (blank
  # lines, HTML comments, empty checkboxes) does not count as filled in.
  local heading=$1
  awk -v h="$heading" '
    index($0, h) == 1 { inside = 1; next }
    inside && /^## / { exit }
    inside {
      line = $0
      gsub(/<!--.*-->/, "", line)          # strip inline comments
      if (line ~ /^[[:space:]]*<!--/) next # comment block opener
      if (line ~ /^[[:space:]]*-->/) next  # comment block closer
      gsub(/^[[:space:]]*[-*][[:space:]]*\[[ xX]\][[:space:]]*/, "", line) # checkbox marker
      gsub(/^[[:space:]]*[-*][[:space:]]*/, "", line)                      # bullet marker
      gsub(/\*\*/, "", line)               # bold markers around field labels
      gsub(/^[[:space:]]+/, "", line); gsub(/[[:space:]]+$/, "", line)
      # A bare "Invariant:" with nothing after the colon is an unfilled
      # template field, not content. Without this, shipping the PR template
      # stanza verbatim would satisfy the gate.
      if (line ~ /^[A-Za-z][A-Za-z0-9 \/_()-]*:$/) next
      gsub(/[[:space:]]/, "", line)
      if (length(line) > 0) { found = 1; exit }
    }
    END { exit(found ? 0 : 1) }
  ' <<< "$BODY"
}

MISSING=()
for section in "${REQUIRED[@]}"; do
  if ! grep -qF "$section" <<< "$BODY"; then
    MISSING+=("$section (heading absent)")
  elif ! _section_has_content "$section"; then
    MISSING+=("$section (heading present but empty)")
  fi
done

if [[ ${#MISSING[@]} -eq 0 ]]; then
  echo "${GREEN}OK:${RESET} delivery contract present for: ${MATCHED[*]}"
  exit 0
fi

# -- report -------------------------------------------------------------------

{
  echo ""
  echo "${RED}Delivery contract required.${RESET}"
  echo ""
  echo "This PR touches:"
  for m in "${MATCHED[@]}"; do echo "  • $m"; done
  echo ""
  echo "Missing from the PR description:"
  for m in "${MISSING[@]}"; do echo "  ${YELLOW}✗${RESET} $m"; done
  echo ""
  cat <<'TEMPLATE'
Add these sections to the PR body:

  ## Risk Class
  <which surface(s) above, and the blast radius if this is wrong>

  ## Delivery Contract
  - Invariant: <what must remain true after this merges>
  - Runtime boundaries touched: <processes, queues, external calls>
  - All writers/callers checked: <how you know nothing else depends on the old shape>
  - Silent fallback paths changed or ruled out: <where a failure could go unnoticed>
  - Rollback/killswitch: <how to undo this in production>

  ## Real Proof
  <evidence it works: test output, a real request/response, a screenshot,
   a log line from an actual run — not "should work" or "tests pass">

Not applicable? Apply the `skip-delivery-contract` label.
See .claude/rules/delivery-contract.md
TEMPLATE
} >&2

if [[ "$MODE" == "warn" ]]; then
  echo "${YELLOW}(advisory mode — not failing)${RESET}" >&2
  exit 0
fi
exit 1
