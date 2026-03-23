#!/bin/bash
# ==============================================================================
# Adscreen — Aruba AP-305 Serial Configuration via Raspberry Pi GPIO UART
# ==============================================================================
# This script configures the Aruba AP-305 access point through the Pi's
# UART serial console (GPIO pins 6/8/10) using minicom/expect.
#
# Hardware wiring (Pi GPIO to AP-305 console port):
#   Pi Pin 6  (GND)  → AP-305 GND
#   Pi Pin 8  (TX)   → AP-305 RX
#   Pi Pin 10 (RX)   → AP-305 TX
#
# What this script does:
#   Phase 1: Installs minicom + expect for serial automation
#   Phase 2: Enables Pi UART overlay in config.txt
#   Phase 3: Factory-resets the AP-305 (optional)
#   Phase 4: Configures IAP mode with hidden SSID "Adscreen_Net"
#   Phase 5: Sets static IP, VLAN, and management credentials
#
# Usage: sudo bash setup_aruba_ap305.sh [--factory-reset] [--interactive]
#
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# -- Configuration (edit these for your environment) --
AP_SERIAL_DEV="/dev/ttyAMA0"
AP_BAUD="9600"
AP_ADMIN_USER="admin"
AP_ADMIN_PASS="Adscreen@2024"
SSID_NAME="Adscreen_Net"
SSID_PASS="Adscreen@WiFi2024"
AP_STATIC_IP="10.10.1.50"
AP_NETMASK="255.255.252.0"
AP_GATEWAY="10.10.0.1"
AP_DNS="1.1.1.1"
VLAN_ID="100"
COUNTRY_CODE="AZ"
CHANNEL_2G="6"
CHANNEL_5G="36"
TX_POWER="18"

FACTORY_RESET=false
INTERACTIVE=false

for arg in "$@"; do
    case "$arg" in
        --factory-reset) FACTORY_RESET=true ;;
        --interactive)   INTERACTIVE=true ;;
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
echo -e "${CYAN}  Adscreen — Aruba AP-305 Serial Configuration${NC}"
echo -e "${CYAN}================================================${NC}\n"

# ==============================================================================
# Phase 1: Install dependencies
# ==============================================================================
info "Phase 1: Installing serial tools..."

apt-get update -qq
apt-get install -y minicom expect

log "minicom and expect installed"

# ==============================================================================
# Phase 2: Enable UART on Pi GPIO
# ==============================================================================
info "Phase 2: Configuring Pi UART..."

CONFIG_TXT="/boot/firmware/config.txt"

# Enable UART0 on GPIO14/15 (pins 8/10)
if ! grep -q "^dtoverlay=uart0" "$CONFIG_TXT" 2>/dev/null; then
    echo "" >> "$CONFIG_TXT"
    echo "# Aruba AP-305 serial console" >> "$CONFIG_TXT"
    echo "dtoverlay=uart0" >> "$CONFIG_TXT"
    echo "enable_uart=1" >> "$CONFIG_TXT"
    warn "UART overlay added to config.txt — reboot required if /dev/ttyAMA0 doesn't exist"
fi

# Disable serial console on UART (free it for AP use)
if grep -q "console=serial0" /boot/firmware/cmdline.txt 2>/dev/null; then
    sed -i 's/console=serial0,[0-9]* //g' /boot/firmware/cmdline.txt
    warn "Removed kernel serial console from cmdline.txt"
fi

# Disable serial-getty service on ttyAMA0
systemctl stop serial-getty@ttyAMA0.service 2>/dev/null || true
systemctl disable serial-getty@ttyAMA0.service 2>/dev/null || true

if [[ ! -c "$AP_SERIAL_DEV" ]]; then
    warn "$AP_SERIAL_DEV not found. A reboot may be needed."
    echo -e "  Run: ${CYAN}sudo reboot${NC} then re-run this script."
    exit 0
fi

log "UART enabled on $AP_SERIAL_DEV"

# ==============================================================================
# Phase 3: Factory Reset (optional)
# ==============================================================================
if $FACTORY_RESET; then
    info "Phase 3: Factory-resetting AP-305..."
    warn "This erases ALL AP configuration. Press Ctrl+C within 5s to abort."
    sleep 5

    /usr/bin/expect <<'FACTORY_EOF'
set timeout 120
spawn minicom -b 9600 -D /dev/ttyAMA0 -o

# Wake AP console
send "\r"
sleep 2

# Enter enable mode
expect {
    "#" { }
    ">" { send "enable\r"; expect "#" }
    timeout { puts "ERROR: No AP console response"; exit 1 }
}

