---
name: claws-update
description: Full rebuild — pull latest Claws, re-run entire installer (all 8 steps), sync extension, show changelog. This is the standard operating procedure for every update.
---

# /claws-update

Standard operating procedure. Full rebuild every time.

## What to do

Step 1 — Pull latest and re-run the full installer:
```bash
cd ~/.claws-src && git pull origin main && bash scripts/install.sh
```

This re-runs ALL 8 steps:
1. git pull latest
2. Re-link VS Code extension (picks up new extension.js + images + README)
3. Re-set permissions on all scripts
4. Verify Node.js (zero Python needed)
5. Re-register MCP server (node mcp_server.js)
6. Re-inject ALL rules + skills + 17 slash commands + CLAUDE.md section
7. Re-inject shell hook (picks up new ASCII banner + commands)
8. Verify everything

Step 2 — Sync extension assets:
```bash
cd ~/.claws-src && cp README.md extension/README.md && cp CHANGELOG.md extension/CHANGELOG.md
```

Step 3 — Read the changelog:
```bash
cat ~/.claws-src/CHANGELOG.md
```

Step 4 — Summarize what's new for the user. Read the CHANGELOG.md output and show the latest version's Added/Fixed/Changed sections as a friendly message.

Step 5 — Tell the user:

"Claws fully rebuilt to [version from changelog]. Reload VS Code: Cmd+Shift+P → Developer: Reload Window.

Here's how to use the latest:
→ `/claws` for the dashboard
→ `/claws-do <task>` to run anything visibly
→ `/claws-go <mission>` to spawn an AI worker
→ `/claws-learn` for the full prompt guide
→ `/claws-watch` to see all terminals"
