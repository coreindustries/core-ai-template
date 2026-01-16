# AGENTS.md

Quick reference for AI agents. **Full details: `prd/01_Technical_standards.md`**

## Core Principles

**Autonomy:** Bias to action. Implement with reasonable assumptions rather than requesting clarification.

**Persistence:** Complete tasks end-to-end. Don't stop at plans or partial fixes.

**Quality:** Correctness over speed. No risky shortcuts, tight error handling, DRY principle.

## Efficient Exploration

```
# BAD: Sequential reads
read("api/routes.{ext}")
read("services/user.{ext}")

# GOOD: Parallel batch (think first, then batch)
read_parallel(["api/routes.{ext}", "services/user.{ext}", "models/user.{ext}"])
```

## Code Standards Quick Reference

- **Type annotations** on everything (functions, attributes, returns)
- **Docstrings** on public functions/classes (use project's convention)
- **Modern syntax:** Use current language features, avoid deprecated patterns
- **Error handling:** No broad exception catches, propagate errors explicitly
- **DRY:** Search for existing implementations before creating new

## Quality Check Loop

```bash
# During development (every 15-30 min)
# See prd/02_Tech_stack.md for specific commands:
{lint_check} {source_dir}
{type_check} {source_dir}
{test_specific} tests/unit/test_module.{ext}

# Before commits
{test_with_coverage}
```

## Project-Specific Patterns

See `prd/02_Tech_stack.md` for technology-specific patterns including:
- Database access patterns
- Audit logging usage
- ORM-specific requirements

## Git Hygiene

- **Never revert** changes you didn't make
- **Never use** destructive commands without explicit approval
- **Commit format:** `<type>: <description>` with `Co-Authored-By: Claude`

## Context Recovery (After Compression)

1. Read `prd/00_PRD_index.md` → Find "In Progress" features
2. Read `prd/tasks/{feature}_tasks.md` → Load context and progress
3. Review "Next Session Priorities" → Continue where left off
4. Update task file every 30-60 minutes with `/checkpoint`

## Task Tracking

For long-running features:
- Create: `prd/tasks/{feature}_tasks.md` (use template)
- Update: Every 30-60 min or after milestones
- Commit IDs: `[PRD-XX Task Y.Z]` in commit messages

## Common Gotchas

See `prd/02_Tech_stack.md` for technology-specific gotchas.

**Universal gotchas:**
1. Use project's package manager (never install to host OS)
2. Regenerate clients after schema changes
3. Use singleton database patterns
4. Mark integration tests appropriately

## Skills Reference

| Skill | Purpose |
|-------|---------|
| `/new-feature` | Scaffold feature with routes, models, services, tests |
| `/checkpoint` | Update task file with progress |
| `/test` | Run tests with coverage |
| `/refactor` | Safely refactor code |
| `/lint` | Format and check code |

## Deep Reference

- **Full standards:** `prd/01_Technical_standards.md`
- **Tech stack:** `prd/02_Tech_stack.md`
- **Task template:** `prd/tasks/TASK_TEMPLATE.md`
- **Security:** `prd/03_Security.md`
