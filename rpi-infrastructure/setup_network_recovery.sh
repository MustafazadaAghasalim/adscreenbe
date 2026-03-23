#!/bin/bash
# ==============================================================================
# Adscreen — Raspberry Pi Network Recovery & Hardening
# ==============================================================================
# Ensures the Pi always has DNS, proper routing, and fallback connectivity.
# Designed to prevent the DNS/network outage that took down adscreen.az.
#
# What this script does:
#   1. Hardens DNS config (persistent nameservers on all connections)
#   2. Installs a NetworkManager dispatcher to fix empty resolv.conf
#   3. Adds a systemd watchdog for cloudflared
#   4. Configures Wi-Fi as automatic fallback
#   5. Adds monitoring cron jobs
#
# Usage: sudo bash setup_network_recovery.sh
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    err "Run as root: sudo bash $0"
fi

echo -e "\n${CYAN}=================================================${NC}"
echo -e "${CYAN}  Adscreen — Network Recovery & Hardening${NC}"
echo -e "${CYAN}=================================================${NC}\n"

# ==============================================================================
# 1. Harden DNS on all NetworkManager connections
# ==============================================================================
info "Step 1: Adding persistent DNS to all connections..."

for conn in $(nmcli -t -f NAME connection show | grep -v '^lo$'); do
    current_dns=$(nmcli -g ipv4.dns connection show "$conn" 2>/dev/null || echo "")
    if [[ -z "$current_dns" || "$current_dns" == "--" ]]; then
        nmcli connection modify "$conn" ipv4.dns "1.1.1.1 8.8.8.8 8.8.4.4" 2>/dev/null || true
        log "Added DNS to connection: $conn"
    else
        info "Connection '$conn' already has DNS: $current_dns"
    fi
done

# ==============================================================================
# 2. NetworkManager dispatcher: ensure resolv.conf is never empty
# ==============================================================================
info "Step 2: Installing DNS watchdog dispatcher..."

cat > /etc/NetworkManager/dispatcher.d/99-dns-fallback <<'DISPATCHER'
#!/bin/bash
# Ensure /etc/resolv.conf always has nameservers
# Triggered on any interface up/down event

RESOLV="/etc/resolv.conf"

# Count actual nameserver lines
NS_COUNT=$(grep -c '^nameserver' "$RESOLV" 2>/dev/null || echo 0)

if [[ "$NS_COUNT" -eq 0 ]]; then
    logger -t dns-fallback "WARN: resolv.conf has no nameservers, adding fallback"
    # Append fallback DNS
    echo "# Fallback DNS added by dns-fallback dispatcher" >> "$RESOLV"
    echo "nameserver 1.1.1.1" >> "$RESOLV"
    echo "nameserver 8.8.8.8" >> "$RESOLV"
fi
DISPATCHER

chmod 755 /etc/NetworkManager/dispatcher.d/99-dns-fallback
log "DNS fallback dispatcher installed"

# ==============================================================================
# 3. Cloudflared watchdog (restart if tunnel fails)
# ==============================================================================
info "Step 3: Installing cloudflared watchdog..."

cat > /etc/systemd/system/cloudflared-watchdog.service <<'WATCHDOG_SVC'
[Unit]
Description=Cloudflared Tunnel Watchdog
After=cloudflared.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cloudflared-watchdog.sh
WATCHDOG_SVC

cat > /etc/systemd/system/cloudflared-watchdog.timer <<'WATCHDOG_TMR'
[Unit]
Description=Run cloudflared watchdog every 5 minutes

[Timer]
OnBootSec=120
OnUnitActiveSec=300
AccuracySec=30

[Install]
WantedBy=timers.target
WATCHDOG_TMR

cat > /usr/local/bin/cloudflared-watchdog.sh <<'WATCHDOG_SH'
#!/bin/bash
# Check if cloudflared tunnel is healthy
# If the service is crash-looping or DNS is broken, fix and restart

LOG_TAG="cf-watchdog"

