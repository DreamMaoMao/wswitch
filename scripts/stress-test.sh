#!/bin/bash
# Snappy Switcher Stress Test Suite
# Tests daemon stability under various load conditions

set -e
BINARY="./snappy-switcher"
PASS=0
FAIL=0

log() { echo "[$(date +%H:%M:%S)] $1"; }
pass() { ((PASS++)); log "✅ PASS: $1"; }
fail() { ((FAIL++)); log "❌ FAIL: $1"; }

cleanup() {
    pkill -f "snappy-switcher --daemon" 2>/dev/null || true
    rm -f /tmp/snappy-switcher-*.sock 2>/dev/null || true
    sleep 0.5
}

# Test 1: Basic startup/shutdown
test_startup() {
    log "Test 1: Basic Startup/Shutdown"
    cleanup
    $BINARY --daemon &
    PID=$!
    sleep 2
    if ps -p $PID > /dev/null 2>&1; then
        pass "Daemon started (PID: $PID)"
        kill $PID 2>/dev/null || true
        sleep 1
        if ! ps -p $PID > /dev/null 2>&1; then
            pass "Daemon stopped cleanly"
        else
            fail "Daemon did not stop"
            kill -9 $PID 2>/dev/null || true
        fi
    else
        fail "Daemon failed to start"
    fi
}

# Test 2: Rapid toggle cycles
test_rapid_toggle() {
    log "Test 2: Rapid Toggle Cycles (30 cycles)"
    cleanup
    $BINARY --daemon &
    PID=$!
    sleep 2
    
    for i in $(seq 1 30); do
        $BINARY toggle >/dev/null 2>&1 || true
        sleep 0.1
    done
    
    if ps -p $PID > /dev/null 2>&1; then
        pass "Survived 30 rapid toggles"
    else
        fail "Crashed during rapid toggles"
    fi
    cleanup
}

# Test 3: Navigation stress
test_navigation() {
    log "Test 3: Navigation Stress (50 next/prev)"
    cleanup
    $BINARY --daemon &
    PID=$!
    sleep 2
    
    $BINARY toggle >/dev/null 2>&1 || true
    sleep 0.5
    
    for i in $(seq 1 25); do
        $BINARY next >/dev/null 2>&1 || true
        sleep 0.05
        $BINARY prev >/dev/null 2>&1 || true
        sleep 0.05
    done
    
    if ps -p $PID > /dev/null 2>&1; then
        pass "Survived 50 navigation commands"
    else
        fail "Crashed during navigation"
    fi
    cleanup
}

# Test 4: Repeated show/hide
test_show_hide() {
    log "Test 4: Show/Hide Cycles (20 cycles)"
    cleanup
    $BINARY --daemon &
    PID=$!
    sleep 2
    
    for i in $(seq 1 20); do
        $BINARY toggle >/dev/null 2>&1 || true
        sleep 0.2
        $BINARY hide >/dev/null 2>&1 || true
        sleep 0.2
    done
    
    if ps -p $PID > /dev/null 2>&1; then
        pass "Survived 20 show/hide cycles"
    else
        fail "Crashed during show/hide"
    fi
    cleanup
}

# Test 5: Concurrent commands
test_concurrent() {
    log "Test 5: Concurrent Commands"
    cleanup
    $BINARY --daemon &
    PID=$!
    sleep 2
    
    for i in $(seq 1 10); do
        $BINARY toggle &
        $BINARY next &
        $BINARY prev &
        wait
        sleep 0.1
    done
    
    sleep 1
    if ps -p $PID > /dev/null 2>&1; then
        pass "Survived concurrent command bursts"
    else
        fail "Crashed during concurrent commands"
    fi
    cleanup
}

# Test 6: Memory leak check (basic)
test_memory() {
    log "Test 6: Memory Stability (100 operations)"
    cleanup
    $BINARY --daemon &
    PID=$!
    sleep 2
    
    MEM_START=$(ps -o rss= -p $PID 2>/dev/null || echo "0")
    
    for i in $(seq 1 100); do
        $BINARY toggle >/dev/null 2>&1 || true
        sleep 0.05
        $BINARY next >/dev/null 2>&1 || true
        sleep 0.05
        $BINARY hide >/dev/null 2>&1 || true
        sleep 0.05
    done
    
    MEM_END=$(ps -o rss= -p $PID 2>/dev/null || echo "0")
    
    if ps -p $PID > /dev/null 2>&1; then
        log "  Memory: ${MEM_START}KB -> ${MEM_END}KB"
        # Allow up to 50% growth as acceptable
        if [ "$MEM_END" -lt $((MEM_START * 3 / 2)) ]; then
            pass "Memory stable after 100 operations"
        else
            fail "Significant memory growth detected"
        fi
    else
        fail "Crashed during memory test"
    fi
    cleanup
}

# Test 7: Quit command
test_quit() {
    log "Test 7: Quit Command"
    cleanup
    $BINARY --daemon &
    PID=$!
    sleep 2
    
    $BINARY quit >/dev/null 2>&1 || true
    sleep 1
    
    if ! ps -p $PID > /dev/null 2>&1; then
        pass "Quit command worked"
    else
        fail "Quit command failed"
        kill -9 $PID 2>/dev/null || true
    fi
}

# Main
main() {
    log "========================================="
    log "Snappy Switcher Stress Test Suite"
    log "========================================="
    
    if [ ! -f "$BINARY" ]; then
        log "Building..."
        make clean && make
    fi
    
    test_startup
    test_rapid_toggle
    test_navigation
    test_show_hide
    test_concurrent
    test_memory
    test_quit
    
    log "========================================="
    log "Results: $PASS passed, $FAIL failed"
    log "========================================="
    
    cleanup
    
    if [ $FAIL -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

main
