# WezTerm Persistent Remote Sessions with Mux Servers

> **The problem:** You work across multiple remote servers. When your Mac sleeps, reboots, or loses power, all your terminal sessions vanish. tmux works, but nested scrollback is confusing and keybindings conflict with local terminal shortcuts.
>
> **The solution:** WezTerm's native multiplexing with `wezterm-mux-server` running on each remote via systemd. Sessions persist on the server; your Mac just reconnects and picks up where you left off.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           YOUR MAC (WezTerm GUI)                             │
│                                                                              │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│   │ 󰍹  Local    │  │ 󰒋  Dev      │  │ 󰒋  Staging  │  │ 󰻠  Workstation│   │
│   │              │  │   purple     │  │   amber      │  │   crimson     │   │
│   │  [3 tabs]    │  │  [3 tabs]    │  │  [3 tabs]    │  │  [3 tabs]     │   │
│   └──────────────┘  └──────┬───────┘  └──────┬───────┘  └───────┬───────┘   │
│          │                 │                 │                  │           │
│     (fresh each       SSH+Mux           SSH+Mux            SSH+Mux         │
│      startup)       (persistent)      (persistent)       (persistent)      │
│                           │                 │                  │            │
└───────────────────────────┼─────────────────┼──────────────────┼────────────┘
                            ▼                 ▼                  ▼
                 ┌──────────────────────────────────────────────────────┐
                 │                    REMOTE SERVERS                     │
                 │                                                       │
                 │  dev-server          staging           workstation    │
                 │  10.20.30.1          10.20.30.2        192.168.1.50   │
                 │                                                       │
                 │  wezterm-mux-server  wezterm-mux-server  wezterm-mux- │
                 │  (systemd, linger)   (systemd, linger)   server       │
                 │                                                       │
                 │  Sessions persist here - survive Mac sleep, reboot,   │
                 │  network drops, even power loss on your laptop.       │
                 └──────────────────────────────────────────────────────┘
```

---

## Table of Contents

- [Why Not tmux?](#why-not-tmux)
- [Prerequisites](#prerequisites)
- [Remote Server Setup](#remote-server-setup)
- [Local WezTerm Configuration](#local-wezterm-configuration)
- [Smart Startup Behavior](#smart-startup-behavior)
- [Keybindings](#keybindings)
- [Maintenance Commands](#maintenance-commands)
- [Troubleshooting](#troubleshooting)

---

## Why Not tmux?

| Feature | tmux | WezTerm Mux |
|:--------|:-----|:------------|
| **Scrollback** | Nested (confusing) | Native terminal scrollback |
| **Keybindings** | Prefix conflicts with terminal | Single namespace |
| **GPU rendering** | Text only | Full GPU acceleration |
| **Mouse** | Needs configuration | Native support |
| **Setup** | Install everywhere | Same WezTerm config |
| **Visual theming** | Limited | Full colors, gradients, tab bar |

If you're happy with tmux, keep using it. This guide is for those who want their remote sessions to feel like local tabs.

---

## Prerequisites

| Component | Where | Version |
|:----------|:------|:--------|
| WezTerm | Local Mac | 20240101+ (same version on all machines) |
| WezTerm | Each remote server | Must match local version |
| SSH access | Local → remotes | Key-based auth recommended |
| systemd | Remote servers | For persistent mux-server |

### Install WezTerm on Remote Servers

```bash
# Ubuntu/Debian
curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
sudo apt update && sudo apt install wezterm

# Verify version matches local
wezterm --version
```

---

## Remote Server Setup

Each remote server needs two things:
1. A systemd user service to run `wezterm-mux-server`
2. `loginctl enable-linger` to keep it running when you disconnect

### Step 1: Create the Systemd Service

SSH to each remote server and create the service file:

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/wezterm-mux-server.service << 'EOF'
[Unit]
Description=WezTerm Mux Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/wezterm-mux-server --daemonize=false
Restart=on-failure
RestartSec=5
Environment=WEZTERM_LOG=warn

[Install]
WantedBy=default.target
EOF
```

