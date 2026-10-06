#!/bin/bash
# Route + bind helper notes for MTN via Ghafir (STE).
# App uses MTN_SMS_BIND_INTERFACE=wlp131s0 (CURLOPT_INTERFACE).
set -euo pipefail
WIFI="${MTN_SMS_IFACE:-wlp131s0}"
GW="${MTN_SMS_GW:-192.168.1.1}"
SRC="$(ip -4 -o addr show dev "$WIFI" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1 || true)"
if [[ -z "${SRC}" ]]; then
  echo "ERROR: no IPv4 on $WIFI (is Ghafir connected?)" >&2
  exit 1
fi
mapfile -t IPS < <(getent ahostsv4 services.mtnsyr.com 2>/dev/null | awk '{print $1}' | sort -u)
IPS+=("188.160.0.43")
declare -A SEEN=()
for ip in "${IPS[@]}"; do
  [[ -z "$ip" ]] && continue
  [[ -n "${SEEN[$ip]:-}" ]] && continue
  SEEN[$ip]=1
  ip route replace "${ip}/32" via "$GW" dev "$WIFI" src "$SRC" metric 5
  echo "routed $ip via $WIFI src=$SRC"
done
echo -n "exit IP via $WIFI: "
curl -4 -sS --interface "$WIFI" --connect-timeout 8 --max-time 12 https://api.ipify.org; echo
