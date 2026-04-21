#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# assert-migration-conventions.sh
# -----------------------------------------------------------------------------
# Enforces .claude/rules/database-migrations.md conventions:
#   1. Migration filenames match YYYYMMDDHHMMSS_<snake>.sql
#   2. No already-committed migration is being modified
#   3. Every CREATE TABLE in public schema is followed somewhere by
#      `enable row level security` on the same table
#
# Fails fast on any violation. Intended for pre-commit and CI.
# -----------------------------------------------------------------------------
set -euo pipefail

MIGRATIONS_DIR="supabase/migrations"
BASE_REF=${BASE_REF:-origin/main}

RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
GREEN=$'\033[0;32m'
RESET=$'\033[0m'

[[ -d "$MIGRATIONS_DIR" ]] || { echo "${GREEN}OK:${RESET} no $MIGRATIONS_DIR yet."; exit 0; }

OFFENDERS=()

# --- 1. filename convention --------------------------------------------------

while IFS= read -r -d '' f; do
  base=$(basename "$f")
  [[ "$base" == ".gitkeep" ]] && continue
  if [[ ! "$base" =~ ^[0-9]{14}_[a-z0-9_]+\.sql$ ]]; then
    OFFENDERS+=("bad-filename: $f (must match YYYYMMDDHHMMSS_<snake>.sql)")
  fi
done < <(find "$MIGRATIONS_DIR" -type f -print0 2>/dev/null || true)

# --- 2. no edits to already-committed migrations -----------------------------

if git rev-parse "$BASE_REF" >/dev/null 2>&1; then
  COMMITTED=$(git ls-tree -r --name-only "$BASE_REF" -- "$MIGRATIONS_DIR" 2>/dev/null || true)
  CHANGED=$(git diff --name-only "$BASE_REF"...HEAD -- "$MIGRATIONS_DIR" 2>/dev/null || true)
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if echo "$COMMITTED" | grep -Fxq "$f"; then
      # The file existed on base and was modified (not just added). Check it's a real modification.
      if ! git diff --quiet "$BASE_REF"...HEAD -- "$f"; then
        # Allow deletes (reverting a never-run migration on a feature branch) — flag modifications only.
        if git cat-file -e "HEAD:$f" 2>/dev/null; then
          OFFENDERS+=("committed-migration-modified: $f (migrations are immutable once merged; add a new migration to reverse)")
        fi
      fi
    fi
  done <<< "$CHANGED"
fi

# --- 3. new public-schema tables must enable RLS -----------------------------

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  [[ ! -f "$f" ]] && continue
  # Find `create table public.<name>` and look for the matching RLS enable in the same file
  tables=$(grep -iEo 'create table[[:space:]]+(if not exists[[:space:]]+)?public\.[a-z_][a-z0-9_]*' "$f" \
    | sed -E 's/create table[[:space:]]+(if not exists[[:space:]]+)?public\.//i' || true)
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if ! grep -iqE "alter table[[:space:]]+(only[[:space:]]+)?public\.$t[[:space:]]+enable row level security" "$f"; then
      OFFENDERS+=("missing-rls: public.$t created in $f but no 'enable row level security' in same migration")
    fi
  done <<< "$tables"
done < <(find "$MIGRATIONS_DIR" -type f -name '*.sql' 2>/dev/null || true)

# --- report ------------------------------------------------------------------

if [[ ${#OFFENDERS[@]} -gt 0 ]]; then
  echo "${RED}ERROR:${RESET} migration convention violations:"
  for o in "${OFFENDERS[@]}"; do
    echo "  ${YELLOW}✗${RESET} $o"
  done
  echo ""
  echo "See .claude/rules/database-migrations.md"
  exit 1
fi

echo "${GREEN}OK:${RESET} migrations pass convention checks."
exit 0
