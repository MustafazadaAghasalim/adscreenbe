#!/bin/bash
# ==============================================================================
# Adscreen Pi 5 — NVMe SSD + PoE HAT Setup
# ==============================================================================
# This script:
#   1. Installs nvme-cli for SSD monitoring
#   2. Partitions & formats the NVMe SSD (ext4)
#   3. Mounts at /mnt/ssd with fstab entry
#   4. Configures PoE HAT fan temperature thresholds
#   5. Migrates PostgreSQL 17 data to SSD
#   6. Migrates Docker data to SSD
#   7. Moves adscreen backups to SSD
#
# Usage: sudo bash setup_ssd_poe.sh
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

NVME_DEV="/dev/nvme0n1"
NVME_PART="${NVME_DEV}p1"
MOUNT_POINT="/mnt/ssd"
CONFIG_TXT="/boot/firmware/config.txt"
FSTAB="/etc/fstab"

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

# ==============================================================================
# Pre-flight checks
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
    err "Run as root: sudo bash $0"
fi

if [[ ! -b "$NVME_DEV" ]]; then
    err "NVMe device $NVME_DEV not found. Check connection."
fi

echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}  Adscreen Pi 5 — SSD + PoE HAT Setup${NC}"
echo -e "${CYAN}========================================${NC}\n"

info "NVMe device: $(lsblk -dno MODEL "$NVME_DEV" | xargs) ($(lsblk -dno SIZE "$NVME_DEV" | xargs))"
info "CPU temp: $(vcgencmd measure_temp 2>/dev/null || echo 'unknown')"
echo ""

# ==============================================================================
# Phase 1: Install nvme-cli
# ==============================================================================
echo -e "\n${CYAN}--- Phase 1: Install NVMe tools ---${NC}"
if ! command -v nvme &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq nvme-cli
    log "nvme-cli installed"
else
    log "nvme-cli already installed"
fi

# ==============================================================================
# Phase 2: Partition & Format NVMe SSD
# ==============================================================================
echo -e "\n${CYAN}--- Phase 2: Partition & Format SSD ---${NC}"

# Check if already partitioned and mounted
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    log "SSD already mounted at $MOUNT_POINT — skipping partition/format"
else
    # Check for existing partitions
    PART_COUNT=$(lsblk -n "$NVME_DEV" | wc -l)
    if [[ $PART_COUNT -gt 1 ]]; then
        warn "SSD already has partitions:"
        lsblk "$NVME_DEV"
        echo ""
        read -rp "$(echo -e "${YELLOW}Wipe and re-partition? (yes/no): ${NC}")" CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            info "Skipping partition — will try to mount existing partition"
            # Try to mount existing first partition
            EXISTING_PART=$(lsblk -rno NAME,TYPE "$NVME_DEV" | awk '$2=="part"{print "/dev/"$1; exit}')
            if [[ -n "$EXISTING_PART" ]]; then
                mkdir -p "$MOUNT_POINT"
                if ! mountpoint -q "$MOUNT_POINT"; then
                    mount "$EXISTING_PART" "$MOUNT_POINT"
                    log "Mounted $EXISTING_PART at $MOUNT_POINT"
                fi
            fi
        else
            # Wipe and partition
            wipefs -af "$NVME_DEV"
            sgdisk -Zo "$NVME_DEV"
            sgdisk -n 1:0:0 -t 1:8300 -c 1:"adscreen-data" "$NVME_DEV"
            partprobe "$NVME_DEV"
            sleep 2
            mkfs.ext4 -L adscreen-ssd -F "$NVME_PART"
            log "SSD partitioned and formatted (ext4, label: adscreen-ssd)"
        fi
    else
        # Fresh disk — partition it
        info "SSD is raw, creating partition..."
        sgdisk -Zo "$NVME_DEV"
        sgdisk -n 1:0:0 -t 1:8300 -c 1:"adscreen-data" "$NVME_DEV"
        partprobe "$NVME_DEV"
        sleep 2
        mkfs.ext4 -L adscreen-ssd -F "$NVME_PART"
        log "SSD partitioned and formatted (ext4, label: adscreen-ssd)"
    fi

    # Mount
    mkdir -p "$MOUNT_POINT"
    if ! mountpoint -q "$MOUNT_POINT"; then
        mount "$NVME_PART" "$MOUNT_POINT"
        log "Mounted at $MOUNT_POINT"
    fi
