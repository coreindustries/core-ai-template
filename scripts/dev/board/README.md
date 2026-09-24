# scripts/dev/board — agent-lanes tooling

Deterministic tools for the Release Manager, Feature and Bugfix agent lanes. GitHub Issues are the
single source of truth; these scripts do the repetitive coordination (claims, state labels, PR/CI
diagnosis, deploys, log triage) so no model call has to rediscover state it could ask `gh` for.

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
| `list [--lane b\|f\|r] [--state s] [--agent NAME] [--unclaimed] [--json]` | Open `lane:*` issues, P0→P3 then oldest first. |
| `next --lane b\|f --agent NAME` | Claims the highest-priority, oldest unclaimed issue. Exit 3 = none; 4/5 = lost a race. |
| `claim <issue> <NAME>` | `agent:<NAME>` + a `claim:` comment, then a race check: an earlier unreleased claim wins and this call backs off (exit 4). Refuses (exit 5) if another agent holds it. |
| `release <issue> <NAME> [--reason ...]` | Drops the claim with a `release:` comment. |
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

## Known limitations

- `prd-scan` makes two `gh` searches per requirement id; scope it with `--prd <file>`.
- `render` shows open issues only — a work-in-flight board, not an archive.
- `ladder.sh health` can count commits behind only when the running SHA exists in local history.
