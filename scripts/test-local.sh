#!/usr/bin/env bash
# Runs the real functions/ code locally (wrangler pages dev) against a LOCAL D1 database
# with fake Stripe keys, and checks: config, cart validation, webhook signature checks,
# order insert, idempotency, and refund handling. Needs no accounts and no network login.
# It writes a temporary .dev.vars and removes it afterwards; it refuses to overwrite an
# existing one unless you pass --force.
. "$(dirname "$0")/lib.sh"
PORT=8799; BASE="http://127.0.0.1:$PORT"; SECRET="whsec_localtest_$(date +%s)"
[ -f .dev.vars ] && [ "${1:-}" != "--force" ] && die ".dev.vars exists. Re-run with --force to overwrite it (it will be deleted afterwards)."
FAILS=0
pass() { ok "$1"; }
fail() { printf '  FAIL  %s\n' "$1" >&2; FAILS=$((FAILS+1)); }
expect() { [ "$2" = "$3" ] && pass "$1" || fail "$1 (expected '$2', got '$3')"; }

cleanup() { [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null; pkill -x workerd 2>/dev/null || true; rm -f .dev.vars /tmp/fttp-*.json; }
trap cleanup EXIT
rm -rf .wrangler/state
cat > .dev.vars << VARS
STRIPE_SECRET_KEY=sk_test_localfake
STRIPE_PUBLISHABLE_KEY=pk_test_localfake
STRIPE_WEBHOOK_SECRET=$SECRET
STRIPE_TAX_ENABLED=false
VARS

say "Local database"
wr d1 execute "$D1_NAME" --local --file=schema.sql >/dev/null 2>&1 && pass "schema applied to local D1" || die "local schema apply failed"
d1q() { wr d1 execute "$D1_NAME" --local --command "$1" --json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const r=JSON.parse(s)[0].results;process.stdout.write(JSON.stringify(r))})'; }

say "Starting wrangler pages dev on $BASE"
wr pages dev public --port "$PORT" --ip 127.0.0.1 >/tmp/fttp-dev.log 2>&1 &
PID=$!
for _ in $(seq 1 90); do curl -s -o /dev/null "$BASE/api/config" && break; sleep 1; done
curl -s -o /dev/null "$BASE/api/config" || { tail -20 /tmp/fttp-dev.log; die "dev server did not start"; }
pass "dev server up"

say "Static site and config"
expect "GET / returns 200" 200 "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/")"
expect "/api/config publishableKey" pk_test_localfake "$(curl -s "$BASE/api/config" | jget publishableKey)"
expect "/api/config taxEnabled" false "$(curl -s "$BASE/api/config" | jget taxEnabled)"
# Pages answers unknown paths with index.html (status 200), so check the body, not the status.
expect "SETUP.md contents are not served" 0 "$(curl -s "$BASE/SETUP.md" | grep -c 'Payment System Setup')"
expect "schema.sql contents are not served" 0 "$(curl -s "$BASE/schema.sql" | grep -c 'CREATE TABLE')"
expect "function source is not served" 0 "$(curl -s "$BASE/functions/_lib/products.js" | grep -c 'price_cents')"

say "Checkout validation (no Stripe call reaches success with fake keys)"
post() { curl -s -w '\n%{http_code}' -X POST "$BASE/api/checkout" -H 'Content-Type: application/json' --data "$1"; }
ADDR='"address":{"line1":"1 Mill Rd","city":"Floyd","state":"VA","postal_code":"24091"}'
R="$(post '{"cart":[{"id":"nope","qty":1}],"email":"a@b.co","name":"Jane Doe",'"$ADDR"'}')"
expect "unknown product -> 400" 400 "$(echo "$R" | tail -1)"
R="$(post '{"cart":[{"id":"ap","qty":0}],"email":"a@b.co","name":"Jane Doe",'"$ADDR"'}')"
expect "quantity 0 -> 400" 400 "$(echo "$R" | tail -1)"
R="$(post '{"cart":[{"id":"ap","qty":1}],"email":"bad","name":"Jane Doe",'"$ADDR"'}')"
expect "bad email -> 400" 400 "$(echo "$R" | tail -1)"
R="$(post '{"cart":[],"email":"a@b.co","name":"Jane Doe",'"$ADDR"'}')"
expect "empty cart -> 400" 400 "$(echo "$R" | tail -1)"
R="$(post '{"cart":[{"id":"ap","qty":1,"price":0.01}],"email":"a@b.co","name":"Jane Doe",'"$ADDR"'}')"
expect "valid cart passes validation, then fake key fails at Stripe -> 500" 500 "$(echo "$R" | tail -1)"

