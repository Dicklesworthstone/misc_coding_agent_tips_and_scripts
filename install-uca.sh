#!/usr/bin/env bash
#
# install-uca.sh — Universal Coding Agent (UCA) Harness Updater & Status Dashboard Installer
#
# Production-grade installer built using the /installer-workmanship standard:
#   • Gum styling with automatic ANSI double-line box fallback
#   • Atomic locking with stale PID detection
#   • Dual platform background services (systemd user timers on Linux, launchd on macOS)
#   • Automatic shell integration for bash, zsh, and fish
#   • AI agent harness detection (Claude Code, Codex, Antigravity, Grok, OMP)
#   • Post-install diagnostics & self-test
#
# Usage:
#   ./install-uca.sh              # Standard user-level install (~/.local/bin)
#   ./install-uca.sh --system     # System-wide install (/usr/local/bin, requires sudo)
#   ./install-uca.sh --uninstall  # Stop service/timer and remove binaries
#   ./install-uca.sh --dry-run    # Preview actions without making changes
#   ./install-uca.sh --no-gum     # Force pure ANSI output
#   ./install-uca.sh --quiet      # Minimal output
#
# One-liner curl install:
#   curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-uca.sh?$(date +%s)" | bash

set -euo pipefail
shopt -s lastpipe 2>/dev/null || true
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
TEMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'uca-install')"
LOCK_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/uca/.install-lock"

QUIET=0
NO_GUM=0
FORCE=0
DRY_RUN=0
UNINSTALL=0
SYSTEM_MODE=0
IGNORE_DISK_SPACE=0
MIN_DISK_MB=500

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --quiet|-q)       QUIET=1 ;;
    --no-gum)         NO_GUM=1 ;;
    --force|-f)       FORCE=1 ;;
    --dry-run)        DRY_RUN=1 ;;
    --uninstall)      UNINSTALL=1 ;;
    --system)         SYSTEM_MODE=1 ;;
    --ignore-disk-space) IGNORE_DISK_SPACE=1 ;;
    --min-disk-mb=*)  MIN_DISK_MB="${arg#*=}" ;;
    --help|-h)
      echo "Usage: ./install-uca.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --quiet, -q          Minimal output"
      echo "  --no-gum             Force ANSI fallback output (disable gum)"
      echo "  --force, -f          Force overwrite and reinstallation"
      echo "  --dry-run            Preview actions without modifying system"
      echo "  --system             Install to /usr/local/bin (requires root)"
      echo "  --ignore-disk-space  Bypass disk space safety checks"
      echo "  --min-disk-mb <N>    Minimum free disk space in MB (default: 500)"
      echo "  --uninstall          Remove UCA, UCAS, and background timers"
      echo "  --help, -h           Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

