#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Adscreen — Device Owner Provisioning Script
# ═══════════════════════════════════════════════════════════════════════════════
#
# USAGE:
#   ./provision_device_owner.sh                  # Single device (connected via USB)
#   ./provision_device_owner.sh --serial ABC123  # Specific device by serial
#   ./provision_device_owner.sh --all            # All connected devices
#   ./provision_device_owner.sh --install-apk /path/to/adscreen.apk
#
# PREREQUISITES:
#   1. Tablet MUST be factory-reset (Settings → System → Reset → Erase all data)
#   2. During setup wizard, tap the welcome screen 7 times to enter QR provisioning,
#      OR complete setup WITHOUT adding a Google account, then run this script.
#   3. USB debugging enabled (Settings → Developer Options → USB Debugging)
#   4. ADB authorized (accept the RSA key dialog on the tablet)
#
# WHAT THIS SCRIPT DOES:
#   ✅ Sets com.example.adscreen/.DeviceAdmin as Device Owner
#   ✅ Grants WRITE_SECURE_SETTINGS for ADB toggle control
#   ✅ Disables battery optimization for the app
#   ✅ Sets the app as the default Home launcher
#   ✅ Grants all runtime permissions silently
#   ✅ Locks down the device for kiosk operation
#
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

PACKAGE="com.example.adscreen"
ADMIN_RECEIVER="com.example.adscreen/.DeviceAdmin"
APK_PATH=""
TARGET_SERIAL=""
PROVISION_ALL=false

# ── Parse Arguments ──
while [[ $# -gt 0 ]]; do
    case $1 in
        --serial)    TARGET_SERIAL="$2"; shift 2 ;;
        --all)       PROVISION_ALL=true; shift ;;
        --install-apk) APK_PATH="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--serial SERIAL] [--all] [--install-apk PATH]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Helpers ──
log_step()  { echo -e "${CYAN}[STEP]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[  OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $1"; }

adb_cmd() {
    local serial="$1"
    shift
    adb -s "$serial" "$@" 2>&1
}

