#!/usr/bin/env bash
# check-codex-skills.sh — verifies the Codex skill-discovery surface stays wired up.
#
# Codex (developers.openai.com/codex/skills) discovers Agent Skills by walking
# from the current directory up to the repo root looking for `.agents/skills/`,
# reading each subdirectory's SKILL.md frontmatter for `name` and `description`.
# It does not read `.claude/skills` directly, and it follows symlinked skill
# folders — so this repo keeps ONE source of truth (`.claude/skills/`) and
# exposes it to Codex via a symlink at `.agents/skills`, rather than
# maintaining a second copy that can drift.
#
# This script fails (non-zero) when:
#   1. `.agents/skills` is missing, not a symlink, or a broken/dangling symlink.
#   2. `.agents/skills` does not resolve to `.claude/skills` (drift protection —
#      catches an accidental `rm` + recreate as a real directory, or a
#      re-point to the wrong target).
#   3. Any `.claude/skills/<name>/SKILL.md` is missing a non-empty `name:` or
#      `description:` frontmatter field, which is all Codex's skill frontmatter
#      requires (it needs neither `allowed-tools` nor any other Claude-only key).
#
# `.claude/skills/_shared/` intentionally has no SKILL.md — it holds
# `agent-protocol.md`, a shared doc `require`d by lane skills' bodies, not a
# skill of its own. Codex's skill loader looks for SKILL.md per subdirectory
# and simply will not find one there; that absence is expected and this script
# does not flag it as an error. Any OTHER subdirectory without a SKILL.md is a
# real gap and fails the check.
#
# Wired into .github/workflows/ci.yml (Lint job) — runs unconditionally, since
# it only inspects .agents/ and .claude/skills/, never the project's own
# src/tests, so it works the same on an uninitialized template.
#
# Usage: scripts/check-codex-skills.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 2

SKILLS_LINK=".agents/skills"
SKILLS_TARGET=".claude/skills"
EXEMPT_DIR="_shared"

fail=0
fail() {
  echo "check-codex-skills: $1" >&2
  fail=1
}

# --- 1 & 2: the symlink must exist, be a symlink, and resolve to .claude/skills ---
if [ ! -e "$SKILLS_LINK" ] && [ ! -L "$SKILLS_LINK" ]; then
  fail "$SKILLS_LINK is missing — Codex will not discover any skills. Create it with: ln -s ../.claude/skills $SKILLS_LINK"
elif [ ! -L "$SKILLS_LINK" ]; then
  fail "$SKILLS_LINK exists but is not a symlink — it must be a symlink to $SKILLS_TARGET, not a real directory (a real copy drifts from .claude/skills silently)."
else
  # -e on a symlink path follows it; if the symlink is dangling this is false.
  if [ ! -e "$SKILLS_LINK" ]; then
    fail "$SKILLS_LINK is a broken symlink (target does not exist)."
  else
    resolved_link="$(cd "$SKILLS_LINK" 2>/dev/null && pwd -P)"
    resolved_target="$(cd "$SKILLS_TARGET" 2>/dev/null && pwd -P)"
    if [ -z "$resolved_link" ] || [ -z "$resolved_target" ] || [ "$resolved_link" != "$resolved_target" ]; then
      fail "$SKILLS_LINK does not resolve to $SKILLS_TARGET (resolved: '${resolved_link:-<unreadable>}' vs '${resolved_target:-<unreadable>}')."
    fi
  fi
fi

# --- 3: every skill dir's SKILL.md needs non-empty name + description ---
if [ -d "$SKILLS_TARGET" ]; then
  for dir in "$SKILLS_TARGET"/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    [ "$name" = "$EXEMPT_DIR" ] && continue

    skill_md="${dir}SKILL.md"
    if [ ! -f "$skill_md" ]; then
      fail "$skill_md is missing (every non-_shared skill directory needs one)."
      continue
    fi

    # Frontmatter is the block between the first two lines that are exactly
    # "---". Extract it, then look for non-empty `name:`/`description:` keys.
    # Handles both single-line (`description: foo`) and YAML block-scalar
    # (`description: >-` / `description: |`, value on following indented
    # lines) forms already used across this repo's SKILL.md files.
    frontmatter="$(awk '
      /^---[[:space:]]*$/ { c++; next }
      c == 1 { print }
      c >= 2 { exit }
    ' "$skill_md")"

    if [ -z "$frontmatter" ]; then
      fail "$skill_md has no --- frontmatter block."
      continue
    fi

    name_line="$(printf '%s\n' "$frontmatter" | grep -E '^name:[[:space:]]*' | head -1)"
    name_val="$(printf '%s' "$name_line" | sed -E 's/^name:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//')"
    if [ -z "$name_val" ]; then
      fail "$skill_md has no non-empty 'name:' frontmatter field."
    fi

    desc_line="$(printf '%s\n' "$frontmatter" | grep -E '^description:[[:space:]]*' | head -1)"
    desc_rest="$(printf '%s' "$desc_line" | sed -E 's/^description:[[:space:]]*//')"
    case "$desc_rest" in
      '>'*|'|'*)
        # Block scalar: the description text is the next non-empty indented
        # line(s), not the `>-`/`|` marker itself.
        next_val="$(printf '%s\n' "$frontmatter" | awk '/^description:[[:space:]]*[>|]/{f=1;next} f && NF{print; exit}')"
        [ -z "$next_val" ] && fail "$skill_md 'description:' uses a block scalar but has no following text."
        ;;
      '')
        fail "$skill_md has no non-empty 'description:' frontmatter field."
        ;;
    esac
  done
else
  fail "$SKILLS_TARGET does not exist."
fi

if [ "$fail" -eq 0 ]; then
  echo "check-codex-skills: OK — $SKILLS_LINK -> $SKILLS_TARGET, all SKILL.md files have name + description."
fi
exit "$fail"
