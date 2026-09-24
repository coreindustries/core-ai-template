#!/usr/bin/env node
// scripts/tests/ratchet.test.mjs — node:test suite for scripts/ratchet.mjs.
//
// Each test builds a throwaway git repo under a tmp dir (git ls-files reads
// the index, so `git init` + `git add` is enough — no commit needed), writes
// a `.claude/ratchets.json` + source files, then runs the real ratchet.mjs
// as a child process against that repo (cwd = the tmp repo, or a
// subdirectory of it where a test specifically covers that).
//
// Run: node --test scripts/tests/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const here = dirname(fileURLToPath(import.meta.url));
const ratchetScript = join(here, '..', 'ratchet.mjs');
const realRepoRoot = join(here, '..', '..');

function makeRepo() {
  const dir = mkdtempSync(join(tmpdir(), 'ratchet-test-'));
  execFileSync('git', ['init', '-q'], { cwd: dir });
  return dir;
}

function write(dir, relPath, content) {
  const full = join(dir, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, content);
}

function gitAdd(dir) {
  execFileSync('git', ['add', '-A'], { cwd: dir });
}

function writeConfig(dir, config) {
  write(dir, '.claude/ratchets.json', JSON.stringify(config, null, 2));
}

function runRatchet(dir, args = [], cwd = dir, timeout = 10000) {
  try {
    const out = execFileSync('node', [ratchetScript, ...args], { cwd, encoding: 'utf8', timeout });
    return { status: 0, stdout: out };
  } catch (e) {
    return { status: e.status ?? 1, stdout: (e.stdout ?? '') + (e.stderr ?? '') };
  }
}

// Loads the real shipped pattern (not a re-implementation) so tests for
// one-line / CRLF / ellipsis / widened JS coverage exercise the exact regex
// that ships, not a copy that could drift from it.
function realPattern(labelSubstring) {
  const cfg = JSON.parse(readFileSync(join(realRepoRoot, '.claude', 'ratchets.json'), 'utf8'));
  const check = cfg.checks.find((c) => c.kind === 'pattern');
  const pattern = check.patterns.find((p) => p.label.includes(labelSubstring));
  assert.ok(pattern, `no shipped pattern matches "${labelSubstring}"`);
  return pattern;
}

function singlePatternConfig(pattern, baseline) {
  return {
    roots: ['src', 'tests', 'scripts'],
    checks: [{ id: 'silent-exception-swallowing', kind: 'pattern', baseline, patterns: [pattern] }],
  };
}

const PATTERN_CONFIG_BASE = {
  roots: ['src', 'tests', 'scripts'],
  checks: [
    {
      id: 'silent-exception-swallowing',
      kind: 'pattern',
      baseline: 0,
      patterns: [
        {
          label: 'python: bare except swallowed with pass',
          ext: ['.py'],
          regex: 'except[^\\n:]*:[ \\t]*(#.*)?\\n[ \\t]*pass\\b',
        },
      ],
    },
  ],
};

// ---------------------------------------------------------------------------
// Core baseline math
// ---------------------------------------------------------------------------

test('pattern check: count matches baseline -> pass', () => {
  const dir = makeRepo();
  writeConfig(dir, { ...PATTERN_CONFIG_BASE, checks: [{ ...PATTERN_CONFIG_BASE.checks[0], baseline: 1 }] });
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception:\n    pass\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('pattern check: count above baseline -> fail (regression, always fatal)', () => {
  const dir = makeRepo();
  writeConfig(dir, PATTERN_CONFIG_BASE); // baseline 0
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception:\n    pass\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /src\/a\.py:3/);
  assert.match(result.stdout, /regression/i);
  rmSync(dir, { recursive: true, force: true });
});

test('pattern check: count below baseline is a WARNING by default (slack, exit 0)', () => {
  const dir = makeRepo();
  writeConfig(dir, { ...PATTERN_CONFIG_BASE, checks: [{ ...PATTERN_CONFIG_BASE.checks[0], baseline: 3 }] });
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception:\n    pass\n'); // only 1 actual
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  assert.match(result.stdout, /slack/i);
  assert.match(result.stdout, /WARN/);
  rmSync(dir, { recursive: true, force: true });
});

test('pattern check: count below baseline fails under --strict', () => {
  const dir = makeRepo();
  writeConfig(dir, { ...PATTERN_CONFIG_BASE, checks: [{ ...PATTERN_CONFIG_BASE.checks[0], baseline: 3 }] });
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception:\n    pass\n'); // only 1 actual
  gitAdd(dir);

  const result = runRatchet(dir, ['--strict']);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /slack/i);
  rmSync(dir, { recursive: true, force: true });
});

