#!/usr/bin/env bash
#
# install-qwen38-uncensored.sh — Qwen3.8-27B-Uncensored-FP8 on dual RTX 4090s,
# served by vLLM, wired into omp (Oh My Pi) as a provider.
#
# One-liner install (with cache buster):
#   curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-qwen38-uncensored.sh?$(date +%s)" | bash
#
# Or without cache buster:
#   curl -fsSL https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-qwen38-uncensored.sh | bash
#
# What it does (every step is idempotent — safe to re-run; completed steps are
# detected, skipped, and reported as already done):
#   1. Preflight: Linux, NVIDIA GPUs + total VRAM, disk space, RAM, network
#   2. Installs uv (if missing), creates a Python 3.12 venv, installs latest vLLM
#   3. Downloads the model (~31 GB) from Hugging Face (account + gated access +
#      token) or ModelScope (no login) — your choice; ModelScope is the default
#      when HF auth is absent
#   4. Installs tuned Triton block-FP8 configs for RTX 4090 (sm_89), adapted
#      from shipped L40S tunings when available; backend use varies by version
#   5. Installs two commands in ~/.local/bin:
#        qwenserve — start the OpenAI-compatible server (dual-4090-tuned:
#                    TP=2, FP8 KV cache, MTP speculative decoding, 160K context,
#                    qwen3 reasoning + qwen3_coder tool-call parsers)
#        qwenstop  — stop it: graceful SIGTERM, waits for VRAM to drain,
#                    SIGKILLs only surviving owned processes, then reports
#                    each GPU's memory/power
#   6. Installs omp (via bun) if missing, and registers the vLLM server as a
#      keyless provider in ~/.omp/agent/models.yml
#   7. Optional: --with-service installs a systemd user unit so the server
#      starts on login; --start launches and smoke-tests end-to-end
#
# Options:
#   --modelscope       Force ModelScope download (no Hugging Face login needed)
#   --hf               Force Hugging Face download (requires prior `hf auth login`)
#   --with-service     Install + enable a systemd user service for qwenserve
#   --start            Launch the server after install and run an e2e smoke test
#                      (first launch compiles kernels: allow up to ~40 min)
#   --verify           Only run post-install diagnostics, change nothing
#   --uninstall        Remove qwenserve/qwenstop, the service, and the omp entry
#                      (keeps the venv and model weights; see --purge)
#   --purge            With --uninstall: also delete the venv and model weights
#   --dry-run          Print what would be done, change nothing
#   --force            Reinstall/upgrade even when components look current
#   --quiet            Suppress non-error output
#   --no-gum           Disable gum formatting even if available
#   --port N           Server port (default: 8000)
#   --data-root DIR    Base dir for venv + models (default: ~/.local/share/qwenserve)
#   --help             Show this help
#
# Env overrides honored by the installed qwenserve script:
#   QWEN_PORT QWEN_TP QWEN_MAX_LEN QWEN_GPU_UTIL QWEN_MAX_SEQS QWEN_SPEC_TOKENS
#
# See: QWEN38_UNCENSORED_ON_DUAL_4090_WITH_VLLM_AND_OMP.md

set -euo pipefail
shopt -s lastpipe 2>/dev/null || true
umask 022

# ── Configuration ────────────────────────────────────────────────────────────

MODEL_ID="orcarouter/Qwen3.8-27B-Uncensored-FP8"
MODEL_NAME="Qwen3.8-27B-Uncensored-FP8"
SERVED_NAME="Qwen3.8-27B-Uncensored"
OMP_PACKAGE="@oh-my-pi/pi-coding-agent"
MIN_MODEL_DISK_GB=40        # 31 GB weights + headroom
MIN_TOTAL_VRAM_GB=36        # weights ~31 GB FP8 + minimum KV cache
RECOMMENDED_VRAM_GB=44      # comfortable 2x24 GB
MIN_DRIVER_MAJOR=570        # CUDA 12.8+ wheels; 580+ recommended (CUDA 13)

PORT=8000
PORT_EXPLICIT=0
DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/qwenserve"
BIN_DIR="$HOME/.local/bin"
WITH_SERVICE=0
DO_START=0
DO_VERIFY=0
UNINSTALL=0
PURGE=0
DRY_RUN=0
FORCE=0
QUIET=0
NO_GUM=0
SOURCE=""                 # "" | modelscope | hf

# ── Argument parsing ─────────────────────────────────────────────────────────

usage() {
  if [ -r "$0" ] && [ "$(basename "$0")" != "bash" ] && [ "$(basename "$0")" != "sh" ]; then
    sed -n '2,54p' "$0" | sed 's/^# \{0,1\}//'
  else
    # curl-pipe invocation: $0 is the shell, not this script
    echo "install-qwen38-uncensored.sh — Qwen3.8-27B-Uncensored-FP8 on dual RTX 4090s (vLLM + omp)"
    echo ""
    echo "Options: --modelscope | --hf | --with-service | --start | --verify |"
    echo "         --uninstall [--purge] | --dry-run | --force | --quiet | --no-gum |"
    echo "         --port N | --data-root DIR | --help"
    echo ""
    echo "Full docs: https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/blob/main/QWEN38_UNCENSORED_ON_DUAL_4090_WITH_VLLM_AND_OMP.md"
  fi
  return 0
}

parse_args() {
while [ $# -gt 0 ]; do
  case "$1" in
    --modelscope)   [ "$SOURCE" != hf ] || { echo '--hf and --modelscope are mutually exclusive' >&2; return 2; }; SOURCE="modelscope" ;;
    --hf)           [ "$SOURCE" != modelscope ] || { echo '--hf and --modelscope are mutually exclusive' >&2; return 2; }; SOURCE="hf" ;;
    --with-service) WITH_SERVICE=1 ;;
    --start)        DO_START=1 ;;
    --verify)       DO_VERIFY=1 ;;
    --uninstall)    UNINSTALL=1 ;;
    --purge)        PURGE=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    --force)        FORCE=1 ;;
    --quiet)        QUIET=1 ;;
    --no-gum)       NO_GUM=1 ;;
    --port)         [ $# -ge 2 ] || { echo '--port needs a value' >&2; return 2; }
                    PORT="$2"; PORT_EXPLICIT=1; shift ;;
    --data-root)    [ $# -ge 2 ] || { echo '--data-root needs a value' >&2; return 2; }
                    DATA_ROOT="$2"; shift ;;
    --help|-h)      usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; return 2 ;;
  esac
  shift
done
  if ! [[ "$PORT" =~ ^[0-9]{1,5}$ ]] || [ "$((10#$PORT))" -lt 1 ] || [ "$((10#$PORT))" -gt 65535 ]; then
    echo '--port must be an integer from 1 to 65535' >&2; return 2
  fi
  PORT=$((10#$PORT))
  [[ "$PROMPT_TIMEOUT" =~ ^[1-9][0-9]{0,4}$ ]] || { echo 'QWEN_INSTALL_PROMPT_TIMEOUT must be a positive integer below 100000' >&2; return 2; }
  [ -n "$DATA_ROOT" ] || { echo '--data-root must not be empty' >&2; return 2; }
  if [ "$PURGE" -eq 1 ] && [ "$UNINSTALL" -ne 1 ]; then
    echo '--purge requires --uninstall' >&2; return 2
  fi
  if [ "$DO_VERIFY" -eq 1 ] && { [ "$UNINSTALL" -eq 1 ] || [ "$DO_START" -eq 1 ]; }; then
    echo '--verify cannot be combined with --uninstall or --start' >&2; return 2
  fi
  if [ "$UNINSTALL" -eq 1 ] && [ "$DO_START" -eq 1 ]; then
    echo '--uninstall cannot be combined with --start' >&2; return 2
  fi
}

configure_paths() {
DATA_ROOT=$(python3 -c 'import os,sys; print(os.path.realpath(os.path.expanduser(sys.argv[1])))' "$DATA_ROOT") || return 1
if [ "$PORT_EXPLICIT" -eq 0 ] && [ -f "$DATA_ROOT/.qwenserve-install.json" ]; then
  local saved_settings
  saved_settings=$(python3 - "$DATA_ROOT/.qwenserve-install.json" "$DATA_ROOT" "$MODEL_ID" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    value = json.loads(stream.read(65537))
if value.get('schema') != 1 or value.get('data_root') != sys.argv[2] or value.get('model_id') != sys.argv[3]:
    raise SystemExit('Invalid Qwen installation settings; pass --port explicitly to replace them')
port = value.get('port')
tp = value.get('tp_default')
if type(port) is not int or not 1 <= port <= 65535 or type(tp) is not int or tp not in (1, 2):
    raise SystemExit('Invalid saved Qwen port; pass --port explicitly to replace it')
print(port, tp)
PY
  ) || return 1
  read -r PORT TP_DEFAULT <<< "$saved_settings"
fi
VENV_DIR="$DATA_ROOT/venv"
MODEL_DIR="$DATA_ROOT/models/$MODEL_NAME"
VLLM_BIN="$VENV_DIR/bin/vllm"
VENV_PY="$VENV_DIR/bin/python"
OMP_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"
MODELS_YML="$OMP_AGENT_DIR/models.yml"
SERVICE_NAME="qwenserve"
UNIT_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
}

record_installation() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  python3 - "$DATA_ROOT" "$MODEL_ID" "$PORT" "$TP_DEFAULT" <<'PY'
import json, os, sys, tempfile
from pathlib import Path
root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
with tempfile.NamedTemporaryFile(mode='w', prefix='.qwen-settings.', dir=root, delete=False) as stream:
    json.dump({'schema':1, 'data_root':str(root), 'model_id':sys.argv[2], 'port':int(sys.argv[3]), 'tp_default':int(sys.argv[4])}, stream, sort_keys=True)
    stream.write('\n')
    staged = stream.name
os.replace(staged, root / '.qwenserve-install.json')
PY
}

