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
#   4. Installs tuned Triton block-FP8 kernel configs for RTX 4090 (sm_89)
#      adapted from vLLM's shipped L40S tunings (big concurrent-throughput win)
#   5. Installs two commands in ~/.local/bin:
#        qwenserve — start the OpenAI-compatible server (dual-4090-tuned:
#                    TP=2, FP8 KV cache, MTP speculative decoding, 160K context,
#                    qwen3 reasoning + qwen3_coder tool-call parsers)
#        qwenstop  — stop it: graceful SIGTERM, waits for VRAM to drain,
#                    SIGKILLs only leftover vLLM pids, then reports each GPU's
#                    memory/power so you can see the cards back at idle
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
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --modelscope)   SOURCE="modelscope" ;;
    --hf)           SOURCE="hf" ;;
    --with-service) WITH_SERVICE=1 ;;
    --start)        DO_START=1 ;;
    --verify)       DO_VERIFY=1 ;;
    --uninstall)    UNINSTALL=1 ;;
    --purge)        PURGE=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    --force)        FORCE=1 ;;
    --quiet)        QUIET=1 ;;
    --no-gum)       NO_GUM=1 ;;
    --port)         PORT="${2:?--port needs a value}"; shift ;;
    --data-root)    DATA_ROOT="${2:?--data-root needs a value}"; shift ;;
    --help|-h)      usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
  shift
done

VENV_DIR="$DATA_ROOT/venv"
MODEL_DIR="$DATA_ROOT/models/$MODEL_NAME"
VLLM_BIN="$VENV_DIR/bin/vllm"
VENV_PY="$VENV_DIR/bin/python"
OMP_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.omp/agent}"
MODELS_YML="$OMP_AGENT_DIR/models.yml"
SERVICE_NAME="qwenserve"
UNIT_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"

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
    PROXY_ARGS=(--proxy "$HTTPS_PROXY"); info "Using HTTPS proxy: $HTTPS_PROXY"
  elif [ -n "${HTTP_PROXY:-}" ]; then
    PROXY_ARGS=(--proxy "$HTTP_PROXY"); info "Using HTTP proxy: $HTTP_PROXY"
  fi
}

# ── Temp dir + locking ───────────────────────────────────────────────────────

TMP="$(mktemp -d)"
LOCK_DIR=""
cleanup() {
  if [ -n "$LOCK_DIR" ]; then
    rm -f "$LOCK_DIR/pid" 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

acquire_lock() {
  LOCK_DIR="${TMPDIR:-/tmp}/qwen38-install.lock"
  local tries=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    local pid_file="$LOCK_DIR/pid" old_pid=""
    [ -f "$pid_file" ] && old_pid=$(cat "$pid_file" 2>/dev/null || true)
    if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
      warn "Removing stale install lock (pid $old_pid is gone)"
      rm -f "$pid_file"; rmdir "$LOCK_DIR" 2>/dev/null || true
      continue
    fi
    tries=$((tries+1))
    if [ "$tries" -gt 30 ]; then
      err "Another install is running (lock: $LOCK_DIR, pid ${old_pid:-unknown})"
      exit 1
    fi
    sleep 2
  done
  echo $$ > "$LOCK_DIR/pid"
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
  if [ "$DRY_RUN" -eq 0 ]; then mkdir -p "$model_parent" 2>/dev/null || true; fi
  local avail
  avail=$(df -Pk "$model_parent" 2>/dev/null | awk 'NR==2 {print int($4/1048576)}')
  if [ -n "$avail" ] && [ "$avail" -lt "$MIN_MODEL_DISK_GB" ]; then
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

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then ok "uv present: $(uv --version | head -1)"; return 0; fi
  if [ -x "$HOME/.local/bin/uv" ]; then
    export PATH="$HOME/.local/bin:$PATH"; ok "uv present: $(uv --version | head -1)"; return 0
  fi
  info "Installing uv"
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] curl astral.sh/uv/install.sh | sh"; return 0; fi
  curl -fsSL "${PROXY_ARGS[@]}" https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$PATH"
  command -v uv >/dev/null 2>&1 || { err "uv install failed"; exit 1; }
  ok "uv installed: $(uv --version | head -1)"
}

