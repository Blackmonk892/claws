#!/usr/bin/env python3
"""Basic orchestrator — list terminals, create one, run a command, read output."""

from claws import ClawsClient

# Connect to the Claws socket (adjust path to your workspace)
client = ClawsClient("/path/to/workspace/.claws/claws.sock")

# List existing terminals
print("=== Current terminals ===")
for t in client.list():
    wrap = "wrapped" if t.log_path else "unwrapped"
    print(f"  {t.id}  {t.name:<25} pid={t.pid}  [{wrap}]")

# Create a wrapped terminal
term = client.create("demo-worker", wrapped=True)
print(f"\nCreated terminal: id={term.id}")

# Wait for shell to initialize
import time
time.sleep(1.5)

# Execute a command and capture output
result = client.exec(term.id, "echo hello from claws && whoami && date")
print(f"\n=== Exec result ===")
print(f"exit code: {result.exit_code}")
print(f"output:\n{result.output}")

# Read the pty log (everything that happened in this terminal)
log = client.read_log(term.id, lines=20)
print(f"\n=== Pty log (last 20 lines) ===")
print(log)

# Clean up
client.close(term.id)
print(f"\nTerminal {term.id} closed.")
