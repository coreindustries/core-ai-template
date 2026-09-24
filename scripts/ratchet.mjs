#!/usr/bin/env node
// ratchet.mjs — CI fails only when a bad pattern's count rises above a
// committed baseline. Config-driven, zero npm dependencies (see
// docs/decisions/2026-09-24-node-for-template-tooling.md).
//
// Usage:
//   node scripts/ratchet.mjs           # gate: exit 1 on regression (always)
//                                       # or on slack, only with --strict
//   node scripts/ratchet.mjs --strict  # also fail on "slack" (count < baseline)
//   node scripts/ratchet.mjs --list    # also print every site, incl. allowed
//   node scripts/ratchet.mjs --update  # lower baselines to match reality;
//                                       # refuses to raise them; exits 1 if
//                                       # any check is still regressed after
//
// Config: .claude/ratchets.json (see that file's `_comment` for the full
// schema — "kind: pattern" / "kind: unreferenced", the declared-runners
// contract, why "slack" defaults to a warning, the check-specific
// `ratchet-allow(<check-id>):` exemption syntax, and the ReDoS-safety
// caution for writing pattern regexes).
//
// Resolves the repo root via `git rev-parse --show-toplevel`, so it works
// run from any subdirectory, not just the repo root.

import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname, basename } from 'node:path';

const args = new Set(process.argv.slice(2));
const LIST = args.has('--list');
const UPDATE = args.has('--update');
const STRICT = args.has('--strict');

function findRepoRoot() {
  try {
    return execFileSync('git', ['rev-parse', '--show-toplevel'], {
      cwd: process.cwd(),
      encoding: 'utf8',
    }).trim();
  } catch (e) {
    throw new Error(`not inside a git repository (git rev-parse --show-toplevel failed from ${process.cwd()}): ${e.message}`);
  }
}

// Whether a wiringFiles glob entry is one resolveWiringFiles can actually
// resolve: a single `*` confined to the final path segment. `**` and brace
// expansion are rejected here rather than silently resolving to zero files.
function isSupportedWiringGlob(pattern) {
  if (pattern.includes('**') || pattern.includes('{')) return false;
  if (!pattern.includes('*')) return true;
  return !dirname(pattern).includes('*');
}

function validateConfig(cfg) {
  if (!Array.isArray(cfg.roots) || cfg.roots.some((r) => typeof r !== 'string')) {
    throw new Error('"roots" must be an array of strings');
  }
  if (!Array.isArray(cfg.checks) || cfg.checks.length === 0) {
    throw new Error('"checks" must be a non-empty array');
  }
  for (const check of cfg.checks) {
    if (typeof check.id !== 'string' || check.id.length === 0) {
      throw new Error('a check is missing a string "id"');
    }
    if (!Number.isInteger(check.baseline) || check.baseline < 0) {
      throw new Error(`check "${check.id}": "baseline" must be a non-negative integer, got ${JSON.stringify(check.baseline)}`);
    }
    if (check.kind !== 'pattern' && check.kind !== 'unreferenced') {
      throw new Error(`check "${check.id}": "kind" must be "pattern" or "unreferenced", got ${JSON.stringify(check.kind)}`);
    }
    if (check.kind === 'pattern') {
      if (!Array.isArray(check.patterns) || check.patterns.length === 0) {
        throw new Error(`check "${check.id}": "patterns" must be a non-empty array`);
      }
      for (const p of check.patterns) {
        if (typeof p.label !== 'string' || !Array.isArray(p.ext) || p.ext.length === 0 || typeof p.regex !== 'string') {
          throw new Error(`check "${check.id}": malformed pattern entry ${JSON.stringify(p)}`);
        }
      }
    } else {
      if (!Array.isArray(check.testGlobs) || check.testGlobs.length === 0) {
        throw new Error(`check "${check.id}": "testGlobs" must be a non-empty array`);
      }
      if (!Array.isArray(check.wiringFiles) || check.wiringFiles.length === 0) {
        throw new Error(`check "${check.id}": "wiringFiles" must be a non-empty array`);
      }
      for (const wf of check.wiringFiles) {
        if (typeof wf !== 'string' || !isSupportedWiringGlob(wf)) {
          throw new Error(
            `check "${check.id}": wiringFiles entry ${JSON.stringify(wf)} is not resolvable — only a single "*" confined to the final path segment is supported, not "**" or "{...}"`,
          );
        }
      }
      if (!Array.isArray(check.runners)) {
        throw new Error(`check "${check.id}": "runners" must be an array (can be empty)`);
      }
      for (const r of check.runners) {
        if (!Array.isArray(r.covers) || r.covers.length === 0 || typeof r.by !== 'string' || r.by.length === 0) {
          throw new Error(`check "${check.id}": malformed runner entry ${JSON.stringify(r)}`);
        }
        if (r.by.length < 6 || !/[/ ]/.test(r.by)) {
          throw new Error(
            `check "${check.id}": runner "by" must be a specific invocation (a path or a command with an argument), not a bare word: ${JSON.stringify(r.by)}`,
          );
        }
      }
    }
  }
}

