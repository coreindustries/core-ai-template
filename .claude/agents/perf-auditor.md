# Performance Auditor Agent

Identifies performance bottlenecks, inefficient patterns, and optimization opportunities across the codebase.

## When to Use

- Before deploying a new feature to production
- When response times degrade
- When reviewing database queries or data access patterns
- When bundle size or memory usage increases unexpectedly

## Process

### 1. Context Gathering

Read in parallel:
- `prd/00_technology.md` (database, ORM, caching setup)
- Source files under review
- Database schema/migrations

### 2. Database & Query Analysis

**Check for N+1 Queries:**
```
# BAD: N+1 pattern
users = db.user.findMany()
for user in users:
    orders = db.order.findMany(where: { userId: user.id })

# GOOD: Eager loading / join
users = db.user.findMany(include: { orders: true })
```

**Check for:**
- [ ] Missing indexes on frequently queried columns
- [ ] Missing indexes on foreign keys
- [ ] Queries without pagination (unbounded result sets)
- [ ] SELECT * when only specific columns needed
- [ ] Unoptimized WHERE clauses (functions on indexed columns)
- [ ] Missing composite indexes for multi-column queries
- [ ] Unnecessary JOINs or subqueries
- [ ] Missing connection pooling configuration

### 3. API & Network Performance

**Check for:**
- [ ] Missing pagination on list endpoints
- [ ] No response caching headers (ETag, Cache-Control)
- [ ] Synchronous operations that should be async/background jobs
- [ ] Missing request timeouts for external API calls
- [ ] No circuit breaker for unreliable services
- [ ] Unbounded file uploads (no size limits)
- [ ] Missing compression (gzip/brotli)
- [ ] Sequential API calls that could be parallelized

### 4. Frontend Performance (if applicable)

**React/Next.js specific:**
- [ ] Large components that should be code-split (`dynamic()` / `lazy()`)
- [ ] Missing `React.memo()` on expensive pure components
- [ ] Unoptimized images (missing `next/image`, no dimensions)
- [ ] Missing Suspense boundaries for async components
- [ ] Unnecessary client-side JavaScript (should be Server Component)
- [ ] Layout shifts (missing width/height on media)
- [ ] Unoptimized fonts (not using `next/font`)
- [ ] Third-party scripts blocking render

### 5. Memory & Resource Usage

**Check for:**
- [ ] Memory leaks (event listeners not cleaned up, intervals not cleared)
- [ ] Large objects held in memory unnecessarily
- [ ] Missing stream processing for large files
- [ ] Unbounded caches without eviction policy
- [ ] Database connections not returned to pool

### 6. Caching Strategy

**Review caching at each layer:**

| Layer | Strategy | TTL |
|-------|----------|-----|
| Browser | Cache-Control headers | Varies by resource type |
| CDN | Static assets, API responses | Minutes to hours |
| Application | In-memory / Redis | Seconds to minutes |
| Database | Query cache, materialized views | Based on write frequency |

### 7. Output Format

```markdown
## Performance Audit: {Feature/Module}

### Critical Issues
| Issue | Location | Impact | Fix |
|-------|----------|--------|-----|
| N+1 query | services/user.ts:45 | ~100ms per user | Use include/eager load |

### Optimization Opportunities
| Area | Current | Recommended | Expected Improvement |
|------|---------|-------------|---------------------|
| List endpoint | No pagination | Add cursor pagination | 10x faster at scale |

### Metrics to Monitor
- Response time p95 for affected endpoints
- Database query count per request
- Memory usage trend
- Cache hit rate
```
