#!/usr/bin/env bash
#
# install-post-compact-reminder.sh
# Installs Claude Code hook to remind about AGENTS.md after context compaction
#
# Usage:
#   ./install-post-compact-reminder.sh
#   curl -fsSL <url> | bash
#
# Options:
#   --help, -h      Show help
#   --dry-run, -n   Preview changes without modifying anything
#   --uninstall     Remove the hook
#   --force         Reinstall even if already installed
#
# Environment variables:
#   HOOK_DIR=/path    Override hook script location (default: ~/.local/bin)
#   SETTINGS_DIR=/p   Override settings location (default: ~/.claude)
#

set -euo pipefail

VERSION="1.1.0"
SCRIPT_NAME="claude-post-compact-reminder"
LOCK_FILE="/tmp/.post-compact-reminder-install.lock"
GITHUB_RAW_URL="https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-post-compact-reminder.sh"

# Changelog (newest first)
CHANGELOG_1_1_0="Added --status, --verbose, --restore, --diff, --interactive, --yes, --completions, --template, --show-template, --update, --changelog, --log flags. Enhanced customization support."
CHANGELOG_1_0_0="Initial release with basic install/uninstall, dry-run, force reinstall, quiet mode, and no-color support."

# -----------------------------------------------------------------------------
# Cleanup and error handling
# -----------------------------------------------------------------------------
cleanup() {
    rm -f "$LOCK_FILE" 2>/dev/null || true
}
trap cleanup EXIT

# Acquire lock to prevent concurrent runs
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "Another instance is running (PID: $pid). Exiting." >&2
            exit 1
        fi
        # Stale lock file, remove it
        rm -f "$LOCK_FILE"
    fi
    echo $$ > "$LOCK_FILE"
}

# -----------------------------------------------------------------------------
# Colors and Styles
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'
UNDERLINE='\033[4m'
NC='\033[0m'

# Box drawing characters (rounded corners)
BOX_TL='╭' BOX_TR='╮' BOX_BL='╰' BOX_BR='╯'
BOX_H='─' BOX_V='│'

# -----------------------------------------------------------------------------
# Logging with Style
# -----------------------------------------------------------------------------
QUIET="false"
VERBOSE="false"
YES_FLAG="false"
LOG_FILE=""
HAS_JQ="false"
HAS_PYTHON="false"

log_to_file() {
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    fi
}

log_info()    { [[ "$QUIET" == "true" ]] || echo -e "${CYAN}ℹ${NC}  $1"; log_to_file "INFO: $1"; }
log_warn()    { echo -e "${YELLOW}⚠${NC}  $1"; log_to_file "WARN: $1"; }  # Always show warnings
log_error()   { echo -e "${RED}✖${NC}  $1" >&2; log_to_file "ERROR: $1"; }  # Always show errors
log_step()    { [[ "$QUIET" == "true" ]] || echo -e "${BLUE}▸${NC}  $1"; log_to_file "STEP: $1"; }
log_success() { [[ "$QUIET" == "true" ]] || echo -e "${GREEN}✔${NC}  $1"; log_to_file "SUCCESS: $1"; }
log_skip()    { [[ "$QUIET" == "true" ]] || echo -e "${DIM}○${NC}  $1"; log_to_file "SKIP: $1"; }
log_verbose() { [[ "$VERBOSE" == "true" ]] && echo -e "${DIM}   $1${NC}"; log_to_file "VERBOSE: $1"; }

# -----------------------------------------------------------------------------
# Message Templates
# -----------------------------------------------------------------------------
TEMPLATE_MINIMAL="Context compacted. Re-read AGENTS.md."

TEMPLATE_DETAILED="Context was just compacted. Please:
1. Re-read AGENTS.md for project conventions
2. Check the current task list
3. Review recent git commits (git log --oneline -5)
4. Verify any uncommitted changes (git status)"

TEMPLATE_CHECKLIST="Context compacted. Before continuing:
- [ ] Re-read AGENTS.md
- [ ] Check task list (/tasks)
- [ ] Review recent commits
- [ ] Run test suite
- [ ] Check git status"

