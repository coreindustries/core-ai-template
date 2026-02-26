# Code Review Expert

A comprehensive code review skill for [OpenClaw](https://github.com/openclaw/openclaw). Performs structured reviews with a senior engineer lens, covering architecture, security, performance, and code quality.

## Installation

Copy the `code-review-expert` directory into your OpenClaw `skills/` folder:

```bash
cp -r code-review-expert ~/.openclaw/skills/
```

Or clone and symlink:

```bash
git clone <this-repo> /path/to/code-review-expert
ln -s /path/to/code-review-expert ~/.openclaw/skills/code-review-expert
```

## Features

- **SOLID Principles** — Detect SRP, OCP, LSP, ISP, DIP violations
- **Security Scan** — XSS, injection, SSRF, race conditions, auth gaps, secrets leakage
- **Performance** — N+1 queries, CPU hotspots, missing cache, memory issues
- **Error Handling** — Swallowed exceptions, async errors, missing boundaries
- **Boundary Conditions** — Null handling, empty collections, off-by-one, numeric limits
- **Removal Planning** — Identify dead code with safe deletion plans

## Usage

After installation, invoke in any OpenClaw session:

```
/code-review-expert
```

The skill automatically reviews your current git changes.

### Options

```
/code-review-expert src/             # Review specific directory
/code-review-expert --commit HEAD~3  # Review last 3 commits
/code-review-expert --strict         # Stricter thresholds
```

## Workflow

1. **Preflight** — Scope changes via `git diff`
2. **SOLID + Architecture** — Check design principles
3. **Removal Candidates** — Find dead/unused code
4. **Security Scan** — Vulnerability detection
5. **Code Quality** — Error handling, performance, boundaries
6. **Output** — Findings by severity (P0–P3)
7. **Confirmation** — Ask user before implementing fixes

## Severity Levels

| Level | Name | Action |
|-------|------|--------|
| P0 | Critical | Must block merge |
| P1 | High | Should fix before merge |
| P2 | Medium | Fix or create follow-up |
| P3 | Low | Optional improvement |

## Structure

```
code-review-expert/
├── SKILL.md                          # Main skill definition
├── README.md                         # This file
└── references/
    ├── solid-checklist.md            # SOLID smell prompts
    ├── security-checklist.md         # Security & reliability
    ├── code-quality-checklist.md     # Error, perf, boundaries
    └── removal-plan.md              # Deletion planning template
```

## References

Each checklist provides detailed prompts and anti-patterns:

- **solid-checklist.md** — SOLID violations + common code smells
- **security-checklist.md** — OWASP risks, race conditions, crypto, supply chain
- **code-quality-checklist.md** — Error handling, caching, N+1, null safety
- **removal-plan.md** — Safe vs deferred deletion with rollback plans

## License

MIT
