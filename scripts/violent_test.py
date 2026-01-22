#!/usr/bin/env python3
"""
Violent Stress Test for Snappy Switcher Daemon
===============================================
This script subjects the daemon to extreme conditions to verify robustness.

Attack Vectors:
1. Flooding: 10 threads × 50 commands = 500 rapid NEXT commands
2. Ghosting: 50 connect/disconnect cycles with 0 bytes sent
3. Garbage: Send random binary junk to the socket

PASS: Daemon still running after all attacks (pgrep finds PID)
"""

import socket
import threading
import subprocess
import os
import sys
import time
import random

SOCKET_PATH = "/tmp/snappy-switcher.sock"
DAEMON_NAME = "snappy-switcher"


def log(msg: str, symbol: str = "•"):
    """Print formatted log message."""
    print(f"  {symbol} {msg}")


def check_daemon_running() -> bool:
    """Check if the daemon is running."""
    try:
        result = subprocess.run(
            ["pgrep", "-x", DAEMON_NAME],
            capture_output=True,
            text=True
        )
        return result.returncode == 0
    except Exception:
        return False


def get_daemon_pid() -> str:
    """Get the daemon PID."""
    try:
        result = subprocess.run(
            ["pgrep", "-x", DAEMON_NAME],
            capture_output=True,
            text=True
        )
        return result.stdout.strip() if result.returncode == 0 else "N/A"
    except Exception:
        return "N/A"


def send_command(cmd: str) -> bool:
    """Send a command to the daemon socket."""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(1.0)
        sock.connect(SOCKET_PATH)
        sock.send(cmd.encode())
        sock.close()
        return True
    except Exception:
        return False


def attack_flood_worker(thread_id: int, count: int, results: list):
    """Worker thread for flood attack."""
    success = 0
    for _ in range(count):
        if send_command("NEXT"):
            success += 1
        time.sleep(0.001)  # 1ms between commands
    results.append((thread_id, success))


def attack_flood():
    """
    Attack 1: Flooding
    10 threads sending 50 NEXT commands each (500 total operations)
    """
    print("\n╔══════════════════════════════════════════════════════════════╗")
    print("║  ATTACK 1: FLOODING (10 threads × 50 commands = 500 ops)     ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    
    threads = []
    results = []
    num_threads = 10
    commands_per_thread = 50
    
    log(f"Spawning {num_threads} attack threads...")
    
    start_time = time.time()
    for i in range(num_threads):
        t = threading.Thread(target=attack_flood_worker, args=(i, commands_per_thread, results))
        threads.append(t)
        t.start()
    
    for t in threads:
        t.join()
    
    elapsed = time.time() - start_time
    total_success = sum(r[1] for r in results)
    total_ops = num_threads * commands_per_thread
    
    log(f"Completed: {total_success}/{total_ops} commands in {elapsed:.2f}s")
    log(f"Rate: {total_ops/elapsed:.0f} ops/sec")
    
    return check_daemon_running()


def attack_ghost():
    """
    Attack 2: Ghosting
    Open and close socket 50 times with 0 bytes sent
    """
    print("\n╔══════════════════════════════════════════════════════════════╗")
    print("║  ATTACK 2: GHOSTING (50 empty connection cycles)             ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    
    success = 0
    failures = 0
    
    for i in range(50):
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(0.5)
            sock.connect(SOCKET_PATH)
            # Send nothing - immediate close
            sock.close()
            success += 1
        except Exception:
            failures += 1
        time.sleep(0.01)  # 10ms between attempts
    
    log(f"Ghost connections: {success}/50 successful, {failures} failed")
    
    return check_daemon_running()


def attack_garbage():
    """
    Attack 3: Garbage
    Send random binary junk to the socket
    """
    print("\n╔══════════════════════════════════════════════════════════════╗")
    print("║  ATTACK 3: GARBAGE (random binary data)                      ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    
    garbage_sizes = [0, 1, 8, 64, 256, 1024, 4096, 65536]
    results = []
    
    for size in garbage_sizes:
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(1.0)
            sock.connect(SOCKET_PATH)
            
            if size > 0:
                garbage = bytes([random.randint(0, 255) for _ in range(size)])
                sock.send(garbage)
            
            sock.close()
            results.append((size, "OK"))
        except Exception as e:
            results.append((size, f"ERR: {type(e).__name__}"))
        
        time.sleep(0.05)
    
    for size, status in results:
        log(f"{size:>5} bytes → {status}")
    
    return check_daemon_running()


def start_daemon():
    """Start the daemon if not running."""
    if check_daemon_running():
        log(f"Daemon already running (PID: {get_daemon_pid()})")
        return True
    
    log("Starting daemon...")
    try:
        # Start daemon in background
        subprocess.Popen(
            [DAEMON_NAME, "--daemon"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        
        # Wait for it to be ready
        for _ in range(20):
            time.sleep(0.25)
            if os.path.exists(SOCKET_PATH):
                log(f"Daemon started (PID: {get_daemon_pid()})")
                return True
        
        log("Failed to start daemon", "✗")
        return False
    except Exception as e:
        log(f"Error starting daemon: {e}", "✗")
        return False


def main():
    print("╔══════════════════════════════════════════════════════════════╗")
    print("║     SNAPPY SWITCHER - VIOLENT STRESS TEST                    ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    
    # Pre-flight check
    print("\n[PRE-FLIGHT]")
    if not start_daemon():
        print("\n❌ FAILED: Could not start daemon")
        sys.exit(1)
    
    initial_pid = get_daemon_pid()
    
    # Run attacks
    results = {
        "flood": attack_flood(),
        "ghost": attack_ghost(),
        "garbage": attack_garbage(),
    }
    
    # Final verdict
    print("\n╔══════════════════════════════════════════════════════════════╗")
    print("║                      FINAL REPORT                            ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    
    final_running = check_daemon_running()
    final_pid = get_daemon_pid()
    
    print(f"\n  Initial PID: {initial_pid}")
    print(f"  Final PID:   {final_pid}")
    print(f"  PID Match:   {'✓ Yes' if initial_pid == final_pid else '✗ No (respawned?)'}")
    print()
    
    for attack, survived in results.items():
        status = "✓ SURVIVED" if survived else "✗ CRASHED"
        print(f"  {attack.capitalize():12} → {status}")
    
    print()
    
    if final_running and all(results.values()):
        print("  ╔════════════════════════════════════════════════════════╗")
        print("  ║              ✓ ALL TESTS PASSED                        ║")
        print("  ╚════════════════════════════════════════════════════════╝")
        sys.exit(0)
    else:
        print("  ╔════════════════════════════════════════════════════════╗")
        print("  ║              ✗ TESTS FAILED                            ║")
        print("  ╚════════════════════════════════════════════════════════╝")
        sys.exit(1)


if __name__ == "__main__":
    main()
