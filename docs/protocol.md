# Claws Protocol Specification v1

## Transport

- **Unix socket** (default): workspace-relative path, default `.claws/claws.sock`
- **WebSocket** (planned): `ws://host:port` with token auth

## Framing

Newline-delimited JSON. Each message is one JSON object terminated by `\n`. Client sends requests; server sends responses. Every request carries an `id` (integer or string) which the server echoes in the response.

## Requests

```json
{ "id": 1, "cmd": "list" }
```

## Responses

```json
{ "id": 1, "ok": true, "terminals": [...] }
```

On error:

```json
{ "id": 1, "ok": false, "error": "description" }
```

---

## Commands

### `list`

Enumerate all open VS Code terminals.

**Request:** `{ "id": N, "cmd": "list" }`

**Response:**
```json
{
  "id": N,
  "ok": true,
  "terminals": [
    {
      "id": "1",
      "name": "Terminal Name",
      "pid": 12345,
      "hasShellIntegration": true,
      "active": false,
      "logPath": "/absolute/path/to/pty.log"  // null if unwrapped
    }
  ]
}
```

### `create`

Open a new terminal.

**Request:**
```json
{
  "id": N,
  "cmd": "create",
  "name": "my-terminal",       // optional, default "claws"
  "cwd": "/path/to/dir",       // optional, default workspace root
  "wrapped": true,              // optional, default false — wrap in script(1) for pty logging
  "show": true                  // optional, default true — show the terminal panel
}
```

**Response:**
```json
{
  "id": N,
  "ok": true,
  "id": "5",                    // terminal id
  "logPath": "/path/to/pty.log" // only present if wrapped=true
}
```

### `show`

Focus a terminal in the panel.

**Request:** `{ "id": N, "cmd": "show", "id": "5", "preserveFocus": true }`

**Response:** `{ "id": N, "ok": true }`

### `send`

Send text into a terminal. Supports bracketed paste for multi-line text.

**Request:**
```json
{
  "id": N,
  "cmd": "send",
  "id": "5",
  "text": "echo hello",
  "newline": true    // optional, default true — append Enter after text
}
```

**Response:** `{ "id": N, "ok": true }`

### `readLog`

Read a wrapped terminal's pty log. Only works for terminals created with `wrapped: true`.

**Request:**
```json
{
  "id": N,
  "cmd": "readLog",
  "id": "5",
  "offset": 0,       // optional — byte offset; default = tail of file
  "limit": 524288,    // optional — max bytes; default 512KB
  "strip": true       // optional — strip ANSI escape sequences; default true
}
```

**Response:**
```json
{
  "id": N,
  "ok": true,
  "bytes": "cleaned text content...",
  "offset": 0,
  "nextOffset": 1234,
  "totalSize": 5678,
  "truncated": false,
  "logPath": "/absolute/path/to/pty.log"
}
```

### `poll`

Drain shell-integration command-completion events since a cursor.

**Request:** `{ "id": N, "cmd": "poll", "since": 0 }`

**Response:**
```json
{
  "id": N,
  "ok": true,
  "events": [
    {
      "seq": 1,
      "terminalId": "3",
      "terminalName": "worker",
      "commandLine": "echo hello",
      "output": "hello\n",
      "exitCode": 0,
      "startedAt": 1713168000000,
      "endedAt": 1713168001000
    }
  ],
  "cursor": 1
}
```

Note: `poll` relies on VS Code shell integration (`onDidEndTerminalShellExecution`), which is unreliable in wrapped terminals and TUI sessions. For reliable output capture, use `readLog` on wrapped terminals or file-based `exec`.

### `close`

Dispose a terminal.

**Request:** `{ "id": N, "cmd": "close", "id": "5" }`

**Response:** `{ "id": N, "ok": true }`

---

## Error Codes

All errors return `{ "ok": false, "error": "message" }`. Common errors:

| Error | Meaning |
|---|---|
| `unknown terminal id X` | Terminal ID not found (closed or never existed) |
| `terminal X is not wrapped (no log path)` | `readLog` called on an unwrapped terminal |
| `bad json` | Request could not be parsed as JSON |
| `unknown cmd: X` | Unrecognized command name |

---

## Versioning

The protocol version is not currently exchanged in-band. Future versions will add a `handshake` command:

```json
{ "id": 0, "cmd": "handshake", "protocol": "claws/1", "client": "claws-python/0.1.0" }
```
