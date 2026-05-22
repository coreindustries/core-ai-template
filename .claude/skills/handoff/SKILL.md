---
name: handoff
description: "Write a structured handoff at session end. Preserves context so the next agent can resume without human briefing. Invoke before ending any feature session longer than 30 minutes."
---

# /handoff

Write a structured handoff so the next agent can resume work without human briefing.

## Usage

```
/handoff [--feature <name>]
```

## Arguments

- `--feature`: Feature name override (auto-detected from active task file if omitted)

## Instructions

### Steps

1. **Find or create the task file**

   - Check `prd/00_index.md` for "In Progress" features
   - If found: open `prd/tasks/{feature_name}_tasks.md`
   - If not found: create `prd/tasks/{feature_name}_tasks.md` from `prd/_task_template.md`

2. **Update the task file**

   - Mark completed tasks `[x]`
   - Add newly discovered tasks
   - Update progress percentages in the Progress Summary table
   - Replace "Next Session Priorities" with the immediate next step (one actionable sentence per item)
   - Append a Session Log entry for today

   Append this block to the task file under a new `## Handoff` heading:

   ```markdown
   ## Handoff — {feature} — {ISO date}

   ### Completed This Session
   - [→ ✅] {task description}

   ### Decisions Made
   - {decision}: {rationale}

   ### Current Blockers
   - {blocker or "none"}

   ### Last File Touched
   - {path:line}

   ### Recommended Next Action
   {one sentence — what the next agent should do first}
   ```

3. **Write or update CONTEXT.md in the worktree root**

   If inside a git worktree, write `CONTEXT.md` at the worktree root. If working on `main`, skip this step.

   ```markdown
   # Worktree Context
   <!-- MACHINE UPDATED — do not edit manually -->

   **Feature:** {feature name}
   **Goal:** {one sentence from PRD}
   **Last updated:** {ISO datetime}
   **Last agent action:** {one sentence}
   **Decisions made:**
   - {decision}: {rationale}

   **Current blockers:** {blocker or "none"}
   **Recommended next action:** {one actionable sentence}
   **Last file touched:** {path:line}
   ```

4. **Update `## Current State` in CLAUDE.md**

   Find the `## Current State` block and replace its content. Touch nothing else in CLAUDE.md.

   ```markdown
   ## Current State
   <!-- MACHINE UPDATED — do not edit manually -->
   <!-- Last updated by: claude on {ISO date} -->

   **Active feature:** {feature name or "none"}
   **Last action:** {one sentence}
   **Blockers:** {blocker or "none"}
   **Next action:** {one actionable sentence}
   **Worktree:** {branch name or "main"}
   ```

5. **Commit the handoff**

   ```bash
   git add prd/tasks/ CONTEXT.md CLAUDE.md
   git commit -m "🔧 chore: update handoff context [{feature}]"
   ```

### When to Invoke

- **Always:** end of any feature session >30 minutes
- **Always:** before switching to a different feature or handing off to another agent
- **Optional:** CLAUDE.md may instruct auto-invoke on session end

### What /handoff Is NOT

- Not a replacement for `/checkpoint` — use checkpoint during a session, handoff at session end
- Not a commit of feature code — only commits context files
- Not required for quick single-task sessions
