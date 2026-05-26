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
# CompVis/stable-diffusion is used as the substitute; compatibility patches
# are applied below (step 4) to fill in the missing API surface.
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
# Stability-AI added several symbols to their fork that the webui depends on.
# CompVis/stable-diffusion lacks them. We patch after clone so any fresh
# setup (on a new machine or after wiping repositories/) gets the patches too.
# All patches are idempotent — safe to apply multiple times.

SD_REPO="$REPOS/stable-diffusion-stability-ai"
echo "Applying compatibility patches to CompVis/stable-diffusion..."

# 4a. MiDaS depth-estimation stub (ldm/modules/midas/)
mkdir -p "$SD_REPO/ldm/modules/midas"
cat > "$SD_REPO/ldm/modules/midas/__init__.py" << 'EOF'
from . import api
EOF

cat > "$SD_REPO/ldm/modules/midas/api.py" << 'EOF'
# Compatibility stub: Stability-AI added MiDaS depth support; CompVis did not.
# SD 1.5 inference never calls these — stubs prevent ImportError.
ISL_PATHS = {
    "dpt_large": "dpt_large-midas-2f21e586.pt",
    "dpt_hybrid": "dpt_hybrid-midas-501f0c75.pt",
    "midas_v21": "midas_v21-f6b98070.pt",
    "midas_v21_small": "midas_v21_small-70d6b9c8.pt",
}

def load_model(model_type):
    raise NotImplementedError(
        "MiDaS depth model not available in CompVis/stable-diffusion. "
        "This stub prevents import errors for SD 1.5 which does not use depth conditioning."
    )
EOF

# 4b. AddMiDaS transform stub (ldm/data/util.py)
mkdir -p "$SD_REPO/ldm/data"
touch "$SD_REPO/ldm/data/__init__.py"
if ! grep -q "AddMiDaS" "$SD_REPO/ldm/data/util.py" 2>/dev/null; then
cat >> "$SD_REPO/ldm/data/util.py" << 'EOF'

# Compatibility stub: AddMiDaS was added in Stability-AI fork.
class AddMiDaS:
    """Stub: depth-conditioned transform not needed for SD 1.5."""
    def __init__(self, model_type="dpt_hybrid"):
        self.model_type = model_type

    def __call__(self, sample):
        raise NotImplementedError(
            "AddMiDaS is a depth-conditioning transform not available in "
            "CompVis/stable-diffusion. This stub prevents import errors."
        )
EOF
fi

# 4c. LatentDepth2ImageDiffusion / LatentInpaintDiffusion stubs (ddpm.py)
if ! grep -q "LatentDepth2ImageDiffusion" "$SD_REPO/ldm/models/diffusion/ddpm.py"; then
cat >> "$SD_REPO/ldm/models/diffusion/ddpm.py" << 'EOF'

# ── Compatibility stubs for symbols added in Stability-AI fork ───────────────
class LatentDepth2ImageDiffusion(LatentDiffusion):
    """Stub: Depth-guided image diffusion (Stability-AI fork only)."""
    pass

class LatentInpaintDiffusion(LatentDiffusion):
    """Stub: Inpainting diffusion (Stability-AI fork only)."""
    pass
EOF
fi

# 4d. ATTENTION_MODES on BasicTransformerBlock + use_linear on SpatialTransformer
# (both attributes were added in the Stability-AI fork; webui's sd_hijack_unet
#  checks them at runtime via getattr)
ATTN="$SD_REPO/ldm/modules/attention.py"
if ! grep -q "ATTENTION_MODES" "$ATTN"; then
  ATTN_PATH="$ATTN" python3 - << 'PYEOF'
import os
path = os.environ['ATTN_PATH']
with open(path) as f:
    src = f.read()
old = 'class BasicTransformerBlock(nn.Module):\n    def __init__'
new = (
    'class BasicTransformerBlock(nn.Module):\n'
    '    # ATTENTION_MODES added for compatibility with AUTOMATIC1111 webui\n'
    '    ATTENTION_MODES = {\n'
    '        "softmax": CrossAttention,\n'
    '        "softmax-xformers": CrossAttention,\n'
    '    }\n\n'
    '    def __init__'
)
assert old in src, f"Could not find BasicTransformerBlock.__init__ in {path}"
src = src.replace(old, new, 1)
with open(path, 'w') as f:
    f.write(src)
print(f"  Patched: ATTENTION_MODES added to BasicTransformerBlock")
PYEOF
fi

if ! grep -q "use_linear" "$ATTN"; then
  ATTN_PATH="$ATTN" python3 - << 'PYEOF'
import os
path = os.environ['ATTN_PATH']
with open(path) as f:
    src = f.read()
old = 'class SpatialTransformer(nn.Module):\n    """\n'
new = (
    'class SpatialTransformer(nn.Module):\n'
    '    # use_linear=False: CompVis always uses Conv2d projection (not linear).\n'
    '    # Added for compatibility with AUTOMATIC1111\'s sd_hijack_unet which checks\n'
    '    # this attribute (the attribute was introduced in Stability-AI/stablediffusion).\n'
    '    use_linear = False\n\n'
    '    """\n'
)
assert old in src, f"Could not find SpatialTransformer docstring in {path}"
src = src.replace(old, new, 1)
with open(path, 'w') as f:
    f.write(src)
print(f"  Patched: use_linear = False added to SpatialTransformer")
PYEOF
fi

echo ""
echo "Setup complete. Run smoke.sh to launch and verify."
