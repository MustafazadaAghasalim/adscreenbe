#!/bin/bash
# ============================================================================
#  RPi Infrastructure Stack — Full Deployment Script
#  Run this FROM your development machine (Mac)
#
#  Deploys: Portainer · Tailscale · Nginx Proxy Manager · Watchtower
#           Grafana · Prometheus · Node Exporter · Gitea · AdGuard Home
#
#  Usage:
#    chmod +x deploy_infrastructure.sh
#    ./deploy_infrastructure.sh
# ============================================================================

set -euo pipefail

# ── Pi Connection Details ───────────────────────────────────────────────
PI_HOST="pi.local"
PI_USER="zynorex"
PI_PASS="15261526"
REMOTE_DIR="/home/$PI_USER/rpi-infrastructure"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colors ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

banner() { echo -e "\n${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}${BOLD}  $1${NC}"; echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }
step()   { echo -e "${GREEN}[✓] $1${NC}"; }
info()   { echo -e "${YELLOW}[i] $1${NC}"; }
fail()   { echo -e "${RED}[✗] $1${NC}"; exit 1; }

# ── Check sshpass ───────────────────────────────────────────────────────
if ! command -v sshpass &>/dev/null; then
    info "Installing sshpass..."
    if [[ "$(uname)" == "Darwin" ]]; then
        brew install hudochenkov/sshpass/sshpass 2>/dev/null || brew install esolitos/ipa/sshpass
    else
        sudo apt-get install -y sshpass
    fi
fi

export SSHPASS="$PI_PASS"
SSH_CMD="sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 $PI_USER@$PI_HOST"
SCP_CMD="sshpass -e scp -o StrictHostKeyChecking=no"

# ========================================================================
banner "🚀 RPi Infrastructure — Full Stack Deployment"
# ========================================================================

# ── Step 1: Test SSH ────────────────────────────────────────────────────
info "Testing SSH connection to $PI_HOST..."
if $SSH_CMD "echo 'SSH OK'" &>/dev/null; then
    step "SSH connection successful"
else
    fail "Cannot connect to $PI_HOST via SSH. Is the Pi on and SSH enabled?"
fi

# Get Pi IP for later
PI_IP=$($SSH_CMD "hostname -I | awk '{print \$1}'" 2>/dev/null || echo "$PI_HOST")
step "Pi IP address: $PI_IP"

# ── Step 2: Enable SSH permanently ─────────────────────────────────────
info "Ensuring SSH is enabled on boot..."
$SSH_CMD "sudo systemctl enable ssh && sudo systemctl start ssh" 2>/dev/null
step "SSH enabled on boot"

# ── Step 3: Install Docker ─────────────────────────────────────────────
info "Checking Docker installation..."
if $SSH_CMD "command -v docker" &>/dev/null; then
    step "Docker already installed"
else
    info "Installing Docker (this may take a few minutes)..."
    $SSH_CMD "curl -fsSL https://get.docker.com | sudo sh"
    $SSH_CMD "sudo usermod -aG docker $PI_USER"
    step "Docker installed"
fi

# Ensure docker compose plugin is available
info "Checking Docker Compose..."
if $SSH_CMD "docker compose version" &>/dev/null; then
    step "Docker Compose available"
else
    info "Installing Docker Compose plugin..."
    $SSH_CMD "sudo apt-get install -y docker-compose-plugin"
    step "Docker Compose installed"
fi

# Ensure Docker is running
$SSH_CMD "sudo systemctl enable docker && sudo systemctl start docker" 2>/dev/null
step "Docker service running"

# ── Step 4: Disable systemd-resolved (for AdGuard DNS on port 53) ─────
info "Checking for port 53 conflicts..."
if $SSH_CMD "sudo systemctl is-active systemd-resolved" &>/dev/null 2>&1; then
    info "Disabling systemd-resolved to free port 53 for AdGuard..."
    $SSH_CMD "sudo systemctl stop systemd-resolved && sudo systemctl disable systemd-resolved"
    # Set a fallback DNS
    $SSH_CMD "echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf > /dev/null"
    step "systemd-resolved disabled, using 8.8.8.8 as fallback DNS"
else
    step "No port 53 conflict"
fi

# ── Step 5: Create /dev/net/tun for Tailscale ─────────────────────────
info "Ensuring TUN device exists for Tailscale..."
$SSH_CMD "sudo mkdir -p /dev/net && sudo mknod /dev/net/tun c 10 200 2>/dev/null; sudo chmod 666 /dev/net/tun" 2>/dev/null || true
step "TUN device ready"

# ── Step 6: Upload files ───────────────────────────────────────────────
info "Uploading infrastructure files to Pi..."
$SSH_CMD "mkdir -p $REMOTE_DIR/prometheus $REMOTE_DIR/grafana/provisioning/datasources"

$SCP_CMD "$LOCAL_DIR/docker-compose.yml" "$PI_USER@$PI_HOST:$REMOTE_DIR/docker-compose.yml"
$SCP_CMD "$LOCAL_DIR/prometheus/prometheus.yml" "$PI_USER@$PI_HOST:$REMOTE_DIR/prometheus/prometheus.yml"
$SCP_CMD "$LOCAL_DIR/grafana/provisioning/datasources/prometheus.yml" "$PI_USER@$PI_HOST:$REMOTE_DIR/grafana/provisioning/datasources/prometheus.yml"
step "All files uploaded"

# ── Step 7: Pull and start the stack ──────────────────────────────────
info "Pulling Docker images (this may take a while on first run)..."
$SSH_CMD "cd $REMOTE_DIR && sudo docker compose pull"
step "All images pulled"

info "Starting the stack..."
$SSH_CMD "cd $REMOTE_DIR && sudo docker compose up -d"
step "All containers started"

# ── Step 8: Wait for services to initialize ────────────────────────────
info "Waiting 15 seconds for services to initialize..."
sleep 15

# ── Step 9: Verify ─────────────────────────────────────────────────────
banner "📋 Container Status"
$SSH_CMD "cd $REMOTE_DIR && sudo docker compose ps"

# ── Step 10: Print Summary ─────────────────────────────────────────────
banner "🎉 Deployment Complete!"

echo -e "${BOLD}Your RPi Cloud Infrastructure is Live!${NC}\n"
echo -e "  ${GREEN}Portainer${NC}            https://$PI_IP:9443  or  http://$PI_IP:9000"
echo -e "  ${GREEN}Nginx Proxy Manager${NC}  http://$PI_IP:81"
echo -e "  ${GREEN}Grafana${NC}              http://$PI_IP:3000"
echo -e "  ${GREEN}Prometheus${NC}           http://$PI_IP:9090"
echo -e "  ${GREEN}Gitea${NC}                http://$PI_IP:3001"
echo -e "  ${GREEN}AdGuard Home${NC}         http://$PI_IP:3002"
echo ""
echo -e "${BOLD}Default Credentials:${NC}"
echo -e "  Portainer:  Set on first visit"
echo -e "  NPM:        admin@example.com / changeme"
echo -e "  Grafana:    admin / admin"
echo -e "  Gitea:      Set on first visit"
echo -e "  AdGuard:    Set on first visit"
echo ""
echo -e "${YELLOW}${BOLD}⚠ Tailscale:${NC} Run this to authenticate:"
echo -e "  ${CYAN}ssh $PI_USER@$PI_IP${NC}"
echo -e "  ${CYAN}sudo docker exec tailscale tailscale up${NC}"
echo -e "  Then follow the URL to log in.\n"
echo -e "${YELLOW}${BOLD}⚠ Watchtower:${NC} Running silently, auto-updating all containers every 24h.\n"
