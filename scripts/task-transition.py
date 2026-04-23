#!/usr/bin/env python3
"""Single entrypoint for task status transitions."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

FIELD_RE = re.compile(r"^\*\*(.+?)：\*\*\s*(.*)$")

VALID_TRANSITIONS = {
    "待确认": ["执行中"],
    "执行中": ["待验收", "待确认"],  # 待确认 = --fail-execution / --cancel-manual 回退
    "待验收": ["已完成", "执行中"],  # 执行中 = PM 打回
    "已完成": [],
}

# `执行中 → 待确认` is only reachable via --fail-execution or --cancel-manual;
# plain --to 待确认 from 执行中 is rejected.
RESTRICTED_TRANSITIONS = {("执行中", "待确认")}

SCRIPTS_DIR = Path(__file__).resolve().parent
EVENTS_SCRIPT = SCRIPTS_DIR / "task-events.py"


def find_main_repo_root() -> Path:
    """Resolve real repo root (not a worktree)."""
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


def pending_manual_path(task_file: Path) -> Path:
    """Locate the .pending-manual-<task_id>.json file in main repo's .runs/."""
    repo = find_main_repo_root()
    task_id = task_file.stem
    short_id_match = re.match(r"^(task-\d+)", task_id)
    short_id = short_id_match.group(1) if short_id_match else task_id
    return repo / ".runs" / f".pending-manual-{short_id}.json"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def save_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def read_fields(task_file: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    with task_file.open(encoding="utf-8") as fh:
        for idx, line in enumerate(fh):
            if idx >= 40:
                break
            match = FIELD_RE.match(line.strip())
            if match:
                fields[match.group(1).strip()] = match.group(2).strip()
    return fields


def update_field(text: str, field: str, value: str) -> tuple[str, int]:
    pattern = re.compile(
        rf"(^[ \t]*\*\*{re.escape(field)}：\*\*\s*).*$", re.MULTILINE
    )
    return pattern.subn(rf"\g<1>{value}", text, count=1)


def has_section_content(text: str, section_name: str) -> bool:
    """Check if a markdown section has non-template content."""
    pattern = re.compile(
        rf"^## {re.escape(section_name)}.*$", re.MULTILINE
    )
    match = pattern.search(text)
    if not match:
        return False

    # Get content between this section and the next
    start = match.end()
    next_section = re.search(r"^## ", text[start:], re.MULTILINE)
    if next_section:
        content = text[start : start + next_section.start()]
    else:
        content = text[start:]

    # Strip template lines and check for real content
    lines = [
        l.strip()
        for l in content.strip().split("\n")
        if l.strip()
        and not l.strip().startswith(">")
        and not l.strip().startswith("| 文档位置")
        and not l.strip().startswith("|---")
        and not l.strip().startswith("### 自审 1 - [")
        and not l.strip().startswith("### 执行报告 - [")
        and not l.strip().startswith("### 反馈 1 - [")
        and not l.strip().startswith("**工具：**")
        and not l.strip().startswith("**结果：**")
        and not l.strip().startswith("**详细发现：**")
        and not l.strip().startswith("**遗留问题：**")
        and not l.strip().startswith("**改动摘要：**")
        and not l.strip().startswith("**问题描述：**")
        and not l.strip().startswith("**要求修改：**")
        and not l.strip().startswith("**处理结果：**")
        and l.strip() != "无"
        and l.strip() != "---"
    ]
    return len(lines) > 0


def find_sibling_tasks(task_file: Path) -> list[tuple[Path, str]]:
    """Find other task files in the same req directory and their statuses."""
    tasks_dir = task_file.parent
    result = []
    for tf in sorted(tasks_dir.glob("task-*.md")):
        if tf == task_file:
            continue
        fields = read_fields(tf)
        status = fields.get("状态", "")
        result.append((tf, status))
    return result


def check_serial_constraint(task_file: Path) -> None:
    """v1 串行强制：同 req 下不能有其他 task 在执行中或待验收。"""
    siblings = find_sibling_tasks(task_file)
    blocking = [
        (tf.name, st)
        for tf, st in siblings
        if st in ("执行中", "待验收")
    ]
    if blocking:
        names = ", ".join(f"{n} ({s})" for n, s in blocking)
        print(
            f"Error: v1 串行模式下，同 req 下已有 task 在活跃状态: {names}。"
            f"请先完成当前 task 再启动新 task。",
            file=sys.stderr,
        )
        sys.exit(1)


def check_preconditions(
    task_file: Path, current: str, target: str, text: str, note: str | None
) -> None:
    """Check preconditions for a state transition."""

    if current == "待确认" and target == "执行中":
        # v1 串行强制
        check_serial_constraint(task_file)

    elif current == "执行中" and target == "待验收":
        # 1. 文档偏差 section 已填
        if not has_section_content(text, "文档偏差"):
            # Check for "无偏差"
            doc_section = re.search(
                r"^## 文档偏差.*?(?=^## |\Z)", text, re.MULTILINE | re.DOTALL
            )
            if doc_section and "无偏差" not in doc_section.group():
                print(
                    "Error: 文档偏差 section 未填写。请填写文档偏差或写'无偏差'。",
                    file=sys.stderr,
                )
                sys.exit(1)

        # 2. 自审记录 section 有内容
        if not has_section_content(text, "自审记录"):
            print(
                "Error: 自审记录 section 为空。请至少完成一次自审并记录结果。",
                file=sys.stderr,
            )
            sys.exit(1)

        # 3. 审查工具校验（通过事件流）
        result = subprocess.run(
            [sys.executable, str(EVENTS_SCRIPT), "check-reviews", str(task_file)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            output = (result.stdout or result.stderr or "").strip()
            print(f"Error: {output}", file=sys.stderr)
            sys.exit(1)

    elif current == "待验收" and target == "执行中":
        # PM 打回需要 note
        if not note:
            print(
                "Error: PM 打回必须提供反馈。使用 --note 参数。",
                file=sys.stderr,
            )
            sys.exit(1)


def append_event(task_file: Path, from_status: str, to_status: str, note: str | None) -> None:
    """Append a status_changed event to the event stream."""
    cmd = [
        sys.executable,
        str(EVENTS_SCRIPT),
        "append",
        str(task_file),
        "--type",
        "status_changed",
        "--from-status",
        from_status,
        "--to-status",
        to_status,
    ]
    if note:
        cmd.extend(["--note", note])
    subprocess.run(cmd, capture_output=True, text=True)


def do_transition(
    task_file: Path, current: str, target: str, note: str | None, via: str = "normal"
) -> None:
    """Execute the state transition and write event.

    `via` controls precondition bypass:
      - normal: full precondition check
      - fail-execution: skips 待验收 precondition check (failure回退)
      - cancel-manual: same as fail-execution
    """
    text = read_text(task_file)
    if via == "normal":
        check_preconditions(task_file, current, target, text, note)

    new_text, count = update_field(text, "状态", target)
    if count == 0:
        print("Error: 无法更新状态字段。", file=sys.stderr)
        sys.exit(1)
    save_text(task_file, new_text)
    append_event(task_file, current, target, note)


def cmd_fail_execution(task_file: Path, reason: str) -> None:
    """Handle --fail-execution: normalize failure fallback to 待确认."""
    fields = read_fields(task_file)
    current = fields.get("状态", "")
    if current != "执行中":
        print(
            f"Error: --fail-execution requires current status to be 执行中, got {current}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Clean up any stale pending-manual marker
    pf = pending_manual_path(task_file)
    if pf.exists():
        pf.unlink()

    note = f"执行失败回退：{reason}"
    do_transition(task_file, current, "待确认", note, via="fail-execution")
    print(f"✅ 执行失败已回退：执行中 → 待确认（{reason}）")


def cmd_cancel_manual(task_file: Path) -> None:
    """Handle --cancel-manual: PM gives up on manual task."""
    fields = read_fields(task_file)
    current = fields.get("状态", "")
    pf = pending_manual_path(task_file)
    if current != "执行中":
        print(
            f"Error: --cancel-manual 要求当前状态为 执行中，实际 {current}",
            file=sys.stderr,
        )
        sys.exit(1)
    if not pf.exists():
        print(
            f"Error: 找不到 manual 标记文件 {pf}。"
            f"只有当前正在 manual 等待的 task 可以 cancel。",
            file=sys.stderr,
        )
        sys.exit(1)

    pf.unlink()
    do_transition(task_file, current, "待确认", "PM 放弃 manual", via="cancel-manual")
    print(f"✅ Manual 放弃：标记已删除，状态回到 待确认")


def cmd_snooze_manual(task_file: Path, days: int) -> None:
    """Handle --snooze-manual --days N: suppress manual preamble reminder."""
    from datetime import datetime, timedelta, timezone

    pf = pending_manual_path(task_file)
    if not pf.exists():
        print(f"Error: 找不到 manual 标记文件 {pf}", file=sys.stderr)
        sys.exit(1)

    try:
        data = json.loads(pf.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"Error: 无法解析 manual 标记文件：{exc}", file=sys.stderr)
        sys.exit(1)

    until = datetime.now(timezone.utc) + timedelta(days=days)
    data["snoozed_until"] = until.isoformat()
    pf.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"✅ Manual 提醒暂缓 {days} 天（至 {until.date()}）")


def main() -> None:
    parser = argparse.ArgumentParser(description="Task status transition")
    parser.add_argument("task_file", help="Path to task file")
    parser.add_argument("--to", dest="target", help="Target status (normal transition)")
    parser.add_argument("--note", help="Note (required for PM rejection)")
    # Special-purpose flags
    parser.add_argument(
        "--fail-execution",
        action="store_true",
        help="Fail currently-executing task (执行中 → 待确认). Requires --reason.",
    )
    parser.add_argument(
        "--reason",
        help="Failure classification or description (used with --fail-execution)",
    )
    parser.add_argument(
        "--cancel-manual",
        action="store_true",
        help="PM 放弃 manual task: delete pending marker + 转回待确认",
    )
    parser.add_argument(
        "--snooze-manual",
        action="store_true",
        help="暂缓 manual 提醒 N 天，不改状态。与 --days 配合使用",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=3,
        help="Days to snooze manual reminder (default 3)",
    )
    args = parser.parse_args()

    task_file = Path(args.task_file).resolve()
    if not task_file.exists():
        print(f"Error: task file not found: {task_file}", file=sys.stderr)
        sys.exit(1)

    # Dispatch
    if args.fail_execution:
        if not args.reason:
            print("Error: --fail-execution requires --reason", file=sys.stderr)
            sys.exit(1)
        cmd_fail_execution(task_file, args.reason)
        return

    if args.cancel_manual:
        cmd_cancel_manual(task_file)
        return

    if args.snooze_manual:
        cmd_snooze_manual(task_file, args.days)
        return

    # Normal transition
    if not args.target:
        print("Error: --to <status> required for normal transitions", file=sys.stderr)
        sys.exit(1)

    fields = read_fields(task_file)
    current = fields.get("状态", "")
    if not current:
        print("Error: 无法读取 task 状态字段。", file=sys.stderr)
        sys.exit(1)

    target = args.target
    valid = VALID_TRANSITIONS.get(current, [])
    if target not in valid:
        print(
            f"Error: 非法状态转换: {current} → {target}。"
            f"合法目标: {', '.join(valid) if valid else '无（终态）'}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Block restricted transitions from going through plain --to
    if (current, target) in RESTRICTED_TRANSITIONS:
        print(
            f"Error: 非法状态转换: {current} → {target} 不能通过 --to 触发。"
            f"请用 --fail-execution --reason <text> 或 --cancel-manual。",
            file=sys.stderr,
        )
        sys.exit(1)

    # Clean up manual marker on transition to 待确认 (decisive policy)
    if target == "待确认":
        pf = pending_manual_path(task_file)
        if pf.exists():
            pf.unlink()

    do_transition(task_file, current, target, args.note)
    print(f"✅ Task 状态转换: {current} → {target}")
    if args.note:
        print(f"   备注: {args.note}")


if __name__ == "__main__":
    main()
