// POST /api/order-alert-test
//
// Sends a sample order alert email so the mill can confirm alerts arrive.
// Only callers who present the Proton SMTP token itself (Authorization: Bearer
// <token>) can use it: the "Send a test order alert" GitHub workflow does this.
// Returns { sent: true } or { sent: false, error } (the error never contains the token).

import { sendMail, orderAlert, DEFAULT_ALERT_TO } from '../_lib/mailer.js';
import { connect } from '../_lib/smtp-socket.js';

export async function onRequestPost({ request, env }) {
  const token = env.PROTON_SMTP_TOKEN;
  if (!token) return json({ sent: false, error: 'PROTON_SMTP_TOKEN is not set on the site' }, 503);
  const given = (request.headers.get('authorization') || '').replace(/^Bearer\s+/i, '');
  if (!(await sameSecret(given, token))) return json({ sent: false, error: 'unauthorized' }, 401);

  const sample = {
    id: 'pi_TEST_example', livemode: true, amount: 2544, receipt_email: 'customer@example.com',
    shipping: { name: 'Test Customer', address: { line1: '1 Mill Rd', city: 'Floyd', state: 'VA', postal_code: '24091' } },
    metadata: {
      cart_items: JSON.stringify([{ qty: 1, name: 'All-Purpose Flour', size: '3 lb', line_subtotal_cents: 1600 }]),
      subtotal_cents: '1600', shipping_cents: '928', tax_cents: '16',
      shipping_method: 'USPS Ground Advantage, 4 lb', shipping_zone: '1',
    },
  };
  const { subject, text } = orderAlert(sample);
  try {
    await sendMail({ connect, token, to: env.ORDER_ALERT_TO || DEFAULT_ALERT_TO,
      subject: 'TEST — ' + subject,
      text: 'This is a TEST of the order alert. No real order was placed.\n\n' + text });
    return json({ sent: true });
  } catch (e) {
    return json({ sent: false, error: String(e.message).split(token).join('[token]') }, 502);
  }
}

async function sameSecret(a, b) {
  const enc = new TextEncoder();
  const [x, y] = await Promise.all([crypto.subtle.digest('SHA-256', enc.encode(a)), crypto.subtle.digest('SHA-256', enc.encode(b))]);
  const u = new Uint8Array(x), v = new Uint8Array(y);
  let d = 0; for (let i = 0; i < u.length; i++) d |= u[i] ^ v[i];
  return d === 0;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
}
