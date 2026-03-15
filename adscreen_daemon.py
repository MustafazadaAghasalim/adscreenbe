#!/usr/bin/env python3
"""
ADSCREEN Command Center — Raspberry Pi Companion Daemon
========================================================
Gathers real system metrics and sends JSON telemetry to Arduino Mega
via USB Serial (115200 baud). Listens for touch-triggered commands
from the Arduino and executes them.

Protocol:
  - Messages wrapped in < > markers: <{"c":45,"r":80,...}>
  - Arduino sends commands: <{"cmd":"reboot_pi"}>
  - Pi sends telemetry + acks: <{"c":45,"r":80,"t":65,...}>

Auto-recovery:
  - Reconnects on USB disconnect
  - Survives Pi reboot via systemd service
  - Handles serial timeouts gracefully

Usage:
  python3 adscreen_daemon.py
  # Or install as systemd service (see setup_adscreen.sh)
"""

import json
import logging
import os
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path

import psutil
import serial
import serial.tools.list_ports

# ============================================================================
# CONFIGURATION
# ============================================================================
BAUD_RATE = 115200
SEND_INTERVAL = 2.0        # Seconds between telemetry pushes
RECONNECT_DELAY = 3.0      # Seconds to wait before reconnecting
SERIAL_TIMEOUT = 1.0       # Serial read timeout
LOG_FILE = "/var/log/adscreen_daemon.log"

# ============================================================================
# LOGGING
# ============================================================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(LOG_FILE, mode="a", encoding="utf-8"),
    ] if os.access(os.path.dirname(LOG_FILE), os.W_OK) else [
        logging.StreamHandler(sys.stdout),
    ]
)
log = logging.getLogger("adscreen")

# ============================================================================
# GLOBALS
# ============================================================================
running = True
ser = None


def signal_handler(sig, frame):
    global running
    log.info("Shutdown signal received, exiting...")
    running = False


signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)


# ============================================================================
# SERIAL PORT DISCOVERY
# ============================================================================
def find_arduino():
    """Auto-detect Arduino Mega on USB serial."""
    patterns = ["/dev/ttyACM", "/dev/ttyUSB"]
    for port in serial.tools.list_ports.comports():
        for pat in patterns:
            if port.device.startswith(pat):
                log.info(f"Found Arduino at {port.device} [{port.description}]")
                return port.device
    # Fallback: try common paths
    for path in ["/dev/ttyACM0", "/dev/ttyACM1", "/dev/ttyUSB0", "/dev/ttyUSB1"]:
        if os.path.exists(path):
            log.info(f"Fallback: found serial port at {path}")
            return path
    return None


def connect_serial():
    """Connect to Arduino with retry logic."""
    global ser
    while running:
        port = find_arduino()
        if port:
            try:
                ser = serial.Serial(port, BAUD_RATE, timeout=SERIAL_TIMEOUT)
                time.sleep(2)  # Arduino resets on serial connect
                ser.reset_input_buffer()
                log.info(f"Connected to {port} at {BAUD_RATE} baud")
                return True
            except serial.SerialException as e:
                log.error(f"Failed to open {port}: {e}")
        else:
            log.warning("No Arduino found, retrying...")
        time.sleep(RECONNECT_DELAY)
    return False


# ============================================================================
# SYSTEM METRICS COLLECTION
# ============================================================================
def run_cmd(cmd, timeout=5):
    """Run shell command and return stdout, or empty string on failure."""
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        )
        return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return ""


def get_cpu_temp():
    """Read CPU temperature (Raspberry Pi)."""
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
            return int(f.read().strip()) // 1000
    except (FileNotFoundError, ValueError):
        temp = run_cmd("vcgencmd measure_temp 2>/dev/null")
        if temp:
            try:
                return int(float(temp.replace("temp=", "").replace("'C", "")))
            except ValueError:
                pass
    return 0


