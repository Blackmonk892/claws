---
name: claws-update
description: One command. Pulls latest Claws, rebuilds the TypeScript extension bundle, re-runs the project-local installer (migrates legacy CLAUDE.md, refreshes .mcp.json + .claws-bin + .claude), shows what's new, renders the CLAWS banner. The user types /claws-update and waits. Nothing else needed.
---

# /claws-update

**Run from the project root** (so project-local install targets the right folder). Single bash call — pull, rebuild, re-install, migrate, verify, render banner:

```bash
PROJECT_PWD="$(pwd)" && cd ~/.claws-src && git pull origin main 2>&1 && ( cd extension && npm install --no-audit --no-fund --loglevel=error --silent && npm run build --silent ) 2>&1 | tail -5 && cp README.md extension/README.md 2>/dev/null; cp CHANGELOG.md extension/CHANGELOG.md 2>/dev/null; cd "$PROJECT_PWD" && bash ~/.claws-src/scripts/install.sh && echo "" && echo "  ═══════════════════════════════════════" && echo "  WHAT'S NEW (full: ~/.claws-src/CHANGELOG.md):" && echo "  ═══════════════════════════════════════" && head -60 ~/.claws-src/CHANGELOG.md | tail -55 && echo "" && echo "  ═══════════════════════════════════════" && unset CLAWS_BANNER_SHOWN && source ~/.claws-src/scripts/shell-hook.sh
```

ONE bash call. Do NOT break into multiple steps. Do NOT interleave commentary. Let the output speak for itself.

## What this does for v0.3 → v0.4 upgraders

1. **Pulls latest** into `~/.claws-src`.
2. **Rebuilds the extension bundle** — TypeScript + esbuild produce `dist/extension.js`. Optional `node-pty` native module compiles; if it fails the installer falls back to legacy JS (extension still works, without the Pseudoterminal path).
3. **Runs the installer against THIS project** — writes `<project>/.mcp.json`, `<project>/.claws-bin/mcp_server.js`, `<project>/.claude/{commands,rules,skills}/`, and **automatically migrates any legacy `## CLAWS — Terminal Orchestration Active` section** in `<project>/CLAUDE.md` into the new fenced `<!-- CLAWS:BEGIN --> ... <!-- CLAWS:END -->` block.
4. **Shows the v0.4 changelog + renders the ASCII banner.**

## After the output finishes, tell the user EXACTLY this

Update complete. **Two things to activate v0.4:**

1. **Reload VS Code** — `Cmd+Shift+P → Developer: Reload Window`
2. **Restart Claude Code in this project** — exit this Claude session and re-open `claude` from the project root so the new project-local `.mcp.json` is picked up.

If the MCP tools don't appear after restart, run `/claws-fix`.
