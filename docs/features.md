# Claws — Complete Feature Reference

Everything the extension can do, in depth. For the quick overview, see the [README](../README.md).

---

## Table of Contents

- [Terminal Discovery](#terminal-discovery)
- [Terminal Creation](#terminal-creation)
- [Wrapped Terminals](#wrapped-terminals)
- [Text Injection (send)](#text-injection)
- [Command Execution (exec)](#command-execution)
- [Pty Log Reading (readLog)](#pty-log-reading)
- [Event Streaming (poll)](#event-streaming)
- [Terminal Profile — Dropdown Integration](#terminal-profile)
- [Safety Gate](#safety-gate)
- [Bracketed Paste](#bracketed-paste)
- [Configuration Reference](#configuration-reference)
- [Socket Server Internals](#socket-server-internals)
- [Cross-Device Control](#cross-device-control)

---

## Terminal Discovery

**Command**: `list`

Returns every open VS Code terminal with full metadata:

| Field | Type | Description |
|---|---|---|
| `id` | string | Stable numeric ID, persists for the terminal's lifetime |
| `name` | string | Terminal display name (user-set or auto-assigned) |
| `pid` | number | Shell process ID |
| `hasShellIntegration` | boolean | Whether VS Code's shell integration is active |
| `active` | boolean | Whether this is the currently focused terminal |
| `logPath` | string or null | Absolute path to the pty log file (null if not wrapped) |

**Why stable IDs matter**: VS Code's terminal API identifies terminals by object reference internally. Claws assigns each terminal a monotonically increasing numeric ID at first sight and holds it in a `WeakMap`. The ID survives terminal renames, focus changes, and extension reloads within the same VS Code session. External clients use this ID for every subsequent command — no fragile name-matching.

**Example response**:
```json
{
  "ok": true,
  "terminals": [
    {"id": "1", "name": "zsh", "pid": 45123, "hasShellIntegration": true, "active": false, "logPath": null},
    {"id": "3", "name": "build-worker", "pid": 45890, "hasShellIntegration": false, "active": true, "logPath": "/project/.claws/terminals/claws-3.log"}
  ]
}
```

---

## Terminal Creation

**Command**: `create`

Opens a new VS Code integrated terminal with full control over its configuration.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | string | `"claws"` | Display name in the terminal panel |
| `cwd` | string | workspace root | Working directory |
| `wrapped` | boolean | `false` | Wrap in `script(1)` for pty logging |
| `show` | boolean | `true` | Show the terminal panel and focus it |
| `shellPath` | string | system default | Override the shell binary |
| `env` | object | `{}` | Additional environment variables |

**Returns**: `{ id, logPath }` — the new terminal's stable ID and (if wrapped) the absolute path to its pty log file.

**Terminal naming**: the `name` parameter sets the tab label in VS Code's terminal panel. Use descriptive names for orchestration (`"lint-worker"`, `"test-runner"`, `"ai-session-1"`) so you can identify terminals visually.

**Working directory**: defaults to the workspace root. Set `cwd` to any absolute path to start the terminal elsewhere — useful for monorepo setups where different workers operate in different packages.

---

## Wrapped Terminals

The core innovation. A wrapped terminal runs your shell inside `script(1)`:

```
VS Code Terminal Panel
└── script(1) process
    └── /bin/zsh (your actual shell)
        └── whatever you run (claude, npm, vim, etc.)
```

`script(1)` is a standard Unix utility (ships with macOS and Linux) that records everything that flows through a pseudo-terminal to a file. Claws sets the output file to `.claws/terminals/claws-<id>.log` and passes it via the `CLAWS_TERM_LOG` environment variable.

### What gets captured

Everything. Every byte that the terminal renders:

- Shell prompts and command echoes
- stdout and stderr from every command
- Interactive TUI rendering (Claude Code's Ink framework, vim's ncurses, htop's dashboard)
- ANSI escape sequences (colors, cursor movement, screen clearing)
- Control characters

### What you get back (after ANSI stripping)

Clean, readable text. Claws strips ANSI CSI sequences (`\e[...m`, `\e[...H`, etc.), OSC sequences (`\e]...BEL`), and control characters (`\x00-\x1f` except `\n` and `\t`). The result is what a human would read if they were watching the terminal.

### Visual impact

Zero. A wrapped terminal looks, feels, and behaves identically to a regular terminal. The `script(1)` layer adds no visible latency, no changed prompts, no extra processes in the shell's job table. The user cannot tell the difference unless they check for the `CLAWS_WRAPPED=1` environment variable.

### Log buffering

`script(1)` buffers output before writing to disk. On macOS with the default settings (no `-F` flag), there's a ~1-2 second delay before new content appears in the log file. This is intentional — aggressive flushing (`-F` flag) causes visual corruption in Ink-based TUI renderers (like Claude Code) by splitting their atomic frame updates across flush boundaries.

### Creating wrapped terminals

Three ways:

1. **From the dropdown**: Click the arrow next to `+` in the terminal panel → "Claws Wrapped Terminal"
2. **From code**: `client.create("name", wrapped=True)`
3. **From the socket**: `{"cmd": "create", "name": "name", "wrapped": true}`

### The wrapper script

Located at `scripts/terminal-wrapper.sh`. It:

1. Creates the log directory if missing
2. Truncates the log file (fresh start)
3. Sets `CLAWS_WRAPPED=1` in the environment
4. Exec-replaces itself with `script -q "$CLAWS_TERM_LOG" /bin/zsh -il`

The script is resolved at runtime: Claws checks for a workspace-local `scripts/terminal-wrapper.sh` first, then falls back to the extension-bundled copy.

---

## Text Injection

**Command**: `send`

Sends text into any terminal's input stream. This is equivalent to a human typing — the text appears at whatever input cursor is active (shell prompt, TUI input field, REPL prompt).

| Parameter | Type | Default | Description |
|---|---|---|---|
| `id` | string | required | Target terminal ID |
| `text` | string | required | Text to send |
| `newline` | boolean | `true` | Append Enter (newline) after the text |

**Single-line**: `{"cmd": "send", "id": "3", "text": "ls -la"}` — sends `ls -la\n` into the terminal.

**Raw keystrokes**: Set `newline: false` and send control characters directly:
- `\r` — Enter (carriage return, needed for some TUIs)
- `\x03` — Ctrl+C (interrupt)
- `\x04` — Ctrl+D (EOF)
- `\x1a` — Ctrl+Z (suspend)
- `\x1b` — Escape

**Sending to TUI sessions**: When the terminal is running Claude Code, vim, or any interactive program, `send` delivers text to that program's input handler. This is how AI orchestration works — you send a prompt as text into a Claude Code session, and Claude Code processes it as a user turn.

---

## Command Execution

**Command**: `exec`

Runs a shell command in a terminal and captures structured output. Unlike `send`, `exec` waits for the command to finish and returns the result.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `id` | string | auto-created | Target terminal ID |
| `command` | string | required | Shell command to run |
| `timeoutMs` | number | `180000` | Max wait time in milliseconds |

**Returns**:
```json
{
  "ok": true,
  "terminalId": "3",
  "commandLine": "npm test",
  "output": "PASS src/utils.test.ts\nTests: 5 passed\n",
  "exitCode": 0
}
```

### How file-based capture works

Shell integration (`onDidEndTerminalShellExecution`) is unreliable in many terminal configurations. Claws uses a robust alternative:

1. Wraps your command: `{ your_command; } > /tmp/claws-exec/abc123.out 2>&1; echo $? > /tmp/claws-exec/abc123.done`
2. Sends the wrapped command via `send`
3. Polls for the `.done` marker file
4. Reads the output file and exit code
5. Cleans up both temp files

This works in **every terminal type** — wrapped, unwrapped, with or without shell integration, bash, zsh, fish.

### Auto-created exec terminal

If you call `exec` without specifying a terminal `id`, Claws automatically creates (or reuses) a terminal named `claws-work` for execution. This is the simplest path for scripts that just need to run commands.

### Timeout handling

If the command doesn't produce a `.done` file within `timeoutMs`, `exec` returns an error with whatever partial output was captured. The command itself keeps running in the terminal — Claws doesn't kill it.

---

## Pty Log Reading

**Command**: `readLog`

Reads a wrapped terminal's pty log file with optional ANSI stripping.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `id` | string | required | Terminal ID (must be wrapped) |
| `offset` | number | tail of file | Byte offset to start reading from |
| `limit` | number | `524288` | Max bytes to read (512KB) |
| `strip` | boolean | `true` | Strip ANSI escape sequences |

**Returns**:
```json
{
  "ok": true,
  "bytes": "$ npm test\nPASS src/utils.test.ts\nTests: 5 passed\n$ ",
  "offset": 4096,
  "nextOffset": 4350,
  "totalSize": 4350,
  "truncated": false,
  "logPath": "/project/.claws/terminals/claws-3.log"
}
```

### Incremental tailing

Use `offset` and `nextOffset` for efficient tailing without re-reading the entire file:

```python
cursor = 0
while True:
    resp = client._send({"cmd": "readLog", "id": term_id, "offset": cursor})
    if resp["nextOffset"] > cursor:
        print(resp["bytes"])  # new content
        cursor = resp["nextOffset"]
    time.sleep(1)
```

### ANSI stripping

When `strip: true` (default), Claws removes:
- CSI sequences: `\e[0m`, `\e[31;1m`, `\e[2J`, `\e[H`, etc.
- OSC sequences: `\e]0;title\a`, `\e]133;...`, etc.
- Control characters: `\x00`-`\x08`, `\x0b`-`\x1a`, `\x1c`-`\x1f`, `\x7f`

Set `strip: false` to get the raw pty output with all escape sequences intact — useful for terminal replay or debugging rendering issues.

### Errors

- `"terminal X is not wrapped (no log path)"` — you called readLog on an unwrapped terminal. Create it with `wrapped: true`.
- `"read failed: ..."` — file I/O error (permissions, disk full, etc.)

---

## Event Streaming

**Command**: `poll`

Returns shell-integration command-completion events since a cursor position.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `since` | number | `0` | Sequence cursor — return only events after this |

Each event contains:

| Field | Type | Description |
|---|---|---|
| `seq` | number | Monotonically increasing sequence number |
| `terminalId` | string | Which terminal this event came from |
| `terminalName` | string | Terminal display name at time of event |
| `commandLine` | string | The command that was executed |
| `output` | string | Captured stdout (up to `maxOutputBytes`) |
| `exitCode` | number | Process exit code |
| `startedAt` | number | Epoch ms when the command started |
| `endedAt` | number | Epoch ms when the command finished |

**Cursor-based pagination**: Save the `cursor` from each response and pass it as `since` in the next call. You'll only receive new events.

**Reliability note**: `poll` depends on VS Code's `onDidEndTerminalShellExecution` API, which requires shell integration to be active. It's unreliable in wrapped terminals (where shell integration often doesn't inject) and in TUI sessions. For those cases, use `readLog` instead.

**Ring buffer**: Claws stores the last `maxHistory` events (default 500). Older events are dropped. If you poll infrequently, you may miss events that were pushed out of the buffer.

---

## Terminal Profile

Claws registers a terminal profile so "Claws Wrapped Terminal" appears in the VS Code terminal dropdown (the arrow next to `+`).

When selected:
1. Claws reserves a terminal ID and computes a log path
2. A new terminal opens with `scripts/terminal-wrapper.sh` as the shell
3. The `CLAWS_TERM_LOG` environment variable points to the log file
4. `onDidOpenTerminal` fires, Claws associates the terminal with the reserved ID

The profile name includes the ID: "Claws Wrapped 5". This is used for internal matching and can be renamed by the user after creation without affecting Claws.

---

## Safety Gate

Before `send` injects text, Claws inspects the terminal's process tree to detect the foreground process:

1. Reads the terminal's shell PID from VS Code's API
2. Runs `pgrep -P <pid>` to find child processes
3. Checks if the foreground child is a known shell (`bash`, `zsh`, `fish`, `sh`, `dash`, `ksh`)
4. If it's not a shell (e.g., `claude`, `vim`, `less`, `top`, `python3`), emits a warning

**Default behavior**: warn and proceed. The send goes through with a `[warning: foreground is 'vim' (not a shell)]` prefix in the response. The caller decides whether to continue.

**Strict mode**: Pass `strict: true` in the send request. Claws will refuse the send and return an error instead of a warning.

**Why warn instead of block**: The primary use case for Claws is AI pair programming, where you intentionally send prompts into Claude Code's TUI input. Blocking that would defeat the purpose. The warning exists to catch accidental sends (e.g., a script meant to run a shell command but the terminal is in vim).

---

## Bracketed Paste

When `send` receives multi-line text (contains `\n`), it automatically wraps it in bracketed paste mode:

```
\x1b[200~your multi-line text here\x1b[201~
```

This tells the terminal to treat the entire block as a single paste operation. Without it, each `\n` in the text would be interpreted as a separate Enter keystroke, causing the shell to execute each line independently — breaking multi-line commands, heredocs, and prompt text.

After the bracketed paste block, Claws sends a separate `\r` (carriage return) to submit the pasted content.

**Disable with `paste: false`** if you want raw line-by-line behavior.

---

## Configuration Reference

All settings live under the `claws` namespace in VS Code's settings (`settings.json`).

### `claws.socketPath`
- **Type**: string
- **Default**: `.claws/claws.sock`
- **Description**: Path to the Unix domain socket, relative to the workspace root. Claws creates the parent directory if it doesn't exist. The socket is created with `chmod 600` (owner-only access).

### `claws.logDirectory`
- **Type**: string
- **Default**: `.claws/terminals`
- **Description**: Directory where wrapped terminal pty logs are stored. Each terminal gets its own file: `claws-<id>.log`. Add `.claws/` to your `.gitignore`.

### `claws.defaultWrapped`
- **Type**: boolean
- **Default**: `false`
- **Description**: When `true`, every terminal created via the Claws API (not via VS Code's `+` button) is automatically wrapped with pty logging. Useful for AI orchestration setups where you always want readable terminals.

### `claws.maxOutputBytes`
- **Type**: number
- **Default**: `262144` (256KB)
- **Description**: Maximum bytes of stdout captured per shell-integration command event. Larger outputs are truncated with a `[...truncated N bytes]` note. Does not affect `readLog` (which has its own `MAX_READLOG_BYTES` of 512KB).

### `claws.maxHistory`
- **Type**: number
- **Default**: `500`
- **Description**: Maximum number of command-completion events retained in the ring buffer for `poll`. Older events are dropped FIFO. Increase if you poll infrequently and don't want to miss events.

---

## Socket Server Internals

### Lifecycle

1. **Activation**: Claws activates on `onStartupFinished`. It reads the workspace root, constructs the socket path, creates the directory, and starts a `net.createServer` listener.
2. **Connection**: Each client gets its own socket connection. Multiple clients can connect simultaneously. Requests are handled independently.
3. **Protocol**: Newline-delimited JSON. Each `\n`-terminated line is parsed as a JSON request, handled asynchronously, and the response is written back as a `\n`-terminated JSON line.
4. **Deactivation**: On VS Code shutdown or extension deactivation, the server is closed and the socket file is unlinked.

### Error handling

- Malformed JSON → `{"ok": false, "error": "bad json"}`
- Unknown command → `{"ok": false, "error": "unknown cmd: X"}`
- Missing terminal → `{"ok": false, "error": "unknown terminal id X"}`
- Handler exceptions → `{"ok": false, "error": "Error message"}`

### Security

- Socket created with `chmod 600` — only the current user can connect
- No authentication on Unix socket (same-user access is the trust boundary)
- WebSocket transport (planned) will add token-based auth + TLS

---

## Cross-Device Control

**Status**: Planned for v0.3

### Current workaround — SSH tunnel

You can control a remote VS Code instance today using an SSH tunnel:

```bash
# On your local machine:
ssh -L 9999:/remote/workspace/.claws/claws.sock user@remote-host

# Then connect locally:
from claws import ClawsClient
client = ClawsClient("/tmp/claws-remote.sock")  # forwarded socket
```

### Planned architecture

```
Device A (controller)           Device B (workspace)
┌──────────────┐               ┌──────────────────┐
│ Python/Node  │◄── WebSocket ─►│ Claws Extension  │
│ client       │    + TLS       │ (VS Code)        │
└──────────────┘    + token     └──────────────────┘
```

- **WebSocket transport**: opt-in alongside Unix socket
- **Token auth**: generated per-session, shown in the Claws output panel
- **TLS**: self-signed or ACME for encrypted connections
- **mDNS discovery**: auto-discover Claws-enabled VS Code instances on your LAN
- **Team config**: named devices with per-terminal read/write access control
