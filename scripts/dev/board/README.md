# scripts/dev/board — agent-lanes tooling

Deterministic tools for the Release Manager, Feature, Bugfix and PRD-manager agent lanes. GitHub
Issues are the single source of truth; these scripts do the repetitive coordination (claims, state
labels, PR/CI diagnosis, deploys, log triage) so no model call has to rediscover state it could ask
`gh` for.

- The workflow they serve: `.claude/skills/_shared/agent-protocol.md`.
- Every project-specific value: `.claude/agent-lanes.json` (validate with `lanes-config.sh check`).
- Shared shell helpers: `lib.sh` (sourced by every script; it loads `lanes-config.sh`).
- Portable: macOS bash 3.2 + Linux; `gh`, `jq`, `git`, `python3` (log triage only).

| Script | Purpose |
|---|---|
| `board.sh` | Issues and PRs: labels, claims, state, handoffs, queues, PR status, board render, project sync |
| `pr-watch.sh` | Babysit an agent's PRs; one `ACTION` line per PR that needs it |
| `wt-clean.sh` | Remove merged PRs' worktrees, safely |
| `gh-checks.sh` | Read PR check runs even with a fine-grained PAT (sourced) |
| `issue-fetch.sh` / `issue-watch.sh` | Read an issue with its screenshots / watch for new work (via `board.sh show` / `watch`) |
| `ladder.sh` | The environment ladder: health by content, deploy, rollback |
| `release-prs.sh` | PRs in a release range, deploy-bound or not, with each `## Real Proof` |
| `log-triage.py` | Before/after log triage per environment, redacted in code, filed as issues |
| `pr-check.sh` | The PR gates, locally (`make pr-check`) |
| `lanes-config.sh` | Read and validate `.claude/agent-lanes.json` |

## board.sh

```
scripts/dev/board/board.sh <subcommand> [args...]      # board.sh help for the full list
```

