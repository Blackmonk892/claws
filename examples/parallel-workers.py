#!/usr/bin/env python3
"""Parallel workers — spawn N terminals, run independent tasks, collect results."""

import time
from claws import ClawsClient

client = ClawsClient("/path/to/workspace/.claws/claws.sock")

tasks = [
    ("worker-1", "find . -name '*.py' | wc -l"),
    ("worker-2", "git log --oneline -5"),
    ("worker-3", "df -h | head -5"),
]

# Spawn all workers
workers = []
for name, cmd in tasks:
    term = client.create(name, wrapped=True)
    workers.append((term, cmd))
    print(f"spawned {name} -> id={term.id}")
time.sleep(1.5)  # let shells initialize

# Fire all commands
for term, cmd in workers:
    client.send(term.id, f"{{ {cmd}; }} && echo DONE", newline=True)
    print(f"fired command in {term.id}")

# Wait and collect
time.sleep(3)
for term, cmd in workers:
    log = client.read_log(term.id, lines=30)
    print(f"\n=== {term.name} ===")
    print(log)
    client.close(term.id)
    print(f"  (closed)")
