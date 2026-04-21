#!/usr/bin/env node
// sync-agent-models.mjs — keep .claude/agents/*.md model frontmatter in sync with
// a single source of truth at .claude/agent-models.json.
//
// Why: without a central config, the `model:` field drifts across agent files as
// people edit them by hand. Drift is silent — an agent meant to run on opus
// quietly downgrades to sonnet. This script makes the config the source of
// truth and the agent files a generated artifact.
//
// Usage:
//   node scripts/sync-agent-models.mjs                # Sync (writes changes)
//   node scripts/sync-agent-models.mjs --check        # CI mode: exit 1 on drift
//   node scripts/sync-agent-models.mjs --dry-run      # Show diffs, no writes
//
// Config shape (.claude/agent-models.json):
//   {
//     "default": { "model": "sonnet" },
//     "agents": {
//       "security-reviewer": { "model": "opus" },
//       "test-writer":       { "model": "haiku" }
//     }
//   }
//
// Opt-in: if .claude/agent-models.json is missing, this script is a no-op.

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join, basename, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const agentsDir = join(repoRoot, '.claude', 'agents');
const configPath = join(repoRoot, '.claude', 'agent-models.json');

const args = new Set(process.argv.slice(2));
const CHECK = args.has('--check');
const DRY_RUN = args.has('--dry-run');

if (!existsSync(configPath)) {
  console.log(`no config at ${configPath} — skipping (opt-in feature)`);
  process.exit(0);
}

if (!existsSync(agentsDir)) {
  console.error(`agents directory missing: ${agentsDir}`);
  process.exit(1);
}

const config = JSON.parse(readFileSync(configPath, 'utf8'));
const defaultModel = config.default?.model;
if (!defaultModel) {
  console.error(`config ${configPath} must define default.model`);
  process.exit(1);
}
const perAgent = config.agents ?? {};

const SKIP = new Set(['_template.md']);

const agentFiles = readdirSync(agentsDir)
  .filter((f) => extname(f) === '.md' && !SKIP.has(f) && !f.startsWith('.'));

let drift = 0;
let updated = 0;

for (const file of agentFiles) {
  const path = join(agentsDir, file);
  const name = basename(file, '.md');
  const targetModel = perAgent[name]?.model ?? defaultModel;
  const before = readFileSync(path, 'utf8');
  const after = setFrontmatterModel(before, name, targetModel);
  if (after === before) continue;

  drift += 1;
  const label = CHECK ? 'DRIFT' : DRY_RUN ? 'WOULD UPDATE' : 'UPDATED';
  console.log(`${label}  ${file}  →  model: ${targetModel}`);

  if (!CHECK && !DRY_RUN) {
    writeFileSync(path, after);
    updated += 1;
  }
}

if (CHECK && drift > 0) {
  console.error(`\n${drift} agent file(s) out of sync with ${configPath}`);
  console.error(`Run: node scripts/sync-agent-models.mjs`);
  process.exit(1);
}

console.log(
  `\n${agentFiles.length} agent(s) checked, ${drift} drifted, ${updated} written.`,
);

// ---------------------------------------------------------------------------
// Frontmatter editing — line-based, no YAML dependency.
//
// Agent files come in two shapes:
//   1. With frontmatter: "---\nname: x\nmodel: sonnet\n---\n\n# Body"
//   2. Without:          "# Body"
// This function produces shape 1 with the target model, preserving other keys
// if they exist and inserting a minimal `name` key when creating fresh
// frontmatter.
function setFrontmatterModel(content, name, model) {
  const fmMatch = content.match(/^---\n([\s\S]*?)\n---\n?/);

  if (!fmMatch) {
    const fm = `---\nname: ${name}\nmodel: ${model}\n---\n\n`;
    return fm + content;
  }

  const [full, body] = fmMatch;
  const lines = body.split('\n');
  let sawModel = false;

  const newLines = lines.map((line) => {
    const m = line.match(/^(\s*model\s*:\s*)(\S.*)$/);
    if (!m) return line;
    sawModel = true;
    return `${m[1]}${model}`;
  });

  if (!sawModel) newLines.push(`model: ${model}`);

  const rebuilt = `---\n${newLines.join('\n')}\n---\n`;
  const rest = content.slice(full.length);
  return rebuilt + (rest.startsWith('\n') ? rest : `\n${rest}`);
}
