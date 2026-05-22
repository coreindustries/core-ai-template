#!/usr/bin/env bash
# Classify a failed GitHub Actions CI run by job name.
# Usage: ./scripts/classify-ci-failure.sh <run_id>
# Output (stdout): lint | types | test | flaky | build | unknown
# Requires: gh CLI authenticated, GITHUB_REPOSITORY env var set

set -euo pipefail

RUN_ID="${1:?Usage: classify-ci-failure.sh <run_id>}"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"

failed_job=$(gh api "repos/${REPO}/actions/runs/${RUN_ID}/jobs" \
  --jq '[.jobs[] | select(.conclusion == "failure") | .name] | first // "unknown"')

case "$failed_job" in
  Lint|*[Ll]int*)
    echo "lint"
    ;;
  "Type Check"|*[Tt]ypecheck*|*[Mm]ypy*)
    echo "types"
    ;;
  Test|*[Tt]est*|*[Pp]ytest*)
    # Check whether any step in the failed job has a retry/flaky name
    flaky=$(gh api "repos/${REPO}/actions/runs/${RUN_ID}/jobs" \
      --jq '[.jobs[] | select(.conclusion == "failure") | .steps[] | select(.name | test("retry|flaky|Retry|Flaky"; "i"))] | length')
    if [ "${flaky}" -gt 0 ]; then
      echo "flaky"
    else
      echo "test"
    fi
    ;;
  Build|*[Bb]uild*|*[Dd]ocker*)
    echo "build"
    ;;
  *)
    echo "unknown"
    ;;
esac