say "Webhook signature checks"
cat > /tmp/fttp-pi.json << JSON
{"id":"evt_local_1","object":"event","type":"payment_intent.succeeded","data":{"object":{"id":"pi_local_1","object":"payment_intent","amount":1600,"currency":"usd","receipt_email":"jane@example.com","shipping":{"name":"Jane Doe","address":{"line1":"1 Mill Rd","line2":"","city":"Floyd","state":"VA","postal_code":"24091","country":"US"}},"metadata":{"cart_items":"[{\"id\":\"ap\",\"name\":\"All-Purpose Flour\",\"size\":\"3 lb\",\"qty\":1,\"unit_price_cents\":800,\"line_subtotal_cents\":800}]","subtotal_cents":"800","shipping_cents":"800"}}}}
JSON
hook() { curl -s -o /tmp/fttp-hook.out -w '%{http_code}' -X POST "$BASE/api/stripe-webhook" -H "stripe-signature: $1" --data-binary @"$2"; }
expect "missing signature -> 400" 400 "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/stripe-webhook" --data-binary @/tmp/fttp-pi.json)"
expect "wrong secret -> 400" 400 "$(hook "$(node scripts/sign-webhook.mjs whsec_wrong /tmp/fttp-pi.json)" /tmp/fttp-pi.json)"
expect "timestamp 10 minutes old -> 400" 400 "$(hook "$(node scripts/sign-webhook.mjs "$SECRET" /tmp/fttp-pi.json --age=600)" /tmp/fttp-pi.json)"
expect "no order row written by rejected requests" "[]" "$(d1q 'SELECT id FROM orders')"

say "Order insert, idempotency, refund"
SIG="$(node scripts/sign-webhook.mjs "$SECRET" /tmp/fttp-pi.json)"
expect "valid payment_intent.succeeded -> 200" 200 "$(hook "$SIG" /tmp/fttp-pi.json)"
expect "one order row" 1 "$(d1q 'SELECT id FROM orders' | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>process.stdout.write(String(JSON.parse(s).length)))')"
expect "order total_cents" 1600 "$(d1q "SELECT total_cents AS t FROM orders WHERE id='pi_local_1'" | jget 0.t)"
expect "order shipping_cents" 800 "$(d1q "SELECT shipping_cents AS t FROM orders WHERE id='pi_local_1'" | jget 0.t)"
expect "order status pending" pending "$(d1q "SELECT fulfillment_status AS t FROM orders WHERE id='pi_local_1'" | jget 0.t)"
expect "replayed event -> 200" 200 "$(hook "$(node scripts/sign-webhook.mjs "$SECRET" /tmp/fttp-pi.json)" /tmp/fttp-pi.json)"
expect "replay flagged duplicate" true "$(jget duplicate </tmp/fttp-hook.out)"
expect "still one order row after replay" 1 "$(d1q 'SELECT COUNT(*) AS n FROM orders' | jget 0.n)"
cat > /tmp/fttp-refund.json << JSON
{"id":"evt_local_2","object":"event","type":"charge.refunded","data":{"object":{"id":"ch_local_1","object":"charge","payment_intent":"pi_local_1","amount":1600,"amount_refunded":1600}}}
JSON
expect "charge.refunded -> 200" 200 "$(hook "$(node scripts/sign-webhook.mjs "$SECRET" /tmp/fttp-refund.json)" /tmp/fttp-refund.json)"
expect "order marked refunded" refunded "$(d1q "SELECT fulfillment_status AS t FROM orders WHERE id='pi_local_1'" | jget 0.t)"

echo
if [ "$FAILS" = 0 ]; then echo "ALL LOCAL TESTS PASSED"; else echo "$FAILS LOCAL TEST(S) FAILED. Dev server log: /tmp/fttp-dev.log"; exit 1; fi
