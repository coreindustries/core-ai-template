# PRD-05 Autonomous Dev Workflow Tasks

## Context

**Feature:** Autonomous Dev Workflow — stop babysitting agents
**PRD Reference:** PRD-05
**Branch:** `worktree-feat+prd-05-autonomous-dev-workflow`
**Started:** 2026-05-22
**Estimated Completion:** 2026-05-22

## Key Decisions

| Decision | Rationale | Date |
|----------|-----------|------|
| Node.js built-ins only for send-hook.js | No package.json in template — avoid npm dependency | 2026-05-22 |
| workflow_run trigger for auto-fix | Only trigger available that fires after CI completes | 2026-05-22 |
| Same-repo guard on auto-fix | Prevent fork PRs from running Claude with our API key | 2026-05-22 |
| gh pr merge --auto for auto-merge | Uses GitHub's native feature; cleaner than manual polling | 2026-05-22 |
| sleep 1800 for Tier-1 delay | PRD-specified; note in comments to replace with delay action in production | 2026-05-22 |

## Tasks

### Phase 1: Agent Context Bus

- [ ] Task 1.1: Save PRD file to prd/05-autonomous-dev-workflow.md
- [ ] Task 1.2: Create this task tracking file
- [ ] Task 1.3: Create /handoff skill
- [ ] Task 1.4: Add Current State block to CLAUDE.md
- [ ] Task 1.5: Update prd/00_index.md

### Phase 2: Self-Healing CI

- [ ] Task 2.1: Create scripts/classify-ci-failure.sh
- [ ] Task 2.2: Create .github/workflows/auto-fix.yml

### Phase 3: Auto-Merge Policy

- [ ] Task 3.1: Create .github/workflows/auto-merge.yml

### Phase 4: Deploy Observability

- [ ] Task 4.1: Create tools/comms/send-hook.js
- [ ] Task 4.2: Create scripts/post-deploy-health.sh

### Phase 5: CTO Agent Failure Triage

- [ ] Task 5.1: Create .claude/agents/cto.md

## Progress Summary

| Phase | Status | Progress |
|-------|--------|----------|
| Phase 1 | In Progress | 40% |
| Phase 2 | Not Started | 0% |
| Phase 3 | Not Started | 0% |
| Phase 4 | Not Started | 0% |
| Phase 5 | Not Started | 0% |
| **Overall** | | **8%** |

## Next Session Priorities

1. Complete Task 1.3: /handoff skill
2. Complete Task 1.4: CLAUDE.md Current State block
3. Move to Phase 2: scripts/classify-ci-failure.sh

## Blockers

- None

## Session Log

### 2026-05-22 - Session 1

**Duration:** In progress

**Completed:**
- Wrote implementation plan (docs/superpowers/plans/2026-05-22-autonomous-dev-workflow.md)
- Created worktree (feat+prd-05-autonomous-dev-workflow)
- Task 1.1: Created PRD file
- Task 1.2: Created task tracking file

**In Progress:**
- Task 1.5: Update prd/00_index.md

**Notes:**
- No package.json in template — send-hook.js must use Node.js built-ins only
- zizmor review of new workflows needed before merge
