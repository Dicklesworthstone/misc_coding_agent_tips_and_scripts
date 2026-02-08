# Misc Coding Agent Tips and Scripts

Practical guides for AI coding agents, terminal customization, and development tooling. Each guide documents a real problem encountered during daily work, the solution that fixed it, and copy-paste configurations to replicate the setup.

## Quick Reference

| Guide | Problem Solved | Time to Set Up |
|:------|:---------------|:---------------|
| [Destructive Git Command Protection](#destructive-git-command-protection) | AI agent ran `git checkout --` and destroyed uncommitted work | 5 min |
| [Post-Compact AGENTS.md Reminder](#post-compact-agentsmd-reminder) | Claude forgets project conventions after context compaction | 2 min |
| [Host-Aware Terminal Colors](#host-aware-color-themes) | Can't tell which terminal is connected to production | 5-15 min |
| [WezTerm Persistent Sessions](#wezterm-persistent-remote-sessions) | Remote terminal sessions die when Mac sleeps or reboots | 20 min |
| [WezTerm Mux Tuning for Agent Swarms](#wezterm-mux-tuning-for-agent-swarms) | Mux server becomes unresponsive with 20+ agents | 5 min |
| [Ghostty Terminfo for Remote Machines](#ghostty-terminfo-for-remote-machines) | Numpad Enter shows `[57414u` garbage when SSH'd | 2 min |
| [macOS NFS Auto-Mount](#macos-nfs-auto-mount) | Have to manually mount remote dev server after every reboot | 10 min |
| [Budget 10GbE Direct Link](#budget-10gbe-direct-link) | File transfers crawl at 100MB/s through gigabit switch | 30 min |
| [MX Master Tab Switching](#mx-master-thumbwheel-tab-switching) | Thumbwheel does horizontal scroll instead of something useful | 10 min |
| [Doodlestein Punk Theme](#doodlestein-punk-theme-for-ghostty) | Need a cyberpunk color scheme for Ghostty | 1 min |
| [Reducing Vercel Build Credits](#reducing-vercel-build-credits) | Automatic deployments burn through Pro plan credits | 10 min |
| [Claude Code Native Install Fix](#claude-code-native-install-fix) | `claude --version` shows old version after native install | 5 min |
| [Claude Code MCP Config Fix](#claude-code-mcp-config-fix) | MCP servers wiped out, need quick restore | 2 min |
| [Mirror Claude Code Skills](#mirror-claude-code-skills) | Copy project skills to global ~/.claude/skills | 2 min |
| [Beads Setup](#beads-setup) | Worktree errors when syncing Beads | 5 min |
| [Moonlight Streaming](#moonlight-streaming-configuration) | Remote desktop to Linux workstation with AV1 encoding | 30 min |
| [Vault HA Cluster](#hashicorp-vault-ha-cluster) | Single Vault instance is a single point of failure | 45 min |
| [DevOps CLI Tools](#devops-cli-tools) | Clicking through web dashboards wastes time | 15 min |
| [Gemini CLI Crash + Retry Fix](#gemini-cli-crash--retry-fix) | Gemini CLI crashes with EBADF and gives up after 3 retries | 10 sec |

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

### Post-Compact AGENTS.md Reminder

> **Problem:** During long coding sessions, Claude Code compacts the conversation to stay within context limits. After compaction, Claude "forgets" project-specific conventions documented in AGENTS.md.

A bash hook that detects context compaction and injects a reminder for Claude to re-read AGENTS.md.

**How it works:** Claude Code's `SessionStart` hook fires with `source: "compact"` after compaction. The hook checks this field and outputs a reminder message that Claude sees immediately.

<details>
<summary><strong>Quick install</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-post-compact-reminder.sh | bash
# Restart Claude Code after installation
```

Or manually create `~/.local/bin/claude-post-compact-reminder`:

```bash
#!/usr/bin/env bash
set -e
INPUT=$(cat)
SOURCE=$(echo "$INPUT" | jq -r '.source // empty')
if [[ "$SOURCE" == "compact" ]]; then
    cat <<'EOF'
<post-compact-reminder>
Context was just compacted. Please reread AGENTS.md to refresh your understanding of project conventions and agent coordination patterns.
</post-compact-reminder>
EOF
fi
exit 0
```

Then add to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          { "type": "command", "command": "$HOME/.local/bin/claude-post-compact-reminder" }
        ]
      }
    ]
  }
}
```

</details>

**[Full guide →](CLAUDE_CODE_POST_COMPACT_AGENTS_MD_REMINDER.md)**

---

## Terminal Customization

### Ghostty Terminfo for Remote Machines

When using Ghostty to SSH into remote servers, you might see garbage like `[57414u` when pressing numpad Enter. This happens because the remote system doesn't understand the Kitty keyboard protocol that Ghostty uses.

**One-liner fix:**

```bash
infocmp -x xterm-ghostty | ssh user@your-server 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo -'
```

<details>
<summary><strong>Helper function for multiple servers</strong></summary>

Add to `~/.zshrc`:

```bash
ghostty_push_terminfo() {
  local host="$1"
  [[ -z "$host" ]] && { echo "Usage: ghostty_push_terminfo <host>" >&2; return 1; }
  infocmp -x xterm-ghostty | ssh "$host" 'mkdir -p ~/.terminfo && tic -x -o ~/.terminfo -'
}
```

Then: `ghostty_push_terminfo ubuntu@dev-server`

</details>

**[Full guide →](GHOSTTY_TERMINFO_FOR_REMOTE_MACHINES.md)**

---

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

### WezTerm Persistent Remote Sessions

Remote terminal sessions that survive Mac sleep, reboot, or power loss. Uses WezTerm's native multiplexing with `wezterm-mux-server` running on remote servers via systemd.

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ 󰍹  Local    │  │ 󰒋  Dev      │  │ 󰒋  Staging  │  │ 󰻠  Workstation│
│  [3 tabs]    │  │  [3 tabs]    │  │  [3 tabs]    │  │  [3 tabs]     │
│  (fresh)     │  │ (persistent) │  │ (persistent) │  │ (persistent)  │
└──────────────┘  └──────────────┘  └──────────────┘  └───────────────┘
```

**Key features:**

| Feature | How It Works |
|:--------|:-------------|
| Persistent sessions | `wezterm-mux-server` on remote holds state; Mac just reconnects |
| Smart startup | Doesn't accumulate tabs on restart (checks if remote has existing tabs) |
| Domain-specific colors | Each server gets distinct gradient + tab bar theme |
| Better than tmux | Native scrollback, single keybinding namespace, GPU rendering |

<details>
<summary><strong>Remote setup (per server)</strong></summary>

```bash
# Create systemd user service
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/wezterm-mux-server.service << 'EOF'
[Unit]
Description=WezTerm Mux Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/wezterm-mux-server --daemonize=false
Restart=on-failure

[Install]
WantedBy=default.target
EOF

# Enable and start
systemctl --user daemon-reload
systemctl --user enable --now wezterm-mux-server
sudo loginctl enable-linger $USER
```

</details>

**[Full guide →](WEZTERM_PERSISTENT_REMOTE_SESSIONS.md)**

---

### WezTerm Mux Tuning for Agent Swarms

When running 20+ AI coding agents (Claude, Codex) simultaneously, the default wezterm-mux-server configuration can't keep up. Output buffers overflow, caches thrash, and connections time out, killing all your agent sessions.

This guide provides RAM-tiered performance profiles that trade memory for throughput:

| Setting | Default | 512GB Profile | Why It Helps |
|:--------|:--------|:--------------|:-------------|
| `scrollback_lines` | 3,500 | 10,000,000 | Agents produce massive output; don't truncate |
| `mux_output_parser_buffer_size` | 128KB | 16MB | Batch-process output bursts instead of choking |
| `mux_output_parser_coalesce_delay_ms` | 3ms | 1ms | Reduce accumulated lag on high-throughput output |
| `shape_cache_size` | 1,024 | 65,536 | Cache font shaping to avoid CPU spikes |

**Smart sizing:** Uses linear interpolation based on actual RAM, not fixed tiers. A 200GB system gets proportionally scaled settings.

**Bonus:** Emergency rescue procedure to migrate agent sessions to tmux using `reptyr` when the mux server becomes unresponsive (saves ~50-70% of sessions).

<details>
<summary><strong>Quick install</strong></summary>

```bash
./wezterm-mux-tune.sh              # Auto-detect RAM, interpolate
./wezterm-mux-tune.sh --dry-run    # Preview settings
./wezterm-mux-tune.sh --ram 200    # Specific RAM amount
./wezterm-mux-tune.sh --profile 256  # Fixed profile
./wezterm-mux-tune.sh --restore    # Restore backup
```

Then restart the mux server:
```bash
pkill -9 -f wezterm-mux
wezterm-mux-server --daemonize
```

</details>

**[Full guide →](WEZTERM_MUX_PERFORMANCE_TUNING_FOR_AGENT_SWARMS.md)** | **[Install script →](wezterm-mux-tune.sh)**

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

**Companion script:** [`bettermouse_config.py`](bettermouse_config.py) exports and imports BetterMouse settings as JSON for backup or sharing. Run with `uv run bettermouse_config.py show` to view your current config.

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

### Doodlestein Punk Theme for Ghostty

A vibrant cyberpunk-inspired color scheme for Ghostty featuring deep space black backgrounds with electric neon accents.

```
┌─────────────────────────────────────────────────────┐
│  Background: #0a0e14 (deep space black)             │
│  Foreground: #b3f4ff (electric cyan)                │
│  Cursor:     #ff00ff (hot magenta)                  │
│                                                     │
│  Palette highlights:                                │
│    Red:    #ff3366 → #ff6b9d (electric pink)        │
│    Green:  #39ffb4 → #6bffcd (neon teal)            │
│    Blue:   #00aaff → #66ccff (cyber blue)           │
│    Magenta:#ff00ff → #ff66ff (hot purple)           │
└─────────────────────────────────────────────────────┘
```

**Quick install:**

```bash
# Copy theme to Ghostty themes directory
mkdir -p ~/.config/ghostty/themes
cp doodlestein-punk-theme-for-ghostty ~/.config/ghostty/themes/
```

**Usage:** Add to your Ghostty config (`~/.config/ghostty/config`):

```
theme = doodlestein-punk-theme-for-ghostty
```

<details>
<summary><strong>Full palette</strong></summary>

| Index | Normal | Bright | Color Name |
|:------|:-------|:-------|:-----------|
| 0/8   | `#1a1f29` | `#3d4f5f` | Black/Gray |
| 1/9   | `#ff3366` | `#ff6b9d` | Red/Pink |
| 2/10  | `#39ffb4` | `#6bffcd` | Green/Teal |
| 3/11  | `#ffe566` | `#ffef99` | Yellow |
| 4/12  | `#00aaff` | `#66ccff` | Blue/Cyan |
| 5/13  | `#ff00ff` | `#ff66ff` | Magenta |
| 6/14  | `#00ffff` | `#66ffff` | Cyan |
| 7/15  | `#c7d5e0` | `#ffffff` | White |

</details>

**[Theme file →](doodlestein-punk-theme-for-ghostty)**

---

## Remote Development

### macOS NFS Auto-Mount

If you have a remote Linux workstation with projects at `/data/projects`, you can make it automatically mount on your Mac at boot with graceful retry logic.

**What you get:**

```
~/dev-projects → /Volumes/dev-server/projects → 10.0.0.50:/data/projects
```

**Components:**

| Component | Purpose |
|:----------|:--------|
| Mount script | Retries with exponential backoff when server is offline |
| LaunchDaemon | Runs at boot, re-mounts on network changes |
| Symlink | Convenient `~/dev-projects` path |
| Synthetic firmlink | Optional `/dev/projects` root-level path |

<details>
<summary><strong>Quick setup</strong></summary>

```bash
# Create mount script
sudo tee /usr/local/bin/mount-dev-nfs << 'EOF'
#!/bin/bash
REMOTE_HOST="10.0.0.50"
MOUNT_POINT="/Volumes/dev-server"
[ -d "$MOUNT_POINT" ] || mkdir -p "$MOUNT_POINT"
mount | grep -q "$MOUNT_POINT" && exit 0
ping -c 1 -W 1 "$REMOTE_HOST" &>/dev/null || exit 1
/sbin/mount_nfs -o resvport,rw,soft,intr,bg "$REMOTE_HOST:/data" "$MOUNT_POINT"
EOF
sudo chmod +x /usr/local/bin/mount-dev-nfs

# Create LaunchDaemon (see full guide for complete plist)
# Then: sudo launchctl load /Library/LaunchDaemons/com.local.mount-dev-nfs.plist

# Create symlink
ln -sf /Volumes/dev-server/projects ~/dev-projects
```

</details>

**[Full guide →](MACOS_NFS_AUTOMOUNT_FOR_REMOTE_DEV.md)**

---

### Budget 10GbE Direct Link

Connect your Mac directly to a Linux workstation with 10GbE for ~$90 total, achieving 800+ MB/s transfers.

```
Mac Mini M4                    Linux Workstation
┌─────────────┐                ┌─────────────────┐
│ Thunderbolt │◄──Cat6 $5────►│ Built-in 10GbE  │
│ 10GbE ~$85  │                │ (Aquantia)      │
└─────────────┘                └─────────────────┘
     Static IPs: 10.10.10.x | Speed: ~850 MB/s
```

**What you need:**

| Component | Cost |
|:----------|:-----|
| IOCREST Thunderbolt 10GbE adapter | ~$85 (AliExpress) |
| Cat6 cable | ~$5 |

Many high-end workstations (Threadripper PRO, EPYC) have **unused 10GbE ports**. The IOCREST adapter uses the same Aquantia chip as Mac Studio's built-in 10GbE.

**Also includes:**
- SHA-256 verified file transfers with speed reporting
- Clipboard sync between Mac and Linux (Wayland/X11)
- Remote display wake-up commands
- AI coding agent aliases (Claude, Gemini, Codex)

**[Full guide →](BUDGET_10GBE_DIRECT_LINK_AND_REMOTE_PRODUCTIVITY.md)**

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

### Claude Code MCP Config Fix

Claude Code stores MCP server configurations in `~/.claude.json`. These can get wiped out by fresh installs, updates, or config corruption. Instead of running the full MCP Agent Mail installer, use this lightweight script that only restores the MCP config.

**One command fix:**

```bash
fix_cc_mcp
```

**What it restores:**

| Server | Type | Purpose |
|:-------|:-----|:--------|
| `mcp-agent-mail` | HTTP | Multi-agent coordination, messaging, file reservations |
| `morph-mcp` | stdio | AI-powered code search via `warp_grep` |

<details>
<summary><strong>Quick install</strong></summary>

```bash
# Download and install the script
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/FIX_CLAUDE_CODE_MCP_CONFIG.md | \
  sed -n '/^SCRIPT$/,/^SCRIPT$/p' | sed '1d;$d' > ~/.local/bin/fix_cc_mcp
chmod +x ~/.local/bin/fix_cc_mcp

# Edit to add your Morph API key
nano ~/.local/bin/fix_cc_mcp
```

Or copy the script from the full guide.

</details>

**Token discovery:** The script automatically finds your bearer token from `MCP_AGENT_MAIL_TOKEN` env var, `~/mcp_agent_mail/.env`, or existing `~/.claude.json`.

**[Full guide →](FIX_CLAUDE_CODE_MCP_CONFIG.md)**

---

### Mirror Claude Code Skills

Claude Code skills are directories containing a `SKILL.md` file, stored in `.claude/skills/`. Project-local skills only work in that project, but global skills in `~/.claude/skills/` are available everywhere. This script mirrors skills from a project to the global directory using rsync.

**Usage:**

```bash
mirror_cc_skills                     # Mirror from current project
mirror_cc_skills /path/to/project    # Mirror from specific project
mirror_cc_skills --dry-run           # Preview changes
mirror_cc_skills --sync              # Delete skills not in source (backs up first)
```

**Behavior:**

| Mode | What it does |
|:-----|:-------------|
| Default | Only adds/updates skills, never deletes from destination |
| `--sync` | Full sync: deletes skills not in source (creates timestamped backup first) |
| `--dry-run` | Shows what would be copied without making changes |

<details>
<summary><strong>Quick install</strong></summary>

```bash
# Download and install
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/mirror_cc_skills \
  -o ~/.local/bin/mirror_cc_skills
chmod +x ~/.local/bin/mirror_cc_skills
```

Or copy from this repo:
```bash
cp mirror_cc_skills ~/.local/bin/
chmod +x ~/.local/bin/mirror_cc_skills
```

</details>

**Note:** The script automatically installs [gum](https://github.com/charmbracelet/gum) on first run for prettier output (styled boxes and spinners). Works fine without it if installation fails.

**[Script source →](mirror_cc_skills)**

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

### Gemini CLI Crash + Retry Fix

Google's Gemini CLI (`@google/gemini-cli`) has two bugs that make it nearly unusable in practice:

1. **EBADF crash on every launch** (wide terminals): The CLI uses `node-pty` for shell execution. A React `useEffect` fires `resizePty()` after the PTY's file descriptor is already closed. The native C++ addon throws `Error("ioctl(2) failed, EBADF")`, but the catch blocks only check `err.code === 'ESRCH'` — the native addon sets **no `.code` property** (only `.message`), so the error falls through and crashes the entire CLI.

2. **"Sorry there's high demand" gives up after 3 tries**: The default retry config (`DEFAULT_MAX_ATTEMPTS = 3`, `maxDelayMs = 30000`) means Gemini gives up after ~45 seconds. Worse, `TerminalQuotaError` (which fires for daily limits **and** temporary overload) bypasses retry entirely and immediately surrenders.

**One-liner fix:**

```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/fix-gemini-cli-ebadf-crash.sh | bash
```

**What it patches (4 patches across 3 files, all idempotent):**

| Patch | File | Change |
|:------|:-----|:-------|
| EBADF catch #1 | `shellExecutionService.js` | Add `err.message?.includes('EBADF')` to `resizePty()` catch |
| EBADF catch #2 | `AppContainer.js` | Add `EBADF` + `ESRCH` checks to React useEffect catch |
| Aggressive retry | `retry.js` | `maxAttempts` 3 → 1000, `initialDelay` 5s → 1s, `maxDelay` 30s → 5s |
| Never bail on quota | `retry.js` | `TerminalQuotaError` retries with backoff instead of immediately giving up |

<details>
<summary><strong>Other modes</strong></summary>

```bash
./fix-gemini-cli-ebadf-crash.sh --check     # check if patches are needed (no changes)
./fix-gemini-cli-ebadf-crash.sh --verify    # reproduce the EBADF bug + show retry config
./fix-gemini-cli-ebadf-crash.sh --revert    # undo all patches
./fix-gemini-cli-ebadf-crash.sh --uninstall # same as --revert
```

</details>

<details>
<summary><strong>How the EBADF bug was diagnosed</strong></summary>

```bash
$ node -e "const pty = require('@lydell/node-pty-linux-x64/pty.node'); \
  try { pty.resize(-1, 80, 24); } catch(e) { \
    console.log('message:', e.message); \
    console.log('code:', e.code); \
    console.log('has code:', 'code' in e); }"

message: ioctl(2) failed, EBADF
code: undefined
has code: false
```

The native addon throws a plain `Error` with `"EBADF"` only in the message string. The existing catch checks `err.code === 'ESRCH'` which is `undefined === 'ESRCH'` → `false`. The error falls through and crashes React's commit phase.

</details>

**Note:** Patches live in `node_modules` and will be overwritten by package updates. Re-run the script after `bun update -g @google/gemini-cli`.

**[Script source →](fix-gemini-cli-ebadf-crash.sh)**

---

### Reducing Vercel Build Credits

Vercel's automatic deployments on every push can burn through Pro plan credits quickly. Use the REST API to disable auto-deployments and take control of when builds happen.

**Before:**
```
git push → Vercel webhook → Build → Deploy → 💸 (every single push)
```

**After:**
```
git push → (nothing)
vercel --prod → Build → Deploy → 💸 (only when you're ready)
```

**API command to disable auto-deploys:**

```bash
curl -X PATCH "https://api.vercel.com/v9/projects/${PROJECT_ID}?teamId=${TEAM_ID}" \
  -H "Authorization: Bearer ${VERCEL_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"gitProviderOptions": {"createDeployments": "disabled"}}'
```

<details>
<summary><strong>Additional optimizations</strong></summary>

| Setting | API Field | Effect |
|:--------|:----------|:-------|
| Disable auto-deploy | `gitProviderOptions.createDeployments` | No deploys on push/PR |
| Smart skip | `enableAffectedProjectsDeployments` | Skip unchanged monorepo projects |
| Custom check | `commandForIgnoringBuildStep` | Run script to decide |

</details>

**[Full guide →](REDUCING_VERCEL_BUILD_CREDITS.md)**

---

### DevOps CLI Tools

Master the CLI for each cloud platform instead of clicking through web dashboards. This guide covers installation, authentication, and common commands for the tools you use daily.

| Tool | Purpose |
|:-----|:--------|
| `gh` | GitHub PRs, issues, releases |
| `vercel` | Deployments, logs, env vars |
| `wrangler` | Cloudflare Workers, R2 storage |
| `gcloud` | Google Cloud APIs, billing |
| `supabase` | Database migrations, types |

<details>
<summary><strong>Quick install (all tools)</strong></summary>

```bash
# GitHub CLI
brew install gh
gh auth login

# Vercel
bun add -g vercel
vercel login

# Cloudflare Wrangler
bun add -g wrangler
wrangler login

# Supabase
bun add -g supabase
supabase login
```

</details>

The guide also includes AGENTS.md blurbs for each tool with placeholders for your project-specific values.

**[Full guide →](GUIDE_TO_DEVOPS_CLI_TOOLS.md)**

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

## Infrastructure

### HashiCorp Vault HA Cluster

A highly available secrets manager using 3-node Raft consensus. If the leader fails, the cluster elects a new leader and keeps running.

```
┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
│   NODE 1         │   │   NODE 2         │   │   NODE 3         │
│   (Leader)       │   │   (Follower)     │   │   (Follower)     │
│   10.0.1.10      │   │   10.0.1.11      │   │   10.0.1.12      │
└────────┬─────────┘   └────────┬─────────┘   └────────┬─────────┘
         └──────────────────────┼──────────────────────┘
                          Raft Consensus
```

**Why Integrated Raft:**

| Benefit | Description |
|:--------|:------------|
| No external dependencies | Storage built into Vault |
| Automatic failover | Leader election in seconds |
| Consistent replication | All nodes have the same data |

<details>
<summary><strong>Initialize cluster (first node only)</strong></summary>

```bash
export VAULT_ADDR='http://127.0.0.1:8200'

# Initialize with Shamir's Secret Sharing
vault operator init -key-shares=5 -key-threshold=3

# Save the unseal keys and root token securely!
# You need 3 of 5 keys to unseal after restart.

# Unseal
vault operator unseal  # x3 with different keys
```

</details>

<details>
<summary><strong>Check cluster health</strong></summary>

```bash
vault operator raft list-peers
# Node     Address              State       Voter
# node1    10.0.1.10:8201       leader      true
# node2    10.0.1.11:8201       follower    true
# node3    10.0.1.12:8201       follower    true
```

</details>

**[Full guide →](HASHICORP_VAULT_HA_CLUSTER_SETUP.md)**

---

## Tech Stack

| Category | Tools |
|:---------|:------|
| AI Agents | Claude Code, Codex, Gemini CLI |
| Terminals | WezTerm, Ghostty, iTerm2 |
| Editors | VS Code, Zed |
| Version Control | Git (with safety hooks) |
| Remote Access | NFS, SSH, Moonlight, Sunshine |
| Infrastructure | HashiCorp Vault, systemd |
| Platforms | Vercel |
| Package Managers | bun, npm, native installers |
| Hardware | NVIDIA GPUs, Logitech MX Master |
| OS | macOS, Linux (Ubuntu, Arch) |

## Related

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
- [MCP Agent Mail](https://github.com/Dicklesworthstone/mcp_agent_mail) - Multi-agent coordination server
- [Morph MCP](https://github.com/morphllm/morphmcp) - AI-powered code search
- [Beads Project](https://github.com/beads-project/beads)
- [Moonlight](https://moonlight-stream.org/) / [Sunshine](https://github.com/LizardByte/Sunshine)
- [BetterMouse](https://better-mouse.com)
- [WezTerm](https://wezfurlong.org/wezterm/) / [Ghostty](https://ghostty.org)
- [HashiCorp Vault](https://www.vaultproject.io/) / [Vault Tutorials](https://developer.hashicorp.com/vault/tutorials)
- [Vercel REST API](https://vercel.com/docs/rest-api)

---

*Last updated: January 2026*
