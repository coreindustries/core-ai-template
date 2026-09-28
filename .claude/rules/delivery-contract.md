# Delivery Contract — Evidence for High-Risk Changes

Auto-loaded rule. Applies to any PR touching a high-risk surface.

## Core Directive

**A PR that changes a high-risk surface must carry evidence that it actually works — not a claim that it should.**

"Tests pass" is not evidence that a prompt change improved output quality, that a migration is reversible, or that a deploy change works on a cold runner. The three sections below force the author to state what must remain true, how they verified it, and how to undo it.

The gate is `scripts/pr-delivery-contract-check.sh`, run by `.github/workflows/delivery-contract.yml`. Docs-only and test-only PRs never trigger it.

---

## Rule 1 — The six high-risk surfaces

A PR needs a delivery contract when it touches any of these:

| Surface | Why it's high-risk |
|---|---|
| **LLM / prompt / agent behavior** | Failures are silent and probabilistic. Nothing crashes; output just gets worse. |
| **Infra, CI, or deploy** | Blast radius is everyone. A broken gate stops being a gate without announcing it. |
| **Database schema or writers** | Data loss is often irreversible and discovered late. |
| **Scheduled / background jobs** | No user watches them fail. A broken cron is invisible until the backlog is a week deep. |
| **Cost-bearing API surface** | Bugs bill real money, often at a rate proportional to traffic. |
| **User-visible UI** | The failure mode is "looks fine in CI, broken on a real device". |

The path patterns for each live in `RISK_PATTERNS` in the check script. Tune them per project — a template's defaults will not match every layout.

---

## Rule 2 — The three required sections

### `## Risk Class`

Which surface(s) from Rule 1, and the blast radius if this change is wrong. One or two sentences. "Infra — if the pin is wrong, every PR check fails closed and nothing merges."

### `## Delivery Contract`

- **Invariant** — what must remain true after this merges.
- **Runtime boundaries touched** — processes, queues, external calls, schedules.
- **All writers/callers checked** — how you know nothing else still depends on the old shape.
- **Silent fallback paths changed or ruled out** — where could this fail *without* raising? This is the line that catches the bugs the other five miss.
- **Rollback/killswitch** — how to undo this in production, specifically.

### `## Real Proof`

Evidence from an actual run. Acceptable:

- Command output pasted from a real execution (including the failing case before the fix)
- A real request/response pair
- A screenshot from a real device, not a CI snapshot
- A log line showing the new path was taken

Not acceptable: "tests pass", "should work", "verified locally" with nothing attached, or a description of what you would expect to see.

For the LLM/prompt surface specifically, "tests pass" never counts — unit tests can't catch an output-quality regression. Acceptable proof is a `make eval ARGS="<suite> --require-judge"` summary from before and after the change, showing `judge: ran N call(s)` with zero errored (not `SKIPPED`, not `(E errored)`, and not "no judge scorers in this run") on both runs (see `.claude/references/llm-evals.md`).

---

## Rule 3 — The escape hatch is labeled, not silent

If the contract genuinely does not apply — a typo fix in a workflow comment, say — apply the **`skip-delivery-contract`** label. The label is visible in the PR list and in the audit trail; skipping the gate by deleting the sections is not.

Do not use the label to avoid writing proof for a change that has real risk. If writing the Real Proof section is hard, that is a signal about the change, not about the gate.

---

## Rule 4 — Agent behavior

An AI agent opening a PR must:

- **Fill in all three sections itself** when the PR touches a Rule 1 surface. The agent ran the commands; it has the evidence. Pasting real output costs nothing.
- **Never** write "tests pass" as Real Proof when it did not run the tests, and never paste output it did not actually observe.
- **Never** apply `skip-delivery-contract` on its own initiative — that is the human's call.
- **State explicitly** when it could not verify something, rather than filling the section with plausible-looking text. "Could not verify the rollback path — no staging environment available in this session" is a useful contract line. A fabricated one is worse than an empty one.

If an agent notices a high-risk surface being changed incidentally (a migration pulled in by an unrelated refactor), it should flag that in the PR body rather than quietly widening scope.

---

## Rule 5 — Cost-bearing and background features are safe by default

The cost and background surfaces from Rule 1 fail in a particular way: invisibly, until someone reads the bill or notices output that never arrived. Real cases include a default-on generator that produced about 168 images a day, displayed none of them, and ran until the account was out of credit; and a scheduled job that died on every host behind `catch (e) { process.exit(0) }` with nothing alerting anyone. Any feature that calls a paid API, or runs on a loop, cron or queue, ships with all of the following. Name each one in the Delivery Contract.

- **Off by default or hard-capped.** Default-off, or a per-period budget cap, from the first commit.
- **A killswitch the code reads at execution time.** A flag checked only at deploy time, or one nothing reads, is decoration. Name the flag and the line that reads it.
- **Failure alerts a person.** Repeated failure, quota exhaustion and a dead schedule must reach someone who will act, not only `log.error`. Say where the alert goes.
- **Attribution names the real caller.** Cost telemetry, event names and log prefixes identify the code path that actually spent the money, not the feature it borrowed.
- **Output reaches the user.** For anything that generates something user-visible, prove it exists in the store *and* appears where the user actually looks. Generated but never displayed is a bug, whatever the tests say.

