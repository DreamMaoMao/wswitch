#!/usr/bin/env bash
#═══════════════════════════════════════════════════════════════════════════════
#  SNAPPY SWITCHER - ULTIMATE STRESS TEST SUITE
#═══════════════════════════════════════════════════════════════════════════════
#  A comprehensive battery of tests covering:
#    1. Signal Handling (SIGINT, SIGTERM, SIGHUP, SIGUSR1)
#    2. Config Self-Healing (missing config, corrupt config, permission denied)
#    3. Socket Robustness (stale socket, rapid reconnect, concurrent clients)
#    4. Memory Stability (leak detection, long-running stress)
#    5. Crash Recovery (force kill + restart)
#    6. Edge Cases (empty commands, oversized payloads, special characters)
#═══════════════════════════════════════════════════════════════════════════════

# Don't exit on error - we want to continue testing
set -uo pipefail

DAEMON="snappy-switcher"
SOCKET="/tmp/snappy-switcher.sock"
CONFIG_DIR="$HOME/.config/snappy-switcher"
CONFIG_FILE="$CONFIG_DIR/config.ini"
LOGFILE="/tmp/snappy-stress-test.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Counters
PASS=0
FAIL=0
SKIP=0

#───────────────────────────────────────────────────────────────────────────────
# Utilities
#───────────────────────────────────────────────────────────────────────────────

log() { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); }
skip() { echo -e "  ${YELLOW}⊘${NC} $1 (skipped)"; ((SKIP++)); }
header() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  $1${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
}

daemon_running() { pgrep -x "$DAEMON" >/dev/null 2>&1; }
get_pid() { pgrep -x "$DAEMON" 2>/dev/null || echo "N/A"; }
kill_daemon() { pkill -x "$DAEMON" 2>/dev/null || true; sleep 0.5; }
start_daemon() {
    if ! daemon_running; then
        "$DAEMON" --daemon &>/dev/null &
        sleep 1
    fi
}
wait_for_socket() {
    for i in {1..20}; do
        [[ -S "$SOCKET" ]] && return 0
        sleep 0.25
    done
    return 1
}
send_cmd() { echo -n "$1" | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null || true; }

#───────────────────────────────────────────────────────────────────────────────
# TEST 1: Signal Handling
#───────────────────────────────────────────────────────────────────────────────

