#!/usr/bin/env node
// Example `command` scorer: any executable, any language, output on stdin,
// exit 0 = pass. This one demonstrates the stack-agnostic extension point —
// a real project might shell out to a Python linter, a Go binary, etc.
//
// Rule: the sample output must not end in trailing whitespace.

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (chunk) => { input += chunk; });
process.stdin.on('end', () => {
  if (input !== input.trimEnd()) {
    process.stderr.write('output ends with trailing whitespace\n');
    process.exit(1);
  }
  process.exit(0);
});
