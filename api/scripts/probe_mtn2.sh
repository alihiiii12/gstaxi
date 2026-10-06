#!/bin/bash
cd /var/www/gstaxi/api
echo "=== mtn log tail ==="
grep -E '\[mtn_sms\]|Phone OTP MTN' storage/logs/laravel.log | tail -50
echo "=== interfaces ==="
ip -br addr
echo "=== ping mtn ip ==="
ping -c 2 -W 3 188.160.0.43 || true
echo "=== traceroute hops ==="
traceroute -n -w 2 -q 1 -m 8 188.160.0.43 2>/dev/null | head -15 || true
echo "=== openssl ==="
timeout 20 openssl s_client -connect services.mtnsyr.com:7443 -servername services.mtnsyr.com </dev/null 2>&1 | head -20 || true
echo "=== done2 ==="
