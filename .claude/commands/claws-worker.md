---
name: claws-worker
description: Spawn a full worker pattern — create wrapped terminal, launch a process inside it, attach a monitor. The production-grade way to run autonomous tasks. Arguments — name (required), command (required).
---

# /claws-worker <name> <command>

Spawn a complete worker terminal with monitoring. This is the pair-programmer pattern for autonomous tasks.

## What to do

1. Create a wrapped terminal:
```python
# Create terminal
python3 -c "
import json, socket
s = socket.socket(socket.AF_UNIX); s.connect('.claws/claws.sock')
s.sendall((json.dumps({'id':1,'cmd':'create','name':'$1','wrapped':True}) + '\n').encode())
resp = json.loads(s.recv(65536).decode().split('\n')[0])
print(f\"TERM_ID={resp['id']}\nLOG={resp.get('logPath')}\")
s.close()
"
```

2. Wait 1.5 seconds for the shell to initialize.

3. Send the command into the terminal:
```python
python3 -c "
import json, socket
s = socket.socket(socket.AF_UNIX); s.connect('.claws/claws.sock')
s.sendall((json.dumps({'id':1,'cmd':'send','id':'TERM_ID','text':'$2'}) + '\n').encode())
s.recv(4096)
s.close()
"
```

4. Attach a Monitor to the pty log for real-time event streaming:
```bash
tail -F LOG_PATH | perl -pe 'BEGIN{$|=1} s/\e\[[0-9;?]*[a-zA-Z]//g; s/\e\][^\a]*\a//g; s/[\x00-\x08\x0b-\x1a\x1c-\x1f\x7f]//g' | grep --line-buffered -E '(Read|Write|Edit|Bash|Grep|Glob)\([^)]{3,}|MISSION_COMPLETE|MISSION_FAILED|Traceback|Error|permission denied'
```

5. Report to the user: "Worker '$1' spawned. Terminal ID=X. Monitor attached. Watching for events."

6. When the task completes (MISSION_COMPLETE detected or process exits):
   - Read the final pty log via `/claws-read`
   - Close the terminal via the socket
   - Stop the monitor
   - Report: "Worker '$1' done. Terminal closed."
