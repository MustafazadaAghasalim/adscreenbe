#!/bin/bash
# ==============================================================================
# Adscreen Pi 5 — Hardware Diagnostics
# Quick health check for NVMe SSD, PoE HAT, and system status
# Usage: bash hw_diagnostics.sh
# ==============================================================================

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "\n${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Adscreen Pi 5 — HW Diagnostics    ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}\n"

# --- System ---
echo -e "${CYAN}[System]${NC}"
echo "  Model:   $(cat /proc/device-tree/model 2>/dev/null)"
echo "  Kernel:  $(uname -r)"
echo "  Uptime:  $(uptime -p)"
echo ""

# --- Temperatures ---
echo -e "${CYAN}[Temperatures]${NC}"
CPU_TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oP '[\d.]+')
NVME_TEMP_RAW=$(cat /sys/class/hwmon/hwmon1/temp1_input 2>/dev/null || echo "0")
NVME_TEMP=$((NVME_TEMP_RAW / 1000))

color_temp() {
    local t=$1 label=$2
    if (( t >= 70 )); then echo -e "  ${label}: ${RED}${t}°C${NC} ⚠️"
    elif (( t >= 55 )); then echo -e "  ${label}: ${YELLOW}${t}°C${NC}"
    else echo -e "  ${label}: ${GREEN}${t}°C${NC}"; fi
}

color_temp "${CPU_TEMP%.*}" "CPU "
color_temp "$NVME_TEMP" "NVMe"
echo ""

# --- PoE HAT Fan ---
echo -e "${CYAN}[PoE HAT Fan]${NC}"
for h in /sys/class/hwmon/hwmon*/; do
    if grep -q "pwmfan" "${h}name" 2>/dev/null; then
        RPM=$(cat "${h}fan1_input" 2>/dev/null || echo "N/A")
        PWM=$(cat "${h}pwm1" 2>/dev/null || echo "N/A")
        ENABLE=$(cat "${h}pwm1_enable" 2>/dev/null || echo "N/A")
        echo "  Driver:  pwmfan"
        echo "  RPM:     $RPM"
        echo "  PWM:     $PWM / 255"
        echo "  Mode:    $(case $ENABLE in 0) echo 'off';; 1) echo 'manual';; 2) echo 'auto';; *) echo $ENABLE;; esac)"
    fi
done
echo ""

# --- NVMe SSD ---
echo -e "${CYAN}[NVMe SSD]${NC}"
if [[ -b /dev/nvme0n1 ]]; then
    MODEL=$(lsblk -dno MODEL /dev/nvme0n1 | xargs)
    SIZE=$(lsblk -dno SIZE /dev/nvme0n1 | xargs)
    echo "  Model:   $MODEL"
    echo "  Size:    $SIZE"

    if command -v nvme &>/dev/null; then
        SMART=$(sudo nvme smart-log /dev/nvme0n1 -o json 2>/dev/null)
        if [[ -n "$SMART" ]]; then
            WEAR=$(echo "$SMART" | python3 -c "import json,sys;print(json.load(sys.stdin).get('percent_used',0))" 2>/dev/null)
            READS=$(echo "$SMART" | python3 -c "import json,sys;print(json.load(sys.stdin).get('data_units_read',0))" 2>/dev/null)
            WRITES=$(echo "$SMART" | python3 -c "import json,sys;print(json.load(sys.stdin).get('data_units_written',0))" 2>/dev/null)
            POWER_ON=$(echo "$SMART" | python3 -c "import json,sys;print(json.load(sys.stdin).get('power_on_hours',0))" 2>/dev/null)

            echo "  Wear:    ${WEAR}%"
            echo "  Power:   ${POWER_ON} hours"
            if (( WEAR > 80 )); then
                echo -e "  Health:  ${RED}REPLACE SOON${NC}"
            elif (( WEAR > 50 )); then
                echo -e "  Health:  ${YELLOW}MODERATE${NC}"
            else
                echo -e "  Health:  ${GREEN}GOOD${NC}"
            fi
        fi
    else
        echo "  SMART:   nvme-cli not installed (run: sudo apt install nvme-cli)"
    fi

    # Mount status
    MOUNT=$(findmnt -rno TARGET /dev/nvme0n1p1 2>/dev/null)
    if [[ -n "$MOUNT" ]]; then
        echo "  Mount:   $MOUNT"
        df -h /dev/nvme0n1p1 2>/dev/null | tail -1 | awk '{printf "  Usage:   %s / %s (%s)\n", $3, $2, $5}'
    else
        echo -e "  Mount:   ${YELLOW}NOT MOUNTED${NC}"
    fi
else
    echo -e "  ${RED}NVMe device not detected!${NC}"
fi
echo ""

# --- Storage Overview ---
echo -e "${CYAN}[Storage]${NC}"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE | grep -v "loop\|zram"
echo ""

# --- Services ---
echo -e "${CYAN}[Services]${NC}"
for svc in postgresql docker pm2-zynorex adscreen-daemon cloudflared webhook; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
    case "$STATUS" in
        active)    echo -e "  $svc: ${GREEN}$STATUS${NC}" ;;
        inactive)  echo -e "  $svc: ${YELLOW}$STATUS${NC}" ;;
        *)         echo -e "  $svc: ${RED}$STATUS${NC}" ;;
    esac
done
echo ""

# --- Network (PoE power comes via Ethernet) ---
echo -e "${CYAN}[Network]${NC}"
IP=$(hostname -I | awk '{print $1}')
echo "  IP:      $IP"
echo "  Link:    $(cat /sys/class/net/eth0/operstate 2>/dev/null || echo 'unknown')"
SPEED=$(cat /sys/class/net/eth0/speed 2>/dev/null || echo "?")
echo "  Speed:   ${SPEED} Mbps"
echo ""

# --- Memory ---
echo -e "${CYAN}[Memory]${NC}"
free -h | awk '/^Mem:/{printf "  RAM:     %s used / %s total (%s avail)\n", $3, $2, $7}'
free -h | awk '/^Swap:/{printf "  Swap:    %s used / %s total\n", $3, $2}'
echo ""
