#!/usr/bin/env bash
# Attaches DOMAIN to the Pages project through the Cloudflare API and polls its status.
# HUMAN PREREQUISITE for an apex domain such as flourtothepeople.org: the domain must be a
# zone on the same Cloudflare account, with the registrar's nameservers changed to
# Cloudflare's. Changing nameservers moves ALL DNS for the domain; before doing it, copy every
# existing record (MX, TXT, etc.) so email and verification records keep working.
# Requires: CF_API_TOKEN (Pages Edit), CLOUDFLARE_ACCOUNT_ID, DOMAIN.
. "$(dirname "$0")/lib.sh"
require_var CF_API_TOKEN; require_var CLOUDFLARE_ACCOUNT_ID; require_var DOMAIN

say "Attach $DOMAIN to $CF_PAGES_PROJECT"
RESP="$(cf_api POST "/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$CF_PAGES_PROJECT/domains" --data "{\"name\":\"$DOMAIN\"}")"
if [ "$(printf '%s' "$RESP" | jget success)" = true ]; then ok "domain added; status: $(printf '%s' "$RESP" | jget result.status)"
else printf '%s\n' "$RESP" | head -c 700; warn "API did not report success (already attached is fine)"; fi

say "Waiting for activation (up to 10 minutes)"
for _ in $(seq 1 20); do
  S="$(cf_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$CF_PAGES_PROJECT/domains/$DOMAIN" | jget result.status)"
  info "status: ${S:-unknown}"
  [ "$S" = active ] && { ok "$DOMAIN is active"; exit 0; }
  sleep 30
done
human "Still not active. Open Cloudflare > Workers & Pages > $CF_PAGES_PROJECT > Custom domains, and finish the nameserver change at the registrar. DNS changes can take hours."
