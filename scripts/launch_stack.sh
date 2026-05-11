#!/bin/bash
# FaceSwap API + Cloudflare Named Tunnel launcher for LaunchAgent.
# Stored outside Desktop to avoid macOS TCC blocking execution from Desktop.
set -uo pipefail

API_PORT=9999
PUBLIC_URL="https://facefusion.baoganai.com"
TUNNEL_NAME="facefusion-api"
TUNNEL_CONFIG="$HOME/.cloudflared/facefusion-config.yml"
PROJECT_DIR="$HOME/Desktop/致富经/apps/face-swap-video"
API_DIR="$PROJECT_DIR/server/api"
PYTHON="/opt/miniconda3/envs/facefusion/bin/python"
LOG_DIR="$HOME/Library/Logs/facefusion"
TUNNEL_URL_FILE="$HOME/.facefusion_tunnel_url"

mkdir -p "$LOG_DIR"
echo "[$(date)] Starting FaceSwap stack..." | tee -a "$LOG_DIR/launcher.log"

lsof -ti :$API_PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
pkill -f "cloudflared tunnel.*facefusion-api" 2>/dev/null || true
pkill -f "cloudflared tunnel.*$API_PORT" 2>/dev/null || true
sleep 1

cd "$API_DIR" || exit 1
$PYTHON -c "
from server import app
import uvicorn
uvicorn.run(app, host='0.0.0.0', port=$API_PORT, log_level='info')
" > "$LOG_DIR/api.log" 2>&1 &
API_PID=$!
echo "[$(date)] API server started (PID: $API_PID)" | tee -a "$LOG_DIR/launcher.log"

for i in $(seq 1 30); do
    if curl -sf http://localhost:$API_PORT/api/health > /dev/null 2>&1; then
        echo "[$(date)] API server ready" | tee -a "$LOG_DIR/launcher.log"
        break
    fi
    sleep 1
done

start_tunnel() {
    echo "[$(date)] Starting named tunnel $TUNNEL_NAME -> $PUBLIC_URL" | tee -a "$LOG_DIR/launcher.log"
    echo "$PUBLIC_URL" > "$TUNNEL_URL_FILE"
    cloudflared tunnel --protocol http2 --config "$TUNNEL_CONFIG" run "$TUNNEL_NAME" \
        > "$LOG_DIR/tunnel.log" 2>&1 &
    TUNNEL_PID=$!

    for i in $(seq 1 20); do
        if kill -0 $TUNNEL_PID 2>/dev/null; then
            if grep -E 'Registered tunnel connection|Connection .* registered|Initial protocol' "$LOG_DIR/tunnel.log" >/dev/null 2>&1; then
                echo "[$(date)] Named tunnel ready: $PUBLIC_URL (PID: $TUNNEL_PID)" | tee -a "$LOG_DIR/launcher.log"
                return 0
            fi
        else
            echo "[$(date)] Named tunnel process died" | tee -a "$LOG_DIR/launcher.log"
            tail -n 40 "$LOG_DIR/tunnel.log" | tee -a "$LOG_DIR/launcher.log"
            return 1
        fi
        sleep 1
    done

    if kill -0 $TUNNEL_PID 2>/dev/null; then
        echo "[$(date)] Named tunnel running: $PUBLIC_URL (PID: $TUNNEL_PID)" | tee -a "$LOG_DIR/launcher.log"
        return 0
    fi
    return 1
}

start_tunnel || echo "[$(date)] WARNING: Named tunnel unavailable, API is local-only" | tee -a "$LOG_DIR/launcher.log"
echo "[$(date)] Stack running. Monitoring..." | tee -a "$LOG_DIR/launcher.log"
TUNNEL_CHECK_COUNTER=0

while true; do
    if ! curl -sf http://localhost:$API_PORT/api/health > /dev/null 2>&1; then
        echo "[$(date)] API server died, restarting..." | tee -a "$LOG_DIR/launcher.log"
        lsof -ti :$API_PORT 2>/dev/null | xargs kill -9 2>/dev/null || true
        cd "$API_DIR" || exit 1
        $PYTHON -c "from server import app; import uvicorn; uvicorn.run(app, host='0.0.0.0', port=$API_PORT)" \
            > "$LOG_DIR/api.log" 2>&1 &
        sleep 3
    fi

    if ! pgrep -f "cloudflared tunnel.*facefusion-api" > /dev/null 2>&1; then
        echo "[$(date)] Named tunnel died, restarting..." | tee -a "$LOG_DIR/launcher.log"
        start_tunnel || true
    else
        TUNNEL_CHECK_COUNTER=$((TUNNEL_CHECK_COUNTER + 1))
        if [ "$TUNNEL_CHECK_COUNTER" -ge 2 ]; then
            TUNNEL_CHECK_COUNTER=0
            if ! curl -sf --max-time 10 "$PUBLIC_URL/api/health" > /dev/null 2>&1; then
                echo "[$(date)] Named tunnel health check failed, restarting..." | tee -a "$LOG_DIR/launcher.log"
                pkill -f "cloudflared tunnel.*facefusion-api" 2>/dev/null || true
                sleep 1
                start_tunnel || true
            fi
        fi
    fi

    sleep 30
done
