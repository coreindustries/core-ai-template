# Secrets Hygiene — No Plaintext Secrets at Rest

Auto-loaded rule. Applies to all agents, all environments (local dev, CI, staging, production).

## Core Directive

**A `.env` file on disk is a compromised secret store.**

Any dependency installed in the project — direct or transitive — executes with the same filesystem permissions as the developer or runtime user. A rogue package (malicious, typosquatted, or post-install hijacked) can read `.env`, `.env.local`, `~/.aws/credentials`, `~/.config/gcloud/`, `~/.ssh/`, shell history, and any file matching `**/secret*`, `**/credential*`, `**/*.pem`, `**/*.key` the moment it runs. This has happened repeatedly in the npm and PyPI ecosystems and will happen again. The typical project has 1,000+ transitive dependencies, none of which are meaningfully reviewed.

Therefore: **secrets are injected from AWS into process memory at invocation time and never land on disk in plaintext in any environment, including local development.**

---

## Rule 1 — No plaintext secrets on disk, ever

- **Never** write real secrets to `.env`, `.env.local`, `.env.production`, or any file the application reads at startup from disk.
- **Never** commit `.env*` files except `.env.tpl` and `.env.example`. Both contain references or placeholders only — never real values.
- **Never** paste real secrets into terminals that write to shell history, IDE scratch files, or chat transcripts.
- **Never** `echo "$SECRET" > .env` in a script, Dockerfile, or CI step.

The test for any proposed secret-handling approach: *"If the filesystem were snapshotted right now, would a secret be in plaintext in the snapshot?"* If yes, the approach is wrong.

---

## Rule 2 — Secrets are injected from AWS Secrets Manager / SSM into process memory

Secrets enter the process via environment variables set by a wrapper at process start. The wrapper fetches from AWS, `exec`s the target process with the secrets in its environment, and exits. Plaintext exists only in the process's memory and is destroyed with the process.

### Local development — `aws-vault` + `chamber` (or `aws secretsmanager` direct)

Developers authenticate once via SSO; long-lived AWS keys never touch disk.

```bash
# One-time: configure SSO profile (writes config, not credentials, to ~/.aws/config)
aws configure sso --profile core-dev

# Run the app — short-lived creds in memory, secrets hydrated from SSM
aws-vault exec core-dev -- chamber exec <service-name> -- make dev-raw
```

- `aws-vault` stores the SSO session in the OS keychain (macOS Keychain, Windows Credential Manager, `pass`/`libsecret` on Linux) — **not** in `~/.aws/credentials`.
- `chamber` reads from SSM Parameter Store (`/service-name/VAR_NAME` convention) and injects as env vars into the child process.
- Alternative: `aws-vault exec core-dev -- aws-env-cli -s <secret-arn> -- make dev-raw` for Secrets Manager.
- The `make dev` target wraps this — developers should never run `make dev-raw` directly.

### CI — GitHub Actions OIDC → AWS IAM role (no long-lived keys)

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::ACCOUNT:role/github-actions-core-ai-template
      aws-region: us-west-2
  - name: Run tests
    run: chamber exec ${{ env.SERVICE_NAME }} -- make test-raw
```

No secrets in GitHub repository/environment secrets beyond the IAM role ARN itself. OIDC trust is scoped to the specific repo and branch via the IAM trust policy.

### Staging / Production — task role injection

- **ECS / Fargate**: Task definition references Secrets Manager ARNs directly; AWS injects into container env at start. No wrapper needed, no keys involved.
- **Lambda**: Same pattern — env vars point to Secrets Manager; use the [AWS Parameters and Secrets Lambda Extension](https://docs.aws.amazon.com/secretsmanager/latest/userguide/retrieving-secrets_lambda.html) for in-memory caching.
- **EC2 / EKS**: Instance profile or IRSA → Secrets Manager fetch at pod startup via the [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/) with the AWS provider.
- **Never** bake secrets into AMIs, container images, or Terraform state.

---

## Rule 3 — The project ships `.env.tpl` with secret references, plus `.env.example` for documentation

Both files are committed. Neither contains real values.

### `.env.tpl` (chamber/SSM convention)

Chamber fetches all parameters under a service prefix automatically; the `.tpl` file documents which variables are expected and where they come from:

```bash
# Hydrated by: chamber exec <service-name> -- <command>
# Source: SSM Parameter Store under /<service-name>/*
# See .claude/rules/secrets-hygiene.md