ensure_vllm() {
  if [ -x "$VLLM_BIN" ] && [ "$FORCE" -eq 0 ]; then
    ok "vLLM already installed: $("$VLLM_BIN" --version 2>/dev/null || echo unknown) — skipping (use --force to upgrade)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] create venv $VENV_DIR + install latest vllm"; return 0; fi
  if [ ! -x "$VENV_PY" ]; then
    run_with_spinner "Creating Python 3.12 venv at $VENV_DIR" \
      uv venv "$VENV_DIR" --python 3.12
  fi
  info "Installing latest vLLM (this downloads several GB of wheels)"
  run_with_spinner "Installing vLLM into $VENV_DIR" \
    uv pip install --python "$VENV_PY" --upgrade vllm
  "$VLLM_BIN" --version >/dev/null 2>&1 || { err "vLLM install failed"; exit 1; }
  ok "vLLM installed: $("$VLLM_BIN" --version)"
}

# ── Model download (HF gated | ModelScope open mirror) ───────────────────────

model_files_present() {
  [ -f "$MODEL_DIR/config.json" ] && \
  [ -f "$MODEL_DIR/model.safetensors.index.json" ] && \
  [ -f "$MODEL_DIR/tokenizer.json" ] && \
  ls "$MODEL_DIR"/model-*.safetensors >/dev/null 2>&1
}

ensure_hf_cli() {
  if command -v hf >/dev/null 2>&1; then return 0; fi
  info "Installing the Hugging Face CLI (hf)"
  run uv tool install huggingface_hub
  export PATH="$HOME/.local/bin:$PATH"
  command -v hf >/dev/null 2>&1 || { err "hf CLI install failed"; exit 1; }
}

hf_authed() { command -v hf >/dev/null 2>&1 && hf auth whoami >/dev/null 2>&1; }

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
      "The SAME weights are mirrored on ModelScope with NO login:" \
      "  https://modelscope.cn/models/$MODEL_ID" \
      "(Downloads from outside China can be slower.)"
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
      hf download "$MODEL_ID" --local-dir "$MODEL_DIR"
      ;;
    modelscope)
      info "Downloading $MODEL_ID from ModelScope (no login; ~31 GB)"
      if ! command -v modelscope >/dev/null 2>&1; then
        uv tool install modelscope
        export PATH="$HOME/.local/bin:$PATH"
      fi
      modelscope download --model "$MODEL_ID" --local_dir "$MODEL_DIR"
      ;;
  esac
  if model_files_present; then
    ok "Model downloaded to $MODEL_DIR"
  else
    err "Download finished but expected files are missing in $MODEL_DIR"
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
  local cfg_dir
  cfg_dir=$("$VENV_PY" - <<'PY' 2>/dev/null
import os, vllm
print(os.path.join(os.path.dirname(vllm.__file__),
                   "model_executor/layers/quantization/utils/configs"))
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
  dev=$("$VENV_PY" -c 'import torch; print(torch.cuda.get_device_name(0).replace(" ", "_"))' 2>/dev/null)
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
  else
    ok "FP8 kernel configs already in place ($present present) — skipping"
  fi
}

# ── qwenserve / qwenstop ─────────────────────────────────────────────────────

