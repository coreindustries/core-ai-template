# Spread-Kit — Bring an Existing Repo Up to Template Spec

This document is the **operator's manual** for applying the tooling, process,
and security standards from this template to an existing repository. It is
written so an AI agent (or a human) can execute it top-to-bottom on a target
repo without prior knowledge of that repo.

The kit is **generic and stack-agnostic**. Stack-specific commands appear as
`{placeholders}` that the operator fills in after reading
`prd/00_technology.md` (or its equivalent) in the target repo.

---

## What "Up to Spec" Means

A repo is up to spec when **all** of the following are true:

| Pillar | Requirement |
|---|---|
| **Secrets** | No plaintext `.env` on disk; secrets injected from a secret manager into process memory at start; `.env.tpl` + `.env.example` committed; gitleaks runs in pre-commit, pre-push, and CI |
| **Dependencies** | All direct deps pinned to exact versions; lockfile committed; 24-hour cooldown enforced via Dependabot/Renovate config + CI gate; base images and CI actions pinned by digest/SHA |
| **Quality gates** | Pre-commit runs lint + format + secret scan; CI runs lint → typecheck → test (with coverage threshold) → security → build; commit messages enforced (Conventional Commits) |
| **Migrations** | Numbered, timestamped, reviewed; never edited after merge; expand/contract for breaking changes; RLS enforced where applicable |
| **Agent guidance** | `CLAUDE.md` + `AGENTS.md` present; `.claude/rules/` auto-loaded universal rules; platform rules opted in via symlink; skills + agents + references available |
| **Process docs** | `CONTRIBUTING.md`, `prd/` scaffolding, `docs/decisions/` (ADRs), `docs/solutions/` (knowledge capture), task templates |
| **Recovery** | `make doctor` audits the repo; task files survive context compression; ADRs explain non-obvious decisions |

If any item is missing or partial, the corresponding phase below applies.

---

## Operating Principles

1. **Idempotent.** Every phase checks for existing state and skips or merges
   instead of overwriting. Re-running the kit on a partially-adopted repo
   converges; it does not regress.
2. **Non-destructive.** Never delete or rewrite project-specific files
   (source code, tests, custom configs). When merging into a file the target
   already owns (e.g. `package.json`, an existing `Makefile`), surface the
   diff and ask before clobbering.
3. **One PR per phase.** Each phase is a reviewable unit. Do not bundle
   "secrets hygiene" with "agent guidance" — they have different reviewers
   and different blast radii.
4. **Verify after each phase.** Each phase ends with a "Verify" block that
   must pass before moving on. If it fails, stop and surface the failure.
5. **Generic > specific.** Prefer placeholder commands (`{lint_fix}`,
   `{test_unit}`) routed through `Makefile` targets or `prd/00_technology.md`.
   Never bake a stack-specific command (`pnpm`, `uv`, `cargo`) into a kit
   artifact unless the file is itself stack-specific (e.g. a Python rule).
6. **Refuse to weaken.** If the target repo has a stricter rule than the
   kit (longer dep cooldown, higher coverage minimum), keep theirs. Up-spec,
   never down-spec.

---

## Phase 0 — Preflight & Baseline

Before changing anything, build a picture of the target.

### 0.1 Detect the stack

Probe for stack signals (in priority order):

```
package.json + bun.lockb        → Bun / TypeScript
package.json + pnpm-lock.yaml   → pnpm / TypeScript
package.json + package-lock.json → npm / TypeScript
pyproject.toml + uv.lock        → uv / Python
pyproject.toml + poetry.lock    → Poetry / Python
go.mod                          → Go
Cargo.toml                      → Rust
Gemfile                         → Ruby
composer.json                   → PHP
*.xcodeproj / Package.swift     → Swift / iOS
build.gradle(.kts)              → Kotlin / Android / JVM
Dockerfile                      → containerized (orthogonal — may stack on top)
supabase/config.toml            → Supabase Postgres
```