# ── Output stack (gum + ANSI fallback) ───────────────────────────────────────

HAS_GUM=0
if command -v gum >/dev/null 2>&1 && [ -t 1 ]; then HAS_GUM=1; fi

log()  { [ "$QUIET" -eq 1 ] && return 0; echo -e "$@"; }
info() { [ "$QUIET" -eq 1 ] && return 0
         if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then gum style --foreground 39 "→ $*"
         else echo -e "\033[0;34m→\033[0m $*"; fi; }
ok()   { [ "$QUIET" -eq 1 ] && return 0
         if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then gum style --foreground 42 "✓ $*"
         else echo -e "\033[0;32m✓\033[0m $*"; fi; }
warn() { [ "$QUIET" -eq 1 ] && return 0
         if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then gum style --foreground 214 "⚠ $*"
         else echo -e "\033[1;33m⚠\033[0m $*"; fi; }
err()  { if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ]; then gum style --foreground 196 "✗ $*" >&2
         else echo -e "\033[0;31m✗\033[0m $*" >&2; fi; }

# Spinner wrapper for long operations; dry-run aware (prints instead of runs)
run_with_spinner() {
  local title="$1"; shift
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] $title"; return 0; fi
  if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ] && [ "$QUIET" -eq 0 ]; then
    gum spin --spinner dot --title "$title" -- "$@"
  else
    info "$title"
    "$@"
  fi
}

draw_box() {
  [ "$QUIET" -eq 1 ] && return 0
  local color="$1"; shift
  local lines=("$@")
  local max_width=0 esc strip
  esc=$(printf '\033')
  for line in ${lines[@]+"${lines[@]}"}; do
    strip=$(printf '%b' "$line" | LC_ALL=C sed "s/${esc}\\[[0-9;]*m//g")
    [ "${#strip}" -gt "$max_width" ] && max_width=${#strip}
  done
  local border="" i
  for ((i=0; i<max_width+4; i++)); do border+="═"; done
  printf "\033[%sm╔%s╗\033[0m\n" "$color" "$border"
  for line in ${lines[@]+"${lines[@]}"}; do
    strip=$(printf '%b' "$line" | LC_ALL=C sed "s/${esc}\\[[0-9;]*m//g")
    local pad=""
    for ((i=0; i<max_width-${#strip}; i++)); do pad+=" "; done
    printf "\033[%sm║\033[0m  %b%s  \033[%sm║\033[0m\n" "$color" "$line" "$pad" "$color"
  done
  printf "\033[%sm╚%s╝\033[0m\n" "$color" "$border"
}

# Operator TTY: under `curl | bash`, stdin is the pipe — prompt via /dev/tty.
TTY_DEV=""
if ( : </dev/tty >/dev/tty ) 2>/dev/null; then TTY_DEV="/dev/tty"; fi
have_tty() { [ -n "$TTY_DEV" ]; }
PROMPT_TIMEOUT="${QWEN_INSTALL_PROMPT_TIMEOUT:-120}"

ask_yn() { # ask_yn "<prompt>" "<y|n default>"; default on timeout/EOF/no-tty
  local prompt="$1" default="${2:-n}" reply="" st=0
  if have_tty; then
    printf '%s ' "$prompt" >"$TTY_DEV" 2>/dev/null || true
    IFS= read -r -t "$PROMPT_TIMEOUT" reply <"$TTY_DEV" 2>/dev/null || st=$?
    if [ "$st" -ne 0 ]; then
      reply=""
      printf '\n' >"$TTY_DEV" 2>/dev/null || true
      warn "No reply (timeout/EOF); taking default ($default)"
    fi
  fi
  [ -n "$reply" ] || reply="$default"
  if [ "$default" = "y" ]; then
    case "$reply" in n|N|no|No|NO) return 1 ;; *) return 0 ;; esac
  else
    case "$reply" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac
  fi
}

# run: execute, or echo under --dry-run
run() {
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] $*"; else "$@"; fi
}

# ── Proxy support ────────────────────────────────────────────────────────────

PROXY_ARGS=()
setup_proxy() {
  if [ -n "${HTTPS_PROXY:-}" ]; then
    PROXY_ARGS=(--proxy "$HTTPS_PROXY"); info "Using HTTPS proxy"
  elif [ -n "${HTTP_PROXY:-}" ]; then
    PROXY_ARGS=(--proxy "$HTTP_PROXY"); info "Using HTTP proxy"
  fi
}

# ── Temp dir + locking ───────────────────────────────────────────────────────

LOCK_DIR=""
LOCK_OWNER=""
cleanup() {
  # A failed contender must never remove another installer's lock.
  if [ -n "$LOCK_DIR" ] && [ -n "$LOCK_OWNER" ] && \
     [ "$(cat "$LOCK_DIR/pid" 2>/dev/null)" = "$LOCK_OWNER" ]; then
    rm -f "$LOCK_DIR/pid" 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}

acquire_lock() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  mkdir -p "$BIN_DIR"
  local candidate="$BIN_DIR/.qwenserve-install.lock" old_pid=""
  if ! mkdir "$candidate" 2>/dev/null; then
    old_pid=$(cat "$candidate/pid" 2>/dev/null || true)
    err "Install lock exists: $candidate (pid ${old_pid:-unknown})."
    err "If that process is gone, inspect and remove the stale lock before retrying."
    return 1
  fi
  LOCK_DIR="$candidate"
  LOCK_OWNER="${BASHPID:-$$}"
  printf '%s\n' "$LOCK_OWNER" > "$LOCK_DIR/pid"
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

# ── Preflight ────────────────────────────────────────────────────────────────

GPU_COUNT=0
TOTAL_VRAM_GB=0
GPU_NAMES=""
DRIVER_VERSION=""
TP_DEFAULT=2

check_platform() {
  if [ "$(uname -s)" != "Linux" ]; then
    err "This installer targets Linux (vLLM + NVIDIA). Detected: $(uname -s)"
    exit 1
  fi
  if [ "$(uname -m)" != "x86_64" ]; then
    err "This installer targets x86_64. Detected: $(uname -m)"
    exit 1
  fi
  if grep -qi microsoft /proc/version 2>/dev/null; then
    warn "WSL detected. vLLM works under WSL2, but dual-GPU TP and systemd user"
    warn "services may need extra setup. Continuing."
  fi
}

check_gpus() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    err "nvidia-smi not found — this setup needs NVIDIA GPUs with the driver installed."
    err "Install the driver first (e.g. sudo apt install nvidia-driver-595-open)."
    exit 1
  fi
  GPU_NAMES=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | sort | uniq -c | sed 's/^ *//' | paste -sd',' || true)
  GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l | tr -d ' ')
  local mib_total
  mib_total=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | awk '{s+=$1} END {print int(s)}')
  TOTAL_VRAM_GB=$((mib_total / 1024))
  DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)

  info "GPUs: $GPU_COUNT ($GPU_NAMES), total VRAM ${TOTAL_VRAM_GB} GB, driver $DRIVER_VERSION"

  TP_DEFAULT=2
  if [ "$GPU_COUNT" -lt 2 ]; then TP_DEFAULT=1; fi

  local drv_major="${DRIVER_VERSION%%.*}"
  if [ -n "$drv_major" ] && [ "$drv_major" -lt "$MIN_DRIVER_MAJOR" ] 2>/dev/null; then
    warn "Driver $DRIVER_VERSION is older than $MIN_DRIVER_MAJOR.x — current vLLM wheels"
    warn "bundle CUDA 12.8/13.0 runtimes and may refuse to load. Upgrade first, e.g.:"
    warn "  sudo apt install nvidia-driver-595-open   # then reload modules or reboot"
  fi

  if [ "$TOTAL_VRAM_GB" -lt "$MIN_TOTAL_VRAM_GB" ]; then
    warn "Only ${TOTAL_VRAM_GB} GB total VRAM; this FP8 checkpoint needs ~31 GB for"
    warn "weights plus KV cache (>= ${MIN_TOTAL_VRAM_GB} GB total required, ${RECOMMENDED_VRAM_GB}+ GB recommended)."
    if [ "$FORCE" -eq 0 ] && ! ask_yn "Continue anyway? [y/N]" "n"; then
      err "Aborting: insufficient VRAM"
      exit 1
    fi
  fi
}

