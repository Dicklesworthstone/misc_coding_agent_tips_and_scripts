# Host-Aware Color Themes for Ghostty and WezTerm

> **The problem:** You have terminals open to 4 different servers. Which one is production?
>
> **The solution:** Each server gets a distinct color scheme, applied automatically when you connect.

```
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ ▓▓▓ PURPLE ▓▓▓▓▓ │  │ ▓▓▓ AMBER ▓▓▓▓▓▓ │  │ ▓▓▓ EMERALD ▓▓▓▓ │  │ ▓▓▓ CRIMSON ▓▓▓▓ │
│                  │  │                  │  │                  │  │                  │
│  contabo-vps     │  │  ovh-bare-metal  │  │  hetzner-vps     │  │  contabo-metal   │
│  (dev server)    │  │  (staging)       │  │  (CI runner)     │  │  (production!)   │
│                  │  │                  │  │                  │  │                  │
└──────────────────┘  └──────────────────┘  └──────────────────┘  └──────────────────┘
```

---

## Table of Contents

- [Choose Your Approach](#choose-your-approach)
- [Ghostty Setup](#ghostty-setup): shell functions, works in any terminal
- [WezTerm Setup](#wezterm-setup): native Lua, richer features
- [Design Your Own Color Schemes](#design-your-own-color-schemes)
- [Troubleshooting](#troubleshooting)

---

## Choose Your Approach

| | **Ghostty (Shell)** | **WezTerm (Lua)** |
|:--|:--|:--|
| **How it works** | Shell functions wrap SSH and emit color-changing escape codes | Native config detects which domain you're in and applies themes |
| **Setup time** | ~5 minutes | ~15 minutes |
| **Works in** | Any modern terminal | WezTerm only |
| **Tab bar theming** | No | Yes |
| **Gradient backgrounds** | No | Yes |
| **Session persistence** | No (standard SSH) | Yes (survives disconnects) |
| **Best for** | Quick setup, portability | Power users, rich visuals |

> **Recommendation:** Start with Ghostty if you want something working in 5 minutes. Move to WezTerm if you want gradients, tab bar theming, and persistent sessions.

---

## Ghostty Setup

This approach uses **OSC escape sequences**, special codes that tell the terminal to change colors on the fly. The technique works in Ghostty, WezTerm, iTerm2, and most modern terminals.

### How It Works

```
You type:  contabo-vps
              │
              ▼
┌─────────────────────────────────────┐
│ Shell function runs:                │
│   1. printf '\e]11;#1a0d1a\a'  ───────▶ Terminal background turns purple
│   2. ssh ubuntu@contabo-vps    ───────▶ You're connected
│   3. [you work, then exit]          │
│   4. printf '\e]111\a'         ───────▶ Colors reset to default
└─────────────────────────────────────┘
```

<details>
<summary><strong>What are OSC escape sequences?</strong></summary>

**OSC** (Operating System Command) sequences are instructions embedded in terminal output that control terminal behavior. The format is:

```
\e]<code>;<value>\a
    │       │     └── String Terminator (BEL character)
    │       └──────── The value to set
    └──────────────── The property to change
```

| Code | What it changes | Reset code |
|:-----|:----------------|:-----------|
| `10` | Foreground (text) color | `110` |
| `11` | Background color | `111` |
| `12` | Cursor color | `112` |
| `4;N` | Palette color N (0-15) | `104` |

These are standardized and work across terminals. When your shell function runs `printf '\e]11;#1a0d1a\a'`, it's telling the terminal: "change background to `#1a0d1a`".

</details>

### Quick Start

Add to your `~/.zshrc` (or `~/.bashrc`):

```bash
# contabo-vps: Purple theme
contabo-vps() {
  printf '\e]11;#1a0d1a\a\e]10;#e8d4f8\a\e]12;#bb9af7\a'  # Set colors
  ssh ubuntu@contabo-vps.example.com "$@"
  printf '\e]111\a\e]110\a\e]112\a\e]104\a'               # Reset colors
}
```

Then: `source ~/.zshrc` and type `contabo-vps` to connect.

### Full Configuration

<details>
<summary><strong>Complete 4-server setup with detailed color palettes</strong></summary>

```bash
# =============================================================================
# HOST-AWARE SSH FUNCTIONS
# =============================================================================
# Each function: sets colors → connects via SSH → resets colors on exit
# Colors chosen for distinctiveness: purple, amber, emerald, crimson
# =============================================================================

# ┌─────────────────────────────────────────────────────────────────────────────
# │ CONTABO-VPS: Purple/Violet
# │ Use case: Development server
# └─────────────────────────────────────────────────────────────────────────────
contabo-vps() {
  printf '\e]11;#1a0d1a\a'   # bg:      deep purple-black
  printf '\e]10;#e8d4f8\a'   # fg:      lavender (high contrast on dark purple)
  printf '\e]12;#bb9af7\a'   # cursor:  soft violet
  printf '\e]4;4;#7c3aed\a'  # blue:    purple (affects ls directories, etc.)
  printf '\e]4;5;#c792ea\a'  # magenta: orchid
  printf '\e]4;6;#a78bfa\a'  # cyan:    violet
  ssh ubuntu@contabo-vps.example.com "$@"
  printf '\e]111\a\e]110\a\e]112\a\e]104\a'
}

# ┌─────────────────────────────────────────────────────────────────────────────
# │ OVH-BARE-METAL: Amber/Warm
# │ Use case: Staging environment
# └─────────────────────────────────────────────────────────────────────────────
ovh-bare-metal() {
  printf '\e]11;#1a0f05\a'   # bg:      dark brown
  printf '\e]10;#f8e4d4\a'   # fg:      warm cream
  printf '\e]12;#e0af68\a'   # cursor:  amber
  printf '\e]4;1;#ff9e64\a'  # red:     orange
  printf '\e]4;3;#ffc777\a'  # yellow:  golden
  printf '\e]4;5;#d19a66\a'  # magenta: bronze
  ssh ubuntu@ovh-bare-metal.example.com "$@"
  printf '\e]111\a\e]110\a\e]112\a\e]104\a'
}

# ┌─────────────────────────────────────────────────────────────────────────────
# │ HETZNER-VPS: Emerald/Green
# │ Use case: CI runners, build servers
# └─────────────────────────────────────────────────────────────────────────────
hetzner-vps() {
  printf '\e]11;#0a1a0f\a'   # bg:      deep forest
  printf '\e]10;#d4f8e4\a'   # fg:      mint
  printf '\e]12;#50fa7b\a'   # cursor:  bright green
  printf '\e]4;2;#9ece6a\a'  # green:   lime
  printf '\e]4;4;#34d399\a'  # blue:    emerald
  printf '\e]4;6;#2dd4bf\a'  # cyan:    teal
  ssh ubuntu@hetzner-vps.example.com "$@"
  printf '\e]111\a\e]110\a\e]112\a\e]104\a'
}

# ┌─────────────────────────────────────────────────────────────────────────────
# │ CONTABO-BARE-METAL: Crimson/Red
# │ Use case: PRODUCTION (red = danger, be careful!)
# └─────────────────────────────────────────────────────────────────────────────
contabo-bare-metal() {
  printf '\e]11;#1a0a0a\a'   # bg:      deep crimson-black
  printf '\e]10;#f8d4d4\a'   # fg:      soft rose
  printf '\e]12;#ff6b6b\a'   # cursor:  bright coral
  printf '\e]4;1;#f7768e\a'  # red:     soft coral
  printf '\e]4;3;#fca5a5\a'  # yellow:  salmon
  printf '\e]4;5;#ff79c6\a'  # magenta: hot pink
  ssh ubuntu@contabo-bare-metal.example.com "$@"
  printf '\e]111\a\e]110\a\e]112\a\e]104\a'
}

# Optional: Short aliases
alias cv='contabo-vps'
alias ob='ovh-bare-metal'
alias hv='hetzner-vps'
alias cb='contabo-bare-metal'
```

</details>

### Robust Version (Handles Ctrl+C)

If you interrupt SSH with Ctrl+C, the reset codes after `ssh` won't run. Use `trap` to guarantee cleanup:

```bash
contabo-vps() {
  printf '\e]11;#1a0d1a\a\e]10;#e8d4f8\a\e]12;#bb9af7\a'
  trap 'printf "\e]111\a\e]110\a\e]112\a\e]104\a"' EXIT
  ssh ubuntu@contabo-vps.example.com "$@"
  trap - EXIT
  printf '\e]111\a\e]110\a\e]112\a\e]104\a'
}
```

---

## WezTerm Setup

WezTerm's Lua configuration enables features impossible with escape sequences: gradient backgrounds, themed tab bars, status badges, and **multiplexed sessions** that persist through disconnections.

### How It Works

```
You connect to domain "contabo-vps"
              │
              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│ WezTerm's update-status event fires                                         │
│              │                                                              │
│              ▼                                                              │
│ Lua code: domain = pane:get_domain_name()  →  "contabo-vps"                 │
│              │                                                              │
│              ▼                                                              │
│ Applies domain_colors["contabo-vps"]:                                       │
│   • Background gradient: #1a0d1a → #2e1a2e → #3e163e                        │
│   • Tab bar: purple active tab, dark inactive tabs                          │
│   • Status badge: "󰒋 Contabo VPS" in purple                                 │
│   • Window title: "󰒋 Contabo VPS │ zsh"                                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

<details>
<summary><strong>What is WezTerm multiplexing?</strong></summary>

**Multiplexing** means WezTerm runs a server process (`wezterm-mux-server`) on the remote host that manages your sessions. Benefits:

| Feature | Standard SSH | WezTerm Multiplexing |
|:--------|:-------------|:---------------------|
| Network drops | Session dies | Session continues |
| Close laptop | Session dies | Reconnect later, same state |
| Multiple tabs | Local terminal tabs | Remote tabs in native UI |
| Scrollback | Local only | Preserved on server |

Think of it as tmux integrated into WezTerm's native tab/pane system.

**Setup:** Install WezTerm on the remote host. The mux server starts automatically when you connect via an SSH domain with `multiplexing = 'WezTerm'`.

</details>

### Quick Start

Add to your `~/.wezterm.lua`:

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- Define your servers
config.ssh_domains = {
  { name = 'contabo-vps', remote_address = 'contabo-vps.example.com', username = 'ubuntu', multiplexing = 'WezTerm' },
}

-- Connect: Ctrl+Shift+L → select "contabo-vps"

return config
```

For full theming, continue to the complete configuration below.

### Full Configuration

<details>
<summary><strong>Complete setup with 4 servers, gradients, and status bar</strong></summary>

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ============================================================================
-- SSH DOMAINS
-- ============================================================================
-- multiplexing = 'WezTerm' enables persistent sessions (requires wezterm on remote)
-- assume_shell = 'Posix' helps with shell detection on Linux servers
-- ============================================================================

config.ssh_domains = {
  {
    name = 'contabo-vps',
    remote_address = 'contabo-vps.example.com',
    username = 'ubuntu',
    multiplexing = 'WezTerm',
    assume_shell = 'Posix',
  },
  {
    name = 'ovh-bare-metal',
    remote_address = 'ovh-bare-metal.example.com',
    username = 'ubuntu',
    multiplexing = 'WezTerm',
    assume_shell = 'Posix',
  },
  {
    name = 'hetzner-vps',
    remote_address = 'hetzner-vps.example.com',
    username = 'ubuntu',
    multiplexing = 'WezTerm',
    assume_shell = 'Posix',
  },
  {
    name = 'contabo-bare-metal',
    remote_address = 'contabo-bare-metal.example.com',
    username = 'ubuntu',
    multiplexing = 'WezTerm',
    assume_shell = 'Posix',
  },
}

-- ============================================================================
-- COLOR SCHEMES PER DOMAIN
-- ============================================================================
-- Each domain gets:
--   • Gradient background (3 colors, diagonal)
--   • Matching cursor and split colors
--   • Themed tab bar (active/inactive/hover states)
-- ============================================================================

local domain_colors = {
  ['contabo-vps'] = {
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

  ['ovh-bare-metal'] = {
    background = {{
      source = { Gradient = {
        colors = { '#1a0d0d', '#2e1a1a', '#3e2116' },
        orientation = { Linear = { angle = -45.0 } },
      }},
      width = '100%', height = '100%', opacity = 0.92,
    }},
    colors = {
      background = '#1a0d0d',
      cursor_bg = '#e0af68',
      cursor_border = '#e0af68',
      split = '#e0af68',
      tab_bar = {
        background = 'rgba(26, 13, 13, 0.9)',
        active_tab = { bg_color = '#e0af68', fg_color = '#1a0d0d', intensity = 'Bold' },
        inactive_tab = { bg_color = '#2e1a1a', fg_color = '#a08060' },
        inactive_tab_hover = { bg_color = '#3e2116', fg_color = '#e0af68' },
      },
    },
  },

  ['hetzner-vps'] = {
    background = {{
      source = { Gradient = {
        colors = { '#0a1a0f', '#1a2e1a', '#163e1e' },
        orientation = { Linear = { angle = -45.0 } },
      }},
      width = '100%', height = '100%', opacity = 0.92,
    }},
    colors = {
      background = '#0a1a0f',
      cursor_bg = '#50fa7b',
      cursor_border = '#50fa7b',
      split = '#50fa7b',
      tab_bar = {
        background = 'rgba(10, 26, 15, 0.9)',
        active_tab = { bg_color = '#50fa7b', fg_color = '#0a1a0f', intensity = 'Bold' },
        inactive_tab = { bg_color = '#1a2e1a', fg_color = '#70a080' },
        inactive_tab_hover = { bg_color = '#163e1e', fg_color = '#50fa7b' },
      },
    },
  },

  ['contabo-bare-metal'] = {
    background = {{
      source = { Gradient = {
        colors = { '#1a0d0d', '#2e1416', '#3e1a1c' },
        orientation = { Linear = { angle = -45.0 } },
      }},
      width = '100%', height = '100%', opacity = 0.92,
    }},
    colors = {
      background = '#1a0d0d',
      cursor_bg = '#dc143c',
      cursor_border = '#dc143c',
      split = '#dc143c',
      tab_bar = {
        background = 'rgba(26, 13, 13, 0.9)',
        active_tab = { bg_color = '#dc143c', fg_color = '#ffffff', intensity = 'Bold' },
        inactive_tab = { bg_color = '#2e1416', fg_color = '#a06070' },
        inactive_tab_hover = { bg_color = '#3e1a1c', fg_color = '#dc143c' },
      },
    },
  },
}

-- ============================================================================
-- DOMAIN METADATA (for status bar and window titles)
-- ============================================================================

local domain_info = {
  ['contabo-vps']       = { name = 'Contabo VPS',   icon = '󰒋 ', color = '#bb9af7' },
  ['ovh-bare-metal']    = { name = 'OVH Metal',     icon = '󰒋 ', color = '#e0af68' },
  ['hetzner-vps']       = { name = 'Hetzner VPS',   icon = '󰒋 ', color = '#50fa7b' },
  ['contabo-bare-metal']= { name = 'Contabo Metal', icon = '󰻠 ', color = '#dc143c' },
}

-- ============================================================================
-- DYNAMIC WINDOW TITLE
-- ============================================================================

wezterm.on('format-window-title', function(tab, pane, tabs, panes, config)
  local domain = pane.domain_name or 'local'
  local title = pane.title or ''
  local info = domain_info[domain]
  if info then
    return info.icon .. info.name .. ' │ ' .. title
  end
  return '󰍹  Local │ ' .. title
end)

-- ============================================================================
-- APPLY COLORS WHEN DOMAIN CHANGES
-- ============================================================================
-- Caches last domain per window to avoid unnecessary redraws (which break
-- text selection if they happen during a drag).
-- ============================================================================

local last_domain = {}

wezterm.on('update-status', function(window, pane)
  local domain = pane:get_domain_name()
  local win_id = tostring(window:window_id())

  -- Only update if domain changed
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

  -- Right status: show domain badge
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

return config
```

</details>

### Connecting to Domains

| Method | How |
|:-------|:----|
| **Launcher menu** | `Ctrl+Shift+L` → select domain from list |
| **New tab in domain** | Right-click tab bar → "New Tab" → select domain |
| **Command palette** | `Ctrl+Shift+P` → "Connect to SSH Domain" |

### Installing WezTerm on Remote Hosts

For multiplexing to work, WezTerm must be installed on the server:

```bash
# Ubuntu/Debian
curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
sudo apt update && sudo apt install wezterm

# The mux server starts automatically on first connection
```

> **Note:** Multiplexing is optional. Remove `multiplexing = 'WezTerm'` to use standard SSH (colors still work, but sessions won't persist).

---

## Design Your Own Color Schemes

### Color Selection Principles

| Principle | Why | Example |
|:----------|:----|:--------|
| **Dark, saturated backgrounds** | Readable, distinctive, not distracting | `#1a0d1a` not `#800080` |
| **High-contrast foreground** | Text must be readable | Lavender `#e8d4f8` on purple `#1a0d1a` |
| **Accent from same hue family** | Visual coherence | Purple bg → violet cursor |
| **Distinct hues between hosts** | Instantly distinguishable | Purple vs Amber vs Green vs Red |

### Suggested Palette

| Name | Background | Accent | Feeling |
|:-----|:-----------|:-------|:--------|
| Purple | `#1a0d1a` | `#bb9af7` | Creative, dev |
| Amber | `#1a0f05` | `#e0af68` | Warm, staging |
| Emerald | `#0a1a0f` | `#50fa7b` | Fresh, CI/build |
| Crimson | `#1a0a0a` | `#dc143c` | Alert, production |
| Cyan | `#0a1a1a` | `#7dcfff` | Cool, testing |
| Gold | `#1a1505` | `#ffd700` | Bright, demo |

### Creating Gradients (WezTerm)

Gradients add depth. Start with your base color and create lighter variants:

```lua
-- Base: #1a0d1a (purple)
colors = {
  '#1a0d1a',  -- darkest (bottom-right)
  '#2e1a2e',  -- mid
  '#3e163e',  -- lightest (top-left)
}
-- Technique: increase each RGB channel by ~20-30 per step
```

### ANSI Palette Colors (Ghostty)

When you set `\e]4;N;COLOR\a`, you're changing palette color N:

| N | Name | Typically affects |
|:--|:-----|:------------------|
| 0 | Black | Backgrounds |
| 1 | Red | Errors, git deletions |
| 2 | Green | Success, git additions |
| 3 | Yellow | Warnings |
| 4 | Blue | Directories, info |
| 5 | Magenta | Keywords, special |
| 6 | Cyan | Strings, constants |
| 7 | White | Text |

> **Tip:** Only override colors that reinforce your theme. Changing red/green can make git diffs confusing.

---

## Troubleshooting

### Ghostty Issues

| Symptom | Cause | Fix |
|:--------|:------|:----|
| Colors don't change | Terminal doesn't support OSC | Try iTerm2, WezTerm, or Kitty |
| Colors don't reset after exit | Reset codes after SSH didn't run | Use the `trap` version above |
| Colors persist after Ctrl+C | Interrupt skipped cleanup | Use the `trap` version above |
| Colors look different than expected | Terminal color interpretation varies | Adjust hex values to taste |

### WezTerm Issues

| Symptom | Cause | Fix |
|:--------|:------|:----|
| Colors don't change | `update-status` not firing | Check Lua syntax; run `wezterm` from terminal to see errors |
| Domain not in launcher | `ssh_domains` misconfigured | Verify Lua table syntax, check for typos |
| "Connection refused" | wezterm-mux-server not running | Install WezTerm on remote host |
| Colors flash/flicker | Overrides applied too frequently | Ensure `last_domain` cache is working |
| Tab bar not themed | `tab_bar` missing from colors | Add `tab_bar` block to `domain_colors` |

**Debug tip:** Run WezTerm from another terminal to see Lua errors:

```bash
wezterm 2>&1 | grep -i error
```

---

## Quick Reference

### Ghostty: Add a New Host

```bash
# Template: copy and customize
new-host() {
  printf '\e]11;#BACKGROUND\a'  # Background
  printf '\e]10;#FOREGROUND\a'  # Foreground
  printf '\e]12;#CURSOR\a'      # Cursor
  ssh user@hostname "$@"
  printf '\e]111\a\e]110\a\e]112\a\e]104\a'
}
```

### WezTerm: Add a New Host

1. Add to `config.ssh_domains`:
   ```lua
   { name = 'new-host', remote_address = 'host.example.com', username = 'ubuntu', multiplexing = 'WezTerm' },
   ```

2. Add to `domain_colors`:
   ```lua
   ['new-host'] = {
     background = {{ source = { Gradient = { colors = { '#BASE', '#MID', '#LIGHT' }, orientation = { Linear = { angle = -45.0 }}}}, width = '100%', height = '100%', opacity = 0.92 }},
     colors = { background = '#BASE', cursor_bg = '#ACCENT', cursor_border = '#ACCENT', split = '#ACCENT',
       tab_bar = { background = 'rgba(R,G,B,0.9)', active_tab = { bg_color = '#ACCENT', fg_color = '#BASE', intensity = 'Bold' }, inactive_tab = { bg_color = '#MID', fg_color = '#DIM' }, inactive_tab_hover = { bg_color = '#LIGHT', fg_color = '#ACCENT' }}},
   },
   ```

3. Add to `domain_info`:
   ```lua
   ['new-host'] = { name = 'Display Name', icon = '󰒋 ', color = '#ACCENT' },
   ```

---

*Last updated: January 2026*