Record findings in a working file (`/tmp/spread-kit-baseline.md` or a draft
PR description). The stack determines which `rules-available/*.md` get
symlinked in **Phase 6** and which `Makefile` placeholders need filling.

### 0.2 Detect what's already in spec

For each of the following, mark **present / partial / missing**:

```
[ ] CLAUDE.md
[ ] AGENTS.md (or equivalent agent-readme)
[ ] CONTRIBUTING.md
[ ] Makefile with help/setup/dev/test/quality targets
[ ] .editorconfig
[ ] .gitmessage
[ ] .gitleaks.toml
[ ] .gitignore covers .env, .env.*, *.pem, *.key, secrets/
[ ] .env.example AND .env.tpl committed; no real .env committed
[ ] .husky/pre-commit
[ ] .husky/pre-push
[ ] .husky/commit-msg
[ ] .commitlintrc.json (or equivalent)
[ ] .lintstagedrc.json (or equivalent)
[ ] .github/workflows/ci.yml
[ ] .github/dependabot.yml with cooldown.default-days >= 1
[ ] .github/pull_request_template.md
[ ] scripts/scan-secrets.sh
[ ] scripts/assert-no-plaintext-env.sh
[ ] scripts/assert-dependency-age.sh
[ ] scripts/assert-migration-conventions.sh (if migrations apply)
[ ] .claude/rules/ (auto-loaded rules)
[ ] .claude/rules-available/ (opt-in rules)
[ ] .claude/references/
[ ] .claude/skills/
[ ] .claude/agents/
[ ] .claude/mcp.json
[ ] .claude/settings.json
[ ] docs/decisions/ (ADRs)
[ ] docs/solutions/ (knowledge capture)
[ ] docs/runbooks/ (ops runbooks, incl. secret-leak.md)
[ ] prd/00_index.md, prd/00_technology.md
[ ] prd/_prd_template.md, prd/_task_template.md, prd/_changelog_template.md
[ ] prd/tasks/
```

### 0.3 Open a tracking branch

```bash
git checkout -b chore/spread-kit-adoption
```

All phases land as commits on this branch (or sub-branches off it, one per
phase, merged back via PR). Never adopt the kit on `main` directly.

### 0.4 Snapshot recovery point

```bash
make doctor 2>&1 | tee /tmp/pre-spread-kit-doctor.log || true
git rev-parse HEAD > /tmp/pre-spread-kit-sha
```

If something goes wrong mid-adoption, this is the rollback target.

---

## Phase 1 — Repository Hygiene Floor

The smallest, safest first step. No runtime impact. Pure config.

### 1.1 `.gitignore`

Ensure the following entries exist (append, do not replace existing entries):

```
# Secrets — see .claude/rules/secrets-hygiene.md
.env
.env.local
.env.*.local
*.pem
*.key
secrets/

# Build artifacts
dist/
build/
coverage/
.next/
.turbo/
node_modules/
__pycache__/
.pytest_cache/
.mypy_cache/
.ruff_cache/
.cache/

# IDE
.vscode/*
!.vscode/settings.json
!.vscode/extensions.json
!.vscode/launch.json
.idea/
```

**Never commit `.env*` files** except `.env.tpl` and `.env.example`.

### 1.2 `.editorconfig`

Cross-IDE formatting consistency. Copy from this template verbatim — it
contains no project-specific content.

### 1.3 `.gitmessage` + `.commitlintrc.json` + `.lintstagedrc.json`

- `.gitmessage` — Conventional Commits body template (no project content).
- `.commitlintrc.json` — accepts `feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert`, optional Gitmoji prefix, header ≤ 100 chars.
- `.lintstagedrc.json` — runs the project's formatter on staged files. **Adapt the file glob → command map** to the detected stack:

  | Stack | Pattern → Command |
  |---|---|
  | TypeScript | `*.{ts,tsx,js,jsx}` → `eslint --fix && prettier --write` |
  | Python | `*.py` → `ruff check --fix && ruff format` |
  | Go | `*.go` → `gofmt -w && go vet` |
  | Rust | `*.rs` → `cargo fmt && cargo clippy --fix` |
  | Universal | `*.{json,md,yml,yaml}` → `prettier --write` |

