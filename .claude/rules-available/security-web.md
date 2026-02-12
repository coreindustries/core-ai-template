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

Prevent injection of malicious scripts into web pages.

### 1.1 Core Rules

- **NEVER** use `dangerouslySetInnerHTML` with unsanitized input
- **ALWAYS** sanitize user-generated content before rendering
- **ESCAPE** HTML entities in dynamic content
- **USE** Content Security Policy (CSP) headers

### 1.2 React-Specific Patterns

```typescript
// CORRECT: React auto-escapes by default
function SafeComponent({ userInput }: { userInput: string }) {
  return <div>{userInput}</div>; // Auto-escaped
}

// CORRECT: Sanitize when HTML is required
import DOMPurify from 'dompurify';

function SafeHtmlComponent({ html }: { html: string }) {
  const sanitizedHtml = DOMPurify.sanitize(html);
  return <div dangerouslySetInnerHTML={{ __html: sanitizedHtml }} />;
}
```

```typescript
// WRONG: Unsanitized HTML injection
function UnsafeComponent({ userHtml }: { userHtml: string }) {
  return <div dangerouslySetInnerHTML={{ __html: userHtml }} />;
}
```

### 1.3 Content Security Policy

Implement CSP headers to restrict resource loading:

```typescript
// Next.js example - next.config.js
const securityHeaders = [
  {
    key: 'Content-Security-Policy',
    value: `
      default-src 'self';
      script-src 'self' 'unsafe-inline' 'unsafe-eval';
      style-src 'self' 'unsafe-inline';
      img-src 'self' data: https:;
      font-src 'self';
      connect-src 'self' https://api.example.com;
    `.replace(/\n/g, '')
  }
];
```

### 1.4 URL Handling

```typescript
// CORRECT: Validate URLs before use
function SafeLink({ url }: { url: string }) {
  const isValidUrl = url.startsWith('https://') || url.startsWith('/');

  if (!isValidUrl) {
    return null;
  }

  return <a href={url}>Link</a>;
}

// WRONG: Potential javascript: protocol injection
function UnsafeLink({ url }: { url: string }) {
  return <a href={url}>Link</a>; // Could be javascript:alert('xss')
}
```

## 2. CSRF (Cross-Site Request Forgery) Protection

Prevent unauthorized actions from malicious websites.

### 2.1 Core Rules

- **IMPLEMENT** CSRF tokens for state-changing operations
- **USE** SameSite cookie attribute
- **VALIDATE** Origin and Referer headers
- **REQUIRE** re-authentication for sensitive operations

### 2.2 Cookie Configuration

```typescript
// CORRECT: Secure cookie settings
res.cookie('session', sessionId, {
  httpOnly: true,      // Prevent JavaScript access
  secure: true,        // HTTPS only
  sameSite: 'strict',  // Prevent CSRF
  maxAge: 3600000,     // 1 hour
  path: '/'
});
```

### 2.3 CSRF Token Implementation

```typescript
// Server: Generate and validate CSRF token
import crypto from 'crypto';

function generateCsrfToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

function validateCsrfToken(token: string, sessionToken: string): boolean {
  return crypto.timingSafeEqual(
    Buffer.from(token),
    Buffer.from(sessionToken)
  );
}

// Client: Include token in requests
async function submitForm(data: FormData, csrfToken: string) {
  return fetch('/api/submit', {
    method: 'POST',
    headers: {
      'X-CSRF-Token': csrfToken,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(data)
  });
}
```

## 3. SQL Injection Prevention

Prevent malicious SQL execution through user input.

### 3.1 Core Rules

- **ALWAYS** use parameterized queries or prepared statements
- **NEVER** concatenate user input into SQL strings
- **USE** ORMs with proper escaping (Prisma, Drizzle, TypeORM)
- **VALIDATE** and sanitize all input before database operations

### 3.2 Safe Query Patterns

```typescript
// CORRECT: Parameterized query
const result = await db.query(
  'SELECT * FROM users WHERE email = $1 AND status = $2',
  [email, 'active']
);

// CORRECT: Prisma ORM
const user = await prisma.user.findFirst({
  where: {
    email: userEmail,
    status: 'active'
  }
});

// CORRECT: Drizzle ORM
const users = await db.select()
  .from(usersTable)
  .where(eq(usersTable.email, userEmail));
```

```typescript
// WRONG: String interpolation
const result = await db.query(
  `SELECT * FROM users WHERE email = '${email}'`
);

// WRONG: Template literal in query
const result = await db.query(
  `SELECT * FROM users WHERE id = ${userId}`
);
```

## 4. HTTPS and Transport Security

Ensure all data is transmitted securely.

### 4.1 Core Rules

- **ENFORCE** HTTPS for all connections
- **IMPLEMENT** HSTS (HTTP Strict Transport Security)
- **USE** secure cookies only
- **REDIRECT** HTTP to HTTPS

### 4.2 Security Headers

```typescript
// Next.js security headers configuration
const securityHeaders = [
  {
    key: 'Strict-Transport-Security',
    value: 'max-age=63072000; includeSubDomains; preload'
  },
  {
    key: 'X-Frame-Options',
    value: 'DENY'
  },
  {
    key: 'X-Content-Type-Options',
    value: 'nosniff'
  },
  {
    key: 'Referrer-Policy',
    value: 'strict-origin-when-cross-origin'
  },
  {
    key: 'Permissions-Policy',
    value: 'camera=(), microphone=(), geolocation=()'
  }
];

// next.config.js
module.exports = {
  async headers() {
    return [
      {
        source: '/:path*',
        headers: securityHeaders
      }
    ];
  }
};
```