# Check if cloudflared is active
if ! systemctl is-active --quiet cloudflared; then
    logger -t "$LOG_TAG" "cloudflared is not active, attempting restart"

    # First check DNS
    if ! host -W 3 cloudflare.com 1.1.1.1 >/dev/null 2>&1; then
        logger -t "$LOG_TAG" "DNS broken, fixing resolv.conf"
        if ! grep -q '^nameserver' /etc/resolv.conf 2>/dev/null; then
            echo "nameserver 1.1.1.1" >> /etc/resolv.conf
            echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        fi
    fi

    # Check if we have any default route
    if ! ip route show default | grep -q '^default'; then
        logger -t "$LOG_TAG" "No default route, enabling wifi"
        nmcli radio wifi on 2>/dev/null || true
        sleep 10
    fi

    systemctl restart cloudflared
    logger -t "$LOG_TAG" "cloudflared restarted"
fi
WATCHDOG_SH

chmod 755 /usr/local/bin/cloudflared-watchdog.sh
systemctl daemon-reload
systemctl enable cloudflared-watchdog.timer
systemctl start cloudflared-watchdog.timer

log "Cloudflared watchdog timer enabled (every 5 min)"

# ==============================================================================
# 4. Ensure Wi-Fi is enabled and auto-connects
# ==============================================================================
info "Step 4: Configuring Wi-Fi as fallback..."

nmcli radio wifi on 2>/dev/null || true

# Increase Wi-Fi priority so it auto-connects when eth0 has no gateway
for wifi_conn in $(nmcli -t -f NAME,TYPE connection show | grep ':wifi' | cut -d: -f1); do
    nmcli connection modify "$wifi_conn" connection.autoconnect yes 2>/dev/null || true
    log "Wi-Fi '$wifi_conn' set to autoconnect"
done

# ==============================================================================
# 5. Connectivity monitoring cron
# ==============================================================================
info "Step 5: Installing connectivity monitor..."

cat > /usr/local/bin/adscreen-netcheck.sh <<'NETCHECK'
#!/bin/bash
# Quick connectivity check — logs to journal if issues found
LOG_TAG="adscreen-netcheck"
FAILURES=0

# Check internet
if ! ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1; then
    FAILURES=$((FAILURES + 1))
    logger -t "$LOG_TAG" "WARN: Cannot reach 1.1.1.1"
fi

# Check DNS
if ! host -W 5 adscreen.az >/dev/null 2>&1; then
    FAILURES=$((FAILURES + 1))
    logger -t "$LOG_TAG" "WARN: DNS resolution failed for adscreen.az"
fi

# Check cloudflared
if ! systemctl is-active --quiet cloudflared; then
    FAILURES=$((FAILURES + 1))
    logger -t "$LOG_TAG" "WARN: cloudflared is not active"
fi

# Check PM2
if ! su - zynorex -c "pm2 pid adscreen-api" >/dev/null 2>&1; then
    FAILURES=$((FAILURES + 1))
    logger -t "$LOG_TAG" "WARN: PM2 adscreen-api not running"
fi

if [[ $FAILURES -gt 0 ]]; then
    logger -t "$LOG_TAG" "Health check: $FAILURES failures detected"
else
    logger -t "$LOG_TAG" "Health check: ALL OK"
fi
NETCHECK

chmod 755 /usr/local/bin/adscreen-netcheck.sh

# Add cron job (every 10 minutes)
CRON_LINE="*/10 * * * * /usr/local/bin/adscreen-netcheck.sh"
(crontab -l 2>/dev/null | grep -v "adscreen-netcheck"; echo "$CRON_LINE") | crontab -

log "Network health check cron installed (every 10 min)"

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}  Network Recovery Setup Complete${NC}"
echo -e "${CYAN}=================================================${NC}"
echo ""
echo -e "  ${GREEN}[✓]${NC} Persistent DNS on all connections"
echo -e "  ${GREEN}[✓]${NC} DNS fallback dispatcher (auto-fix empty resolv.conf)"
echo -e "  ${GREEN}[✓]${NC} Cloudflared watchdog (auto-restart every 5 min)"
echo -e "  ${GREEN}[✓]${NC} Wi-Fi auto-connect as fallback"
echo -e "  ${GREEN}[✓]${NC} Connectivity monitor cron (every 10 min)"
echo ""
echo -e "  Check logs:  ${CYAN}journalctl -t cf-watchdog -t dns-fallback -t adscreen-netcheck --since '1 hour ago'${NC}"
echo ""
