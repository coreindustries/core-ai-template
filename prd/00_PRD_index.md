# PRD Index

## Core Documentation

- [x] 01_Technical_standards.md - Code quality, best practices, AI agent development patterns
- [ ] 02_Tech_stack.md - Technology stack (TEMPLATE - fill in for your project)
- [x] 03_Security.md - Security standards and OWASP Top 10

## Tech Stack Summary

> **Fill in when implementing for a specific project**

| Component | Technology |
|-----------|------------|
| Language | `{language}` |
| Package Manager | `{package_manager}` |
| API Framework | `{api_framework}` |
| Database | `{database}` |
| ORM | `{orm}` |
| Testing | `{test_framework}` |
| Linting | `{linter}` |
| Type Checking | `{type_checker}` |

## Task Tracking

**Task Files Directory:** `prd/tasks/`

For long-running features that span multiple sessions, create task files to track progress and preserve context across context compression events.

**Template:** `prd/tasks/TASK_TEMPLATE.md`

**Active Features (In Progress):**
- None currently (this is a template)

**Completed Features:**
- 01_Technical_standards - Language-agnostic technical standards
- 03_Security - Security standards and OWASP guidelines

**How to Use:**
1. Create task file when feature will span >1 session: `prd/tasks/{feature}_tasks.md`
2. Update task file every 30-60 minutes during implementation
3. Reference task file in PRD "Implementation Status" section
4. Use `/checkpoint` skill to update automatically
5. Include task IDs in commits: `[PRD-XX Task Y.Z]`

**Recovery After Context Compression:**
1. Read `prd/00_PRD_index.md` to find "In Progress" features
2. Read corresponding task file: `prd/tasks/{feature}_tasks.md`
3. Review "Next Session Priorities" and "Decisions Made"
4. Continue from last incomplete task

## Implementation Order

1. **Phase 1: Setup**
   - Fill in `02_Tech_stack.md` with your technology choices
   - Update `CLAUDE.md` commands for your stack
   - Configure linting, testing, type checking

2. **Phase 2: Core Features**
   - [Add PRDs as needed for your project]

3. **Phase 3: Advanced Features**
   - [Add PRDs as needed for your project]
