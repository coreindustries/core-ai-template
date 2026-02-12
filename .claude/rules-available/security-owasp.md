# Security Rules

**Scope:** Security standards (OWASP Top 10, best practices, audit logging)

## OWASP Top 10 Requirements

### A01: Broken Access Control
- Implement authorization middleware/decorators for route protection
- Validate user permissions before data access
- Use parameterized queries with user context validation
- Avoid exposing internal IDs or direct object references

### A02: Cryptographic Failures
- Use modern cryptography libraries for encryption
- Use cryptographically secure random number generation
- Use bcrypt or argon2 for password hashing (never MD5/SHA1)
- Store secrets in environment variables or secret management systems
- Use TLS 1.2+ for all external communications
- Encrypt sensitive data at rest

### A03: Injection
- Use parameterized queries with ORMs
- Use prepared statements for raw SQL
- Validate and sanitize all user inputs
- Use input validation libraries
- Escape shell commands or use safe execution methods

### A04: Insecure Design
- Implement security by design principles
- Use secure defaults in frameworks
- Implement comprehensive input validation at API boundaries
- Implement rate limiting and throttling
- Design with least privilege principle

### A05: Security Misconfiguration
- Remove default credentials
- Configure security headers
- Exclude sensitive files from version control
- Use environment-specific configurations
- Disable debug mode in production
- Configure CORS properly

### A06: Vulnerable and Outdated Components
- Regularly scan dependencies for vulnerabilities
- Keep frameworks and libraries updated
- Remove unused dependencies
- Use lock files for reproducible builds

### A07: Identification and Authentication Failures
- Enforce strong password policies
- Implement password strength validation
- Use secure session management
- Implement multi-factor authentication (MFA)
- Protect against brute force (rate limiting, account lockout)
- Use secure password reset flows
- Use JWT with short expiration times and refresh tokens

### A08: Software and Data Integrity Failures
- Avoid insecure deserialization (use JSON, avoid language-specific serialization)
- Validate data integrity with checksums or signatures
- Use dependency pinning and lock files
- Verify package signatures
- Implement CI/CD pipeline security

### A09: Security Logging and Monitoring Failures
- Log all authentication attempts
- Log authorization failures
- Log security-relevant events
- Implement log monitoring and alerting
- Use structured logging
- Protect log files from unauthorized access
- Implement log retention policies

### A10: Server-Side Request Forgery (SSRF)
- Validate and whitelist allowed URLs/domains
- Use URL parsing libraries
- Block access to private/internal IP ranges
- Use outbound proxy with restrictions
- Implement request timeouts
- Validate response content types

## Security Best Practices

### Secrets Management
- Use environment variables or secret management services
- Never commit `.env` files or hardcode secrets
- Rotate secrets regularly
- Use different secrets for different environments

### Input Validation
- Use validation libraries
- Validate all user inputs at API boundaries
- Sanitize inputs before processing
- Use parameterized queries
- Validate file uploads (type, size, content)

### Error Handling
- Log errors with appropriate detail
- Don't expose stack traces to end users
- Use generic error messages for users
- Log security-relevant errors

### Authentication & Authorization
- Use established authentication libraries
- Enforce strong password policies
- Implement rate limiting for login attempts
- Use secure session management
- Implement CSRF protection
- Implement MFA

### Data Protection
- Encrypt sensitive data at rest
- Use secure data storage
- Implement data retention policies
- Use secure data transmission (TLS/SSL)
- Implement data masking for logs

### API Security
- Implement API authentication
- Use rate limiting
- Validate all API requests
- Use HTTPS for all endpoints
- Implement proper CORS policies

## Audit Logging

**Required Events:**
- `AUTH_SUCCESS` - Successful authentication
- `AUTH_FAILURE` - Failed authentication
- `AUTH_LOGOUT` - User logout
- `ACCESS_DENIED` - Authorization failure
- `DATA_CREATE` - Sensitive data creation
- `DATA_READ` - Sensitive data access
- `DATA_UPDATE` - Sensitive data modification
- `DATA_DELETE` - Sensitive data deletion
- `CONFIG_CHANGE` - Configuration modification
- `SECURITY_EVENT` - Security-relevant events

**Log Fields:**
- `timestamp` - ISO 8601 timestamp
- `event_type` - Type of event
- `user_id` - User identifier
- `ip_address` - Client IP
- `resource_type` - Type of resource accessed
- `resource_id` - ID of resource
- `action` - Action performed
- `status` - Success/failure
- `details` - Additional context

## Pre-Commit Security Checklist

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

## Security Severity Levels

| Level | Description | Response Time |
|-------|-------------|---------------|
| **Critical** | Exploitable, high impact | Immediate |
| **High** | Exploitable, medium impact | 24 hours |
| **Medium** | Limited exploitability | 1 week |
| **Low** | Minimal risk | Next release |
| **Info** | Best practice suggestion | Backlog |
