#!/bin/bash
# ============================================================================
# ADSCREEN Command Center — Raspberry Pi Setup Script
# Run this ON the Raspberry Pi to install and configure the daemon.
#
# Usage:
#   chmod +x setup_adscreen.sh
#   sudo ./setup_adscreen.sh
# ============================================================================

set -euo pipefail

INSTALL_DIR="/home/zynorex/adscreen_tft"
SERVICE_NAME="adscreen-daemon"
USER="zynorex"

echo "============================================"
echo "  ADSCREEN Command Center — Pi Setup"
echo "============================================"
echo ""

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo ./setup_adscreen.sh)"
    exit 1
fi

# 1) Install system dependencies
echo "[1/6] Installing system dependencies..."
apt-get update -y
apt-get install -y python3 python3-pip python3-serial curl

# 2) Install Python packages
echo "[2/6] Installing Python packages..."
pip3 install --break-system-packages psutil pyserial 2>/dev/null || \
pip3 install psutil pyserial

# 3) Create install directory
echo "[3/6] Setting up $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

# Copy daemon script
cp -f adscreen_daemon.py "$INSTALL_DIR/adscreen_daemon.py"
chmod +x "$INSTALL_DIR/adscreen_daemon.py"
chown -R "$USER:$USER" "$INSTALL_DIR"

# 4) Create log file
echo "[4/6] Setting up logging..."
touch /var/log/adscreen_daemon.log
chown "$USER:$USER" /var/log/adscreen_daemon.log

# 5) Install systemd service
echo "[5/6] Installing systemd service..."
cp -f adscreen-daemon.service /etc/systemd/system/adscreen-daemon.service
systemctl daemon-reload
systemctl enable adscreen-daemon.service

# 6) Add user to dialout group (for serial access)
echo "[6/6] Configuring serial port access..."
usermod -aG dialout "$USER"

# 7) Udev rule for consistent Arduino detection
echo 'SUBSYSTEM=="tty", ATTRS{idVendor}=="2341", ATTRS{idProduct}=="0042", SYMLINK+="arduino_mega", MODE="0666"' \
    > /etc/udev/rules.d/99-arduino.rules
udevadm control --reload-rules
udevadm trigger

echo ""
echo "============================================"
echo "  Installation Complete!"
echo "============================================"
echo ""
echo "Commands:"
echo "  sudo systemctl start adscreen-daemon     # Start now"
echo "  sudo systemctl status adscreen-daemon    # Check status"
echo "  sudo systemctl stop adscreen-daemon      # Stop"
echo "  sudo journalctl -u adscreen-daemon -f    # Live logs"
echo ""
echo "The service will auto-start on boot."
echo "Connect the Arduino via USB, then run:"
echo "  sudo systemctl start adscreen-daemon"
echo ""
