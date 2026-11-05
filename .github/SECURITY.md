# Security Policy

This file is the entry point. The policies themselves live in the sources linked below; read those, not a copy here.

## Reporting a vulnerability

Report privately through GitHub: **Security → Report a vulnerability** on this repository. Do not open a public issue. Forks of this template: replace this section with your own contact and response targets.

## Leaked credential

A secret on disk, in git history, in CI logs or in a PR: follow [`docs/runbooks/secret-leak.md`](../docs/runbooks/secret-leak.md). Rotate first, investigate second.

## Sources of truth

| Topic | Source |
|---|---|
| Secrets never at rest in plaintext | [`.claude/rules/secrets-hygiene.md`](../.claude/rules/secrets-hygiene.md), [ADR 0001](../docs/decisions/0001-no-plaintext-secrets-on-disk.md) |
| Core secure-coding rules | [`.claude/rules/security-core.md`](../.claude/rules/security-core.md) |
| Dependency pinning and the 3-day cooldown | [`.claude/rules/dependency-security.md`](../.claude/rules/dependency-security.md) |
| Agent safety boundaries | [`.claude/rules/guardrails.md`](../.claude/rules/guardrails.md) |
| Secret and PII scanning | [`.gitleaks.toml`](../.gitleaks.toml), `make scan-secrets` |
