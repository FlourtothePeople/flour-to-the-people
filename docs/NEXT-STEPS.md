# Where things stand (October 1, 2026)

## Done

- **Site:** live at https://flour-to-the-people-5vp.pages.dev on the free Cloudflare Pages plan, account FlourtothePeople@protonmail.com.
- **Code:** GitHub repository `FlourtothePeople/flour-to-the-people`. Every push to `main` deploys automatically (`.github/workflows/deploy.yml`).
- **Payments:** Stripe **live** mode. A real $16.00 order succeeded and the webhook returned 200. That order was kept, not refunded.
- **Orders database:** Cloudflare D1 `flour-to-the-people-orders`, created and filled by `scripts/ci-payments.sh` during each deploy.
- **GitHub Actions secrets:** `CLOUDFLARE_API_TOKEN` (Pages Edit + D1 Edit), `CLOUDFLARE_ACCOUNT_ID`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_SECRET_KEY` (live keys). The Stripe webhook signing secret goes straight from Stripe to Cloudflare and is never stored in GitHub.

## Still to do

### 1. Point flourtothepeople.org at the new site

Checked on October 1, 2026: the domain is registered at **Domain.com** (nameservers `ns1.domain.com`, `ns2.domain.com`). It has **no email records** (no MX, no TXT) and one A record, `206.188.192.94`, which serves the old website. Moving it does not affect any email.

1. **Cloudflare:** Add a domain, enter `flourtothepeople.org`, and choose the Free plan. Continue past the scanned records. Note the two `*.ns.cloudflare.com` nameservers.
2. **Domain.com:** Domains, flourtothepeople.org, DNS & Nameservers. Replace the two `domain.com` nameservers with Cloudflare's two and save. Then click Check nameservers in Cloudflare.
3. **Wait** for Cloudflare's "domain is active" email (usually under an hour, up to a day).
4. **Cloudflare:** Workers & Pages, flour-to-the-people, Custom domains, Set up a custom domain. Add `flourtothepeople.org`, then add `www.flourtothepeople.org`.

Payments need no change. The Stripe webhook keeps using the `-5vp.pages.dev` address, which stays valid.

### 2. Old copy of the site

`https://flour-to-the-people.pages.dev` belongs to the previous owner's Cloudflare account (GitHub `Anarchitecht`). It still publicly serves `SETUP.md`, and it uses this Stripe account's live keys, so any order placed there charges this account but records the order in their database. Ask them to delete that Pages project. As an alternative, in Stripe live mode, delete the webhook endpoint at `flour-to-the-people.pages.dev/api/stripe-webhook` (not the `-5vp` one). If the old copy's secret key is a separate key from the new site's, roll that key.

### 3. Sales tax

The checkout charges no sales tax (`docs/KNOWN-ISSUES.md`, issue 1). Ask an accountant whether tax must be collected. Adding it is a code change.

### 4. Order notifications

The site sends no order emails itself. Turn on Stripe's Successful payments email in your Stripe profile's communication preferences.
