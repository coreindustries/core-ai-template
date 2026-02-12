# /lint

Run code quality checks including linting, formatting, and type checking.

## Usage

```
/lint [target] [--fix] [--strict]
```

## Arguments

- `target`: Specific file or directory (default: `src/ tests/`)
- `--fix`: Auto-fix issues where possible
- `--strict`: Fail on warnings (for CI)

## Instructions

When this skill is invoked:

### Full Lint Pipeline

1. **Read `prd/02_Tech_stack.md`** to find the correct commands

2. **Run all checks in sequence**:
   ```bash
   # Linting (see prd/02_Tech_stack.md for specific command)
   {lint_check_command} src/ tests/

   # Formatting check
   {format_check_command} src/ tests/

   # Type checking
   {type_check_command} src/
   ```

3. **Report Results**:
   ```
   ==================== Lint Results ====================

   📋 Linting
   ✅ No issues found

   📐 Formatting
   ⚠️  2 files need formatting:
      - src/{project}/api/routes
      - tests/unit/test_config

   🔍 Type Checking
   ✅ No type errors

   ==================== Summary ====================
   ✅ Linting: Passed
   ⚠️  Formatting: 2 issues (run with --fix)
   ✅ Type Checking: Passed

   Run '/lint --fix' to auto-fix formatting issues.
   ```

### With --fix Flag

```bash
# Fix linting issues
{lint_fix_command} src/ tests/

# Fix formatting
{format_fix_command} src/ tests/
```

Report what was fixed:
```
🔧 Auto-fixed issues:

Linting:
- src/{project}/api/routes: Removed unused import
- src/{project}/services/user: Sorted imports

Formatting:
- src/{project}/api/routes: Reformatted
- tests/unit/test_config: Reformatted

✅ All issues fixed!
```

### Specific Checks

Run individual checks (commands from `prd/02_Tech_stack.md`):

```bash
# Linting only
{lint_check_command} src/

# Formatting only
{format_check_command} src/

# Type checking only
{type_check_command} src/

# Security rules only (if supported)
{security_lint_command} src/
```

### CI Mode (--strict)

For CI pipelines, use strict mode:
- Returns non-zero exit code on any issue
- Treats warnings as errors
- Outputs machine-readable format if available

## Quality Standards

From `.claude/rules/code-quality.md`:

- ✅ All functions must have type annotations
- ✅ All classes must have docstrings
- ✅ No unused imports
- ✅ Imports sorted
- ✅ Line length within configured limit
- ✅ No security issues

## Example Output

```
$ /lint

🔍 Running code quality checks...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📋 Linting
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ All 15 files passed

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📐 Formatting
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ All files formatted correctly

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Type Checking
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Success: no issues found in 15 source files

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ All checks passed!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