install_qwenserve() {
  if [ "$DRY_RUN" -eq 0 ]; then mkdir -p "$BIN_DIR"; fi
  local dest="$BIN_DIR/qwenserve"
  if [ -x "$dest" ] && [ "$FORCE" -eq 0 ] && grep -q "qwenserve - serve $SERVED_NAME" "$dest" 2>/dev/null; then
    ok "qwenserve already installed at $dest — skipping"
  else
    info "Installing qwenserve to $dest"
    if [ "$DRY_RUN" -eq 0 ]; then
      cat > "$dest" <<EOF
#!/usr/bin/env bash
# qwenserve - serve $SERVED_NAME (FP8) via vLLM with dual-4090-tuned defaults.
# Env knobs: QWEN_PORT QWEN_TP QWEN_MAX_LEN QWEN_GPU_UTIL QWEN_MAX_SEQS QWEN_SPEC_TOKENS
set -euo pipefail

MODEL_DIR="\${QWEN_MODEL_DIR:-$MODEL_DIR}"
VLLM_BIN="\${VLLM_BIN:-$VLLM_BIN}"
PORT="\${QWEN_PORT:-$PORT}"
TP="\${QWEN_TP:-$TP_DEFAULT}"
MAX_LEN="\${QWEN_MAX_LEN:-163840}"
GPU_UTIL="\${QWEN_GPU_UTIL:-0.94}"
MAX_SEQS="\${QWEN_MAX_SEQS:-64}"
SPEC_TOKENS="\${QWEN_SPEC_TOKENS:-3}"

exec "\$VLLM_BIN" serve "\$MODEL_DIR" \\
  --served-model-name $SERVED_NAME \\
  --tensor-parallel-size "\$TP" \\
  --speculative-config "{\\"method\\":\\"mtp\\",\\"num_speculative_tokens\\":\${SPEC_TOKENS}}" \\
  --kv-cache-dtype fp8 \\
  --gpu-memory-utilization "\$GPU_UTIL" \\
  --max-model-len "\$MAX_LEN" \\
  --max-num-seqs "\$MAX_SEQS" \\
  --trust-remote-code \\
  --reasoning-parser qwen3 \\
  --enable-auto-tool-choice \\
  --tool-call-parser qwen3_coder \\
  --port "\$PORT" \\
  "\$@"
EOF
      chmod 0755 "$dest"
      ok "qwenserve installed"
    else
      info "[dry-run] write $dest"
    fi
  fi

  local stop="$BIN_DIR/qwenstop"
  if [ -x "$stop" ] && [ "$FORCE" -eq 0 ] && grep -q "qwenstop - stop" "$stop" 2>/dev/null; then
    ok "qwenstop already installed at $stop — skipping"
  else
    info "Installing qwenstop to $stop"
    if [ "$DRY_RUN" -eq 0 ]; then
      cat > "$stop" <<'QWENSTOP_EOF'
#!/usr/bin/env bash
# qwenstop - stop the qwenserve vLLM server, free GPU memory, and let the
# cards drop back to idle power. Safe no-op when nothing is running.
set -euo pipefail

MODEL_DIR="__MODEL_DIR__"
VENV_DIR="__VENV_DIR__"
SERVICE_NAME="__SERVICE_NAME__"

info() { echo -e "\033[0;34m→\033[0m $*"; }
ok()   { echo -e "\033[0;32m✓\033[0m $*"; }
warn() { echo -e "\033[1;33m⚠\033[0m $*"; }

# 1. systemd user service, if installed and active
if command -v systemctl >/dev/null 2>&1 && \
   systemctl --user list-unit-files "$SERVICE_NAME.service" 2>/dev/null | grep -q "$SERVICE_NAME" && \
   systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
  info "Stopping systemd service $SERVICE_NAME"
  systemctl --user stop "$SERVICE_NAME"
fi

# 2. Any vllm serve process for this model, however it was launched
if pkill -TERM -f "vllm serve.*$MODEL_DIR" 2>/dev/null; then
  info "Sent SIGTERM to the vLLM server (graceful shutdown)"
fi

# 3. Wait for GPU memory to drain. The SIGKILL fallback targets only pids
#    whose cmdline is our venv's python or a VLLM:: worker proctitle — never
#    unrelated GPU processes. (On a box running several vLLM servers for
#    different models, the VLLM:: fallback could catch another server's
#    workers — the graceful SIGTERM path above is model-dir-scoped and is
#    what normally does the job.)
leftover=""
deadline=$((SECONDS + 90))
while [ $SECONDS -lt $deadline ]; do
  leftover=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | while read -r pid; do
    [ -n "$pid" ] || continue
    if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qE "$VENV_DIR|VLLM::"; then
      echo "$pid"
    fi
  done)
  [ -z "$leftover" ] && break
  sleep 3
