# Secrets Hygiene — No Plaintext Secrets at Rest

Auto-loaded rule. Applies to all agents, all environments (local dev, CI, staging, production).

## Core Directive

**A `.env` file on disk is a compromised secret store.**

Any dependency installed in the project — direct or transitive — executes with the same filesystem permissions as the developer or runtime user. A rogue package (malicious, typosquatted, or post-install hijacked) can read `.env`, `.env.local`, cloud credential files in the home directory, `~/.ssh/`, shell history, and any file matching `**/secret*`, `**/credential*`, `**/*.pem`, `**/*.key` the moment it runs. This has happened repeatedly in the npm and PyPI ecosystems and will happen again. The typical project has 1,000+ transitive dependencies, none of which are meaningfully reviewed.

Therefore: **secrets are injected into process memory at invocation time and never land on disk in plaintext in any environment, including local development.**

This rule specifies a **property, not a product**. It names no secret-manager vendor — see `docs/decisions/0001-no-plaintext-secrets-on-disk.md` for why. Any tool satisfying the wrapper contract in Rule 2 is conformant.

---

## Rule 1 — No plaintext secrets on disk, ever

- **Never** write real secrets to `.env`, `.env.local`, `.env.production`, or any file the application reads at startup from disk.
- **Never** commit `.env*` files except `.env.tpl` and `.env.example`. Both contain references or placeholders only — never real values.
- **Never** paste real secrets into terminals that write to shell history, IDE scratch files, or chat transcripts.
- **Never** `echo "$SECRET" > .env` in a script, Dockerfile, or CI step.

The test for any proposed secret-handling approach: *"If the filesystem were snapshotted right now, would a secret be in plaintext in the snapshot?"* If yes, the approach is wrong.

---

## Rule 2 — Secrets are injected into process memory by a wrapper

Secrets enter the process via environment variables set by a wrapper at process start. The wrapper fetches from the secret store, `exec`s the target process with the secrets in its environment, and exits. Plaintext exists only in the process's memory and is destroyed with the process.

### The wrapper contract

A conformant injector must:

1. **Fetch** secrets from the project's secret store at invocation time.
2. **`exec`** the target process with those secrets in its environment.
3. **Never write** them to a file — plaintext lives only in process memory.

Choose any tool that satisfies all three. Selection criteria worth weighing: does it produce an audit log of secret access; does it support rotation without redeploying; does it avoid writing a credential cache to disk (OS keychain rather than a dotfile); and does it already exist in your infrastructure.

### Configuration

The wrapper is configured in exactly one place — `WRAPPER` in the `Makefile`:

```makefile
WRAPPER ?= <your-secret-cli> exec <service> --

dev:
	$(WRAPPER) $(RUNNER) dev

test:
	$(WRAPPER) $(RUNNER) test
```

`WRAPPER` is unset in this template. Until a project sets it, commands run without injection and the application's own fail-closed check (Rule 8) reports which variables are missing. `make doctor` warns while it is unset.

### CI

Use short-lived federated credentials (OIDC or equivalent) rather than long-lived keys stored as CI secrets. Inject at the **step** level, never job or workflow scope:

```yaml
- name: Run tests
  env:
    DATABASE_URL: ${{ secrets.DATABASE_URL }}
  run: make test-raw
```

Where the platform supports it, prefer fetching from the secret store inside the step over storing the value as a CI secret at all — that keeps one store as the source of truth.

### Staging / production

Prefer platform-native injection: the host fetches from the secret store and places values in the process environment at container or function start, with no wrapper and no keys involved. Never bake secrets into images, machine templates, or infrastructure state files.

---

## Rule 3 — The project ships `.env.tpl` with references, plus `.env.example` for documentation

Both files are committed. Neither contains real values.

### `.env.tpl`

Documents which variables are expected and where each comes from:

```bash
# Hydrated by the wrapper — see Makefile WRAPPER and
# .claude/rules/secrets-hygiene.md

# Required (source: your secret store)
DATABASE_URL              # connection string
ANTHROPIC_API_KEY         # Claude API key

# Non-secret configuration — set directly, not from the secret store
LOG_LEVEL
```

### `.env.example`

Placeholders only — obviously fake, never real:

```bash
DATABASE_URL=postgresql://user:placeholder@localhost:5432/dbname
ANTHROPIC_API_KEY=placeholder-not-a-real-key
LOG_LEVEL=debug
```

