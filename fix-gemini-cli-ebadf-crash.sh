#!/usr/bin/env bash
set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────────────┐
# │  Gemini CLI Patcher                                                     │
# │  https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts│
# └─────────────────────────────────────────────────────────────────────────┘
#
# Fixes several issues in @google/gemini-cli:
#
#  1. EBADF CRASH: @lydell/node-pty's native C++ addon throws
#     Error("ioctl(2) failed, EBADF") when resizing a PTY whose fd is already
#     closed. The existing catch blocks only check err.code === 'ESRCH', but the
#     native addon puts "EBADF" only in .message (no .code property). The error
#     falls through and crashes the entire CLI.
#     FIX: Add err.message?.includes('EBADF') to both catch sites + at the
#          native pty.resize() source in unixTerminal.js (belt-and-suspenders).
#
#  2. RATE LIMIT GIVES UP TOO FAST: The default retry config only attempts 10
#     times with a 30s max delay. During high-demand periods this means Gemini
#     gives up too quickly showing "Sorry there's high demand".
#     FIX: Bump maxAttempts 10 → 1000, maxDelayMs 30s → 5s, initialDelayMs 5s → 1s.
#     This hammers the API with short delays until it lets you through.
#
#  3. DEAD HOOKS CAUSE BEFOORETOOL ERRORS: Hooks in ~/.gemini/settings.json
#     that reference nonexistent binaries fire BeforeTool errors on every tool
#     call. Hooks designed for Claude Code (JSON protocol) are incompatible with
#     Gemini's BeforeTool format and should be removed.
#     FIX: Parse settings.json, remove hooks with dead command binaries.
#
#  4. BUN NODE WRAPPER BREAKS PTY: If ~/.bun/bin appears before /usr/bin in
#     the gmi wrapper's PATH, #!/usr/bin/env node resolves to bun's node compat
#     shim (~/.bun/bin/node → bun). Bun's node wrapper has broken process.argv
#     and exits 0 on uncaught exceptions, causing node-pty native addon failures
#     that manifest as SIGHUP (signal 1) on every shell command.
#     FIX: Reorder PATH in gmi wrapper so /usr/bin comes before .bun/bin.
#
# Usage:
#   ./fix-gemini-cli-ebadf-crash.sh           # auto-detect and patch
#   ./fix-gemini-cli-ebadf-crash.sh --check   # check status without patching
#   ./fix-gemini-cli-ebadf-crash.sh --verify  # verify the EBADF bug exists
#   ./fix-gemini-cli-ebadf-crash.sh --revert  # undo all patches
#   ./fix-gemini-cli-ebadf-crash.sh --uninstall  # same as --revert
#
# IMPORTANT: Requires a real node binary (/usr/bin/node). Bun's `node` wrapper
# has a broken process.argv (eats first arg) and exits 0 on uncaught exceptions,
# which silently breaks the marker detection and file patching.
#
# Idempotent: safe to run multiple times. Re-run after `npm/bun update`.
# Cross-platform: macOS, Linux, WSL. Uses node for string replacement.

# ── Colors & Symbols ────────────────────────────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
RESET='\033[0m'

CHECK="${GREEN}✔${RESET}"
CROSS="${RED}✘${RESET}"
ARROW="${CYAN}▶${RESET}"
WRENCH="${YELLOW}🔧${RESET}"
BUG="${RED}🐛${RESET}"
SPARKLE="${MAGENTA}✨${RESET}"
RETRY="${CYAN}🔄${RESET}"

info()    { printf "  ${CYAN}${BOLD}info${RESET}  %s\n" "$*"; }
ok()      { printf "  ${CHECK}  ${GREEN}%s${RESET}\n" "$*"; }
warn()    { printf "  ${YELLOW}${BOLD}warn${RESET}  %s\n" "$*"; }
fail()    { printf "  ${CROSS}  ${RED}${BOLD}%s${RESET}\n" "$*"; exit 1; }
step()    { printf "\n  ${ARROW}  ${WHITE}%s${RESET}\n" "$*"; }
detail()  { printf "     ${DIM}%s${RESET}\n" "$*"; }

# ── Box drawing (emoji-free for guaranteed alignment) ─────────────────────

BOX_W=64

_box_rule() { local r; printf -v r '%*s' "$BOX_W" ''; echo "${r// /═}"; }
_box_dash() { local r; printf -v r '%*s' "$((BOX_W - 6))" ''; echo "${r// /─}"; }

box_top()    { printf "  ${BOLD}${CYAN}╔%s╗${RESET}\n" "$(_box_rule)"; }
box_bottom() { printf "  ${BOLD}${CYAN}╚%s╝${RESET}\n" "$(_box_rule)"; }
box_empty()  { printf "  ${BOLD}${CYAN}║${RESET}%*s${BOLD}${CYAN}║${RESET}\n" "$BOX_W" ""; }
box_sep()    { printf "  ${BOLD}${CYAN}║${RESET}   ${DIM}%s${RESET}   ${BOLD}${CYAN}║${RESET}\n" "$(_box_dash)"; }

