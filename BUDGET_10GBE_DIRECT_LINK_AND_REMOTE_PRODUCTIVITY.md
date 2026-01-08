# Budget 10GbE Direct Link and Remote Dev Productivity

> **The problem:** Your Mac and Linux workstation are on the same network, but transfers crawl at 100MB/s through your gigabit switch. Remote file access feels sluggish. Clipboard doesn't sync. Every SSH session looks the same.
>
> **The solution:** A ~$90 direct 10GbE link that hits 800+ MB/s, plus shell aliases that make remote work feel local.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   Mac Mini M4                          Linux Workstation                    │
│   ┌─────────────┐                      ┌─────────────────┐                  │
│   │             │    ~$90 total        │                 │                  │
│   │  Thunderbolt├────────────────────► │ Built-in 10GbE  │                  │
│   │  to 10GbE   │   Cat6 cable ($5)    │ (Aquantia)      │                  │
│   │  adapter    │                      │                 │                  │
│   │  (~$85)     │                      │                 │                  │
│   └─────────────┘                      └─────────────────┘                  │
│        │                                      │                             │
│        │         Static IPs: 10.10.10.x       │                             │
│        │         Speed: ~800 MB/s             │                             │
│        │         Latency: <0.1ms              │                             │
│        └──────────────────────────────────────┘                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Table of Contents

