"""Claws Python client — zero-dependency socket client for the Claws VS Code extension."""

from __future__ import annotations

import json
import socket
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ExecResult:
    terminal_id: str
    command_line: str
    output: str
    exit_code: int | None


@dataclass(frozen=True)
class Terminal:
    id: str
    name: str
    pid: int | None
    has_shell_integration: bool
    active: bool
    log_path: str | None


class ClawsError(Exception):
    pass


class ClawsClient:
    """Client for the Claws VS Code extension socket server.

    Args:
        socket_path: Path to the Unix socket (absolute or relative to cwd).
        timeout: Default timeout in seconds for socket operations.
    """

    def __init__(self, socket_path: str | Path, *, timeout: float = 180.0) -> None:
        self._socket_path = Path(socket_path)
        self._timeout = timeout
        self._counter = 0

    def _send(self, req: dict[str, Any], timeout: float | None = None) -> dict[str, Any]:
        self._counter += 1
        req = {"id": self._counter, **req}
        t = timeout or self._timeout
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(t)
        try:
            sock.connect(str(self._socket_path))
            sock.sendall((json.dumps(req) + "\n").encode("utf-8"))
            buf = b""
            while b"\n" not in buf:
                chunk = sock.recv(65536)
                if not chunk:
                    break
                buf += chunk
            line = buf.split(b"\n", 1)[0]
            if not line:
                raise ClawsError("empty response from extension")
            return json.loads(line.decode("utf-8"))
        except (ConnectionRefusedError, FileNotFoundError) as e:
            raise ClawsError(f"cannot connect to {self._socket_path}: {e}") from e
        finally:
            try:
                sock.close()
            except Exception:
                pass

    def _require_ok(self, resp: dict[str, Any]) -> dict[str, Any]:
        if not resp.get("ok"):
            raise ClawsError(resp.get("error", "unknown error"))
        return resp

    def list(self) -> list[Terminal]:
        resp = self._require_ok(self._send({"cmd": "list"}))
        return [
            Terminal(
                id=t["id"],
                name=t.get("name", ""),
                pid=t.get("pid"),
                has_shell_integration=t.get("hasShellIntegration", False),
                active=t.get("active", False),
                log_path=t.get("logPath"),
            )
            for t in resp.get("terminals", [])
        ]

    def create(
        self,
        name: str = "claws",
        *,
        cwd: str | None = None,
        wrapped: bool = False,
        show: bool = True,
    ) -> Terminal:
        resp = self._require_ok(
            self._send({
                "cmd": "create",
                "name": name,
                "cwd": cwd,
                "wrapped": wrapped,
                "show": show,
            })
        )
        return Terminal(
            id=resp["id"],
            name=name,
            pid=None,
            has_shell_integration=False,
            active=True,
            log_path=resp.get("logPath"),
        )

    def show(self, terminal_id: str, *, preserve_focus: bool = True) -> None:
        self._require_ok(
            self._send({"cmd": "show", "id": terminal_id, "preserveFocus": preserve_focus})
        )

    def send(
        self,
        terminal_id: str,
        text: str,
        *,
        newline: bool = True,
    ) -> None:
        self._require_ok(
            self._send({"cmd": "send", "id": terminal_id, "text": text, "newline": newline})
        )

    def exec(
        self,
        terminal_id: str,
        command: str,
        *,
        timeout_ms: int = 180000,
        exec_dir: str | Path | None = None,
    ) -> ExecResult:
        """Execute a command with file-based output capture.

        This bypasses shell integration and works in any terminal type.
        Creates a temp file, redirects stdout+stderr into it, polls for
        a done marker, then reads the output.
        """
        exec_id = uuid.uuid4().hex[:10]
        base = Path(exec_dir) if exec_dir else Path("/tmp/claws-exec")
        base.mkdir(parents=True, exist_ok=True)
        out_path = base / f"{exec_id}.out"
        done_path = base / f"{exec_id}.done"
        wrapper = f"{{ {command}; }} > {out_path} 2>&1; echo $? > {done_path}"
        self.send(terminal_id, wrapper, newline=True)
        deadline = time.time() + (timeout_ms / 1000)
        while time.time() < deadline:
            if done_path.exists():
                break
            time.sleep(0.15)
        else:
            partial = out_path.read_text(errors="replace") if out_path.exists() else ""
            raise ClawsError(
                f"exec timeout after {timeout_ms}ms"
                + (f"\npartial output:\n{partial}" if partial else "")
            )
        exit_raw = done_path.read_text(errors="replace").strip()
        try:
            exit_code: int | None = int(exit_raw)
        except ValueError:
            exit_code = None
        output = out_path.read_text(errors="replace") if out_path.exists() else ""
        try:
            out_path.unlink(missing_ok=True)
            done_path.unlink(missing_ok=True)
        except OSError:
            pass
        return ExecResult(
            terminal_id=terminal_id,
            command_line=command,
            output=output,
            exit_code=exit_code,
        )

    def read_log(
        self,
        terminal_id: str,
        *,
        offset: int | None = None,
        limit: int | None = None,
        strip: bool = True,
        lines: int = 200,
    ) -> str:
        req: dict[str, Any] = {"cmd": "readLog", "id": terminal_id, "strip": strip}
        if offset is not None:
            req["offset"] = offset
        if limit is not None:
            req["limit"] = limit
        resp = self._require_ok(self._send(req))
        body = resp.get("bytes", "")
        all_lines = body.splitlines()
        tail = all_lines[-lines:] if len(all_lines) > lines else all_lines
        return "\n".join(tail)

    def poll(self, since: int = 0) -> tuple[list[dict[str, Any]], int]:
        resp = self._require_ok(self._send({"cmd": "poll", "since": since}))
        return resp.get("events", []), resp.get("cursor", since)

    def close(self, terminal_id: str) -> None:
        self._require_ok(self._send({"cmd": "close", "id": terminal_id}))
