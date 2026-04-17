---
name: claws-read
description: Read a wrapped terminal's pty log — see everything that happened including TUI sessions. Arguments — terminal ID (required), lines (optional, default 50).
---

# /claws-read <id> [lines]

Read the last N lines from a wrapped terminal's pty log with ANSI stripping.

## What to do

1. Read via the socket:
```python
python3 -c "
import json, socket
s = socket.socket(socket.AF_UNIX)
s.connect('.claws/claws.sock')
s.sendall((json.dumps({'id': 1, 'cmd': 'readLog', 'id': '$1', 'strip': True}) + '\n').encode())
resp = json.loads(s.recv(524288).decode().split('\n')[0])
if resp.get('ok'):
    body = resp.get('bytes', '')
    lines = body.splitlines()
    n = int('${2:-50}')
    for l in lines[-n:]:
        print(l)
    print(f'\n[{resp.get(\"totalSize\", 0)} bytes total · showing last {min(n, len(lines))} of {len(lines)} lines]')
else:
    print(f\"ERROR: {resp.get('error')}\")
s.close()
"
```

2. Show the clean text output to the user. Note: this only works for wrapped terminals (created with `wrapped: true`).
