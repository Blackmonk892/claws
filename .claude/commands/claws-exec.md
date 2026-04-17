---
name: claws-exec
description: Execute a command in a terminal and capture stdout + stderr + exit code. Arguments — terminal ID (optional, auto-creates if omitted), command (required).
---

# /claws-exec [id] <command>

Run a shell command in a terminal and return the captured output.

## What to do

1. If no terminal ID provided, create a temporary wrapped terminal first using `/claws-create exec-worker`.

2. Execute via file-based capture:
```python
python3 -c "
import json, socket, time, uuid, os
from pathlib import Path

s = socket.socket(socket.AF_UNIX)
s.connect('.claws/claws.sock')
tid = '$1'
cmd = '''$2'''

# file-based capture
eid = uuid.uuid4().hex[:8]
base = Path('/tmp/claws-exec')
base.mkdir(exist_ok=True)
out_f = base / f'{eid}.out'
done_f = base / f'{eid}.done'
wrapper = f'{{ {cmd}; }} > {out_f} 2>&1; echo \$? > {done_f}'

s.sendall((json.dumps({'id': 1, 'cmd': 'send', 'id': tid, 'text': wrapper}) + '\n').encode())
s.recv(4096)

deadline = time.time() + 180
while time.time() < deadline:
    if done_f.exists(): break
    time.sleep(0.2)

if done_f.exists():
    exit_code = done_f.read_text().strip()
    output = out_f.read_text() if out_f.exists() else ''
    print(f'exit={exit_code}')
    print(output)
    out_f.unlink(missing_ok=True)
    done_f.unlink(missing_ok=True)
else:
    print('TIMEOUT')
s.close()
"
```

3. Report the exit code and output to the user.