check_disk_space() {
  local model_parent="$DATA_ROOT/models"
  # df must inspect an existing ancestor, including on a fresh dry run.
  while [ ! -d "$model_parent" ] && [ "$model_parent" != / ]; do model_parent=$(dirname "$model_parent"); done
  local avail
  avail=$(df -Pk "$model_parent" 2>/dev/null | awk 'NR==2 {print int($4/1048576)}') || {
    err "Cannot check free disk space for $DATA_ROOT"; return 1;
  }
  if [ -n "$avail" ] && [ "$avail" -lt "$MIN_MODEL_DISK_GB" ] && ! model_files_present; then
    err "Only ${avail} GB free at $DATA_ROOT (need >= ${MIN_MODEL_DISK_GB} GB for weights plus ~6 GB venv)"
    err "Point --data-root at a bigger disk."
    exit 1
  fi
  ok "Disk space OK (${avail:-?} GB free at $DATA_ROOT)"
}

check_ram() {
  local avail_gb
  avail_gb=$(awk '/MemAvailable/ {print int($2/1048576)}' /proc/meminfo 2>/dev/null || echo 0)
  if [ "$avail_gb" -lt 16 ]; then
    warn "Only ${avail_gb} GB RAM available — weight loading needs several GB of page cache."
  fi
}

check_network() {
  local target="https://huggingface.co"
  [ "$SOURCE" = "modelscope" ] && target="https://modelscope.cn"
  if ! curl -fsSL --connect-timeout 5 --max-time 8 -o /dev/null "${PROXY_ARGS[@]}" "$target" 2>/dev/null; then
    warn "Cannot reach $target — downloads may fail (check proxy settings)"
  fi
}

preflight() {
  info "Running preflight checks"
  check_platform
  check_gpus
  check_disk_space
  check_ram
  check_network
}

# ── uv + venv + vLLM ─────────────────────────────────────────────────────────

