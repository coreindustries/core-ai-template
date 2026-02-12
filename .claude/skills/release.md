# /release

Tag a version, generate changelog, and create a GitHub release.

## Usage

```
/release [version] [--dry-run] [--draft]
```

## Arguments

- `version`: Semver version (`1.2.3`) or bump type (`patch`, `minor`, `major`)
- `--dry-run`: Preview release without creating anything
- `--draft`: Create as draft release (don't publish)

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Determine version bump from commit history if not specified
- Generate changelog from conventional commits
- Create tag and GitHub release end-to-end

**Safety:**
- Never release from a dirty worktree
- Never release from a non-main branch without confirmation
- Always run quality checks before tagging

### Release Process

#### Phase 1: Pre-Release Checks

1. **Verify clean worktree**:
   ```bash
   git status --porcelain
   ```
   If dirty, stop and ask user to commit or stash.

2. **Verify branch**:
   ```bash
   git branch --show-current
   ```
   Warn if not `main` or `master`.

3. **Run quality checks**:
   ```bash
   make quality  # or equivalent from prd/00_technology.md
   ```
   All checks must pass before release.

4. **Get current version**:
   ```bash
   git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"
   ```

#### Phase 2: Determine Version

If version not specified, analyze commits since last tag:

```bash
git log $(git describe --tags --abbrev=0 2>/dev/null || echo "")..HEAD --oneline
```

**Auto-bump rules (conventional commits):**
- `feat!:` or `BREAKING CHANGE:` → **major**
- `feat:` → **minor**
- `fix:`, `perf:`, `refactor:` → **patch**

#### Phase 3: Generate Changelog

Categorize commits since last tag:

```markdown
## What's Changed

### Breaking Changes
- description (#PR)

### Features
- description (#PR)

### Bug Fixes
- description (#PR)

### Performance
- description (#PR)

### Other Changes
- description (#PR)

**Full Changelog**: v1.0.0...v1.1.0
```

#### Phase 4: Create Release

1. **Update version** in package config if applicable:
   ```bash
   # package.json, pyproject.toml, Cargo.toml, etc.
   ```

2. **Commit version bump** (if file changed):
   ```bash
   git add {package_config}
   git commit -m "chore: bump version to {version}"
   ```

3. **Create annotated tag**:
   ```bash
   git tag -a v{version} -m "Release v{version}"
   ```

4. **Push tag**:
   ```bash
   git push origin main --tags
   ```

5. **Create GitHub release**:
   ```bash
   gh release create v{version} --title "v{version}" --notes "{changelog}"
   # or with --draft flag
   gh release create v{version} --title "v{version}" --notes "{changelog}" --draft
   ```

### Dry Run Mode

When `--dry-run` is specified:
- Show what version would be created
- Show generated changelog
- Show files that would be modified
- Do NOT create tags, commits, or releases

### Version File Locations

| Stack | File | Field |
|-------|------|-------|
| Node.js | `package.json` | `version` |
| Python | `pyproject.toml` | `[project] version` |
| Go | No file (tags only) | — |
| iOS | `Info.plist` | `CFBundleShortVersionString` |
| Android | `build.gradle.kts` | `versionName` / `versionCode` |

## Example Output

```
$ /release minor

Pre-release checks...
  Branch: main
  Worktree: clean
  Tests: passing (142/142)
  Lint: clean
  Current version: v1.2.0

Analyzing commits since v1.2.0...
  3 features, 2 fixes, 1 refactor

Bumping: v1.2.0 → v1.3.0

Changelog:
  ## What's Changed
  ### Features
  - Add OAuth2 login support (#45)
  - Add user avatar uploads (#48)
  - Add dark mode toggle (#52)
  ### Bug Fixes
  - Fix memory leak in image processing (#46)
  - Fix pagination on user list (#50)

Creating release...
  Updated package.json version
  Created tag v1.3.0
  Pushed to origin/main
  Created GitHub release: https://github.com/org/repo/releases/tag/v1.3.0

Release v1.3.0 published!
```
