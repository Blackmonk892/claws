---
name: claws-update
description: Pull the latest Claws, re-inject all rules/skills/commands into Claude Code globally, update the Python client, reload the shell hook. Full update in one command.
---

# /claws-update

Pull latest and re-inject everything into this machine's Claude Code.

## What to do

Run ALL of these steps in sequence:

```bash
cd ~/.claws-src && git pull origin main && echo "=== pulled ===" && git log --oneline -5
```

```bash
chmod +x ~/.claws-src/scripts/terminal-wrapper.sh ~/.claws-src/scripts/install.sh ~/.claws-src/mcp_server.py ~/.claws-src/scripts/test-install.sh
```

```bash
# Re-inject behavior rule
cp ~/.claws-src/rules/claws-default-behavior.md ~/.claude/rules/ 2>/dev/null

# Re-inject skills
cp -r ~/.claws-src/.claude/skills/claws-orchestration-engine ~/.claude/skills/ 2>/dev/null
cp -r ~/.claws-src/.claude/skills/prompt-templates ~/.claude/skills/claws-prompt-templates 2>/dev/null

# Re-inject all slash commands
for cmd in claws-status claws-connect claws-create claws-send claws-exec claws-read claws-worker claws-fleet claws-update claws-install; do
  [ -f ~/.claws-src/.claude/commands/${cmd}.md ] && cp ~/.claws-src/.claude/commands/${cmd}.md ~/.claude/commands/
done

echo "✓ rules + skills + commands re-injected"
```

```bash
pip3 install -e ~/.claws-src/clients/python --quiet 2>/dev/null && echo "✓ python client updated"
```

```bash
source ~/.claws-src/scripts/shell-hook.sh
```

After running all steps, tell the user:

"Claws updated. Rules, skills, commands, and shell hook all re-injected. Reload VS Code to activate extension changes: Cmd+Shift+P → Developer: Reload Window.

**Quick guide — talk to me naturally:**

Instead of 'run npm test', say:
→ 'run the tests in a visible terminal so I can watch'

Instead of 'fix this bug', say:
→ 'spawn a worker to fix this bug — I want to see the process'

Instead of 'check lint, test, and types', say:
→ 'spawn 3 parallel workers for lint, test, and typecheck'

Power moves:
→ 'spawn a Claude worker to refactor the auth module'
→ 'run a fleet of 3 audit workers analyzing latency, tokens, and code quality'
→ 'create a wrapped terminal and drive it step by step'"
