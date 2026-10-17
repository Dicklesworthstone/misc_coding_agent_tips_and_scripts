#!/usr/bin/env bash
# Exercise the real model-download functions without GPU setup or large downloads.
# Callbacks and state below are consumed by the dynamically loaded functions.
# shellcheck disable=SC2034,SC2329
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${1:-$ROOT/install-qwen38-uncensored.sh}"
FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/qwen-download-test.XXXXXX")"
fail=0

# Load functions without argument processing, locks, installation, or main.
# Match the literal source guard; expanding it here would defeat the check.
# shellcheck disable=SC2016
if ! grep -Fq 'if [ "${QWEN_INSTALLER_LIB:-0}" != 1 ]; then' "$INSTALLER"; then
  echo 'Refusing to source an installer without the library-mode guard' >&2
  exit 2
fi
# shellcheck disable=SC1090
QWEN_INSTALLER_LIB=1 source "$INSTALLER"
set +e

info() { :; }
ok() { :; }
err() { printf '%s\n' "$*" >&2; }

write_model_files() {
  python3 - "$MODEL_DIR" <<'PY'
import json, struct, sys
from pathlib import Path
root = Path(sys.argv[1]); root.mkdir(parents=True, exist_ok=True)
(root / 'config.json').write_text('{"model_type":"fixture"}')
(root / 'tokenizer.json').write_text('{"version":"1.0"}')
weight_map = {}
for i in (1, 2):
    name = f'model-{i:05}-of-00002.safetensors'
    tensor = f'weight_{i}'
    header = json.dumps({tensor: {'dtype':'F32', 'shape':[1], 'data_offsets':[0,4]}}).encode()
    (root / name).write_bytes(struct.pack('<Q', len(header)) + header + b'\0' * 4)
    weight_map[tensor] = name
(root / 'model.safetensors.index.json').write_text(json.dumps({'weight_map':weight_map}))
PY
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

check_case() {
  local label="$1"; shift
  local output rc
  output=$( (set -e; "$@") 2>&1 ); rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "ok   $label"
  else
    echo "FAIL $label (exit $rc): $output"
    fail=1
  fi
}

check_args() {
  local rc argument
  for argument in --unknown --purge; do
    rc=0; bash "$INSTALLER" "$argument" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 2 ] || return 1
  done
  for argument in 0 65536 invalid '8000;echo bad'; do
    rc=0; bash "$INSTALLER" --port "$argument" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 2 ] || return 1
  done
  rc=0; bash "$INSTALLER" --hf --modelscope >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ]
}

check_partial_shards() {
  MODEL_DIR="$FIXTURES/partial-shards"
  write_model_files
  model_files_present
  python3 - "$MODEL_DIR" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]); (root/'model-00002-of-00002.safetensors').rename(root/'retained-shard')
PY
  if model_files_present; then return 1; fi
  UV_LOG="$FIXTURES/partial-uv.log" DOWNLOAD_MODE=complete SOURCE=modelscope DRY_RUN=0
  download_model
  [ -s "$UV_LOG" ]
}

check_bad_shards() {
  MODEL_DIR="$FIXTURES/truncated-shards"
  write_model_files
  python3 - "$MODEL_DIR" <<'PY'
from pathlib import Path
import sys
with (Path(sys.argv[1])/'model-00002-of-00002.safetensors').open('r+b') as stream: stream.truncate(10)
PY
  if model_files_present; then return 1; fi
}

check_json_and_paths() {
  MODEL_DIR="$FIXTURES/invalid-json"
  write_model_files
  printf '{broken' > "$MODEL_DIR/tokenizer.json"
  if model_files_present; then return 1; fi
  write_model_files
  printf '{"weight_map":{"weight_1":"../outside.safetensors"}}' > "$MODEL_DIR/model.safetensors.index.json"
  if model_files_present; then return 1; fi
}

check_read_only() {
  DATA_ROOT="$FIXTURES/not-created/deep/root"
  BIN_DIR="$FIXTURES/not-created/bin"
  MODEL_DIR="$DATA_ROOT/models/fixture"
  DRY_RUN=1
  df() {
    [ "$1" = -Pk ] && [ -d "$2" ] || return 1
    printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfixture 209715200 0 209715200 0%% /\n'
  }
  acquire_lock
  check_disk_space
  [ ! -e "$FIXTURES/not-created" ]
}

