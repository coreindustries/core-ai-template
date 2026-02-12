# /deps

Audit, update, and manage project dependencies safely.

## Usage

```
/deps [action] [package] [--security] [--outdated]
```

## Arguments

- `action`: `audit`, `update`, `add`, `remove`, `outdated` (default: `audit`)
- `package`: Specific package name (for add/remove/update)
- `--security`: Focus on security vulnerabilities only
- `--outdated`: Show only outdated packages

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Complete dependency operations end-to-end
- Verify changes don't break the build
- Run tests after updates

**Safety:**
- Never auto-update major versions without confirmation
- Always check for breaking changes
- Create atomic commits for dependency changes

### Actions

#### Audit (`/deps audit`)

Check for security vulnerabilities and issues:

1. **Read `prd/00_technology.md`** for audit commands
2. **Run security audit**:
   ```bash
   # Commands vary by stack (see prd/00_technology.md)
   {dependency_audit_command}
   ```
3. **Categorize findings** by severity
4. **Suggest remediations**

#### Outdated (`/deps outdated`)

List packages with available updates:

1. **Check for updates**:
   ```bash
   {outdated_command}
   ```
2. **Categorize by update type**:
   - Patch updates (safe)
   - Minor updates (usually safe)
   - Major updates (review changelog)

3. **Present update plan**

#### Update (`/deps update [package]`)

Update dependencies safely:

1. **If specific package**:
   ```bash
   {update_package_command} <package>
   ```

2. **If all packages** (patch/minor only):
   ```bash
   {update_all_command}
   ```

3. **Verify after update**:
   ```bash
   {install_command}
   {test_command}
   {build_command}
   ```

4. **Create commit**:
   ```
   chore(deps): update <package> to <version>
   ```

#### Add (`/deps add <package>`)

Add new dependency:

1. **Check if already installed**
2. **Verify package legitimacy**:
   - Check download stats
   - Check maintenance status
   - Check for known vulnerabilities
3. **Install**:
   ```bash
   {add_package_command} <package>
   ```
4. **Verify installation**:
   ```bash
   {test_command}
   ```

#### Remove (`/deps remove <package>`)

Remove dependency:

1. **Check for usages** in codebase
2. **Warn if package is used**
3. **Remove**:
   ```bash
   {remove_package_command} <package>
   ```
4. **Clean up imports** if needed
5. **Verify**:
   ```bash
   {test_command}
   ```

### Dependency Report Format

```markdown
## Dependency Audit Report

**Date:** YYYY-MM-DD
**Total packages:** X
**Direct dependencies:** Y
**Vulnerabilities found:** Z

### Security Vulnerabilities

| Severity | Package | Current | Fixed In | CVE |
|----------|---------|---------|----------|-----|
| High | lodash | 4.17.15 | 4.17.21 | CVE-2021-23337 |
| Medium | axios | 0.21.0 | 0.21.1 | CVE-2021-3749 |

### Outdated Packages

| Package | Current | Latest | Type |
|---------|---------|--------|------|
| react | 17.0.2 | 18.2.0 | Major |
| typescript | 4.9.5 | 5.3.2 | Major |
| jest | 29.5.0 | 29.7.0 | Minor |

### Recommendations

1. **Immediate**: Update lodash to fix high severity CVE
2. **Soon**: Update axios for security patch
3. **Plan**: Evaluate React 18 migration
```

### Update Safety Rules

1. **Patch updates** (1.0.0 → 1.0.1): Auto-update OK
2. **Minor updates** (1.0.0 → 1.1.0): Auto-update with tests
3. **Major updates** (1.0.0 → 2.0.0): Review changelog, confirm

### Lockfile Handling

- Always commit lockfile changes
- Never manually edit lockfiles
- Regenerate if conflicts occur

## Example Output

```
$ /deps audit --security

Auditing dependencies...

Package manager: npm
Total packages: 245 (42 direct, 203 transitive)

Security Scan Results:

🔴 High Severity (1)
━━━━━━━━━━━━━━━━━━━
lodash@4.17.15
  CVE-2021-23337: Prototype pollution
  Fixed in: 4.17.21
  Recommendation: npm update lodash

🟡 Medium Severity (2)
━━━━━━━━━━━━━━━━━━━━━
axios@0.21.0
  CVE-2021-3749: ReDoS vulnerability
  Fixed in: 0.21.1

minimist@1.2.5
  CVE-2021-44906: Prototype pollution
  Fixed in: 1.2.6

🟢 Low Severity (0)

━━━━━━━━━━━━━━━━━━━━━
Summary: 3 vulnerabilities found
  - 1 high (action required)
  - 2 medium (update soon)

Suggested fix:
npm update lodash axios minimist

Run `/deps update` to apply security patches.
```
