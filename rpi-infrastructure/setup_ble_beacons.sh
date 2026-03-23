#!/bin/bash
# ==============================================================================
# Adscreen — Aruba AP-305 BLE Beacon Configuration
# ==============================================================================
# Configures BLE (Bluetooth Low Energy) beacons on the Aruba AP-305
# for proximity-based digital signage triggering.
#
# Supports:
#   - Eddystone-URL beacons (broadcast URL to nearby phones)
#   - iBeacon (UUID-based proximity detection)
#   - BLE asset tracking profile
#
# Prerequisites:
#   - AP-305 already configured (run setup_aruba_ap305.sh first)
#   - Serial console access via /dev/ttyAMA0
#
# Usage: sudo bash setup_ble_beacons.sh [--eddystone|--ibeacon|--both]
#
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# -- Configuration --
AP_SERIAL_DEV="/dev/ttyAMA0"
AP_BAUD="9600"
AP_ADMIN_USER="admin"
AP_ADMIN_PASS="Adscreen@2024"

# BLE Beacon settings
EDDYSTONE_URL="https://adscreen.az"
EDDYSTONE_TX_POWER="-4"
IBEACON_UUID="A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
IBEACON_MAJOR="100"
IBEACON_MINOR="1"
IBEACON_TX_POWER="-59"
BLE_PROFILE_NAME="adscreen-ble"
BLE_BEACON_INTERVAL="100"

# Parse args
MODE="both"
for arg in "$@"; do
    case "$arg" in
        --eddystone) MODE="eddystone" ;;
        --ibeacon)   MODE="ibeacon" ;;
        --both)      MODE="both" ;;
    esac
done

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    err "Run as root: sudo bash $0"
fi

if [[ ! -c "$AP_SERIAL_DEV" ]]; then
    err "Serial device $AP_SERIAL_DEV not found. Run setup_aruba_ap305.sh first."
fi

echo -e "\n${CYAN}================================================${NC}"
echo -e "${CYAN}  Adscreen — BLE Beacon Configuration${NC}"
echo -e "${CYAN}================================================${NC}"
echo -e "  Mode: ${GREEN}$MODE${NC}\n"

# ==============================================================================
# Generate expect script for BLE configuration
# ==============================================================================
BLE_SCRIPT=$(mktemp /tmp/aruba_ble_XXXXXX.exp)
chmod 600 "$BLE_SCRIPT"

cat > "$BLE_SCRIPT" <<BLE_EOF
#!/usr/bin/expect -f
set timeout 30

spawn minicom -b $AP_BAUD -D $AP_SERIAL_DEV -o

sleep 2
send "\r"
sleep 1

# Login / enable
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
    timeout { puts "ERROR: No AP console response"; exit 1 }
}

send "configure terminal\r"
expect "(config)#"

# --- Enable BLE radio ---
puts "\n>> Enabling BLE radio..."
send "ble-radio-profile $BLE_PROFILE_NAME\r"
expect {
    "(BLE radio profile)#" { }
    "(config)#" { send "ble-radio-profile $BLE_PROFILE_NAME\r"; expect "(BLE radio profile)#" }
}

send "radio-state enable\r"
expect "(BLE radio profile)#"

send "tx-power $EDDYSTONE_TX_POWER\r"
expect "(BLE radio profile)#"

send "beacon-rate $BLE_BEACON_INTERVAL\r"
expect "(BLE radio profile)#"

send "exit\r"
expect "(config)#"

BLE_EOF

# Add Eddystone config if requested
if [[ "$MODE" == "eddystone" || "$MODE" == "both" ]]; then
    cat >> "$BLE_SCRIPT" <<EDDY_EOF

# --- Eddystone-URL Beacon ---
puts "\n>> Configuring Eddystone-URL beacon..."
send "ble-beacon-profile eddystone-adscreen\r"
expect {
    "(BLE beacon profile)#" { }
    "(config)#" { send "ble-beacon-profile eddystone-adscreen\r"; expect "(BLE beacon profile)#" }
}

send "beacon-type eddystone-url\r"
expect "(BLE beacon profile)#"

send "eddystone-url $EDDYSTONE_URL\r"
expect "(BLE beacon profile)#"

send "tx-power $EDDYSTONE_TX_POWER\r"
expect "(BLE beacon profile)#"

send "advertising-interval $BLE_BEACON_INTERVAL\r"
expect "(BLE beacon profile)#"

send "enable\r"
expect "(BLE beacon profile)#"

send "exit\r"
expect "(config)#"

EDDY_EOF
fi

# Add iBeacon config if requested
if [[ "$MODE" == "ibeacon" || "$MODE" == "both" ]]; then
    cat >> "$BLE_SCRIPT" <<IBEACON_EOF

