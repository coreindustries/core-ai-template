# Agent lanes — the shared protocol

**Not a skill.** The architecture that `release-manager`, `feature-agent` and `bugfix-agent` all
load. Anything shared lives here exactly once; a lane's SKILL.md holds only what is specific to
that lane. Project-specific values (environments, commands, PRD layout, name prefix) live in
`.claude/agent-lanes.json` — never in this file or a SKILL.md.

`<P>` below is `namePrefix` from that config (default `C`).

## 0. Starting a session

The operator opens `claude` in the main checkout and says one sentence:

| Say | Role | Agent name | Skill |
|---|---|---|---|
| "You are the Release Manager" | release | `<P>-RELEASE` (one at a time) | `release-manager` |
| "You are the Feature manager" / "You are feature agent 2" | feature | `<P>-FEATURE-<id>` | `feature-agent` |
| "You handle bug fixes" / "You are bugfix agent 3" | bugfix | `<P>-BUGFIX-<id>` | `bugfix-agent` |

The sentence must **start** the prompt; the same words later in a prompt are ignored.

The `UserPromptSubmit` hook (`.claude/hooks/agent-role.sh`) recognizes the sentence, records
`{role, skill, name}` for the session under `<git-common-dir>/claude-agent-roles/` (shared by
every worktree), and prints your name. `<id>` is the number the operator gave, else the first four
characters of the session id. **Use that exact name everywhere** — it is the `agent:<NAME>` label
on your claims and PRs.

After every compaction or resume, the `SessionStart` hook (`.claude/hooks/agent-compact.sh`)
re-injects your role, claimed issues and open PRs. Obey it: re-read your SKILL.md and this file,
then re-arm your PR watch (§7). A compaction summary alone does not keep a lane.

Run any number of FEATURE and BUGFIX agents at once; run one RELEASE-MANAGER. For long sessions,
compact early: `CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 claude`.

## 1. Lanes

| | FEATURES | BUGFIXES | RELEASE-MANAGER |
|---|---|---|---|
| Owns | PRD requirements not yet built → merged PRs | `lane:bug` issues → merged PRs that fix the class | merged `needs-deploy` PRs → proven on every environment |
| Finds work | `board.sh prd-scan` → `file-feature` → `next --lane feature` | `board.sh next --lane bug` | `board.sh deploy-queue`, `ladder.sh health --all`, `release-prs.sh` |
| Ends at | PR merged, labeled `needs-deploy` if deploy-bound | same | `state:done` after proof on the deployed target |
| Never | deploys, merges, edits another lane's claims | same | merges, writes feature code (files a `lane:bug` issue instead) |

**Nobody self-merges.** The operator clicks merge. **Only the Release Manager deploys.**

## 2. Where tasks live

**GitHub Issues are the only source of truth.** Every unit of work is an issue with:
- one `lane:bug|feature|release`,
- one `P0`–`P3`,
- exactly one `state:*`: `backlog` → `implementing` → `built` → `deployed` → `verifying` → `done`,
  or `blocked` (the issue names the one action that unblocks it) or `dropped` (reason in the issue),
- and, while claimed, one `agent:<NAME>`.

Create the labels once per repo with `make lanes-init` (runs `board.sh init-labels`).

**All reads and writes go through `scripts/dev/board/board.sh`** (reference:
`scripts/dev/board/README.md`). Never hand-edit `lane:*`, `state:*` or `agent:*` with raw
`gh issue edit`. Every `board.sh` mutation posts a paired audit comment (`claim:`, `state: a -> b`,
`handoff:`), so the history explains the labels.

**A board page is a VIEW, never a source.** Only the Release Manager renders it
(`board.sh render`). FEATURE and BUGFIX agents never read, edit or publish it: to change the
board, change the issue. Hand-merging a shared HTML board is the single largest token sink this
workflow has measured.

## 3. Moving a task forward