def get_local_ip():
    """Get primary local IP address."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(1)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "0.0.0.0"


def get_public_ip():
    """Get public IP (cached for 60s to avoid rate limits)."""
    if not hasattr(get_public_ip, "_cache"):
        get_public_ip._cache = ("N/A", 0)
    ip, ts = get_public_ip._cache
    if time.time() - ts < 60:
        return ip
    result = run_cmd("curl -s --max-time 3 ifconfig.me 2>/dev/null")
    if result and len(result) < 20:
        get_public_ip._cache = (result, time.time())
        return result
    return ip


def get_ping():
    """Ping 8.8.8.8 and return latency in ms."""
    result = run_cmd("ping -c 1 -W 2 8.8.8.8 2>/dev/null | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}'")
    return result if result else "N/A"


def get_ssh_users():
    """Count active SSH sessions."""
    result = run_cmd("who | grep -c pts 2>/dev/null")
    return result if result else "0"


def get_network_bytes():
    """Get RX/TX in MB."""
    net = psutil.net_io_counters()
    rx_mb = net.bytes_recv // (1024 * 1024)
    tx_mb = net.bytes_sent // (1024 * 1024)
    return rx_mb, tx_mb


def get_wifi_status():
    """Check WiFi / network connectivity."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(1)
        s.connect(("8.8.8.8", 53))
        s.close()
        return "OK"
    except OSError:
        return "DOWN"


def get_docker_status():
    """Check if Docker daemon is running and count containers."""
    status = run_cmd("systemctl is-active docker 2>/dev/null")
    if status == "active":
        count = run_cmd("docker ps -q 2>/dev/null | wc -l")
        try:
            return "UP", int(count)
        except ValueError:
            return "UP", 0
    return "DOWN", 0


def get_nginx_status():
    """Check Nginx status."""
    status = run_cmd("systemctl is-active nginx 2>/dev/null")
    return "UP" if status == "active" else "DOWN"


def get_http_status():
    """Check local HTTP response code."""
    result = run_cmd("curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://localhost/ 2>/dev/null")
    try:
        return int(result)
    except ValueError:
        return 0


def get_ssl_days():
    """Check SSL certificate expiry days (if applicable)."""
    hostname = socket.gethostname()
    result = run_cmd(
        f"echo | openssl s_client -connect localhost:443 -servername {hostname} 2>/dev/null "
        "| openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2"
    )
    if result:
        try:
            from datetime import datetime
            expiry = datetime.strptime(result, "%b %d %H:%M:%S %Y %Z")
            delta = expiry - datetime.utcnow()
            return max(0, delta.days)
        except (ValueError, ImportError):
            pass
    return 0


def get_uptime_short():
    """Get system uptime in short format."""
    uptime_sec = int(time.time() - psutil.boot_time())
    days = uptime_sec // 86400
    hours = (uptime_sec % 86400) // 3600
    mins = (uptime_sec % 3600) // 60
    if days > 0:
        return f"{days}d{hours}h"
    if hours > 0:
        return f"{hours}h{mins}m"
    return f"{mins}m"


def collect_telemetry():
    """Gather all metrics into a compact JSON dict."""
    cpu = int(psutil.cpu_percent(interval=0))
    ram = int(psutil.virtual_memory().percent)
    temp = get_cpu_temp()
    disk = int(psutil.disk_usage("/").percent)
    wifi = get_wifi_status()
    docker_status, docker_count = get_docker_status()
    uptime = get_uptime_short()
    hostname = socket.gethostname()

    ip = get_local_ip()
    pubip = get_public_ip()
    ping = get_ping()
    ssh = get_ssh_users()
    rx, tx = get_network_bytes()

    http = get_http_status()
    nginx = get_nginx_status()
    ssl = get_ssl_days()

    return {
        # Dashboard
        "c": cpu, "r": ram, "t": temp, "dk": disk,
        "w": wifi, "d": docker_status, "up": uptime, "h": hostname,
        # Server status
        "ht": http, "ng": nginx, "sl": ssl, "cn": docker_count,
        # Network
        "ip": ip, "pi": pubip, "pg": ping, "ss": ssh,
        "rx": rx, "tx": tx
    }


# ============================================================================
# SEND / RECEIVE
# ============================================================================
def send_telemetry(data):
    """Send telemetry JSON wrapped in < > markers."""
    global ser
    try:
        payload = "<" + json.dumps(data, separators=(",", ":")) + ">\n"
        ser.write(payload.encode("utf-8"))
        ser.flush()
    except (serial.SerialException, OSError) as e:
        log.error(f"Send error: {e}")
        raise