# Wipe to factory defaults
send "write erase all\r"
expect {
    "Are you sure" { send "y\r" }
    "#"            { }
}

expect {
    "completed" { }
    "#"         { }
    timeout     { puts "WARNING: write erase may still be running"; }
}

send "reload\r"
expect {
    "Are you sure"  { send "y\r" }
    "Restarting"    { }
}

puts "\nFactory reset initiated. AP will reboot (~3 minutes)."
sleep 5
send "\x01"; send "x"
FACTORY_EOF

    log "Factory reset command sent. Waiting 180s for AP to boot..."
    sleep 180
    log "AP should be ready now"
fi

# ==============================================================================
# Phase 4: Configure IAP mode with hidden SSID
# ==============================================================================
info "Phase 4: Configuring Aruba AP-305 in IAP mode..."

# Create expect script for AP configuration
EXPECT_SCRIPT=$(mktemp /tmp/aruba_config_XXXXXX.exp)
chmod 600 "$EXPECT_SCRIPT"

cat > "$EXPECT_SCRIPT" <<EXPECT_EOF
#!/usr/bin/expect -f
set timeout 30

spawn minicom -b $AP_BAUD -D $AP_SERIAL_DEV -o

# Wait for console
sleep 2
send "\r"
sleep 1
send "\r"

# Handle login or direct prompt
expect {
    "User:" {
        send "$AP_ADMIN_USER\r"
        expect "Password:"
        send "$AP_ADMIN_PASS\r"
        expect "#"
    }
    ">" {
        send "enable\r"
        expect {
            "Password:" { send "$AP_ADMIN_PASS\r"; expect "#" }
            "#" { }
        }
    }
    "#" { }
    timeout {
        puts "ERROR: Cannot reach AP console on $AP_SERIAL_DEV"
        exit 1
    }
}

# Enter config mode
send "configure terminal\r"
expect "(config)#"

# --- Set country code ---
send "country-code $COUNTRY_CODE\r"
expect "(config)#"

# --- Create hidden SSID profile ---
send "wlan ssid-profile $SSID_NAME\r"
expect "(SSID Profile)#"

send "essid $SSID_NAME\r"
expect "(SSID Profile)#"

send "type employee\r"
expect "(SSID Profile)#"

send "opmode wpa2-aes\r"
expect "(SSID Profile)#"

send "wpa-passphrase $SSID_PASS\r"
expect "(SSID Profile)#"

# Hide SSID (no broadcast)
send "hide-ssid\r"
expect "(SSID Profile)#"

# VLAN assignment
send "vlan $VLAN_ID\r"
expect "(SSID Profile)#"

send "exit\r"
expect "(config)#"

# --- Radio settings ---
# 2.4 GHz
send "radio-profile 2.4ghz-profile\r"
expect {
    "(Radio Profile)#" { }
    "(config)#" { send "radio-profile 2.4ghz-profile\r"; expect "(Radio Profile)#" }
}

send "channel $CHANNEL_2G\r"
expect "(Radio Profile)#"

send "tx-power $TX_POWER\r"
expect "(Radio Profile)#"

send "exit\r"
expect "(config)#"

# 5 GHz
send "radio-profile 5ghz-profile\r"
expect {
    "(Radio Profile)#" { }
    "(config)#" { send "radio-profile 5ghz-profile\r"; expect "(Radio Profile)#" }
}

send "channel $CHANNEL_5G\r"
expect "(Radio Profile)#"

send "tx-power $TX_POWER\r"
expect "(Radio Profile)#"

send "exit\r"
expect "(config)#"

# --- Management credentials ---
send "mgmt-user $AP_ADMIN_USER $AP_ADMIN_PASS\r"
expect "(config)#"

# --- Exit config ---
send "exit\r"
expect "#"

# --- Save ---
send "write memory\r"
expect "#"

puts "\n\nAP-305 configuration complete!"

# Exit minicom cleanly (Ctrl-A then X)
sleep 1
send "\x01"
send "x"

expect eof
EXPECT_EOF

chmod 700 "$EXPECT_SCRIPT"