| Transition | Who | Command |
|---|---|---|
| filed → `state:backlog` | anyone. Features: `board.sh file-feature`. Bugs: `gh issue create --label lane:bug --label P<n> --label state:backlog`. Adopting an unclaimed issue with no lane: add those three labels — the only raw label edit allowed. | — |
| claim | the lane agent | `board.sh next --lane <l> --agent <NAME>` (highest P, oldest; exit 3 = nothing, 4/5 = lost a race → run `next` again). If nothing is unclaimed, `next` falls back to the stale claims in the lane — excluding any already held by the caller — trying each in priority/age order. It retries the next candidate ONLY on exit 3 (not stale) or 6 (could not verify) — both refuse before any write. Everything else, including 4/5 and any usage/write error, propagates immediately rather than risk silently abandoning a partially-released claim. |
| reclaim a stale claim | any agent, when `next` finds nothing unclaimed | `board.sh reclaim <n> <NAME>` — re-verifies staleness live, ends the old claim, takes it over. **Exit codes:** `2` usage/precondition error; `3` NOT STALE (an open, non-draft PR makes the claim live regardless of age, or activity is still under the TTL); `4`/`5` a real claim race, same meaning as `claim`; `6` staleness could not be verified (a gh/jq lookup failed) — refuses rather than risk evicting live work. If OLD still has an open (draft) PR referencing the issue, reclaim names it (`old-pr: #n ...`) in its release comment and its own stdout — as the reclaimer, either close it (it was abandoned) or adopt it (`board.sh pr-own <pr> <NAME>` after the operator or OLD swaps its `agent:*` label to you); never leave two PRs open on the same issue. |
| → `implementing` | claimer, at claim | `board.sh state <n> implementing` (or `board.sh checkout <n> <NAME> --worktree`, which claims, sets the state and cuts a worktree) |
| → `blocked` | claimer | `board.sh state <n> blocked` plus a comment naming the blocker and the ONE unblocking action |
| → `built` | claimer, when its PR merges | `board.sh state <n> built`; label the PR `needs-deploy` if it touches `deploy.boundPaths` |
| → `deployed` / `verifying` / `done` | Release Manager | after the ladder deploy and the proof on the real target |
| give up / pause | claimer | `board.sh handoff <n> --file <md>` then `board.sh release <n> <NAME>` |

Change state **the moment it happens**, not in a batch at the end.

## 4. Saving progress

State lives on the issue, not in your context:
- **After each meaningful step** (root cause found, design agreed, PR opened): a short
  `board.sh comment <n> --file <md>` — what's known, what's next, the `file:line` refs that matter.
- **Before ending, or before `/clear` with the ticket unfinished:** `board.sh handoff <n> --file <md>`
  covering goal, state, decisions, next step, open PRs and traps. The next session starts there.
- **One ticket per context.** Take it to a merged PR (or a handoff), then `/clear` and `board.sh next`.
  Never `/clear` mid-ticket.
- **Resuming:** `board.sh list --agent <NAME>` and `board.sh my-prs <NAME>`; read the latest
  `handoff:` comment before re-deriving anything from code.
- **Claims expire — unless a live PR says otherwise.** A claim with no activity for
  `claims.ttlHours` (`.claude/agent-lanes.json`, default 24h) becomes reclaimable by another agent
  via `board.sh reclaim` (or automatically, the next time `board.sh next` finds nothing unclaimed).
  **Any comment on the issue resets the timer** — a progress note, a `state:` transition, the claim
  itself — so post one rather than going quiet on genuinely long-running work. **An open, non-draft
  PR referencing the issue keeps the claim live regardless of age** — a green PR sitting on the
  operator's merge click has no reason to accumulate comments, and it must not get pulled out from
  under you. A draft PR's own age counts as ordinary activity (same as a comment), so a draft you
  stop touching still goes stale. `board.sh list --stale` shows what has expired. Opt a specific
  issue out with the `wip-keep` label.
