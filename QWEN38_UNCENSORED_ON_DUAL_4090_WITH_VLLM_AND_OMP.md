# Qwen3.8-27B-Uncensored-FP8 on Dual RTX 4090s: vLLM + omp, Tuned

> **TL;DR:** A 27B hybrid-attention (Gated DeltaNet + full attention) vision-language model with a built-in MTP speculative-decoding head fits on two consumer RTX 4090s (2×24 GB) in block-FP8 — with room for a 160K-token context. One idempotent installer sets up a current-driver-compatible vLLM stack, downloads the weights (Hugging Face *or* no-login ModelScope), installs tuned FP8 kernel configs (+87% concurrent throughput, measured), drops two commands (`qwenserve` / `qwenstop`) on your PATH, and registers the server as a provider in omp so you can code against it with `omp --model vllm/Qwen3.8-27B-Uncensored`.

> **Origin story:** This model dropped with no consumer-GPU serving guidance — just an H100/H200 docker line. Getting it onto 2×24 GB cards took a driver upgrade, VRAM budgeting against vLLM's own KV estimator, a research pass on how others tuned the sibling Qwen3.6-27B-FP8 on 4090s, and one deadlocked MTP experiment. This guide is the repeatable, scripted version of all of that.

> ⚠️ **Read before use:** this checkpoint has had its refusal alignment *removed* (abliteration). It will comply with requests the base model refuses. It is for research, red-teaming, and interpretability work — do not expose it to end users without your own moderation layer. Apache 2.0, inherited from Qwen.

## Quick Start

```bash
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/main/install-qwen38-uncensored.sh?$(date +%s)" | bash
```

**What that does by default:** preflights your GPUs/VRAM/driver/disk/network → installs `uv` + latest vLLM into an isolated Python 3.12 venv → downloads the 31 GB weights (ModelScope, no login, unless you're already `hf auth login`'d — it asks first when interactive) → installs tuned sm_89 FP8 kernel configs → installs `qwenserve` + `qwenstop` into `~/.local/bin` → installs omp if missing and registers the server as a keyless `vllm` provider. It does **not** start the server or touch systemd unless you ask. Every step is idempotent — re-run freely; completed steps report "already done — skipping".

**Key options (agent-friendly):** `--dry-run` (print plan, change nothing) · `--verify` (diagnostics only, exit non-zero if broken) · `--start` (launch server + e2e smoke test) · `--with-service` (systemd user unit, auto-start on login) · `--modelscope` / `--hf` (pin download source) · `--quiet` (errors only) · `--uninstall` (add `--purge` to also delete weights) · `--port N` · `--data-root DIR` · `--force` (upgrade vLLM / rewrite scripts).

If port 8000 already hosts another service, choose a free port during installation:

```bash
./install-qwen38-uncensored.sh --hf --port 8001 --data-root /path/to/qwenserve-data
```

This updates both the launcher and OMP's `providers.vllm.baseUrl` to `http://127.0.0.1:8001/v1`. The chosen port is saved under that data root and reused when you re-run with the same `--data-root`; an explicit `--port` overrides it. `qwenserve` defaults to loopback and checks the socket before importing vLLM. Runtime overrides such as `QWEN_PORT=8002 qwenserve` require the OMP URL to be updated to match.

The launcher and stop command are compared against the complete generated content. A changed data root, vLLM path, port, or script body causes a backed-up, atomic update without requiring `--force`. Version reporting reads package metadata instead of repeatedly importing the ML stack. `--dry-run` and `--verify` acquire no install lock and create no temporary directories. Interrupted installs that leave a lock require inspection of `~/.local/bin/.qwenserve-install.lock` before removing it; a competing installer never removes the owner's lock.

When `uv` or Bun is missing, the installer downloads its official GitHub release binary, verifies the release asset's published SHA256 and size, and atomically installs the selected executable with an existing-file backup. It refuses missing hashes, incomplete downloads, and mismatches. These checks trust the publisher's GitHub release metadata over HTTPS; they do not provide an independent signature check. Proxy environment variables are honored for these downloads.

Then:

```bash
qwenserve                    # start the server (first start compiles kernels: ~10-20 min)
omp --model vllm/Qwen3.8-27B-Uncensored   # in another shell: use it
qwenstop                     # stop it; frees VRAM, GPUs drop back to idle power
```

## At a Glance

