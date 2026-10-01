// Prints a Stripe-style signature header for a payload file:
//   node scripts/sign-webhook.mjs <secret> <payload-file> [--age=SECONDS]
// Header format (documented in functions/_lib/webhook.js): t=TIMESTAMP,v1=HMAC_SHA256(secret, `${t}.${body}`)
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
const [secret, file, ...rest] = process.argv.slice(2);
if (!secret || !file) { console.error('usage: sign-webhook.mjs <secret> <payload-file> [--age=SECONDS]'); process.exit(2); }
const age = Number((rest.find((a) => a.startsWith('--age=')) || '--age=0').split('=')[1]);
const t = Math.floor(Date.now() / 1000) - age;
const body = readFileSync(file, 'utf8');
const v1 = createHmac('sha256', secret).update(`${t}.${body}`).digest('hex');
process.stdout.write(`t=${t},v1=${v1}`);