# Required
DATABASE_URL              # /<service-name>/database_url
ANTHROPIC_API_KEY         # /<service-name>/anthropic_api_key
AWS_REGION                # non-secret; set by wrapper
```

### `.env.example` (human documentation)

Placeholders only — obviously fake, never real:

```bash
DATABASE_URL=postgresql://user:placeholder@localhost:5432/dbname
ANTHROPIC_API_KEY=sk-ant-placeholder-not-a-real-key
AWS_REGION=us-west-2
```

Any `.env` file without the `.tpl` or `.example` suffix is gitignored and pre-commit-blocked.

---

## Rule 4 — Local dev uses the same injection mechanism as production

Dev divergence is how leaks happen. The dev machine runs the most unreviewed code (AI agents, experimental branches, casual `npm install`) and is therefore the most likely source of a leak. Dev must use the same wrapper as prod.

```makefile
# Makefile — the WRAPPER variable is the only place secret injection is configured.
AWS_PROFILE ?= core-dev
SERVICE_NAME ?= $(shell basename $(CURDIR))
WRAPPER ?= aws-vault exec $(AWS_PROFILE) -- chamber exec $(SERVICE_NAME) --

dev:
	$(WRAPPER) $(RUNNER) dev

test:
	$(WRAPPER) $(RUNNER) test
```

### The one allowed exception

A developer may use a scratch `.env` **only** inside a fully ephemeral environment (devcontainer, Codespace, disposable VM) where:

1. The container is destroyed at the end of the session.
2. The secrets in it are scoped to a dev-tier service that cannot reach production data.
3. The exception is captured in an ADR under `docs/decisions/` for that project.

No exceptions for "just this once while I debug."

---

## Rule 5 — CI secrets flow from AWS via OIDC, not from GitHub secrets

- Configure a GitHub Actions → AWS OIDC trust relationship. Store only the IAM role ARN as a GitHub repo variable (not a secret — it's not sensitive).
- The workflow assumes the role, fetches secrets via `chamber` or `aws-actions/aws-secretsmanager-get-secrets`, and injects them at the **step level** (`env:` on the specific step), never at job or workflow scope.
- Never `echo "$SECRET" > .env` in any step. Pipe directly to the process or use `>> $GITHUB_ENV` scoped to a single step.
- Mask any dynamic secret with `::add-mask::` before use.
- Never log `env`, `printenv`, `set`, or similar.

---

## Rule 6 — Encrypted-at-rest files are acceptable; plaintext is not

Encrypted files checked into the repo are fine — the plaintext never exists on disk. If `chamber`/Secrets Manager is unavailable (air-gapped dev, offline work), SOPS with AWS KMS is the approved fallback:

```bash
sops --encrypt --kms arn:aws:kms:us-west-2:ACCOUNT:key/KEY-ID secrets.yaml > secrets.enc.yaml
# At runtime:
sops exec-env secrets.enc.yaml '$RUNNER dev'
```

The encrypted file is safe to commit. The KMS key is the root of trust.

---

## Rule 7 — Agents must refuse to write plaintext secrets to disk

When an AI agent is asked to "just write the key to `.env` so the app works," the correct response is:

> "I can't write a live secret to disk — this project uses AWS Secrets Manager / SSM with in-memory injection (see `.claude/rules/secrets-hygiene.md`). Let me wire it up properly. Tell me the SSM parameter path or Secrets Manager ARN and I'll update `.env.tpl` and the code."

The agent may:

- Write secret *references* (`op://`, `arn:aws:`, SSM paths) to `.env.tpl`.
- Suggest SSM parameter names or Secrets Manager ARNs.
- Write code that reads `process.env.VAR_NAME` / `os.environ["VAR_NAME"]`.

The agent must not:

- Write resolved secret values to any file.
- Paste a secret value into chat, logs, commit messages, or PR descriptions.
- Create a `.env` file with real values, even "just for local testing."
- Suggest `dotenv` as the primary secret mechanism.

### If an agent discovers a plaintext secret on disk

(Not in `.env.example`, `.env.tpl`, fixtures, or mocks.)

