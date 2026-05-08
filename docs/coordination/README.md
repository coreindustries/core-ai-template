# Cross-Repo Coordination

This directory tracks **work that crosses a repository boundary** — a
schema change in one repo that another repo depends on, an ops task
the other team must do before this team can ship, a contract
negotiation between two services, etc.

GitHub issues and PRs are the right tool for work inside one repo.
But when the change spans two (or more), the issue tracker on either
side gives only half the picture. A coordination doc is the durable,
checked-in record of the cross-cut: who needs what, who's doing it,
what state both sides are in.

## When to open a coordination doc

Open one when **all** of the following are true:

1. Work in this repo blocks (or is blocked by) work in another repo.
2. The other repo is owned by a different team, or by the same team
   but has its own release cadence.
3. The change is large enough that "ping in chat" will get lost.

If the work is < 1 hour and the other-repo PR will land today, a
chat thread or a single PR comment is fine. Coordination docs are
for work that lives across days/weeks.

## File naming and location

```
docs/coordination/
  README.md              # this file (the index)
  _template.md           # blank template for new docs
  001_<slug>.md
  002_<slug>.md
  ...
```

Three-digit zero-padded sequence number, then a short slug. The
sequence is local to **this** repo — the partner repo has its own
sequence. Each doc cross-references the partner's doc number.

## Frontmatter schema

Every coordination doc starts with YAML frontmatter:

```yaml
---
id: 5                            # matches the filename prefix
direction: incoming              # incoming | outgoing
title: Short description
from: <originating-repo>         # owner/repo
to: <receiving-repo>             # owner/repo
prd: PRD-NNN or "ad-hoc"         # parent PRD or goal, if any
status: Requested                # Requested | In Progress | Done | Superseded
created: 2026-MM-DD              # ISO date
branch: <branch-name>            # optional: where the related work lives
related_pr:                      # optional: list of PR URLs on either side
  - https://github.com/.../pull/123
---
```

## Lifecycle

### Incoming: another repo → this repo

The partner repo writes the request in **their** `docs/coordination/`.
When work begins on our side, we **mirror** the doc here with an
`## Implementation Notes` section prepended.

| Stage | Their status | Our status | Action |
|---|---|---|---|
| Request opened | `Requested` | — | Partner writes their doc |
| Work starts | `In Progress` | `In Progress` | Mirror here, begin implementation |
| Our PR merges | `In Progress` | `Done` | Update our status; reference doc # in PR body |
| Partner confirms | `Done` | `Done` | Partner updates their status |

**To pick up a new incoming request:**

1. `git pull` in the partner repo to get their latest
   `docs/coordination/`.
2. Copy `<their-repo>/docs/coordination/NNN_*.md` here.
3. Set `direction: incoming` and update `status: In Progress`.
4. Insert `## Implementation Notes` at the top of the body
   (above the partner's original write-up).
5. Implement, open a PR, reference this coordination doc number in
   the PR body.

### Outgoing: this repo → another repo

We write the request here, then file an issue or open a PR in the
partner repo with a link back to this doc.

| Stage | Our status | Their status | Action |
|---|---|---|---|
| Request opened | `Requested` | — | We write the doc here |
| Work starts | `In Progress` | `In Progress` | Partner mirrors in their repo, begins work |
| Their PR merges | `In Progress` | `Done` | Partner notifies via PR; we update status |
| We confirm + ship | `Done` | `Done` | We merge dependent code |

**To open a new outgoing request:**

1. `cp _template.md NNN_<slug>.md` (next sequence number).
2. Fill in the frontmatter with `direction: outgoing`.
3. File an issue or PR in the partner repo with a link to this doc.
4. Update `status: In Progress` once the partner acknowledges.

## What goes in the doc body

The body is split into two sections:

### `## Implementation Notes` (top of body, mirrored docs only)

The receiving side's perspective. What did/will we change, on what
branch, what tests, what's left? When this hits `Done`, this section
becomes the primary reference for "what we shipped on our side."

### Original request (below)

The originator's write-up. Don't edit it once it lands here — treat
it as immutable history. If the spec changes, append a `## Update
YYYY-MM-DD` section rather than overwriting.

## Common request types

A coordination doc usually maps to one of these:

- **Schema migration** — we need a new column, table, index, RLS
  policy, etc. in the partner repo's database.
- **Schema question** — clarify column semantics or expected value
  ranges before we depend on them.
- **API contract update** — we want to write/read a new field; the
  partner needs to confirm or extend their schema.
- **Ops request** — partner must update a deploy path, inject a new
  env var, change a CI rule.
- **Deprecation** — we're dropping a contract; partner needs lead
  time to migrate consumers.

## What this directory is **not**

- Not a substitute for tickets in the partner team's tracker if they
  use one — file there too.
- Not a chat history. Discussion belongs in the linked PR / issue.
  This directory is the durable summary of state.
- Not a place for project-internal task lists — use `prd/tasks/` for
  those.

## Index

Maintain two tables below as the work moves. When status changes,
update both this index and the doc's frontmatter.

### Incoming requests

| # | Title | From | PRD | Status |
|---|---|---|---|---|
| _none yet_ | | | | |

### Outgoing requests

| # | Title | To | PRD | Status |
|---|---|---|---|---|
| _none yet_ | | | | |
