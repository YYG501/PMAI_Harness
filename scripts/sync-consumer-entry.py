#!/usr/bin/env python3
"""Check or apply the PMAI-managed AGENTS.md startup entry."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from _lib.atomic_file import AtomicFileError, replace_text_if_unchanged  # noqa: E402
from _lib.consumer_entry import ConsumerEntryError, plan_consumer_entry  # noqa: E402


SCHEMA_VERSION = 1


def _output(plan, *, mode: str, status: str | None = None, changed: bool = False) -> None:
    payload = {
        "schema_version": SCHEMA_VERSION,
        "mode": mode,
        "status": status or plan.status,
        "target": "AGENTS.md",
        "strategy": plan.strategy,
        "changed": changed,
    }
    if plan.reason:
        payload["message"] = plan.reason
    print(json.dumps(payload, ensure_ascii=False, indent=2))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--apply", action="store_true")
    args = parser.parse_args(argv)

    try:
        root = Path(args.repo_root).expanduser().resolve(strict=True)
        if not root.is_dir():
            raise ConsumerEntryError("消费仓根目录不是目录")
        template = SCRIPT_DIR.parent / "templates" / "AGENTS.md.tmpl"
        plan = plan_consumer_entry(root, template)
    except (ConsumerEntryError, OSError, RuntimeError, ValueError) as exc:
        print(
            json.dumps(
                {
                    "schema_version": SCHEMA_VERSION,
                    "mode": "apply" if args.apply else "check",
                    "status": "unsafe",
                    "target": "AGENTS.md",
                    "strategy": None,
                    "changed": False,
                    "message": str(exc),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 2

    selected_mode = "apply" if args.apply else "check"
    if args.check:
        _output(plan, mode=selected_mode)
        return 0 if plan.status == "current" else 1 if plan.can_apply else 2
    if plan.status == "current":
        _output(plan, mode=selected_mode)
        return 0
    if not plan.can_apply or plan.current_text is None or plan.rendered_text is None:
        _output(plan, mode=selected_mode)
        return 2
    try:
        replace_text_if_unchanged(
            plan.path,
            plan.rendered_text,
            expected_text=plan.current_text,
        )
    except AtomicFileError as exc:
        _output(plan, mode=selected_mode, status="unsafe")
        print(f"入口同步失败: {exc}", file=sys.stderr)
        return 2
    _output(plan, mode=selected_mode, status="updated", changed=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
