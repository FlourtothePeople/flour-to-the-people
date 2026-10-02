// POST /api/shipping-quote
//
// Body: { cart: [{ id, qty }, ...], postal_code: '24091' }
// Returns: { shipping_cents, zone } — the same amount /api/checkout will charge.
// Lets the checkout form show shipping as soon as the customer types a ZIP code.

import { validateCart } from '../_lib/products.js';
import { calculateShipping } from '../_lib/shipping.js';

export async function onRequestPost({ request }) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Invalid JSON body' }, 400);
  }
  try {
    const { total_weight_oz } = validateCart(body && body.cart);
    const s = calculateShipping(total_weight_oz, body && body.postal_code);
    return json({ shipping_cents: s.cents, zone: s.zone });
  } catch (e) {
    return json({ error: e.message }, 400);
  }
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
}
