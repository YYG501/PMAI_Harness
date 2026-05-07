#!/usr/bin/env python3
"""Global status overview for PM AI Workflow."""

from __future__ import annotations

import argparse
import glob
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# 兼容两种 task 元信息格式（同 task-transition.py）：
#   旧版（段落）：**字段：** 值
#   新版（任务卡表格）：| **字段** | 值 |
FIELD_RE = re.compile(r"^\*\*(.+?)：\*\*\s*(.*)$")
FIELD_RE_NEW = re.compile(r"^\|\s*\*\*(.+?)\*\*\s*\|\s*(.*?)\s*\|.*$")


def _parse_field_line(line: str) -> tuple[str, str] | None:
    stripped = line.strip()
    m = FIELD_RE.match(stripped)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    m = FIELD_RE_NEW.match(stripped)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    return None
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
    """Read field-value pairs from task file header. Tolerates both
    old paragraph format (**字段：** 值) and new task-card table format
    (| **字段** | 值 |). Reads first 40 lines."""
    fields: dict[str, str] = {}
    with task_file.open(encoding="utf-8") as fh:
        for idx, line in enumerate(fh):
            if idx >= 40:
                break
            parsed = _parse_field_line(line)
            if parsed:
                name, value = parsed
                fields[name] = value
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


def _collect_active_from(active_dir: Path) -> list[tuple[Path, dict]]:
    """Return all status=active reqs in a single requirements/active/ dir."""
    if not active_dir.exists():
        return []
    found: list[tuple[Path, dict]] = []
    for req_dir in sorted(active_dir.iterdir()):
        meta_file = req_dir / ".req-meta.json"
        if not meta_file.exists():
            continue
        try:
            meta = json.loads(meta_file.read_text(encoding="utf-8"))
        except Exception:
            continue
        if meta.get("status") == "active":
            found.append((req_dir, meta))
    return found


def find_all_active_reqs(repo_root: Path) -> list[tuple[Path, dict]]:
    """Return every active req visible from the current cwd.

    - In a req/task worktree, the current worktree is authoritative (cwd 唯一定 req)
      and the result has at most one entry.
    - On main, scan the main repo + every .worktrees/req-* worktree; multiple
      active reqs may co-exist.
    Results are deduplicated by req id (basename).
    """
    current_wt = find_current_worktree_root()
    current_branch = find_current_branch()

    if current_branch.startswith("req-"):
        local = _collect_active_from(current_wt / "requirements" / "active")
        if local:
            return local

    if current_branch.startswith("task-"):
        worktrees_dir = repo_root / ".worktrees"
        if worktrees_dir.exists():
            for wt in sorted(worktrees_dir.iterdir()):
                if wt.name.startswith("req-"):
                    local = _collect_active_from(wt / "requirements" / "active")
                    if local:
                        return local

    seen: set[str] = set()
    results: list[tuple[Path, dict]] = []
    for req_dir, meta in _collect_active_from(repo_root / "requirements" / "active"):
        if req_dir.name in seen:
            continue
        seen.add(req_dir.name)
        results.append((req_dir, meta))

    worktrees_dir = repo_root / ".worktrees"
    if worktrees_dir.exists():
        for wt in sorted(worktrees_dir.iterdir()):
            if not (wt.name.startswith("req-") and wt.is_dir()):
                continue
            for req_dir, meta in _collect_active_from(wt / "requirements" / "active"):
                if req_dir.name in seen:
                    continue
                seen.add(req_dir.name)
                results.append((req_dir, meta))

    return results


def find_active_req(repo_root: Path) -> tuple[Path | None, dict | None]:
    """Backward-compat single-active accessor.

    Returns the first active req from find_all_active_reqs (None when zero).
    Callers that need to handle multi-active should call find_all_active_reqs
    directly.
    """
    found = find_all_active_reqs(repo_root)
    if not found:
        return None, None
    return found[0]


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


_PLAN_ROW_RE = re.compile(r"^\|[^|]*?(task-\d{3,})[^|]*\|\s*([^|]*?)\s*\|")


