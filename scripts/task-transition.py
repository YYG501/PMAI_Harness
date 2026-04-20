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
    "执行中": ["待验收"],
    "待验收": ["已完成", "执行中"],  # 执行中 = PM 打回
    "已完成": [],
}

SCRIPTS_DIR = Path(__file__).resolve().parent
EVENTS_SCRIPT = SCRIPTS_DIR / "task-events.py"


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


def main() -> None:
    parser = argparse.ArgumentParser(description="Task status transition")
    parser.add_argument("task_file", help="Path to task file")
    parser.add_argument(
        "--to", required=True, dest="target", help="Target status"
    )
    parser.add_argument("--note", help="Note (required for PM rejection)")
    args = parser.parse_args()

    task_file = Path(args.task_file).resolve()
    if not task_file.exists():
        print(f"Error: task file not found: {task_file}", file=sys.stderr)
        sys.exit(1)

    # Read current state
    fields = read_fields(task_file)
    current = fields.get("状态", "")
    if not current:
        print("Error: 无法读取 task 状态字段。", file=sys.stderr)
        sys.exit(1)

    target = args.target

    # Validate transition
    valid = VALID_TRANSITIONS.get(current, [])
    if target not in valid:
        print(
            f"Error: 非法状态转换: {current} → {target}。"
            f"合法目标: {', '.join(valid) if valid else '无（终态）'}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Check preconditions
    text = read_text(task_file)
    check_preconditions(task_file, current, target, text, args.note)

    # Execute transition
    new_text, count = update_field(text, "状态", target)
    if count == 0:
        print("Error: 无法更新状态字段。", file=sys.stderr)
        sys.exit(1)

    save_text(task_file, new_text)

    # Append event
    append_event(task_file, current, target, args.note)

    print(f"✅ Task 状态转换: {current} → {target}")
    if args.note:
        print(f"   备注: {args.note}")


if __name__ == "__main__":
    main()
