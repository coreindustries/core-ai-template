#!/usr/bin/env node
// check-context-budget.mjs — fail when the always-loaded agent context grows
// past a recorded ceiling. Always-loaded = CLAUDE.md plus every .claude/rules/*.md
// (symlinks included) without `paths:` frontmatter; path-scoped rules load only
// when a matching file is touched, so they do not count.
//
// The ceiling lives in .claude/context-budget.json (bytes). Raising it is a
// reviewed change: say in the PR what the new always-loaded text buys and what
// you considered moving to a path-scoped rule or `.claude/references/` instead.
//
// Usage: node scripts/check-context-budget.mjs [repo-root]
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { realpathSync } from 'node:fs';

const SCOPED = /^---\r?\n[\s\S]*?\bpaths:[\s\S]*?\r?\n---/;

/** Always-loaded files and their sizes in bytes, largest first. */
export function alwaysLoaded(root) {
  const files = [{ file: 'CLAUDE.md', bytes: Buffer.byteLength(readFileSync(join(root, 'CLAUDE.md'))) }];
  const dir = join(root, '.claude/rules');
  for (const name of readdirSync(dir).filter((n) => n.endsWith('.md'))) {
    const text = readFileSync(join(dir, name), 'utf8');
    if (!SCOPED.test(text)) files.push({ file: `.claude/rules/${name}`, bytes: Buffer.byteLength(text) });
  }
  return files.sort((a, b) => b.bytes - a.bytes);
}

/** Returns { total, ceiling, files, ok }. Throws if the ceiling is missing or invalid. */
export function checkBudget(root) {
  const cfg = JSON.parse(readFileSync(join(root, '.claude/context-budget.json'), 'utf8'));
  if (!Number.isInteger(cfg.ceilingBytes) || cfg.ceilingBytes <= 0) {
    throw new Error('.claude/context-budget.json: "ceilingBytes" must be a positive integer');
  }
  const files = alwaysLoaded(root);
  const total = files.reduce((n, f) => n + f.bytes, 0);
  return { total, ceiling: cfg.ceilingBytes, files, ok: total <= cfg.ceilingBytes };
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  const r = checkBudget(process.argv[2] ?? '.');
  console.log(`always-loaded context: ${r.total} / ${r.ceiling} bytes (~${Math.round(r.total / 4)} tokens)`);
  if (!r.ok) {
    console.error(`ERROR: over budget by ${r.total - r.ceiling} bytes. Largest always-loaded files:`);
    for (const f of r.files.slice(0, 5)) console.error(`  ${String(f.bytes).padStart(6)}  ${f.file}`);
    console.error('Move text to a path-scoped rule or .claude/references/, or raise ceilingBytes in .claude/context-budget.json with a reason in the PR.');
    process.exit(1);
  }
}
