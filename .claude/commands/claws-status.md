---
name: claws-status
description: Show Claws extension status — socket path, connected clients, active terminals, wrapped terminals, log sizes. Quick health check.
---

# /claws-status

Show the current state of the Claws extension in this workspace.

## What to do

1. Check if the Claws socket exists and is listening:
```bash
ls -la .claws/claws.sock 2>/dev/null && echo "socket exists" || echo "no socket — is Claws extension activated?"
```

2. List all terminals via the socket:
```python
python3 -c "
import json, socket
s = socket.socket(socket.AF_UNIX)
s.connect('.claws/claws.sock')
s.sendall(b'{\"id\":1,\"cmd\":\"list\"}\n')
d = json.loads(s.recv(65536).decode().split('\n')[0])
for t in d.get('terminals', []):
    wrap = 'WRAPPED' if t.get('logPath') else 'unwrapped'
    marker = '*' if t.get('active') else ' '
    print(f\"{marker} {t['id']}  {t['name']:<30} pid={t['pid']}  [{wrap}]\")
s.close()
"
```

3. Show wrapped terminal log sizes:
```bash
ls -lh .claws/terminals/*.log 2>/dev/null || echo "no wrapped terminal logs"
```

4. Report the status concisely to the user.
