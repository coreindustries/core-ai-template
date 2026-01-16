---
prd_version: "1.0"
status: "Draft" # Draft | Active | Deprecated
last_updated: "YYYY-MM-DD"
owner: "@github-handle"
---

# [PRD Number] – [Feature Name]

## 1. Purpose

[Describe the audeience, purpose and goals of this feature]

## 2. Functional Requirements

### FR[X].1 – [Requirement Name]

[Description of requirement]

## 3. Technical Implementation

### 3.1 [Component Name]

[Implementation details]

### 3.2 Database Schema

**REQUIRED:** All PRDs that modify the database schema MUST include this section.

Describe the schema changes needed:

- New models to add (with field descriptions)
- Models to modify (which fields to add/remove/modify)
- New enums to create
- Existing enums to extend
- Indexes to add
- Constraints to add
- Relationships to establish

**Example:**

```sql
CREATE TABLE new_model (
  id VARCHAR(255) PRIMARY KEY,
  -- ... additional fields
);
```

### 3.3 Database Migration

**REQUIRED:** All PRDs that modify the database schema MUST include this section.

**Migration Steps:**

1. **Create Migration:**

   ```bash
   [migration_tool] [migration_command] --name [descriptive_migration_name]
   ```

   - Migration name format: `YYYYMMDDHHMMSS_descriptive_name`
   - Example: `20251203143000_add_inbound_links_table`
   - Replace `[migration_tool]` and `[migration_command]` with your project's migration tooling (e.g., `alembic`, `django migrate`, `rails db:migrate`, `prisma migrate`, etc.)

2. **Migration File Location:**

   - Migration files will be created in `[migrations_directory]/[migration_name]/`
   - Replace `[migrations_directory]` with your project's migration directory (e.g., `migrations/`, `db/migrations/`, `prisma/migrations/`, etc.)
   - Migration files typically include SQL scripts or schema definition files as required by your migration tool

3. **Migration Contents:**

   - List the SQL operations that will be performed:
     - CREATE TABLE statements
     - ALTER TABLE statements (add/remove columns)
     - CREATE TYPE statements (enums)
     - CREATE INDEX statements
     - ALTER TYPE statements (add enum values)
     - Foreign key constraints
     - Unique constraints

4. **Testing:**

   - Test migration on local database
   - Verify migration can be rolled back (if applicable)
   - Test with sample data

5. **Version Control:**

   - Commit migration files alongside schema changes
   - Migration files MUST be tracked in Git
   - Never commit schema changes without corresponding migrations

6. **Deployment:**
   - Ensure migrations run before application startup
   - Migrations should execute in the correct order
   - Application services should depend on migrations completing successfully
   - Document your deployment process for running migrations (e.g., CI/CD pipeline, container orchestration, manual steps, etc.)

**Reference:** See your project's database migration documentation for detailed migration guidelines and best practices.

### 3.4 [Other Implementation Sections]

[Additional implementation details]

## 4. Configuration

[Environment variables, feature flags, etc.]

## 5. Error Handling

[Error handling strategies]

## 6. Performance Considerations

[Performance optimizations and considerations]

## 7. Future Enhancements

[Potential future improvements]