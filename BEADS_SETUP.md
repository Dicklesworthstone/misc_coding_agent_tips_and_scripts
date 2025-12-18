# Beads Setup Guide

## Initial Setup for New Projects

When setting up beads in a new repository, always configure a dedicated sync branch to avoid worktree conflicts.

### Quick Setup

```bash
# In your project directory
git branch beads-sync main
git push -u origin beads-sync
bd config set sync.branch beads-sync
```

### Why This Is Needed

Beads uses git worktrees for sync operations. If `sync.branch` is set to your current branch (e.g., `main`), you'll get:

```
Error pulling from sync branch: failed to create worktree: exit status 128
fatal: 'main' is already checked out at '/path/to/repo'
```

Git cannot create a worktree for a branch that's already checked out. A dedicated sync branch solves this.

## Sync Commands

| Command | Purpose |
|---------|---------|
| `bd sync` | Full sync: export to JSONL, commit to sync branch, push to remote |
| `bd sync --from-main` | One-way import: pull beads changes from main branch |
| `bd sync --merge` | Merge sync branch back into main |
| `bd sync --no-pull` | Export and push only (skip pull) |
| `bd sync --flush-only` | Export to JSONL only (no git operations) |
| `bd sync --status` | Show diff between sync branch and main |

## Configuration

Check current config:
```bash
bd config list
```

Key settings:
```bash
bd config set sync.branch beads-sync     # Sync branch name
bd config set issue_prefix myproject     # Issue ID prefix
```

## Troubleshooting

### Worktree Errors

If you see worktree errors:
```bash
bd config get sync.branch
```

If it returns your current branch name, fix it:
```bash
git branch beads-sync main
git push -u origin beads-sync
bd config set sync.branch beads-sync
```

### Sync Branch Doesn't Exist on Remote

```bash
git push -u origin beads-sync
```

### Check Health

```bash
bd doctor
```
