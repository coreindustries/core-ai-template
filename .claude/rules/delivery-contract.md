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