# box_line PLAIN [FORMATTED]
# PLAIN = visible chars only (no ANSI, no emojis) for width calculation.
# FORMATTED = same content with ANSI color codes. If omitted, uses PLAIN.
box_line() {
    local plain="$1" fmt="${2:-$1}"
    local pad=$((BOX_W - ${#plain}))
    (( pad < 0 )) && pad=0
    printf "  ${BOLD}${CYAN}║${RESET}%b%*s${BOLD}${CYAN}║${RESET}\n" "$fmt" "$pad" ""
}

summary_rule() {
    local r; printf -v r '%*s' "$((BOX_W + 2))" ''; printf "  ${BOLD}${CYAN}%s${RESET}\n" "${r// /═}"
}

# ── Banner ────────────────────────────────────────────────────────────────

banner() {
    printf "\n"
    box_top
    box_empty
    box_line \
        "   GEMINI CLI PATCHER" \
        "   ${BOLD}${WHITE}GEMINI CLI PATCHER${RESET}"
    box_sep
    box_empty
    box_line \
        "     ▸ Fix EBADF crash on PTY resize" \
        "     ${RED}▸${RESET} Fix EBADF crash on PTY resize"
    box_line \
        "     ▸ Rate-limit retries: 10 → 1000, fast backoff" \
        "     ${YELLOW}▸${RESET} Rate-limit retries: 10 ${YELLOW}→${RESET} 1000, fast backoff"
    box_line \
        "     ▸ Quota errors retry instead of giving up" \
        "     ${GREEN}▸${RESET} Quota errors retry instead of giving up"
    box_line \
        "     ▸ Remove dead hooks from settings.json" \
        "     ${MAGENTA}▸${RESET} Remove dead hooks from settings.json"
    box_line \
        "     ▸ Fix bun-node PATH order in gmi wrapper" \
        "     ${CYAN}▸${RESET} Fix bun-node PATH order in gmi wrapper"
    box_empty
    box_bottom
    printf "\n"
}

# ── Mode parsing ────────────────────────────────────────────────────────────

MODE="patch"
case "${1:-}" in
    --check)  MODE="check" ;;
    --verify) MODE="verify" ;;
    --revert|--uninstall) MODE="revert" ;;
    --help|-h)
        banner
        printf "  ${BOLD}Usage:${RESET}\n"
        printf "    %s              ${DIM}# auto-detect and apply all patches${RESET}\n" "$(basename "$0")"
        printf "    %s --check      ${DIM}# check if patches are needed (no changes)${RESET}\n" "$(basename "$0")"
        printf "    %s --verify     ${DIM}# reproduce the EBADF bug to confirm it exists${RESET}\n" "$(basename "$0")"
        printf "    %s --revert     ${DIM}# undo all patches (restore originals)${RESET}\n" "$(basename "$0")"
        printf "    %s --uninstall  ${DIM}# same as --revert${RESET}\n" "$(basename "$0")"
        printf "\n"
        printf "  ${BOLD}What it fixes:${RESET}\n"
        printf "    ${BUG}  ${BOLD}EBADF crash${RESET} — ioctl(2) on closed PTY fd crashes the CLI\n"
        printf "    ${RETRY} ${BOLD}Rate limiting${RESET} — gives up after 10 attempts; patched to 1000 with fast retry\n"
        printf "\n"
        printf "  ${BOLD}Notes:${RESET}\n"
        printf "    ${DIM}Idempotent — safe to run multiple times${RESET}\n"
        printf "    ${DIM}Patches live in node_modules — re-run after updating Gemini CLI${RESET}\n"
        printf "    ${DIM}Cross-platform — macOS, Linux, WSL (requires node)${RESET}\n"
        printf "\n"
        exit 0
        ;;
    "") ;;
    *)  fail "Unknown flag: $1 (use --help)" ;;
esac

banner

# ── Prerequisites ───────────────────────────────────────────────────────────

step "Checking prerequisites"

# Find a REAL node binary. Bun ships a "node" wrapper that:
#   1. Eats the first positional arg from process.argv
#   2. Exits 0 on uncaught exceptions when stderr is redirected
# Both bugs silently break node_contains() and node_replace().
# Prefer /usr/bin/node or any node that isn't bun's wrapper.
NODE_BIN=""
for candidate in /usr/bin/node /usr/local/bin/node; do
    if [[ -x "$candidate" ]]; then
        NODE_BIN="$candidate"
        break
    fi
done
if [[ -z "$NODE_BIN" ]]; then
    # Fall back to PATH, but verify it's not bun's broken wrapper
    if command -v node &>/dev/null; then
        NODE_BIN="$(command -v node)"
        # Detect bun's wrapper by checking if it eats argv
        ARGV_TEST="$("$NODE_BIN" -e "console.log(process.argv.length)" dummy 2>/dev/null || echo 0)"
        if [[ "$ARGV_TEST" -lt 2 ]]; then
            warn "Detected bun's node wrapper (broken process.argv). Looking for real node..."
            # Try nvm, fnm, etc.
            for d in "$HOME/.nvm/versions/node"/*/bin/node "$HOME/.local/share/fnm/node-versions"/*/installation/bin/node; do
                if [[ -x "$d" ]]; then
                    NODE_BIN="$d"
                    break
                fi
            done
        fi
    fi
fi

if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
    fail "node is required but not found (bun's node wrapper is not compatible)"
fi
NODE_VER="$("$NODE_BIN" --version 2>/dev/null || echo 'unknown')"
ok "node $NODE_VER ($NODE_BIN)"

