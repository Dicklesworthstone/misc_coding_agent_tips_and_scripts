# WezTerm Mux Performance Tuning for AI Agent Swarms

> **TL;DR:** Running 20+ AI agents overwhelms wezterm-mux-server defaults. This guide provides RAM-optimized configs that trade memory for throughput, with linear interpolation for any RAM size.

```
Quick Start:  curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/wezterm-mux-tune.sh | bash
              Then:  pkill -9 -f wezterm-mux && wezterm-mux-server --daemonize
```

---

## At a Glance

| Setting | Default | 512GB Profile | Effect |
|:--------|--------:|-------------:|:-------|
| `scrollback_lines` | 3,500 | 10,000,000 | History per pane |
| `mux_output_parser_buffer_size` | 128 KB | 16 MB | Output batch size |
| `mux_output_parser_coalesce_delay_ms` | 3 ms | 1 ms | Parse latency |
| `ratelimit_mux_line_prefetches_per_second` | 50 | 1,000 | Scroll speed |
| `shape_cache_size` | 1,024 | 65,536 | Font shaping cache |

**Profiles:** [64GB](#profile-64gb-ram-conservative) ・ [128GB](#profile-128gb-ram-moderate) ・ [256GB](#profile-256gb-ram-aggressive) ・ [512GB](#profile-512gb-ram-maximum)

---

## Table of Contents

- [The Problem](#the-agent-swarm-problem)
- [Settings Explained](#how-each-setting-helps)
- [Configuration Profiles](#tiered-configuration-profiles)
- [Installation](#installation)
- [Emergency Rescue](#emergency-session-rescue)
- [Monitoring](#monitoring-and-diagnostics)
- [Troubleshooting](#troubleshooting)

---

## The Agent Swarm Problem

When running AI coding agents (Claude Code, Codex, Gemini CLI), each agent:

1. **Produces continuous output** — tool calls, code diffs, test results
2. **Runs for hours** — accumulating massive scrollback
3. **Spawns subprocesses** — tests, builds, linters
4. **Operates in parallel** — 20+ simultaneous output streams

```
┌─────────────────────────────────────────────────────────────────┐
│                     AGENT SWARM PRESSURE                        │
│                                                                 │
│   Agent 1    Agent 2    Agent 3         Agent N                 │
│      │          │          │               │                    │
│      ▼          ▼          ▼               ▼                    │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │              wezterm-mux-server                         │   │
│   │                                                         │   │
│   │   Defaults:  128KB buffer  │  3,500 scrollback         │   │
│   │              1,024 cache   │  50 prefetch/sec          │   │
│   │                                                         │   │
│   │   Problem:   Buffers overflow → parser bottleneck       │   │
│   │              Caches thrash  → CPU spikes                │   │
│   │              Result: UNRESPONSIVE SERVER                │   │
│   └─────────────────────────────────────────────────────────┘   │
│                            │                                    │
│                            ▼                                    │
│              Connection Timeout / Session Loss                  │
└─────────────────────────────────────────────────────────────────┘
```

### Default vs Reality

| Assumption | Reality with Swarms |
|:-----------|:--------------------|
| ~100 lines/sec | 1,000+ lines/sec across panes |
| Occasional scrollback | Scrollback is primary debug tool |
| Few panes | 20+ panes, all active |
| Cache hits common | Rapid changes → cache misses |

### Failure Cascade

1. Output buffer fills → parser falls behind
2. Coalesce delay accumulates → lag builds
3. Caches thrash → CPU spikes on render
4. Socket buffers fill → connection hangs
5. You restart mux → **all sessions die**

---

## How Each Setting Helps

### `scrollback_lines`

| | |
|:--|:--|
| **Default** | 3,500 |
| **Purpose** | Maximum history lines per pane |
| **Problem** | A single `cargo build` produces 10,000+ lines |

**Recommended values:**

| RAM | Value | Memory Headroom |
|----:|------:|:----------------|
| 64 GB | 1,000,000 | ~6 GB |
| 128 GB | 2,000,000 | ~12 GB |
| 256 GB | 5,000,000 | ~30 GB |
| 512 GB | 10,000,000 | ~60 GB |

```lua
config.scrollback_lines = 10000000
```

---

### `mux_output_parser_buffer_size`

| | |
|:--|:--|
| **Default** | 128 KB |
| **Purpose** | Buffer for raw PTY output before parsing |
| **Problem** | Small buffer forces frequent small parses |

**Recommended values:**

| RAM | Value | Handles |
|----:|------:|:--------|
| 64 GB | 2 MB | Moderate bursts |
| 128 GB | 4 MB | Large diffs |
| 256 GB | 8 MB | Test suite output |
| 512 GB | 16 MB | Anything |

```lua
config.mux_output_parser_buffer_size = 16 * 1024 * 1024
```

---

### `mux_output_parser_coalesce_delay_ms`

| | |
|:--|:--|
| **Default** | 3 ms |
| **Purpose** | Wait time to batch fragmented writes |
| **Problem** | 3ms × 1,000 chunks/sec = 3 sec accumulated lag |

**Recommended values:**

| Use Case | Value |
|:---------|------:|
| TUI-heavy (vim, htop) | 3 ms |
| Agent swarms | 1 ms |
| Benchmarking | 0 ms |

```lua
config.mux_output_parser_coalesce_delay_ms = 1
```

---

### `ratelimit_mux_line_prefetches_per_second`

| | |
|:--|:--|
| **Default** | 50 |
| **Purpose** | Scroll prefetch rate |
| **Problem** | At 50/sec, scrolling 10,000 lines takes 200 seconds |

**Recommended:** 500–1000 for all systems

```lua
config.ratelimit_mux_line_prefetches_per_second = 1000
```

---

### Cache Settings

WezTerm maintains several caches to avoid expensive recomputation:

| Cache | Default | Purpose |
|:------|--------:|:--------|
| `shape_cache_size` | 1,024 | Font shaping results |
| `line_state_cache_size` | 1,024 | Line colors/attributes |
| `line_quad_cache_size` | 1,024 | GPU render geometry |
| `line_to_ele_shape_cache_size` | 1,024 | Line-to-element mapping |
| `glyph_cache_image_cache_size` | 256 | Rasterized glyphs |

**Recommended values by RAM:**

| RAM | shape | line_state | line_quad | line_to_ele | glyph |
|----:|------:|-----------:|----------:|------------:|------:|
| 64 GB | 8,192 | 8,192 | 8,192 | 8,192 | 512 |
| 128 GB | 16,384 | 16,384 | 16,384 | 16,384 | 1,024 |
| 256 GB | 32,768 | 32,768 | 32,768 | 32,768 | 2,048 |
| 512 GB | 65,536 | 65,536 | 65,536 | 65,536 | 4,096 |

```lua
config.shape_cache_size = 65536
config.line_state_cache_size = 65536
config.line_quad_cache_size = 65536
config.line_to_ele_shape_cache_size = 65536
config.glyph_cache_image_cache_size = 4096
```

---

## Tiered Configuration Profiles

### Profile: 64GB RAM (Conservative)

<details>
<summary><strong>View configuration</strong> — Est. 3-8 GB under load</summary>

```lua
-- ============================================================
-- PERFORMANCE TUNING (64GB system)
-- ============================================================
config.scrollback_lines = 1000000
config.mux_output_parser_buffer_size = 2 * 1024 * 1024
config.mux_output_parser_coalesce_delay_ms = 2
config.ratelimit_mux_line_prefetches_per_second = 500
config.shape_cache_size = 8192
config.line_state_cache_size = 8192
config.line_quad_cache_size = 8192
config.line_to_ele_shape_cache_size = 8192
config.glyph_cache_image_cache_size = 512
```

</details>

---

### Profile: 128GB RAM (Moderate)

<details>
<summary><strong>View configuration</strong> — Est. 5-15 GB under load</summary>

```lua
-- ============================================================
-- PERFORMANCE TUNING (128GB system)
-- ============================================================
config.scrollback_lines = 2000000
config.mux_output_parser_buffer_size = 4 * 1024 * 1024
config.mux_output_parser_coalesce_delay_ms = 1
config.ratelimit_mux_line_prefetches_per_second = 750
config.shape_cache_size = 16384
config.line_state_cache_size = 16384
config.line_quad_cache_size = 16384
config.line_to_ele_shape_cache_size = 16384
config.glyph_cache_image_cache_size = 1024
```

</details>

---

### Profile: 256GB RAM (Aggressive)

<details>
<summary><strong>View configuration</strong> — Est. 8-25 GB under load</summary>

```lua
-- ============================================================
-- HIGH-RAM PERFORMANCE TUNING (256GB system)
-- ============================================================
config.scrollback_lines = 5000000
config.mux_output_parser_buffer_size = 8 * 1024 * 1024
config.mux_output_parser_coalesce_delay_ms = 1
config.ratelimit_mux_line_prefetches_per_second = 500
config.shape_cache_size = 32768
config.line_state_cache_size = 32768
config.line_quad_cache_size = 32768
config.line_to_ele_shape_cache_size = 32768
config.glyph_cache_image_cache_size = 2048
```

</details>

---

### Profile: 512GB RAM (Maximum)

<details>
<summary><strong>View configuration</strong> — Est. 15-60 GB under load</summary>

```lua
-- ============================================================
-- HIGH-RAM PERFORMANCE TUNING (512GB system)
-- ============================================================
config.scrollback_lines = 10000000
config.mux_output_parser_buffer_size = 16 * 1024 * 1024
config.mux_output_parser_coalesce_delay_ms = 1
config.ratelimit_mux_line_prefetches_per_second = 1000
config.shape_cache_size = 65536
config.line_state_cache_size = 65536
config.line_quad_cache_size = 65536
config.line_to_ele_shape_cache_size = 65536
config.glyph_cache_image_cache_size = 4096
```

</details>

---

## Installation

### Automatic (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/wezterm-mux-tune.sh | bash
```

The script uses **linear interpolation** to calculate optimal settings based on your actual RAM, rather than snapping to fixed tiers. A 200GB system gets settings proportionally between the 128GB and 256GB anchor points.

**Script options:**

```bash
./wezterm-mux-tune.sh              # Auto-detect RAM, interpolate settings
./wezterm-mux-tune.sh --dry-run    # Preview without applying
./wezterm-mux-tune.sh --ram 200    # Calculate for specific RAM amount
./wezterm-mux-tune.sh --profile 256  # Use exact fixed profile
./wezterm-mux-tune.sh --restore    # Restore from backup
./wezterm-mux-tune.sh --help       # Show all options
```

**Anchor points for interpolation:**

| RAM | scrollback | buffer | caches | prefetch |
|----:|-----------:|-------:|-------:|---------:|
| 64 GB | 1M | 2 MB | 8K | 500 |
| 128 GB | 2M | 4 MB | 16K | 750 |
| 256 GB | 5M | 8 MB | 32K | 500 |
| 512 GB | 10M | 16 MB | 64K | 1000 |

Values extrapolate linearly beyond this range (e.g., 768GB gets ~15M scrollback, 24MB buffer).

### Manual

1. **Backup:**
   ```bash
   cp ~/.wezterm.lua ~/.wezterm.lua.backup
   ```

2. **Edit** `~/.wezterm.lua` — add profile before `return config`

3. **Restart mux:**
   ```bash
   pkill -9 -f wezterm-mux && wezterm-mux-server --daemonize
   ```

4. **Reconnect** your client

---

## Emergency Session Rescue

> **Scenario:** Mux server is unresponsive, but you have agent sessions you need to save.

### Why This Is Hard

Agent processes are attached to wezterm's PTYs. Kill wezterm → PTYs close → agents die.

### Solution: `reptyr -T`

`reptyr` can steal terminal attachments via ptrace. The `-T` flag handles processes with subprocesses.

### Procedure

<details>
<summary><strong>Full rescue script</strong></summary>

```bash
# 1. Connect via plain SSH (bypass broken mux)
ssh user@host

# 2. Install reptyr
sudo apt-get install -y reptyr

# 3. Enable ptrace
sudo sysctl -w kernel.yama.ptrace_scope=0

# 4. Create tmux rescue session
tmux new-session -d -s rescue -x 200 -y 50

# 5. Find agent PIDs
ps -eo pid,args | grep -E 'claude --dangerously|codex --dangerously' | grep -v grep

# 6. Migrate each agent
for pid in $(ps -eo pid,args | grep -E 'claude --dangerously|codex --dangerously' | grep -v grep | awk '{print $1}'); do
  tmux new-window -t rescue -n "agent-$pid"
  tmux send-keys -t "rescue:agent-$pid" "reptyr -T $pid" Enter
  sleep 0.5
done

# 7. Verify
for win in $(tmux list-windows -t rescue -F "#{window_name}" | grep agent); do
  tmux capture-pane -t "rescue:$win" -p | grep -qE "bypass|Claude" && echo "OK: $win" || echo "FAILED: $win"
done

# 8. Kill broken wezterm (safe now)
pkill -9 -f wezterm-mux

# 9. Restore ptrace security
sudo sysctl -w kernel.yama.ptrace_scope=1

# 10. Restart mux
wezterm-mux-server --daemonize

# 11. Attach to rescued sessions
tmux attach -t rescue
```

</details>

### Success Rate

Typically **50–70%** of sessions migrate successfully.

| Factor | Impact |
|:-------|:-------|
| Process age | Older = more reliable |
| Subprocess count | Fewer = better |
| Activity level | Idle = better |
| Protections | Some block ptrace |

---

## Monitoring and Diagnostics

### Mux Server Health

```bash
# Running?
ps aux | grep wezterm-mux | grep -v grep

# Recent logs
tail -20 /run/user/$(id -u)/wezterm/wezterm-mux-server-log-*.txt

# Socket status
ls -la /run/user/$(id -u)/wezterm/sock
```

### System Resources

```bash
# Load vs cores
echo "Load: $(uptime | awk -F'load average:' '{print $2}') / $(nproc) cores"

# Memory
free -h | awk '/Mem:/{print "Memory: " $7 " available of " $2}'

# File descriptors
cat /proc/sys/fs/file-nr | awk '{print "FDs: " $1 "/" $3}'
```

### Live Monitoring

```bash
watch -n1 'ps aux | grep wezterm-mux | grep -v grep | awk "{print \"RSS: \" \$6/1024 \"MB\"}"'
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|:--------|:------|:----|
| Connection timeout | Buffer overflow | ↑ `mux_output_parser_buffer_size` |
| Laggy scrolling | Low prefetch rate | ↑ `ratelimit_mux_line_prefetches_per_second` |
| High CPU on render | Cache thrashing | ↑ all cache sizes |
| Truncated history | Small scrollback | ↑ `scrollback_lines` |
| "Broken pipe" in logs | Client disconnect | Check network stability |
| reptyr "Operation not permitted" | ptrace blocked | `sudo sysctl -w kernel.yama.ptrace_scope=0` |

---

## See Also

- [WezTerm Persistent Remote Sessions](WEZTERM_PERSISTENT_REMOTE_SESSIONS.md)
- [WezTerm Multiplexing Docs](https://wezterm.org/multiplexing.html)
- [WezTerm Scrollback Docs](https://wezterm.org/scrollback.html)

---

<sub>Last updated: January 2026</sub>
