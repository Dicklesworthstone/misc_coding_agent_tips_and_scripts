# Moonlight Streaming Setup

Remote desktop streaming from a Linux workstation (Hyprland/Wayland, dual RTX 4090) to Mac using Moonlight with AV1 encoding.

---

## Quick Reference

| Command | What it does |
|:--------|:-------------|
| `ml` | Start Moonlight streaming (AV1, 3072x1728@30fps) |
| `trj` | SSH into threadripperje |
| `wu` | Wake up the remote display if it went to sleep |
| `cptl` | Copy Mac clipboard to Linux |
| `cpfm` | Copy Linux clipboard to Mac |

| App | What it does |
|:----|:-------------|
| `apptab.app` | Toggle between Moonlight and Mac desktop (map to mouse button) |
| `cptl.app` | Clipboard to Linux (map to mouse button) |
| `cpfm.app` | Clipboard from Linux (map to mouse button) |

---

## Server Setup (threadripperje)

| Component | Configuration |
|:----------|:--------------|
| GPU | Dual RTX 4090 |
| Streaming Server | Sunshine (user service) |
| Compositor | Hyprland (Wayland) |
| Display | Dell U3224KB 6K via DP-5 on card3 (renderD129) |

### Sunshine Config

`~/.config/sunshine/sunshine.conf`:

```ini
adapter_name = /dev/dri/renderD129
output_name = 0
capture = kms
encoder = nvenc
```

---

## Client Setup (Mac)

| Component | Location |
|:----------|:---------|
| App | Custom Moonlight build with AV1 support (`~/Downloads/Moonlight.app`) |
| Launch script | `~/bin/ml` |

---

## Troubleshooting

| Problem | Cause | Fix |
|:--------|:------|:----|
| "GPU doesn't support AV1" | Display went to sleep, disconnected from DRM | Run `wu`, or toggle monitor power, then `ssh ubuntu@threadripperje "systemctl --user restart sunshine"` |
| "Couldn't find monitor" | Same as above | Same as above |
| Display keeps sleeping | hypridle running, NVIDIA persistence off | Comment out `exec-once = hypridle` in Hyprland config; run `sudo nvidia-smi -pm 1` |
| Can't escape fullscreen | No way to switch apps | Set macOS hot corner for Mission Control, or map mouse button to `apptab.app` |
| Clipboard doesn't sync | Moonlight limitation | Use `cptl`/`cpfm` commands or map mouse buttons to the `.app` versions |

---

## Files Modified

### Mac

| File | Purpose |
|:-----|:--------|
| `~/.zshrc` | Aliases: `ml`, `trj`, `wu`, `cptl`, `cpfm` |
| `~/bin/ml` | Moonlight launch script |
| `/Applications/apptab.app` | Toggle Moonlight/Mac spaces |
| `/Applications/cptl.app` | Clipboard to Linux |
| `/Applications/cpfm.app` | Clipboard from Linux |

### threadripperje

| File | Purpose |
|:-----|:--------|
| `~/.config/sunshine/sunshine.conf` | Sunshine streaming config |
| `~/.config/hypr/configs/Startup_Apps.conf` | Disabled hypridle |
| NVIDIA settings | Persistence mode enabled (`nvidia-smi -pm 1`) |

---

## Mouse Button Setup (BetterMouse)

Map extra mouse buttons to these apps in `/Applications/`:

| Button | App | Function |
|:-------|:----|:---------|
| Thumb back | `apptab.app` | Toggle between Moonlight and Mac (most useful) |
| Thumb forward | `cptl.app` | Send clipboard to Linux |
| Side button | `cpfm.app` | Get clipboard from Linux |

---

*Last updated: January 2026*
