---
name: compact
description: "Create a token-efficient state snapshot for context preservation during long sessions."
---

# /compact

Create a token-efficient state snapshot for context preservation during long sessions. This is the creation side of context recovery — `/resume` is the reconstruction side.

## Usage

```
/compact [--save]
```

## Arguments

- `--save`: Write the snapshot to `prd/tasks/{feature}_compact.md` (default: display only)

## How This Differs From /checkpoint

| Skill | Purpose | Output | When to Use |
|-------|---------|--------|-------------|
| `/checkpoint` | Update task tracking with progress details | Full task file update | Every 30-60 min during development |
| `/compact` | Create minimal recovery snapshot | Dense state summary | Before context limit, before long breaks |

`/checkpoint` maintains detailed progress. `/compact` creates the minimum context needed to reconstruct working state after full context loss.

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Detect current feature from branch name or active task file
- Build the snapshot without prompting
- Include only information that cannot be derived from reading the code

**Discipline:**
- Maximum 200 lines for the snapshot
- Focus on decisions, state, and next steps — not code summaries
- If code tells the story, don't repeat it in the snapshot

### Process

#### 1. Gather Current State

Run in parallel:
```bash
git branch --show-current
git log --oneline -10
git diff --stat
git diff --cached --stat
```

Read in parallel:
- `prd/00_index.md` — find active features
- `prd/tasks/{feature}_tasks.md` — if it exists
- `docs/decisions/` — any ADRs created this session

#### 2. Build Snapshot

Create a dense state summary with these sections:

```markdown
# Compact: {Feature Name}
**Branch:** {branch}
**Date:** {YYYY-MM-DD HH:MM}
**Session duration:** ~{estimated time}

## State
{2-3 sentences: what exists now that didn't before this session}

## Decisions Made
{Numbered list of decisions with one-line rationale each}
1. {Decision}: {why}
2. {Decision}: {why}

## What's Done
{Bulleted list of completed work — file paths, not descriptions}
- [x] {file or feature}
- [x] {file or feature}

## What's In Progress
- [ ] {current task}: {where it stands}

## What's Blocked
- {blocker}: {what's needed to unblock}

## Next Steps (Priority Order)
1. {First thing to do when resuming}
2. {Second thing}
3. {Third thing}

## Key Files
{Files that must be read to understand current state}
- `{file}` — {one-line role}
```

#### 3. Output

If `--save` is specified:
- Write to `prd/tasks/{feature}_compact.md`
- Confirm: "Snapshot saved to `prd/tasks/{feature}_compact.md`"

Otherwise:
- Display the snapshot directly
- Suggest: "Run `/compact --save` to persist this snapshot"

## When to Use This Skill

Use `/compact`:
- When you've been working for 45+ minutes on a complex feature
- Before ending a session on multi-session work
- When context window is getting large and compression may happen
- Before switching to a different feature branch

**Don't use for:**
- Quick single-session tasks
- When `/checkpoint` already captured recent progress (use `/compact` only when you need a more condensed format)