### 4.3 HTTPS Enforcement

```typescript
// Express middleware for HTTPS redirect
function httpsRedirect(req: Request, res: Response, next: NextFunction) {
  if (req.headers['x-forwarded-proto'] !== 'https' && process.env.NODE_ENV === 'production') {
    return res.redirect(301, `https://${req.hostname}${req.url}`);
  }
  next();
}
```

## 5. Rate Limiting

Protect against brute force and denial of service attacks.

### 5.1 Core Rules

- **APPLY** rate limiting to all authentication endpoints
- **IMPLEMENT** exponential backoff for repeated failures
- **USE** different limits for different endpoint types
- **MONITOR** and alert on rate limit violations

### 5.2 Recommended Limits

| Endpoint Type             | Limit | Window     |
|---------------------------|-------|------------|
| Login attempts            | 5     | 15 minutes |
| Password reset            | 3     | 1 hour     |
| API calls (authenticated) | 100   | 1 minute   |
| API calls (anonymous)     | 20    | 1 minute   |
| File uploads              | 10    | 1 hour     |

### 5.3 Implementation

```typescript
// Using express-rate-limit
import rateLimit from 'express-rate-limit';

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5, // 5 attempts
  message: {
    error: 'Too many login attempts. Please try again later.'
  },
  standardHeaders: true,
  legacyHeaders: false
});

app.post('/api/login', loginLimiter, loginHandler);

// API rate limiter
const apiLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 100,
  keyGenerator: (req) => req.user?.id || req.ip
});

app.use('/api/', apiLimiter);
```

### 5.4 Exponential Backoff

```typescript
function calculateBackoff(attempts: number): number {
  const baseDelay = 1000; // 1 second
  const maxDelay = 30000; // 30 seconds
  const delay = Math.min(baseDelay * Math.pow(2, attempts), maxDelay);
  return delay;
}
```

## 6. Authentication Security

Secure user authentication and session management.

### 6.1 Core Rules

- **STORE** tokens in httpOnly cookies (not localStorage)
- **IMPLEMENT** secure session management
- **ENFORCE** strong password requirements
- **USE** secure password hashing (bcrypt, argon2)

### 6.2 Token Storage

| Storage         | Security | Use Case                       |
|-----------------|----------|--------------------------------|
| httpOnly Cookie | High     | Session tokens, refresh tokens |
| Memory (state)  | Medium   | Short-lived access tokens      |
| localStorage    | Low      | Never for auth tokens          |
| sessionStorage  | Low      | Never for auth tokens          |

### 6.3 Secure Authentication Flow

```typescript
// CORRECT: httpOnly cookie for tokens
res.cookie('refreshToken', refreshToken, {
  httpOnly: true,
  secure: process.env.NODE_ENV === 'production',
  sameSite: 'strict',
  maxAge: 7 * 24 * 60 * 60 * 1000, // 7 days
  path: '/api/auth'
});

// Access token in memory only (not persisted)
return res.json({ accessToken }); // Short-lived, stored in app state
```

```typescript
// WRONG: Storing tokens in localStorage
localStorage.setItem('authToken', token);
localStorage.setItem('refreshToken', refreshToken);
```

### 6.4 Password Hashing

```typescript
import bcrypt from 'bcrypt';

// CORRECT: Use bcrypt with sufficient rounds
const SALT_ROUNDS = 12;

async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, SALT_ROUNDS);
}

async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash);
}
```

### 6.5 Logout Security

```typescript
async function logout(req: Request, res: Response) {
  // Invalidate session server-side
  await invalidateSession(req.sessionId);

  // Clear all auth cookies
  res.clearCookie('refreshToken', { path: '/api/auth' });
  res.clearCookie('session');

  return res.json({ success: true });
}
```

## 7. Security Headers Summary

Apply these headers to all responses:

| Header                      | Value                                 | Purpose                   |
|-----------------------------|---------------------------------------|---------------------------|
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains` | Force HTTPS               |
| `X-Frame-Options`           | `DENY`                                | Prevent clickjacking      |
| `X-Content-Type-Options`    | `nosniff`                             | Prevent MIME sniffing     |
| `Referrer-Policy`           | `strict-origin-when-cross-origin`     | Control referrer info     |
| `Content-Security-Policy`   | (see section 1.3)                     | Prevent XSS               |
| `Permissions-Policy`        | `camera=(), microphone=()`            | Restrict browser features |

## 8. CORS Configuration

Configure Cross-Origin Resource Sharing securely.

### 8.1 Rules

- **NEVER** use `origin: '*'` in production
- **WHITELIST** specific trusted origins
- **RESTRICT** allowed methods and headers

### 8.2 Secure CORS Configuration

```typescript
// CORRECT: Specific origins
const corsOptions = {
  origin: [
    'https://app.example.com',
    'https://admin.example.com'
  ],
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
  maxAge: 86400 // 24 hours
};

app.use(cors(corsOptions));
```

```typescript
// WRONG: Allow all origins
app.use(cors({ origin: '*' }));
app.use(cors()); // Defaults to allow all
```

## See Also

- `.claude/rules/security-core.md` - Core security practices (always auto-loaded)
- `.claude/rules-available/security-owasp.md` - OWASP Top 10 and security standards
