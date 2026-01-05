# Misc Coding Agent Tips and Scripts

Practical guides for AI coding agents, terminal customization, and development tooling. Each guide documents a real problem encountered during daily work, the solution that fixed it, and copy-paste configurations to replicate the setup.

## Quick Reference

| Guide | Problem Solved | Time to Set Up |
|:------|:---------------|:---------------|
| [Destructive Git Command Protection](#destructive-git-command-protection) | AI agent ran `git checkout --` and destroyed uncommitted work | 5 min |
| [Host-Aware Terminal Colors](#host-aware-color-themes) | Can't tell which terminal is connected to production | 5-15 min |
| [MX Master Tab Switching](#mx-master-thumbwheel-tab-switching) | Thumbwheel does horizontal scroll instead of something useful | 10 min |
| [Claude Code Native Install Fix](#claude-code-native-install-fix) | `claude --version` shows old version after native install | 5 min |
| [Beads Setup](#beads-setup) | Worktree errors when syncing Beads | 5 min |
| [Moonlight Streaming](#moonlight-streaming-configuration) | Remote desktop to Linux workstation with AV1 encoding | 30 min |

---

## AI Agent Safety

### Destructive Git Command Protection

> **Origin story:** An AI agent ran `git checkout --` on files containing hours of uncommitted work from a parallel coding session. The files were recovered via `git fsck --lost-found`, but this prompted creating a mechanical enforcement system.

A Python hook for Claude Code that intercepts Bash commands and blocks destructive operations before they execute.

**Blocked commands:**

| Command | Why it's dangerous |
|:--------|:-------------------|
| `git checkout -- <files>` | Discards uncommitted changes permanently |
| `git reset --hard` | Destroys all uncommitted work |
| `git clean -f` | Deletes untracked files |
| `git push --force` | Overwrites remote history |
| `rm -rf` (non-temp paths) | Recursive deletion |

**How it works:** Claude Code's `PreToolUse` hook system runs the guard script before each Bash command. The script pattern-matches against known destructive commands and returns a deny decision with an explanation. Safe variants (like `git checkout -b`, `git clean -n`, `rm -rf /tmp/...`) are allowlisted.

<details>
<summary><strong>Quick install</strong></summary>

See the [full guide](DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md) for the automated installer. After running it:

```bash
# Restart Claude Code for hooks to take effect
```

Test that it works:
```bash
echo '{"tool_name": "Bash", "tool_input": {"command": "git checkout -- file.txt"}}' | \
  python3 .claude/hooks/git_safety_guard.py
# Should output: permissionDecision: deny
```

</details>

**[Full guide →](DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md)**

---

## Terminal Customization

### Host-Aware Color Themes

When you have terminals open to multiple servers, color-coding each connection prevents accidentally running commands on the wrong machine.

```
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  PURPLE         │ │  AMBER          │ │  CRIMSON        │
│  dev-server     │ │  staging        │ │  production     │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

**Two approaches:**

| | Ghostty/Shell | WezTerm/Lua |
|:--|:--------------|:------------|
| Setup time | ~5 min | ~15 min |
| Works in | Any terminal with OSC support | WezTerm only |
| Tab bar theming | No | Yes |
| Gradient backgrounds | No | Yes |
| Session persistence | No | Yes (survives disconnects) |

<details>
<summary><strong>Ghostty quick setup</strong></summary>

Add to `~/.zshrc`:

```bash
my-server() {
  printf '\e]11;#1a0d1a\a\e]10;#e8d4f8\a\e]12;#bb9af7\a'  # purple theme
  ssh ubuntu@my-server.example.com "$@"
  printf '\e]111\a\e]110\a\e]112\a\e]104\a'               # reset on exit
}
```

The `printf` commands send OSC escape sequences that change terminal colors. `\e]11;#1a0d1a\a` sets background; `\e]111\a` resets it.

</details>

**[Full guide →](GUIDE_TO_SETTING_UP_HOST_AWARE_COLOR_THEMES_FOR_GHOSTTY_AND_WEZTERM.md)**

---

### MX Master Thumbwheel Tab Switching

The horizontal thumbwheel on Logitech MX Master mice is designed for horizontal scrolling, which most developers rarely use. This guide repurposes it for tab switching across terminals, editors, and browsers.

**Setup:**

1. Install [BetterMouse](https://better-mouse.com) ($10 one-time)
2. Map thumbwheel to `Ctrl+Shift+Arrow`:
   ```
   Thumbwheel <<  →  Ctrl+Shift+Left
   Thumbwheel >>  →  Ctrl+Shift+Right
   ```
3. Add keybindings to each app (WezTerm, Ghostty, VS Code, etc.)

**Companion script:** [`bettermouse_config.py`](bettermouse_config.py) — Export/import BetterMouse settings as JSON for backup or sharing. Run with `uv run bettermouse_config.py show` to view your current config.

<details>
<summary><strong>Why Ctrl+Shift+Arrow?</strong></summary>

| Shortcut | Problem |
|:---------|:--------|
| `Ctrl+Tab` | Can't rebind in Chrome |
| `Cmd+[` / `Cmd+]` | Used for navigation history |
| `Cmd+Shift+[` / `Cmd+Shift+]` | Used for tab switching in some apps, but not universal |
| `Ctrl+Shift+Arrow` | Rarely used as a default; easy to rebind everywhere |

</details>

**[Full guide →](GUIDE_TO_SETTING_UP_YOUR_MX_MASTER_MOUSE_FOR_DEV_WORK_ON_MAC.md)**

---

## Development Tools

### Claude Code Native Install Fix

After installing Claude Code via `curl -fsSL https://claude.ai/install.sh | bash`, you might still see the old version if a previous bun/npm installation is earlier in your PATH.

**Symptoms:**
- `claude --version` shows old version
- "Auto-update failed" errors
- `claude doctor` shows "Currently running: unknown"

**Fix:**

```bash
# Use explicit path in aliases
alias cc='~/.local/bin/claude --dangerously-skip-permissions'

# Update alias uses native updater
alias uca='~/.local/bin/claude update'

# Remove stale symlinks
rm ~/.bun/bin/claude 2>/dev/null
```

**[Full guide →](SETTING_UP_CLAUDE_CODE_NATIVE.md)**

---

### Beads Setup

[Beads](https://github.com/beads-project/beads) uses git worktrees for sync operations. If your `sync.branch` is set to your current branch, you'll get:

```
fatal: 'main' is already checked out at '/path/to/repo'
```

**Fix:** Create a dedicated sync branch:

```bash
git branch beads-sync main
git push -u origin beads-sync
bd config set sync.branch beads-sync
```

**[Full guide →](BEADS_SETUP.md)**

---

## Remote Desktop

### Moonlight Streaming Configuration

Setup for streaming from a Linux workstation (Hyprland/Wayland, dual RTX 4090) to a Mac client using Moonlight with AV1 encoding.

| Component | Configuration |
|:----------|:--------------|
| Server | Sunshine on Hyprland with NVENC |
| Client | Custom Moonlight build with AV1 |
| Resolution | 3072x1728 @ 30fps |
| Codec | AV1 (requires RTX 40-series) |

<details>
<summary><strong>Shell aliases</strong></summary>

```bash
ml      # Start Moonlight streaming
trj     # SSH into remote server
wu      # Wake up remote display
cptl    # Copy clipboard to Linux
cpfm    # Copy clipboard from Mac
```

</details>

**Common issues:** Display sleep disconnects GPU from DRM, causing "GPU doesn't support AV1" errors. Fix: enable NVIDIA persistence mode (`nvidia-smi -pm 1`) and disable hypridle.

**[Full guide →](MOONLIGHT_CONFIG_DOC.md)**

---

## Tech Stack

| Category | Tools |
|:---------|:------|
| AI Agents | Claude Code, Codex, Gemini CLI |
| Terminals | WezTerm, Ghostty, iTerm2 |
| Editors | VS Code, Zed |
| Version Control | Git (with safety hooks) |
| Remote Desktop | Moonlight, Sunshine |
| Package Managers | bun, npm, native installers |
| Hardware | NVIDIA GPUs, Logitech MX Master |
| OS | macOS, Linux (Ubuntu, Arch) |

## Related

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [Beads Project](https://github.com/beads-project/beads)
- [Moonlight](https://moonlight-stream.org/) / [Sunshine](https://github.com/LizardByte/Sunshine)
- [BetterMouse](https://better-mouse.com)
- [WezTerm](https://wezfurlong.org/wezterm/) / [Ghostty](https://ghostty.org)

---

*Last updated: January 2026*
