#!/usr/bin/env bash
# Exercise the real model-download functions without GPU setup or large downloads.
# Callbacks and state below are consumed by the dynamically loaded functions.
# shellcheck disable=SC2034,SC2329
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${1:-$ROOT/install-qwen38-uncensored.sh}"
FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/qwen-download-test.XXXXXX")"
fail=0

# Load only the download functions, excluding installer setup and main.
# shellcheck disable=SC1090
source <(sed -n '/^model_files_present() {/,/^# .*Tuned Triton FP8/p' "$INSTALLER")

info() { :; }
ok() { :; }
err() { printf '%s\n' "$*" >&2; }

write_model_files() {
  mkdir -p "$MODEL_DIR"
  local name
  for name in config.json model.safetensors.index.json tokenizer.json model-00001.safetensors; do
    printf '{}\n' > "$MODEL_DIR/$name"
  done
}

# Existing global aliases must never supply the isolated ModelScope download.
modelscope() { echo 'Unexpected global modelscope invocation' >&2; return 73; }
ms() { echo 'Unexpected global ms invocation' >&2; return 74; }

uv() {
  printf '%s\n' "$@" >> "$UV_LOG"
  if [ "${1:-}" != tool ] || [ "${2:-}" != run ]; then
    echo 'Expected tool execution, not global tool installation' >&2
    return 2
  fi
  shift 2
  local isolated=0 package=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --isolated) isolated=1; shift ;;
      --from) package="${2:-}"; shift 2 ;;
      *) break ;;
    esac
  done
  [ "$isolated" -eq 1 ] && [ "$package" = modelscope-hub ] || return 2
  [ "${1:-}" = modelscope ] && [ "${2:-}" = download ] || return 2
  shift 2
  # Match the current CLI grammar: positional repo ID, then --local-dir.
  [ $# -eq 3 ] && [ "$1" = "$MODEL_ID" ] && \
    [ "$2" = --local-dir ] && [ "$3" = "$MODEL_DIR" ] || return 2
  case "$DOWNLOAD_MODE" in
    complete) write_model_files ;;
    incomplete) : ;;
    failed) return 17 ;;
  esac
}

check_download() {
  local label="$1" mode="$2" cached="$3" dry_run="$4" expected="$5"
  local global_cli="${6:-present}"
  local case_dir="$FIXTURES/$label" rc
  mkdir -p "$case_dir"
  (
    set -e
    MODEL_ID="fixture/qwen"
    MODEL_DIR="$case_dir/model with spaces"
    SOURCE=modelscope
    DRY_RUN="$dry_run"
    DOWNLOAD_MODE="$mode"
    UV_LOG="$case_dir/uv.log"
    if [ "$global_cli" = absent ]; then unset -f modelscope ms; fi
    if [ "$cached" -eq 1 ]; then write_model_files; fi
    download_model
  ) > "$case_dir/output.log" 2>&1
  rc=$?
  if [ "$rc" -ne "$expected" ]; then
    echo "FAIL $label: exit $rc, expected $expected"
    cat "$case_dir/output.log"
    fail=1
    return
  fi
  if [ "$cached" -eq 1 ] || [ "$dry_run" -eq 1 ]; then
    if [ -e "$case_dir/uv.log" ]; then
      echo "FAIL $label: unexpectedly ran uv"
      fail=1
      return
    fi
  elif [ ! -s "$case_dir/uv.log" ]; then
    echo "FAIL $label: did not exercise the download command"
    fail=1
    return
  fi
  if [ "$mode" = incomplete ] && ! grep -q 'expected files are missing' "$case_dir/output.log"; then
    echo "FAIL $label: missing incomplete-download diagnostic"
    fail=1
    return
  fi
  if [ "$mode" = failed ] && ! grep -q 'same --data-root' "$case_dir/output.log"; then
    echo "FAIL $label: missing recovery instructions"
    fail=1
    return
  fi
  echo "ok   $label"
}

check_download 'isolated download with quoted paths' complete 0 0 0
check_download 'missing global CLI uses isolated package' complete 0 0 0 absent
check_download 'cached model skips download' complete 1 0 0
check_download 'dry run skips download' complete 0 1 0
check_download 'download failure is propagated' failed 0 0 17
check_download 'incomplete download is rejected' incomplete 0 0 1

if [ "$fail" -ne 0 ]; then echo "Fixtures: $FIXTURES"; fi
exit "$fail"
