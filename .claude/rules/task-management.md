# Task Management Rules

**Scope:** Task tracking, plan discipline, PRD implementation workflow

## When to Create Plans

**Skip Plans For:**
- Straightforward tasks (easiest ~25% of work)
- Single-step changes
- Obvious fixes

**Create Plans For:**
- Multi-step features
- Complex refactorings
- Cross-cutting changes
- Tasks requiring coordination across multiple files

## Plan Discipline

**REQUIRED:** Plans MUST be reconciled before finishing a task.

**Plan Lifecycle:**
1. Create plan with clear steps
2. Update plan after completing each step (mark as Done)
3. Before finishing, ensure every item is:
   - **Done**: Completed successfully
   - **Blocked**: With one-sentence reason and targeted question
   - **Cancelled**: With reason for cancellation
4. No in_progress or pending items when finishing

**Deliverable is Working Code:**
- Never end with only a plan
- Implement, test, and verify before completion

## Task Tracking for Long-Running Features

Long-running features that span multiple sessions require persistent task tracking to survive context compression.

**When to Create Task Files:**
- Feature will span multiple agent sessions
- Feature has >5 distinct tasks
- Feature is marked "In Progress" in PRD index

**Location:** `prd/tasks/{feature_name}_tasks.md`

**Template:** Use `prd/_task_template.md` as starting point

**Key Sections:**
1. **Context** - High-level overview and key decisions (critical for recovery)
2. **Tasks** - Hierarchical checklist with phase grouping
3. **Progress Summary** - Percentage complete per phase
4. **Next Session Priorities** - What to do immediately when resuming
5. **Decisions Made** - Architectural decisions with rationale

**Maintenance:**
- Update every 30-60 minutes during active development
- Use `/checkpoint` skill to update automatically

**Context Compression Recovery:**
1. Read `prd/00_index.md` to find "In Progress" features
2. Read corresponding task file
3. Start from "Next Session Priorities"

## PRD Implementation Workflow

### Before Starting Implementation

**Read PRDs thoroughly:**
1. Review the PRD document for the feature you're implementing
2. Understand dependencies on other PRDs
3. Review `.claude/rules/` for coding and security requirements

**Setup development environment:**
```bash
{package_manager} install
{start_dependencies}
{db_generate}
{db_migrate}
```

### Before Creating Pull Request

**Final verification:**
```bash
# 1. Ensure you're up to date with main
git fetch origin
git rebase origin/main

# 2. Run full test suite
{test_all}

# 3. Verify coverage
{test_with_coverage}

# 4. Review your changes
git log origin/main..HEAD
git diff origin/main
```

**Pull Request Checklist:**
- [ ] All tests pass
- [ ] Coverage is maintained or improved
- [ ] Linting passes
- [ ] Type checking passes
- [ ] Security scan passes
- [ ] All functions have type annotations
- [ ] All public functions have docstrings