def read_task_plan_ids(req_dir: Path) -> list[tuple[str, str]]:
    """Parse task-plan.md and return [(task_id, title), ...] from the planning table.

    Limits parsing to the region BEFORE the first '## ' heading to avoid
    matching task ids mentioned in '## 变更记录' / '## 执行顺序与并行性' /
    other narrative sections. Returns [] if file missing.
    """
    plan_file = req_dir / "task-plan.md"
    if not plan_file.exists():
        return []

    content = plan_file.read_text(encoding="utf-8")
    head = content.split("\n## ", 1)[0]

    results: list[tuple[str, str]] = []
    seen: set[str] = set()
    for line in head.splitlines():
        match = _PLAN_ROW_RE.match(line)
        if not match:
            continue
        task_id = match.group(1).strip()
        title = match.group(2).strip()
        if task_id in seen:
            continue
        seen.add(task_id)
        results.append((task_id, title))
    return results


def discarded_task_ids(req_dir: Path) -> set[str]:
    """Return the set of task ids that have been discarded (moved to tasks/discarded/)."""
    discarded_dir = req_dir / "tasks" / "discarded"
    if not discarded_dir.exists():
        return set()
    ids: set[str] = set()
    for f in discarded_dir.glob("task-*.md"):
        match = re.match(r"(task-\d{3,})", f.stem)
        if match:
            ids.add(match.group(1))
    return ids


def specced_task_ids(tasks: list[tuple[Path, dict[str, str]]]) -> set[str]:
    """Return the set of task ids that have been spec'd (have a tasks/<id>*.md file)."""
    ids: set[str] = set()
    for task_file, _ in tasks:
        match = re.match(r"(task-\d{3,})", task_file.stem)
        if match:
            ids.add(match.group(1))
    return ids


def pending_spec_task_ids(
    req_dir: Path, tasks: list[tuple[Path, dict[str, str]]]
) -> list[tuple[str, str]]:
    """Return task ids planned in task-plan.md but not yet spec'd (and not discarded).

    Returned in plan order so the next-action hint can pick the first one.
    """
    planned = read_task_plan_ids(req_dir)
    if not planned:
        return []
    discarded = discarded_task_ids(req_dir)
    specced = specced_task_ids(tasks)
    return [
        (tid, title)
        for tid, title in planned
        if tid not in specced and tid not in discarded
    ]


def _task_worktree_exists(repo_root: Path, task_stem: str) -> bool:
    worktrees_dir = repo_root / ".worktrees"
    if not worktrees_dir.exists():
        return False
    exact = worktrees_dir / task_stem
    if exact.is_dir():
        return True
    return any(
        wt.is_dir() and wt.name.startswith(f"{task_stem}-")
        for wt in worktrees_dir.iterdir()
    )


def _iter_active_req_dirs(repo_root: Path) -> list[Path]:
    """Return all active req directories (deduped by basename) across main and worktrees."""
    active_roots = [repo_root / "requirements" / "active"]
    worktrees_dir = repo_root / ".worktrees"
    if worktrees_dir.exists():
        active_roots.extend(
            wt / "requirements" / "active"
            for wt in sorted(worktrees_dir.glob("req-*"))
            if wt.is_dir()
        )

    seen: set[str] = set()
    req_dirs: list[Path] = []
    for active_root in active_roots:
        if not active_root.exists():
            continue
        for req_dir in sorted(active_root.iterdir()):
            if not req_dir.is_dir() or req_dir.name in seen:
                continue
            seen.add(req_dir.name)
            req_dirs.append(req_dir)
    return req_dirs


def _iter_summary_tasks(repo_root: Path) -> list[Path]:
    task_files: list[Path] = []
    for req_dir in _iter_active_req_dirs(repo_root):
        tasks_dir = req_dir / "tasks"
        if tasks_dir.exists():
            task_files.extend(sorted(tasks_dir.glob("task-*.md")))
    return task_files


