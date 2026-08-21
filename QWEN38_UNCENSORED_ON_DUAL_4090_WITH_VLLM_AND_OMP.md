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

## Driver and CUDA

vLLM 0.27 wheels bundle a CUDA 13.0 runtime. You want a recent driver — the reference box runs **595.71.05** (`nvidia-driver-595-open` on Ubuntu 25.10, hot-swapped without reboot: no display manager + no GPU processes → `modprobe -r nvidia_drm nvidia_uvm nvidia_modeset nvidia && modprobe nvidia`). A system CUDA toolkit is optional (Triton ships its own ptxas); `cuda-toolkit-13-3` from NVIDIA's repo is the current latest if you want nvcc around.

The installer warns if your driver is older than 570 and continues.

## Getting the weights: Hugging Face vs ModelScope

The HF repo is **gated** (account + accept terms). The same weights are mirrored on ModelScope with **no login**:

```bash
# ModelScope (no login)
modelscope download --model orcarouter/Qwen3.8-27B-Uncensored-FP8 --local_dir ./Qwen3.8-27B-Uncensored-FP8

# Hugging Face (if you have access)
hf download orcarouter/Qwen3.8-27B-Uncensored-FP8 --local-dir ./Qwen3.8-27B-Uncensored-FP8
```

The installer auto-detects `hf auth login` state and uses HF when present; otherwise it interactively explains the HF signup/gate/token steps and offers ModelScope (the default when non-interactive). Downloads from outside China can be slower on ModelScope — use HF if you have access.

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

- **`qwenserve`** — starts the server in the foreground on `http://127.0.0.1:8000` (OpenAI-compatible). Keep it in a tmux window, or use `--with-service` for a systemd user unit (`systemctl --user start qwenserve`; the installer enables linger so it survives logout). Env knobs: `QWEN_PORT`, `QWEN_TP`, `QWEN_MAX_LEN`, `QWEN_GPU_UTIL`, `QWEN_MAX_SEQS`, `QWEN_SPEC_TOKENS`.
- **`qwenstop`** — stops it cleanly: stops the systemd unit if that's how it runs, `SIGTERM`s any `vllm serve` for this model however launched, waits up to 90s for VRAM to drain (SIGKILLing only leftover vLLM pids — never unrelated GPU processes), then prints per-GPU memory/power so you can watch the cards fall back to idle (~10-20 W from ~150 W under load).

Why a dedicated stop command: vLLM spawns an API server, an EngineCore, and one worker per GPU — a bare `Ctrl-C` on the wrong process (or killing only the API server) can orphan workers holding ~15 GiB each, and the cards keep burning power. `qwenstop` is a safe no-op when nothing is running.

## What to expect on first start

The first `qwenserve` launch runs `torch.compile` over the 64-layer hybrid graph plus the MTP drafter — **10-20 minutes** of one-time compilation (the shm_broadcast "no available block" log lines during this are benign). Artifacts cache to `~/.cache/vllm/torch_compile_cache`; subsequent starts are ~2-5 minutes. Note the cache key includes the serving config — changing `QWEN_SPEC_TOKENS` or batched-token limits recompiles once.

## Troubleshooting

| Symptom | Cause / fix |
|:--------|:-----------|
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

The uninstall stops a running server first (freeing the GPUs), removes `qwenserve`/`qwenstop`, removes the systemd unit, and removes the `vllm` block from `models.yml` (timestamped backup kept). Weights and the venv are kept unless `--purge`.

---

*Reference measurements: 2× RTX 4090 (24 GiB each), driver 595.71.05, CUDA 13.3 toolkit, vLLM 0.27.1, Python 3.12, Ubuntu 25.10.*
