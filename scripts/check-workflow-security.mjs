#!/usr/bin/env node
// check-workflow-security.mjs — enforce GitHub Actions hardening rules that
// otherwise exist only as prose. Run by CI lint and `make quality`.
//
// Rules, per .github/workflows/*.yml (composite actions under .github/actions/
// are not scanned):
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
// Line-based, not a YAML parser: it errs toward flagging. A false positive
// fails loudly; fix the workflow or the pattern.
//
// Usage: node scripts/check-workflow-security.mjs [workflows-dir]
import { readdirSync, readFileSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const indentOf = (l) => l.length - l.trimStart().length;
const isItem = (l) => /^\s*-\s/.test(l);

/** Text of the step (list item) containing line i. */
function stepAround(lines, i) {
  let start = i;
  if (!isItem(lines[i])) {
    while (start > 0 && !(isItem(lines[start]) && indentOf(lines[start]) < indentOf(lines[i]))) start--;
  }
  const dash = indentOf(lines[start]);
  let end = start + 1;
  while (end < lines.length) {
    const l = lines[end];
    if (l.trim() !== '' && (indentOf(l) < dash || (indentOf(l) === dash && isItem(l)))) break;
    end++;
  }
  return lines.slice(start, end).join('\n');
}

/** Return violation strings for one workflow file's text. */
export function checkWorkflow(name, text) {
  const out = [];
  const lines = text.split('\n').filter((l) => !/^\s*#/.test(l));
  const code = lines.join('\n');

  if (!/^permissions:/m.test(code)) {
    out.push(`${name}: no top-level "permissions:" block (defaults to the repo-wide token scope)`);
  } else if (/^permissions:\s*write-all/m.test(code)) {
    out.push(`${name}: top-level "permissions: write-all"`);
  }

  let checkouts = 0;
  lines.forEach((l, i) => {
    if (!/uses:\s*['"]?actions\/checkout@/.test(l)) return;
    checkouts++;
    if (!/persist-credentials:\s*['"]?false/.test(stepAround(lines, i))) {
      out.push(`${name}: actions/checkout without "persist-credentials: false"`);
    }
  });

  if (/\bpull_request_target\b/.test(code) && checkouts > 0) {
    out.push(`${name}: pull_request_target workflow checks out code`);
  }

  const onWorkflowRun = /^\s*workflow_run:/m.test(code) || /^on:.*\bworkflow_run\b/m.test(code);
  if (onWorkflowRun && !/head_repository\.full_name\s*==\s*github\.repository/.test(code)) {
    out.push(`${name}: workflow_run trigger without a "head_repository.full_name == github.repository" guard`);
  }
  return out;
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
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
