# ADR: Three-Day Cooldown on New Dependency Versions

- **Status**: Accepted
- **Date**: 2026-11-04
- **Deciders**: Operator
- **Supersedes**: ADR-0002 (cooldown length only; its pinning decisions stand)
- **Related**: `.claude/rules/dependency-security.md`

## Context

ADR-0002 set a 24-hour cooldown because malicious versions were typically yanked
within 4–36 hours. A 24-hour wait sits inside the top of that range: a version
yanked at hour 30 would already be in our builds. The operator wants more margin
than that, but a 7-day wait was rejected in ADR-0002 as too much friction on
legitimate fixes.

## Decision

Every added or upgraded dependency must be **at least 3 days (72 hours) old** at
merge time, for every ecosystem and update type (no separate, shorter or longer
major-version window).

- One source of the number: `MIN_AGE_HOURS` default in
  `scripts/assert-dependency-age.sh`. CI relies on that default.
- Dependabot: `cooldown.default-days: 3` in `.github/dependabot.yml`.
- Waiver label renamed `security-hotfix-24h-waiver` → `security-hotfix-waiver`,
  because the old name embedded the superseded length. Same rules: a published
  advisory (GHSA/CVE) must be cited.

All other ADR-0002 decisions (exact pins, lockfiles, SHA/digest pinning) are
unchanged.

## Consequences

- Covers the observed 4–36 hour yank window with margin; a fix that is not a
  published advisory waits up to 3 days.
- Dependabot PRs open up to 2 days later than before.
- Consumers who adopted the old label name get it renamed in place by
  `labels-sync` (the `aliases:` entry in `.github/labels.yml`).

## Alternatives considered

- **Keep 24 hours**: inside the yank window; rejected for margin.
- **7 days**: more margin, but more friction on legitimate fixes (ADR-0002's
  objection still applies).