TEMPLATE_DEFAULT="Context was just compacted. Please reread AGENTS.md to refresh your understanding of project conventions and agent coordination patterns."

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
print_banner() {
    [[ "$QUIET" == "true" ]] && return
    echo ""
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║${NC}                                                              ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}║${NC}  🔄 ${WHITE}${BOLD}post-compact-reminder${NC} ${DIM}v${VERSION}${NC}                             ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}║${NC}                                                              ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}║${NC} ${DIM}${ITALIC}\"We stop your bot from going on a post-compaction rampage.\"${NC} ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}║${NC}                                                              ${CYAN}${BOLD}║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
show_help() {
    print_banner
    echo -e "${CYAN}${BOLD}${UNDERLINE}SYNOPSIS${NC}"
    echo -e "  ${WHITE}install-post-compact-reminder.sh${NC} ${DIM}[OPTIONS]${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}${UNDERLINE}DESCRIPTION${NC}"
    echo -e "  Installs a ${GREEN}SessionStart${NC} hook that fires after context compaction"
    echo -e "  and reminds Claude to re-read ${YELLOW}AGENTS.md${NC} for project conventions."
    echo ""
    echo -e "${CYAN}${BOLD}${UNDERLINE}INSTALLATION OPTIONS${NC}"
    echo -e "  ${GREEN}--help${NC}, ${GREEN}-h${NC}            Show this help message"
    echo -e "  ${GREEN}--version${NC}, ${GREEN}-v${NC}         Show version number"
    echo -e "  ${GREEN}--dry-run${NC}, ${GREEN}-n${NC}         Preview changes without modifying anything"
    echo -e "  ${GREEN}--uninstall${NC}, ${GREEN}--remove${NC}  Remove the hook and settings entry"
    echo -e "  ${GREEN}--force${NC}, ${GREEN}-f${NC}           Reinstall even if already at latest version"
    echo -e "  ${GREEN}--yes${NC}, ${GREEN}-y${NC}             Skip confirmation prompts"
    echo ""
    echo -e "${CYAN}${BOLD}${UNDERLINE}CUSTOMIZATION OPTIONS${NC}"
    echo -e "  ${GREEN}--interactive${NC}, ${GREEN}-i${NC}     Interactive setup with template selection"
    echo -e "  ${GREEN}--template${NC} ${MAGENTA}<name>${NC}    Apply preset template (minimal|detailed|checklist|default)"
    echo -e "  ${GREEN}--show-template${NC}       Show currently installed reminder message"
    echo ""
    echo -e "${CYAN}${BOLD}${UNDERLINE}DIAGNOSTIC OPTIONS${NC}"
    echo -e "  ${GREEN}--status${NC}, ${GREEN}--check${NC}     Show installation health and configuration"
    echo -e "  ${GREEN}--diff${NC}                Show changes between installed and new version"
    echo -e "  ${GREEN}--verbose${NC}             Enable verbose/debug output"
    echo -e "  ${GREEN}--log${NC} ${MAGENTA}<file>${NC}         Log all operations to specified file"
    echo ""
    echo -e "${CYAN}${BOLD}${UNDERLINE}MAINTENANCE OPTIONS${NC}"
    echo -e "  ${GREEN}--restore${NC}             Restore settings.json from backup"
    echo -e "  ${GREEN}--update${NC}              Self-update installer from GitHub"
    echo -e "  ${GREEN}--changelog${NC}           Show version history"
    echo -e "  ${GREEN}--completions${NC} ${MAGENTA}<shell>${NC} Generate shell completions (bash|zsh)"
    echo ""
    echo -e "${CYAN}${BOLD}${UNDERLINE}OUTPUT OPTIONS${NC}"
    echo -e "  ${GREEN}--quiet${NC}, ${GREEN}-q${NC}           Suppress non-essential output"
    echo -e "  ${GREEN}--no-color${NC}            Disable colored output"
    echo ""
    echo -e "${CYAN}${BOLD}${UNDERLINE}ENVIRONMENT VARIABLES${NC}"
    echo -e "  ${MAGENTA}HOOK_DIR${NC}              Override hook script location ${DIM}(default: ~/.local/bin)${NC}"
    echo -e "  ${MAGENTA}SETTINGS_DIR${NC}          Override settings location ${DIM}(default: ~/.claude)${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}${UNDERLINE}EXAMPLES${NC}"
    echo -e "  ${DIM}${ITALIC}# One-liner install${NC}"
    echo -e "  ${WHITE}curl -fsSL <url> | bash${NC}"
    echo ""
    echo -e "  ${DIM}${ITALIC}# Check installation status${NC}"
    echo -e "  ${WHITE}./install-post-compact-reminder.sh --status${NC}"
    echo ""
    echo -e "  ${DIM}${ITALIC}# Interactive setup with custom message${NC}"
    echo -e "  ${WHITE}./install-post-compact-reminder.sh --interactive${NC}"
    echo ""
    echo -e "  ${DIM}${ITALIC}# Apply minimal template${NC}"
    echo -e "  ${WHITE}./install-post-compact-reminder.sh --template minimal${NC}"
    echo ""
    echo -e "  ${DIM}${ITALIC}# Preview changes${NC}"
    echo -e "  ${WHITE}./install-post-compact-reminder.sh --dry-run${NC}"
    echo ""
    echo -e "  ${DIM}${ITALIC}# Uninstall${NC}"
    echo -e "  ${WHITE}./install-post-compact-reminder.sh --uninstall${NC}"
    echo ""
    echo -e "  ${DIM}${ITALIC}# Generate bash completions${NC}"
    echo -e "  ${WHITE}./install-post-compact-reminder.sh --completions bash >> ~/.bashrc${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# Dependency checks and auto-installation
# -----------------------------------------------------------------------------
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v brew &> /dev/null; then
        echo "brew"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    else
        echo ""
    fi
}

install_package() {
    local pkg="$1"
    local pkg_manager="$2"

    case "$pkg_manager" in
        apt)
            sudo apt-get update -qq && sudo apt-get install -y "$pkg"
            ;;
        brew)
            if [[ "$pkg" == "python3" ]]; then
                pkg="python"
            fi
            brew install "$pkg"
            ;;
        dnf)
            sudo dnf install -y "$pkg"
            ;;
        yum)
            sudo yum install -y "$pkg"
            ;;
        pacman)
            sudo pacman -S --noconfirm "$pkg"
            ;;
        *)
            return 1
            ;;
    esac
}

