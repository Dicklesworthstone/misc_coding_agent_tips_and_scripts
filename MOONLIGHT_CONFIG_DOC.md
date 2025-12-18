# Moonlight Streaming Setup - threadripperje

## Quick Reference

| Command/App | What it does |
|-------------|--------------|
| `ml` | Start Moonlight streaming to threadripperje (AV1, 3072x1728@30fps) |
| `trj` | SSH into threadripperje |
| `wu` | Wake up the remote display if it went to sleep |
| `cptl` | Copy Mac clipboard → Linux |
| `cpfm` | Copy Linux clipboard → Mac |
| **apptab.app** | Toggle between Moonlight and Mac desktop (map to mouse button) |
| **cptl.app** | Clipboard to Linux (map to mouse button) |
| **cpfm.app** | Clipboard from Linux (map to mouse button) |

## The Setup

### Server (threadripperje)
- **GPU**: Dual RTX 4090
- **Streaming Server**: Sunshine (running as user service)
- **Compositor**: Hyprland (Wayland)
- **Display**: Dell U3224KB 6K via DP-5 on card3 (renderD129)

### Sunshine Config (`~/.config/sunshine/sunshine.conf`)
```
adapter_name = /dev/dri/renderD129
output_name = 0
capture = kms
encoder = nvenc
```

### Client (Mac)
- **App**: Custom Moonlight build with AV1 support (`~/Downloads/Moonlight.app`)
- **Script**: `~/bin/ml`

## Common Issues & Fixes

### "GPU doesn't support AV1" or "Couldn't find monitor"
The display went to sleep and disconnected from DRM.

**Fix:**
1. Run `wu` to try waking it, OR
2. Toggle the physical monitor off/on
3. Then restart Sunshine: `ssh ubuntu@threadripperje "systemctl --user restart sunshine"`

### Display keeps sleeping
We disabled this by:
- Disabling hypridle: commented out `exec-once = hypridle` in `~/.config/hypr/configs/Startup_Apps.conf`
- Enabling NVIDIA persistence mode: `sudo nvidia-smi -pm 1`

### Can't escape Moonlight fullscreen
- **Hot corner**: Set up a macOS hot corner for Mission Control
- **Mouse button**: Map a button to `apptab.app` which toggles between Moonlight and Mac desktop

### Clipboard doesn't sync
Moonlight doesn't sync clipboards. Use:
- Terminal: `cptl` / `cpfm`
- Mouse buttons: Map to `cptl.app` / `cpfm.app`

## Files Modified

### Mac
- `~/.zshrc` - aliases: `ml`, `trj`, `wu`, `cptl`, `cpfm`
- `~/bin/ml` - Moonlight launch script
- `/Applications/apptab.app` - Toggle Moonlight/Mac spaces
- `/Applications/cptl.app` - Clipboard to Linux
- `/Applications/cpfm.app` - Clipboard from Linux

### threadripperje
- `~/.config/sunshine/sunshine.conf` - Sunshine streaming config
- `~/.config/hypr/configs/Startup_Apps.conf` - Disabled hypridle
- NVIDIA persistence mode enabled

## Mouse Button Setup (BetterMouse)

Map extra mouse buttons to these apps in `/Applications/`:
1. **apptab** - Toggle between Moonlight and Mac (most useful)
2. **cptl** - Send clipboard to Linux
3. **cpfm** - Get clipboard from Linux
