# macOS NFS Auto-Mount for Remote Dev Machines

> **The problem:** Your remote Linux workstation has projects at `/data/projects`, but every time you reboot your Mac you have to manually mount the NFS share.
>
> **The solution:** A LaunchDaemon that auto-mounts on boot, retries gracefully when the server is offline, and gives you a convenient local path.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Mac boots                                                                   │
│     │                                                                       │
│     ▼                                                                       │
│ LaunchDaemon starts ──▶ Network up? ──▶ Server reachable? ──▶ Mount NFS    │
│     │                       │                  │                            │
│     │                       no                 no                           │
│     │                       ▼                  ▼                            │
│     │               Wait + retry        Wait + retry (exponential backoff)  │
│     │                                                                       │
│     ▼                                                                       │
│ ~/dev-server/projects ──▶ /Volumes/dev-server/projects ──▶ 10.0.0.50:/data │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Table of Contents

- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
- [The Mount Script](#the-mount-script)
- [The LaunchDaemon](#the-launchdaemon)
- [Convenient Path Shortcuts](#convenient-path-shortcuts)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

Run these commands to set up auto-mounting for a remote NFS share:

```bash
# 1. Create the mount script
sudo tee /usr/local/bin/mount-dev-nfs << 'SCRIPT'
#!/bin/bash
REMOTE_HOST="10.0.0.50"
REMOTE_PATH="/data"
MOUNT_POINT="/Volumes/dev-server"
MAX_RETRIES=5
LOG_TAG="mount-dev-nfs"

log() { /usr/bin/logger -t "$LOG_TAG" "$1"; }

if mount | grep -q "$MOUNT_POINT"; then
    log "Already mounted at $MOUNT_POINT"
    exit 0
fi

[ -d "$MOUNT_POINT" ] || mkdir -p "$MOUNT_POINT"

retry=0
while ! /sbin/ping -c 1 -W 1 "$REMOTE_HOST" &>/dev/null; do
    retry=$((retry + 1))
    [ $retry -ge $MAX_RETRIES ] && { log "Host unreachable after $MAX_RETRIES attempts"; exit 1; }
    sleep $((2 ** retry))
done

log "Mounting $REMOTE_HOST:$REMOTE_PATH"
/sbin/mount_nfs -o resvport,rw,soft,intr,bg,retrycnt=3,nfc "$REMOTE_HOST:$REMOTE_PATH" "$MOUNT_POINT"
SCRIPT
sudo chmod +x /usr/local/bin/mount-dev-nfs

# 2. Create the LaunchDaemon
sudo tee /Library/LaunchDaemons/com.local.mount-dev-nfs.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.mount-dev-nfs</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/mount-dev-nfs</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>WatchPaths</key>
    <array>
        <string>/Library/Preferences/SystemConfiguration</string>
    </array>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>30</integer>
    <key>NetworkState</key>
    <true/>
</dict>
</plist>
PLIST
sudo chmod 644 /Library/LaunchDaemons/com.local.mount-dev-nfs.plist
sudo chown root:wheel /Library/LaunchDaemons/com.local.mount-dev-nfs.plist

# 3. Load the daemon
sudo launchctl load /Library/LaunchDaemons/com.local.mount-dev-nfs.plist

# 4. Create convenient symlink
ln -sf /Volumes/dev-server/projects ~/dev-projects

# 5. (Optional) Add root-level path after next reboot
echo 'dev	/Volumes/dev-server' | sudo tee -a /etc/synthetic.conf
```

After reboot, you'll have:
- `~/dev-projects` → your remote projects
- `/dev/projects` → same, via synthetic firmlink

---

## How It Works

### Boot Sequence

| Step | What Happens |
|:-----|:-------------|
| 1 | Mac boots, LaunchDaemon system starts |
| 2 | `com.local.mount-dev-nfs` daemon loads (waits for network) |
| 3 | Mount script pings remote host with exponential backoff |
| 4 | Once reachable, mounts NFS share to `/Volumes/dev-server` |
| 5 | If mount fails, retries every 30 seconds |

### Network Change Handling

The `WatchPaths` key monitors `/Library/Preferences/SystemConfiguration`. When network configuration changes (WiFi reconnect, VPN connect, etc.), the daemon re-runs the mount script.

### Why NFS Instead of SSHFS/SFTP?

| Feature | NFS | SSHFS |
|:--------|:----|:------|
| **Performance** | Native, kernel-level | FUSE, userspace |
| **Large files** | Fast | Slow |
| **Random access** | Efficient | Every read = network round trip |
| **Setup** | Requires NFS server | Just SSH |
| **Security** | IP-based or Kerberos | SSH keys |

**Use NFS when:** You have a dedicated dev server on a trusted network (home lab, direct link, VPN).

**Use SSHFS when:** You need ad-hoc access to any SSH server without server-side setup.

---

## The Mount Script

### Full Script with Comments

```bash
#!/bin/bash
# /usr/local/bin/mount-dev-nfs
# Robust NFS mounter with retry logic and logging

# ============================================================================
# CONFIGURATION - Edit these for your setup
# ============================================================================
REMOTE_HOST="10.0.0.50"           # IP or hostname of your dev server
REMOTE_PATH="/data"                # Path exported via NFS on the server
MOUNT_POINT="/Volumes/dev-server"  # Local mount point
MAX_RETRIES=5                      # Give up after this many ping failures
LOG_TAG="mount-dev-nfs"            # Tag for syslog entries

# ============================================================================
# FUNCTIONS
# ============================================================================
log() { /usr/bin/logger -t "$LOG_TAG" "$1"; }

# ============================================================================
# MAIN
# ============================================================================

# Already mounted? Exit early.
if mount | grep -q "$MOUNT_POINT"; then
    log "Already mounted at $MOUNT_POINT"
    exit 0
fi

# Create mount point if needed
[ -d "$MOUNT_POINT" ] || mkdir -p "$MOUNT_POINT"

# Wait for host with exponential backoff (2s, 4s, 8s, 16s, 32s)
retry=0
while ! /sbin/ping -c 1 -W 1 "$REMOTE_HOST" &>/dev/null; do
    retry=$((retry + 1))
    if [ $retry -ge $MAX_RETRIES ]; then
        log "Host $REMOTE_HOST unreachable after $MAX_RETRIES attempts, giving up"
        exit 1
    fi
    sleep_time=$((2 ** retry))
    log "Waiting for $REMOTE_HOST (attempt $retry/$MAX_RETRIES, sleeping ${sleep_time}s)"
    sleep $sleep_time
done

# Mount with robust options
# - resvport: use privileged port (required by most NFS servers)
# - rw:       read-write access
# - soft:     return errors on timeout (don't hang forever)
# - intr:     allow interrupt of hung operations
# - bg:       retry mount in background if first attempt fails
# - retrycnt: limit background retries
# - nfc:      Unicode normalization (macOS compatibility)
log "Mounting $REMOTE_HOST:$REMOTE_PATH -> $MOUNT_POINT"
if /sbin/mount_nfs -o resvport,rw,soft,intr,bg,retrycnt=3,nfc \
    "$REMOTE_HOST:$REMOTE_PATH" "$MOUNT_POINT"; then
    log "Successfully mounted $MOUNT_POINT"
    exit 0
else
    log "Failed to mount $MOUNT_POINT"
    exit 1
fi
```

### NFS Mount Options Explained

| Option | Purpose | Why It Matters |
|:-------|:--------|:---------------|
| `resvport` | Use privileged port (<1024) | Most NFS servers require this |
| `rw` | Read-write access | You want to edit files |
| `soft` | Return errors on timeout | Prevents hung Finder/terminal |
| `intr` | Allow interrupt | Ctrl+C works on stuck operations |
| `bg` | Background retry | First failure doesn't block boot |
| `retrycnt=3` | Limit retries | Don't retry forever |
| `nfc` | Unicode normalization | Fixes filename issues on macOS |

---

## The LaunchDaemon

### Plist Explained

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Unique identifier for this daemon -->
    <key>Label</key>
    <string>com.local.mount-dev-nfs</string>

    <!-- The script to run -->
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/mount-dev-nfs</string>
    </array>

    <!-- Run when the daemon loads (at boot) -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Re-run when network config changes -->
    <key>WatchPaths</key>
    <array>
        <string>/Library/Preferences/SystemConfiguration</string>
    </array>

    <!-- Retry on failure (exit code != 0) -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <!-- Minimum 30s between retries -->
    <key>ThrottleInterval</key>
    <integer>30</integer>

    <!-- Wait for network before first run -->
    <key>NetworkState</key>
    <true/>
</dict>
</plist>
```

### Managing the Daemon

| Action | Command |
|:-------|:--------|
| Load (enable) | `sudo launchctl load /Library/LaunchDaemons/com.local.mount-dev-nfs.plist` |
| Unload (disable) | `sudo launchctl unload /Library/LaunchDaemons/com.local.mount-dev-nfs.plist` |
| Check status | `sudo launchctl list \| grep mount-dev-nfs` |
| View logs | `log show --last 5m --predicate 'eventMessage contains "mount-dev-nfs"'` |
| Force run now | `sudo /usr/local/bin/mount-dev-nfs` |

---

## Convenient Path Shortcuts

### Option 1: Symlink in Home Directory

```bash
ln -sf /Volumes/dev-server/projects ~/dev-projects
```

Access via: `cd ~/dev-projects`

### Option 2: Synthetic Firmlink (Root-Level Path)

macOS's read-only root filesystem requires `/etc/synthetic.conf` for root-level paths:

```bash
# Add the mapping (tab-separated!)
echo 'dev	/Volumes/dev-server' | sudo tee -a /etc/synthetic.conf

# Reboot required for synthetic.conf changes
```

After reboot, access via: `cd /dev/projects`

<details>
<summary><strong>What is synthetic.conf?</strong></summary>

Since macOS Catalina, the root filesystem (`/`) is read-only. You can't `mkdir /data` directly.

`/etc/synthetic.conf` creates "firmlinks", special symlinks that appear at the root level. Each line is:

```
name<TAB>target
```

The system creates `/name` pointing to `target` at boot. Changes require a reboot.

**Common uses:**
- `/data` → external drive or NFS mount
- `/nix` → Nix package manager
- `/opt` → custom software

</details>

### Option 3: Both

For maximum convenience:

```bash
# Immediate access
ln -sf /Volumes/dev-server/projects ~/dev-projects

# Root-level access after reboot
echo 'dev	/Volumes/dev-server' | sudo tee -a /etc/synthetic.conf
```

---

## Server-Side NFS Setup

Your Linux server needs to export the directory via NFS.

### Ubuntu/Debian

```bash
# Install NFS server
sudo apt install nfs-kernel-server

# Add export (edit /etc/exports)
echo '/data 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash)' | sudo tee -a /etc/exports

# Apply changes
sudo exportfs -ra

# Ensure NFS is running
sudo systemctl enable --now nfs-server
```

### Export Options Explained

| Option | Purpose |
|:-------|:--------|
| `rw` | Read-write access |
| `sync` | Write to disk before responding (safer) |
| `no_subtree_check` | Faster, avoids issues with renamed files |
| `no_root_squash` | Root on client = root on server (use carefully) |

### Firewall

If using `ufw`:

```bash
sudo ufw allow from 10.0.0.0/24 to any port nfs
sudo ufw allow from 10.0.0.0/24 to any port 111  # portmapper
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|:--------|:------|:----|
| Mount hangs | Server unreachable or NFS not running | Check `ping`, verify NFS server is running |
| "Permission denied" | Export doesn't include your IP | Check `/etc/exports` on server |
| "Operation not permitted" | Missing `resvport` option | Ensure mount uses `-o resvport` |
| Slow performance | Network issues or wrong options | Check network speed; try `async` on server |
| Files have wrong owner | UID mismatch | Ensure UIDs match or use `no_root_squash` |
| Daemon doesn't start | Plist syntax error | Check with `plutil /Library/LaunchDaemons/com.local.mount-dev-nfs.plist` |
| Mount disappears | Server rebooted or network changed | Daemon should remount; check logs |

### Viewing Logs

```bash
# Recent mount attempts
log show --last 10m --predicate 'eventMessage contains "mount-dev-nfs"' --style compact

# All NFS-related messages
log show --last 10m --predicate 'subsystem == "com.apple.nfs"' --style compact
```

### Manual Mount Test

```bash
# Test the mount command directly
sudo mount_nfs -o resvport,rw,soft,intr,nfc 10.0.0.50:/data /Volumes/dev-server

# Check if mounted
mount | grep dev-server
```

---

## Quick Reference

### Files Created

| File | Purpose |
|:-----|:--------|
| `/usr/local/bin/mount-dev-nfs` | Mount script with retry logic |
| `/Library/LaunchDaemons/com.local.mount-dev-nfs.plist` | Daemon configuration |
| `/etc/synthetic.conf` | Root-level path mapping (optional) |
| `~/dev-projects` | Convenience symlink (optional) |

### Customization Points

| Setting | Location | Default |
|:--------|:---------|:--------|
| Remote host IP | Mount script, `REMOTE_HOST` | `10.0.0.50` |
| Remote path | Mount script, `REMOTE_PATH` | `/data` |
| Local mount point | Mount script, `MOUNT_POINT` | `/Volumes/dev-server` |
| Retry attempts | Mount script, `MAX_RETRIES` | `5` |
| Retry throttle | Plist, `ThrottleInterval` | `30` seconds |

---

*Last updated: January 2026*
