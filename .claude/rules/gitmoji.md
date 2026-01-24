# Gitmoji Reference

**Source:** Gitmoji standard (https://gitmoji.dev)

This rule extends Conventional Commits with Gitmoji emoji prefixes for visual commit identification.

## Format

When Gitmoji is enabled, commit messages follow this structure:

```
<emoji> <type>(<scope>)?[!]: <description>

[optional body]

[optional footer(s)]
```

**Example:** `✨ feat(auth): add OAuth2 login support`

## Rules

- **Always** prefix the commit message with the appropriate Gitmoji
- **Use the actual emoji character** (✨), not the `:shortcode:` format (`:sparkles:`)
- The emoji comes **before the type**, separated by a space
- For breaking changes, **always use 💥** regardless of the commit type

## Type and Emoji Mapping

Each conventional commit type has a primary Gitmoji:

| Type       | Primary Emoji | Description                                              |
|------------|---------------|----------------------------------------------------------|
| `feat`     | ✨            | A new feature                                            |
| `fix`      | 🐛            | A bug fix                                                |
| `docs`     | 📝            | Documentation-only changes                               |
| `style`    | 🎨            | Formatting, whitespace, etc. (no code behavior changes)  |
| `refactor` | ♻️            | Code change that neither fixes a bug nor adds a feature  |
| `perf`     | ⚡️            | Performance-related change                               |
| `test`     | ✅            | Adding or updating tests                                 |
| `build`    | 📦️            | Build system or external dependencies (webpack, npm)     |
| `ci`       | 👷            | CI configuration and scripts                             |
| `chore`    | 🔧            | Routine tasks, maintenance, or non-code changes          |
| `revert`   | ⏪️            | A commit that reverts previous commits                   |

## Extended Gitmoji Reference

For more specific intents, use these additional gitmojis:

### Features & Enhancements
- 🎉 `:tada:` - Begin a project / initial commit
- 🚀 `:rocket:` - Deploy stuff
- 💄 `:lipstick:` - Add or update UI and style files
- 🌐 `:globe_with_meridians:` - Internationalization and localization
- ♿️ `:wheelchair:` - Improve accessibility
- 📱 `:iphone:` - Work on responsive design
- 🗃️ `:card_file_box:` - Perform database related changes
- 🔊 `:loud_sound:` - Add or update logs
- 🌱 `:seedling:` - Add or update seed files
- 🚩 `:triangular_flag_on_post:` - Add, update, or remove feature flags
- 👔 `:necktie:` - Add or update business logic
- 🛂 `:passport_control:` - Work on authorization, roles, permissions
- 🩺 `:stethoscope:` - Add or update healthcheck
- 🦺 `:safety_vest:` - Add or update validation code
- 📈 `:chart_with_upwards_trend:` - Add or update analytics or tracking

### Bug Fixes
- 🔒️ `:lock:` - Fix security or privacy issues
- 🚑️ `:ambulance:` - Critical hotfix
- 🩹 `:adhesive_bandage:` - Simple fix for a non-critical issue
- 🚨 `:rotating_light:` - Fix compiler / linter warnings
- 💚 `:green_heart:` - Fix CI build
- ✏️ `:pencil2:` - Fix typos

### Refactoring
- 🔥 `:fire:` - Remove code or files
- 🚚 `:truck:` - Move or rename resources (files, paths, routes)
- ⚰️ `:coffin:` - Remove dead code
- 🏗️ `:building_construction:` - Make architectural changes
- 🔇 `:mute:` - Remove logs
- 🏷️ `:label:` - Add or update types

### Tests
- 🧪 `:test_tube:` - Add a failing test

### Build & Dependencies
- ⬆️ `:arrow_up:` - Upgrade dependencies
- ⬇️ `:arrow_down:` - Downgrade dependencies
- ➕ `:heavy_plus_sign:` - Add a dependency
- ➖ `:heavy_minus_sign:` - Remove a dependency
- 📌 `:pushpin:` - Pin dependencies to specific versions
- 🧱 `:bricks:` - Infrastructure related changes

### Chores & Maintenance
- 🔧 `:wrench:` - Add or update configuration files
- 🔨 `:hammer:` - Add or update development scripts
- 🙈 `:see_no_evil:` - Add or update .gitignore file
- 📄 `:page_facing_up:` - Add or update license
- 🔖 `:bookmark:` - Release / version tags
- 🧑‍💻 `:technologist:` - Improve developer experience

### Documentation
- 💡 `:bulb:` - Add or update comments in source code

### Special
- 💥 `:boom:` - Introduce breaking changes (use with any type + `!`)
- 🚧 `:construction:` - Work in progress (use sparingly)

## Choosing the Right Emoji

1. Start with the **primary emoji** for your commit type
2. If a more specific emoji better describes the intent, use that instead
3. When in doubt, use the primary emoji for the type
4. For breaking changes, **always use 💥** regardless of the underlying type

## Examples

```
✨ feat(auth): add OAuth2 login support
🐛 fix: resolve memory leak in image processing
💥 feat!: change user id format from int to uuid
⬆️ build(deps): upgrade React to v19
🚑️ fix: critical auth bypass vulnerability
🎉 feat: initial project setup
```

## Quick Reference

| Intent                  | Commit Format                                    |
|-------------------------|--------------------------------------------------|
| New feature             | `✨ feat: add [feature]`                         |
| Bug fix                 | `🐛 fix: resolve [issue]`                        |
| Critical hotfix         | `🚑️ fix: [critical fix]`                         |
| Security fix            | `🔒️ fix: [security issue]`                       |
| Documentation           | `📝 docs: update [doc]`                          |
| Refactor                | `♻️ refactor: [refactor description]`            |
| Performance             | `⚡️ perf: improve [area]`                        |
| Tests                   | `✅ test: add tests for [feature]`               |
| Dependencies            | `⬆️ build(deps): upgrade [package]`              |
| CI/CD                   | `👷 ci: update [pipeline]`                       |
| Config                  | `🔧 chore: update [config]`                      |
| Breaking change         | `💥 feat!: [breaking change]`                    |
| Initial commit          | `🎉 feat: initial project setup`                 |

## CLI Tools

### gitmoji-cli

Install [gitmoji-cli](https://github.com/carloscuesta/gitmoji-cli) for interactive commits:

```bash
npm i -g gitmoji-cli
gitmoji -c  # Interactive commit
```

### gitmojis npm package

For programmatic use:

```bash
npm i gitmojis
```
