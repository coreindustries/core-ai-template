#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# assert-dependency-age.sh
# -----------------------------------------------------------------------------
# Fails if any dependency added or upgraded in the current branch was
# published to its registry less than MIN_AGE_HOURS ago (default: 24).
#
# Supports: npm (package-lock.json, pnpm-lock.yaml), pip/uv (uv.lock,
# poetry.lock, requirements.txt), cargo (Cargo.lock), gomod (go.mod),
# github-actions (.github/workflows/*.yml `uses:` refs).
#
# Enforces .claude/rules/dependency-security.md Rule 2.
# -----------------------------------------------------------------------------
set -euo pipefail

MIN_AGE_HOURS=${MIN_AGE_HOURS:-24}
BASE_REF=${BASE_REF:-origin/main}
NOW_EPOCH=$(date -u +%s)
MIN_AGE_SECONDS=$((MIN_AGE_HOURS * 3600))

RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
GREEN=$'\033[0;32m'
RESET=$'\033[0m'

command -v jq >/dev/null 2>&1 || { echo "${RED}ERROR:${RESET} jq is required"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "${RED}ERROR:${RESET} curl is required"; exit 2; }

if ! git rev-parse "$BASE_REF" >/dev/null 2>&1; then
  echo "${YELLOW}WARN:${RESET} base ref $BASE_REF not found. Skipping age check."
  exit 0
fi

CHANGED=$(git diff --name-only "$BASE_REF"...HEAD -- \
  'package-lock.json' 'pnpm-lock.yaml' 'yarn.lock' \
  'uv.lock' 'poetry.lock' 'requirements.txt' 'requirements*.txt' \
  'Cargo.lock' 'go.mod' 'go.sum' \
  '.github/workflows/*.yml' '.github/workflows/*.yaml' 2>/dev/null || true)

if [[ -z "$CHANGED" ]]; then
  echo "${GREEN}OK:${RESET} no lockfile or workflow changes."
  exit 0
fi

OFFENDERS=()

# -- helpers ------------------------------------------------------------------

_check_age() {
  # $1=ecosystem  $2=package  $3=version  $4=iso8601-publish-time
  local eco=$1 pkg=$2 ver=$3 published=$4
  local pub_epoch
  pub_epoch=$(date -u -d "$published" +%s 2>/dev/null || \
              date -u -jf "%Y-%m-%dT%H:%M:%S" "${published%.*}" +%s 2>/dev/null || echo 0)
  [[ "$pub_epoch" -eq 0 ]] && return 0
  local age=$((NOW_EPOCH - pub_epoch))
  if (( age < MIN_AGE_SECONDS )); then
    local hours=$((age / 3600))
    OFFENDERS+=("$eco: $pkg@$ver — published ${hours}h ago (< ${MIN_AGE_HOURS}h)")
  fi
}

_added_npm() {
  # Diff package-lock.json and extract newly-added (pkg, version) pairs.
  git diff "$BASE_REF"...HEAD -- package-lock.json pnpm-lock.yaml yarn.lock 2>/dev/null \
    | grep -E '^\+.*"version":' \
    | grep -oE '"version":\s*"[^"]+"' \
    | awk -F'"' '{print $4}' \
    | sort -u
}

