# Nine issues in the code and guides were found while preparing this package

Each entry states what happens, how it was found, and what to change.

## 1. Tax is never charged, and `STRIPE_TAX_ENABLED` has no effect

- `functions/api/checkout.js` sets `tax_cents = 0` for every order and says in a comment that the Tax Calculation flow is planned for a later phase.
- `functions/api/config.js` returns `taxEnabled` to the browser, but `public/index.html` never reads it.
- `SETUP.md` step 6 and its failure-mode list describe the flag as switching tax on; it does not.
- To collect tax, implement Stripe's Tax Calculation API (`/v1/tax/calculations`, then the PaymentIntent, then `/v1/tax/transactions`) in `checkout.js` and the webhook. The decision whether to collect tax is H7.

## 2. `SETUP.md` step 8 asks for a $0.50 test purchase, which the site cannot accept

The cheapest product costs $7.00 and shipping is $8.00 below a $50.00 subtotal, so the smallest order is $15.00 (`ORDER_MIN_CENTS` is 50 cents, but the real minimum comes from the prices). Use a $15.00 purchase and refund it.

## 3. Two database names appeared in the original files

`SETUP.md` and `wrangler.toml` use `flour-to-the-people-orders`. `schema.sql` named `flour-to-the-people` in a comment; the comment now says `flour-to-the-people-orders`.

## 4. The original deploy published documentation and the schema

The original workflow deployed the repository root (`pages deploy .`). A local run of that layout served the real contents of `SETUP.md` and `schema.sql` to any visitor. This package deploys only `public/`, which removes the exposure. If the original deployment is still live, a redeploy from this layout removes the two files from the site.

## 5. Page prices and server prices can drift apart

`public/index.html` shows a price; `functions/_lib/products.js` sets the charged price. A mismatch shows one price and charges another. `scripts/check-prices.mjs` compares all 21 products and runs in the deploy workflow.

## 6. Unknown web addresses answer with the home page and status 200

The project has no `404.html`, so Cloudflare Pages returns `public/index.html` for any unknown path. Status checks alone cannot show that a file is absent; check the response body (`scripts/test-local.sh` does this).

## 7. The contact form opens the visitor's email program

The "Send Message" button builds a `mailto:` link to FlourtothePeople@protonmail.com. No message reaches a server, so there is no record of messages and no spam filtering beyond the mailbox.

## 8. Orders are recorded but nothing notifies the mill automatically

The webhook writes each paid order to D1 with status `pending`. The code sends no email to the mill (the stubs for email, shipping labels, and stock counts are marked "Phase 2" in `stripe-webhook.js`). The mill learns about orders from Stripe Dashboard notification settings or by querying D1 (`AGENTS.md`, "Reading and fulfilling orders").

## 9. `wrangler.toml` makes the file the source of truth for bindings

With `pages_build_output_dir` in `wrangler.toml`, Cloudflare uses the file's D1 binding for deployments. `SETUP.md` step 3 describes adding the D1 binding in the dashboard instead. Use one method; this package uses the file.