Note the placeholder does not imitate the provider's real key prefix. The
pre-commit regex backstop (`scripts/precommit-secret-patterns.sh`) matches on
prefixes alone and deliberately does not honour gitleaks' `pragma: allowlist
secret`, so a realistic-looking fake in documentation will block the commit.
That strictness is correct — write placeholders that cannot be mistaken for the
real format.

Any `.env` file without the `.tpl` or `.example` suffix is gitignored and pre-commit-blocked.

---

## Rule 4 — Local dev uses the same injection mechanism as production

Dev divergence is how leaks happen. The dev machine runs the most unreviewed code (AI agents, experimental branches, casual `npm install`) and is therefore the most likely source of a leak. Dev must use the same wrapper contract as prod, even if the concrete tool differs between them.

### The one allowed exception

A developer may use a scratch `.env` **only** inside a fully ephemeral environment (devcontainer, Codespace, disposable VM) where:

1. The container is destroyed at the end of the session.
2. The secrets in it are scoped to a dev-tier service that cannot reach production data.
3. The exception is captured in an ADR under `docs/decisions/` for that project.

No exceptions for "just this once while I debug."

---

## Rule 5 — CI secrets are step-scoped and short-lived

- Prefer federated, short-lived credentials over long-lived keys held as CI secrets.
- Inject at the **step** level (`env:` on the specific step), never at job or workflow scope.
- Never `echo "$SECRET" > .env` in any step. Pipe directly to the process, or write to the step-scoped environment file.
- Mask any dynamic secret before use (e.g. `::add-mask::` on GitHub Actions).
- Never log `env`, `printenv`, `set`, or similar.

---

## Rule 6 — Encrypted-at-rest files are acceptable; plaintext is not

Encrypted files checked into the repo are fine — the plaintext never exists on disk. If the secret store is unavailable (air-gapped dev, offline work), an encrypted-file approach such as SOPS backed by a managed key service is the approved fallback:

```bash
sops --encrypt --kms <key-reference> secrets.yaml > secrets.enc.yaml
# At runtime:
sops exec-env secrets.enc.yaml '$RUNNER dev'
```

The encrypted file is safe to commit. The managed key is the root of trust — never commit the key itself, which would make the encryption decorative.

---

## Rule 7 — Agents must refuse to write plaintext secrets to disk

When an AI agent is asked to "just write the key to `.env` so the app works," the correct response is:

> "I can't write a live secret to disk — this project injects secrets into process memory at start (see `.claude/rules/secrets-hygiene.md`). Let me wire it up properly. Tell me which secret store you use and the reference for this value, and I'll update `.env.tpl` and the code."

The agent may:

- Write secret *references* (store paths, ARNs, item names) to `.env.tpl`.
- Suggest names and locations for new secrets.
- Write code that reads `process.env.VAR_NAME` / `os.environ["VAR_NAME"]`.

The agent must not:

- Write resolved secret values to any file.
- Paste a secret value into chat, logs, commit messages, or PR descriptions.
- Create a `.env` file with real values, even "just for local testing."
- Suggest `dotenv` as the primary secret mechanism.
- Assume a particular secret-manager vendor. Ask which one the project uses.

### If an agent discovers a plaintext secret on disk

(Not in `.env.example`, `.env.tpl`, fixtures, or mocks.)

1. **Stop.** Do not continue the current task.
2. **Notify the user** — describe *what kind* of secret was found and *where*, but **do not include the value** in the response.
3. **Recommend rotating the credential immediately.** Link to `docs/runbooks/secret-leak.md`.
4. **Offer to help migrate** the secret into the project's store and update `.env.tpl`.
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
    sys.stderr.write("Run through the secret wrapper — see Makefile WRAPPER.\n")
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
  console.error("Run through the secret wrapper — see Makefile WRAPPER.");
  process.exit(1);
}

import { existsSync } from "node:fs";
if (ENV === "production" && existsSync(".env")) {
  console.error("Refusing to start: .env file present in production. See secrets-hygiene.md");
  process.exit(1);
}
```

This check is what makes an unset `WRAPPER` safe to ship: the app reports exactly which variables are missing instead of silently starting with none.

Do **not** use `dotenv` / `python-dotenv` as a runtime dependency in production code paths. If used at all, scope it to `if (ENV === "development")` and document the exception in an ADR.

---

## Enforcement (defense in depth)

| Layer | Control | Fails on |
|---|---|---|
| Gitignore | `.env`, `.env.*` blocked except `.env.tpl` / `.env.example` / `.env.sample` | Accidental `git add .` |
| Pre-commit | `scripts/assert-no-plaintext-env.sh` + gitleaks `protect --staged` | Any `.env` with non-reference values |
| Pre-push | `scripts/prepush-secret-check.sh` — range scan + regex backstop | Anything committed with `--no-verify` |
| CI | gitleaks full-history + custom `plaintext-env-file` rule | Anything that slipped past pre-commit |
| Runtime | App refuses to start in production if `.env` exists on disk | Residual `.env` on a running box |
| Audit | `make doctor` reports any `.env` file in the tree, and warns when `WRAPPER` is unset | Quarterly drift checks |

---

## Rationale

The threat isn't hypothetical. Documented supply chain attacks in 2024–2025 included npm and PyPI packages that recursively scanned the filesystem for `.env` and cloud credential files and exfiltrated them to attacker-controlled endpoints. The typical developer has no visibility into the 1,000+ transitive dependencies their `node_modules` or `site-packages` pulls in, and post-install scripts run with full user permissions.

A `.env` file is a loaded weapon on the same floor as every package that `npm install` or `uv sync` brings in. The mitigation is not "be careful which packages you install" — that's unscalable and has repeatedly failed. The mitigation is to ensure the weapon isn't loaded until the instant the process needs it, and is unloaded the instant the process exits.

Which vendor holds the secrets is a downstream decision. Whether the plaintext ever touches disk is not.

---

## References

- `docs/decisions/0001-no-plaintext-secrets-on-disk.md` — the ADR behind this rule
- `docs/runbooks/secret-leak.md` — incident response
- OWASP Top 10 CI/CD Security Risks: Insufficient Credential Hygiene
- NIST SP 800-57 Part 1 Rev 5: Key Management Recommendations
- [SOPS](https://github.com/getsops/sops) — encrypted-file fallback