if $INTERACTIVE; then
    info "Interactive mode: launching minicom directly."
    info "Manual commands to run inside minicom:"
    echo ""
    echo -e "  ${CYAN}enable${NC}"
    echo -e "  ${CYAN}configure terminal${NC}"
    echo -e "  ${CYAN}country-code $COUNTRY_CODE${NC}"
    echo -e "  ${CYAN}wlan ssid-profile $SSID_NAME${NC}"
    echo -e "  ${CYAN}essid $SSID_NAME${NC}"
    echo -e "  ${CYAN}type employee${NC}"
    echo -e "  ${CYAN}opmode wpa2-aes${NC}"
    echo -e "  ${CYAN}wpa-passphrase $SSID_PASS${NC}"
    echo -e "  ${CYAN}hide-ssid${NC}"
    echo -e "  ${CYAN}vlan $VLAN_ID${NC}"
    echo -e "  ${CYAN}exit${NC}"
    echo -e "  ${CYAN}write memory${NC}"
    echo ""
    info "Exit minicom with: Ctrl-A then X"
    echo ""
    minicom -b "$AP_BAUD" -D "$AP_SERIAL_DEV" -o
else
    info "Running automated configuration..."
    /usr/bin/expect "$EXPECT_SCRIPT"
fi

# Cleanup
rm -f "$EXPECT_SCRIPT"
log "AP-305 SSID '$SSID_NAME' configured (hidden, WPA2-AES, VLAN $VLAN_ID)"

# ==============================================================================
# Phase 5: Set AP static IP
# ==============================================================================
info "Phase 5: Setting AP static IP..."

STATIC_SCRIPT=$(mktemp /tmp/aruba_static_XXXXXX.exp)
chmod 600 "$STATIC_SCRIPT"

cat > "$STATIC_SCRIPT" <<STATIC_EOF
#!/usr/bin/expect -f
set timeout 30

spawn minicom -b $AP_BAUD -D $AP_SERIAL_DEV -o

sleep 2
send "\r"

expect {
    "User:" {
        send "$AP_ADMIN_USER\r"
        expect "Password:"
        send "$AP_ADMIN_PASS\r"
        expect "#"
    }
    ">" { send "enable\r"; expect "#" }
    "#" { }
    timeout { puts "ERROR: No console response"; exit 1 }
}

send "configure terminal\r"
expect "(config)#"

# Set static IP on the AP
send "ip-address $AP_STATIC_IP $AP_NETMASK $AP_GATEWAY\r"
expect "(config)#"

# Set DNS
send "ip-dns-server $AP_DNS\r"
expect "(config)#"

# NTP (Cloudflare)
send "ntp-server 162.159.200.1\r"
expect "(config)#"

# Set hostname
send "hostname Adscreen-AP305\r"
expect "(config)#"

send "exit\r"
expect "#"

send "write memory\r"
expect "#"

puts "\nStatic IP $AP_STATIC_IP configured."

sleep 1
send "\x01"
send "x"
expect eof
STATIC_EOF

chmod 700 "$STATIC_SCRIPT"

if ! $INTERACTIVE; then
    /usr/bin/expect "$STATIC_SCRIPT"
fi

rm -f "$STATIC_SCRIPT"
log "AP-305 static IP set to $AP_STATIC_IP"

# ==============================================================================
# Create minicom shortcut
# ==============================================================================
info "Creating convenience alias..."

ALIAS_LINE="alias aruba-console='minicom -b $AP_BAUD -D $AP_SERIAL_DEV -o'"
BASHRC="/home/zynorex/.bashrc"
if ! grep -q "aruba-console" "$BASHRC" 2>/dev/null; then
    echo "" >> "$BASHRC"
    echo "# Aruba AP-305 serial console shortcut" >> "$BASHRC"
    echo "$ALIAS_LINE" >> "$BASHRC"
    log "Added 'aruba-console' alias to .bashrc"
fi

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Aruba AP-305 Configuration Complete${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
echo -e "  SSID:       ${GREEN}$SSID_NAME${NC} (hidden)"
echo -e "  Security:   ${GREEN}WPA2-AES${NC}"
echo -e "  VLAN:       ${GREEN}$VLAN_ID${NC}"
echo -e "  AP IP:      ${GREEN}$AP_STATIC_IP${NC}"
echo -e "  Gateway:    ${GREEN}$AP_GATEWAY${NC}"
echo -e "  Admin:      ${GREEN}$AP_ADMIN_USER${NC}"
echo -e "  Country:    ${GREEN}$COUNTRY_CODE${NC}"
echo -e "  2.4GHz Ch:  ${GREEN}$CHANNEL_2G${NC}"
echo -e "  5GHz Ch:    ${GREEN}$CHANNEL_5G${NC}"
echo ""
echo -e "  Serial console: ${CYAN}aruba-console${NC} (or minicom -b $AP_BAUD -D $AP_SERIAL_DEV -o)"
echo -e "  AP web UI:      ${CYAN}https://$AP_STATIC_IP:4343${NC}"
echo ""
