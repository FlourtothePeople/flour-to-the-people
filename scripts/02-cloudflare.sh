#!/usr/bin/env bash
# Creates the Pages project and the D1 database, writes the database ID into
# wrangler.toml, applies schema.sql to the remote database, and verifies the tables.
# Idempotent: each step is skipped when its result already exists.
# Requires: wrangler authenticated (human: `npx wrangler login`).
. "$(dirname "$0")/lib.sh"
need node "Install Node.js 20 or newer"

say "Cloudflare authentication"
OUT="$(wr whoami 2>&1 || true)" ; grep -qi "not authenticated" <<<"$OUT" && die "wrangler is not logged in. HUMAN: run 'npx wrangler login' (or set CF_WRANGLER_API_TOKEN)."
ok "authenticated"
if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  IDS="$(echo "$OUT" | grep -oE '[0-9a-f]{32}' | sort -u)"
  if [ "$(printf '%s\n' "$IDS" | grep -c .)" = 1 ]; then set_env_var CLOUDFLARE_ACCOUNT_ID "$IDS"; ok "saved CLOUDFLARE_ACCOUNT_ID"; else warn "several accounts visible; set CLOUDFLARE_ACCOUNT_ID in .env.handoff (candidates: $(echo $IDS))"; fi
fi

say "Pages project $CF_PAGES_PROJECT"
PROJECTS="$(wr pages project list 2>/dev/null || true)"
if grep -q "$CF_PAGES_PROJECT" <<<"$PROJECTS"; then
  ok "already exists"
else
  wr pages project create "$CF_PAGES_PROJECT" --production-branch main && ok "created" || die "pages project create failed"
fi

say "D1 database $D1_NAME"
D1_ID=""
if wr d1 info "$D1_NAME" --json >/tmp/fttp-d1info.json 2>/dev/null; then
  D1_ID="$(jget uuid </tmp/fttp-d1info.json)"; [ -n "$D1_ID" ] || D1_ID="$(jget database_id </tmp/fttp-d1info.json)"; [ -n "$D1_ID" ] || D1_ID="$(jget id </tmp/fttp-d1info.json)"
  [ -n "$D1_ID" ] || D1_ID="$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' /tmp/fttp-d1info.json | head -1)"
  ok "already exists"
else
  CREATE_OUT="$(wr d1 create "$D1_NAME" 2>&1)" || { echo "$CREATE_OUT"; die "d1 create failed"; }
  D1_ID="$(echo "$CREATE_OUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)"
  ok "created"
fi
[ -n "$D1_ID" ] || die "Could not read the database ID. Run 'npx wrangler d1 info $D1_NAME' and put the ID in wrangler.toml by hand."
ok "database_id $D1_ID"

say "wrangler.toml"
node -e '
const fs=require("fs");const [id,name]=process.argv.slice(1);
let t=fs.readFileSync("wrangler.toml","utf8");
t=t.replace(/database_id\s*=\s*"[^"]*"/,`database_id = "${id}"`).replace(/database_name\s*=\s*"[^"]*"/,`database_name = "${name}"`);
fs.writeFileSync("wrangler.toml",t);' "$D1_ID" "$D1_NAME"
ok "D1 binding DB -> $D1_NAME ($D1_ID)"

say "Schema (schema.sql is idempotent: CREATE ... IF NOT EXISTS)"
wr d1 execute "$D1_NAME" --remote --file=schema.sql --yes >/dev/null && ok "applied" || die "schema apply failed"
TABLES="$(wr d1 execute "$D1_NAME" --remote --command "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name" --json 2>/dev/null)"
for t in orders processed_events; do grep -q "\"$t\"" <<<"$TABLES" && ok "table $t present" || die "table $t missing"; done
echo; echo "Next: scripts/03-stripe.sh"
