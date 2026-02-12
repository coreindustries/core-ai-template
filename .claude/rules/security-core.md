# Core Security Rules

**These rules apply to ALL development** regardless of platform (web, mobile, backend). Security is not optional—these practices must be followed in every codebase.

## Quick Reference

- **Secrets**: Never hardcode, always use environment variables or secret managers
- **Auto-Run**: Turn OFF auto-run for AI-generated code, review before execution
- **Database**: Never DROP without approval, always use parameterized queries
- **Dependencies**: Audit regularly, pin versions, review before adding
- **Errors**: Never expose stack traces or sensitive data to users
- **AI Code**: Review all generated code, verify security patterns

## 1. Secrets Management

**NEVER** commit secrets to version control.

### What Constitutes a Secret

- API Keys (Stripe, Twilio, AWS, etc.)
- Credentials (database passwords, OAuth secrets)
- Tokens (JWT signing keys, access tokens)
- Encryption Keys (AES, RSA private keys, certificates)
- Service URLs with embedded auth

### Rules

- Use environment variables or secret managers
- Never log secrets, even in debug mode
- Never include secrets in error messages
- Never pass secrets via URL query parameters

### Storage Methods

| Environment | Method |
|-------------|--------|
| Local Dev | `.env` files (must be in `.gitignore`) |
| CI/CD | Pipeline secrets (GitHub Secrets, GitLab CI Variables) |
| Production | Secret managers (AWS Secrets Manager, HashiCorp Vault) |
| Containers | Mounted secrets, environment injection |

### .gitignore Requirements

```
.env
.env.local
.env.*.local
*.pem
*.key
secrets/
```

## 2. Auto-Run Prevention

**Turn OFF** auto-run for AI-generated code snippets.

### Rules

- Use allow-lists for trusted scripts
- Review all generated code before execution
- Sandbox untrusted code execution

### Prohibited Patterns

- `eval()` - Arbitrary code execution
- `new Function()` - Dynamic code creation
- `child_process.exec()` with user input - Command injection
- `dangerouslySetInnerHTML` with unsanitized input - XSS

## 3. Database Safety

Protect database integrity and prevent data loss.

### Prohibited Operations (Without Approval)

| Operation | Risk | Requirement |
|-----------|------|-------------|
| `DROP TABLE` | Critical | Team lead approval + backup verification |
| `DROP DATABASE` | Critical | Never in application code |
| `TRUNCATE` | High | Explicit confirmation required |
| `DELETE` without `WHERE` | High | Must have WHERE clause |
| `UPDATE` without `WHERE` | High | Must have WHERE clause |

### Migration Rules

- Preview only: Run migrations in preview/dry-run mode first
- Reversible: All migrations must have rollback scripts
- Tested: Test on copy of production data
- Staged: Apply to staging before production

### Query Safety

```typescript
// CORRECT: Parameterized query
const user = await db.query('SELECT * FROM users WHERE id = $1', [userId]);

// CORRECT: ORM with type safety
const user = await prisma.user.findUnique({ where: { id: userId } });

// WRONG: String interpolation (SQL injection risk)
const user = await db.query(`SELECT * FROM users WHERE id = ${userId}`);
```

## 4. Dependency Security

Maintain secure and up-to-date dependencies.

### Rules

- Audit regularly: Run security audits on every PR and weekly
- Pin versions: Use exact versions, not ranges, for production
- Review changes: Check changelogs before updating
- Avoid deprecated: Replace deprecated packages promptly

### Audit Commands

```bash
npm audit && npm audit fix
yarn audit
pnpm audit
```

### Lock Files

Always commit lock files: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`

### Dependency Review Checklist

Before adding a new dependency:
- [ ] Check download count and maintenance status
- [ ] Review open security issues
- [ ] Verify package source and maintainers
- [ ] Assess dependency tree size
- [ ] Consider if functionality can be implemented without dependency

## 5. Error Handling

Handle errors securely without leaking sensitive information.

### Rules

- Never expose stack traces to end users
- Never include sensitive data in error messages
- Log securely: Sanitize logs, use structured logging
- Fail safely: Default to secure state on errors

### Error Response Patterns

```typescript
// CORRECT: Generic user-facing error
function handleError(error: Error, res: Response) {
  logger.error('Request failed', { error: error.message, stack: error.stack, requestId: req.id });
  res.status(500).json({ error: 'An unexpected error occurred', requestId: req.id });
}

// WRONG: Exposing internal details
res.status(500).json({ error: error.message, stack: error.stack, query: sqlQuery });
```

### Logging Security

| Do | Don't |
|----|-------|
| Log request IDs for tracing | Log passwords or tokens |
| Log sanitized user identifiers | Log full credit card numbers |
| Log error types and codes | Log API keys or secrets |
| Use structured logging (JSON) | Log PII without masking |

## 6. Security Code Review Checklist

Before committing code, verify:

### Secrets
- [ ] No hardcoded secrets, API keys, or credentials
- [ ] Secrets loaded from environment variables or secret stores
- [ ] `.env` files are gitignored

### Input Handling
- [ ] All user input is validated and sanitized
- [ ] No SQL injection vulnerabilities
- [ ] No command injection vulnerabilities

### Data Protection
- [ ] Sensitive data is encrypted at rest and in transit
- [ ] PII is handled according to privacy requirements
- [ ] Proper access controls are in place

### Error Handling
- [ ] Errors don't expose sensitive information
- [ ] Logging doesn't include secrets or PII
- [ ] Application fails safely to a secure state

### Dependencies
- [ ] New dependencies are vetted for security
- [ ] No known vulnerabilities in dependencies
- [ ] Lock files are committed

## 7. AI-Assisted Development

When generating code with AI assistance:

### Rules

- Review all generated code before committing
- Verify security patterns are correctly implemented
- Test edge cases that AI may not consider
- Don't trust AI-generated secrets or example credentials

### Common AI Security Pitfalls

| Issue | Example |
|-------|---------|
| Placeholder secrets | `apiKey = "your-api-key-here"` committed as-is |
| Insecure defaults | `cors({ origin: '*' })` |
| Missing validation | No input sanitization on user data |
| Outdated patterns | Using deprecated security libraries |

## See Also

- `.claude/rules-available/security-owasp.md` - OWASP Top 10 and audit logging
- `.claude/rules-available/security-web.md` - Web-specific security (XSS, CSRF, etc.)
- `.claude/rules-available/security-mobile.md` - Mobile-specific security (React Native)

**Note:** Platform-specific security rules are in `rules-available/` and must be symlinked into `rules/` during project setup to be auto-loaded.
