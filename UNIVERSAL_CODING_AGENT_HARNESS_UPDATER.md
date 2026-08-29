# Universal Coding Agent (UCA) Harness Updater and Status Dashboard

UCA manages updates, version tracking, and background scheduling for five AI coding agent harnesses: **Claude Code**, **OpenAI Codex**, **Google Antigravity (AGY)**, **xAI Grok**, and **OMP**.

It runs as a standalone, zero-dependency Bash script with a memory footprint under 2MB and execution startup under 5ms. It includes automatic 3-hour background scheduling, terminal dashboard formatting with ANSI fallback, atomic locking, pre-flight disk space protection, and a self-healing diagnostic system.

---

## Quick Start

### One-Line Install

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-uca.sh?$(date +%s)" | bash
```

### Local Clone Install

```bash
git clone https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts.git
cd misc_coding_agent_tips_and_scripts
./install-uca.sh
```

---

## Supported Harnesses

| Harness | Target Binary | Update Command |
|:---|:---|:---|
| **Claude Code** | `~/.local/bin/claude` | `claude update` |
| **OpenAI Codex** | `~/.bun/bin/codex` | `bun install -g @openai/codex@latest` (fallback `codex update`) |
| **Google Antigravity** | `~/.local/bin/agy` | `agy update` |
| **xAI Grok** | `~/.grok/bin/grok` | `grok update` |
| **OMP** | `~/.bun/bin/omp` | `omp update` |

---

## Command Reference

### Updating Harnesses

Update all installed harnesses sequentially:
```bash
uca
```

Sample output:
```text
════════════════════════════════════════════════════════════════════════════
 UCA: Universal Coding Agent Harness Updater
 Started at: 2026-08-29 18:18:13
════════════════════════════════════════════════════════════════════════════

  ⟳ Updating Claude Code...         ✔ Claude Code          Up to date (2.1.251) (1.0s)
  ⟳ Updating OpenAI Codex...        ✔ OpenAI Codex         Up to date (0.151.0) (0.3s)
  ⟳ Updating Google Antigravity...  ✔ Google Antigravity   Up to date (1.1.22) (0.2s)
  ⟳ Updating xAI Grok...            ✔ xAI Grok             Up to date (1.0.13) (0.7s)
  ⟳ Updating OMP...                 ✔ OMP                  UPDATED: From version 18.0.0 to version 18.0.11 (1.1s)

────────────────────────────────────────────────────────────────────────────
 Completed in: 3.3s • Status: Completed
 Most Recent Update: OMP (From version 18.0.0 to 18.0.11, 5s ago)
════════════════════════════════════════════════════════════════════════════
```

Update a single harness by name:
```bash
uca omp       # Update only OMP
uca claude    # Update only Claude Code
uca codex     # Update only OpenAI Codex
uca agy       # Update only Google Antigravity
uca grok      # Update only xAI Grok
```

Dry run (check versions without applying changes):
```bash
uca --dry-run
```

---

### Status Dashboard (`ucas`)

View the status breakdown, semver transition history, background timer state, and free disk space:

```bash
ucas
```

Sample dashboard output:
```text
════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
 UCA STATUS: Universal Coding Agent Harness Dashboard
 Last Full Run: 10s ago
 Background Service: ACTIVE • launchd background service active (every 3 hours / 10800s)
 Disk Safety: 439.0 GB free (healthy) • Threshold: 500 MB
