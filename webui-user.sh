#!/bin/bash
#########################################################
# Uncomment and change the variables below to your need:#
#########################################################

# Install directory without trailing slash
#install_dir="/home/$(whoami)"

# Name of the subdirectory
#clone_dir="stable-diffusion-webui"

# ── AMD Renoir/Cezanne iGPU (ROCm) ───────────────────────────────────────────
# Required so PyTorch/ROCm recognises the Cezanne integrated GPU.
export HSA_OVERRIDE_GFX_VERSION=9.0.0

# ── Venv bootstrap ───────────────────────────────────────────────────────────
# The venv must be created with --system-site-packages so it inherits
# torch 2.6.0+rocm6.2 from the comfyui conda env without re-downloading it.
# webui.sh would create a plain venv if the directory were missing, so we
# pre-create it here when needed.
_COMFYUI_PYTHON="/home/david1/anaconda3/envs/comfyui/bin/python3.10"
_SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
if [[ ! -f "$_SCRIPT_DIR/venv/bin/python" ]]; then
    echo "Bootstrapping venv with --system-site-packages (inherits torch+ROCm)..."
    "$_COMFYUI_PYTHON" -m venv --system-site-packages "$_SCRIPT_DIR/venv"
fi

# Point python_cmd at the venv directly so webui.sh uses it from the start.
python_cmd="$_SCRIPT_DIR/venv/bin/python"

# ── Launch flags ─────────────────────────────────────────────────────────────
# --skip-torch-cuda-test   : CUDA is not available; ROCm reports via HIP
# --skip-python-version-check : we run 3.10, which is fine
# --no-half                : required for stability on AMD iGPU (fp16 issues)
# --do-not-download-clip   : skip auto-download of CLIP weights on startup
export COMMANDLINE_ARGS="--skip-prepare-environment --skip-torch-cuda-test --skip-python-version-check --no-half --do-not-download-clip"

# ── Torch install ─────────────────────────────────────────────────────────────
# torch is already present via --system-site-packages; tell launch.py to skip
# the install step entirely so it doesn't try to download a 2 GB wheel.
export TORCH_COMMAND="echo 'torch already available via system-site-packages, skipping install'"

# ── Substitute SD repo (Stability-AI/stablediffusion was deleted) ─────────────
# launch.py's prepare_environment() tries to git-fetch the Stability AI repo to
# verify a specific commit; that repo no longer exists.  --skip-prepare-environment
# above skips the entire step, but if it ever runs, these vars point it at the
# CompVis clone we actually have checked out.
export STABLE_DIFFUSION_REPO="https://github.com/CompVis/stable-diffusion.git"
export STABLE_DIFFUSION_COMMIT_HASH="21f890f9da3cfbeaba8e2ac3c425ee9e998d5229"

# git executable
#export GIT="git"

# python3 venv without trailing slash (defaults to ${install_dir}/${clone_dir}/venv)
#venv_dir="venv"

# script to launch to start the app
#export LAUNCH_SCRIPT="launch.py"

# Requirements file to use for stable-diffusion-webui
#export REQS_FILE="requirements_versions.txt"

# Fixed git repos
#export K_DIFFUSION_PACKAGE=""
#export GFPGAN_PACKAGE=""

# Fixed git commits
#export STABLE_DIFFUSION_COMMIT_HASH=""
#export CODEFORMER_COMMIT_HASH=""
#export BLIP_COMMIT_HASH=""

# Uncomment to enable accelerated launch
#export ACCELERATE="True"

# Uncomment to disable TCMalloc
#export NO_TCMALLOC="True"

###########################################