| Subcommand | What it does |
|---|---|
| `init-labels [--dry-run]` | Creates the lane taxonomy from the "Agent lanes" section of `.github/labels.yml` (the one source). `agent:<NAME>` labels are created on demand. `make lanes-init` runs this. |
| `list [--lane b\|f\|r\|p] [--state s] [--agent NAME] [--unclaimed] [--stale] [--json]` | Open `lane:*` issues, P0→P3 then oldest first. A `STALE` column shows `stale <N>h` for claims idle past `claims.ttlHours`; `--stale` filters to only those; `--json` carries a `staleHours` field (null when not stale). |
| `next --lane b\|f\|p --agent NAME` | Claims the highest-priority, oldest unclaimed issue. Exit 3 = none; 4/5 = lost a race. Falls back to the lane's stale claims (via `reclaim`), oldest/highest-priority first, excluding any already held by the caller. A refused candidate is skipped in favor of the next one ONLY on exit 3 (not eligible) or 6 (could not verify) — both refuse before any write; every other code, including 7, propagates immediately. |
| `claim <issue> <NAME>` | `agent:<NAME>` + a `claim:` comment, then a race check: an earlier unreleased claim wins and this call backs off (exit 4). Refuses (exit 5) if another agent holds it. Same-second ties (two claims posted in the same wall-clock second, so their timestamps are byte-identical) are broken by comment ORDER, not by comparing that identical timestamp text. A claim ends on either a `release:` comment OR a lost racer's own `claim-lost: NAME to WINNER` — treating only the first as a release let a racer who had already lost block every later claimant forever. If the race outcome can't be verified even after one retry (the comments read-back is invalid, or the claimant's own just-posted comment never shows up), `claim` posts `release: NAME ts unverified` before exiting 4 — dying silently would leave that same kind of never-released ghost claim. |
| `release <issue> <NAME> [--reason ...]` | Drops the claim with a `release:` comment. |
| `reclaim <issue> <NAME>` | Takes over a claim idle past `claims.ttlHours`. Re-checks staleness live; an OPEN, NON-DRAFT PR referencing the issue makes the claim live regardless of age (a green PR awaiting the operator's merge click has no reason to comment); only a DRAFT PR's age counts as ordinary activity. Posts `release: OLD ... reclaimed-by NEW` (naming any open PR OLD still has, so it isn't silently orphaned), removes `agent:OLD`, then runs the normal `claim` path. **Exit codes:** `2` usage error (bad args, already claimed by you); `3` NOT ELIGIBLE, refused before any write (closed, `agent:*` label gone, state changed, `wip-keep`, `claims.ttlHours` is 0, a live PR, or still under the TTL); `4`/`5` a real claim race, same as `claim`; `6` COULD NOT VERIFY, also refused before any write (a gh/jq lookup failed, including the release comment itself); `7` a write happened (the release comment landed) but the claim afterward failed anyway — never retried. |
| `state <issue> <new-state>` | Swaps to exactly one `state:*` label, with a `state: old -> new` comment. |
| `handoff` / `comment <issue> --file <md>` | A resumable `handoff:` comment / a progress note, always from a file. |
| `show <issue>` / `watch --agent NAME [--lane l]` | Issue text with downloaded screenshots / new-work events for Monitor. |
| `checkout <issue> <NAME> [--worktree]` | Claim + `implementing` + show, and optionally a worktree under `worktreeDir` on a fresh branch. |
| `deploy-queue [--json]` | Merged `needs-deploy` PRs (14 days), `NO-PROOF` when the body lacks `## Real Proof`. |
| `render --out <f.html> [--hash-file <p>]` | Self-contained, mobile-friendly light/dark HTML board. `--hash-file` prints `CHANGED`/`UNCHANGED` ignoring the timestamp. |
| `project-sync [...]` | Optional mirror into GitHub Projects (v2). See "Live board". |
| `prd-scan [--json] [--prd f]` | PRD requirement ids (per `prd.frPattern`) with no tracking issue/PR. A candidate list, not a verdict. |
| `file-feature --prd f --fr id --priority Pn --title t --body-file md` | Files a `lane:feature` issue with the canonical token; exit 5 if already tracked. |
| `pr-status <pr> [--json]` | Draft/mergeable/behind, check buckets, first error line per failed check. |
| `pr-update <pr>` | Merge the default branch into the PR (never a rebase). |
| `pr-own <pr> <NAME>` / `my-prs <NAME>` | Mark a PR as an agent's / list an agent's open PRs. |
| `reconcile-age --workflow f.yml [--max-hours 3]` | `OK` / `STALE` / `NONE` for a workflow's last successful scheduled run. |

**PRD tracking token:** `[<prd_id> FR<N>]`, where `<prd_id>` is the PRD's `prd.idField` frontmatter
value (else the filename stem) and `FR-6` normalizes to `FR6`. An issue or PR tracks a requirement
iff its title or body contains the token.

### Live board (GitHub Projects) — optional

`project-sync` mirrors the labels into Projects fields (Lane, State, Priority, Agent, and GitHub's
built-in Status: `backlog`→Todo, `done`/`dropped`→Done, everything else→In Progress). Disable the
project's built-in workflows (Project → Workflows) or they will fight the sync over Status.

Setup, once: a token with Projects read/write + Issues read as the `BOARD_PROJECT_TOKEN` secret;
`GH_TOKEN=<token> board.sh project-sync --create`; the printed number as the `BOARD_PROJECT_NUMBER`
repo variable. `.github/workflows/board-project-sync.yml` then syncs on every lane issue event
(per-issue concurrency, so a label burst cannot cancel other issues' syncs) plus an hourly reconcile,
and reports on every run whether that scheduled reconcile is actually firing. Before relying on it,
`board.sh project-sync --self-check --number <N>` prints the real JSON keys `gh` returns.

**Adding a new lane (e.g. `prd`) to an already-created project:** `gh` CLI cannot add an option to an
existing single-select field — only create the field with its initial option list, or edit an item's
value against options that already exist. When a new lane is added to `field_defs`'s Lane CSV after
the Lane field already exists on the live project, `project-sync` detects the mismatch and only
**WARNs** (`field 'Lane' ... has no option 'prd' — leaving unset`); it never mutates or breaks the
sync for other issues. A human adds the option by hand once: project Settings → Fields → **Lane** →
add option → `prd`. One-time per new lane, not recurring — `project-sync` picks it up automatically
on its next field-list read once it exists.

The project is for people. Agents read their queue from Issues, never from the project.

## PR babysitting

```
scripts/dev/board/pr-watch.sh (--agent NAME | <pr>...) [--interval 120] [--max-wait 3300] [--once]
make -C <pr-worktree> pr-check BODY=<body.md> [BASE=main]
scripts/dev/board/wt-clean.sh (--pr <n>... | --agent NAME | --all-merged) [--dry-run]
```

- **`pr-watch.sh`** is silent while checks are pending; exit 10 prints `ACTION pr=<n> event=<e>`
  (`check-failed`, `check-cancelled`, `conflict`, `behind`, `draft-green`, `ready`, `merged`,
  `closed`), each (head, event) once. `draft-green` is not green: a draft runs a subset of CI.
  `check-cancelled` means a gate was cancelled and never re-ran on this head; names in
  `checks.cancelledOk` are exempt. `--agent` mode costs one `gh pr list` per poll.
- **`pr-check.sh`** runs branch-name, non-empty-diff, delivery-contract, proof-URL and configured
  ratchet gates, and notes unpushed commits.
- **`wt-clean.sh`** removes a worktree only when its PR is MERGED, it is clean, and its HEAD is the
  merged PR head or inside it. Never `--force`, never a locked worktree; everything else is
  `SKIP <reason>`.
- **`gh-checks.sh`**: fine-grained PATs cannot be granted *Checks*. `gh_checks` accepts only
  `pr view|list --json …statusCheckRollup…`, retries once against the keyring login on that exact
  denial (or uses `BOARD_CHECKS_TOKEN`), and fails loudly — never an empty rollup.
- **`ci-triage`** (`.claude/agents/ci-triage.md`) turns a red PR into one line per check.

## Release tooling

```
scripts/dev/board/ladder.sh envs | health (<env>|--all) [--json]
scripts/dev/board/ladder.sh deploy <env> --sha <sha> [--print] | rollback <env> --to <sha> [--print]
scripts/dev/board/release-prs.sh <from-sha> <to-sha> [--json]
scripts/dev/board/log-triage.py capture before|after <env> --release <sha8> [--since-minutes N]
scripts/dev/board/log-triage.py report <sha8> [--all] | file <sha8> [--apply] [--max-new 15]
```

- **`ladder.sh`** runs each environment's configured commands. A deploy is `VERIFIED` only when that
  environment's `health` reports the deployed SHA. `--print` runs nothing — never `make -n` a deploy
  target (make still executes `$(MAKE)` lines); `lanes-config.sh check` rejects that.
- **`log-triage.py`** runs each environment's `logs` command, redacts secrets and personal data in
  code before anything is stored or printed, groups lines into signatures, and gives each a verdict
  (`RELEASE-SUSPECT`, `PRE-EXISTING`, `UNATTRIBUTED`, `BASELINED`). `file` is a dry run unless
  `--apply`. It never baselines anything; that is a reviewed PR to `logTriage.baselineFile`.

## Testing

```
make lanes-test            # scripts/dev/board/tests/run-all.sh
```

Every test runs against fake `gh`/`curl`/`sleep` binaries on `PATH` and disposable git repos — no
network, no token. `.github/workflows/agent-lanes.yml` runs them in CI. The claim-race, ordering and
redaction tests carry mutation checks: break the guard on a throwaway copy and confirm the test fails.

## Stale-claim reclaim

There is no scheduled sweep — staleness is computed at read time by `list --stale`, `render`, and
`next`'s fallback, from `.claude/agent-lanes.json`'s `claims.ttlHours` / `claims.keepLabel`. A
claim's "last activity" is the later of the newest comment on the issue and the newest `updatedAt`
of an open, **DRAFT** PR labeled `agent:<NAME>` whose body references `#<issue>` or an
`/issues/<issue>` URL — never the issue's own `updatedAt`, which bots (labeler, project-sync) bump
without the claimant doing anything.

**An open, NON-DRAFT PR referencing the issue makes the claim LIVE regardless of age.** A green PR
sitting on the operator's merge click has no reason to accumulate comments; reclaiming it out from
under the claimant would duplicate work and let the old PR's `Fixes #n` close the issue out from
under the new claimant. Only a draft PR's own age counts as ordinary activity — a draft nobody is
touching still goes stale. This reads ONLY the PR's `body` text and its own `agent:<NAME>` label —
never its title, its commits, or GitHub's "linked issues" sidebar (`closingIssuesReferences`, a
separate field this tool never queries); a PR linked only that way is invisible to it.

Only `state:implementing` and a claimed `state:backlog` issue can be stale; `built` and later belong
to the Release Manager. `claims.ttlHours: 0` disables the check entirely — as does any malformed
explicit value (`-1`, `1.5`, `"off"`, `false`, `null`): `_claim_ttl_hours` fails CLOSED (disabled)
and logs once to stderr rather than silently defaulting to 24 (feature ON); `lanes-config.sh check`
rejects the same malformed values outright, reading the raw config value with no `// default`
masking. Any `gh`/`jq` failure while computing staleness fails closed (treated as NOT stale) and
logs `stale-check SKIPPED #<n>: <why>` to stderr — a lookup failure must never evict live work.
`gh pr list --label agent:X` is cached per agent within one `list`/`render`/`next` call, so N stale
issues held by the same agent cost one PR lookup, not N.

`next`'s stale fallback never offers the caller's own claims as candidates (reclaiming yourself is
nonsensical, not a race). On refusal it retries the next candidate ONLY for exit `3` (not eligible)
and `6` (could not verify) — both refuse before making any write. Every other code, including `4`/`5`
(a real claim race), `2` (a usage error) and `7` (a write DID happen — the release comment landed —
but the claim afterward failed anyway), propagates immediately: retrying past `7` would silently
abandon that issue (OLD's claim already released, NEW's claim never completed) while `next` moved on
and looked successful. `claim`/`reclaim` never rely on `set -e` to catch a failed `gh`/`jq` call —
calling `cmd_claim` from `cmd_reclaim` goes through `$(...)` for the same reason: `exit` (which `die`
uses) ends the current shell outright rather than "returning" to an `if`, so a direct function call
would let cmd_claim's raw exit code escape uncaught instead of being remapped to `7`. Every gh/jq call
is followed by an explicit `|| die`, because bash 3.2 does not propagate `-e` into a `$(...)` command
substitution at all, and even where it can on other bash versions, the race check runs nested inside
an `if` (where `-e` is always suspended for the whole condition). The claim-race resolver itself
fails (not "wins") when the comments read-back is empty/invalid or when the claimant's own
just-posted claim comment isn't in it yet — it re-reads once after a short delay before giving up.
A claim ends on a `release:` comment OR a lost racer's own `claim-lost: NAME to WINNER` — treating
only the first as a release let a racer who had already lost block every later claimant forever; the
unverified-race path above posts its own `release: NAME ts unverified` for the identical reason,
since dying with no comment at all leaves the same kind of claim that nothing ever ends.

## Known limitations

- `prd-scan` makes two `gh` searches per requirement id; scope it with `--prd <file>`.
- `render` shows open issues only — a work-in-flight board, not an archive.
- `ladder.sh health` can count commits behind only when the running SHA exists in local history.