════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

 ⭐ MOST RECENTLY UPDATED HARNESS:
    omp  •  From version 18.0.0 to version 18.0.11  (10s ago)


 HARNESS BREAKDOWN
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 Harness               Version     Status          Version Changes                                     Checked     
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 Claude Code           2.1.251     ✔ Up to date    Up to date at 2.1.251                               10s ago     
 OpenAI Codex          0.151.0     ✔ Up to date    Up to date at 0.151.0                               10s ago     
 Google Antigravity    1.1.22      ✔ Up to date    Up to date at 1.1.22                                10s ago     
 xAI Grok              1.0.13      ✔ Up to date    Up to date at 1.0.13                                10s ago     
 OMP                   18.0.11     ✔ Up to date    From version 18.0.0 to version 18.0.11              10s ago     
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

 📜 RECENT VERSION CHANGE HISTORY
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  • 2026-08-29 18:18  omp                From version 18.0.0 to version 18.0.11
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

 Commands: uca (update all) • ucas (status) • ucas -w (watch) • uca doctor • uca logs • uca uninstall
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
```

#### Fast Parallel Probing

Probe all harness versions concurrently in parallel subshells:
```bash
ucas -f
```

#### Live Watch Mode

Auto-refresh the terminal dashboard on a set interval (default 5 seconds):
```bash
ucas -w        # Refresh every 5 seconds
ucas -w 2      # Refresh every 2 seconds
```

#### JSON Machine Output

Export the complete state file in JSON format for automated pipelines:
```bash
ucas --json
```

---

### World-Class Doctor Subsystem (`uca doctor`)

UCA includes a self-healing diagnostic system adhering to detect-then-fix rules: diagnosis has zero side effects, every mutation creates a byte-for-byte backup, and all repairs are reversible.

| Command | Description | Exit Codes |
|:---|:---|:---|
| `uca doctor` | Read-only diagnostics | `0` = healthy, `1` = findings detected |
| `uca doctor --fix` | Apply automated repairs with backups | `0` = success, `2` = partial, `3` = rollback, `4` = unsafe |
| `uca doctor --dry-run --fix` | Print planned repair actions without writing to disk | `0` = success |
| `uca doctor undo [run-id]` | Revert changes from a repair run (`latest` if omitted) | `0` = restored, `1` = error |
| `uca doctor health` | Fast one-line health check for scripts and CI | `0` = healthy, `1` = unhealthy |
| `uca doctor capabilities` | Export JSON schema of all detectors, fixers, and exit codes | `0` = success |
| `uca doctor robot-docs` | Output agent handbook for calling harnesses | `0` = success |
| `uca doctor --robot-triage` | Single-call JSON mega-command with findings and suggested fix | `0` / `1` |

#### Supported Detectors and Fixers

1. `DET-LOCK-STALE` / `FIX-LOCK-STALE`: Detects abandoned lock directories from dead process IDs and reclaims them safely.
2. `DET-SERVICE-INACTIVE` / `FIX-SERVICE-INACTIVE`: Detects inactive or unloaded launchd agents / systemd timers and re-enables them.
3. `DET-SYMLINK-BROKEN` / `FIX-SYMLINK-BROKEN`: Detects missing or corrupted `ucas` command symlinks in `~/.local/bin` and restores them.
4. `DET-STATE-CORRUPTED` / `FIX-STATE-CORRUPTED`: Detects truncated or invalid `state.json` files, creates a backup, and initializes clean state.
5. `DET-DISK-SPACE`: Detects free disk space below safety threshold (default 500 MB).
6. `DET-HARNESS-SMOKE` / `FIX-HARNESS-SMOKE`: Executes `--help` smoke tests against all installed harnesses, flagging corrupted binaries and re-running updates.
7. `DET-PATH-ENV` / `FIX-PATH-ENV`: Verifies `~/.local/bin` is present in shell search paths.

#### Sample Doctor Output

```bash
uca doctor
```

```text
════════════════════════════════════════════════════════════════════════════
 UCA DOCTOR: Harness & Environment Diagnostics
════════════════════════════════════════════════════════════════════════════

  ✔ Shell runtime: Bash 5.3.9 (/bin/zsh)
  ✔ Charmbracelet Gum: Found (gum version 0.17.0)
  ✔ State storage: /Users/jemanuel/.local/share/uca (writable=true)
  ✔ Disk Space Safety: 439.0 GB free on /Users/jemanuel (Min safety threshold: 500 MB)
  ✔ 3-Hour Auto-Updater: launchd background service active (every 3 hours / 10800s)

  Harness Integrity & Smoke Checks:
    ✔ Claude Code          /Users/jemanuel/.local/bin/claude      Version: 2.1.251        Smoke: Ready
    ✔ OpenAI Codex         /Users/jemanuel/.bun/bin/codex         Version: 0.151.0        Smoke: Ready
    ✔ Google Antigravity   /Users/jemanuel/.local/bin/agy         Version: 1.1.22         Smoke: Ready
    ✔ xAI Grok             /Users/jemanuel/.grok/bin/grok         Version: 1.0.13         Smoke: Ready
    ✔ OMP                  /Users/jemanuel/.bun/bin/omp           Version: 18.0.11        Smoke: Ready

