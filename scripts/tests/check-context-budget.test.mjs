import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, symlinkSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { alwaysLoaded, checkBudget } from '../check-context-budget.mjs';

const script = fileURLToPath(new URL('../check-context-budget.mjs', import.meta.url));

function repo(ceiling, rules) {
  const root = mkdtempSync(join(tmpdir(), 'ctxbudget-'));
  mkdirSync(join(root, '.claude/rules'), { recursive: true });
  writeFileSync(join(root, 'CLAUDE.md'), 'x'.repeat(100));
  writeFileSync(join(root, '.claude/context-budget.json'), JSON.stringify({ ceilingBytes: ceiling }));
  for (const [name, text] of Object.entries(rules)) writeFileSync(join(root, '.claude/rules', name), text);
  return root;
}

test('counts CLAUDE.md and unscoped rules, skips path-scoped rules', () => {
  const root = repo(1000, {
    'always.md': 'a'.repeat(200),
    'scoped.md': '---\npaths:\n  - "**/*.ts"\n---\n' + 'b'.repeat(5000),
  });
  const files = alwaysLoaded(root);
  assert.deepEqual(files.map((f) => f.file), ['.claude/rules/always.md', 'CLAUDE.md']);
  assert.equal(checkBudget(root).total, 300);
});

test('a "paths:" mention in the body of an unscoped rule does not make it scoped', () => {
  const root = repo(1000, { 'body.md': '# Title\n\nMentions paths: in prose.\n' });
  assert.equal(alwaysLoaded(root).length, 2);
});

test('frontmatter without paths: is counted even if the body mentions paths: and has a later ---', () => {
  const root = repo(1000, {
    'fm.md': '---\nname: x\n---\nBody mentions\npaths:\n  - a\n---\nmore',
    'key.md': '---\ninclude-paths:\n  - a\n---\nbody',
  });
  assert.equal(alwaysLoaded(root).length, 3);
});

test('a dangling rule symlink fails with a message naming the file', () => {
  const root = repo(1000, {});
  symlinkSync(join(root, 'missing.md'), join(root, '.claude/rules/dangling.md'));
  assert.throws(() => alwaysLoaded(root), /dangling\.md.*dangling symlink/);
});

test('under the ceiling passes, over it fails with exit 1', () => {
  assert.equal(spawnSync('node', [script, repo(1000, { 'a.md': 'a'.repeat(200) })]).status, 0);
  const over = spawnSync('node', [script, repo(250, { 'a.md': 'a'.repeat(200) })]);
  assert.equal(over.status, 1);
  assert.match(over.stderr.toString(), /over budget by 50 bytes/);
});

test('an invalid ceiling throws instead of passing', () => {
  assert.throws(() => checkBudget(repo('big', {})), /ceilingBytes/);
});

test('this repo is within its recorded ceiling', () => {
  const r = checkBudget(fileURLToPath(new URL('../../', import.meta.url)));
  assert.ok(r.ok, `${r.total} > ${r.ceiling}`);
});