check_dependencies() {
    local allow_install="${1:-true}"
    local missing=()

    if command -v jq &> /dev/null; then
        HAS_JQ="true"
    else
        HAS_JQ="false"
        missing+=("jq")
    fi

    if command -v python3 &> /dev/null; then
        HAS_PYTHON="true"
    else
        HAS_PYTHON="false"
        missing+=("python3")
    fi

    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    log_warn "Missing dependencies: ${missing[*]}"

    if [[ "$allow_install" != "true" ]]; then
        log_warn "Dry run: skipping auto-install. Some checks may be skipped."
        return 0
    fi

    # Try to auto-install
    local pkg_manager
    pkg_manager=$(detect_package_manager)

    if [[ -z "$pkg_manager" ]]; then
        log_error "Could not detect package manager. Please install manually:"
        echo ""
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        return 1
    fi

    log_step "Attempting to install missing dependencies using $pkg_manager..."

    for dep in "${missing[@]}"; do
        log_step "Installing $dep..."
        if install_package "$dep" "$pkg_manager"; then
            log_success "Installed $dep"
        else
            log_error "Failed to install $dep"
            echo ""
            echo "Please install manually:"
            case "$pkg_manager" in
                apt)
                    echo "  sudo apt-get install $dep"
                    ;;
                brew)
                    echo "  brew install $dep"
                    ;;
                dnf|yum)
                    echo "  sudo $pkg_manager install $dep"
                    ;;
                pacman)
                    echo "  sudo pacman -S $dep"
                    ;;
            esac
            return 1
        fi
    done

    # Verify installation
    local still_missing=()
    if command -v jq &> /dev/null; then
        HAS_JQ="true"
    else
        HAS_JQ="false"
        still_missing+=("jq")
    fi
    if command -v python3 &> /dev/null; then
        HAS_PYTHON="true"
    else
        HAS_PYTHON="false"
        still_missing+=("python3")
    fi

    if [[ ${#still_missing[@]} -gt 0 ]]; then
        log_error "Dependencies still missing after install attempt: ${still_missing[*]}"
        return 1
    fi

    log_success "All dependencies installed"
    return 0
}

# -----------------------------------------------------------------------------
# Version management
# -----------------------------------------------------------------------------
get_installed_version() {
    local script_path="$1"
    if [[ -x "$script_path" ]]; then
        grep -m1 '^# Version:' "$script_path" 2>/dev/null | cut -d' ' -f3 || echo ""
    else
        echo ""
    fi
}

# -----------------------------------------------------------------------------
# Hook script content
# -----------------------------------------------------------------------------
generate_hook_script() {
    cat << HOOK_SCRIPT
#!/usr/bin/env bash
# Version: ${VERSION}
# SessionStart hook: Remind Claude to reread AGENTS.md after compaction
# Input: JSON with session_id, source on stdin
#
# This hook fires when source="compact" (configured via matcher in settings.json)
# and outputs a reminder that Claude sees in its context.

set -e

# Read JSON input from Claude Code
INPUT=\$(cat)
SOURCE=\$(echo "\$INPUT" | jq -r '.source // empty')

# Double-check source (belt and suspenders with the matcher)
if [[ "\$SOURCE" == "compact" ]]; then
    cat <<'EOF'
<post-compact-reminder>
Context was just compacted. Please reread AGENTS.md to refresh your understanding of project conventions and agent coordination patterns.
</post-compact-reminder>
EOF
fi

# SessionStart hooks don't block, just exit 0
exit 0
HOOK_SCRIPT
}

# -----------------------------------------------------------------------------
# Settings management
# -----------------------------------------------------------------------------
check_settings_has_hook() {
    local settings_file="$1"
    if [[ ! -f "$settings_file" ]]; then
        return 1
    fi
    if [[ "$HAS_PYTHON" != "true" ]]; then
        return 1
    fi

    python3 -c "
import json
import sys

try:
    with open('$settings_file', 'r') as f:
        settings = json.load(f)

    hooks = settings.get('hooks', {}).get('SessionStart', [])
    for hook_group in hooks:
        for hook in hook_group.get('hooks', []):
            if 'post-compact-reminder' in hook.get('command', ''):
                sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null
}

add_hook_to_settings() {
    local settings_file="$1"
    local hook_path="$2"
    local dry_run="$3"

    if [[ "$dry_run" == "true" ]]; then
        log_step "[dry-run] Would add SessionStart hook to $settings_file"
        return 0
    fi

    # Create backup before modifying
    if [[ -f "$settings_file" ]]; then
        cp "$settings_file" "${settings_file}.bak" 2>/dev/null || true
    fi

    python3 << MERGE_SCRIPT
import json
import os
import sys
import tempfile
import shutil

settings_file = "$settings_file"
hook_path = "$hook_path"

try:
    # Load or create settings
    if os.path.exists(settings_file):
        with open(settings_file, 'r') as f:
            settings = json.load(f)
    else:
        settings = {}

    # Ensure hooks structure exists
    if 'hooks' not in settings:
        settings['hooks'] = {}

    # Check if SessionStart already has our hook
    session_start = settings['hooks'].get('SessionStart', [])
    already_exists = False

    for hook_group in session_start:
        for hook in hook_group.get('hooks', []):
            if 'post-compact-reminder' in hook.get('command', ''):
                already_exists = True
                break

    if not already_exists:
        # Add our hook with matcher
        session_start.append({
            "matcher": "compact",
            "hooks": [
                {
                    "type": "command",
                    "command": hook_path
                }
            ]
        })
        settings['hooks']['SessionStart'] = session_start

        # Atomic write: write to temp file then rename
        dir_name = os.path.dirname(settings_file) or '.'
        with tempfile.NamedTemporaryFile(mode='w', dir=dir_name, delete=False, suffix='.tmp') as tf:
            json.dump(settings, tf, indent=2)
            tf.write('\n')
            temp_path = tf.name

        shutil.move(temp_path, settings_file)
        print('added')
    else:
        print('exists')

except Exception as e:
    print(f'error: {e}', file=sys.stderr)
    sys.exit(1)
MERGE_SCRIPT
}

remove_hook_from_settings() {
    local settings_file="$1"
    local dry_run="$2"

    if [[ ! -f "$settings_file" ]]; then
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_step "[dry-run] Would remove SessionStart hook from $settings_file"
        return 0
    fi

    # Create backup before modifying
    cp "$settings_file" "${settings_file}.bak" 2>/dev/null || true

    python3 << REMOVE_SCRIPT
import json
import os
import sys
import tempfile
import shutil

settings_file = "$settings_file"

try:
    if not os.path.exists(settings_file):
        sys.exit(0)

    with open(settings_file, 'r') as f:
        settings = json.load(f)

    session_start = settings.get('hooks', {}).get('SessionStart', [])
    new_session_start = []

    for hook_group in session_start:
        new_hooks = []
        for hook in hook_group.get('hooks', []):
            if 'post-compact-reminder' not in hook.get('command', ''):
                new_hooks.append(hook)
        if new_hooks:
            # Create new dict to avoid mutating original
            new_group = dict(hook_group)
            new_group['hooks'] = new_hooks
            new_session_start.append(new_group)

    if new_session_start:
        settings['hooks']['SessionStart'] = new_session_start
    else:
        settings.get('hooks', {}).pop('SessionStart', None)

    # Clean up empty hooks
    if not settings.get('hooks'):
        settings.pop('hooks', None)

    # Atomic write: write to temp file then rename
    dir_name = os.path.dirname(settings_file) or '.'
    with tempfile.NamedTemporaryFile(mode='w', dir=dir_name, delete=False, suffix='.tmp') as tf:
        json.dump(settings, tf, indent=2)
        tf.write('\n')
        temp_path = tf.name

    shutil.move(temp_path, settings_file)

except Exception as e:
    print(f'error: {e}', file=sys.stderr)
    sys.exit(1)
REMOVE_SCRIPT
}

# -----------------------------------------------------------------------------
# Test hook
# -----------------------------------------------------------------------------
test_hook() {
    local script_path="$1"

    local test_result
    test_result=$(echo '{"session_id": "test", "source": "compact"}' | \
        "$script_path" 2>/dev/null || true)

    if echo "$test_result" | grep -q "post-compact-reminder" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Status check
# -----------------------------------------------------------------------------
do_status() {
    local hook_dir="$1"
    local settings_dir="$2"

    local script_path="${hook_dir}/${SCRIPT_NAME}"
    local settings_file="${settings_dir}/settings.json"

    # Quick dependency check (just set flags, don't install)
    command -v jq &> /dev/null && HAS_JQ="true" || HAS_JQ="false"
    command -v python3 &> /dev/null && HAS_PYTHON="true" || HAS_PYTHON="false"

    print_banner

    echo -e "${WHITE}${BOLD}${UNDERLINE}Installation Status${NC}"
    echo ""

    # Check script
    echo -e "  ${CYAN}${BOLD}Hook Script:${NC}"
    if [[ -f "$script_path" ]]; then
        local installed_version
        installed_version=$(get_installed_version "$script_path")
        if [[ -x "$script_path" ]]; then
            echo -e "    ${GREEN}✔${NC} Installed at ${WHITE}$script_path${NC}"
            echo -e "    ${GREEN}✔${NC} Executable: yes"
            echo -e "    ${CYAN}ℹ${NC} Version: ${WHITE}${installed_version:-unknown}${NC}"
            if [[ "$installed_version" != "$VERSION" && -n "$installed_version" ]]; then
                echo -e "    ${YELLOW}⚠${NC} Update available: ${installed_version} → ${VERSION}"
            fi
        else
            echo -e "    ${YELLOW}⚠${NC} File exists but not executable"
        fi
    else
        echo -e "    ${RED}✖${NC} Not installed at $script_path"
    fi
    echo ""

    # Check settings
    echo -e "  ${CYAN}${BOLD}Settings Configuration:${NC}"
    if [[ -f "$settings_file" ]]; then
        echo -e "    ${GREEN}✔${NC} Settings file exists at ${WHITE}$settings_file${NC}"
        if [[ "$HAS_PYTHON" == "true" ]]; then
            if check_settings_has_hook "$settings_file"; then
                echo -e "    ${GREEN}✔${NC} Hook configured in settings.json"
            else
                echo -e "    ${RED}✖${NC} Hook NOT configured in settings.json"
            fi
        else
            echo -e "    ${YELLOW}⚠${NC} Cannot verify hook config (python3 not available)"
        fi
        if [[ -f "${settings_file}.bak" ]]; then
            echo -e "    ${CYAN}ℹ${NC} Backup exists: ${settings_file}.bak"
        fi
    else
        echo -e "    ${RED}✖${NC} Settings file not found"
    fi
    echo ""

    # Check dependencies
    echo -e "  ${CYAN}${BOLD}Dependencies:${NC}"
    if [[ "$HAS_JQ" == "true" ]]; then
        echo -e "    ${GREEN}✔${NC} jq: $(jq --version 2>/dev/null || echo 'installed')"
    else
        echo -e "    ${RED}✖${NC} jq: not installed"
    fi
    if [[ "$HAS_PYTHON" == "true" ]]; then
        echo -e "    ${GREEN}✔${NC} python3: $(python3 --version 2>/dev/null || echo 'installed')"
    else
        echo -e "    ${RED}✖${NC} python3: not installed"
    fi
    echo ""

    # Test hook if installed
    if [[ -x "$script_path" ]]; then
        echo -e "  ${CYAN}${BOLD}Hook Test:${NC}"
        if test_hook "$script_path"; then
            echo -e "    ${GREEN}✔${NC} Hook responds correctly to compact events"
        else
            echo -e "    ${RED}✖${NC} Hook test failed"
        fi
        echo ""
    fi
}

# -----------------------------------------------------------------------------
# Restore settings backup
# -----------------------------------------------------------------------------
do_restore() {
    local settings_dir="$1"
    local dry_run="$2"

    local settings_file="${settings_dir}/settings.json"
    local backup_file="${settings_file}.bak"

    print_banner

    if [[ ! -f "$backup_file" ]]; then
        log_error "No backup file found at $backup_file"
        echo ""
        echo -e "  ${DIM}Backups are created automatically when settings.json is modified.${NC}"
        return 1
    fi

    log_info "Found backup: $backup_file"

    # Show what's different
    if command -v diff &> /dev/null && [[ -f "$settings_file" ]]; then
        echo ""
        echo -e "${WHITE}${BOLD}Changes to restore:${NC}"
        echo ""
        diff --color=auto -u "$settings_file" "$backup_file" 2>/dev/null || true
        echo ""
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_step "[dry-run] Would restore $backup_file to $settings_file"
        return 0
    fi

    # Confirm unless --yes
    if [[ "$YES_FLAG" != "true" ]]; then
        echo -e "${YELLOW}Restore settings.json from backup?${NC} [y/N] "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Restore cancelled"
            return 0
        fi
    fi

    cp "$backup_file" "$settings_file"
    log_success "Restored settings.json from backup"
    echo ""
    echo -e "${YELLOW}Restart Claude Code for changes to take effect.${NC}"
}

# -----------------------------------------------------------------------------
# Show diff between installed and new version
# -----------------------------------------------------------------------------
do_diff() {
    local hook_dir="$1"

    local script_path="${hook_dir}/${SCRIPT_NAME}"

    print_banner

    if [[ ! -f "$script_path" ]]; then
        log_error "Hook not installed at $script_path"
        echo -e "  ${DIM}Run without --diff to install first.${NC}"
        return 1
    fi

    local installed_version
    installed_version=$(get_installed_version "$script_path")

    echo -e "${WHITE}${BOLD}${UNDERLINE}Version Comparison${NC}"
    echo ""
    echo -e "  Installed: ${CYAN}${installed_version:-unknown}${NC}"
    echo -e "  Available: ${GREEN}${VERSION}${NC}"
    echo ""

    if [[ "$installed_version" == "$VERSION" ]]; then
        log_info "Already at latest version"
        return 0
    fi

    echo -e "${WHITE}${BOLD}Hook script diff:${NC}"
    echo ""

    # Generate new script to temp file for comparison
    local temp_new
    temp_new=$(mktemp)
    generate_hook_script > "$temp_new"

    if command -v diff &> /dev/null; then
        diff --color=auto -u "$script_path" "$temp_new" || true
    else
        echo -e "${DIM}(diff not available - showing new version)${NC}"
        cat "$temp_new"
    fi

    rm -f "$temp_new"
    echo ""
}

# -----------------------------------------------------------------------------
# Interactive customization mode
# -----------------------------------------------------------------------------
do_interactive() {
    local hook_dir="$1"
    local settings_dir="$2"

    local script_path="${hook_dir}/${SCRIPT_NAME}"

    print_banner

    echo -e "${WHITE}${BOLD}${UNDERLINE}Interactive Setup${NC}"
    echo ""

    # Step 1: Choose template
    echo -e "${CYAN}${BOLD}Step 1:${NC} Choose a message template"
    echo ""
    echo -e "  ${GREEN}1)${NC} ${WHITE}minimal${NC}   - Short one-liner"
    echo -e "     ${DIM}\"$TEMPLATE_MINIMAL\"${NC}"
    echo ""
    echo -e "  ${GREEN}2)${NC} ${WHITE}detailed${NC}  - Step-by-step instructions"
    echo -e "     ${DIM}\"Context was just compacted. Please: 1. Re-read AGENTS.md...\"${NC}"
    echo ""
    echo -e "  ${GREEN}3)${NC} ${WHITE}checklist${NC} - Markdown checklist format"
    echo -e "     ${DIM}\"Context compacted. Before continuing: - [ ] Re-read AGENTS.md...\"${NC}"
    echo ""
    echo -e "  ${GREEN}4)${NC} ${WHITE}default${NC}   - Standard message"
    echo -e "     ${DIM}\"$TEMPLATE_DEFAULT\"${NC}"
    echo ""
    echo -e "  ${GREEN}5)${NC} ${WHITE}custom${NC}    - Enter your own message"
    echo ""

    echo -n "Choose template [1-5]: "
    read -r template_choice

    local chosen_message=""
    case "$template_choice" in
        1) chosen_message="$TEMPLATE_MINIMAL" ;;
        2) chosen_message="$TEMPLATE_DETAILED" ;;
        3) chosen_message="$TEMPLATE_CHECKLIST" ;;
        4) chosen_message="$TEMPLATE_DEFAULT" ;;
        5)
            echo ""
            echo -e "${CYAN}${BOLD}Step 2:${NC} Enter your custom message (end with empty line):"
            echo ""
            chosen_message=""
            while IFS= read -r line; do
                [[ -z "$line" ]] && break
                chosen_message+="$line"$'\n'
            done
            chosen_message="${chosen_message%$'\n'}"  # Remove trailing newline
            ;;
        *)
            log_warn "Invalid choice, using default"
            chosen_message="$TEMPLATE_DEFAULT"
            ;;
    esac

    echo ""
    echo -e "${WHITE}${BOLD}Preview:${NC}"
    echo ""
    echo -e "  ${MAGENTA}${BOX_TL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}${NC}"
    echo -e "  ${MAGENTA}${BOX_V}${NC} ${CYAN}<post-compact-reminder>${NC}"
    echo "$chosen_message" | while IFS= read -r line; do
        printf "  ${MAGENTA}${BOX_V}${NC} %s\n" "$line"
    done
    echo -e "  ${MAGENTA}${BOX_V}${NC} ${CYAN}</post-compact-reminder>${NC}"
    echo -e "  ${MAGENTA}${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}${NC}"
    echo ""

    echo -n "Install with this message? [Y/n]: "
    read -r confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        log_info "Installation cancelled"
        return 0
    fi

    # Generate custom hook script
    echo ""
    log_step "Creating directories..."
    mkdir -p "$hook_dir"
    mkdir -p "$settings_dir"

    log_step "Creating hook script with custom message..."

    cat > "$script_path" << CUSTOM_HOOK