check_lock_contender() {
  BIN_DIR="$FIXTURES/lock-contender/bin"
  mkdir -p "$BIN_DIR/.qwenserve-install.lock"
  printf '%s\n' "$BASHPID" > "$BIN_DIR/.qwenserve-install.lock/pid"
  DRY_RUN=0 LOCK_DIR="" LOCK_OWNER=""
  if acquire_lock; then return 1; fi
  cleanup
  [ -s "$BIN_DIR/.qwenserve-install.lock/pid" ]
}

prepare_launchers() {
  BIN_DIR="$FIXTURES/generated/bin"
  MODEL_DIR="$FIXTURES/generated/model with spaces and \"quotes\" and \$dollar"
  VENV_DIR="$FIXTURES/generated/venv"
  VLLM_BIN="$VENV_DIR/bin/vllm"
  PORT=8001 TP_DEFAULT=2 SERVICE_NAME=qwenserve DRY_RUN=0 FORCE=0
  mkdir -p "$(dirname "$VLLM_BIN")" "$MODEL_DIR"
  cat > "$VLLM_BIN" <<'STUB'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ['ARGV_LOG'], 'w') as stream:
    json.dump({'argv':sys.argv[1:], 'model_tag':os.environ.get('QWENSERVE_MODEL_DIR'), 'leaked_vllm_bin':'VLLM_BIN' in os.environ, 'cuda_home':os.environ.get('CUDA_HOME')},stream)
STUB
  chmod 0755 "$VLLM_BIN"
  mkdir -p "$VENV_DIR/metadata/torch" "$VENV_DIR/metadata/torch-0.0.dist-info"
  printf 'Name: torch\nVersion: 0.0\n' > "$VENV_DIR/metadata/torch-0.0.dist-info/METADATA"
  printf 'cuda = "13.0"\n' > "$VENV_DIR/metadata/torch/version.py"
  printf '#!/bin/bash\nexport PYTHONPATH=%q\nexec %q "$@"\n' "$VENV_DIR/metadata" "$(command -v python3)" > "$VENV_DIR/bin/python"
  chmod 0755 "$VENV_DIR/bin/python"
  local cuda="$FIXTURES/cuda"
  mkdir -p "$cuda/bin" "$cuda/include" "$cuda/lib64"
  : > "$cuda/include/cuda_runtime.h"
  : > "$cuda/lib64/libcudart.so"
  # The generated compiler must receive its own arguments.
  # shellcheck disable=SC2016
  printf '#!/bin/bash\ncase "$1" in --version) echo "release 13.3,";; --help) echo --compress-mode;; esac\n' > "$cuda/bin/nvcc"
  chmod 0755 "$cuda/bin/nvcc"
  install_qwenserve
}