let repoRoot;
let configPath;
let config;
try {
  repoRoot = findRepoRoot();
  configPath = join(repoRoot, '.claude', 'ratchets.json');
  if (!existsSync(configPath)) {
    throw new Error(`missing config file: ${configPath}`);
  }
  config = JSON.parse(readFileSync(configPath, 'utf8'));
  validateConfig(config);
} catch (e) {
  console.error(`ratchet.mjs: ${e.message}`);
  process.exit(1);
}

const roots = config.roots;

function gitLsFiles(paths) {
  if (paths.length === 0) return [];
  let out;
  try {
    // -z: NUL-separated, unquoted — otherwise git quotes/octal-escapes any
    // non-ASCII byte in a path by default (core.quotepath), which would
    // silently break every join(repoRoot, file) lookup for such a path.
    out = execFileSync('git', ['ls-files', '-z', '--', ...paths], { cwd: repoRoot, encoding: 'utf8' });
  } catch (e) {
    throw new Error(`git ls-files failed for [${paths.join(', ')}]: ${e.message}`);
  }
  return out.split('\0').filter(Boolean);
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

// Expands one flat `{a,b,c}` alternation (no nesting) into multiple globs,
// e.g. "*.spec.{ts,js}" -> ["*.spec.ts", "*.spec.js"].
function expandBraceGlob(glob) {
  const m = glob.match(/\{([^{}]+)\}/);
  if (!m) return [glob];
  const options = m[1].split(',');
  return options.flatMap((opt) => expandBraceGlob(glob.slice(0, m.index) + opt + glob.slice(m.index + m[0].length)));
}

function expandGlobs(globs) {
  return globs.flatMap(expandBraceGlob);
}

function matchesAnyGlob(relPath, globs) {
  return globs.some((g) => globToRegExp(g).test(relPath));
}

// A file-type-aware comment marker, used so `ratchet-allow(<check-id>):`
// only counts when it follows a real comment marker on the line — not text
// sitting inside a string literal elsewhere on that same line.
function commentPrefixFor(file) {
  return /\.(py|sh|bash)$/.test(file) ? '#' : '//';
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// `ratchet-allow(<check-id>): <reason>` — check-specific, so a marker naming
// one check never silently exempts a site that belongs to a different check.
function allowRegexFor(file, checkId) {
  return new RegExp(`${commentPrefixFor(file)}.*ratchet-allow\\(${escapeRegExp(checkId)}\\):`);
}

// Strips whole `#`-comment lines (YAML/Makefile/pyproject.toml style) before
// a wiring file's content is matched against a runner's `by` string, so a
// `by` mentioned only in a comment doesn't count as actually wired.
function stripHashCommentLines(content) {
  return content
    .split('\n')
    .filter((l) => !/^\s*#/.test(l))
    .join('\n');
}

// Normalizes one wiring line down to its individual command(s) and checks
// whether `by` equals one of them exactly — not merely appears as a
// substring/prefix of a longer command. See ratchets.json's `_comment` for
// the full rationale and residual limits (trailing comments, echo strings).
// Strips leading Makefile variable references (`$(WRAPPER)`, `$(RUNNER)`, ...)
// and leading shell `VAR=value` assignments, repeatedly, so a command like
// `FOO=bar $(WRAPPER) node --test 'x'` reduces to `node --test 'x'` — the
// `$(WRAPPER) $(RUNNER) ...` convention used elsewhere in this template's own
// Makefile would otherwise never match a concrete `by` string.
function stripLeadingMakeVarsAndAssignments(text) {
  let s = text;
  let changed = true;
  while (changed) {
    changed = false;
    let m = s.match(/^\$\([A-Za-z_][A-Za-z0-9_]*\)\s*/);
    if (m) {
      s = s.slice(m[0].length);
      changed = true;
      continue;
    }
    m = s.match(/^[A-Za-z_][A-Za-z0-9_]*=\S*\s*/);
    if (m) {
      s = s.slice(m[0].length);
      changed = true;
    }
  }
  return s;
}

function commandSegmentsOf(rawLine) {
  const isMakefileRecipe = rawLine.startsWith('\t');
  let line = isMakefileRecipe ? rawLine.slice(1) : rawLine;
  if (isMakefileRecipe) {
    while (line[0] === '@' || line[0] === '-' || line[0] === '+') line = line.slice(1);
  }
  line = line.trim();
  if (line.startsWith('- ')) line = line.slice(2).trim(); // YAML list item
  if (line.startsWith('run:')) line = line.slice(4).trim(); // YAML `run:` step
  return line
    .split(/&&|;|\|/)
    .map((s) => stripLeadingMakeVarsAndAssignments(s.trim()).trim())
    .filter(Boolean);
}

function isWiredAnywhere(wiringContent, by) {
  return wiringContent.split('\n').some((line) => commandSegmentsOf(line).includes(by));
}

// Precomputed line index: O(n) once per file instead of O(n) per match
// (content.slice(0, i).split('\n').length would be quadratic across many
// matches in a large file).
function fileLineNumberer(content) {
  const offsets = [0];
  for (let i = 0; i < content.length; i++) if (content[i] === '\n') offsets.push(i + 1);
  return (charIndex) => {
    let lo = 0;
    let hi = offsets.length - 1;
    let ans = 0;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      if (offsets[mid] <= charIndex) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans + 1;
  };
}

const allRootFiles = gitLsFiles(roots);
const rootsAbsent = allRootFiles.length === 0;

function runPatternCheck(check) {
  const sites = [];
  const filesConsideredSet = new Set();
  for (const pattern of check.patterns) {
    const candidates = allRootFiles.filter((f) => pattern.ext.some((e) => f.endsWith(e)));
    candidates.forEach((f) => filesConsideredSet.add(f));
    const re = new RegExp(pattern.regex, 'g');
    for (const file of candidates) {
      const content = readFileSync(join(repoRoot, file), 'utf8');
      const lines = content.split('\n');
      const lineOf = fileLineNumberer(content);
      const allowRe = allowRegexFor(file, check.id);
      re.lastIndex = 0;
      let m;
      while ((m = re.exec(content)) !== null) {
        const start = m.index;
        const end = start + m[0].length;
        const startLine = lineOf(start);
        const endLine = lineOf(Math.max(start, end - 1));
        let allowed = false;
        for (let i = startLine - 1; i < endLine; i++) {
          if (allowRe.test(lines[i])) {
            allowed = true;
            break;
          }
        }
        sites.push({ file, line: startLine, label: pattern.label, allowed });
        if (m[0].length === 0) re.lastIndex++; // guard against zero-width match loops
      }
    }
  }
  return { sites, filesConsidered: [...filesConsideredSet] };
}

function resolveWiringFiles(wiringFilesConfig) {
  const resolved = [];
  for (const pattern of wiringFilesConfig) {
    if (pattern.includes('*')) {
      const dir = dirname(pattern);
      const base = basename(pattern);
      const dirPath = join(repoRoot, dir);
      if (!existsSync(dirPath)) continue;
      const entryRe = globToRegExp(base);
      for (const entry of readdirSync(dirPath)) {
        if (entryRe.test(entry)) resolved.push(`${dir}/${entry}`);
      }
    } else if (existsSync(join(repoRoot, pattern))) {
      resolved.push(pattern);
    }
  }
  return resolved;
}

function runUnreferencedCheck(check) {
  const testGlobs = expandGlobs(check.testGlobs);
  const testFiles = allRootFiles.filter((f) => matchesAnyGlob(f, testGlobs));

  // Explicit wiring files only — never arbitrary files under the scanned
  // roots, so a runner's `by` can't be satisfied by coincidence. Full-line
  // `#`-comments are stripped first, so a `by` mentioned only in a comment
  // doesn't count as wired.
  const wiringFiles = resolveWiringFiles(check.wiringFiles);
  const wiringContent = wiringFiles
    .map((f) => stripHashCommentLines(readFileSync(join(repoRoot, f), 'utf8')))
    .join('\n');

  const runners = (check.runners ?? []).map((r) => ({
    ...r,
    covers: expandGlobs(r.covers),
    wired: isWiredAnywhere(wiringContent, r.by),
  }));

  const sites = [];

  // A declared runner not actually wired anywhere is a violation in its own
  // right — otherwise the declaration could lie about what runs the tests.
  for (const runner of runners) {
    if (!runner.wired) {
      sites.push({
        file: '.claude/ratchets.json',
        line: 0,
        label: `runner not invoked by any wiring file: "${runner.by}"`,
        allowed: false,
      });
    }
  }

  for (const file of testFiles) {
    const covered = runners.some((r) => r.wired && matchesAnyGlob(file, r.covers));
    if (!covered) {
      const content = readFileSync(join(repoRoot, file), 'utf8');
      const allowRe = allowRegexFor(file, check.id);
      // Only the first 3 lines are checked — an orphan exemption is a
      // file-level statement, not tied to a specific matched line, so it
      // must be declared up front rather than found anywhere in the file.
      const allowed = content.split('\n').slice(0, 3).some((l) => allowRe.test(l));
      sites.push({ file, line: 1, label: 'orphaned test file (no declared runner covers it)', allowed });
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

  if (filesConsidered.length === 0 && rootsAbsent) {
    if (check.baseline === 0) {
      return { check, violations, allowed, count, severity: 'pass', reason: `scanned 0 files (roots absent: ${roots.join(', ')})` };
    }
    return {
      check,
      violations,
      allowed,
      count,
      // A vanished root is a different, worse signal than ordinary slack
      // (the whole check has gone blind) — always fatal, not gated by --strict.
      severity: 'fail',
      reason: `scanned 0 files (roots absent: ${roots.join(', ')}) — scan roots vanished — refusing to pass`,
    };
  }

  const filterNote = filesConsidered.length === 0 ? "0 candidate files matched this check's filter; " : '';
  if (count > check.baseline) {
    return { check, violations, allowed, count, severity: 'fail', reason: `${filterNote}${count} > baseline ${check.baseline} (regression)` };
  }
  if (count < check.baseline) {
    return {
      check,
      violations,
      allowed,
      count,
      severity: STRICT ? 'fail' : 'warn',
      reason: `${filterNote}${count} < baseline ${check.baseline} (slack) — run --update to lower the baseline`,
    };
  }
  return { check, violations, allowed, count, severity: 'pass', reason: `${filterNote}${count} == baseline ${check.baseline}` };
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

  if (r.severity === 'fail') {
    anyFail = true;
    console.log('FAIL');
  } else if (r.severity === 'warn') {
    console.log('WARN (use --strict to fail on this)');
  } else {
    console.log('PASS');
  }
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
    // NOTE: this rewrites the whole file via JSON.stringify (2-space indent)
    // rather than patching only the changed baseline values in place. Given
    // ratchets.json is itself written in this same style, the practical
    // diff is just the touched numbers — but any manual reformatting of the
    // file would be lost. A minimal in-place patch was judged not worth the
    // added complexity for a config this size; revisit if that changes.
    writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
    console.log(`\nWrote ${configPath}`);
  } else {
    console.log('\nNo baselines needed lowering.');
  }
  const stillRegressed = results.some((r) => r.count > r.check.baseline);
  process.exit(stillRegressed ? 1 : 0);
}

process.exit(anyFail ? 1 : 0);
