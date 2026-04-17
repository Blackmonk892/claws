"""Claws — Python client for the Claws VS Code extension.

Zero external dependencies. Stdlib only.

Usage:
    from claws import ClawsClient

    client = ClawsClient("/path/to/workspace/.claws/claws.sock")
    terminals = client.list()
    term = client.create("worker", wrapped=True)
    result = client.exec(term["id"], "echo hello")
    print(result["output"])
    client.close(term["id"])
"""

from claws.client import ClawsClient

__all__ = ["ClawsClient"]
__version__ = "0.1.0"
