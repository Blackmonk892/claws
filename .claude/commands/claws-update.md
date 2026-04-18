---
name: claws-update
description: One command. Pulls the latest Claws source, runs the project-local installer (which rebuilds the TypeScript bundle, refreshes .mcp.json + .claws-bin + .claude, migrates legacy CLAUDE.md, verifies everything with 10 checks), syncs extension docs, shows the changelog, and renders the CLAWS banner. The user types /claws-update and waits.
---

# /claws-update

**Run from the project root** so the installer targets the right folder. Single bash call:

```bash
PROJECT_PWD="$(pwd)" && cd ~/.claws-src && git pull --ff-only origin main && cp README.md extension/README.md 2>/dev/null; cp CHANGELOG.md extension/CHANGELOG.md 2>/dev/null; cd "$PROJECT_PWD" && bash ~/.claws-src/scripts/install.sh && echo "" && echo "  ═══════════════════════════════════════" && echo "  WHAT'S NEW (full log: ~/.claws-src/CHANGELOG.md)" && echo "  ═══════════════════════════════════════" && awk '/^## \[/{c++} c==1 && NR>1{print}' ~/.claws-src/CHANGELOG.md | head -60 && echo "" && echo "  ═══════════════════════════════════════" && unset CLAWS_BANNER_SHOWN && source ~/.claws-src/scripts/shell-hook.sh
```

ONE bash call. Do NOT break into multiple steps. Do NOT interleave commentary. Let the output speak for itself.

## What this does

1. **`cd ~/.claws-src && git pull --ff-only origin main`** — fast-forward pull of the source.
2. **Syncs `README.md` and `CHANGELOG.md` into `extension/`** — keeps the marketplace-facing docs in step with the root.
3. **Runs `~/.claws-src/scripts/install.sh` from the current project root** — this is the rewritten v0.4 installer. It:
   - Rebuilds the TypeScript bundle (`dist/extension.js`) with esbuild. Falls back to legacy JS if `node-pty` doesn't compile.
   - Re-creates/refreshes the `~/.vscode/extensions/neunaha.claws-<version>` symlink.
   - Writes `<project>/.mcp.json`, `<project>/.claws-bin/{mcp_server.js, shell-hook.sh}`.
   - Copies all 19 slash commands, rules, and skills into `<project>/.claude/`.
   - Runs the CLAUDE.md injector — **migrates legacy v0.1–v0.3 `## CLAWS — Terminal Orchestration Active` sections into the new fenced `<!-- CLAWS:BEGIN --> ... <!-- CLAWS:END -->` block** while preserving all other project content.
   - Runs 10 verification checks with visible ✓/✗ markers.
   - Saves a full install log to `/tmp/claws-install-<timestamp>.log`.
4. **Prints the latest changelog entry** (just the newest `## [x.y.z]` section).
5. **Re-sources the shell hook** so the new CLAWS banner renders in the current terminal.

## After the output finishes, tell the user EXACTLY this

Update complete. **Two things to activate:**

1. **Reload VS Code** — `Cmd+Shift+P → Developer: Reload Window`
2. **Restart Claude Code in this project** — exit this Claude session and re-open `claude` from the project root so the new project-local `.mcp.json` is picked up.

If anything looks off:
- **MCP tools not appearing?** → run `/claws-fix`
- **Install looked wrong or something failed?** → run `/claws-report` to bundle logs + diagnostics, then share the file (`~/claws-report-<timestamp>.txt`) for help.
- **See the install log directly**: the banner at the end of `/claws-update` prints the log path (`/tmp/claws-install-<timestamp>.log`).
