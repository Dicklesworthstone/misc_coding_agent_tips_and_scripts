# Safe Automatic Swap Flushing for AI Agent Swarms

> **TL;DR:** AI coding agents cause memory spikes that leave gigabytes of cold data stuck in disk swap, dragging on responsiveness long after the spike is over. This guide installs a systemd timer that flushes disk swap every 30 minutes — but **only when both worth it AND safe**, so it never causes an OOM or piles work onto a busy box. One-command installer; three files end up on disk.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-swap-flush.sh | sudo bash
```

That writes three files (the script and the systemd unit + timer), runs `daemon-reload`, and enables the timer. First fire is 15 minutes after the next boot (or immediately on a long-uptime host), then every 30 minutes with up to 5 minutes of random jitter.

To uninstall later:

```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-swap-flush.sh | sudo bash -s -- --uninstall
```

The installer also accepts `--dry-run` (preview what it would do) and `--help`.

---

## The Swap Paradox

Run a few Claude Code or Codex agents in parallel on a workstation with substantial RAM, give them an hour, and you'll see something weird:

```text
$ free -h
              total        used        free       shared       buff/cache  available
Mem:          215Gi        66Gi        39Gi       26Gi         150Gi       149Gi
Swap:          71Gi        71Gi          0B
```

**149 GB of RAM available. 71 GB of swap full.** The system isn't currently under memory pressure — there's plenty of headroom. But during an earlier spike (a big build, a bunch of test runs, a model spinning up locally) the kernel evicted ~71 GB of cold pages to disk. Now those pages just *sit there*. The kernel doesn't proactively migrate them back to RAM. They only fault back in when something touches them.

So when an agent comes back to a session it parked an hour ago — opens a buffer, reads its scrollback, asks a question that needs to walk a process tree — every touch on a swapped-out page is a **random disk read**, often blocking other work. The whole machine feels sluggish even though `top` shows nothing wrong.

The fix is simple. `sudo swapoff -a && sudo swapon -a` forces the kernel to migrate every swapped-out page back into RAM in one bulk operation, then re-enable swap fresh. A few minutes of mild I/O (longer for hundreds of GB) for restored responsiveness. The catch is **the flush itself can OOM the box** if you don't leave enough RAM headroom — and on a fleet of agent swarm hosts you don't want to remember to babysit this manually.

## At a Glance

| Predicate | Default | What it protects against |
|:----------|:--------|:-------------------------|
| `MIN_DISK_SWAP_GB` | 4 GB | Doing the work for a trivial reclaim |
| `MEM_SAFETY_FACTOR` | 1.5× | OOM during the migrate-pages-back operation |
| `MAX_MEM_PRESSURE` | 5.0 % PSI avg10 | Piling work onto an already memory-stressed host |
| `MAX_LOAD_RATIO` | 1.0× nproc | Piling work onto a CPU-stressed host |

If all four hold, swapoff/swapon runs. Otherwise it logs a skip reason to journald and exits cleanly.

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                          swap-flush DECISION TREE                            ┃
┃                                                                              ┃
┃     Timer fires every 30 min (with 5-min random jitter)                      ┃
┃           │                                                                  ┃
┃           ▼                                                                  ┃
┃     Read disk swap used                          via `swapon --show`         ┃
┃     Read available RAM, PSI avg10, load          via /proc/*                 ┃
┃           │                                                                  ┃
┃           ▼                                                                  ┃
┃     ┌───────────────────────────────────────────────────────────────────┐    ┃
┃     │  disk swap >= MIN_DISK_SWAP_GB ?     (worth it?)                  │    ┃
┃     │  available RAM >= disk_swap × FACTOR ?   (safe to absorb?)        │    ┃
┃     │  PSI avg10 <= MAX_MEM_PRESSURE ?     (system not strained?)       │    ┃
┃     │  load_1 <= nproc × RATIO ?           (system not CPU-busy?)       │    ┃
┃     └───────────────────────────────────────────────────────────────────┘    ┃
┃           │                                                                  ┃
┃        all yes? ────► no ────► log "skip: <reason>" → exit 0                 ┃
┃           │                                                                  ┃
┃           ▼                                                                  ┃
┃     swapoff -av                                  bulk-migrate pages to RAM   ┃
┃     swapon  -av                                  re-enable swap fresh        ┃
┃     restart zram-swap.service if present                                     ┃
┃           │                                                                  ┃
┃           ▼                                                                  ┃
┃     log "flush complete: disk_swap=BEFORE_MB->AFTER_MB (net change DELTA_MB)" ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

---

## Why each predicate is there

### 1. `MIN_DISK_SWAP_GB` (default 4 GB)

If only a few hundred MB are in swap, the latency hit on the next access is negligible and not worth the I/O of a bulk flush. The flush isn't free — `swapoff -a` on big swap can take 5–25 minutes — so we want a minimum that justifies the work.

**zram doesn't count.** zram swap is RAM-backed compressed pages; there's no random-read latency to restore. Including it would let `MIN_DISK_SWAP_GB` trigger on hosts that have 30 GB of zram swap but zero disk swap — pointless work, plus the "flush" would expand compressed pages back to full size and chew through RAM headroom.

### 2. `MEM_SAFETY_FACTOR` (default 1.5×)

This is the OOM gate. To migrate pages back, the kernel needs RAM room for the same data that's currently in swap (plus working set the running processes need). If `swap_used = 30 GB` and `mem_available = 25 GB`, attempting `swapoff -a` will either fail partway through or trigger the OOM killer.

A factor of `1.5×` requires `mem_available >= 1.5 × disk_swap_used`. That gives the kernel headroom for the migration plus normal allocation churn from running processes. On a system with `swap_used = 30 GB` we'll only attempt the flush when `mem_available >= 45 GB`.

This is the **only env var where a malformed value fails open**: if you typo `MEM_SAFETY_FACTOR="1,5"` (comma instead of period), awk silently parses it as 0 and the safety check trivially passes. The script catches this at startup with an explicit regex and aborts with a clear error before any swap manipulation.

### 3. `MAX_MEM_PRESSURE` (default 5.0 %)

The Linux kernel's [Pressure Stall Information](https://docs.kernel.org/accounting/psi.html) reports the percentage of time tasks were stalled waiting for memory. `avg10 = 5.0` means 5% of the last 10 seconds were spent in stall. Above that, the system is genuinely strained and we should NOT add a multi-minute bulk operation that grabs even more RAM headroom.

PSI is also our "real-time" signal. The other predicates look at a snapshot; PSI tells us whether the snapshot is actually a stable state or whether the system is mid-spike. If PSI is climbing, wait it out.

### 4. `MAX_LOAD_RATIO` (default 1.0× nproc)

The CPU-side equivalent. If load average is above `nproc × 1.0`, every core is fully utilized and `swapoff` will fight for cycles, which slows everything down. The default ratio of 1.0 means "skip if the box is fully busy"; bump to 2.0 on hosts where steady-state load runs hot but you still want auto-flushing to happen.

---

## Settings

| Variable | Default | Range |
|:---------|:--------|:------|
| `MIN_DISK_SWAP_GB` | `4` | Any non-negative number, integer or decimal |
| `MEM_SAFETY_FACTOR` | `1.5` | `1.0` = no headroom; `2.0` = paranoid |
| `MAX_MEM_PRESSURE` | `5.0` | `0` = any pressure blocks; `100` = never blocks |
| `MAX_LOAD_RATIO` | `1.0` | `0.5` = strict; `2.0` = relaxed |
| `DRY_RUN` | unset | Set to `1` to log decisions without flushing |

### Per-host overrides

Drop a file at `/etc/systemd/system/swap-flush.service.d/override.conf`:

```ini
[Service]
Environment=MEM_SAFETY_FACTOR=2.0
Environment=MAX_LOAD_RATIO=2.0
```

Then `sudo systemctl daemon-reload`. The next timer fire uses the new values. No edits to the script or the main service unit.

Or use systemd's editor wrapper, which handles the daemon-reload for you:

```bash
sudo systemctl edit swap-flush.service
```

### Manual invocation

The same script is callable directly. It respects all four predicates plus `DRY_RUN`:

```bash
# Use defaults from the service unit's Environment= lines
sudo /usr/local/bin/swap-flush

