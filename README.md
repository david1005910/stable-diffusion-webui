# Stable Diffusion WebUI — AMD Renoir fork

> Fork of [AUTOMATIC1111/stable-diffusion-webui](https://github.com/AUTOMATIC1111/stable-diffusion-webui) **v1.10.1**  
> Adds compatibility patches for AMD Renoir/Cezanne iGPU and a one-command run skill for headless environments.

![WebUI screenshot](.claude/skills/run-stable-diffusion-webui/screenshot.png)

---

## What this fork adds

| Change | Why |
|---|---|
| `webui-user.sh` — bootstraps venv, sets AMD env vars and launch flags | `./webui.sh` works out of the box with no extra steps |
| `venv` created with `--system-site-packages` from the `comfyui` conda env (Python 3.10 + `torch 2.6.0+rocm6.2`) | Reuses an existing ROCm-enabled PyTorch — no CUDA required, no 2 GB download |
| `repositories/stable-diffusion-stability-ai` — cloned from `CompVis/stable-diffusion` with compatibility stubs | `Stability-AI/stablediffusion` was deleted from GitHub; these stubs fill in the missing API surface |
| `.claude/skills/run-stable-diffusion-webui/` — `setup.sh` + `smoke.sh` | One-command environment setup and headless smoke test |

### Compatibility stubs (for the deleted Stability-AI/stablediffusion repo)

The webui expects `Stability-AI/stablediffusion` (their SD2 fork) which no longer exists. The `CompVis/stable-diffusion` repo is used instead, with the following stubs committed directly into `repositories/stable-diffusion-stability-ai/`:

| File | Stubs |
|---|---|
| `ldm/modules/midas/__init__.py` + `api.py` | MiDaS depth estimation API (`ISL_PATHS`, `load_model`) |
| `ldm/data/util.py` | `AddMiDaS` preprocessing transform |
| `ldm/models/diffusion/ddpm.py` | `LatentDepth2ImageDiffusion`, `LatentInpaintDiffusion` |
| `ldm/modules/attention.py` | `ATTENTION_MODES` dict on `BasicTransformerBlock` |

**Impact:** depth-guided img2img (SD2 depth model) is not available. Everything else — txt2img, standard img2img, LoRA, extras, extensions — works normally.

---

## Hardware

- **CPU:** AMD Cezanne (Ryzen 5000 series)
- **GPU:** AMD Renoir/Cezanne integrated GPU (Radeon Vega, `HSA_OVERRIDE_GFX_VERSION=9.0.0`)
- **PyTorch:** `2.6.0.dev+rocm6.2` (ROCm 6.2, from the `comfyui` conda env)
- Runs **CPU-only** for testing; set `HSA_OVERRIDE_GFX_VERSION=9.0.0` for ROCm

---

## Quick start

### 1. Prerequisites

- The `comfyui` conda environment must exist at `/home/david1/anaconda3/envs/comfyui` — it provides Python 3.10 and `torch 2.6.0+rocm6.2`.
- `git` must be on `PATH`.

No other setup is needed before the first run.

### 2. Run

```bash
./webui.sh
```

That's it. On first run, `webui-user.sh` automatically:
1. Creates `venv/` with `--system-site-packages` (inherits torch from the comfyui env — no download)
2. Clones the five required repositories into `repositories/`
3. Installs remaining Python dependencies into the venv

On subsequent runs the venv and repos already exist, so startup takes only a few seconds.

Open **http://127.0.0.1:7860** in your browser. On first run without a model it will download `v1-5-pruned-emaonly.safetensors` (~4 GB). To skip that during testing:

```bash
./webui.sh --ckpt test/test_files/empty.pt
```

### 3. Smoke test (headless)

```bash
bash .claude/skills/run-stable-diffusion-webui/smoke.sh
# Curl checks + screenshot → /tmp/sdwebui-screenshot.png
```

Launches with the empty test checkpoint, runs three curl checks, saves a headless Chrome screenshot, then shuts the server down.

---

## Known issues

- **`--api` flag crashes** — FastAPI 0.94 + starlette 0.26 raise `RuntimeError: Cannot add middleware after an application has started`. Don't pass `--api`; the Gradio queue and info routes still work.
- **Depth-guided img2img** — Not available (see stub table above).
- **`xformers` not installed** — Not needed for CPU/ROCm; the webui falls back to standard attention automatically.

---

## Original project

All credit for the webui itself goes to [AUTOMATIC1111](https://github.com/AUTOMATIC1111/stable-diffusion-webui) and its contributors.  
This fork only adds environment-specific patches and tooling; it does not modify any generation logic.

For upstream features, installation on other platforms, and the full wiki, see:  
➜ https://github.com/AUTOMATIC1111/stable-diffusion-webui
