# LLM Output Quality Evals

**Scope:** On-demand reference for `scripts/eval/run-eval.mjs` — the golden-fixture
harness that catches LLM output regressions unit tests can't. Loaded by `/tdd`,
`/eval`-shaped work, and any agent touching prompts. See
`.claude/rules/delivery-contract.md` Rule 2 for when this is required as Real Proof.

## Why this exists

A prompt change that makes output worse doesn't throw an exception — unit tests
stay green while quality silently regresses. This harness scores **captured
artifacts** (model outputs saved as fixtures), never app code, which is what
keeps it stack-agnostic: any project — Python, Node, Go — writes its outputs
somewhere and scores them the same way.

Zero npm dependencies. Runs on the runner's default Node (same precedent as
`scripts/sync-agent-models.mjs`).

## Suite layout

```
evals/<suite>/
  scorers.json       # array of scorer definitions
  good-*.json        # fixtures where every scorer must pass
  defect-*.json       # fixtures that name which scorer(s) must fail
  scorers/            # optional: scripts for `command`-type scorers
```

`evals/_example/` ships with the template as the harness's own self-test: 2
good + 2 defect fixtures using only deterministic scorers. If a scorer breaks
in a way that makes it always pass, the defect fixtures go red — that's the
signal the harness itself is trustworthy. Do not delete it; add your own
suites alongside it.

## Fixture schema

```json
{
  "output": "the captured model output, as a string",
  "provenance": "where this sample came from — a real request, a specific run, a date",
  "expect": {
    "shouldFail": ["<scorer-id>", "..."]
  }
}
```

- **`good-*.json`**: `expect.shouldFail` must be `[]`. Every scorer must pass.
- **`defect-*.json`**: `expect.shouldFail` must name at least one scorer id.
  That scorer must fail; every other scorer must still pass.
- **`provenance`** is required and enforced at load time. Write down what real
  interaction (or intentional construction) produced this sample — "captured
  from a manual test of the `/summarize` endpoint on 2026-09-01" or "hand-built
  to exercise the profanity scorer's defect path." A fixture with no
  provenance is a fixture nobody can trust six months from now.

**Capturing a real sample:** run the feature, take the actual model output
(not a hand-edited version of it), paste it into `output` verbatim, and write
what produced it into `provenance`. Resist the urge to "clean up" a captured
output before saving it — a fixture that doesn't match what the model actually
said isn't testing anything.

## Scorer types

All scorers share `{ "id": "...", "type": "..." }` plus type-specific fields.

### `regex`

```json
{ "id": "no-placeholder-text", "type": "regex", "mustNotMatch": "TODO|FIXME", "flags": "i" }
```

`mustMatch` and/or `mustNotMatch` (regex source strings), optional `flags`.

### `length`

```json
{ "id": "min-length", "type": "length", "min": 20, "max": 4000 }
```

Character length of `output`. Either or both of `min`/`max`.

### `command` — the stack-agnostic extension point

```json
{ "id": "valid-yaml", "type": "command", "command": "python3", "args": ["evals/my-suite/scorers/check-yaml.py"] }
```

Any executable, any language. The fixture's `output` is written to the
child's stdin; exit code `0` = pass, anything else = fail. Spawned **without**
a shell — `args` is an array, never a string that gets interpolated — so
there's no command-injection surface (`security-core.md`). Working directory
is pinned to the repo root, so relative script paths resolve the same way
under `make eval` and under `node --test`.

### `judge` — LLM-graded rubric

```json
{ "id": "professional-tone", "type": "judge", "rubric": "The text must be professional and free of profanity or sarcasm." }
```

Calls the Anthropic Messages API via global `fetch` (no SDK dependency). Model
comes from `EVAL_JUDGE_MODEL` — **never hardcoded** (`.claude/rules/ai-agent-patterns.md`);
if it's unset, the judge is unavailable, same as a missing key. Credential
comes from `ANTHROPIC_API_KEY`, injected by the secret wrapper, never a
`.env` file. The system prompt block carries `cache_control: { type: "ephemeral" }`
per the Claude API defaults in `ai-agent-patterns.md`.

