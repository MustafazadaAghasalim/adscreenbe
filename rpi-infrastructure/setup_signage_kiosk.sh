#!/bin/bash
# ==============================================================================
# Adscreen — Raspberry Pi Digital Signage Kiosk Setup
# ==============================================================================
# Complete setup script for a new Pi to join the Adscreen signage network.
# This configures a Pi as a kiosk display that connects to the AP-305
# hidden SSID and displays content from the adscreen.az dashboard.
#
# What this script does:
#   1. System update & base packages
#   2. Connect to hidden "Adscreen_Net" Wi-Fi
#   3. Install Chromium kiosk mode (full-screen signage display)
#   4. Configure auto-login and kiosk autostart
#   5. Install signage client agent (health reporting)
#   6. Set timezone, hostname, and locale
#
# Usage: sudo bash setup_signage_kiosk.sh [--hostname KIOSK-01] [--url URL]
#
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# -- Configuration --
KIOSK_HOSTNAME="adscreen-kiosk-01"
DISPLAY_URL="https://adscreen.az/display"
WIFI_SSID="Adscreen_Net"
WIFI_PASS="Adscreen@WiFi2024"
TIMEZONE="Asia/Baku"
KIOSK_USER="kiosk"
REPORT_ENDPOINT="https://adscreen.az/api/kiosk/heartbeat"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hostname) KIOSK_HOSTNAME="$2"; shift 2 ;;
        --url)      DISPLAY_URL="$2"; shift 2 ;;
        *)          shift ;;
    esac
done

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    err "Run as root: sudo bash $0"
fi

echo -e "\n${CYAN}================================================${NC}"
echo -e "${CYAN}  Adscreen — Signage Kiosk Setup${NC}"
echo -e "${CYAN}================================================${NC}"
echo -e "  Hostname: ${GREEN}$KIOSK_HOSTNAME${NC}"
echo -e "  URL:      ${GREEN}$DISPLAY_URL${NC}"
echo -e "\n"

# ==============================================================================
# Step 1: System Update & Base Packages
# ==============================================================================
info "Step 1: Updating system and installing packages..."

apt-get update -y
apt-get upgrade -y
apt-get install -y \
    chromium-browser \
    unclutter \
    xdotool \
    xserver-xorg \
    xinit \
    x11-xserver-utils \
    lightdm \
    openbox \
    curl \
    jq \
    NetworkManager

log "Base packages installed"

# ==============================================================================
# Step 2: Connect to Hidden Wi-Fi "Adscreen_Net"
# ==============================================================================
info "Step 2: Connecting to hidden SSID '$WIFI_SSID'..."

# Create NetworkManager connection for hidden SSID
nmcli connection add \
    type wifi \
    con-name "Adscreen_Net" \
    ifname wlan0 \
    ssid "$WIFI_SSID" \
    wifi.hidden yes \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$WIFI_PASS" \
    connection.autoconnect yes \
    connection.autoconnect-priority 10 \
    ipv4.dns "1.1.1.1 8.8.8.8" 2>/dev/null || {
    # Connection might already exist, modify instead
    nmcli connection modify "Adscreen_Net" \
        wifi.hidden yes \
        wifi-sec.psk "$WIFI_PASS" \
        connection.autoconnect yes 2>/dev/null || true
}

# Bring up the connection
nmcli connection up "Adscreen_Net" 2>/dev/null && \
    log "Connected to $WIFI_SSID" || \
    warn "Could not connect to $WIFI_SSID now (AP may not be ready)"

# ==============================================================================
# Step 3: Create Kiosk User
# ==============================================================================
info "Step 3: Setting up kiosk user..."

if ! id "$KIOSK_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$KIOSK_USER"
    log "Created user: $KIOSK_USER"
else
    info "User $KIOSK_USER already exists"
fi

# ==============================================================================
# Step 4: Configure Auto-Login
# ==============================================================================
info "Step 4: Configuring auto-login..."

mkdir -p /etc/lightdm/lightdm.conf.d

cat > /etc/lightdm/lightdm.conf.d/50-autologin.conf <<LIGHTDM
[Seat:*]
autologin-user=$KIOSK_USER
autologin-user-timeout=0
user-session=openbox
LIGHTDM

log "Auto-login configured for $KIOSK_USER"

# ==============================================================================
# Step 5: Chromium Kiosk Autostart
# ==============================================================================
info "Step 5: Setting up Chromium kiosk mode..."

KIOSK_HOME="/home/$KIOSK_USER"
mkdir -p "$KIOSK_HOME/.config/openbox"

cat > "$KIOSK_HOME/.config/openbox/autostart" <<KIOSK
#!/bin/bash
# Adscreen Kiosk Autostart

# Disable screen blanking and power management
xset s off
xset -dpms
xset s noblank

# Hide mouse cursor after 3 seconds of inactivity
unclutter -idle 3 -root &

# Wait for network
sleep 5

# Launch Chromium in kiosk mode
chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --disable-translate \
    --no-first-run \
    --start-fullscreen \
    --disable-features=TranslateUI \
    --check-for-update-interval=31536000 \
    --disable-component-update \
    --autoplay-policy=no-user-gesture-required \
    --disable-background-networking \
    --password-store=basic \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    "$DISPLAY_URL" &