test('--update lowers a stale (too-high) baseline and exits 0', () => {
  const dir = makeRepo();
  writeConfig(dir, { ...PATTERN_CONFIG_BASE, checks: [{ ...PATTERN_CONFIG_BASE.checks[0], baseline: 5 }] });
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception:\n    pass\n'); // only 1 actual
  gitAdd(dir);

  const result = runRatchet(dir, ['--update']);
  assert.equal(result.status, 0, result.stdout);
  const updated = JSON.parse(readFileSync(join(dir, '.claude/ratchets.json'), 'utf8'));
  assert.equal(updated.checks[0].baseline, 1);
  rmSync(dir, { recursive: true, force: true });
});

test('--update refuses to raise a baseline and exits 1 (still regressed)', () => {
  const dir = makeRepo();
  writeConfig(dir, PATTERN_CONFIG_BASE); // baseline 0
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception:\n    pass\n'); // 1 actual > baseline
  gitAdd(dir);

  const result = runRatchet(dir, ['--update']);
  const updated = JSON.parse(readFileSync(join(dir, '.claude/ratchets.json'), 'utf8'));
  assert.equal(updated.checks[0].baseline, 0, 'baseline must not be raised by --update');
  assert.match(result.stdout, /refus/i);
  assert.equal(result.status, 1, 'must exit 1 when a check is still regressed after --update');
  rmSync(dir, { recursive: true, force: true });
});

test('ratchet-allow(<check-id>) comment (on the matched line, in that file type\'s comment syntax) exempts a site', () => {
  const dir = makeRepo();
  writeConfig(dir, PATTERN_CONFIG_BASE); // baseline 0
  write(
    dir,
    'src/a.py',
    'try:\n    x()\nexcept Exception:  # ratchet-allow(silent-exception-swallowing): legacy shim, tracked in TICKET-1\n    pass\n',
  );
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);

  const listResult = runRatchet(dir, ['--list']);
  assert.match(listResult.stdout, /ALLOWED/);
  rmSync(dir, { recursive: true, force: true });
});

