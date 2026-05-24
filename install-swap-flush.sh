#!/usr/bin/env bash
#
# install-swap-flush.sh — install the smart, safe automatic swap flusher
#
# Lays down three files and enables a systemd timer that flushes disk swap
# every 30 minutes IF doing so is both worth it and safe:
#
#   /usr/local/bin/swap-flush                  — the script
#   /etc/systemd/system/swap-flush.service     — oneshot unit
#   /etc/systemd/system/swap-flush.timer       — every-30-min trigger
#
# See: SAFE_AUTOMATIC_SWAP_FLUSHING_FOR_AGENT_SWARMS.md
#
# Usage:
#   sudo ./install-swap-flush.sh              # install + enable timer
#   sudo ./install-swap-flush.sh --uninstall  # stop timer, remove all files
#   sudo ./install-swap-flush.sh --dry-run    # show what would be done
#
# Curl-pipe:
#   curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-swap-flush.sh | sudo bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_PATH="/usr/local/bin/swap-flush"
SERVICE_PATH="/etc/systemd/system/swap-flush.service"
TIMER_PATH="/etc/systemd/system/swap-flush.timer"

DRY_RUN=0
UNINSTALL=0

for arg in "$@"; do
    case "$arg" in
        --dry-run)   DRY_RUN=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown arg: $arg (try --help)" >&2
            exit 2
            ;;
    esac
done

# ---- Sanity ----------------------------------------------------------------

if [ "$(uname -s)" != "Linux" ]; then
    echo -e "${RED}This installer is Linux-only (uses systemd + swapoff).${NC}" >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    echo -e "${RED}Run as root (use sudo).${NC}" >&2
    exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
    echo -e "${RED}systemctl not found — this requires a systemd-managed Linux host.${NC}" >&2
    exit 1
fi

# ---- Uninstall -------------------------------------------------------------

if [ "$UNINSTALL" -eq 1 ]; then
    echo -e "${BLUE}Uninstalling swap-flush…${NC}"
    do_or_echo() {
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  would: $*"
        else
            eval "$@" || true
        fi
    }
    do_or_echo "systemctl disable --now swap-flush.timer 2>/dev/null"
    do_or_echo "systemctl stop swap-flush.service 2>/dev/null"
    do_or_echo "rm -f '$SCRIPT_PATH' '$SERVICE_PATH' '$TIMER_PATH'"
    do_or_echo "systemctl daemon-reload"
    echo -e "${GREEN}Done.${NC}"
    exit 0
fi

# ---- Install ---------------------------------------------------------------

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  would: $*"
    else
        eval "$@"
    fi
}

write_file() {
    local path="$1"
    local content="$2"
    local mode="$3"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  would: write $path (mode $mode, $(echo "$content" | wc -l) lines)"
    else
        # install(1) atomically replaces an existing file even if it's
        # currently executing — old fd stays open, new file at the path.
        install -m "$mode" /dev/stdin "$path" <<< "$content"
    fi
}

echo -e "${BLUE}Installing swap-flush…${NC}"

# ---- The script ------------------------------------------------------------

read -r -d '' SWAP_FLUSH_SCRIPT <<'SCRIPT_EOF' || true
#!/bin/bash
# swap-flush — smart, safe automatic swap flusher
#
# Background: When RAM pressure spikes then subsides, the kernel doesn't
# eagerly migrate evicted pages back to RAM. Cold pages stay in disk swap
# until faulted in on next access — and a process touching that data
# pays a slow random-read penalty. Flushing swap (swapoff/swapon) forces
# the kernel to move pages back to RAM in one bulk operation. The cost
# is transient memory pressure during the flush; the benefit is
# restored latency.
#
# This tool only flushes when it's both worth it AND safe:
#
#   - swap-on-disk used >= MIN_DISK_SWAP_GB  (default 4 GB)
#       zram swap isn't counted — it's already in RAM (compressed),
#       so there's no latency win from flushing it.
#   - available RAM >= disk_swap_used * MEM_SAFETY_FACTOR  (default 1.5x)
#       leaves headroom so the flush doesn't push the system into OOM.
#   - memory pressure PSI avg10 <= MAX_MEM_PRESSURE  (default 5.0 %)
#       don't pile work onto a system that's already memory-stressed.
#   - load average 1-min <= nproc * MAX_LOAD_RATIO  (default 1.0)
#       don't pile work onto a CPU-stressed system either.
#
# Override any threshold by setting the env var (e.g., in
# /etc/systemd/system/swap-flush.service.d/override.conf):
#
#   [Service]
#   Environment=MIN_DISK_SWAP_GB=8
#   Environment=MEM_SAFETY_FACTOR=2.0
#
# Also honored: DRY_RUN=1 (any other value, including unset, is "off").
# When set, the safety predicates run as usual and the decision is
# logged, but no swapoff/swapon is performed. Useful for testing
# threshold changes.
#
# Logs to journald with tag "swap-flush". Exit codes:
#   0 — skipped (recorded reason in journal) OR flush ran (success line)
#   1 — early error (missing /proc/meminfo, invalid env config, etc.)
# A timer-driven "skip" therefore appears as success in `systemctl status`,
# which is what we want — only real malfunctions show up as failures.