fi

# Add fstab entry if missing
if ! grep -q "$MOUNT_POINT" "$FSTAB"; then
    PART_UUID=$(blkid -s UUID -o value "$NVME_PART")
    echo "UUID=$PART_UUID  $MOUNT_POINT  ext4  defaults,noatime,commit=60  0  2" >> "$FSTAB"
    log "Added fstab entry (UUID=$PART_UUID)"
else
    log "fstab entry already exists"
fi

# Create directory structure on SSD
mkdir -p "$MOUNT_POINT"/{postgresql,docker,backups,adscreen-data}
chown postgres:postgres "$MOUNT_POINT/postgresql"
log "SSD directory structure created"

echo ""
df -h "$MOUNT_POINT"

# ==============================================================================
# Phase 3: PoE HAT Fan Configuration
# ==============================================================================
echo -e "\n${CYAN}--- Phase 3: PoE HAT Fan Configuration ---${NC}"

# Check if pwmfan is active
if [[ -d /sys/class/hwmon/hwmon3 ]] && grep -q "pwmfan" /sys/class/hwmon/hwmon3/name 2>/dev/null; then
    FAN_RPM=$(cat /sys/class/hwmon/hwmon3/fan1_input 2>/dev/null || echo "0")
    FAN_PWM=$(cat /sys/class/hwmon/hwmon3/pwm1 2>/dev/null || echo "0")
    log "PoE HAT fan driver active (RPM: $FAN_RPM, PWM: $FAN_PWM)"
else
    # Find pwmfan in any hwmon
    for h in /sys/class/hwmon/hwmon*/; do
        if grep -q "pwmfan" "${h}name" 2>/dev/null; then
            log "PoE HAT fan found at $h"
            break
        fi
    done
fi

# Add PoE fan temperature thresholds to config.txt if not present
# These control when the fan kicks in at different speeds
if ! grep -q "poe_fan_temp" "$CONFIG_TXT"; then
    info "Adding PoE HAT fan temperature thresholds to config.txt..."

    # Backup config.txt
    cp "$CONFIG_TXT" "${CONFIG_TXT}.bak.$(date +%Y%m%d%H%M%S)"

    cat >> "$CONFIG_TXT" << 'EOF'

# --- PoE HAT Fan Control (added by setup_ssd_poe.sh) ---
# Fan speeds ramp up with temperature (millidegrees, hysteresis)
# Speed 1 (25%): 40°C on, 38°C off
dtparam=poe_fan_temp0=40000,poe_fan_temp0_hyst=2000
# Speed 2 (50%): 45°C on, 43°C off
dtparam=poe_fan_temp1=45000,poe_fan_temp1_hyst=2000
# Speed 3 (75%): 50°C on, 48°C off
dtparam=poe_fan_temp2=50000,poe_fan_temp2_hyst=2000
# Speed 4 (100%): 55°C on, 53°C off
dtparam=poe_fan_temp3=55000,poe_fan_temp3_hyst=2000
EOF
    log "PoE fan thresholds added to config.txt"
    warn "Fan thresholds take effect after reboot"
else
    log "PoE fan thresholds already configured in config.txt"
fi

# ==============================================================================
# Phase 4: Migrate PostgreSQL to SSD
# ==============================================================================
echo -e "\n${CYAN}--- Phase 4: Migrate PostgreSQL 17 to SSD ---${NC}"

PG_OLD="/var/lib/postgresql/17/main"
PG_NEW="$MOUNT_POINT/postgresql/17/main"

if [[ -d "$PG_NEW/base" ]]; then
    log "PostgreSQL data already on SSD — skipping migration"
