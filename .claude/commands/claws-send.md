---
name: claws-send
description: Send text into a terminal via Claws. Arguments — terminal ID (required), text (required). Supports multi-line via bracketed paste.
---

# /claws-send <id> <text>

Send text into terminal `<id>`. The text is delivered to whatever is running in that terminal — shell prompt, TUI input, REPL.

## What to do

1. Send the text via the socket:
```python
python3 -c "
import json, socket
s = socket.socket(socket.AF_UNIX)
s.connect('.claws/claws.sock')
s.sendall((json.dumps({'id': 1, 'cmd': 'send', 'id': '$1', 'text': '''$2''', 'newline': True}) + '\n').encode())
resp = json.loads(s.recv(65536).decode().split('\n')[0])
print('sent' if resp.get('ok') else f\"ERROR: {resp.get('error')}\")
s.close()
"
```

2. If the terminal is running a TUI (vim, claude, etc.), note the safety warning in the response but proceed — that's the intended use for AI orchestration.

3. Report success. If the user wants to see what happened, suggest `/claws-read <id>`.
