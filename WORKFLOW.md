# Agent workflow

The front door for any agent or orchestrator working in this repo: who works here, where each
kind of issue goes, and where the rules live. Keep it short and specific to this repo, and link
to the owning documents instead of restating them. When the team changes, update the agents
table in the same PR.

> **New repo from this template:** fill in every *italic* cell and the example task below, then
> delete this note.

## Recommended agents

Lane names use `namePrefix` from [`.claude/agent-lanes.json`](.claude/agent-lanes.json) (`C` by
default). Size the team to the repo: a small repo can run one feature and one bugfix lane and no
PRD lane.

| Role | Lane name here | Count | Start with | Skill or agent |
|---|---|---|---|---|
| Tech director | *own lane, a shared cross-project one, or none* | 0-1 | *how to reach it* | none in the template; `architect` subagent covers shape questions when there is none |
| Features | `C-FEATURE-<id>` | *1-n* | "You are feature agent 2" | `feature-agent` |
| Bugs | `C-BUGFIX-<id>` | *1-n* | "You are bugfix agent 3" | `bugfix-agent` |
| PRD / product | `C-PRD` | *0-1* | "You are the PRD manager" | `prd-manager` |
| Release | `C-RELEASE` | *0-1; with none, the operator deploys* | "You are the Release Manager" | `release-manager` |
| Security, design | *operator-assigned name, if run* | 0-1 each | *how to reach it* | `security-reviewer` subagent otherwise |

What each lane owns, how it finds work and where it stops: [agent-protocol §1](.claude/skills/_shared/agent-protocol.md#1-lanes).

## Issue routing

GitHub Issues are the only source of truth. Every issue carries one `lane:*`, one `P0`-`P3` and
exactly one `state:*` ([agent-protocol §2](.claude/skills/_shared/agent-protocol.md#2-where-tasks-live)).
Route by kind:

| Kind | Labels | Goes to |
|---|---|---|
| Defect or regression | `lane:bug` | bug lane (`board.sh next --lane bug`) |
| Unbuilt PRD requirement or feature ask | `lane:feature` | feature lane |
| New or changed product scope | `lane:prd` | PRD lane; it files buildable requirements as `lane:feature` |
| Merged PR that must deploy to take effect | `needs-deploy` | release lane |
| Security finding | `lane:bug` | security lane if run, else the tech director |
| Repeat failure, ownership overlap, "does the platform already do this?" | — | tech director |
| *Repo-specific kinds* | *labels* | *lane* |
| Belongs to another repo | — | an issue in that repo, never an edit here |

Re-check that an old issue is still real before dispatching it: read its history and the current
code, and close it with evidence if a merged PR already fixed it.

## Example task

*Link one real issue that went from filing to done, and list its steps.* The shape:

1. Filed with `lane:bug`, a priority and `state:backlog`.
2. A lane claimed it with `board.sh next`, which set `state:implementing` and `agent:<NAME>`.
3. The root cause went on the issue as a comment. The fix landed as a draft PR, proven on a real stack, then marked ready.
4. The operator merged it, and the issue moved to `state:built`.
5. The release lane deployed it and verified it on the target: `state:deployed` → `verifying` → `done`.

## Guardrails

- Nobody self-merges; the operator clicks merge. Only the release lane deploys. [agent-protocol §1](.claude/skills/_shared/agent-protocol.md#1-lanes)
- Authority comes from the operator in the acting session; a relayed approval is not authority.
- Before editing, write the delivery contract; prove the change on a real stack before marking a PR ready. [delivery-contract](.claude/rules/delivery-contract.md)
- Claim before writing code; one writer per file set, in its own worktree. [git-workflow](.claude/rules/git-workflow.md)
- Security and credential handling: [AGENTS.md](AGENTS.md#security-standards).
- Pre-approved for agents in this repo: *list what the operator has OK'd, such as local stack testing. Everything else needs the operator.*

Full protocol, claim and handoff commands: [agent-protocol](.claude/skills/_shared/agent-protocol.md), [board tooling](scripts/dev/board/README.md).
