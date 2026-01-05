# Thumbwheel Tab Switching: MX Master Setup for Mac Developers

Transform your Logitech MX Master's underused thumbwheel into an ergonomic tab-switching tool that works across your entire development environment.

---

## TL;DR: Quick Start

If you just want to get this working:

1. **Install [BetterMouse](https://better-mouse.com)** ($10 one-time) and grant accessibility permissions
2. **Configure thumbwheel** in BetterMouse → Buttons tab:
   - Thumbwheel << → `Ctrl+Shift+Left` (displays as `⇧⌃ ←`)
   - Thumbwheel >> → `Ctrl+Shift+Right` (displays as `⇧⌃ →`)
3. **Add keybindings** to your apps (see [Application Configs](#quick-reference-configs) below)
4. **For Chrome**: Add as exception in BetterMouse using `Cmd+Option+Arrow` instead

Read on for the full explanation and rationale.

---

## Table of Contents

- [Why Do This?](#why-do-this)
- [How It Works](#how-it-works)
- [What You'll Need](#what-youll-need)
- [Part 1: Setting Up BetterMouse](#part-1-setting-up-bettermouse)
- [Part 2: Configuring Your Applications](#part-2-configuring-your-applications)
- [Part 3: Handling Special Cases](#part-3-handling-special-cases)
- [Working with Remote Servers](#working-with-remote-servers)
- [Troubleshooting](#troubleshooting)
- [Appendix: Why Ctrl+Shift+Arrow?](#appendix-why-ctrlshiftarrow)
- [Quick Reference Configs](#quick-reference-configs)

---

## Why Do This?

The MX Master's horizontal thumbwheel was designed for scrolling sideways in spreadsheets and timelines. In practice, most developers rarely need horizontal scrolling, but we switch between tabs *constantly*.

Tab switching typically requires awkward keyboard shortcuts like `Cmd+Shift+[`, `Ctrl+Tab`, or clicking tiny tab headers. With this setup, you just scroll the thumbwheel: left for previous tab, right for next tab. Works everywhere.

---

## How It Works

```
Thumbwheel scroll left
        ↓
   BetterMouse intercepts
        ↓
   Emits keystroke: Ctrl+Shift+←
        ↓
   Application receives keystroke
        ↓
   Switches to previous tab
```

BetterMouse doesn't communicate directly with applications. It simply **translates thumbwheel movements into keyboard shortcuts**. Each application then responds to those shortcuts according to its own keybinding configuration.

This works well because:
- Compatible with *any* app that supports custom keybindings
- Completely transparent to applications (they just see keystrokes)
- Allows per-app customization via BetterMouse's exception system

---

## What You'll Need

| Item | Notes |
|------|-------|
| Logitech MX Master mouse | MX Master 3, 3S, or 4 (any with horizontal thumbwheel) |
| macOS | Tested on Sonoma/Sequoia; should work on earlier versions |
| [BetterMouse](https://better-mouse.com) | $10 one-time purchase (no subscription) |
| ~15 minutes | Initial setup time |

> **Note:** I have no affiliation with BetterMouse. It's the best tool I've found for this; Logitech's own software (Logi Options+) cannot map the thumbwheel to arbitrary keyboard shortcuts.

### Keyboard Symbol Reference

This guide uses macOS keyboard symbols. Here's a quick reference:

| Symbol | Mac Key | Windows/Third-Party Keyboard |
|--------|---------|------------------------------|
| `⌃` | Control | Ctrl |
| `⌥` | Option | Alt |
| `⌘` | Command | Windows key (⊞) |
| `⇧` | Shift | Shift |

So `⇧⌃ ←` means **Shift + Control + Left Arrow**, and `⌥⌘ →` means **Option + Command + Right Arrow** (or **Alt + Windows + Right Arrow** on third-party keyboards).

---

## Part 1: Setting Up BetterMouse

### Step 1: Install and Authorize

1. Download from [better-mouse.com](https://better-mouse.com)
2. Move to Applications and launch
3. **Grant accessibility permissions** when prompted:
   - System Settings → Privacy & Security → Accessibility
   - Enable the checkbox for BetterMouse
4. Purchase license ($10) to remove trial limitations

### Step 2: Configure the Thumbwheel

1. Open BetterMouse from the menu bar
2. Go to the **Buttons** tab
3. Scroll down to find the thumbwheel settings:

| Gesture | Action | Click-through | Multi-shot |
|---------|--------|---------------|------------|
| Thumbwheel ↓ | Smart Zoom | ☐ | n/a |
| Thumbwheel << | `⇧⌃ ←` | ☐ | ☐ |
| Thumbwheel >> | `⇧⌃ →` | ☐ | ☐ |

4. **To set the left scroll (Thumbwheel <<):**
   - Click the dropdown next to "Thumbwheel <<"
   - With the dropdown open, press `Ctrl + Shift + Left Arrow` on your keyboard
   - It should display as `⇧⌃ ←`

5. **To set the right scroll (Thumbwheel >>):**
   - Same process: press `Ctrl + Shift + Right Arrow`
   - Should display as `⇧⌃ →`

6. **Important checkbox settings:**
   - **Click-through** (☐): Passes clicks to underlying windows; leave **unchecked** for tab switching
   - **Multi-shot** (☐): Triggers the action repeatedly (rapid-fire); keep this **unchecked** to prevent switching multiple tabs per scroll

### Step 3: Verify It's Working

Open any text editor and scroll the thumbwheel. You should see text selections happening (since `Ctrl+Shift+Arrow` selects words in some contexts). This confirms BetterMouse is sending the keystrokes.

---

## Part 2: Configuring Your Applications

Now we need each application to respond to `Ctrl+Shift+Left/Right` by switching tabs.

### WezTerm

**Config file:** `~/.wezterm.lua`

Add to your `config.keys` table:

```lua
-- Thumbwheel tab switching (via BetterMouse Ctrl+Shift+Arrow)
{
  key = 'LeftArrow',
  mods = 'SHIFT|CTRL',
  action = wezterm.action.ActivateTabRelative(-1),
},
{
  key = 'RightArrow',
  mods = 'SHIFT|CTRL',
  action = wezterm.action.ActivateTabRelative(1),
},
```

**Reload config:** The config auto-reloads, or press `Ctrl+Shift+R` (if you have that binding).

---

### Ghostty

**Config file:** `~/Library/Application Support/com.mitchellh.ghostty/config`

Add these lines:

```ini
# Thumbwheel tab switching (Ctrl+Shift+Arrow via BetterMouse)
keybind = ctrl+shift+left=previous_tab
keybind = ctrl+shift+right=next_tab
```

**Reload config:** Ghostty auto-reloads on save. If not, restart the app.

---

### Zed

**Config file:** `~/.config/zed/keymap.json`

Add this binding block:

```json
[
  {
    "context": "Workspace",
    "bindings": {
      "ctrl-shift-left": "pane::ActivatePrevItem",
      "ctrl-shift-right": "pane::ActivateNextItem"
    }
  }
]
```

**Reload:** Zed auto-reloads keymap changes.

---

### VS Code

**Config file:** `~/Library/Application Support/Code/User/keybindings.json`

Or open via: `Cmd+Shift+P` → "Preferences: Open Keyboard Shortcuts (JSON)"

```json
[
  {
    "key": "ctrl+shift+left",
    "command": "workbench.action.previousEditor"
  },
  {
    "key": "ctrl+shift+right",
    "command": "workbench.action.nextEditor"
  }
]
```

---

### iTerm2

Go to: **Preferences → Keys → Key Bindings → +**

| Setting | Value |
|---------|-------|
| Keyboard Shortcut | `⌃⇧←` (press Ctrl+Shift+Left) |
| Action | Select Menu Item... |
| Menu Item | Window → Select Previous Tab |

Repeat for `⌃⇧→` with "Select Next Tab".

---

## Part 3: Handling Special Cases

### Chrome, Arc, Brave, and Chromium Browsers

These browsers don't easily let you remap `Ctrl+Shift+Arrow` to tab switching. The workaround: use BetterMouse's **per-application exceptions** to send a *different* shortcut to Chrome, one it already understands natively.

#### Setting Up the Chrome Exception

1. Open BetterMouse → **Exceptions** tab
2. Click **+** to add a new exception
3. Navigate to `/Applications` and select **Google Chrome** (or Arc, Brave, etc.)
4. Configure thumbwheel mappings for this exception:

| Gesture | Shortcut | Notes |
|---------|----------|-------|
| Thumbwheel << | `⌥⌘ ←` | Cmd+Option+Left (Chrome's native "previous tab") |
| Thumbwheel >> | `⌥⌘ →` | Cmd+Option+Right (Chrome's native "next tab") |

**Repeat for each Chromium browser** you use (Arc, Brave, Edge, etc.).

#### Alternative: Browser Extension

If you prefer using `Ctrl+Shift+Arrow` universally (including in browsers), install an extension that allows custom keybindings:

- **[Shortkeys](https://chrome.google.com/webstore/detail/shortkeys-custom-keyboard/logpjaacgmcbpdkdchjiaagddngobkck)**: Simple custom shortcuts
- **[Vimium](https://chrome.google.com/webstore/detail/vimium/dbepggeogbaibhgnhhndojpepiihcmeb)**: Full vim-style navigation

---

### Safari

Safari's keyboard shortcuts can be customized via macOS System Settings:

1. System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts
2. Click **+** and select Safari
3. Add these two shortcuts:

| Menu Title | Shortcut |
|------------|----------|
| Show Previous Tab | `⌃⇧←` |
| Show Next Tab | `⌃⇧→` |

**Important:** Menu titles must match *exactly* what appears in Safari's Window menu.

---

### Finder

Finder uses tabs too! Add via System Settings → Keyboard → App Shortcuts:

| Menu Title | Shortcut |
|------------|----------|
| Show Previous Tab | `⌃⇧←` |
| Show Next Tab | `⌃⇧→` |

---

## Working with Remote Servers

A common question: *"Does this work when I'm SSH'd into a server?"*

### Understanding the Layers

When you're working remotely, there are potentially multiple "tab" concepts:

```
┌─────────────────────────────────────────────┐
│  Your Mac                                   │
│  ┌───────────────────────────────────────┐  │
│  │  Terminal App (WezTerm/Ghostty)       │  │
│  │  [Tab 1] [Tab 2] [Tab 3]  ← These     │  │
│  │  ┌─────────────────────────────────┐  │  │
│  │  │  SSH Session                    │  │  │
│  │  │  ┌───────────────────────────┐  │  │  │
│  │  │  │  tmux                     │  │  │  │
│  │  │  │  [Window 1] [Window 2]    │  │  │  │
│  │  │  │  ← Or these              │  │  │  │
│  │  │  └───────────────────────────┘  │  │  │
│  │  └─────────────────────────────────┘  │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### Scenario A: Standard SSH

With a standard SSH connection, the thumbwheel switches your **local terminal's tabs**, not tmux windows. This is usually what you want: one tab per server, and you thumb-scroll between them.

For tmux window navigation, use tmux's own bindings (typically `Ctrl+A` then `n`/`p`).

### Scenario B: WezTerm Multiplexing (Seamless Remote Tabs)

WezTerm has a powerful alternative to tmux: **native multiplexing**. You run `wezterm-mux-server` on the remote machine, and WezTerm connects directly to it.

```lua
-- In ~/.wezterm.lua
config.ssh_domains = {
  {
    name = 'my-server',
    remote_address = 'server.example.com',
    username = 'ubuntu',
    multiplexing = 'WezTerm',  -- The key setting
  },
}
```

**Benefits:**
- Remote tabs appear as native WezTerm tabs
- Thumbwheel switching works identically to local tabs
- Sessions persist through disconnection; reconnecting restores all tabs
- No need to learn tmux keybindings

When you connect to a WezTerm-multiplexed domain, you're essentially opening a window into the remote server's WezTerm instance. The thumbwheel → `Ctrl+Shift+Arrow` → tab switch chain works exactly the same, because WezTerm is handling everything on both ends.

---

## Troubleshooting

### Thumbwheel does nothing

| Check | Solution |
|-------|----------|
| BetterMouse not running | Look for icon in menu bar; relaunch if missing |
| Permissions missing | System Settings → Privacy & Security → Accessibility → BetterMouse ☑ |
| Mapping not set | BetterMouse → Buttons → Verify thumbwheel action is set to a keystroke |
| Mouse not detected | Try unplugging and reconnecting; check BetterMouse device list |

### Works in some apps, not others

| Check | Solution |
|-------|----------|
| App in exception list | BetterMouse → Exceptions → Remove app or fix its mappings |
| App doesn't have keybinding | Add the keybinding per instructions above |
| Keybinding conflict | App may use `Ctrl+Shift+Arrow` for something else; check app's shortcut settings |

### Tab switches multiple times per scroll

| Check | Solution |
|-------|----------|
| Multi-shot enabled | BetterMouse → Buttons → Uncheck "Multi-shot" for thumbwheel gestures |
| Sensitivity too high | BetterMouse → Scroll → Reduce thumbwheel sensitivity |

### Conflict with text selection

In some text editors, `Ctrl+Shift+Arrow` selects words. If this bothers you:
1. Add the app as an exception in BetterMouse
2. Use a different shortcut for that app (e.g., `Cmd+Option+Arrow`)
3. Or remap the editor's word selection to something else

---

## Appendix: Why Ctrl+Shift+Arrow?

Choosing the right shortcut required avoiding conflicts with existing shortcuts. The options considered:

| Shortcut | Why Not |
|----------|---------|
| `Ctrl+Tab` | Browser standard; can't easily remap in Chrome |
| `Cmd+[` / `Cmd+]` | Navigation history in browsers, Xcode, etc. |
| `Cmd+{` / `Cmd+}` | Tab switching in Safari, Terminal.app, but not universal |
| `Cmd+Option+Arrow` | Works in Chrome but not elsewhere by default |
| `Ctrl+Arrow` | Word-by-word cursor movement; too commonly used |
| `Ctrl+Shift+Arrow` | Word selection in *some* apps, but easy to override |

**Ctrl+Shift+Arrow wins because:**
- Few apps use it as an unremappable default
- Easy to bind in most applications
- Doesn't conflict with macOS system shortcuts
- The rare conflicts (word selection) are in apps where you're not switching tabs anyway

---

## Quick Reference Configs

### BetterMouse Global Settings

```
Thumbwheel <<  →  ⇧⌃ ←  (Ctrl+Shift+Left)
Thumbwheel >>  →  ⇧⌃ →  (Ctrl+Shift+Right)
```

### BetterMouse Chrome Exception

```
Thumbwheel <<  →  ⌥⌘ ←  (Cmd+Option+Left)
Thumbwheel >>  →  ⌥⌘ →  (Cmd+Option+Right)
```

### Application Keybindings

<details>
<summary><strong>WezTerm</strong>: <code>~/.wezterm.lua</code></summary>

```lua
{
  key = 'LeftArrow',
  mods = 'SHIFT|CTRL',
  action = wezterm.action.ActivateTabRelative(-1),
},
{
  key = 'RightArrow',
  mods = 'SHIFT|CTRL',
  action = wezterm.action.ActivateTabRelative(1),
},
```
</details>

<details>
<summary><strong>Ghostty</strong>: <code>~/Library/Application Support/com.mitchellh.ghostty/config</code></summary>

```ini
keybind = ctrl+shift+left=previous_tab
keybind = ctrl+shift+right=next_tab
```
</details>

<details>
<summary><strong>Zed</strong>: <code>~/.config/zed/keymap.json</code></summary>

```json
[
  {
    "context": "Workspace",
    "bindings": {
      "ctrl-shift-left": "pane::ActivatePrevItem",
      "ctrl-shift-right": "pane::ActivateNextItem"
    }
  }
]
```
</details>

<details>
<summary><strong>VS Code</strong>: <code>keybindings.json</code></summary>

```json
[
  { "key": "ctrl+shift+left", "command": "workbench.action.previousEditor" },
  { "key": "ctrl+shift+right", "command": "workbench.action.nextEditor" }
]
```
</details>

<details>
<summary><strong>iTerm2</strong></summary>

Preferences → Keys → Key Bindings:
- `⌃⇧←` → Select Menu Item → Window → Select Previous Tab
- `⌃⇧→` → Select Menu Item → Window → Select Next Tab
</details>

<details>
<summary><strong>Safari / Finder</strong>: System Settings</summary>

System Settings → Keyboard → Keyboard Shortcuts → App Shortcuts → +
- Show Previous Tab: `⌃⇧←`
- Show Next Tab: `⌃⇧→`
</details>

---

## Beyond Tab Switching

Once you have BetterMouse configured, consider these other useful mappings:

| Button | Suggested Action |
|--------|------------------|
| Thumb button (back) | Mission Control or App Exposé |
| Thumb button (forward) | Show Desktop or Launchpad |
| Middle click | Close tab (`Cmd+W`) or Paste |
| Gesture button + scroll | Volume control or zoom |

The MX Master has more inputs than most developers use. BetterMouse lets you put them all to work.

---

*Last updated: January 2026*