# ── Locate the Gemini CLI installation ──────────────────────────────────────

step "Searching for Gemini CLI installation"

find_gemini_root() {
    local candidates=()

    # bun global
    candidates+=("$HOME/.bun/install/global/node_modules/@google/gemini-cli")

    # npm global
    if command -v npm &>/dev/null; then
        local npm_root
        if npm_root="$(npm root -g 2>/dev/null)"; then
            candidates+=("$npm_root/@google/gemini-cli")
        fi
    fi

    # yarn global
    if command -v yarn &>/dev/null; then
        local yarn_root
        if yarn_root="$(yarn global dir 2>/dev/null)"; then
            candidates+=("$yarn_root/node_modules/@google/gemini-cli")
        fi
    fi

    # pnpm global
    if command -v pnpm &>/dev/null; then
        local pnpm_root
        if pnpm_root="$(pnpm root -g 2>/dev/null)"; then
            candidates+=("$pnpm_root/@google/gemini-cli")
        fi
    fi

    # Homebrew (macOS)
    if command -v brew &>/dev/null; then
        local brew_prefix
        brew_prefix="$(brew --prefix 2>/dev/null)"
        candidates+=("$brew_prefix/lib/node_modules/@google/gemini-cli")
    fi

    # NVM / fnm
    if command -v node &>/dev/null; then
        local node_prefix
        node_prefix="$("$NODE_BIN" -e 'console.log(process.execPath.replace(/\/bin\/node$/, ""))' 2>/dev/null || true)"
        if [[ -n "$node_prefix" ]]; then
            candidates+=("$node_prefix/lib/node_modules/@google/gemini-cli")
        fi
    fi

    for dir in "${candidates[@]}"; do
        if [[ -d "$dir/dist" ]]; then
            echo "$dir"
            return 0
        fi
    done
    return 1
}

GEMINI_ROOT=""
if ! GEMINI_ROOT="$(find_gemini_root 2>/dev/null)"; then
    fail "Could not find @google/gemini-cli — is it installed globally?"
fi
ok "Found: $GEMINI_ROOT"

# Get version
GEMINI_VER="unknown"
if [[ -f "$GEMINI_ROOT/package.json" ]]; then
    GEMINI_VER="$("$NODE_BIN" -e "console.log(require('$GEMINI_ROOT/package.json').version)" 2>/dev/null || echo 'unknown')"
fi
detail "Version: $GEMINI_VER"

# ── Resolve patch target paths ──────────────────────────────────────────────

step "Locating target files"

CORE_BASE="$(dirname "$GEMINI_ROOT")/gemini-cli-core"

resolve_path() {
    realpath "$1" 2>/dev/null || readlink -f "$1" 2>/dev/null || echo "$1"
}

SHELL_SVC="$(resolve_path "$CORE_BASE/dist/src/services/shellExecutionService.js")"
APP_CONTAINER="$(resolve_path "$GEMINI_ROOT/dist/src/ui/AppContainer.js")"
RETRY_JS="$(resolve_path "$CORE_BASE/dist/src/utils/retry.js")"

# Find unixTerminal.js in @lydell/node-pty (the native PTY addon)
UNIX_TERMINAL=""
for candidate in \
    "$(dirname "$GEMINI_ROOT")/@lydell/node-pty/unixTerminal.js" \
    "$(dirname "$GEMINI_ROOT")/../@lydell/node-pty/unixTerminal.js"; do
    if [[ -f "$candidate" ]]; then
        UNIX_TERMINAL="$(resolve_path "$candidate")"
        break
    fi
done

check_file() {
    local file="$1" label="$2"
    if [[ -f "$file" ]]; then
        ok "$label"
        detail "$file"
    else
        warn "$label — not found at: $file"
    fi
}

check_file "$SHELL_SVC"      "shellExecutionService.js"
check_file "$APP_CONTAINER"   "AppContainer.js"
check_file "$RETRY_JS"        "retry.js"
if [[ -n "$UNIX_TERMINAL" ]]; then
    check_file "$UNIX_TERMINAL"   "unixTerminal.js"
else
    warn "unixTerminal.js — not found (searched @lydell/node-pty)"
fi

# ── Utility: check if a file contains a string ────────────────────────────

node_contains() {
    "$NODE_BIN" -e "
        const fs = require('fs');
        process.exit(fs.readFileSync(process.argv[1],'utf8').includes(process.argv[2]) ? 0 : 1);
    " "$1" "$2" 2>/dev/null
}

# ── Verify mode ─────────────────────────────────────────────────────────────

