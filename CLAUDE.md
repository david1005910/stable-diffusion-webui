# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## First-time Setup

On a fresh machine, run the setup script once before `./webui.sh`:

```bash
bash .claude/skills/run-stable-diffusion-webui/setup.sh
```

This script (idempotent, safe to re-run):
1. Creates `venv/` with `--system-site-packages` from the `comfyui` conda env at `/home/david1/anaconda3/envs/comfyui` (Python 3.10 + `torch 2.6.0+rocm6.2` — no PyTorch download)
2. Installs CLIP, taming-transformers, dctorch, `requirements.txt`, and pins `gradio-client==0.5.0`, `pydantic<2`, and `transformers==4.30.2` (see **Known Limitations**)
3. Clones five repositories into `repositories/`:
   - `stable-diffusion-stability-ai` — CompVis/stable-diffusion (SD1/SD2 LDM core)
   - `generative-models` — Stability-AI/generative-models (SDXL)
   - `k-diffusion` — crowsonkb/k-diffusion (DPM/Karras samplers)
   - `BLIP` — salesforce/BLIP (image interrogation)
   - `stable-diffusion-webui-assets` — AUTOMATIC1111/stable-diffusion-webui-assets (fonts/etc.)
4. Applies four compatibility patch groups to the CompVis repo (see **Compatibility Stubs** below)

Set `SKIP_VENV=1` to skip steps 1–2 (venv/pip) and only perform steps 3–4 — used when Pinokio manages its own venv:

```bash
SKIP_VENV=1 bash .claude/skills/run-stable-diffusion-webui/setup.sh
```

## Running the Application

```bash
# Standard launch (venv + repos assumed present after setup.sh)
./webui.sh

# Skip the 4 GB model download during development/testing
./webui.sh --ckpt test/test_files/empty.pt

# Windows
webui.bat

# API-only mode (no Gradio UI)
./webui.sh --nowebui
```

**This fork's `webui-user.sh`** configures the environment for AMD Renoir/Cezanne iGPU:
- Bootstraps `venv/` with `--system-site-packages` on first run (inherits `torch 2.6.0+rocm6.2` from the `comfyui` conda env — no PyTorch download needed)
- Exports `HSA_OVERRIDE_GFX_VERSION=9.0.0` (required for AMD Renoir ROCm recognition)
- Passes `--skip-prepare-environment --no-half --skip-torch-cuda-test --skip-python-version-check --do-not-download-clip` automatically
- Sets `TORCH_COMMAND="echo '...skipping'"` — prevents `launch.py` from downloading a 2 GB PyTorch wheel if `--skip-prepare-environment` is ever removed
- Sets `STABLE_DIFFUSION_REPO` / `STABLE_DIFFUSION_COMMIT_HASH` — redirect `launch.py`'s git-fetch from the deleted Stability AI repo to the CompVis substitute

Set `WEBUI_LAUNCH_LIVE_OUTPUT=1` to print subprocess output live (useful when debugging launch_utils dependency installation).

Key CLI flags in `modules/cmd_args.py`: `--lowvram`/`--medvram` (VRAM optimization), `--share` (Gradio public link), `--listen` (bind to all interfaces), `--port` (default 7860).

CLI flags can also be passed via the `COMMANDLINE_ARGS` environment variable (parsed in `modules/paths_internal.py`), which is how `webui-user.sh` appends the AMD/ROCm flags without editing `webui.sh`.

## Smoke Test

```bash
# Launch with empty checkpoint, run curl checks, take screenshot, then shut down
bash .claude/skills/run-stable-diffusion-webui/smoke.sh

# Leave the server running after checks (useful during development)
KEEP_RUNNING=1 bash .claude/skills/run-stable-diffusion-webui/smoke.sh

# Use a different port
PORT=7861 bash .claude/skills/run-stable-diffusion-webui/smoke.sh
```

Output: `/tmp/sdwebui-smoke.log` (server log) and `/tmp/sdwebui-screenshot.png`.

## Linting

```bash
# Python — Ruff (configured in pyproject.toml)
ruff check .
ruff check --fix .

# JavaScript — ESLint (configured in .eslintrc.js)
npm run lint
npm run fix
```

Ruff ignores E501, E721, E731, I001, C901, C408, W605. The `extensions/` and `extensions-disabled/` directories are excluded from linting.

## Testing

Tests require a running server. The CI workflow starts the server first, then runs pytest against it:

