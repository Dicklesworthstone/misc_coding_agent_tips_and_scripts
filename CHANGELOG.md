# Changelog

All notable changes to [misc_coding_agent_tips_and_scripts](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts) are documented here.

This project has no formal versioning or GitHub Releases. There are no tags. Changes are tracked by commit history on the `main` branch. Each entry links directly to its commit on GitHub.

---

## AI Agent Safety

### Destructive Git Command Protection

A Python `PreToolUse` hook for Claude Code that intercepts Bash commands and blocks destructive operations (`git checkout --`, `git reset --hard`, `git clean -f`, `git push --force`, `rm -rf` on non-temp paths) before they execute. Safe variants (`git checkout -b`, `git clean -n`, `rm -rf /tmp/...`) are allowlisted.

**Initial release** (2025-12-17):
- [`9df65ef`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/9df65ef47671f9a06c27a9dd5114cb5432a31164) -- Add files via upload (includes `DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md`)

**`rm -rf` handling update** (2025-12-19):
- [`f9ea4fc`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/f9ea4fcfb213fd13ebda6c37e27d7ab9bcd93499) -- Update rm -rf command handling in safety hooks

**Pattern-matching bug fixes** (2026-01-03):
Six fixes addressing bugs found during fresh-eyes review: case sensitivity, `rm` with separate (`-r -f`) and long (`--recursive --force`) flags, `git restore --staged --worktree` bypass, null/non-string input crashes, `git push origin -f` (flag after remote) bypass.
- [`531e190`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/531e190130e456a8dadcd1da264a8eea223ff7cd) -- Fix case sensitivity and rm flag handling in safety guard
- [`1e7f999`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/1e7f99952c0a9763170aea05bd27516c5516305a) -- Fix additional pattern bugs found during fresh-eyes review
- [`f318867`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/f31886775174b0cd31776c4c980c339453edb651) -- Fix git restore --staged --worktree slipping through safety guard
- [`7b56ea8`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/7b56ea8bfa6b3f6d08e29c0138bc313c1f3bde2a) -- Fix null input crash and add rm separate/long flag patterns
- [`ffc8b2f`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/ffc8b2f62dd359eac6bf045eb30da261e19da54b) -- Fix non-string command crash and git push origin -f bypass

**Absolute path bypass and git clean false positive** (2026-01-05):
- [`d6a61e1`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/d6a61e17d5c2854661ed8dcb0d917f76d0cde307) -- Fix absolute path bypass and git clean dry-run false positive

---

### Post-Compact AGENTS.md Reminder

A bash `SessionStart` hook that detects Claude Code context compaction and injects a reminder to re-read AGENTS.md. Includes a curl-pipe-bash installer (`install-post-compact-reminder.sh`) with template selection.

**v1.1.0** (2026-01-26):
Comprehensive CLI enhancements: `--yes`/`-y` unattended install, `--interactive`/`-i` guided setup, `--template <name>` presets (minimal, detailed, checklist, default), `--show-template`, `--status`/`--check`, `--diff`, `--verbose`/`-V`.
- [`852efff`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/852efff21a39bf9ba3e21d6fdd74137961cf1684) -- feat(post-compact-reminder): Add v1.1.0 with comprehensive CLI enhancements
- [`380cb53`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/380cb5383aa07bc8ec5172f7b7d755611f1f1d75) -- fix(post-compact-reminder): Fix argument order, add missing flags, remove double banner

---

## Gemini CLI Patcher

`fix-gemini-cli-ebadf-crash.sh` -- a curl-pipe-bash patcher for `@google/gemini-cli` bugs. Auto-detects install location (bun/npm/yarn/pnpm/brew/nvm/fnm). All patches are idempotent. Supports `--check`, `--verify`, `--revert`, and `--uninstall` modes.

### Initial release -- Patches 1-4 (2026-02-08)

Two root bugs addressed:

1. **EBADF crash:** `node-pty` native addon throws `Error("ioctl(2) failed, EBADF")` with no `.code` property, but catch blocks only check `err.code === 'ESRCH'`. Patched `shellExecutionService.js` and `AppContainer.js` to also match `err.message?.includes('EBADF')`.
2. **Rate limit surrender:** `DEFAULT_MAX_ATTEMPTS=3`, `maxDelayMs=30s` means Gemini gives up after ~45s. `TerminalQuotaError` bypasses retry entirely. Patched to 1000 attempts with 1-5s delays; quota errors now retry with backoff.

