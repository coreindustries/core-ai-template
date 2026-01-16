# /new-feature

Scaffold a new feature with routes, models, services, and tests following project standards.

## Usage

```
/new-feature <feature_name> [--with-db] [--crud] [--prd <prd_number>]
```

## Arguments

- `feature_name`: Name of the feature (e.g., `user_profile`, `payment`)
- `--with-db`: Include database model scaffold
- `--crud`: Generate full CRUD operations
- `--prd <prd_number>`: Link to PRD number (branches from the PRD branch)

## Instructions

When this skill is invoked:

### Agent Behavior (Codex-Max Pattern)

**Autonomy:**
- Complete all scaffolding end-to-end without stopping midway
- Make reasonable assumptions for field types if not specified
- Implement with working defaults, don't request clarification unless truly blocked

**Exploration:**
- Read all relevant files in parallel before starting:
  - Check existing routes in `api/`
  - Check existing services in `services/`
  - Check existing models in `models/`
  - Check database schema if `--with-db` is used
  - Read `prd/02_Tech_stack.md` for language-specific patterns
- Use one parallel batch read, don't read files sequentially

**Quality:**
- Generate tests alongside code (not as an afterthought)
- Run type check and tests after scaffolding
- Ensure coverage for generated code

### Implementation Steps

1. **Read `prd/02_Tech_stack.md`** for:
   - File naming conventions
   - Import patterns
   - Framework-specific syntax

2. **Validate the feature name**:
   - Must follow project's naming convention
   - Must not conflict with existing features
   - Check `src/{project}/` for existing modules

3. **Create or switch to the appropriate branch**:
   - If `--prd` is specified: `git checkout -b feat/{feature} prd/{prd_number}-*`
   - If no PRD: `git checkout -b feat/{feature} main`

4. **Create the following files** (adapt to your stack):

   ### API Route (`src/{project}/api/{feature}`)
   - List endpoint (GET /)
   - Get by ID endpoint (GET /:id)
   - Create endpoint (POST /)
   - Update endpoint (PATCH /:id)
   - Delete endpoint (DELETE /:id)

   ### Model (`src/{project}/models/{feature}`)
   - Base schema
   - Create schema
   - Update schema
   - Response schema

   ### Service (`src/{project}/services/{feature}`)
   - get_by_id method
   - list_all method
   - create method
   - update method
   - delete method
   - Audit logging for mutations

   ### Tests (`tests/unit/test_{feature}`)
   - API endpoint tests
   - Service tests
   - Model validation tests

5. **If `--with-db` is specified**, add to database schema:
   - Model with id, timestamps
   - Appropriate indexes

6. **Register the router** in main routes file

7. **After scaffolding**:
   - If `--with-db`: Run schema generate and migration commands
   - Run quality checks:
     ```bash
     {lint_fix} src/ tests/
     {type_check} src/
     {test_specific} tests/unit/test_{feature}
     ```
   - Verify all files created successfully
   - Present summary with file references

8. **Verification and next steps**:
   - Confirm all tests pass
   - Show coverage
   - Suggest next steps:
     1. Update generated code with feature-specific fields
     2. Test the endpoints
     3. Add integration tests if needed

## File Structure Created

```
src/{project}/
├── api/{feature}           # API routes
├── models/{feature}        # Request/response schemas
└── services/{feature}      # Business logic

tests/
└── unit/test_{feature}     # Unit tests
```

## Branching Workflow

```
main ─────────────────────────────────────────────►
       │                              ▲
       │ create prd branch            │ merge PRD PR
       ▼                              │
prd/{n}-{name} ──────────────────────►│
       │                ▲             │
       │ create feature │ merge feat  │
       ▼                │             │
feat/{feature} ────────►│             │
```

### Merge Strategy

1. **Feature → PRD branch**: Feature PRs target their parent PRD branch
2. **PRD → main**: Once all features are complete, PRD branch merges to main
3. **Standalone features**: Features without a PRD target `main` directly

## Example

```
$ /new-feature user_profile --with-db --crud --prd 04

📁 Creating feature: user_profile

Reading project patterns...
Creating branch: feat/user_profile from prd/04-*

Files created:
✅ src/{project}/api/user_profile
✅ src/{project}/models/user_profile
✅ src/{project}/services/user_profile
✅ tests/unit/test_user_profile

Database:
✅ Added UserProfile model to schema
⚠️  Run: {db_generate} && {db_migrate}

Quality checks:
✅ Linting passed
✅ Type checking passed
✅ Tests passed (4/4)

Next steps:
1. Run {db_generate} to generate client
2. Run {db_migrate} to create migration
3. Update generated code with feature-specific fields
4. Start dev server and test endpoints
5. Commit: git commit -m "feat(user_profile): scaffold feature"
```
