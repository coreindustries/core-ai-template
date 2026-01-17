# /migrate

Manage database schema migrations.

## Usage

```
/db-migrate [action] [--name <migration_name>]
```

## Arguments

- `action`: `create`, `run`, `status`, `rollback` (default: `run`)
- `--name`: Name for new migration

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Complete migration operation end-to-end
- Verify migration success
- Report any issues clearly

**Safety:**
- Always check migration status before running
- Warn about destructive operations
- Suggest backup for production

### Actions

#### Create Migration

```bash
/migrate create --name add_user_profile
```

1. **Read `prd/02_Tech_stack.md`** for migration command
2. **Generate migration**:
   ```bash
   {migration_create_command} --name {name}
   ```
3. **Report created file location**
4. **Suggest next steps**

#### Run Migrations

```bash
/migrate run
```

1. **Check migration status**:
   ```bash
   {migration_status_command}
   ```
2. **Run pending migrations**:
   ```bash
   {migration_run_command}
   ```
3. **Regenerate client** (if applicable):
   ```bash
   {db_generate_command}
   ```
4. **Verify success**

#### Check Status

```bash
/migrate status
```

1. **Show migration status**:
   ```bash
   {migration_status_command}
   ```
2. **List pending migrations**
3. **List applied migrations**

#### Rollback (Careful!)

```bash
/migrate rollback
```

1. **⚠️ Warn about data loss**
2. **Confirm with user**
3. **Execute rollback**:
   ```bash
   {migration_rollback_command}
   ```

### Common Workflows

**After schema changes:**
```bash
# 1. Generate client (if ORM requires)
/migrate create --name describe_changes

# 2. Review generated migration

# 3. Run migration
/migrate run

# 4. Verify
/migrate status
```

**Before deployment:**
```bash
# Check pending migrations
/migrate status

# Run in production (with backup!)
/migrate run
```

## Example Output

```
$ /migrate create --name add_user_preferences

📋 Creating migration: add_user_preferences

Running: {migration_create_command} --name add_user_preferences

✅ Migration created: {migration_file_path}

Next steps:
1. Review the generated migration
2. Run: /migrate run
3. Regenerate client: {db_generate_command}
```

```
$ /migrate status

📋 Migration Status

Applied:
✅ 001_initial_schema (2026-01-10)
✅ 002_add_users (2026-01-12)
✅ 003_add_posts (2026-01-14)

Pending:
⏳ 004_add_user_preferences

Run '/migrate run' to apply pending migrations.
```
