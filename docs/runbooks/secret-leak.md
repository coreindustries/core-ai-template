# Runbook: Secret Leaked on Disk or in Git History

**Trigger:** A plaintext credential has been discovered on a developer machine, in a CI log, in git history, in a PR, or in a shared document. This runbook applies whether the credential was committed or only written to local disk.

**Time target:** Rotation complete within 60 minutes of discovery.

---

## First 5 minutes — contain

1. **Do not delete the file or rewrite history yet.** You may need forensics.
2. **Do not share the secret value in Slack, email, or ticket systems.** Refer to it by name only ("the production Anthropic key," not the value).
3. **Assume the secret is compromised from the moment it hit disk.** The goal is rotation, not concealment.
4. **Notify:** post in `#sec-incidents` (or email `security@core-industries.com`) with:
   - What kind of secret (no value)
   - Where it was found (path, repo, CI job, commit SHA)
   - Who discovered it and when
   - Whether the file is committed, staged, or only local

## Next 30 minutes — rotate

### AWS-managed secrets (Secrets Manager / SSM)

```bash
# 1. Rotate
aws secretsmanager rotate-secret --secret-id <arn> --force-rotate-immediately
# or for SSM:
chamber write <service-name> <key> '<new-value>'

# 2. Verify
chamber list <service-name>

# 3. Redeploy consumers so they pick up the new value
#    (ECS task definitions need a new revision + service update for Secrets Manager
#     ARN changes; chamber values are picked up on next start automatically)
```

### Third-party API keys (Anthropic, OpenAI, Stripe, etc.)

1. Log into the provider dashboard.
2. **Create** a new key first.
3. **Deploy** the new key to production (via SSM/Secrets Manager as normal).
4. **Revoke** the old key only after deploy is confirmed healthy.
5. Rotating order matters: revoking first causes downtime.

### AWS IAM credentials (long-lived access keys — if any exist, they shouldn't)

1. Deactivate the key in IAM console (don't delete yet — CloudTrail will want it).
2. Create a replacement key.
3. Update wherever it was consumed.
4. Delete the old key after 48 hours.
5. File a follow-up task to eliminate the long-lived key (convert to SSO or IAM role).

## Next 30 minutes — contain history

### If the secret was committed to a git repo

1. **Identify the scope:**
   ```bash
   git log --all --oneline -S '<distinctive-fragment-of-secret>' -- .
   # or for a known file:
   git log --all --oneline -- <path>
   ```
2. **If the commit is on a branch not yet merged to `main`:** force-push to remove the commit, then follow up with rotation (already done above).
3. **If the commit is on `main` or any shared branch:** do NOT force-push without incident commander approval. History rewrite invalidates every outstanding PR, breaks every clone, and is rarely worth it *after* rotation has already neutralized the secret.
   - Instead: document the leak in the incident report, confirm rotation is complete, and move on.
   - Consider making the repo private temporarily if the secret grants access to systems that can't be rotated within the hour.
4. **GitHub secret scanning** should auto-revoke many provider credentials (AWS, Stripe, Slack, etc.) — check `https://github.com/<org>/<repo>/security/secret-scanning` for confirmation.

### If the secret was only in local filesystem

1. Shred the file:
   ```bash
   # macOS / Linux with secure-delete installed:
   srm -v <path>
   # Or fallback:
   shred -vzu <path> 2>/dev/null || rm -P <path> 2>/dev/null || rm <path>
   ```
2. Clear shell history if the secret was pasted into a terminal:
   ```bash
   history -c && history -w
   # Also: ~/.zsh_history, ~/.bash_history, ~/.python_history, ~/.node_repl_history
   ```
3. Clear clipboard: `pbcopy < /dev/null` (macOS) or `xclip -selection clipboard < /dev/null` (Linux).
4. Check IDE scratch files: `.vscode/`, `.idea/`, JetBrains "Local History," Zed recent files.

## Audit

1. **CloudTrail:** check for unexpected API calls from the leaked credential in the window between leak and rotation:
   ```bash
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=AccessKeyId,AttributeValue=<key-id> \
     --start-time <leak-time>
   ```
2. **Provider logs:** for Anthropic / OpenAI / Stripe, check usage dashboards for unexpected activity during the exposure window.
3. **Egress logs** (if VPC flow logs enabled): look for unusual outbound connections from the machine that held the secret.

## Post-incident

Within 48 hours, file an incident report in `docs/incidents/YYYY-MM-DD-<slug>.md` covering:

- Timeline (discovery → rotation → verification)
- Root cause (how did the secret land on disk in the first place?)
- Blast radius (what was accessible with this credential?)
- Evidence of abuse (CloudTrail, provider logs, egress)
- Remediation (what was rotated, what was history-rewritten, what was left alone and why)
- Prevention (what rule, control, or process change prevents recurrence?)

**Every incident must close with at least one mechanical control added.** Policy changes alone don't count. Examples of valid closures:

- New gitleaks rule
- New pre-commit check
- New CI gate
- New runtime assertion
- Tightened IAM policy

If the root cause is "someone bypassed the wrapper and used `.env` directly," the closure is to make that bypass harder (e.g., app refuses to start if `.env` exists, expanded `make doctor` check, etc.).

## What NOT to do

- **Don't** paste the secret into the incident channel, Slack DMs, or email so "everyone knows what to look for." Refer by name.
- **Don't** assume `git filter-branch` or BFG Repo-Cleaner makes the secret safe. Anyone who cloned or forked the repo has the history. Rotation is the only real fix.
- **Don't** delay rotation to "investigate first." Rotate, then investigate.
- **Don't** skip the post-incident report because "we rotated, it's fine." The goal is preventing the next one, not the current one.
