---
name: run-stable-diffusion-webui
description: Run, start, launch, screenshot, or verify stable-diffusion-webui. Drives the Gradio web UI at localhost:7860 using curl smoke tests and a headless Chrome screenshot.
---

# run-stable-diffusion-webui

Stable Diffusion WebUI is a Gradio-based web app (AUTOMATIC1111 v1.10.1).
It is driven headlessly via `curl` + `google-chrome --headless --screenshot`.
All paths below are relative to the repo root (`/home/david1/문서/stable-diffusion-webui-master`).

---

## Prerequisites (one-time)

These were verified working on this machine:

```bash
# Python 3.10 with torch+ROCm is in the comfyui conda env — no GPU install needed
# git must be available
```

Run setup **once** (idempotent):

```bash
.claude/skills/run-stable-diffusion-webui/setup.sh
```

This creates `venv/` (Python 3.10, inherits `torch 2.6.0+rocm6.2` from comfyui env),
installs all requirements, and clones the 5 required repositories into `repositories/`.

---

## Run (agent path) — launch + smoke test + screenshot

```bash
.claude/skills/run-stable-diffusion-webui/smoke.sh
```

- Starts the server (CPU-only, empty test checkpoint — no model download)
- Polls until Gradio responds on port 7860
- Runs 3 curl checks: `GET /`, `GET /queue/status`, `GET /info`
- Takes a screenshot → `/tmp/sdwebui-screenshot.png`
- Kills the server when done

**To leave the server running** after the checks (for interactive use):

```bash
KEEP_RUNNING=1 .claude/skills/run-stable-diffusion-webui/smoke.sh
```

**To use a different port:**

```bash
PORT=7861 .claude/skills/run-stable-diffusion-webui/smoke.sh
```

---

## Run (human path)

```bash
cd /home/david1/문서/stable-diffusion-webui-master
HSA_OVERRIDE_GFX_VERSION=9.0.0 \
  venv/bin/python launch.py \
    --skip-prepare-environment \
    --skip-torch-cuda-test \
    --skip-python-version-check \
    --no-half \
    --use-cpu all \
    --do-not-download-clip \
    --port 7860
# Opens http://127.0.0.1:7860 in browser. Ctrl-C to stop.
# Will download v1-5-pruned-emaonly.safetensors (3.97 GB) on first run without --ckpt.
# To skip the download during testing, add: --ckpt test/test_files/empty.pt
```

---

## What's served

- `http://127.0.0.1:7860/` — Gradio UI (txt2img, img2img, Extras, Settings, Extensions tabs)
- `http://127.0.0.1:7860/queue/status` — queue health
- `http://127.0.0.1:7860/info` — Gradio API info
- REST API (`/sdapi/v1/…`) only works when `--api` flag is passed (see Gotchas)

---

## Gotchas

### `Stability-AI/stablediffusion` is deleted from GitHub
The webui hardcodes `Stability-AI/stablediffusion.git` but that repo no longer
exists. `setup.sh` clones `CompVis/stable-diffusion` instead, which has a
different API. The following compatibility stubs are already committed in this
repo's copy of the `repositories/stable-diffusion-stability-ai/` directory:

| File | What it stubs |
|---|---|
| `ldm/modules/midas/__init__.py` + `api.py` | MiDaS depth model — used only for SD2 depth img2img |
| `ldm/data/util.py` → `AddMiDaS` | Depth preprocessing transform |
| `ldm/models/diffusion/ddpm.py` → `LatentDepth2ImageDiffusion` | SD2 depth model class |
| `ldm/modules/attention.py` → `BasicTransformerBlock.ATTENTION_MODES` | Dict added by Stability AI fork for xformers routing |

**Impact:** depth-guided img2img (SD2 depth model) does not work. Everything
else (txt2img, standard img2img, extras, LoRA, etc.) works normally.

### `--api` flag crashes with newer starlette
```
RuntimeError: Cannot add middleware after an application has started
```
FastAPI 0.94 / starlette 0.26 changed when middleware can be registered.
The webui's `api_middleware()` is called after Gradio already started the ASGI
app. Workaround: **don't pass `--api`**. The built-in Gradio routes
(`/queue/status`, `/info`, the generation queue) still work.

### AMD Renoir iGPU — must set `HSA_OVERRIDE_GFX_VERSION=9.0.0`
Without this env var, PyTorch sees "No HIP GPUs are available" and the
memory monitor errors. Set it in the launch command; `smoke.sh` already does.

### `clip` package fails to build in isolated pip environment
`pip install` for the CLIP zip-archive fails with `ModuleNotFoundError: No module named 'pkg_resources'`
in the isolated build env. Fix: `pip install setuptools` first, then install
with `--no-build-isolation`. `setup.sh` handles this.

### `taming` and `dctorch` are not in `requirements.txt`
The `CompVis/stable-diffusion` repo imports `taming.modules` at load time.
`k-diffusion` imports `dctorch`. Neither is listed in requirements.txt.
`setup.sh` installs `taming-transformers-rom1504` and `dctorch` explicitly.

### Do not re-clone `stable-diffusion-stability-ai` from scratch
The compatibility patches in `repositories/stable-diffusion-stability-ai/`
are not in any git repo — they are local modifications. If you delete and
re-clone, you must re-apply the stubs listed in the table above.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `AssertionError: Couldn't find Stable Diffusion in any of: [...]` | The `repositories/stable-diffusion-stability-ai/` dir is missing. Run `setup.sh`. |
| `ModuleNotFoundError: No module named 'ldm.modules.midas'` | Stubs weren't applied. Check that `ldm/modules/midas/` exists inside `repositories/stable-diffusion-stability-ai/`. |
| `ModuleNotFoundError: No module named 'taming'` | Run: `venv/bin/pip install taming-transformers-rom1504` |
| `ModuleNotFoundError: No module named 'dctorch'` | Run: `venv/bin/pip install dctorch` |
| `AttributeError: type object 'BasicTransformerBlock' has no attribute 'ATTENTION_MODES'` | The `ATTENTION_MODES = {}` patch is missing from `ldm/modules/attention.py`. Check the class definition. |
| `RuntimeError: Cannot add middleware after an application has started` | Remove `--api` from launch args. |
| `Downloading: "https://huggingface.co/.../v1-5-pruned-emaonly.safetensors"` (3.97 GB) | Add `--ckpt test/test_files/empty.pt` to skip the download during testing. |
| Server starts but screenshot is just `Loading...` | The `--virtual-time-budget` wasn't long enough. Increase it or wait for `/queue/status` to respond first. |
