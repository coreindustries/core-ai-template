---
name: bugfix-agent
description: "Become a BUGFIXES lane agent: take the highest-priority lane:bug issue, reproduce it, find the root cause and fix the whole class through subagents, review with judge, and babysit the PR until it merges. Use when told 'You handle bug fixes', 'you are the bugfix agent', 'bugfix agent 2', or /bugfix-agent. Do not use for a one-off bug outside the lanes workflow (that is /debug)."
---

# BUGFIXES lane (`<P>-BUGFIX-<id>`)

**Load first:** `.claude/skills/_shared/agent-protocol.md` — how to start, where tasks live, saving
progress, tools, delegation, PR babysitting, communication. This file adds only the BUGFIXES lane.

**Goal:** each bug is fixed at its root cause, for every instance of its class, with a test that
fails without the fix and a post-deploy check that proves it on the real target. You never deploy
or merge.

## 1. Start or resume

1. Take your name from the role hook.
2. Arm **both** watches with Monitor and keep them armed all session (max timeout, re-armed on every
   expiry; their dedup state is on disk, so a restart resumes):
   - `board.sh watch --agent <NAME> --lane bug` — new and queued issues, activity on your claims;
   - `pr-watch.sh --agent <NAME>` — failed or cancelled checks, conflicts, behind, merged. Arm it with
     your **first** PR, not only on resume: a merged sibling PR can leave your other PR conflicting.
   - Run both from a worktree detached at the default branch
     (`git worktree add --detach <worktreeDir>/lane-tools origin/<defaultBranch>`, refreshed before
     each re-arm), never from the main checkout — that is the operator's copy and goes stale.
3. `board.sh list --agent <NAME>` and `board.sh my-prs <NAME>`. Holding something → resume from its
   `handoff:` comment.
4. Otherwise `board.sh next --lane bug --agent <NAME>`. Exit 3 = queue empty: do §2. Exit 4 or 5 =
   lost a race: `next` again.

**Reacting to `board.sh watch` events:**
- `NEW-ISSUE` — re-measure it and intake per §2. A P0 preempts the current ticket: hand off the
  current one, then claim the P0.
- `QUEUE-P0` — same: preempt and claim now.
- `QUEUE` — note it; take it with `board.sh next` once the current ticket is done.
- `ISSUE-EVENT` on a claimed issue — read it (`board.sh show <n>` pulls screenshots).
- `WATCH-ERROR` — a scan failed; it retries next poll. Repeated errors: check `gh auth status`.

## 2. Intake (only when the queue is empty)

Open bugs without a lane: `gh issue list --label bug --state open --json number,title,labels`,
filtered to those with no `lane:*` label.
- **Re-measure before adopting**: is the symptom still present on the default branch or the deployed
  SHA? A findings list goes stale within days.
- Adopt a live one with `lane:bug`, `P<n>`, `state:backlog` (the one raw label edit the protocol
  allows, and only on an unclaimed issue). Close a dead one with the evidence.

Priority:
- P0: data loss, security, or down for users.
- P1: user-visible failure, or a **silent** failure. Silent outranks loud.
- P2: degraded.
- P3: cosmetic, or a rollup of minor signatures.

## 3. Fix the claimed bug

1. `board.sh checkout <n> <NAME> --worktree`.
2. **Reproduce before theorizing.** Take the exact symptom, SHA, environment and time from the issue.
   Reproduce locally (a unit repro or the local stack) or with a **read-only** probe. Mutating a
   deployed environment belongs to the Release Manager — ask on the issue. Reading production user
   data needs the operator's explicit OK.
3. **Root cause** (`/debug` discipline): push log trawls and multi-file reading into implementer
   subagents that return the verdict with `file:line`; read a dependency's source at its pinned version
   before inferring its behavior. Post the root cause as an issue comment **before** fixing.
4. **Fix the class, not the instance.** Grep every other call site with the same shape. More than
   one → the fix includes a ratchet (a check in `prCheck.ratchets` or CI) so the class can't return.
   Check for the two recurring root causes: a control nothing consumes, and a failure that degrades
   open without any signal.
5. Draft PR as the claim, `board.sh pr-own <pr> <NAME>`; the body carries `Fixes #<n>` and the
   `## Delivery Contract`.
6. **Implement through the implementer model** in a worktree: the regression test comes first and
   must **fail without the fix**; fixtures use the real data shape captured from a running system;
   the change stays small — no unrelated behavior changes.
7. Commit yourself, explicit paths.
8. **`judge`** reviews the diff. P1/P2 back to an implementer, then re-judge.
9. Write `## Real Proof` for the Release Manager: the post-deploy check on the real target; **the
   fallback or skip log line that would prove it is still broken**, exact wording; a control such as
   a count before the deploy.
10. `make -C <pr-worktree> pr-check BODY=<body.md>`, push, babysit per protocol §7. On `conflict` /
    `behind`: merge the default branch in at once, re-run targeted tests and ratchets, check it didn't
    merge meanwhile (`gh pr view --json state`), push, confirm `mergeable: MERGEABLE`. When one of your
    PRs merges, re-check your others; two PRs editing one file will conflict, so say so in both bodies.
    After merge: `board.sh state <n> built`, `needs-deploy` if deploy-bound.
11. Diagnosis took more than ~15 minutes → capture it with `/compound`. Then `/clear` and `next`.

## 4. Lane rules

- **Diagnostics are not a fix.** Instrumentation-only PRs say "instrumented and waiting" and leave the
  issue at `implementing`.
- **A green test is not evidence.** The issue closes only after the Release Manager's proof on the
  deployed target (`state:done`).
- Don't name a cause without having read the evidence — yours as much as CI's.
- A feature request disguised as a bug: file it `lane:feature`, release your claim, move on.
