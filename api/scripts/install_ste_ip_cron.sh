#!/bin/bash
set -euo pipefail
mkdir -p /home/gstaxi_1z/bin /var/www/gstaxi/api/storage/logs
cp -f /var/www/gstaxi/api/scripts/watch_ste_ip.sh /home/gstaxi_1z/bin/watch_ste_ip.sh
chmod +x /home/gstaxi_1z/bin/watch_ste_ip.sh
bash /home/gstaxi_1z/bin/watch_ste_ip.sh
CRON_LINE='15 * * * * /home/gstaxi_1z/bin/watch_ste_ip.sh >> /var/www/gstaxi/api/storage/logs/ste_ip_watch.cron.log 2>&1'
tmp="$(mktemp)"
crontab -l 2>/dev/null | grep -v watch_ste_ip.sh > "$tmp" || true
echo "$CRON_LINE" >> "$tmp"
crontab "$tmp"
rm -f "$tmp"
echo "crontab:"
crontab -l | grep watch_ste_ip || true
