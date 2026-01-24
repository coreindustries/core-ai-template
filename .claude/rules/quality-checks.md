# Quality Checks Rules

**Source:** PRD 01 - Technical Standards, Section 8

## Frequent Check Pattern

**REQUIRED:** Run quality checks every 15-30 minutes during active development.

**Benefits:**
- Prevents error accumulation (50% less debugging time)
- Immediate feedback on smaller change sets
- Easier to identify which change caused issues
- Reduces pre-commit hook failures (40% less frustration)

**During Development:**
```bash
# After writing/modifying a file
{lint_check} src/{module}
{format_check} src/{module}

# After writing type annotations
{type_check} src/{module}

# After writing tests
{test_specific} tests/unit/test_{module}
```

## Pre-Commit Requirements

**REQUIRED:** All code MUST pass linting before commits.

**Typical tools (see `prd/02_Tech_stack.md` for specifics):**
- Linting tool
- Formatting tool
- Static type checker
- Security analyzer
- Dependency vulnerability scanner

## Before Every Commit

**REQUIRED:** Run the full quality check suite:

```bash
# 1. Lint and format
{lint_fix} src/ tests/

# 2. Type check
{type_check} src/

# 3. Security scan
{security_scan} src/

# 4. Tests with coverage
{test_with_coverage}

# 5. Verify changes
git status
git diff
```

**All checks MUST pass before committing.**

## CI/CD Pipeline Requirements

**Required Stages:**
1. **Lint** - Run linting and formatting checks
2. **Test** - Run tests with coverage
3. **Security** - Run security scanners
4. **Build** - Build application/container
5. **Deploy** - Deploy to target environment

**Pre-merge Requirements:**
- All CI stages pass
- Code review approved
- Test coverage maintained
- No security vulnerabilities
- Documentation updated if needed

## Quality Checklist

- [ ] Linting passes
- [ ] Formatting passes
- [ ] Type checking passes
- [ ] Security scan passes
- [ ] Tests pass with coverage
- [ ] All checks run before commit
- [ ] CI/CD pipeline passes
