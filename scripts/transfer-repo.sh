#!/usr/bin/env bash
# For the CURRENT OWNER of the GitHub repository: starts a transfer to NEW_OWNER.
#   bash scripts/transfer-repo.sh <new-owner-username-or-org>
# GitHub sends the new owner an email; for a personal account the transfer completes only
# after the new owner accepts it. Requires gh logged in as the current owner.
. "$(dirname "$0")/lib.sh"
need gh "Install the GitHub CLI from https://cli.github.com"
NEW="${1:?usage: transfer-repo.sh <new-owner>}"
require_var GITHUB_OWNER
REPO="$GITHUB_OWNER/$GITHUB_REPO"
say "Transfer $REPO to $NEW"
read -r -p "Type the new owner's name again to confirm: " CONFIRM
[ "$CONFIRM" = "$NEW" ] || die "Names differ; nothing was done."
gh api -X POST "repos/$REPO/transfer" -f new_owner="$NEW" >/dev/null && ok "transfer requested" || die "GitHub rejected the request"
human "$NEW must accept the transfer from the email GitHub sent, or at https://github.com/$REPO"