- [`0877bb0`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/0877bb03e2b05b5b3af61e9f639e993ed00f1b1e) -- Add Gemini CLI patcher: fix EBADF crash + aggressive rate-limit retry
- [`ad5068b`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/ad5068bff88a12c6521419ef6c7ebbc44f9a5b92) -- fix: banner alignment, add --uninstall, verify P4
- [`16c6199`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/16c61998ceac55ebef0d99f720c85a9d13069e51) -- fix: P1 revert failure, README file count, header comment

### Patch 5 + bun node detection (2026-02-19)

Root-caused why the patcher silently reported "already patched" when zero patches had been applied: bun's `node` wrapper at `~/.bun/bin/node` eats the first positional argument from `process.argv` and exits 0 on uncaught exceptions when stderr is redirected, breaking the `node_contains()` marker detection.

- **Patch 5:** Catches EBADF in `pty.resize()` calls in the shell execution service.
- **Robust node detection:** Patcher now prefers `/usr/bin/node` or system node over bun's broken shim.

- [`b59f7ac`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/b59f7ac4963628ad08a6a867730cd1088cde9076) -- fix: detect bun's broken node wrapper, add Patch 5 for pty.resize() EBADF

### Patches 6-7 (2026-02-23)

- **Patch 6 (dead hook sanitizer):** Parses `~/.gemini/settings.json`, finds hooks whose command binary no longer exists on disk (e.g. expired nix-shell temp dirs), and removes them. Dead hooks cause BeforeTool errors on every tool call.
- **Patch 7 (bun-node PATH fix):** Detects when `~/.bun/bin` precedes `/usr/bin` in the `gmi` wrapper script's PATH. Bun's `node` shim has broken `process.argv` handling and silently swallows exceptions, causing SIGHUP on every PTY child. Patch reorders PATH so real node is found first.

- [`9cea9b9`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/9cea9b963015b94c5529b111ebbdd7a61850fc51) -- feat: add Patch 6 (dead hook sanitizer) and Patch 7 (bun-node PATH fix)

### v0.31.0 retry patch update (2026-02-27)