install_bootstrap_binary() {
  # Download a release asset completely and verify GitHub's published SHA256.
  # Extract only the named executable; never run a fetched installer script.
  timeout 300 python3 - "$1" "$BIN_DIR" <<'PY'
import hashlib, io, json, os, platform, re, shutil, sys, tarfile, tempfile, urllib.request, zipfile
from pathlib import Path

tool, destination = sys.argv[1:]
machine = platform.machine()
if machine not in ('x86_64', 'aarch64') or tool not in ('uv', 'bun'):
    raise SystemExit('Unsupported bootstrap tool or architecture')
repo = 'astral-sh/uv' if tool == 'uv' else 'oven-sh/bun'
asset_name = (f'uv-{machine}-unknown-linux-gnu.tar.gz' if tool == 'uv' else
              'bun-linux-x64-baseline.zip' if machine == 'x86_64' else 'bun-linux-aarch64.zip')

def fetch(url, limit):
    request = urllib.request.Request(url, headers={'User-Agent':'qwenserve-installer', 'Accept':'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError('Bootstrap response exceeds its size limit')
    return data

try:
    release = json.loads(fetch(f'https://api.github.com/repos/{repo}/releases/latest', 4 * 1024 * 1024))
    assets = [asset for asset in release['assets'] if asset.get('name') == asset_name]
    if len(assets) != 1:
        raise ValueError(f'Expected one release asset named {asset_name}')
    asset = assets[0]
    digest = asset.get('digest') or ''
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', digest):
        raise ValueError('Release asset has no published SHA256; refusing an unverified download')
    url = asset['browser_download_url']
    if not url.startswith(f'https://github.com/{repo}/releases/download/'):
        raise ValueError('Unexpected release asset URL')
    data = fetch(url, 256 * 1024 * 1024)
    if len(data) != asset['size'] or 'sha256:' + hashlib.sha256(data).hexdigest() != digest:
        raise ValueError('Release asset size or SHA256 mismatch')
    if tool == 'uv':
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
            members = [m for m in archive.getmembers() if m.name == asset_name.removesuffix('.tar.gz') + '/uv']
            if len(members) != 1 or not members[0].isfile() or members[0].size > 256 * 1024 * 1024:
                raise ValueError('Invalid uv executable in release archive')
            with archive.extractfile(members[0]) as stream:
                binary = stream.read()
    else:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            members = [m for m in archive.infolist() if m.filename == asset_name.removesuffix('.zip') + '/bun']
            if len(members) != 1 or members[0].file_size > 256 * 1024 * 1024:
                raise ValueError('Invalid Bun executable in release archive')
            binary = archive.read(members[0])
    if not binary:
        raise ValueError('Empty bootstrap executable')
    root = Path(destination); root.mkdir(parents=True, exist_ok=True)
    target = root / tool
    if target.exists() or target.is_symlink():
        with tempfile.NamedTemporaryFile(prefix=tool+'.bak.', dir=root, delete=False) as backup:
            backup_path = backup.name
        shutil.copy2(target, backup_path, follow_symlinks=False)
    with tempfile.NamedTemporaryFile(prefix='.'+tool+'.', dir=root, delete=False) as stream:
        stream.write(binary); staged = stream.name
    os.chmod(staged, 0o755)
    os.replace(staged, target)
    print(f'{tool}: installed {release["tag_name"]} with verified SHA256')
except (OSError, ValueError, KeyError, TypeError, tarfile.TarError, zipfile.BadZipFile) as error:
    print(f'{tool}: bootstrap failed: {error}', file=sys.stderr)
    sys.exit(1)
PY
}

ensure_uv() {
  local version=""
  if command -v uv >/dev/null 2>&1 && version=$(timeout 10 uv --version 2>/dev/null); then
    ok "uv present: $version"; return 0
  fi
  if [ -x "$BIN_DIR/uv" ] && version=$(timeout 10 "$BIN_DIR/uv" --version 2>/dev/null); then
    export PATH="$BIN_DIR:$PATH"; ok "uv present: $version"; return 0
  fi
  info "Installing uv"
  if [ "$DRY_RUN" -eq 1 ]; then info '[dry-run] install uv from a SHA256-verified release asset'; return 0; fi
  install_bootstrap_binary uv || return $?
  export PATH="$BIN_DIR:$PATH"
  version=$(timeout 10 uv --version 2>/dev/null) || { err "uv install failed"; return 1; }
  ok "uv installed: $version"
}

ensure_vllm() {
  local version=""
  if [ -x "$VLLM_BIN" ] && version=$(vllm_version) && [ "$FORCE" -eq 0 ]; then
    ok "vLLM already installed: $version — skipping (use --force to upgrade)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] create venv $VENV_DIR + install latest vllm"; return 0; fi
  if [ ! -x "$VENV_PY" ]; then
    run_with_spinner "Creating Python 3.12 venv at $VENV_DIR" \
      uv venv "$VENV_DIR" --python 3.12 || return $?
  fi
  info "Installing latest vLLM (this downloads several GB of wheels)"
  run_with_spinner "Installing vLLM into $VENV_DIR" \
    uv pip install --python "$VENV_PY" --upgrade vllm || return $?
  version=$(vllm_version) || { err "vLLM install failed"; return 1; }
  [ -x "$VLLM_BIN" ] || { err "vLLM executable missing"; return 1; }
  ok "vLLM installed: $version"
}

# Shared with the generated launcher: inspect metadata without importing torch.
# FlashInfer JIT needs a full toolkit matching the wheel's CUDA major version.
select_cuda_toolkit() {
  "$1" - <<'PY'
import glob, importlib.metadata, os, re, shutil, subprocess, sys
from pathlib import Path
try:
    text = Path(importlib.metadata.distribution('torch').locate_file('torch/version.py')).read_text()
    match = re.search(r'cuda[^=\n]*=\s*[\x27\x22](\d+)\.(\d+)', text)
    if match is None:
        raise ValueError('cannot determine the installed PyTorch CUDA version')
    required = tuple(map(int, match.groups()))
    explicit = os.environ.get('CUDA_HOME') or os.environ.get('CUDA_PATH')
    override = os.environ.get('FLASHINFER_NVCC')
    if override and not explicit:
        executable = shutil.which(override)
        if not executable:
            raise ValueError(f'FLASHINFER_NVCC is not executable: {override}')
        explicit = str(Path(executable).resolve().parent.parent)
    candidates = [explicit] if explicit else ['/usr/local/cuda', *sorted(glob.glob('/usr/local/cuda-*'), reverse=True)]
    if not explicit and shutil.which('nvcc'):
        candidates.append(str(Path(shutil.which('nvcc')).resolve().parent.parent))
    rejected = []
    for candidate in dict.fromkeys(candidates):
        root = Path(candidate).resolve()
        compiler = root / 'bin/nvcc'
        try:
            if override and Path(shutil.which(override) or override).resolve() != compiler.resolve():
                raise ValueError('FLASHINFER_NVCC and CUDA_HOME select different toolkits')
            version = subprocess.check_output([str(compiler), '--version'], text=True, stderr=subprocess.STDOUT, timeout=10)
            match = re.search(r'release (\d+)\.(\d+)', version)
            actual = tuple(map(int, match.groups())) if match else (0, 0)
            if actual[0] != required[0] or actual < max(required, (12, 8)):
                raise ValueError(f'CUDA {actual[0]}.{actual[1]} does not satisfy wheel CUDA {required[0]}.{required[1]} and FlashInfer >=12.8')
            help_text = subprocess.check_output([str(compiler), '--help'], text=True, stderr=subprocess.STDOUT, timeout=10)
            if '--compress-mode' not in help_text:
                raise ValueError('nvcc lacks --compress-mode required by FlashInfer')
            if not (root / 'include/cuda_runtime.h').is_file() or not any((root / lib / 'libcudart.so').is_file() for lib in ('lib64', 'lib')):
                raise ValueError('CUDA runtime headers or development library are missing')
            print(root)
            sys.exit(0)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            rejected.append(f'{root}: {error}')
    raise ValueError('no compatible full CUDA toolkit found; set CUDA_HOME to a toolkit matching the PyTorch CUDA major version. ' + '; '.join(rejected))
except (OSError, ValueError, importlib.metadata.PackageNotFoundError) as error:
    print(f'qwenserve: CUDA preflight failed: {error}', file=sys.stderr)
    sys.exit(1)
PY
}

check_cuda_toolkit() {
  if [ "$DRY_RUN" -eq 1 ]; then info '[dry-run] check CUDA toolkit compatibility with installed PyTorch'; return 0; fi
  local cuda_root
  cuda_root=$(select_cuda_toolkit "$VENV_PY") || return $?
  ok "CUDA toolkit: $cuda_root (FlashInfer JIT)"
}

vllm_version() {
  # Importing vLLM initializes the ML stack and can take minutes under load.
  # Package metadata is enough for version reporting; serving is tested separately.
  [ -x "$VENV_PY" ] || return 1
  timeout 10 "$VENV_PY" -c 'from importlib.metadata import version; print(version("vllm"))' 2>/dev/null
}

# ── Model download (HF gated | ModelScope open mirror) ───────────────────────

model_files_present() {
  python3 - "$MODEL_DIR" <<'PY'
import json, struct, sys
from pathlib import Path

root = Path(sys.argv[1])

def read_json(path, limit):
    with path.open('rb') as stream:
        data = stream.read(limit + 1)
    if not data or len(data) > limit:
        raise ValueError('invalid JSON file size')
    value = json.loads(data, object_pairs_hook=unique_object)
    if not isinstance(value, dict) or not value:
        raise ValueError('expected a nonempty JSON object')
    return value

def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError('duplicate JSON key')
        value[key] = item
    return value

try:
    read_json(root / 'config.json', 4 * 1024 * 1024)
    read_json(root / 'tokenizer.json', 128 * 1024 * 1024)
    index = read_json(root / 'model.safetensors.index.json', 32 * 1024 * 1024)
    weight_map = index['weight_map']
    if not isinstance(weight_map, dict) or not weight_map:
        raise ValueError('missing weight map')
    shards = {}
    for tensor, filename in weight_map.items():
        if not isinstance(tensor, str) or not tensor or not isinstance(filename, str):
            raise ValueError('invalid weight map')
        if Path(filename).name != filename or not filename.endswith('.safetensors'):
            raise ValueError('invalid shard filename')
        shards.setdefault(filename, set()).add(tensor)
    for filename, expected in shards.items():
        with (root / filename).open('rb') as stream:
            prefix = stream.read(8)
            if len(prefix) != 8:
                raise ValueError('truncated shard')
            header_size = struct.unpack('<Q', prefix)[0]
            if not 2 <= header_size <= 16 * 1024 * 1024:
                raise ValueError('invalid safetensors header size')
            header = json.loads(stream.read(header_size), object_pairs_hook=unique_object)
            if not isinstance(header, dict) or set(header) - {'__metadata__'} != expected:
                raise ValueError('shard does not match its index')
            spans = []
            for name in expected:
                begin, end = header[name]['data_offsets']
                if type(begin) is not int or type(end) is not int or not 0 <= begin <= end:
                    raise ValueError('invalid tensor offsets')
                spans.append((begin, end))
            position = 0
            for begin, end in sorted(spans):
                if begin != position:
                    raise ValueError('overlapping or missing tensor data')
                position = end
            if (root / filename).stat().st_size != 8 + header_size + position:
                raise ValueError('truncated or oversized shard')
except (OSError, ValueError, TypeError, KeyError, OverflowError, RecursionError, struct.error):
    sys.exit(1)
PY
}

ensure_hf_cli() {
  if command -v hf >/dev/null 2>&1 && timeout 10 hf --help >/dev/null 2>&1; then return 0; fi
  info "Installing the Hugging Face CLI (hf)"
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] install or repair the hf CLI"; return 0; fi
  uv tool install --force huggingface_hub
  export PATH="$HOME/.local/bin:$PATH"
  timeout 10 hf --help >/dev/null 2>&1 || { err "hf CLI install failed"; return 1; }
}

hf_authed() { command -v hf >/dev/null 2>&1 && timeout 20 hf auth whoami >/dev/null 2>&1; }

choose_source() {
  [ -n "$SOURCE" ] && return 0
  if hf_authed; then SOURCE="hf"; return 0; fi
  if have_tty && [ "$DRY_RUN" -eq 0 ]; then
    draw_box "1;33" \
      "Model download source" \
      "" \
      "This model is GATED on Hugging Face: you need a free HF account," \
      "to accept the terms on the model page, and an access token:" \
      "  1. https://huggingface.co/join" \
      "  2. open https://huggingface.co/$MODEL_ID and accept" \
      "  3. create a READ token at https://huggingface.co/settings/tokens" \
      "  4. run:  hf auth login   (paste the token)" \
      "" \
      "Alternatively, try ModelScope (no login for public models):" \
      "  https://modelscope.cn/models/$MODEL_ID" \
      "(Mirror availability varies; downloads outside China can be slower.)"
    if ask_yn "Use Hugging Face now (you already ran 'hf auth login')? [y/N]" "n"; then
      SOURCE="hf"
    else
      SOURCE="modelscope"
    fi
  else
    SOURCE="modelscope"
  fi
}

download_model() {
  if model_files_present; then
    ok "Model already downloaded at $MODEL_DIR — skipping"
    return 0
  fi
  choose_source
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] download $MODEL_ID via $SOURCE to $MODEL_DIR"; return 0; fi
  mkdir -p "$MODEL_DIR"
  case "$SOURCE" in
    hf)
      if ! hf_authed; then
        ensure_hf_cli
        if ! hf_authed; then
          err "Hugging Face auth required. Run 'hf auth login' first (or re-run with --modelscope)."
          exit 1
        fi
      fi
      info "Downloading $MODEL_ID from Hugging Face (~31 GB)"
      hf download "$MODEL_ID" --local-dir "$MODEL_DIR" || return $?
      ;;
    modelscope)
      info "Downloading $MODEL_ID from ModelScope (no login; ~31 GB)"
      # modelscope-hub owns the CLI. Run it in isolation: installing it globally
      # also installs `ms`, which can collide with an unrelated command.
      uv tool run --isolated --from modelscope-hub \
        modelscope download "$MODEL_ID" --local-dir "$MODEL_DIR" || {
          local download_status=$?
          err "ModelScope download failed. If the mirror is missing or private, run 'hf auth login',"
          err "then re-run this installer with --hf and the same --data-root."
          return "$download_status"
        }
      ;;
  esac
  if model_files_present; then
    ok "Model downloaded to $MODEL_DIR"
  else
    err "Download finished but expected files are missing or invalid in $MODEL_DIR"
    exit 1
  fi
}

