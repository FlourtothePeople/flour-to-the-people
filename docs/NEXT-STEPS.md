# Where things stand (October 2, 2026)

## Done

- **Site:** live at https://flour-to-the-people-5vp.pages.dev on the free Cloudflare Pages plan, account FlourtothePeople@protonmail.com.
- **Code:** GitHub repository `FlourtothePeople/flour-to-the-people`. Every push to `main` deploys automatically (`.github/workflows/deploy.yml`).
- **Payments:** Stripe **live** mode. A real $16.00 order succeeded and the webhook returned 200. That order was kept, not refunded.
- **Orders database:** Cloudflare D1 `flour-to-the-people-orders`, created and filled by `scripts/ci-payments.sh` during each deploy.
- **GitHub Actions secrets:** `CLOUDFLARE_API_TOKEN` (Pages Edit + D1 Edit), `CLOUDFLARE_ACCOUNT_ID`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_SECRET_KEY` (live keys). The Stripe webhook signing secret goes straight from Stripe to Cloudflare and is never stored in GitHub.

- **Domain:** flourtothepeople.org and www.flourtothepeople.org point to the site (Cloudflare nameservers `daisy`/`jay.ns.cloudflare.com`, set October 2, 2026). The Stripe webhook still uses the `-5vp.pages.dev` address, which stays valid.
- **Old copy cut off:** on October 2, 2026 the Stripe live secret key was rotated (old key expired immediately), the new key was stored in the GitHub secret and redeployed, both unused restricted keys were deleted, and the old copy's webhook endpoint was deleted.
- **Old hosting:** Domain.com Basic Hosting and both nsProtect certificates set not to renew (they expire May and July 2027). Domain registration, privacy and expiration protection stay on auto-renew (paid through April 12, 2028).
- **Order notifications:** Stripe "Successful payment receipt" emails are on.
- **Sales tax:** 1% on Virginia orders' item subtotal (`docs/KNOWN-ISSUES.md`, issue 1).

## Still to do

1. Confirm with an accountant: Virginia sales tax registration and filing, and whether anything is owed on orders taken before October 2, 2026 without tax.
