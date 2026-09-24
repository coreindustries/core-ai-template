#!/usr/bin/env node
// scripts/tests/ratchet.test.mjs — node:test suite for scripts/ratchet.mjs.
//
// Each test builds a throwaway git repo under a tmp dir (git ls-files reads
// the index, so `git init` + `git add` is enough — no commit needed), writes
// a `.claude/ratchets.json` + source files, then runs the real ratchet.mjs
// as a child process against that repo (cwd = the tmp repo).
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

function runRatchet(dir, args = []) {
  try {
    const out = execFileSync('node', [ratchetScript, ...args], { cwd: dir, encoding: 'utf8' });
    return { status: 0, stdout: out };
  } catch (e) {
    return { status: e.status ?? 1, stdout: (e.stdout ?? '') + (e.stderr ?? '') };
  }
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

test('pattern check: count matches baseline -> pass', () => {
  const dir = makeRepo();
  writeConfig(dir, { ...PATTERN_CONFIG_BASE, checks: [{ ...PATTERN_CONFIG_BASE.checks[0], baseline: 1 }] });
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception:\n    pass\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('pattern check: count above baseline -> fail (regression)', () => {
  const dir = makeRepo();
  writeConfig(dir, PATTERN_CONFIG_BASE); // baseline 0
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception:\n    pass\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /src\/a\.py:3/);
  assert.match(result.stdout, /regression|baseline/i);
  rmSync(dir, { recursive: true, force: true });
});

test('pattern check: count below baseline -> fail (slack)', () => {
  const dir = makeRepo();
  writeConfig(dir, { ...PATTERN_CONFIG_BASE, checks: [{ ...PATTERN_CONFIG_BASE.checks[0], baseline: 3 }] });
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception:\n    pass\n'); // only 1 actual
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /slack/i);
  rmSync(dir, { recursive: true, force: true });
});

test('--update lowers a stale (too-high) baseline', () => {
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

test('--update refuses to raise a baseline', () => {
  const dir = makeRepo();
  writeConfig(dir, PATTERN_CONFIG_BASE); // baseline 0
  write(dir, 'src/a.py', 'try:\n    x()\nexcept Exception:\n    pass\n'); // 1 actual > baseline
  gitAdd(dir);

  const result = runRatchet(dir, ['--update']);
  const updated = JSON.parse(readFileSync(join(dir, '.claude/ratchets.json'), 'utf8'));
  assert.equal(updated.checks[0].baseline, 0, 'baseline must not be raised by --update');
  assert.match(result.stdout, /refus/i);
  rmSync(dir, { recursive: true, force: true });
});

test('ratchet-allow comment exempts a site from the count', () => {
  const dir = makeRepo();
  writeConfig(dir, PATTERN_CONFIG_BASE); // baseline 0
  write(
    dir,
    'src/a.py',
    'try:\n    x()\nexcept Exception:  # ratchet-allow: legacy shim, tracked in TICKET-1\n    pass\n',
  );
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);

  const listResult = runRatchet(dir, ['--list']);
  assert.match(listResult.stdout, /ALLOWED/);
  rmSync(dir, { recursive: true, force: true });
});

test('unreferenced check: orphaned test file is detected', () => {
  const dir = makeRepo();
  writeConfig(dir, {
    roots: ['src', 'tests', 'scripts'],
    checks: [
      {
        id: 'orphaned-test-files',
        kind: 'unreferenced',
        baseline: 0,
        testGlobs: ['**/*.test.sh'],
        wiringGlobs: ['Makefile'],
      },
    ],
  });
  write(dir, 'scripts/tests/orphan.test.sh', '#!/usr/bin/env bash\necho ok\n');
  write(dir, 'Makefile', 'help:\n\techo hi\n'); // does not reference the test file or its dir
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /orphan\.test\.sh/);
  rmSync(dir, { recursive: true, force: true });
});

test('unreferenced check: a wired directory reference clears everything beneath it', () => {
  const dir = makeRepo();
  writeConfig(dir, {
    roots: ['src', 'tests', 'scripts'],
    checks: [
      {
        id: 'orphaned-test-files',
        kind: 'unreferenced',
        baseline: 0,
        testGlobs: ['**/*.test.sh'],
        wiringGlobs: ['Makefile'],
      },
    ],
  });
  write(dir, 'scripts/dev/tests/wired.test.sh', '#!/usr/bin/env bash\necho ok\n');
  write(dir, 'Makefile', 'lanes-test:\n\tscripts/dev/tests/run-all.sh\n');
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  rmSync(dir, { recursive: true, force: true });
});

test('empty roots: 0 files scanned, baseline 0 -> pass', () => {
  const dir = makeRepo();
  writeConfig(dir, PATTERN_CONFIG_BASE); // baseline 0, no files exist at all
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 0, result.stdout);
  assert.match(result.stdout, /roots absent/i);
  rmSync(dir, { recursive: true, force: true });
});

test('vanished roots: 0 files scanned, baseline > 0 -> fail', () => {
  const dir = makeRepo();
  writeConfig(dir, { ...PATTERN_CONFIG_BASE, checks: [{ ...PATTERN_CONFIG_BASE.checks[0], baseline: 2 }] });
  gitAdd(dir);

  const result = runRatchet(dir);
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stdout, /scan roots vanished/i);
  rmSync(dir, { recursive: true, force: true });
});
