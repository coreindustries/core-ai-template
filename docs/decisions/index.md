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
- New ADR files are named `YYYY-MM-DD-short-title.md`: the date the
  ADR was written, plus a slug. Do not take "the next number". Parallel
  agents doing that pick the same one. The numbered ADRs below keep
  their IDs, and `scripts/assert-doc-ids.sh` (CI + `make pr-check`)
  rejects any *new* numbered ADR.
- **Don't rewrite an accepted ADR.** Supersede it by creating a new
  ADR that references the old one.

## Status lifecycle

- `Proposed` — under discussion, not yet binding
- `Accepted` — active, must be followed
- `Superseded by <id>` — replaced by a newer ADR
- `Deprecated` — no longer relevant, kept for history
- `Rejected` — proposed but not adopted (kept for the record)

## Index

| ID | Title | Status | Date |
|---|---|---|---|
| [0001](0001-no-plaintext-secrets-on-disk.md) | No Plaintext Secrets on Disk — Inject Into Process Memory | Accepted | 2026-04-21 |
| [0002](0002-pin-dependencies-with-24h-cooldown.md) | Pin Dependencies + 24-Hour Cooldown on New Versions | Accepted | 2026-04-21 |
| [0003](0003-supabase-migrations.md) | Database Migrations via Supabase CLI (Default) | Accepted | 2026-04-21 |
| [0004](0004-unified-review-skill-claude-and-cursor.md) | Unified `/review` skill for Claude Code and Cursor | Accepted | 2026-05-13 |
| [0005](0005-ci-cd-supply-chain-hardening.md) | CI/CD Supply Chain Hardening (SHA-pinned actions, credential scope, Zizmor) | Accepted | 2026-05-21 |
| [0006](0006-autonomous-dev-workflow.md) | Autonomous Dev Workflow (self-healing CI, tier-based auto-merge, alert routing) | Accepted | 2026-05-22 |
| [2026-09-24-node-for-template-tooling](2026-09-24-node-for-template-tooling.md) | Template Tooling Runs on the Runner's Default Node, Zero npm Dependencies | Accepted | 2026-09-24 |

## Template

See [adr-template.md](adr-template.md) for the blank template. The
`/adr` skill creates new ADRs from this template, names them by date
and slug, and adds an entry to the index above.

## When an ADR is required

Open an ADR for any change that affects:

- Public or internal API contracts
- Database schema or storage layer
- Deployment architecture (where things run, how they're packaged)
- Security boundaries or trust model
- Major technology choices (language, framework, datastore, queue)

Don't open an ADR for: routine refactors, dependency bumps, bug
fixes, doc edits, or formatting changes.
