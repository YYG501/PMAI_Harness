#!/usr/bin/env python3
"""Append-only JSONL event stream for task lifecycle tracking."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

# 让 _lib 可 import（task-events.py 在 scripts/，_lib 是同级子目录）
_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.events import CLI_RESTRICTED_EVENT_TYPES  # noqa: E402

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

    # 物理拒绝伪造审计证据：execution_started / execution_manual_completed
    # 不允许通过 CLI 直接写入。合规通路在 task-transition.py。
    if args.type in CLI_RESTRICTED_EVENT_TYPES:
        print(
            f"Error: 事件类型 {args.type!r} 不允许通过 task-events.py CLI 写入。\n"
            "  这是受保护的审计证据，必须经合规通路写入：\n"
            "    • 走 dispatch（执行器派发）：/task-execute 自动通过\n"
            "      python3 .claude/scripts/task-transition.py <task> --to 执行中 \\\n"
            "          --bound-to-execution-event started [...payload]\n"
            "    • Work 已手做完、PM 拍板补登（task 状态=执行中）：\n"
            "      python3 .claude/scripts/task-transition.py <task> \\\n"
            "          --register-manual-completion --reason \"<为何手做、PM 拍板>\"\n"
            "    • task 状态已=已完成、事件流缺 exec event（close-task I-CT7 挡）：\n"
            "      python3 .claude/scripts/task-transition.py <task> \\\n"
            "          --repair-evidence --reason \"<为何 work 真实完成>\"",
            file=sys.stderr,
        )
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


NO_REVIEW_SENTINELS = {"", "(无)", "无", "(none)", "none", "-", "n/a", "N/A"}


def _collect_completed(task_file: Path, event_type: str) -> set[str]:
    ep = events_path(task_file)
    completed: set[str] = set()
    if not ep.exists():
        return completed
    for line in ep.read_text(encoding="utf-8").strip().split("\n"):
        if not line:
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("event") == event_type:
            tool = ev.get("tool", "")
            if tool:
                completed.add(tool)
    return completed


def cmd_check_plan_reviews(args: argparse.Namespace) -> None:
    """Show plan_review status (informational, always exit 0).

    Plan reviews are PM-driven recommendations; this command lists the
    recommended set (by 「所属模块」) and which ones already have
    `plan_review_completed` events on record. It does not gate any
    transition — kept as a query interface for status views and skill
    summaries.
    """
    task_file = Path(args.task_file)
    if not task_file.exists():
        print(f"Error: task file not found: {task_file}", file=sys.stderr)
        sys.exit(1)

    fields = read_task_fields(task_file)
    module = fields.get("所属模块", "").strip()

    if module == "基础设施":
        recommended = ["/plan-eng-review"]
    else:
        recommended = ["/plan-eng-review", "/plan-design-review"]

    completed = _collect_completed(task_file, "plan_review_completed")
    ran = [t for t in recommended if t in completed]
    pending = [t for t in recommended if t not in completed]
    extra = sorted(completed - set(recommended))

    print(f"recommended: {', '.join(recommended)}")
    print(f"ran: {', '.join(ran) if ran else '(none)'}")
    print(f"pending: {', '.join(pending) if pending else '(none)'}")
    if extra:
        print(f"extra: {', '.join(extra)}")
    sys.exit(0)


def cmd_check_reviews(args: argparse.Namespace) -> None:
    """Show post-execute review status (informational, always exit 0).

    Recommended tools come from the task file's 「审查工具」 field
    (now semantically "推荐 review 工具"). PM runs them manually and
    pastes results back; AI appends `review_completed` events as an
    audit trail. This command never gates a transition.
    """
    task_file = Path(args.task_file)
    if not task_file.exists():
        print(f"Error: task file not found: {task_file}", file=sys.stderr)
        sys.exit(1)

    fields = read_task_fields(task_file)
    tools_str = fields.get("审查工具", "").strip()

    if tools_str in NO_REVIEW_SENTINELS:
        print("recommended: (none)")
        sys.exit(0)

    recommended = [
        t.strip()
        for t in tools_str.split(",")
        if t.strip() and t.strip() not in NO_REVIEW_SENTINELS
    ]
    if not recommended:
        print("recommended: (none)")
        sys.exit(0)

    completed = _collect_completed(task_file, "review_completed")
    ran = [t for t in recommended if t in completed]
    pending = [t for t in recommended if t not in completed]
    extra = sorted(completed - set(recommended))

    print(f"recommended: {', '.join(recommended)}")
    print(f"ran: {', '.join(ran) if ran else '(none)'}")
    print(f"pending: {', '.join(pending) if pending else '(none)'}")
    if extra:
        print(f"extra: {', '.join(extra)}")
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

    # check-reviews (informational; never exits non-zero)
    p_check = sub.add_parser(
        "check-reviews",
        help="Show recommended/ran/pending review tools (informational)",
    )
    p_check.add_argument("task_file", help="Path to task file")

    # check-plan-reviews (informational; never exits non-zero)
    p_plan = sub.add_parser(
        "check-plan-reviews",
        help="Show recommended/ran/pending plan review tools (informational)",
    )
    p_plan.add_argument("task_file", help="Path to task file")

    args = parser.parse_args()
    if args.command == "append":
        cmd_append(args)
    elif args.command == "list":
        cmd_list(args)
    elif args.command == "check-reviews":
        cmd_check_reviews(args)
    elif args.command == "check-plan-reviews":
        cmd_check_plan_reviews(args)


if __name__ == "__main__":
    main()
