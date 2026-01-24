# AI Agent Development Patterns

**Source:** PRD 01 - Technical Standards, Sections 4 & 6

## Autonomy and Persistence

**REQUIRED:** AI agents MUST operate autonomously and persist until tasks are fully complete.

**Autonomous Senior Engineer Mindset:**
- Once given direction, proactively gather context, plan, implement, test, and refine
- No waiting for additional prompts at each step
- Complete tasks end-to-end within a single turn whenever feasible
- Bias to action: default to implementing with reasonable assumptions

**Persistence Criteria:**
- Don't stop at analysis or partial fixes
- Carry changes through implementation, verification, and clear explanation
- Continue until working code is delivered, not just a plan
- Only pause if explicitly redirected or truly blocked

**Anti-patterns to Avoid:**
- Stopping after creating a plan without implementing
- Requesting clarification on details that can be reasonably inferred
- Implementing halfway and asking "should I continue?"
- Excessive looping on the same files without progress

## Bias to Action

**REQUIRED:** Agents MUST default to implementation over clarification.

**When to Implement Immediately:**
- Requirements are reasonably clear (even if some details missing)
- Multiple valid approaches exist (choose the most standard one)
- Implementation patterns exist in the codebase
- Missing details can be inferred from context

**When to Ask Questions:**
- Critical architectural decisions with significant tradeoffs
- Conflicting requirements that need resolution
- Truly blocked on external information
- User preference matters significantly and isn't inferrable

**Example Decision Tree:**
```
User: "Add user authentication"
├─ API approach? → JWT (standard, matches existing patterns)
├─ Password hashing? → bcrypt/argon2 (industry standard)
├─ Session storage? → Redis (if already configured)
└─ IMPLEMENT with these defaults ✓

User: "Add payment processing"
├─ Provider? → Could be Stripe, PayPal, Square... → ASK ✓
```

## Correctness Over Speed

**REQUIRED:** Prioritize correctness, clarity, and reliability over implementation speed.

**Quality Criteria:**
- Cover the root cause or core ask, not just symptoms
- Avoid risky shortcuts and speculative changes
- Investigate before implementing to ensure understanding
- No messy hacks just to get code working

**Discerning Engineer Approach:**
- Read enough context before changing files
- Understand existing patterns and follow them
- Consider edge cases and error paths
- Write production-ready code, not just "working" code

## Comprehensiveness and Completeness

**REQUIRED:** Ensure changes are comprehensive across all relevant surfaces.

**Example:**
```
Task: Add "archived" status to users

Incomplete (❌):
- Only add field to database schema

Complete (✓):
- Add field to database schema
- Generate migration
- Update create/update models
- Add filtering in service layer
- Add query param to API endpoint
- Update tests for archived users
- Add audit logging for archive action
```

## Behavior-Safe Defaults

**REQUIRED:** Preserve intended behavior and UX.

- Don't change existing behavior without explicit request
- Gate intentional behavior changes with feature flags or configuration
- Add tests when behavior shifts
- Document behavioral changes in commit messages

**Example:**
```javascript
// UNSAFE: Changes default behavior
getUsers(includeDeleted = true)  // Was false

// SAFE: Preserves existing behavior
getUsers(includeDeleted = false, includeArchived = false)  // New parameter
```

## Exploration Patterns

### Think First, Batch Everything

**REQUIRED:** Plan all file reads before executing, then batch them in parallel.

**Pattern:**
1. **Think**: Decide ALL files/resources needed
2. **Batch**: Read all files together in one parallel call
3. **Analyze**: Process results
4. **Repeat**: Only if new, unpredictable reads are needed

**Example:**
```javascript
// BAD: Sequential reads
read("api/routes.js")
// ... analyze ...
read("services/user.js")
// ... analyze ...

// GOOD: Parallel batch
read_parallel([
    "api/routes.js",
    "services/user.js",
    "models/user.js"
])
// ... analyze all together ...
```

### Maximize Parallelism

**REQUIRED:** Always read files in parallel unless logically unavoidable.

**Applies To:**
- File reads
- File searches
- Directory listings
- Git operations

**Only Sequential If:**
- You truly cannot know the next file without seeing a result first
- Example: Reading a config file to determine which modules to load next

### Efficient, Coherent Edits

**REQUIRED:** Batch logical edits together, not repeated micro-edits.

- Read enough context before changing a file
- Make all related changes in one pass
- Avoid thrashing with many tiny patches to the same file
