# {Feature Name} Tasks

> **Instructions:** Copy this template to create a new task file for a long-running feature.
> Name the file: `prd/tasks/{feature_name}_tasks.md`
> Update this file every 30-60 minutes during active development.

## Context

**Feature:** {Brief description of what's being built}

**PRD Reference:** PRD-{XX}

**Branch:** `feat/{feature_name}`

**Started:** {Date}

**Estimated Completion:** {Date or "TBD"}

## Key Decisions

> Document architectural and implementation decisions here for context recovery.

| Decision | Rationale | Date |
|----------|-----------|------|
| {Decision 1} | {Why this choice} | {Date} |
| {Decision 2} | {Why this choice} | {Date} |

## Tasks

### Phase 1: {Phase Name}

- [ ] Task 1.1: {Description}
- [ ] Task 1.2: {Description}
- [ ] Task 1.3: {Description}

### Phase 2: {Phase Name}

- [ ] Task 2.1: {Description}
- [ ] Task 2.2: {Description}
- [ ] Task 2.3: {Description}

### Phase 3: {Phase Name}

- [ ] Task 3.1: {Description}
- [ ] Task 3.2: {Description}

## Progress Summary

| Phase | Status | Progress |
|-------|--------|----------|
| Phase 1 | {Not Started/In Progress/Complete} | {X}% |
| Phase 2 | {Not Started/In Progress/Complete} | {X}% |
| Phase 3 | {Not Started/In Progress/Complete} | {X}% |
| **Overall** | | **{X}%** |

## Next Session Priorities

> **CRITICAL:** Update this section before ending each session.
> This is what you'll read first after context compression.

1. {Immediate next task}
2. {Second priority}
3. {Third priority}

## Blockers

> List any blockers preventing progress.

- [ ] {Blocker 1}: {Description} - **Waiting on:** {What/Who}
- [ ] {Blocker 2}: {Description}

## Session Log

> Add entries for each work session.

### {Date} - Session {N}

**Duration:** {X} hours

**Completed:**
- {Task completed}
- {Task completed}

**In Progress:**
- {Task in progress}: {Current status}

**Notes:**
- {Any relevant observations}
- {Problems encountered and solutions}

**Next:**
- {What to do next session}

---

### {Date} - Session {N-1}

**Duration:** {X} hours

**Completed:**
- {Task completed}

**Notes:**
- {Notes}

---

## Related Files

> List key files being created or modified.

| File | Purpose | Status |
|------|---------|--------|
| `src/{project}/{file}` | {Purpose} | {New/Modified/Complete} |
| `tests/unit/test_{file}` | {Purpose} | {New/Modified/Complete} |

## Testing Checklist

- [ ] Unit tests written
- [ ] Integration tests written
- [ ] All tests passing
- [ ] Coverage meets minimum ({X}%)
- [ ] Edge cases covered

## Quality Checklist

- [ ] Type annotations complete
- [ ] Docstrings added
- [ ] Linting passes
- [ ] Security scan passes
- [ ] Code reviewed
