#!/usr/bin/env bash
# Registers the Stripe webhook endpoint through the Stripe API (the signing secret
# is returned once, at creation), then uploads the four Pages secrets.
# Re-run with the LIVE keys to create the live-mode endpoint (Stripe keeps test and
# live endpoints separate). Flags: --recreate  deletes and recreates an existing endpoint.
# Requires: STRIPE_SECRET_KEY and STRIPE_PUBLISHABLE_KEY in .env.handoff (HUMAN copies them
# from Stripe Dashboard > Developers > API keys).
. "$(dirname "$0")/lib.sh"
RECREATE=0; [ "${1:-}" = "--recreate" ] && RECREATE=1
require_var STRIPE_SECRET_KEY; require_var STRIPE_PUBLISHABLE_KEY
MODE="$(stripe_mode)"; [ "$MODE" != unknown ] || die "STRIPE_SECRET_KEY must start with sk_test_ or sk_live_"
case "$MODE:$STRIPE_PUBLISHABLE_KEY" in test:pk_test_*|live:pk_live_*) ;; *) die "Secret key is $MODE mode but the publishable key is not $MODE mode." ;; esac
[ "$MODE" = live ] && warn "LIVE mode. Confirm scripts/06-smoke-test.sh passed in test mode first."

say "Stripe key check"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -u "$STRIPE_SECRET_KEY:" https://api.stripe.com/v1/balance)"
[ "$CODE" = 200 ] || die "Stripe rejected the secret key (HTTP $CODE)."
ok "key accepted ($MODE mode)"

resolve_site_url strict
WEBHOOK_URL="$SITE_URL/api/stripe-webhook"
say "Webhook endpoint $WEBHOOK_URL"
LIST="$(stripe_api GET "/v1/webhook_endpoints?limit=100")"
EXISTING_ID="$(printf '%s' "$LIST" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const u=process.argv[1];try{const e=JSON.parse(s).data.find(x=>x.url===u);process.stdout.write(e?e.id:"")}catch(_){}})' "$WEBHOOK_URL")"

if [ -n "$EXISTING_ID" ] && [ "$RECREATE" = 1 ]; then
  stripe_api DELETE "/v1/webhook_endpoints/$EXISTING_ID" >/dev/null && ok "deleted old endpoint $EXISTING_ID"; EXISTING_ID=""
fi

if [ -n "$EXISTING_ID" ]; then
  if [ -n "${STRIPE_WEBHOOK_SECRET:-}" ] && [ "${STRIPE_WEBHOOK_SECRET_MODE:-}" = "$MODE" ]; then
    ok "endpoint $EXISTING_ID exists; reusing the stored $MODE-mode signing secret"
  else
    die "Endpoint $EXISTING_ID exists but its signing secret is not stored for $MODE mode (Stripe shows it only at creation). Re-run with --recreate."
  fi
else
  RESP="$(stripe_api POST /v1/webhook_endpoints \
    --data-urlencode "url=$WEBHOOK_URL" \
    --data-urlencode "description=Flour to the People orders ($MODE)" \
    --data-urlencode "enabled_events[]=payment_intent.succeeded" \
    --data-urlencode "enabled_events[]=payment_intent.payment_failed" \
    --data-urlencode "enabled_events[]=charge.refunded")"
  SECRET="$(printf '%s' "$RESP" | jget secret)"
  [ -n "$SECRET" ] || { printf '%s\n' "$RESP" | head -c 600; die "Stripe did not return a signing secret."; }
  set_env_var STRIPE_WEBHOOK_SECRET "$SECRET"; set_env_var STRIPE_WEBHOOK_SECRET_MODE "$MODE"
  ok "created endpoint $(printf '%s' "$RESP" | jget id); signing secret saved to .env.handoff"
fi

say "Cloudflare Pages secrets for project $CF_PAGES_PROJECT"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
node -e '
const o={STRIPE_SECRET_KEY:process.env.STRIPE_SECRET_KEY,STRIPE_PUBLISHABLE_KEY:process.env.STRIPE_PUBLISHABLE_KEY,STRIPE_WEBHOOK_SECRET:process.env.STRIPE_WEBHOOK_SECRET,STRIPE_TAX_ENABLED:process.env.STRIPE_TAX_ENABLED||"false"};
require("fs").writeFileSync(process.argv[1],JSON.stringify(o));' "$TMP"
wr pages secret bulk "$TMP" --project-name "$CF_PAGES_PROJECT" >/dev/null && ok "4 secrets uploaded" || die "secret upload failed (is the Pages project created? run 02 first)"
echo; echo "Secrets apply to the next deployment. Next: scripts/04-deploy.sh"
