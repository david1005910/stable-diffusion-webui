#!/usr/bin/env bash
# Smoke test for stable-diffusion-webui.
# Launches the server (CPU-only, empty test checkpoint), waits for it,
# runs curl checks, takes a screenshot, then shuts down.
#
# Usage:
#   ./smoke.sh                  # launch + smoke + screenshot + kill
#   KEEP_RUNNING=1 ./smoke.sh   # leave server running after checks
#   PORT=7861 ./smoke.sh        # use a different port
#
# Outputs:
#   /tmp/sdwebui-smoke.log        server log
#   /tmp/sdwebui-screenshot.png   screenshot of the Gradio UI

set -euo pipefail

REPO=/home/david1/문서/stable-diffusion-webui-master
VENV="$REPO/venv"
PYTHON="$VENV/bin/python"
PORT="${PORT:-7860}"
KEEP_RUNNING="${KEEP_RUNNING:-0}"
LOG=/tmp/sdwebui-smoke.log
SCREENSHOT=/tmp/sdwebui-screenshot.png
BASE="http://127.0.0.1:$PORT"

cd "$REPO"

# Kill any leftover server on this port
pkill -f "launch.py.*$PORT" 2>/dev/null || true

echo "Starting webui on port $PORT..."
HSA_OVERRIDE_GFX_VERSION=9.0.0 \
  "$PYTHON" launch.py \
    --skip-prepare-environment \
    --skip-torch-cuda-test \
    --skip-python-version-check \
    --no-half \
    --use-cpu all \
    --do-not-download-clip \
    --port "$PORT" \
    --ckpt test/test_files/empty.pt \
    > "$LOG" 2>&1 &
SERVER_PID=$!
echo "Server PID: $SERVER_PID"

# ── Wait for Gradio to be ready ───────────────────────────────────────────────
echo -n "Waiting for server..."
SECONDS=0
until curl -sf --max-time 2 "$BASE/" > /dev/null 2>&1; do
  if (( SECONDS > 90 )); then
    echo ""
    echo "ERROR: server didn't start in 90s. Last log lines:"
    tail -20 "$LOG"
    kill "$SERVER_PID" 2>/dev/null || true
    exit 1
  fi
  echo -n "."
  sleep 2
done
echo " ready (${SECONDS}s)"

# ── Curl smoke checks ─────────────────────────────────────────────────────────
echo ""
echo "=== Smoke checks ==="

# 1. HTML page
HTML=$(curl -sf --max-time 5 "$BASE/")
echo "[OK] GET / — $(echo "$HTML" | wc -c) bytes HTML"

# 2. Gradio queue endpoint
QUEUE=$(curl -sf --max-time 5 "$BASE/queue/status")
echo "[OK] GET /queue/status — $QUEUE"

# 3. Gradio info (lists loaded tabs/endpoints)
INFO=$(curl -sf --max-time 5 "$BASE/info")
PAGES=$(echo "$INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('named_endpoints',{})), 'named endpoints')" 2>/dev/null || echo "info ok")
echo "[OK] GET /info — $PAGES"

# ── Screenshot ────────────────────────────────────────────────────────────────
echo ""
echo "Taking screenshot → $SCREENSHOT"
google-chrome --headless --disable-gpu \
  --screenshot="$SCREENSHOT" \
  --window-size=1280,900 \
  --virtual-time-budget=5000 \
  "$BASE" 2>/dev/null
echo "[OK] screenshot saved"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "=== All checks passed ==="
echo "Server log: $LOG"
echo "Screenshot: $SCREENSHOT"

if [[ "$KEEP_RUNNING" == "1" ]]; then
  echo "Server left running (PID $SERVER_PID) at $BASE"
else
  echo "Stopping server..."
  kill "$SERVER_PID" 2>/dev/null || true
fi