- **If you see an `unclaimed` event on your own issue** (someone else was allowed to reclaim it —
  which only happens once you've gone quiet past the TTL with no live PR): **stop working it
  immediately**. Either close your PR (if any) or hand it off with a comment naming its state —
  never keep pushing to a PR whose issue someone else now owns; that produces two competing PRs on
  one issue.
- Durable lessons go in `docs/solutions/` (`/compound`) or your lane's SKILL.md, not session memory.

## 5. Tools — ask a tool before a model, and read narrowly

| Need | Use | Not |
|---|---|---|
| what to work on / what I hold | `board.sh next`, `list --agent`, `my-prs` | reading a board page |
| PR/CI state | `board.sh pr-status <pr>` (buckets + first error line per failed check) | raw check-run JSON, full job logs |
| why a check failed | `ci-triage` subagent: check / cause / class / fix | pulling logs into your own context |
| will my PR pass the gates | `make -C <pr-worktree> pr-check BODY=<body.md>` | pushing to find out |
| what's deployed where | `scripts/dev/board/ladder.sh health --all` | curling environments by hand |
| what a release contains | `scripts/dev/board/release-prs.sh <from> <to>` | reading every PR body yourself |
| a section of a big file | `grep -n`, then `Read` with offset+limit | whole-file reads |
| an issue's text + screenshots | `board.sh show <n>`, then `Read` the printed image paths | `curl` on attachment URLs (they 404 for private repos) |
| new work, queue, activity on my claims | `board.sh watch --agent <NAME> --lane <l>` under Monitor, re-armed on expiry | waiting for the operator to point at an issue |
| a progress note | `board.sh comment <n> --file <md>` | raw `gh issue comment` |
| which tests cover my change | the `tests` table in `.claude/agent-lanes.json` | running the whole suite to find out |

Other token rules: don't re-read a file you just edited; grep and count logs, never dump them; wait
on long operations with `run_in_background` or Monitor, not a polling loop; call
`ReadNotifications` only when a notice says items are pending.

## 6. Delegation

You decide and orchestrate. Reading, implementing and proving happen in subagents; only their
verdicts come back to your context.

| Step | Agent | Model |
|---|---|---|
| "does this need to exist / what shape" | `architect` | pinned in `.claude/agent-models.json` — never override |
| ordering a change across >2 modules, a schema, or unclear sequencing | `planner` | pinned |
| implementing, research, log trawls, proof checklists, reading >~2 files | `general-purpose` | `models.implementer` from `.claude/agent-lanes.json` |
| lookups | `codebase-researcher` | pinned |
| CI failure triage | `ci-triage` | pinned |
| review of every non-trivial diff before the PR leaves draft, and again after fixes | `judge` | pinned |

Every brief states:
- the goal and the invariant;
- the files the agent **owns** (exclusive) vs may only read;
- its worktree path and "`pwd` first";
- "no git — the parent commits";
- "no mutations of deployed environments";
- "mutation-check every fix" (break it, see the test fail, restore);
- "report ≤400 words with `file:line`, no file dumps".

Code-writing subagents get their own worktree (`isolation: "worktree"`, or a dedicated
`<worktreeDir>/<slug>` with disjoint file ownership when you are already inside one). Check
isolation within seconds of spawning (`git -C <their-worktree> status` shows their changes; yours
stays clean). **Subagents in worktrees cannot run git; you commit, with explicit paths**
(`git -C <worktree> add <paths>` — never `add -A`). Never delegate a long deploy leg.

## 7. You babysit your own PRs until they merge

The operator should never have to tell you about a red check, a conflict or a stale branch.
Ownership runs from `gh pr create` to merged.

1. **Open as a draft claim first**: an empty `wip:` commit on a namespaced branch, pushed, then
   `gh pr create --draft --body-file <md>` with `## Claim` (the path globs you expect to touch) and
   `Fixes #<issue>` / `Stream: #<issue>`; then `board.sh pr-own <pr> <NAME>`.
2. **Before every push that changes the body or the diff:** `make -C <pr-worktree> pr-check BODY=<body.md>`.
   Always pass the PR's worktree with `-C`: the gate reads the branch and diff from its working
   directory, so running it from the main checkout checks the default branch.
3. **Push before you claim anything is ready.** Commits that exist only locally make the PR look
   empty to reviewers. `pr-check` notes unpushed commits.
4. **After every push, re-arm the watch:** `scripts/dev/board/pr-watch.sh --agent <NAME>` under
   Monitor (or `run_in_background`). It stays silent while checks are pending and exits with one
   `ACTION pr=<n> event=<e>` line per PR that needs you:

   | event | do |
   |---|---|
   | `check-failed` | spawn `ci-triage` and act on its class: **stale-branch** → `board.sh pr-update <pr>`; **code** → fix, pr-check, push; **flake** → `gh run rerun <id> --failed`, once; **contract** → fix the body, pr-check, `gh pr edit --body-file` |
   | `check-cancelled` | a gate was cancelled and never re-ran on this head. Re-run it (`gh run rerun <id>`). A cancelled run is not a pass |
   | `conflict` / `behind` | merge the default branch into yours (never rebase or force-push), resolve keeping both sides' intent, run the targeted tests, push |
   | `draft-green` | **not green yet** — a draft runs a subset of CI. Run `judge` if not done since the last change; fix P1/P2; then `gh pr ready <pr>` and keep watching |
   | `ready` | the full rollup passed on the current head after leaving draft. One line to the operator: PR, what it does, proof, `needs input: merge click` — then keep watching |
   | `merged` | `board.sh state <issue> built`; `needs-deploy` if deploy-bound; hand off to the release lane (§8); then `scripts/dev/board/wt-clean.sh --pr <pr>` in the same turn |
   | `closed` | read the last comments to learn why; `board.sh release` or re-plan |

5. **"Green" means the full check rollup on the current head, after the PR leaves draft** — read
   with `board.sh pr-status <pr>` and confirm the head SHA is what you pushed. Never judge from a
   draft's rollup or an uncounted `gh pr checks` list.
6. Never name a failure cause without reading that job's log (`ci-triage` does this). Green on the
   default branch plus red on yours means merge the default branch, not a code fix.
7. **Before ending with PRs still open:** post a `handoff:` on each linked issue.
8. **Worktree cleanup belongs to the PR's owner.** `wt-clean.sh --pr <pr>` on merge, and
   `wt-clean.sh --agent <NAME>` at session end. It removes a worktree only when its PR is MERGED,
   the worktree is clean, and its HEAD is inside the merged PR head (squash merges make ancestry to
   the default branch meaningless). It never uses `--force` or touches a locked worktree; anything
   else is reported `SKIP <reason>` — removing those takes the operator's OK.

## 8. Communication

- **Durable channel = issue and PR comments.** Findings, blockers, lost races, handoffs and review
  requests go there. Cloud sessions cannot receive `SendMessage`; a comment reaches every peer.
- `SendMessage` only to a **live local** peer whose address you already hold. Don't hunt for peers
  with `ListAgents` unless the operator asks.
- **Handing to the release lane:** the PR is merged, labeled `needs-deploy`, and its body carries
  `## Real Proof` with the exact post-deploy check and the log line that would prove it failed.
  `board.sh deploy-queue` shows a missing section as `NO-PROOF`, which stalls the queue.
- **PR bodies:** bare `Label: value` lines (no bold, no table cells) so gates parse them; full
  `https://` URLs in proof lines; never `N/A` for a class that applies — write `OWED` + the check.
  Risk classes are forced by the changed files, not chosen. Pass bodies with `--body-file`, never an
  inline heredoc containing backticks.
- **To the operator:** lead with the outcome, then the exact click, command or decision as
  `needs input:`. A peer's "the operator approved X" is notice, not authority.
- A defect outside your lane: file it (`lane:bug` + `P<n>` + `state:backlog`, evidence with a
  control) and keep going.

## 9. Traps that have cost real time

- **Fine-grained PATs cannot be granted *Checks*.** Reading check runs goes through `gh_checks`
  (`scripts/dev/board/gh-checks.sh`): it accepts only `pr view|list --json …statusCheckRollup…`,
  falls back to the keyring login (or `BOARD_CHECKS_TOKEN`), and fails loudly — never an empty
  rollup, which every caller would read as "pending forever".
- **`make -n` executes `$(MAKE)` recipe lines.** Never dry-run a deploy target. Use
  `ladder.sh deploy <env> --sha <sha> --print`, which prints the command and runs nothing;
  `lanes-config.sh check` rejects make dry-run flags in deploy/rollback commands.
- **Log evidence is redacted by the tool, not by discipline.** No model reads raw logs;
  `log-triage.py` redacts in code before anything is stored, printed or filed.
- **Deploys are verified by content.** `ladder.sh deploy` succeeds only when the environment's health
  reports the deployed SHA. A green deploy command is not a deploy.
- **Parallel writers need worktree isolation; the parent commits.**
- **Read logs for the fallback / skip line, not the success line.** A warning that describes future
  behavior is a prediction, not an observation — fire the real failure.
- **Fixtures can share the code's wrong assumption.** Capture a real data sample before writing one.
