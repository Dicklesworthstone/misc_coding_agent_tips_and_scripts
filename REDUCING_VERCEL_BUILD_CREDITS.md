# Reducing Vercel Build Credits via API

> **The problem:** Vercel automatically deploys on every git push and PR, burning through your build credits. You hit your Pro plan limits halfway through the month.
>
> **The solution:** Use Vercel's REST API to disable automatic deployments, enable smart build skipping, and deploy manually when you're ready.

```
Before: Every push triggers a build
────────────────────────────────────────────────────────────────
  git push → Vercel webhook → Build → Deploy → 💸 Credits used
  git push → Vercel webhook → Build → Deploy → 💸 Credits used
  git push → Vercel webhook → Build → Deploy → 💸 Credits used
                                              (even for typo fixes)

After: You control when builds happen
────────────────────────────────────────────────────────────────
  git push → (nothing happens)
  git push → (nothing happens)
  vercel --prod → Build → Deploy → 💸 One intentional deploy
```

---

## Table of Contents

- [Finding Your Credentials](#finding-your-credentials)
- [Disable Automatic Deployments](#disable-automatic-deployments)
- [Smart Build Skipping](#smart-build-skipping)
- [Custom Ignore Build Script](#custom-ignore-build-script)
- [Verification](#verification)
- [Manual Deployment Workflow](#manual-deployment-workflow)
- [Restoring Automatic Deployments](#restoring-automatic-deployments)
- [Quick Reference](#quick-reference)

---

## Finding Your Credentials

You'll need three values for the API calls:

| Value | Where to Find |
|:------|:--------------|
| `VERCEL_TOKEN` | Auth token from Vercel CLI |
| `PROJECT_ID` | Project settings or `.vercel/project.json` |
| `TEAM_ID` | Team settings (for team projects) |

### Get Your Auth Token

The Vercel CLI stores your auth token locally:

```bash
cat "$HOME/Library/Application Support/com.vercel.cli/auth.json"
```

Extract the `token` value from the JSON output.

### Get Project and Team IDs

**Option 1: From linked project**
```bash
cat .vercel/project.json
# Shows: {"projectId":"prj_abc123...", "orgId":"team_xyz789..."}
```

**Option 2: Via CLI**
```bash
vercel project ls
vercel project inspect <project-name>
```

### Set Environment Variables

```bash
export VERCEL_TOKEN="<your-token>"
export PROJECT_ID="prj_abc123..."
export TEAM_ID="team_xyz789..."
```

---

## Disable Automatic Deployments

This prevents Vercel from automatically deploying on every git push or PR:

```bash
curl -s -X PATCH "https://api.vercel.com/v9/projects/${PROJECT_ID}?teamId=${TEAM_ID}" \
  -H "Authorization: Bearer ${VERCEL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "gitProviderOptions": {
      "createDeployments": "disabled"
    }
  }'
```

### Options

| Value | Behavior |
|:------|:---------|
| `"enabled"` | Deploy on every push (default) |
| `"disabled"` | Never auto-deploy; manual only |

---

## Smart Build Skipping

For monorepos or projects where not every commit affects the deployed app, enable affected projects detection:

```bash
curl -s -X PATCH "https://api.vercel.com/v9/projects/${PROJECT_ID}?teamId=${TEAM_ID}" \
  -H "Authorization: Bearer ${VERCEL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "enableAffectedProjectsDeployments": true
  }'
```

This tells Vercel to analyze which files changed and skip builds when no relevant files were modified.

---

## Custom Ignore Build Script

For fine-grained control, add a script that decides whether to build based on changed files.

### Step 1: Create the Script

Create `scripts/vercel-ignore-build.sh` in your project:

```bash
#!/bin/bash
# Vercel Ignored Build Step
# https://vercel.com/docs/projects/overview#ignored-build-step
#
# Exit 1 = SKIP build (no relevant changes)
# Exit 0 = PROCEED with build (relevant changes detected)

set -e

echo "Checking for relevant changes..."

PREV_SHA="${VERCEL_GIT_PREVIOUS_SHA:-HEAD~1}"
CURR_SHA="${VERCEL_GIT_COMMIT_SHA:-HEAD}"

# Paths that should trigger a rebuild (customize for your project)
TRIGGER_PATHS=(
    "apps/web/"           # Your app directory
    "packages/ui/"        # Shared UI components
    "package.json"        # Root dependencies
    "pnpm-lock.yaml"      # Lockfile changes
)

for path in "${TRIGGER_PATHS[@]}"; do
    if git diff --name-only "$PREV_SHA" "$CURR_SHA" 2>/dev/null | grep -q "^${path}"; then
        echo "✓ Changes detected in: $path"
        exit 0  # Build
    fi
done

echo "✗ No relevant changes - skipping build"
exit 1  # Skip
```

### Step 2: Configure via API

```bash
curl -s -X PATCH "https://api.vercel.com/v9/projects/${PROJECT_ID}?teamId=${TEAM_ID}" \
  -H "Authorization: Bearer ${VERCEL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "commandForIgnoringBuildStep": "bash scripts/vercel-ignore-build.sh"
  }'
```

### Step 3: Add to vercel.json (Alternative)

You can also specify the ignore command in `vercel.json`:

```json
{
  "ignoreCommand": "bash scripts/vercel-ignore-build.sh"
}
```

---

## All-in-One Configuration

Apply all optimizations in a single API call:

```bash
curl -s -X PATCH "https://api.vercel.com/v9/projects/${PROJECT_ID}?teamId=${TEAM_ID}" \
  -H "Authorization: Bearer ${VERCEL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "gitProviderOptions": {
      "createDeployments": "disabled"
    },
    "enableAffectedProjectsDeployments": true,
    "commandForIgnoringBuildStep": "bash scripts/vercel-ignore-build.sh"
  }'
```

---

## Verification

Check that your settings were applied:

```bash
curl -s -X GET "https://api.vercel.com/v9/projects/${PROJECT_ID}?teamId=${TEAM_ID}" \
  -H "Authorization: Bearer ${VERCEL_TOKEN}" \
  -H "Content-Type: application/json" | jq '{
    name: .name,
    createDeployments: .gitProviderOptions.createDeployments,
    affectedProjects: .enableAffectedProjectsDeployments,
    ignoreCommand: .commandForIgnoringBuildStep
  }'
```

Expected output:

```json
{
  "name": "my-project",
  "createDeployments": "disabled",
  "affectedProjects": true,
  "ignoreCommand": "bash scripts/vercel-ignore-build.sh"
}
```

---

## Manual Deployment Workflow

With automatic deployments disabled, deploy when you're ready:

```bash
# Production deployment
vercel --prod

# Preview deployment (for testing)
vercel

# Deploy specific directory
vercel ./dist --prod
```

### Suggested Workflow

1. Develop locally, push to feature branches freely (no builds)
2. When ready to deploy, run `vercel --prod`
3. Preview deployments only when you explicitly need them

---

## Restoring Automatic Deployments

If you want to re-enable automatic deployments:

```bash
curl -s -X PATCH "https://api.vercel.com/v9/projects/${PROJECT_ID}?teamId=${TEAM_ID}" \
  -H "Authorization: Bearer ${VERCEL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "gitProviderOptions": {
      "createDeployments": "enabled"
    }
  }'
```

---

## Quick Reference

### API Settings

| Setting | API Field | Value | Effect |
|:--------|:----------|:------|:-------|
| Disable auto-deploy | `gitProviderOptions.createDeployments` | `"disabled"` | No deploys on push/PR |
| Smart skip | `enableAffectedProjectsDeployments` | `true` | Skip unchanged projects |
| Custom check | `commandForIgnoringBuildStep` | `"bash ..."` | Run script to decide |

### Common Trigger Paths

Customize `TRIGGER_PATHS` in your ignore script for your project structure:

| Project Type | Typical Trigger Paths |
|:-------------|:----------------------|
| Next.js | `app/`, `pages/`, `components/`, `package.json` |
| Monorepo | `apps/web/`, `packages/ui/`, `pnpm-lock.yaml` |
| Static site | `src/`, `public/`, `content/` |
| API | `api/`, `lib/`, `functions/` |

### Shell Alias

Add to `~/.zshrc` for quick deploys:

```bash
alias vdeploy='vercel --prod'
alias vpreview='vercel'
```

---

## Sources

- [Vercel REST API Documentation](https://vercel.com/docs/rest-api)
- [Ignored Build Step](https://vercel.com/docs/projects/overview#ignored-build-step)
- [Managing Deployments](https://vercel.com/docs/deployments/managing-deployments)
- [GitHub Discussion: Disable Preview Deployments](https://github.com/vercel/vercel/discussions/5878)

---

*Last updated: January 2026*
