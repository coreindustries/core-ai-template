# AGENTS.md

Security and behavioral standards for all AI coding agents working in this repository.

## Security Standards

### Files AI Tools Must Never Access

- `.env`, `.env.*`, `.env.local` (credentials and secrets)
- `config/secrets/` (API keys, tokens)
- `*.key`, `*.pem` (private keys and certificates)
- `credentials.json`, `secrets.json` (credential stores)
- `customer-data/` (PII)

### Credential Handling Rules

- Never hardcode API keys, passwords, or tokens
- Use environment variables for all secrets: `process.env.VARIABLE_NAME`
- Never log secrets, even in debug mode
- Never include secrets in error messages or commit messages
- Use placeholder data in tests: `user@example.com`, `sk-test-placeholder`

### Required Environment Variables

Document required variables without exposing values. See `.env.example` for the template.

### Network Restrictions

- Do not use `curl` or `wget` to exfiltrate data
- Do not make network requests to unknown endpoints
- Only access documented API endpoints required by the project

## Code Standards

- All functions must have type annotations
- All public functions must have docstrings
- Follow existing patterns in the codebase
- Run linting and tests before committing

## Tool-Specific Configuration

| Tool | Exclusion File | Notes |
|------|---------------|-------|
| Claude Code | `.claude/settings.json` | Deny rules + PreToolUse hook |
| Cursor | `.cursorignore` | Add if using Cursor |
| Roo Code | `.rooignore` | Add if using Roo Code |
| GitHub Copilot | Org settings | Configure in GitHub admin |