check_generated_commands() {
  prepare_launchers
  bash -n "$BIN_DIR/qwenserve"
  python3 - "$BIN_DIR/qwenstop" <<'PY'
from pathlib import Path
import sys
compile(Path(sys.argv[1]).read_text(), sys.argv[1], 'exec')
PY
  local before
  before=$(stat -c '%i' "$BIN_DIR/qwenserve")
  install_qwenserve
  [ "$(stat -c '%i' "$BIN_DIR/qwenserve")" = "$before" ]
  PORT=8002
  install_qwenserve
  [ "$(stat -c '%i' "$BIN_DIR/qwenserve")" != "$before" ]
  python3 - "$BIN_DIR/qwenserve" "$VLLM_BIN" "$MODEL_DIR" "$FIXTURES/generated" "$FIXTURES/cuda" <<'PY'
import json, os, socket, subprocess, sys
from pathlib import Path
launcher,vllm,model,work,cuda=sys.argv[1:]
log=Path(work)/'argv.json'
env=dict(os.environ, ARGV_LOG=str(log))
env['CUDA_HOME']=cuda; env.pop('FLASHINFER_NVCC',None)
env['VLLM_BIN']=vllm; env.pop('QWEN_MODEL_DIR',None); env.pop('QWEN_PORT',None)
with socket.socket() as sock:
    sock.bind(('127.0.0.1',0)); occupied=sock.getsockname()[1]
    env['QWEN_PORT']=str(occupied)
    rejected=subprocess.run([launcher],env=env,capture_output=True,text=True,timeout=10)
    assert rejected.returncode != 0 and not log.exists(), rejected
    assert 'update the OMP vllm baseUrl' in rejected.stderr
env['QWEN_PORT']='0'
assert subprocess.run([launcher],env=env,capture_output=True,timeout=10).returncode != 0
with socket.socket() as sock:
    sock.bind(('127.0.0.1',0)); free=sock.getsockname()[1]
env['QWEN_PORT']=str(free)
result=subprocess.run([launcher],env=env,capture_output=True,text=True,timeout=10)
assert result.returncode == 0, result.stderr
captured=json.loads(log.read_text())
assert captured['argv'][:2]==['serve',model]
assert captured['argv'][captured['argv'].index('--port')+1]==str(free)
assert captured['argv'][captured['argv'].index('--host')+1]=='127.0.0.1'
assert captured['model_tag']==os.path.realpath(model)
assert not captured['leaked_vllm_bin']
assert captured['cuda_home']==cuda
PY
}

check_cuda_selection() {
  prepare_launchers
  local cuda="$FIXTURES/cuda" rc=0 selected
  selected=$(CUDA_HOME="$cuda" select_cuda_toolkit "$VENV_DIR/bin/python") || return 1
  [ "$selected" = "$cuda" ] || return 1
  printf '#!/bin/bash\necho "release 12.4,"\n' > "$cuda/bin/nvcc"
  CUDA_HOME="$cuda" select_cuda_toolkit "$VENV_DIR/bin/python" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || return 1
  # shellcheck disable=SC2016
  printf '#!/bin/bash\ncase "$1" in --version) echo "release 13.3,";; --help) echo unsupported;; esac\n' > "$cuda/bin/nvcc"
  rc=0
  CUDA_HOME="$cuda" select_cuda_toolkit "$VENV_DIR/bin/python" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || return 1
  # The launcher must refuse the compiler before it invokes vLLM.
  python3 - "$BIN_DIR/qwenserve" "$cuda" <<'PY'
import os, socket, subprocess, sys
with socket.socket() as sock:
    sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
env = dict(os.environ, CUDA_HOME=sys.argv[2], QWEN_PORT=str(port))
env.pop('FLASHINFER_NVCC', None)
result = subprocess.run([sys.argv[1]], env=env, capture_output=True, text=True, timeout=10)
assert result.returncode != 0 and 'CUDA preflight failed' in result.stderr, result
PY
}

check_stop_ownership() {
  prepare_launchers
  python3 - "$BIN_DIR/qwenstop" "$MODEL_DIR" "$FIXTURES/proc" <<'PY'
import os, runpy, signal, sys
from pathlib import Path
from unittest.mock import patch
script,model,root=sys.argv[1:]; root=Path(root); root.mkdir()
namespace=runpy.run_path(script,run_name='test')
def record(pid,parent,argv,env=b''):
    path=root/str(pid); path.mkdir()
    fields=['S',str(parent)]+['0']*17+['100']
    (path/'stat').write_text(f'{pid} (fixture) '+' '.join(fields))
    (path/'cmdline').write_bytes(b'\0'.join(os.fsencode(arg) for arg in argv)+b'\0')
    (path/'environ').write_bytes(env)
record(101,1,['python','/venv/bin/vllm','serve',model])
record(102,101,['VLLM::Worker'])
record(103,1,['VLLM::Worker'],b'QWENSERVE_MODEL_DIR='+os.fsencode(os.path.realpath(model))+b'\0')
record(104,1,['python','/venv/bin/vllm','serve',model+'-other'])
record(105,104,['VLLM::Worker'])
record(106,1,['python','/venv/bin/unrelated-job'])
with patch.dict(os.environ,{'QWEN_MODEL_DIR':model}):
    selected=namespace['owned_processes'](root)
assert set(selected)=={101,102,103}, selected
globals_=namespace['send_signal'].__globals__
sent=[]
with patch.object(os,'pidfd_open',return_value=999), patch.object(os,'close'), \
     patch.object(signal,'pidfd_send_signal',side_effect=lambda *args:sent.append(args)):
    with patch.dict(globals_,{'process_record':lambda pid:{'start':'reused'}}):
        namespace['send_signal']({'pid':101,'start':'100'},signal.SIGTERM)
    assert not sent, sent
    with patch.dict(globals_,{'process_record':lambda pid:{'start':'100'}}):
        namespace['send_signal']({'pid':101,'start':'100'},signal.SIGTERM)
    assert sent==[(999,signal.SIGTERM)], sent
PY
}