def send_ack(msg):
    """Send acknowledgement to Arduino."""
    send_telemetry({"ack": "ok", "msg": msg})


def read_command():
    """Non-blocking read of command from Arduino. Returns dict or None."""
    global ser
    try:
        if ser.in_waiting == 0:
            return None
        raw = ser.readline().decode("utf-8", errors="ignore").strip()
        if not raw:
            return None

        # Extract JSON between < >
        start = raw.find("<")
        end = raw.find(">")
        if start >= 0 and end > start:
            json_str = raw[start + 1:end]
            return json.loads(json_str)

        # Fallback: legacy format "REQ:PAGEn" or "CMD:xxx"
        if raw.startswith("REQ:"):
            return {"cmd": "request_data"}
        if raw.startswith("CMD:"):
            return {"cmd": raw[4:].lower()}

        return None
    except (json.JSONDecodeError, serial.SerialException, OSError):
        return None


# ============================================================================
# COMMAND EXECUTION
# ============================================================================
def execute_command(cmd_data):
    """Execute a command received from Arduino."""
    cmd = cmd_data.get("cmd", "")
    target = cmd_data.get("target", "")
    log.info(f"Executing command: {cmd} target={target}")

    if cmd == "reboot_pi":
        send_ack("Rebooting in 3s...")
        time.sleep(1)
        os.system("sudo reboot")

    elif cmd == "shutdown_pi":
        send_ack("Shutting down...")
        time.sleep(1)
        os.system("sudo shutdown -h now")

    elif cmd == "restart_docker":
        send_ack("Restarting Docker...")
        os.system("sudo systemctl restart docker")
        time.sleep(2)
        send_ack("Docker restarted")

    elif cmd == "restart_service":
        svc = target if target else "nginx"
        # Sanitize service name (allow only alphanumeric, dash, underscore)
        sanitized = "".join(c for c in svc if c.isalnum() or c in "-_")
        if sanitized:
            send_ack(f"Restarting {sanitized}...")
            os.system(f"sudo systemctl restart {sanitized}")
            time.sleep(2)
            send_ack(f"{sanitized} restarted")
        else:
            send_ack("Invalid service name")

    elif cmd == "clear_cache":
        send_ack("Clearing caches...")
        os.system("sudo sync && sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches'")
        send_ack("Caches cleared")

    elif cmd == "update_os":
        send_ack("Starting apt update...")
        os.system("sudo apt-get update -y && sudo apt-get upgrade -y &")
        send_ack("Update started (background)")

    elif cmd == "request_data":
        # Immediate data push
        data = collect_telemetry()
        send_telemetry(data)

    elif cmd == "ping_test":
        result = run_cmd("ping -c 3 8.8.8.8 2>/dev/null | tail -1")
        send_ack(result[:40] if result else "Ping failed")

    else:
        log.warning(f"Unknown command: {cmd}")
        send_ack(f"Unknown: {cmd}")


# ============================================================================
# MAIN LOOP
# ============================================================================
def main():
    global ser, running

    log.info("=" * 50)
    log.info("ADSCREEN Command Center Daemon starting...")
    log.info("=" * 50)

    # Initial CPU measurement (first call returns 0)
    psutil.cpu_percent(interval=0)

    while running:
        # Connect
        if ser is None or not ser.is_open:
            if not connect_serial():
                continue

        last_send = 0

        try:
            while running and ser and ser.is_open:
                now = time.time()

                # Read commands from Arduino (non-blocking)
                cmd = read_command()
                if cmd:
                    execute_command(cmd)

                # Send telemetry at interval
                if now - last_send >= SEND_INTERVAL:
                    data = collect_telemetry()
                    send_telemetry(data)
                    last_send = now

                time.sleep(0.05)  # Small sleep to avoid busy-wait

        except (serial.SerialException, OSError) as e:
            log.error(f"Serial connection lost: {e}")
            try:
                if ser:
                    ser.close()
            except Exception:
                pass
            ser = None
            log.info(f"Reconnecting in {RECONNECT_DELAY}s...")
            time.sleep(RECONNECT_DELAY)

    # Cleanup
    log.info("Daemon shutting down")
    if ser and ser.is_open:
        try:
            ser.close()
        except Exception:
            pass


if __name__ == "__main__":
    main()
