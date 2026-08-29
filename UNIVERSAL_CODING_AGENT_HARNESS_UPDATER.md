# Universal Coding Agent (UCA) Harness Updater & Status Dashboard

> **Problem:** Developers and autonomous agent workflows rely on multiple evolving AI coding agent CLIs simultaneously—**Claude Code**, **OpenAI Codex**, **Google Antigravity (AGY)**, **xAI Grok**, and **OMP**. Keeping all harnesses updated manually requires remembering different package managers (`bun`, native self-updaters, npm), leaves versions out of sync, lacks upgrade history visibility, and risks background update collisions across terminal sessions.

**UCA (`uca`)** and **UCAS (`ucas`)** provide a unified, robust multi-agent harness management system with automatic 3-hour background scheduling, Charmbracelet Gum dashboard visualization, version change tracking (`"From version xyz to version abc"`), atomic locking, and health diagnostics.

---

## Quick Start

### One-Liner Install

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-uca.sh?$(date +%s)" | bash
```

Or from a local clone:

```bash
git clone https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts.git
cd misc_coding_agent_tips_and_scripts
./install-uca.sh
```

---

## Key Features

- **Unified Multi-Harness Updates (`uca`)**:
  Sequentially updates Claude Code (`claude update`), OpenAI Codex (`bun install -g @openai/codex@latest`), Google Antigravity (`agy update`), xAI Grok (`grok update`), and OMP (`omp update`).
- **Interactive Status Dashboard (`ucas`)**:
  Renders a visual dashboard featuring a **⭐ Most Recently Updated Harness** highlight, detailed semver changes (`"From version xyz to version abc"`), per-harness health badges, and background timer telemetry.
- **Automated 3-Hour Background Scheduling**:
  - **Linux (systemd)**: Configured as a user-level oneshot service and calendar timer (`00,03,06,09,12,15,18,21:00:00`) with 3-minute randomized jitter and boot persistence.
  - **macOS (launchd)**: Configured as a LaunchAgent (`com.jemanuel.uca.plist`) triggering every 10,800 seconds (3 hours).
- **Installer-Workmanship Robustness**:
  - **Zero External Dependencies & Instant Execution**: 100% pure, lightweight Bash engine (< 2MB memory, ~5ms execution) requiring no Python, Ruby, or heavyweight runtimes.
  - **Dual-Path Output**: Automatically utilizes Charmbracelet Gum when interactive, with seamless ANSI double-line box fallback for pipes and non-TTYs.
  - **Atomic PID Locking**: Prevents concurrent updates from clobbering state files when manual runs collide with background timers, with automatic stale PID recovery.
  - **Zero-Disk-Space Crash Prevention**: Inspects filesystem free capacity prior to running package installs, skipping updates if free disk space is critically low (< 500 MB).
  - **Diagnostic Health Checks (`uca doctor`)**: Tests shell environment, Gum binary, state directory permissions, background service status, disk space safety, and binary paths for all harnesses.
  - **Proxy & Network Resilience**: Inherits `HTTPS_PROXY` / `HTTP_PROXY` and applies timeout safeguards.

---

## Commands & Usage

### 1. Update All Agent Harnesses

```bash
uca
```

Output:
```text
════════════════════════════════════════════════════════════════════════════
 UCA — Universal Coding Agent Harness Updater
 Started at: 2026-08-29 18:18:13
════════════════════════════════════════════════════════════════════════════

  ⟳ Updating Claude Code...         ✔ Claude Code          Up to date (2.1.251) (1.0s)
  ⟳ Updating OpenAI Codex...        ✔ OpenAI Codex         Up to date (0.151.0) (0.3s)
  ⟳ Updating Google Antigravity...  ✔ Google Antigravity   Up to date (1.1.22) (0.2s)
  ⟳ Updating xAI Grok...            ✔ xAI Grok             Up to date (1.0.13) (0.7s)
  ⟳ Updating OMP...                 🎉 OMP                  UPDATED: From version 18.0.0 to version 18.0.11 (1.1s)

