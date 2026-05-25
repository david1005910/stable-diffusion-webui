#!/usr/bin/env bash
# One-time environment setup for stable-diffusion-webui.
# Run once from the repo root. Safe to re-run (idempotent).
# Requires: git, the comfyui conda env's Python 3.10 (has torch+ROCm).
set -euo pipefail

REPO=/home/david1/문서/stable-diffusion-webui-master
COMFYUI_PYTHON=/home/david1/anaconda3/envs/comfyui/bin/python3.10
VENV="$REPO/venv"

cd "$REPO"

# ── 1. Python venv (inherits comfyui env's torch 2.6+ROCm) ───────────────────
if [ ! -f "$VENV/bin/python" ]; then
  echo "Creating venv..."
  "$COMFYUI_PYTHON" -m venv --system-site-packages "$VENV"
fi

PIP="$VENV/bin/pip"
PYTHON="$VENV/bin/python"

# ── 2. Core Python packages ───────────────────────────────────────────────────
echo "Installing requirements..."
"$PIP" install --upgrade pip setuptools -q

# CLIP can't be built in an isolated env (missing pkg_resources in build env)
"$PIP" install "https://github.com/openai/CLIP/archive/d50d76daa670286dd6cacf3bcd80b5e4823fc8e1.zip" \
  --no-build-isolation -q

# taming-transformers and dctorch are needed by the ldm + k-diffusion repos
"$PIP" install taming-transformers-rom1504 dctorch -q

"$PIP" install -r requirements.txt -q

# ── 3. Clone required git repositories ───────────────────────────────────────
REPOS="$REPO/repositories"
mkdir -p "$REPOS"

clone_if_missing() {
  local url="$1" dest="$2" name="$3"
  if [ ! -d "$dest/.git" ]; then
    echo "Cloning $name..."
    git clone --depth 1 "$url" "$dest"
  else
    echo "$name already cloned."
  fi
}

# NOTE: Stability-AI/stablediffusion was deleted from GitHub.
# CompVis/stable-diffusion is used as the substitute; compatibility stubs
# were already applied to the checked-out repo (see ldm/modules/midas,
# ldm/data/util.py, ldm/models/diffusion/ddpm.py, ldm/modules/attention.py).
clone_if_missing \
  https://github.com/CompVis/stable-diffusion.git \
  "$REPOS/stable-diffusion-stability-ai" \
  "Stable Diffusion (CompVis)"

clone_if_missing \
  https://github.com/Stability-AI/generative-models.git \
  "$REPOS/generative-models" \
  "Stable Diffusion XL (generative-models)"

clone_if_missing \
  https://github.com/crowsonkb/k-diffusion.git \
  "$REPOS/k-diffusion" \
  "k-diffusion"

clone_if_missing \
  https://github.com/salesforce/BLIP.git \
  "$REPOS/BLIP" \
  "BLIP"

clone_if_missing \
  https://github.com/AUTOMATIC1111/stable-diffusion-webui-assets.git \
  "$REPOS/stable-diffusion-webui-assets" \
  "webui-assets"

# ── 4. Apply compatibility patches to the CompVis repo ───────────────────────
# These patches are already committed in this repo under:
#   repositories/stable-diffusion-stability-ai/ldm/modules/midas/
#   repositories/stable-diffusion-stability-ai/ldm/data/util.py
#   (stubs for symbols removed when Stability AI deleted their fork)
# The patches in ldm/modules/attention.py and ldm/models/diffusion/ddpm.py
# are checked in at the time of setup — they persist across re-runs.

echo ""
echo "Setup complete. Run smoke.sh to launch and verify."
