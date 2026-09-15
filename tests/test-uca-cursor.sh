#!/usr/bin/env bash
# Regression test for Cursor Agent support: `uca cursor` must find the CLI the
# way Cursor's installer lays it out, drive `cursor-agent update`, and order its
# <date>-<hash> versions by date only.
#
# Cursor's installer (curl https://cursor.com/install -fsS | bash) links both
# ~/.local/bin/cursor-agent and ~/.local/bin/agent at
# ~/.local/share/cursor-agent/versions/<ver>/cursor-agent and reports versions
# such as 2026.09.10-fd3934a. Two builds on the same day differ only in hash,
# which is not a pre-release tag, so a same-day rebuild must never be reported
# as DOWNGRADED. A bare `agent` that is not Cursor's must be ignored.
#
# The test stands up a fake install under an isolated HOME and drives the real
# `uca cursor` end to end. No network, nothing real is touched.
#
# Usage: bash tests/test-uca-cursor.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t uca-cursor-test)"
WORK="$(cd "$WORK" && pwd -P)"   # physical path: uca compares realpath()s
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

HOME_DIR="$WORK/home"
BIN_DIR="$HOME_DIR/.local/bin"
TREE="$HOME_DIR/.local/share/cursor-agent/versions/2026.09.10-fd3934a"
STATE="$HOME_DIR/.local/share/uca/state.json"
mkdir -p "$BIN_DIR" "$TREE"

# The "installed" cursor-agent: prints the version file; `update` installs
# whatever $WORK/next_version says and logs that it ran.
cat > "$TREE/cursor-agent" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  --version|-v) cat "$WORK/cursor_version" ;;
  update|upgrade) echo "\$0 \$*" >> "$WORK/update.log"; cat "$WORK/next_version" > "$WORK/cursor_version" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$TREE/cursor-agent"
ln -s "$TREE/cursor-agent" "$BIN_DIR/cursor-agent"
ln -s "$TREE/cursor-agent" "$BIN_DIR/agent"

run_uca() {  # run_uca LABEL INSTALLED NEXT
  local label="$1" installed="$2" next="$3"
  echo "$installed" > "$WORK/cursor_version"
  echo "$next"      > "$WORK/next_version"
  rm -f "$WORK/update.log"
  RC=0
  OUT="$WORK/$label.out"
  (
    export HOME="$HOME_DIR" XDG_DATA_HOME="$HOME_DIR/.local/share" XDG_CONFIG_HOME="$HOME_DIR/.config"
    # Fixed PATH: the developer's own ~/.local/bin must not leak a real
    # cursor-agent into the isolated HOME.
    export PATH="$BIN_DIR:/usr/local/bin:/usr/bin:/bin" NO_COLOR=1
    "$ROOT/uca" cursor --no-gum --ignore-disk-space
  ) >"$OUT" 2>&1 || RC=$?
  echo "== $label: exit=$RC, cursor now $(cat "$WORK/cursor_version"), updates=$(grep -c '' "$WORK/update.log" 2>/dev/null || echo 0)"
}

# 1. Newer date: plain upgrade, reported as UPDATED and persisted to state.
run_uca upgrade 2026.09.10-fd3934a 2026.09.17-abc1234
[ "$RC" -eq 0 ] || { cat "$OUT"; fail "upgrade exited $RC"; }
[ -f "$WORK/update.log" ] || { cat "$OUT"; fail "upgrade: cursor-agent update was not invoked"; }
grep -q 'UPDATED' "$OUT" || { cat "$OUT"; fail "upgrade: not reported as UPDATED"; }
grep -q '2026.09.10-fd3934a.*2026.09.17-abc1234' "$OUT" || { cat "$OUT"; fail "upgrade: version transition missing"; }
grep -q '"cursor": {' "$STATE" || fail "upgrade: state.json has no cursor block"
grep -A3 '"cursor": {' "$STATE" | grep -q '"current_version": "2026.09.17-abc1234"' || { cat "$STATE"; fail "upgrade: state.json did not record the new version"; }

# 2. Same-day rebuild with a lexically smaller hash: an update, not a downgrade.
run_uca same-day 2026.09.10-fd3934a 2026.09.10-0000000
[ "$RC" -eq 0 ] || { cat "$OUT"; fail "same-day exited $RC"; }
grep -q 'UPDATED' "$OUT" || { cat "$OUT"; fail "same-day: rebuild not reported as UPDATED"; }
if grep -q 'DOWNGRADED' "$OUT"; then cat "$OUT"; fail "same-day: rebuild reported as DOWNGRADED"; fi

