#!/bin/bash
###############################################################################
#  update-tunnel-config.sh — Add ntfy & mail subdomains to Cloudflare Tunnel
#  Run on Pi: sudo bash update-tunnel-config.sh
###############################################################################
set -euo pipefail

CONFIG="/etc/cloudflared/config.yml"
BACKUP="${CONFIG}.bak.$(date +%s)"

echo "📋 Backing up current tunnel config..."
cp "$CONFIG" "$BACKUP"

# Check if ntfy already exists
if grep -q "ntfy.adscreen.az" "$CONFIG"; then
    echo "✅ ntfy.adscreen.az already configured"
else
    echo "Adding ntfy.adscreen.az ingress rule..."
    # Insert before the catch-all rule (last ingress entry)
    sed -i '/^  - service: http_status:404$/i\  - hostname: ntfy.adscreen.az\n    service: http://127.0.0.1:8089\n    originRequest:\n      noTLSVerify: true\n      connectTimeout: 30s\n      keepAliveTimeout: 90s' "$CONFIG"
    echo "✅ ntfy.adscreen.az added"
fi

# Check if mail already exists
if grep -q "mail.adscreen.az" "$CONFIG"; then
    echo "✅ mail.adscreen.az already configured"
else
    echo "Adding mail.adscreen.az ingress rule..."
    sed -i '/^  - service: http_status:404$/i\  - hostname: mail.adscreen.az\n    service: http://127.0.0.1:8880\n    originRequest:\n      noTLSVerify: true\n      connectTimeout: 30s\n      keepAliveTimeout: 90s' "$CONFIG"
    echo "✅ mail.adscreen.az added"
fi

echo ""
echo "🔄 Restarting cloudflared tunnel..."
systemctl restart cloudflared
sleep 2

if systemctl is-active --quiet cloudflared; then
    echo "✅ Cloudflare tunnel restarted successfully"
else
    echo "❌ Tunnel failed to restart. Restoring backup..."
    cp "$BACKUP" "$CONFIG"
    systemctl restart cloudflared
    echo "⚠️  Backup restored. Check config manually."
fi

echo ""
echo "🌐 New subdomains:"
echo "  - https://ntfy.adscreen.az  (Push Notifications)"
echo "  - https://mail.adscreen.az  (Mailcow Webmail)"
echo ""
echo "📌 Remember to add DNS records in Cloudflare:"
echo "  ntfy.adscreen.az  → CNAME → <tunnel-id>.cfargotunnel.com"
echo "  mail.adscreen.az  → CNAME → <tunnel-id>.cfargotunnel.com"
