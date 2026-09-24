#!/usr/bin/env node
// scripts/eval/run-eval.mjs — golden-fixture harness for LLM output quality.
//
// Why: unit tests can't catch LLM output regressions (a prompt tweak that makes
// output worse doesn't throw). This scores ARTIFACTS — captured model outputs
// stored as fixtures — against scorers, never app code. That's what keeps it
// stack-agnostic: any project (Python, Node, Go...) can write its outputs to a
// directory and score them the same way. Zero npm deps; runs on the runner's
// default Node (precedent: scripts/sync-agent-models.mjs).
//
// See .claude/references/llm-evals.md for the fixture/scorer schema and the
// judge skip semantics in detail.
//
// Usage:
//   node scripts/eval/run-eval.mjs                       # run every suite under evals/
//   node scripts/eval/run-eval.mjs <suite>                # run one suite
//   node scripts/eval/run-eval.mjs <suite> --dir=<path>   # score fixtures from <path> instead
//   node scripts/eval/run-eval.mjs --no-judge             # skip judge scorers (intentional)
//   node scripts/eval/run-eval.mjs --require-judge        # exit 3 if any judge row was skipped
//   node scripts/eval/run-eval.mjs --record               # append summary to .eval-history/<suite>.jsonl
//   node scripts/eval/run-eval.mjs trend <suite> [--last=N]
//
// Env:
//   ANTHROPIC_API_KEY   judge scorer credential (never read from a .env file —
//                       inject via the WRAPPER, see secrets-hygiene.md)
//   EVAL_JUDGE_MODEL    judge model id — never hardcoded; unset means "no judge"
//   EVAL_MAX_JUDGE_CALLS  cost cap, default 20
//   EVAL_THRESHOLD        aggregate pass gate, default 1.0

