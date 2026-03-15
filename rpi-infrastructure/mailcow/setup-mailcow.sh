#!/bin/bash
###############################################################################
#  setup-mailcow.sh — Install & configure Mailcow on Raspberry Pi 5
#  Run as: sudo bash setup-mailcow.sh
###############################################################################
set -euo pipefail

MAILCOW_DIR="/opt/mailcow-dockerized"
DOMAIN="mail.adscreen.az"

echo "═══════════════════════════════════════════════════════════"
echo "  Mailcow Setup for adscreen.az on Raspberry Pi 5"
echo "═══════════════════════════════════════════════════════════"

# 1. Prerequisites
echo "📦 Installing prerequisites..."
apt-get update -qq
apt-get install -y -qq git curl

# 2. Clone Mailcow
if [ ! -d "$MAILCOW_DIR" ]; then
    echo "📥 Cloning Mailcow..."
    git clone https://github.com/mailcow/mailcow-dockerized "$MAILCOW_DIR"
else
    echo "✅ Mailcow directory already exists, pulling latest..."
    cd "$MAILCOW_DIR" && git pull
fi

cd "$MAILCOW_DIR"

# 3. Generate config non-interactively
echo "⚙️  Generating mailcow.conf..."
cat > mailcow.conf << EOF
# Mailcow Configuration for adscreen.az
MAILCOW_HOSTNAME=${DOMAIN}
MAILCOW_PASS_SCHEME=BLF-CRYPT
DBNAME=mailcow
DBUSER=mailcow
DBPASS=$(openssl rand -hex 16)
DBROOT=$(openssl rand -hex 16)
HTTP_PORT=8880
HTTP_BIND=0.0.0.0
HTTPS_PORT=8443
HTTPS_BIND=0.0.0.0
SMTP_PORT=25
SMTPS_PORT=465
SUBMISSION_PORT=587
IMAP_PORT=143
IMAPS_PORT=993
POP_PORT=110
POPS_PORT=995
SIEVE_PORT=4190
API_KEY=$(openssl rand -hex 32)
API_ALLOW_FROM=127.0.0.1,::1,172.16.0.0/12,10.0.0.0/8
COMPOSE_PROJECT_NAME=mailcowdockerized
SKIP_LETS_ENCRYPT=y
SKIP_CLAMD=y
SKIP_SOLR=y
ALLOW_ADMIN_EMAIL_LOGIN=y
TZ=Asia/Baku
EOF

echo ""
echo "🔑 IMPORTANT — Save your API key:"
grep "API_KEY=" mailcow.conf
echo ""

# 4. Copy port override
if [ -f "/home/zynorex/rpi-infrastructure/mailcow/docker-compose.override.yml" ]; then
    cp /home/zynorex/rpi-infrastructure/mailcow/docker-compose.override.yml "$MAILCOW_DIR/docker-compose.override.yml"
    echo "✅ Port override applied"
fi

# 5. Pull & start
echo "🐳 Pulling Mailcow images (this takes a while on Pi)..."
docker compose pull

echo "🚀 Starting Mailcow..."
docker compose up -d

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✅ Mailcow is starting at http://localhost:8880"
echo "  Admin: https://mail.adscreen.az (after tunnel config)"
echo "  Default admin: admin / moohoo (CHANGE IMMEDIATELY)"
echo ""
echo "  Next: Add to Cloudflare tunnel config:"
echo "    - hostname: mail.adscreen.az"
echo "      service: http://127.0.0.1:8880"
echo ""
echo "  Then run provisioning:"
echo "    export MAILCOW_API_KEY=<from mailcow.conf>"
echo "    node /home/zynorex/rpi-infrastructure/mailcow/mailcow-provision.js"
echo "═══════════════════════════════════════════════════════════"