test('ratchet-allow naming a DIFFERENT check does not exempt this one', () => {
  const dir = makeRepo();
  writeConfig(dir, PATTERN_CONFIG_BASE); // baseline 0, check id "silent-exception-swallowing"
  write(
    dir,
    'src/a.py',
    'try:\n    x()\nexcept Exception:  # ratchet-allow(orphaned-test-files): wrong check name\n    pass\n',
  );
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('ratchet-allow must follow a real comment marker, not just appear as text in a string literal', () => {
  const dir = makeRepo();
  writeConfig(dir, PATTERN_CONFIG_BASE); // baseline 0
  write(
    dir,
    'src/a.py',
    "try:\n    x()\nexcept Exception:\n    pass; msg = 'ratchet-allow(silent-exception-swallowing): nope, not a comment'\n",
  );
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, 'must NOT be exempted — no "#" comment marker precedes it on the line');
  rmSync(dir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Widened pattern coverage (P2) — exercised against the real shipped regexes
// ---------------------------------------------------------------------------

test('python pattern: one-line "except E: pass" is counted', () => {
  const dir = makeRepo();
  const pattern = realPattern('python');
  writeConfig(dir, singlePatternConfig(pattern, 1));
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception: pass\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('python pattern: CRLF line endings are counted', () => {
  const dir = makeRepo();
  const pattern = realPattern('python');
  writeConfig(dir, singlePatternConfig(pattern, 1));
  write(dir, 'src/a.py', 'try:\r\n    x()\r\nexcept Exception:\r\n    pass\r\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('python pattern: "..." stub body is counted', () => {
  const dir = makeRepo();
  const pattern = realPattern('python');
  writeConfig(dir, singlePatternConfig(pattern, 1));
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception:\n    ...\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('python pattern: word boundary — "on_except(" is not mistaken for "except"', () => {
  const dir = makeRepo();
  const pattern = realPattern('python');
  writeConfig(dir, singlePatternConfig(pattern, 0));
  write(dir, 'src/a.py', 'def on_except(handler):\n    pass\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('js pattern: comment-only catch body is counted', () => {
  const dir = makeRepo();
  const pattern = realPattern('empty (or comment-only) catch');
  writeConfig(dir, singlePatternConfig(pattern, 1));
  write(dir, 'src/a.js', 'try {\n  x();\n} catch (e) {\n  // ignore\n}\n'); // ratchet-allow(silent-exception-swallowing): fixture string scanned as this repo's own source, not real code
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('js pattern: catch-arrow undefined/null bodies are counted', () => {
  const dir = makeRepo();
  const pattern = realPattern('undefined/null');
  writeConfig(dir, singlePatternConfig(pattern, 2));
  write(dir, 'src/a.js', 'foo().catch(() => undefined);\nbar().catch(() => null);\n'); // ratchet-allow(silent-exception-swallowing): fixture string scanned as this repo's own source, not real code
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('js pattern: async-arrow empty catch body is counted', () => {
  const dir = makeRepo();
  const pattern = realPattern('undefined/null');
  writeConfig(dir, singlePatternConfig(pattern, 1));
  write(dir, 'src/a.js', 'foo().catch(async () => {});\n'); // ratchet-allow(silent-exception-swallowing): fixture string scanned as this repo's own source, not real code
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('js pattern: catch-function empty body is counted', () => {
  const dir = makeRepo();
  const pattern = realPattern('function () {}');
  writeConfig(dir, singlePatternConfig(pattern, 1));
  write(dir, 'src/a.js', 'foo().catch(function () {});\n'); // ratchet-allow(silent-exception-swallowing): fixture string scanned as this repo's own source, not real code
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('js pattern: TS-typed catch-arrow params are counted, e.g. (e: unknown) => {}', () => {
  const dir = makeRepo();
  const pattern = realPattern('undefined/null');
  writeConfig(dir, singlePatternConfig(pattern, 2));
  write(
    dir,
    'src/a.ts',
    'foo().catch((e: unknown) => {});\nbar().catch((_e: any) => undefined);\n', // ratchet-allow(silent-exception-swallowing): fixture string scanned as this repo's own source, not real code
  );
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('ReDoS safety: a long run of "/" inside a non-empty catch body completes in well under a second', () => {
  const dir = makeRepo();
  const pattern = realPattern('empty (or comment-only) catch');
  writeConfig(dir, singlePatternConfig(pattern, 0)); // body is NOT empty -> must not match, must not hang
  const slashes = '/'.repeat(200);
  write(
    dir,
    'src/a.js',
    `try {\n  x();\n} catch (e) {\n  ${slashes}\n  doSomethingReal();\n}\n`, // ratchet-allow(silent-exception-swallowing): fixture string scanned as this repo's own source, not real code
  );
  gitAdd(dir);

  const start = Date.now();
  const result = runRatchet(dir, [], dir, 5000);
  const elapsed = Date.now() - start;
  assert.ok(elapsed < 1000, `expected < 1000ms, took ${elapsed}ms — possible ReDoS regression in the empty-catch pattern`);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('ReDoS safety: many /* step */ block comments inside a non-empty catch body completes quickly', () => {
  const dir = makeRepo();
  const pattern = realPattern('empty (or comment-only) catch');
  writeConfig(dir, singlePatternConfig(pattern, 0));
  const comments = '/* step */\n'.repeat(200); // judge's repro: ~26 lines took 13s pre-fix
  write(
    dir,
    'src/a.js',
    `try {\n  x();\n} catch (e) {\n  ${comments}  doSomethingReal();\n}\n`, // ratchet-allow(silent-exception-swallowing): fixture string scanned as this repo's own source, not real code
  );
  gitAdd(dir);

  const start = Date.now();
  const result = runRatchet(dir, [], dir, 5000);
  const elapsed = Date.now() - start;
  assert.ok(elapsed < 1000, `expected < 1000ms, took ${elapsed}ms — possible ReDoS regression in the block-comment alternative`);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('ReDoS safety: a TS-typed catch param with many interior spaces completes quickly', () => {
  const dir = makeRepo();
  const pattern = realPattern('undefined/null');
  writeConfig(dir, singlePatternConfig(pattern, 0));
  const spaces = ' '.repeat(5000);
  write(
    dir,
    'src/a.ts',
    `foo().catch((e:${spaces}unknown) => doSomethingReal());\n`, // ratchet-allow(silent-exception-swallowing): fixture string scanned as this repo's own source, not real code
  );
  gitAdd(dir);

  const start = Date.now();
  const result = runRatchet(dir, [], dir, 5000);
  const elapsed = Date.now() - start;
  assert.ok(elapsed < 1000, `expected < 1000ms, took ${elapsed}ms — possible ReDoS regression in the TS-typed param group`);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('js pattern: block-comment variants still match — { /* ignore */ }, {/***/}, and mixed // + /* */ bodies', () => {
  const dir = makeRepo();
  const pattern = realPattern('empty (or comment-only) catch');
  writeConfig(dir, singlePatternConfig(pattern, 3));
  write(
    dir,
    'src/a.js',
    [
      'try { a(); } catch (e) { /* ignore */ }', // ratchet-allow(silent-exception-swallowing): fixture string scanned as this repo's own source, not real code
      'try { b(); } catch (e) {/***/}', // ratchet-allow(silent-exception-swallowing): fixture string scanned as this repo's own source, not real code
      'try { c(); } catch (e) {\n  // note\n  /* and also */\n}', // ratchet-allow(silent-exception-swallowing): fixture string scanned as this repo's own source, not real code
      '',
    ].join('\n'),
  );
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Structural ReDoS safety net (P2): fuzz EVERY pattern in the real config
// against a generated adversarial corpus, so a future pattern added to
// ratchets.json is covered automatically instead of needing its own
// hand-written repro after the fact.
// ---------------------------------------------------------------------------

const FUZZ_SIZES = [5000, 20000];
const FUZZ_BUDGET_MS = 1000;

const FUZZ_FRAGMENTS = {
  slashes: (n) => '/'.repeat(n),
  starComments: (n) => '/**/'.repeat(Math.ceil(n / 4)),
  starCommentLines: (n) => '/* x */\n'.repeat(Math.ceil(n / 8)),
  lineComments: (n) => '//\n'.repeat(Math.ceil(n / 3)),
  spaces: (n) => ' '.repeat(n),
  colonSpaces: (n) => ':' + ' '.repeat(n),
  crlfMix: (n) =>
    Array.from({ length: Math.ceil(n / 4) }, (_, i) => (i % 2 === 0 ? '//\r\n' : '//\n')).join(''),
};

function wrapForPattern(pattern, fragment) {
  if (pattern.ext.includes('.py')) return `except ${fragment}:\n    pass\n`;
  return `catch (e) {${fragment}x }\n`;
}

// One node subprocess per case: exec()'s the exact shipped regex against
// generated content, wall-clock budgeted. Isolated per case so one runaway
// pattern can't stall or crash the whole fuzz test.
function execRegexBudgeted(regexSource, content, budgetMs) {
  const script = `
    const re = new RegExp(process.argv[1], 'g');
    const fs = require('node:fs');
    const content = fs.readFileSync(process.argv[2], 'utf8');
    re.exec(content);
  `;
  const contentFile = join(mkdtempSync(join(tmpdir(), 'ratchet-fuzz-')), 'case.txt');
  writeFileSync(contentFile, content);
  const start = Date.now();
  try {
    execFileSync('node', ['-e', script, regexSource, contentFile], { timeout: budgetMs });
    return Date.now() - start;
  } finally {
    rmSync(dirname(contentFile), { recursive: true, force: true });
  }
}

test('ReDoS fuzz budget: every pattern check in ratchets.json stays under budget on adversarial input', () => {
  const cfg = JSON.parse(readFileSync(join(realRepoRoot, '.claude', 'ratchets.json'), 'utf8'));
  const patternChecks = cfg.checks.filter((c) => c.kind === 'pattern');
  assert.ok(patternChecks.length > 0, 'expected at least one pattern check in the real config');

  const slow = [];
  for (const check of patternChecks) {
    for (const pattern of check.patterns) {
      for (const [fragName, fragFn] of Object.entries(FUZZ_FRAGMENTS)) {
        for (const size of FUZZ_SIZES) {
          const content = wrapForPattern(pattern, fragFn(size));
          const label = `${pattern.label} / ${fragName} / ${size}`;
          let elapsed;
          try {
            elapsed = execRegexBudgeted(pattern.regex, content, FUZZ_BUDGET_MS);
          } catch (e) {
            slow.push(`${label}: killed at budget (${FUZZ_BUDGET_MS}ms) — ${e.message}`);
            continue;
          }
          if (elapsed >= FUZZ_BUDGET_MS) slow.push(`${label}: ${elapsed}ms`);
        }
      }
    }
  }
  assert.equal(slow.length, 0, `ReDoS-suspect pattern/fragment combinations:\n${slow.join('\n')}`);
});

// ---------------------------------------------------------------------------
// P1 — unreferenced check: explicit declared runners, not substring heuristics
// ---------------------------------------------------------------------------

function runnersConfig({ testGlobs, wiringFiles, runners }) {
  return {
    roots: ['src', 'tests', 'scripts'],
    checks: [
      { id: 'orphaned-test-files', kind: 'unreferenced', baseline: 0, testGlobs, wiringFiles, runners },
    ],
  };
}

test('unreferenced: a bare-root-token mention (e.g. "pytest tests/") does NOT wire a file with no declared runner', () => {
  const dir = makeRepo();
  writeConfig(
    dir,
    runnersConfig({ testGlobs: ['**/test_*.py'], wiringFiles: ['Makefile'], runners: [] }),
  );
  write(dir, 'Makefile', 'test:\n\tpytest tests/\n# also relevant: src/\n');
  write(dir, 'tests/unit/test_new.py', 'def test_x():\n    assert True\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /tests\/unit\/test_new\.py/);
  rmSync(dir, { recursive: true, force: true });
});

test('unreferenced: a declared runner whose "by" is not wired anywhere is its own failure', () => {
  const dir = makeRepo();
  writeConfig(
    dir,
    runnersConfig({
      testGlobs: ['**/*.test.mjs'],
      wiringFiles: ['Makefile'],
      runners: [{ covers: ['scripts/tests/*.test.mjs'], by: 'node --test scripts/tests/' }],
    }),
  );
  write(dir, 'Makefile', 'help:\n\techo hi\n'); // does not mention the runner string
  write(dir, 'scripts/tests/foo.test.mjs', '// test\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /not invoked/i);
  assert.match(result.stdout, /foo\.test\.mjs/); // also orphaned, since its runner isn't actually wired
  rmSync(dir, { recursive: true, force: true });
});

test('unreferenced: a file covered by a runner whose "by" IS wired is not orphaned', () => {
  const dir = makeRepo();
  writeConfig(
    dir,
    runnersConfig({
      testGlobs: ['**/*.test.mjs'],
      wiringFiles: ['Makefile'],
      runners: [{ covers: ['scripts/tests/*.test.mjs'], by: 'node --test scripts/tests/' }],
    }),
  );
  write(dir, 'Makefile', 'test:\n\tnode --test scripts/tests/\n');
  write(dir, 'scripts/tests/foo.test.mjs', '// test\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('unreferenced: a "by" string appearing only in a comment line is not wired (comment lines stripped)', () => {
  const dir = makeRepo();
  writeConfig(
    dir,
    runnersConfig({
      testGlobs: ['**/*.test.mjs'],
      wiringFiles: ['Makefile'],
      runners: [{ covers: ['scripts/tests/*.test.mjs'], by: 'node --test scripts/tests/' }],
    }),
  );
  write(dir, 'Makefile', '# node --test scripts/tests/\nhelp:\n\techo hi\n');
  write(dir, 'scripts/tests/foo.test.mjs', '// test\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /not invoked/i);
  rmSync(dir, { recursive: true, force: true });
});

test('unreferenced: "by" must equal a whole command — a prefix like "node --test" is NOT wired by "node --test scripts/tests/"', () => {
  const dir = makeRepo();
  writeConfig(
    dir,
    runnersConfig({
      testGlobs: ['**/*.test.mjs'],
      wiringFiles: ['Makefile'],
      runners: [{ covers: ['scripts/tests/*.test.mjs'], by: 'node --test' }],
    }),
  );
  write(dir, 'Makefile', 'test:\n\tnode --test scripts/tests/\n');
  write(dir, 'scripts/tests/foo.test.mjs', '// test\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /not invoked/i);
  rmSync(dir, { recursive: true, force: true });
});

test('unreferenced: "by" matching the exact whole command IS wired (Makefile recipe with @ silent-prefix)', () => {
  const dir = makeRepo();
  writeConfig(
    dir,
    runnersConfig({
      testGlobs: ['**/*.test.mjs'],
      wiringFiles: ['Makefile'],
      runners: [{ covers: ['scripts/tests/*.test.mjs'], by: 'node --test scripts/tests/' }],
    }),
  );
  write(dir, 'Makefile', 'test:\n\t@node --test scripts/tests/\n'); // Makefile "@" (silent) prefix
  write(dir, 'scripts/tests/foo.test.mjs', '// test\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('unreferenced: narrowed covers — real config only wires test_log_triage.py, not a sibling test_*.py', () => {
  const dir = makeRepo();
  const cfg = JSON.parse(readFileSync(join(realRepoRoot, '.claude', 'ratchets.json'), 'utf8'));
  const realCheck = cfg.checks.find((c) => c.kind === 'unreferenced');
  writeConfig(dir, { roots: ['src', 'tests', 'scripts'], checks: [{ ...realCheck, baseline: 0 }] });
  write(dir, 'Makefile', 'lanes-test:\n\tscripts/dev/board/tests/run-all.sh\n');
  write(dir, 'scripts/dev/board/tests/test_log_triage.py', 'def test_x():\n    pass\n');
  write(dir, 'scripts/dev/board/tests/test_new_thing.py', 'def test_y():\n    pass\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  assert.doesNotMatch(result.stdout, /test_log_triage\.py/, 'the covered file must not be flagged');
  assert.match(result.stdout, /test_new_thing\.py/, 'a sibling not in the narrowed covers glob must be orphaned');
  rmSync(dir, { recursive: true, force: true });
});

test('unreferenced: ratchet-allow(<check-id>) in the first 3 lines exempts an orphaned test file', () => {
  const dir = makeRepo();
  writeConfig(
    dir,
    runnersConfig({ testGlobs: ['**/test_*.py'], wiringFiles: ['Makefile'], runners: [] }),
  );
  write(dir, 'Makefile', 'test:\n\techo hi\n');
  write(
    dir,
    'tests/unit/test_new.py',
    '# ratchet-allow(orphaned-test-files): intentionally run manually, tracked in TICKET-2\ndef test_x():\n    assert True\n',
  );
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('unreferenced: ratchet-allow(<check-id>) past the first 3 lines does NOT exempt', () => {
  const dir = makeRepo();
  writeConfig(
    dir,
    runnersConfig({ testGlobs: ['**/test_*.py'], wiringFiles: ['Makefile'], runners: [] }),
  );
  write(dir, 'Makefile', 'test:\n\techo hi\n');
  write(
    dir,
    'tests/unit/test_new.py',
    '\n\n\n\n# ratchet-allow(orphaned-test-files): too late, past line 3\ndef test_x():\n    assert True\n',
  );
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Config validation
// ---------------------------------------------------------------------------

test('config validation: non-integer baseline exits 1 with a clear message', () => {
  const dir = makeRepo();
  writeConfig(dir, { ...PATTERN_CONFIG_BASE, checks: [{ ...PATTERN_CONFIG_BASE.checks[0], baseline: 'zero' }] });
  write(dir, 'src/a.py', 'x = 1\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /baseline/i);
  rmSync(dir, { recursive: true, force: true });
});

test('config validation: unknown "kind" exits 1 with a clear message', () => {
  const dir = makeRepo();
  writeConfig(dir, { ...PATTERN_CONFIG_BASE, checks: [{ ...PATTERN_CONFIG_BASE.checks[0], kind: 'bogus' }] });
  write(dir, 'src/a.py', 'x = 1\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /kind/i);
  rmSync(dir, { recursive: true, force: true });
});

test('config validation: malformed runner entry exits 1 with a clear message', () => {
  const dir = makeRepo();
  writeConfig(
    dir,
    runnersConfig({
      testGlobs: ['**/*.test.mjs'],
      wiringFiles: ['Makefile'],
      runners: [{ covers: 'not-an-array', by: 123 }],
    }),
  );
  write(dir, 'Makefile', 'help:\n\techo hi\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /runner/i);
  rmSync(dir, { recursive: true, force: true });
});

test('config validation: a runner "by" that is a bare word (too short / no path or space) exits 1', () => {
  const dir = makeRepo();
  writeConfig(
    dir,
    runnersConfig({
      testGlobs: ['**/*.test.mjs'],
      wiringFiles: ['Makefile'],
      runners: [{ covers: ['scripts/tests/*.test.mjs'], by: 'test' }],
    }),
  );
  write(dir, 'Makefile', 'test:\n\techo hi\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /"by"/);
  rmSync(dir, { recursive: true, force: true });
});

test('config validation: a wiringFiles glob using ** or braces (unsupported by the resolver) exits 1', () => {
  const dir = makeRepo();
  writeConfig(
    dir,
    runnersConfig({
      testGlobs: ['**/*.test.mjs'],
      wiringFiles: ['**/*.yml'],
      runners: [],
    }),
  );
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1);
  assert.match(result.stdout, /wiringFiles/i);
  rmSync(dir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Roots edge cases
// ---------------------------------------------------------------------------

test('empty roots: 0 files scanned, baseline 0 -> pass', () => {
  const dir = makeRepo();
  writeConfig(dir, PATTERN_CONFIG_BASE); // baseline 0, no files exist at all
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  assert.match(result.stdout, /roots absent/i);
  rmSync(dir, { recursive: true, force: true });
});

test('vanished roots: 0 files scanned, baseline > 0 -> fail (always fatal, not gated by --strict)', () => {
  const dir = makeRepo();
  writeConfig(dir, { ...PATTERN_CONFIG_BASE, checks: [{ ...PATTERN_CONFIG_BASE.checks[0], baseline: 2 }] });
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /scan roots vanished/i);
  rmSync(dir, { recursive: true, force: true });
});

// ---------------------------------------------------------------------------
// Misc correctness (P2/P3)
// ---------------------------------------------------------------------------

test('git ls-files -z: a non-ASCII filename is read correctly, not quoted/mangled', () => {
  const dir = makeRepo();
  writeConfig(dir, { ...PATTERN_CONFIG_BASE, checks: [{ ...PATTERN_CONFIG_BASE.checks[0], baseline: 1 }] });
  write(dir, 'src/café.py', 'try:\n    x()\nexcept Exception:\n    pass\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  assert.doesNotMatch(result.stdout, /\\3\d\d/, 'path must not appear octal-escaped');
  assert.doesNotMatch(result.stdout, /WARN|slack/i, 'the file must actually be found and counted, not silently dropped');
  assert.match(result.stdout, /1 == baseline 1/, 'the café.py match must be counted exactly once');
  rmSync(dir, { recursive: true, force: true });
});

test('resolves the repo root via `git rev-parse --show-toplevel` (works from a subdirectory)', () => {
  const dir = makeRepo();
  writeConfig(dir, PATTERN_CONFIG_BASE); // baseline 0, no source files
  mkdirSync(join(dir, 'sub'), { recursive: true });
  gitAdd(dir);

  const result = runRatchet(dir, [], join(dir, 'sub'));
  assert.equal(result.status, 0, result.stdout);
  assert.match(result.stdout, /roots absent/i);
  rmSync(dir, { recursive: true, force: true });
});