# ── Tuned Triton FP8 kernel configs (sm_89) ──────────────────────────────────
# vLLM ships per-device Triton configs for its w8a8 block-FP8 GEMM. It has
# L40S tunings but none for the RTX 4090 — both are sm_89 (Ada), so the L40S
# configs are a close analog. Without them vLLM logs "Using default W8A8 Block
# FP8 kernel config. Performance might be sub-optimal!". Measured on 2x4090
# TP=2: 8-way concurrent aggregate 84.6 -> 158 tok/s (+87%).

install_fp8_configs() {
  local tp="${QWEN_TP:-$TP_DEFAULT}"
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] install sm_89 FP8 kernel configs"; return 0; fi
  case "$tp" in 1|2) ;; *) info "No FP8 tuning defined for TP=$tp — skipping"; return 0 ;; esac
  local cfg_dir
  cfg_dir=$("$VENV_PY" - <<'PY' 2>/dev/null
from importlib.metadata import distribution
print(distribution('vllm').locate_file('vllm/model_executor/layers/quantization/utils/configs'))
PY
)
  [ -d "$cfg_dir" ] || { warn "vLLM configs dir not found; skipping kernel tuning"; return 0; }

  # Only worthwhile on Ada consumer cards (sm_89). Other archs pick
  # DeepGEMM/CUTLASS paths or already ship configs.
  local ccap
  ccap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ')
  if [ "$ccap" != "8.9" ]; then
    info "Compute capability $ccap — skipping sm_89 FP8 config install"
    return 0
  fi

  local dev
  dev=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 | tr ' ' '_')
  [ -n "$dev" ] || { warn "Could not resolve device name; skipping"; return 0; }

  # (N,K) GEMM shapes for this model per TP degree, mapped to same-K L40S donors.
  # entry format: ourN:ourK:donorN:donorK
  local shapes=()
  if [ "$tp" = "2" ]; then
    shapes=("8192:5120:10240:5120" "5120:3072:5120:8192" "17408:5120:10240:5120" "5120:8704:5120:8192" "7168:5120:10240:5120")
  else
    shapes=("16384:5120:10240:5120" "5120:6144:5120:8192" "34816:5120:51200:5120" "5120:17408:5120:25600" "14336:5120:10240:5120")
  fi

  local installed=0 present=0
  for entry in "${shapes[@]}"; do
    local n k dn dk
    IFS=: read -r n k dn dk <<< "$entry"
    local dst="$cfg_dir/N=${n},K=${k},device_name=${dev},dtype=fp8_w8a8,block_shape=[128,128].json"
    local src="$cfg_dir/N=${dn},K=${dk},device_name=NVIDIA_L40S,dtype=fp8_w8a8,block_shape=[128,128].json"
    if [ -f "$dst" ]; then present=$((present+1)); continue; fi
    if [ ! -f "$src" ]; then warn "Donor config missing in this vLLM build: $(basename "$src")"; continue; fi
    cp "$src" "$dst"
    installed=$((installed+1))
  done
  if [ "$installed" -gt 0 ]; then
    ok "Installed $installed tuned FP8 kernel config(s) for $dev"
  elif [ "$present" -gt 0 ]; then
    ok "FP8 kernel configs already in place ($present present) — skipping"
  else
    warn "No compatible FP8 configs were found; vLLM will use its selected kernel defaults"
  fi
}

# ── qwenserve / qwenstop ─────────────────────────────────────────────────────

write_managed_file() {
  local name="$1" content="$2" mode="${3:-0755}" dest="${4:-$BIN_DIR/$1}" staged backup
  if [ -f "$dest" ] && [ "$(stat -c '%a' -- "$dest")" = "${mode#0}" ] && [ "$FORCE" -eq 0 ] && [ "$(cat "$dest")" = "$content" ]; then
    ok "$name already matches this installation — skipping"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] write $dest"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  staged=$(mktemp "$(dirname "$dest")/.$name.XXXXXX")
  printf '%s\n' "$content" > "$staged"
  chmod "$mode" "$staged"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup=$(mktemp "$dest.bak.XXXXXX")
    cp -pP -- "$dest" "$backup"
    info "Backed up $dest to $backup"
  fi
  mv -f -- "$staged" "$dest"
  ok "$name installed for $MODEL_DIR (port $PORT)"
}

render_qwenserve() {
  cat <<'EOF'
#!/usr/bin/env bash
# qwenserve - serve the configured Qwen model via vLLM.
set -euo pipefail
EOF
  printf 'DEFAULT_MODEL_DIR=%q\nDEFAULT_VLLM_BIN=%q\nDEFAULT_PORT=%q\nDEFAULT_TP=%q\nSERVED_NAME=%q\n' \
    "$MODEL_DIR" "$VLLM_BIN" "$PORT" "$TP_DEFAULT" "$SERVED_NAME"
  declare -f select_cuda_toolkit
  cat <<'EOF'
MODEL_DIR="${QWEN_MODEL_DIR:-$DEFAULT_MODEL_DIR}"
VLLM_BIN="${VLLM_BIN:-$DEFAULT_VLLM_BIN}"
export -n VLLM_BIN
PORT="${QWEN_PORT:-$DEFAULT_PORT}"
HOST="${QWEN_HOST:-127.0.0.1}"
TP="${QWEN_TP:-$DEFAULT_TP}"
MAX_LEN="${QWEN_MAX_LEN:-163840}"
GPU_UTIL="${QWEN_GPU_UTIL:-0.94}"
MAX_SEQS="${QWEN_MAX_SEQS:-64}"
SPEC_TOKENS="${QWEN_SPEC_TOKENS:-3}"
args=("$@")
check_socket=1
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    --port) PORT="${args[$((i+1))]:-}" ;;
    --port=*) PORT="${args[$i]#--port=}" ;;
    --host) HOST="${args[$((i+1))]:-}" ;;
    --host=*) HOST="${args[$i]#--host=}" ;;
    --help|-h) check_socket=0 ;;
  esac
done
if [ ! -x "$VLLM_BIN" ] || [ ! -d "$MODEL_DIR" ]; then
  echo 'qwenserve: missing vLLM executable or model directory; re-run the installer with the intended --data-root.' >&2
  exit 1
fi
if [ "$check_socket" -eq 1 ]; then
  python3 - "$HOST" "$PORT" <<'PY'
import socket, sys
host, port = sys.argv[1:]
try:
    if not port.isascii() or not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise ValueError('port must be an integer from 1 to 65535')
    family = socket.AF_INET6 if ':' in host else socket.AF_INET
    with socket.socket(family) as sock:
        sock.bind((host, int(port)))
except (OSError, ValueError) as error:
    print(f'qwenserve: cannot bind {host}:{port}: {error}. Choose a free QWEN_PORT and update the OMP vllm baseUrl to the same port.', file=sys.stderr)
    sys.exit(1)
PY
  CUDA_HOME=$(select_cuda_toolkit "$(dirname "$VLLM_BIN")/python") || exit $?
  export CUDA_HOME
  export CUDA_PATH="$CUDA_HOME" FLASHINFER_NVCC="$CUDA_HOME/bin/nvcc"
fi
export QWENSERVE_MODEL_DIR
QWENSERVE_MODEL_DIR=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$MODEL_DIR")
printf 'qwenserve: %s on http://%s:%s (vLLM: %s)\n' "$MODEL_DIR" "$HOST" "$PORT" "$VLLM_BIN"
exec "$VLLM_BIN" serve "$MODEL_DIR" \
  --served-model-name "$SERVED_NAME" \
  --tensor-parallel-size "$TP" \
  --speculative-config "{\"method\":\"mtp\",\"num_speculative_tokens\":${SPEC_TOKENS}}" \
  --kv-cache-dtype fp8 \
  --gpu-memory-utilization "$GPU_UTIL" \
  --max-model-len "$MAX_LEN" \
  --max-num-seqs "$MAX_SEQS" \
  --trust-remote-code \
  --reasoning-parser qwen3 \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder \
  --host "$HOST" \
  --port "$PORT" \
  "$@"
