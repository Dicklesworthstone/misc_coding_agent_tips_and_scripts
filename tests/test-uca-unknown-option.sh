#!/usr/bin/env bash
#
# uca must reject words it does not recognize instead of treating them as "update everything".
# Before the fix, `uca --version` (a common read-only probe) started a full update of every harness.
#
# Every case passes --dry-run first, so if the rejection ever regresses this test performs a dry run
# (no installs) and fails, rather than updating real agents.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
uca="$ROOT/uca"
fail=0

check() {
  local label=$1; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" -ne 2 ]; then echo "FAIL $label: exit $rc, want 2"; fail=1; return; fi
  case "$out" in
    *"no update was run"*) echo "ok   $label" ;;
    *) echo "FAIL $label: missing refusal message: $out"; fail=1 ;;
  esac
}

check "--version is refused"        bash "$uca" --dry-run --version
check "unknown long option refused" bash "$uca" --dry-run --definitely-not-a-flag
check "unknown harness refused"     bash "$uca" --dry-run nosuchharness
check "refused before known flags"  bash "$uca" --bogus --dry-run --quiet

# The refusal must name the offending word.
out=$(bash "$uca" --dry-run --version 2>&1)
case "$out" in *"'--version'"*) echo "ok   message names the word" ;; *) echo "FAIL message does not name the word: $out"; fail=1 ;; esac

# Known flags and the help path still work (help exits 0 and runs nothing).
if bash "$uca" --help >/dev/null 2>&1; then echo "ok   --help still exits 0"; else echo "FAIL --help"; fail=1; fi

exit "$fail"