### Step 2: Enable and Start the Service

```bash
# Reload systemd to pick up new service
systemctl --user daemon-reload

# Enable (start on boot) and start now
systemctl --user enable --now wezterm-mux-server

# Enable lingering (keeps user session alive without login)
sudo loginctl enable-linger $USER
```

### Step 3: Verify It's Running

```bash
systemctl --user status wezterm-mux-server
# Should show "active (running)"
```

### Step 4: Minimal Remote WezTerm Config (Optional)

Create `~/.wezterm.lua` on the remote to ensure login shells:

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Ensure we get proper login shells
config.default_prog = { '/bin/bash', '-l' }

return config
```

Repeat Steps 1-4 on each remote server.

---

## Local WezTerm Configuration

This config:
- Defines SSH domains with multiplexing
- Applies domain-specific colors
- Creates 4 windows on startup (1 local + 3 remote)
- Avoids tab accumulation on restart (smart startup)

### ~/.wezterm.lua

<details>
<summary><strong>Full configuration (click to expand)</strong></summary>

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ============================================================================
-- SSH DOMAINS
-- ============================================================================

config.ssh_domains = {
  {
    name = 'dev-server',
    remote_address = '10.20.30.1',
    username = 'ubuntu',
    multiplexing = 'WezTerm',
    assume_shell = 'Posix',
  },
  {
    name = 'staging',
    remote_address = '10.20.30.2',
    username = 'ubuntu',
    multiplexing = 'WezTerm',
    assume_shell = 'Posix',
  },
  {
    name = 'workstation',
    remote_address = '192.168.1.50',
    username = 'dev',
    multiplexing = 'WezTerm',
    assume_shell = 'Posix',
  },
}

-- ============================================================================
-- DOMAIN COLORS
-- ============================================================================

local domain_colors = {
  ['dev-server'] = {
    background = {{
      source = { Gradient = {
        colors = { '#1a0d1a', '#2e1a2e', '#3e163e' },
        orientation = { Linear = { angle = -45.0 } },
      }},
      width = '100%', height = '100%', opacity = 0.92,
    }},
    colors = {
      background = '#1a0d1a',
      cursor_bg = '#bb9af7',
      cursor_border = '#bb9af7',
      split = '#bb9af7',
      tab_bar = {
        background = 'rgba(26, 13, 26, 0.9)',
        active_tab = { bg_color = '#bb9af7', fg_color = '#1a0d1a', intensity = 'Bold' },
        inactive_tab = { bg_color = '#2e1a2e', fg_color = '#9070a0' },
        inactive_tab_hover = { bg_color = '#3e163e', fg_color = '#bb9af7' },
      },
    },
  },

  ['staging'] = {
    background = {{
      source = { Gradient = {
        colors = { '#1a0f05', '#2e1a10', '#3e2116' },
        orientation = { Linear = { angle = -45.0 } },
      }},
      width = '100%', height = '100%', opacity = 0.92,
    }},
    colors = {
      background = '#1a0f05',
      cursor_bg = '#e0af68',
      cursor_border = '#e0af68',
      split = '#e0af68',
      tab_bar = {
        background = 'rgba(26, 15, 5, 0.9)',
        active_tab = { bg_color = '#e0af68', fg_color = '#1a0f05', intensity = 'Bold' },
        inactive_tab = { bg_color = '#2e1a10', fg_color = '#a08060' },
        inactive_tab_hover = { bg_color = '#3e2116', fg_color = '#e0af68' },
      },
    },
  },

  ['workstation'] = {
    background = {{
      source = { Gradient = {
        colors = { '#1a0a0a', '#2e1416', '#3e1a1c' },
        orientation = { Linear = { angle = -45.0 } },
      }},
      width = '100%', height = '100%', opacity = 0.92,
    }},
    colors = {
      background = '#1a0a0a',
      cursor_bg = '#dc143c',
      cursor_border = '#dc143c',
      split = '#dc143c',
      tab_bar = {
        background = 'rgba(26, 10, 10, 0.9)',
        active_tab = { bg_color = '#dc143c', fg_color = '#ffffff', intensity = 'Bold' },
        inactive_tab = { bg_color = '#2e1416', fg_color = '#a06070' },
        inactive_tab_hover = { bg_color = '#3e1a1c', fg_color = '#dc143c' },
      },
    },
  },
}

local domain_info = {
  ['dev-server']  = { name = 'Dev Server',   icon = '󰒋 ', color = '#bb9af7' },
  ['staging']     = { name = 'Staging',      icon = '󰒋 ', color = '#e0af68' },
  ['workstation'] = { name = 'Workstation',  icon = '󰻠 ', color = '#dc143c' },
}

-- ============================================================================
-- APPLY COLORS DYNAMICALLY
-- ============================================================================

local last_domain = {}

wezterm.on('update-status', function(window, pane)
  local domain = pane:get_domain_name()
  local win_id = tostring(window:window_id())

  if last_domain[win_id] ~= domain then
    last_domain[win_id] = domain
    local overrides = window:get_config_overrides() or {}

    if domain_colors[domain] then
      overrides.background = domain_colors[domain].background
      overrides.colors = domain_colors[domain].colors
    else
      overrides.background = nil
      overrides.colors = nil
    end
    window:set_config_overrides(overrides)
  end

  -- Right status badge
  local info = domain_info[domain]
  if info then
    window:set_right_status(wezterm.format {
      { Foreground = { Color = '#0d0d1a' } },
      { Background = { Color = info.color } },
      { Attribute = { Intensity = 'Bold' } },
      { Text = ' ' .. info.icon .. info.name .. ' ' },
    })
  else
    window:set_right_status('')
  end
end)

-- ============================================================================
-- SMART STARTUP
-- ============================================================================
-- Creates 4 windows on launch:
--   1. Local window with 3 tabs
--   2-4. Remote windows (connects to mux-server, creates tabs only if empty)

local remote_domains = {
  { name = 'dev-server',  cwd = '/data/projects' },
  { name = 'staging',     cwd = '/var/www' },
  { name = 'workstation', cwd = '/home/dev/code' },
}

local tabs_per_window = 3

wezterm.on('gui-startup', function(cmd)
  -- Local window
  local local_tab, local_pane, local_window = wezterm.mux.spawn_window {
    cwd = wezterm.home_dir .. '/projects',
  }
  for i = 2, tabs_per_window do
    local_window:spawn_tab { cwd = wezterm.home_dir .. '/projects' }
  end

  -- Remote windows
  for _, remote in ipairs(remote_domains) do
    local ok, err = pcall(function()
      local tab, pane, window = wezterm.mux.spawn_window {
        domain = { DomainName = remote.name },
        cwd = remote.cwd,
      }
      -- Check if mux-server already has windows
      local existing_tabs = window:tabs()
      if #existing_tabs <= 1 then
        -- Fresh mux-server, create additional tabs
        for i = 2, tabs_per_window do
          window:spawn_tab { cwd = remote.cwd }
        end
      end
      -- Else: mux-server has existing tabs, don't create more
    end)
    if not ok then
      wezterm.log_warn('Failed to connect to ' .. remote.name .. ': ' .. tostring(err))
    end
  end
end)

-- ============================================================================
-- LEADER KEY
-- ============================================================================

config.leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 1000 }

config.keys = {
  -- Quick tab creation per domain
  { key = '1', mods = 'LEADER', action = wezterm.action.SpawnCommandInNewTab {
    domain = { DomainName = 'dev-server' }, cwd = '/data/projects' }},
  { key = '2', mods = 'LEADER', action = wezterm.action.SpawnCommandInNewTab {
    domain = { DomainName = 'staging' }, cwd = '/var/www' }},
  { key = '3', mods = 'LEADER', action = wezterm.action.SpawnCommandInNewTab {
    domain = { DomainName = 'workstation' }, cwd = '/home/dev/code' }},

  -- Tab switching
  { key = 'LeftArrow', mods = 'SHIFT|CTRL', action = wezterm.action.ActivateTabRelative(-1) },
  { key = 'RightArrow', mods = 'SHIFT|CTRL', action = wezterm.action.ActivateTabRelative(1) },

  -- Domain launcher
  { key = 'w', mods = 'LEADER', action = wezterm.action.ShowLauncherArgs { flags = 'DOMAINS' } },
}

return config
```