#!/usr/bin/env bash
# Version: ${VERSION}
# SessionStart hook: Remind Claude to reread AGENTS.md after compaction
# Generated by interactive setup

set -e

INPUT=\$(cat)
SOURCE=\$(echo "\$INPUT" | jq -r '.source // empty')

if [[ "\$SOURCE" == "compact" ]]; then
    cat <<'EOF'
<post-compact-reminder>
${chosen_message}
</post-compact-reminder>
EOF
fi

exit 0
CUSTOM_HOOK

    chmod +x "$script_path"
    log_success "Created $script_path"

    # Update settings
    log_step "Updating settings.json..."
    local settings_file="${settings_dir}/settings.json"
    local hook_path_for_settings="\$HOME/.local/bin/${SCRIPT_NAME}"
    add_hook_to_settings "$settings_file" "$hook_path_for_settings" "false" > /dev/null
    log_success "Settings updated"

    # Test
    log_step "Testing hook..."
    if test_hook "$script_path"; then
        log_success "Hook test passed"
    else
        log_warn "Hook test inconclusive"
    fi

    echo ""
    log_success "Interactive setup complete!"
    echo ""
    echo -e "${YELLOW}⚡ Restart Claude Code for the hook to take effect.${NC}"
}

# -----------------------------------------------------------------------------
# Show current installed template
# -----------------------------------------------------------------------------
do_show_template() {
    local hook_dir="$1"

    local script_path="${hook_dir}/${SCRIPT_NAME}"

    if [[ ! -f "$script_path" ]]; then
        log_error "Hook not installed at $script_path"
        return 1
    fi

    print_banner

    echo -e "${WHITE}${BOLD}${UNDERLINE}Currently Installed Message${NC}"
    echo ""

    # Extract the message from between <post-compact-reminder> tags
    local in_message=false
    while IFS= read -r line; do
        if [[ "$line" == *"<post-compact-reminder>"* ]]; then
            in_message=true
            echo -e "  ${CYAN}<post-compact-reminder>${NC}"
            continue
        fi
        if [[ "$line" == *"</post-compact-reminder>"* ]]; then
            echo -e "  ${CYAN}</post-compact-reminder>${NC}"
            break
        fi
        if [[ "$in_message" == true ]]; then
            echo "  $line"
        fi
    done < "$script_path"

    echo ""
    echo -e "${DIM}File: $script_path${NC}"
}