| What | Where | Purpose |
|:-----|:------|:--------|
| `install-qwen38-uncensored.sh` | this repo | The installer (idempotent, `--dry-run`, `--uninstall`) |
| `qwenserve` | `~/.local/bin` | Start the OpenAI-compatible server with tuned dual-4090 flags |
| `qwenstop` | `~/.local/bin` | Stop it; drains VRAM; prints per-GPU memory/power at idle |
| vLLM venv | `~/.local/share/qwenserve/venv` | Python 3.12 + latest vLLM, isolated |
| Model weights (~31 GB) | `~/.local/share/qwenserve/models/` | Block-FP8 checkpoint from HF or ModelScope |
| omp provider entry | `~/.omp/agent/models.yml` | Keyless `vllm` provider → `http://127.0.0.1:8000/v1` |
| systemd unit (optional) | `~/.config/systemd/user/qwenserve.service` | `--with-service`; starts on login |
| Compile cache | `~/.cache/vllm/torch_compile_cache` | Makes restarts ~2-5 min instead of ~10-20 |

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                           THE STACK                                      ┃
┃                                                                          ┃
┃   omp --model vllm/Qwen3.8-27B-Uncensored                                ┃
┃        │  OpenAI-compatible chat + tools + reasoning                     ┃
┃        ▼                                                                 ┃
┃   vLLM 0.27 server  (qwenserve: port 8000, FP8 KV, MTP draft head)       ┃
┃        │  tensor parallel = 2                                            ┃
┃        ▼                                                                 ┃
┃   GPU 0: ~15 GiB weights + KV  ◄──── PCIe TP allreduce ──►  GPU 1: same  ┃
┃                                                                          ┃
┃   48 linear-attn layers (constant state) + 16 full-attn layers (FP8 KV)  ┃
┃   = 32 KB/token total  →  160K context fits in 48 GB consumer VRAM       ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

---

## Why this model, and why it fits

Qwen3.8-27B is a dense 27B with an unusual layer mix: **48 linear-attention (Gated DeltaNet) layers + 16 full-attention layers** (interval 4), 64 layers total, hidden 5120, plus a native vision tower and an **MTP draft head** for speculative decoding. The OrcaRouter build removes the refusal direction, then re-quantizes to the *byte-identical* block-FP8 scheme of the official Qwen FP8 checkpoint — so it serves on the exact same vLLM kernel path.

The VRAM math that makes dual 4090s work:

| Component | Per GPU (TP=2) | Notes |
|:----------|:---------------|:------|
| Weights (block-FP8) | ~14.8 GiB | 31 GB total, sharded |
| Vision tower + norms + embed (BF16) | included above | not quantized |
| KV cache (FP8) | 32 KB/token ÷ 2 | only the 16 full-attn layers pay per-token KV |
| GDN recurrent state | ~147 MiB/request | constant, not per-token |
| Budget at `--gpu-memory-utilization 0.94` | 22.1 GiB | of 24 GiB |

KV cost is only 32 KB/token because linear-attention layers keep a fixed-size state — that's how a 27B with 64 layers still fits a 160K context on 48 GB of consumer VRAM. The full 262,144-token context needs 4.57 GiB/GPU of KV and vLLM measured 3.18 GiB free at util 0.92 — so the default ships 160K; raise it with `QWEN_MAX_LEN=262144 qwenserve` if you trim elsewhere (`--language-model-only`, lower util won't get you there alone).

## The serving configuration (and why each flag)

`qwenserve` (installed to `~/.local/bin`) is a thin wrapper around `vllm serve` with everything pre-tuned:

```bash
vllm serve <model-dir> \
  --served-model-name Qwen3.8-27B-Uncensored \
  --tensor-parallel-size 2 \        # split across both 4090s
  --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
  --kv-cache-dtype fp8 \            # halves KV memory; sm_89 supports FP8 KV
  --gpu-memory-utilization 0.94 \
  --max-model-len 163840 \          # 160K; see VRAM math above
  --max-num-seqs 64 \
  --trust-remote-code \
  --reasoning-parser qwen3 \        # thinking trace lands in .reasoning, not .content
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder    # OpenAI-style tool calling, incl. multi-turn
```

- **MTP speculative decoding** uses the draft head inside the checkpoint. On the sibling Qwen3.6-27B-FP8, an N-sweep on a 4090 measured N=4 as the all-around sweet spot (short +211%, 10-way concurrent +61%); N≥5 collapses under concurrency. We default to N=3 (most conservative of the winning range — N=4 hit a FlashInfer graph-profiling deadlock once on vLLM 0.27.1/sm_89 and needs a careful retry). Override: `QWEN_SPEC_TOKENS=4 qwenserve`.
- **`--reasoning-parser qwen3` is not optional in practice:** the chat template opens every assistant turn with `<think>`; without the parser the reasoning flood lands in `content` and can eat your whole token budget before the answer starts.
- Do **not** pass `--quantization fp8` — the block-FP8 scheme is read from `config.json`.

## The FP8 kernel config trick (+87% concurrent throughput)

vLLM's w8a8 block-FP8 GEMM uses per-device tuned Triton configs. It ships L40S tunings but none for the RTX 4090 — both are sm_89 (Ada), so the L40S numbers transfer. Without them, startup logs warn `Using default W8A8 Block FP8 kernel config. Performance might be sub-optimal!` for each of the 5 TP-sharded GEMM shapes (linear-attn in_proj, o_proj/out_proj, MLP gate_up, MLP down, full-attn QKV).