# Override at invocation. Note `sudo env VAR=value` — bare `VAR=value sudo`
# would not pass the env through (sudo strips env by default).
sudo env MIN_DISK_SWAP_GB=2 /usr/local/bin/swap-flush

# Test threshold changes without actually flushing
sudo env DRY_RUN=1 MEM_SAFETY_FACTOR=3.0 /usr/local/bin/swap-flush
```

---

## What it logs

All decisions go to journald under tag `swap-flush`. Each invocation produces exactly one summary line, plus the per-device output of `swapoff -av` / `swapon -av` if the flush ran.

### Skip — not enough swap

```
skip: disk_swap_used=2GB < MIN_DISK_SWAP_GB=4; state=[disk_swap_used=2GB mem_available=194GB mem_pressure_avg10=0.00% load_1=6.95 nproc=64]
```

### Skip — not safe (insufficient headroom)

```
skip: mem_available=20GB < required=45GB (=disk_swap*1.5); state=[disk_swap_used=30GB mem_available=20GB mem_pressure_avg10=8.2% load_1=128 nproc=64]
```

### Skip — under pressure

```
skip: mem_pressure_avg10=12.4 > MAX=5.0; state=[disk_swap_used=12GB mem_available=80GB mem_pressure_avg10=12.4% load_1=42 nproc=64]
```

### Flushed

```
flushing: state=[disk_swap_used=10GB mem_available=84GB mem_pressure_avg10=0.02% load_1=18 nproc=128]
flush complete: elapsed=201s disk_swap=10240MB->0MB (net change 10240MB)
```

A `net change` close to zero (or even slightly negative) is normal on a busy host — the kernel may swap pages back out during the `swapon -a` window. The swapoff itself almost certainly drained pages; some just got refilled. The script logs this without escalating to a warning.

### Inspection

```bash
# Everything swap-flush has done today
journalctl -t swap-flush --since today