check_provider_merge() {
  OMP_AGENT_DIR="$FIXTURES/provider"
  MODELS_YML="$OMP_AGENT_DIR/models.yml"
  VENV_PY="$(command -v python3)" PORT=8001 DRY_RUN=0
  mkdir -p "$OMP_AGENT_DIR"
  cat > "$MODELS_YML" <<'YAML'
models:
  vllm:
    keep: untouched
providers:
  other:
    baseUrl: https://example.invalid/v1
  vllm:
    baseUrl: http://127.0.0.1:8000/v1
    auth: none
    custom: preserve
YAML
  configure_omp_provider
  python3 - "$MODELS_YML" <<'PY'
import sys,yaml
from pathlib import Path
data=yaml.safe_load(Path(sys.argv[1]).read_text())
assert data['models']['vllm']=={'keep':'untouched'}
assert data['providers']['vllm']=={'baseUrl':'http://127.0.0.1:8001/v1','auth':'none','custom':'preserve'}
assert data['providers']['other']=={'baseUrl':'https://example.invalid/v1'}
PY
  local before
  before=$(stat -c '%i' "$MODELS_YML")
  configure_omp_provider
  [ "$(stat -c '%i' "$MODELS_YML")" = "$before" ]
}

check_saved_port() {
  DATA_ROOT="$FIXTURES/saved-settings"
  PORT=8001 PORT_EXPLICIT=1 TP_DEFAULT=2 DRY_RUN=0
  configure_paths
  record_installation
  PORT=8000 PORT_EXPLICIT=0
  configure_paths
  [ "$PORT" -eq 8001 ]
  PORT=8002 PORT_EXPLICIT=1
  configure_paths
  [ "$PORT" -eq 8002 ]
}

check_uninstall_scope() {
  DATA_ROOT="$FIXTURES/uninstall"
  BIN_DIR="$DATA_ROOT/bin"
  MODEL_DIR="$DATA_ROOT/models/fixture"
  VENV_DIR="$DATA_ROOT/venv"
  VENV_PY="$(command -v python3)"
  MODELS_YML="$DATA_ROOT/models.yml"
  UNIT_FILE="$DATA_ROOT/no-service"
  SERVICE_NAME=qwenserve DRY_RUN=0 PURGE=1
  mkdir -p "$DATA_ROOT"
  cat > "$MODELS_YML" <<'YAML'
models:
  vllm:
    keep: untouched
providers:
  vllm:
    baseUrl: http://127.0.0.1:8001/v1
    auth: none
  other:
    baseUrl: https://example.invalid/v1
YAML
  render_qwenstop() { echo 'pass'; }
  rm() { printf '%s\n' "$@" >> "$DATA_ROOT/removal.log"; }
  uninstall
  python3 - "$DATA_ROOT" <<'PY'
from pathlib import Path
import sys,yaml
root=Path(sys.argv[1]); actual=(root/'removal.log').read_text().splitlines()
assert actual==['-rf','--',str(root/'venv'),str(root/'models/fixture')], actual
config=yaml.safe_load((root/'models.yml').read_text())
assert config['models']['vllm']=={'keep':'untouched'}
assert config['providers']=={'other':{'baseUrl':'https://example.invalid/v1'}}
PY
}

