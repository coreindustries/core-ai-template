# /resume

Recover context and resume work after a new session or context compression.

## Usage

```
/resume [feature_name]
```

## Arguments

- `feature_name` (optional): Specific feature to resume. If omitted, auto-detects from branch name or active tasks.

## Instructions

When this skill is invoked:

### 1. Detect Current Context

Run in parallel:
```bash
git branch --show-current
git status --short
git log --oneline -5
git diff --stat
```

### 2. Find Active Work

Read `prd/00_PRD_index.md` to find "In Progress" features.

If `feature_name` was provided:
- Read `prd/tasks/{feature_name}_tasks.md`

If not provided:
- Infer from branch name (e.g., `feat/user-auth` → `user-auth`)
- Check for any task files in `prd/tasks/`
- If multiple found, list them and ask which to resume

### 3. Load Feature Context

From the task file, extract and present:
- **Context**: What the feature is and key decisions made
- **Progress**: What's done, what's pending
- **Next Session Priorities**: The most critical section - what to do right now
- **Blockers**: Anything preventing progress
- **Key Files**: Files being created or modified

### 4. Check Code State

```bash
# What's changed since last commit?
git diff --stat

# Any staged changes?
git diff --cached --stat

# Are tests passing?
{test_all_command}
```

### 5. Present Recovery Summary

```markdown
## Session Recovery: {Feature Name}

### Where We Left Off
{Summary from task file's "Next Session Priorities"}

### Progress
Phase 1: Setup ████████░░ 80%
Phase 2: Implementation ████░░░░░░ 40%
Phase 3: Testing ░░░░░░░░░░ 0%

### Uncommitted Changes
{git diff summary}

### Tests
{pass/fail status}

### Immediate Next Steps
1. {First priority from task file}
2. {Second priority}
3. {Third priority}

### Key Decisions Already Made
| Decision | Choice | Rationale |
|----------|--------|-----------|
| {from task file} | | |
```

### 6. Begin Work

After presenting the summary:
- Ask if the priorities are correct or if the user wants to adjust
- Once confirmed, begin working on the first priority
- Update the task file as work progresses

## Recovery Without Task File

If no task file exists:
1. Check git log for recent commits related to the feature
2. Look at modified files on the current branch vs main
3. Summarize what appears to have been done
4. Ask the user for context on what to do next
5. Suggest creating a task file: `cp prd/tasks/TASK_TEMPLATE.md prd/tasks/{feature}_tasks.md`
