---
name: adr
description: >-
  Record an Architecture Decision Record when making a non-obvious architectural call,
  capturing the decision, its alternatives, and the constraints a future agent must not
  silently undo. Use when choosing between viable approaches, adopting or dropping a
  dependency, or changing a pattern other code depends on. Do not use for routine
  implementation choices that no future reader would question, or to document a decision
  already recorded — amend that ADR instead.
---

# /adr

Create an Architecture Decision Record (ADR) when making a non-obvious architectural call. Captures the decision, context, and agent-specific guidance to prevent future agents from undoing intentional choices.

## Usage

```
/adr <title> [--status <status>]
```

## Arguments

- `title`: Short description of the decision (e.g., "use Prisma over SQLAlchemy")
- `--status`: Decision status (default: `Accepted`). Options: `Proposed`, `Accepted`, `Deprecated`

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Gather context from the current session — what was decided and why
- Determine the next ADR number automatically
- Generate the full ADR document without prompting
- Update the index file

**Quality:**
- Focus on the WHY, not just the WHAT
- The `Agent Guidance` field is the most important — it tells future agents what to do
- The `Do Not Change` field prevents accidental refactoring of intentional patterns
- Keep it concise — aim for a document that takes < 2 minutes to read

### Process

#### 1. Assign the ADR ID

The ID is today's date plus a slug: `YYYY-MM-DD-<slug>`. Do **not** find the highest number and add one. Two agents doing that at the same time pick the same number, and neither finds out until merge. Existing `NNNN-*` ADRs keep their numbers; `scripts/assert-doc-ids.sh` rejects any *new* numbered one.

```bash
echo "$(date -u +%F)-<kebab-slug>"   # e.g. 2026-09-24-queue-backend
```

#### 2. Gather Decision Context

From the current session, extract:

- **Context**: What problem or question led to this decision?
- **Options considered**: What alternatives were evaluated?
- **Decision**: What was chosen and why?
- **Trade-offs**: What are the positive and negative consequences?
- **Agent guidance**: One sentence telling future agents how to behave
- **Do not change**: Patterns that must be preserved

If context is unclear, ask the user a maximum of 2 clarifying questions.

#### 3. Create ADR File

**Filename:** `docs/decisions/YYYY-MM-DD-{slug}.md`

Use the template from `docs/decisions/adr-template.md` with all fields filled in.

#### 4. Update Index

Add a row to the table in `docs/decisions/index.md`:

```markdown
| [YYYY-MM-DD-{slug}](YYYY-MM-DD-{slug}.md) | {Title} | Accepted | YYYY-MM-DD |
```

#### 5. Present Summary

```
ADR created: docs/decisions/YYYY-MM-DD-{slug}.md

Decision: {one-line summary}
Agent Guidance: {the agent-guidance field}
Do Not Change: {count} patterns locked

Index updated: docs/decisions/index.md
```

## When to Use This Skill

Use `/adr` after:
- Choosing one technology/library over another
- Deciding on an architectural pattern (e.g., service layer, event sourcing)
- Making a non-obvious design choice that future developers might question
- Resolving a trade-off where the reasoning matters
- Any decision where you think "a future agent might try to change this"

**Don't use for:**
- Obvious choices that follow existing project patterns
- Trivial implementation details
- Temporary workarounds (use `/compound` instead)

## Example

```
$ /adr "use cursor-based pagination over offset"

ADR created: docs/decisions/0001-use-cursor-based-pagination-over-offset.md

Decision: Use cursor-based pagination for all list endpoints
Agent Guidance: Do not convert cursor pagination to offset — cursor was
chosen for consistent ordering under concurrent writes.
Do Not Change: 2 patterns locked

Index updated: docs/decisions/index.md
```
