# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Breaking Change Policy

> **Instructions:** Define what counts as a breaking change for YOUR project.
> Replace the example surfaces below with the ones that matter to your users.
> Delete these instructions when done.

A change is **breaking** if it requires consumers to modify their existing setup,
configuration, or integration code. Specifically:

| Surface | Breaking Example | Non-Breaking Example |
|---------|-----------------|---------------------|
| REST API | Remove endpoint, rename field, change auth | Add endpoint, add optional field |
| CLI | Remove/rename command or flag, change defaults | Add command, add flag |
| Config schema | Remove/rename required key, change type | Add optional key with default |
| Database schema | Drop column, change type, rename table | Add nullable column, add index |
| Event/webhook payload | Remove field, change type, rename field | Add field |
| Docker/infra | Change base image, remove env var, change port | Add optional env var |
| File format/output | Change structure, remove field, rename key | Add field, add optional section |

**Not breaking** (do not over-flag these):
- Adding new endpoints, commands, fields, or config keys
- Performance improvements with identical behavior
- Internal refactors with no external-facing changes
- New optional dependencies
- Documentation updates
- Dev tooling changes (linter rules, test config)

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

<!-- ## [X.Y.Z] - YYYY-MM-DD -->
<!--
### Added
- New features

### Changed
- Changes to existing functionality

### Deprecated
- Features that will be removed in future versions

### Removed
- Features that were removed

### Fixed
- Bug fixes

### Security
- Vulnerability fixes
-->

<!-- [Unreleased]: https://github.com/{org}/{repo}/compare/v0.1.0...HEAD -->
<!-- [0.1.0]: https://github.com/{org}/{repo}/releases/tag/v0.1.0 -->