test_signals() {
    header "TEST 1: SIGNAL HANDLING"

    # Test SIGTERM
    log "Testing SIGTERM (graceful shutdown)..."
    kill_daemon
    start_daemon
    local pid=$(get_pid)
    kill -TERM "$pid" 2>/dev/null
    sleep 1
    if ! daemon_running && [[ ! -S "$SOCKET" ]]; then
        pass "SIGTERM: Daemon exited cleanly, socket removed"
    else
        fail "SIGTERM: Daemon didn't exit or socket left behind"
    fi

    # Test SIGINT (Ctrl+C)
    log "Testing SIGINT (Ctrl+C)..."
    start_daemon
    pid=$(get_pid)
    kill -INT "$pid" 2>/dev/null
    sleep 1
    if ! daemon_running && [[ ! -S "$SOCKET" ]]; then
        pass "SIGINT: Daemon exited cleanly, socket removed"
    else
        fail "SIGINT: Daemon didn't exit or socket left behind"
    fi

    # Test SIGHUP (traditionally reload config)
    log "Testing SIGHUP (should not crash)..."
    start_daemon
    pid=$(get_pid)
    kill -HUP "$pid" 2>/dev/null
    sleep 0.5
    if daemon_running; then
        pass "SIGHUP: Daemon survived (ignored signal)"
    else
        fail "SIGHUP: Daemon crashed unexpectedly"
        start_daemon
    fi

    # Test SIGUSR1 (random user signal)
    log "Testing SIGUSR1 (should not crash)..."
    pid=$(get_pid)
    kill -USR1 "$pid" 2>/dev/null
    sleep 0.5
    if daemon_running; then
        pass "SIGUSR1: Daemon survived"
    else
        fail "SIGUSR1: Daemon crashed"
        start_daemon
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# TEST 2: Config Self-Healing
#───────────────────────────────────────────────────────────────────────────────

test_config_healing() {
    header "TEST 2: CONFIG SELF-HEALING"

    kill_daemon

    # Backup existing config
    local backup=""
    if [[ -f "$CONFIG_FILE" ]]; then
        backup=$(mktemp)
        cp "$CONFIG_FILE" "$backup"
    fi

    # Test missing config (need to also hide system config temporarily)
    log "Testing missing config.ini..."
    rm -f "$CONFIG_FILE"
    # Temporarily rename system config if it exists (requires sudo, skip if not available)
    local sys_config="/etc/xdg/snappy-switcher/config.ini"
    local sys_backup=""
    if [[ -f "$sys_config" ]] && sudo -n true 2>/dev/null; then
        sys_backup="${sys_config}.bak.$$"
        sudo mv "$sys_config" "$sys_backup" 2>/dev/null || true
    fi
    start_daemon
    sleep 0.5  # Give daemon time to create config
    local config_created=false
    if [[ -f "$CONFIG_FILE" ]] && daemon_running; then
        config_created=true
        pass "Missing config: Auto-created config.ini"
    elif daemon_running && [[ -n "$sys_backup" ]]; then
        # System config was hidden but daemon still started (from defaults)
        pass "Missing config: Daemon started with built-in defaults"
        config_created=true
    elif daemon_running; then
        # System config exists, daemon used it - this is expected
        pass "Missing config: Daemon used system config fallback"
        config_created=true
    else
        fail "Missing config: Failed to create config.ini"
    fi
    # Restore system config
    if [[ -n "$sys_backup" ]] && [[ -f "$sys_backup" ]]; then
        sudo mv "$sys_backup" "$sys_config" 2>/dev/null || true
    fi

    # Test corrupt config (invalid INI syntax)
    log "Testing corrupt config.ini..."
    kill_daemon
    echo "THIS IS NOT VALID INI [[[[" > "$CONFIG_FILE"
    start_daemon
    if daemon_running; then
        pass "Corrupt config: Daemon started with defaults"
    else
        fail "Corrupt config: Daemon failed to start"
    fi

    # Test empty config
    log "Testing empty config.ini..."
    kill_daemon
    : > "$CONFIG_FILE"  # Empty file
    start_daemon
    if daemon_running; then
        pass "Empty config: Daemon started with defaults"
    else
        fail "Empty config: Daemon failed to start"
    fi

    # Restore backup
    if [[ -n "$backup" ]]; then
        cp "$backup" "$CONFIG_FILE"
        rm -f "$backup"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# TEST 3: Socket Robustness
#───────────────────────────────────────────────────────────────────────────────

test_socket() {
    header "TEST 3: SOCKET ROBUSTNESS"

    kill_daemon

    # Test stale socket recovery
    log "Testing stale socket file recovery..."
    touch "$SOCKET"  # Create fake stale socket file
    start_daemon
    if daemon_running && [[ -S "$SOCKET" ]]; then
        pass "Stale socket: Daemon recovered and replaced file"
    else
        fail "Stale socket: Daemon failed to start"
        rm -f "$SOCKET"
        start_daemon
    fi

    # Test rapid reconnect (100 connections in sequence)
    log "Testing rapid reconnect (100 connections)..."
    wait_for_socket  # Ensure socket is ready
    sleep 0.5  # Let daemon settle
    local success=0
    for i in {1..100}; do
        # Use socat's -t flag for timeout instead of bash timeout
        if echo "NEXT" | socat -t 1 - "UNIX-CONNECT:$SOCKET" 2>/dev/null; then
            ((success++)) || true
        fi
    done
    if [[ $success -ge 80 ]]; then
        pass "Rapid reconnect: $success/100 connections succeeded"
    else
        fail "Rapid reconnect: Only $success/100 connections succeeded"
    fi

    # Test concurrent clients (10 parallel connections)
    log "Testing concurrent clients (10 parallel)..."
    local pids=()
    for i in {1..10}; do
        (
            for j in {1..10}; do
                echo "NEXT" | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null
            done
        ) &
        pids+=($!)
    done
    wait "${pids[@]}" 2>/dev/null || true
    if daemon_running; then
        pass "Concurrent clients: Daemon survived 10 parallel clients"
    else
        fail "Concurrent clients: Daemon crashed"
        start_daemon
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# TEST 4: Memory Stability (requires valgrind)
#───────────────────────────────────────────────────────────────────────────────

test_memory() {
    header "TEST 4: MEMORY STABILITY"

    if ! command -v valgrind &>/dev/null; then
        skip "Valgrind not installed - skipping memory tests"
        return
    fi

    kill_daemon

    log "Running short valgrind check (10 seconds)..."
    timeout 10s valgrind --leak-check=summary --error-exitcode=1 \
        "$DAEMON" --daemon 2>"$LOGFILE" &
    local vpid=$!
    sleep 2

    # Send some commands
    for i in {1..20}; do
        send_cmd "NEXT"
        send_cmd "TOGGLE"
        send_cmd "PREV"
    done

    # Wait and check
    sleep 5
    kill -TERM $vpid 2>/dev/null || true
    wait $vpid 2>/dev/null || true

    if grep -q "definitely lost: 0 bytes" "$LOGFILE" 2>/dev/null; then
        pass "Memory: No definite leaks detected"
    elif grep -q "ERROR SUMMARY: 0 errors" "$LOGFILE" 2>/dev/null; then
        pass "Memory: No valgrind errors"
    else
        fail "Memory: Possible leaks detected (check $LOGFILE)"
    fi

    rm -f "$SOCKET"
    start_daemon
}

#───────────────────────────────────────────────────────────────────────────────
# TEST 5: Crash Recovery
#───────────────────────────────────────────────────────────────────────────────

test_crash_recovery() {
    header "TEST 5: CRASH RECOVERY"

    start_daemon

    # Force kill (SIGKILL - simulate crash)
    log "Simulating daemon crash (SIGKILL)..."
    local pid=$(get_pid)
    kill -KILL "$pid" 2>/dev/null
    sleep 0.5

    # Check socket state after crash
    if [[ -S "$SOCKET" ]]; then
        log "Stale socket left after crash (expected)..."
    fi

    # Try to restart
    log "Attempting restart after crash..."
    start_daemon
    if daemon_running && [[ -S "$SOCKET" ]]; then
        pass "Crash recovery: Daemon restarted successfully"
    else
        fail "Crash recovery: Failed to restart"
    fi

    # Multiple rapid kill/restart cycles
    log "Testing 5 rapid kill/restart cycles..."
    local cycles_ok=0
    for i in {1..5}; do
        pid=$(get_pid)
        kill -KILL "$pid" 2>/dev/null
        sleep 0.2
        "$DAEMON" --daemon &>/dev/null &
        sleep 0.5
        if wait_for_socket && daemon_running; then
            ((cycles_ok++))
        fi
    done
    if [[ $cycles_ok -eq 5 ]]; then
        pass "Rapid restart: All 5 cycles successful"
    else
        fail "Rapid restart: Only $cycles_ok/5 cycles successful"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# TEST 6: Edge Cases
#───────────────────────────────────────────────────────────────────────────────

test_edge_cases() {
    header "TEST 6: EDGE CASES"

    start_daemon

    # Empty command
    log "Testing empty command..."
    echo -n "" | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null || true
    if daemon_running; then
        pass "Empty command: Daemon survived"
    else
        fail "Empty command: Daemon crashed"
        start_daemon
    fi

    # Null bytes
    log "Testing null bytes..."
    printf '\x00\x00\x00\x00' | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null || true
    if daemon_running; then
        pass "Null bytes: Daemon survived"
    else
        fail "Null bytes: Daemon crashed"
        start_daemon
    fi

    # Very long command (10KB)
    log "Testing oversized command (10KB)..."
    head -c 10240 /dev/urandom | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null || true
    if daemon_running; then
        pass "Oversized command: Daemon survived"
    else
        fail "Oversized command: Daemon crashed"
        start_daemon
    fi

    # Special characters / shell injection attempt
    log "Testing special characters..."
    echo '; rm -rf / ; $(reboot) `shutdown` ${HOME} | cat /etc/passwd' | \
        socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null || true
    if daemon_running; then
        pass "Special chars: Daemon survived (no injection)"
    else
        fail "Special chars: Daemon crashed"
        start_daemon
    fi

    # Newlines embedded
    log "Testing embedded newlines..."
    printf "NEXT\nNEXT\nNEXT\n" | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null || true
    if daemon_running; then
        pass "Embedded newlines: Daemon survived"
    else
        fail "Embedded newlines: Daemon crashed"
        start_daemon
    fi

    # Unicode / UTF-8
    log "Testing Unicode characters..."
    echo "🔥💀🎉 NEXT 日本語 العربية" | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null || true
    if daemon_running; then
        pass "Unicode: Daemon survived"
    else
        fail "Unicode: Daemon crashed"
        start_daemon
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# TEST 7: Long-Running Stress
#───────────────────────────────────────────────────────────────────────────────

test_endurance() {
    header "TEST 7: ENDURANCE TEST (30 seconds)"

    start_daemon
    local start_pid=$(get_pid)
    local start_time=$(date +%s)
    local cmds=0

    log "Starting endurance test..."

    while (( $(date +%s) - start_time < 30 )); do
        # Mix of valid and invalid commands
        send_cmd "NEXT"
        send_cmd "PREV"
        send_cmd "TOGGLE"
        send_cmd "HIDE"
        send_cmd "GARBAGE$(head -c 10 /dev/urandom | base64)"
        ((cmds+=5))
        
        # Occasional pause
        if (( cmds % 100 == 0 )); then
            sleep 0.1
        fi
    done

    local end_pid=$(get_pid)
    
    if [[ "$start_pid" == "$end_pid" ]] && daemon_running; then
        pass "Endurance: Survived 30s, $cmds commands, same PID"
    else
        fail "Endurance: PID changed or daemon died (sent $cmds cmds)"
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Main
#───────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║        SNAPPY SWITCHER - ULTIMATE STRESS TEST SUITE                  ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Pre-flight
    if ! command -v socat &>/dev/null; then
        echo -e "${RED}ERROR: 'socat' is required but not installed${NC}"
        echo "Install with: sudo pacman -S socat"
        exit 1
    fi

    log "Pre-flight: Ensuring daemon is running..."
    start_daemon
    log "Daemon PID: $(get_pid)"

    # Run all tests
    test_signals
    test_config_healing
    test_socket
    test_memory
    test_crash_recovery
    test_edge_cases
    test_endurance

    # Final report
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                          FINAL REPORT                                ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${GREEN}PASSED:${NC}  $PASS"
    echo -e "  ${RED}FAILED:${NC}  $FAIL"
    echo -e "  ${YELLOW}SKIPPED:${NC} $SKIP"
    echo ""

    if [[ $FAIL -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${GREEN}${BOLD}║              ✓ ALL TESTS PASSED                        ║${NC}"
        echo -e "  ${GREEN}${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
        exit 0
    else
        echo -e "  ${RED}${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "  ${RED}${BOLD}║              ✗ SOME TESTS FAILED                       ║${NC}"
        echo -e "  ${RED}${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
        exit 1
    fi
}

main "$@"