import { readFileSync, readdirSync, existsSync, mkdirSync, appendFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(scriptDir, '..', '..');
const evalsRoot = join(repoRoot, 'evals');
const historyRoot = join(repoRoot, '.eval-history');

const JUDGE_SYSTEM_PROMPT =
  'You are a strict evaluation judge. Apply the given rubric to the OUTPUT and ' +
  'reply with exactly one word on the first line: PASS or FAIL. You may add a ' +
  'one-sentence reason on a second line. Never say anything else on line one.';

// ---------------------------------------------------------------------------
// Arg parsing
// ---------------------------------------------------------------------------

export function parseArgs(argv) {
  const opts = { mode: 'run', suite: null, dir: null, noJudge: false, requireJudge: false, record: false, last: 10 };
  const positional = [];
  for (const a of argv) {
    if (a === '--no-judge') opts.noJudge = true;
    else if (a === '--require-judge') opts.requireJudge = true;
    else if (a === '--record') opts.record = true;
    else if (a.startsWith('--dir=')) opts.dir = a.slice('--dir='.length);
    else if (a.startsWith('--last=')) opts.last = Math.max(1, Number(a.slice('--last='.length)) || 10);
    else if (!a.startsWith('--')) positional.push(a);
  }
  if (positional[0] === 'trend') {
    opts.mode = 'trend';
    opts.suite = positional[1] || null;
  } else if (positional[0]) {
    opts.suite = positional[0];
  }
  return opts;
}

// ---------------------------------------------------------------------------
// Fixture + scorer loading
// ---------------------------------------------------------------------------

function loadScorers(suiteDir) {
  const p = join(suiteDir, 'scorers.json');
  if (!existsSync(p)) throw new Error(`no scorers.json in ${suiteDir}`);
  const scorers = JSON.parse(readFileSync(p, 'utf8'));
  if (!Array.isArray(scorers) || scorers.length === 0) throw new Error(`${p} must be a non-empty array`);
  for (const s of scorers) {
    if (!s.id || !s.type) throw new Error(`scorer missing id/type in ${p}: ${JSON.stringify(s)}`);
    if (!['regex', 'length', 'command', 'judge'].includes(s.type)) throw new Error(`unknown scorer type "${s.type}" (${s.id})`);
  }
  return scorers;
}

function loadFixtures(dir) {
  if (!existsSync(dir)) throw new Error(`fixture dir not found: ${dir}`);
  const files = readdirSync(dir).filter((f) => /^(good|defect)-.*\.json$/.test(f)).sort();
  if (files.length === 0) throw new Error(`no good-*.json / defect-*.json fixtures in ${dir}`);
  return files.map((file) => {
    let raw;
    try {
      raw = JSON.parse(readFileSync(join(dir, file), 'utf8'));
    } catch (err) {
      throw new Error(`fixture ${file} is not valid JSON: ${err.message}`);
    }
    if (typeof raw.output !== 'string') throw new Error(`fixture ${file}: "output" must be a string`);
    if (!raw.provenance) throw new Error(`fixture ${file}: "provenance" is required (where did this sample come from?)`);
    const shouldFail = raw.expect?.shouldFail ?? [];
    if (!Array.isArray(shouldFail)) throw new Error(`fixture ${file}: expect.shouldFail must be an array`);
    const isGood = file.startsWith('good-');
    if (isGood && shouldFail.length > 0) throw new Error(`fixture ${file}: good-* fixtures must have an empty shouldFail`);
    if (!isGood && shouldFail.length === 0) throw new Error(`fixture ${file}: defect-* fixtures must name at least one shouldFail scorer`);
    return { file, output: raw.output, provenance: raw.provenance, shouldFail };
  });
}

// ---------------------------------------------------------------------------
// Scorers
// ---------------------------------------------------------------------------

export function scoreRegex(scorer, output) {
  const flags = scorer.flags ?? '';
  if (scorer.mustMatch && !new RegExp(scorer.mustMatch, flags).test(output)) {
    return { pass: false, detail: `did not match /${scorer.mustMatch}/${flags}` };
  }
  if (scorer.mustNotMatch && new RegExp(scorer.mustNotMatch, flags).test(output)) {
    return { pass: false, detail: `matched forbidden /${scorer.mustNotMatch}/${flags}` };
  }
  return { pass: true, detail: 'ok' };
}

export function scoreLength(scorer, output) {
  const len = output.length;
  if (typeof scorer.min === 'number' && len < scorer.min) return { pass: false, detail: `length ${len} < min ${scorer.min}` };
  if (typeof scorer.max === 'number' && len > scorer.max) return { pass: false, detail: `length ${len} > max ${scorer.max}` };
  return { pass: true, detail: `length ${len} ok` };
}

// Stack-agnostic extension point: any executable, any language. Output goes on
// stdin; exit 0 = pass. Spawned without a shell, args as an array — no string
// interpolation into a shell (security-core.md, no command injection surface).
export function scoreCommand(scorer, output) {
  return new Promise((resolve) => {
    // cwd pinned to repoRoot regardless of the caller's cwd, so a scorer's
    // relative script path (e.g. "evals/_example/scorers/x.mjs") resolves the
    // same way whether invoked via `make eval` or `node --test`.
    const child = spawn(scorer.command, scorer.args ?? [], { stdio: ['pipe', 'pipe', 'pipe'], cwd: repoRoot });
    let stderr = '';
    child.stderr.on('data', (d) => { stderr += d; });
    child.on('error', (err) => resolve({ pass: false, error: true, detail: `spawn failed: ${err.message}` }));
    child.on('close', (code) => {
      resolve({ pass: code === 0, detail: code === 0 ? 'exit 0' : `exit ${code}${stderr ? `: ${stderr.trim()}` : ''}` });
    });
    child.stdin.write(output);
    child.stdin.end();
  });
}

function parseVerdict(text) {
  const firstLine = String(text || '').trim().split('\n')[0]?.trim().toUpperCase();
  if (firstLine === 'PASS') return true;
  if (firstLine === 'FAIL') return false;
  return null;
}

export function buildJudgePrompt(rubric, output) {
  return `RUBRIC:\n${rubric}\n\nOUTPUT:\n${output}`;
}

async function defaultJudgeFetch({ prompt, model, apiKey }) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify({
      model,
      max_tokens: 100,
      temperature: 0, // a grader, not a generator — the same output must judge the same way every run
      system: [{ type: 'text', text: JUDGE_SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } }],
      messages: [{ role: 'user', content: prompt }],
    }),
    signal: AbortSignal.timeout(30000),
  });
  if (!res.ok) throw new Error(`anthropic ${res.status}: ${(await res.text().catch(() => '')).slice(0, 200)}`);
  const data = await res.json();
  return data?.content?.[0]?.text || '';
}

