#!/usr/bin/env bash
# lib.sh — helpers shared by every scripts/dev/board/ tool. Source it; don't run it.
# Also loads lanes-config.sh, so a sourcing script gets lanes_cfg too.
# Portability: macOS bash 3.2 (no `declare -A`, no GNU-only flags) + Linux.

BOARD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$BOARD_LIB_DIR/lanes-config.sh"

# die <message> [exit-code=2] — prefixed with the calling script's name.
die() {
  echo "$(basename "$0"): $1" >&2
  exit "${2:-2}"
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "'$c' not found on PATH"
  done
}
require_gh() { require_cmd gh; }
require_jq() { require_cmd jq; }

# now_iso — current UTC time, second resolution, ISO8601 Z-suffixed.
# BOARD_NOW_ISO overrides it, but ONLY when BOARD_TEST=1 is also set AND the
# value matches the exact ISO8601 shape this function itself produces — a
# stray BOARD_NOW_ISO left set in a real operator's shell (or anything
# malformed) must never silently freeze a real claim's timestamp; it just
# falls through to the real clock.
now_iso() {
  if [ "${BOARD_TEST:-0}" = "1" ] \
     && printf '%s' "${BOARD_NOW_ISO:-}" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'; then
    printf '%s' "$BOARD_NOW_ISO"
  else
    date -u +%Y-%m-%dT%H:%M:%SZ
  fi
}

# sanitize_id <text> — safe for a file or directory name.
sanitize_id() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_'
}

# render_table — read TSV on stdin, print space-aligned columns. Pure awk,
# because `column`'s flags differ between BSD and GNU.
render_table() {
  awk -F'\t' '
    {
      for (i = 1; i <= NF; i++) if (length($i) > w[i]) w[i] = length($i)
      lines[NR] = $0
    }
    END {
      for (r = 1; r <= NR; r++) {
        m = split(lines[r], f, "\t")
        line = ""
        for (i = 1; i <= m; i++) {
          line = line f[i]
          if (i < m) for (k = 0; k < w[i] - length(f[i]) + 2; k++) line = line " "
        }
        print line
      }
    }
  '
}