════════════════════════════════════════════════════════════════════════════
```

#### Reversing a Doctor Repair Run

When `uca doctor --fix` modifies files, it creates verbatim copies under `~/.local/share/uca/.doctor/runs/<run-id>/backups/` and logs operations with before-and-after SHA-256 hashes in `actions.jsonl`.

To reverse the most recent repair:
```bash
uca doctor undo latest
```

To reverse a specific run ID:
```bash
uca doctor undo 2026-08-29T22-35-54Z__a4f7b0
```

---

### Inspecting Logs (`uca logs`)

View update logs:
```bash
uca logs            # View the last 40 entries
uca logs --errors   # Show only error and warning events
uca logs --follow   # Stream real-time log output
```

Log files are stored at:
- Standard log: `~/.local/share/uca/uca.log`
- Error log: `~/.local/share/uca/uca-error.log`

---

### Managing Background Scheduling

UCA schedules automated runs every 3 hours.

Inspect scheduler status:
```bash
uca service status
```

Re-install or re-enable the background scheduler:
```bash
uca service install
```

- **macOS**: Configured via launchd at `~/Library/LaunchAgents/com.<username>.uca.plist` with a 10,800-second interval (`StartInterval = 10800`).
- **Linux**: Configured via systemd user timer at `~/.config/systemd/user/uca.timer` with calendar schedule `*-*-* 00,03,06,09,12,15,18,21:00:00` and randomized 3-minute jitter.

---

## Safety Features

### Zero-Disk-Space Crash Prevention

Before initiating package updates, UCA queries filesystem capacity with `df -Pk`. If available space drops below the threshold (default: 500 MB), UCA skips the update cycle, outputs a warning, and prevents corrupted downloads or partial installations.

In background service runs (`--quiet`), UCA logs the skip and sends a desktop notification without writing large error dumps.

Override or configure the threshold:
```bash
uca --min-disk-mb 1000     # Require 1 GB free
uca --ignore-disk-space    # Bypass check
export UCA_MIN_DISK_MB=250 # Environment override
```

### Atomic Directory Locking

UCA protects state files with directory-level atomic locking (`~/.local/share/uca/.lock`). If a manual terminal run and a background timer run start at the same time, one acquires the lock and proceeds while the other exits cleanly. Stale locks from crashed processes are identified via `kill -0 <pid>` and automatically reclaimed.

### Post-Update Smoke Verification

After each update, UCA executes a quick verification call (`<harness> --help`) to confirm the binary remains functional. If an update breaks the binary or produces a runtime error, UCA flags the harness with a warning in `ucas` and `uca doctor`.

### Desktop Notifications

On version upgrades, UCA sends a desktop alert via macOS `osascript` or Linux `notify-send` showing the previous and new version numbers. Routine runs with no version changes execute silently.

---

## Complete CLI Options

```text
Usage:
  uca                 Update all agent harnesses (claude, codex, agy, grok, omp)
  ucas                Show status breakdown, version changes, and schedule
  ucas -w, --watch    Interactive live auto-refreshing dashboard
  ucas -f, --fast     Probe versions in parallel (sub-second discovery)
  uca <harness>       Update specific harness (e.g. 'uca omp', 'uca claude')
  uca doctor          Run preflight diagnostics and environment verification
  uca doctor --fix    Safely repair detected issues with automated backups
  uca doctor undo     Revert changes from a doctor repair run
  uca logs            Inspect update logs (--errors, --follow)
  uca service install Install 3-hour background auto-updater service
  uca service status  Show background service status
  uca uninstall       Cleanly remove UCA, timers, and aliases (--purge)
  uca check           Probe versions without running updates

Options:
  -q, --quiet            Minimal output (for cron / background runs)
  --notify               Dispatch desktop notification on version change
  --no-smoke-test        Skip post-update verification guard
  --ignore-disk-space    Bypass free disk space safety threshold
  --min-disk-mb <N>      Set minimum free disk space threshold (default: 500 MB)
  --dry-run              Check versions without applying updates
  --no-gum               Disable gum styling and use pure ANSI fallback
  --json                 Output status in JSON format
  -h, --help             Show this help message
```

---

## Uninstallation

Remove UCA, background launchd/systemd services, symlinks, and shell aliases:

```bash
# In-CLI uninstallation
uca uninstall

# Purge state cache and logs
uca uninstall --purge -y

# Dedicated standalone uninstaller script
./uninstall-uca.sh --purge

# One-line curl removal
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/uninstall-uca.sh?$(date +%s)" | bash
```