// judgeState is shared mutable run-level state: call count, cap, credentials,
// and the injectable fetch impl (tests pass a stub — never a real network call).
async function scoreJudge(scorer, output, judgeState) {
  if (judgeState.noJudge) return { skip: true, reason: '--no-judge' };
  if (!judgeState.apiKey || !judgeState.model) return { skip: true, reason: 'no ANTHROPIC_API_KEY / EVAL_JUDGE_MODEL' };
  if (judgeState.calls >= judgeState.cap) { judgeState.capHit = true; return { skip: true, reason: 'CAP HIT' }; }

  judgeState.calls += 1;
  const prompt = buildJudgePrompt(scorer.rubric, output);
  let text;
  try {
    text = await judgeState.fetchImpl({ prompt, model: judgeState.model, apiKey: judgeState.apiKey });
  } catch (err) {
    return { pass: false, error: true, detail: `judge call failed: ${err.message}` };
  }
  const verdict = parseVerdict(text);
  if (verdict === null) {
    // Unparseable output is a loud error, never a silent pass (error-handling.md).
    return { pass: false, error: true, detail: `unparseable judge verdict: ${JSON.stringify(text).slice(0, 120)}` };
  }
  return { pass: verdict, detail: text.trim().slice(0, 200) };
}

async function runScorer(scorer, output, judgeState) {
  try {
    if (scorer.type === 'regex') return { id: scorer.id, ...scoreRegex(scorer, output) };
    if (scorer.type === 'length') return { id: scorer.id, ...scoreLength(scorer, output) };
    if (scorer.type === 'command') return { id: scorer.id, ...(await scoreCommand(scorer, output)) };
    if (scorer.type === 'judge') return { id: scorer.id, ...(await scoreJudge(scorer, output, judgeState)) };
  } catch (err) {
    // Isolate scorer failures: a throwing scorer is a loud failed row, not a
    // crash that masks every other result in the suite.
    return { id: scorer.id, pass: false, error: true, detail: `scorer threw: ${err.message}` };
  }
  throw new Error(`unhandled scorer type ${scorer.type}`);
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

export async function evaluateFixture(fixture, scorers, judgeState) {
  const wanted = new Set(fixture.shouldFail);
  const rows = [];
  for (const scorer of scorers) {
    rows.push(await runScorer(scorer, fixture.output, judgeState));
  }
  let total = 0;
  let met = 0;
  let skipped = 0;
  const mismatches = [];
  for (const row of rows) {
    if (row.skip) { skipped += 1; continue; } // excluded from the aggregate entirely — never counted as a mismatch
    total += 1;
    const expectFail = wanted.has(row.id);
    const actualFail = !row.pass;
    if (expectFail === actualFail) met += 1;
    else mismatches.push(`${row.id} expected=${expectFail ? 'fail' : 'pass'} actual=${actualFail ? 'fail' : 'pass'} (${row.detail})`);
  }
  return { file: fixture.file, provenance: fixture.provenance, rows, total, met, skipped, matched: mismatches.length === 0, mismatches };
}

async function runSuite(name, dir, judgeState) {
  const suiteDir = join(evalsRoot, name);
  const scorers = loadScorers(suiteDir);
  const fixtures = loadFixtures(dir ?? suiteDir);
  const results = [];
  for (const fixture of fixtures) results.push(await evaluateFixture(fixture, scorers, judgeState));
  const total = results.reduce((n, r) => n + r.total, 0);
  const met = results.reduce((n, r) => n + r.met, 0);
  const skipped = results.reduce((n, r) => n + r.skipped, 0);
  const aggregate = total > 0 ? met / total : 1;
  return { name, results, total, met, skipped, aggregate };
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

function judgeLine(judgeState) {
  if (judgeState.calls > 0) {
    return `judge: ran ${judgeState.calls} call(s)${judgeState.capHit ? ' — CAP HIT, remaining judge expectations unverified' : ''}`;
  }
  if (judgeState.noJudge) return `judge: SKIPPED (--no-judge) — ${judgeState.skippedExpectations} expectations unverified`;
  return `judge: SKIPPED (no ANTHROPIC_API_KEY / EVAL_JUDGE_MODEL) — ${judgeState.skippedExpectations} expectations unverified`;
}

function printSuite(suite) {
  const lines = [`\nSuite: ${suite.name}`, '='.repeat(60)];
  for (const r of suite.results) {
    lines.push(`${r.matched ? '✓' : '✗'} ${r.file}  (${r.provenance})`);
    for (const m of r.mismatches) lines.push(`    ✗ ${m}`);
  }
  lines.push('-'.repeat(60));
  lines.push(`aggregate ${suite.total ? (suite.met / suite.total).toFixed(3) : '1.000'} (${suite.met}/${suite.total} met, ${suite.skipped} skipped)`);
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// Trend
// ---------------------------------------------------------------------------

function runTrend(suite, last) {
  const p = join(historyRoot, `${suite}.jsonl`);
  if (!existsSync(p)) return { code: 1, output: `no history at ${p} — run with --record first` };
  const lines = readFileSync(p, 'utf8').trim().split('\n').filter(Boolean).slice(-last);
  const out = lines.map((l) => {
    const row = JSON.parse(l);
    return `${row.at}  aggregate=${row.aggregate}  ${row.judge}`;
  });
  return { code: 0, output: out.join('\n') };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

export async function main(argv, overrides = {}) {
  const opts = parseArgs(argv);
  const env = overrides.env ?? process.env;

  if (opts.mode === 'trend') {
    if (!opts.suite) return { code: 2, output: 'usage: run-eval.mjs trend <suite> [--last=N]' };
    return runTrend(opts.suite, opts.last);
  }

  const threshold = Number(env.EVAL_THRESHOLD ?? 1.0);
  const cap = Number(env.EVAL_MAX_JUDGE_CALLS ?? 20);
  const judgeState = {
    noJudge: opts.noJudge,
    apiKey: env.ANTHROPIC_API_KEY,
    model: env.EVAL_JUDGE_MODEL,
    fetchImpl: overrides.fetchImpl ?? defaultJudgeFetch,
    cap,
    calls: 0,
    capHit: false,
    skippedExpectations: 0,
  };

  let suiteNames;
  try {
    suiteNames = opts.suite ? [opts.suite] : readdirSync(evalsRoot).filter((f) => existsSync(join(evalsRoot, f, 'scorers.json')));
  } catch (err) {
    return { code: 2, output: `FATAL: ${err.message}` };
  }
  if (suiteNames.length === 0) return { code: 2, output: `FATAL: no suites found under ${evalsRoot}` };

  const suites = [];
  try {
    for (const name of suiteNames) suites.push(await runSuite(name, opts.dir, judgeState));
  } catch (err) {
    return { code: 2, output: `FATAL: ${err.message}` };
  }

  // Count skipped expectations after the run so the judge summary line is accurate
  // even though skips happen scorer-by-scorer inside evaluateFixture.
  judgeState.skippedExpectations = suites.reduce((n, s) => n + s.skipped, 0);

  const totalMet = suites.reduce((n, s) => n + s.met, 0);
  const totalAll = suites.reduce((n, s) => n + s.total, 0);
  const aggregate = totalAll > 0 ? totalMet / totalAll : 1;
  const passed = aggregate >= threshold;

  const lines = suites.map(printSuite);
  lines.push('');
  lines.push(judgeLine(judgeState));
  lines.push(`overall aggregate ${aggregate.toFixed(3)} (threshold ${threshold}) — ${passed ? 'PASS' : 'FAIL'}`);

  if (opts.record) {
    mkdirSync(historyRoot, { recursive: true });
    for (const s of suites) {
      const row = { at: new Date().toISOString(), aggregate: s.total ? s.met / s.total : 1, judge: judgeLine(judgeState) };
      appendFileSync(join(historyRoot, `${s.name}.jsonl`), JSON.stringify(row) + '\n');
    }
  }

  const judgeUnverified = judgeState.skippedExpectations > 0 || judgeState.capHit;
  if (opts.requireJudge && judgeUnverified) {
    lines.push('--require-judge: judge expectations were skipped or capped — failing closed');
    return { code: 3, output: lines.join('\n') };
  }
  return { code: passed ? 0 : 1, output: lines.join('\n') };
}

const isMain = process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url;
if (isMain) {
  main(process.argv.slice(2)).then((result) => {
    process.stdout.write(result.output + '\n');
    process.exit(result.code);
  }).catch((err) => {
    process.stderr.write(`FATAL: ${err.stack || err.message}\n`);
    process.exit(2);
  });
}