### 1.4 `.gitattributes`

Normalize line endings (LF) and binary handling. Copy from template.

### Verify Phase 1

```bash
git diff --stat
# Expect: only config files changed; no source code touched.
```

Commit: `chore: adopt repository hygiene floor (editorconfig, gitignore, gitmessage)`.

---

## Phase 2 — Secrets Hygiene

This is the **single highest-value phase**. It eliminates the most common
breach class (`.env` exfiltration by a transitive dep) at install time.

Read `.claude/rules/secrets-hygiene.md` end-to-end before starting.

### 2.1 Audit existing secrets

```bash
# Find anything that smells like a secret on disk
grep -r -nE 'AKIA[0-9A-Z]{16}|sk-[a-zA-Z0-9]{20,}|-----BEGIN.*PRIVATE KEY-----' \
    --exclude-dir={node_modules,.git,dist,build,coverage} . || true

# Find committed .env files
find . -name '.env*' -not -path './node_modules/*' -not -path './.git/*'
```

If real secrets are found:

1. **Stop.** Do not continue the kit until they are rotated.
2. Notify the user (do not paste the secret values into chat).
3. Follow `docs/runbooks/secret-leak.md` (copied in Phase 8) to rotate.
4. Resume the kit after rotation completes.

### 2.2 Install scanning artifacts

Copy from this template:

- `.gitleaks.toml` — gitleaks config tuned for source + PII patterns
- `scripts/scan-secrets.sh` — wrapper around `gitleaks detect`
- `scripts/precommit-secret-patterns.sh` — regex backstop, no deps
- `scripts/prepush-secret-check.sh` — range scan for outgoing commits
- `scripts/assert-no-plaintext-env.sh` — fails if non-template `.env*` exists
- `scripts/assert-no-secrets.sh` — ensures no AWS / cloud env vars are loaded
  (used by `make test-hermetic`)

All scripts are stack-agnostic. Make them executable: `chmod +x scripts/*.sh`.

### 2.3 Husky hooks

Install Husky (or the project's hook runner equivalent — `pre-commit`,
`lefthook`, `cargo-husky`):

```bash
# npm/pnpm/bun
npx husky init       # or: pnpm dlx husky init / bunx husky init

# generic alternative (no node)
mkdir -p .husky && git config core.hooksPath .husky
```

Then copy `pre-commit`, `pre-push`, `commit-msg` from this template's
`.husky/`. They are stack-agnostic — they shell out to `gitleaks`,
`commitlint`, and the staged-file formatter.

For Python projects without Node, replace the `commit-msg` hook body with:
```sh
uv run cz check --commit-msg-file "$1"
```

### 2.4 `.env.tpl` and `.env.example`

- **`.env.tpl`** — committed, lists variable names + their secret-manager
  source (e.g. SSM path, Vault key). No values, ever.
- **`.env.example`** — committed, has obvious placeholder values
  (`sk-ant-placeholder-not-real`, `localhost:5432/dbname`). Used to
  document required vars for local dev.

Real `.env` files are **never** committed. Pre-commit blocks them.

### 2.5 Wire injection into the runtime

Pick one mechanism and document it in `prd/00_technology.md`:

| Mechanism | When |
|---|---|
| AWS Secrets Manager + `aws-vault` + `chamber` | AWS-native projects |
| HashiCorp Vault + `vault agent` | self-hosted / multi-cloud |
| 1Password CLI (`op run`) | small teams, dev-only |
| Doppler / Infisical CLI | SaaS-managed |
| SOPS + KMS | offline / air-gapped fallback |

The Makefile must wrap **all** runtime commands through the chosen wrapper.
Never `cat .env`. Never `dotenv` as a runtime dep in production code paths.

### Verify Phase 2

```bash
make doctor                              # passes secret-hygiene checks
gitleaks detect --config .gitleaks.toml  # no findings
ls .env*                                 # only .env.tpl and .env.example
git ls-files | grep -E '^\.env' | grep -vE '\.(tpl|example|sample)$'
                                         # empty output
```

