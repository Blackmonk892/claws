---
name: claws-fleet
description: Spawn N parallel workers from a task list. Each task gets its own wrapped terminal + monitor. Fleet-level orchestration for parallel autonomous work.
---

# /claws-fleet <task-file-or-inline-json>

Spawn a fleet of parallel workers. Each task in the list gets its own wrapped terminal, its own command, and its own monitor. The orchestrator watches all monitors and reports as each worker completes.

## Input format

Either a JSON file path or inline JSON array:

```json
[
  {"name": "lint", "command": "npm run lint"},
  {"name": "test", "command": "npm test"},
  {"name": "build", "command": "npm run build"}
]
```

## What to do

1. Parse the task list.

2. For each task, in parallel:
   a. Create a wrapped terminal via `/claws-create <name>`
   b. Send the command via `/claws-send <id> <command>`
   c. Attach a Monitor to the pty log

3. Aggregate results as workers complete. Report:
   - Which workers finished successfully (exit 0 detected in log)
   - Which workers failed (error/traceback detected)
   - Which workers are still running

4. When all workers reach terminal state:
   - Close all worker terminals
   - Stop all monitors
   - Report final fleet summary: N succeeded, N failed, total wall-clock

## Example usage

```
/claws-fleet [{"name":"audit-a","command":"python3 scripts/audit_latency.py"},{"name":"audit-b","command":"python3 scripts/audit_tokens.py"}]
```