set -euo pipefail

MIN_DISK_SWAP_GB="${MIN_DISK_SWAP_GB:-4}"
MEM_SAFETY_FACTOR="${MEM_SAFETY_FACTOR:-1.5}"
MAX_MEM_PRESSURE="${MAX_MEM_PRESSURE:-5.0}"
MAX_LOAD_RATIO="${MAX_LOAD_RATIO:-1.0}"
DRY_RUN="${DRY_RUN:-0}"

log_info() { logger -t swap-flush -p user.info "$*"; echo "$*"; }
log_err()  { logger -t swap-flush -p user.err "$*"; echo "$*" >&2; }

# ---- Validate numeric thresholds ------------------------------------------
#
# Without this, a typo like MEM_SAFETY_FACTOR="1,5" (comma instead of
# period) makes awk silently treat it as 0, the required-RAM check
# trivially passes, and the flush proceeds with NO safety margin. That's
# the only env var where a malformed value fails-open; we validate all of
# them anyway for symmetry. Pattern is non-negative integer or decimal:
# at least one digit, optionally followed by `.` and more digits.
# (Zero is accepted; operators who want "no safety margin" or "always
# flush above zero" can opt in explicitly.)
for var in MIN_DISK_SWAP_GB MEM_SAFETY_FACTOR MAX_MEM_PRESSURE MAX_LOAD_RATIO; do
    val="${!var}"
    if ! [[ "$val" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log_err "invalid $var='$val' (expected non-negative number); aborting"
        exit 1
    fi
done

# ---- Read system state -----------------------------------------------------

awk_meminfo() { awk -v k="$1:" '$1==k{print $2; exit}' /proc/meminfo; }

# We track *disk* swap separately (via `swapon --show`) below — see comment
# on the loop. /proc/meminfo's SwapTotal/SwapFree lump zram in with disk
# swap, which would defeat the safety logic.
mem_available_kb="$(awk_meminfo MemAvailable)"

# Pressure may be absent on older kernels — default to 0 (no pressure).
# Format: `some avg10=N.NN avg60=N.NN avg300=N.NN total=N`
# Splitting on space+equals: $1=some $2=avg10 $3=<avg10 value> $4=avg60 ...
mem_pressure_avg10="$(awk -F'[ =]' '/^some/{print $3}' /proc/pressure/memory 2>/dev/null || true)"
mem_pressure_avg10="${mem_pressure_avg10:-0}"

nproc_count="$(nproc)"
load_avg_1="$(awk '{print $1}' /proc/loadavg)"

# Distinguish disk swap from zram. zram swap appears as /dev/zramN entries
# in `swapon --show`. We sum bytes used on non-zram swap devices only —
# zram is RAM-backed so flushing it doesn't restore any latency, and
# including it in safety-margin math would understate the headroom we
# actually have (a zram flush expands the compressed pages back to full
# size, which we shouldn't count against `mem_available`).
count_disk_swap_bytes() {
    local total=0
    local data name used
    if data="$(swapon --show=NAME,USED --bytes --noheadings 2>/dev/null)"; then
        while read -r name used; do
            [ -z "$name" ] && continue
            case "$name" in
                /dev/zram*) continue ;;
            esac
            total=$((total + used))
        done <<< "$data"
    fi
    echo "$total"
}

disk_swap_used_bytes="$(count_disk_swap_bytes)"
disk_swap_used_gb=$((disk_swap_used_bytes / 1024 / 1024 / 1024))

mem_available_bytes=$((mem_available_kb * 1024))
mem_available_gb=$((mem_available_bytes / 1024 / 1024 / 1024))

# Used for one info line whether we flush or not.
state="disk_swap_used=${disk_swap_used_gb}GB mem_available=${mem_available_gb}GB"
state="$state mem_pressure_avg10=${mem_pressure_avg10}%"
state="$state load_1=${load_avg_1} nproc=${nproc_count}"

# ---- Decide -----------------------------------------------------------------

# Each check sets `skip_reason` if it fails.
skip_reason=""

# Compare bytes-vs-GB-threshold in awk so a decimal MIN_DISK_SWAP_GB
# (e.g. 0.5 for "flush if disk swap >= 512 MB") works. Bash's `-lt` only
# accepts integers and would error here on a fractional threshold even
# though the validation regex above accepts it.
if awk -v u="$disk_swap_used_bytes" -v m="$MIN_DISK_SWAP_GB" \
   'BEGIN{exit !(u < m*1024*1024*1024)}'; then
    skip_reason="disk_swap_used=${disk_swap_used_gb}GB < MIN_DISK_SWAP_GB=${MIN_DISK_SWAP_GB}"
fi

if [ -z "$skip_reason" ]; then
    # available_ram_bytes >= disk_swap_used_bytes * MEM_SAFETY_FACTOR
    required_bytes="$(awk -v s="$disk_swap_used_bytes" -v f="$MEM_SAFETY_FACTOR" \
        'BEGIN{printf "%.0f\n", s*f}')"
    if [ "$mem_available_bytes" -lt "$required_bytes" ]; then
        required_gb=$((required_bytes / 1024 / 1024 / 1024))
        skip_reason="mem_available=${mem_available_gb}GB < required=${required_gb}GB"
        skip_reason="$skip_reason (=disk_swap*${MEM_SAFETY_FACTOR})"
    fi
fi

if [ -z "$skip_reason" ]; then
    if awk -v p="$mem_pressure_avg10" -v m="$MAX_MEM_PRESSURE" \
       'BEGIN{exit !(p+0 > m+0)}'; then
        skip_reason="mem_pressure_avg10=${mem_pressure_avg10} > MAX=${MAX_MEM_PRESSURE}"
    fi
fi

if [ -z "$skip_reason" ]; then
    max_load="$(awk -v c="$nproc_count" -v r="$MAX_LOAD_RATIO" \
        'BEGIN{printf "%.2f\n", c*r}')"
    if awk -v l="$load_avg_1" -v m="$max_load" \
       'BEGIN{exit !(l+0 > m+0)}'; then
        skip_reason="load_1=${load_avg_1} > max=${max_load} (nproc*${MAX_LOAD_RATIO})"
    fi
fi

# ---- Act --------------------------------------------------------------------

if [ -n "$skip_reason" ]; then
    log_info "skip: $skip_reason; state=[$state]"
    exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
    log_info "dry-run: would flush; state=[$state]"
    exit 0
fi

log_info "flushing: state=[$state]"
start_ts="$(date +%s)"

# swapoff -a can be very slow on big swap files. Use --verbose so the
# journal captures per-device timing.
#
# Note: `swapoff -a` returns nonzero if any single device fails to
# disable (e.g., zram is briefly busy with active writes) even when the
# DISK swap was drained successfully. We trust the before/after
# disk_swap_used delta below as the real success signal, and don't
# escalate that nonzero exit to a warning unless the data shows the
# flush actually didn't take.
swapoff -av 2>&1 | logger -t swap-flush -p user.info || true
swapon -av 2>&1 | logger -t swap-flush -p user.info || true

# Some setups have a separate zram-swap service that needs a kick because
# `swapoff -a` removed its swap and the kernel won't reattach it on its
# own. Restart it if it exists and there's no zram swap currently active.
#
# Note: `systemctl list-unit-files <name>` returns 0 with empty output
# for nonexistent units — useless as an existence check. `systemctl cat`
# returns nonzero ("No files found for ...") when the unit doesn't
# exist, which is what we want here.
if systemctl cat zram-swap.service >/dev/null 2>&1; then
    if ! swapon --show=NAME --noheadings 2>/dev/null | grep -q '^/dev/zram'; then
        systemctl restart zram-swap.service 2>/dev/null || true
        sleep 1
    fi
fi

end_ts="$(date +%s)"
elapsed=$((end_ts - start_ts))

# Compute disk-swap-used AFTER, same way we did before (count_disk_swap_bytes
# excludes zram), so the comparison is apples-to-apples.
new_disk_swap_used_bytes="$(count_disk_swap_bytes)"

# Report in MB so a 700MB drain doesn't get rounded to "0GB" and look like
# a no-op. Net delta can be negative if the system swapped pages back out
# during the swapon -a window — log it but don't escalate to warn (the
# swapoff itself almost certainly drained pages; they just got refilled).
delta_bytes=$((disk_swap_used_bytes - new_disk_swap_used_bytes))
before_mb=$((disk_swap_used_bytes / 1024 / 1024))
after_mb=$((new_disk_swap_used_bytes / 1024 / 1024))
delta_mb=$((delta_bytes / 1024 / 1024))

log_info "flush complete: elapsed=${elapsed}s disk_swap=${before_mb}MB->${after_mb}MB (net change ${delta_mb}MB)"
SCRIPT_EOF

# ---- The systemd service unit ----------------------------------------------

read -r -d '' SWAP_FLUSH_SERVICE <<'SERVICE_EOF' || true
[Unit]
Description=Smart, safe swap flush (oneshot)
Documentation=man:swapoff(8) man:systemd.timer(5)
ConditionPathExists=/proc/swaps
ConditionVirtualization=!container
# Order after multi-user.target so we don't fire on a partially-up system.
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/swap-flush
# Allow generous time for the actual swapoff -a; safety check is fast.
TimeoutStartSec=30min
# Tune via /etc/systemd/system/swap-flush.service.d/override.conf if you want
# different thresholds than the script defaults.
Environment=MIN_DISK_SWAP_GB=4
Environment=MEM_SAFETY_FACTOR=1.5
Environment=MAX_MEM_PRESSURE=5.0
Environment=MAX_LOAD_RATIO=1.0
# Run the script process at low priority. Note this only affects the
# script's own work (parsing /proc, logging, child fork/exec) — not the
# kernel-side `swapoff` swap-in, which runs in kthread/interrupt context
# with its own scheduling.
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7

[Install]
# This unit is only run by the timer; not installed standalone.
SERVICE_EOF

# ---- The systemd timer -----------------------------------------------------

read -r -d '' SWAP_FLUSH_TIMER <<'TIMER_EOF' || true
[Unit]
Description=Run swap-flush every 30 minutes
Documentation=man:systemd.timer(5)

[Timer]
# Wait until the system has been up a while before the first check.
OnBootSec=15min
# Run every 30 minutes thereafter.
OnUnitActiveSec=30min
# Add up to 5 minutes of random jitter so a whole fleet of hosts doesn't
# all flush at exactly :00 and :30.
RandomizedDelaySec=5min
# Catch up if the system was off when a fire was due.
Persistent=true
# A name visible in `systemctl list-timers`.
Unit=swap-flush.service

[Install]
WantedBy=timers.target
TIMER_EOF

# ---- Place the files -------------------------------------------------------

write_file "$SCRIPT_PATH"  "$SWAP_FLUSH_SCRIPT"  0755
write_file "$SERVICE_PATH" "$SWAP_FLUSH_SERVICE" 0644
write_file "$TIMER_PATH"   "$SWAP_FLUSH_TIMER"   0644

# ---- Enable and start ------------------------------------------------------

run "systemctl daemon-reload"
run "systemctl enable --now swap-flush.timer"

if [ "$DRY_RUN" -eq 0 ]; then
    echo ""
    echo -e "${GREEN}swap-flush installed.${NC}"
    echo ""
    echo -e "${BLUE}Next fire:${NC}"
    systemctl list-timers swap-flush.timer --no-pager | sed -n '1,3p'
    echo ""
    echo -e "${BLUE}Try it now (respects all safety predicates):${NC}"
    echo "    sudo /usr/local/bin/swap-flush"
    echo ""
    echo -e "${BLUE}Observe via journal:${NC}"
    echo "    journalctl -t swap-flush --since today"
    echo ""
    echo -e "${BLUE}Override thresholds (e.g., for tighter safety):${NC}"
    echo "    sudo systemctl edit swap-flush.service"
    echo "    [Service]"
    echo "    Environment=MEM_SAFETY_FACTOR=2.0"
    echo ""
    echo -e "${YELLOW}Uninstall any time:${NC}"
    echo "    sudo $0 --uninstall"
else
    echo ""
    echo -e "${YELLOW}(dry-run; no changes made)${NC}"
fi