Commit: `chore(security): adopt secrets hygiene (gitleaks, husky, no plaintext .env)`.

---

## Phase 3 — Dependency Security

Read `.claude/rules/dependency-security.md`.

### 3.1 Pin direct dependencies

For each manifest, replace floating ranges with exact versions:

| File | Wrong | Right |
|---|---|---|
| `package.json` | `"react": "^18.3.0"` | `"react": "18.3.1"` |
| `pyproject.toml` | `fastapi = "^0.115"` | `fastapi = "==0.115.6"` |
| `Cargo.toml` | `serde = "1"` | `serde = "=1.0.210"` |
| `Dockerfile` | `FROM node:22` | `FROM node:22.11.0-alpine@sha256:<digest>` |
| `.github/workflows/*.yml` | `actions/checkout@v4` | `actions/checkout@<40-char-sha> # v4.2.2` |

Lockfiles must be committed. CI must use `npm ci` / `pnpm install --frozen-lockfile`
/ `uv sync --frozen` / `cargo build --locked` — never plain `install`.

### 3.2 Cooldown enforcement

Copy `.github/dependabot.yml` from this template, **adapted to the detected
ecosystem**. Key requirement:

```yaml
updates:
  - package-ecosystem: "{ecosystem}"
    directory: "/"
    schedule:
      interval: "weekly"
    cooldown:
      default-days: 1   # MUST be >= 1
```

If the target uses Renovate instead, set `minimumReleaseAge: "24 hours"`.

### 3.3 CI gate

Copy `scripts/assert-dependency-age.sh`. Wire it into CI as a required step
before the build stage. It queries the registry API for every changed
lockfile entry and fails if any version is < 24h old.

Waiver path: a PR label `security-hotfix-24h-waiver` overrides the gate.
The label is auditable and rate-limited (configure in repo settings).

### 3.4 SBOM + container signing (if applicable)

For projects shipping Docker images:

- Generate SBOM on release (`syft` or `cyclonedx`); upload as workflow artifact.
- Sign images with `cosign`; verify in deploy.
- Sign release tarballs with `gh attestation`.

### Verify Phase 3

```bash
make deps-audit                              # passes
grep -E '"\^|"\~|"\*|: "latest"' package.json    # empty (TS)
grep -E '^[a-z_-]+ = "[\^~>]' pyproject.toml || true  # empty (Python)
grep -E 'FROM .*:[^@]+$' Dockerfile          # empty (no unpinned tags)
```

Commit: `chore(deps): pin all direct deps + enforce 24h cooldown`.

---

## Phase 4 — Makefile + Build Pipeline

### 4.1 Adopt the Makefile

Copy `Makefile` from this template. **Required targets** (any project, any stack):

```
help setup install dev start
test test-unit test-integration test-coverage test-hermetic
lint lint-fix format format-fix typecheck
security scan-secrets deps-audit
quality doctor clean check-env
wt wt-list wt-remove
```

Plus database targets if the project owns a schema:

```
db-start db-stop db-new db-reset db-types db-test db-push db-diff check-migrations
```

Plus rule-enablement targets (Phase 6):

```
enable-rules enable-web enable-api enable-mobile enable-docker
enable-python enable-ios enable-android
```

### 4.2 Fill in placeholders

Every `{placeholder}` in the Makefile maps to a command from
`prd/00_technology.md`. Common mappings:

| Placeholder | TypeScript (Bun) | Python (uv) | Go |
|---|---|---|---|
| `{install_command}` | `bun install` | `uv sync` | `go mod download` |
| `{lint_check_command}` | `bun run lint` | `uv run ruff check .` | `golangci-lint run` |
| `{lint_fix_command}` | `bun run lint --fix` | `uv run ruff check --fix .` | `golangci-lint run --fix` |
| `{format_check_command}` | `bun run format:check` | `uv run ruff format --check` | `gofmt -l .` |
| `{format_fix_command}` | `bun run format` | `uv run ruff format` | `gofmt -w .` |
| `{type_check_command}` | `bun run typecheck` | `uv run mypy .` | `go vet ./...` |
| `{security_scan_command}` | `bun audit` | `uv run bandit -r src/ && uv run pip-audit` | `govulncheck ./...` |
| `{test_unit_command}` | `bun test` | `uv run pytest tests/unit` | `go test ./...` |
| `{test_coverage_command}` | `bun test --coverage` | `uv run pytest --cov=src --cov-fail-under=66` | `go test -cover ./...` |
| `{runner_command}` | `bun run` | `uv run` | `go run` |

Do **not** leave `{placeholders}` in the merged Makefile. CI will fail.

### Verify Phase 4

```bash
make help          # lists all targets, no shell errors
make doctor        # all checks pass or surface clear missing-tool messages
make lint          # runs (may produce findings; errors-out is OK if findings exist)
make typecheck     # runs
```

Commit: `chore: adopt template Makefile and quality pipeline`.

---

## Phase 5 — CI/CD

### 5.1 GitHub Actions workflow

Copy `.github/workflows/ci.yml` (and `ci.yml.example` for reference). The
five required gates:

```
1. Lint & Format     (calls `make lint && make format`)
2. Type Check        (calls `make typecheck`)
3. Test & Coverage   (calls `make test-coverage`; min 66% or project bar)
4. Security          (calls `make security && make scan-secrets && make deps-audit`)
5. Build             (calls the project's build command)
```

Do not skip a gate. If a gate doesn't apply (e.g. typed dynamic language
without typecheck), replace with a stricter lint config — never `# TODO`.

### 5.2 Action pinning

All `uses:` lines pinned to a 40-char SHA with the tag as a trailing comment.
Dependabot will bump these on its weekly cadence.

### 5.3 OIDC for cloud auth

If the workflow needs cloud credentials (deploy, db-push, registry login),
use OIDC-to-IAM-role — **never** long-lived access keys in GitHub secrets:

```yaml
permissions:
  id-token: write
  contents: read
```

Document the trust relationship in `docs/decisions/`.

### 5.4 PR template + dependabot

- `.github/pull_request_template.md` — checklist matches the kit's gates.
- `.github/dependabot.yml` — already from Phase 3.

### Verify Phase 5