check_smoke_identity() {
  PORT=8001 DRY_RUN=0
  curl() {
    case "$*" in
      */v1/models*) printf '{"data":[{"id":"%s"}]}' "$SERVED_NAME" ;;
      *) printf '{"choices":[{"message":{"content":"WRONG"}}]}' ;;
    esac
  }
  if (smoke_test) >/dev/null 2>&1; then return 1; fi
  curl() { printf '{"data":[{"id":"unrelated-model"}]}'; }
  if server_has_model; then return 1; fi
}

check_service_install() {
  BIN_DIR="$FIXTURES/service bin with % spaces"
  UNIT_FILE="$FIXTURES/units/qwenserve.service"
  SERVICE_NAME=qwenserve MODEL_DIR="$FIXTURES/model" PORT=8001 DRY_RUN=0 FORCE=0
  local reject_enable=0
  systemctl() { if [[ "$*" == *' enable '* ]] && [ "$reject_enable" -eq 1 ]; then return 5; fi; }
  loginctl() { return 1; }
  install_service
  [ "$(stat -c '%a' "$UNIT_FILE")" = 644 ]
  grep -Fq '%%' "$UNIT_FILE"
  reject_enable=1
  if install_service; then return 1; fi
}

check_hf_failure() {
  MODEL_DIR="$FIXTURES/hf-failure"
  SOURCE=hf DRY_RUN=0
  hf_authed() { return 0; }
  hf() { write_model_files; return 17; }
  local rc=0
  download_model || rc=$?
  [ "$rc" -eq 17 ]
}

check_upgrade_failure() {
  prepare_launchers
  VENV_PY="$(command -v python3)" FORCE=1
  vllm_version() { echo 0.31.0; }
  uv() { return 17; }
  local rc=0
  ensure_vllm || rc=$?
  [ "$rc" -eq 17 ]
}

check_unsupported_yaml() {
  OMP_AGENT_DIR="$FIXTURES/unsupported-yaml"
  MODELS_YML="$OMP_AGENT_DIR/models.yml"
  VENV_PY="$(command -v python3)" PORT=8001 DRY_RUN=0
  mkdir -p "$OMP_AGENT_DIR"
  printf 'providers: {vllm: {baseUrl: "http://127.0.0.1:8000/v1"}}\n' > "$MODELS_YML"
  local before rc=0
  before=$(sha256sum "$MODELS_YML")
  configure_omp_provider || rc=$?
  [ "$rc" -eq 1 ] && [ "$(sha256sum "$MODELS_YML")" = "$before" ]
}

check_library_guard() {
  local legacy="$FIXTURES/legacy-installer.sh" rc=0
  printf '#!/bin/bash\necho UNEXPECTED-INSTALL\n' > "$legacy"
  bash "${BASH_SOURCE[0]}" "$legacy" > "$FIXTURES/legacy-output" 2>&1 || rc=$?
  [ "$rc" -eq 2 ] && ! grep -q UNEXPECTED-INSTALL "$FIXTURES/legacy-output"
}

check_verify_failures() {
  prepare_launchers
  VENV_PY="$(command -v python3)"
  MODELS_YML="$FIXTURES/verify-models.yml" UNIT_FILE="$FIXTURES/absent.service"
  printf 'providers:\n  vllm:\n    baseUrl: http://127.0.0.1:8001/v1\n' > "$MODELS_YML"
  nvidia-smi() { echo fixture; }
  vllm_version() { echo 0.31.0; }
  model_files_present() { return 0; }
  server_has_model() { return 1; }
  check_cuda_toolkit() { return 0; }
  local omp_status=0
  omp() { echo omp/fixture; return "$omp_status"; }
  # timeout cannot invoke a shell function, so preserve only that test boundary.
  timeout() { shift; "$@"; }
  verify || return 1
  omp_status=17
  if verify; then return 1; fi
  omp_status=0
  check_cuda_toolkit() { return 17; }
  if verify; then return 1; fi
}

