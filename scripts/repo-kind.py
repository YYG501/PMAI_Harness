#!/usr/bin/env python3
"""Resolve generator / consumer / uninitialized repository identity."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

from _lib.repo_identity import RepoIdentityError, classify_repo  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".", help="checkout root to classify")
    parser.add_argument("--json", action="store_true", help="emit a JSON object")
    args = parser.parse_args()

    try:
        root = Path(args.repo_root).expanduser().resolve(strict=True)
        kind = classify_repo(root)
    except RepoIdentityError as exc:
        print(f"repo identity error: {exc}", file=sys.stderr)
        return 2
    except (OSError, RuntimeError) as exc:
        print(f"repo identity error: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps({"schema_version": 1, "repo_root": str(root), "repo_kind": kind.value}))
    else:
        print(kind.value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
