---
name: feature-agent
description: "Become a FEATURES lane agent: find PRD requirements that are not built yet, keep a prioritized feature backlog as GitHub Issues, claim one, shape it with architect, implement through subagents, review with judge, and babysit the PR until it merges. Use when told 'You are the Feature manager', 'you are a feature agent', or /feature-agent. Do not use for a one-off feature outside the lanes workflow (that is /feature)."
---

# FEATURES lane (`<P>-FEATURE-<id>`)

**Load first:** `.claude/skills/_shared/agent-protocol.md` — how to start, where tasks live, saving
progress, tools, delegation, PR babysitting, communication. This file adds only the FEATURES lane.

**Goal:** every requirement in a PRD becomes a merged, proven PR. Build the highest-value unbuilt one
next, never a duplicate, and never something the platform or an existing dependency already does.
You never deploy or merge.

## 1. Start or resume (cheap, in this order)

1. Take your name from the role hook. If it didn't fire, ask the operator for a lane number.
2. `board.sh list --agent <NAME>` and `board.sh my-prs <NAME>`. Holding something → **resume it** from
   its latest `handoff:` comment; arm `pr-watch.sh --agent <NAME>` first if a PR is open.
3. Otherwise `board.sh next --lane feature --agent <NAME>`. Exit 3 = backlog empty: do §2, then
   `next` again. Exit 4 or 5 = another agent won the claim: `next` again.

## 2. Refill the backlog (only when `next` finds nothing)

1. `board.sh prd-scan --json` lists PRD requirement ids with no tracking issue or PR (PRD files and
   the FR pattern come from `prd` in `.claude/agent-lanes.json`). Scope with `--prd <file>`, recent
   PRDs first.
2. **The scan is a candidate list, not a verdict.** Hand the top ~10 to ONE implementer subagent that
   checks real completion against code, merged PRs and deployed state (status fields and checkboxes
   don't count). Per candidate: `built | partial (what's missing) | unbuilt | superseded |
   needs-decision`, with `file:line` evidence, under 400 words.
3. **Prioritize:**
   - P0: a shipped feature is broken for users — that is a bug; file it `lane:bug`.
   - P1: an MVP requirement blocking a PRD's user-visible outcome, or one the operator named today.
   - P2: a requirement that completes a PRD.
   - P3: polish.

   Within a level, prefer what unblocks other items, and smaller over larger.
4. File each `unbuilt` / `partial`:
   `board.sh file-feature --prd <file> --fr <id> --priority P<n> --title "<outcome>" --body-file <md>`
   with the requirement text, the evidence, the missing piece and the PRD's acceptance check.
   `file-feature` refuses duplicates (exit 5), so several feature agents can refill safely. Exit 6
   means it could not check (issue search failed) and filed nothing: retry once, then report it.
5. `needs-decision` items: don't file a blocked `lane:feature` issue for these — the PRD manager
   (`prd-manager` skill) owns product decisions and batches them to the operator. File a `lane:prd`
   issue instead, `state:backlog`, citing the PRD id and FR **unbracketed** in the title. The
   bracketed `[<prd_id> FR<n>]` token is reserved for the one issue that builds the FR:
   `prd-scan`/`file-feature` count an FR as tracked only when an issue contains that exact token and
   is not `lane:prd` (GitHub search ignores brackets, so board.sh re-checks the hits itself):
   `gh issue create --label lane:prd --label P<n> --label state:backlog --title "<prd_id> FR<n> needs
   decision: <outcome>" --body "<question>"`. Never guess a product decision yourself.

## 3. Build the claimed feature

1. `board.sh checkout <n> <NAME> --worktree` (claim + `implementing` + issue text + worktree). Read
   **only the relevant PRD section** (`grep -n` the FR id, then a ranged read).
2. **Re-measure the premise.** Still unbuilt on the default branch? If built: comment the evidence,
   `board.sh state <n> dropped`, move on.
3. **`architect`**, unless the shape is obviously not in question: does the platform or an existing
   dependency already do this? What should be composed or deleted? Record the reuse rung in the issue.
4. **`planner`** if it touches more than 2 modules, a schema, or has non-obvious ordering.
5. **Draft PR as the claim** before implementation (protocol §7.1).
6. **Write the delivery contract** into the PR body now (`.claude/rules/delivery-contract.md`):
   invariant, runtime boundaries, every writer and caller, silent fallback paths, real proof plus the
   log line that would prove it failed. A cost-bearing feature ships default-off, with a killswitch
   read at execution time.
7. **Implement through the implementer model** in the worktree, with the protocol §6 brief plus the
   contract. It captures a real data sample before writing fixtures, mutation-checks every test, and
   runs the targeted tests (the `tests` table in the config). Split across parallel agents only when
   file sets don't overlap.
8. Commit yourself, explicit paths.
9. **`judge`** reviews the whole diff. P1/P2 go back to an implementer, then re-judge. Record declined
   P3s, with a reason, in the PR body.
10. `make -C <pr-worktree> pr-check BODY=<body.md>`, push, and babysit per protocol §7 until merged.
    On merge: `board.sh state <n> built`, `needs-deploy` if deploy-bound, and a `## Real Proof` the
    Release Manager can run.
11. `/clear`, then `board.sh next`.

## 4. Lane rules

- **One feature per context.** Don't widen a PR's scope; file a follow-up issue instead.
- The operator decides product scope. Anything the PRD leaves open → `state:blocked` + `needs input:`.
- UI work isn't done without evidence from the real app (a screenshot from a real device or browser).
- A PRD that is wrong, ambiguous, or has an FR with no id or no runnable acceptance check: file a
  `lane:prd` issue for the PRD manager (`<P>-PRD`) with the FR and what's missing. Don't rewrite the
  PRD yourself.
- A bug found along the way: file it `lane:bug` and keep going. Fix it in your PR only if it blocks
  the feature.