Updated the retry patch target value from `DEFAULT_MAX_ATTEMPTS = 3` to `DEFAULT_MAX_ATTEMPTS = 10` to match gemini-cli-core v0.31.0 (upstream raised the default from 3 to 10, so the patch's search string needed updating).

- [`4aaac2a`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/4aaac2ab3fbfe3b731f43fc24e0599aae7069f27) -- fix: update retry patch for gemini-cli-core v0.31.0 (DEFAULT_MAX_ATTEMPTS 3->10)

### v0.34.0 compatibility (2026-03-18)

Tracked v0.34.0 code reorganization: the resize `useEffect` that triggers the EBADF crash moved from `AppContainer.js` to `ShellToolMessage.js`. Also hardened Patch 7 against `set -e` abort when the node detection step fails.

- [`3ca5459`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/3ca5459606e44b4b2f815d64b21e60cec0e0a0ae) -- fix: update Gemini CLI fix script for v0.34.0 (ShellToolMessage.js replaces AppContainer.js)
- [`25d8243`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/25d8243a33f8a40cdf0b8e69320a3415c7452bb4) -- fix: prevent set -e from aborting script on Patch 7 node failure

---

## Encrypted GitHub Issues

`gh-issue-decrypt` -- a dual-purpose CLI tool for submitting and receiving encrypted security reports through public GitHub issues using age public-key encryption (X25519, Curve25519 ECDH).

**Sender workflow:** `--encrypt PUBKEY` encrypts stdin; `--submit OWNER/REPO` creates the encrypted issue directly via `gh` CLI.

**Receiver workflow:** `gh-issue-decrypt OWNER/REPO` scans all open issues for `[enc:age]` armored blocks and decrypts with a local identity key.

**Agent integration:** `--json` mode produces clean JSON lines; running with no arguments prints a full interactive guide for agents. Claude Code skill added under `skills/reporting-sensitive-encrypted-gh-issues/`.

Auto-installs age on first use across apt, dnf, pacman, apk, zypper, nix, Homebrew, MacPorts, and GitHub binary fallback.

**Initial release** (2026-03-18):
- [`81babe1`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/81babe1f14331ea4f98fbec7345c28d7137efda6) -- feat: add gh-issue-decrypt -- encrypted GitHub Issues via age (X25519)

**Documentation and GitHub Pages** (2026-03-18):
- [`1463119`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/1463119fcbfebfea48a713df8827f7cb4fc9d4b7) -- docs: add "Encrypted GitHub Issues" article to README
- [`dfe4bbe`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/dfe4bbed4a4348cc4dd625aef9ce16ffc294fdbf) -- docs: add exported session transcript of building the system
- [`a108207`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/a1082071ebc13a356926d6ee11e3bbe362f66266) -- docs: link session transcript from article, enable GitHub Pages
- [`55bc57f`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/55bc57f105fb9dcc570e42b7b44f79ca6a85db21) -- style: de-slopify the Encrypted GitHub Issues article
- [`468a5d9`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/468a5d9e6be6f886200c0bfb39bea1bd6878a92d) -- fix: add .nojekyll to bypass Jekyll processing for GitHub Pages
- [`4a0e6c3`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/4a0e6c326563078cebb0f97e7e73aae6f28f019f) -- fix: correct session transcript message count (19 human turns, not 577)

**Session transcript cleanup** (2026-03-18):
- [`454d9a0`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/454d9a08bae439a64683a3ab670c387894e369e9) -- remove session transcript (contained proprietary content)
- [`63e7986`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/63e7986a3e1d7cbc78db22d79147fd46104ed5f2) -- restore session transcript with all proprietary content removed

**filter-repo corruption recovery** (2026-03-18):
- [`c0add09`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/c0add097d34cc154131d19fa5b768e2665546ea5) -- fix: restore gh-issue-decrypt script (filter-repo had corrupted it with HTML content)

---

## Claude Code Tooling

### Mirror Claude Code Skills

`mirror_cc_skills` -- syncs Claude Code skills from a project's `.claude/skills/` to the global `~/.claude/skills/` directory using rsync. Default mode adds/updates only; `--sync` mode does full sync with automatic timestamped backup; `--dry-run` previews changes. Auto-installs [gum](https://github.com/charmbracelet/gum) for prettier output.

**Initial release** (2026-01-17):
- [`5edda67`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/5edda67f7d329c1a0fe665b74718a7d4b0eacea3) -- Add mirror_cc_skills for syncing skills to global ~/.claude/skills
- [`06f5c0e`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/06f5c0e6a8f4cbe7f12314ea225bf482e9b0f44b) -- Fix empty skills list display in mirror_cc_skills

**filter-repo corruption recovery** (2026-03-18):
- [`ab3a22c`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/ab3a22cf3637817265c88ae87bdc32e8f3f75e05) -- fix: restore mirror_cc_skills (also corrupted by filter-repo)

### Claude Code MCP Config Fix

`FIX_CLAUDE_CODE_MCP_CONFIG.md` with embedded `fix_cc_mcp` script that recovers mcp-agent-mail and morph-mcp server configs in ~2 seconds instead of running the full installer (~60 seconds). Auto-discovers bearer token from `MCP_AGENT_MAIL_TOKEN` env var, `.env` file, or existing `claude.json`.

- [`846a6f5`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/846a6f551f63d4536fd781b465fbdc6415308fab) -- Add fix_cc_mcp script documentation for quick MCP config recovery (2026-01-13)

### Claude Code Native Install Fix

Troubleshooting guide for when `claude --version` shows the old version after native install. Covers PATH ordering between `~/.local/bin/claude` and stale `~/.bun/bin/claude` symlinks.

- [`9df65ef`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/9df65ef47671f9a06c27a9dd5114cb5432a31164) -- Add files via upload (includes `SETTING_UP_CLAUDE_CODE_NATIVE.md`) (2025-12-17)
- [`82ab40a`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/82ab40a74f50704c35b66f5351264ea77f019617) -- Update troubleshooting steps for Claude Code installation (2025-12-18)

---

## Terminal Customization

### WezTerm Persistent Remote Sessions

Guide for remote terminal sessions that survive Mac sleep, reboot, or power loss using WezTerm's native multiplexing with `wezterm-mux-server` running on remote servers via systemd.

- [`819c649`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/819c649bb473166d431d712aa25152846b0fd9fd) -- Add guides for WezTerm mux, Vercel credits, Vault HA, and DevOps CLIs (2026-01-08)

### WezTerm Mux Tuning for Agent Swarms

Guide and script (`wezterm-mux-tune.sh`) for tuning `wezterm-mux-server` when running 20+ AI coding agents simultaneously. Uses linear interpolation based on actual RAM for setting `scrollback_lines`, `mux_output_parser_buffer_size`, `coalesce_delay_ms`, prefetch rate, and cache sizes. Includes emergency session rescue procedure using `reptyr`.

- [`27194a4`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/27194a46a729f03fac5d421fec7985e119f1a8a7) -- feat(wezterm-mux): Add performance tuning guide and script for agent swarms (2026-01-26)

### Host-Aware Terminal Color Themes

Guide for color-coding terminal connections by hostname using OSC escape sequences (Ghostty) or Lua (WezTerm), preventing running commands on the wrong server.

- [`78600a4`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/78600a4d642812e818dea48e81da2bd7d6fcf562) -- Add host-aware terminal color themes guide (2026-01-05)
- [`cc77df9`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/cc77df9b9019bed4cc98b8534cfc084def1d0bc1) -- Fix ASCII diagram alignment in host-aware color themes guide (2026-01-05)

### Ghostty Terminfo for Remote Machines

One-liner fix for numpad Enter sending `[57414u` garbage when SSH'd from Ghostty. Pushes the `xterm-ghostty` terminfo to remote servers.

- [`8aac6f3`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/8aac6f317c32fe9050910858a74380b2fe8fef3d) -- Add guides for Ghostty terminfo, NFS auto-mount, and 10GbE direct link (2026-01-07)

### Doodlestein Punk Theme for Ghostty

A cyberpunk color scheme for the Ghostty terminal emulator featuring deep space black backgrounds with electric neon accents.

- [`b7e372c`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/b7e372cf81214fe52357f014483fafb57e6cb046) -- Add Doodlestein Punk theme for Ghostty (2026-01-24)

### Zellij Scroll Wheel Fix

Three-part workaround for Zellij bug [#3941](https://github.com/zellij-org/zellij/issues/3941) where the mouse scroll wheel sends arrow keys instead of scrolling the terminal buffer over SSH:

1. Zellij `Alt+Up`/`Alt+Down` keybinds for scrollback
2. Hammerspoon event tap on macOS to translate scroll wheel to Alt key combos
3. atuin `--disable-up-arrow` to prevent scroll triggering shell history

Covers Hammerspoon gotchas: GC killing event taps via `local` variables, `tapDisabledByTimeout`, and expensive callback performance.

- [`e489efa`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/e489efaab943ee03dde0d320999bd8c65986826f) -- Add guide: Mouse wheel scrollback in Zellij over SSH (2026-02-10)

---

## macOS Hardware

### MX Master Thumbwheel Tab Switching

Guide for repurposing the Logitech MX Master horizontal thumbwheel for tab switching across terminals, editors, and browsers using BetterMouse ($10).

- [`9fe495a`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/9fe495a0037760695409c164dbf33cb5c77d92b8) -- Add MX Master thumbwheel tab switching guide (2026-01-05)
- [`7949022`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/794902219044fc5025946a176278901c0e23735f) -- Fix inaccurate BetterMouse checkbox terminology (2026-01-05)
- [`21f38bd`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/21f38bda69e08da6fd13f89123d5410cd54518f9) -- Add keyboard symbol reference and fix ASCII diagram alignment (2026-01-05)

### BetterMouse Config Tool

Standalone PEP 723 UV-compatible Python tool (`bettermouse_config.py`) for exporting and importing BetterMouse settings as JSON.

- [`19c7140`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/19c714024e4d4e57da8b5b036a1e13ff062b41af) -- Replace BetterMouse config script with PEP 723 UV-compatible Python tool (2026-01-05)
- [`d0237f3`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/d0237f31cd5c9e2a5e8d185e148ac9651a32920a) -- Extract BetterMouse config tool to standalone script (2026-01-05)
- [`7f996c4`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/7f996c448992ff8d6f76894b247036e929da8f94) -- Add type guard in gesture parsing to prevent crash (2026-01-05)

---

## Remote Development

### macOS NFS Auto-Mount

Auto-mount remote Linux dev server directories on macOS at boot with LaunchDaemon, exponential backoff retry, and optional synthetic firmlink at `/dev/projects`.

- [`8aac6f3`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/8aac6f317c32fe9050910858a74380b2fe8fef3d) -- Add guides for Ghostty terminfo, NFS auto-mount, and 10GbE direct link (2026-01-07)

### Budget 10GbE Direct Link

Connect Mac directly to Linux workstation with 10GbE for ~$90 total (IOCREST Thunderbolt adapter + Cat6), achieving 800+ MB/s transfers. Also covers SHA-256 verified file transfers, clipboard sync, remote display wake-up, and AI agent aliases.

- [`8aac6f3`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/8aac6f317c32fe9050910858a74380b2fe8fef3d) -- Add guides for Ghostty terminfo, NFS auto-mount, and 10GbE direct link (2026-01-07)

### Moonlight Streaming Configuration

Setup for streaming from a Linux workstation (Hyprland/Wayland, dual RTX 4090) to a Mac client using Moonlight with AV1 encoding via Sunshine/NVENC.

- [`9df65ef`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/9df65ef47671f9a06c27a9dd5114cb5432a31164) -- Add files via upload (includes `MOONLIGHT_CONFIG_DOC.md`) (2025-12-17)

---

## Platform Guides

### Reducing Vercel Build Credits

Use the Vercel REST API to disable automatic deployments and deploy only when ready, preventing Pro plan credit burn from webhook-triggered builds on every push.

- [`819c649`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/819c649bb473166d431d712aa25152846b0fd9fd) -- Add guides for WezTerm mux, Vercel credits, Vault HA, and DevOps CLIs (2026-01-08)

### DevOps CLI Tools

Installation, authentication, and common commands for `gh`, `vercel`, `wrangler`, `gcloud`, and `supabase`. Includes AGENTS.md blurbs with placeholders for project-specific values.

- [`819c649`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/819c649bb473166d431d712aa25152846b0fd9fd) -- Add guides for WezTerm mux, Vercel credits, Vault HA, and DevOps CLIs (2026-01-08)

---

## Infrastructure

### HashiCorp Vault HA Cluster

3-node highly available secrets manager using Integrated Raft consensus. Covers initialization with Shamir's Secret Sharing, unsealing, peer joining, and health checks.

- [`819c649`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/819c649bb473166d431d712aa25152846b0fd9fd) -- Add guides for WezTerm mux, Vercel credits, Vault HA, and DevOps CLIs (2026-01-08)

---

## Beads Setup

Guide for fixing `fatal: 'main' is already checked out` errors when using Beads git worktree sync. Solution: create a dedicated `beads-sync` branch.

- [`9df65ef`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/9df65ef47671f9a06c27a9dd5114cb5432a31164) -- Add files via upload (includes `BEADS_SETUP.md`) (2025-12-17)

---

## Repository Meta

### README

Created via PR [#1](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/pull/1) (`copilot/create-good-readme`) with quick reference table and guide navigation. Updated over time as new guides and scripts were added.

- [`3639e29`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/3639e293bd80142874f927905efbd286d0822b2d) -- Create comprehensive README.md with guide summaries and navigation (2025-12-17)
- [`c3e93ed`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/c3e93ed5c3c8d1cd2476efbe9b61120776cfecbc) -- Merge pull request #1 (2025-12-17)
- [`8388856`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/83888565e5fe3483e9f59a7398895aea26ec914b) -- Remove contributing section from README (2025-12-17)
- [`608e098`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/608e0984940a8280eba3ebbe756fd39d727fdeeb) -- Update README with new guide entries and metadata (2026-01-05)
- [`15c45a0`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/15c45a07e91fbbfe36f8878dd4165379223efaa5) -- Improve formatting and structure across all guides (2026-01-05)

### License

MIT with OpenAI/Anthropic Rider restricting use by OpenAI, Anthropic, and their affiliates without express written permission from Jeffrey Emanuel.

- [`38a7a74`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/38a7a7440e91ba1ffee68dade44f5d17fb8ece8b) -- Add MIT License (2026-01-21)
- [`df73122`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/df73122c3a70d2944a09860ec2f63ec452d1140e) -- chore: update license to MIT with OpenAI/Anthropic Rider (2026-02-21)

### Repo hygiene

- [`f3af244`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/f3af244250f399ff9ee603656594008ed9c0b417) -- chore: add .gitignore and .ubsignore for ephemeral files (2026-01-09)
- [`4b395c8`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/4b395c86292360e33355a5df61e10d6868b6b931) -- chore: add GitHub social preview image (1280x640) (2026-02-21)
- [`8ac14ec`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/8ac14ec94164d4a2862959643bfc7444bf240b5e) -- chore: trigger Pages rebuild (2026-03-18)
- [`c568213`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/c5682139840c647d98780b62da25d93ff550ffa0) -- chore: trigger GitHub Pages rebuild to clear cached content (2026-03-18)

### Documentation formatting

- [`b46d95a`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/b46d95a15bf2a494cb608832a66867c5b0e16085) -- Fix placeholder URL in README (2025-12-17)
- [`98d2bcc`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/98d2bcc0f7fdfda6fe1b9fd2188838b4f0108681) -- Remove specific date for better long-term readability (2025-12-17)
- [`120de4b`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/120de4bc5c3c02d0c708ec6c5cb014b6c1958480) -- Fix ASCII diagram alignment: add missing space in tmux box (2026-01-05)
- [`8000e95`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/8000e95aeeaae7164ddbab6631e0bfa1d458eb59) -- fix: Align ASCII diagram box drawing characters (2026-01-26)
- [`4fdaeef`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/4fdaeefd49d0d68c512a629a5d0f20ad13a1a7be) -- docs: Split Quick Start commands into separate copyable blocks (2026-01-26)
- [`9a17dba`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/9a17dba60d6eee286a614b95e784945ee86ac2e4) -- docs: Remove collapsible sections, show all content directly (2026-01-26)
- [`2211d77`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/2211d775f833a6c83f940b653422d0f5b57a1f3d) -- docs: Polish article formatting and upgrade ASCII diagram (2026-01-26)

---

## File Inventory

Current files in the repository (latest commit on main: [`25d8243`](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/commit/25d8243a33f8a40cdf0b8e69320a3415c7452bb4), 2026-03-18):

| File | Category |
|:-----|:---------|
| `DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md` | AI Agent Safety |
| `install-post-compact-reminder.sh` | AI Agent Safety |
| `CLAUDE_CODE_POST_COMPACT_AGENTS_MD_REMINDER.md` | AI Agent Safety |
| `fix-gemini-cli-ebadf-crash.sh` | Gemini CLI Patcher |
| `gh-issue-decrypt` | Security |
| `skills/reporting-sensitive-encrypted-gh-issues/SKILL.md` | Security |
| `mirror_cc_skills` | Claude Code Tooling |
| `FIX_CLAUDE_CODE_MCP_CONFIG.md` | Claude Code Tooling |
| `SETTING_UP_CLAUDE_CODE_NATIVE.md` | Claude Code Tooling |
| `bettermouse_config.py` | macOS Tooling |
| `wezterm-mux-tune.sh` | Terminal Tooling |
| `WEZTERM_MUX_PERFORMANCE_TUNING_FOR_AGENT_SWARMS.md` | Terminal Guide |
| `WEZTERM_PERSISTENT_REMOTE_SESSIONS.md` | Terminal Guide |
| `GUIDE_TO_SETTING_UP_HOST_AWARE_COLOR_THEMES_FOR_GHOSTTY_AND_WEZTERM.md` | Terminal Guide |
| `GHOSTTY_TERMINFO_FOR_REMOTE_MACHINES.md` | Terminal Guide |
| `doodlestein-punk-theme-for-ghostty` | Terminal Theme |
| `ZELLIJ_SCROLL_WHEEL_FIX.md` | Terminal Guide |
| `GUIDE_TO_SETTING_UP_YOUR_MX_MASTER_MOUSE_FOR_DEV_WORK_ON_MAC.md` | Hardware Guide |
| `MACOS_NFS_AUTOMOUNT_FOR_REMOTE_DEV.md` | Remote Dev Guide |
| `BUDGET_10GBE_DIRECT_LINK_AND_REMOTE_PRODUCTIVITY.md` | Remote Dev Guide |
| `MOONLIGHT_CONFIG_DOC.md` | Remote Desktop Guide |
| `REDUCING_VERCEL_BUILD_CREDITS.md` | Platform Guide |
| `GUIDE_TO_DEVOPS_CLI_TOOLS.md` | Platform Guide |
| `HASHICORP_VAULT_HA_CLUSTER_SETUP.md` | Infrastructure Guide |
| `BEADS_SETUP.md` | Setup Guide |
| `cc_session_making_encrypted_gh_issues_system.html` | Session Transcript |
| `gh_og_share_image.png` | Branding |
| `LICENSE` | MIT + OpenAI/Anthropic Rider |
