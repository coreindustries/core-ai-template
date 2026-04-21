# Runbook: Dev → Prod Pipeline

**Trigger:** You have a change ready to ship — feature, fix, refactor, or config.
**Time target:** Total elapsed ≤ 45 minutes for a single-service change.

The four stages below are ordered by **cost of failure**. A failing unit test is cheap to diagnose; a failing production deploy is expensive to roll back. Skipping earlier stages to save time pushes failure onto more expensive stages — never a win.

Replace `{placeholder}` commands with the entries from `prd/00_technology.md` as you adopt this template.

---

## Stage 1 — Local fast gate  (< 2 min)

Run before every commit. No containers, no external services.

```bash
make lint             # {lint_check}
make typecheck        # {type_check}
make test-unit        # {test_unit}
make scan-secrets     # gitleaks on staged files
```

**Fails on:** syntax/type errors, failing unit tests, leaked secrets in staged files.
**Why it's first:** catches 80% of mistakes in 2 minutes. Everything downstream is slower.

---

## Stage 2 — Integration gate  (< 10 min)

Run before pushing the branch. Exercises database + external-service wiring.

```bash
make db-start              # supabase start (local)
make db-reset              # apply migrations from scratch
make db-test               # pgTAP + RLS policy tests
make test-integration      # {test_integration}
```

**Fails on:** broken migration, missing RLS policy, failing integration test, schema drift from `supabase db diff`.
**Why it's second:** migrations are high-blast-radius — catching a bad one here is the difference between "fix before commit" and "roll forward on a prod incident." See `.claude/rules/database-migrations.md`.

---

## Stage 3 — Quality gate  (< 15 min)

Run before opening a PR (or let CI run it on push). Full pipeline.

```bash
make quality               # lint + typecheck + security + secrets + tests + coverage
make deps-audit            # pinned + 24h cooldown check
make check-migrations      # filename convention + RLS enforcement
```

**Fails on:** coverage regression, unpinned dep, sub-24h-old dep in lockfile, migration missing RLS, any security finding.
**Why it's third:** expensive to run locally but free to run in CI. The goal of running it locally before pushing is avoiding the 5-minute CI feedback loop for trivial fixes. See `.claude/rules/dependency-security.md` and `.claude/rules/secrets-hygiene.md`.

---

## Stage 4 — Deploy

After PR approval + CI green + merge to `main`.

```bash
# 1. Apply migrations to staging first (never simultaneously with app deploy)
chamber exec <service-name> -- supabase db push --db-url "$STAGING_DB_URL"

# 2. Build + push artifact (ECR / registry)
make build
make push SHA=$(git rev-parse --short HEAD)

# 3. Deploy the app
make deploy ENV=staging SHA=<sha>

# 4. Poll until live + SHA verified
make deploy-status ENV=staging
```

**Order matters:** migration before app deploy, always. Never reverse. Never parallel. If the migration fails, stop — a half-migrated database with the new app code is the worst outcome.

For production:

```bash
# Same sequence, with explicit profile — no cross-account mistakes
AWS_PROFILE=core-prod chamber exec <service-name> -- supabase db push --db-url "$PROD_DB_URL"
AWS_PROFILE=core-prod make deploy ENV=prod SHA=<sha>
AWS_PROFILE=core-prod make deploy-status ENV=prod
```

**Fails on:** migration error (stop here; do not deploy app), build failure, deploy timeout, post-deploy healthcheck failure.

---

## What NOT to do

- **Don't** run stages out of order. Each stage catches a class of failure the later ones can't (or can only catch more expensively).
- **Don't** skip Stage 1 because "it's just a small change." Stage 1 is 2 minutes; rerunning CI after a typo is 5+.
- **Don't** run `supabase db push` against any URL containing `prod` without an explicit profile and a colleague on screen-share if it's your first time.
- **Don't** deploy across environments in parallel to "save time." The rollback path assumes one environment is healthy.
- **Don't** edit a committed migration to "fix" a deploy — write a new migration. See `.claude/rules/database-migrations.md`.

---

## Rollback

If Stage 4 fails after the migration applied but before the app is healthy:

1. **Do not auto-rollback the migration.** Many migrations (add column, add table) are forward-compatible with the old app.
2. **Redeploy the previous app SHA** pointing at the migrated schema. Most migrations tolerate this.
3. **Only roll back the migration** if the new schema is incompatible with the previous app (column drop, type change). In that case, follow the expand/contract runbook (coming soon) to reverse safely.
4. **Always write a post-mortem** within 48 hours, even for a clean rollback — the question isn't "did we recover?" but "what made this necessary?".