────────────────────────────────────────────────────────────────────────────
 Completed in: 3.3s • Status: Completed
 Most Recent Update: OMP (From version 18.0.0 to 18.0.11, 5s ago)
════════════════════════════════════════════════════════════════════════════
```

### 2. View Status Dashboard (`ucas`)

```bash
ucas
```

```text
╭───────────────────────────────────────────────────────────────────────────────────────────────────╮
│ UCA STATUS — Universal Coding Agent Harness Dashboard                                             │
│ Last Full Run: 2m ago (2026-08-29 18:18:13 EDT)                                                   │
│ Background Service: ACTIVE • launchd background service active (every 3 hours / 10800s, exit: 0) │
╰───────────────────────────────────────────────────────────────────────────────────────────────────╯
┌───────────────────────────────────────────────────────────────────────────────────────────────────┐
│ ⭐ MOST RECENTLY UPDATED HARNESS                                                                  │
│ OMP • From version 18.0.0 to version 18.0.11 (2m ago)                                             │
└───────────────────────────────────────────────────────────────────────────────────────────────────┘

 HARNESS BREAKDOWN
────────────────────────────────────────────────────────────────────────────────────────────────────
 Harness               Version     Status          Version Changes                                     Checked     
────────────────────────────────────────────────────────────────────────────────────────────────────
 Claude Code           2.1.251     ✔ Up to date    Up to date at 2.1.251                               2m ago      
 OpenAI Codex          0.151.0     ✔ Up to date    Up to date at 0.151.0                               2m ago      
 Google Antigravity    1.1.22      ✔ Up to date    Up to date at 1.1.22                                2m ago      
 xAI Grok              1.0.13      ✔ Up to date    Up to date at 1.0.13                                2m ago      
 OMP                   18.0.11     ✔ Up to date    From version 18.0.0 to version 18.0.11 (2m ago)     2m ago      
────────────────────────────────────────────────────────────────────────────────────────────────────

 📜 RECENT VERSION CHANGE HISTORY
────────────────────────────────────────────────────────────────────────────────────────────────────
  • 2026-08-29 18:18  OMP                From version 18.0.0 to version 18.0.11
────────────────────────────────────────────────────────────────────────────────────────────────────

 Commands: uca (update all) • ucas (status) • uca <harness> (update one) • uca doctor (health) • uca service install
```

### 3. Update a Specific Harness

```bash
uca omp       # Update only OMP
uca claude    # Update only Claude Code
uca codex     # Update only OpenAI Codex
uca agy       # Update only Google Antigravity
uca grok      # Update only xAI Grok
```

### 4. Run Preflight & Health Diagnostics

```bash
uca doctor
```

Output:
```text
════════════════════════════════════════════════════════════════════════════
 UCA DOCTOR — Harness & Environment Diagnostics
════════════════════════════════════════════════════════════════════════════

  ✔ Python runtime: 3.14.6 (/opt/homebrew/opt/python@3.14/bin/python3.14)
  ✔ Charmbracelet Gum: Found (gum version 0.17.0)
  ✔ State storage: /Users/jemanuel/.local/share/uca (writable=True)
  ✔ 3-Hour Auto-Updater: launchd background service active (every 3 hours / 10800s, last exit: 0)

  Harness Integrity Checks:
    ✔ Claude Code          /Users/jemanuel/.local/bin/claude        Version: 2.1.251
    ✔ OpenAI Codex         /Users/jemanuel/.bun/bin/codex           Version: 0.151.0
    ✔ Google Antigravity   /Users/jemanuel/.local/bin/agy           Version: 1.1.22
    ✔ xAI Grok             /Users/jemanuel/.grok/bin/grok           Version: 1.0.13
    ✔ OMP                  /Users/jemanuel/.bun/bin/omp             Version: 18.0.11

