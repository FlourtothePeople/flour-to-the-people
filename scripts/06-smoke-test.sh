#!/usr/bin/env bash
# Tests the DEPLOYED site (SITE_URL, default: the project's pages.dev host).
#   (default)  read-only HTTP checks; in test mode also creates one unpaid test PaymentIntent.
#   --e2e      test mode only: pays a test PaymentIntent with Stripe's test card token
#              pm_card_visa, waits for the webhook to write the order into remote D1, checks the
#              row, and deletes that test row again.
# Never run --e2e with live keys; the script refuses.
. "$(dirname "$0")/lib.sh"
E2E=0; [ "${1:-}" = "--e2e" ] && E2E=1
MODE="$(stripe_mode)"
resolve_site_url
FAILS=0
fail() { printf '  FAIL  %s\n' "$1" >&2; FAILS=$((FAILS+1)); }
expect() { [ "$2" = "$3" ] && ok "$1" || fail "$1 (expected '$2', got '$3')"; }
[ "$E2E" = 1 ] && [ "$MODE" != test ] && die "--e2e needs STRIPE_SECRET_KEY in test mode (sk_test_...)."

say "Site $SITE_URL"
expect "GET / returns 200" 200 "$(curl -s -o /dev/null -w '%{http_code}' "$SITE_URL/")"
HOME_BODY="$(curl -s "$SITE_URL/")"
grep -qi "flour to the people" <<<"$HOME_BODY" && ok "home page contains the site name" || fail "home page does not contain the site name"
PK="$(curl -s "$SITE_URL/api/config" | jget publishableKey)"
case "$PK" in pk_*) ok "/api/config returns a publishable key ($(printf '%s' "$PK" | cut -c1-8)...)" ;; *) fail "/api/config has no publishable key (run scripts/03-stripe.sh, then scripts/04-deploy.sh)" ;; esac
[ -n "${STRIPE_PUBLISHABLE_KEY:-}" ] && expect "deployed publishable key equals .env.handoff" "$STRIPE_PUBLISHABLE_KEY" "$PK"
expect "SETUP.md contents are not served" 0 "$(curl -s "$SITE_URL/SETUP.md" | grep -c 'Payment System Setup')"

say "Server-side validation"
ADDR='"address":{"line1":"1 Mill Rd","city":"Floyd","state":"VA","postal_code":"24091"}'
post() { curl -s -o /tmp/fttp-smoke.json -w '%{http_code}' -X POST "$SITE_URL/api/checkout" -H 'Content-Type: application/json' --data "$1"; }
expect "unknown product is rejected (400)" 400 "$(post '{"cart":[{"id":"nope","qty":1}],"email":"a@b.co","name":"Jane Doe",'"$ADDR"'}')"
expect "unsigned webhook is rejected (400; 500 means STRIPE_WEBHOOK_SECRET is missing)" 400 "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$SITE_URL/api/stripe-webhook" --data '{}')"

if [ "$MODE" = test ]; then
  say "Test-mode checkout"
  CODE="$(post '{"cart":[{"id":"ap","qty":1}],"email":"smoke-test@example.com","name":"Smoke Test",'"$ADDR"'}')"
  expect "valid cart creates a PaymentIntent (200)" 200 "$CODE"
  PI="$(jget orderId </tmp/fttp-smoke.json)"; TOTAL="$(jget amount.total_cents </tmp/fttp-smoke.json)"
  expect "total = \$8.00 product + \$8.00 shipping (1600 cents)" 1600 "$TOTAL"
  if [ "$E2E" = 1 ] && [ -n "$PI" ]; then
    say "End-to-end payment with Stripe test card token"
    R="$(stripe_api POST "/v1/payment_intents/$PI/confirm" -d payment_method=pm_card_visa --data-urlencode return_url="https://example.com")"
    expect "PaymentIntent status" succeeded "$(printf '%s' "$R" | jget status)"
    info "waiting up to 60 seconds for the webhook to write the order to D1"
    GOT=""
    for _ in $(seq 1 12); do
      GOT="$(wr d1 execute "$D1_NAME" --remote --command "SELECT total_cents AS t FROM orders WHERE id='$PI'" --json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const r=JSON.parse(s)[0].results;process.stdout.write(r.length?String(r[0].t):"")}catch(e){}})')"
      [ -n "$GOT" ] && break; sleep 5
    done
    expect "order row appeared in D1 with total_cents" 1600 "$GOT"
    wr d1 execute "$D1_NAME" --remote --command "DELETE FROM orders WHERE id='$PI'" --yes >/dev/null 2>&1 && ok "test order $PI removed from D1"
  fi
elif [ "$MODE" = live ]; then
  info "Live key detected: skipping checkout creation. Do one real purchase yourself (see AGENTS.md, section Going live)."
fi

echo
if [ "$FAILS" = 0 ]; then echo "SMOKE TEST PASSED"; else echo "$FAILS CHECK(S) FAILED"; exit 1; fi
