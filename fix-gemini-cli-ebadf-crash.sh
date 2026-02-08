#!/usr/bin/env bash
set -euo pipefail

# ┌─────────────────────────────────────────────────────────────────────────┐
# │  Gemini CLI Patcher                                                     │
# │  https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts│
# └─────────────────────────────────────────────────────────────────────────┘
#
# Fixes two bugs in @google/gemini-cli:
#
#  1. EBADF CRASH: @lydell/node-pty's native C++ addon throws
#     Error("ioctl(2) failed, EBADF") when resizing a PTY whose fd is already
#     closed. The existing catch blocks only check err.code === 'ESRCH', but the
#     native addon puts "EBADF" only in .message (no .code property). The error
#     falls through and crashes the entire CLI.
#     FIX: Add err.message?.includes('EBADF') to both catch sites.
#
#  2. RATE LIMIT GIVES UP TOO FAST: The default retry config only attempts 3
#     times with a 30s max delay. During high-demand periods this means Gemini
#     gives up after ~45 seconds showing "Sorry there's high demand".
#     FIX: Bump maxAttempts 3 → 1000, maxDelayMs 30s → 5s, initialDelayMs 5s → 1s.
#     This hammers the API with short delays until it lets you through.
#
# Usage:
#   ./fix-gemini-cli-ebadf-crash.sh           # auto-detect and patch
#   ./fix-gemini-cli-ebadf-crash.sh --check   # check status without patching
#   ./fix-gemini-cli-ebadf-crash.sh --verify  # verify the EBADF bug exists
#   ./fix-gemini-cli-ebadf-crash.sh --revert  # undo all patches
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

# ── Banner ──────────────────────────────────────────────────────────────────

banner() {
    printf "\n"
    printf "  ${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════════╗${RESET}\n"
    printf "  ${BOLD}${CYAN}║${RESET}  ${WRENCH} ${BOLD}Gemini CLI Patcher${RESET}                                        ${BOLD}${CYAN}║${RESET}\n"
    printf "  ${BOLD}${CYAN}║${RESET}                                                               ${BOLD}${CYAN}║${RESET}\n"
    printf "  ${BOLD}${CYAN}║${RESET}  ${BUG} Fix 1: EBADF crash during PTY resize                     ${BOLD}${CYAN}║${RESET}\n"
    printf "  ${BOLD}${CYAN}║${RESET}  ${RETRY} Fix 2: Rate-limit retry gives up way too easily           ${BOLD}${CYAN}║${RESET}\n"
    printf "  ${BOLD}${CYAN}║${RESET}                                                               ${BOLD}${CYAN}║${RESET}\n"
    printf "  ${BOLD}${CYAN}║${RESET}  ${DIM}Patches @google/gemini-cli + gemini-cli-core in node_modules${RESET} ${BOLD}${CYAN}║${RESET}\n"
    printf "  ${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════════╝${RESET}\n"
    printf "\n"
}

# ── Mode parsing ────────────────────────────────────────────────────────────

MODE="patch"
case "${1:-}" in
    --check)  MODE="check" ;;
    --verify) MODE="verify" ;;
    --revert) MODE="revert" ;;
    --help|-h)
        banner
        printf "  ${BOLD}Usage:${RESET}\n"
        printf "    %s              ${DIM}# auto-detect and apply all patches${RESET}\n" "$(basename "$0")"
        printf "    %s --check      ${DIM}# check if patches are needed (no changes)${RESET}\n" "$(basename "$0")"
        printf "    %s --verify     ${DIM}# reproduce the EBADF bug to confirm it exists${RESET}\n" "$(basename "$0")"
        printf "    %s --revert     ${DIM}# undo all patches (restore originals)${RESET}\n" "$(basename "$0")"
        printf "\n"
        printf "  ${BOLD}What it fixes:${RESET}\n"
        printf "    ${BUG}  ${BOLD}EBADF crash${RESET} — ioctl(2) on closed PTY fd crashes the CLI\n"
        printf "    ${RETRY} ${BOLD}Rate limiting${RESET} — gives up after 3 attempts (~45s); patched to 1000 with fast retry\n"
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

if command -v node &>/dev/null; then
    NODE_VER="$(node --version 2>/dev/null || echo 'unknown')"
    ok "node $NODE_VER"
else
    fail "node is required but not found in PATH"
fi

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
        node_prefix="$(node -e 'console.log(process.execPath.replace(/\/bin\/node$/, ""))' 2>/dev/null || true)"
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
    GEMINI_VER="$(node -e "console.log(require('$GEMINI_ROOT/package.json').version)" 2>/dev/null || echo 'unknown')"
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

check_file() {
    local file="$1" label="$2"
    if [[ -f "$file" ]]; then
        ok "$label"
        detail "$file"
    else
        warn "$label — not found at: $file"
    fi
}

check_file "$SHELL_SVC"    "shellExecutionService.js"
check_file "$APP_CONTAINER" "AppContainer.js"
check_file "$RETRY_JS"      "retry.js"