# -----------------------------------------------------------------------------
# Apply a preset template
# -----------------------------------------------------------------------------
do_template() {
    local hook_dir="$1"
    local template_name="$2"

    local script_path="${hook_dir}/${SCRIPT_NAME}"

    print_banner

    local chosen_message=""
    case "$template_name" in
        minimal)   chosen_message="$TEMPLATE_MINIMAL" ;;
        detailed)  chosen_message="$TEMPLATE_DETAILED" ;;
        checklist) chosen_message="$TEMPLATE_CHECKLIST" ;;
        default)   chosen_message="$TEMPLATE_DEFAULT" ;;
        *)
            log_error "Unknown template: $template_name"
            echo ""
            echo -e "Available templates: ${GREEN}minimal${NC}, ${GREEN}detailed${NC}, ${GREEN}checklist${NC}, ${GREEN}default${NC}"
            return 1
            ;;
    esac

    log_info "Applying template: $template_name"
    echo ""

    mkdir -p "$hook_dir"

    cat > "$script_path" << TEMPLATE_HOOK
#!/usr/bin/env bash
# Version: ${VERSION}
# SessionStart hook: Remind Claude to reread AGENTS.md after compaction
# Template: ${template_name}

set -e

INPUT=\$(cat)
SOURCE=\$(echo "\$INPUT" | jq -r '.source // empty')

if [[ "\$SOURCE" == "compact" ]]; then
    cat <<'EOF'
<post-compact-reminder>
${chosen_message}
</post-compact-reminder>
EOF
fi

