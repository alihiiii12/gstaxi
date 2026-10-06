#!/bin/bash
# Switch WiFi to Alaa ghafir and probe/send MTN SMS.
set -euo pipefail
SSID='Alaa ghafir'
PASS='1234567890'
WIFI=wlp131s0
API=/var/www/gstaxi/api

echo "=== backup netplan ==="
cp -a /etc/netplan/60-wifi.yaml "/etc/netplan/60-wifi.yaml.bak.$(date +%s)" || true

echo "=== write 60-wifi.yaml ==="
python3 - <<PY
from pathlib import Path
ssid = """${SSID}"""
pw = """${PASS}"""
Path("/etc/netplan/60-wifi.yaml").write_text(
f"""network:
  version: 2
  renderer: networkd
  wifis:
    {WIFI}:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 600
      access-points:
        "{ssid}":
          password: "{pw}"
"""
)
print("wrote ok")
PY
chmod 600 /etc/netplan/60-wifi.yaml
cat /etc/netplan/60-wifi.yaml

echo "=== netplan apply ==="
netplan apply
sleep 8
ip link set "$WIFI" up || true
sleep 5

echo "=== link ==="
iw dev "$WIFI" link || true
ip -br addr show "$WIFI" || true

echo "=== public IP via wifi ==="
curl -4 -sS --interface "$WIFI" --connect-timeout 10 --max-time 15 https://api.ipify.org || echo FAIL
echo
curl -4 -sS --interface "$WIFI" --connect-timeout 10 --max-time 15 https://ipinfo.io/org || true
echo

echo "=== MTN 7443 via wifi ==="
python3 - <<'PY'
import socket
s=socket.socket(); s.settimeout(12)
try:
  s.setsockopt(socket.SOL_SOCKET,25,b"wlp131s0\0")
  s.connect(("188.160.0.43",7443))
  print("7443 OPEN")
except Exception as e:
  print("7443 CLOSED", e)
finally:
  s.close()
PY

echo "=== send MTN test ==="
cd "$API"
# ensure bind interface
grep -q '^MTN_SMS_BIND_INTERFACE=' .env && sed -i 's/^MTN_SMS_BIND_INTERFACE=.*/MTN_SMS_BIND_INTERFACE=wlp131s0/' .env || echo 'MTN_SMS_BIND_INTERFACE=wlp131s0' >> .env
php artisan config:clear >/dev/null
php artisan config:cache >/dev/null
php scripts/test_mtn_sms.php 0938828814 || true
grep -E '\[mtn_sms\]' storage/logs/laravel.log | tail -5 || true
echo DONE
