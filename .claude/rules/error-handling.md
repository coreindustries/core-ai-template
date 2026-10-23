# Error Handling Rules

**Scope:** Error handling patterns. Examples, checklist and ratchet details: `.claude/references/error-handling-detail.md`.

## Rules

- Use specific exception/error types, not broad catches; create custom exceptions for domain errors.
- Always include context in error messages.
- Never swallow exceptions silently.
- Do NOT add broad `try/catch` that swallows errors, catch-all without re-raising or logging, success-shaped fallbacks that hide failures, or early returns on invalid input without logging.
- Errors are logged appropriately and re-raised or handled explicitly.

## Enforcement

`node scripts/ratchet.mjs` (run by CI lint and `make pr-check`, non-strict; `make ratchet`/`make quality` strict) fails if silent-swallow patterns (Python `except: pass`, empty JS/TS `catch {}` / `.catch(() => {})`) rise above the baseline in `.claude/ratchets.json`. A genuine exception gets an inline `ratchet-allow(silent-exception-swallowing): <reason>` comment, not a baseline bump. It is a regex heuristic: a clean run is not proof of no silent swallowing (known gaps in the detail file). Prefer a linter's native rule (`ruff` S110, `eslint` `no-empty`) once configured.
