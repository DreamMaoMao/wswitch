#!/usr/bin/env bash
#═══════════════════════════════════════════════════════════════════════════════
#  SNAPPY SWITCHER - PERFORMANCE BENCHMARK
#═══════════════════════════════════════════════════════════════════════════════
#  Measures latency, throughput, and resource usage
#═══════════════════════════════════════════════════════════════════════════════

set -uo pipefail

DAEMON="snappy-switcher"
SOCKET="/tmp/snappy-switcher.sock"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

header() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
}

ensure_daemon() {
    if ! pgrep -x "$DAEMON" >/dev/null; then
        echo "Starting daemon..."
        "$DAEMON" --daemon &
        sleep 1
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Benchmark: Single Command Latency
#───────────────────────────────────────────────────────────────────────────────

bench_latency() {
    header "BENCHMARK 1: SINGLE COMMAND LATENCY"
    
    local samples=100
    local total=0
    
    echo -e "${CYAN}Running $samples samples...${NC}"
    
    for i in $(seq 1 $samples); do
        start=$(date +%s%N)
        echo "NEXT" | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null
        end=$(date +%s%N)
        elapsed=$(( (end - start) / 1000 ))  # microseconds
        total=$((total + elapsed))
    done
    
    avg=$((total / samples))
    echo ""
    echo -e "  ${GREEN}Average Latency:${NC} ${avg} µs (${YELLOW}$(echo "scale=2; $avg/1000" | bc) ms${NC})"
    echo -e "  ${GREEN}Total for $samples:${NC} $(echo "scale=2; $total/1000000" | bc) s"
}

#───────────────────────────────────────────────────────────────────────────────
# Benchmark: Throughput (Commands per Second)
#───────────────────────────────────────────────────────────────────────────────

bench_throughput() {
    header "BENCHMARK 2: THROUGHPUT (Commands/sec)"
    
    local duration=5
    local count=0
    local end_time=$(($(date +%s) + duration))
    
    echo -e "${CYAN}Running for $duration seconds...${NC}"
    
    while [[ $(date +%s) -lt $end_time ]]; do
        echo "NEXT" | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null && ((count++))
    done
    
    local rate=$((count / duration))
    echo ""
    echo -e "  ${GREEN}Total Commands:${NC} $count"
    echo -e "  ${GREEN}Throughput:${NC} ${YELLOW}$rate ops/sec${NC}"
}

#───────────────────────────────────────────────────────────────────────────────
# Benchmark: Concurrent Connections
#───────────────────────────────────────────────────────────────────────────────

bench_concurrent() {
    header "BENCHMARK 3: CONCURRENT CONNECTIONS"
    
    local clients=(1 5 10 25 50)
    
    for n in "${clients[@]}"; do
        local count=0
        local start=$(date +%s%N)
        
        # Start all clients in parallel
        for i in $(seq 1 $n); do
            (
                for j in {1..10}; do
                    echo "NEXT" | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null
                done
            ) &
        done
        wait
        
        local end=$(date +%s%N)
        local elapsed=$(( (end - start) / 1000000 ))  # milliseconds
        local ops=$((n * 10))
        local rate=$((ops * 1000 / elapsed))
        
        printf "  ${GREEN}%3d clients × 10 cmds:${NC} %4d ms (${YELLOW}%d ops/sec${NC})\n" "$n" "$elapsed" "$rate"
    done
}

#───────────────────────────────────────────────────────────────────────────────
# Benchmark: Resource Usage
#───────────────────────────────────────────────────────────────────────────────

bench_resources() {
    header "BENCHMARK 4: RESOURCE USAGE"
    
    local pid=$(pgrep -x "$DAEMON")
    
    if [[ -z "$pid" ]]; then
        echo "  Daemon not running!"
        return
    fi
    
    echo -e "  ${GREEN}PID:${NC} $pid"
    
    # Memory usage
    local mem_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
    local mem_mb=$(echo "scale=2; $mem_kb / 1024" | bc)
    echo -e "  ${GREEN}Memory (RSS):${NC} ${YELLOW}$mem_mb MB${NC}"
    
    # Virtual memory
    local vsz_kb=$(ps -o vsz= -p "$pid" 2>/dev/null | tr -d ' ')
    local vsz_mb=$(echo "scale=2; $vsz_kb / 1024" | bc)
    echo -e "  ${GREEN}Virtual Memory:${NC} $vsz_mb MB"
    
    # CPU (snapshot)
    local cpu=$(ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' ')
    echo -e "  ${GREEN}CPU (snapshot):${NC} $cpu%"
    
    # Open file descriptors
    local fds=$(ls /proc/"$pid"/fd 2>/dev/null | wc -l)
    echo -e "  ${GREEN}Open FDs:${NC} $fds"
    
    # Threads
    local threads=$(ls /proc/"$pid"/task 2>/dev/null | wc -l)
    echo -e "  ${GREEN}Threads:${NC} $threads"
    
    # Stress: measure memory after 1000 commands
    echo ""
    echo -e "  ${CYAN}After 1000 commands:${NC}"
    for i in {1..1000}; do
        echo "NEXT" | socat - "UNIX-CONNECT:$SOCKET" 2>/dev/null
    done
    
    mem_kb=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
    mem_mb=$(echo "scale=2; $mem_kb / 1024" | bc)
    echo -e "  ${GREEN}Memory (RSS):${NC} ${YELLOW}$mem_mb MB${NC}"
    
    fds=$(ls /proc/"$pid"/fd 2>/dev/null | wc -l)
    echo -e "  ${GREEN}Open FDs:${NC} $fds"
}

#───────────────────────────────────────────────────────────────────────────────
# Main
#───────────────────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║           SNAPPY SWITCHER - PERFORMANCE BENCHMARK                    ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"

    if ! command -v socat &>/dev/null; then
        echo -e "\n${YELLOW}ERROR: 'socat' is required. Install with: sudo pacman -S socat${NC}"
        exit 1
    fi
    
    if ! command -v bc &>/dev/null; then
        echo -e "\n${YELLOW}ERROR: 'bc' is required. Install with: sudo pacman -S bc${NC}"
        exit 1
    fi

    ensure_daemon

    bench_latency
    bench_throughput
    bench_concurrent
    bench_resources

    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  BENCHMARK COMPLETE${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

main "$@"