if [[ "$MODE" == "verify" ]]; then
    step "Verifying the EBADF bug in your native pty addon"

    PTY_NODE=""
    PLATFORM="$("$NODE_BIN" -e "console.log(process.platform + '-' + process.arch)")"
    for candidate in \
        "$(dirname "$GEMINI_ROOT")/../@lydell/node-pty-${PLATFORM}/pty.node" \
        "$(dirname "$GEMINI_ROOT")/../@lydell/node-pty/prebuilds/${PLATFORM}/pty.node"; do
        if [[ -f "$candidate" ]]; then
            PTY_NODE="$(resolve_path "$candidate")"
            break
        fi
    done

    if [[ -z "$PTY_NODE" ]]; then
        warn "Could not find native pty.node for $PLATFORM"
    else
        ok "Found native addon: $PTY_NODE"
        detail "Calling pty.resize(-1, 80, 24) to trigger EBADF..."

        RESULT="$("$NODE_BIN" -e "
            const pty = require('$PTY_NODE');
            try {
                pty.resize(-1, 80, 24);
                console.log('NO_ERROR');
            } catch(e) {
                console.log('message=' + e.message);
                console.log('code=' + e.code);
                console.log('has_code_prop=' + ('code' in e));
            }
        " 2>&1 || true)"

        if echo "$RESULT" | grep -q "EBADF"; then
            printf "\n  ${BUG}  ${RED}${BOLD}Bug confirmed!${RESET}\n\n"
            echo "$RESULT" | while IFS= read -r line; do detail "$line"; done
            if echo "$RESULT" | grep -q "code=undefined"; then
                printf "\n"
                printf "     ${YELLOW}The native addon sets NO .code property.${RESET}\n"
                printf "     ${YELLOW}err.code === 'EBADF' will always be false.${RESET}\n"
                printf "     ${YELLOW}Only err.message.includes('EBADF') catches it.${RESET}\n"
            fi
        else
            ok "Bug not reproducible — pty.resize didn't throw EBADF"
        fi
    fi

    step "Checking retry configuration"
    if [[ -f "$RETRY_JS" ]]; then
        MAX_ATTEMPTS="$("$NODE_BIN" -e "
            const c = require('fs').readFileSync('$RETRY_JS','utf8');
            const m = c.match(/DEFAULT_MAX_ATTEMPTS\s*=\s*(\d+)/);
            console.log(m ? m[1] : 'unknown');
        " 2>/dev/null || echo 'unknown')"
        MAX_DELAY="$("$NODE_BIN" -e "
            const c = require('fs').readFileSync('$RETRY_JS','utf8');
            const m = c.match(/maxDelayMs:\s*(\d+)/);
            console.log(m ? m[1] : 'unknown');
        " 2>/dev/null || echo 'unknown')"
        INIT_DELAY="$("$NODE_BIN" -e "
            const c = require('fs').readFileSync('$RETRY_JS','utf8');
            const m = c.match(/initialDelayMs:\s*(\d+)/);
            console.log(m ? m[1] : 'unknown');
        " 2>/dev/null || echo 'unknown')"

        detail "DEFAULT_MAX_ATTEMPTS = $MAX_ATTEMPTS (should be 1000)"
        detail "initialDelayMs = $INIT_DELAY (should be 1000)"
        detail "maxDelayMs = $MAX_DELAY (should be 5000)"

        if [[ "$MAX_ATTEMPTS" == "10" ]]; then
            printf "\n     ${YELLOW}Only 10 retry attempts — gives up too quickly.${RESET}\n"
            printf "     ${YELLOW}Run this script to bump to 1000 attempts with fast retry.${RESET}\n"
        elif [[ "$MAX_ATTEMPTS" == "1000" ]]; then
            ok "Already patched to 1000 attempts"
        fi

        step "Checking TerminalQuotaError behavior"
        if node_contains "$RETRY_JS" "// PATCHED: treat TerminalQuotaError as retryable"; then
            ok "TerminalQuotaError retries with backoff (patched)"
        else
            printf "     ${YELLOW}TerminalQuotaError causes immediate give-up (unpatched).${RESET}\n"
            printf "     ${YELLOW}Run this script to make it retry with backoff.${RESET}\n"
        fi
    else
        warn "retry.js not found"
    fi

    printf "\n"
    exit 0
fi

# ── Patch engine ────────────────────────────────────────────────────────────

patched=0
skipped=0
failed=0
total=0
inc_patched() { patched=$((patched + 1)); }
inc_skipped() { skipped=$((skipped + 1)); }
inc_failed()  { failed=$((failed + 1));  }
inc_total()   { total=$((total + 1)); }

node_replace() {
    "$NODE_BIN" -e "
        const fs = require('fs');
        const [,file,old_str,new_str] = process.argv;
        let content = fs.readFileSync(file, 'utf8');
        if (!content.includes(old_str)) process.exit(2);
        content = content.replace(old_str, new_str);
        fs.writeFileSync(file, content, 'utf8');
    " "$1" "$2" "$3" 2>/dev/null
}

# patch_file FILE MARKER OLD NEW LABEL
# MARKER: string that only exists in the patched version
# In revert mode: checks for MARKER presence, replaces NEW → OLD
patch_file() {
    local file="$1" marker="$2" old_string="$3" new_string="$4" label="$5"
    inc_total

    if [[ ! -f "$file" ]]; then
        warn "$label — file not found, skipping"
        inc_failed
        return 0
    fi

    local has_marker=false
    node_contains "$file" "$marker" && has_marker=true

    case "$MODE" in
        check)
            if $has_marker; then
                ok "$label — already patched"
                inc_skipped
            else
                printf "  ${WRENCH}  ${YELLOW}%s — needs patching${RESET}\n" "$label"
                inc_failed
            fi
            ;;
        patch)
            if $has_marker; then
                ok "$label — already patched, skipping"
                inc_skipped
            elif node_contains "$file" "$old_string"; then
                detail "Applying..."
                if node_replace "$file" "$old_string" "$new_string"; then
                    ok "$label — patched"
                    inc_patched
                else
                    warn "$label — replacement failed"
                    inc_failed
                fi
            else
                warn "$label — original pattern not found (different version?)"
                inc_failed
            fi
            ;;
        revert)
            if ! $has_marker; then
                ok "$label — not patched, nothing to revert"
                inc_skipped
            elif node_contains "$file" "$new_string"; then
                detail "Reverting..."
                if node_replace "$file" "$new_string" "$old_string"; then
                    ok "$label — reverted"
                    inc_patched
                else
                    warn "$label — revert failed"
                    inc_failed
                fi
            else
                warn "$label — marker found but exact patch text not found"
                inc_failed
            fi
            ;;
    esac
}

