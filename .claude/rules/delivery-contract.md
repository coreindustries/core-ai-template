# Delivery Contract — Evidence for High-Risk Changes

Auto-loaded rule. Surface table, section guidance, rationale and the full ownership list: `.claude/references/delivery-contract-detail.md`.

**A PR that changes a high-risk surface must carry evidence that it works, not a claim that it should.** "Tests pass" is not evidence for a prompt-quality change, a reversible migration, or a cold-runner deploy. Gate: `scripts/pr-delivery-contract-check.sh` via `.github/workflows/delivery-contract.yml` (path patterns in `RISK_PATTERNS`; docs-only and test-only PRs never trigger it).

## Rule 1 — High-risk surfaces

LLM/prompt/agent behavior · infra, CI, or deploy · database schema or writers · scheduled/background jobs · cost-bearing API surface · user-visible UI.

## Rule 2 — Required PR sections

- `## Risk Class` — which surface(s) and the blast radius if wrong (1-2 sentences).
- `## Delivery Contract` — Invariant; runtime boundaries touched; all writers/callers checked; silent fallback paths changed or ruled out; rollback/killswitch.
- `## Real Proof` — output from an actual run (including the failing case before the fix), a real request/response, a real-device screenshot, or a log line showing the new path ran. Not acceptable: "tests pass", "should work", "verified locally" with nothing attached.

For the LLM/prompt surface, "tests pass" never counts: attach a `make eval ARGS="<suite> --require-judge"` summary from before and after, showing `judge: ran N call(s)` with zero errored (not `SKIPPED`, `(E errored)`, or "no judge scorers in this run") on both runs (`.claude/references/llm-evals.md`).

## Rule 3 — Escape hatch

If the contract genuinely does not apply, apply the `skip-delivery-contract` label; never skip by deleting the sections. Don't use it to avoid proof for a risky change.

## Rule 4 — Agent behavior

An agent opening a PR on a Rule 1 surface MUST:
- Fill in all three sections itself, with output it actually observed.
- Never write "tests pass" as Real Proof if it did not run them, or paste output it did not observe.
- Never apply `skip-delivery-contract` on its own initiative.
- State explicitly what it could not verify; a fabricated line is worse than an empty one.
- Flag incidentally changed high-risk surfaces in the PR body rather than quietly widening scope.

## Rule 5 — Cost-bearing and background features are safe by default

Any feature that calls a paid API or runs on a loop, cron or queue ships with all of these, each named in the Delivery Contract:
- **Off by default or hard-capped** (per-period budget) from the first commit.
- **A killswitch the code reads at execution time** (name the flag and the line that reads it).
- **Failure alerts a person**: repeated failure, quota exhaustion, a dead schedule; say where the alert goes.
- **Attribution names the real caller** in cost telemetry, event names and log prefixes.
- **Output reaches the user**: prove it exists in the store and appears where the user looks.

## Ownership, retirement, and delivery cost

Apply to the affected boundary before implementation; record answers in the existing plan and contract fields (no second template, registry, approval loop or CI workflow). A small local edit needs only the decisions it touches. These grant no deployment, production-data, external-message, or destructive-operation authority.

1. **Ship an observable outcome**: name the customer result or the recurring engineering cost removed; don't invent a refactor to force deletions.
2. **One authority per responsibility**: name the state owner and every writer/launcher before and after; two independent schedulers/config writers/publishers/launchers can't coexist indefinitely; prefer supported interfaces; a third mechanism to align two needs a demonstrated unmet requirement.
3. **Retirement is part of replacement**: remove superseded callers, launch paths, flags, compat code, tests and docs; if coexistence is needed, name its owner, removal condition and rollback implications.
4. **Build once, promote the verified artifact**: use the committed lock; never delete a lock to pass a build; verify published digests and release inputs, not just a SHA; rebuild only when inputs changed, the artifact is invalid, or reproducibility is requested; changed artifacts need new proof.
5. **Separate durable state from release assets and caches**: identify what survives replacement and who may migrate/delete it; prove upgrades on representative existing state; never treat customer records or sole-copy memory as cache.
6. **Test the risky seam early**: run the smallest authorized probe against the real SDK/image/caller/storage/UI before broad implementation; a green mock or disabled flag is not delivery proof; name remaining proof.
7. **Fix causes before adding machinery**: no retries, longer timeouts, watchdogs, repair loops, extra reviewers or gates without a causal explanation; a new control needs an uncovered failure, an observed trigger, and a consumer of its result; bounded retries need evidence of a transient condition and safe replay; keep required checks until a reviewed replacement preserves the guarantee.
8. **Measure before adding boundaries**: a rewrite, repo/service split, provider layer or microVM needs a measured bottleneck or isolation requirement, a simpler alternative, and an exit path; token/tool-call/cost claims need actual usage records.
9. **Isolate before coordinating**: independent features get exclusive file ownership and independent test resources (ports, volumes, tags); shared contracts have one integrator; a worktree alone does not isolate Docker or a database.

**Enforcement:** architect proposals and planner steps resolve applicable gaps before implementation; the judge returns `HOLD` for unresolved material violations, with a concrete failure mode and the P1/P2 rubric. New files or higher line count alone are not a finding.

## Enforcement

| Layer | Control |
|---|---|
| CI | `.github/workflows/delivery-contract.yml` fails on a missing/empty required section on a high-risk PR |
| Script | `scripts/pr-delivery-contract-check.sh` (local dry run: `gh pr view --json body -q .body \| MODE=warn scripts/pr-delivery-contract-check.sh`) |
| Label | `skip-delivery-contract` (auditable opt-out) |

See also: `quality-checks.md`, `ai-agent-patterns.md`, `database-migrations.md`.
