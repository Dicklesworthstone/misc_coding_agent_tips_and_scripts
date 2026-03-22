# Changelog

All notable changes to [misc_coding_agent_tips_and_scripts](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts) are documented here.

This project has no formal versioning or GitHub Releases. Changes are tracked by commit history on the `main` branch. Each entry links to a representative commit.

---

## 2026-03-18 — Encrypted GitHub Issues + Gemini CLI v0.34.0 Updates

### Encrypted GitHub Issues via age (X25519)

Added `gh-issue-decrypt`, a dual-purpose CLI tool for submitting and receiving encrypted security reports through public GitHub issues using age public-key encryption (X25519, Curve25519 ECDH).

- **Sender workflow:** `--encrypt PUBKEY` encrypts stdin; `--submit OWNER/REPO` creates the encrypted issue directly via `gh` CLI
- **Receiver workflow:** `gh-issue-decrypt OWNER/REPO` scans all open issues for `[enc:age]` armored blocks and decrypts with a local identity key
- **Agent integration:** `--json` mode produces clean JSON lines; running with no arguments prints a full interactive guide for agents
- **Auto-installs** age on first use across apt, dnf, pacman, apk, zypper, nix, Homebrew, MacPorts, and GitHub binary fallback
- Claude Code skill added under `skills/reporting-sensitive-encrypted-gh-issues/`
- Article linked from README with session transcript published to GitHub Pages

Representative commits:
- [`81babe1`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/81babe1f14331ea4f98fbec7345c28d7137efda6) — feat: add gh-issue-decrypt
- [`1463119`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/1463119fcbfebfea48a713df8827f7cb4fc9d4b7) — docs: add article to README
- [`dfe4bbe`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/dfe4bbed4a4348cc4dd625aef9ce16ffc294fdbf) — docs: add session transcript
- [`468a5d9`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/468a5d9e6be6f886200c0bfb39bea1bd6878a92d) — fix: add .nojekyll for GitHub Pages

### Gemini CLI Patcher v0.34.0 Compatibility

Updated the Gemini CLI patcher to track v0.34.0 code reorganization: the resize `useEffect` that triggers the EBADF crash moved from `AppContainer.js` to `ShellToolMessage.js`. Also hardened Patch 7 (bun-node PATH fix) against `set -e` abort when the node detection step fails.

- [`3ca5459`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/3ca5459606e44b4b2f815d64b21e60cec0e0a0ae) — fix: update script for v0.34.0
- [`25d8243`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/25d8243a33f8a40cdf0b8e69320a3415c7452bb4) — fix: prevent set -e from aborting on Patch 7 node failure

### Maintenance

- [`c0add09`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/c0add097d34cc154131d19fa5b768e2665546ea5) — fix: restore gh-issue-decrypt script (filter-repo had corrupted it with HTML content)
- [`ab3a22c`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/ab3a22cf3637817265c88ae87bdc32e8f3f75e05) — fix: restore mirror_cc_skills (also corrupted by filter-repo)

---

## 2026-02-27 — Gemini CLI Patcher: v0.31.0 Retry Patch Update

