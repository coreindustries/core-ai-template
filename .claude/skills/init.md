# /init

Initialize a new project with structure, configuration, and boilerplate.

## Usage

```
/init <project_name> [--template <template>] [--stack <stack>]
```

## Arguments

- `project_name`: Name for the new project (kebab-case)
- `--template`: Project template (api, cli, library, fullstack)
- `--stack`: Technology stack (python, typescript, go)

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Complete project setup end-to-end
- Make reasonable technology choices based on template
- Configure all tooling without prompting

**Quality:**
- Follow best practices for the chosen stack
- Include comprehensive .gitignore
- Set up quality tooling (linting, testing, formatting)

### Initialization Process

1. **Validate project name**:
   - Must be kebab-case
   - Must not conflict with existing directories
   - Must be valid package name

2. **Determine stack** (if not specified):
   - Ask user preference
   - Or detect from context

3. **Create project structure**

4. **Initialize version control**:
   ```bash
   git init
   git add .
   git commit -m "chore: initial project setup"
   ```

5. **Install dependencies**

6. **Verify setup**:
   ```bash
   {test_command}
   {lint_command}
   {build_command}
   ```

### Project Templates

#### API (`--template api`)

REST/GraphQL API service:

```
project-name/
├── src/
│   ├── api/              # Route handlers
│   ├── services/         # Business logic
│   ├── models/           # Data models
│   ├── middleware/       # Request middleware
│   ├── config/           # Configuration
│   └── main.{ext}        # Entry point
├── tests/
│   ├── unit/
│   └── integration/
├── docs/
├── .env.example
├── .gitignore
├── README.md
└── {package_config}
```

#### CLI (`--template cli`)

Command-line application:

```
project-name/
├── src/
│   ├── commands/         # CLI commands
│   ├── utils/            # Utilities
│   └── main.{ext}        # Entry point
├── tests/
├── .gitignore
├── README.md
└── {package_config}
```

#### Library (`--template library`)

Reusable library/package:

```
project-name/
├── src/
│   ├── index.{ext}       # Public API
│   └── lib/              # Implementation
├── tests/
├── docs/
├── .gitignore
├── README.md
├── LICENSE
└── {package_config}
```

#### Fullstack (`--template fullstack`)

Full-stack web application:

```
project-name/
├── apps/
│   ├── api/              # Backend API
│   └── web/              # Frontend app
├── packages/
│   └── shared/           # Shared code
├── .gitignore
├── README.md
└── {monorepo_config}
```

### Stack Configuration

#### Python (`--stack python`)

```yaml
Package Manager: uv
Framework: FastAPI (api), Click (cli), none (library)
Testing: pytest, pytest-cov
Linting: ruff
Type Checking: mypy
```

**Files created:**
- `pyproject.toml`
- `.python-version`
- `src/{project}/__init__.py`
- `tests/conftest.py`

#### TypeScript (`--stack typescript`)

```yaml
Runtime: Node.js / Bun
Package Manager: bun
Framework: Hono (api), Commander (cli), none (library)
Testing: vitest
Linting: eslint, prettier
Type Checking: tsc
```

**Files created:**
- `package.json`
- `tsconfig.json`
- `.eslintrc.js`
- `.prettierrc`
- `src/index.ts`

### Generated Files

**Always included:**
- `.gitignore` (comprehensive for stack)
- `README.md` (with getting started)
- `.env.example` (if config needed)
- `LICENSE` (MIT default)

**AI Agent support:**
- `CLAUDE.md` (from template)
- `.claude/rules/` (universal rules, from template)
- `.claude/rules-available/` (platform rules, from template)
- `.claude/references/` (on-demand references, from template)
- `.claude/skills/` (from template)

### Enable Platform Rules

Based on the chosen template and stack, symlink relevant rules from `rules-available/` into `rules/`:

**Web / Fullstack (Next.js, React):**
```bash
ln -s ../rules-available/nextjs.md .claude/rules/nextjs.md
ln -s ../rules-available/security-web.md .claude/rules/security-web.md
ln -s ../rules-available/security-owasp.md .claude/rules/security-owasp.md
```

**API (any stack):**
```bash
ln -s ../rules-available/security-owasp.md .claude/rules/security-owasp.md
```

**Dockerized project:**
```bash
ln -s ../rules-available/docker.md .claude/rules/docker.md
ln -s ../rules-available/security-owasp.md .claude/rules/security-owasp.md
```

**Mobile (React Native):**
```bash
ln -s ../rules-available/security-mobile.md .claude/rules/security-mobile.md
ln -s ../rules-available/security-web.md .claude/rules/security-web.md
ln -s ../rules-available/security-owasp.md .claude/rules/security-owasp.md
```

### Post-Init Checklist

- [ ] Project structure created
- [ ] Platform-specific rules symlinked
- [ ] Dependencies installed
- [ ] Git initialized
- [ ] Tests pass
- [ ] Linting passes
- [ ] README accurate

## Example Output

```
$ /init my-api --template api --stack python

Creating project: my-api

Template: API
Stack: Python (uv + FastAPI)

Creating directory structure...
  ✅ src/my_api/
  ✅ src/my_api/api/
  ✅ src/my_api/services/
  ✅ src/my_api/models/
  ✅ tests/unit/
  ✅ tests/integration/

Creating configuration files...
  ✅ pyproject.toml
  ✅ .python-version (3.13)
  ✅ .gitignore
  ✅ .env.example
  ✅ README.md
  ✅ CLAUDE.md

Installing dependencies...
  ✅ uv sync

Initializing git...
  ✅ git init
  ✅ Initial commit created

Running verification...
  ✅ Tests pass (2/2)
  ✅ Linting passes
  ✅ Type checking passes

Project created successfully!

Next steps:
1. cd my-api
2. cp .env.example .env
3. Edit .env with your configuration
4. uv run uvicorn src.my_api.main:app --reload
5. Visit http://localhost:8000/docs

Happy coding!
```
