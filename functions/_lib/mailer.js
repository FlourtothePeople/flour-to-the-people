// Sends email through Proton's SMTP server (smtp.protonmail.ch:587, STARTTLS,
// AUTH PLAIN) using a Proton SMTP token for orders@flourtothepeople.org.
//
// `connect` is passed in (Cloudflare's TCP socket API from ./smtp-socket.js in
// production; a fake in tests), so this file has no Workers-only imports.

export const SMTP_HOST = 'smtp.protonmail.ch';
export const SMTP_PORT = 587;
export const MAIL_FROM = 'orders@flourtothepeople.org';
export const MAIL_FROM_NAME = 'Flour to the People';
export const DEFAULT_ALERT_TO = 'FlourtothePeople@protonmail.com';

// ---- encoding helpers (no Node Buffer in Workers) ----
function b64(str) {
  const bytes = new TextEncoder().encode(str);
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}
// Header text may contain customer-typed names: strip line breaks (header
// injection) and encode non-ASCII per RFC 2047.
export function headerText(s) {
  const clean = String(s).replace(/[\r\n]+/g, ' ').slice(0, 300);
  return /^[\x20-\x7e]*$/.test(clean) ? clean : `=?UTF-8?B?${b64(clean)}?=`;
}
function bodyB64(text) {
  return b64(text.replace(/\r?\n/g, '\r\n')).replace(/.{1,76}/g, '$&\r\n');
}

export function buildMessage({ to, subject, text, from = MAIL_FROM, fromName = MAIL_FROM_NAME, date = new Date() }) {
  const id = `${date.getTime()}.${Math.random().toString(36).slice(2)}@flourtothepeople.org`;
  return [
    `From: ${headerText(fromName)} <${from}>`,
    `To: <${to}>`,
    `Subject: ${headerText(subject)}`,
    `Date: ${date.toUTCString().replace('GMT', '+0000')}`,
    `Message-ID: <${id}>`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: base64',
    '',
    bodyB64(text),
  ].join('\r\n');
}

// ---- minimal SMTP client ----
class Conn {
  constructor(socket) { this.attach(socket); }
  attach(socket) {
    this.socket = socket;
    this.reader = socket.readable.getReader();
    this.writer = socket.writable.getWriter();
    this.buf = '';
    this.dec = new TextDecoder();
  }
  release() { this.reader.releaseLock(); this.writer.releaseLock(); }
  async line() {
    for (;;) {
      const i = this.buf.indexOf('\n');
      if (i >= 0) { const l = this.buf.slice(0, i).replace(/\r$/, ''); this.buf = this.buf.slice(i + 1); return l; }
      const { value, done } = await this.reader.read();
      if (done) throw new Error('SMTP connection closed');
      this.buf += this.dec.decode(value, { stream: true });
    }
  }
  // Reads a full (possibly multi-line) reply; throws unless its code is expected.
  async reply(expect, step) {
    let l, lines = [];
    do { l = await this.line(); lines.push(l); } while (/^\d{3}-/.test(l));
    const code = Number(l.slice(0, 3));
    if (!expect.includes(code)) throw new Error(`SMTP ${step} failed: ${lines.join(' | ').slice(0, 200)}`);
    return lines;
  }
  async send(s) { await this.writer.write(new TextEncoder().encode(s + '\r\n')); }
}