exit 0
TEMPLATE_HOOK

    chmod +x "$script_path"
    log_success "Applied '$template_name' template to $script_path"

    # Test
    if test_hook "$script_path"; then
        log_success "Hook test passed"
    fi

    echo ""
    echo -e "${YELLOW}⚡ Restart Claude Code for changes to take effect.${NC}"
}

# -----------------------------------------------------------------------------
# Show changelog
# -----------------------------------------------------------------------------
do_changelog() {
    print_banner

    echo -e "${WHITE}${BOLD}${UNDERLINE}Changelog${NC}"
    echo ""
    echo -e "  ${GREEN}${BOLD}v1.1.0${NC}"
    echo -e "  ${DIM}$CHANGELOG_1_1_0${NC}"
    echo ""
    echo -e "  ${CYAN}${BOLD}v1.0.0${NC}"
    echo -e "  ${DIM}$CHANGELOG_1_0_0${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# Self-update from GitHub
# -----------------------------------------------------------------------------
do_update() {
    local dry_run="$1"

    print_banner

    log_info "Checking for updates..."

    if ! command -v curl &> /dev/null; then
        log_error "curl is required for updates"
        return 1
    fi

    # Fetch remote version
    local remote_script
    remote_script=$(curl -fsSL "$GITHUB_RAW_URL" 2>/dev/null) || {
        log_error "Failed to fetch from GitHub"
        return 1
    }

    local remote_version
    remote_version=$(echo "$remote_script" | grep -m1 '^VERSION=' | cut -d'"' -f2)

    if [[ -z "$remote_version" ]]; then
        log_error "Could not determine remote version"
        return 1
    fi

    echo ""
    echo -e "  Current version: ${CYAN}${VERSION}${NC}"
    echo -e "  Remote version:  ${GREEN}${remote_version}${NC}"
    echo ""

    if [[ "$VERSION" == "$remote_version" ]]; then
        log_success "Already at latest version"
        return 0
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_step "[dry-run] Would update to $remote_version"
        return 0
    fi

    # Confirm unless --yes
    if [[ "$YES_FLAG" != "true" ]]; then
        echo -n "Update to $remote_version? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Update cancelled"
            return 0
        fi
    fi

    # Get the path to this script
    local this_script
    this_script=$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")

    # Create backup
    cp "$this_script" "${this_script}.bak"
    log_verbose "Backup created at ${this_script}.bak"

    # Update
    echo "$remote_script" > "$this_script"
    chmod +x "$this_script"

    log_success "Updated to version $remote_version"
    echo ""
    echo -e "${YELLOW}Run the installer again to update the hook script.${NC}"
}

# -----------------------------------------------------------------------------
# Generate shell completions
# -----------------------------------------------------------------------------
do_completions() {
    local shell_type="$1"

    case "$shell_type" in
        bash)
            cat << 'BASH_COMPLETIONS'
# Bash completions for install-post-compact-reminder.sh
# Add to ~/.bashrc or /etc/bash_completion.d/

_post_compact_reminder() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    opts="--help -h --version -v --dry-run -n --uninstall --remove --force -f --quiet -q --no-color --status --check --verbose --restore --diff --interactive -i --yes -y --completions --template --show-template --update --changelog --log"

    case "$prev" in
        --template)
            COMPREPLY=( $(compgen -W "minimal detailed checklist default" -- "$cur") )
            return 0
            ;;
        --completions)
            COMPREPLY=( $(compgen -W "bash zsh" -- "$cur") )
            return 0
            ;;
        --log)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
    esac

    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
}

complete -F _post_compact_reminder install-post-compact-reminder.sh
complete -F _post_compact_reminder ./install-post-compact-reminder.sh
BASH_COMPLETIONS
            ;;

        zsh)
            cat << 'ZSH_COMPLETIONS'
#compdef install-post-compact-reminder.sh

# Zsh completions for install-post-compact-reminder.sh
# Add to ~/.zshrc or place in your fpath

_install_post_compact_reminder() {
    local -a opts
    opts=(
        '--help[Show help message]::'
        '-h[Show help message]::'
        '--version[Show version number]::'
        '-v[Show version number]::'
        '--dry-run[Preview changes without modifying]::'
        '-n[Preview changes without modifying]::'
        '--uninstall[Remove the hook]::'
        '--remove[Remove the hook]::'
        '--force[Reinstall even if already installed]::'
        '-f[Reinstall even if already installed]::'
        '--quiet[Suppress non-essential output]::'
        '-q[Suppress non-essential output]::'
        '--no-color[Disable colored output]::'
        '--status[Show installation status]::'
        '--check[Show installation status]::'
        '--verbose[Enable verbose output]::'
        '--restore[Restore settings.json from backup]::'
        '--diff[Show changes on upgrade]::'
        '--interactive[Interactive setup mode]::'
        '-i[Interactive setup mode]::'
        '--yes[Skip confirmation prompts]::'
        '-y[Skip confirmation prompts]::'
        '--completions[Generate shell completions]:shell:(bash zsh)'
        '--template[Apply a preset template]:template:(minimal detailed checklist default)'
        '--show-template[Show current installed message]::'
        '--update[Self-update from GitHub]::'
        '--changelog[Show version history]::'
        '--log[Log operations to file]:file:_files'
    )

    _arguments -s $opts
}

_install_post_compact_reminder "$@"
ZSH_COMPLETIONS
            ;;

        *)
            log_error "Unknown shell: $shell_type"
            echo ""
            echo -e "Supported shells: ${GREEN}bash${NC}, ${GREEN}zsh${NC}"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Install
