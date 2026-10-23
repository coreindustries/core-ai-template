---
paths:
  - "**/*.{js,cjs,mjs,jsx,ts,cts,mts,tsx}"
---

# Node.js Error Handling

**Scope:** Process-level handlers, async callback boundaries and logging in Node.js code. Adds to, and does not replace, `error-handling.md`.

## Process-level handlers

Register `uncaughtException` and `unhandledRejection` handlers first in every server entry point, before any app code, so module-load errors are caught too.

- `uncaughtException`: log at error level, then exit non-zero. Do not run graceful shutdown from here; it may throw too.
- `unhandledRejection`: log at warn level and continue if the failure is isolated and survivable.

## Async timer callbacks

`setTimeout(async () => ...)` and `setInterval(async () => ...)` return a Promise that Node ignores, so a throw becomes an unhandled rejection. Wrap and catch:

```js
// BAD: rejection is dropped
setInterval(async () => { await doWork(); }, 15000);

// GOOD
setInterval(() => {
  doWork().catch(err => log.warn('doWork failed', { err }));
}, 15000);
```

Never re-throw inside a timer callback; it becomes `uncaughtException`.

## EventEmitters and watchers

An `'error'` event with no listener throws. Give every emitter that can emit one (file watchers, sockets, streams, child processes) an `.on('error', ...)` handler that logs. Non-critical watchers log at warn; data-bearing ones at error.

## Fire-and-forget promises

Every Promise that is not awaited or returned needs a `.catch()` that logs.

## Synchronous calls in async contexts

A synchronous call that can throw (database driver, `JSON.parse`, file read) invoked from a timer or event callback must be wrapped in try/catch at the call site. Otherwise one bad row or file crashes the process.

## Logging

Use the project's logger, not `console.*`, in library code.

| Level | Use for |
|-------|---------|
| error | Data-loss risk, failed writes, unrecoverable state |
| warn | Recoverable failures, degraded functionality |
| info | Significant state changes |
| debug | High-frequency traces; off in production |

Never log user message content or secrets at info or above; log IDs, counts and lengths (see `secrets-hygiene.md`).