EOF
}

render_qwenstop() {
  printf '#!/usr/bin/env python3\n# qwenstop - stop only processes belonging to this Qwen model.\n'
  printf 'MODEL_DIR = %s\nSERVICE_NAME = %s\n' \
    "$(python3 -c 'import sys; print(repr(sys.argv[1]))' "$MODEL_DIR")" \
    "$(python3 -c 'import sys; print(repr(sys.argv[1]))' "$SERVICE_NAME")"
  cat <<'QWENSTOP_EOF'
import os, signal, subprocess, sys, time
from pathlib import Path

def process_record(pid, proc=Path('/proc')):
    try:
        root = proc / str(pid)
        if root.stat().st_uid != os.getuid():
            return None
        fields = (root / 'stat').read_text().rsplit(')', 1)[1].split()
        if fields[0] == 'Z':
            return None
        argv = (root / 'cmdline').read_bytes().split(b'\0')
        try:
            env = (root / 'environ').read_bytes().split(b'\0')
        except PermissionError:
            env = []
        model = os.fsencode(os.path.realpath(os.environ.get('QWEN_MODEL_DIR', MODEL_DIR)))
        tagged = any(value == b'QWENSERVE_MODEL_DIR=' + model for value in env)
        direct = any(Path(os.fsdecode(arg)).name == 'vllm' and argv[i+1:i+3] == [b'serve', model]
                     for i, arg in enumerate(argv[:2]))
        return {'pid': pid, 'parent': int(fields[1]), 'start': fields[19], 'owned': tagged or direct}
    except (OSError, ValueError, IndexError):
        return None

def owned_processes(proc=Path('/proc')):
    records = {}
    for path in proc.iterdir():
        if path.name.isdecimal():
            record = process_record(int(path.name), proc)
            if record:
                records[record['pid']] = record
    protected = {os.getpid()}
    parent = os.getppid()
    while parent in records and parent not in protected:
        protected.add(parent)
        parent = records[parent]['parent']
    owned = {pid for pid, record in records.items() if record['owned'] and pid not in protected}
    while True:
        extra = {pid for pid, record in records.items() if record['parent'] in owned and pid not in protected}
        if extra <= owned:
            return {pid: records[pid] for pid in owned}
        owned |= extra

def send_signal(record, signum):
    # Hold a pidfd while validating start time so PID reuse cannot hit another job.
    try:
        descriptor = os.pidfd_open(record['pid'])
    except ProcessLookupError:
        return
    try:
        current = process_record(record['pid'])
        if current and current['start'] == record['start']:
            try:
                signal.pidfd_send_signal(descriptor, signum)
            except ProcessLookupError:
                pass
    finally:
        os.close(descriptor)

def remaining(tracked):
    return {pid: record for pid, record in tracked.items()
            if (current := process_record(pid)) and current['start'] == record['start']}

def main():
    tracked = owned_processes()
    if tracked:
        try:
            service = subprocess.run(['systemctl', '--user', 'show', SERVICE_NAME, '-p', 'MainPID', '--value'],
                                     capture_output=True, text=True, timeout=5)
            if service.returncode == 0 and service.stdout.strip().isdecimal() and int(service.stdout) in tracked:
                subprocess.run(['systemctl', '--user', 'stop', SERVICE_NAME], check=True, timeout=10)
        except (OSError, subprocess.SubprocessError) as error:
            print(f'qwenstop: systemd stop unavailable: {error}', file=sys.stderr)
        for record in tracked.values():
            if record['parent'] not in tracked:
                send_signal(record, signal.SIGTERM)
        deadline = time.monotonic() + 90
        empty_samples = 0
        while time.monotonic() < deadline:
            tracked.update(owned_processes())
            empty_samples = 0 if remaining(tracked) else empty_samples + 1
            if empty_samples >= 2:
                break
            time.sleep(1)
        tracked.update(owned_processes())
        for record in remaining(tracked).values():
            send_signal(record, signal.SIGKILL)
        if remaining(tracked):
            time.sleep(2)
        if remaining(tracked):
            print('qwenstop: some owned processes have not exited', file=sys.stderr)
            return 1
        print('qwenstop: owned Qwen processes stopped')
    else:
        print('qwenstop: no matching Qwen processes are running')
    try:
        subprocess.run(['nvidia-smi', '--query-gpu=index,memory.used,power.draw', '--format=csv,noheader'], timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return 0

if __name__ == '__main__':
    sys.exit(main())
QWENSTOP_EOF
}

install_qwenserve() {
  write_managed_file qwenserve "$(render_qwenserve)"
  write_managed_file qwenstop "$(render_qwenstop)"

  # Guided-install explanation of the two commands
  draw_box "0;36" \
    "Your two commands" \
    "" \
    "  qwenserve   Start the model server on http://127.0.0.1:$PORT" \
    "              (OpenAI-compatible). Runs in the foreground — keep" \
    "              it in a tmux/terminal, or use --with-service instead." \
    "              First start compiles kernels once (~10-20 min);" \
    "              later starts take ~2-5 min (cached)." \
    "" \
    "  qwenstop    Stop the server and free the GPUs: sends SIGTERM," \
    "              waits for workers to exit, SIGKILLs only owned Qwen" \
    "              processes, then prints each GPU's memory + power draw" \
    "              so you can confirm the cards are back at idle." \
    "" \
    "  Tunables (env):  QWEN_MAX_LEN=262144 qwenserve   # bigger context" \
    "                   QWEN_SPEC_TOKENS=4  qwenserve   # MTP draft depth"

  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not on PATH — add:  export PATH=\"$BIN_DIR:\$PATH\"" ;;
  esac
}

# ── systemd user service (optional) ──────────────────────────────────────────

install_service() {
  if ! command -v systemctl >/dev/null 2>&1; then
    err "--with-service requires systemd"; return 1
  fi
  info "Installing systemd user service '$SERVICE_NAME'"
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] write $UNIT_FILE + enable"; return 0; fi
  local unit_content
  unit_content=$(cat <<EOF
[Unit]
Description=qwenserve - vLLM server for $SERVED_NAME
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1].replace("%", "%%")))' "$BIN_DIR/qwenserve")
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF
)
  write_managed_file "$SERVICE_NAME.service" "$unit_content" 0644 "$UNIT_FILE"
  # shellcheck disable=SC2015  # intentional: tolerate enable-linger failure when loginctl exists
  command -v loginctl >/dev/null 2>&1 && loginctl enable-linger "$(whoami)" 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable "$SERVICE_NAME" >/dev/null 2>&1 || { err "Could not enable $SERVICE_NAME"; return 1; }
  ok "Service installed (start with: systemctl --user start $SERVICE_NAME)"
  warn "First start compiles kernels — 'journalctl --user -u $SERVICE_NAME -f' to watch."
}

# ── omp install + provider wiring ────────────────────────────────────────────

ensure_omp() {
  local version=""
  if command -v omp >/dev/null 2>&1 && version=$(timeout 10 omp --version 2>/dev/null); then
    ok "omp present: $version — skipping install"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] install bun if needed, then $OMP_PACKAGE"; return 0; fi
  info "omp not found — installing"
  if ! command -v bun >/dev/null 2>&1 || ! timeout 10 bun --version >/dev/null 2>&1; then
    info "Installing bun"
    install_bootstrap_binary bun || return $?
    export PATH="$BIN_DIR:$PATH"
  fi
  command -v bun >/dev/null 2>&1 || { err "bun install failed; install omp manually"; return 1; }
  run_with_spinner "Installing omp ($OMP_PACKAGE)" \
    bun install -g "$OMP_PACKAGE" || { err "omp installation failed"; return 1; }
  export PATH="$HOME/.bun/bin:$PATH"
  if command -v omp >/dev/null 2>&1 && version=$(timeout 10 omp --version 2>/dev/null); then
    ok "omp installed: $version"
  else
    err "omp executable missing after installation"; return 1
  fi
}