Updated the retry patch target value from `DEFAULT_MAX_ATTEMPTS = 3` to `DEFAULT_MAX_ATTEMPTS = 10` to match gemini-cli-core v0.31.0 (upstream raised the default from 3 to 10, so the patch's search string needed updating).

- [`4aaac2a`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/4aaac2ab3fbfe3b731f43fc24e0599aae7069f27) — fix: update retry patch for gemini-cli-core v0.31.0

---

## 2026-02-23 — Gemini CLI Patcher: Patch 6 + Patch 7

Added two new patches to the Gemini CLI patcher, bringing the total to 7.

- **Patch 6 (dead hook sanitizer):** Parses `~/.gemini/settings.json`, finds hooks whose command binary no longer exists on disk (e.g. expired nix-shell temp dirs), and removes them. Dead hooks cause BeforeTool errors on every tool call.
- **Patch 7 (bun-node PATH fix):** Detects when `~/.bun/bin` precedes `/usr/bin` in the `gmi` wrapper script's PATH. Bun's `node` shim has broken `process.argv` handling and silently swallows exceptions, causing SIGHUP on every PTY child. Patch reorders PATH so real node is found first.

- [`9cea9b9`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/9cea9b963015b94c5529b111ebbdd7a61850fc51) — feat: add Patch 6 and Patch 7

---

## 2026-02-21 — License and Branding

- **License update:** Replaced plain MIT license with MIT + OpenAI/Anthropic Rider restricting use by OpenAI, Anthropic, and their affiliates without express written permission from Jeffrey Emanuel.
- **Social preview image:** Added 1280x640 GitHub social preview (`gh_og_share_image.png`).

- [`df73122`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/df73122c3a70d2944a09860ec2f63ec452d1140e) — chore: update license
- [`4b395c8`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/4b395c86292360e33355a5df61e10d6868b6b931) — chore: add social preview image

---

## 2026-02-19 — Gemini CLI Patcher: Patch 5 + Bun Node Detection

Root-caused why the patcher was silently reporting "already patched" when zero patches had been applied: bun's `node` wrapper at `~/.bun/bin/node` eats the first positional argument from `process.argv` and exits 0 on uncaught exceptions when stderr is redirected. This broke the `node_contains()` marker detection.

- **Patch 5 (pty.resize EBADF):** Catches EBADF in `pty.resize()` calls in the shell execution service.
- **Robust node detection:** Patcher now prefers `/usr/bin/node` or system node over bun's broken shim.

- [`b59f7ac`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/b59f7ac4963628ad08a6a867730cd1088cde9076) — fix: detect bun's broken node wrapper, add Patch 5

---

## 2026-02-10 — Zellij Scroll Wheel Fix Guide

Added a comprehensive guide documenting the Zellij scroll wheel bug (#3941) and the working three-part workaround:

1. Zellij `Alt+Up`/`Alt+Down` keybinds for scrollback
2. Hammerspoon event tap on macOS to translate scroll wheel to Alt key combos
3. atuin `--disable-up-arrow` to prevent scroll triggering shell history

Covers Hammerspoon gotchas: GC killing event taps via `local` variables, `tapDisabledByTimeout`, and expensive callback performance.

- [`e489efa`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/e489efaab943ee03dde0d320999bd8c65986826f) — Add guide: Mouse wheel scrollback in Zellij over SSH

---

## 2026-02-08 — Gemini CLI Patcher (Initial Release)

Added `fix-gemini-cli-ebadf-crash.sh`, a curl-pipe-bash patcher for two bugs in `@google/gemini-cli`:

1. **EBADF crash:** `node-pty` native addon throws `Error("ioctl(2) failed, EBADF")` with no `.code` property, but catch blocks only check `err.code === 'ESRCH'`. Patched `shellExecutionService.js` and `AppContainer.js` to also check `err.message?.includes('EBADF')`.
2. **Rate limit gives up too fast:** `DEFAULT_MAX_ATTEMPTS=3`, `maxDelayMs=30s` means Gemini surrenders after ~45s. `TerminalQuotaError` bypasses retry entirely. Patched to 1000 attempts with 1-5s delays; quota errors now retry with backoff.

Auto-detects install location (bun/npm/yarn/pnpm/brew/nvm/fnm). Supports `--check`, `--verify`, `--revert`, and `--uninstall` modes. All patches are idempotent.

- [`0877bb0`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/0877bb03e2b05b5b3af61e9f639e993ed00f1b1e) — Add Gemini CLI patcher
- [`ad5068b`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/ad5068bff88a12c6521419ef6c7ebbc44f9a5b92) — fix: banner alignment, add --uninstall, verify P4
- [`16c6199`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/16c61998ceac55ebef0d99f720c85a9d13069e51) — fix: P1 revert failure, README file count, header comment

---

## 2026-01-26 — Post-Compact Reminder v1.1.0 + WezTerm Mux Tuning

### Post-Compact Reminder v1.1.0

Major upgrade to `install-post-compact-reminder.sh` with comprehensive CLI enhancements:

- `--yes`/`-y` for unattended installs
- `--interactive`/`-i` guided setup with template selection
- `--template <name>` presets: minimal, detailed, checklist, default
- `--show-template` to display currently installed reminder
- `--status`/`--check` for installation health and version info
- `--diff` to compare installed vs. new version
- `--verbose`/`-V` for debug output

- [`852efff`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/852efff21a39bf9ba3e21d6fdd74137961cf1684) — feat(post-compact-reminder): Add v1.1.0
- [`380cb53`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/380cb5383aa07bc8ec5172f7b7d755611f1f1d75) — fix: argument order, missing flags, double banner

### WezTerm Mux Tuning for Agent Swarms

New guide and script for tuning `wezterm-mux-server` when running 20+ AI coding agents simultaneously. Default configuration overwhelms: buffers overflow, caches thrash, connections time out.

- `WEZTERM_MUX_PERFORMANCE_TUNING_FOR_AGENT_SWARMS.md` with RAM-tiered profiles
- `wezterm-mux-tune.sh` with linear interpolation for any RAM size
- Emergency session rescue procedure using `reptyr`
- Key settings tuned: `scrollback_lines`, `mux_output_parser_buffer_size`, `coalesce_delay_ms`, prefetch rate, cache sizes

- [`27194a4`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/27194a46a729f03fac5d421fec7985e119f1a8a7) — feat(wezterm-mux): Add performance tuning guide and script

### Documentation Polish

- [`4fdaeef`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/4fdaeefd49d0d68c512a629a5d0f20ad13a1a7be) — docs: Split Quick Start commands into separate copyable blocks
- [`9a17dba`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/9a17dba60d6eee286a614b95e784945ee86ac2e4) — docs: Remove collapsible sections, show all content directly
- [`2211d77`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/2211d775f833a6c83f940b653422d0f5b57a1f3d) — docs: Polish article formatting and upgrade ASCII diagram

---

## 2026-01-24 — Doodlestein Punk Theme for Ghostty

Added a cyberpunk color scheme for the Ghostty terminal emulator (`doodlestein-punk-theme-for-ghostty`).

- [`b7e372c`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/b7e372cf81214fe52357f014483fafb57e6cb046) — Add Doodlestein Punk theme for Ghostty

---

## 2026-01-21 — MIT License

Added MIT License to the project.

- [`38a7a74`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/38a7a7440e91ba1ffee68dade44f5d17fb8ece8b) — Add MIT License

---

## 2026-01-17 — Mirror Claude Code Skills Script

Added `mirror_cc_skills`, a script to sync Claude Code skills from a project's `.claude/skills/` to the global `~/.claude/skills/` directory using rsync.

- Default mode: add/update only, never deletes
- `--sync` mode: full sync with automatic timestamped backup
- `--dry-run` for previewing changes
- Auto-installs [gum](https://github.com/charmbracelet/gum) for prettier output

- [`5edda67`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/5edda67f7d329c1a0fe665b74718a7d4b0eacea3) — Add mirror_cc_skills
- [`06f5c0e`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/06f5c0e6a8f4cbe7f12314ea225bf482e9b0f44b) — Fix empty skills list display

---

## 2026-01-13 — Claude Code MCP Config Fix

Added `FIX_CLAUDE_CODE_MCP_CONFIG.md` with a script (`fix_cc_mcp`) that recovers mcp-agent-mail and morph-mcp server configs in ~2 seconds instead of running the full installer (~60 seconds). Auto-discovers bearer token from `MCP_AGENT_MAIL_TOKEN` env var, `.env` file, or existing `claude.json`.

- [`846a6f5`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/846a6f551f63d4536fd781b465fbdc6415308fab) — Add fix_cc_mcp script documentation

---

## 2026-01-09 — Repo Hygiene

Added `.gitignore` and `.ubsignore` for ephemeral files (build artifacts, perf data, sqlite, etc.).

- [`f3af244`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/f3af244250f399ff9ee603656594008ed9c0b417) — chore: add .gitignore and .ubsignore

---

## 2026-01-08 — WezTerm, Vercel, Vault HA, and DevOps CLI Guides

Added four new guides in a single commit:

| Guide | File |
|:------|:-----|
| WezTerm persistent remote sessions with mux-server | `WEZTERM_PERSISTENT_REMOTE_SESSIONS.md` |
| Reducing Vercel build credits via API | `REDUCING_VERCEL_BUILD_CREDITS.md` |
| HashiCorp Vault HA cluster with Raft storage | `HASHICORP_VAULT_HA_CLUSTER_SETUP.md` |
| DevOps CLI tools (gh, vercel, wrangler, gcloud, supabase) | `GUIDE_TO_DEVOPS_CLI_TOOLS.md` |

- [`819c649`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/819c649bb473166d431d712aa25152846b0fd9fd) — Add guides for WezTerm mux, Vercel credits, Vault HA, and DevOps CLIs

---

## 2026-01-07 — Ghostty Terminfo, NFS Auto-Mount, and 10GbE Guides

Added three new guides:

| Guide | File |
|:------|:-----|
| Ghostty terminfo fix for numpad Enter on remote machines | `GHOSTTY_TERMINFO_FOR_REMOTE_MACHINES.md` |
| macOS NFS auto-mount with LaunchDaemon + exponential backoff | `MACOS_NFS_AUTOMOUNT_FOR_REMOTE_DEV.md` |
| Budget 10GbE direct link ($90 setup, 800+ MB/s transfers) | `BUDGET_10GBE_DIRECT_LINK_AND_REMOTE_PRODUCTIVITY.md` |

- [`8aac6f3`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/8aac6f317c32fe9050910858a74380b2fe8fef3d) — Add guides for Ghostty terminfo, NFS auto-mount, and 10GbE direct link

---

## 2026-01-05 — MX Master Guide, Host-Aware Colors, BetterMouse Config Tool

### New Guides

- **MX Master thumbwheel tab switching:** Configure Logitech MX Master's horizontal scroll wheel for browser tab switching using BetterMouse on macOS.
- **Host-aware terminal color themes:** Color-code terminal connections by hostname using OSC escape sequences (Ghostty) or Lua (WezTerm) to prevent running commands on the wrong server.

### BetterMouse Config Tool

Replaced the inline BetterMouse config script with a standalone PEP 723 UV-compatible Python tool (`bettermouse_config.py`) with type guard for gesture parsing crash prevention.

### Git Safety Guard Hardening

Batch of six fixes to the destructive git command safety guard, addressing bugs found during fresh-eyes review:

- Case-insensitive pattern matching
- Proper `rm` flag handling for separate (`-r -f`) and long (`--recursive --force`) forms
- `git restore --staged --worktree` slipping through
- Null/non-string input crashes
- `git push origin -f` (flag after remote) bypass
- Absolute path bypass and `git clean -n` false positive

Representative commits:
- [`9fe495a`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/9fe495a0037760695409c164dbf33cb5c77d92b8) — Add MX Master guide
- [`78600a4`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/78600a4d642812e818dea48e81da2bd7d6fcf562) — Add host-aware color themes guide
- [`19c7140`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/19c714024e4d4e57da8b5b036a1e13ff062b41af) — Replace BetterMouse config with PEP 723 UV tool
- [`7f996c4`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/7f996c448992ff8d6f76894b247036e929da8f94) — Add type guard in gesture parsing
- [`531e190`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/531e190130e456a8dadcd1da264a8eea223ff7cd) — Fix case sensitivity and rm flag handling
- [`d6a61e1`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/d6a61e17d5c2854661ed8dcb0d917f76d0cde307) — Fix absolute path bypass and git clean dry-run false positive

---

## 2026-01-03 — Git Safety Guard Bug Fixes

Multiple pattern-matching fixes for the destructive git command guard. See 2026-01-05 entry above for the complete list of issues addressed.

- [`1e7f999`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/1e7f99952c0a9763170aea05bd27516c5516305a) — Fix additional pattern bugs found during fresh-eyes review
- [`f318867`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/f31886775174b0cd31776c4c980c339453edb651) — Fix git restore --staged --worktree slipping through
- [`7b56ea8`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/7b56ea8bfa6b3f6d08e29c0138bc313c1f3bde2a) — Fix null input crash and add rm separate/long flag patterns
- [`ffc8b2f`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/ffc8b2f62dd359eac6bf045eb30da261e19da54b) — Fix non-string command crash and git push origin -f bypass

---

## 2025-12-19 — Safety Hook Update

Updated `rm -rf` command handling in safety hooks.

- [`f9ea4fc`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/f9ea4fcfb213fd13ebda6c37e27d7ab9bcd93499) — Update rm -rf command handling in safety hooks

---

## 2025-12-17 — Initial Release

Initial upload of the repository with four guides and the destructive git command safety guard.

### Guides

| Guide | File |
|:------|:-----|
| Destructive Git Command Protection (PreToolUse hook for Claude Code) | `DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md` |
| Claude Code Native Install Fix | `SETTING_UP_CLAUDE_CODE_NATIVE.md` |
| Moonlight Streaming Configuration (Hyprland/Wayland + AV1) | `MOONLIGHT_CONFIG_DOC.md` |
| Beads Setup (git worktree sync fix) | `BEADS_SETUP.md` |

### README

Created via PR #1 (`copilot/create-good-readme`), with quick reference table and guide navigation.

Representative commits:
- [`9df65ef`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/9df65ef47671f9a06c27a9dd5114cb5432a31164) — Add files via upload (initial guides)
- [`c3e93ed`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/c3e93ed5c3c8d1cd2476efbe9b61120776cfecbc) — Merge PR #1: comprehensive README
- [`82ab40a`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/82ab40a74f50704c35b66f5351264ea77f019617) — Update troubleshooting steps for Claude Code installation

---

## File Inventory

Current files in the repository as of 2026-03-18 (latest commit [`25d8243`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/25d8243a33f8a40cdf0b8e69320a3415c7452bb4)):

| File | Category |
|:-----|:---------|
| `DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md` | AI Agent Safety |
| `install-post-compact-reminder.sh` | AI Agent Safety |
| `fix-gemini-cli-ebadf-crash.sh` | AI Agent Tooling |
| `gh-issue-decrypt` | Security |
| `mirror_cc_skills` | Claude Code Tooling |
| `bettermouse_config.py` | macOS Tooling |
| `wezterm-mux-tune.sh` | Terminal Tooling |
| `doodlestein-punk-theme-for-ghostty` | Terminal Theme |
| `GUIDE_TO_SETTING_UP_HOST_AWARE_COLOR_THEMES_FOR_GHOSTTY_AND_WEZTERM.md` | Terminal Guide |
| `GUIDE_TO_SETTING_UP_YOUR_MX_MASTER_MOUSE_FOR_DEV_WORK_ON_MAC.md` | Hardware Guide |
| `GHOSTTY_TERMINFO_FOR_REMOTE_MACHINES.md` | Terminal Guide |
| `ZELLIJ_SCROLL_WHEEL_FIX.md` | Terminal Guide |
| `WEZTERM_PERSISTENT_REMOTE_SESSIONS.md` | Remote Dev Guide |
| `WEZTERM_MUX_PERFORMANCE_TUNING_FOR_AGENT_SWARMS.md` | Remote Dev Guide |
| `MACOS_NFS_AUTOMOUNT_FOR_REMOTE_DEV.md` | Remote Dev Guide |
| `BUDGET_10GBE_DIRECT_LINK_AND_REMOTE_PRODUCTIVITY.md` | Remote Dev Guide |
| `REDUCING_VERCEL_BUILD_CREDITS.md` | Platform Guide |
| `GUIDE_TO_DEVOPS_CLI_TOOLS.md` | Platform Guide |
| `HASHICORP_VAULT_HA_CLUSTER_SETUP.md` | Infrastructure Guide |
| `MOONLIGHT_CONFIG_DOC.md` | Remote Desktop Guide |
| `SETTING_UP_CLAUDE_CODE_NATIVE.md` | Setup Guide |
| `CLAUDE_CODE_POST_COMPACT_AGENTS_MD_REMINDER.md` | Setup Guide |
| `FIX_CLAUDE_CODE_MCP_CONFIG.md` | Setup Guide |
| `BEADS_SETUP.md` | Setup Guide |
| `LICENSE` | MIT + OpenAI/Anthropic Rider |
