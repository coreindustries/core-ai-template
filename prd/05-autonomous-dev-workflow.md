---
prd_version: "1.0"
status: "Draft"
last_updated: "2026-05-22"
owner: "@coreyszopinski"
---

# PRD-05 — Autonomous Dev Workflow (Stop Babysitting Agents)

## 1. Purpose

**Audience:** Core (CEO / operator), Claude Code agents, CI/CD pipeline

**Problem:** 80% of Core's dev time is agent babysitting — copy-pasting context, monitoring deploys, triaging CI failures, and rubber-stamping trivial PRs. This is a structural problem, not a capacity problem.

**Goal:** Reduce human-in-the-loop overhead to <20% of dev time by building the scaffolding that makes agents self-sufficient, failures self-routing, and deploys self-observable.

**Success metric:** Core spends ≥70% of dev time on feature invention, not coordination.

**Non-goal:** Fully removing humans from logic/architecture decisions — those stay.

---

## 2. Functional Requirements

### FR1 — Shared Agent Context Bus

**FR1.1 — Handoff Skill**

Every agent session MUST terminate by writing a structured handoff file. No agent requires a human briefing to resume work.

- File location: `prd/tasks/{feature_name}_tasks.md`
- Written by: `/handoff` Claude Code skill (auto-invoked at session end)
- Read by: next agent session as first step before any file reads

**FR1.2 — CLAUDE.md Current State Block**

`CLAUDE.md` MUST include a machine-updated `## Current State` block. Agents update it on every commit. Core never updates it manually.

**FR1.3 — Worktree Context File**

Each git worktree (`.git/worktrees/{name}`) gets a `CONTEXT.md` at root. Contains: feature goal, decisions made, blockers, last agent action, next action.

---

### FR2 — Self-Healing CI

**FR2.1 — Auto-Fix Agent on Deterministic CI Failures**

When CI fails on lint, format, or type errors, an auto-fix agent runs automatically — no human trigger required.

- Trigger: CI job fails on `feat/*` or `bug/*` branch
- Agent scope: lint fix, format fix, type error fix only — no logic changes
- Commit message: `chore: auto-fix ci [lint|types|format]`
- On success: re-trigger CI, post result to `#csuite-cto`
- On failure (agent can't fix): notify Core via `#csuite-cto` with failure type + log snippet

**FR2.2 — Failure Taxonomy**

All CI failures MUST be classified before routing to human:

| Failure Class | Auto-Fix? | Human Notified? |
|---|---|---|
| Lint / format / import order | ✅ Yes | Only if fix fails |
| Type annotation errors | ✅ Yes | Only if fix fails |
| Test failure — deterministic | ✅ Yes (fix agent) | After fix attempt |
| Test failure — flaky (retry pattern) | ⚠️ Retry once | If retry fails |
| Build failure | ❌ No | Immediately |
| Logic failure / unknown | ❌ No | Immediately with triage |

---

### FR3 — Auto-Merge Policy

**FR3.1 — Tier-Based PR Routing**

PRs are auto-classified by commit type prefix and scope. Auto-merge executes without Core's review where safe.

| Tier | Criteria | Action |
|---|---|---|
| 0 — Auto | `chore:` / `docs:` / `style:` + all CI green | Auto-merge immediately |
| 1 — Fast | `fix:` + full test coverage + CI green | Auto-merge after 30min window |
| 2 — Review | `feat:` — any size | Requires Core review |
| 3 — Hold | Any PR touching: auth, billing schema, infra, migrations | Requires Core review + `needs-review` label |

**FR3.2 — Auto-Merge Enforcement**

- Implemented via GitHub branch protection rules + `auto-merge.yml` workflow
- Tier 0 and Tier 1 PRs get `auto-merge` label applied by workflow on open
- GitHub native auto-merge executes when conditions met
- All auto-merged PRs post summary to `#csuite-cto`

---

### FR4 — Deploy Observability

**FR4.1 — Post-Deploy Health Check**

Every deploy MUST run a health check and report result to Slack. Core never watches a deploy console.

- Health check hits: `/api/health` + 2–3 critical business endpoints
- On pass: post green summary to `#csuite-cto` with deploy SHA and duration
- On fail: post red alert to `#emergency` with failing endpoint + response

**FR4.2 — Deploy Summary Format**

```
✅ Deploy green — seesweet.ai
SHA: abc1234 | Duration: 2m 14s | Env: prod
Health: /api/health ✓ | /api/usage ✓ | /api/clients ✓
```

```
🚨 Deploy failed health check — seesweet.ai
SHA: abc1234 | Env: prod
Failing: /api/usage → 503 after 3 retries
Action required.
```

**FR4.3 — WatchTower Integration (deferred)**

When PRD-04 (WatchTower) ships, FR4.1 health checks migrate to WatchTower monitors. The GitHub Actions post-deploy check remains as a fast-path first signal.

---

### FR5 — Agent Failure Triage Routing

**FR5.1 — CTO Agent Owns Failure Triage**

The `CTO` C-suite agent is the first receiver of all classified CI/CD failures. Core only sees failures that are unresolvable or require architectural judgment.

**FR5.2 — Failure Message Format (Slack)**

All agent-posted failures MUST use structured format:

```
🔴 [FAILURE CLASS] — {repo}/{branch}
PR: #{number} | Commit: {sha}
Class: {lint|types|test|build|unknown}
Auto-fix attempted: {yes|no}
Result: {fixed|failed|not attempted}
Next: {auto-merging|fix agent running|needs Core review}
Log: {link or 3-line snippet}
```

---

## 3. Rollout Sequence

| Phase | Deliverable | Effort | Impact |
|---|---|---|---|
| 1 | `/handoff` skill + `prd/tasks/` enforcement | 2h | Kills copy-paste immediately |
| 2 | `auto-fix.yml` CI workflow | 3h | Eliminates deterministic failure babysitting |
| 3 | Auto-merge rules (Tier 0 / Tier 1) | 2h | Eliminates trivial PR reviews |
| 4 | Post-deploy health check script + Slack routing | 2h | Eliminates deploy watching |
| 5 | CTO agent failure triage routing | 3h | Triage becomes agent job, not Core's |

---

## 4. Configuration

| Variable | Description | Where |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude API key for auto-fix agent | GitHub Secrets |
| `DEPLOY_URL` | Base URL for health checks | GitHub Env / `.env` |
| `DEPLOY_SHA` | Injected by deploy workflow | GitHub Actions |
| `SLACK_WEBHOOK_CTO` | Slack webhook for #csuite-cto | GitHub Secrets / AWS SSM |
| `SLACK_WEBHOOK_EMERGENCY` | Slack webhook for #emergency | GitHub Secrets / AWS SSM |

---

## 5. Future Enhancements

- **WatchTower (PRD-04):** Absorbs FR4 health checks into persistent uptime monitoring
- **PR summary agent:** Auto-generates human-readable PR description from diff + task file
- **Test flakiness tracker:** Logs flaky test patterns over time; auto-quarantines tests with >2 flaky hits in 7 days
- **Agent loop metrics:** Track agent session outcomes (fixed / escalated / failed)
