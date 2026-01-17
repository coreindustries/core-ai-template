# /hotfix

Quick patch workflow for production issues with minimal risk.

## Usage

```
/hotfix <issue> [--from <branch>] [--cherry-pick <commit>]
```

## Arguments

- `issue`: Issue number, description, or "rollback"
- `--from <branch>`: Base branch (default: production/main)
- `--cherry-pick <commit>`: Apply specific commit as hotfix

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Move quickly but safely
- Minimize changes to only what's necessary
- Complete the hotfix cycle end-to-end

**Safety:**
- Never skip tests
- Always verify fix in isolation
- Create clear audit trail

**Urgency:**
- Prioritize fix over perfection
- Document thoroughly for follow-up
- Communicate status clearly

### Hotfix Process

#### Phase 1: Assess

1. **Understand the issue**:
   - Severity level (critical, high, medium)
   - Impact scope (all users, subset, specific feature)
   - Current workarounds (if any)

2. **Determine approach**:
   - New fix vs cherry-pick existing commit
   - Rollback vs forward-fix
   - Scope of changes needed

3. **Create hotfix branch**:
   ```bash
   git checkout main
   git pull origin main
   git checkout -b hotfix/{issue_number}-{description}
   ```

#### Phase 2: Fix

1. **Implement minimal fix**:
   - Change only what's necessary
   - Avoid refactoring
   - Avoid unrelated improvements

2. **Add targeted test**:
   - Test the specific failure case
   - Regression test for the bug
   - Keep test focused

3. **Verify locally**:
   ```bash
   {test_command} tests/ -v
   {lint_command}
   ```

#### Phase 3: Validate

1. **Run full test suite**:
   ```bash
   {test_command} tests/ --tb=short
   ```

2. **Security check**:
   ```bash
   {security_scan_command}
   ```

3. **Review changes**:
   ```bash
   git diff main...HEAD
   ```

#### Phase 4: Deploy

1. **Create commit**:
   ```bash
   git commit -m "$(cat <<'EOF'
   hotfix(scope): brief description

   Issue: #123
   Severity: Critical
   Impact: All users experiencing login failures

   Root cause: [brief explanation]
   Fix: [what was changed]

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```

2. **Push and create PR**:
   ```bash
   git push -u origin hotfix/{branch_name}

   gh pr create \
     --title "HOTFIX: brief description" \
     --body "[hotfix PR template]" \
     --label "hotfix,urgent"
   ```

3. **Request expedited review**:
   - Tag on-call reviewer
   - Note urgency in PR

4. **After merge**:
   - Verify deployment
   - Monitor for issues
   - Update incident log

### Rollback Workflow

When `/hotfix rollback` is invoked:

1. **Identify last good commit**:
   ```bash
   git log --oneline -20
   ```

2. **Create revert commit**:
   ```bash
   git revert <bad_commit> --no-edit
   ```

3. **Or deploy previous version**:
   ```bash
   git checkout <last_good_commit>
   ```

4. **Verify rollback**:
   - Run smoke tests
   - Check critical paths

### Cherry-Pick Workflow

When `--cherry-pick` is specified:

1. **Fetch the commit**:
   ```bash
   git fetch origin
   git cherry-pick <commit_hash>
   ```

2. **Resolve conflicts** if any

3. **Verify cherry-pick**:
   ```bash
   {test_command}
   ```

### Hotfix PR Template

```markdown
## HOTFIX: [Brief Description]

**Severity:** Critical / High / Medium
**Issue:** #123
**Incident:** [Link to incident if applicable]

### Problem

[1-2 sentences describing what's broken]

### Impact

- Affected users: [All / Subset / Specific]
- Started: [Timestamp]
- Current workaround: [If any]

### Root Cause

[Brief technical explanation]

### Fix

[What this PR changes]

### Testing

- [ ] Unit test added for failure case
- [ ] Full test suite passes
- [ ] Manually verified fix

### Rollback Plan

[How to rollback if this fix causes issues]

### Follow-up

- [ ] Post-mortem scheduled
- [ ] Long-term fix ticket created: #XXX

---
**HOTFIX - Expedited review requested**
```

### Post-Hotfix Checklist

- [ ] Fix deployed to production
- [ ] Monitoring shows improvement
- [ ] Incident communication sent
- [ ] Follow-up ticket created
- [ ] Post-mortem scheduled (if critical)

## Example Output

```
$ /hotfix 789 --from main

HOTFIX Mode Activated

Issue: #789 - Users unable to login
Severity: Critical
Branch: hotfix/789-login-failure

Creating hotfix branch from main...
  ✅ Branch created: hotfix/789-login-failure

Analyzing issue...
  Reading: src/services/auth.py
  Reading: src/api/login.py
  Reading: recent commits

Root cause identified:
  Commit abc123 introduced a typo in token validation
  `token.exipres` instead of `token.expires`

Implementing fix...
  ✅ Fixed typo in src/services/auth.py:45

Adding regression test...
  ✅ Created tests/unit/test_auth_token_expiry.py

Running verification...
  ✅ Tests pass (145/145)
  ✅ Linting passes
  ✅ Security scan clean

Ready to commit:

hotfix(auth): fix token expiration check typo

Issue: #789
Severity: Critical
Impact: All users unable to login due to token validation failure

Root cause: Typo in token.expires property access (exipres → expires)
Fix: Corrected property name in validation check

Co-Authored-By: Claude <noreply@anthropic.com>

Creating PR...
  ✅ PR created: https://github.com/org/repo/pull/456
  ✅ Labels added: hotfix, urgent
  ✅ Reviewers notified

Next steps:
1. Get expedited review
2. Merge when approved
3. Monitor deployment
4. Update incident channel
```
