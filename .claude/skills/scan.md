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

### Agent Behavior (Codex-Max Pattern)

**Autonomy:**
- Complete all security scans end-to-end
- Categorize findings by severity
- Provide remediation guidance

**Thoroughness:**
- Run all applicable security tools
- Check against OWASP Top 10
- Follow `prd/03_Security.md` guidelines

### Scan Process

1. **Read `prd/02_Tech_stack.md`** for security tools
2. **Read `prd/03_Security.md`** for security standards

3. **Run dependency scan**:
   ```bash
   # Tool depends on your stack (see prd/02_Tech_stack.md)
   {dependency_scan_command}
   ```

4. **Run static code analysis**:
   ```bash
   {security_scan_command} src/
   ```

5. **Run secrets detection**:
   ```bash
   {secrets_scan_command}
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

### Recommendations

1. **Immediate**: Upgrade {package} to fix CVE-XXXX
2. **High Priority**: Move hardcoded secrets to .env
3. **Medium Priority**: Fix SQL injection in queries
```

### OWASP Top 10 Checks

From `prd/03_Security.md`:

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
🔑 Secrets Detection
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ No secrets detected

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Security Score: 78/100
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Recommendations:
1. Upgrade requests to 2.28.0+
2. Upgrade yaml to 6.0.0+
3. Fix SQL injection in src/db/queries:45
```