# ── Define patches ──────────────────────────────────────────────────────────

# --- Patch 1: shellExecutionService.js EBADF ---
P1_MARKER="err.message?.includes('EBADF')"
P1_OLD="const isEsrch = err.code === 'ESRCH';
                const isWindowsPtyError = err.message?.includes('Cannot resize a pty that has already exited');
                if (isEsrch || isWindowsPtyError) {
                    // On Unix, we get an ESRCH error.
                    // On Windows, we get a message-based error.
                    // In both cases, it's safe to ignore."
P1_NEW="const isEsrch = err.code === 'ESRCH';
                const isEbadf = err.code === 'EBADF' || err.message?.includes('EBADF');
                const isWindowsPtyError = err.message?.includes('Cannot resize a pty that has already exited');
                if (isEsrch || isEbadf || isWindowsPtyError) {
                    // On Unix, we get an ESRCH error (process gone) or EBADF (fd closed).
                    // Native pty addon throws Error with message containing 'EBADF' (no .code).
                    // On Windows, we get a message-based error.
                    // In all cases, it's safe to ignore."

# --- Patch 2: AppContainer.js EBADF ---
P2_MARKER="e.message.includes('EBADF')"
P2_OLD="if (!(e instanceof Error &&
                    e.message.includes('Cannot resize a pty that has already exited'))) {
                    throw e;
                }"
P2_NEW="if (!(e instanceof Error &&
                    (e.message.includes('Cannot resize a pty that has already exited') ||
                     e.message.includes('EBADF') ||
                     e.code === 'EBADF' ||
                     e.code === 'ESRCH'))) {
                    throw e;
                }"

