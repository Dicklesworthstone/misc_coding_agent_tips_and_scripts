#!/usr/bin/env bash
# Regression test for issue #9: install-uca.sh and uninstall-uca.sh must run to
# completion when gum is installed and stdout is a terminal.
#
# Two failure modes are covered, both independent of the gum major version
# (reproduced identically on gum 0.17.0 and gum 2.0.0):
#   1. `gum style "-> text"`  -> "gum: error: unknown flag ->"   (text parsed as flag)
#   2. `gum spin -- <function>` -> "exec: ...: executable file not found in $PATH"
#
# The scripts only enable gum when stdout is a tty, so each run happens inside a
# pseudo-terminal via script(1). A logging shim in front of the real gum proves
# the gum code paths were actually exercised (positive control).
#
# Usage: bash tests/test-uca-gum.sh          (skips when gum is not installed)
#        GUM_BIN=/path/to/gum bash tests/test-uca-gum.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUM_BIN="${GUM_BIN:-$(command -v gum 2>/dev/null || true)}"
if [ -z "$GUM_BIN" ]; then
  echo "SKIP: gum not installed"
  exit 0
fi
if ! command -v script >/dev/null 2>&1; then
  echo "SKIP: script(1) not available for a pseudo-terminal"
  exit 0
fi

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t uca-gum-test)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/home"
GUM_LOG="$WORK/gum.log"

# Shim: record every gum invocation, then defer to the real binary.
cat > "$WORK/bin/gum" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GUM_LOG"
exec "$GUM_BIN" "\$@"
EOF
chmod +x "$WORK/bin/gum"

fail() { echo "FAIL: $*" >&2; exit 1; }

# run_pty OUTFILE CMD [ARGS...] — run CMD with stdout on a pty; returns its exit code.
run_pty() {
  local out="$1"; shift
  local cmd
  cmd="$(printf '%q ' "$@")"
  local rc=0
  if script --version >/dev/null 2>&1; then
    # util-linux
    script -qec "$cmd" /dev/null >"$out" 2>&1 || rc=$?
  else
    # BSD / macOS
    script -q /dev/null bash -c "$cmd" >"$out" 2>&1 || rc=$?
  fi
  return "$rc"
}

# Environment for every run: isolated HOME/XDG so nothing real is touched,
# the shim first on PATH so gum is "installed".
run_case() {  # run_case LABEL SCRIPT [ARGS...]
  local label="$1"; shift
  local out="$WORK/$label.out"
  : > "$GUM_LOG"
  local rc=0
  (
    export HOME="$WORK/home" XDG_DATA_HOME="$WORK/home/.local/share" XDG_CONFIG_HOME="$WORK/home/.config"
    export PATH="$WORK/bin:$PATH" TERM="${TERM:-xterm-256color}"
    run_pty "$out" "$@"
  ) || rc=$?
  echo "== $label: exit=$rc, gum calls=$(grep -c '' "$GUM_LOG" 2>/dev/null || echo 0)"
  [ "$rc" -eq 0 ] || { cat "$out"; fail "$label exited $rc"; }
  if grep -q "unknown flag" "$out"; then cat "$out"; fail "$label: gum rejected message text as a flag"; fi
  if grep -q "executable file not found" "$out"; then cat "$out"; fail "$label: a shell function was handed to gum spin"; fi
  grep -q '^style' "$GUM_LOG" || fail "$label: gum was never used (tty detection or probe failed)"
  # The message helpers (info/ok/...) must be styled by gum, not the ANSI
  # fallback; their text ("-> ...") travels on stdin, so only flags are logged.
  grep -q '^style --foreground 39$' "$GUM_LOG" || fail "$label: info() did not go through gum"
  # gum spin must never be asked to run one of our shell functions.
  if grep -E '^spin .*(install_uca_script|configure_background_service)' "$GUM_LOG"; then
    fail "$label: shell function passed to gum spin"
  fi
}
cd "$ROOT"
run_case install-dry-run   ./install-uca.sh --dry-run
run_case uninstall-dry-run ./uninstall-uca.sh --dry-run --yes

echo "OK: gum-enabled installer and uninstaller complete (gum: $("$GUM_BIN" --version 2>/dev/null | head -1))"
