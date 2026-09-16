# ADR-0001: No Plaintext Secrets on Disk — Inject Into Process Memory

| Field | Value |
|---|---|
| Status | Accepted |
| Date | 2026-04-21 |
| Decision owners | Engineering |
| Supersedes | N/A |
| Agents must not change without | Explicit owner approval + replacement ADR |

## Context

This template is the foundation for downstream projects. Each will depend on hundreds to thousands of transitive packages (npm, PyPI, Cargo, etc.) that execute with the same filesystem permissions as the developer or runtime user.

Documented supply chain attacks in 2021–2025 have repeatedly shown that rogue dependencies — whether through account takeover, typosquatting, or post-install script injection — harvest on-disk credential stores at the moment they run. Targets include:

- `.env`, `.env.local`, `.env.production`
- Cloud provider credential files in the user's home directory
- `~/.ssh/`
- Files matching `**/secret*`, `**/credential*`, `**/*.pem`, `**/*.key`

The classical mitigation — "audit your dependencies" — does not scale and has repeatedly failed in practice. Developer workstations running AI agents and experimental branches are the most exposed hosts in any engineering organization.

## Decision

**No plaintext secrets will be stored on disk in any environment (local development, CI, staging, production).** Secrets are fetched from a secret manager into process environment memory at invocation time by a wrapper that `exec`s the target process. The plaintext value exists only in the child process's memory and dies with the process.

**This template deliberately names no secret-manager vendor.** The decision is about the *property*, not the product. Any tool satisfying the wrapper contract below is conformant, and the choice belongs to the downstream project, which knows what infrastructure it already runs.

### The wrapper contract

A conformant secret injector must:

1. Fetch secrets from the project's secret store at invocation time.
2. `exec` the target process with those secrets in its environment.
3. Never write them to a file — plaintext lives only in process memory.

It is configured once, as `WRAPPER` in the `Makefile`, and every runtime target flows through it.

### Components — by role, not by product

| Layer | Responsibility | Chosen by |
|---|---|---|
| Local developer auth | Human auth with no long-lived keys written to disk | Downstream project |
| Local credential cache | OS keychain-backed short-lived credential storage | Downstream project |
| Local secret injection | Fetch + inject into the child process env (`WRAPPER`) | Downstream project |
| CI auth | Short-lived federated credentials (e.g. OIDC), not long-lived keys stored as CI secrets | Downstream project |
| CI secret injection | Step-scoped env vars only — never job- or workflow-scoped | This template (pattern) |
| Runtime | Platform-native secret injection at container/function start | Hosting platform |
| Offline fallback | Encrypted-at-rest file decrypted into memory (e.g. SOPS with a KMS of your choice) | Downstream project |

### What is committed to the repo

- `.env.tpl` — variable names + where each is sourced from (references, not values)
- `.env.example` — variable names + obvious placeholder values (for documentation)
- `.gitleaks.toml` — custom `plaintext-env-file` rule blocks real values slipping in
- `scripts/assert-no-plaintext-env.sh` — pre-commit gate
- `Makefile` — `WRAPPER` wraps all runtime commands through the secret injector

### What is NOT committed

- Any `.env` file with real values (blocked by gitignore, pre-commit, CI, runtime)
- Long-lived cloud or API credentials of any kind
- Encrypted secret files whose decryption key is not held in a managed key service

## Consequences

### Positive

- A compromised transitive dependency on a developer workstation cannot read production secrets from disk — they aren't on disk.
- Dev / CI / prod use the same injection mechanism, eliminating the "it worked locally" class of secret-handling bugs.
- Secret access is auditable, assuming the chosen store provides an audit log — a selection criterion, not an afterthought.
- Secret rotation is a one-command operation in the store rather than a fleet-wide file replacement.
- Developers cannot accidentally commit `.env` because the file doesn't exist.

### Negative

- Adds a dependency on the chosen secret manager for all development work. Developers offline, or during an outage of that service, cannot start the application. Mitigated by the encrypted-file fallback for air-gapped work.
- Requires every contributor to install the wrapper tooling and hold credentials for the store. Adds onboarding time.
- Team members without access to the store cannot run the project. This is a feature, not a bug — it enforces least privilege — but it's operationally heavier than `cp .env.example .env`.
- CI setup requires provisioning a federated trust relationship, which is one-time but not trivial.
- **The template ships with `WRAPPER` unset.** Until a project sets it, commands run without injection. This keeps an uninitialized template runnable, and `make doctor` warns about it, but it does mean the protection is opt-in at first run rather than default-on.

### Neutral

- Requires discipline: every new secret must go through the store, not `.env`. Enforced mechanically via the pre-commit gate, but still requires team literacy.

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| `.env` + git-ignore (status quo in most templates) | Doesn't address the rogue dependency threat; `.env` is readable by every installed package |
| Naming one specific vendor in the template | Forces downstream projects onto infrastructure they may not run, and dates the template as products change. The wrapper contract captures what actually matters |
| Environment variables set in a shell profile (`~/.zshrc`) | Persists on disk in shell rc files; same threat model as `.env` |
| Pure runtime workload identity, no secrets at all | Ideal where it applies, and preferred when it does — but not possible for third-party API keys, so it cannot be the whole answer |
| Committing encrypted secrets with the key in the repo | Moves the problem rather than solving it; the key is then the on-disk secret |

## Agent Guidance

**When working in this codebase, AI agents must:**

1. Never create a `.env` file containing real secret values.
2. Refuse requests to "just write the key to `.env` to get things working." Instead, offer to add the reference to `.env.tpl` and wire the code to read it from the environment.
3. When asked to add a new secret, the workflow is: confirm with the user where it lives in their store → update `.env.tpl` → update code to read from env → never write the value anywhere.
4. When asked to debug missing secrets, check: is `WRAPPER` set and being used? Does the secret exist in the store? Are the credentials scoped correctly? Never suggest "add it to `.env` as a workaround."
5. Never name or assume a specific secret-manager vendor. Ask which one the project uses.
6. If a plaintext secret is discovered on disk, stop, notify the user (without including the value), and recommend rotation + migration. See `docs/runbooks/secret-leak.md`.

## References

- `.claude/rules/secrets-hygiene.md` — operational rules (auto-loaded)
- `docs/runbooks/secret-leak.md` — incident response
- OWASP Top 10 CI/CD Security Risks: CICD-SEC-6 Insufficient Credential Hygiene
- NIST SP 800-57 Part 1 Rev 5 — Key Management Recommendations
