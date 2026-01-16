---
prd_version: "1.0"
status: "Active"
last_updated: "2026-01-15"
---

# 03 – Security Standards

## 1. Purpose

Implement comprehensive security scanning and code review capabilities to identify vulnerabilities in dependencies, detect OWASP Top 10 security violations, and enforce security best practices.

**Key capabilities:**
- Automated vulnerability scanning for dependencies
- Static code analysis for OWASP Top 10 security violations
- Security best practices enforcement and reporting
- Integration with CI/CD pipelines for continuous security monitoring

## 2. Goals

- **Dependency Security**: Identify known vulnerabilities in all third-party dependencies
- **Code Security**: Detect common security vulnerabilities (SQL injection, XSS, insecure deserialization, etc.)
- **Best Practices**: Enforce security coding standards
- **Compliance**: Ensure adherence to OWASP security guidelines
- **Automation**: Integrate security checks into development workflow

## 3. Key Concepts

- **Vulnerability Scan** – Automated check against known vulnerability databases (CVE, GitHub Advisory, OSV)
- **Security Issue** – Detected vulnerability or security violation
- **Security Report** – Aggregated scan results
- **Remediation** – Action to fix or mitigate a security issue
- **Security Score** – Quantitative measure (0-100)

## 4. OWASP Top 10 Detection

### 4.1 A01:2021 – Broken Access Control

**Best Practices:**
- Implement authorization middleware/decorators for route protection
- Validate user permissions before data access
- Use parameterized queries with user context validation
- Avoid exposing internal IDs or direct object references

**Detection:**
- Missing authentication/authorization checks
- Insecure direct object references (IDOR)
- Missing function-level access control
- Privilege escalation vulnerabilities

### 4.2 A02:2021 – Cryptographic Failures

**Best Practices:**
- Use modern cryptography libraries for encryption
- Use cryptographically secure random number generation
- Use bcrypt or argon2 for password hashing (never MD5/SHA1)
- Store secrets in environment variables or secret management systems
- Use TLS 1.2+ for all external communications
- Encrypt sensitive data at rest

**Detection:**
- Use of weak encryption algorithms (DES, MD5, SHA1, RC4)
- Hardcoded secrets and credentials
- Insecure random number generation
- Missing HTTPS/TLS enforcement
- Plaintext storage of sensitive data

### 4.3 A03:2021 – Injection

**Best Practices:**
- Use parameterized queries with ORMs
- Use prepared statements for raw SQL
- Validate and sanitize all user inputs
- Use input validation libraries
- Escape shell commands or use safe execution methods
- Use query builders that prevent injection

**Detection:**
- SQL injection (string concatenation in queries)
- Command injection (unsafe shell execution)
- NoSQL injection
- Template injection
- LDAP/XPath injection

### 4.4 A04:2021 – Insecure Design

**Best Practices:**
- Implement security by design principles
- Use secure defaults in frameworks
- Implement comprehensive input validation at API boundaries
- Implement rate limiting and throttling
- Design with least privilege principle

**Detection:**
- Missing security controls in design
- Insecure default configurations
- Missing input validation
- Missing rate limiting
- Missing request size limits

### 4.5 A05:2021 – Security Misconfiguration

**Best Practices:**
- Remove default credentials
- Configure security headers
- Exclude sensitive files from version control
- Use environment-specific configurations
- Disable debug mode in production
- Configure CORS properly

**Detection:**
- Default credentials in code
- Missing security headers (CSP, X-Frame-Options, HSTS)
- Exposed sensitive files (`.env`, `.git`, credentials)
- Insecure CORS (`Access-Control-Allow-Origin: *`)
- Debug mode enabled in production
- Verbose error messages

### 4.6 A06:2021 – Vulnerable and Outdated Components

**Best Practices:**
- Regularly scan dependencies for vulnerabilities
- Keep frameworks and libraries updated
- Remove unused dependencies
- Use lock files for reproducible builds

**Detection:**
- Known CVEs in dependencies
- Outdated packages with security patches available
- Abandoned or unmaintained packages