# ── Verify mode ─────────────────────────────────────────────────────────────

if [[ "$MODE" == "verify" ]]; then
    step "Verifying the EBADF bug in your native pty addon"

    PTY_NODE=""
    PLATFORM="$(node -e "console.log(process.platform + '-' + process.arch)")"
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

        RESULT="$(node -e "
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
        MAX_ATTEMPTS="$(node -e "
            const c = require('fs').readFileSync('$RETRY_JS','utf8');
            const m = c.match(/DEFAULT_MAX_ATTEMPTS\s*=\s*(\d+)/);
            console.log(m ? m[1] : 'unknown');
        " 2>/dev/null || echo 'unknown')"
        MAX_DELAY="$(node -e "
            const c = require('fs').readFileSync('$RETRY_JS','utf8');
            const m = c.match(/maxDelayMs:\s*(\d+)/);
            console.log(m ? m[1] : 'unknown');
        " 2>/dev/null || echo 'unknown')"
        INIT_DELAY="$(node -e "
            const c = require('fs').readFileSync('$RETRY_JS','utf8');
            const m = c.match(/initialDelayMs:\s*(\d+)/);
            console.log(m ? m[1] : 'unknown');
        " 2>/dev/null || echo 'unknown')"

        detail "DEFAULT_MAX_ATTEMPTS = $MAX_ATTEMPTS (should be 1000)"
        detail "initialDelayMs = $INIT_DELAY (should be 1000)"
        detail "maxDelayMs = $MAX_DELAY (should be 5000)"

        if [[ "$MAX_ATTEMPTS" == "3" ]]; then
            printf "\n     ${YELLOW}Only 3 retry attempts — gives up after ~45 seconds.${RESET}\n"
            printf "     ${YELLOW}Run this script to bump to 1000 attempts with fast retry.${RESET}\n"
        elif [[ "$MAX_ATTEMPTS" == "1000" ]]; then
            ok "Already patched to 1000 attempts"
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

node_contains() {
    node -e "
        const fs = require('fs');
        process.exit(fs.readFileSync(process.argv[1],'utf8').includes(process.argv[2]) ? 0 : 1);
    " "$1" "$2" 2>/dev/null
}

node_replace() {
    node -e "
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
                    // On Unix, we get ESRCH (process gone) or EBADF (fd already closed).
                    // Native pty addon throws Error with 'EBADF' in message (no .code).
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
P3_OLD="export const DEFAULT_MAX_ATTEMPTS = 3;
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

# ── Apply patches ───────────────────────────────────────────────────────────

case "$MODE" in
    patch)  step "Applying patches (4 total)" ;;
    check)  step "Checking patch status" ;;
    revert) step "Reverting patches" ;;
esac

printf "\n"
info "Patch 1/4: EBADF catch in shellExecutionService.js"
detail "resizePty() — add EBADF to the list of safe-to-ignore errors"
patch_file "$SHELL_SVC" "$P1_MARKER" "$P1_OLD" "$P1_NEW" "shellExecutionService.js EBADF"

printf "\n"
info "Patch 2/4: EBADF catch in AppContainer.js"
detail "React useEffect resize wrapper — add EBADF + ESRCH checks"
patch_file "$APP_CONTAINER" "$P2_MARKER" "$P2_OLD" "$P2_NEW" "AppContainer.js EBADF"

printf "\n"
info "Patch 3/4: Retry config in retry.js"
detail "maxAttempts 3→1000, initialDelay 5s→1s, maxDelay 30s→5s"
detail "Keeps hammering the API with fast retries until it lets you through"
patch_file "$RETRY_JS" "$P3_MARKER" "$P3_OLD" "$P3_NEW" "retry.js rate-limit retry"

printf "\n"
info "Patch 4/4: Never bail on TerminalQuotaError in retry.js"
detail "TerminalQuotaError (daily/overload) normally causes immediate give-up"
detail "Patched to retry with backoff instead of surrendering"
patch_file "$RETRY_JS" "$P4_MARKER" "$P4_OLD" "$P4_NEW" "retry.js no-terminal-bail"

# ── Summary ─────────────────────────────────────────────────────────────────

printf "\n"
printf "  ${BOLD}${CYAN}══════════════════════════════════════════════════════════${RESET}\n"

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
                printf "     ${RETRY} Rate-limit retry: 1000 attempts, 1-5s delay (was 3/~45s)\n"
            fi
            if node_contains "$RETRY_JS" "$P4_MARKER" 2>/dev/null; then
                printf "     ${RETRY} Quota errors now retry with backoff instead of giving up\n"
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

printf "  ${BOLD}${CYAN}══════════════════════════════════════════════════════════${RESET}\n"

if [[ "$MODE" != "check" ]]; then
    printf "\n"
    detail "Patches live in node_modules — re-run after updating Gemini CLI:"
    detail "  bun update -g @google/gemini-cli"
fi
printf "\n"