# Cleanup trap
cleanup() {
  local exit_code=$?
  if [ -d "$LOCK_DIR" ]; then
    local pid_file="$LOCK_DIR/pid"
    if [ -f "$pid_file" ] && [ "$(cat "$pid_file" 2>/dev/null || echo "")" = "$$" ]; then
      rm -f "$pid_file" 2>/dev/null || true
      rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
  fi
  rm -rf "$TEMP_DIR" 2>/dev/null || true
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

# Proxy setup
PROXY_ARGS=()
if [ -n "${HTTPS_PROXY:-}" ]; then
  PROXY_ARGS=(--proxy "$HTTPS_PROXY")
elif [ -n "${HTTP_PROXY:-}" ]; then
  PROXY_ARGS=(--proxy "$HTTP_PROXY")
fi

# Gum detection
HAS_GUM=0
if command -v gum &>/dev/null && [ -t 1 ] && [ "$NO_GUM" -eq 0 ]; then
  HAS_GUM=1
fi

# Logging functions (Gum + ANSI fallback)
info() {
  [ "$QUIET" -eq 1 ] && return 0
  if [ "$HAS_GUM" -eq 1 ]; then
    gum style --foreground 39 "-> $*"
  else
    echo -e "\033[38;5;39m->\033[0m $*"
  fi
}

ok() {
  [ "$QUIET" -eq 1 ] && return 0
  if [ "$HAS_GUM" -eq 1 ]; then
    gum style --foreground 42 "✔ $*"
  else
    echo -e "\033[38;5;42m✔\033[0m $*"
  fi
}

warn() {
  if [ "$HAS_GUM" -eq 1 ]; then
    gum style --foreground 214 "⚠️  $*"
  else
    echo -e "\033[38;5;214m⚠️  $*\033[0m"
  fi
}

err() {
  if [ "$HAS_GUM" -eq 1 ]; then
    gum style --foreground 196 "✗ $*" >&2
  else
    echo -e "\033[38;5;196m✗ $*\033[0m" >&2
  fi
}

run_with_spinner() {
  local title="$1"; shift
  if [ "$HAS_GUM" -eq 1 ] && [ "$QUIET" -eq 0 ]; then
    gum spin --spinner dot --title "$title" -- "$@"
  else
    info "$title"
    "$@"
  fi
}

# ANSI Box Drawing Fallback
draw_box() {
  local color_code="$1"; shift
  local lines=("$@")
  local max_len=0
  local strip_regex=$'\x1b\\[[0-9;]*[a-zA-Z]'

  for line in "${lines[@]}"; do
    local plain
    plain=$(echo -e "$line" | sed -E "s/${strip_regex}//g")
    local len=${#plain}
    [ "$len" -gt "$max_len" ] && max_len=$len
  done

  local width=$((max_len + 4))
  local border=""
  for ((i=0; i<width; i++)); do border+="═"; done

  echo -e "\033[38;5;${color_code}m╔${border}╗\033[0m"
  for line in "${lines[@]}"; do
    local plain
    plain=$(echo -e "$line" | sed -E "s/${strip_regex}//g")
    local pad=$((max_len - ${#plain}))
    local pad_spaces=""
    for ((i=0; i<pad; i++)); do pad_spaces+=" "; done
    echo -e "\033[38;5;${color_code}m║\033[0m  ${line}${pad_spaces}  \033[38;5;${color_code}m║\033[0m"
  done
  echo -e "\033[38;5;${color_code}m╚${border}╝\033[0m"
}

# Platform Detection
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="arm64" ;;
esac

IS_WSL=0
if [ "$OS" = "linux" ] && grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=1
fi

# Determine Destination Paths
if [ "$SYSTEM_MODE" -eq 1 ]; then
  DEST_DIR="/usr/local/bin"
  STATE_DIR="/var/lib/uca"
else
  DEST_DIR="${HOME}/.local/bin"
  STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/uca"
fi

BINARY_PATH="${DEST_DIR}/uca"
SYMLINK_PATH="${DEST_DIR}/ucas"

# Branded Header Banner
if [ "$QUIET" -eq 0 ]; then
  if [ "$HAS_GUM" -eq 1 ]; then
    gum style \
      --border rounded \
      --border-foreground 39 \
      --padding "0 1" \
      --margin "1 0" \
      "$(gum style --foreground 42 --bold 'UCA & UCAS INSTALLER')" \
      "$(gum style --foreground 245 'Universal Coding Agent Harness Auto-Updater & Version Tracker')" \
      "$(gum style --foreground 245 'Target: ') $(gum style --bold --foreground 252 "$BINARY_PATH")"
  else
    banner_lines=(
      "\033[1;38;5;42mUCA & UCAS INSTALLER\033[0m"
      "\033[38;5;245mUniversal Coding Agent Harness Auto-Updater & Version Tracker\033[0m"
      "\033[38;5;245mTarget: \033[1;38;5;252m${BINARY_PATH}\033[0m"
    )
    draw_box 39 "${banner_lines[@]}"
  fi
fi

# Atomic Locking (mkdir-based with stale PID detection)
acquire_lock() {
  mkdir -p "$(dirname "$LOCK_DIR")"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    local pid_file="$LOCK_DIR/pid"
    if [ -f "$pid_file" ]; then
      local old_pid
      old_pid=$(cat "$pid_file" 2>/dev/null || echo "")
      if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
        err "Another installer instance (PID $old_pid) is currently running."
        exit 1
      fi
    fi
    # Reclaim stale lock
    rm -rf "$LOCK_DIR" 2>/dev/null || true
    mkdir -p "$LOCK_DIR"
  fi
  echo "$$" > "$LOCK_DIR/pid"
}
acquire_lock

# Uninstall Flow
if [ "$UNINSTALL" -eq 1 ]; then
  info "Uninstalling UCA, UCAS, and background services..."
  
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  would disable background service and remove $BINARY_PATH $SYMLINK_PATH"
    ok "Dry run complete."
    exit 0
  fi

  # Stop launchd
  if [ "$OS" = "darwin" ]; then
    local current_user="${USER:-$(whoami 2>/dev/null || echo "user")}"
    for plist_name in "com.${current_user}.uca.plist" "com.jemanuel.uca.plist" "com.uca.updater.plist"; do
      local plist_file="$HOME/Library/LaunchAgents/$plist_name"
      if [ -f "$plist_file" ]; then
        launchctl unload "$plist_file" 2>/dev/null || true
        rm -f "$plist_file" 2>/dev/null || true
        ok "Removed launchd agent ($plist_name)"
      fi
    done
  fi

  # Stop systemd
  if command -v systemctl &>/dev/null; then
    systemctl --user disable --now uca.timer 2>/dev/null || true
    systemctl --user stop uca.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/uca.service" "$HOME/.config/systemd/user/uca.timer" 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
    ok "Disabled and removed systemd user units"
  fi

  rm -f "$BINARY_PATH" "$SYMLINK_PATH" 2>/dev/null || true
  ok "Removed $BINARY_PATH and $SYMLINK_PATH"
  ok "UCA uninstalled successfully."
  exit 0
fi

# Preflight Checks
preflight_checks() {
  info "Running preflight checks..."
  
  # Check Python 3
  if ! command -v python3 &>/dev/null; then
    err "Python 3 is required but was not found in PATH."
    exit 1
  fi
  local py_ver
  py_ver=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "0.0")
  ok "Python 3 detected (v$py_ver)"

  # Check write permissions
  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$DEST_DIR" 2>/dev/null || {
      err "Cannot write to $DEST_DIR. Run with sudo or omit --system for user install."
      exit 1
    }
    mkdir -p "$STATE_DIR" 2>/dev/null || {
      err "Cannot create state directory $STATE_DIR"
      exit 1
    }
  fi
  ok "Write permissions verified for $DEST_DIR and $STATE_DIR"

  # Check disk space safety
  local free_kb free_mb min_kb
  free_kb=$(df -Pk "$DEST_DIR" 2>/dev/null | tail -1 | awk '{print $4}' || echo "1000000")
  free_mb=$((free_kb / 1024))
  min_kb=$((MIN_DISK_MB * 1024))

  if [ "$free_kb" -lt 51200 ] && [ "$IGNORE_DISK_SPACE" -eq 0 ]; then
    err "Critical disk space shortage: only ${free_mb}MB free on $DEST_DIR (minimum 50MB required)."
    err "Aborting installation to prevent disk corruption. Pass --ignore-disk-space to override."
    exit 1
  elif [ "$free_kb" -lt "$min_kb" ] && [ "$IGNORE_DISK_SPACE" -eq 0 ]; then
    warn "Low disk space on partition (${free_mb}MB free, recommended: ${MIN_DISK_MB}MB+)."
  else
    ok "Disk space check passed (${free_mb}MB free)"
  fi
}
preflight_checks

# Detect Agent Harnesses
info "Scanning for installed AI coding agent harnesses..."
CLAUDE_VER="Not installed"
CODEX_VER="Not installed"
AGY_VER="Not installed"
GROK_VER="Not installed"
OMP_VER="Not installed"

if command -v claude &>/dev/null || [ -f "$HOME/.local/bin/claude" ]; then
  CLAUDE_VER=$(claude --version 2>/dev/null || "$HOME/.local/bin/claude" --version 2>/dev/null || echo "Found")
fi
if command -v codex &>/dev/null || [ -f "$HOME/.bun/bin/codex" ] || [ -f "$HOME/.local/bin/codex" ]; then
  CODEX_VER=$(codex --version 2>/dev/null || "$HOME/.bun/bin/codex" --version 2>/dev/null || echo "Found")
fi
if command -v agy &>/dev/null || [ -f "$HOME/.local/bin/agy" ]; then
  AGY_VER=$(agy --version 2>/dev/null || "$HOME/.local/bin/agy" --version 2>/dev/null || echo "Found")
fi
if command -v grok &>/dev/null || [ -f "$HOME/.grok/bin/grok" ] || [ -f "$HOME/.local/bin/grok" ]; then
  GROK_VER=$(grok --version 2>/dev/null || "$HOME/.grok/bin/grok" --version 2>/dev/null || echo "Found")
fi
if command -v omp &>/dev/null || [ -f "$HOME/.bun/bin/omp" ] || [ -f "$HOME/.local/bin/omp" ]; then
  OMP_VER=$(omp --version 2>/dev/null || "$HOME/.bun/bin/omp" --version 2>/dev/null || echo "Found")
fi

# Acquire / Install Binary
install_uca_script() {
  local src_file=""
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/uca" ]; then
    src_file="$SCRIPT_DIR/uca"
  elif [ -f "./uca" ]; then
    src_file="./uca"
  elif [ -f "$HOME/.local/bin/uca" ]; then
    src_file="$HOME/.local/bin/uca"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  would install $src_file -> $BINARY_PATH"
    echo "  would symlink $BINARY_PATH -> $SYMLINK_PATH"
    return 0
  fi

  if [ -n "$src_file" ] && [ -f "$src_file" ]; then
    cp -f "$src_file" "$BINARY_PATH"
  else
    # Download or embedded fallback
    local remote_url="https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/uca"
    if curl -fsSL ${PROXY_ARGS[@]+"${PROXY_ARGS[@]}"} "$remote_url" -o "$TEMP_DIR/uca" 2>/dev/null; then
      cp -f "$TEMP_DIR/uca" "$BINARY_PATH"
    else
      err "Could not find local uca script or download from repository."
      exit 1
    fi
  fi

  chmod 0755 "$BINARY_PATH"
  ln -sf "$BINARY_PATH" "$SYMLINK_PATH"
  ok "Installed $BINARY_PATH (mode 0755)"
  ok "Symlinked $SYMLINK_PATH -> $BINARY_PATH"
}
run_with_spinner "Installing UCA and UCAS binaries..." install_uca_script

# Background Service Setup
configure_background_service() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  would configure 3-hour background service"
    return 0
  fi

  "$BINARY_PATH" service install >/dev/null 2>&1 || true
  ok "Configured automatic 3-hour background update service"
}
run_with_spinner "Configuring 3-hour background scheduler..." configure_background_service

# Shell Integration
configure_shell_integration() {
  local zshrc="$HOME/.zshrc"
  local bashrc="$HOME/.bashrc"
  
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  would verify PATH and alias in shell configs"
    return 0
  fi

  # Add alias to .zshrc if not present
  if [ -f "$zshrc" ] && [ -w "$zshrc" ]; then
    if ! grep -q "alias ucas=" "$zshrc" 2>/dev/null; then
      echo "alias ucas='uca status'" >> "$zshrc"
    fi
    # Remove old complex uca alias if present
    if grep -q "alias uca=" "$zshrc" 2>/dev/null; then
      sed -i.bak '/alias uca=/d' "$zshrc" 2>/dev/null || true
      rm -f "${zshrc}.bak" 2>/dev/null || true
    fi
  fi

  # Add alias to .bashrc if not present
  if [ -f "$bashrc" ] && [ -w "$bashrc" ]; then
    if ! grep -q "alias ucas=" "$bashrc" 2>/dev/null; then
      echo "alias ucas='uca status'" >> "$bashrc"
    fi
  fi
  ok "Configured shell integration (alias ucas='uca status')"
}
configure_shell_integration

# Run Self-Test Diagnostics
if [ "$DRY_RUN" -eq 0 ] && [ "$QUIET" -eq 0 ]; then
  echo ""
  "$BINARY_PATH" doctor || true
fi

# Final Summary Box
if [ "$QUIET" -eq 0 ]; then
  summary_lines=(
    "\033[1;38;5;42mUCA & UCAS are now active!\033[0m"
    ""
    "\033[1;38;5;252mHarness Status:\033[0m"
    "  • Claude Code:          \033[38;5;245m${CLAUDE_VER}\033[0m"
    "  • OpenAI Codex:         \033[38;5;245m${CODEX_VER}\033[0m"
    "  • Google Antigravity:   \033[38;5;245m${AGY_VER}\033[0m"
    "  • xAI Grok:             \033[38;5;245m${GROK_VER}\033[0m"
    "  • OMP:                  \033[38;5;245m${OMP_VER}\033[0m"
    ""
    "\033[1;38;5;252mBackground Schedule:\033[0m \033[38;5;42mActive\033[0m (every 3 hours)"
    "\033[1;38;5;252mState Directory:\033[0m     \033[38;5;245m${STATE_DIR}\033[0m"
    ""
    "\033[1;38;5;39mQuick Commands:\033[0m"
    "  \033[1;38;5;252muca\033[0m         Update all 5 harnesses sequentially"
    "  \033[1;38;5;252mucas\033[0m        Open status dashboard with version transitions"
    "  \033[1;38;5;252muca omp\033[0m     Update only OMP (or claude, codex, agy, grok)"
    "  \033[1;38;5;252muca doctor\033[0m  Run environment & harness diagnostics"
    ""
    "\033[3;38;5;245mTo uninstall: ./install-uca.sh --uninstall\033[0m"
  )

  if [ "$HAS_GUM" -eq 1 ]; then
    {
      gum style --foreground 42 --bold "UCA & UCAS are now active!"
      echo ""
      gum style --foreground 252 --bold "Harness Status:"
      gum style --foreground 245 "  • Claude Code:          ${CLAUDE_VER}"
      gum style --foreground 245 "  • OpenAI Codex:         ${CODEX_VER}"
      gum style --foreground 245 "  • Google Antigravity:   ${AGY_VER}"
      gum style --foreground 245 "  • xAI Grok:             ${GROK_VER}"
      gum style --foreground 245 "  • OMP:                  ${OMP_VER}"
      echo ""
      echo "$(gum style --foreground 252 --bold 'Background Schedule:') $(gum style --foreground 42 --bold 'Active (every 3 hours)')"
      echo "$(gum style --foreground 252 --bold 'State Directory:')     $(gum style --foreground 245 "$STATE_DIR")"
      echo ""
      gum style --foreground 39 --bold "Quick Commands:"
      echo "  $(gum style --bold --foreground 252 'uca')         Update all 5 harnesses sequentially"
      echo "  $(gum style --bold --foreground 252 'ucas')        Open status dashboard with version transitions"
      echo "  $(gum style --bold --foreground 252 'uca omp')     Update only OMP (or claude, codex, agy, grok)"
      echo "  $(gum style --bold --foreground 252 'uca doctor')  Run environment & harness diagnostics"
      echo ""
      gum style --foreground 245 --italic "To uninstall: ./install-uca.sh --uninstall"
    } | gum style --border rounded --border-foreground 42 --padding "1 2" --margin "1 0"
  else
    draw_box 42 "${summary_lines[@]}"
  fi
fi
