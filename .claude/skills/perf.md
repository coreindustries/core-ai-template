# /perf

Profile, benchmark, and optimize application performance.

## Usage

```
/perf [target] [--profile] [--benchmark] [--lighthouse]
```

## Arguments

- `target`: File, endpoint, component, or area to analyze
- `--profile`: Run profiler and identify bottlenecks
- `--benchmark`: Run benchmarks and compare
- `--lighthouse`: Run Lighthouse audit (web only)

## Instructions

When this skill is invoked:

### Agent Behavior

**Autonomy:**
- Identify bottlenecks and implement optimizations
- Measure before and after to prove improvement
- Follow platform-specific best practices

**Safety:**
- Never optimize without measuring first
- Keep optimizations readable — don't sacrifice clarity
- Run tests after every optimization to prevent regressions

### Performance Process

#### Phase 1: Measure Baseline

Establish current performance metrics before changing anything.

**Web (Next.js / React):**
```bash
# Lighthouse CI
npx lighthouse http://localhost:3000 --output json --output-path ./perf-baseline.json

# Bundle analysis
npx @next/bundle-analyzer
# or
npx webpack-bundle-analyzer stats.json
```

**Python (FastAPI):**
```bash
# Endpoint profiling
uv run python -m cProfile -o profile.out src/{project}/main.py
uv run py-spy record -o profile.svg -- python src/{project}/main.py

# Load testing
uv run locust -f tests/load/locustfile.py
```

**iOS:**
```
Instruments → Time Profiler, Allocations, Network
Xcode → Debug Navigator → CPU / Memory / Network gauges
```

**Android:**
```
Android Studio → Profiler → CPU / Memory / Network
./gradlew benchmark
```

#### Phase 2: Identify Bottlenecks

Analyze profiling results and categorize:

| Category | Symptoms | Common Causes |
|----------|----------|---------------|
| **Slow queries** | High DB time, N+1 | Missing indexes, unoptimized joins |
| **Memory leaks** | Growing memory, OOM | Unclosed connections, retained references |
| **Bundle size** | Slow page load | Large dependencies, no tree-shaking |
| **Render perf** | Janky UI, low FPS | Unnecessary re-renders, large lists |
| **Network** | Slow API calls | No caching, large payloads, no compression |

#### Phase 3: Optimize

Apply targeted fixes based on findings:

**Database:**
- Add missing indexes
- Fix N+1 queries (use eager loading / joins)
- Add query result caching
- Optimize query structure

**API:**
- Add response caching headers
- Implement pagination
- Compress responses (gzip/brotli)
- Use connection pooling

**Frontend:**
- Lazy load components and routes
- Optimize images (next/image, WebP, sizing)
- Reduce bundle size (dynamic imports, tree-shaking)
- Memoize expensive computations

**Mobile:**
- Use `FlatList` / `LazyColumn` / `LazyVStack` for lists
- Optimize image loading and caching
- Reduce main thread work
- Minimize bridge calls (React Native)

#### Phase 4: Verify

Measure again and compare:

```markdown
## Performance Comparison

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| API Response (p95) | 450ms | 120ms | -73% |
| Bundle Size | 1.2MB | 680KB | -43% |
| Lighthouse Score | 62 | 94 | +52% |
| Memory Usage | 256MB | 180MB | -30% |
| DB Query Count | 47 | 12 | -74% |
```

Run full test suite to confirm no regressions:
```bash
{test_all_command}
```

### Performance Report Format

```markdown
## Performance Report

**Target:** {what was analyzed}
**Date:** {date}

### Baseline Metrics
{metrics before optimization}

### Bottlenecks Found
1. {bottleneck}: {impact}
2. {bottleneck}: {impact}

### Optimizations Applied
1. {change}: {expected improvement}
2. {change}: {expected improvement}

### Results
{metrics after optimization with comparison}

### Recommendations
- {further optimizations not yet applied}
```

## Example Output

```
$ /perf /api/users --profile

Profiling /api/users endpoint...

Baseline (10 requests, p95):
  Response time: 450ms
  DB queries: 47
  Memory: 45MB

Bottlenecks found:
  1. N+1 query on user.posts (38 extra queries)
  2. No index on users.email (full table scan)
  3. Serializing unused fields (posts.body)

Applying fixes...
  Added eager loading for user.posts
  Created index on users.email
  Added field selection to query

Results:
  Response time: 120ms (-73%)
  DB queries: 3 (-94%)
  Memory: 38MB (-16%)

All tests passing (142/142).
```
