#!/usr/bin/env node
// check-workflow-security.mjs — enforce GitHub Actions hardening rules that
// otherwise exist only as prose. Run by CI lint and `make quality`.
//
// Rules, per .github/workflows/*.yml:
//   1. A top-level `permissions:` block exists and is not `write-all`.
//   2. Every actions/checkout step sets `persist-credentials: false`, so the
//      token is never left in .git/config for later steps (or an agent) to read.
//      A step that must push passes the token only to that step instead.
//   3. A `pull_request_target` workflow never checks out code (it runs with
//      write access, so checking out a PR head would run untrusted code).
//   4. A `workflow_run` workflow guards on the triggering run's repository
//      (`head_repository.full_name == github.repository`), so a fork's run
//      cannot drive a job that holds write access.
//
// Usage: node scripts/check-workflow-security.mjs [workflows-dir]
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

/** Split a workflow into steps: a step starts at a `- ` list item under `steps:`. */
function stepsOf(text) {
  const steps = [];
  let current = null;
  let stepIndent = -1;
  for (const line of text.split('\n')) {
    const m = line.match(/^(\s*)- (?:name|uses|run|id|if|env|with|shell):/);
    if (m && (stepIndent === -1 || m[1].length === stepIndent)) {
      stepIndent = m[1].length;
      current = [];
      steps.push(current);
    }
    if (current) current.push(line);
  }
  return steps.map((s) => s.join('\n'));
}

/** Return violation strings for one workflow file's text. */
export function checkWorkflow(name, text) {
  const out = [];
  const code = text.split('\n').filter((l) => !/^\s*#/.test(l)).join('\n');

  if (!/^permissions:/m.test(code)) {
    out.push(`${name}: no top-level "permissions:" block (defaults to the repo-wide token scope)`);
  } else if (/^permissions:\s*write-all/m.test(code)) {
    out.push(`${name}: top-level "permissions: write-all"`);
  }

  const checkouts = stepsOf(code).filter((s) => /uses:\s*actions\/checkout@/.test(s));
  for (const step of checkouts) {
    if (!/persist-credentials:\s*false/.test(step)) {
      out.push(`${name}: actions/checkout without "persist-credentials: false"`);
    }
  }

  if (/^\s*pull_request_target:/m.test(code) && checkouts.length > 0) {
    out.push(`${name}: pull_request_target workflow checks out code`);
  }

  if (/^\s*workflow_run:/m.test(code) && !/head_repository\.full_name\s*==\s*github\.repository/.test(code)) {
    out.push(`${name}: workflow_run trigger without a "head_repository.full_name == github.repository" guard`);
  }
  return out;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = process.argv[2] ?? '.github/workflows';
  const violations = readdirSync(dir)
    .filter((f) => /\.ya?ml$/.test(f))
    .flatMap((f) => checkWorkflow(f, readFileSync(join(dir, f), 'utf8')));
  if (violations.length > 0) {
    console.error(violations.map((v) => `ERROR: ${v}`).join('\n'));
    process.exit(1);
  }
  console.log('workflow security: ok');
}
