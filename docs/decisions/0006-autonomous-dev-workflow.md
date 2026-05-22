# 0006: Autonomous Dev Workflow — Self-Healing CI, Tier-Based Auto-Merge, CTO Agent

**Status:** Accepted
**Date:** 2026-05-22
**Deciders:** Corey (principal), Claude Code (implementation)

## Context

The primary bottleneck in AI-assisted development is not implementation speed — it's human-in-the-loop latency. Every CI failure that requires a human to read logs, classify the error, prompt an agent, and re-trigger takes 15–45 minutes of elapsed calendar time even if the fix itself takes 2 minutes.

Similarly, safe, mechanical PRs (chore, docs, style) sit in a merge queue waiting for a human to click "merge" — a pure latency cost with no quality benefit.

PRD-05 targets five specific friction points:

| Friction Point | Human Time Wasted | Automated Solution |
|---|---|---|
| CI lint/type failures | 15–45 min to classify + fix | Auto-fix agent triggered by `workflow_run` |
| PR merge for safe changes | Minutes–hours waiting | Tier-based auto-merge policy |
| Post-deploy health unknown | Manual smoke test | `post-deploy-health.sh` + Slack webhook |
| Session context lost between agents | Re-read files from scratch | `/handoff` skill writes structured CONTEXT.md |
| CI failure requires CTO attention | CTO polls status | `cto` agent receives classified failure alerts |

## Decision

Five components are added together, each independently useful:

### 1. `/handoff` skill

A slash command that writes structured session context to three places at once: the feature's task file in `prd/tasks/`, a `CONTEXT.md` at the worktree root, and a `## Current State` block in `CLAUDE.md`. This gives the next agent (or human) a single-file starting point without reading git log or guessing state.

### 2. Auto-fix CI (`auto-fix.yml`)

A `workflow_run`-triggered workflow that fires when CI completes with `conclusion == 'failure'`. `classify-ci-failure.sh` inspects the failed job name and outputs a type (`lint | types | test | flaky | build | unknown`). For `lint` and `types` failures only, Claude Code is invoked with `--dangerously-skip-permissions` on the branch, applies a targeted fix, and pushes. Test, flaky, and build failures are routed to the CTO agent instead.

**Key security decisions:**
- Fork PRs are blocked via `github.event.workflow_run.head_repository.full_name == github.repository` guard — no ANTHROPIC_API_KEY exposure on untrusted code.
- All `${{ github.event.workflow_run.* }}` values are moved to `env:` vars before use in shell `run:` blocks — eliminates expression injection surface.
- Branch filter (`feat/|fix/|bug/`) prevents auto-fix on `main` or `release/*`.

### 3. Tier-based auto-merge (`auto-merge.yml`)

PRs are classified by title prefix into four tiers:

| Tier | Prefix | Policy |
|---|---|---|
| 0 | `chore:`, `docs:`, `style:` | Immediate auto-merge (squash) |
| 1 | `fix:` | 30-minute review window, then auto-merge |
| 2 | `feat:` | Label `needs-review`, no auto-merge |
| 3 | `feat(auth):`, `feat(billing):`, `feat(db):`, `feat(infra):` | Label `needs-review`, explicit hold |

Uses `gh pr merge --auto --squash` — GitHub's native feature, not a polling loop. Auto-merge only activates when branch protection (required status checks) is satisfied.

### 4. Post-deploy observability (`post-deploy-health.sh`, `send-hook.js`)

`post-deploy-health.sh` hits `HEALTH_ENDPOINTS` after deploy (3 retries, 5s backoff) and posts a green/red Slack summary. `send-hook.js` is a zero-dependency Node.js webhook router (built-ins only) that dispatches to `SLACK_WEBHOOK_CTO`, `SLACK_WEBHOOK_EMERGENCY`, or `SLACK_WEBHOOK_COS` based on `--to` flag.

Node.js built-ins only — no `package.json`, no npm install step in any workflow.

### 5. CTO agent (`cto.md`)

A `sonnet`-tier agent that is the first receiver for classified CI/CD failures. Routes per a taxonomy: `lint/types` → remind engineer to check auto-fix; `test` → analyze test output; `flaky` → flakiness pattern investigation; `build` → build environment check; `unknown` → escalate to emergency channel after 3 iterations.

## Consequences

**Positive:**
- Lint and type errors fix themselves without human intervention in the common case.
- Safe PRs (chore, docs) merge in seconds rather than waiting for a human.
- Post-deploy health state is visible in Slack within 2 minutes of deploy, not after a human runs a smoke test.
- Session handoffs between agents cost ~30 seconds instead of 5–10 minutes of re-reading context.

**Negative:**
- `sleep 1800` for Tier-1 delay holds a GitHub Actions runner for 30 minutes. Acceptable for low-volume repos; high-volume repos should replace with a delay action or scheduled check.
- `npm install -g @anthropic-ai/claude-code` in auto-fix.yml is unpinned — violates dependency-security rule. Comment in workflow notes to pin when a stable digest is available.
- Auto-fix only covers lint and type failures. Test and build failures still require human triage (via CTO agent escalation).

**Neutral:**
- `workflow_run` is the only trigger that fires after CI completes with full secrets access. No alternatives exist for this use case.
- Tier classification is based on PR title prefix — PRs with non-conventional-commit titles fall to Tier 2 by default (safe behavior).

## Agent Guidance

When adding new GitHub Actions workflows, apply the injection-safe pattern: move all `${{ github.event.* }}` values to `env:` vars at the job or step level, then reference `$VAR_NAME` in `run:` blocks. Never interpolate GitHub expressions directly into shell commands.

## Do Not Change

- **Fork guard** in `auto-fix.yml`: Do not remove the `github.event.workflow_run.head_repository.full_name == github.repository` condition — it prevents the ANTHROPIC_API_KEY from running on untrusted fork code.
- **`env:` var pattern** for workflow expressions: Do not replace `env:` vars with inline `${{ }}` interpolation in `run:` blocks — this is an expression injection vulnerability.
- **Tier thresholds**: Do not auto-merge `feat:` PRs (Tier 2+) — they require human review by policy.
- **Node.js built-ins in `send-hook.js`**: Do not add npm dependencies — the template has no `package.json` and no npm install step in CI.