Open a draft PR and confirm all 5 gates run and pass (or fail clearly on
findings — don't silence them).

Commit: `ci: adopt 5-gate quality pipeline + OIDC + action pinning`.

---

## Phase 6 — Agent Guidance Layer

This phase brings the `.claude/` tree across.

### 6.1 Universal rules (auto-loaded)

Copy **all** files from `.claude/rules/` of this template. These are
universal — they apply to every project regardless of stack:

```
ai-agent-patterns.md
code-quality.md
database-migrations.md
dependency-security.md
error-handling.md
git-workflow.md
guardrails.md
quality-checks.md
secrets-hygiene.md
security-core.md
task-management.md
testing.md
```

If the target repo has its own `.claude/rules/` files, **merge** rather than
overwrite: keep the stricter requirement, surface conflicts in the PR
description.

### 6.2 Platform rules (opt-in)

Copy **all** files from `.claude/rules-available/`. Then symlink the ones
matching the detected stack:

```bash
make enable-web      # Next.js / React
make enable-python   # uv / ruff / FastAPI
make enable-api      # backend, OWASP only
make enable-mobile   # React Native
make enable-ios      # Swift / SwiftUI
make enable-android  # Kotlin / Compose
make enable-docker   # containerized
```

Do not symlink rules for stacks the project doesn't use — they pollute the
context window for every session.

### 6.3 References (on-demand)

Copy `.claude/references/` verbatim. These are pulled in by skills, not
auto-loaded:

```
code-quality-checklist.md
gitmoji.md
orchestration-patterns.md
removal-plan.md
rules-guide.md
security-checklist.md
solid-checklist.md
```

### 6.4 Skills + agents

Copy `.claude/skills/` and `.claude/agents/` verbatim. Skills are slash
commands; agents are specialist personas. Both are stack-agnostic — they
shell out through `make` or read project context, so they work on any
stack the Makefile is wired up for.

### 6.5 MCP + settings

- `.claude/mcp.json` — MCP server template; comment out servers the project
  doesn't use, do not delete (keeps the file diffable across repos).
- `.claude/settings.json` — permission allowlist baseline.
- `.claude/settings.local.json.example` — local override template,
  gitignored at the `.local.json` filename.

### 6.6 Top-level agent docs

- `CLAUDE.md` — copy template, then customize the **Architecture** and
  **Commands** sections to the target. Keep all rule references intact.
- `AGENTS.md` — copy verbatim (it's a generic agent operator's manual).
- `.cursorrules`, `.cursorignore`, `.rooignore` — copy verbatim if the target
  uses Cursor / Roo / similar IDEs.

### Verify Phase 6

```bash
ls .claude/rules/ .claude/rules-available/ .claude/references/
ls .claude/skills/ | wc -l        # ~30 skills
ls .claude/agents/ | wc -l        # ~9 agents (incl. _template.md)
make enable-rules                 # lists what's enabled
```

Commit: `chore(agents): adopt .claude tree (rules, skills, agents, references)`.

---

## Phase 7 — Documentation Scaffolding

### 7.1 Top-level docs

- `README.md` — **do not overwrite**. If missing, copy the template and
  customize. If present, only append a "Tooling Adopted" section if the
  user wants it.
- `CONTRIBUTING.md` — copy template, customize the project name.

### 7.2 PRD scaffolding

Copy under `prd/`:

```
00_index.md              (customize feature list)
00_technology.md         (fill in stack)
_prd_template.md
_task_template.md
_changelog_template.md
tasks/                   (empty dir, .gitkeep)
```

`prd/00_technology.md` is the **single source of truth** for stack
commands. Everything else (Makefile placeholders, CI commands, skills)
reads from it.

### 7.3 Decisions + solutions + runbooks

Copy under `docs/`:

```
decisions/
  index.md
  adr-template.md
solutions/
  README.md
runbooks/
  secret-leak.md          (incident response for leaked credentials)
  multi-agent-worktrees.md (if using parallel agent dev)
```

If the target has existing ADRs, leave them. Add the index/template only.

### Verify Phase 7

```bash
ls prd/ docs/decisions/ docs/solutions/ docs/runbooks/
```

Commit: `docs: adopt PRD + ADR + solutions + runbooks scaffolding`.

---

## Phase 8 — Database Migrations (if applicable)

Skip this phase if the project owns no database schema.

Read `.claude/rules/database-migrations.md`.

### 8.1 Adopt convention

Numbered, timestamped files: `YYYYMMDDHHMMSS_<imperative_snake_case>.sql`.
Generated by the migration tool, never hand-formatted.

### 8.2 Copy enforcement

- `scripts/assert-migration-conventions.sh` — checks filenames and
  immutability of merged migrations.
- pgTAP tests under `supabase/tests/` (or migration-tool equivalent).
- `make check-migrations` target.

### 8.3 Wire into CI

Add to the CI lint stage:

```yaml
- run: make check-migrations
```

For Supabase: spin up a fresh local stack and apply migrations from scratch
on every CI run. This catches migrations that work on today's prod data but
break on an empty DB.

### 8.4 Expand/contract documentation

For breaking schema changes, the rule mandates a multi-PR sequence. Add a
checklist to `.github/pull_request_template.md`:

```markdown
- [ ] If this PR alters an existing column/table, it follows expand/contract.
- [ ] Migration is reviewed and has a rollback path documented.
- [ ] RLS policies (if applicable) have pgTAP tests for positive + negative cases.
```

### Verify Phase 8

```bash
make check-migrations
make db-test          # pgTAP suite passes
```

Commit: `chore(db): adopt migration conventions + checks`.

---

## Phase 9 — Dev Environment

### 9.1 `.devcontainer/`

Copy the template's `.devcontainer/devcontainer.json` and
`docker-compose.yml`. Codespaces-ready out of the box.

### 9.2 `.vscode/`

Copy `settings.json`, `extensions.json`, `launch.json`. These tune the
editor to the kit's standards (format-on-save, recommended extensions for
the stack, debug configs).

