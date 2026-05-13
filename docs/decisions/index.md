# Architecture Decision Records

Short, durable records capturing significant technical decisions made
in this project. Format is inspired by [MADR](https://adr.github.io/madr/)
with two AI-agent-specific additions: every ADR includes an
**Agent Guidance** line (one sentence the agent must follow) and a
**Do Not Change** list (patterns the agent must preserve).

## How to use

- **Before proposing architectural changes**, read relevant ADRs to
  understand why current patterns exist.
- **After making a non-obvious decision**, run `/adr` to capture it.
- ADR files are stored in this directory as
  `NNNN-short-title.md` (zero-padded, strictly increasing).
- **Don't rewrite an accepted ADR.** Supersede it by creating a new
  ADR that references the old one.

## Status lifecycle

- `Proposed` — under discussion, not yet binding
- `Accepted` — active, must be followed
- `Superseded by NNNN` — replaced by a newer ADR
- `Deprecated` — no longer relevant, kept for history
- `Rejected` — proposed but not adopted (kept for the record)

## Index

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-no-plaintext-secrets-on-disk.md) | No Plaintext Secrets on Disk — AWS SSM/Secrets Manager Injection | Accepted | 2026-04-21 |
| [0002](0002-pin-dependencies-with-24h-cooldown.md) | Pin Dependencies + 24-Hour Cooldown on New Versions | Accepted | 2026-04-21 |
| [0003](0003-supabase-migrations.md) | Database Migrations via Supabase CLI (Default) | Accepted | 2026-04-21 |
| [0004](0004-unified-review-skill-claude-and-cursor.md) | Unified `/review` skill for Claude Code and Cursor | Accepted | 2026-05-13 |

## Template

See [adr-template.md](adr-template.md) for the blank template. The
`/adr` skill creates new ADRs from this template, picks the next
number, and prepends an entry to the index above.

## When an ADR is required

Open an ADR for any change that affects:

- Public or internal API contracts
- Database schema or storage layer
- Deployment architecture (where things run, how they're packaged)
- Security boundaries or trust model
- Major technology choices (language, framework, datastore, queue)

Don't open an ADR for: routine refactors, dependency bumps, bug
fixes, doc edits, or formatting changes.
