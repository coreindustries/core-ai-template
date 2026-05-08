# Spread-Kit

A generic, stack-agnostic toolkit for bringing existing repositories up to
this template's tooling, security, and process spec.

## Entry Point

→ **[`APPLY.md`](./APPLY.md)** — phased operator's manual.

## What It Is

A markdown playbook an operator (human or AI agent) can execute on a target
repo to adopt:

- Secrets hygiene (no plaintext `.env`, secret-manager injection, gitleaks)
- Dependency security (exact pinning, 24h cooldown, lockfile integrity)
- Quality gates (pre-commit hooks, 5-gate CI, conventional commits)
- Migration discipline (numbered, immutable, expand/contract)
- Agent guidance (`.claude/` tree: rules, skills, agents, references)
- Process docs (CLAUDE.md, AGENTS.md, CONTRIBUTING.md, PRD, ADRs, runbooks)
- Dev environment (devcontainer, VS Code, worktrees)

## Operating Principles

Idempotent · non-destructive · one PR per phase · verify after each phase ·
generic over stack-specific · refuse to weaken existing stricter rules.

## Re-run

The kit is safe to re-run when it upgrades (new rule, tightened scanner,
new skill). Each phase checks for existing state and merges or skips.

## Inputs the Kit Reads

- `prd/00_technology.md` of the target repo (after Phase 7 fills it in) —
  source of truth for stack-specific commands.
- `Makefile` — every kit target shells through `make`.

Nothing in this directory contains project-specific identifiers, customer
names, or proprietary configuration. It is safe to publish.
