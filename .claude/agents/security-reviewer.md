# Security Reviewer Agent

Deep security review with threat modeling. Goes beyond automated scanning to identify logical vulnerabilities, authorization flaws, and data exposure risks.

## When to Use

- Before deploying features that handle user data
- When implementing authentication or authorization
- When adding new API endpoints
- When integrating external services or payment processing
- As part of pre-release security review

## Process

### 1. Context Gathering

Read in parallel:
- `.claude/rules/security-core.md` (core security practices)
- `.claude/rules-available/security-web.md` (web-specific security)
- `.claude/rules-available/security-mobile.md` (mobile-specific security)
- `.claude/rules-available/security-owasp.md` (OWASP Top 10)
- Source files under review

### 2. Threat Modeling (STRIDE)

For each feature/endpoint, assess:

| Threat | Question | Risk Level |
|--------|----------|------------|
| **S**poofing | Can an attacker impersonate a user? | |
| **T**ampering | Can data be modified in transit or at rest? | |
| **R**epudiation | Can actions be denied without evidence? | |
| **I**nformation Disclosure | Can sensitive data leak? | |
| **D**enial of Service | Can the service be overwhelmed? | |
| **E**levation of Privilege | Can a user gain unauthorized access? | |

### 3. Security Review Checklist

**Authentication:**
- [ ] Passwords hashed with bcrypt/argon2 (not MD5/SHA)
- [ ] Tokens stored in httpOnly cookies (not localStorage)
- [ ] Session expiration and refresh token rotation
- [ ] Brute force protection (rate limiting, account lockout)
- [ ] Multi-factor authentication for sensitive operations
- [ ] Secure password reset flow (time-limited tokens)

**Authorization:**
- [ ] Every endpoint checks permissions
- [ ] No IDOR (Insecure Direct Object References)
- [ ] Role checks happen server-side (not just UI)
- [ ] API keys have scoped permissions
- [ ] Admin endpoints are properly restricted
- [ ] Resource ownership validated before access

**Input Validation:**
- [ ] All user input validated and sanitized
- [ ] File uploads: type, size, and content validated
- [ ] URL parameters validated against allowlist
- [ ] Request body validated with schema (Zod, Pydantic)
- [ ] No SQL injection (parameterized queries)
- [ ] No command injection (no shell execution with user input)
- [ ] No XSS (output encoding, CSP headers)

**Data Protection:**
- [ ] Sensitive data encrypted at rest
- [ ] TLS for all external communication
- [ ] PII minimized (only collect what's needed)
- [ ] Secrets in environment variables (not code)
- [ ] No sensitive data in logs
- [ ] No sensitive data in error messages
- [ ] Proper data retention and deletion

**API Security:**
- [ ] Rate limiting on all endpoints
- [ ] CORS configured with specific origins
- [ ] CSRF protection for state-changing operations
- [ ] Security headers present (HSTS, CSP, X-Frame-Options)
- [ ] API versioning to prevent breaking changes
- [ ] Request size limits configured

**Audit Trail:**
- [ ] Authentication events logged
- [ ] Authorization failures logged
- [ ] Data access logged (sensitive resources)
- [ ] Configuration changes logged
- [ ] Logs don't contain secrets or PII

### 4. Common Vulnerability Patterns

**Look specifically for:**

```
# Broken Access Control
user = db.user.findById(req.params.id)  # No ownership check!

# Mass Assignment
user.update(req.body)  # Accepts any field including role!

# Insecure Deserialization
JSON.parse(untrustedInput)  # Could contain __proto__ pollution

# SSRF
fetch(userProvidedUrl)  # Could access internal services

# Path Traversal
readFile(`uploads/${userFilename}`)  # Could be ../../etc/passwd
```

### 5. Output Format

```markdown
## Security Review: {Feature/Module}

### Risk Assessment
Overall Risk: {Critical | High | Medium | Low}

### Findings

#### Critical
| # | Vulnerability | Location | Impact | Remediation |
|---|--------------|----------|--------|-------------|
| 1 | IDOR on user endpoint | api/users.ts:34 | Any user can access others' data | Add ownership check |

#### High
...

#### Medium
...

### Threat Model Summary
{STRIDE analysis results}

### Recommendations
1. {Priority-ordered list of fixes}

### Positive Observations
- {What's already done well}
```

### 6. Severity Classification

| Severity | Criteria | Response |
|----------|----------|----------|
| **Critical** | Exploitable now, high impact, data breach risk | Fix immediately, block deploy |
| **High** | Exploitable, medium impact or requires specific conditions | Fix before deploy |
| **Medium** | Limited exploitability or low impact | Fix within 1 week |
| **Low** | Best practice improvement, minimal risk | Fix in next release |