# --- Patch 3: retry.js — hammer the API until it lets you through ---
P3_MARKER="DEFAULT_MAX_ATTEMPTS = 1000"
P3_OLD="export const DEFAULT_MAX_ATTEMPTS = 10;
const DEFAULT_RETRY_OPTIONS = {
    maxAttempts: DEFAULT_MAX_ATTEMPTS,
    initialDelayMs: 5000,
    maxDelayMs: 30000, // 30 seconds"
P3_NEW="export const DEFAULT_MAX_ATTEMPTS = 1000;
const DEFAULT_RETRY_OPTIONS = {
    maxAttempts: DEFAULT_MAX_ATTEMPTS,
    initialDelayMs: 1000,
    maxDelayMs: 5000, // 5 seconds max between retries"

# --- Patch 4: retry.js — don't immediately bail on TerminalQuotaError ---
# The original code sees TerminalQuotaError (daily limit / overloaded) and
# immediately throws without retrying. We convert it to a RetryableQuotaError
# so it keeps retrying with backoff instead of giving up.
P4_MARKER="// PATCHED: treat TerminalQuotaError as retryable"
P4_OLD="            if (classifiedError instanceof TerminalQuotaError ||
                classifiedError instanceof ModelNotFoundError) {
                if (onPersistent429) {
                    try {
                        const fallbackModel = await onPersistent429(authType, classifiedError);
                        if (fallbackModel) {
                            attempt = 0; // Reset attempts and retry with the new model.
                            currentDelay = initialDelayMs;
                            continue;
                        }
                    }
                    catch (fallbackError) {
                        debugLogger.warn('Fallback to Flash model failed:', fallbackError);
                    }
                }
                // Terminal/not_found already recorded; nothing else to mark here.
                throw classifiedError; // Throw if no fallback or fallback failed.
            }"
P4_NEW="            // PATCHED: treat TerminalQuotaError as retryable — don't give up
            if (classifiedError instanceof ModelNotFoundError) {
                throw classifiedError; // Model genuinely doesn't exist, no point retrying.
            }
            if (classifiedError instanceof TerminalQuotaError) {
                // Instead of immediately giving up, retry with backoff.
                // The 'terminal' classification is often just temporary overload.
                if (attempt >= maxAttempts) {
                    if (onPersistent429) {
                        try {
                            const fallbackModel = await onPersistent429(authType, classifiedError);
                            if (fallbackModel) {
                                attempt = 0;
                                currentDelay = initialDelayMs;
                                continue;
                            }
                        }
                        catch (fallbackError) {
                            debugLogger.warn('Fallback failed:', fallbackError);
                        }
                    }
                    throw classifiedError;
                }
                const jitter = currentDelay * 0.3 * (Math.random() * 2 - 1);
                const delayWithJitter = Math.max(0, currentDelay + jitter);
                debugLogger.warn(\`Attempt \${attempt} hit quota limit: \${classifiedError.message}. Retrying in \${Math.round(delayWithJitter)}ms...\`);
                if (onRetry) { onRetry(attempt, classifiedError, delayWithJitter); }
                await delay(delayWithJitter, signal);
                currentDelay = Math.min(maxDelayMs, currentDelay * 2);
                continue;
            }"

# --- Patch 5: unixTerminal.js — catch EBADF at the pty.resize() source ---
# Belt-and-suspenders: even if the higher-level catches miss it, this prevents
# the native ioctl error from escaping node-pty entirely.
P5_MARKER="// PATCHED: catch EBADF from native pty.resize"
P5_OLD="    UnixTerminal.prototype.resize = function (cols, rows) {
        if (cols <= 0 || rows <= 0 || isNaN(cols) || isNaN(rows) || cols === Infinity || rows === Infinity) {
            throw new Error('resizing must be done using positive cols and rows');
        }
        pty.resize(this._fd, cols, rows);
        this._cols = cols;
        this._rows = rows;
    };"
P5_NEW="    UnixTerminal.prototype.resize = function (cols, rows) {
        // PATCHED: catch EBADF from native pty.resize
        if (cols <= 0 || rows <= 0 || isNaN(cols) || isNaN(rows) || cols === Infinity || rows === Infinity) {
            throw new Error('resizing must be done using positive cols and rows');
        }
        try {
            pty.resize(this._fd, cols, rows);
        } catch (e) {
            // The native addon throws \"ioctl(2) failed, EBADF\" when the fd
            // is already closed (race between exit and resize). Safe to ignore.
            if (e && (e.message?.includes('EBADF') || e.message?.includes('ESRCH') || e.code === 'EBADF' || e.code === 'ESRCH')) {
                return;
            }
            throw e;
        }
        this._cols = cols;
        this._rows = rows;
    };"

# ── Apply patches ───────────────────────────────────────────────────────────

case "$MODE" in
    patch)  step "Applying patches (5 node_modules + 2 environment)" ;;
    check)  step "Checking patch status" ;;
    revert) step "Reverting patches" ;;
esac

printf "\n"
info "Patch 1/7: EBADF catch in shellExecutionService.js"
detail "resizePty() — add EBADF to the list of safe-to-ignore errors"
patch_file "$SHELL_SVC" "$P1_MARKER" "$P1_OLD" "$P1_NEW" "shellExecutionService.js EBADF"

printf "\n"
info "Patch 2/7: EBADF catch in AppContainer.js"
detail "React useEffect resize wrapper — add EBADF + ESRCH checks"
patch_file "$APP_CONTAINER" "$P2_MARKER" "$P2_OLD" "$P2_NEW" "AppContainer.js EBADF"

printf "\n"
info "Patch 3/7: Retry config in retry.js"
detail "maxAttempts 10→1000, initialDelay 5s→1s, maxDelay 30s→5s"
detail "Keeps hammering the API with fast retries until it lets you through"
patch_file "$RETRY_JS" "$P3_MARKER" "$P3_OLD" "$P3_NEW" "retry.js rate-limit retry"

printf "\n"
info "Patch 4/7: Never bail on TerminalQuotaError in retry.js"
detail "TerminalQuotaError (daily/overload) normally causes immediate give-up"
detail "Patched to retry with backoff instead of surrendering"
patch_file "$RETRY_JS" "$P4_MARKER" "$P4_OLD" "$P4_NEW" "retry.js no-terminal-bail"

printf "\n"
info "Patch 5/7: EBADF catch at source in unixTerminal.js"
detail "Belt-and-suspenders: wrap native pty.resize() in try/catch for EBADF/ESRCH"
patch_file "$UNIX_TERMINAL" "$P5_MARKER" "$P5_OLD" "$P5_NEW" "unixTerminal.js EBADF"

# --- Patch 6: Sanitize ~/.gemini/settings.json hooks ---
# Remove hooks whose command binary doesn't exist or that use Claude Code's
# JSON protocol (incompatible with Gemini's BeforeTool format).
printf "\n"
info "Patch 6/7: Sanitize dead hooks in ~/.gemini/settings.json"
detail "Remove hooks pointing to nonexistent binaries"

GEMINI_SETTINGS="$HOME/.gemini/settings.json"
inc_total

if [[ ! -f "$GEMINI_SETTINGS" ]]; then
    ok "~/.gemini/settings.json — not found, skipping"
    inc_skipped
elif ! "$NODE_BIN" -e "JSON.parse(require('fs').readFileSync('$GEMINI_SETTINGS','utf8'))" 2>/dev/null; then
    warn "~/.gemini/settings.json — invalid JSON, skipping"
    inc_failed
else
    case "$MODE" in
        patch|check)
            DEAD_HOOKS="$("$NODE_BIN" -e "
                const fs = require('fs');
                const path = require('path');
                const settings = JSON.parse(fs.readFileSync('$GEMINI_SETTINGS', 'utf8'));
                const hooks = settings.hooks || {};
                const dead = [];
                for (const [event, matchers] of Object.entries(hooks)) {
                    if (!Array.isArray(matchers)) continue;
                    for (const matcher of matchers) {
                        const cmds = matcher.hooks || [];
                        for (const hook of cmds) {
                            if (hook.command) {
                                // Extract the binary from the command string
                                const bin = hook.command.split(/\s+/)[0]
                                    .replace(/^\\\$HOME/, process.env.HOME || '')
                                    .replace(/^~/, process.env.HOME || '');
                                try { fs.accessSync(bin, fs.constants.X_OK); }
                                catch { dead.push(event + ':' + bin); }
                            }
                        }
                    }
                }
                console.log(JSON.stringify(dead));
            " 2>/dev/null || echo '[]')"

            DEAD_COUNT="$("$NODE_BIN" -e "console.log(JSON.parse(process.argv[1]).length)" "$DEAD_HOOKS" 2>/dev/null || echo 0)"

            if [[ "$DEAD_COUNT" -eq 0 ]]; then
                # Also check if hooks section exists but is empty
                HAS_HOOKS="$("$NODE_BIN" -e "
                    const s = JSON.parse(require('fs').readFileSync('$GEMINI_SETTINGS','utf8'));
                    console.log(s.hooks && Object.keys(s.hooks).length > 0 ? 'yes' : 'no');
                " 2>/dev/null || echo 'no')"
                if [[ "$HAS_HOOKS" == "no" ]]; then
                    ok "settings.json hooks — clean (no hooks or all valid)"
                    inc_skipped
                else
                    ok "settings.json hooks — all hook binaries exist"
                    inc_skipped
                fi
            elif [[ "$MODE" == "check" ]]; then
                printf "  ${WRENCH}  ${YELLOW}settings.json — %d dead hook(s) found${RESET}\n" "$DEAD_COUNT"
                "$NODE_BIN" -e "JSON.parse(process.argv[1]).forEach(h => console.log('     ' + h))" "$DEAD_HOOKS" 2>/dev/null
                inc_failed
            else
                detail "Found $DEAD_COUNT dead hook(s), removing..."
                "$NODE_BIN" -e "
                    const fs = require('fs');
                    const settingsPath = '$GEMINI_SETTINGS';
                    const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
                    const hooks = settings.hooks || {};
                    let removed = 0;

                    for (const [event, matchers] of Object.entries(hooks)) {
                        if (!Array.isArray(matchers)) continue;
                        for (let i = matchers.length - 1; i >= 0; i--) {
                            const cmds = matchers[i].hooks || [];
                            for (let j = cmds.length - 1; j >= 0; j--) {
                                if (cmds[j].command) {
                                    const bin = cmds[j].command.split(/\s+/)[0]
                                        .replace(/^\\\$HOME/, process.env.HOME || '')
                                        .replace(/^~/, process.env.HOME || '');
                                    try { fs.accessSync(bin, fs.constants.X_OK); }
                                    catch {
                                        console.log('  Removed: ' + event + ' → ' + cmds[j].command);
                                        cmds.splice(j, 1);
                                        removed++;
                                    }
                                }
                            }
                            if (cmds.length === 0) matchers.splice(i, 1);
                        }
                        if (matchers.length === 0) delete hooks[event];
                    }

                    if (Object.keys(hooks).length === 0) delete settings.hooks;
                    else settings.hooks = hooks;

                    fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n', 'utf8');
                    console.log('Removed ' + removed + ' dead hook(s)');
                " 2>/dev/null
                ok "settings.json hooks — sanitized"
                inc_patched
            fi
            ;;
        revert)
            ok "settings.json hooks — revert not supported (manual config)"
            inc_skipped
            ;;
    esac
fi

# --- Patch 7: Fix gmi wrapper PATH ordering ---
# If ~/.bun/bin appears before /usr/bin in PATH, #!/usr/bin/env node resolves
# to bun's node wrapper which breaks node-pty native addons → SIGHUP on all
# shell commands. Fix: ensure /usr/bin comes first.
printf "\n"
info "Patch 7/7: Fix PATH ordering in gmi wrapper"
detail "Ensure /usr/bin before .bun/bin so real node is used, not bun's shim"

GMI_WRAPPER="$HOME/.local/bin/gmi"
P7_MARKER="/usr/bin MUST come before .bun/bin"
inc_total

if [[ ! -f "$GMI_WRAPPER" ]]; then
    ok "gmi wrapper — not found at $GMI_WRAPPER, skipping"
    inc_skipped
else
    case "$MODE" in
        check)
            if grep -q "$P7_MARKER" "$GMI_WRAPPER" 2>/dev/null; then
                ok "gmi wrapper — PATH already fixed"
                inc_skipped
            elif grep -q '\.bun/bin.*/usr/bin' "$GMI_WRAPPER" 2>/dev/null; then
                printf "  ${WRENCH}  ${YELLOW}gmi wrapper — .bun/bin before /usr/bin in PATH (needs fix)${RESET}\n"
                inc_failed
            else
                ok "gmi wrapper — PATH order looks OK"
                inc_skipped
            fi
            ;;
        patch)
            if grep -q "$P7_MARKER" "$GMI_WRAPPER" 2>/dev/null; then
                ok "gmi wrapper — PATH already fixed, skipping"
                inc_skipped
            elif grep -q '\.bun/bin.*/usr/bin' "$GMI_WRAPPER" 2>/dev/null; then
                detail "Reordering PATH: /usr/bin before .bun/bin..."
                # Replace any PATH= assignment where .bun/bin precedes /usr/bin
                "$NODE_BIN" -e "
                    const fs = require('fs');
                    let content = fs.readFileSync('$GMI_WRAPPER', 'utf8');
                    // Match PATH assignments where .bun/bin comes before /usr/bin
                    const pathRe = /PATH=\"([^\"]*\.bun\/bin[^\"]*\/usr\/bin[^\"]*)\"/;
                    const m = content.match(pathRe);
                    if (m) {
                        const oldPath = m[1];
                        // Split on :, move /usr/bin and /usr/local/bin to front
                        const parts = oldPath.split(':');
                        const usrBin = parts.filter(p => p === '/usr/bin' || p === '/usr/local/bin');
                        const rest = parts.filter(p => p !== '/usr/bin' && p !== '/usr/local/bin');
                        const newPath = [...usrBin, ...rest].join(':');
                        content = content.replace(oldPath, newPath);
                        // Add comment if not present
                        if (!content.includes('$P7_MARKER')) {
                            content = content.replace(
                                /(\nexec env )/,
                                '\n# CRITICAL: /usr/bin MUST come before .bun/bin so #!/usr/bin/env node resolves\n# to real node (/usr/bin/node), NOT bun' + \"'\" + 's node wrapper (~/.bun/bin/node → bun).\n# Bun' + \"'\" + 's node compat shim breaks node-pty native addons causing SIGHUP on all\n# shell commands (every PTY child gets signal 1 immediately).\n\$1'
                            );
                        }
                        fs.writeFileSync('$GMI_WRAPPER', content, 'utf8');
                        console.log('Reordered: ' + newPath);
                    } else {
                        console.log('No PATH pattern matched');
                        process.exit(2);
                    }
                " 2>/dev/null
                if [[ $? -eq 0 ]]; then
                    ok "gmi wrapper — PATH reordered"
                    inc_patched
                else
                    warn "gmi wrapper — could not auto-fix PATH order"
                    inc_failed
                fi
            else
                ok "gmi wrapper — PATH order already correct"
                inc_skipped
            fi
            ;;
        revert)
            ok "gmi wrapper — revert not supported (manual fix)"
            inc_skipped
            ;;
    esac
fi

# ── Summary ─────────────────────────────────────────────────────────────────

printf "\n"
summary_rule

case "$MODE" in
    patch)
        if [[ $failed -gt 0 ]]; then
            printf "  ${WRENCH}  ${YELLOW}${BOLD}%d/%d patched, %d skipped, %d failed${RESET}\n" "$patched" "$total" "$skipped" "$failed"
            detail "Some patches could not be applied — your Gemini CLI version may differ."
        elif [[ $patched -gt 0 ]]; then
            printf "  ${SPARKLE}  ${GREEN}${BOLD}%d/%d patched, %d already applied${RESET}\n" "$patched" "$total" "$skipped"
        else
            printf "  ${SPARKLE}  ${GREEN}${BOLD}All %d patches already applied — nothing to do${RESET}\n" "$total"
        fi
        if [[ $((patched + skipped)) -gt 0 ]]; then
            printf "\n"
            if [[ $patched -gt 0 ]] || node_contains "$SHELL_SVC" "$P1_MARKER" 2>/dev/null; then
                printf "     ${BUG} EBADF resize crash → fixed\n"
            fi
            if node_contains "$RETRY_JS" "$P3_MARKER" 2>/dev/null; then
                printf "     ${RETRY} Rate-limit retry: 1000 attempts, 1-5s delay (was 10/30s)\n"
            fi
            if node_contains "$RETRY_JS" "$P4_MARKER" 2>/dev/null; then
                printf "     ${RETRY} Quota errors now retry with backoff instead of giving up\n"
            fi
            if [[ -f "$GEMINI_SETTINGS" ]] && ! "$NODE_BIN" -e "const s=JSON.parse(require('fs').readFileSync('$GEMINI_SETTINGS','utf8'));process.exit(s.hooks?1:0)" 2>/dev/null; then
                printf "     ${WRENCH} Dead hooks removed from settings.json\n"
            fi
            if [[ -f "$GMI_WRAPPER" ]] && grep -q "$P7_MARKER" "$GMI_WRAPPER" 2>/dev/null; then
                printf "     ${WRENCH} gmi wrapper PATH: /usr/bin before .bun/bin\n"
            fi
        fi
        ;;
    check)
        if [[ $failed -gt 0 ]]; then
            printf "  ${WRENCH}  ${YELLOW}${BOLD}%d/%d patches needed${RESET}\n" "$failed" "$total"
            detail "Run without --check to apply."
        else
            printf "  ${SPARKLE}  ${GREEN}${BOLD}All %d patches already applied${RESET}\n" "$total"
        fi
        ;;
    revert)
        if [[ $patched -gt 0 ]]; then
            printf "  ${CHECK}  ${GREEN}${BOLD}%d/%d patches reverted${RESET}\n" "$patched" "$total"
        else
            printf "  ${DIM}  Nothing to revert — no patches were applied${RESET}\n"
        fi
        ;;
esac

summary_rule

if [[ "$MODE" != "check" ]]; then
    printf "\n"
    detail "Patches live in node_modules — re-run after updating Gemini CLI:"
    detail "  bun update -g @google/gemini-cli"
fi
printf "\n"
