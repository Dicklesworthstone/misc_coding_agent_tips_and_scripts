# Beads Setup Guide

## Quick Fix

If you're getting worktree errors when running `bd sync`:

```bash
git branch beads-sync main
git push -u origin beads-sync
bd config set sync.branch beads-sync
```

---

## The Problem

Beads uses git worktrees for sync operations. If your `sync.branch` points to your current branch, git cannot create a worktree for it:

```
Error pulling from sync branch: failed to create worktree: exit status 128
fatal: 'main' is already checked out at '/path/to/repo'
```

The fix: create a dedicated sync branch that you never check out directly.

---

## Initial Setup

For new projects, always configure a dedicated sync branch:

```bash
git branch beads-sync main
git push -u origin beads-sync
bd config set sync.branch beads-sync
```

---

## Sync Commands

| Command | What it does |
|:--------|:-------------|
| `bd sync` | Full sync: export to JSONL, commit to sync branch, push to remote |
| `bd sync --from-main` | One-way import: pull beads changes from main branch |
| `bd sync --merge` | Merge sync branch back into main |
| `bd sync --no-pull` | Export and push only (skip pull) |
| `bd sync --flush-only` | Export to JSONL only (no git operations) |
| `bd sync --status` | Show diff between sync branch and main |

---

## Configuration

```bash
bd config list                              # Show all settings
bd config get sync.branch                   # Check current sync branch
bd config set sync.branch beads-sync        # Set sync branch
bd config set issue_prefix myproject        # Set issue ID prefix
```

---

## Troubleshooting

| Problem | Diagnosis | Fix |
|:--------|:----------|:----|
| Worktree errors | `bd config get sync.branch` returns your current branch | Run the Quick Fix commands above |
| Sync branch missing on remote | `git ls-remote --heads origin beads-sync` returns empty | `git push -u origin beads-sync` |
| General health check | Unknown | `bd doctor` |

---

*Last updated: January 2026*