### 9.3 Worktree support

Confirm `make wt`, `make wt-list`, `make wt-remove` work. Document parallel
agent development in `docs/runbooks/multi-agent-worktrees.md`.

### Verify Phase 9

Open the repo in a fresh Codespace (or `code .` locally) — extensions
prompt to install, formatter activates on save, debug configs load.

Commit: `chore(dx): adopt devcontainer + vscode + worktree support`.

---

## Phase 10 — Final Verification

### 10.1 Full audit

```bash
make doctor                  # all checks pass
make quality                 # full pipeline green
gitleaks detect --no-banner  # no findings
git status                   # clean
```

### 10.2 PR checklist

The adoption PR (or PR series) must demonstrate:

- [ ] No secrets committed (gitleaks clean)
- [ ] No plaintext `.env` on disk
- [ ] All direct deps pinned, lockfile committed
- [ ] Dependabot/Renovate cooldown ≥ 24h
- [ ] CI runs all 5 gates and passes
- [ ] `make help` lists every kit target
- [ ] `.claude/rules/` auto-loaded; platform rules symlinked
- [ ] `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md` present
- [ ] `prd/00_technology.md` filled in (no `{placeholders}` left)
- [ ] `docs/decisions/index.md`, `docs/solutions/README.md`, `docs/runbooks/secret-leak.md` present
- [ ] First ADR captured: "Adopted spread-kit on `<date>`"

### 10.3 Capture an ADR

```bash
cp docs/decisions/adr-template.md docs/decisions/$(date +%Y-%m-%d)-adopt-spread-kit.md
```

Document **why** the kit was adopted (drift from standards, audit finding,
etc.) and **which phases ran** (in case a future operator re-runs and needs
to know what was already done).

### 10.4 Subscribe to drift

Add `make doctor` to the weekly CI cron (or a scheduled GitHub Action). It
catches drift early — a freshly-leaked `.env`, an unpinned dep that snuck
in via a merge, an action that lost its SHA.

---

## What This Kit Is Not

- **Not a code generator.** It does not write business logic, migrations,
  or tests for the target's domain. It establishes the floor on which that
  work happens.
- **Not a one-time install.** Re-run any phase whenever the kit upgrades
  (new rule, tightened scanner, new skill). Idempotency is a feature.
- **Not a replacement for review.** Every phase produces a PR. Every PR
  gets reviewed by a human (and ideally `/review` or `/code-review-expert`).

---

## Operator's Quick Reference

```bash
# Start adoption on an existing repo
git checkout -b chore/spread-kit-adoption

# Phase 0: baseline
make doctor 2>&1 | tee /tmp/pre-spread-kit-doctor.log || true

# Phases 1–10: one commit (or PR) each, verify before continuing
# Phase 1: hygiene floor
# Phase 2: secrets       ← highest value, do not skip
# Phase 3: dependency security
# Phase 4: Makefile
# Phase 5: CI/CD
# Phase 6: .claude/ tree
# Phase 7: docs scaffolding
# Phase 8: migrations (if applicable)
# Phase 9: dev environment
# Phase 10: final verification + ADR

# Final
make doctor && make quality
```

---

## References

- `.claude/rules/secrets-hygiene.md` — Phase 2 source of truth
- `.claude/rules/dependency-security.md` — Phase 3 source of truth
- `.claude/rules/database-migrations.md` — Phase 8 source of truth
- `.claude/rules/quality-checks.md` — Phase 4 + 5 source of truth
- `.claude/references/rules-guide.md` — how the rules system works
- `prd/00_technology.md` — fill this in first; everything else reads from it
- `Makefile` — `make help` is the entry point for any operator