════════════════════════════════════════════════════════════════════════════
```

### 5. Live Interactive Watch Mode (`ucas -w`)

```bash
ucas -w        # Auto-refreshes every 5 seconds
ucas -w 2      # Auto-refreshes every 2 seconds
```

### 6. Inspect Update Logs (`uca logs`)

```bash
uca logs            # View recent update log entries
uca logs --errors   # Filter to errors and warnings only
uca logs --follow   # Live tail update log output
```

### 7. Check Service Status & Reinstall Timer

```bash
uca service status   # Check status of background scheduler
uca service install  # Re-register systemd timer or launchd agent
```

---

## Advanced Capabilities

1. **Post-Update Smoke Test & Verification Guard**:
   Immediately after upgrading each harness, UCA executes an automated smoke test verification pass (`<harness> --help` / `--version`) to confirm the binary didn't break or suffer from runtime corruption. If any harness fails verification, UCA flags it with yellow/red telemetry and records diagnostic details.
2. **Native Desktop & Terminal Notifications**:
   When background auto-updater jobs upgrade any harness to a newer release, UCA dispatches a native desktop notification (`display notification` on macOS, `notify-send` on Linux) detailing the transition (`"From version xyz to version abc"`). When no updates occur, runs stay completely silent.
3. **Parallel Async Version Probing**:
   Using `concurrent.futures.ThreadPoolExecutor`, version inspection queries all 5 agent CLIs in parallel, completing live status discovery in <300ms (`ucas -f`).
4. **Interactive Dashboard Watch Mode**:
   Running `ucas -w` provides a live monitoring HUD showing current versions, latest upgrade pulses, background timer status, and clock telemetry.
5. **Zero-Disk-Space Crash Prevention & Safety Guard**:
   Before downloading tarballs or running package installations, UCA queries filesystem free space across `$HOME`, `/tmp`, and state partitions. If free disk space falls below the safety threshold (default: 500 MB, configurable via `UCA_MIN_DISK_MB` or `--min-disk-mb`), UCA immediately aborts the update run, prevents broken/corrupted installations, alerts the user, and skips background execution to avoid worsening system disk pressure. Override with `--ignore-disk-space`.

---

## Supported Harnesses

| Harness | Primary Binary | Update Mechanism |
|:---|:---|:---|
| **Claude Code** | `~/.local/bin/claude` | `claude update` |
| **OpenAI Codex** | `~/.bun/bin/codex` | `bun install -g @openai/codex@latest` (fallback `codex update`) |
| **Google Antigravity** | `~/.local/bin/agy` | `agy update` |
| **xAI Grok** | `~/.grok/bin/grok` | `grok update` |
| **OMP** | `~/.bun/bin/omp` | `omp update` |

---

## Architecture & State Management

All telemetry and upgrade history are persisted in `~/.local/share/uca/state.json`:

```json
{
  "version": 1,
  "last_run_at": "2026-08-29T22:18:13.227240+00:00",
  "last_run_duration_secs": 3.32,
  "last_run_status": "success",
  "most_recently_updated": {
    "key": "omp",
    "name": "OMP",
    "timestamp": "2026-08-29T22:18:13.227240+00:00",
    "from_version": "18.0.0",
    "to_version": "18.0.11",
    "duration_secs": 1.12,
    "status": "success"
  },
  "harnesses": { ... }
}
```

Writes are executed atomically via temporary file replacement (`state.json.tmp.<pid>` -> `state.json`) protected by `AtomicLock`.

---

## Uninstallation

To cleanly and completely remove UCA, its background services, symlinks, and shell aliases:

```bash
# In-binary removal
uca uninstall

# Or with state cache purge
uca uninstall --purge -y

# Or via dedicated uninstaller script
./uninstall-uca.sh --purge

# Or via curl one-liner
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/uninstall-uca.sh?$(date +%s)" | bash
```