configure_omp_provider() {
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] merge vllm provider into $MODELS_YML"; return 0; fi
  mkdir -p "$OMP_AGENT_DIR"
  info "Registering vLLM provider in $MODELS_YML"
  local merge_msg
  merge_msg=$(MODELS_YML_PATH="$MODELS_YML" VLLM_PORT="$PORT" "${VENV_PY:-python3}" - <<'PY'
import copy, os, re, shutil, stat, tempfile, yaml

path = os.path.realpath(os.environ["MODELS_YML_PATH"])
port = os.environ["VLLM_PORT"]
block = f"""  vllm:
    baseUrl: http://127.0.0.1:{port}/v1
    auth: none
"""
action = "created"
original = None
before = {}

if not os.path.exists(path):
    new_text = "providers:\n" + block
else:
    with open(path) as fh:
        text = fh.read()
    original = text
    try:
        before = yaml.safe_load(text) or {}
    except yaml.YAMLError:
        raise SystemExit('Invalid YAML; models.yml left unchanged')
    if not isinstance(before, dict) or not isinstance(before.get('providers', {}), (dict, type(None))):
        raise SystemExit('Expected a providers mapping; models.yml left unchanged')
    if text and not text.endswith('\n'):
        text += '\n'
    lines = text.splitlines(keepends=True)
    provider_headers = [i for i, line in enumerate(lines) if re.match(r'''^["']?providers["']?\s*:''', line)]
    if len(provider_headers) > 1:
        raise ValueError('multiple providers sections; configuration left unchanged')
    has_providers = bool(provider_headers)
    start, end = 0, 0
    if has_providers:
        start = provider_headers[0]
        if not re.match(r'''^["']?providers["']?\s*:\s*(?:#.*)?$''', lines[start].rstrip('\n')):
            raise ValueError('providers must use an indented block mapping; configuration left unchanged')
        end = start + 1
        while end < len(lines) and (not lines[end].strip() or lines[end].startswith((' ', '\t', '#'))):
            end += 1
    matches = [i for i in range(start + 1, end) if re.match(r'''^  ["']?vllm["']?\s*:''', lines[i])]
    if len(matches) > 1:
        raise ValueError('multiple vllm entries; configuration left unchanged')
    vllm_idx = matches[0] if matches else None
    if vllm_idx is not None:
        j = vllm_idx + 1
        while j < len(lines) and (lines[j].startswith("    ") or lines[j].strip() == ""):
            j += 1
        old_block = lines[vllm_idx:j]
        if not re.match(r'''^  ["']?vllm["']?\s*:\s*(?:#.*)?$''', old_block[0].rstrip('\n')):
            raise ValueError('vllm must use an indented block mapping; configuration left unchanged')
        urls = [i for i, line in enumerate(old_block) if re.match(r'''^    ["']?baseUrl["']?\s*:''', line)]
        if len(urls) > 1:
            raise ValueError('multiple vllm baseUrl fields; configuration left unchanged')
        replacement = list(old_block)
        url_line = f'    baseUrl: http://127.0.0.1:{port}/v1\n'
        if urls:
            replacement[urls[0]] = url_line
        else:
            replacement.insert(1, url_line)
        if not any(re.match(r'''^    ["']?auth["']?\s*:''', line) for line in replacement):
            replacement.insert(2, '    auth: none\n')
        if replacement == old_block:
            print("models.yml: already configured — skipping")
            raise SystemExit(0)
        lines[vllm_idx:j] = replacement
        new_text = "".join(lines)
        action = "updated"
    elif has_providers:
        lines.insert(start + 1, block)
        new_text = "".join(lines)
        action = "added"
    else:
        if not text.endswith("\n"):
            text += "\n"
        new_text = text + "\nproviders:\n" + block
        action = "added"

expected = copy.deepcopy(before)
providers = dict(expected.get('providers') or {})
provider = providers.get('vllm') or {}
if not isinstance(provider, dict):
    raise SystemExit('Expected a vllm mapping; models.yml left unchanged')
provider = dict(provider)
provider['baseUrl'] = f'http://127.0.0.1:{port}/v1'
provider.setdefault('auth', 'none')
providers['vllm'] = provider
expected['providers'] = providers
try:
    if yaml.safe_load(new_text) != expected:
        raise SystemExit('Unsupported YAML layout; models.yml left unchanged')
except yaml.YAMLError:
    raise SystemExit('Unsupported YAML layout; models.yml left unchanged')
if os.path.exists(path):
    with open(path) as fh:
        if fh.read() != original:
            raise SystemExit('Configuration changed concurrently; refusing to overwrite it')
    with tempfile.NamedTemporaryFile(prefix=os.path.basename(path) + '.bak.', dir=os.path.dirname(path), delete=False) as backup:
        backup_path = backup.name
    shutil.copy2(path, backup_path)
with tempfile.NamedTemporaryFile(mode='w', prefix='.models.', dir=os.path.dirname(path), delete=False) as fh:
    fh.write(new_text)
    staged = fh.name
if original is not None:
    with open(path) as fh:
        if fh.read() != original:
            raise ValueError('configuration changed concurrently; refusing to overwrite it')
    os.chmod(staged, stat.S_IMODE(os.stat(path).st_mode))
elif os.path.exists(path):
    raise SystemExit('Configuration appeared concurrently; refusing to overwrite it')
os.replace(staged, path)
print(f"models.yml: {action}")
PY
) || { err "Could not update the OMP provider"; return 1; }
  info "$merge_msg"
  ok "omp provider configured (vllm -> http://127.0.0.1:$PORT/v1)"
}

# ── e2e smoke test ───────────────────────────────────────────────────────────

server_has_model() {
  curl -fsS --max-time 3 "http://127.0.0.1:$PORT/v1/models" 2>/dev/null | \
    python3 -c 'import json,sys; data=json.load(sys.stdin); sys.exit(0 if any(isinstance(item,dict) and item.get("id")==sys.argv[1] for item in data.get("data",[])) else 1)' "$SERVED_NAME" 2>/dev/null
}

smoke_test() {
  local base="http://127.0.0.1:$PORT"
  if server_has_model; then
    info "Server already responding on port $PORT"
  else
    info "Launching qwenserve (first start compiles kernels — allow up to ~40 min)"
    if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] launch + poll + chat smoke test"; return 0; fi
    local logf="$DATA_ROOT/qwenserve.log"
    nohup "$BIN_DIR/qwenserve" >"$logf" 2>&1 &
    local server_pid=$!
    local deadline=$((SECONDS + 2400)) up=0
    while [ $SECONDS -lt $deadline ]; do
      if server_has_model; then up=1; break; fi
      if ! kill -0 "$server_pid" 2>/dev/null; then
        err "qwenserve exited during startup — see $logf"
        exit 1
      fi
      sleep 10
    done
    [ "$up" -eq 1 ] || { err "Server did not come up in 40 min — see $logf"; exit 1; }
    ok "Server is up"
  fi

  [ "$DRY_RUN" -eq 1 ] && return 0
  local reply
  reply=$(curl -fsS --max-time 300 "$base/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$SERVED_NAME\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: QWEN-OK\"}],\"max_tokens\":16,\"chat_template_kwargs\":{\"enable_thinking\":false}}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["choices"][0]["message"]["content"])' 2>/dev/null || true)
  if [ "$reply" = QWEN-OK ]; then
    ok "Chat completion works: ${reply:0:40}"
  else
    err "Smoke test failed — expected QWEN-OK from $SERVED_NAME, received an error or a different answer"
    exit 1
  fi
  if command -v omp >/dev/null 2>&1; then
    if omp models find qwen 2>/dev/null | grep -qi "$SERVED_NAME"; then
      ok "omp discovers the model: vllm/$SERVED_NAME"
    else
      warn "omp did not list the model — check $MODELS_YML"
    fi
  fi
}

# ── verify (diagnostics only) ────────────────────────────────────────────────

verify() {
  local fail=0
  log "qwenserve install diagnostics"
  log "─────────────────────────────"
  if command -v nvidia-smi >/dev/null 2>&1; then
    ok "GPUs: $(nvidia-smi --query-gpu=name --format=csv,noheader | paste -sd',')"
    ok "Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
  else
    err "nvidia-smi missing"; fail=1
  fi
  if [ -x "$VLLM_BIN" ] && vllm_version >/dev/null; then ok "vLLM: $(vllm_version)"; else err "vLLM missing or invalid at $VLLM_BIN"; fail=1; fi
  check_cuda_toolkit || fail=1
  if model_files_present; then
    ok "Model: $(du -shL "$MODEL_DIR" 2>/dev/null | cut -f1) at $MODEL_DIR"
  else
    err "Model incomplete at $MODEL_DIR"; fail=1
  fi
  if [ -x "$BIN_DIR/qwenserve" ] && [ "$(cat "$BIN_DIR/qwenserve")" = "$(render_qwenserve)" ]; then
    ok "qwenserve: matches model, vLLM path, and port $PORT"
  else err "qwenserve missing or stale; re-run with the intended --data-root and --port"; fail=1; fi
  if [ -x "$BIN_DIR/qwenstop" ] && [ "$(cat "$BIN_DIR/qwenstop")" = "$(render_qwenstop)" ]; then
    ok "qwenstop: matches this installation"
  else err "qwenstop missing or stale"; fail=1; fi
  local omp_version
  if command -v omp >/dev/null 2>&1 && omp_version=$(timeout 10 omp --version 2>/dev/null); then
    ok "omp: $omp_version"
  else err "omp missing or failing its version check"; fail=1; fi
  if "$VENV_PY" - "$MODELS_YML" "$PORT" <<'PY' 2>/dev/null
import sys, yaml
with open(sys.argv[1]) as stream:
    config = yaml.safe_load(stream)
url = config['providers']['vllm']['baseUrl']
sys.exit(0 if url.rstrip('/') == f'http://127.0.0.1:{sys.argv[2]}/v1' else 1)
PY
  then ok "omp provider: matches port $PORT"
  else err "omp provider missing or pointing to another port"; fail=1; fi
  if [ -f "$UNIT_FILE" ]; then
    ok "systemd unit: $UNIT_FILE ($(systemctl --user is-enabled "$SERVICE_NAME" 2>/dev/null || echo unknown))"
  fi
  if server_has_model; then
    ok "Server: responding on port $PORT"
  else
    info "Server: not running (start with 'qwenserve' or 'systemctl --user start $SERVICE_NAME')"
  fi
  return $fail
}