---

## Ownership, retirement, and delivery cost

Apply the following decisions to the affected boundary before implementation.
Record answers in the existing plan and delivery-contract fields; do not add a
second PR template, registry, approval loop, or CI workflow. A small local edit
needs only the decisions it actually touches. These rules do not grant deployment,
production-data, external-message, or destructive-operation authority.

1. **Ship an observable outcome.** Name the customer result, or the specific
   recurring engineering cost this cut removes. Keep independent feature lines
   moving; a platform rebuild is not an implicit prerequisite or feature freeze.
   Do not invent a refactor merely to make every feature delete code.
2. **One authority per responsibility.** Name the authoritative state owner and
   every writer/launcher before and after. Multiple workers may share a service's
   concurrency contract; two independent schedulers, config writers, release
   publishers, or runtime launchers cannot be left to reconcile indefinitely.
   Prefer supported interfaces and existing modules. A third mechanism to keep two
   overlapping mechanisms aligned needs a demonstrated unmet requirement.
3. **Retirement is part of replacement.** Include superseded callers, launch paths,
   flags, compatibility code, tests and documentation in the removal plan. If
   coexistence is necessary, name its owner, observable removal condition and
   rollback implications in the existing issue/PR. Do not claim extraction or
   migration complete while the old authority remains active unintentionally.
4. **Build once, promote the verified artifact.** Use the owning committed lock
   and native workspace layout; do not delete a lock or resolve fresh dependencies
   to make a build pass. Reuse the existing build implementation. Verify published
   image digests and release inputs (including skill/package pins and configuration),
   not just a source SHA or tag. Rebuild only when required inputs changed, the
   artifact is unavailable/invalid, or the user requests a reproducibility check.
   Changed artifacts require new proof before promotion; preserve existing gates.
5. **Separate durable state from release assets and caches.** Identify which data
   survives worker/image replacement and who may migrate or delete it. Prove
   upgrades against representative existing state, not only empty fixtures. For
   dependency/artifact publication, exercise stale-state removal, interrupted
   copy/write, readiness stamped only after success, retry and rollback where
   consequential. Never treat customer records or the sole copy of memory as cache.
6. **Test the risky seam early.** Before broad implementation, run the smallest
   authorized probe that can invalidate the design against the actual SDK, image,
   caller, storage or UI. A green mock, generated artifact, or disabled flag is
   not proof of delivery. Name remaining proof explicitly; follow
   `testing.md` and this contract without duplicating their procedures.
7. **Fix causes before adding machinery.** A repeated failure first requires a
   causal explanation. Do not paper over it with retries, longer timeouts,
   watchdogs, repair loops, another reviewer, or another gate. A new control needs
   an uncovered failure, a reason the current owner cannot handle it, an observed
   trigger and a result consumed by the actual decision maker. Bounded retries
   need evidence of a transient condition and safe replay; repeated failure stops
   blind retry and returns to diagnosis. Keep required checks until a reviewed
   replacement preserves their guarantee.
8. **Measure before adding boundaries.** A Rust rewrite, repository/service split,
   provider layer or microVM harness needs a measured bottleneck or demonstrated
   isolation/release-ownership requirement, a simpler alternative, compatibility
   costs and an incremental exit/retirement path. When evidence is missing, run a
   bounded experiment; do not present a language or hosting change as a speedup.
   Token, tool-call and cost claims require actual usage records; output bytes or
   file/PR counts are not substitutes for those metrics or engineering effort.
9. **Isolate before coordinating.** Independent features get exclusive file
   ownership and independent writable test resources, ports, volumes and image
   tags. Use the active runtime's capacity limits. Shared contracts have one
   integrator; shared artifact publication and production mutations keep their
   existing owner/locks. A Git worktree alone does not isolate Docker or a database.

**Enforcement:** architect proposals and planner steps must resolve applicable
ownership, retirement and proof gaps before implementation; the judge must return
`HOLD` for unresolved material violations, with a concrete failure mode and the
existing P1/P2 severity rubric. New files or a higher line count alone are not a
finding. Fix within authorized scope; do not create a new permission ceremony or
demand unrelated cleanup. No claim of general productivity gain follows merely
from adopting these instructions.

## Enforcement

| Layer | Control | Fails on |
|---|---|---|
| CI | `.github/workflows/delivery-contract.yml` | Missing or empty required section on a high-risk PR |
| Script | `scripts/pr-delivery-contract-check.sh` | Same; runnable locally with `MODE=warn` for a dry run |
| Label | `skip-delivery-contract` | Auditable opt-out |
| Review | PR template prompts | Human backstop |

Run it locally before pushing:

```bash
gh pr view --json body -q .body | MODE=warn scripts/pr-delivery-contract-check.sh
```

## See Also

- `.claude/rules/quality-checks.md` — the pre-merge checklist this complements
- `.claude/rules/ai-agent-patterns.md` — comprehensiveness and behavior-safe defaults
- `.claude/rules/database-migrations.md` — expand/contract, the canonical high-risk change
