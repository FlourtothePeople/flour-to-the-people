// POST /api/checkout
//
// Body (JSON):
//   {
//     cart: [{ id: 'ap', qty: 2 }, ...],
//     email: 'customer@example.com',
//     name: 'Jane Smith',
//     address: { line1, line2?, city, state, postal_code, country? }
//   }
//
// Response:
//   {
//     clientSecret: 'pi_..._secret_...',
//     orderId: 'pi_...',
//     amount: {
//       subtotal_cents: 2400,
//       shipping_cents: 928,   // cheapest USPS Click-N-Ship option to this ZIP
//       tax_cents: 24,     // 1% of subtotal for Virginia addresses, else 0
//       total_cents: 3424,
//     }
//   }
//
// Errors return: { error: 'human-readable message' }, HTTP 400 or 500.

import { validateCart, calculateTaxCents, ORDER_MIN_CENTS, ORDER_MAX_CENTS } from '../_lib/products.js';
import { calculateShipping } from '../_lib/shipping.js';
import { createCustomer, createPaymentIntent, retrievePaymentIntent } from '../_lib/stripe.js';

export async function onRequestPost({ request, env }) {
  if (!env.STRIPE_SECRET_KEY) {
    return jsonResponse({ error: 'Payment system not configured' }, 500);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body' }, 400);
  }

  // --- Validate inputs ---
  const { cart, email, name, address } = body || {};
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return jsonResponse({ error: 'Valid email required' }, 400);
  }
  if (!name || typeof name !== 'string' || name.trim().length < 2) {
    return jsonResponse({ error: 'Name required' }, 400);
  }
  if (!address || typeof address !== 'object') {
    return jsonResponse({ error: 'Shipping address required' }, 400);
  }
  for (const field of ['line1', 'city', 'state', 'postal_code']) {
    if (!address[field] || typeof address[field] !== 'string' || !address[field].trim()) {
      return jsonResponse({ error: `Shipping address missing: ${field}` }, 400);
    }
  }

  // --- Validate cart against server catalog ---
  let cartValidation;
  try {
    cartValidation = validateCart(cart);
  } catch (e) {
    return jsonResponse({ error: e.message }, 400);
  }

  const { lineItems, subtotal_cents, total_weight_oz } = cartValidation;
  let shipping;
  try {
    shipping = calculateShipping(total_weight_oz, address.postal_code);
  } catch (e) {
    return jsonResponse({ error: e.message }, 400);
  }
  const shipping_cents = shipping.cents;
  const pre_tax_cents = subtotal_cents + shipping_cents;

  if (pre_tax_cents < ORDER_MIN_CENTS) {
    return jsonResponse({ error: 'Order total below minimum' }, 400);
  }
  if (pre_tax_cents > ORDER_MAX_CENTS) {
    return jsonResponse({ error: 'Order total exceeds maximum' }, 400);
  }

  // --- Create Stripe Customer with shipping address ---
  // Stripe Tax needs a Customer with an address to compute tax.
  let customer;
  try {
    customer = await createCustomer(env.STRIPE_SECRET_KEY, {
      email: email.trim().toLowerCase(),
      name: name.trim(),
      address: {
        line1: address.line1.trim(),
        line2: (address.line2 || '').trim(),
        city: address.city.trim(),
        state: address.state.trim(),
        postal_code: address.postal_code.trim(),
        country: address.country || 'US',
      },
    });
  } catch (e) {
    return jsonResponse({ error: 'Failed to create customer record' }, 500);
  }

  // --- Sales tax ---
  // 1% Virginia grocery rate on the item subtotal for Virginia addresses, else 0.
  // See calculateTaxCents in functions/_lib/products.js.
  const tax_cents = calculateTaxCents(subtotal_cents, address.state);

  // --- Create PaymentIntent ---
  let intent;
  try {
    intent = await createPaymentIntent(env.STRIPE_SECRET_KEY, {
      amount: pre_tax_cents + tax_cents,
      currency: 'usd',
      customer: customer.id,
      automatic_payment_methods: { enabled: true },
      // Hold, don't charge: the mill confirms stock, then captures the payment in
      // the Stripe Dashboard (Payments > Uncaptured > Capture), or cancels it to
      // release the hold. Stripe only offers payment methods that support holds
      // (cards, Apple Pay, Google Pay, Link, Klarna, Afterpay, Affirm; not ACH).
      // Card holds expire after about 5 days (Visa) to 7 days (others).
      capture_method: 'manual',
      shipping: {
        name: name.trim(),
        address: {
          line1: address.line1.trim(),
          line2: (address.line2 || '').trim(),
          city: address.city.trim(),
          state: address.state.trim(),
          postal_code: address.postal_code.trim(),
          country: address.country || 'US',
        },
      },
      receipt_email: email.trim().toLowerCase(),
      metadata: {
        cart_items: JSON.stringify(lineItems),
        subtotal_cents: String(subtotal_cents),
        shipping_cents: String(shipping_cents),
        shipping_method: shipping.method.slice(0, 500),
        shipping_zone: String(shipping.zone),
        tax_cents: String(tax_cents),
      },
    });
  } catch (e) {
    console.error('PaymentIntent create failed:', e.message);
    return jsonResponse({ error: 'Failed to initialize payment' }, 500);
  }

  const total_cents = intent.amount;

  return jsonResponse({
    clientSecret: intent.client_secret,
    orderId: intent.id,
    amount: {
      subtotal_cents,
      shipping_cents,
      tax_cents: Math.max(0, tax_cents),
      total_cents,
    },
  });
}

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
