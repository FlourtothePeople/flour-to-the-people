// Compares every product in public/index.html (add({id:"ap",...,price:8,...}))
// with functions/_lib/products.js (price_cents). Exit code 1 on any difference.
// Customers see the page price; the server charges the products.js price.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const html = readFileSync(join(root, 'public', 'index.html'), 'utf8');
const { PRODUCTS } = await import(join(root, 'functions', '_lib', 'products.js'));

const page = new Map();
for (const m of html.matchAll(/add\(\{id:"([a-z0-9]+)",name:"([^"]*)",size:"([^"]*)",price:([0-9.]+)/g)) {
  page.set(m[1], { name: m[2], size: m[3], price_cents: Math.round(parseFloat(m[4]) * 100) });
}

const problems = [];
for (const [id, p] of Object.entries(PRODUCTS)) {
  const h = page.get(id);
  if (!h) { problems.push(`${id} (${p.name}) is in products.js but has no add() button in index.html`); continue; }
  if (h.price_cents !== p.price_cents) problems.push(`${id} (${p.name}): page ${h.price_cents}c, server ${p.price_cents}c`);
  if (h.size !== p.size) problems.push(`${id} (${p.name}): page size "${h.size}", server size "${p.size}"`);
}
for (const id of page.keys()) if (!PRODUCTS[id]) problems.push(`${id} has an add() button in index.html but is missing from products.js (checkout would reject it)`);

if (problems.length) {
  console.error('PRICE CHECK FAILED:\n  ' + problems.join('\n  '));
  process.exit(1);
}
console.log(`Price check passed: ${Object.keys(PRODUCTS).length} products match between index.html and products.js.`);
