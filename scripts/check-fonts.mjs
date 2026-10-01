// Enforces the site's hard rule: no font-size below 12px anywhere in public/index.html,
// in <style> rules or in inline style="" attributes. Exit code 1 on any violation.
// Limit: it reads px values only; rem, em, and clamp() sizes are not evaluated.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const file = join(dirname(fileURLToPath(import.meta.url)), '..', 'public', 'index.html');
const lines = readFileSync(file, 'utf8').split('\n');
const bad = [];
lines.forEach((line, i) => {
  for (const m of line.matchAll(/font-size\s*:\s*([0-9]*\.?[0-9]+)px/g)) {
    if (parseFloat(m[1]) < 12) bad.push(`line ${i + 1}: font-size ${m[1]}px`);
  }
});
if (bad.length) {
  console.error('FONT FLOOR CHECK FAILED (minimum is 12px):\n  ' + bad.join('\n  '));
  console.error('Inline style="" attributes override CSS rules, so fix the attribute, not only the stylesheet.');
  process.exit(1);
}
console.log('Font floor check passed: no px font-size below 12px.');
