#!/usr/bin/env bash
# Commits the configured files and deploys.
#   (default)   git push to origin/main; the GitHub Action deploys; this script watches it.
#   --direct    skips GitHub and deploys public/ + functions/ with wrangler right now.
# Requires: no database_id placeholder in wrangler.toml (run 02 first), price check passing.
. "$(dirname "$0")/lib.sh"
DIRECT=0; [ "${1:-}" = "--direct" ] && DIRECT=1

say "Pre-flight"
grep -q "REPLACE_WITH_DATABASE_ID" wrangler.toml && die "wrangler.toml still has the database_id placeholder. Run scripts/02-cloudflare.sh."
node scripts/check-prices.mjs || die "Fix the price mismatch first."
ok "wrangler.toml and prices are consistent"

if [ "$DIRECT" = 1 ]; then
  say "Direct deploy with wrangler"
  wr pages deploy public --project-name="$CF_PAGES_PROJECT" --branch=main || die "deploy failed"
else
  need gh "Install the GitHub CLI, or use: scripts/04-deploy.sh --direct"
  say "Commit"
  git add -A
  if git diff --cached --quiet; then info "nothing new to commit"; else
    [ -n "$(git config user.email || true)" ] || die "git identity missing. HUMAN: git config --global user.name 'Name' && git config --global user.email 'you@example.com'"
    git commit -q -m "Configure Cloudflare Pages deployment and handoff tooling" && ok "committed"
  fi
  say "Push (this triggers .github/workflows/deploy.yml)"
  git push -u origin main || die "push failed. If the remote already has commits, HUMAN decides whether to force push; the agent must not."
  REPO="$(git remote get-url origin | sed -E 's#.*github.com[:/]##; s#\.git$##')"
  info "waiting for the workflow run to appear"
  RUN=""
  for _ in $(seq 1 20); do
    RUN="$(gh run list -R "$REPO" --workflow deploy.yml --limit 1 --json databaseId,status -q '.[0].databaseId' 2>/dev/null || true)"
    [ -n "$RUN" ] && break; sleep 3
  done
  [ -n "$RUN" ] || die "No workflow run found. Check the Actions tab on GitHub."
  gh run watch "$RUN" -R "$REPO" --exit-status && ok "workflow succeeded" || die "workflow failed: gh run view $RUN -R $REPO --log-failed"
fi

say "Live check"
resolve_site_url
sleep 5
CODE="$(curl -s -o /dev/null -w '%{http_code}' "$SITE_URL/")"; [ "$CODE" = 200 ] && ok "$SITE_URL answers HTTP 200" || warn "$SITE_URL answered HTTP $CODE"
curl -s "$SITE_URL/api/config"; echo
echo; echo "Next: scripts/06-smoke-test.sh (then 05-domain.sh when the test passes)"