# ═══════════════════════════════════════════════════════════════════════════════
#  PROVISION A SINGLE DEVICE
# ═══════════════════════════════════════════════════════════════════════════════
provision_device() {
    local serial="$1"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Provisioning device: ${serial}${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"

    # ── 0. Verify device is reachable ──
    log_step "Verifying ADB connection..."
    local state
    state=$(adb -s "$serial" get-state 2>&1 || true)
    if [[ "$state" != "device" ]]; then
        log_fail "Device $serial is not in 'device' state (got: $state)"
        log_warn "Ensure USB debugging is enabled and ADB is authorized."
        return 1
    fi
    log_ok "Device $serial is connected"

    # ── 1. Install APK if provided ──
    if [[ -n "$APK_PATH" ]]; then
        log_step "Installing APK: $APK_PATH"
        adb_cmd "$serial" install -r -t "$APK_PATH"
        log_ok "APK installed"
    fi

    # ── 2. Check if any Google accounts exist (blocker for Device Owner) ──
    log_step "Checking for Google accounts (must be zero)..."
    local accounts
    accounts=$(adb_cmd "$serial" shell pm list accounts 2>/dev/null || echo "")
    if echo "$accounts" | grep -qi "google"; then
        log_fail "Google account found on device. Device Owner CANNOT be set."
        log_warn "Factory reset the device first, or remove all Google accounts."
        log_warn "  adb -s $serial shell am start -a android.settings.SYNC_SETTINGS"
        return 1
    fi
    log_ok "No Google accounts found"

    # ── 3. Remove any existing Device Owner (if set to a different app) ──
    log_step "Checking existing Device Owner..."
    local existing_do
    existing_do=$(adb_cmd "$serial" shell dpm list-owners 2>/dev/null || echo "")
    if echo "$existing_do" | grep -q "Device Owner"; then
        if echo "$existing_do" | grep -q "$PACKAGE"; then
            log_ok "Already our Device Owner — skipping set-device-owner"
        else
            log_fail "Another app is Device Owner. Factory reset required."
            return 1
        fi
    else
        # ── 4. Set Device Owner ──
        log_step "Setting Device Owner: $ADMIN_RECEIVER"
        local result
        result=$(adb_cmd "$serial" shell dpm set-device-owner "$ADMIN_RECEIVER")
        if echo "$result" | grep -qi "success\|active admin"; then
            log_ok "Device Owner set successfully"
        else
            log_fail "Failed to set Device Owner: $result"
            return 1
        fi
    fi

    # ── 5. Grant WRITE_SECURE_SETTINGS (needed for ADB toggle, screen timeout) ──
    log_step "Granting WRITE_SECURE_SETTINGS..."
    adb_cmd "$serial" shell pm grant "$PACKAGE" android.permission.WRITE_SECURE_SETTINGS || true
    log_ok "WRITE_SECURE_SETTINGS granted"

    # ── 6. Grant all runtime permissions silently ──
    log_step "Granting runtime permissions..."
    local permissions=(
        "android.permission.CAMERA"
        "android.permission.RECORD_AUDIO"
        "android.permission.ACCESS_FINE_LOCATION"
        "android.permission.ACCESS_COARSE_LOCATION"
        "android.permission.ACCESS_BACKGROUND_LOCATION"
    )
    for perm in "${permissions[@]}"; do
        adb_cmd "$serial" shell pm grant "$PACKAGE" "$perm" 2>/dev/null || true
    done
    log_ok "All runtime permissions granted"

    # ── 7. Disable battery optimization ──
    log_step "Disabling battery optimization..."
    adb_cmd "$serial" shell dumpsys deviceidle whitelist +"$PACKAGE" || true
    log_ok "Battery optimization disabled for $PACKAGE"

    # ── 8. Set as preferred Home launcher ──
    log_step "Setting as preferred Home launcher..."
    adb_cmd "$serial" shell cmd package set-home-activity "$PACKAGE/.MainActivity" || true
    log_ok "Home launcher set"

    # ── 9. Hide the setup wizard & disable non-essential system apps ──
    log_step "Disabling interfering system packages..."
    local disable_packages=(
        "com.google.android.setupwizard"
        "com.android.provision"
    )
    for pkg in "${disable_packages[@]}"; do
        adb_cmd "$serial" shell pm disable-user --user 0 "$pkg" 2>/dev/null || true
    done
    log_ok "System packages disabled"

    # ── 10. Enable stay-awake while charging ──
    log_step "Enabling stay-awake while charging..."
    adb_cmd "$serial" shell settings put global stay_on_while_plugged_in 3
    log_ok "Stay awake enabled (USB + AC + Wireless)"

    # ── 11. Disable screen lock / keyguard ──
    log_step "Disabling keyguard..."
    adb_cmd "$serial" shell locksettings set-disabled true 2>/dev/null || true
    adb_cmd "$serial" shell settings put secure lockscreen.disabled 1 2>/dev/null || true
    log_ok "Keyguard disabled"

    # ── 12. Set screen timeout to never (when on battery, handled by app) ──
    log_step "Setting screen timeout..."
    adb_cmd "$serial" shell settings put system screen_off_timeout 2147483647
    log_ok "Screen timeout set to max"

    # ── 13. Disable system navigation bar (Overscan trick for older Android) ──
    log_step "Applying immersive mode policy..."
    adb_cmd "$serial" shell settings put global policy_control "immersive.full=*" 2>/dev/null || true
    log_ok "Global immersive mode applied"

    # ── 14. Verify final state ──
    log_step "Verifying provisioning..."
    local verify_do
    verify_do=$(adb_cmd "$serial" shell dpm list-owners 2>/dev/null || echo "")
    if echo "$verify_do" | grep -q "$PACKAGE"; then
        echo ""
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ✅ Device $serial provisioned successfully!${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"

        # ── 15. Force-start the app ──
        log_step "Launching Adscreen..."
        adb_cmd "$serial" shell am start -n "$PACKAGE/.MainActivity" \
            --activity-clear-top --activity-single-top
        log_ok "Adscreen launched"
    else
        log_fail "Verification failed — Device Owner not confirmed"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN — Discover devices and provision
# ═══════════════════════════════════════════════════════════════════════════════
echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║        Adscreen — Device Owner Provisioning Tool         ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check ADB is available
if ! command -v adb &>/dev/null; then
    log_fail "ADB not found. Install Android SDK Platform Tools."
    echo "  brew install android-platform-tools"
    exit 1
fi

# Get connected devices
DEVICES=()
while IFS= read -r line; do
    serial=$(echo "$line" | awk '{print $1}')
    if [[ -n "$serial" && "$serial" != "List" ]]; then
        DEVICES+=("$serial")
    fi
done < <(adb devices | grep -v "^$")

if [[ ${#DEVICES[@]} -eq 0 ]]; then
    log_fail "No ADB devices found. Connect a tablet via USB."
    exit 1
fi

log_ok "Found ${#DEVICES[@]} device(s): ${DEVICES[*]}"

# Provision
SUCCESS_COUNT=0
FAIL_COUNT=0

if [[ -n "$TARGET_SERIAL" ]]; then
    provision_device "$TARGET_SERIAL" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
elif [[ "$PROVISION_ALL" == true ]]; then
    for serial in "${DEVICES[@]}"; do
        provision_device "$serial" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
    done
else
    # Default: first device
    provision_device "${DEVICES[0]}" && ((SUCCESS_COUNT++)) || ((FAIL_COUNT++))
fi

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "  Results: ${GREEN}$SUCCESS_COUNT succeeded${NC}, ${RED}$FAIL_COUNT failed${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
