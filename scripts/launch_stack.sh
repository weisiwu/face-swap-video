#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
# FaceSwap API + Cloudflare Tunnel launcher
# Auto-restart on exit, save tunnel URL to ~/.facefusion_tunnel_url
# ─────────────────────────────────────────────────────────────────────

set -uo pipefail  # Don't exit on individual command failures

API_PORT=8765
PROJECT_DIR="$HOME/Desktop/致富经/apps/face-swap-video"
API_DIR="$PROJECT_DIR/server/api"
PYTHON="/opt/miniconda3/envs/facefusion/bin/python"
LOG_DIR="$HOME/Library/Logs/facefusion"
TUNNEL_URL_FILE="$HOME/.facefusion_tunnel_url"

mkdir -p "$LOG_DIR"

echo "[$(date)] Starting FaceSwap stack..." | tee -a "$LOG_DIR/launcher.log"

# ── 1. Kill any existing processes ──────────────────────────────────
lsof -ti :$API_PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
pkill -f "cloudflared tunnel.*8765" 2>/dev/null || true
sleep 1

# ── 2. Start API server in background ──────────────────────────────
cd "$API_DIR"
$PYTHON -c "
from server import app
import uvicorn
uvicorn.run(app, host='0.0.0.0', port=$API_PORT, log_level='info')
" > "$LOG_DIR/api.log" 2>&1 &
API_PID=$!
echo "[$(date)] API server started (PID: $API_PID)" | tee -a "$LOG_DIR/launcher.log"

# Wait for API to be ready
for i in $(seq 1 30); do
    if curl -sf http://localhost:$API_PORT/api/health > /dev/null 2>&1; then
        echo "[$(date)] API server ready" | tee -a "$LOG_DIR/launcher.log"
        break
    fi
    sleep 1
done

# ── 3. Start Cloudflare Tunnel (with retry) ──────────────────────────

start_tunnel() {
    local max_retries=10
    local attempt=1
    
    while [ $attempt -le $max_retries ]; do
        echo "[$(date)] Tunnel attempt $attempt/$max_retries" | tee -a "$LOG_DIR/launcher.log"
        
        cloudflared tunnel --url http://localhost:$API_PORT --no-autoupdate \
            > "$LOG_DIR/tunnel.log" 2>&1 &
        TUNNEL_PID=$!
        
        # Wait for URL
        for i in $(seq 1 20); do
            URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG_DIR/tunnel.log" 2>/dev/null | head -1 || true)
            if [ -n "$URL" ]; then
                echo "$URL" > "$TUNNEL_URL_FILE"
                echo "[$(date)] Tunnel URL: $URL (PID: $TUNNEL_PID)" | tee -a "$LOG_DIR/launcher.log"
                return 0
            fi
            
            # Check if process died with error
            if ! kill -0 $TUNNEL_PID 2>/dev/null; then
                echo "[$(date)] Tunnel process died, retrying..." | tee -a "$LOG_DIR/launcher.log"
                break
            fi
            sleep 2
        done
        
        # Process still running but no URL => kill and retry
        kill $TUNNEL_PID 2>/dev/null || true
        wait $TUNNEL_PID 2>/dev/null || true
        attempt=$((attempt + 1))
        sleep 1
    done
    
    echo "[$(date)] Failed to create tunnel after $max_retries attempts" | tee -a "$LOG_DIR/launcher.log"
    return 1
}

start_tunnel || echo "[$(date)] WARNING: No tunnel available, API is local-only" | tee -a "$LOG_DIR/launcher.log"

# ── 4. Keep running, restart on crash ──────────────────────────────
echo "[$(date)] Stack running. Monitoring..." | tee -a "$LOG_DIR/launcher.log"

while true; do
    # Check API
    if ! curl -sf http://localhost:$API_PORT/api/health > /dev/null 2>&1; then
        echo "[$(date)] API server died, restarting..." | tee -a "$LOG_DIR/launcher.log"
        lsof -ti :$API_PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
        cd "$API_DIR"
        $PYTHON -c "from server import app; import uvicorn; uvicorn.run(app, host='0.0.0.0', port=$API_PORT)" \
            > "$LOG_DIR/api.log" 2>&1 &
        sleep 3
    fi

    # Check tunnel
    if ! pgrep -f "cloudflared tunnel.*8765" > /dev/null 2>&1; then
        echo "[$(date)] Tunnel died, restarting..." | tee -a "$LOG_DIR/launcher.log"
        cloudflared tunnel --url http://localhost:$API_PORT --no-autoupdate \
            > "$LOG_DIR/tunnel.log" 2>&1 &
        sleep 5
        URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG_DIR/tunnel.log" 2>/dev/null | head -1)
        if [ -n "$URL" ]; then
            echo "$URL" > "$TUNNEL_URL_FILE"
            echo "[$(date)] New tunnel URL: $URL" | tee -a "$LOG_DIR/launcher.log"
        fi
    fi

    sleep 30
done
