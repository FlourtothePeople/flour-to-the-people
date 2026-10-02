# Give this folder to a coding agent and it performs every setup step except eight that need your login or decision

## Do this

1. Install Node.js 20 or newer (https://nodejs.org), git, and the GitHub CLI (https://cli.github.com). The scripts need a Bash shell: macOS Terminal, Linux, Windows Subsystem for Linux, or Git Bash.
2. Unzip this folder and open it in a coding agent that can run shell commands.
3. Tell the agent: "Read AGENTS.md and complete the setup. Stop and tell me exactly what to do whenever a step needs me."
4. Complete each human step the agent names. The exact click paths are in `docs/HUMAN-STEPS.md`.

## The eight human steps

| ID | What you do |
|---|---|
| H1 | Log in to GitHub (`gh auth login`) and set your git name and email. |
| H2 | Only if the repository moves from another owner: accept GitHub's transfer email. |
| H3 | Create a Cloudflare account and run `npx wrangler login`. |
| H4 | Create a Cloudflare API token with Account, Cloudflare Pages, Edit. |
| H5 | Create and verify a Stripe account, then copy its API keys into `.env.handoff`. |
| H6 | Change the domain's nameservers at the registrar. Copy the existing DNS records first. |
| H7 | Decide about sales tax with an accountant. The site does not charge tax yet. |
| H8 | Approve going live, buy one product with your own card, and refund it. |

## Without an agent

Run these in order from this folder. Each command explains any human step it needs.

```
npm run doctor
bash scripts/01-github.sh
bash scripts/02-cloudflare.sh
bash scripts/03-stripe.sh
bash scripts/04-deploy.sh
bash scripts/06-smoke-test.sh
bash scripts/05-domain.sh
```

## What changed from the original repository

- `index.html` and `images/` moved into `public/`. The original deploy published the whole repository root, including `SETUP.md` and `schema.sql`.
- Added `wrangler.toml` (D1 binding), the scripts, the documentation in `docs/`, `AGENTS.md`, `CLAUDE.md`, and two CI checks (prices, font floor).
- The changes are uncommitted in this folder's git history (39 earlier commits are preserved). Run `git status` to see them.

## What still needs your decision

`docs/KNOWN-ISSUES.md` lists nine issues. The two that affect money: sales tax is never charged (issue 1), and `SETUP.md` asks for a $0.50 test purchase that the site cannot accept; the minimum order is about $17 (issue 2).
