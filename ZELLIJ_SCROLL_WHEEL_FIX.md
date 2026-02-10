# Mouse Wheel Scrollback in Zellij over SSH

Fix mouse wheel scrolling in Zellij when connecting to a remote machine from macOS. Without this fix, the scroll wheel triggers shell history (atuin) or sends arrow keys instead of scrolling the terminal buffer.

---

## TL;DR: Quick Start

Three components, takes about 10 minutes:

1. **Zellij config** (remote server): Bind `Alt+Up`/`Alt+Down` to `ScrollUp`/`ScrollDown` in locked mode
2. **Hammerspoon** (Mac): Intercept scroll wheel events and convert them to `Alt+Up`/`Alt+Down` keystrokes when your terminal app is focused
3. **Atuin** (remote server, optional): Add `--disable-up-arrow` so stray arrow keys don't trigger history search

Read on for the full explanation, the wrong turns, and why this specific approach works.

---

## Table of Contents

- [The Problem](#the-problem)
- [Why This Happens](#why-this-happens)
- [What Doesn't Work](#what-doesnt-work)
- [The Solution](#the-solution)
- [Part 1: Zellij Configuration](#part-1-zellij-configuration)
- [Part 2: Hammerspoon on macOS](#part-2-hammerspoon-on-macos)
- [Part 3: Atuin Guard](#part-3-atuin-guard)
- [WezTerm Native Alternative](#wezterm-native-alternative)
- [Tuning Scroll Speed](#tuning-scroll-speed)
- [Troubleshooting](#troubleshooting)
- [Why Not Other Approaches](#why-not-other-approaches)

---

## The Problem

> **Origin story:** SSH into a Linux workstation from a Mac Mini using a terminal emulator (Ghostty or WezTerm). The remote machine runs Zellij as the terminal multiplexer. Everything works great except scrolling: the mouse wheel opens atuin's full-screen history search instead of scrolling the terminal buffer. You want scrollback that feels like there's no mux at all.

The expected behavior:

```
Mouse wheel up → Terminal scrolls up through output history
Mouse wheel down → Terminal scrolls back down
```

What actually happens:

```
Mouse wheel up → Sends ↑ arrow key → Atuin opens full-screen history TUI
Mouse wheel down → Sends ↓ arrow key → Nothing useful
```

---

## Why This Happens

There's a chain of three systems interacting, and the break happens in Zellij:

```
┌──────────────────────────────────────────────────────────────┐
│  Terminal Emulator (Ghostty/WezTerm on Mac)                  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  SSH Connection                                        │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  Zellij (on remote server)                       │  │  │
│  │  │  ┌────────────────────────────────────────────┐  │  │  │
│  │  │  │  Shell (zsh + atuin)                       │  │  │  │
│  │  │  │  ↑ arrow = atuin history search            │  │  │  │
│  │  │  └────────────────────────────────────────────┘  │  │  │
│  │  │  ❌ Scroll events converted to arrow keys        │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
│  ✅ Mouse tracking works fine (sends proper SGR events)      │
└──────────────────────────────────────────────────────────────┘
```

**Step by step:**

1. **Zellij runs in the alternate screen buffer** and enables mouse tracking (sends `\e[?1000h`, `\e[?1002h`, `\e[?1003h`, etc.)
2. **The terminal emulator sees mouse tracking is enabled** and sends proper SGR mouse events (`\e[<65;col;rowM`) for scroll wheel actions
3. **Zellij receives the mouse scroll events** but converts them to arrow key presses instead of scrolling its own buffer
4. **The arrow keys reach the shell**, where atuin intercepts the up arrow to show history

This is a known Zellij limitation documented in [GitHub issue #3941](https://github.com/zellij-org/zellij/issues/3941) and [discussion #4117](https://github.com/zellij-org/zellij/discussions/4117). Zellij handles mouse clicks and drag for pane selection/resize, but scroll wheel events get translated to arrow keys regardless of mode.

### How we confirmed this

**Test 1: strace on Zellij startup** showed it sends all the correct mouse tracking enable sequences:

```
\e[?1000h  (basic mouse tracking)
\e[?1002h  (button-event tracking)
\e[?1003h  (all-motion tracking)
\e[?1015h  (urxvt mouse encoding)
\e[?1006h  (SGR mouse encoding)
```

**Test 2: Raw mouse capture over plain SSH** (no Zellij) confirmed the terminal emulator sends proper SGR mouse events:

```bash
#!/bin/bash
# Enable alternate screen + mouse tracking
printf '\e[?1049h\e[?1000h\e[?1002h\e[?1006h'
printf '\e[2J\e[HMouse tracking active. Scroll wheel to test. Ctrl-C to exit.\n'
trap 'printf "\e[?1006l\e[?1002l\e[?1000l\e[?1049l"' EXIT
cat -v  # Shows raw input
```

Output when scrolling:

```
^[[<65;22;9M    ← scroll up event (proper SGR encoding)
^[[<64;22;9M    ← scroll down event
```

The terminal sends correct events. Zellij is where they get lost.

---

## What Doesn't Work

We tried several approaches before landing on the working solution:

| Approach | Why It Fails |
|:---------|:-------------|
| Change Zellij `default_mode` from `locked` to `normal` | Doesn't affect scroll handling; Zellij converts scroll to arrows in all modes |
| Quit BetterMouse (smooth scrolling app) | Scroll events still reach Zellij correctly; BetterMouse isn't the problem |
| WezTerm `mouse_bindings` with `act.SendKey` | `SendKey` used directly in mouse bindings [silently fails](https://github.com/wezterm/wezterm/issues/5230) |
| WezTerm `mouse_bindings` with `action_callback` | Should work in theory but didn't trigger in practice with `mouse_reporting = true` |
| Disabling atuin's up-arrow binding | Stops atuin from triggering, but you still get arrow key behavior instead of scrollback |

---

## The Solution

The working approach has three parts:

```
┌────────────────┐     ┌───────────────────┐     ┌──────────────────┐
│  Hammerspoon   │     │  Terminal (SSH)    │     │  Zellij          │
│  (macOS)       │────►│  passes keystroke  │────►│  (remote server) │
│                │     │  over SSH          │     │                  │
│  Scroll wheel  │     │                    │     │  Alt+Up bound    │
│  → Alt+Up/Down │     │                    │     │  to ScrollUp     │
└────────────────┘     └───────────────────┘     └──────────────────┘
```

1. **Zellij** binds `Alt+Up` and `Alt+Down` to `ScrollUp` and `ScrollDown` in locked mode
2. **Hammerspoon** on the Mac intercepts scroll wheel events when a terminal app is focused and converts them to `Alt+Up`/`Alt+Down` keystrokes
3. The keystrokes travel through SSH to Zellij, which handles them as scroll commands

---

## Part 1: Zellij Configuration

Add `Alt+Up` and `Alt+Down` bindings to your locked mode in `~/.config/zellij/config.kdl`:

```kdl
keybinds clear-defaults=true {
    locked {
        bind "Ctrl g" { SwitchToMode "Normal"; }
        // Scroll wheel support: Hammerspoon sends Alt+Up/Down from Mac
        bind "Alt Up" { ScrollUp; }
        bind "Alt Down" { ScrollDown; }
    }

    // ... rest of your keybinds ...
}
```

If you don't use `clear-defaults=true`, you can add these bindings to whatever mode is your default. The key requirement is that they're active in the mode Zellij is in when you're at the shell prompt.

**Important settings** that should also be in your config:

```kdl
mouse_mode true
scroll_buffer_size 100000  // 100k lines of scrollback per pane
```

Restart Zellij or detach and reattach for the new config to take effect.

---

## Part 2: Hammerspoon on macOS

### Install

```bash
brew install --cask hammerspoon
open -a Hammerspoon
```

On first launch, grant **Accessibility permissions** when prompted:
- System Settings → Privacy & Security → Accessibility → Hammerspoon ✓

Add Hammerspoon to login items so it starts at boot:
- System Settings → General → Login Items → + → Hammerspoon

### Configuration

Create `~/.hammerspoon/init.lua`:

```lua
-- ============================================================================
-- Hammerspoon: Scroll wheel -> Alt+Up/Down for Zellij scrollback
-- ============================================================================
-- GLOBAL variables prevent Lua GC from killing the event tap
-- Return replacement events as table (2nd return value) instead of :post()
-- This keeps the callback fast and avoids macOS tapDisabledByTimeout

require("hs.ipc")

-- Track frontmost app via watcher (cheap, runs only on app switch)
inTerminal = false

appWatcher = hs.application.watcher.new(function(name, eventType, app)
    if eventType == hs.application.watcher.activated then
        local bid = app and app:bundleID() or ""
        inTerminal = (bid == "com.mitchellh.ghostty" or bid == "com.github.wez.wezterm")
    end
end)
appWatcher:start()

-- Set initial state
do
    local front = hs.application.frontmostApplication()
    if front then
        local bid = front:bundleID() or ""
        inTerminal = (bid == "com.mitchellh.ghostty" or bid == "com.github.wez.wezterm")
    end
end

-- The event tap callback returns replacement events as 2nd return value
-- This is non-blocking (events posted AFTER callback returns)
scrollToZellij = hs.eventtap.new({hs.eventtap.event.types.scrollWheel}, function(event)
    if not inTerminal then return false end

    local delta = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
    if delta == 0 then return false end

    local key = delta > 0 and "up" or "down"

    -- Return true (consume event) + replacement key events
    return true, {
        hs.eventtap.event.newKeyEvent({"alt"}, key, true),
        hs.eventtap.event.newKeyEvent({"alt"}, key, false),
    }
end)
scrollToZellij:start()

-- Watchdog: re-enable tap if macOS kills it
scrollWatchdog = hs.timer.doEvery(5, function()
    if scrollToZellij and not scrollToZellij:isEnabled() then
        scrollToZellij:start()
    end
end)

hs.alert.show("Zellij scroll active", 2)
```

Restart Hammerspoon after saving: click the Hammerspoon menu bar icon → Reload Config, or run `killall Hammerspoon && open -a Hammerspoon`.

### Why this specific pattern matters

Getting Hammerspoon event taps to work reliably with scroll wheel events requires understanding three failure modes:

**1. Lua garbage collection kills the tap**

If you declare the event tap as `local`, Lua's garbage collector will destroy the underlying `CGEventTap` after some time (30-90 minutes). The tap silently stops working.

```lua
-- BAD: local variable gets garbage collected
local scrollTap = hs.eventtap.new(...)

-- GOOD: global variable persists forever
scrollToZellij = hs.eventtap.new(...)
```

This is documented in Hammerspoon issues [#1406](https://github.com/Hammerspoon/hammerspoon/issues/1406), [#1103](https://github.com/Hammerspoon/hammerspoon/issues/1103), [#1859](https://github.com/Hammerspoon/hammerspoon/issues/1859), and [#3294](https://github.com/Hammerspoon/hammerspoon/issues/3294).

**2. macOS kills slow callbacks (`tapDisabledByTimeout`)**

macOS automatically disables any `CGEventTap` whose callback takes too long to return. If you call `hs.eventtap.keyStroke()` or `:post()` inside the callback, the synchronous delay (200ms+ per keystroke) triggers the timeout.

```lua
-- BAD: blocks the callback with synchronous key events
return true, function()
    hs.eventtap.keyStroke({"alt"}, "up")  -- 200ms blocking!
end

-- GOOD: return events as table (posted by C code AFTER callback returns)
return true, {
    hs.eventtap.event.newKeyEvent({"alt"}, key, true),
    hs.eventtap.event.newKeyEvent({"alt"}, key, false),
}
```

The second return value is a table of events that Hammerspoon's C code posts *after* the callback returns, keeping the callback fast.

**3. Checking frontmost app on every event is expensive**

`hs.application.frontmostApplication()` is a heavyweight call. With smooth scrolling generating dozens of events per second, calling it on every scroll event can make the callback too slow. Use an app watcher instead:

```lua
-- BAD: expensive call on every scroll event
local app = hs.application.frontmostApplication()

-- GOOD: cheap boolean check; app watcher updates it asynchronously
if not inTerminal then return false end
```

**4. The watchdog timer is insurance**

Even with all the above, macOS can occasionally kill the tap (especially after sleep/wake cycles). The 5-second watchdog timer re-enables it automatically:

```lua
scrollWatchdog = hs.timer.doEvery(5, function()
    if scrollToZellij and not scrollToZellij:isEnabled() then
        scrollToZellij:start()
    end
end)
```

### Adding more terminal apps

To support additional terminal emulators, add their bundle IDs to both the watcher and the initial state check:

```lua
-- Find an app's bundle ID:
-- osascript -e 'id of app "AppName"'
-- or: mdls -name kMDItemCFBundleIdentifier /Applications/AppName.app

inTerminal = (bid == "com.mitchellh.ghostty"
           or bid == "com.github.wez.wezterm"
           or bid == "com.googlecode.iterm2")
```

---

## Part 3: Atuin Guard

If you use [atuin](https://atuin.sh/) for shell history, add `--disable-up-arrow` so that any stray arrow key events (before Hammerspoon intercepts them, or from other input methods) don't trigger the full-screen history TUI:

In `~/.zshrc`:

```bash
eval "$(atuin init zsh --disable-up-arrow)"
```

You can still access atuin search with `Ctrl+R`. This just unbinds the up arrow trigger.

---

## WezTerm Native Alternative

WezTerm has a `mouse_bindings` feature that can theoretically handle this without Hammerspoon. The config would map scroll wheel events in alternate screen mode to keystrokes:

```lua
config.mouse_bindings = {
  {
    event = { Down = { streak = 1, button = { WheelUp = 1 } } },
    mods = 'NONE',
    alt_screen = true,
    mouse_reporting = true,
    action = wezterm.action_callback(function(window, pane)
      window:perform_action(act.SendKey { key = 'UpArrow', mods = 'ALT' }, pane)
    end),
  },
  {
    event = { Down = { streak = 1, button = { WheelDown = 1 } } },
    mods = 'NONE',
    alt_screen = true,
    mouse_reporting = true,
    action = wezterm.action_callback(function(window, pane)
      window:perform_action(act.SendKey { key = 'DownArrow', mods = 'ALT' }, pane)
    end),
  },
}
```

**Key details:**

- `alt_screen = true` restricts it to alternate screen mode (where Zellij runs)
- `mouse_reporting = true` is required because Zellij enables mouse reporting
- `wezterm.action_callback` wrapping is required because direct `act.SendKey` in mouse bindings [silently fails](https://github.com/wezterm/wezterm/issues/5230) (known WezTerm bug)

In our testing this didn't work reliably. The Hammerspoon approach is more dependable, and it works regardless of which terminal emulator you use.

---

## Tuning Scroll Speed

The Hammerspoon config sends one `Alt+Up` or `Alt+Down` per scroll event. With smooth scrolling (BetterMouse, trackpad), each physical scroll gesture can generate many events with varying delta values.

To adjust sensitivity, you can accumulate deltas and only fire keystrokes past a threshold:

```lua
-- Replace the simple scrollToZellij callback with this:
local scrollAccum = 0
local SCROLL_THRESHOLD = 3  -- higher = less sensitive

scrollToZellij = hs.eventtap.new({hs.eventtap.event.types.scrollWheel}, function(event)
    if not inTerminal then return false end

    local delta = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
    if delta == 0 then return false end

    scrollAccum = scrollAccum + delta

    if scrollAccum >= SCROLL_THRESHOLD then
        scrollAccum = 0
        return true, {
            hs.eventtap.event.newKeyEvent({"alt"}, "up", true),
            hs.eventtap.event.newKeyEvent({"alt"}, "up", false),
        }
    elseif scrollAccum <= -SCROLL_THRESHOLD then
        scrollAccum = 0
        return true, {
            hs.eventtap.event.newKeyEvent({"alt"}, "down", true),
            hs.eventtap.event.newKeyEvent({"alt"}, "down", false),
        }
    end

    return true  -- consume event but don't emit keys yet
end)
```

| `SCROLL_THRESHOLD` | Behavior |
|:--------------------|:---------|
| 1 | Very sensitive; every tiny scroll moves a line |
| 3 | Moderate; smooth scrolling feels natural |
| 5 | Coarse; each scroll gesture moves fewer lines |
| 10 | Very coarse; requires deliberate scrolling |

---

## Troubleshooting

### Scroll does nothing

| Check | Solution |
|:------|:---------|
| Hammerspoon not running | Look for icon in menu bar; `open -a Hammerspoon` |
| Accessibility permissions | System Settings → Privacy & Security → Accessibility → Hammerspoon ✓ |
| Wrong terminal bundle ID | Run `osascript -e 'id of app "YourTerminal"'` and add to config |
| Zellij config not loaded | Detach (`Ctrl+G`, `d`) and reattach to pick up new config |

### Scroll works briefly then stops

This is the `tapDisabledByTimeout` problem. Ensure:

1. All Hammerspoon variables are **global** (no `local` keyword)
2. You're returning events as a **table** (second return value), not calling `:post()` or `keyStroke()`
3. The **watchdog timer** is active (re-enables the tap every 5 seconds)

### Scroll direction is inverted

Swap the direction check:

```lua
-- Original: delta > 0 = up
local key = delta > 0 and "up" or "down"

-- Inverted: delta > 0 = down
local key = delta > 0 and "down" or "up"
```

### Atuin still opens on scroll

Verify atuin was initialized with `--disable-up-arrow`:

```bash
grep atuin ~/.zshrc
# Should show: eval "$(atuin init zsh --disable-up-arrow)"
```

Reload your shell: `exec zsh`

### Scrollback exits immediately

When you enter Zellij scrollback mode, pressing any non-scroll key exits it. With the `Alt+Up`/`Alt+Down` approach in locked mode, you stay in normal shell mode while scrolling. If you want to enter full scrollback mode (with search via `/`), use `Ctrl+G`, `s`.

To exit scrollback mode: press `Esc` or `Enter`.

---

## Why Not Other Approaches

### Why not Karabiner-Elements?

Karabiner-Elements (free, popular macOS key remapper) cannot intercept scroll wheel events. Its `basic` manipulators only handle `key_code`, `consumer_key_code`, and `pointing_button` — not scroll events. Despite being installed and having the right permissions, it's simply the wrong tool for this job.

### Why not BetterTouchTool?

[BetterTouchTool](https://folivora.ai/) ($22) can map scroll wheel to keystrokes per-app through its GUI. It handles `CGEventTap` management internally and is generally more stable than Hammerspoon for this use case. If you already own it, it's a viable alternative to Hammerspoon.

### Why not fix it in Zellij?

The Zellij project is aware of this issue ([#3941](https://github.com/zellij-org/zellij/issues/3941)). Until Zellij properly handles mouse scroll events in its buffer, the Mac-side workaround is the only option.

### Why not tmux?

tmux handles mouse scrolling correctly with `set -g mouse on`. If you're choosing a multiplexer from scratch and scrollback is a priority, tmux works out of the box. Zellij has other advantages (better UI, session management, plugins) that may make the workaround worthwhile.

---

## Setup Checklist

- [ ] Zellij config: `Alt+Up`/`Alt+Down` bound to `ScrollUp`/`ScrollDown` in locked mode
- [ ] Zellij config: `mouse_mode true` and `scroll_buffer_size` set
- [ ] Zellij session restarted (detach + reattach)
- [ ] Hammerspoon installed (`brew install --cask hammerspoon`)
- [ ] Hammerspoon: Accessibility permissions granted
- [ ] Hammerspoon: `~/.hammerspoon/init.lua` created with scroll config
- [ ] Hammerspoon: Added to login items
- [ ] Hammerspoon: Config reloaded (menu bar icon → Reload Config)
- [ ] Atuin: `--disable-up-arrow` added to `~/.zshrc`
- [ ] Shell reloaded (`exec zsh`)
- [ ] Test: Mouse wheel scrolls through terminal output in Zellij

---

## Hardware & Software Tested

| Component | Version |
|:----------|:--------|
| macOS | Sequoia |
| WezTerm | Latest stable |
| Ghostty | 1.3.0 (nightly) |
| Zellij | 0.43.1 |
| Hammerspoon | 1.1.0 |
| Atuin | Latest |
| Mouse | Logitech MX Master 4 |
| BetterMouse | Installed (smooth scrolling) |
| Connection | SSH over 10GbE direct link |

---

*Last updated: February 2026*
