// scripts/eval/tests/run-eval.test.mjs — node:test, zero deps.
//
// Lives under scripts/eval/tests/ (not scripts/tests/) to avoid colliding with
// a parallel PR's test tree. Run: node --test scripts/eval/tests/
//
// No real network calls: judge scorer tests inject a stub fetchImpl through
// main()'s overrides parameter. ANTHROPIC_API_KEY is never read from the real
// environment in these tests — each test passes its own `env` object so a key
// that happens to be set in the runner's shell can never turn an offline test
// into a live, billed call.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, mkdirSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { main, parseArgs, scoreRegex, scoreLength, scoreCommand, evaluateFixture, buildJudgePrompt } from '../run-eval.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, '..', '..', '..');
const evalsRoot = join(repoRoot, 'evals');

function makeSuite({ scorers, fixtures }) {
  const suiteName = `tmp-${Math.random().toString(36).slice(2)}`;
  const dir = join(evalsRoot, suiteName);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, 'scorers.json'), JSON.stringify(scorers, null, 2));
  for (const [name, content] of Object.entries(fixtures)) {
    writeFileSync(join(dir, name), JSON.stringify(content, null, 2));
  }
  return { suiteName, dir };
}

function cleanup(dir) {
  rmSync(dir, { recursive: true, force: true });
}

// ---------------------------------------------------------------------------
// Deterministic scorers
// ---------------------------------------------------------------------------

test('regex scorer: mustMatch / mustNotMatch', () => {
  assert.equal(scoreRegex({ mustMatch: 'hello' }, 'hello world').pass, true);
  assert.equal(scoreRegex({ mustMatch: 'goodbye' }, 'hello world').pass, false);
  assert.equal(scoreRegex({ mustNotMatch: 'bad' }, 'hello world').pass, true);
  assert.equal(scoreRegex({ mustNotMatch: 'hello' }, 'hello world').pass, false);
});

test('length scorer: min / max', () => {
  assert.equal(scoreLength({ min: 5 }, 'hello').pass, true);
  assert.equal(scoreLength({ min: 6 }, 'hello').pass, false);
  assert.equal(scoreLength({ max: 5 }, 'hello').pass, true);
  assert.equal(scoreLength({ max: 4 }, 'hello').pass, false);
});

test('command scorer: exit 0 = pass, spawned without a shell', async () => {
  // A trivial script under the OS temp dir, invoked with args as an array.
  const dir = mkdtempSync(join(tmpdir(), 'eval-cmd-'));
  const scriptPath = join(dir, 'check.mjs');
  writeFileSync(scriptPath, `
    let input = '';
    process.stdin.on('data', (c) => { input += c; });
    process.stdin.on('end', () => process.exit(input.includes('ok') ? 0 : 1));
  `);
  const pass = await scoreCommand({ command: process.execPath, args: [scriptPath] }, 'this is ok');
  const fail = await scoreCommand({ command: process.execPath, args: [scriptPath] }, 'this is not');
  assert.equal(pass.pass, true);
  assert.equal(fail.pass, false);
  cleanup(dir);
});

// ---------------------------------------------------------------------------
// shouldFail semantics
// ---------------------------------------------------------------------------

test('evaluateFixture: good fixture — all scorers must pass to be matched', async () => {
  const scorers = [{ id: 's1', type: 'regex', mustNotMatch: 'bad' }];
  const good = { file: 'good-1.json', output: 'fine text', provenance: 'test', shouldFail: [] };
  const judgeState = { noJudge: true, calls: 0, cap: 20 };
  const result = await evaluateFixture(good, scorers, judgeState);
  assert.equal(result.matched, true);
  assert.equal(result.met, 1);
  assert.equal(result.total, 1);
});

test('evaluateFixture: defect fixture — the named scorer must fail to be matched', async () => {
  const scorers = [{ id: 's1', type: 'regex', mustNotMatch: 'bad' }];
  const defect = { file: 'defect-1.json', output: 'this is bad text', provenance: 'test', shouldFail: ['s1'] };
  const judgeState = { noJudge: true, calls: 0, cap: 20 };
  const result = await evaluateFixture(defect, scorers, judgeState);
  assert.equal(result.matched, true, `expected matched, got mismatches: ${result.mismatches}`);
});

