---
name: claws-update
description: Full rebuild — pull latest Claws, re-run entire installer, show what's new from the changelog. Every update is a complete fresh install.
---

# /claws-update

Full rebuild + changelog summary.

## What to do

Step 1 — Pull and rebuild:
```bash
cd ~/.claws-src && git pull origin main && bash scripts/install.sh
```

Step 2 — Read the changelog and show the user what's new:
```bash
cat ~/.claws-src/CHANGELOG.md
```

Step 3 — After the rebuild, read the CHANGELOG.md output and summarize it for the user. Show them the latest version section only — what was Added, Fixed, and Changed since their last update. Format it as a friendly "here's what's new" message.

Step 4 — End with usage suggestions based on what's new. For example, if a new command was added, show them how to use it. If a bug was fixed, tell them the issue is resolved.

Example response after update:

"Claws updated to v0.2.0. Here's what's new:

**New features:**
- MCP Server — every Claude Code session now has 8 native terminal tools
- `/claws-help` — prompt engineering guide from beginner to power user
- Your terminal now shows the CLAWS banner with live status
- `claws_worker` auto-launches Claude Code with full permissions

**Fixes:**
- Linux support — wrapped terminals now work on Ubuntu/Fedora
- macOS pip errors resolved
- Install never fails — everything continues gracefully

**Try these now:**
→ `/claws-help` for the full prompt guide
→ 'spawn a worker to run my tests'
→ 'run lint, test, build in 3 parallel terminals'

Reload VS Code to activate: Cmd+Shift+P → Developer: Reload Window"
