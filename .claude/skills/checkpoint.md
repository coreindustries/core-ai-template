# /checkpoint

Update task tracking file with current progress. Essential for preserving context across sessions.

## Usage

```
/checkpoint [--summary "progress summary"]
```

## Arguments

- `--summary`: Optional summary of recent progress

## Instructions

When this skill is invoked:

### Agent Behavior (Codex-Max Pattern)

**Autonomy:**
- Automatically detect the current task file from `prd/00_PRD_index.md`
- Update all relevant sections without prompting
- Create task file if one doesn't exist for a long-running feature

**Thoroughness:**
- Update task completion status
- Document any decisions made
- Note any blockers or issues
- Update "Next Session Priorities"

### Steps

1. **Find active task file**:
   - Check `prd/00_PRD_index.md` for "In Progress" features
   - Locate corresponding `prd/tasks/{feature}_tasks.md`

2. **Update task file sections**:

   **Tasks Section:**
   - Mark completed tasks as `[x]`
   - Update in-progress tasks with current status
   - Add any new tasks discovered

   **Progress Summary:**
   - Update percentage complete for each phase
   - Note overall progress

   **Next Session Priorities:**
   - Update with immediate next steps
   - Ensure context is recoverable after compression

   **Decisions Made:**
   - Document any architectural or implementation decisions
   - Include rationale

3. **Commit checkpoint** (if requested):
   ```bash
   git add prd/tasks/
   git commit -m "chore: checkpoint - {summary}"
   ```

### Task File Format

```markdown
# {Feature} Tasks

## Context
High-level overview of what's being built.

## Key Decisions
- Decision 1: Rationale
- Decision 2: Rationale

## Tasks

### Phase 1: Setup
- [x] Task 1.1
- [x] Task 1.2
- [ ] Task 1.3 (in progress)

### Phase 2: Implementation
- [ ] Task 2.1
- [ ] Task 2.2

## Progress Summary
- Phase 1: 66% complete
- Phase 2: 0% complete
- Overall: 33% complete

## Next Session Priorities
1. Complete Task 1.3
2. Start Task 2.1
3. Review design for Phase 2

## Blockers
- None currently

## Session Log
### {Date}
- Completed: Task 1.1, 1.2
- Started: Task 1.3
- Notes: {Any relevant notes}
```

### When to Use

**Use /checkpoint:**
- Every 30-60 minutes during active development
- Before taking a break
- After completing a significant milestone
- When switching to a different task
- Before context might be compressed

**Don't need /checkpoint:**
- For quick, single-session tasks
- When no task file exists and feature is simple

## Example

```
$ /checkpoint --summary "Completed auth endpoints, starting tests"

📝 Updating task file: prd/tasks/user_auth_tasks.md

Updated sections:
✅ Tasks: Marked 3 tasks complete
✅ Progress: Phase 1 now 80% complete
✅ Next Session: Updated priorities
✅ Session Log: Added entry for 2026-01-15

Task file saved. Context preserved for next session.
```