### 4.7 A07:2021 – Identification and Authentication Failures

**Best Practices:**
- Enforce strong password policies
- Implement password strength validation
- Use secure session management
- Implement multi-factor authentication (MFA)
- Protect against brute force (rate limiting, account lockout)
- Use secure password reset flows
- Use JWT with short expiration times and refresh tokens

**Detection:**
- Weak password policies
- Session fixation vulnerabilities
- Missing MFA
- Insecure session management
- Missing brute force protection
- Insecure password reset flows

### 4.8 A08:2021 – Software and Data Integrity Failures

**Best Practices:**
- Avoid insecure deserialization (use JSON, avoid language-specific serialization)
- Validate data integrity with checksums or signatures
- Use dependency pinning and lock files
- Verify package signatures
- Implement CI/CD pipeline security

**Detection:**
- Insecure deserialization
- Missing integrity checks
- Insecure CI/CD pipelines
- Missing dependency verification

### 4.9 A09:2021 – Security Logging and Monitoring Failures

**Best Practices:**
- Log all authentication attempts
- Log authorization failures
- Log security-relevant events
- Implement log monitoring and alerting
- Use structured logging
- Protect log files from unauthorized access
- Implement log retention policies

**Detection:**
- Missing security event logging
- Insufficient log monitoring
- Missing alerting
- Unprotected logs
- Missing retention policies

### 4.10 A10:2021 – Server-Side Request Forgery (SSRF)

**Best Practices:**
- Validate and whitelist allowed URLs/domains
- Use URL parsing libraries
- Block access to private/internal IP ranges
- Use outbound proxy with restrictions
- Implement request timeouts
- Validate response content types

**Detection:**
- Unvalidated user-controlled URLs
- Missing URL validation
- Insecure internal network access
- Missing IP address filtering

## 5. Security Best Practices

### 5.1 Secrets Management

**Best Practices:**
- Use environment variables or secret management services
- Never commit `.env` files or hardcode secrets
- Rotate secrets regularly
- Use different secrets for different environments

**Detection:**
- Hardcoded API keys, passwords, tokens
- Secrets in version control
- Common secret patterns

### 5.2 Input Validation

**Best Practices:**
- Use validation libraries
- Validate all user inputs at API boundaries
- Sanitize inputs before processing
- Use parameterized queries
- Validate file uploads (type, size, content)

**Detection:**
- Missing input sanitization
- Insufficient validation
- Missing output encoding
- Direct use of user input

### 5.3 Error Handling

**Best Practices:**
- Log errors with appropriate detail
- Don't expose stack traces to end users
- Use generic error messages for users
- Log security-relevant errors

**Detection:**
- Information disclosure in errors
- Stack traces exposed
- Missing error logging
- Verbose error messages

### 5.4 Authentication & Authorization

**Best Practices:**
- Use established authentication libraries
- Enforce strong password policies
- Implement rate limiting for login attempts
- Use secure session management
- Implement CSRF protection
- Implement MFA

**Detection:**
- Weak password requirements
- Missing rate limiting
- Insecure session management
- Missing CSRF protection

### 5.5 Data Protection

**Best Practices:**
- Encrypt sensitive data at rest
- Use secure data storage
- Implement data retention policies
- Use secure data transmission (TLS/SSL)
- Implement data masking for logs

**Detection:**
- Missing encryption
- Insecure data storage
- Missing retention policies
- Plaintext sensitive information

### 5.6 API Security

**Best Practices:**
- Implement API authentication
- Use rate limiting
- Validate all API requests
- Use HTTPS for all endpoints
- Implement proper CORS policies

**Detection:**
- Missing API authentication
- Insufficient rate limiting
- Missing request validation
- HTTP instead of HTTPS
- Overly permissive CORS

## 6. Security Scanning Tools

### 6.1 Dependency Scanning

**Tools by ecosystem:**
- **Python**: Safety, pip-audit, OSV
- **Node.js**: npm audit, yarn audit, Snyk
- **Go**: govulncheck, nancy
- **Ruby**: bundler-audit
- **General**: Dependabot, Snyk, OWASP Dependency-Check

