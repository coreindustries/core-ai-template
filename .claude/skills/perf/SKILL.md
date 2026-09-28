---
name: perf
description: >-
  Profile, benchmark, and optimize performance, measuring before and after so the change
  is attributable. Use when something is measurably slow or a latency budget is missed.
  Do not use for speculative optimization without a measurement, and do not use it to
  scan for known bottleneck patterns statically — that is the `perf-auditor` agent.
---

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

## Workflow

Read `prd/00_technology.md` and `.claude/rules/delivery-contract.md` and `testing.md`.

1. Establish the user's performance question and representative workload. `--profile` identifies bottlenecks; `--benchmark` compares measurements; `--lighthouse` audits the relevant web surface with project tooling. A measurement-only request does not authorize optimization.
2. Capture baseline revision, workload, environment, warm/cold state, sample size and relevant latency/resource metrics. Use existing tools before adding dependencies or infrastructure.
3. Explain the measured cause and simplest supported change. A language rewrite, new service/repository/provider boundary or isolation layer needs measured need, a simpler alternative, compatibility costs and incremental retirement/rollback. Missing evidence calls for a bounded experiment.
4. Implement only authorized changes. Repeat comparable measurements and affected correctness checks; broaden for integration risk or required gates. Separate observed improvement from noise and remaining uncertainty.
5. Token, tool-call and cost claims require actual usage records and comparable real runs. Output bytes, line counts and PR counts are not proxies for those metrics or engineering effort. Report measurements, conditions and limitations without fabricated sample numbers.
