# Core Security Rules

Applies to ALL development regardless of platform. Tables, code samples and checklists: `.claude/references/security-core-detail.md`.

## 1. Secrets

- **NEVER** commit secrets (API keys, credentials, tokens, encryption keys, URLs with embedded auth). Use environment variables or secret managers (see `secrets-hygiene.md`).
- Never log secrets, put them in error messages, or pass them in URL query parameters.
- `.env*`, `*.pem`, `*.key`, `secrets/` must be gitignored.

## 2. Auto-Run Prevention

Turn OFF auto-run for AI-generated code; review before execution; allow-list trusted scripts; sandbox untrusted code. Prohibited: `eval()`, `new Function()`, `child_process.exec()` with user input, `dangerouslySetInnerHTML` with unsanitized input.

## 3. Database Safety

- Always use parameterized queries or an ORM; never string-interpolate SQL.
- `DROP TABLE` needs approval + verified backup; `DROP DATABASE` never in application code; `TRUNCATE` needs explicit confirmation; `DELETE`/`UPDATE` must have a `WHERE`.
- Migrations: preview/dry-run first, reversible (rollback script), tested on a copy of production data, staged before production.

## 4. Dependencies

- Audit (`npm audit` / `yarn audit` / `pnpm audit`) on every PR and weekly; pin exact versions for production; review changelogs before updating; replace deprecated packages; always commit lock files.
- Before adding one: check maintenance and open security issues, verify source/maintainers, assess tree size, consider doing without it.

## 5. Errors and Logging

- Never expose stack traces or sensitive data to users; return a generic message plus a request ID, log details server-side.
- Sanitized structured logs; never log passwords, tokens, API keys, full card numbers, or unmasked PII. Fail to a secure state.

## 6. Pre-Commit Security Checklist

- [ ] No hardcoded secrets; secrets from env/secret store; `.env` gitignored
- [ ] User input validated and sanitized; no SQL or command injection
- [ ] Sensitive data encrypted at rest and in transit; PII handled per privacy requirements; access controls in place
- [ ] Errors and logs expose no secrets or PII; app fails safely
- [ ] New dependencies vetted; no known vulnerabilities; lock files committed

## 7. AI-Assisted Development

Review all generated code before committing; verify security patterns; test edge cases the AI may not consider; don't trust AI-generated secrets or example credentials. Watch for placeholder secrets committed as-is, insecure defaults (`cors({ origin: '*' })`), missing validation, deprecated security libraries.

## See Also

`rules-available/security-owasp.md`, `security-web.md`, `security-mobile.md` (symlink into `rules/` during project setup to auto-load).