def render_summary(repo_root: Path) -> None:
    """Render a one-line task overview for preamble output."""
    counts = {"执行中": 0, "待验收": 0, "待启动": 0, "待 spec": 0}
    seen_stems: set[str] = set()

    for task_file in _iter_summary_tasks(repo_root):
        task_stem = task_file.stem
        if task_stem in seen_stems:
            continue
        seen_stems.add(task_stem)

        fields = read_task_fields(task_file)
        status = fields.get("状态", "")
        if status == "执行中":
            counts["执行中"] += 1
        elif status == "待验收":
            counts["待验收"] += 1
        elif status == "待确认" and _task_worktree_exists(repo_root, task_stem):
            counts["待启动"] += 1

    # 待 spec：plan 里规划但 tasks/ 下没文件 (扫所有 active req 的 task-plan.md)
    for req_dir in _iter_active_req_dirs(repo_root):
        tasks = list_tasks(req_dir)
        counts["待 spec"] += len(pending_spec_task_ids(req_dir, tasks))

    if not any(counts.values()):
        print("📋 暂无 active task")
        return

    print(
        "📋 task 概览: "
        f"执行中 {counts['执行中']} / "
        f"待验收 {counts['待验收']} / "
        f"待启动 {counts['待启动']} / "
        f"待 spec {counts['待 spec']}"
    )
    if counts["待验收"] > 0:
        print(
            f"⚠️ {counts['待验收']} 个 task 待验收，"
            "请去对应新窗口验收（或 /task-status 看详情）"
        )


def suggest_next_action(
    meta: dict, tasks: list[tuple[Path, dict[str, str]]], req_dir: Path | None = None
) -> str:
    """Suggest what PM should do next."""
    stage = meta.get("stage", 0)

    if stage <= 5:
        return f"继续 stage {stage}（{STAGE_NAMES.get(stage, '?')}）的工作"

    if stage == 6:
        # Check task statuses on already-spec'd tasks
        for task_file, fields in tasks:
            status = fields.get("状态", "")
            name = task_file.stem
            if status == "待验收":
                return f"验收 {name}：运行 /task-submit"
            if status == "执行中":
                return f"等待 {name} 完成实现和自审"
            if status == "待确认":
                return f"确认启动 {name}：运行 /task-confirm"

        # All spec'd tasks are 已完成 — but plan may still have un-spec'd entries.
        # Cross-reference task-plan.md to avoid the "已完成 1 / 待启动 0 → all done"
        # trap when only task-001 has been spec'd from a 4-task plan.
        all_done = all(f.get("状态") == "已完成" for _, f in tasks)
        if not (all_done and tasks):
            return "运行 /task-status 查看详情"

        pending = pending_spec_task_ids(req_dir, tasks) if req_dir else []
        if pending:
            next_id, next_title = pending[0]
            tail = f"（还有 {len(pending)} 个未 spec）" if len(pending) > 1 else ""
            return f"task-plan 里还有未 spec 的 task：先运行 /task-spec {next_id}{tail}"

        return "所有 task 已完成，运行 /close-req 关闭需求"

    if stage == 7:
        return "Req 正在关闭中"

    return "运行 /task-status 查看详情"


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


def render_quickfix_section(repo_root: Path) -> None:
    """Render recent quick-fix commits if any exist."""
    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                str(repo_root),
                "log",
                "--grep",
                r"^\[quick-fix\]",
                "--format=%h %ci %s",
                "-3",
            ],
            check=False,
            text=True,
            capture_output=True,
        )
    except Exception:
        return

    lines = [line for line in result.stdout.splitlines() if line.strip()]
    if not lines:
        return

    print("最近 quick-fix：")
    for line in lines:
        print(f"  {line}")
    print()


