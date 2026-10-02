#!/usr/bin/env bash
# Runs inside GitHub Actions before each deploy (see .github/workflows/deploy.yml).
# Does nothing unless the GitHub secret STRIPE_SECRET_KEY is set. When it is set:
#   1. Creates the D1 orders database if missing, applies schema.sql, and writes the
#      database ID into wrangler.toml for this deploy only (the commit is unchanged).
#   2. Uploads the Stripe keys to Cloudflare Pages as encrypted secrets.
#   3. Creates the Stripe webhook endpoint for SITE_URL if this Stripe mode (test or
#      live) has none yet, and uploads its signing secret. Stripe keeps test and live
#      endpoints separately, so switching keys creates the live endpoint automatically.
# Keys are never printed; only the first 8 characters appear in the log.
set -euo pipefail
: "${CLOUDFLARE_API_TOKEN:?}" "${CLOUDFLARE_ACCOUNT_ID:?}" "${SITE_URL:?}"
PROJECT=flour-to-the-people
D1_NAME=flour-to-the-people-orders
WR="npx --yes wrangler@4"

if [ -z "${STRIPE_SECRET_KEY:-}" ]; then
  echo "STRIPE_SECRET_KEY is not set; payments stay off. Skipping."
  exit 0
fi
[ -n "${STRIPE_PUBLISHABLE_KEY:-}" ] || { echo "::error::STRIPE_PUBLISHABLE_KEY is missing"; exit 1; }
case "$STRIPE_SECRET_KEY" in sk_test_*) MODE=test;; sk_live_*|rk_live_*) MODE=live;; *) echo "::error::STRIPE_SECRET_KEY does not start with sk_test_ or sk_live_"; exit 1;; esac
case "$STRIPE_PUBLISHABLE_KEY" in pk_${MODE}_*) ;; *) echo "::error::Publishable key mode does not match secret key mode ($MODE)"; exit 1;; esac
echo "Stripe mode: $MODE (secret ${STRIPE_SECRET_KEY:0:8}..., publishable ${STRIPE_PUBLISHABLE_KEY:0:8}...)"

# 1. Orders database
echo "== Orders database"
DB_ID="$($WR d1 list --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const r=JSON.parse(s).find(d=>d.name===process.argv[1]);process.stdout.write(r?(r.uuid||r.database_id||r.id||""):"")})' "$D1_NAME")"
if [ -z "$DB_ID" ]; then
  echo "Creating D1 database $D1_NAME"
  $WR d1 create "$D1_NAME" >/dev/null
  DB_ID="$($WR d1 list --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const r=JSON.parse(s).find(d=>d.name===process.argv[1]);process.stdout.write(r?(r.uuid||r.database_id||r.id||""):"")})' "$D1_NAME")"
fi
[ -n "$DB_ID" ] || { echo "::error::Could not find or create the D1 database. Does the Cloudflare token include Account, D1, Edit?"; exit 1; }
echo "Database ID: $DB_ID"
$WR d1 execute "$D1_NAME" --remote --file=schema.sql --yes >/dev/null
echo "Schema applied"
cat >> wrangler.toml << TOML

[[d1_databases]]
binding = "DB"
database_name = "$D1_NAME"
database_id = "$DB_ID"
TOML

# 2 and 3. Stripe secrets and webhook
echo "== Stripe"
HOOK_URL="$SITE_URL/api/stripe-webhook"
SECRETS="$(mktemp)"; trap 'rm -f "$SECRETS"' EXIT
EXISTING="$(curl -sS -u "$STRIPE_SECRET_KEY:" "https://api.stripe.com/v1/webhook_endpoints?limit=100" \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);if(j.error){console.error(j.error.message);process.exit(1)};const e=j.data.find(x=>x.url===process.argv[1]);process.stdout.write(e?e.id:"")})' "$HOOK_URL")"
NEW_ID=""
if [ -z "$EXISTING" ]; then
  echo "Creating $MODE webhook endpoint for $HOOK_URL"
  RESP="$(curl -sS -u "$STRIPE_SECRET_KEY:" https://api.stripe.com/v1/webhook_endpoints \
    -d url="$HOOK_URL" \
    -d "enabled_events[]=payment_intent.succeeded" \
    -d "enabled_events[]=payment_intent.payment_failed" \
    -d "enabled_events[]=charge.refunded" \
    -d "enabled_events[]=payment_intent.amount_capturable_updated" \
    -d "enabled_events[]=payment_intent.canceled" \
    -d description="Flour to the People orders")"
  NEW_ID="$(echo "$RESP" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);if(j.error){console.error(j.error.message);process.exit(1)};process.stdout.write(j.id)})')"
  WHSEC="$(echo "$RESP" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(JSON.parse(s).secret))')"
  echo "::add-mask::$WHSEC"
  node -e 'require("fs").writeFileSync(process.argv[1],JSON.stringify({STRIPE_SECRET_KEY:process.env.STRIPE_SECRET_KEY,STRIPE_PUBLISHABLE_KEY:process.env.STRIPE_PUBLISHABLE_KEY,STRIPE_TAX_ENABLED:"false",STRIPE_WEBHOOK_SECRET:process.argv[2]}))' "$SECRETS" "$WHSEC"
else
  echo "Webhook endpoint for this mode already exists ($EXISTING); keeping its signing secret"
  # Keep its event list current (card holds need amount_capturable_updated and canceled).
  curl -sS -u "$STRIPE_SECRET_KEY:" "https://api.stripe.com/v1/webhook_endpoints/$EXISTING" \
    -d "enabled_events[]=payment_intent.succeeded" \
    -d "enabled_events[]=payment_intent.payment_failed" \
    -d "enabled_events[]=charge.refunded" \
    -d "enabled_events[]=payment_intent.amount_capturable_updated" \
    -d "enabled_events[]=payment_intent.canceled" \
    | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);if(j.error){console.error("::error::Updating webhook events failed: "+j.error.message);process.exit(1)};console.log("Webhook events: "+j.enabled_events.join(", "))})'
  node -e 'require("fs").writeFileSync(process.argv[1],JSON.stringify({STRIPE_SECRET_KEY:process.env.STRIPE_SECRET_KEY,STRIPE_PUBLISHABLE_KEY:process.env.STRIPE_PUBLISHABLE_KEY,STRIPE_TAX_ENABLED:"false"}))' "$SECRETS"
fi
if ! $WR pages secret bulk "$SECRETS" --project-name="$PROJECT" >/dev/null; then
  # Do not leave an endpoint whose signing secret never reached Cloudflare.
  [ -n "$NEW_ID" ] && curl -sS -u "$STRIPE_SECRET_KEY:" -X DELETE "https://api.stripe.com/v1/webhook_endpoints/$NEW_ID" >/dev/null
  echo "::error::Uploading secrets to Cloudflare Pages failed"; exit 1
fi
echo "Secrets uploaded to Cloudflare Pages ($MODE mode)"