The installer copies the same-K L40S configs to RTX_4090 filenames inside the venv. Measured on the reference box (2×4090, TP=2, MTP on):

| Workload | Default configs | With tuned configs |
|:---------|:----------------|:-------------------|
| Single-stream decode (512 tok) | 22–25 tok/s | 24–27 tok/s |
| 8-way concurrent aggregate | 84.6 tok/s | **158 tok/s (+87%)** |

Single-stream is memory-bandwidth-bound so it barely moves; batched GEMMs are where tile configs pay. For the last few percent, run a true autotune sweep (`benchmarks/kernels/benchmark_w8a8_block_fp8.py` in the vLLM repo, patched with the 5 shapes above) — it writes the same filename format into the same directory.

These measurements describe the vLLM 0.27.1 reference configuration. Newer versions can select a different kernel: the 0.31.0 validation run selected `MarlinFP8ScaledMMLinearKernel` on the 4090s. Copying the Triton configs does not prove that the selected backend uses them or that the historical throughput gain applies. Benchmark the running version before making a performance claim.

## Driver and CUDA

The tested vLLM 0.31.0 environment has PyTorch 2.13.0 with a bundled CUDA 13.0 runtime. FlashInfer also compiles attention kernels at startup, so this configuration needs a **full CUDA toolkit**, including `nvcc`, runtime headers, and development libraries. Triton's bundled compiler tools do not replace that requirement.

The installer and launcher check the toolkit against the installed PyTorch wheel without importing PyTorch. They prefer compatible toolkits under `/usr/local/cuda*`, then the compiler on `PATH`. The toolkit must have the same CUDA major version as PyTorch, at least its minor version, and support FlashInfer's `--compress-mode` flag (CUDA 12.8 or newer). An explicit `CUDA_HOME` or `CUDA_PATH` takes precedence and is checked rather than silently replaced. On the tested machine, `/usr/bin/nvcc` was CUDA 12.4 and failed during startup; selecting the existing `/usr/local/cuda-13.3` fixed that compiler selection. This affects the Qwen process only.

Use a driver compatible with your wheel and toolkit. The current machine has driver **595.99.02**. For an explicit toolkit selection:

```bash
CUDA_HOME=/usr/local/cuda-13.3 qwenserve
```

The installer warns if your driver is older than 570 and continues.

## Getting the weights: Hugging Face vs ModelScope

The HF repo is **gated** (account + accept terms). The installer also supports the same model ID on ModelScope, where public models need **no login**. Mirror availability can change: an anonymous 404 means the model or file is missing or private. In that case, use Hugging Face after obtaining access.

```bash
# ModelScope (no login)
uv tool run --isolated --from modelscope-hub \
  modelscope download orcarouter/Qwen3.8-27B-Uncensored-FP8 --local-dir ./Qwen3.8-27B-Uncensored-FP8

# Hugging Face (if you have access)
hf download orcarouter/Qwen3.8-27B-Uncensored-FP8 --local-dir ./Qwen3.8-27B-Uncensored-FP8
```

The installer auto-detects `hf auth login` state and uses HF when present; otherwise it interactively explains the HF signup/gate/token steps and offers ModelScope (the default when non-interactive). Downloads from outside China can be slower on ModelScope — use HF if you have access.

A completed model requires valid core JSON files and every shard named by the safetensors index. The installer checks each shard's tensor names, header offsets, and file length to reject missing files, truncated downloads, Git LFS pointers, and absolute or traversal-based shard filenames. These structural checks do not hash all tensor payloads or prove inference quality.

ModelScope's CLI is supplied by [`modelscope-hub`](https://pypi.org/project/modelscope-hub/), not the umbrella `modelscope` package. The installer runs it through `uv` in isolation, reusing the cached environment on subsequent runs and leaving global commands such as `ms` alone. The current download syntax takes a positional model ID and `--local-dir`.

To skip the source prompt, pass `--modelscope` or `--hf`. With no reply within 120 seconds (or EOF), the prompt defaults to ModelScope; set `QWEN_INSTALL_PROMPT_TIMEOUT` to change the timeout. After an interrupted install, re-run with the same `--data-root` to reuse the vLLM venv and resume the download.

## Using it from omp

omp has a built-in `vllm` provider that discovers models from `/v1/models` (and reads `max_model_len` as the context window). The installer merges this into `~/.omp/agent/models.yml` (with timestamped backups, skipping if already present):

```yaml
providers:
  vllm:
    baseUrl: http://127.0.0.1:8000/v1
    auth: none
```

Then:

