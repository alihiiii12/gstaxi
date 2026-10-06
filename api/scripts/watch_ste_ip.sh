#!/bin/bash
# يكتب Real IP لخط Ghafir/STE ويُسجّل إن تغيّر (مهم لتفعيل MTN).
set -euo pipefail
IFACE="${MTN_SMS_BIND_INTERFACE:-wlp131s0}"
API_DIR="${GSTAXI_API_DIR:-/var/www/gstaxi/api}"
LOG_DIR="${API_DIR}/storage/logs"
IP_FILE="${LOG_DIR}/ste_public_ip.txt"
CHANGE_LOG="${LOG_DIR}/ste_ip_changes.log"

mkdir -p "$LOG_DIR"
IP="$(curl -4 -sS --interface "$IFACE" --connect-timeout 8 --max-time 15 https://api.ipify.org || true)"
if [[ -z "$IP" ]]; then
  echo "FAIL: no public IP via $IFACE" >&2
  exit 1
fi

OLD=""
[[ -f "$IP_FILE" ]] && OLD="$(tr -d ' \n\r' < "$IP_FILE" || true)"
printf '%s\n' "$IP" > "$IP_FILE"
echo "STE/Ghafir Real IP: $IP (iface=$IFACE)"

if [[ -n "$OLD" && "$OLD" != "$IP" ]]; then
  msg="$(date '+%Y-%m-%d %H:%M:%S') STE IP changed: ${OLD} -> ${IP}"
  echo "$msg" | tee -a "$CHANGE_LOG"
  echo "WARN: بلّغ MTN بالـ IP الجديد وإلا SMS يتوقف." >&2
fi