_check_npm() {
  # For each newly added entry, extract package name from the path and query the registry.
  while IFS= read -r entry; do
    [[ -z "$entry" ]] && continue
    local pkg
    pkg=$(jq -r --arg v "$entry" '
      .packages // {} | to_entries[]
      | select(.value.version == $v)
      | .key
      | sub("^node_modules/"; "")
      | select(length > 0)' package-lock.json 2>/dev/null | head -1)
    [[ -z "$pkg" ]] && continue
    local published
    published=$(curl -fsSL "https://registry.npmjs.org/${pkg}" 2>/dev/null \
      | jq -r --arg v "$entry" '.time[$v] // empty')
    [[ -n "$published" ]] && _check_age "npm" "$pkg" "$entry" "$published"
  done < <(_added_npm)
}

_check_pypi() {
  # Parse newly added (name, version) from uv.lock / poetry.lock / requirements*.txt
  local pairs=""
  if [[ -f uv.lock ]] && git diff "$BASE_REF"...HEAD -- uv.lock 2>/dev/null | grep -q '^+'; then
    pairs+=$(git diff "$BASE_REF"...HEAD -- uv.lock | awk '
      /^\+name = / { name=$3; gsub(/"/,"",name) }
      /^\+version = / { ver=$3; gsub(/"/,"",ver); if (name && ver) print name, ver; name=""; ver="" }
    ')
    pairs+=$'\n'
  fi
  if [[ -f poetry.lock ]]; then
    pairs+=$(git diff "$BASE_REF"...HEAD -- poetry.lock | awk '
      /^\+name = / { name=$3; gsub(/"/,"",name) }
      /^\+version = / { ver=$3; gsub(/"/,"",ver); if (name && ver) print name, ver; name=""; ver="" }
    ')
    pairs+=$'\n'
  fi
  while read -r name ver; do
    [[ -z "$name" || -z "$ver" ]] && continue
    local published
    published=$(curl -fsSL "https://pypi.org/pypi/${name}/${ver}/json" 2>/dev/null \
      | jq -r '.urls[0].upload_time_iso_8601 // empty')
    [[ -n "$published" ]] && _check_age "pypi" "$name" "$ver" "$published"
  done <<< "$pairs"
}

_check_cargo() {
  [[ -f Cargo.lock ]] || return 0
  local pairs
  pairs=$(git diff "$BASE_REF"...HEAD -- Cargo.lock 2>/dev/null | awk '
    /^\+name = / { name=$3; gsub(/"/,"",name) }
    /^\+version = / { ver=$3; gsub(/"/,"",ver); if (name && ver) print name, ver; name=""; ver="" }
  ')
  while read -r name ver; do
    [[ -z "$name" || -z "$ver" ]] && continue
    local published
    published=$(curl -fsSL "https://crates.io/api/v1/crates/${name}/${ver}" 2>/dev/null \
      | jq -r '.version.created_at // empty')
    [[ -n "$published" ]] && _check_age "crates" "$name" "$ver" "$published"
  done <<< "$pairs"
}

_check_gomod() {
  [[ -f go.sum ]] || return 0
  local entries
  entries=$(git diff "$BASE_REF"...HEAD -- go.sum 2>/dev/null | grep -E '^\+[^+]' \
    | awk '{print $1, $2}' | sort -u)
  while read -r sign line; do
    local mod="${line% *}" ver="${line#* }"
    mod="${mod#+}"
    # Strip /go.mod suffix if present
    ver="${ver% */go.mod}"
    [[ -z "$mod" || -z "$ver" ]] && continue
    local published
    published=$(curl -fsSL "https://proxy.golang.org/${mod}/@v/${ver}.info" 2>/dev/null \
      | jq -r '.Time // empty')
    [[ -n "$published" ]] && _check_age "gomod" "$mod" "$ver" "$published"
  done <<< "$entries"
}

_check_github_actions() {
  # Extract newly added/changed `uses: owner/repo@ref` refs from workflow files.
  # Actions are SHA-pinned with a `# vX.Y.Z` trailing comment (see
  # dependency-security.md Rule 1), so prefer the release tag's publish time and
  # fall back to the pinned commit's author date.
  # Every pipeline below is `|| true`-guarded: under `set -euo pipefail` a grep
  # that matches nothing (no workflow change, no `# vX.Y.Z` comment) or a curl
  # that 404s would otherwise kill the script silently with exit 1.
  local lines
  lines=$(git diff "$BASE_REF"...HEAD -- \
    '.github/workflows/*.yml' '.github/workflows/*.yaml' 2>/dev/null \
    | grep '^+[^+]' \
    | grep -E 'uses:[[:space:]]+[^./[:space:]][^/[:space:]]*/[^@[:space:]]+@[A-Za-z0-9]' \
    | sed 's/^+//' | sort -u || true)
  [[ -z "$lines" ]] && return 0

  # Seeded with the Accept header so the array is never empty — an empty
  # "${arr[@]}" is an unbound-variable error under `set -u` on bash < 4.4 (macOS).
  local -a curl_args=(-fsSL -H "Accept: application/vnd.github+json")
  [[ -n "${GITHUB_TOKEN:-}" ]] && curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local uses_val tag owner_repo ref published=""
    uses_val=$(sed -E 's/.*uses:[[:space:]]+([^[:space:]#]+).*/\1/' <<< "$line")
    tag=$(grep -oE '#[[:space:]]*v[0-9][^[:space:]]*' <<< "$line" \
      | sed -E 's/#[[:space:]]*//' | head -1 || true)
    owner_repo=${uses_val%%@*}
    ref=${uses_val#*@}
    [[ -z "$owner_repo" || -z "$ref" || "$owner_repo" == "$uses_val" ]] && continue

    # Reusable workflows (`owner/repo/.github/workflows/x.yml@ref`) → trim to owner/repo
    owner_repo=$(cut -d/ -f1,2 <<< "$owner_repo")

    [[ -z "$tag" && "$ref" =~ ^v[0-9] ]] && tag="$ref"
    if [[ -n "$tag" ]]; then
      published=$(curl "${curl_args[@]}" \
        "https://api.github.com/repos/${owner_repo}/releases/tags/${tag}" 2>/dev/null \
        | jq -r '.published_at // empty' || true)
    fi
    if [[ -z "$published" ]]; then
      published=$(curl "${curl_args[@]}" \
        "https://api.github.com/repos/${owner_repo}/commits/${ref}" 2>/dev/null \
        | jq -r '.commit.author.date // empty' || true)
    fi

    if [[ -n "$published" ]]; then
      _check_age "github-actions" "$owner_repo" "${tag:-${ref:0:12}}" "$published"
    fi
  done <<< "$lines"
  return 0
}

# -- run checks ---------------------------------------------------------------

[[ -f package-lock.json ]] && _check_npm
[[ -f uv.lock || -f poetry.lock ]] && _check_pypi
[[ -f Cargo.lock ]] && _check_cargo
[[ -f go.sum ]] && _check_gomod
_check_github_actions

if [[ ${#OFFENDERS[@]} -gt 0 ]]; then
  echo "${RED}ERROR:${RESET} dependencies newer than ${MIN_AGE_HOURS}h cooldown:"
  for f in "${OFFENDERS[@]}"; do
    echo "  ${YELLOW}✗${RESET} $f"
  done
  echo ""
  echo "See .claude/rules/dependency-security.md Rule 2."
  echo ""
  echo "Options:"
  echo "  1. Wait ${MIN_AGE_HOURS}h from each package's publish time, rebase, try again."
  echo "  2. Downgrade to the previous stable version."
  echo "  3. If this is a published security advisory fix, request a waiver and"
  echo "     apply the 'security-hotfix-24h-waiver' label on the PR."
  exit 1
fi

echo "${GREEN}OK:${RESET} all added/changed deps are ≥ ${MIN_AGE_HOURS}h old."
exit 0
