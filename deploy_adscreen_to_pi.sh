#!/bin/bash
# ============================================================================
# Deploy ADSCREEN daemon files to Raspberry Pi and start the service
# Run this FROM your development machine (Mac/Windows)
#
# Usage:
#   chmod +x deploy_adscreen_to_pi.sh
#   ./deploy_adscreen_to_pi.sh
# ============================================================================

set -euo pipefail

PI_HOST="pi.local"
PI_USER="zynorex"
PI_PASS="15261526"
REMOTE_DIR="/home/$PI_USER/adscreen_tft"

echo "============================================"
echo "  Deploying ADSCREEN to Pi ($PI_HOST)"
echo "============================================"

# Check for sshpass
if ! command -v sshpass &>/dev/null; then
    echo "Installing sshpass..."
    if [[ "$(uname)" == "Darwin" ]]; then
        brew install hudochenkov/sshpass/sshpass 2>/dev/null || brew install esolitos/ipa/sshpass
    else
        sudo apt-get install -y sshpass
    fi
fi

SSHPASS_CMD="sshpass -p $PI_PASS"
SSH_CMD="$SSHPASS_CMD ssh -o StrictHostKeyChecking=no $PI_USER@$PI_HOST"
SCP_CMD="$SSHPASS_CMD scp -o StrictHostKeyChecking=no"

# 1) Create remote directory
echo "[1/4] Creating remote directory..."
$SSH_CMD "mkdir -p $REMOTE_DIR"

# 2) Copy files
echo "[2/4] Copying files to Pi..."
$SCP_CMD adscreen_daemon.py "$PI_USER@$PI_HOST:$REMOTE_DIR/adscreen_daemon.py"
$SCP_CMD adscreen-daemon.service "$PI_USER@$PI_HOST:$REMOTE_DIR/adscreen-daemon.service"
$SCP_CMD setup_adscreen.sh "$PI_USER@$PI_HOST:$REMOTE_DIR/setup_adscreen.sh"

# 3) Run setup on Pi
echo "[3/4] Running setup on Pi (this may take a minute)..."
$SSH_CMD "cd $REMOTE_DIR && chmod +x setup_adscreen.sh && sudo ./setup_adscreen.sh"

# 4) Start the service
echo "[4/4] Starting ADSCREEN service..."
$SSH_CMD "sudo systemctl restart adscreen-daemon"
sleep 2
$SSH_CMD "sudo systemctl status adscreen-daemon --no-pager"

echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "============================================"
echo ""
echo "  View live logs: ssh $PI_USER@$PI_HOST 'journalctl -u adscreen-daemon -f'"
echo ""
