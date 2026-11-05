import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { checkWorkflow } from '../check-workflow-security.mjs';

const OK = `name: x
on: pull_request
permissions:
  contents: read
jobs:
  a:
    steps:
      - uses: actions/checkout@abc # v1
        with:
          persist-credentials: false
      - run: echo hi
`;

test('clean workflow passes', () => {
  assert.deepEqual(checkWorkflow('ok.yml', OK), []);
});

test('missing permissions is flagged', () => {
  const v = checkWorkflow('p.yml', OK.replace(/permissions:\n  contents: read\n/, ''));
  assert.equal(v.length, 1);
  assert.match(v[0], /permissions/);
});

test('write-all is flagged', () => {
  const v = checkWorkflow('p.yml', OK.replace('permissions:\n  contents: read', 'permissions: write-all'));
  assert.match(v.join(), /write-all/);
});

test('persist-credentials true or absent is flagged', () => {
  assert.match(checkWorkflow('c.yml', OK.replace('persist-credentials: false', 'persist-credentials: true')).join(), /persist-credentials/);
  assert.match(checkWorkflow('c.yml', OK.replace('        with:\n          persist-credentials: false\n', '')).join(), /persist-credentials/);
});

test('a commented-out persist-credentials: false does not count', () => {
  const v = checkWorkflow('c.yml', OK.replace('persist-credentials: false', '# persist-credentials: false'));
  assert.match(v.join(), /persist-credentials/);
});

test('pull_request_target with a checkout is flagged', () => {
  const v = checkWorkflow('t.yml', OK.replace('on: pull_request', 'on:\n  pull_request_target:'));
  assert.match(v.join(), /pull_request_target/);
});

test('workflow_run needs the same-repo guard', () => {
  const wr = OK.replace('on: pull_request', 'on:\n  workflow_run:\n    workflows: [CI]');
  assert.match(checkWorkflow('w.yml', wr).join(), /workflow_run/);
  const guarded = wr.replace('jobs:', 'jobs:\n  # g\n  g:\n    if: github.event.workflow_run.head_repository.full_name == github.repository');
  assert.deepEqual(checkWorkflow('w.yml', guarded).filter((m) => /workflow_run/.test(m)), []);
});

test('every real workflow in this repo passes', () => {
  const dir = new URL('../../.github/workflows/', import.meta.url);
  for (const f of readdirSync(dir).filter((n) => /\.ya?ml$/.test(n))) {
    assert.deepEqual(checkWorkflow(f, readFileSync(new URL(f, dir), 'utf8')), [], f);
  }
});
