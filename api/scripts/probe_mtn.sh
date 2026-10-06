#!/bin/bash
set -e
cd /var/www/gstaxi/api
echo "=== curl MTN ==="
curl -k -sS -m 25 -o /tmp/mtn_body.txt -w "http=%{http_code} time=%{time_total}\n" \
  "https://services.mtnsyr.com:7443/general/MTNSERVICES/ConcatenatedSender.aspx" || echo "curl_exit=$?"
if [ -f /tmp/mtn_body.txt ]; then
  echo "body_len=$(wc -c < /tmp/mtn_body.txt)"
  head -c 200 /tmp/mtn_body.txt; echo
fi
echo "=== ports ==="
timeout 20 bash -c 'echo >/dev/tcp/188.160.0.43/7443' && echo port7443_open || echo port7443_closed
timeout 8 bash -c 'echo >/dev/tcp/188.160.0.43/443' && echo port443_open || echo port443_closed
timeout 8 bash -c 'echo >/dev/tcp/188.160.0.43/80' && echo port80_open || echo port80_closed
echo "=== route ==="
ip route get 188.160.0.43 2>/dev/null || true
echo "=== recent mtn logs ==="
grep -E 'mtn_sms|Phone OTP MTN' storage/logs/laravel.log 2>/dev/null | tail -40 || true
echo "=== done ==="