def _render_single_req(req_dir: Path, meta: dict, repo_root: Path) -> None:
    """Render a single req's stage + task list + next-action."""
    req_id = meta.get("id", "?")
    req_name = meta.get("name", "?")
    stage = meta.get("stage", 0)
    stage_name = STAGE_NAMES.get(stage, "?")
    is_first = meta.get("is_first_req", False)

    print(f"Req：{req_id}（{req_name}）")
    print(f"Stage：{stage} - {stage_name}" + (" [first req]" if is_first else ""))
    print(f"Worktree：{req_dir.parent.parent.parent}")
    print()

    tasks = list_tasks(req_dir)
    pending_spec = pending_spec_task_ids(req_dir, tasks) if stage == 6 else []
    if tasks or pending_spec:
        print("Task 状态：")
        for task_file, fields in tasks:
            status = fields.get("状态", "?")
            icon = STATUS_ICONS.get(status, "❓")
            name = task_file.stem

            try:
                title = task_file.read_text(encoding="utf-8").split("\n")[0]
                title = title.replace("# ", "").strip()
            except Exception:
                title = name

            line = f"  {icon} {title} — {status}"

            if status == "执行中":
                last_event = get_last_event(repo_root, task_file.stem)
                if last_event:
                    line += f"（最后活动：{last_event}）"

            print(line)

        for task_id, title in pending_spec:
            display = title or task_id
            print(f"  📝 {task_id}: {display} — 待 spec")
        print()

    next_action = suggest_next_action(meta, tasks, req_dir)
    print(f"下一步：{next_action}")


def render_status(repo_root: Path) -> None:
    """Render the full status view."""
    active = find_all_active_reqs(repo_root)

    if not active:
        print("📭 没有活跃的需求。运行 /new-req 开始一个新需求。")
        render_manual_section(repo_root)
        render_quickfix_section(repo_root)
        return

    if len(active) == 1:
        req_dir, meta = active[0]
        # 单 active 保持旧文案"当前 Req"
        req_id = meta.get("id", "?")
        req_name = meta.get("name", "?")
        stage = meta.get("stage", 0)
        stage_name = STAGE_NAMES.get(stage, "?")
        is_first = meta.get("is_first_req", False)

        print(f"当前 Req：{req_id}（{req_name}）")
        print(f"Stage：{stage} - {stage_name}" + (" [first req]" if is_first else ""))
        print()

        tasks = list_tasks(req_dir)
        pending_spec = pending_spec_task_ids(req_dir, tasks) if stage == 6 else []
        if tasks or pending_spec:
            print("Task 状态：")
            for task_file, fields in tasks:
                status = fields.get("状态", "?")
                icon = STATUS_ICONS.get(status, "❓")
                name = task_file.stem

                try:
                    title = task_file.read_text(encoding="utf-8").split("\n")[0]
                    title = title.replace("# ", "").strip()
                except Exception:
                    title = name

                line = f"  {icon} {title} — {status}"

                if status == "执行中":
                    last_event = get_last_event(repo_root, task_file.stem)
                    if last_event:
                        line += f"（最后活动：{last_event}）"

                print(line)

            for task_id, title in pending_spec:
                display = title or task_id
                print(f"  📝 {task_id}: {display} — 待 spec")
            print()

        render_manual_section(repo_root)
        render_quickfix_section(repo_root)

        next_action = suggest_next_action(meta, tasks, req_dir)
        print(f"下一步：{next_action}")
        return

    # 多 active：列出每个 req 的细节，独立渲染 next-action
    print(f"📚 {len(active)} 个 active req 并行：")
    print()
    for idx, (req_dir, meta) in enumerate(active):
        if idx > 0:
            print("─" * 60)
        _render_single_req(req_dir, meta, repo_root)
        print()

    render_manual_section(repo_root)
    render_quickfix_section(repo_root)
    print("提示：操作具体 req 请先 cd 进对应 worktree 再跑 skill；主仓视角不默选某个 req。")


def main() -> None:
    parser = argparse.ArgumentParser(description="PM AI Workflow Status View")
    parser.add_argument(
        "repo_root",
        nargs="?",
        default=None,
        help="Repository root (auto-detected if omitted)",
    )
    parser.add_argument(
        "--summary", action="store_true", help="Print one-line task overview"
    )
    args = parser.parse_args()

    if args.repo_root:
        repo_root = Path(args.repo_root)
    else:
        repo_root = find_repo_root()

    if args.summary:
        render_summary(repo_root)
        return

    render_status(repo_root)


if __name__ == "__main__":
    main()
