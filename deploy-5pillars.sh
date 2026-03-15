#!/bin/bash
###############################################################################
#  deploy-5pillars.sh — Deploy all 5 pillar features to Pi
#  Run from Mac: bash deploy-5pillars.sh
###############################################################################
set -euo pipefail

PI_HOST="10.10.1.33"
PI_USER="zynorex"
PI_PASS="15261526"
REMOTE_APP="/home/zynorex/adscreen-website"
REMOTE_INFRA="/home/zynorex/rpi-infrastructure"
LOCAL_APP="adscreen-local/AdscreenWebsite copy"
LOCAL_INFRA="rpi-infrastructure"

SSH="sshpass -p $PI_PASS ssh -o StrictHostKeyChecking=no ${PI_USER}@${PI_HOST}"
SCP="sshpass -p $PI_PASS scp -o StrictHostKeyChecking=no"
RSYNC="sshpass -p $PI_PASS rsync -avz --exclude=node_modules --exclude=.git -e 'ssh -o StrictHostKeyChecking=no'"

echo "═══════════════════════════════════════════════════════════"
echo "  Deploying 5 Pillars to Raspberry Pi"
echo "═══════════════════════════════════════════════════════════"

# 1. Sync app code (backend + frontend)
echo ""
echo "📦 [1/5] Syncing application code..."
eval $RSYNC "${LOCAL_APP}/" "${PI_USER}@${PI_HOST}:${REMOTE_APP}/"

# 2. Sync infrastructure configs
echo ""
echo "📦 [2/5] Syncing infrastructure configs..."
eval $RSYNC "${LOCAL_INFRA}/" "${PI_USER}@${PI_HOST}:${REMOTE_INFRA}/"

# 3. Install new npm dependencies (imap-simple, nodemailer)
echo ""
echo "📦 [3/5] Installing new npm dependencies..."
$SSH "cd ${REMOTE_APP} && npm install imap-simple nodemailer --save --production 2>&1 | tail -5"

# 4. Rebuild frontend
echo ""
echo "🔨 [4/5] Rebuilding frontend..."
$SSH "cd ${REMOTE_APP} && npm run build 2>&1 | tail -5"

# 5. Restart service
echo ""
echo "🔄 [5/5] Restarting adscreen-website service..."
$SSH "sudo systemctl restart adscreen-website && sleep 2 && sudo systemctl is-active adscreen-website"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Deployment complete!"
echo ""
echo "  Features deployed:"
echo "    P1 ✅ Mailcow configs (run setup-mailcow.sh on Pi to install)"
echo "    P2 ✅ In-app Mail Client (Mail tab in admin panel)"
echo "    P3 ✅ ntfy Push Notifications (run docker compose up -d on Pi)"
echo "    P4 ✅ Hard file deletion for security videos"
echo "    P5 ✅ SSD Storage Monitor (Settings → Storage)"
echo ""
echo "  Post-deploy steps:"
echo "    1. Start ntfy: cd ${REMOTE_INFRA} && docker compose up -d ntfy"
echo "    2. Setup Mailcow: sudo bash ${REMOTE_INFRA}/mailcow/setup-mailcow.sh"
echo "    3. Update tunnel: sudo bash ${REMOTE_INFRA}/update-tunnel-config.sh"
echo "    4. Add to .env: NTFY_URL, MAIL_IMAP_HOST, MAIL_PASS_SALIM"
echo "═══════════════════════════════════════════════════════════"