# --- iBeacon ---
puts "\n>> Configuring iBeacon..."
send "ble-beacon-profile ibeacon-adscreen\r"
expect {
    "(BLE beacon profile)#" { }
    "(config)#" { send "ble-beacon-profile ibeacon-adscreen\r"; expect "(BLE beacon profile)#" }
}

send "beacon-type ibeacon\r"
expect "(BLE beacon profile)#"

send "ibeacon-uuid $IBEACON_UUID\r"
expect "(BLE beacon profile)#"

send "ibeacon-major $IBEACON_MAJOR\r"
expect "(BLE beacon profile)#"

send "ibeacon-minor $IBEACON_MINOR\r"
expect "(BLE beacon profile)#"

send "tx-power $IBEACON_TX_POWER\r"
expect "(BLE beacon profile)#"

send "advertising-interval $BLE_BEACON_INTERVAL\r"
expect "(BLE beacon profile)#"

send "enable\r"
expect "(BLE beacon profile)#"

send "exit\r"
expect "(config)#"

IBEACON_EOF
fi

# Add BLE asset tracking and save
cat >> "$BLE_SCRIPT" <<FINAL_EOF

# --- Enable IoT transport for signage triggers ---
puts "\n>> Enabling IoT transport profile..."
send "iot-transport-profile adscreen-iot\r"
expect {
    "(IoT transport profile)#" { }
    "(config)#" { send "iot-transport-profile adscreen-iot\r"; expect "(IoT transport profile)#" }
}

send "server-type websocket\r"
expect "(IoT transport profile)#"

send "server-url ws://10.10.1.33:3000/ble\r"
expect "(IoT transport profile)#"

send "enable\r"
expect "(IoT transport profile)#"

send "exit\r"
expect "(config)#"

# --- Save config ---
send "exit\r"
expect "#"

send "write memory\r"
expect "#"

puts "\n\nBLE beacon configuration complete!"

sleep 1
send "\x01"
send "x"
expect eof
FINAL_EOF

chmod 700 "$BLE_SCRIPT"

info "Applying BLE configuration to AP-305..."
/usr/bin/expect "$BLE_SCRIPT"

rm -f "$BLE_SCRIPT"

# ==============================================================================
# Verification script
# ==============================================================================
info "Creating BLE verification script..."

VERIFY_SCRIPT="/home/zynorex/verify_ble.exp"
cat > "$VERIFY_SCRIPT" <<'VERIFY_EOF'
#!/usr/bin/expect -f
set timeout 15

spawn minicom -b 9600 -D /dev/ttyAMA0 -o

sleep 2
send "\r"

expect {
    "User:" { send "admin\r"; expect "Password:"; send "Adscreen@2024\r"; expect "#" }
    ">" { send "enable\r"; expect "#" }
    "#" { }
}

puts "\n===== BLE STATUS ====="
send "show ble-radio-status\r"
expect "#"

puts "\n===== BLE BEACONS ====="
send "show ble-beacon-config\r"
expect "#"

puts "\n===== IoT STATUS ====="
send "show iot-transport-status\r"
expect "#"

sleep 1
send "\x01"
send "x"
expect eof
VERIFY_EOF

chmod 755 "$VERIFY_SCRIPT"
chown zynorex:zynorex "$VERIFY_SCRIPT"

# ==============================================================================
# Summary
# ==============================================================================
echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  BLE Beacon Configuration Complete${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""
if [[ "$MODE" == "eddystone" || "$MODE" == "both" ]]; then
    echo -e "  Eddystone-URL:  ${GREEN}$EDDYSTONE_URL${NC}"
    echo -e "  TX Power:       ${GREEN}$EDDYSTONE_TX_POWER dBm${NC}"
fi
if [[ "$MODE" == "ibeacon" || "$MODE" == "both" ]]; then
    echo -e "  iBeacon UUID:   ${GREEN}$IBEACON_UUID${NC}"
    echo -e "  Major/Minor:    ${GREEN}$IBEACON_MAJOR / $IBEACON_MINOR${NC}"
fi
echo -e "  Beacon Interval: ${GREEN}${BLE_BEACON_INTERVAL}ms${NC}"
echo -e "  IoT WebSocket:   ${GREEN}ws://10.10.1.33:3000/ble${NC}"
echo ""
echo -e "  Verify with:     ${CYAN}sudo expect /home/zynorex/verify_ble.exp${NC}"
echo ""
echo -e "${YELLOW}  Note: Phones within ~30m will detect Eddystone beacons.${NC}"
echo -e "${YELLOW}  Your signage app can use iBeacon UUID for proximity triggers.${NC}"
echo ""