# ── uninstall ────────────────────────────────────────────────────────────────

uninstall() {
  info "Uninstalling"
  if [ -f "$BIN_DIR/qwenserve" ] && \
     ! grep -Fxq "DEFAULT_MODEL_DIR=$(printf '%q' "$MODEL_DIR")" "$BIN_DIR/qwenserve"; then
    err "The installed launcher belongs to another data root or is an older version."
    err "Re-run the installer for the intended --data-root before uninstalling."
    return 1
  fi
  if [ "$DRY_RUN" -eq 0 ]; then
    QWEN_MODEL_DIR="$MODEL_DIR" python3 -c "$(render_qwenstop)"
    if [ -f "$UNIT_FILE" ] && systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
      err "The service is still active; refusing to remove files for a different or undrained installation."
      return 1
    fi
  fi
  if command -v systemctl >/dev/null 2>&1 && [ -f "$UNIT_FILE" ]; then
    run systemctl --user disable "$SERVICE_NAME" || true
    run rm -f "$UNIT_FILE"
    run systemctl --user daemon-reload || true
    ok "Service removed"
  fi
  for f in qwenserve qwenstop; do
    if [ -f "$BIN_DIR/$f" ]; then run rm -f "$BIN_DIR/$f"; ok "$f removed"; fi
  done
  if grep -q "vllm:" "$MODELS_YML" 2>/dev/null && [ "$DRY_RUN" -eq 0 ]; then
    local rm_msg
    rm_msg=$(MODELS_YML_PATH="$MODELS_YML" "${VENV_PY:-python3}" - <<'PY'
import copy, os, re, shutil, stat, tempfile, yaml
path = os.path.realpath(os.environ["MODELS_YML_PATH"])
with open(path) as fh:
    text = fh.read()
try:
    before = yaml.safe_load(text)
except yaml.YAMLError:
    raise SystemExit('Invalid YAML; models.yml left unchanged')
if not isinstance(before, dict) or not isinstance(before.get('providers'), dict) or 'vllm' not in before['providers']:
    print('models.yml: vllm provider already absent')
    raise SystemExit(0)
expected = copy.deepcopy(before)
del expected['providers']['vllm']
lines = text.splitlines(keepends=True)
headers = [i for i,line in enumerate(lines) if re.match(r'''^["']?providers["']?\s*:\s*(?:#.*)?$''',line.rstrip('\n'))]
if len(headers) != 1:
    raise SystemExit('Unsupported YAML layout; models.yml left unchanged')
start = headers[0]
end = start + 1
while end < len(lines) and (not lines[end].strip() or lines[end].startswith((' ', '\t', '#'))):
    end += 1
entries = [i for i in range(start+1,end) if re.match(r'''^  ["']?vllm["']?\s*:''',lines[i])]
if len(entries) != 1:
    raise SystemExit('Unsupported YAML layout; models.yml left unchanged')
i = entries[0]; j = i+1
while j < end and (not lines[j].strip() or lines[j].startswith('    ')):
    j += 1
del lines[i:j]
if not expected['providers']:
    lines[start] = 'providers: {}\n'
new_text = ''.join(lines)
try:
    if yaml.safe_load(new_text) != expected:
        raise SystemExit('Unsupported YAML layout; models.yml left unchanged')
except yaml.YAMLError:
    raise SystemExit('Unsupported YAML layout; models.yml left unchanged')
with tempfile.NamedTemporaryFile(prefix=os.path.basename(path)+'.bak.', dir=os.path.dirname(path), delete=False) as backup:
    backup_path=backup.name
shutil.copy2(path, backup_path)
with tempfile.NamedTemporaryFile(mode='w',prefix='.models.',dir=os.path.dirname(path),delete=False) as stream:
    stream.write(new_text); staged=stream.name
with open(path) as stream:
    if stream.read() != text:
        raise SystemExit('Configuration changed concurrently; refusing to overwrite it')
os.chmod(staged,stat.S_IMODE(os.stat(path).st_mode))
os.replace(staged,path)
print("models.yml: vllm provider removed")
PY
)
    info "$rm_msg"
    ok "omp provider entry removed"
  fi
  if [ "$PURGE" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] delete only $VENV_DIR and $MODEL_DIR"; else
      warn "Deleting only $VENV_DIR and $MODEL_DIR; preserving other files under $DATA_ROOT"
      rm -rf -- "$VENV_DIR" "$MODEL_DIR"
      ok "Venv and model weights purged"
    fi
  else
    info "Kept venv + model weights under $DATA_ROOT (use --purge to delete)"
  fi
}

# ── main ─────────────────────────────────────────────────────────────────────

main() {
  if [ "$HAS_GUM" -eq 1 ] && [ "$NO_GUM" -eq 0 ] && [ "$QUIET" -eq 0 ]; then
    gum style --border normal --border-foreground 39 --padding "0 1" --margin "1 0" \
      "$(gum style --foreground 42 --bold 'qwenserve installer')" \
      "$(gum style --foreground 245 'Qwen3.8-27B-Uncensored-FP8 · vLLM · dual RTX 4090 · omp provider')"
  else
    log ""
    log "\033[1;32mqwenserve installer\033[0m"
    log "\033[0;90mQwen3.8-27B-Uncensored-FP8 · vLLM · dual RTX 4090 · omp provider\033[0m"
  fi

  setup_proxy

  if [ "$DO_VERIFY" -eq 1 ]; then verify; exit $?; fi
  if [ "$UNINSTALL" -eq 1 ]; then acquire_lock; uninstall; exit 0; fi

  acquire_lock
  preflight

  ensure_uv
  ensure_vllm
  check_cuda_toolkit
  download_model
  install_fp8_configs
  install_qwenserve
  [ "$WITH_SERVICE" -eq 1 ] && install_service
  ensure_omp
  configure_omp_provider
  record_installation
  [ "$DO_START" -eq 1 ] && smoke_test

  # Final summary
  local lines=(
    "vLLM:     $(vllm_version || echo 'not installed')"
    "Model:    $MODEL_DIR"
    "Launcher: $BIN_DIR/qwenserve  (port $PORT, TP=$TP_DEFAULT, FP8 KV, MTP, 160K ctx)"
    "Stop:     $BIN_DIR/qwenstop   (stops this model and reports GPU usage)"
    "omp:      vllm/$SERVED_NAME via $MODELS_YML"
  )
  [ "$WITH_SERVICE" -eq 1 ] && lines+=("Service:  systemctl --user start $SERVICE_NAME")
  local uninstall_command
  printf -v uninstall_command '%q --uninstall --data-root %q --port %q' "$0" "$DATA_ROOT" "$PORT"
  lines+=("" \
    "Start the server:   qwenserve" \
    "Stop the server:    qwenstop" \
    "Use it in omp:      omp --model vllm/$SERVED_NAME" \
    "Uninstall:          $uninstall_command   (add --purge to delete weights)")
  draw_box "0;32" "${lines[@]+"${lines[@]}"}"
  if [ "$DO_START" -eq 0 ]; then
    warn "First 'qwenserve' launch compiles kernels once (~10-20 min). Later starts take ~2-5 min (cached)."
  fi
}

if [ "${QWEN_INSTALLER_LIB:-0}" != 1 ]; then
  parse_args "$@"
  configure_paths
  main
fi