test('evaluateFixture: defect fixture where the named scorer unexpectedly passes is a mismatch', async () => {
  const scorers = [{ id: 's1', type: 'regex', mustNotMatch: 'bad' }];
  const defect = { file: 'defect-1.json', output: 'this is fine text', provenance: 'test', shouldFail: ['s1'] };
  const judgeState = { noJudge: true, calls: 0, cap: 20 };
  const result = await evaluateFixture(defect, scorers, judgeState);
  assert.equal(result.matched, false);
  assert.equal(result.mismatches.length, 1);
});

test('evaluateFixture: a skipped scorer is excluded from total/met entirely (never counted as a mismatch)', async () => {
  // This is the bug the reference implementation had (a skipped judge counted
  // as a mismatch, so key-less CI stayed red). Regex scorer is set up to
  // genuinely fail its expectation; the judge scorer is skipped (--no-judge).
  // A skip must not be silently counted as either a pass or a fail.
  const scorers = [
    { id: 'det', type: 'regex', mustNotMatch: 'bad' },
    { id: 'jud', type: 'judge', rubric: 'irrelevant' },
  ];
  const fixture = { file: 'good-1.json', output: 'this is bad text', provenance: 'test', shouldFail: [] };
  const judgeState = { noJudge: true, calls: 0, cap: 20 };
  const result = await evaluateFixture(fixture, scorers, judgeState);
  assert.equal(result.skipped, 1);
  assert.equal(result.total, 1, 'skipped scorer must not be counted in total');
  assert.equal(result.met, 0, 'the real regex mismatch must still count against the aggregate');
});

// ---------------------------------------------------------------------------
// Threshold + exit codes (via main(), fixtures on disk)
// ---------------------------------------------------------------------------

test('main(): threshold failure exits 1', async () => {
  const { suiteName, dir } = makeSuite({
    scorers: [{ id: 's1', type: 'length', min: 1000 }], // impossible to satisfy — every fixture mismatches
    fixtures: {
      'good-1.json': { output: 'short', provenance: 'test', expect: { shouldFail: [] } },
    },
  });
  const result = await main([suiteName], { env: { EVAL_THRESHOLD: '1.0' } });
  assert.equal(result.code, 1);
  cleanup(dir);
});

test('main(): passing suite exits 0', async () => {
  const { suiteName, dir } = makeSuite({
    scorers: [{ id: 's1', type: 'length', min: 1 }],
    fixtures: {
      'good-1.json': { output: 'fine', provenance: 'test', expect: { shouldFail: [] } },
    },
  });
  const result = await main([suiteName], { env: {} });
  assert.equal(result.code, 0);
  cleanup(dir);
});

// ---------------------------------------------------------------------------
// Judge: no key -> SKIPPED, excluded from aggregate, exit 0
// ---------------------------------------------------------------------------

