#!/bin/bash
python3 - <<'PY'
import json, base64
from pathlib import Path
token = Path('/etc/cloudflared/token').read_text().strip()
part = token.split('.')[1]
part += '=' * ((4 - len(part) % 4) % 4)
data = json.loads(base64.urlsafe_b64decode(part))
print('tunnel_id=' + str(data.get('t','')))
print('cname=' + str(data.get('t','')) + '.cfargotunnel.com')
PY