1. **Stop.** Do not continue the current task.
2. **Notify the user** — describe *what kind* of secret was found and *where*, but **do not include the value** in the response.
3. **Recommend rotating the credential immediately.** Link to `docs/runbooks/secret-leak.md`.
4. **Offer to help migrate** the secret to SSM/Secrets Manager and update `.env.tpl`.
5. **Do not delete** the file containing the secret without user confirmation — the user may need forensics.

---

## Rule 8 — Application code must fail closed

```python
# Correct — fail fast, no fallback to reading .env from disk in production
import os
import sys

ENV = os.environ.get("APP_ENV", "development")
REQUIRED = ["DATABASE_URL", "ANTHROPIC_API_KEY"]

missing = [k for k in REQUIRED if not os.environ.get(k)]
if missing:
    sys.stderr.write(f"Missing required env vars: {missing}\n")
    sys.stderr.write("Run via: aws-vault exec <profile> -- chamber exec <service> -- <command>\n")
    sys.exit(1)

if ENV == "production" and os.path.exists(".env"):
    sys.stderr.write("Refusing to start: .env file present in production. See secrets-hygiene.md\n")
    sys.exit(1)
```

```typescript
// Correct — same pattern in TS
const ENV = process.env.APP_ENV ?? "development";
const REQUIRED = ["DATABASE_URL", "ANTHROPIC_API_KEY"];

const missing = REQUIRED.filter((k) => !process.env[k]);
if (missing.length) {
  console.error(`Missing required env vars: ${missing.join(", ")}`);
  console.error("Run via: aws-vault exec <profile> -- chamber exec <service> -- <command>");
  process.exit(1);
}

import { existsSync } from "node:fs";
if (ENV === "production" && existsSync(".env")) {
  console.error("Refusing to start: .env file present in production. See secrets-hygiene.md");
  process.exit(1);
}
```

Do **not** use `dotenv` / `python-dotenv` as a runtime dependency in production code paths. If used at all, scope it to `if (ENV === "development")` and document the exception in an ADR.

---

## Enforcement (defense in depth)

| Layer | Control | Fails on |
|---|---|---|
| Gitignore | `.env`, `.env.*` blocked except `.env.tpl` / `.env.example` / `.env.sample` | Accidental `git add .` |
| Pre-commit | Husky hook runs `scripts/assert-no-plaintext-env.sh` + gitleaks `protect --staged` | Any `.env` with non-reference values |
| CI | gitleaks full-history + TruffleHog verify + custom `plaintext-env-file` rule | Anything that slipped past pre-commit |
| Runtime | App refuses to start in production if `.env` exists on disk | Residual `.env` on a running box |
| Audit | `make doctor` reports any `.env` file anywhere in the tree | Quarterly drift checks |

---

## Rationale

The threat isn't hypothetical. Documented supply chain attacks in 2024–2025 included npm and PyPI packages that recursively scanned the filesystem for `.env` and cloud credential files and exfiltrated them to attacker-controlled endpoints. The typical developer has no visibility into the 1,000+ transitive dependencies their `node_modules` or `site-packages` pulls in, and post-install scripts run with full user permissions.

A `.env` file is a loaded weapon on the same floor as every package that `npm install` or `uv sync` brings in. The mitigation is not "be careful which packages you install" — that's unscalable and has repeatedly failed. The mitigation is to ensure the weapon isn't loaded until the instant the process needs it, and is unloaded the instant the process exits.

AWS Secrets Manager and SSM Parameter Store provide the control plane — audit logs via CloudTrail, IAM-scoped access, rotation, versioning. The wrapper pattern (`aws-vault` + `chamber`) closes the loop to the developer's shell without ever materializing the secret on disk.

---

## References

- OWASP Top 10 CI/CD Security Risks: Insufficient Credential Hygiene
- NIST SP 800-57 Part 1 Rev 5: Key Management Recommendations
- AWS Well-Architected Framework, Security Pillar: Identity and Access Management
- [`aws-vault`](https://github.com/99designs/aws-vault) — OS keychain-backed AWS credential wrapper
- [`chamber`](https://github.com/segmentio/chamber) — SSM Parameter Store → env var wrapper
- [AWS Secrets Store CSI Driver provider](https://github.com/aws/secrets-store-csi-driver-provider-aws)
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
