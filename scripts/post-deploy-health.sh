#!/usr/bin/env bash
# Post-deploy health check — hit critical endpoints and notify Slack.
#
# Usage: ./scripts/post-deploy-health.sh
#
# Required env vars:
#   DEPLOY_URL   Base URL to health-check (e.g. https://myapp.example.com)
#   DEPLOY_SHA   Git SHA of the deployed commit (injected by deploy workflow)
#
# Optional env vars:
#   HEALTH_ENDPOINTS  Space-separated paths to check (default: /api/health /api/usage /api/clients)
#   SLACK_WEBHOOK_CTO       Slack webhook for success notifications
#   SLACK_WEBHOOK_EMERGENCY Slack webhook for failure alerts
#
# Exit codes: 0 = all endpoints healthy, 1 = one or more failed

set -euo pipefail

BASE_URL="${DEPLOY_URL:?DEPLOY_URL must be set}"
SHA="${DEPLOY_SHA:-unknown}"
ENDPOINTS="${HEALTH_ENDPOINTS:-/api/health /api/usage /api/clients}"
FAILED=0
RESULTS=""

check_endpoint() {
  local path="$1"
  local status
  # Retry up to 3 times with 5s backoff before declaring failure
  for attempt in 1 2 3; do
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${BASE_URL}${path}" || echo "000")
    if [ "$status" -eq 200 ]; then
      RESULTS+="${path} ✓ | "
      return 0
    fi
    [ "$attempt" -lt 3 ] && sleep 5
  done
  RESULTS+="${path} ✗ (${status}) | "
  FAILED=$((FAILED + 1))
}

# shellcheck disable=SC2086
for path in $ENDPOINTS; do
  check_endpoint "$path"
done

# Trim trailing separator
RESULTS="${RESULTS%' | '}"

if [ "$FAILED" -eq 0 ]; then
  node tools/comms/send-hook.js --to cto --from cos \
    --message "✅ Deploy green — ${BASE_URL} | SHA: ${SHA} | ${RESULTS}"
  echo "All endpoints healthy."
  exit 0
else
  node tools/comms/send-hook.js --to emergency --from cos \
    --message "🚨 Deploy health check FAILED — ${BASE_URL} | SHA: ${SHA} | ${RESULTS} | Action required."
  echo "Health check FAILED — ${RESULTS}" >&2
  exit 1
fi
