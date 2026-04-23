#!/usr/bin/env python3
"""Append-only JSONL event stream for task lifecycle tracking."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

FIELD_RE = re.compile(r"^\*\*(.+?)：\*\*\s*(.*)$")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def find_repo_root() -> Path:
    """Find the real repo root (not a worktree)."""
    import subprocess
    try:
        common = subprocess.check_output(
            ["git", "rev-parse", "--git-common-dir"], text=True
        ).strip()
        if common and common != ".git":
            return Path(common).resolve().parent
    except Exception:
        pass
    try:
        return Path(
            subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], text=True
            ).strip()
        )
    except Exception:
        return Path.cwd()


def task_stem(task_file: Path) -> str:
    return task_file.stem


def events_path(task_file: Path) -> Path:
    repo = find_repo_root()
    stem = task_stem(task_file)
    return repo / ".runs" / "events" / f"{stem}.jsonl"


def read_task_fields(task_file: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    with task_file.open(encoding="utf-8") as fh:
        for idx, line in enumerate(fh):
            if idx >= 40:
                break
            m = FIELD_RE.match(line.strip())
            if m:
                fields[m.group(1).strip()] = m.group(2).strip()
    return fields


def cmd_append(args: argparse.Namespace) -> None:
    task_file = Path(args.task_file)
    if not task_file.exists():
        print(f"Error: task file not found: {task_file}", file=sys.stderr)
        sys.exit(1)

    ep = events_path(task_file)
    ep.parent.mkdir(parents=True, exist_ok=True)

    event: dict = {
        "event": args.type,
        "timestamp": now_iso(),
        "task": task_stem(task_file),
    }

    if args.tool:
        event["tool"] = args.tool
    if args.result:
        event["result"] = args.result
    if args.note:
        event["note"] = args.note
    if hasattr(args, "from_status") and args.from_status:
        event["from"] = args.from_status
    if hasattr(args, "to_status") and args.to_status:
        event["to"] = args.to_status
    # Free-form payload for executor events (execution_started/failed/completed etc)
    if hasattr(args, "payload") and args.payload:
        try:
            payload = json.loads(args.payload)
            if isinstance(payload, dict):
                for k, v in payload.items():
                    if k not in event:
                        event[k] = v
        except json.JSONDecodeError as exc:
            print(f"Error: --payload must be valid JSON ({exc})", file=sys.stderr)
            sys.exit(1)

    with ep.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(event, ensure_ascii=False) + "\n")

    print(f"Event appended: {args.type}", file=sys.stderr)


def cmd_list(args: argparse.Namespace) -> None:
    task_file = Path(args.task_file)
    ep = events_path(task_file)
    if not ep.exists():
        print("No events found.")
        return
    print(ep.read_text(encoding="utf-8"), end="")


def cmd_check_reviews(args: argparse.Namespace) -> None:
    """Check if review_completed events cover all required review tools."""
    task_file = Path(args.task_file)
    if not task_file.exists():
        print(f"Error: task file not found: {task_file}", file=sys.stderr)
        sys.exit(1)

    # Read required tools from task file
    fields = read_task_fields(task_file)
    tools_str = fields.get("审查工具", "").strip()

    # Sentinel values meaning "no review required"
    NO_REVIEW_SENTINELS = {"", "(无)", "无", "(none)", "none", "-", "n/a", "N/A"}

    if tools_str in NO_REVIEW_SENTINELS:
        print("PASS: no review tools required (sentinel value)")
        sys.exit(0)

    # Filter out sentinel values from the parsed list
    required = {
        t.strip()
        for t in tools_str.split(",")
        if t.strip() and t.strip() not in NO_REVIEW_SENTINELS
    }

    if not required:
        print("PASS: no review tools required (all values were sentinels)")
        sys.exit(0)

    # Read completed reviews from event stream
    ep = events_path(task_file)
    completed: set[str] = set()
    if ep.exists():
        for line in ep.read_text(encoding="utf-8").strip().split("\n"):
            if not line:
                continue
            try:
                ev = json.loads(line)
                if ev.get("event") == "review_completed":
                    tool = ev.get("tool", "")
                    if tool:
                        completed.add(tool)
            except json.JSONDecodeError:
                continue

    missing = required - completed
    if missing:
        print(f"FAIL: missing reviews for: {', '.join(sorted(missing))}")
        sys.exit(1)
    else:
        print(f"PASS: all {len(required)} review tools completed")
        sys.exit(0)


def main() -> None:
    parser = argparse.ArgumentParser(description="Task event stream manager")
    sub = parser.add_subparsers(dest="command", required=True)

    # append
    p_append = sub.add_parser("append", help="Append an event")
    p_append.add_argument("task_file", help="Path to task file")
    p_append.add_argument("--type", required=True, help="Event type")
    p_append.add_argument("--tool", help="Tool name (for review_completed)")
    p_append.add_argument("--result", help="Result (pass/fail)")
    p_append.add_argument("--note", help="Additional note")
    p_append.add_argument("--from-status", dest="from_status", help="From status")
    p_append.add_argument("--to-status", dest="to_status", help="To status")
    p_append.add_argument(
        "--payload",
        help="Free-form JSON object merged into event (executor/model/exit_code etc)",
    )

    # list
    p_list = sub.add_parser("list", help="List all events")
    p_list.add_argument("task_file", help="Path to task file")

    # check-reviews
    p_check = sub.add_parser("check-reviews", help="Check review coverage")
    p_check.add_argument("task_file", help="Path to task file")

    args = parser.parse_args()
    if args.command == "append":
        cmd_append(args)
    elif args.command == "list":
        cmd_list(args)
    elif args.command == "check-reviews":
        cmd_check_reviews(args)


if __name__ == "__main__":
    main()
