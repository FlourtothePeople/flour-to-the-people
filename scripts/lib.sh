#!/usr/bin/env bash
# Shared helpers for scripts/*.sh. Sourced, never run directly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
ENV_FILE="$ROOT/.env.handoff"
# Real environment variables take precedence over .env.handoff (an empty line in the
# file never erases a value that was exported before the script started).
_KNOWN="GITHUB_OWNER GITHUB_REPO GITHUB_VISIBILITY CF_PAGES_PROJECT D1_NAME CLOUDFLARE_ACCOUNT_ID CF_API_TOKEN CF_WRANGLER_API_TOKEN STRIPE_SECRET_KEY STRIPE_PUBLISHABLE_KEY STRIPE_WEBHOOK_SECRET STRIPE_WEBHOOK_SECRET_MODE STRIPE_TAX_ENABLED DOMAIN SITE_URL"
for _v in $_KNOWN; do eval "_pre_$_v=\"\${$_v-}\""; done
if [ -f "$ENV_FILE" ]; then set -a; . "$ENV_FILE"; set +a; fi
for _v in $_KNOWN; do eval "_p=\"\$_pre_$_v\""; if [ -n "$_p" ]; then export "$_v=$_p"; fi; done

: "${CF_PAGES_PROJECT:=flour-to-the-people}"
: "${D1_NAME:=flour-to-the-people-orders}"
: "${GITHUB_REPO:=flour-to-the-people}"
: "${GITHUB_VISIBILITY:=public}"
: "${STRIPE_TAX_ENABLED:=false}"
export WRANGLER_SEND_METRICS=false

say()  { printf '\n== %s\n' "$*"; }
ok()   { printf '  ok    %s\n' "$*"; }
info() { printf '  ..    %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*" >&2; }
die()  { printf '  FAIL  %s\n' "$*" >&2; exit 1; }
human(){ printf '  HUMAN %s\n' "$*"; }

need() { command -v "$1" >/dev/null 2>&1 || die "$1 is not installed. $2"; }

# Runs wrangler 4. Uses CF_WRANGLER_API_TOKEN when set; otherwise uses the
# browser login from `npx wrangler login`. CF_API_TOKEN (Pages Edit only) is
# deliberately not passed to wrangler because it lacks D1 permission.
wr() {
  if [ -n "${CF_WRANGLER_API_TOKEN:-}" ]; then
    CLOUDFLARE_API_TOKEN="$CF_WRANGLER_API_TOKEN" npx --yes wrangler@4 "$@"
  else
    env -u CLOUDFLARE_API_TOKEN npx --yes wrangler@4 "$@"
  fi
}

# jget PATH < json : prints the value at a dotted path, or nothing when missing.
jget() {
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{let v=JSON.parse(s);for(const k of process.argv[1].split(".")){if(v==null)break;v=v[k]}process.stdout.write(v==null?"":typeof v==="object"?JSON.stringify(v):String(v))}catch(e){}})' "$1"
}

require_var() {
  local name="$1" val
  val="${!name:-}"
  [ -n "$val" ] || die "$name is empty. Set it in .env.handoff."
}

# set_env_var KEY VALUE : writes KEY=VALUE into .env.handoff and exports it.
set_env_var() {
  node -e '
const fs=require("fs");const [f,k,v]=process.argv.slice(1);
let lines=fs.existsSync(f)?fs.readFileSync(f,"utf8").split("\n"):[];
let done=false;
lines=lines.map(l=>{if(l.startsWith(k+"=")){done=true;return k+"="+v;}return l;});
if(!done){if(lines.length&&lines[lines.length-1]==="")lines.pop();lines.push(k+"="+v);lines.push("");}
fs.writeFileSync(f,lines.join("\n"));' "$ENV_FILE" "$1" "$2"
  export "$1=$2"
}

# Cloudflare REST call: cf_api METHOD PATH [curl args...]; needs CF_API_TOKEN.
cf_api() {
  local method="$1" path="$2"; shift 2
  curl -sS -X "$method" "https://api.cloudflare.com/client/v4$path" \
    -H "Authorization: Bearer ${CF_API_TOKEN:?CF_API_TOKEN is empty}" \
    -H "Content-Type: application/json" "$@"
}

# Stripe REST call: stripe_api METHOD PATH [curl args...]; needs STRIPE_SECRET_KEY.
stripe_api() {
  local method="$1" path="$2"; shift 2
  curl -sS -X "$method" "https://api.stripe.com$path" -u "${STRIPE_SECRET_KEY:?STRIPE_SECRET_KEY is empty}:" "$@"
}

stripe_mode() {
  case "${STRIPE_SECRET_KEY:-}" in
    sk_test_*) echo test ;;
    sk_live_*) echo live ;;
    *) echo unknown ;;
  esac
}

# Resolves the public *.pages.dev host for the Pages project into SITE_URL and sets
# SITE_SOURCE to env | api | guess. `resolve_site_url strict` refuses to guess.
# Pages project names are unique across Cloudflare, so a guessed host can belong to a
# different owner; anything that registers URLs (scripts/03-stripe.sh) must use strict.
resolve_site_url() {
  if [ -n "${SITE_URL:-}" ]; then SITE_SOURCE=env; return; fi
  local sub=""
  if [ -n "${CF_API_TOKEN:-}" ] && [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
    sub="$(cf_api GET "/accounts/$CLOUDFLARE_ACCOUNT_ID/pages/projects/$CF_PAGES_PROJECT" 2>/dev/null | jget result.subdomain || true)"
  fi
  if [ -n "$sub" ]; then
    SITE_SOURCE=api
  elif [ "${1:-}" = strict ]; then
    die "Cannot read this project's pages.dev host from the Cloudflare API. Needs CF_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, and an existing Pages project (run scripts/02-cloudflare.sh). Or set SITE_URL=https://<host> in .env.handoff."
  else
    sub="$CF_PAGES_PROJECT.pages.dev"; SITE_SOURCE=guess
    info "Guessing host $sub (the Cloudflare API did not report one); it may belong to someone else"
  fi
  SITE_URL="https://$sub"
  export SITE_URL SITE_SOURCE
}