- [The Hardware Setup](#the-hardware-setup)
- [Network Configuration](#network-configuration)
- [Verified File Transfers](#verified-file-transfers)
- [Clipboard Sync](#clipboard-sync)
- [Remote Display Wake](#remote-display-wake)
- [Modern CLI Tool Replacements](#modern-cli-tool-replacements)
- [AI Coding Agent Aliases](#ai-coding-agent-aliases)

---

## The Hardware Setup

### What You Need

| Component | Cost | Notes |
|:----------|:-----|:------|
| Thunderbolt to 10GbE adapter | ~$85 | IOCREST from AliExpress (uses Aquantia AQC113 chip) |
| Cat6 or Cat6A cable | ~$5 | Any length you need; Cat6 works for short runs |
| **Total** | **~$90** | |

### Why This Works

Many high-end Linux workstations (Threadripper PRO, EPYC, etc.) come with **built-in 10GbE ports** that often go unused because most home networks are gigabit. The Aquantia AQC113 controllers are common on these boards.

Mac Mini M4 (and other recent Macs) have **Thunderbolt 4 ports** that can drive 10GbE adapters at full speed since Thunderbolt 4 provides 40Gbps bandwidth.

### Adapter Recommendations

| Adapter | Price | Notes |
|:--------|:------|:------|
| **IOCREST** | ~$85 | Best value; uses same Aquantia chip as Mac Studio's built-in 10GbE |
| Sonnet Solo10G | ~$200 | Premium build, silent, NBASE-T support (2.5/5G fallback) |
| OWC Thunderbolt 3/4 | ~$150-200 | Solid, bus-powered, large aluminum heatsink |
| QNAP QNA-T310G1S | ~$130 | Compact, good thermal design |

The IOCREST achieves ~9.5 Gbps in iperf3 tests, essentially full line rate.

### Real-World Performance

```
# Before: Through gigabit switch
$ scp large-file.tar.gz workstation:
large-file.tar.gz    100%   10GB  112.3MB/s   01:29

# After: Direct 10GbE link
$ scp large-file.tar.gz workstation:
large-file.tar.gz    100%   10GB  847.2MB/s   00:12
```

That's **7.5x faster** for a $90 investment.

---

## Network Configuration

### Linux Side (Workstation)

Create a netplan config for the 10GbE interface:

```bash
# /etc/netplan/02-direct-link.yaml
sudo tee /etc/netplan/02-direct-link.yaml << 'EOF'
network:
  version: 2
  ethernets:
    eno1:  # Your 10GbE interface name
      addresses:
        - 10.10.10.1/24
      mtu: 9000  # Jumbo frames for better throughput
EOF

sudo chmod 600 /etc/netplan/02-direct-link.yaml
sudo netplan apply
```

<details>
<summary><strong>Find your 10GbE interface name</strong></summary>

```bash
# List network interfaces with their drivers
for iface in /sys/class/net/*; do
  name=$(basename "$iface")
  driver=$(readlink "$iface/device/driver" 2>/dev/null | xargs basename 2>/dev/null)
  echo "$name: $driver"
done

# Look for "atlantic" (Aquantia) or "ixgbe" (Intel 10GbE)
# Common names: eno1, enp6s0, eth1
```

</details>

### Mac Side

1. **Plug in the Thunderbolt 10GbE adapter** - macOS should detect it automatically

2. **Configure static IP:**
   - System Settings → Network → [Your 10G Adapter]
   - Configure IPv4: Manually
   - IP Address: `10.10.10.2`
   - Subnet Mask: `255.255.255.0`
   - Router: (leave blank)

3. **Enable Jumbo Frames (optional but recommended):**
   - In the same network settings, click "Advanced"
   - Hardware tab → MTU: 9000

### Verify Connection

```bash
# From Mac
ping -c 3 10.10.10.1
# Should show <1ms latency

# Speed test
iperf3 -c 10.10.10.1
# Should show ~9.4 Gbps
```

### SSH Config

Add to `~/.ssh/config` on your Mac:

```
# Direct 10GbE link (fast!)
Host workstation
    HostName 10.10.10.1
    User ubuntu
    IdentityFile ~/.ssh/workstation_key

# Tailscale fallback (when not at desk)
Host workstation-ts
    HostName workstation.tailnet-name.ts.net
    User ubuntu
    IdentityFile ~/.ssh/workstation_key
```

Shell aliases in `~/.zshrc`:

```bash
# Direct link (10GbE)
alias ws='ssh workstation'

# Tailscale fallback
alias ws-ts='ssh workstation-ts'
```

---

## Verified File Transfers

These shell functions provide **SCP with SHA-256 verification**, essential for large files where silent corruption can happen.

### The Functions

```bash
# Generic upload with verification
_verified_upload() {
  local key="$1" host="$2" remote_dir="$3" src="$4"
  local filename="${src:t}"  # zsh: basename
  local dest="$remote_dir/$filename"

  [[ ! -f "$src" ]] && { echo "Error: file not found: $src" >&2; return 1; }

  local local_size=$(stat -f%z "$src" 2>/dev/null || stat -c%s "$src" 2>/dev/null)
  local local_sha=$(shasum -a 256 "$src" | awk '{print $1}')

  echo "Uploading: $src -> $host:$dest"
  echo "Local size: $(numfmt --to=iec $local_size 2>/dev/null || echo "$local_size bytes")"

  local start_time=$SECONDS
  scp -i "$key" "$src" "$host:$dest" || { echo "Error: scp failed" >&2; return 1; }
  local elapsed=$((SECONDS - start_time))
  [[ $elapsed -eq 0 ]] && elapsed=1

  local speed=$((local_size / elapsed))
  echo "Transfer complete in ${elapsed}s ($(numfmt --to=iec $speed 2>/dev/null || echo "$speed bytes")/s)"

  echo "Verifying SHA-256..."
  local remote_sha=$(ssh -i "$key" "$host" "shasum -a 256 '$dest'" | awk '{print $1}')

  if [[ "$local_sha" == "$remote_sha" ]]; then
    echo "✓ SHA-256 match: $local_sha"
  else
    echo "✗ SHA-256 MISMATCH!" >&2
    echo "  Local:  $local_sha" >&2
    echo "  Remote: $remote_sha" >&2
    return 1
  fi
}

# Generic download with verification
_verified_download() {
  local key="$1" host="$2" src="$3" local_dir="$4"
  local filename="${src:t}"
  local dest="$local_dir/$filename"

  echo "Checking remote file: $src"
  local remote_size=$(ssh -i "$key" "$host" "stat --printf='%s' '$src'" 2>/dev/null)
  [[ -z "$remote_size" ]] && { echo "Error: remote file not found: $src" >&2; return 1; }

  local remote_sha=$(ssh -i "$key" "$host" "shasum -a 256 '$src'" | awk '{print $1}')

  echo "Downloading: $host:$src -> $dest"
  echo "Remote size: $(numfmt --to=iec $remote_size 2>/dev/null || echo "$remote_size bytes")"

  local start_time=$SECONDS
  scp -i "$key" "$host:$src" "$dest" || { echo "Error: scp failed" >&2; return 1; }
  local elapsed=$((SECONDS - start_time))
  [[ $elapsed -eq 0 ]] && elapsed=1

  local speed=$((remote_size / elapsed))
  echo "Transfer complete in ${elapsed}s ($(numfmt --to=iec $speed 2>/dev/null || echo "$speed bytes")/s)"

  echo "Verifying SHA-256..."
  local local_sha=$(shasum -a 256 "$dest" | awk '{print $1}')

  if [[ "$local_sha" == "$remote_sha" ]]; then
    echo "✓ SHA-256 match: $local_sha"
  else
    echo "✗ SHA-256 MISMATCH!" >&2
    echo "  Remote: $remote_sha" >&2
    echo "  Local:  $local_sha" >&2
    return 1
  fi
}
```

### Per-Server Aliases

```bash
# Upload to workstation
ws-file() {
  [[ -z "$1" ]] && { echo "Usage: ws-file <local_path>" >&2; return 1; }
  _verified_upload "$HOME/.ssh/workstation_key" \
    "ubuntu@10.10.10.1" "/data/projects" "$1"
}

# Download from workstation
ws-file-get() {
  [[ -z "$1" ]] && { echo "Usage: ws-file-get <remote_path>" >&2; return 1; }
  _verified_download "$HOME/.ssh/workstation_key" \
    "ubuntu@10.10.10.1" "$1" "$HOME/projects"
}
```

### Example Output

```
$ ws-file huge-dataset.tar.gz
Uploading: huge-dataset.tar.gz -> ubuntu@10.10.10.1:/data/projects/huge-dataset.tar.gz
Local size: 15G
Transfer complete in 18s (853M/s)
Verifying SHA-256...
✓ SHA-256 match: a3f2b8c9d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1
```

---

## Clipboard Sync

Moonlight and other remote desktop solutions often don't sync clipboard. These aliases solve that:

```bash
# Copy Mac clipboard TO Linux (Wayland)
alias cptl='pbpaste | ssh workstation "wl-copy"'

# Copy FROM Linux to Mac
alias cpfm='ssh workstation "wl-paste" | pbcopy'
```

For X11 systems, use `xclip` instead:

```bash
alias cptl='pbpaste | ssh workstation "xclip -selection clipboard"'
alias cpfm='ssh workstation "xclip -selection clipboard -o" | pbcopy'
```

### Usage

```bash
# Copy something on Mac, then:
cptl
# Now it's on Linux clipboard

# Copy something on Linux, then:
cpfm
# Now it's on Mac clipboard
```

---

## Remote Display Wake

When using remote desktop (Moonlight, Sunshine, etc.), the display sometimes goes to sleep and the GPU disconnects from DRM, breaking streaming.

```bash
# Wake up remote display with a fake keypress
alias wu='ssh workstation "DISPLAY=:0 xdotool key shift"'
```

For Wayland with Hyprland:

```bash
alias wu='ssh workstation "hyprctl dispatch dpms on"'
```

---

## Modern CLI Tool Replacements

These Rust-based tools are faster and more user-friendly than their traditional counterparts:

```bash
# lsd: ls with icons, colors, and git status
alias ls='lsd --inode --long --all --hyperlink=auto'

# bat: cat with syntax highlighting and line numbers
alias cat='bat'

# dust: du with visual size representation
alias du='dust'
```

### Install on macOS

```bash
brew install lsd bat dust
```

### Install on Linux

```bash
# Ubuntu/Debian
sudo apt install lsd bat
cargo install du-dust  # or download from GitHub releases

# Arch
sudo pacman -S lsd bat dust
```

---

## AI Coding Agent Aliases

Unified aliases for all three major AI coding agents:

```bash
# Claude Code (native install)
alias cc='~/.local/bin/claude --dangerously-skip-permissions'

# Gemini CLI
alias gmi='gemini --yolo --model gemini-2.5-pro'

# Codex (OpenAI)
alias cod='codex --dangerously-bypass-approvals-and-sandbox'

# Update all agents at once
alias uca='~/.local/bin/claude update && bun install -g @openai/codex@latest && bun install -g @google/gemini-cli@latest'
```

The `uca` (Update Coding Agents) alias keeps all three agents current with a single command.

---

## Quick Reference

### Shell Aliases Summary

| Alias | What it does |
|:------|:-------------|
| `ws` | SSH to workstation via 10GbE direct link |
| `ws-ts` | SSH to workstation via Tailscale (fallback) |
| `ws-file <path>` | Upload file with SHA-256 verification |
| `ws-file-get <path>` | Download file with SHA-256 verification |
| `cptl` | Copy Mac clipboard to Linux |
| `cpfm` | Copy Linux clipboard to Mac |
| `wu` | Wake up remote display |
| `cc` | Claude Code |
| `gmi` | Gemini CLI |
| `cod` | Codex |
| `uca` | Update all coding agents |

### Performance Numbers

| Metric | Through Switch | Direct 10GbE |
|:-------|:---------------|:-------------|
| Bandwidth | ~112 MB/s | ~850 MB/s |
| Latency | 0.5-1ms | <0.1ms |
| Large file (10GB) | ~90 sec | ~12 sec |

### Hardware Checklist

- [ ] Thunderbolt to 10GbE adapter (~$85)
- [ ] Cat6/Cat6A cable (length you need)
- [ ] Workstation with 10GbE port (check if yours has one!)
- [ ] Static IPs configured (10.10.10.x/24)
- [ ] Jumbo frames enabled (MTU 9000) for best throughput

---

## Troubleshooting

| Symptom | Cause | Fix |
|:--------|:------|:----|
| Link doesn't come up | Cable issue or interface down | Check `ip link show eno1`; try different cable |
| Slow speeds (<1Gbps) | Cat5e cable or MTU mismatch | Use Cat6; ensure both ends have same MTU |
| Works locally, not over Tailscale | Using wrong alias | Use `ws-ts` when not at desk |
| SHA mismatch after transfer | Disk issue or corruption | Re-transfer; check disk health |
| Clipboard sync fails | wl-copy/xclip not installed | Install wayland-utils or xclip on Linux |

---

*Last updated: January 2026*
