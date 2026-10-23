---
name: goal
description: "Offload work at a higher level of abstraction. Hand it an outcome + acceptance criteria; the main session acts as a conductor that decomposes the goal, delegates to specialist subagents (planner/codebase-researcher/judge), and iterates against a feedback gradient (judge findings + tests) until the criteria are met. Reflective delegation loop, prompt-only. Use for multi-step goals with checkable criteria, not trivial one-file fixes."
---

# /goal

Run a **goal-driven orchestration loop**: you state an outcome, the conductor (this
main session) reaches it by delegating and iterating against feedback, instead of
you supervising each step. This is a GEPA-style reflective loop: candidate, evaluate,
reflect on the accumulated feedback, mutate, keep the best.

## Usage

```
/goal <outcome statement>
/goal <outcome> --criteria "<c1>; <c2>; ..." --max-iters 3
```

| Flag | Default | Meaning |
|------|---------|---------|
| `--criteria "..."` | inferred | Explicit acceptance criteria (the metric). Inferred from the goal + codebase if omitted. |
| `--max-iters N` | `3` | No-improvement rounds before stopping and surfacing to the user. |
| `--no-judge` | off | Cheap mode: tests/lint as the only gradient, skip the `judge` round. For low-risk goals. |
| `--plan` | auto | Force a `planner` pass. Auto-on when the goal touches >2 modules or a schema. |

## Critical design note

You are the **conductor**, running in the main session. Subagents you spawn
(`planner`, `codebase-researcher`, `judge`, `Explore`) cannot spawn their own subagents, so
delegation must originate here. Do not hand the whole loop to one `general-purpose`
agent; it cannot close the loop the way you can.

## The loop

### 0. Frame the goal contract

State it back before doing anything (infer gaps, do not interrogate):

```
Goal:        <one sentence>
Criteria:    <checkable bullets, the metric the loop optimizes>
Constraints: <perf budget / no behavior change / files to avoid>
Out of scope:<explicit exclusions>
```

If a criterion is too vague for a test or `judge` to check, sharpen it now. Create
the ledger for this goal (one file per goal run, so parallel runs never collide):

```bash
SLUG=$(echo "<short-goal-slug>" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
RUN_ID=$(printf '%s' "${CLAUDE_AGENT_ID:-$(date +%H%M%S)-$$}" | tr -cd '[:alnum:]_-')
LEDGER=".claude/orchestration/ledger/$(date +%F)-${SLUG}-${RUN_ID}.md"
mkdir -p .claude/orchestration/ledger
[ -f "$LEDGER" ] || printf '# Goal ledger: %s\n\n**Goal:** <goal>\n**Criteria:** <criteria>\n' "$SLUG" > "$LEDGER"
```

Ledger files are local working state; `.claude/orchestration/ledger/` is gitignored
(`/reflect-agents` reads them locally).

Each round appends:

```
## Round N
Candidate: <what changed, files>
Metric:    <criteria met / not met, test + lint results>
Findings:  <judge P1/P2/P3 verbatim, with file:line>
Next:      <targeted fix chosen>
```

### 1. Decompose

- Touches >2 modules, a schema, or has non-obvious sequencing (or `--plan`)? Delegate
  to the **`planner`** agent and act on its plan.
- Otherwise draft the approach inline. Do not pay for planning on a one-liner.

### 2. Execute

- Pull context with **`codebase-researcher`** or **`Explore`**; never inline-read many files
  into your own context.
- Make the change via direct edits or a specialist agent. Use the cheapest model that
  fits the task; never route workers up to the most expensive tier.
- After each edit, run that file's targeted test (`.claude/rules/testing.md`).

### 3. Evaluate: the gradient (do not skip)

Run the project's targeted tests for what changed, then lint and typecheck for
touched areas (`make test`, `make lint`, `make typecheck`, or the narrower
equivalents), plus any smoke/health command the project defines.

Then, unless `--no-judge`, invoke the **`judge`** agent on the diff. Its P1/P2/P3
findings with `file:line` are the optimization signal. Append the round to the ledger.

### 4. Reflect

Read the findings and diagnose **root cause**, reflecting over the **accumulated**
ledger so a round-3 fix does not reopen a round-1 defect. Address the highest
severity finding first.

### 5. Accept or mutate

- **Accept** when every criterion holds and there is no open P1/P2. Promote a
  candidate only if it **strictly improves** the metric versus the prior best; else
  keep the prior best.
- **Mutate** otherwise: a targeted fix (not a blind retry), then back to step 2. If
  two candidates genuinely trade off, keep both and surface the choice.

### 6. Stop, never silently

- **Criteria met**: report the diff and the satisfied criteria. Offer `/reflect-agents`
  to bank the lessons. Do not auto-commit unless asked.
- **`--max-iters` reached with no improvement**: STOP. Report the candidate(s) on the
  frontier, the specific blocker, and what you would try next. No fake success
  (`.claude/rules/error-handling.md`).

## What this is not for

Trivial fixes, single-file edits, or "it obviously works" goals: the planner and
judge overhead per round is pure waste. Do those directly.

## Example

```
/goal "bring src/router.ts to repo standard" \
  --criteria "tests pass; lint clean; no new P1/P2 from judge; no behavior change"
```

Planner sketches the refactor, edits land with per-edit tests, tests and lint run,
judge finds 2 P2s (untyped catch, missing error log), a targeted fix follows, judge
is clean, criteria met, lessons stay in the ledger.