# Auto-reload every 6 hours (refresh content)
while true; do
    sleep 21600
    xdotool key F5
done &
KIOSK

chmod +x "$KIOSK_HOME/.config/openbox/autostart"
chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config"

log "Chromium kiosk mode configured"

# ==============================================================================
# Step 6: Signage Client Agent (heartbeat + screenshot)
# ==============================================================================
info "Step 6: Installing signage client agent..."

cat > /usr/local/bin/adscreen-kiosk-agent.sh <<AGENT
#!/bin/bash
# Adscreen Kiosk Agent — reports health to the dashboard

HOSTNAME="$KIOSK_HOSTNAME"
ENDPOINT="$REPORT_ENDPOINT"

# Gather stats
CPU_TEMP=\$(vcgencmd measure_temp 2>/dev/null | grep -oP '[\d.]+' || echo "0")
MEM_USED=\$(free -m | awk '/Mem:/ {printf "%.0f", \$3/\$2*100}')
DISK_USED=\$(df / | awk 'NR==2 {print \$5}' | tr -d '%')
UPTIME_SEC=\$(awk '{print int(\$1)}' /proc/uptime)
IP_ADDR=\$(hostname -I | awk '{print \$1}')
WIFI_SIGNAL=\$(iwconfig wlan0 2>/dev/null | grep -oP 'Signal level=\K[-\d]+' || echo "0")

# Send heartbeat
curl -s -X POST "\$ENDPOINT" \
    -H "Content-Type: application/json" \
    -d "{
        \"hostname\": \"\$HOSTNAME\",
        \"ip\": \"\$IP_ADDR\",
        \"cpu_temp\": \$CPU_TEMP,
        \"mem_pct\": \$MEM_USED,
        \"disk_pct\": \$DISK_USED,
        \"uptime\": \$UPTIME_SEC,
        \"wifi_dbm\": \$WIFI_SIGNAL,
        \"url\": \"$DISPLAY_URL\",
        \"timestamp\": \$(date +%s)
    }" >/dev/null 2>&1 || true
AGENT

chmod 755 /usr/local/bin/adscreen-kiosk-agent.sh

# Cron: send heartbeat every 2 minutes
AGENT_CRON="*/2 * * * * /usr/local/bin/adscreen-kiosk-agent.sh"
(crontab -l 2>/dev/null | grep -v "adscreen-kiosk-agent"; echo "$AGENT_CRON") | crontab -

log "Kiosk agent installed (heartbeat every 2 min)"

# ==============================================================================
# Step 7: System Configuration
# ==============================================================================
info "Step 7: System configuration..."

# Set hostname
hostnamectl set-hostname "$KIOSK_HOSTNAME"
log "Hostname set to $KIOSK_HOSTNAME"

# Set timezone
timedatectl set-timezone "$TIMEZONE"
log "Timezone set to $TIMEZONE"

# Disable unnecessary services
systemctl disable bluetooth.service 2>/dev/null || true
systemctl disable avahi-daemon.service 2>/dev/null || true

# Enable auto-reboot on kernel panic
echo "kernel.panic = 10" > /etc/sysctl.d/99-kiosk.conf
echo "kernel.panic_on_oops = 1" >> /etc/sysctl.d/99-kiosk.conf
sysctl -p /etc/sysctl.d/99-kiosk.conf 2>/dev/null

# Watchdog: reboot if Chromium crashes
cat > /etc/systemd/system/kiosk-watchdog.service <<KWDOG_SVC
[Unit]
Description=Kiosk Chromium Watchdog
After=graphical.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'pgrep -x chromium-browse || (logger -t kiosk-watchdog "Chromium not running, rebooting" && /sbin/reboot)'
KWDOG_SVC

cat > /etc/systemd/system/kiosk-watchdog.timer <<KWDOG_TMR
[Unit]
Description=Check Chromium is running

[Timer]
OnBootSec=180
OnUnitActiveSec=120

[Install]
WantedBy=timers.target
KWDOG_TMR

systemctl daemon-reload
systemctl enable kiosk-watchdog.timer

log "System hardened for kiosk operation"

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Signage Kiosk Setup Complete${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo -e "  Hostname:     ${GREEN}$KIOSK_HOSTNAME${NC}"
echo -e "  Display URL:  ${GREEN}$DISPLAY_URL${NC}"
echo -e "  Wi-Fi SSID:   ${GREEN}$WIFI_SSID${NC} (hidden)"
echo -e "  Kiosk User:   ${GREEN}$KIOSK_USER${NC} (auto-login)"
echo -e "  Heartbeat:    ${GREEN}Every 2 min → $REPORT_ENDPOINT${NC}"
echo -e "  Auto-reload:  ${GREEN}Every 6 hours${NC}"
echo -e "  Watchdog:     ${GREEN}Reboot if Chromium dies${NC}"
echo ""
echo -e "  ${YELLOW}Reboot now to start kiosk mode:${NC}"
echo -e "  ${CYAN}sudo reboot${NC}"
echo ""
