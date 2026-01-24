# Web Security Rules

**These rules apply to web applications** including React, Next.js, and any browser-based applications. Follow these practices to protect against common web vulnerabilities.

## Quick Reference

- **XSS Prevention**: Never use `dangerouslySetInnerHTML` with unsanitized input, use CSP headers
- **CSRF Protection**: Implement CSRF tokens, use SameSite cookies, validate Origin/Referer
- **SQL Injection**: Always use parameterized queries or ORMs, never string interpolation
- **HTTPS**: Enforce HTTPS, implement HSTS, use secure cookies only
- **Rate Limiting**: Apply to auth endpoints (5 attempts/15min), API endpoints (100/min authenticated)
- **Authentication**: Store tokens in httpOnly cookies, never localStorage, use bcrypt/argon2
- **Security Headers**: HSTS, X-Frame-Options, CSP, X-Content-Type-Options, Referrer-Policy
- **CORS**: Never use `origin: '*'` in production, whitelist specific origins

## 1. XSS (Cross-Site Scripting) Prevention

**NEVER** use `dangerouslySetInnerHTML` with unsanitized input.

### React Patterns

```typescript
// CORRECT: React auto-escapes by default
function SafeComponent({ userInput }: { userInput: string }) {
  return <div>{userInput}</div>; // Auto-escaped
}

// CORRECT: Sanitize when HTML is required
import DOMPurify from 'dompurify';
const sanitizedHtml = DOMPurify.sanitize(html);
return <div dangerouslySetInnerHTML={{ __html: sanitizedHtml }} />;

// WRONG: Unsanitized HTML injection
return <div dangerouslySetInnerHTML={{ __html: userHtml }} />;
```

### Content Security Policy

```typescript
// Next.js - next.config.js
const securityHeaders = [{
  key: 'Content-Security-Policy',
  value: `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';`
}];
```

## 2. CSRF (Cross-Site Request Forgery) Protection

**IMPLEMENT** CSRF tokens for state-changing operations.

### Cookie Configuration

```typescript
res.cookie('session', sessionId, {
  httpOnly: true,
  secure: true,
  sameSite: 'strict', // Prevent CSRF
  maxAge: 3600000
});
```

### CSRF Token

```typescript
// Server: Generate token
const csrfToken = crypto.randomBytes(32).toString('hex');

// Client: Include in requests
fetch('/api/submit', {
  headers: { 'X-CSRF-Token': csrfToken }
});
```

## 3. SQL Injection Prevention

**ALWAYS** use parameterized queries or ORMs.

```typescript
// CORRECT: Parameterized query
await db.query('SELECT * FROM users WHERE email = $1', [email]);

// CORRECT: Prisma ORM
await prisma.user.findFirst({ where: { email: userEmail } });

// WRONG: String interpolation
await db.query(`SELECT * FROM users WHERE email = '${email}'`);
```

## 4. HTTPS and Transport Security

**ENFORCE** HTTPS for all connections, implement HSTS.

### Security Headers

```typescript
const securityHeaders = [
  { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains' },
  { key: 'X-Frame-Options', value: 'DENY' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' }
];
```

## 5. Rate Limiting

**APPLY** rate limiting to authentication endpoints.

### Recommended Limits

| Endpoint Type | Limit | Window |
|--------------|-------|--------|
| Login attempts | 5 | 15 minutes |
| Password reset | 3 | 1 hour |
| API calls (authenticated) | 100 | 1 minute |
| API calls (anonymous) | 20 | 1 minute |

### Implementation

```typescript
import rateLimit from 'express-rate-limit';

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  message: { error: 'Too many login attempts' }
});

app.post('/api/login', loginLimiter, loginHandler);
```

## 6. Authentication Security

**STORE** tokens in httpOnly cookies, never localStorage.

### Token Storage

| Storage | Security | Use Case |
|---------|----------|----------|
| httpOnly Cookie | High | Session tokens, refresh tokens |
| Memory (state) | Medium | Short-lived access tokens |
| localStorage | Low | Never for auth tokens |

### Secure Flow

```typescript
// CORRECT: httpOnly cookie
res.cookie('refreshToken', refreshToken, {
  httpOnly: true,
  secure: true,
  sameSite: 'strict',
  maxAge: 7 * 24 * 60 * 60 * 1000
});

// WRONG: localStorage
localStorage.setItem('authToken', token);
```

### Password Hashing

```typescript
import bcrypt from 'bcrypt';

const SALT_ROUNDS = 12;
const hash = await bcrypt.hash(password, SALT_ROUNDS);
const isValid = await bcrypt.compare(password, hash);
```

## 7. Security Headers Summary

| Header | Value | Purpose |
|--------|-------|---------|
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains` | Force HTTPS |
| `X-Frame-Options` | `DENY` | Prevent clickjacking |
| `X-Content-Type-Options` | `nosniff` | Prevent MIME sniffing |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Control referrer |
| `Content-Security-Policy` | (see CSP section) | Prevent XSS |
| `Permissions-Policy` | `camera=(), microphone=()` | Restrict features |

## 8. CORS Configuration

**NEVER** use `origin: '*'` in production.

### Secure CORS

```typescript
// CORRECT: Specific origins
const corsOptions = {
  origin: ['https://app.example.com', 'https://admin.example.com'],
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  credentials: true
};

app.use(cors(corsOptions));

// WRONG: Allow all origins
app.use(cors({ origin: '*' }));
```

## See Also

- `.claude/rules/security-core.md` - Core security practices (always applies)
- `.claude/rules/security.md` - Platform-specific security rules (OWASP Top 10)
- `.cursor/rules/security-web.mdc` - Full rule with comprehensive examples
