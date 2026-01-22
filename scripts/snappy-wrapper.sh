#!/bin/bash
# Wrapper script for snappy-switcher daemon
# Waits for Hyprland compositor to be fully ready before starting

BINARY="${SNAPPY_BINARY:-/usr/local/bin/snappy-switcher}"
MAX_RETRIES=30
RETRY_DELAY=0.5

# === CRITICAL FIX: Wait for Hyprland to be fully ready ===
# This prevents race conditions during login where the compositor
# isn't fully stabilized yet

wait_for_hyprland() {
    local attempts=0
    local max_attempts=60  # 30 seconds max wait
    
    echo "[snappy-wrapper] Waiting for Hyprland to be ready..."
    
    while [ $attempts -lt $max_attempts ]; do
        # Check if Hyprland socket exists and is responsive
        if [ -S "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ] || \
           [ -S "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" ]; then
            
            # Try to get monitors - confirms compositor is responsive
            if hyprctl monitors &>/dev/null; then
                # Additional delay to ensure outputs are configured
                sleep 1
                echo "[snappy-wrapper] Hyprland is ready"
                return 0
            fi
        fi
        
        ((attempts++))
        sleep 0.5
    done
    
    echo "[snappy-wrapper] Warning: Hyprland readiness check timed out"
    return 1
}

# === CRITICAL: Check if WAYLAND_DISPLAY is set ===
if [ -z "$WAYLAND_DISPLAY" ]; then
    echo "[snappy-wrapper] Error: WAYLAND_DISPLAY not set"
    exit 1
fi

# Check if already running
if pgrep -f "snappy-switcher --daemon" > /dev/null 2>&1; then
    echo "[snappy-wrapper] Daemon already running"
    exit 0
fi

# Wait for Hyprland to be fully ready before starting daemon
wait_for_hyprland

# Additional safety delay for layer shell to be fully available
sleep 0.5

echo "[snappy-wrapper] Starting snappy-switcher daemon..."

for i in $(seq 1 $MAX_RETRIES); do
    # Start daemon
    "$BINARY" --daemon &
    PID=$!
    
    # Wait for startup
    sleep 1.5
    
    # Check if still running
    if kill -0 $PID 2>/dev/null; then
        echo "[snappy-wrapper] Daemon started successfully (PID: $PID)"
        # Wait for it to exit
        wait $PID
        EXIT_CODE=$?
        
        echo "[snappy-wrapper] Daemon exited with code $EXIT_CODE"
        
        # Don't restart if it was a clean shutdown
        if [ $EXIT_CODE -eq 0 ]; then
            echo "[snappy-wrapper] Clean shutdown, not restarting"
            exit 0
        fi
    fi
    
    echo "[snappy-wrapper] Retry $i/$MAX_RETRIES in ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
done

echo "[snappy-wrapper] Failed to start daemon after $MAX_RETRIES attempts"
exit 1
