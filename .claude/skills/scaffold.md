# /scaffold

Generate a new module, component, or screen with boilerplate, tests, and wiring.

## Usage

```
/scaffold <type> <name> [--path <path>]
```

## Arguments

- `type`: What to generate — `module`, `component`, `screen`, `endpoint`, `model`, `service`
- `name`: Name of the thing to create (PascalCase or kebab-case)
- `--path`: Override default location

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Read `prd/00_technology.md` to determine stack and patterns
- Follow existing code conventions (read similar files first)
- Create all related files (implementation + tests + wiring)

**Quality:**
- Match existing code style exactly
- Include type annotations and docstrings
- Create test file with basic test cases
- Wire into existing routing/exports

### Scaffold Types

#### Module (`/scaffold module <name>`)

Create a complete backend module (service + model + route + tests):

```
src/{project}/{name}/
├── __init__.py          # or index.ts
├── service.py           # Business logic
├── models.py            # Request/response schemas
└── router.py            # API route handlers

tests/unit/
└── test_{name}_service.py

tests/integration/
└── test_{name}_api.py
```

**Steps:**
1. **Read existing modules** to match patterns
2. **Create service** with CRUD operations skeleton
3. **Create models** with validation schemas
4. **Create router** with standard endpoints
5. **Create unit test** for service layer
6. **Create integration test** for API endpoints
7. **Register router** in main app

#### Component (`/scaffold component <name>`)

Create a React/UI component (web or mobile):

```
src/components/{name}/
├── {name}.tsx           # Component implementation
├── {name}.test.tsx      # Tests
└── index.ts             # Re-export
```

**Steps:**
1. **Read existing components** to match patterns
2. **Create component** with props interface
3. **Create test** with render + interaction tests
4. **Add re-export** from index
5. **Add to component barrel export** if one exists

#### Screen (`/scaffold screen <name>`)

Create a full screen/page:

**Web (Next.js):**
```
src/app/{name}/
├── page.tsx             # Page component
├── layout.tsx           # Layout (if needed)
└── loading.tsx          # Loading state
```

**Mobile (React Native):**
```
src/screens/{name}/
├── {Name}Screen.tsx     # Screen component
├── {Name}Screen.test.tsx
└── index.ts
```

**iOS (SwiftUI):**
```
Sources/{Feature}/
├── {Name}View.swift
├── {Name}ViewModel.swift
└── {Name}ViewTests.swift
```

**Android (Compose):**
```
app/src/main/java/.../feature/{name}/
├── {Name}Screen.kt
├── {Name}ViewModel.kt
└── {Name}UiState.kt

app/src/test/java/.../feature/{name}/
└── {Name}ViewModelTest.kt
```

**Steps:**
1. **Read existing screens** to match patterns
2. **Create screen component** with standard layout
3. **Create view model / state** if pattern exists
4. **Create test file**
5. **Add to navigation** / router

#### Endpoint (`/scaffold endpoint <name>`)

Create a single API endpoint:

1. **Add route handler** in appropriate router file
2. **Add request/response models** with validation
3. **Add service method** for business logic
4. **Add tests** for happy path + error cases
5. **Register route** in app

#### Model (`/scaffold model <name>`)

Create a data model / database entity:

1. **Create schema definition** (Prisma, SQLAlchemy, SwiftData, Room)
2. **Create request/response DTOs**
3. **Generate migration** if database model
4. **Add basic CRUD queries**
5. **Create test fixtures**

#### Service (`/scaffold service <name>`)

Create a service layer class/module:

1. **Create service** with dependency injection
2. **Add interface/protocol** if pattern exists
3. **Create unit tests** with mocked dependencies
4. **Wire into DI container** if applicable

### Convention Detection

Before generating, read 2-3 existing files of the same type to detect:

- File naming convention (kebab-case, PascalCase, snake_case)
- Import style (relative, absolute, aliases)
- Export pattern (default, named, barrel)
- Test naming and structure
- Documentation style

### Scaffold Checklist

- [ ] Matches existing code conventions
- [ ] Type annotations complete
- [ ] Docstrings / documentation added
- [ ] Test file created with basic cases
- [ ] Wired into app (routes, navigation, exports)
- [ ] Linting passes on new files

## Example Output

```
$ /scaffold module notifications

Reading existing modules for patterns...
  Detected: Python + FastAPI + SQLAlchemy

Creating notification module...
  src/myapp/notifications/__init__.py
  src/myapp/notifications/service.py
    - NotificationService with create, get, list, mark_read
  src/myapp/notifications/models.py
    - CreateNotificationRequest, NotificationResponse
  src/myapp/notifications/router.py
    - POST /api/v1/notifications
    - GET  /api/v1/notifications
    - GET  /api/v1/notifications/{id}
    - PUT  /api/v1/notifications/{id}/read

  tests/unit/test_notifications_service.py (6 tests)
  tests/integration/test_notifications_api.py (4 tests)

Wiring...
  Updated src/myapp/main.py — registered notifications router

Verification...
  Lint: passing
  Tests: 10/10 passing

Module 'notifications' scaffolded successfully.
```