done
if [ -n "$leftover" ]; then
  warn "Graceful stop timed out; SIGKILLing vLLM pids: $leftover"
  echo "$leftover" | xargs -r kill -KILL 2>/dev/null || true
  sleep 3
fi

# 4. Report final GPU state so you can see memory freed and power at idle
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=index,memory.used,power.draw --format=csv,noheader | while read -r line; do
    ok "GPU $line"
  done
fi
ok "vLLM server stopped; GPUs returning to idle power"
QWENSTOP_EOF
      # Bake in this install's paths
      sed -i "s|__MODEL_DIR__|$MODEL_DIR|; s|__VENV_DIR__|$VENV_DIR|; s|__SERVICE_NAME__|$SERVICE_NAME|" "$stop"
      chmod 0755 "$stop"
      ok "qwenstop installed"
    else
      info "[dry-run] write $stop"
    fi
  fi

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
    "              waits for VRAM to drain, SIGKILLs only leftover vLLM" \
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
    warn "systemd not available; skipping service install"
    return 0
  fi
  info "Installing systemd user service '$SERVICE_NAME'"
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] write $UNIT_FILE + enable"; return 0; fi
  mkdir -p "$(dirname "$UNIT_FILE")"
  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=qwenserve - vLLM server for $SERVED_NAME
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN_DIR/qwenserve
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF
  # shellcheck disable=SC2015  # intentional: tolerate enable-linger failure when loginctl exists
  command -v loginctl >/dev/null 2>&1 && loginctl enable-linger "$(whoami)" 2>/dev/null || true
  systemctl --user daemon-reload
  systemctl --user enable "$SERVICE_NAME" >/dev/null 2>&1 || true
  ok "Service installed (start with: systemctl --user start $SERVICE_NAME)"
  warn "First start compiles kernels — 'journalctl --user -u $SERVICE_NAME -f' to watch."
}

# ── omp install + provider wiring ────────────────────────────────────────────

ensure_omp() {
  if command -v omp >/dev/null 2>&1; then
    ok "omp present: $(omp --version 2>/dev/null | head -1) — skipping install"
    return 0
  fi
  info "omp not found — installing"
  if ! command -v bun >/dev/null 2>&1; then
    info "Installing bun"
    if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] curl bun.sh/install | bash"; else
      curl -fsSL "${PROXY_ARGS[@]}" https://bun.sh/install | bash
    fi
    export PATH="$HOME/.bun/bin:$PATH"
  fi
  command -v bun >/dev/null 2>&1 || { err "bun install failed; install omp manually"; return 1; }
  run_with_spinner "Installing omp ($OMP_PACKAGE)" \
    bun install -g "$OMP_PACKAGE"
  export PATH="$HOME/.bun/bin:$PATH"
  if command -v omp >/dev/null 2>&1; then
    ok "omp installed: $(omp --version 2>/dev/null | head -1)"
  else
    warn "omp installed but not on PATH this session — open a new shell"
  fi
}