```bash
# 1. Install test dependencies
pip install wait-for-it -r requirements-test.txt

# 2. Set up environment (downloads dependencies)
python launch.py --skip-torch-cuda-test --exit

# 3. Start test server in background
python launch.py --skip-prepare-environment --skip-torch-cuda-test --test-server \
    --do-not-download-clip --no-half --disable-opt-split-attention --use-cpu all --api-server-stop &

# 4. Wait for server and run tests
wait-for-it --service 127.0.0.1:7860 -t 20
python -m pytest -vv --junitxml=test/results.xml --cov . --cov-report=xml --verify-base-url test

# Run a single test file
python -m pytest test/test_txt2img.py -vv --verify-base-url

# Stop test server
curl -XPOST http://127.0.0.1:7860/sdapi/v1/server-stop
```

The pytest base URL is `http://127.0.0.1:7860` (configured in `pyproject.toml`). Python 3.10.6 is the recommended version.

When importing `webui` outside a server context (e.g., in new test files), set `IGNORE_CMD_ARGS_ERRORS=1` first — `conftest.py` does this automatically for the existing tests via `pytest_configure`.

## Models Directory

Place model files under `models/` before launching:

| Subdirectory | Content |
|---|---|
| `models/Stable-diffusion/` | Checkpoint files (`.ckpt`, `.safetensors`) |
| `models/VAE/` | VAE weights |
| `models/Lora/` | LoRA / LyCORIS weights |
| `models/hypernetworks/` | Hypernetwork weights |
| `models/embeddings/` (alias: `embeddings/`) | Textual inversion embeddings |
| `models/GFPGAN/`, `models/Codeformer/` | Face restoration models |
| `models/ESRGAN/`, `models/RealESRGAN/` | Upscaler models |
| `models/deepbooru/` | DeepDanbooru tagging model |

The path root is controlled by `--data-dir` (default: repo root) and `--models-dir`.

## Compatibility Stubs

`Stability-AI/stablediffusion` (the SD2 repo the webui expects) was deleted from GitHub. This fork uses `CompVis/stable-diffusion` as a substitute, with four patch groups applied by `setup.sh` to `repositories/stable-diffusion-stability-ai/` (5 files total):

| File | What's patched |
|---|---|
| `ldm/modules/midas/__init__.py` + `api.py` | MiDaS depth estimation stub (`ISL_PATHS`, `load_model`) |
| `ldm/data/util.py` | `AddMiDaS` preprocessing transform stub |
| `ldm/models/diffusion/ddpm.py` | `LatentDepth2ImageDiffusion`, `LatentInpaintDiffusion` stubs |
| `ldm/modules/attention.py` | `ATTENTION_MODES` on `BasicTransformerBlock`, `use_linear` on `SpatialTransformer` |

**Impact:** depth-guided img2img (SD2 depth model) is not available. Everything else — txt2img, standard img2img, LoRA, extras, extensions — works normally.

## Known Limitations

- **Depth-guided img2img** — Not available (missing in CompVis base repo; stubs raise `NotImplementedError`).
- **`xformers` not installed** — Not needed for CPU/ROCm; the webui falls back to standard attention automatically.
- **pydantic v2 / gradio-client v2 incompatible** — `fastapi==0.94.0` requires pydantic v1 (`pydantic.fields.Undefined` was removed in v2); `gradio==3.41.2` requires `gradio-client==0.5.0` exactly (the `serializing` module was dropped in 2.x). `setup.sh` pins both after `requirements.txt`.
- **transformers ≥ 5 breaks CLIP loading** — `CLIPTextModel.text_model` was removed in transformers 5.x; `modules/sd_hijack.py:238` accesses it directly. The comfyui conda env ships 5.9.0, which overrides `requirements.txt`'s `transformers==4.30.2` via `--system-site-packages`. `setup.sh` re-pins `transformers==4.30.2` in the venv after `requirements.txt`.

## Architecture

### Startup Sequence

`launch.py` is the true entry point; `webui.sh` just activates the venv and execs it.

```
launch.py
  → launch_utils.prepare_environment()   # pip installs, repo clones (skipped with --skip-prepare-environment)
  → launch_utils.start()                 # re-executes with venv python → imports webui
      webui.py: initialize.imports()     # torch, gradio, ldm, sgm, shared
      webui.py: initialize.check_versions()
      webui.py: initialize.initialize()  # models dir, codeformer/gfpgan, initialize_rest()
          initialize_rest()              # samplers, extensions, scripts, upscalers, VAE, embeddings, optimizers
      → api_only()   if --nowebui        # mounts FastAPI only, no Gradio
      → webui()      otherwise           # builds Gradio Blocks, mounts FastAPI, starts uvicorn
```

All generation requests (UI or API) go through `modules/call_queue.py` which serializes them — only one generation runs at a time. The queue wraps the processing pipeline and gates on `shared.state`.

