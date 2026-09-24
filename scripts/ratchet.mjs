#!/usr/bin/env node
// ratchet.mjs — CI fails only when a bad pattern's count rises above a
// committed baseline. Config-driven, zero npm dependencies (see
// docs/decisions/2026-09-24-node-for-template-tooling.md).
//
// Usage:
//   node scripts/ratchet.mjs           # gate: exit 1 on regression or slack
//   node scripts/ratchet.mjs --list    # also print every site, incl. allowed
//   node scripts/ratchet.mjs --update  # lower baselines to match reality;
//                                       # refuses to raise them
//
// Config: .claude/ratchets.json (see that file's `_comment` for the schema
// and the "kind: pattern" / "kind: unreferenced" semantics — including why
// a count *below* baseline also fails, as "slack").
//
// Run from the repo root; all paths are resolved against process.cwd().

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';

const repoRoot = process.cwd();
const configPath = join(repoRoot, '.claude', 'ratchets.json');

const args = new Set(process.argv.slice(2));
const LIST = args.has('--list');
const UPDATE = args.has('--update');

if (!existsSync(configPath)) {
  console.error(`Ratchet config missing: ${configPath}`);
  process.exit(1);
}

const config = JSON.parse(readFileSync(configPath, 'utf8'));
const roots = config.roots ?? [];

function gitLsFiles(paths) {
  if (paths.length === 0) return [];
  let out;
  try {
    out = execFileSync('git', ['ls-files', '--', ...paths], { cwd: repoRoot, encoding: 'utf8' });
  } catch (e) {
    throw new Error(`git ls-files failed for [${paths.join(', ')}]: ${e.message}`);
  }
  return out.split('\n').filter(Boolean);
}

// Minimal glob matcher: supports `**`, `*`, `?`. No external dependency.
function globToRegExp(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*' && glob[i + 1] === '*') {
      i++;
      if (glob[i + 1] === '/') {
        re += '(?:.*/)?';
        i++;
      } else {
        re += '.*';
      }
    } else if (c === '*') {
      re += '[^/]*';
    } else if (c === '?') {
      re += '[^/]';
    } else if ('.+^${}()|[]\\'.includes(c)) {
      re += `\\${c}`;
    } else {
      re += c;
    }
  }
  return new RegExp(`^${re}$`);
}

function matchesAnyGlob(relPath, globs) {
  return globs.some((g) => globToRegExp(g).test(relPath));
}

function lineAt(content, charIndex) {
  return content.slice(0, charIndex).split('\n').length;
}

function isAllowed(content, startIdx, endIdx) {
  const startLine = lineAt(content, startIdx);
  const endLine = lineAt(content, endIdx);
  const lines = content.split('\n').slice(startLine - 1, endLine);
  return lines.some((l) => l.includes('ratchet-allow:'));
}

const allRootFiles = gitLsFiles(roots);
const rootsAbsent = allRootFiles.length === 0;

function runPatternCheck(check) {
  const sites = [];
  for (const pattern of check.patterns) {
    const candidates = allRootFiles.filter((f) => pattern.ext.some((e) => f.endsWith(e)));
    const re = new RegExp(pattern.regex, 'g');
    for (const file of candidates) {
      const content = readFileSync(join(repoRoot, file), 'utf8');
      re.lastIndex = 0;
      let m;
      while ((m = re.exec(content)) !== null) {
        const start = m.index;
        const end = start + m[0].length;
        sites.push({
          file,
          line: lineAt(content, start),
          label: pattern.label,
          allowed: isAllowed(content, start, end),
        });
        if (m[0].length === 0) re.lastIndex++; // guard against zero-width match loops
      }
    }
  }
  const filesConsidered = allRootFiles.filter((f) =>
    check.patterns.some((p) => p.ext.some((e) => f.endsWith(e))),
  );
  return { sites, filesConsidered };
}