configure_omp_provider() {
  if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] merge vllm provider into $MODELS_YML"; return 0; fi
  mkdir -p "$OMP_AGENT_DIR"
  info "Registering vLLM provider in $MODELS_YML"
  local merge_msg
  merge_msg=$(MODELS_YML_PATH="$MODELS_YML" VLLM_PORT="$PORT" python3 - <<'PY'
import os, shutil, time

path = os.environ["MODELS_YML_PATH"]
port = os.environ["VLLM_PORT"]
block = f"""  vllm:
    baseUrl: http://127.0.0.1:{port}/v1
    auth: none
"""
action = "created"

if not os.path.exists(path):
    new_text = "providers:\n" + block
else:
    with open(path) as fh:
        text = fh.read()
    lines = text.splitlines(keepends=True)
    has_providers = any(l.rstrip() == "providers:" for l in lines)
    vllm_idx = None
    for i, l in enumerate(lines):
        if l.startswith("  vllm:") and not l.startswith("   "):
            vllm_idx = i
            break
    if vllm_idx is not None:
        j = vllm_idx + 1
        while j < len(lines) and (lines[j].startswith("    ") or lines[j].strip() == ""):
            j += 1
        if "".join(lines[vllm_idx:j]) == block:
            print("models.yml: already configured — skipping")
            raise SystemExit(0)
        lines[vllm_idx:j] = [block]
        new_text = "".join(lines)
        action = "updated"
    elif has_providers:
        for i, l in enumerate(lines):
            if l.rstrip() == "providers:":
                lines.insert(i + 1, block)
                break
        new_text = "".join(lines)
        action = "added"
    else:
        if not text.endswith("\n"):
            text += "\n"
        new_text = text + "\nproviders:\n" + block
        action = "added"

if os.path.exists(path):
    shutil.copy2(path, f"{path}.bak.{time.strftime('%Y%m%d%H%M%S')}")
with open(path, "w") as fh:
    fh.write(new_text)
print(f"models.yml: {action}")
PY
)
  info "$merge_msg"
  ok "omp provider configured (vllm -> http://127.0.0.1:$PORT/v1)"
}

# ── e2e smoke test ───────────────────────────────────────────────────────────

smoke_test() {
  local base="http://127.0.0.1:$PORT"
  if curl -fsS --max-time 3 "$base/v1/models" >/dev/null 2>&1; then
    info "Server already responding on port $PORT"
  else
    info "Launching qwenserve (first start compiles kernels — allow up to ~40 min)"
    if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] launch + poll + chat smoke test"; return 0; fi
    local logf="$DATA_ROOT/qwenserve.log"
    nohup "$BIN_DIR/qwenserve" >"$logf" 2>&1 &
    local server_pid=$!
    local deadline=$((SECONDS + 2400)) up=0
    while [ $SECONDS -lt $deadline ]; do
      if curl -fsS --max-time 3 "$base/v1/models" >/dev/null 2>&1; then up=1; break; fi
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
  if [ -n "$reply" ]; then
    ok "Chat completion works: ${reply:0:40}"
  else
    err "Smoke test failed — server answered /v1/models but chat completion errored"
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
  echo "qwenserve install diagnostics"
  echo "─────────────────────────────"
  if command -v nvidia-smi >/dev/null 2>&1; then
    ok "GPUs: $(nvidia-smi --query-gpu=name --format=csv,noheader | paste -sd',')"
    ok "Driver: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
  else
    err "nvidia-smi missing"; fail=1
  fi
  if [ -x "$VLLM_BIN" ]; then ok "vLLM: $("$VLLM_BIN" --version 2>/dev/null)"; else err "vLLM missing at $VLLM_BIN"; fail=1; fi
  if model_files_present; then
    ok "Model: $(du -shL "$MODEL_DIR" 2>/dev/null | cut -f1) at $MODEL_DIR"
  else
    err "Model incomplete at $MODEL_DIR"; fail=1
  fi
  if [ -x "$BIN_DIR/qwenserve" ]; then ok "qwenserve: $BIN_DIR/qwenserve"; else err "qwenserve missing"; fail=1; fi
  if [ -x "$BIN_DIR/qwenstop" ]; then ok "qwenstop: $BIN_DIR/qwenstop"; else err "qwenstop missing"; fail=1; fi
  if command -v omp >/dev/null 2>&1; then ok "omp: $(omp --version 2>/dev/null | head -1)"; else warn "omp not installed"; fi
  if grep -q "vllm:" "$MODELS_YML" 2>/dev/null; then ok "omp provider: configured"; else warn "omp provider not configured"; fi
  if [ -f "$UNIT_FILE" ]; then
    ok "systemd unit: $UNIT_FILE ($(systemctl --user is-enabled $SERVICE_NAME 2>/dev/null || echo unknown))"
  fi
  if curl -fsS --max-time 3 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
    ok "Server: responding on port $PORT"
  else
    info "Server: not running (start with 'qwenserve' or 'systemctl --user start $SERVICE_NAME')"
  fi
  return $fail
}

