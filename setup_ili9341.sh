#!/bin/bash
# ──────────────────────────────────────────────
#  Setup script for ILI9341 Parallel Stats Display
#  Run this on the Raspberry Pi:
#    chmod +x setup_ili9341.sh && sudo ./setup_ili9341.sh
# ──────────────────────────────────────────────

set -e

echo "═══════════════════════════════════════════"
echo "  ILI9341 Parallel Display — Setup"
echo "═══════════════════════════════════════════"

echo ""
echo "[1/3] Updating package list..."
sudo apt-get update -qq

echo ""
echo "[2/3] Installing system dependencies..."
sudo apt-get install -y python3-pip python3-dev

echo ""
echo "[3/3] Installing Python packages..."
# Pi 5 compatibility check and cleanup
if grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null; then
    echo "  > Pi 5 detected. Installing rpi-lgpio..."
    sudo apt-get install -y python3-rpi-lgpio
    # Ensure no pip-version is shadowing the system rpi-lgpio
    sudo pip3 uninstall -y RPi.GPIO --break-system-packages 2>/dev/null || true
else
    pip3 install --break-system-packages psutil RPi.GPIO 2>/dev/null \
      || pip3 install psutil RPi.GPIO
fi

echo ""
echo "═══════════════════════════════════════════"
echo "  Setup complete!"
echo ""
echo "  Run the stats display with:"
echo "    sudo python3 ili9341_stats.py"
echo ""
echo "  To run at boot, add to /etc/rc.local:"
echo "    sudo python3 /home/$(whoami)/ili9341_stats.py &"
echo "═══════════════════════════════════════════"
