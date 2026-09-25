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
elif [ -f "$SKILLS_LINK" ] && [ "$(cat "$SKILLS_LINK")" = "../$SKILLS_TARGET" ]; then
  # git with core.symlinks=false (Windows default without Developer Mode)
  # writes a symlink as a plain file holding its target path.
  fail "$SKILLS_LINK was checked out as a plain text file, not a symlink (git core.symlinks=false, typical on Windows). Fix: enable Windows Developer Mode, run 'git config core.symlinks true', then 'git checkout -- $SKILLS_LINK'."
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

    # One awk pass validates the frontmatter as a whole, printing one line per
    # problem (nothing when valid). Rules, each a real way a skill silently
    # drops out of Codex while a looser check stays green:
    #   - line 1 is `---` and a closing `---` follows (no late or
    #     unterminated block);
    #   - `name:` is lowercase letters, digits and hyphens (quotes stripped);
    #   - `description:` is non-empty after stripping quotes, or is a block
    #     scalar (`>`, `>-`, `|`, `|-`) whose NEXT line is indented text.
    problems="$(awk '
      function unquote(v) {
        sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
        if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
        return v
      }
      NR == 1 {
        if ($0 !~ /^---[ \t]*$/) { print "frontmatter must start on line 1 with ---"; bad = 1; exit }
        infm = 1; next
      }
      infm && /^---[ \t]*$/ { closed = 1; infm = 0; exit }
      infm {
        if (pending) {
          if ($0 ~ /^[ \t]+[^ \t]/) desc_ok = 1
          pending = 0
        }
        if ($0 ~ /^name:/) {
          v = $0; sub(/^name:/, "", v); v = unquote(v)
          have_name = 1
          if (v !~ /^[a-z0-9][a-z0-9-]*$/) { name_invalid = 1; name_bad = v }
        } else if ($0 ~ /^description:/) {
          v = $0; sub(/^description:/, "", v); sub(/^[ \t]+/, "", v)
          have_desc = 1
          if (v ~ /^[>|]/) pending = 1
          else if (unquote(v) != "") desc_ok = 1
        }
      }
      END {
        if (bad) exit
        if (!closed) { print "frontmatter is not closed with a --- line"; exit }
        if (!have_name) print "has no name: field"
        else if (name_invalid) print "name \"" name_bad "\" must be non-empty lowercase letters, digits and hyphens"
        if (!have_desc) print "has no description: field"
        else if (!desc_ok) print "description: is empty (or a block scalar with no indented text after it)"
      }
    ' "$skill_md")"
    if [ -n "$problems" ]; then
      while IFS= read -r p; do
        [ -n "$p" ] && fail "$skill_md: $p"
      done <<<"$problems"
    fi
  done
else
  fail "$SKILLS_TARGET does not exist."
fi

if [ "$fail" -eq 0 ]; then
  echo "check-codex-skills: OK — $SKILLS_LINK -> $SKILLS_TARGET, all SKILL.md files have name + description."
fi
exit "$fail"
