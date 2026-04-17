---
name: claws-create
description: Create a new wrapped terminal via Claws. Arguments — name (required), cwd (optional). Always creates wrapped for full pty capture.
---

# /claws-create <name> [cwd]

Create a new wrapped terminal with the given name.

## What to do

1. Parse the arguments. First arg is the terminal name, second is optional cwd.

2. Create the terminal via the socket:
```python
python3 -c "
import json, socket
s = socket.socket(socket.AF_UNIX)
s.connect('.claws/claws.sock')
req = {'id': 1, 'cmd': 'create', 'name': '$1', 'wrapped': True}
cwd = '$2' if '$2' else None
if cwd: req['cwd'] = cwd
s.sendall((json.dumps(req) + '\n').encode())
resp = json.loads(s.recv(65536).decode().split('\n')[0])
if resp.get('ok'):
    print(f\"created terminal id={resp['id']} logPath={resp.get('logPath')}\")
else:
    print(f\"ERROR: {resp.get('error')}\")
s.close()
"
```

3. Report the terminal ID and log path. Remind the user they can now use `/claws-send <id> <text>` or `/claws-exec <id> <command>`.
