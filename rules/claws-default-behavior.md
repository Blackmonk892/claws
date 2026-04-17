# Claws Terminal Orchestration — Default Behavior

> This rule is auto-installed by Claws. It changes how you operate terminals.
> Remove from ~/.claude/rules/ to revert to default behavior.

## When Claws is available, use it

Before running any shell command via the Bash tool, check if the Claws MCP tools are available (`claws_list`, `claws_create`, `claws_exec`, etc.). If they are:

**Use Claws terminals instead of Bash for all visible work.** The user should see what you're doing in their VS Code terminal panel — not just tool results in the chat.

### Default operating mode

1. **For any task that produces visible output the user should watch** (builds, tests, server starts, code generation, AI worker sessions): create a wrapped Claws terminal and run the work there. The user watches it happen live.

2. **For quick diagnostic commands** (checking a file, git status, reading a value): use the Bash tool directly. No need to spawn a terminal for `ls` or `cat`.

3. **For multi-step tasks**: spawn a dedicated wrapped terminal per work stream. Run each stream visibly. Monitor via `claws_read_log`. Clean up when done.

### The rule of thumb

> If the user would benefit from watching the command run — use Claws.
> If it's a quick lookup you'll report back — use Bash.

### Specific behaviors

**When the user asks to "run tests":**
- Create a wrapped terminal: `claws_create name="tests" wrapped=true`
- Send the test command: `claws_send id=N text="npm test"`
- Read the result: `claws_read_log id=N`
- Report + close: `claws_close id=N`

**When the user asks to "build":**
- Same pattern: create → send → monitor → close

**When the user asks for parallel work (lint + test + build, audit multiple things):**
- Create N wrapped terminals, one per task
- Fire all commands
- Monitor all via read_log rotation
- Close each when done
- Report aggregated results

**When the user asks to run an AI worker session:**
- Use `claws_worker name="worker-name" mission="the mission prompt"`
- This auto-launches Claude Code with full permissions in a visible terminal
- Monitor via `claws_read_log`
- Close when MISSION_COMPLETE detected

**When spawning Claude Code in a terminal:**
- ALWAYS use interactive mode: `claude --dangerously-skip-permissions`
- NEVER use headless mode: `claude -p "..."`
- The user must see the TUI in their terminal panel

### Cleanup is mandatory

Every terminal you create via Claws MUST be closed when the work is done. Run `claws_list` at the end of any orchestration to verify no stale terminals remain. If you find terminals you created that are still open, close them.

### Terminal naming

Use descriptive names: `worker-lint`, `worker-test`, `build-server`, `ai-audit-1`. Never use generic names like `terminal` or `shell`.
