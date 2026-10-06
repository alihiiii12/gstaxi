#!/bin/bash
echo "=== public IPs ==="
echo -n "ethernet Starlink: "
curl -4 -sS --interface enp133s0 --connect-timeout 8 --max-time 12 https://api.ipify.org; echo
echo -n "wifi Ghafir STE: "
curl -4 -sS --interface wlp131s0 --connect-timeout 8 --max-time 12 https://api.ipify.org; echo
echo "=== MTN ports to 188.160.0.43 ==="
python3 - <<'PY'
import socket
for iface, name in [("enp133s0", "ethernet"), ("wlp131s0", "wifi")]:
    for port in (7443, 443, 8443):
        s = socket.socket()
        s.settimeout(10)
        try:
            s.setsockopt(socket.SOL_SOCKET, 25, (iface + "\0").encode())
            s.connect(("188.160.0.43", port))
            print(f"{name:10} :{port} OPEN")
        except Exception as e:
            print(f"{name:10} :{port} CLOSED ({type(e).__name__})")
        finally:
            s.close()
PY
