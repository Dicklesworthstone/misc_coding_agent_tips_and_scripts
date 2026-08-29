#!/usr/bin/env bash
#
# uninstall-uca.sh — Universal Coding Agent (UCA) Uninstaller
#
# Production-grade uninstaller built using the /installer-workmanship standard:
#   • Clean teardown of background services (systemd user units / macOS launchd)
#   • Removal of binaries and symlinks (~/.local/bin/uca, ~/.local/bin/ucas)
#   • Cleans aliases from ~/.zshrc, ~/.bashrc, and fish config
#   • Optional state directory purge (--purge)
#   • Charmbracelet Gum confirmation with seamless ANSI fallback
#
# Usage:
#   ./uninstall-uca.sh            # Interactive uninstall
#   ./uninstall-uca.sh -y, --yes  # Non-interactive uninstall (skip confirmation)
#   ./uninstall-uca.sh --purge    # Also delete logs and state cache
#   ./uninstall-uca.sh --dry-run  # Preview removal actions
#
# Curl one-liner:
#   curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/uninstall-uca.sh?$(date +%s)" | bash

set -euo pipefail
shopt -s lastpipe 2>/dev/null || true
umask 022

PURGE=0
FORCE=0
DRY_RUN=0
NO_GUM=0
QUIET=0

for arg in "$@"; do
  case "$arg" in
    --purge)     PURGE=1 ;;
    --yes|-y|-f|--force) FORCE=1 ;;
    --dry-run)   DRY_RUN=1 ;;
    --no-gum)    NO_GUM=1 ;;
    --quiet|-q)  QUIET=1 ;;
    --help|-h)
      echo "Usage: ./uninstall-uca.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --yes, -y    Non-interactive removal (skip confirmation prompt)"
      echo "  --purge      Also delete telemetry state directory (~/.local/share/uca)"
      echo "  --dry-run    Preview actions without making changes"
      echo "  --no-gum     Disable gum styling and use ANSI fallback"
      echo "  --quiet, -q  Minimal output"
      echo "  --help, -h   Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)" >&2
      exit 2
      ;;
  esac
done

HAS_GUM=0
if command -v gum &>/dev/null && [ -t 1 ] && [ "$NO_GUM" -eq 0 ]; then
  HAS_GUM=1
fi

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

# Confirmation Prompt
if [ "$FORCE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
  if [ "$HAS_GUM" -eq 1 ]; then
    if ! gum confirm "Are you sure you want to completely uninstall UCA and its background services?"; then
      info "Uninstallation aborted."
      exit 0
    fi
  else
    echo -ne "\033[38;5;214mAre you sure you want to completely uninstall UCA and its background services? [y/N]: \033[0m"
    read -r ans
    case "$ans" in
      y|Y|yes|Yes|YES) ;;
      *)
        info "Uninstallation aborted."
        exit 0
        ;;
    esac
  fi
fi

info "Removing UCA background services and binaries..."

# 1. Stop and remove macOS launchd service
if [ "$(uname -s)" = "Darwin" ]; then
  current_user="${USER:-$(whoami 2>/dev/null || echo "user")}"
  for plist_name in "com.${current_user}.uca.plist" "com.uca.updater.plist"; do
    plist_file="$HOME/Library/LaunchAgents/$plist_name"
    if [ -f "$plist_file" ]; then
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "  would unload and remove $plist_file"
      else
        launchctl unload "$plist_file" 2>/dev/null || true
        rm -f "$plist_file" 2>/dev/null || true
        ok "Removed launchd agent ($plist_name)"
      fi
    fi
  done
fi

# 2. Stop and remove Linux systemd units
if command -v systemctl &>/dev/null; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  would disable systemd uca.timer and remove service units"
  else
    systemctl --user disable --now uca.timer 2>/dev/null || true
    systemctl --user stop uca.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/uca.service" "$HOME/.config/systemd/user/uca.timer" 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
    ok "Disabled and removed systemd user units"
  fi
fi

# 3. Clean shell aliases
for shell_rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.config/fish/config.fish"; do
  if [ -f "$shell_rc" ] && [ -w "$shell_rc" ]; then
    if grep -q "alias ucas=" "$shell_rc" 2>/dev/null || grep -q "alias uca=" "$shell_rc" 2>/dev/null; then
      if [ "$DRY_RUN" -eq 1 ]; then
        echo "  would clean aliases from $shell_rc"
      else
        sed -i.bak '/alias ucas=/d; /alias uca=/d' "$shell_rc" 2>/dev/null || true
        rm -f "${shell_rc}.bak" 2>/dev/null || true
        ok "Cleaned aliases from $shell_rc"
      fi
    fi
  fi
done

# 4. Remove binaries and symlinks
for bin_file in "$HOME/.local/bin/uca" "$HOME/.local/bin/ucas" "/usr/local/bin/uca" "/usr/local/bin/ucas"; do
  if [ -f "$bin_file" ] || [ -L "$bin_file" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "  would remove $bin_file"
    else
      rm -f "$bin_file" 2>/dev/null || true
      ok "Removed $bin_file"
    fi
  fi
done

# 5. Optionally purge state and logs
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/uca"
if [ "$PURGE" -eq 1 ] && [ -d "$STATE_DIR" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  would purge state directory $STATE_DIR"
  else
    rm -rf "$STATE_DIR" 2>/dev/null || true
    ok "Purged state directory $STATE_DIR"
  fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
  ok "Dry-run uninstall preview complete."
else
  ok "UCA has been cleanly and completely uninstalled."
fi