The judge is asked for a strict `PASS`/`FAIL` verdict on the first line. An
unparseable response is a **loud scorer error**, not a silent pass
(`error-handling.md`) — this is deliberate: a judge that can't be parsed
correctly is a judge you can't trust, and treating that as a pass would hide
exactly the failure this harness exists to catch.

## Judge skip semantics — read this before adding a judge scorer

The reference implementation this harness learned from had a real bug: a
skipped judge (no API key in CI) counted as an unmet expectation, so key-less
CI runs stayed permanently red — or someone quietly lowered the threshold to
make it go away. This harness does the opposite on purpose:

- **No `ANTHROPIC_API_KEY` or no `EVAL_JUDGE_MODEL`** → every judge row is
  `SKIPPED` and **excluded from the aggregate** — not counted as a pass, not
  counted as a fail. The run prints a loud line:
  `judge: SKIPPED (no ANTHROPIC_API_KEY / EVAL_JUDGE_MODEL) — N expectations unverified`.
- **`--no-judge`** does the same thing intentionally — still printed loudly,
  same format, so a skip is never silent.
- **`--require-judge`** exits `3` if *any* judge expectation was skipped for
  any reason, or the cost cap was hit. Use this in the one place that actually
  needs judge coverage verified (a pre-merge check on a prompt change), not in
  every CI run.
- **Cost cap** (`EVAL_MAX_JUDGE_CALLS`, default `20`): once hit, remaining
  judge rows are `SKIPPED` and the run prints `CAP HIT`. This bounds spend on
  a suite with many fixtures.
- **An error (unparseable verdict, network failure) is NOT a skip.** It's a
  real failed expectation and counts against the aggregate, same as any other
  scorer failure.

CI's unconditional lint-job step runs `--no-judge` — deterministic scorers
only, since a key-less runner can't call the judge anyway. That step can never
be the source of a false "judge covered this" signal, because a skip is never
silently counted as a pass.

## Cost cap and threshold

- `EVAL_MAX_JUDGE_CALLS` (default `20`) — hard cap on judge calls per run.
- `EVAL_THRESHOLD` (default `1.0`) — aggregate score gate. Score is the
  fraction of (fixture × scorer) expectations met, excluding skips.

## Trend

```bash
make eval ARGS="my-suite --record"     # append a summary line to .eval-history/my-suite.jsonl
make eval-trend ARGS="my-suite"        # print the last 10 recorded runs
```

`.eval-history/` is gitignored — this is local/single-machine trend only.
**Cross-machine or cross-CI-run trend needs a store the project chooses**
(a database table, an artifact store, a metrics service) — this harness
doesn't pick one for you. If you need durable cross-run trend, wire
`--record`'s output into whatever the project already uses for CI history.

## Usage

```bash
node scripts/eval/run-eval.mjs                        # run every suite under evals/
node scripts/eval/run-eval.mjs my-suite                # run one suite
node scripts/eval/run-eval.mjs my-suite --dir=/tmp/live-out   # score fixtures from elsewhere (e.g. live-captured outputs)
node scripts/eval/run-eval.mjs --no-judge
node scripts/eval/run-eval.mjs --require-judge
node scripts/eval/run-eval.mjs my-suite --record
node scripts/eval/run-eval.mjs trend my-suite --last=5
```

All commands should be run through the secret wrapper so the judge's API key
never touches disk: `make eval ARGS="my-suite --require-judge"` (the Makefile
target wraps this — see `.claude/rules/secrets-hygiene.md`).

## Adding a new suite

1. `mkdir -p evals/my-suite`
2. Write `scorers.json` — start with deterministic scorers (`regex`/`length`/`command`);
   add `judge` scorers only for checks no deterministic rule can express.
3. Capture at least one real `good-*.json` sample with honest `provenance`.
4. Write at least one `defect-*.json` per scorer you actually expect to catch
   a real failure mode — a scorer with no defect fixture covering it is
   unverified.
5. Run `make eval ARGS=my-suite` locally before committing.
