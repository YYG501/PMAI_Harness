#!/usr/bin/env python3
"""Global status overview for PM AI Workflow."""

from __future__ import annotations

import argparse
import glob
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

FIELD_RE = re.compile(r"^\*\*(.+?)：\*\*\s*(.*)$")
STAGE_NAMES = {
    1: "感受问题",
    2: "需求分析",
    3: "方案设计",
    4: "设计系统建立",
    5: "模块规格 + task 拆分",
    6: "task 执行",
    7: "req close",
}
STATUS_ICONS = {
    "待确认": "⏳",
    "执行中": "🔄",
    "待验收": "📋",
    "已完成": "✅",
}


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


def find_current_worktree_root() -> Path:
    """Find the current worktree root (may differ from repo root)."""
    import subprocess

    try:
        return Path(
            subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], text=True
            ).strip()
        )
    except Exception:
        return Path.cwd()


def find_current_branch() -> str:
    import subprocess

    try:
        return subprocess.check_output(
            ["git", "branch", "--show-current"], text=True
        ).strip()
    except Exception:
        return ""


def read_task_fields(task_file: Path) -> dict[str, str]:
    """Read **field：** value pairs from task file header."""
    fields: dict[str, str] = {}
    with task_file.open(encoding="utf-8") as fh:
        for idx, line in enumerate(fh):
            if idx >= 40:
                break
            match = FIELD_RE.match(line.strip())
            if match:
                fields[match.group(1).strip()] = match.group(2).strip()
    return fields


def get_last_event(repo_root: Path, task_stem: str) -> str | None:
    """Get the last event from the task's event stream."""
    events_file = repo_root / ".runs" / "events" / f"{task_stem}.jsonl"
    if not events_file.exists():
        return None
    try:
        lines = events_file.read_text(encoding="utf-8").strip().split("\n")
        if lines and lines[-1]:
            event = json.loads(lines[-1])
            etype = event.get("event", "")
            if etype == "review_completed":
                tool = event.get("tool", "")
                result = event.get("result", "")
                return f"自审 - {tool} {result}"
            elif etype == "status_changed":
                return f"状态变更 → {event.get('to', '')}"
            else:
                return etype
    except Exception:
        pass
    return None


def _read_active_from(active_dir: Path) -> tuple[Path | None, dict | None]:
    if not active_dir.exists():
        return None, None
    for req_dir in sorted(active_dir.iterdir()):
        meta_file = req_dir / ".req-meta.json"
        if meta_file.exists():
            try:
                meta = json.loads(meta_file.read_text(encoding="utf-8"))
                if meta.get("status") == "active":
                    return req_dir, meta
            except Exception:
                continue
    return None, None


def find_active_req(repo_root: Path) -> tuple[Path | None, dict | None]:
    """Find the active requirement directory and its metadata.

    Active req state lives in the req worktree until close, not on main.
    Resolution order:
      1. If current worktree is a req/task worktree, read from there.
      2. Otherwise scan every req worktree under <repo_root>/.worktrees/req-*/
      3. Fall back to <repo_root>/requirements/active/ (for closed/archived reqs).
    """
    current_wt = find_current_worktree_root()
    current_branch = find_current_branch()

    # 1. If we're on a req branch, the current worktree is authoritative
    if current_branch.startswith("req-"):
        found = _read_active_from(current_wt / "requirements" / "active")
        if found[0]:
            return found

    # 1b. If we're on a task branch, walk up to its parent req worktree
    if current_branch.startswith("task-"):
        # Task worktree is at <repo>/.worktrees/task-*/, its parent req is at
        # <repo>/.worktrees/req-*/ — we don't know the name directly so scan all.
        worktrees_dir = repo_root / ".worktrees"
        if worktrees_dir.exists():
            for wt in sorted(worktrees_dir.iterdir()):
                if wt.name.startswith("req-"):
                    found = _read_active_from(wt / "requirements" / "active")
                    if found[0]:
                        return found

    # 2. Scan all req worktrees
    worktrees_dir = repo_root / ".worktrees"
    if worktrees_dir.exists():
        for wt in sorted(worktrees_dir.iterdir()):
            if wt.name.startswith("req-") and wt.is_dir():
                found = _read_active_from(wt / "requirements" / "active")
                if found[0]:
                    return found

    # 3. Fallback: main repo's active/ (mostly empty in normal flow)
    return _read_active_from(repo_root / "requirements" / "active")


def list_tasks(req_dir: Path) -> list[tuple[Path, dict[str, str]]]:
    """List all task files in a req directory with their fields."""
    tasks_dir = req_dir / "tasks"
    if not tasks_dir.exists():
        return []

    result = []
    for task_file in sorted(tasks_dir.glob("task-*.md")):
        fields = read_task_fields(task_file)
        result.append((task_file, fields))
    return result