function runUnreferencedCheck(check) {
  const testFiles = allRootFiles.filter((f) => matchesAnyGlob(f, check.testGlobs));

  const wiringFiles = [];
  for (const glob of check.wiringGlobs) {
    if (glob.includes('*')) {
      const dir = dirname(glob);
      const base = glob.slice(dir.length + 1);
      if (existsSync(join(repoRoot, dir))) {
        wiringFiles.push(...gitLsFiles([dir]).filter((f) => matchesAnyGlob(f, [`${dir}/${base}`])));
      }
    } else if (existsSync(join(repoRoot, glob))) {
      wiringFiles.push(glob);
    }
  }
  // "Runner scripts": every non-test file already inside the scanned roots.
  wiringFiles.push(...allRootFiles.filter((f) => !matchesAnyGlob(f, check.testGlobs)));

  const wiringContent = wiringFiles.map((f) => readFileSync(join(repoRoot, f), 'utf8')).join('\n---\n');

  const sites = [];
  for (const file of testFiles) {
    const ancestors = [];
    const parts = file.split('/');
    for (let i = 1; i < parts.length; i++) ancestors.push(`${parts.slice(0, i).join('/')}/`);
    const referenced = [file, ...ancestors].some((token) => wiringContent.includes(token));
    if (!referenced) {
      const content = readFileSync(join(repoRoot, file), 'utf8');
      sites.push({ file, line: 1, label: 'orphaned test file (no wiring reference found)', allowed: content.includes('ratchet-allow:') });
    }
  }
  return { sites, filesConsidered: testFiles };
}

function evaluateCheck(check) {
  const { sites, filesConsidered } =
    check.kind === 'pattern' ? runPatternCheck(check) : runUnreferencedCheck(check);
  const violations = sites.filter((s) => !s.allowed);
  const allowed = sites.filter((s) => s.allowed);
  const count = violations.length;

  let status;
  let reason;
  if (filesConsidered.length === 0) {
    if (rootsAbsent) {
      reason = `scanned 0 files (roots absent: ${roots.join(', ')})`;
      status = check.baseline === 0 ? 'pass' : 'fail: scan roots vanished — refusing to pass';
    } else if (count === check.baseline) {
      status = 'pass';
      reason = `0 candidate files matched this check's filter`;
    } else if (count < check.baseline) {
      status = 'fail: slack';
      reason = `0 < baseline ${check.baseline} — run --update to lower the baseline`;
    } else {
      status = 'fail: regression';
      reason = `0 > baseline ${check.baseline}`;
    }
  } else if (count > check.baseline) {
    status = 'fail: regression';
    reason = `${count} > baseline ${check.baseline}`;
  } else if (count < check.baseline) {
    status = 'fail: slack';
    reason = `${count} < baseline ${check.baseline} — run --update to lower the baseline`;
  } else {
    status = 'pass';
    reason = `${count} == baseline ${check.baseline}`;
  }

  return { check, violations, allowed, count, status, reason };
}

const results = config.checks.map(evaluateCheck);

let anyFail = false;
for (const r of results) {
  console.log(`\n=== ${r.check.id} (baseline ${r.check.baseline}) ===`);
  console.log(r.reason);

  const toPrint = LIST ? [...r.violations, ...r.allowed] : r.violations;
  for (const s of toPrint) {
    const tag = s.allowed ? '  [ALLOWED]' : '';
    console.log(`${s.file}:${s.line}  ${s.label}${tag}`);
  }

  if (r.status.startsWith('fail')) anyFail = true;
  console.log(r.status === 'pass' ? 'PASS' : `FAIL (${r.status.split(': ')[1]})`);
}

if (UPDATE) {
  let changed = false;
  for (const r of results) {
    const current = r.check.baseline;
    if (r.count < current) {
      console.log(`\nLowering ${r.check.id} baseline: ${current} -> ${r.count}`);
      r.check.baseline = r.count;
      changed = true;
    } else if (r.count > current) {
      console.log(
        `\nRefusing to raise ${r.check.id} baseline: computed ${r.count} > committed ${current}. Edit .claude/ratchets.json by hand if this is intentional.`,
      );
    }
  }
  if (changed) {
    writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
    console.log(`\nWrote ${configPath}`);
  } else {
    console.log('\nNo baselines needed lowering.');
  }
  process.exit(0);
}

process.exit(anyFail ? 1 : 0);