else
    read -rp "$(echo -e "${YELLOW}Migrate PostgreSQL to SSD? This stops the DB briefly. (yes/no): ${NC}")" CONFIRM_PG
    if [[ "$CONFIRM_PG" == "yes" ]]; then
        info "Stopping PostgreSQL..."
        systemctl stop postgresql

        info "Copying data to SSD (preserving permissions)..."
        mkdir -p "$MOUNT_POINT/postgresql/17"
        rsync -aAXv "$PG_OLD/" "$PG_NEW/"
        chown -R postgres:postgres "$MOUNT_POINT/postgresql"

        info "Updating PostgreSQL config..."
        PG_CONF="/etc/postgresql/17/main/postgresql.conf"
        if [[ -f "$PG_CONF" ]]; then
            # Backup the config
            cp "$PG_CONF" "${PG_CONF}.bak.$(date +%Y%m%d%H%M%S)"

            # Update data_directory
            sed -i "s|^data_directory = .*|data_directory = '$PG_NEW'|" "$PG_CONF"

            # Add SSD-optimized settings if not already present
            if ! grep -q "# SSD optimizations" "$PG_CONF"; then
                cat >> "$PG_CONF" << 'EOF'

# SSD optimizations (added by setup_ssd_poe.sh)
random_page_cost = 1.1
effective_io_concurrency = 200
EOF
            fi
        fi

        # Rename old dir as backup, don't delete
        mv "$PG_OLD" "${PG_OLD}.migrated-to-ssd"

        info "Starting PostgreSQL..."
        systemctl start postgresql

        # Verify
        sleep 2
        if systemctl is-active --quiet postgresql; then
            NEW_DIR=$(sudo -u postgres psql -tAc 'SHOW data_directory;' 2>/dev/null)
            log "PostgreSQL running from: $NEW_DIR"
        else
            err "PostgreSQL failed to start! Restoring from backup..."
            mv "${PG_OLD}.migrated-to-ssd" "$PG_OLD"
            sed -i "s|^data_directory = .*|data_directory = '$PG_OLD'|" "$PG_CONF"
            systemctl start postgresql
            err "Migration rolled back. Check $PG_NEW manually."
        fi
    else
        info "Skipping PostgreSQL migration"
    fi
fi

# ==============================================================================
# Phase 5: Migrate Docker to SSD
# ==============================================================================
echo -e "\n${CYAN}--- Phase 5: Migrate Docker to SSD ---${NC}"

DOCKER_OLD="/var/lib/docker"
DOCKER_NEW="$MOUNT_POINT/docker"
DOCKER_DAEMON="/etc/docker/daemon.json"

if [[ -f "$DOCKER_DAEMON" ]] && grep -q "$DOCKER_NEW" "$DOCKER_DAEMON" 2>/dev/null; then
    log "Docker already configured for SSD — skipping"
else
    read -rp "$(echo -e "${YELLOW}Migrate Docker data to SSD? This stops all containers briefly. (yes/no): ${NC}")" CONFIRM_DOCKER
    if [[ "$CONFIRM_DOCKER" == "yes" ]]; then
        info "Stopping Docker..."
        systemctl stop docker docker.socket

        info "Copying Docker data to SSD..."
        rsync -aAXv "$DOCKER_OLD/" "$DOCKER_NEW/"

        info "Updating Docker config..."
        mkdir -p /etc/docker
        if [[ -f "$DOCKER_DAEMON" ]]; then
            cp "$DOCKER_DAEMON" "${DOCKER_DAEMON}.bak.$(date +%Y%m%d%H%M%S)"
            # Add or update data-root using python3
            python3 -c "
import json, sys
with open('$DOCKER_DAEMON', 'r') as f:
    cfg = json.load(f)
cfg['data-root'] = '$DOCKER_NEW'
with open('$DOCKER_DAEMON', 'w') as f:
    json.dump(cfg, f, indent=2)
"
        else
            echo '{"data-root": "'"$DOCKER_NEW"'"}' > "$DOCKER_DAEMON"
        fi

        info "Starting Docker..."
        systemctl start docker

        sleep 3
        if systemctl is-active --quiet docker; then
            NEW_ROOT=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk '{print $NF}')
            log "Docker running from: $NEW_ROOT"

            # Keep old dir as backup for now
            mv "$DOCKER_OLD" "${DOCKER_OLD}.migrated-to-ssd"
            # Create symlink for any hardcoded paths
            ln -sf "$DOCKER_NEW" "$DOCKER_OLD"
            log "Created symlink: $DOCKER_OLD -> $DOCKER_NEW"
        else
            err "Docker failed to start! Restoring..."
            cp "${DOCKER_DAEMON}.bak."* "$DOCKER_DAEMON" 2>/dev/null
            systemctl start docker
        fi
    else
        info "Skipping Docker migration"
    fi
