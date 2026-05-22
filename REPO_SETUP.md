# Repo Setup — Autonomous Dev Workflow (PRD-05)

One-time configuration steps to activate the autonomous dev workflow features in a GitHub repository. Do these after the PR is merged.

---

## 1. Enable Auto-Merge (GitHub Settings)

`auto-merge.yml` uses `gh pr merge --auto`, which requires this setting.

1. Go to **Settings → General** in your GitHub repository
2. Scroll to **Pull Requests**
3. Check **Allow auto-merge**
4. Check **Automatically delete head branches** (optional but recommended)

---

## 2. Configure Branch Protection

Auto-merge only fires after required status checks pass. Without branch protection, it merges immediately — defeating the purpose.

1. Go to **Settings → Branches**
2. Add a rule for `main`
3. Enable **Require status checks to pass before merging**
4. Add your CI job names as required checks (e.g. `lint`, `test`, `security`)
5. Enable **Require branches to be up to date before merging**
6. Enable **Do not allow bypassing the above settings**

---

## 3. Add GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Required by | Description |
|--------|-------------|-------------|
| `ANTHROPIC_API_KEY` | `auto-fix.yml` | Claude API key for the auto-fix agent |
| `SLACK_WEBHOOK_CTO` | `send-hook.js`, `auto-fix.yml` | Slack incoming webhook URL for CTO channel |
| `SLACK_WEBHOOK_EMERGENCY` | `send-hook.js` | Slack incoming webhook URL for emergency channel |
| `SLACK_WEBHOOK_COS` | `send-hook.js` | Slack incoming webhook URL for COS/chief-of-staff channel (optional) |

**Creating Slack webhooks:**
1. Go to your Slack workspace → **Apps → Incoming Webhooks**
2. Click **Add New Webhook to Workspace**
3. Select the target channel
4. Copy the webhook URL → paste into the GitHub secret

---

## 4. Verify Auto-Merge Labels Exist

`auto-merge.yml` applies labels (`auto-merge-tier-0`, `auto-merge-tier-1`, `needs-review`) that must exist in the repo. Run the labels-sync workflow to create them:

```bash
gh workflow run labels-sync.yml
```

Or push to `main` — `labels-sync.yml` runs on push and reconciles `.github/labels.yml` with the live repo.

---

## 5. Verify the Auto-Fix Workflow Trigger

`auto-fix.yml` uses the `workflow_run` trigger, which requires the source workflow (`CI`) to already be registered in the default branch before it will fire.

```bash
# Confirm CI workflow is registered
gh workflow list

# Expected output includes:
# CI    active    .github/workflows/ci.yml
```

If `CI` is missing, ensure `ci.yml` exists on `main` (not just on a feature branch) and re-trigger.

---

## 6. Test the Setup

### Test auto-merge (Tier 0)

```bash
git checkout -b chore/test-auto-merge
echo "# test" >> README.md
git add README.md
git commit -m "chore: test auto-merge trigger"
git push -u origin chore/test-auto-merge
gh pr create --title "chore: test auto-merge trigger" --body "Testing Tier-0 auto-merge"
```

Expected: PR is auto-merged after CI passes.

### Test post-deploy health check

```bash
# Set required env vars and run locally
HEALTH_ENDPOINTS="/api/health" \
DEPLOY_ENV=staging \
BASE_URL=https://your-staging-url.com \
bash scripts/post-deploy-health.sh
```

Expected: HTTP 200 response from each endpoint, Slack message posted (if `SLACK_WEBHOOK_CTO` is set).

### Test the CTO agent

```bash
# In Claude Code, invoke the agent directly
# claude --agent cto "CI failed with lint errors on PR #42"
```

---

## 7. Optional: Pin the Claude Code CLI Version

`auto-fix.yml` currently installs Claude Code CLI without a version pin:

```yaml
run: npm install -g @anthropic-ai/claude-code
```

This violates the 24-hour dependency cooldown rule (`.claude/rules/dependency-security.md`). Once a stable tagged release is available, pin it:

```yaml
run: npm install -g @anthropic-ai/claude-code@X.Y.Z
```

Track the release at: https://github.com/anthropics/claude-code/releases

---

## Summary Checklist

- [ ] **GitHub Settings → General**: Allow auto-merge enabled
- [ ] **GitHub Settings → Branches**: Branch protection + required status checks on `main`
- [ ] **GitHub Secrets**: `ANTHROPIC_API_KEY`, `SLACK_WEBHOOK_CTO`, `SLACK_WEBHOOK_EMERGENCY` added
- [ ] **Labels**: `auto-merge-tier-0`, `auto-merge-tier-1`, `needs-review` exist in repo (run `labels-sync.yml`)
- [ ] **CI workflow**: `ci.yml` registered on `main` branch (required by `workflow_run` trigger)
- [ ] **Smoke test**: Tier-0 PR auto-merges after CI passes
- [ ] **Optional**: Pin `@anthropic-ai/claude-code` version in `auto-fix.yml`