### 6.2 Static Analysis

**Tools by ecosystem:**
- **Python**: Bandit, Semgrep
- **Node.js**: ESLint security plugins, Semgrep
- **Go**: gosec, staticcheck
- **General**: Semgrep, SonarQube, CodeQL

### 6.3 Secrets Detection

**Tools (language-agnostic):**
- detect-secrets
- gitleaks
- truffleHog
- git-secrets

## 7. CI/CD Integration

**REQUIRED:** Integrate security scans into pipelines:
- Run dependency scans on every build
- Run code security scans on pull requests
- Block deployments if critical vulnerabilities found (configurable)
- Generate security reports as artifacts

**Example pipeline stages:**
1. Lint and type check
2. Run tests
3. Dependency vulnerability scan
4. Static security analysis
5. Build
6. Deploy

## 8. Security Configuration

### 8.1 Environment Variables

```bash
# Scanner Configuration
SECURITY_SCANNER_ENABLED=true
SECURITY_SCAN_ON_BUILD=true

# Blocking Configuration
SECURITY_BLOCK_ON_CRITICAL=true
SECURITY_BLOCK_ON_HIGH=false
SECURITY_FAIL_SCORE_THRESHOLD=70
```

### 8.2 Recommended Security Headers

| Header | Value | Purpose |
|--------|-------|---------|
| `Content-Security-Policy` | `default-src 'self'` | Prevent XSS |
| `X-Content-Type-Options` | `nosniff` | Prevent MIME sniffing |
| `X-Frame-Options` | `DENY` | Prevent clickjacking |
| `Strict-Transport-Security` | `max-age=31536000` | Enforce HTTPS |
| `X-XSS-Protection` | `1; mode=block` | XSS filter |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Control referrer |

## 9. Audit Logging

### 9.1 Required Events

| Event Type | When to Log |
|------------|-------------|
| `AUTH_SUCCESS` | Successful authentication |
| `AUTH_FAILURE` | Failed authentication |
| `AUTH_LOGOUT` | User logout |
| `ACCESS_DENIED` | Authorization failure |
| `DATA_CREATE` | Sensitive data creation |
| `DATA_READ` | Sensitive data access |
| `DATA_UPDATE` | Sensitive data modification |
| `DATA_DELETE` | Sensitive data deletion |
| `CONFIG_CHANGE` | Configuration modification |
| `SECURITY_EVENT` | Security-relevant events |

### 9.2 Log Fields

| Field | Description |
|-------|-------------|
| `timestamp` | ISO 8601 timestamp |
| `event_type` | Type of event |
| `user_id` | User identifier |
| `ip_address` | Client IP |
| `resource_type` | Type of resource accessed |
| `resource_id` | ID of resource |
| `action` | Action performed |
| `status` | Success/failure |
| `details` | Additional context |

## 10. Security Severity Levels

| Level | Description | Response Time |
|-------|-------------|---------------|
| **Critical** | Exploitable, high impact | Immediate |
| **High** | Exploitable, medium impact | 24 hours |
| **Medium** | Limited exploitability | 1 week |
| **Low** | Minimal risk | Next release |
| **Info** | Best practice suggestion | Backlog |

## 11. Pre-Commit Security Checklist

Before committing code, verify:
- [ ] No hardcoded secrets
- [ ] All user inputs validated
- [ ] SQL queries parameterized
- [ ] Error messages don't leak information
- [ ] Sensitive data encrypted
- [ ] Authentication/authorization in place
- [ ] Security logging implemented
- [ ] Dependency scan passed
- [ ] Static analysis passed

## 12. References

**Standards:**
- OWASP Top 10: https://owasp.org/Top10/
- OWASP ASVS: https://owasp.org/www-project-application-security-verification-standard/
- CWE Top 25: https://cwe.mitre.org/top25/

**Tools:**
- Semgrep: https://semgrep.dev/
- Snyk: https://snyk.io/
- OWASP ZAP: https://www.zaproxy.org/
