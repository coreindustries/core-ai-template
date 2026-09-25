#!/usr/bin/env bash
# check-codex-skills.test.sh — fixture tests for scripts/check-codex-skills.sh.
#
# Each case builds a throwaway repo (a copy of the script, a .claude/skills
# tree, and the .agents/skills symlink) and asserts the exit code. The
# malformed-frontmatter cases are the ones a regex-only check let through:
# an empty quoted description, a block scalar with no indented text,
# frontmatter that does not start on line 1, an unterminated block, and a
# name Codex will not accept.
#
# Run: bash scripts/dev/board/tests/check-codex-skills.test.sh
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-codex-skills.sh"

# shellcheck disable=SC1091
source "$TESTS_DIR/lib.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo ""
echo "=== check-codex-skills.sh fixture tests ==="

GOOD='---
name: good-skill
description: Does a good thing. Use when testing.
---

Body.
'

# make_repo <dir> — a repo with one good skill, _shared, and the symlink.
make_repo() {
  local d="$1"
  mkdir -p "$d/scripts" "$d/.claude/skills/good-skill" "$d/.claude/skills/_shared" "$d/.agents"
  cp "$SCRIPT" "$d/scripts/check-codex-skills.sh"
  printf '%s' "$GOOD" > "$d/.claude/skills/good-skill/SKILL.md"
  echo "shared doc" > "$d/.claude/skills/_shared/agent-protocol.md"
  ln -s ../.claude/skills "$d/.agents/skills"
}

# case_skill <name> <want-exit> <SKILL.md content> — adds a second skill.
case_skill() {
  local name="$1" want="$2" content="$3" d rc
  d="$WORK/$(printf '%s' "$name" | tr -c 'a-z0-9' '-')"
  make_repo "$d"
  mkdir -p "$d/.claude/skills/probe"
  printf '%s' "$content" > "$d/.claude/skills/probe/SKILL.md"
  bash "$d/scripts/check-codex-skills.sh" >/dev/null 2>"$d.err"; rc=$?
  if [ "$rc" = "$want" ]; then
    pass "$name (exit $rc)"
  else
    fail "$name: expected exit $want, got $rc — $(head -2 "$d.err" | tr '\n' ' ')"
  fi
}

case_skill "a well-formed skill passes" 0 "$GOOD"
case_skill "a folded block-scalar description passes" 0 '---
name: probe
description: >-
  Folded description text.
---
'
case_skill "a quoted description passes" 0 '---
name: "probe"
description: "Quoted description."
---
'
case_skill "CRLF line endings (Windows autocrlf) pass" 0 "$(printf -- '---\r\nname: probe\r\ndescription: CRLF file.\r\n---\r\n')"
case_skill "empty double-quoted description fails" 1 '---
name: probe
description: ""
---
'
case_skill "empty single-quoted description fails" 1 "---
name: probe
description: ''
---
"
case_skill "block scalar followed directly by the next key fails" 1 '---
name: probe
description: >-
tags: x
---
'
case_skill "frontmatter not on line 1 fails" 1 '
---
name: probe
description: Late frontmatter.
---
'
case_skill "unterminated frontmatter fails" 1 '---
name: probe
description: Never closed.

Body text that is not frontmatter.
'
case_skill "a name with spaces fails" 1 '---
name: my skill!
description: Bad name.
---
'
case_skill "an empty quoted name fails" 1 '---
name: ""
description: Empty name.
---
'
case_skill "a missing name fails" 1 '---
description: No name.
---
'

# Windows / core.symlinks=false: git writes the link as a plain text file
# containing its target. The error must say so and give the fix.
d="$WORK/no-symlinks"
make_repo "$d"
rm "$d/.agents/skills"
printf '../.claude/skills' > "$d/.agents/skills"
bash "$d/scripts/check-codex-skills.sh" >/dev/null 2>"$d.err"; rc=$?
if [ "$rc" = "1" ] && grep -q 'core.symlinks' "$d.err"; then
  pass "a checked-out-as-text symlink (core.symlinks=false) fails and names the fix"
else
  fail "core.symlinks=false case: rc=$rc err=[$(cat "$d.err")]"
fi

print_summary "check-codex-skills.sh"
