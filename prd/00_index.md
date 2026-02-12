# PRD Index

## Tech Stack

- [ ] 00_technology.md - Technology stack (TEMPLATE - fill in for your project)

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

## Active Features (In Progress)

- None currently (this is a template)

## Completed Features

- (none)

## Task Tracking

**Task Files Directory:** `prd/tasks/`

For long-running features that span multiple sessions, create task files to track progress and preserve context across context compression events.

**Template:** `prd/_task_template.md`

**How to Use:**
1. Create task file when feature will span >1 session: `prd/tasks/{feature}_tasks.md`
2. Update task file every 30-60 minutes during implementation
3. Use `/checkpoint` skill to update automatically

**Recovery After Context Compression:**
1. Read this file to find "In Progress" features
2. Read corresponding task file: `prd/tasks/{feature}_tasks.md`
3. Start from "Next Session Priorities"