# ── uninstall ────────────────────────────────────────────────────────────────

uninstall() {
  info "Uninstalling"
  if command -v systemctl >/dev/null 2>&1 && [ -f "$UNIT_FILE" ]; then
    run systemctl --user stop "$SERVICE_NAME" || true
    run systemctl --user disable "$SERVICE_NAME" || true
    run rm -f "$UNIT_FILE"
    run systemctl --user daemon-reload || true
    ok "Service removed"
  fi
  # stop a nohup/manual server so GPUs are freed
  if [ "$DRY_RUN" -eq 0 ]; then
    pkill -TERM -f "vllm serve.*$MODEL_DIR" 2>/dev/null || true
  fi
  for f in qwenserve qwenstop; do
    if [ -f "$BIN_DIR/$f" ]; then run rm -f "$BIN_DIR/$f"; ok "$f removed"; fi
  done
  if grep -q "vllm:" "$MODELS_YML" 2>/dev/null && [ "$DRY_RUN" -eq 0 ]; then
    local rm_msg
    rm_msg=$(MODELS_YML_PATH="$MODELS_YML" python3 - <<'PY'
import os, shutil, time
path = os.environ["MODELS_YML_PATH"]
with open(path) as fh:
    lines = fh.read().splitlines(keepends=True)
out = []
i = 0
while i < len(lines):
    if lines[i].startswith("  vllm:") and not lines[i].startswith("   "):
        i += 1
        while i < len(lines) and (lines[i].startswith("    ") or lines[i].strip() == ""):
            i += 1
        continue
    out.append(lines[i]); i += 1
shutil.copy2(path, f"{path}.bak.{time.strftime('%Y%m%d%H%M%S')}")
with open(path, "w") as fh:
    fh.write("".join(out))
print("models.yml: vllm provider removed")
PY
)
    info "$rm_msg"
    ok "omp provider entry removed"
  fi
  if [ "$PURGE" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then info "[dry-run] delete $DATA_ROOT"; else
      warn "Deleting $DATA_ROOT (venv + $(du -shL "$MODEL_DIR" 2>/dev/null | cut -f1 || echo '?') of weights)"
      rm -rf "$DATA_ROOT"
      ok "Data root purged"
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
  if [ "$UNINSTALL" -eq 1 ]; then uninstall; exit 0; fi

  acquire_lock
  preflight

  ensure_uv
  ensure_vllm
  download_model
  install_fp8_configs
  install_qwenserve
  [ "$WITH_SERVICE" -eq 1 ] && install_service
  if ensure_omp; then configure_omp_provider; fi
  [ "$DO_START" -eq 1 ] && smoke_test

  # Final summary
  local lines=(
    "vLLM:     $([ -x "$VLLM_BIN" ] && "$VLLM_BIN" --version 2>/dev/null || echo 'not installed')"
    "Model:    $MODEL_DIR"
    "Launcher: $BIN_DIR/qwenserve  (port $PORT, TP=$TP_DEFAULT, FP8 KV, MTP, 160K ctx)"
    "Stop:     $BIN_DIR/qwenstop   (frees VRAM, GPUs back to idle power)"
    "omp:      vllm/$SERVED_NAME via $MODELS_YML"
  )
  [ "$WITH_SERVICE" -eq 1 ] && lines+=("Service:  systemctl --user start $SERVICE_NAME")
  lines+=("" \
    "Start the server:   qwenserve" \
    "Stop the server:    qwenstop" \
    "Use it in omp:      omp --model vllm/$SERVED_NAME" \
    "Uninstall:          $0 --uninstall   (add --purge to delete weights)")
  draw_box "0;32" "${lines[@]+"${lines[@]}"}"
  if [ "$DO_START" -eq 0 ]; then
    warn "First 'qwenserve' launch compiles kernels once (~10-20 min). Later starts take ~2-5 min (cached)."
  fi
}

main
