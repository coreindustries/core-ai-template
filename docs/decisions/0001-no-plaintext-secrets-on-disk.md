# ADR-0001: No Plaintext Secrets on Disk — AWS SSM/Secrets Manager Injection

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-21 |
| Decision owners | Core Industries engineering |
| Supersedes | N/A |
| Agents must not change without | Explicit CEO approval + replacement ADR |

## Context

The project template is used as the foundation for all Core Industries downstream projects. Each project will depend on hundreds to thousands of transitive packages (npm, PyPI, Cargo, etc.) that execute with the same filesystem permissions as the developer or runtime user.

Documented supply chain attacks in 2021–2025 have repeatedly shown that rogue dependencies — whether through account takeover, typosquatting, or post-install script injection — harvest on-disk credential stores at the moment they run. Targets include:

- `.env`, `.env.local`, `.env.production`
- `~/.aws/credentials`
- `~/.config/gcloud/`
- `~/.ssh/`
- Files matching `**/secret*`, `**/credential*`, `**/*.pem`, `**/*.key`

The classical mitigation — "audit your dependencies" — does not scale and has repeatedly failed in practice. Developer workstations running AI agents and experimental branches are the most exposed hosts in any engineering organization.

## Decision

**No plaintext secrets will be stored on disk in any environment (local development, CI, staging, production).** Secrets are fetched from AWS Secrets Manager / SSM Parameter Store into process environment memory at invocation time by a wrapper that `exec`s the target process. The plaintext value exists only in the child process's memory and dies with the process.

### Components

| Layer | Tool | Responsibility |
|---|---|---|
| Local dev auth | AWS IAM Identity Center (SSO) | Human auth; no long-lived keys on disk |
| Local credential cache | `aws-vault` | OS keychain-backed short-lived credential cache |
| Local secret injection | `chamber` (SSM) + `aws-vault exec` | Fetch + inject into child process env |
| CI auth | GitHub Actions OIDC → IAM role | No long-lived keys in GitHub secrets |
| CI secret injection | `chamber exec` in workflow step | Step-scoped env vars only |
| Runtime (ECS/Fargate) | Task definition → Secrets Manager ARN | AWS injects at container start |
| Runtime (Lambda) | Parameters and Secrets Lambda Extension | In-memory, cached |
| Runtime (EKS) | Secrets Store CSI Driver (AWS provider) | Projected volume → env var |
| Offline fallback | SOPS + AWS KMS | Encrypted-at-rest file, decrypted in memory |

### What is committed to the repo

- `.env.tpl` — variable names + SSM paths (references, not values)
- `.env.example` — variable names + obvious placeholder values (for documentation)
- `.gitleaks.toml` — custom `plaintext-env-file` rule blocks real values slipping in
- `scripts/assert-no-plaintext-env.sh` — pre-commit gate
- `Makefile` — `WRAPPER` variable wraps all commands through the secret injector

### What is NOT committed

- Any `.env` file with real values (blocked by gitignore, pre-commit, CI, runtime)
- AWS access keys (OIDC + SSO means they don't exist)
- Encrypted secret files without a corresponding decryption key in AWS KMS

## Consequences

### Positive

- A compromised transitive dependency on a developer workstation cannot read production secrets from disk — they aren't on disk.
- Dev / CI / prod use the same injection mechanism, eliminating the "it worked locally" class of secret-handling bugs.
- All secret access is auditable via CloudTrail.
- Secret rotation is a one-command operation (`chamber write ...`) rather than a fleet-wide file replacement.
- Developers cannot accidentally `git add .env` because the file doesn't exist.

### Negative

- Adds a hard dependency on AWS for all development work. Developers offline or in AWS outages cannot start the application. Mitigated by the SOPS+KMS fallback for air-gapped work.
- Requires every contributor to install `aws-vault` and `chamber` and have an SSO-configured AWS account. Adds ~10 minutes to onboarding.
- Team members without AWS access cannot run the project. This is a feature, not a bug — it enforces least privilege — but it's operationally heavier than `cp .env.example .env`.
- CI setup requires provisioning the OIDC trust relationship and IAM role, which is one-time but not trivial.

### Neutral

- Requires discipline: every new secret must go through `chamber write`, not `.env`. Enforced mechanically via the pre-commit gate, but still requires team literacy.

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| `.env` + git-ignore (status quo in most templates) | Doesn't address rogue dependency threat; `.env` is readable by every installed package |
| 1Password CLI (`op run`) | Excellent UX, but introduces non-AWS SaaS dependency and requires 1Password org-wide; AWS-native is the right fit for Core given existing infrastructure |
| HashiCorp Vault | Higher operational burden than SSM/Secrets Manager for the size of Core's operation; worth revisiting at larger scale |
| Doppler / Infisical | Third-party SaaS; adds breach surface and vendor dependency when AWS-native covers the use case |
| Environment variables set by the shell profile (`~/.zshrc`) | Persists on disk in shell rc files; same threat model as `.env` |
| Pure runtime IAM on developer machines (no secrets at all) | Ideal but not always possible for third-party API keys (Anthropic, Stripe, etc.) |

## Agent Guidance

**When working in this codebase, AI agents must:**

1. Never create a `.env` file containing real secret values.
2. Refuse requests to "just write the key to `.env` to get things working." Instead, offer to wire up the SSM reference in `.env.tpl` and update the wrapper command.
3. When asked to add a new secret, the workflow is: confirm the SSM path with the user → update `.env.tpl` → update code to read from env → never write the value anywhere.
4. When asked to debug missing secrets, check: is the wrapper being used? Does the SSM path exist? Is the IAM role scoped correctly? Never suggest "add it to `.env` as a workaround."
5. If a plaintext secret is discovered on disk, stop, notify the user (without including the value), and recommend rotation + migration. See `docs/runbooks/secret-leak.md`.

## References

- `.claude/rules/secrets-hygiene.md` — operational rules (auto-loaded)
- `docs/runbooks/secret-leak.md` — incident response
- [AWS IAM Identity Center (SSO)](https://docs.aws.amazon.com/singlesignon/)
- [`aws-vault`](https://github.com/99designs/aws-vault)
- [`chamber`](https://github.com/segmentio/chamber)
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- OWASP Top 10 CI/CD Security Risks: CICD-SEC-6 Insufficient Credential Hygiene
