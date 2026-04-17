---
name: claws-connect
description: Connect to the Claws socket and verify the bridge is live. Run this first in any new Claude Code session to confirm terminal control is available.
---

# /claws-connect

Verify the Claws bridge is reachable and ready for terminal control.

## What to do

1. Detect the socket path (check config, fall back to default):
```bash
SOCK="${1:-.claws/claws.sock}"
test -S "$SOCK" && echo "socket found: $SOCK" || { echo "ERROR: no socket at $SOCK — is VS Code running with Claws extension?"; exit 1; }
```

2. Send a ping (list command) to verify the server responds:
```python
python3 -c "
import json, socket, sys
sock = socket.socket(socket.AF_UNIX)
try:
    sock.connect('${SOCK:-.claws/claws.sock}')
    sock.sendall(b'{\"id\":0,\"cmd\":\"list\"}\n')
    resp = json.loads(sock.recv(65536).decode().split('\n')[0])
    n = len(resp.get('terminals', []))
    print(f'Claws connected — {n} terminal(s) active')
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
finally:
    sock.close()
"
```

3. If connected, report: "Claws bridge live. N terminals visible. Ready for /claws-create, /claws-send, /claws-exec."
4. If failed, suggest: check that VS Code is open with the Claws extension installed, and run `Cmd+Shift+P → Developer: Reload Window`.