# Decisions only (skip/flush lines, not the per-device swapoff/swapon spam)
journalctl -t swap-flush --since today | grep -E "^[A-Z][a-z]+ [0-9]+ [0-9:]+ [^ ]+ swap-flush\[[0-9]+\]: (skip|flushing|flush complete|invalid|dry-run)"

# Next scheduled fire
systemctl list-timers swap-flush.timer

# Live status of the most recent invocation
systemctl status swap-flush.service
```

---

## Design notes

### Why oneshot, not Type=simple

`Type=oneshot` is the right model for a script that does work and exits. systemd ensures only one instance is active at a time (so timer fires can't overlap and race), and tracks exit code rather than "service is up".

### Why a timer instead of cron

- `RandomizedDelaySec=5min` spreads fleet-wide invocations so 13 boxes don't all flush at exactly `:00` and `:30`.
- `Persistent=true` catches missed fires (the system was off when one was due) — useful for laptops or hosts that get rebooted.
- journald integration: every fire is one entry in `journalctl -t swap-flush`. With cron, you'd be chasing output across `/var/log/cron`, MAILTO, and possibly nowhere.

### Why the artificial 15-minute boot delay

`OnBootSec=15min` keeps the first fire from happening during the messiest part of system startup, when other services are still settling and PSI isn't yet meaningful. On a long-uptime host (boot was already more than 15 minutes ago at enable-time) the timer is eligible to fire immediately; in practice `RandomizedDelaySec=5min` means the first fire lands within five minutes of enable, not later.

### Validation as a load-bearing safety check

The four numeric env vars all go through a regex check at startup:

```bash
for var in MIN_DISK_SWAP_GB MEM_SAFETY_FACTOR MAX_MEM_PRESSURE MAX_LOAD_RATIO; do
    val="${!var}"
    if ! [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_err "invalid $var='$val' (expected non-negative number); aborting"
        exit 1
    fi
done
```

This is the only thing protecting against the European-locale typo `MEM_SAFETY_FACTOR="1,5"`. Without validation, awk would silently parse it as 0, the required-RAM check would trivially pass, and the flush would proceed with zero headroom — a real OOM risk on a tight host. Catching this early is worth the seven lines of bash.

---

## Predicates I considered and rejected

### "Available RAM > swap_total"

Looks safer but it's wrong: `swap_total` includes zram. On a host with 32 GB zram + 8 GB disk swap, requiring `available > 40 GB` would gate the flush on RAM we don't need (zram pages don't migrate anywhere). The script tracks `disk_swap_used` specifically because that's what actually flows back to RAM.

### "Skip if any process has been swapping in the last minute"

Theoretically nice (don't flush while pages are actively being touched) but expensive to measure cheaply across all PIDs, and the PSI predicate captures the same intent at the system level.

### "Adapt thresholds to recent history"

Tracking what previous invocations did and adjusting thresholds is a reasonable feature to build later. The current design is intentionally stateless — every fire is a fresh decision based on current /proc data — which makes it dramatically easier to reason about.

### "Run swapoff per-device with timeout, fall back to per-page if slow"

`swapoff -a` is already pretty smart about ordering and parallelism. Reimplementing it in bash would add complexity without obvious benefit. The 30-minute `TimeoutStartSec` is the safety net if swapoff genuinely hangs.

---

## Troubleshooting

### "I installed it but it never flushes"

The most common reason: the default `MIN_DISK_SWAP_GB=4` isn't being met. Check:

```bash
sudo swapon --show=NAME,USED --bytes --noheadings | grep -v '^/dev/zram' | awk '{sum += $2} END {printf "disk swap used: %.1f GB\n", sum / 1024 / 1024 / 1024}'
```

If that's `< 4.0`, you don't have enough disk swap usage to trigger. Either wait until you do, or lower the threshold:

```bash
sudo systemctl edit swap-flush.service
# Add:
# [Service]
# Environment=MIN_DISK_SWAP_GB=1
sudo systemctl daemon-reload
```

### "swap-flush ran but reported `net change 0MB`"

Common on busy hosts. The flush DID drain swap, but the kernel was actively pushing pages back out as we re-enabled swap, so net change is near zero. The flush wasn't wasted — pages were rotated through RAM during the operation, which is exactly the desired effect.

If you want to see how much was reclaimed mid-flight, the per-device `swapoff -av` output in journald shows the actual bytes drained per device.

### "It tripped the safety check and skipped, but I really want it to flush"

Force it temporarily by relaxing the threshold for just that invocation:

```bash
sudo env MEM_SAFETY_FACTOR=0.5 /usr/local/bin/swap-flush
```

If you find yourself doing this regularly, the timer's defaults are too tight for your workload — adjust the override file.

### "swapoff takes longer than 30 minutes"

Bump `TimeoutStartSec` in the service override:

```ini
[Service]
TimeoutStartSec=60min
```

A 30+ minute swapoff usually means you have 100+ GB of disk swap to drain. Consider whether you actually need that much swap, or whether more RAM would be a better investment.

---

## Files this installs

| Path | Purpose |
|:-----|:--------|
| `/usr/local/bin/swap-flush` | The script — safe to read and run by hand |
| `/etc/systemd/system/swap-flush.service` | oneshot unit with default thresholds in `Environment=` lines |
| `/etc/systemd/system/swap-flush.timer` | every-30-min trigger with 5-min jitter |

The installer is idempotent — running it again overwrites the files in place and re-enables the timer. Uninstall removes all three and `daemon-reload`s.