test('main(): no ANTHROPIC_API_KEY -> judge SKIPPED, excluded from aggregate, exit 0', async () => {
  const { suiteName, dir } = makeSuite({
    scorers: [
      { id: 'det', type: 'length', min: 1 },
      { id: 'jud', type: 'judge', rubric: 'PASS always' },
    ],
    fixtures: {
      // Good fixture: if the skipped judge counted as a mismatch (the bug this
      // harness deliberately avoids), this fixture would fail and drag the
      // aggregate below 1.0 even though nothing is actually wrong.
      'good-1.json': { output: 'fine text here', provenance: 'test', expect: { shouldFail: [] } },
    },
  });
  const result = await main([suiteName], { env: {} }); // no ANTHROPIC_API_KEY, no EVAL_JUDGE_MODEL
  assert.equal(result.code, 0);
  assert.match(result.output, /judge: SKIPPED \(no ANTHROPIC_API_KEY/);
  assert.match(result.output, /overall aggregate 1\.000/);
  cleanup(dir);
});

test('main(): --require-judge with no key exits 3', async () => {
  const { suiteName, dir } = makeSuite({
    scorers: [{ id: 'jud', type: 'judge', rubric: 'PASS always' }],
    fixtures: {
      'good-1.json': { output: 'fine text here', provenance: 'test', expect: { shouldFail: [] } },
    },
  });
  const result = await main([suiteName, '--require-judge'], { env: {} });
  assert.equal(result.code, 3);
  cleanup(dir);
});

// ---------------------------------------------------------------------------
// Cost cap
// ---------------------------------------------------------------------------

test('main(): EVAL_MAX_JUDGE_CALLS caps calls, remaining rows SKIPPED, "CAP HIT" printed', async () => {
  const { suiteName, dir } = makeSuite({
    scorers: [{ id: 'jud', type: 'judge', rubric: 'PASS always' }],
    fixtures: {
      'good-1.json': { output: 'fine text one', provenance: 'test', expect: { shouldFail: [] } },
      'good-2.json': { output: 'fine text two', provenance: 'test', expect: { shouldFail: [] } },
    },
  });
  let calls = 0;
  const fetchImpl = async () => { calls += 1; return 'PASS'; };
  const result = await main([suiteName], {
    env: { ANTHROPIC_API_KEY: 'fake-key-not-used-over-network', EVAL_JUDGE_MODEL: 'fake-model', EVAL_MAX_JUDGE_CALLS: '1' },
    fetchImpl,
  });
  assert.equal(calls, 1, 'only one real call should have been made — the cap must stop the second');
  assert.match(result.output, /CAP HIT/);
  cleanup(dir);
});

// ---------------------------------------------------------------------------
// Unparseable verdict -> error, not pass
// ---------------------------------------------------------------------------

test('main(): unparseable judge verdict is an error, not a silent pass', async () => {
  const { suiteName, dir } = makeSuite({
    scorers: [{ id: 'jud', type: 'judge', rubric: 'PASS always' }],
    fixtures: {
      // shouldFail is empty (a "good" fixture) — if the unparseable verdict
      // were silently treated as a pass, this fixture would still match and
      // the bug would be invisible. It must NOT match.
      'good-1.json': { output: 'fine text', provenance: 'test', expect: { shouldFail: [] } },
    },
  });
  const fetchImpl = async () => 'the model said something that is not PASS or FAIL';
  const result = await main([suiteName], {
    env: { ANTHROPIC_API_KEY: 'fake-key-not-used-over-network', EVAL_JUDGE_MODEL: 'fake-model' },
    fetchImpl,
  });
  assert.equal(result.code, 1, 'an unparseable verdict must fail the aggregate, not pass silently');
  assert.match(result.output, /unparseable judge verdict/);
  cleanup(dir);
});

test('buildJudgePrompt includes the rubric and the output', () => {
  const prompt = buildJudgePrompt('be nice', 'hello');
  assert.match(prompt, /be nice/);
  assert.match(prompt, /hello/);
});

// ---------------------------------------------------------------------------
// The checked-in _example suite (harness self-test)
// ---------------------------------------------------------------------------

test('_example suite: aggregate is 1.0 with --no-judge (deterministic scorers only)', async () => {
  const result = await main(['_example', '--no-judge'], { env: {} });
  assert.equal(result.code, 0, result.output);
  assert.match(result.output, /overall aggregate 1\.000/);
});

test('parseArgs: flags and trend subcommand', () => {
  assert.deepEqual(parseArgs(['suite-a', '--no-judge']), {
    mode: 'run', suite: 'suite-a', dir: null, noJudge: true, requireJudge: false, record: false, last: 10,
  });
  const trend = parseArgs(['trend', 'suite-a', '--last=5']);
  assert.equal(trend.mode, 'trend');
  assert.equal(trend.suite, 'suite-a');
  assert.equal(trend.last, 5);
});
