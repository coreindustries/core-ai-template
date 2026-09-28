# Task Management Rules

**Scope:** Task tracking, plan discipline, PRD implementation workflow

## When to Create Plans

**Skip Plans For:**
- Straightforward tasks
- Single-step changes
- Obvious fixes

**Create Plans For:**
- Multi-step features
- Complex refactorings
- Cross-cutting changes
- Tasks requiring coordination across multiple files

## Plan Discipline

Plans MUST be reconciled before finishing a task.

**Plan Lifecycle:**
1. Create plan with clear steps
2. Update plan after completing each step (mark as Done)
3. Before finishing, ensure every item is:
   - **Done**: Completed successfully
   - **Blocked**: With one-sentence reason and targeted question
   - **Cancelled**: With reason for cancellation
4. No in_progress or pending items when finishing

## Deliver the requested outcome

Implementation requests require appropriately verified working changes. Reviews, audits, design, dry runs and PRD-only requests end with the requested findings or artifact and do not authorize implementation or runtime mutation.

## Long-running work

Keep one authoritative progress record: the existing issue/PR or a task file. Lanes follow their shared protocol's issue ownership. Other documents link to that record instead of maintaining duplicate status or percentages. Use `prd/_task_template.md` only when a task file is the chosen owner.

Update after material decisions, proof or handoff with the outcome, exact artifacts, next step and remaining uncertainty. Resume from this record before re-investigating. Follow `delivery-contract.md` for applicable ownership and retirement decisions.

## PRD implementation and completion

Read the relevant PRD, `prd/00_technology.md` and applicable project rules. Use the existing locked setup commands and authorized test resources; do not assume a database migration or dependency installation is necessary.

Review the actual branch, tracked/staged changes and untracked files. Resolve the repository's default branch; fetch when current upstream state matters. Integrate upstream changes only when required, honoring branch ownership; do not automatically rebase or rewrite shared history.

Complete affected verification and existing required gates under `testing.md` and `quality-checks.md`, including the mandatory judge. Preserve security and coverage requirements. Report remaining gaps accurately; passing focused checks is not proof the entire product was tested.
