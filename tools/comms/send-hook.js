#!/usr/bin/env node
'use strict';
/**
 * Send a notification to a Slack channel via incoming webhook.
 *
 * Usage:
 *   node tools/comms/send-hook.js --to <channel> --from <sender> --message <text>
 *
 * Channel routing (set the matching env var for each channel you use):
 *   --to cto       → SLACK_WEBHOOK_CTO
 *   --to emergency → SLACK_WEBHOOK_EMERGENCY
 *   --to cos       → SLACK_WEBHOOK_COS
 *
 * Exit codes: 0 = success, 1 = config error or HTTP error
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

if (!to || !message) {
  process.stderr.write(
    'Usage: node send-hook.js --to <channel> --from <sender> --message <text>\n'
  );
  process.exit(1);
}

const WEBHOOK_MAP = {
  cto: process.env.SLACK_WEBHOOK_CTO,
  emergency: process.env.SLACK_WEBHOOK_EMERGENCY,
  cos: process.env.SLACK_WEBHOOK_COS,
};

const webhookUrl = WEBHOOK_MAP[to];
if (!webhookUrl) {
  process.stderr.write(
    `No webhook configured for channel "${to}". ` +
    `Set SLACK_WEBHOOK_${to.toUpperCase()} env var.\n`
  );
  process.exit(1);
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