# -----------------------------------------------------------------------------
do_install() {
    local hook_dir="$1"
    local settings_dir="$2"
    local dry_run="$3"
    local force="$4"

    local script_path="${hook_dir}/${SCRIPT_NAME}"
    local settings_file="${settings_dir}/settings.json"

    # Check existing installation
    local installed_version
    installed_version=$(get_installed_version "$script_path")

    if [[ -n "$installed_version" && "$force" != "true" ]]; then
        if [[ "$installed_version" == "$VERSION" ]]; then
            log_info "Already installed at version ${VERSION}"
            if [[ "$HAS_PYTHON" != "true" ]]; then
                log_warn "python3 not found; skipping settings.json inspection"
            else
                if check_settings_has_hook "$settings_file"; then
                    log_skip "Hook already configured in settings.json"
                    echo ""
                    log_success "Nothing to do. Use --force to reinstall."
                    return 0
                else
                    log_warn "Script exists but settings.json needs updating"
                fi
            fi
        else
            log_info "Upgrading: ${installed_version} → ${VERSION}"
        fi
    fi

    # Create directories
    if [[ "$dry_run" != "true" ]]; then
        mkdir -p "$hook_dir"
        mkdir -p "$settings_dir"
    fi

    # Install hook script
    if [[ "$dry_run" == "true" ]]; then
        log_step "[dry-run] Would create $script_path"
    else
        log_step "Creating hook script..."
        generate_hook_script > "$script_path"
        chmod +x "$script_path"
        log_success "Created $script_path"
    fi

    # Update settings.json
    # Note: We use $HOME in settings.json for portability, but only if using default HOOK_DIR
    log_step "Updating settings.json..."
    local hook_path_for_settings
    local default_hook_dir="$HOME/.local/bin"
    if [[ "$hook_dir" == "$default_hook_dir" ]]; then
        # Use $HOME for portability when using default location
        hook_path_for_settings="\$HOME/.local/bin/${SCRIPT_NAME}"
    else
        # Use absolute path for custom HOOK_DIR
        hook_path_for_settings="$script_path"
    fi
    local result
    result=$(add_hook_to_settings "$settings_file" "$hook_path_for_settings" "$dry_run")

    if [[ "$dry_run" != "true" ]]; then
        if [[ "$result" == "added" ]]; then
            log_success "Added SessionStart hook with matcher: compact"
        else
            log_skip "Hook already present in settings.json"
        fi
    fi

    # Test the hook
    if [[ "$dry_run" != "true" ]]; then
        log_step "Testing hook..."
        if test_hook "$script_path"; then
            log_success "Hook test passed"
        else
            log_error "Hook test failed"
            return 1
        fi
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Uninstall
# -----------------------------------------------------------------------------
do_uninstall() {
    local hook_dir="$1"
    local settings_dir="$2"
    local dry_run="$3"

    local script_path="${hook_dir}/${SCRIPT_NAME}"
    local settings_file="${settings_dir}/settings.json"

    log_info "Uninstalling post-compact-reminder..."
    echo ""

    # Confirmation prompt (skip if --yes or --dry-run)
    if [[ "$YES_FLAG" != "true" ]] && [[ "$dry_run" != "true" ]]; then
        echo -e "${YELLOW}This will remove:${NC}"
        [[ -f "$script_path" ]] && echo -e "  ${DIM}•${NC} $script_path"
        [[ -f "$settings_file" ]] && echo -e "  ${DIM}•${NC} Hook entry from $settings_file"
        echo ""
        echo -n -e "${BOLD}Are you sure you want to uninstall? [y/N]${NC} "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Uninstall cancelled."
            exit 0
        fi
        echo ""
    fi

    # Remove script
    if [[ -f "$script_path" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            log_step "[dry-run] Would remove $script_path"
        else
            rm -f "$script_path"
            log_success "Removed $script_path"
        fi
    else
        log_skip "Script not found at $script_path"
    fi

    # Remove from settings
    if [[ -f "$settings_file" ]]; then
        if check_settings_has_hook "$settings_file"; then
            remove_hook_from_settings "$settings_file" "$dry_run"
            if [[ "$dry_run" != "true" ]]; then
                log_success "Removed hook from settings.json"
            fi
        else
            log_skip "Hook not found in settings.json"
        fi
    else
        log_skip "Settings file not found"
    fi

    echo ""
    if [[ "$dry_run" == "true" ]]; then
        log_info "[dry-run] No changes made"
    else
        log_success "Uninstall complete"
        echo ""
        echo -e "${YELLOW}Restart Claude Code for changes to take effect.${NC}"
    fi
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_summary() {
    local dry_run="$1"
    local hook_dir="$2"
    local display_hook_path
    local default_hook_dir="$HOME/.local/bin"
    if [[ "$hook_dir" == "$default_hook_dir" ]]; then
        # shellcheck disable=SC2088  # Intentional: display ~ for readability
        display_hook_path="~/.local/bin/${SCRIPT_NAME}"
    else
        display_hook_path="${hook_dir}/${SCRIPT_NAME}"
    fi

    echo ""
    if [[ "$dry_run" == "true" ]]; then
        echo -e "${BLUE}${BOX_TL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}${NC}"
        echo -e "${BLUE}${BOX_V}${NC}  ${BLUE}${BOLD}📋 DRY RUN${NC} ${DIM}${ITALIC}— No changes were made${NC}                           ${BLUE}${BOX_V}${NC}"
        echo -e "${BLUE}${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}${NC}"
    else
        echo -e "${GREEN}${BOX_TL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}${NC}"
        echo -e "${GREEN}${BOX_V}${NC}  ${GREEN}${BOLD}✨ Installation complete!${NC}                                     ${GREEN}${BOX_V}${NC}"
        echo -e "${GREEN}${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}${NC}"
    fi
    echo ""
    echo -e "${WHITE}${BOLD}${UNDERLINE}What Claude sees after compaction:${NC}"
    echo ""
    echo -e "  ${MAGENTA}${BOX_TL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}${NC}"
    echo -e "  ${MAGENTA}${BOX_V}${NC} ${CYAN}<post-compact-reminder>${NC}                                 ${MAGENTA}${BOX_V}${NC}"
    echo -e "  ${MAGENTA}${BOX_V}${NC}                                                         ${MAGENTA}${BOX_V}${NC}"
    echo -e "  ${MAGENTA}${BOX_V}${NC} ${WHITE}Context was just compacted. Please reread AGENTS.md${NC}    ${MAGENTA}${BOX_V}${NC}"
    echo -e "  ${MAGENTA}${BOX_V}${NC} ${WHITE}to refresh your understanding of project conventions${NC}   ${MAGENTA}${BOX_V}${NC}"
    echo -e "  ${MAGENTA}${BOX_V}${NC} ${WHITE}and agent coordination patterns.${NC}                       ${MAGENTA}${BOX_V}${NC}"
    echo -e "  ${MAGENTA}${BOX_V}${NC}                                                         ${MAGENTA}${BOX_V}${NC}"
    echo -e "  ${MAGENTA}${BOX_V}${NC} ${CYAN}</post-compact-reminder>${NC}                                ${MAGENTA}${BOX_V}${NC}"
    echo -e "  ${MAGENTA}${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}${NC}"
    echo ""

    if [[ "$dry_run" != "true" ]]; then
        echo -e "  ${YELLOW}⚡ ${ITALIC}Restart Claude Code for the hook to take effect.${NC}"
        echo ""

        # Customization section
        echo -e "${WHITE}${BOLD}${UNDERLINE}Customizing the reminder:${NC}"
        echo ""
        echo -e "  The reminder message can be easily customized to fit your workflow."
        echo -e "  Edit the heredoc inside the hook script to change what Claude sees."
        echo ""
        echo -e "  ${CYAN}${BOLD}Step 1:${NC} Open the script in your editor"
        echo ""
        echo -e "    ${WHITE}\$ ${GREEN}nano ${display_hook_path}${NC}"
        echo -e "    ${DIM}${ITALIC}  or: code, vim, emacs, etc.${NC}"
        echo ""
        echo -e "  ${CYAN}${BOLD}Step 2:${NC} Find and modify the message block"
        echo ""
        echo -e "  ${DIM}${BOX_TL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_TR}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC} ${GREEN}cat <<'EOF'${NC}                                             ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC} ${CYAN}<post-compact-reminder>${NC}                                 ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC} ${WHITE}${ITALIC}Your custom message here. Ideas:${NC}                        ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC}                                                         ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC} ${WHITE}- Re-read AGENTS.md for project conventions${NC}            ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC} ${WHITE}- Check the task list with /tasks${NC}                      ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC} ${WHITE}- Review recent commits: git log --oneline -5${NC}          ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC} ${WHITE}- Run the test suite before continuing${NC}                 ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC} ${WHITE}- Check for uncommitted changes: git status${NC}            ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC}                                                         ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC} ${CYAN}</post-compact-reminder>${NC}                                ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_V}${NC} ${GREEN}EOF${NC}                                                     ${DIM}${BOX_V}${NC}"
        echo -e "  ${DIM}${BOX_BL}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_H}${BOX_BR}${NC}"
        echo ""
        echo -e "  ${CYAN}${BOLD}Step 3:${NC} Test your changes"
        echo ""
        echo -e "    ${WHITE}\$ ${GREEN}echo '{\"source\":\"compact\"}' | ~/.local/bin/claude-post-compact-reminder${NC}"
        echo ""
        echo -e "  ${DIM}${ITALIC}Tip: Changes take effect immediately — no restart needed for the hook itself.${NC}"
        echo -e "  ${DIM}${ITALIC}     Claude Code only needs restarting after the initial installation.${NC}"
        echo ""
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    local dry_run="false"
    local uninstall="false"
    local force="false"
    local action=""  # Track which standalone action to perform
    local action_arg=""  # Argument for the action (if needed)

    # Parse arguments (using while + shift for flags with values)
    while [[ $# -gt 0 ]]; do
        case "$1" in
            # Help and version
            --help|-h)
                show_help
                exit 0
                ;;
            --version)
                echo "post-compact-reminder v${VERSION}"
                exit 0
                ;;

            # Installation options
            --dry-run|-n)
                dry_run="true"
                shift
                ;;
            --uninstall|--remove)
                uninstall="true"
                shift
                ;;
            --force|-f)
                force="true"
                shift
                ;;
            --yes|-y)
                YES_FLAG="true"
                shift
                ;;

            # Customization options
            --interactive|-i)
                action="interactive"
                shift
                ;;
            --template)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "--template requires a value (minimal, detailed, checklist)"
                    exit 1
                fi
                action="template"
                action_arg="$2"
                shift 2
                ;;
            --show-template)
                action="show-template"
                shift
                ;;
            --completions)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "--completions requires a shell name (bash, zsh)"
                    exit 1
                fi
                action="completions"
                action_arg="$2"
                shift 2
                ;;

            # Diagnostic options
            --status|--check)
                action="status"
                shift
                ;;
            --diff)
                action="diff"
                shift
                ;;
            --changelog)
                action="changelog"
                shift
                ;;

            # Maintenance options
            --update)
                action="update"
                shift
                ;;
            --restore)
                action="restore"
                shift
                ;;

            # Output options
            --quiet|-q)
                QUIET="true"
                shift
                ;;
            --verbose|-V)
                VERBOSE="true"
                shift
                ;;
            --no-color)
                RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' WHITE='' BOLD='' DIM='' ITALIC='' UNDERLINE='' NC=''
                BOX_TL='┌' BOX_TR='┐' BOX_BL='└' BOX_BR='┘' BOX_H='─' BOX_V='│'
                shift
                ;;
            --log)
                if [[ -z "${2:-}" ]] || [[ "$2" == -* ]]; then
                    log_error "--log requires a file path"
                    exit 1
                fi
                LOG_FILE="$2"
                shift 2
                ;;

            # Unknown options
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
            *)
                log_error "Unexpected argument: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done

    # Initialize log file if specified
    if [[ -n "$LOG_FILE" ]]; then
        log_to_file "=== Session started: $(date) ==="
        log_to_file "Version: $VERSION"
        log_verbose "Logging to: $LOG_FILE"
    fi

    # Configuration
    local hook_dir="${HOOK_DIR:-$HOME/.local/bin}"
    local settings_dir="${SETTINGS_DIR:-$HOME/.claude}"

    # Handle standalone actions (these don't need banner/dependencies/lock)
    case "$action" in
        status)
            do_status "$hook_dir" "$settings_dir"
            exit $?
            ;;
        changelog)
            do_changelog
            exit 0
            ;;
        completions)
            do_completions "$action_arg"
            exit $?
            ;;
        show-template)
            do_show_template "$hook_dir"
            exit $?
            ;;
        diff)
            do_diff "$hook_dir"
            exit $?
            ;;
    esac

    # Acquire lock for operations that modify files
    acquire_lock

    print_banner

    # Check dependencies
    local allow_install="true"
    if [[ "$dry_run" == "true" ]]; then
        allow_install="false"
    fi
    if ! check_dependencies "$allow_install"; then
        exit 1
    fi

    log_info "Hook directory: ${hook_dir}"
    log_info "Settings directory: ${settings_dir}"
    log_verbose "Dry run: $dry_run, Force: $force, Uninstall: $uninstall"
    echo ""

    # Handle actions that modify files
    case "$action" in
        interactive)
            do_interactive "$hook_dir" "$settings_dir" "$dry_run"
            exit $?
            ;;
        template)
            do_template "$action_arg" "$hook_dir" "$dry_run"
            exit $?
            ;;
        update)
            do_update "$dry_run"
            exit $?
            ;;
        restore)
            do_restore "$settings_dir" "$dry_run"
            exit $?
            ;;
    esac

    # Default action: install or uninstall
    if [[ "$uninstall" == "true" ]]; then
        do_uninstall "$hook_dir" "$settings_dir" "$dry_run"
    else
        if do_install "$hook_dir" "$settings_dir" "$dry_run" "$force"; then
            print_summary "$dry_run" "$hook_dir"
        else
            exit 1
        fi
    fi
}

main "$@"
