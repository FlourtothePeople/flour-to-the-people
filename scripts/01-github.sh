#!/usr/bin/env bash
# Creates the GitHub repository (empty), points `origin` at it, and stores the two
# secrets the deploy workflow needs. Does not push; scripts/04-deploy.sh pushes.
# Requires: gh logged in (human: `gh auth login`), GITHUB_OWNER, CF_API_TOKEN, CLOUDFLARE_ACCOUNT_ID.
. "$(dirname "$0")/lib.sh"
need gh "Install the GitHub CLI from https://cli.github.com"
require_var GITHUB_OWNER
gh auth status >/dev/null 2>&1 || die "gh is not logged in. HUMAN: run 'gh auth login'."
REPO="$GITHUB_OWNER/$GITHUB_REPO"

say "Repository $REPO"
if gh repo view "$REPO" >/dev/null 2>&1; then
  ok "already exists"
else
  gh repo create "$REPO" "--$GITHUB_VISIBILITY" --description "flourtothepeople.org: worker-owned stone-milled flour" \
    && ok "created ($GITHUB_VISIBILITY)" || die "gh repo create failed"
fi

say "Git remote"
URL="https://github.com/$REPO.git"
if git remote get-url origin >/dev/null 2>&1; then git remote set-url origin "$URL"; else git remote add origin "$URL"; fi
git branch -M main
ok "origin -> $URL"

say "Actions secrets for .github/workflows/deploy.yml"
require_var CF_API_TOKEN
if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  IDS="$(wr whoami 2>/dev/null | grep -oE '[0-9a-f]{32}' | sort -u)"
  if [ "$(printf '%s\n' "$IDS" | grep -c .)" = 1 ]; then set_env_var CLOUDFLARE_ACCOUNT_ID "$IDS"; ok "account id read from wrangler whoami"; else die "Set CLOUDFLARE_ACCOUNT_ID in .env.handoff (candidates: $(echo $IDS))"; fi
fi
printf '%s' "$CF_API_TOKEN" | gh secret set CLOUDFLARE_API_TOKEN -R "$REPO" && ok "CLOUDFLARE_API_TOKEN stored"
printf '%s' "$CLOUDFLARE_ACCOUNT_ID" | gh secret set CLOUDFLARE_ACCOUNT_ID -R "$REPO" && ok "CLOUDFLARE_ACCOUNT_ID stored"
echo; echo "Next: scripts/02-cloudflare.sh"