# 3. Older date: DOWNGRADED, run fails, state records the error.
run_uca downgrade 2026.09.17-abc1234 2026.09.10-fd3934a
[ "$RC" -ne 0 ] || { cat "$OUT"; fail "downgrade: run succeeded"; }
grep -q 'DOWNGRADED' "$OUT" || { cat "$OUT"; fail "downgrade: DOWNGRADED not reported"; }
if grep -q 'UPDATED' "$OUT"; then cat "$OUT"; fail "downgrade: reported as UPDATED"; fi
grep -A5 '"cursor": {' "$STATE" | grep -q '"last_status": "error"' || { cat "$STATE"; fail "downgrade: state.json does not record the error"; }

# 4. Already current: up to date, and the updater still ran.
run_uca current 2026.09.17-abc1234 2026.09.17-abc1234
[ "$RC" -eq 0 ] || { cat "$OUT"; fail "current exited $RC"; }
grep -q 'Up to date' "$OUT" || { cat "$OUT"; fail "current: not reported as up to date"; }
[ -f "$WORK/update.log" ] || fail "current: cursor-agent update should still run"

# 5. Only the `agent` name is linked (cursor-agent symlink absent): still found,
#    because it resolves into the cursor-agent tree.
rm "$BIN_DIR/cursor-agent"
run_uca agent-only 2026.09.17-abc1234 2026.09.20-1234567
[ "$RC" -eq 0 ] || { cat "$OUT"; fail "agent-only exited $RC"; }
grep -q 'UPDATED' "$OUT" || { cat "$OUT"; fail "agent-only: cursor-agent tree behind 'agent' was not used"; }
grep -q "$BIN_DIR/agent update" "$WORK/update.log" || { cat "$WORK/update.log"; fail "agent-only: update did not run through 'agent'"; }

# 6. An unrelated `agent` binary outside the cursor-agent tree: not Cursor,
#    so the harness reads as not installed and nothing is executed.
rm "$BIN_DIR/agent"
cat > "$BIN_DIR/agent" <<EOF
#!/usr/bin/env bash
echo "unrelated agent \$*" >> "$WORK/update.log"
echo "9.9.9"
EOF
chmod +x "$BIN_DIR/agent"
run_uca foreign-agent 2026.09.20-1234567 2026.09.20-1234567
[ "$RC" -eq 0 ] || { cat "$OUT"; fail "foreign-agent exited $RC"; }
grep -q 'Not installed' "$OUT" || { cat "$OUT"; fail "foreign-agent: unrelated 'agent' was treated as Cursor"; }
[ ! -f "$WORK/update.log" ] || { cat "$WORK/update.log"; fail "foreign-agent: unrelated 'agent' was executed"; }

# 7. harness_version_lt ordering, exercised in-process (uca's functions, main stripped).
hvlt() {
  ( export HOME="$HOME_DIR"; set +u
    # shellcheck disable=SC1090
    source <(grep -v '^main "\$@"$' "$ROOT/uca")
    harness_version_lt "$1" "$2" "$3" )
}
expect_lt()  { hvlt "$1" "$2" "$3" || fail "harness_version_lt $1: expected $2 < $3"; }
expect_nlt() { if hvlt "$1" "$2" "$3"; then fail "harness_version_lt $1: expected NOT $2 < $3"; fi; }
expect_lt  cursor 2026.09.10-fd3934a 2026.09.17-abc1234
expect_lt  cursor 2026.09.30-fd3934a 2026.10.01-0000000
expect_nlt cursor 2026.09.17-abc1234 2026.09.10-fd3934a
expect_nlt cursor 2026.09.10-fd3934a 2026.09.10-0000000
expect_nlt cursor 2026.09.10-0000000 2026.09.10-fd3934a
expect_lt  codex  2.0.0-rc.1 2.0.0          # other harnesses keep semver pre-release order
expect_nlt codex  2.0.0 2.0.0-rc.1
echo "== harness_version_lt: 7 orderings OK"

echo "OK: cursor-agent is resolved safely, updated through its own updater, and date-ordered"