fi

# ==============================================================================
# Phase 6: Move backups to SSD
# ==============================================================================
echo -e "\n${CYAN}--- Phase 6: Adscreen backups → SSD ---${NC}"

BACKUP_OLD="/opt/adscreen-backups"
BACKUP_NEW="$MOUNT_POINT/backups"

if [[ -L "$BACKUP_OLD" ]]; then
    log "Backup dir already symlinked to SSD"
elif [[ -d "$BACKUP_OLD" ]]; then
    info "Moving backups to SSD..."
    rsync -aAXv "$BACKUP_OLD/" "$BACKUP_NEW/"
    mv "$BACKUP_OLD" "${BACKUP_OLD}.migrated"
    ln -sf "$BACKUP_NEW" "$BACKUP_OLD"
    chown -R zynorex:zynorex "$BACKUP_NEW"
    log "Backups moved to SSD, symlink created"
else
    info "No existing backup dir found — will use SSD for new backups"
    mkdir -p "$BACKUP_NEW"
    ln -sf "$BACKUP_NEW" "$BACKUP_OLD"
fi

# ==============================================================================
# Phase 7: NVMe SMART monitoring cron
# ==============================================================================
echo -e "\n${CYAN}--- Phase 7: NVMe health monitoring ---${NC}"

CRON_FILE="/etc/cron.d/nvme-health"
if [[ ! -f "$CRON_FILE" ]]; then
    cat > "$CRON_FILE" << 'EOF'
# Check NVMe SSD health daily at 3 AM and log warnings
0 3 * * * root /usr/sbin/nvme smart-log /dev/nvme0n1 -o json 2>/dev/null | python3 -c "
import json, sys, syslog
data = json.load(sys.stdin)
wear = data.get('percent_used', 0)
temp = data.get('temperature', 0)
if wear > 80:
    syslog.syslog(syslog.LOG_WARNING, f'NVMe SSD wear level critical: {wear}%')
if temp > 70:
    syslog.syslog(syslog.LOG_WARNING, f'NVMe SSD temperature high: {temp}°C')
" 2>/dev/null
EOF
    chmod 644 "$CRON_FILE"
    log "NVMe health monitoring cron job created (daily at 3 AM)"
else
    log "NVMe health cron already exists"
fi

# ==============================================================================
# Summary
# ==============================================================================
echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}  Setup Complete — Summary${NC}"
echo -e "${CYAN}========================================${NC}\n"

echo -e "  ${GREEN}NVMe SSD:${NC}"
df -h "$MOUNT_POINT" | tail -1 | awk '{printf "    Mount: %s | Size: %s | Used: %s | Avail: %s\n", $6, $2, $3, $4}'
echo ""

echo -e "  ${GREEN}PoE HAT Fan:${NC}"
for h in /sys/class/hwmon/hwmon*/; do
    if grep -q "pwmfan" "${h}name" 2>/dev/null; then
        echo "    Driver: $(cat ${h}name) | RPM: $(cat ${h}fan1_input 2>/dev/null) | PWM: $(cat ${h}pwm1 2>/dev/null)/255"
    fi
done
echo ""

echo -e "  ${GREEN}Temperatures:${NC}"
echo "    CPU: $(vcgencmd measure_temp 2>/dev/null)"
NVME_TEMP=$(cat /sys/class/hwmon/hwmon1/temp1_input 2>/dev/null)
if [[ -n "$NVME_TEMP" ]]; then
    echo "    NVMe: $((NVME_TEMP / 1000)).$(( (NVME_TEMP % 1000) / 100 ))°C"
fi
echo ""

echo -e "  ${GREEN}Services:${NC}"
for svc in postgresql docker; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
    echo "    $svc: $STATUS"
done
echo ""

echo -e "  ${GREEN}SSD Layout:${NC}"
ls -la "$MOUNT_POINT"/
echo ""

warn "Reboot recommended to apply PoE fan thresholds: sudo reboot"
echo ""
