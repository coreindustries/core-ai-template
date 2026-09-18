---
name: scan
description: >-
  Run security scans over the codebase: secret and PII detection via gitleaks, plus the
  project's SAST and dependency-vulnerability checks. Use before a PR touching sensitive
  paths, or when CI's Security job fails. Do not use for dependency version and cooldown
  policy (`/deps`), and never use it to confirm a real secret's value — rotate it
  instead, per docs/runbooks/secret-leak.md.
---

# /scan

Run security scans against the codebase.

## Usage

```
/security-scan [target] [--deps] [--code] [--secrets] [--all]
```

## Arguments

- `target`: Specific file or directory (default: entire project)
- `--deps`: Scan dependencies only
- `--code`: Scan code only
- `--secrets`: Scan for secrets only
- `--all`: Run all scans (default)

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Complete all security scans end-to-end
- Categorize findings by severity
- Provide remediation guidance

**Thoroughness:**
- Run all applicable security tools
- Check against OWASP Top 10
- Follow `.claude/rules/security*.md` guidelines

### Scan Process

1. **Read `prd/00_technology.md`** for security tools
2. **Review `.claude/rules/security*.md`** for security standards

3. **Run dependency scan**:
   ```bash
   # Tool depends on your stack (see prd/00_technology.md)
   {dependency_scan_command}
   ```

4. **Run static code analysis**:
   ```bash
   {security_scan_command} src/
   ```

5. **Run secrets and PII detection** (gitleaks):
   ```bash
   # Full repo scan
   scripts/scan-secrets.sh --all

   # Or directly:
   gitleaks detect --config .gitleaks.toml --verbose
   ```

6. **Categorize findings** by severity:
   - **Critical**: Immediate action required
   - **High**: Fix before deployment
   - **Medium**: Address soon
   - **Low**: Review when possible
   - **Info**: Best practice suggestions

7. **Generate report**

### Security Report Format

```markdown
## Security Scan Report

**Scan Date:** {date}
**Overall Score:** {score}/100

---

### Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 3 |
| Info | 5 |

---

### Dependency Vulnerabilities

#### High Severity

1. **CVE-2024-XXXX** in `package@1.2.3`
   - Impact: Remote code execution
   - Fix: Upgrade to 1.2.4+
   - File: package.json:15

---

### Code Security Issues

#### Medium Severity

1. **SQL Injection Risk** (`src/{project}/db/queries:45`)
   ```
   # Issue: String concatenation in query
   query = f"SELECT * FROM users WHERE id = {user_id}"

   # Fix: Use parameterized query
   query = "SELECT * FROM users WHERE id = ?"
   ```

---

### Secrets Detected

#### High Severity

1. **Potential API Key** (`src/{project}/config:23`)
   - Pattern: `API_KEY = "sk-..."`
   - Fix: Move to environment variable

---

### PII Detected

#### High Severity

1. **US Social Security Number** (`src/{project}/utils:78`)
   - Pattern: `ssn = "123-45-6789"`
   - Fix: Remove hardcoded PII, use encrypted storage
2. **Credit Card Number** (`src/{project}/payments:34`)
   - Pattern: `card = "4111-1111-1111-1111"`
   - Fix: Use tokenized payment processing

---

### Recommendations

1. **Immediate**: Upgrade {package} to fix CVE-XXXX
2. **High Priority**: Move hardcoded secrets to .env
3. **Medium Priority**: Fix SQL injection in queries
```

### OWASP Top 10 Checks

From `.claude/rules-available/security-owasp.md`:

| Category | Check |
|----------|-------|
| A01 - Broken Access Control | Auth on all protected routes |
| A02 - Cryptographic Failures | Modern algorithms, no hardcoded secrets |
| A03 - Injection | Parameterized queries, input validation |
| A04 - Insecure Design | Security headers, rate limiting |
| A05 - Security Misconfiguration | No debug in prod, secure defaults |
| A06 - Vulnerable Components | Up-to-date dependencies |
| A07 - Auth Failures | Strong passwords, MFA, session management |
| A08 - Integrity Failures | Safe deserialization, signed packages |
| A09 - Logging Failures | Security event logging |
| A10 - SSRF | URL validation, IP filtering |

## Example Output

```
$ /scan

🔒 Running security scans...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📦 Dependency Scan
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Found 2 vulnerabilities:
  🔴 High: CVE-2024-1234 in requests@2.25.0
  🟡 Medium: CVE-2024-5678 in yaml@5.3.0

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Code Analysis
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Found 1 issue:
  🟡 Medium: Potential SQL injection (src/db/queries:45)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔑 Secrets & PII Detection (gitleaks)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ No secrets or PII detected

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Security Score: 78/100
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Recommendations:
1. Upgrade requests to 2.28.0+
2. Upgrade yaml to 6.0.0+
3. Fix SQL injection in src/db/queries:45
```