```bash
omp --model vllm/Qwen3.8-27B-Uncensored          # direct
omp --model uncensored                            # fuzzy match works too
```

Inside a session, `/model` lists it under **vllm** with thinking levels (low/medium/xhigh). Thinking can also be toggled per request via `chat_template_kwargs`: `{"enable_thinking": false}` answers directly; `{"reasoning_effort": "low"}` is adaptive.

## `qwenserve` and `qwenstop`

Two global commands, installed to `~/.local/bin`:

- **`qwenserve`** — starts the server in the foreground on the configured loopback port (OpenAI-compatible; default 8000). Keep it in a tmux window, or use `--with-service` for a systemd user unit (`systemctl --user start qwenserve`; the installer enables linger so it survives logout). Env knobs: `QWEN_PORT`, `QWEN_HOST`, `QWEN_MODEL_DIR`, `VLLM_BIN`, `QWEN_TP`, `QWEN_MAX_LEN`, `QWEN_GPU_UTIL`, `QWEN_MAX_SEQS`, `QWEN_SPEC_TOKENS`. Set `QWEN_HOST` explicitly if remote access is intended.
- **`qwenstop`** — stops this model's processes: recognizes exact model arguments, inherited ownership tags, and supervised descendants, requests graceful shutdown, then waits up to 90 seconds before escalating against surviving owned processes. Linux pidfds and process start times fence signals against PID reuse. It stops the systemd unit only when its main PID belongs to this model, and reports GPU memory/power afterward. Unrelated models, generic `VLLM::` workers, and other jobs using the same venv are excluded. Older orphan workers with no ownership evidence are left alone.

Why a dedicated stop command: vLLM spawns an API server, an EngineCore, and one worker per GPU — a bare `Ctrl-C` on the wrong process (or killing only the API server) can orphan workers holding ~15 GiB each, and the cards keep burning power. `qwenstop` is a safe no-op when nothing is running.

## What to expect on first start

The first `qwenserve` launch runs `torch.compile` over the 64-layer hybrid graph plus the MTP drafter — **10-20 minutes** of one-time compilation (the shm_broadcast "no available block" log lines during this are benign). Artifacts cache to `~/.cache/vllm/torch_compile_cache`; subsequent starts are ~2-5 minutes. Note the cache key includes the serving config — changing `QWEN_SPEC_TOKENS` or batched-token limits recompiles once.

## Troubleshooting

| Symptom | Cause / fix |
|:--------|:-----------|
| Installer reports a new data root or vLLM version, but `qwenserve` runs an older one | Update and re-run the installer with the intended `--data-root` and `--port`. Generated commands now compare their full content and back up stale versions. |
| `Address already in use` | Another service owns the port. Use `--port 8001` (or another free port) when installing; both the launcher and OMP URL are updated. The launcher checks this before loading vLLM. |
| `No executables are provided by package modelscope` | Update the installer; it must run the CLI from `modelscope-hub`. Use the isolated command above for manual downloads. |
| `ValueError: ... KV cache ... larger than available` | `QWEN_MAX_LEN` too big for your VRAM. vLLM prints the estimated max — use it. |
| 5 tok/s on the very first request | One-time Triton kernel warmup. Second request runs at full speed. |
| `Using default W8A8 Block FP8 kernel config` in logs | Tuned configs missing — re-run the installer (step 4 is idempotent). |
| Startup hangs after "Capturing CUDA graphs" for >30 min | Known once with MTP N=4 on vLLM 0.27.1/sm_89 (FlashInfer graph profiling). `qwenstop`, go back to N=3. |
| omp doesn't list the model | Server must be running (keyless local discovery). Check `omp models find qwen` and `~/.omp/agent/models.yml`. |
| Driver too old for wheels | `sudo apt install nvidia-driver-595-open`, reload modules or reboot. |

## Uninstall

```bash
./install-qwen38-uncensored.sh --uninstall          # scripts + service + omp entry
./install-qwen38-uncensored.sh --uninstall --purge  # also the venv and 31 GB of weights
```

Use the same `--data-root` for uninstalling a custom installation; the install summary prints the complete command. Uninstall refuses to remove a launcher belonging to a different data root, stops owned model processes, removes the commands and service, and removes only `providers.vllm` from `models.yml`, keeping a backup. Weights and the venv are kept unless `--purge`. Purge removes only that venv and model directory, preserving unrelated files, logs, and saved installation settings under the data root.

`--verify` checks the generated commands against the selected installation and verifies the OMP URL matches its port. A responding server must advertise the expected model ID; `--start` additionally requires the requested `QWEN-OK` answer. Configuration checks alone do not certify that the model can load or answer requests.

---

*Reference measurements: 2× RTX 4090 (24 GiB each), driver 595.71.05, CUDA 13.3 toolkit, vLLM 0.27.1, Python 3.12, Ubuntu 25.10.*
