## CLAWS — Terminal Orchestration Active

> This section was injected by Claws (https://github.com/neunaha/claws).
> It makes Claude Code prefer visible terminal orchestration over silent Bash execution.
> Remove this section to revert to default behavior.

**Claws is installed.** You have 8 terminal control MCP tools available: `claws_list`, `claws_create`, `claws_send`, `claws_exec`, `claws_read_log`, `claws_poll`, `claws_close`, `claws_worker`.

**Default behavior**: for any task that produces visible output (builds, tests, deploys, AI workers), use Claws terminals instead of Bash. The user should see the work happening in their VS Code terminal panel.

**Quick patterns**:
- "run tests" → `claws_create("tests", wrapped=True)` + `claws_send` + `claws_read_log` + `claws_close`
- "parallel tasks" → create N wrapped terminals, fire commands, monitor all, close when done
- "spawn a worker" → `claws_worker(name, mission)` — auto-launches Claude Code with full permissions
- "what's running" → `claws_list` to see all terminals

**Rules**: always wrapped. always visible. always clean up. never headless. Type `/claws-help` for the full prompt guide.