### Request Flow

```
User (Browser/API client)
  → Gradio UI (modules/ui.py)  OR  REST API (modules/api/api.py)
  → modules/call_queue.py  (serializes; wraps wrap_gradio_gpu_call / queue_lock)
  → Processing pipeline (modules/processing.py)
      → Model loading (modules/sd_models.py)
      → Text encoding (CLIP via modules/sd_hijack.py)
      → Sampling loop (modules/sd_samplers*.py + modules/sd_schedulers.py)
      → VAE decode (modules/sd_vae*.py)
      → Post-processing (modules/postprocessing.py, modules/extras.py)
  → Image save (modules/images.py) + display in gallery
```

### Key Modules

| Module | Role |
|---|---|
| `webui.py` | Entry point; creates Gradio app and mounts FastAPI |
| `modules/launch_utils.py` | Environment setup, dependency installation |
| `modules/shared.py` | Global state: `sd_model`, `opts`, `state`, `device`, `prompt_styles` |
| `modules/processing.py` | `StableDiffusionProcessingTxt2Img` / `Img2Img` dataclasses + `process_images()` |
| `modules/sd_models.py` | Checkpoint discovery, loading, unloading, VRAM management |
| `modules/sd_samplers*.py` | Sampler implementations (Euler, DPM++, DDIM, etc.) and CFG denoiser |
| `modules/sd_schedulers.py` | Noise schedules (Karras, exponential, etc.) |
| `modules/sd_hijack*.py` | PyTorch patches for attention optimization (xformers, sub-quadratic) |
| `modules/ui.py` | Gradio `Blocks` layout with all tabs |
| `modules/scripts.py` | Script/extension lifecycle; `Script` base class |
| `modules/script_callbacks.py` | Hook system for extensions (image save, UI, sampler, etc.) |
| `modules/api/api.py` | FastAPI endpoints: `/sdapi/v1/txt2img`, `/sdapi/v1/img2img`, etc. |
| `modules/images.py` | Image save/load, PNG metadata, grid generation |
| `modules/devices.py` | CUDA/MPS/CPU detection, dtype helpers |
| `modules/call_queue.py` | Serializes generation requests; `wrap_gradio_gpu_call` gates on `shared.state` |
| `modules/initialize.py` | Startup orchestration: `imports()`, `initialize()`, `initialize_rest()` |
| `modules/errors.py` | Centralized exception reporting; `display(e, task)` for consistent tracebacks |

### Global State (`modules/shared`)

`modules.shared` is a global namespace (not a class instance) that re-exports from sub-modules — when grepping, check the sub-module directly:

| Attribute | Defined in |
|---|---|
| `shared.cmd_opts`, `shared.parser` | `modules/shared_cmd_options.py` |
| `shared.state` (progress, interrupt) | `modules/shared_state.py` |
| `shared.opts` (user settings → `config.json`) | `modules/shared_options.py` |
| `shared.sd_model`, `shared.device` | `modules/shared.py` top-level |
| `shared.OptionInfo` registrations | `modules/shared_options.py` + callback `on_ui_settings` |

### Extension / Script System

**Custom scripts** go in `scripts/`. Built-in scripts include `xyz_grid.py` (parameter sweeps), `prompt_matrix.py`, `loopback.py`, `img2imgalt.py`, and several outpainting/upscaling scripts. Built-in extensions live in `extensions-builtin/`; user-installed extensions in `extensions/`.

Extensions that need custom CLI flags define a top-level `preload(parser)` function in their `scripts/` directory. This is called before any extension imports, during argparse setup. Example (from the LoRA extension):

```python
def preload(parser):
    parser.add_argument("--lora-dir", type=str, help="...", default=None)
```

To write a script, subclass `modules.scripts.Script`:
- `title()` — display name
- `ui(is_img2img)` — return Gradio components
- `run(p, *args)` — called for generation (override for exclusive control)
- `process(p, *args)` — called before sampling (for modifications)
- `postprocess(p, processed, *args)` — called after generation

To add a new `<syntax:name:weight>` extra-network (like LoRA), subclass `modules.extra_networks.ExtraNetwork`:
- `activate(p, params_list)` — called before sampling; `params_list` is a list of `ExtraNetworkParams`
- `deactivate(p)` — called after sampling to undo any model patches

Register with `modules.extra_networks.register_extra_network(instance)` from an `on_before_ui` callback.

Use `modules.script_callbacks` to hook into events without subclassing `Script`. Full callback registry:

| Callback | When it fires |
|---|---|
| `on_app_started(demo, app)` | Gradio + FastAPI apps are fully initialized |
| `on_before_reload()` | UI reload is about to happen |
| `on_model_loaded(sd_model)` | A checkpoint finishes loading |
| `on_ui_tabs()` | Gradio tabs are being built (return `[(block, name, id)]`) |
| `on_ui_train_tabs()` | Training subtabs are being built |
| `on_ui_settings()` | Settings UI is being built (add `OptionInfo` entries) |
| `on_before_image_saved(params)` | Before an image is written to disk |
| `on_image_saved(params)` | After an image is written to disk |
| `on_extra_noise(params)` | Extra noise is injected into the latent |
| `on_cfg_denoiser(params)` | Each CFG denoiser step |
| `on_cfg_denoised(params)` | After each CFG step |
| `on_cfg_after_cfg(params)` | After the CFG combination |
| `on_before_component(component, **kwargs)` | Before any Gradio component is created |
| `on_after_component(component, **kwargs)` | After any Gradio component is created |
| `on_image_grid(params)` | When an image grid is assembled |
| `on_infotext_pasted(infotext, params)` | When PNG infotext is pasted into the UI |
| `on_script_unloaded()` | Scripts are being reloaded |
| `on_before_ui()` | Before the Gradio UI is built |
| `on_list_optimizers(optimizers)` | Attention optimizer list is assembled |
| `on_list_unets(unets)` | U-Net override list is assembled |
| `on_before_token_counter(params)` | Before token counting runs |

### REST API Endpoints

All routes are defined in `modules/api/api.py` under the `/sdapi/v1/` prefix:

| Method | Path | Purpose |
|---|---|---|
| POST | `/txt2img` | Text-to-image generation |
| POST | `/img2img` | Image-to-image generation |
| POST | `/extra-single-image` | Upscale / post-process one image |
| POST | `/extra-batch-images` | Upscale / post-process multiple images |
| POST | `/png-info` | Extract metadata from a PNG |
| GET | `/progress` | Current generation progress |
| POST | `/interrogate` | CLIP/DeepDanbooru image captioning |
| POST | `/interrupt` | Cancel the current generation |
| POST | `/skip` | Skip to next image in batch |
| GET/POST | `/options` | Read or write `shared.opts` settings |
| GET | `/cmd-flags` | Read CLI flags |
| GET | `/samplers`, `/schedulers` | Available sampler/scheduler names |
| GET | `/upscalers`, `/latent-upscale-modes` | Upscaler info |
| GET | `/sd-models`, `/sd-vae` | Checkpoint and VAE lists |
| GET | `/embeddings`, `/hypernetworks` | Loaded embedding/hypernetwork info |
| POST | `/refresh-checkpoints`, `/refresh-vae`, `/refresh-embeddings` | Rescan disk |
| POST | `/create/embedding`, `/create/hypernetwork` | Create new embedding/hypernetwork |
| POST | `/train/embedding`, `/train/hypernetwork` | Train embedding/hypernetwork |
| GET | `/memory` | RAM/VRAM usage |
| POST | `/unload-checkpoint`, `/reload-checkpoint` | VRAM management |
| GET | `/scripts`, `/script-info` | Loaded script list and metadata |
| GET | `/extensions` | Installed extension list |
| POST | `/server-stop`, `/server-restart`, `/server-kill` | Server control (test mode only) |

The interactive Swagger docs are available at `http://localhost:7860/docs` when the server is running.

### Model Support

The codebase handles SD1.x, SD2.x, SDXL, SSD-1B, and SD3. Model type detection happens in `modules/sd_models.py` and `modules/sd_models_config.py`. SD3-specific code is in `modules/models/sd3/`. SDXL-specific handling is in `modules/sd_models_xl.py`.

LDM architecture configs live in `configs/*.yaml` (e.g. `v1-inference.yaml`, `sd_xl_inpaint.yaml`, `sd3-inference.yaml`). `modules/sd_models_config.py` picks the right YAML based on the checkpoint's state-dict shape — this is where to look if a model type is misidentified.

### Frontend

Gradio generates the HTML/JS shell. Additional interactivity is in `javascript/` (vanilla JS). Custom HTML fragments are in `html/`. The Gradio component tree is built in `modules/ui.py` using `gr.Blocks` context managers; component references are stored in `modules/shared.settings_components` after UI initialization.

Key JS globals injected by Gradio (declared in `.eslintrc.js` so ESLint doesn't flag them): `gradioApp`, `opts`, `all_gallery_buttons`, `localSet`/`localGet` (localStorage wrappers), and the `switch_to_*` tab-switching functions generated from tab IDs in `modules/ui.py`.