def suggest_next_action(
    meta: dict, tasks: list[tuple[Path, dict[str, str]]]
) -> str:
    """Suggest what PM should do next."""
    stage = meta.get("stage", 0)

    if stage <= 5:
        return f"继续 stage {stage}（{STAGE_NAMES.get(stage, '?')}）的工作"

    if stage == 6:
        # Check task statuses
        for task_file, fields in tasks:
            status = fields.get("状态", "")
            name = task_file.stem
            if status == "待验收":
                return f"验收 {name}：运行 /task-submit"
            if status == "执行中":
                return f"等待 {name} 完成实现和自审"
            if status == "待确认":
                return f"确认启动 {name}：运行 /task-confirm"

        # All tasks done
        all_done = all(f.get("状态") == "已完成" for _, f in tasks)
        if all_done and tasks:
            return "所有 task 已完成，运行 /close-req 关闭需求"

    if stage == 7:
        return "Req 正在关闭中"

    return "运行 /status 查看详情"


def render_manual_section(repo_root: Path) -> None:
    """Render the Manual 等待中 section if there are pending manual tasks."""
    pending_dir = repo_root / ".runs"
    if not pending_dir.exists():
        return

    pattern = str(pending_dir / ".pending-manual-*.json")
    files = glob.glob(pattern)
    if not files:
        return

    now = datetime.now(timezone.utc)
    items: list[dict] = []
    for fp in files:
        try:
            data = json.load(open(fp, encoding="utf-8"))
        except Exception:
            continue
        snoozed = data.get("snoozed_until")
        if snoozed:
            try:
                s = datetime.fromisoformat(snoozed)
                if s.tzinfo is None:
                    s = s.replace(tzinfo=timezone.utc)
                if s > now:
                    continue  # still in snooze window
            except Exception:
                pass
        items.append(data)

    if not items:
        return

    print("Manual 等待中：")
    for data in sorted(items, key=lambda d: d.get("started_at", "")):
        task_id = data.get("task_id", "?")
        started = data.get("started_at", "")
        age_str = ""
        if started:
            try:
                s = datetime.fromisoformat(started)
                if s.tzinfo is None:
                    s = s.replace(tzinfo=timezone.utc)
                days = (now - s).days
                hrs = int(((now - s).total_seconds() % 86400) // 3600)
                age_str = f"等待 {days} 天 {hrs} 小时"
            except Exception:
                age_str = started
        print(f"  {task_id}（{age_str}）")
    print()
    # Pick the first task_file for copy-paste templating
    sample_task = items[0].get("task_file", "<task-file>")
    sample_id = items[0].get("task_id", "task-NNN")
    print("下一步：")
    print(f"  完成手工实现后： /task-execute {sample_id}")
    print(
        f"  暂时不想管：     python3 .claude/scripts/task-transition.py "
        f"{sample_task} --snooze-manual --days 3"
    )
    print(
        f"  放弃该 task：    python3 .claude/scripts/task-transition.py "
        f"{sample_task} --cancel-manual"
    )
    print()


def render_status(repo_root: Path) -> None:
    """Render the full status view."""
    req_dir, meta = find_active_req(repo_root)

    if meta is None:
        print("📭 没有活跃的需求。运行 /new-req 开始一个新需求。")
        render_manual_section(repo_root)
        return

    req_id = meta.get("id", "?")
    req_name = meta.get("name", "?")
    stage = meta.get("stage", 0)
    stage_name = STAGE_NAMES.get(stage, "?")
    is_first = meta.get("is_first_req", False)

    print(f"当前 Req：{req_id}（{req_name}）")
    print(f"Stage：{stage} - {stage_name}" + (" [first req]" if is_first else ""))
    print()

    # List tasks
    tasks = list_tasks(req_dir)
    if tasks:
        print("Task 状态：")
        for task_file, fields in tasks:
            status = fields.get("状态", "?")
            icon = STATUS_ICONS.get(status, "❓")
            name = task_file.stem

            # Get title from first line
            try:
                title = task_file.read_text(encoding="utf-8").split("\n")[0]
                title = title.replace("# ", "").strip()
            except Exception:
                title = name

            line = f"  {icon} {title} — {status}"

            # Show last event for 执行中 tasks
            if status == "执行中":
                last_event = get_last_event(repo_root, task_file.stem)
                if last_event:
                    line += f"（最后活动：{last_event}）"

            print(line)
        print()

    # Manual pending section (shown regardless of active req status)
    render_manual_section(repo_root)

    # Next action
    next_action = suggest_next_action(meta, tasks)
    print(f"下一步：{next_action}")


def main() -> None:
    parser = argparse.ArgumentParser(description="PM AI Workflow Status View")
    parser.add_argument(
        "repo_root",
        nargs="?",
        default=None,
        help="Repository root (auto-detected if omitted)",
    )
    args = parser.parse_args()

    if args.repo_root:
        repo_root = Path(args.repo_root)
    else:
        repo_root = find_repo_root()

    render_status(repo_root)


if __name__ == "__main__":
    main()