check_verified_bootstrap() {
  local hook="$FIXTURES/bootstrap-hook"
  BIN_DIR="$FIXTURES/bootstrap-bin"
  mkdir -p "$hook" "$BIN_DIR"
  cat > "$hook/sitecustomize.py" <<'PY'
import gzip, hashlib, io, json, os, tarfile, urllib.request, zipfile
binary = b'#!/bin/sh\necho verified-fixture\n'

def fetch(request, timeout):
    url = request.full_url
    uv = 'astral-sh/uv' in url
    repo = 'astral-sh/uv' if uv else 'oven-sh/bun'
    machine = __import__('platform').machine()
    name = (f'uv-{machine}-unknown-linux-gnu.tar.gz' if uv else
            'bun-linux-x64-baseline.zip' if machine == 'x86_64' else 'bun-linux-aarch64.zip')
    stream = io.BytesIO()
    if uv:
        with tarfile.open(fileobj=stream, mode='w') as archive:
            entry = tarfile.TarInfo(name.removesuffix('.tar.gz')+'/uv'); entry.size = len(binary)
            archive.addfile(entry, io.BytesIO(binary))
    else:
        with zipfile.ZipFile(stream, mode='w') as archive:
            archive.writestr(zipfile.ZipInfo(name.removesuffix('.zip')+'/bun'), binary)
    data = gzip.compress(stream.getvalue(), mtime=0) if uv else stream.getvalue()
    if url.endswith('/latest'):
        digest = 'sha256:' + hashlib.sha256(data).hexdigest()
        if os.environ.get('QWEN_BOOTSTRAP_BAD_HASH') == '1': digest = 'sha256:' + '0'*64
        data = json.dumps({'tag_name':'fixture', 'assets':[{'name':name, 'size':len(data), 'digest':digest,
            'browser_download_url':f'https://github.com/{repo}/releases/download/fixture/{name}'}]}).encode()
    return io.BytesIO(data)

urllib.request.urlopen = fetch
PY
  printf 'preserve-existing' > "$BIN_DIR/uv"
  local rc=0
  PYTHONPATH="$hook" QWEN_BOOTSTRAP_BAD_HASH=1 install_bootstrap_binary uv >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && [ "$(cat "$BIN_DIR/uv")" = preserve-existing ] || return 1
  PYTHONPATH="$hook" install_bootstrap_binary uv || return 1
  PYTHONPATH="$hook" install_bootstrap_binary bun || return 1
  [ "$("$BIN_DIR/uv")" = verified-fixture ] && [ "$("$BIN_DIR/bun")" = verified-fixture ]
}

check_case 'invalid options and ports are refused' check_args
check_case 'all indexed shards are required and partial downloads resume' check_partial_shards
check_case 'truncated safetensors are rejected' check_bad_shards
check_case 'invalid JSON and escaping shard paths are rejected' check_json_and_paths
check_case 'dry-run disk checks and locks do not create directories' check_read_only
check_case 'failed lock contender preserves the owner lock' check_lock_contender
check_case 'launchers refresh changed settings and reject occupied ports' check_generated_commands
check_case 'CUDA selection rejects incompatible compilers and missing FlashInfer flags' check_cuda_selection
check_case 'shutdown excludes other models and rejects reused PIDs' check_stop_ownership
check_case 'OMP merge changes only the selected provider and is idempotent' check_provider_merge
check_case 'saved port survives reruns and explicit flags override it' check_saved_port
check_case 'uninstall preserves other sections and purge targets only owned directories' check_uninstall_scope
check_case 'smoke checks reject wrong models and incorrect answers' check_smoke_identity
check_case 'service publication is quoted and enable failures propagate' check_service_install
check_case 'Hugging Face errors cannot be hidden by complete cached shards' check_hf_failure
check_case 'failed upgrades cannot report the previous version as success' check_upgrade_failure
check_case 'unsupported OMP layouts are refused without modifying the file' check_unsupported_yaml
check_case 'test harness refuses legacy installers instead of executing them' check_library_guard
check_case 'diagnostics reject broken OMP and CUDA while allowing a stopped server' check_verify_failures
check_case 'bootstrap verifies release hashes and preserves existing binaries on failure' check_verified_bootstrap

if [ "$fail" -ne 0 ]; then echo "Fixtures: $FIXTURES"; fi
exit "$fail"
