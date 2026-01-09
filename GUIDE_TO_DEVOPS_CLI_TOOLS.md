# DevOps CLI Tools for Modern Web Development

> **The problem:** You're building a Next.js app deployed on Vercel, using Supabase for the database, Cloudflare for Workers/R2, Google Cloud for AI APIs, and GitHub for source control. Each service has its own web dashboard, but clicking through UIs wastes time and breaks your flow.
>
> **The solution:** Master the CLI for each platform. Run commands from your terminal, script common operations, and let AI coding agents interact with your infrastructure directly.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           YOUR DEV WORKFLOW                                  │
│                                                                              │
│   Terminal                                                                   │
│   ├── gh pr create          GitHub: PRs, issues, releases                   │
│   ├── vercel --prod         Vercel: deployments, logs                       │
│   ├── wrangler r2 ...       Cloudflare: Workers, R2, KV                     │
│   ├── gcloud ...            Google Cloud: APIs, billing, auth               │
│   └── supabase db push      Supabase: migrations, functions                 │
│                                                                              │
│   No browser tabs. No context switching. Just commands.                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Table of Contents

- [Installation Overview](#installation-overview)
- [GitHub CLI (gh)](#github-cli-gh)
- [Vercel CLI](#vercel-cli)
- [Cloudflare Wrangler](#cloudflare-wrangler)
- [Google Cloud SDK (gcloud)](#google-cloud-sdk-gcloud)
- [Supabase CLI](#supabase-cli)
- [AGENTS.md Blurbs](#agentsmd-blurbs)

---

## Installation Overview

| Tool | Install Command | Auth Command |
|:-----|:----------------|:-------------|
| gh | `brew install gh` | `gh auth login` |
| vercel | `bun add -g vercel` | `vercel login` |
| wrangler | `bun add -g wrangler` | `wrangler login` |
| gcloud | See [gcloud section](#google-cloud-sdk-gcloud) | `gcloud auth login` |
| supabase | `bun add -g supabase` | `supabase login` |

All tools store credentials locally after authentication. You only need to log in once per machine.

---

## GitHub CLI (gh)

### What It Does

`gh` is the official GitHub CLI. It handles pull requests, issues, releases, gists, and repository management without leaving your terminal.

### Installation

```bash
# macOS
brew install gh

# Linux (Debian/Ubuntu)
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install gh
```

### Authentication

```bash
gh auth login
# Select: GitHub.com
# Select: HTTPS
# Select: Login with a web browser
# Follow the browser prompt
```

Verify:

```bash
gh auth status
# Shows: Logged in to github.com as <username>
```

### Common Commands

```bash
# Pull requests
gh pr create --fill              # Create PR from current branch
gh pr list                        # List open PRs
gh pr checkout 123                # Check out PR #123
gh pr merge 123 --squash          # Squash and merge

# Issues
gh issue create --title "Bug" --body "Description"
gh issue list --state open
gh issue close 456

# Releases
gh release create v1.0.0 --generate-notes
gh release list

# Repository
gh repo clone owner/repo
gh repo view --web                # Open in browser
```

### When to Use

- Creating PRs without leaving the terminal
- Automating issue creation in scripts
- Checking CI status: `gh pr checks`
- Viewing PR comments: `gh pr view 123 --comments`

---

## Vercel CLI

### What It Does

The Vercel CLI deploys your frontend apps, manages environment variables, inspects logs, and configures project settings.

### Installation

```bash
bun add -g vercel

# Verify
vercel --version
```

### Authentication

```bash
vercel login
# Opens browser for OAuth
# Select your team if prompted
```

Check that it worked:

```bash
vercel whoami
# Shows: your-email@example.com
```

### Common Commands

```bash
# Deployments
vercel                            # Preview deploy
vercel --prod                     # Production deploy
vercel list                       # List recent deployments
vercel logs                       # Stream production logs

# Environment variables
vercel env pull .env.local        # Download env vars to local file
vercel env add MY_SECRET          # Add new secret (prompts for value)
vercel env ls                     # List all env vars

# Project management
vercel link                       # Link current directory to a Vercel project
vercel project ls                 # List your projects
vercel rollback                   # Roll back to previous deployment

# Inspect
vercel inspect <deployment-url>   # Show deployment details
```

### When to Use

- Manual deployments when auto-deploy is disabled (to save build credits)
- Pulling production env vars for local development
- Quick rollbacks when a deploy breaks production
- Tailing logs for debugging

---

## Cloudflare Wrangler

### What It Does

Wrangler deploys Cloudflare Workers, manages R2 object storage, handles KV namespaces, and configures DNS.

### Installation

```bash
bun add -g wrangler

# Verify
wrangler --version
```

### Authentication

```bash
wrangler login
# Opens browser for OAuth
```

Check status:

```bash
wrangler whoami
# Shows: account name and ID
```

### Common Commands

```bash
# Workers
wrangler dev                      # Run worker locally
wrangler deploy                   # Deploy to Cloudflare
wrangler tail                     # Stream worker logs

# R2 (object storage)
wrangler r2 bucket list           # List buckets
wrangler r2 bucket create my-bucket
wrangler r2 object put my-bucket/path/file.png --file ./local-file.png
wrangler r2 object get my-bucket/path/file.png --file ./downloaded.png

# KV (key-value storage)
wrangler kv:namespace list
wrangler kv:key put --binding=MY_KV "key" "value"
wrangler kv:key get --binding=MY_KV "key"

# Secrets
wrangler secret put MY_API_KEY    # Prompts for value
wrangler secret list
```

### When to Use

- Deploying edge functions that run before your app
- Storing large files in R2 (S3-compatible, no egress fees)
- Caching data in KV for fast global reads
- Setting up custom domains and SSL

---

## Google Cloud SDK (gcloud)

### What It Does

`gcloud` manages Google Cloud projects, billing, APIs, authentication, and services like Cloud Run, Cloud Functions, and Vertex AI.

### Installation

The SDK is a larger package than the others. Install via the official installer:

```bash
# Download and run installer
curl https://sdk.cloud.google.com | bash

# Restart shell or source the path
exec -l $SHELL

# Verify
gcloud version
```

Alternatively, if already installed locally:

```bash
./google-cloud-sdk/bin/gcloud version
```

### Authentication

```bash
# Interactive login (opens browser)
gcloud auth login

# Application Default Credentials (for API libraries)
gcloud auth application-default login
```

### Common Commands

```bash
# Projects
gcloud projects list
gcloud config set project my-project-id

# APIs
gcloud services list --enabled
gcloud services enable aiplatform.googleapis.com

# Billing
gcloud beta billing accounts list
gcloud beta billing projects link my-project-id --billing-account=XXXXXX-XXXXXX-XXXXXX

# IAM
gcloud iam service-accounts list
gcloud iam service-accounts keys create key.json --iam-account=sa@project.iam.gserviceaccount.com

# Cloud Run
gcloud run deploy my-service --source . --region us-central1
gcloud run services list
```

### When to Use

- Enabling APIs for Gemini, Vertex AI, or other Google services
- Managing billing and cost alerts
- Creating service accounts for CI/CD
- Deploying containers to Cloud Run

---

## Supabase CLI

### What It Does

The Supabase CLI manages database migrations, generates TypeScript types, runs local development instances, and deploys Edge Functions.

### Installation

```bash
bun add -g supabase

# Verify
supabase --version
```

### Authentication

```bash
supabase login
# Opens browser for OAuth
```

Link to a project:

```bash
supabase link --project-ref <your-project-ref>
# Project ref is the random string in your Supabase dashboard URL
```

### Common Commands

```bash
# Database
supabase db push                  # Apply local migrations to remote
supabase db pull                  # Pull remote schema to local
supabase db diff --schema public  # Show schema differences
supabase db reset                 # Reset local DB to clean state

# Migrations
supabase migration new add_users_table
supabase migration list

# Types
supabase gen types typescript --local > src/types/database.ts

# Local development
supabase start                    # Start local Supabase (Docker)
supabase stop                     # Stop local instance
supabase status                   # Show local service URLs

# Edge Functions
supabase functions new my-function
supabase functions serve          # Run locally
supabase functions deploy my-function
```

### When to Use

- Generating TypeScript types from your database schema
- Running migrations in CI/CD
- Testing Edge Functions locally before deploy
- Pulling production schema to compare with local changes

---

## AGENTS.md Blurbs

Copy these sections into your project's AGENTS.md file, replacing placeholders with your actual values.

### GitHub CLI

```markdown
### GitHub CLI (gh)

The `gh` CLI is configured and authenticated.

Common tasks:

- Create PR: `gh pr create --fill`
- List open PRs: `gh pr list`
- Check CI status: `gh pr checks`
- Create issue: `gh issue create --title "..." --body "..."`

Repo: `https://github.com/<OWNER>/<REPO>`
```

### Vercel CLI

```markdown
### Vercel CLI

Vercel CLI is installed and authenticated. Auto-deploys are **disabled** to conserve credits.

Deploy commands:

```bash
vercel --prod    # Production deployment
vercel           # Preview deployment
vercel logs      # Stream production logs
```

Project settings:

| Key | Value |
|-----|-------|
| Project ID | `prj_XXXXXXXXXXXXXXXXXXXX` |
| Team ID | `team_XXXXXXXXXXXXXXXXXXXX` |
| Production URL | `https://<PROJECT>.vercel.app` |

To pull env vars for local dev:

```bash
vercel env pull .env.local
```
```

### Cloudflare Wrangler

```markdown
### Cloudflare Wrangler

Wrangler is installed and authenticated.

R2 bucket: `<BUCKET_NAME>`
Account ID: `<ACCOUNT_ID>`

Common commands:

```bash
wrangler r2 object put <BUCKET>/<path> --file ./local-file
wrangler r2 object get <BUCKET>/<path> --file ./downloaded
wrangler r2 bucket list
```

Env keys for R2 (store in Vault or .env):

- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_ENDPOINT`
- `R2_BUCKET`
```

### Google Cloud SDK

```markdown
### Google Cloud CLI (gcloud)

`gcloud` is installed at `./google-cloud-sdk/bin/gcloud` (or in PATH if installed globally).

Auth:

```bash
gcloud auth login
gcloud auth application-default login  # For API libraries
```

Project:

```bash
gcloud config set project <PROJECT_ID>
```

Enable APIs:

```bash
gcloud services enable aiplatform.googleapis.com
gcloud services enable analyticsdata.googleapis.com
```

Useful commands:

```bash
gcloud projects list
gcloud services list --enabled
gcloud beta billing accounts list
```
```

### Supabase CLI

```markdown
### Supabase CLI

Supabase CLI is installed and linked to the project.

Project ref: `<PROJECT_REF>`
Dashboard: `https://supabase.com/dashboard/project/<PROJECT_REF>`

Database operations:

```bash
supabase db push                  # Apply migrations
supabase db pull                  # Pull schema from remote
supabase gen types typescript --local > src/types/database.ts
```

Local development:

```bash
supabase start                    # Start local Supabase (requires Docker)
supabase stop
```

Connection string (pooler, transaction mode):

```
DATABASE_URL="postgresql://postgres.<PROJECT_REF>:<PASSWORD>@aws-0-<REGION>.pooler.supabase.com:6543/postgres"
```

All keys are in Vault at `secret/<PROJECT>` or in `.env.local`.
```

---

## Quick Reference

| Task | Command |
|:-----|:--------|
| Create GitHub PR | `gh pr create --fill` |
| Deploy to Vercel | `vercel --prod` |
| Upload to R2 | `wrangler r2 object put bucket/path --file ./file` |
| Enable GCP API | `gcloud services enable <api>.googleapis.com` |
| Push Supabase migration | `supabase db push` |
| Generate DB types | `supabase gen types typescript --local > types.ts` |

---

## Sources

- [GitHub CLI Manual](https://cli.github.com/manual/)
- [Vercel CLI Reference](https://vercel.com/docs/cli)
- [Wrangler Commands](https://developers.cloudflare.com/workers/wrangler/commands/)
- [gcloud Reference](https://cloud.google.com/sdk/gcloud/reference)
- [Supabase CLI Reference](https://supabase.com/docs/reference/cli/)

---

*Last updated: January 2026*