</details>

---

## Smart Startup Behavior

The `gui-startup` event handles two scenarios:

### First Launch (after mux-server restart)
1. Creates local window with 3 tabs
2. Connects to each remote mux-server
3. Mux-server has no windows → creates 3 tabs
4. Result: 4 windows, each with 3 tabs

### Subsequent Launches (normal case)
1. Creates local window with 3 tabs (local doesn't persist)
2. Connects to each remote mux-server
3. Mux-server already has windows → just shows them
4. Result: 4 windows with your existing remote tabs exactly as you left them

**No tab accumulation!** The smart startup checks if remotes already have tabs before creating more.

---

## Keybindings

**Leader key:** `Ctrl+a` (1 second timeout)

### Quick Tab Creation

| Key | Action |
|:----|:-------|
| `Leader + 1` | New tab in dev-server |
| `Leader + 2` | New tab in staging |
| `Leader + 3` | New tab in workstation |

### Navigation

| Key | Action |
|:----|:-------|
| `Ctrl+Shift+Left/Right` | Switch tabs |
| `Leader + w` | Domain launcher (connect to any domain) |
| `Cmd+\`` | Cycle windows (macOS default) |

---

## Maintenance Commands

### Check Remote Mux-Server Status

```bash
ssh dev-server 'systemctl --user status wezterm-mux-server'
ssh staging 'systemctl --user status wezterm-mux-server'
ssh workstation 'systemctl --user status wezterm-mux-server'
```

### Restart Mux-Server (Clears All Tabs)

```bash
ssh dev-server 'systemctl --user restart wezterm-mux-server'
```

### View Logs

```bash
ssh dev-server 'journalctl --user -u wezterm-mux-server --since "1 hour ago"'
```

### Check WezTerm Version Match

```bash
# Local
wezterm --version

# Remote
ssh dev-server 'wezterm --version'
```

Both should show the same version (e.g., `20240101-123456-abcdef`).

---

## Troubleshooting

| Symptom | Cause | Fix |
|:--------|:------|:----|
| "Connection failed" on startup | Remote unreachable or mux-server not running | Check SSH connectivity; verify systemd service is active |
| Wrong number of tabs on remote | Previous session state persisted | Restart mux-server: `ssh host 'systemctl --user restart wezterm-mux-server'` |
| Colors not applying | `update-status` event not recognizing domain | Check `pane:get_domain_name()` returns expected value |
| Version mismatch errors | Local and remote WezTerm versions differ | Update WezTerm on both ends to same version |
| Mux-server dies on disconnect | Lingering not enabled | Run `sudo loginctl enable-linger $USER` on remote |
| Can't create new tabs in domain | Mux-server crashed | Check logs; restart service |

### Debug Domain Names

Open WezTerm's debug overlay with `Ctrl+Shift+L` to inspect the current domain and pane state.

---

## Quick Reference

### Files Created

| Location | Purpose |
|:---------|:--------|
| Local `~/.wezterm.lua` | Main configuration with domains, colors, startup |
| Remote `~/.wezterm.lua` | Optional, ensures login shells |
| Remote `~/.config/systemd/user/wezterm-mux-server.service` | Persistent mux-server |

### Adding a New Remote Domain

1. Add to `config.ssh_domains` in local config
2. Add to `remote_domains` table for startup
3. Add color scheme to `domain_colors`
4. Add metadata to `domain_info`
5. Set up mux-server on remote (Steps 1-4 from [Remote Server Setup](#remote-server-setup))

---

*Last updated: January 2026*
