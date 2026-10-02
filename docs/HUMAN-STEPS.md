# Eight steps need a person's login, identity, or money decision

Each step below names what the person does and what the agent does afterwards. The IDs match `AGENTS.md`.

## H1. GitHub login and git identity

1. Install the GitHub CLI from https://cli.github.com.
2. Run `gh auth login` and follow the browser prompt. Check with `gh auth status`.
3. Set the name and email that git attaches to commits:
   `git config --global user.name "Full Name"` and `git config --global user.email "you@example.com"`.

## H2. Repository transfer (only when the repository changes owner)

1. The current owner runs `bash scripts/transfer-repo.sh <new-owner>` (needs `gh` logged in as the current owner and `GITHUB_OWNER` set to the current owner in `.env.handoff`). GitHub emails the new owner.
2. The new owner opens the email and accepts the transfer.
3. A fresh copy instead of a transfer needs no H2: the new owner runs `scripts/01-github.sh`, which creates a new empty repository, and `scripts/04-deploy.sh` pushes the full history from this folder.

## H3. Cloudflare account and login

1. Sign up at https://dash.cloudflare.com/sign-up and verify the email address.
2. Run `npx wrangler login` and approve access in the browser. Check with `npx wrangler whoami`.
3. A machine with no browser can use an API token instead: create a token with Account, Cloudflare Pages, Edit and Account, D1, Edit (confirm the exact permission names on the token screen), and put it in `.env.handoff` as `CF_WRANGLER_API_TOKEN`.

## H4. Cloudflare API token for GitHub Actions and the domain call

1. In the Cloudflare dashboard open the profile menu, then My Profile, then API Tokens, then Create Token, then Create Custom Token (Get started).
2. Name it, for example `flour-pages-deploy`. Under Permissions choose Account, Cloudflare Pages, Edit.
3. Under Account Resources choose the specific account. Continue to summary, then Create Token.
4. Copy the token immediately; Cloudflare shows it once. Put it in `.env.handoff` as `CF_API_TOKEN`.

## H5. Stripe account, verification, and keys

1. Register at https://dashboard.stripe.com/register.
2. Activate the account: legal entity name, tax ID or SSN for a sole proprietor, and the bank account for payouts. Stripe's verification can take hours to a day. Test mode works while verification is pending.
3. Open Developers, then API keys. Copy the test publishable key (`pk_test_...`) and test secret key (`sk_test_...`) into `.env.handoff` as `STRIPE_PUBLISHABLE_KEY` and `STRIPE_SECRET_KEY`.
4. After the test-mode checks pass and Stripe has activated the account, toggle Live mode in the Dashboard sidebar, copy the live keys, and replace the two values in `.env.handoff`.

## H6. Domain nameservers (moves all DNS for the domain)

Cloudflare requires an apex domain such as `flourtothepeople.org` to be a zone on the same Cloudflare account as the Pages project, with the registrar's nameservers changed to Cloudflare's. After the nameservers point to Cloudflare, Cloudflare creates the CNAME record for the Pages project.

1. In the Cloudflare dashboard choose Add a domain and enter `flourtothepeople.org`. Cloudflare scans and lists the existing DNS records.
2. Before changing anything, write down or export every existing record, especially MX records (email delivery) and TXT records (email authentication and service verification). Add any missing ones in Cloudflare's DNS page.
3. Cloudflare shows two nameserver names. At the registrar, replace the current nameservers with those two.
4. Wait until Cloudflare reports the zone active. This can take hours.
5. The domain has served the earlier website built on the edit.site platform. After the nameserver change and `scripts/05-domain.sh`, visitors see the new site. The earlier site's content is already in `public/index.html`.

## H7. Tax decisions

The code does not compute sales tax (`docs/KNOWN-ISSUES.md`, issue 1). A person decides with an accountant whether the mill must collect sales tax on shipped flour in any state, and whether to activate Stripe Tax (Dashboard, Tax, Get started). Implementing tax collection is a code change, not a configuration change.

## H8. Go-live approval and the real test purchase

1. The person approves going live after reading the eight steps in `AGENTS.md`, "Going live".
2. The person buys the cheapest product (minimum total $17.00) with their own card on the live site.
3. The person checks the Stripe Dashboard payment list, then refunds that payment in the Stripe Dashboard.
