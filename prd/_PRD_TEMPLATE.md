---
prd_version: "1.0"
status: "Draft" # Draft | Active | Deprecated
priority: "P1" # P0 (Critical) | P1 (High) | P2 (Medium) | P3 (Low)
last_updated: "YYYY-MM-DD"
owner: "@github-handle"
depends_on: [] # e.g., ["PRD-01", "PRD-03"]
estimated_effort: "S" # S (<1 day) | M (1-3 days) | L (3-5 days) | XL (1-2 weeks)
---

# PRD-{XX} – {Feature Name}

## 1. Purpose

**Problem:** What problem does this solve? Why does it matter now?

**Goal:** What does success look like when this is shipped?

**Users:** Who benefits from this feature?

## 2. User Stories

> Write concrete user stories. AI agents use these to understand expected behavior and generate accurate tests.

- As a {role}, I want to {action} so that {benefit}
- As a {role}, I want to {action} so that {benefit}

## 3. Functional Requirements

### FR1 – {Requirement Name}

**Description:** {What the system must do}

**Acceptance Criteria:**
- [ ] {Specific, testable condition}
- [ ] {Specific, testable condition}
- [ ] {Specific, testable condition}

### FR2 – {Requirement Name}

**Description:** {What the system must do}

**Acceptance Criteria:**
- [ ] {Specific, testable condition}
- [ ] {Specific, testable condition}

## 4. Technical Implementation

### 4.1 Architecture

**Approach:** {High-level approach and key design decisions}

**Components affected:**
- `src/{project}/{component}` — {what changes and why}
- `src/{project}/{component}` — {what changes and why}

**New components:**
- `src/{project}/{component}` — {purpose}

### 4.2 API Contracts

> Skip this section if no API changes. Mark "N/A".

**New Endpoints:**

```
{METHOD} /api/v1/{resource}
  Request:  { field: type }
  Response: { field: type }
  Errors:   400 (validation), 401 (unauthorized), 404 (not found)
```

**Modified Endpoints:**
- `{METHOD} /api/v1/{resource}` — {what changes}

### 4.3 Database Schema

> Skip this section if no schema changes. Mark "N/A".

**New models:**

```sql
CREATE TABLE {table_name} (
  id VARCHAR(255) PRIMARY KEY,
  -- fields with types and constraints
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

**Modified models:**
- `{table_name}` — add `{field}` ({type}, {constraints})

**Indexes:** {any new indexes needed}

**Migration:** Create migration with `{migration_command} --name {descriptive_name}`. Test rollback locally before committing.

## 5. Configuration

> Skip if no new configuration. Mark "N/A".

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `{ENV_VAR}` | {Purpose} | {default or none} | Yes/No |

## 6. Error Handling

| Error Case | Response | User Message | Log Level |
|------------|----------|--------------|-----------|
| {Scenario} | {HTTP status or action} | {User-facing message} | error/warn |
| {Scenario} | {HTTP status or action} | {User-facing message} | error/warn |

## 7. Testing Strategy

**Unit tests:**
- {What to test in isolation — business logic, validation, transformations}

**Integration tests:**
- {What to test with real dependencies — DB operations, API endpoints, external services}

**Edge cases:**
- {Important edge cases to cover}

## 8. Security Considerations

> Skip if no security implications. Mark "N/A".

- [ ] {Authentication/authorization changes}
- [ ] {Input validation requirements}
- [ ] {Data sensitivity — PII, encryption needs}
- [ ] {Audit logging events to add}

## 9. Performance Considerations

> Skip if no performance implications. Mark "N/A".

- {Expected load / data volume}
- {Caching strategy}
- {Query optimization needs}

## 10. Dependencies & Risks

**Prerequisites:**
- {Other PRDs, services, or infrastructure that must exist first}

**Risks:**
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| {Risk} | Low/Med/High | Low/Med/High | {How to mitigate} |

## 11. Rollback Plan

- {How to safely revert this feature if issues arise post-deploy}
- {Data migration rollback considerations}
- {Feature flag to disable without redeploying, if applicable}

## 12. Future Enhancements

- {Potential improvements not in scope for this PRD}
- {Features to consider for a follow-up PRD}
