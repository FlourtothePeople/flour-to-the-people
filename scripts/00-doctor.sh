#!/usr/bin/env bash
# Read-only status report. Safe to run at any time, in any state. Prints what is
# done, what is missing, and the next script to run. Never prints secret values.
. "$(dirname "$0")/lib.sh"
set +e

say "Tools"
need node "Install Node.js 20 or newer from https://nodejs.org"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[ "$NODE_MAJOR" -ge 20 ] && ok "node $(node --version)" || warn "node $(node --version) is older than 20; upgrade it"
need git "Install git"; ok "git $(git --version | cut -d' ' -f3)"
need curl "Install curl"; ok "curl present"
if command -v gh >/dev/null 2>&1; then ok "gh $(gh --version | head -1 | cut -d' ' -f3)"; HAVE_GH=1; else warn "gh (GitHub CLI) missing: install from https://cli.github.com (scripts 01 and 04 need it, unless you use 04 --direct)"; HAVE_GH=0; fi

say "Config file (.env.handoff)"
if [ ! -f "$ENV_FILE" ]; then
  cp .env.handoff.example .env.handoff
  human "Created .env.handoff from the template. Fill in GITHUB_OWNER and the other values, then re-run."
else
  for v in GITHUB_OWNER CLOUDFLARE_ACCOUNT_ID CF_API_TOKEN STRIPE_SECRET_KEY STRIPE_PUBLISHABLE_KEY STRIPE_WEBHOOK_SECRET DOMAIN; do
    if [ -n "${!v:-}" ]; then ok "$v is set"; else info "$v is empty"; fi
  done
fi

say "GitHub"
if [ "$HAVE_GH" = 1 ]; then
  if gh auth status >/dev/null 2>&1; then ok "gh is logged in"; else human "Run: gh auth login   (opens a browser; only the account owner can do this)"; fi
  if [ -n "${GITHUB_OWNER:-}" ] && gh repo view "$GITHUB_OWNER/$GITHUB_REPO" >/dev/null 2>&1; then ok "repo $GITHUB_OWNER/$GITHUB_REPO exists"; else info "repo $GITHUB_OWNER/$GITHUB_REPO does not exist yet (scripts/01-github.sh creates it)"; fi
fi
ORIGIN="$(git remote get-url origin 2>/dev/null)"; info "git origin: ${ORIGIN:-none}"

say "Cloudflare"
if wr whoami >/tmp/fttp-whoami.txt 2>&1 && ! grep -qi "not authenticated" /tmp/fttp-whoami.txt; then ok "wrangler is authenticated"; else human "Run: npx wrangler login   (opens a browser; or set CF_WRANGLER_API_TOKEN)"; fi
if grep -q "REPLACE_WITH_DATABASE_ID" wrangler.toml; then info "wrangler.toml still has the database_id placeholder (scripts/02-cloudflare.sh fills it)"; else ok "wrangler.toml has a database_id"; fi
PROJECTS="$(wr pages project list 2>/dev/null)"
if grep -q "$CF_PAGES_PROJECT" <<<"$PROJECTS"; then ok "Pages project $CF_PAGES_PROJECT exists"; else info "Pages project $CF_PAGES_PROJECT not found yet"; fi
if wr d1 info "$D1_NAME" >/dev/null 2>&1; then ok "D1 database $D1_NAME exists"; else info "D1 database $D1_NAME not found yet"; fi

say "Stripe"
if [ -n "${STRIPE_SECRET_KEY:-}" ]; then
  CODE="$(curl -s -o /dev/null -w '%{http_code}' -u "$STRIPE_SECRET_KEY:" https://api.stripe.com/v1/balance)"
  [ "$CODE" = 200 ] && ok "Stripe key accepted (mode: $(stripe_mode))" || warn "Stripe returned HTTP $CODE for the secret key"
else info "STRIPE_SECRET_KEY empty"; fi

say "Site"
resolve_site_url
if [ "$SITE_SOURCE" = guess ] && ! grep -q "$CF_PAGES_PROJECT" <<<"$PROJECTS"; then
  info "Pages project not found on this Cloudflare account; skipping the site check (the guessed host may be someone else's site)"
else
  CODE="$(curl -s -o /dev/null -w '%{http_code}' "$SITE_URL/")"
  if [ "$CODE" = 200 ]; then
    ok "$SITE_URL answers HTTP 200"
    CFG="$(curl -s "$SITE_URL/api/config")"; PK="$(printf '%s' "$CFG" | jget publishableKey)"
    [ -n "$PK" ] && ok "/api/config returns a publishable key" || warn "/api/config returns no publishable key (run 03 then redeploy with 04)"
  else info "$SITE_URL answered HTTP $CODE (not deployed yet)"; fi
fi

say "Local checks"
node scripts/check-prices.mjs 2>/dev/null && ok "page prices match server prices" || warn "price mismatch; run: node scripts/check-prices.mjs"
echo
echo "Next: follow the numbered order in AGENTS.md (01-github, 02-cloudflare, 03-stripe, 04-deploy, 05-domain, 06-smoke-test)."