export async function sendMail({ connect, user = MAIL_FROM, token, to, subject, text, timeoutMs = 20000 }) {
  if (!token) throw new Error('SMTP token not configured');
  const work = (async () => {
    const socket = connect({ hostname: SMTP_HOST, port: SMTP_PORT }, { secureTransport: 'starttls', allowHalfOpen: false });
    const c = new Conn(socket);
    try {
      await c.reply([220], 'greeting');
      await c.send('EHLO flourtothepeople.org'); await c.reply([250], 'EHLO');
      await c.send('STARTTLS'); await c.reply([220], 'STARTTLS');
      c.release();
      c.attach(socket.startTls());
      await c.send('EHLO flourtothepeople.org'); await c.reply([250], 'EHLO after TLS');
      await c.send('AUTH PLAIN ' + b64(`\u0000${user}\u0000${token}`)); await c.reply([235], 'login');
      await c.send(`MAIL FROM:<${MAIL_FROM}>`); await c.reply([250], 'MAIL FROM');
      await c.send(`RCPT TO:<${to}>`); await c.reply([250, 251], 'RCPT TO');
      await c.send('DATA'); await c.reply([354], 'DATA');
      // Dot-stuffing: a line starting with "." gets an extra "." (base64 never does, headers might).
      const msg = buildMessage({ to, subject, text }).replace(/\r\n\./g, '\r\n..');
      await c.send(msg + '\r\n.'); await c.reply([250], 'message');
      await c.send('QUIT');
    } finally {
      try { c.socket.close(); } catch {}
    }
  })();
  let t;
  const timeout = new Promise((_, rej) => { t = setTimeout(() => rej(new Error('SMTP timed out')), timeoutMs); });
  try { await Promise.race([work, timeout]); } finally { clearTimeout(t); }
}

// ---- the order alert ----
const usd = (c) => '$' + (Number(c || 0) / 100).toFixed(2);

export function orderAlert(pi, now = new Date()) {
  let items = [];
  try { items = JSON.parse(pi.metadata?.cart_items || '[]'); } catch {}
  const sub = Number(pi.metadata?.subtotal_cents || 0);
  const ship = Number(pi.metadata?.shipping_cents || 0);
  const tax = Number(pi.metadata?.tax_cents ?? (pi.amount - sub - ship));
  const one = (s) => String(s ?? '').replace(/[\r\n]+/g, ' ').trim();
  const a = Object.fromEntries(Object.entries(pi.shipping?.address || {}).map(([k, v]) => [k, one(v)]));
  const name = one(pi.shipping?.name) || '(no name)';
  const deadline = new Date(now.getTime() + 4 * 86400000)
    .toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', timeZone: 'America/New_York' });
  const dash = `https://dashboard.stripe.com/${pi.livemode ? '' : 'test/'}payments/${pi.id}`;
  const text = [
    `New order from ${name}: ${usd(pi.amount)} is ON HOLD on their card. Nothing is charged until you capture it.`,
    '',
    `APPROVE BY ${deadline.toUpperCase()}. Visa holds expire after about 5 days (others after 7); an expired hold cancels the order.`,
    '',
    'ITEMS',
    ...items.map((i) => `  ${i.qty} × ${i.name} (${i.size})  ${usd(i.line_subtotal_cents)}`),
    '',
    `  Subtotal  ${usd(sub)}`,
    `  Shipping  ${usd(ship)}`,
    `  Tax       ${usd(tax)}`,
    `  TOTAL     ${usd(pi.amount)}`,
    '',
    'SHIP TO',
    `  ${name}`,
    `  ${a.line1 || ''}${a.line2 ? ', ' + a.line2 : ''}`,
    `  ${a.city || ''}, ${a.state || ''} ${a.postal_code || ''}`,
    `  Customer email: ${pi.receipt_email || '(none)'}`,
    '',
    'LABEL TO BUY (USPS Click-N-Ship)',
    `  ${pi.metadata?.shipping_method || '(see order)'}${pi.metadata?.shipping_zone ? ', zone ' + pi.metadata.shipping_zone : ''}`,
    '',
    'WHAT TO DO',
    '  1. Check you can fill it.',
    '  2. Open the payment in Stripe:',
    `     ${dash}`,
    '  3. Click Capture to charge the card (or capture a smaller amount if',
    '     something is out of stock, and email the customer), or Cancel to',
    '     release the hold and email the customer.',
    '',
    `Order ID: ${pi.id}`,
  ].join('\n');
  return { subject: `New order: ${usd(pi.amount)} from ${name} — approve by ${deadline}`, text };
}
