#!/usr/bin/env node
'use strict';
/**
 * Send a notification to a Slack channel via incoming webhook.
 *
 * Usage:
 *   node tools/comms/send-hook.js --to <channel> --from <sender> --message <text>
 *                                 [--require]
 *
 * CHANNEL ROUTING IS BY CONVENTION, NOT A HARDCODED LIST.
 * `--to <channel>` reads `SLACK_WEBHOOK_<CHANNEL>` from the environment, with
 * dashes upper-cased to underscores:
 *
 *   --to ci-alerts  →  SLACK_WEBHOOK_CI_ALERTS
 *   --to emergency  →  SLACK_WEBHOOK_EMERGENCY
 *
 * This template ships no channels and names no team roles. A downstream repo
 * decides which channels exist purely by setting the matching env vars — see
 * REPO_SETUP.md.
 *
 * UNCONFIGURED CHANNELS ARE SKIPPED, NOT FAILED. A template, or a fork with no
 * Slack workspace, must not have red CI because a notification has nowhere to
 * go. Pass `--require` to make a missing webhook a hard error — which is what a
 * repo that genuinely depends on the notification landing should do.
 *
 * Exit codes:
 *   0 = delivered, or skipped because the channel is not configured
 *   1 = bad usage, malformed webhook URL, or delivery failure
 */

const https = require('https');
const { URL } = require('url');

const args = process.argv.slice(2);
const get = (flag) => {
  const i = args.indexOf(flag);
  return i !== -1 ? (args[i + 1] ?? null) : null;
};

const to = get('--to');
const from = get('--from') ?? 'ci';
const message = get('--message');
const required = args.includes('--require');

if (!to || !message) {
  process.stderr.write(
    'Usage: node send-hook.js --to <channel> --from <sender> --message <text> [--require]\n'
  );
  process.exit(1);
}

// Constrain the channel charset before deriving an env var name from it, so a
// caller can't reach an arbitrary variable through a crafted --to value.
if (!/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(to)) {
  process.stderr.write(
    `Invalid channel name "${to}" — use letters, digits, dashes or underscores.\n`
  );
  process.exit(1);
}

const envVar = `SLACK_WEBHOOK_${to.toUpperCase().replace(/-/g, '_')}`;
const webhookUrl = process.env[envVar];

if (!webhookUrl) {
  if (required) {
    process.stderr.write(
      `${envVar} is not set, so channel "${to}" has nowhere to deliver, ` +
      `and --require was passed.\n`
    );
    process.exit(1);
  }
  // Not an error: an unconfigured channel is the template's default state.
  process.stdout.write(
    `Skipping notification — ${envVar} is not set (channel "${to}").\n`
  );
  process.exit(0);
}

const payload = JSON.stringify({
  text: message,
  username: `CI Bot (from: ${from})`,
  icon_emoji: ':robot_face:',
});

let parsed;
try {
  parsed = new URL(webhookUrl);
} catch {
  process.stderr.write(`Invalid webhook URL for channel "${to}"\n`);
  process.exit(1);
}

const options = {
  hostname: parsed.hostname,
  path: parsed.pathname + parsed.search,
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(payload),
  },
};

const req = https.request(options, (res) => {
  let body = '';
  res.on('data', (chunk) => { body += chunk; });
  res.on('end', () => {
    if (res.statusCode !== 200) {
      process.stderr.write(`Slack webhook returned ${res.statusCode}: ${body}\n`);
      process.exit(1);
    }
    process.stdout.write(`Sent to #${to}\n`);
  });
});

req.on('error', (err) => {
  process.stderr.write(`Failed to send notification: ${err.message}\n`);
  process.exit(1);
});

req.write(payload);
req.end();
