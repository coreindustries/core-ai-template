# Rules Directory

This directory contains modular rule files that are automatically loaded by Claude Code (v2.0.64+).

## How It Works

All `.md` files in `.claude/rules/` are automatically loaded into Claude Code's context when launched. This allows you to organize project instructions into focused, maintainable files instead of one large `CLAUDE.md`.

## Available Rules

| File | Purpose | Source |
|------|---------|--------|
| `code-quality.md` | Code quality standards (DRY, typing, naming, docs) | PRD 01 Section 3 |
| `testing.md` | Testing standards and requirements | PRD 01 Section 7 |
| `ai-agent-patterns.md` | AI agent development principles | PRD 01 Sections 4 & 6 |
| `error-handling.md` | Error handling patterns and requirements | PRD 01 Section 5 |
| `git-workflow.md` | Git workflow and commit standards | PRD 01 Section 9 |
| `gitmoji.md` | Gitmoji emoji prefixes for commits | Gitmoji standard |
| `nextjs.md` | Next.js 16+ development best practices | Next.js patterns |
| `security-core.md` | Core security practices (always applies) | Universal security |
| `security.md` | Security standards and OWASP Top 10 | PRD 03 |
| `quality-checks.md` | Quality check requirements and CI/CD | PRD 01 Section 8 |
| `task-management.md` | Task tracking and PRD workflow | PRD 01 Section 10 |

## Rule Format Standards

### Claude Code Rules

**Location:** `./.claude/rules/`  
**Format:** Markdown files (`.md`)  
**Loading:** All `.md` files automatically loaded by Claude Code v2.0.64+

**Structure:**
```
.claude/
├── CLAUDE.md          # Main project instructions
└── rules/
    ├── code-quality.md
    ├── testing.md
    └── ...
```

**Features:**
- All `.md` files in `.claude/rules/` are automatically loaded
- Supports subdirectories for organization
- Supports symlinks for sharing rules across projects
- Path-specific rules (future feature)

### Cursor IDE Rules

**Location:** Root directory  
**File:** `.cursorrules` (no extension)  
**Format:** Plain text or Markdown

Cursor automatically reads `.cursorrules` from the project root as repo-specific "Rules for AI".

### Rule Loading Precedence (Claude Code)

Claude Code loads rules in this order (later rules override earlier ones):

1. **Managed Policy** (organization-wide)
2. **User-Level Rules** (`~/.claude/rules/`)
3. **Project Main** (`CLAUDE.md` or `.claude/CLAUDE.md`)
4. **Project Rules** (`.claude/rules/*.md`) ← **This directory**
5. **Skills** (`.claude/skills/*.md` - invoked on demand)
6. **Agents** (`.claude/agents/*.md` - invoked on demand)

## Adding New Rules

1. Create a new `.md` file in this directory
2. Use descriptive, kebab-case filename
3. Include clear sections and examples
4. Reference source PRD if applicable
5. Rules will be automatically loaded

## Organization Tips

- Keep rules focused on a single topic
- Use clear headings and examples
- Reference other rules when related
- Update rules when standards change
- Keep rules concise but complete

## Path-Specific Rules (Future)

Claude Code may support path-specific rules in the future, allowing rules to activate only in certain directories or file types.

## See Also

- `CLAUDE.md` - Main project instructions
- `AGENTS.md` - Agent quick reference
- `.cursorrules` - Cursor IDE rules (root)
- `.cursor/rules/` - Cursor IDE workspace rules (.mdc files)
- `prd/01_Technical_standards.md` - Full technical standards
- `prd/03_Security.md` - Full security standards

## References

- [Claude Code - Manage Memory](https://code.claude.com/docs/en/memory)
- [Claude Code - Rules Directory](https://claudefa.st/blog/guide/mechanics/rules-directory)
- [Cursor Docs - Rules](https://cursor.com/docs/context/rules)
