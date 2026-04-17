---
name: claws-update
description: Full rebuild — pull latest Claws, re-run entire installer, re-inject all rules/skills/commands/CLAUDE.md. Every update is a complete fresh install.
---

# /claws-update

Full rebuild. Re-runs the entire installer which pulls latest and re-injects everything.

## What to do

Run the full installer. It's idempotent — safe to re-run anytime:

```bash
cd ~/.claws-src && git pull origin main && bash scripts/install.sh
```

This re-runs ALL 8 steps: pull → extension → permissions → Python client → MCP server → rules + skills + commands + CLAUDE.md → shell hook → verify.

After it completes, tell the user:

"Claws fully rebuilt. Reload VS Code: Cmd+Shift+P → Developer: Reload Window.

Quick guide — talk naturally:
→ 'run tests in a visible terminal'
→ 'spawn a worker to fix that bug'
→ 'run lint, test, build in parallel'
→ 'spawn a Claude worker to refactor the auth module'
→ '/claws-help' for the full prompt guide"
