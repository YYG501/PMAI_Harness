#!/usr/bin/env python3
"""Global status overview for PM AI Workflow — 纯 render 层。

扫描 / parse / 聚合逻辑全部走 `_lib.state.get_overall_state()`（v3 §1 #2
要求；否则 status-view 与 skill-preamble 双轨复现"AI 各自 grep raw / PM
看视觉视图"的真相源漂移）。

本文件只做：
- 选用 active req 渲染策略（0 个 / 1 个 / 多个）
- 单 req 的字段格式（stage 名 / icon / 下一步建议）
- pending manual + quick-fix 段
"""

from __future__ import annotations

import argparse
import glob
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

# 让 _lib 可以 import（status-view.py 自身在 scripts/，_lib 是同级子目录）
_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.state import get_overall_state, get_timeline_state, list_tasks  # noqa: E402

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
    "待执行": "⏳",
    "执行中": "🔄",
    "已完成": "✅",
}


def find_repo_root() -> Path:
    """Find the real repo root (not a worktree)."""
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


def _format_last_event(ev: dict | None) -> str | None:
    """事件 dict → 单行人话描述。无事件返回 None。"""
    if not ev:
        return None
    etype = ev.get("event", "")
    if etype == "review_completed":
        return f"自审 - {ev.get('tool', '')} {ev.get('result', '')}"
    if etype == "status_changed":
        return f"状态变更 → {ev.get('to', '')}"
    return etype


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


def render_summary(state: dict, repo_root: Path) -> None:
    """One-line task overview for preamble output."""
    counts = {"执行中": 0, "待启动": 0, "待 spec": 0}
    seen_stems: set[str] = set()

    for req in state["active_reqs"]:
        for t in req["tasks"]:
            stem = t["path"].stem
            if stem in seen_stems:
                continue
            seen_stems.add(stem)
            status = (t["meta"] or {}).get("status", "")
            if status == "执行中":
                counts["执行中"] += 1
            elif status == "待执行" and _task_worktree_exists(repo_root, stem):
                counts["待启动"] += 1
        counts["待 spec"] += len(req["pending_spec"])

    if not any(counts.values()):
        print("📋 暂无 active task")
        return

    print(
        "📋 task 概览: "
        f"执行中 {counts['执行中']} / "
        f"待启动 {counts['待启动']} / "
        f"待 spec {counts['待 spec']}"
    )


def suggest_next_action(req_view: dict) -> str:
    """Suggest what PM should do next。req_view 是 state['active_reqs'][i]。"""
    meta = req_view["meta"]
    stage = meta.get("stage", 0)
    tasks = req_view["tasks"]

    if stage <= 5:
        return f"继续 stage {stage}（{STAGE_NAMES.get(stage, '?')}）的工作"

    if stage == 6:
        for t in tasks:
            status = (t["meta"] or {}).get("status", "")
            name = t["path"].stem
            if status == "执行中":
                return f"执行中 {name}：实现 / 等待呈交 / PM 验收（可在 task 窗口跑 /task-submit 重新看呈交块）"
            if status == "待执行":
                return f"确认启动 {name}：运行 /task-confirm"

        all_done = bool(tasks) and all(
            (t["meta"] or {}).get("status") == "已完成" for t in tasks
        )
        if not all_done:
            return "运行 /task-status 查看详情"

        pending = req_view["pending_spec"]
        if pending:
            next_id = pending[0]["id"]
            tail = f"（还有 {len(pending)} 个未 spec）" if len(pending) > 1 else ""
            return f"task-plan 里还有未 spec 的 task：先运行 /task-spec {next_id}{tail}"

        return "所有 task 已完成，运行 /close-req 关闭需求"

    if stage == 7:
        return "Req 正在关闭中"

    return "运行 /task-status 查看详情"


def render_manual_section(repo_root: Path) -> None:
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
                    continue
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


def _render_task_lines(req_view: dict) -> None:
    """渲染 req_view 下 spec 过的 task + pending_spec。"""
    for t in req_view["tasks"]:
        meta = t["meta"] or {}
        status = meta.get("status", "?")
        icon = STATUS_ICONS.get(status, "❓")

        try:
            title = t["path"].read_text(encoding="utf-8").split("\n")[0]
            title = title.replace("# ", "").strip()
        except Exception:
            title = t["path"].stem

        line = f"  {icon} {title} — {status}"
        if status == "执行中":
            last_event = _format_last_event(t.get("last_event"))
            if last_event:
                line += f"（最后活动：{last_event}）"
        print(line)

    for p in req_view["pending_spec"]:
        display = p.get("title") or p["id"]
        print(f"  📝 {p['id']}: {display} — 待 spec")


def _render_single_req(req_view: dict) -> None:
    meta = req_view["meta"]
    req_id = meta.get("id", "?")
    req_name = meta.get("name", "?")
    stage = meta.get("stage", 0)
    stage_name = STAGE_NAMES.get(stage, "?")
    is_first = meta.get("is_first_req", False)
    req_dir = req_view["req_dir"]

    print(f"Req：{req_id}（{req_name}）")
    print(f"Stage：{stage} - {stage_name}" + (" [first req]" if is_first else ""))
    print(f"Worktree：{req_dir.parent.parent.parent}")
    print()

    if req_view["tasks"] or req_view["pending_spec"]:
        print("Task 状态：")
        _render_task_lines(req_view)
        print()

    print(f"下一步：{suggest_next_action(req_view)}")


def render_status(state: dict, repo_root: Path) -> None:
    active = state["active_reqs"]

    if not active:
        print("📭 没有活跃的需求。运行 /new-req 开始一个新需求。")
        render_manual_section(repo_root)
        render_quickfix_section(repo_root)
        return

    if len(active) == 1:
        req_view = active[0]
        meta = req_view["meta"]
        req_id = meta.get("id", "?")
        req_name = meta.get("name", "?")
        stage = meta.get("stage", 0)
        stage_name = STAGE_NAMES.get(stage, "?")
        is_first = meta.get("is_first_req", False)

        print(f"当前 Req：{req_id}（{req_name}）")
        print(f"Stage：{stage} - {stage_name}" + (" [first req]" if is_first else ""))
        print()

        if req_view["tasks"] or req_view["pending_spec"]:
            print("Task 状态：")
            _render_task_lines(req_view)
            print()

        render_manual_section(repo_root)
        render_quickfix_section(repo_root)

        print(f"下一步：{suggest_next_action(req_view)}")
        return

    print(f"📚 {len(active)} 个 active req 并行：")
    print()
    for idx, req_view in enumerate(active):
        if idx > 0:
            print("─" * 60)
        _render_single_req(req_view)
        print()

    render_manual_section(repo_root)
    render_quickfix_section(repo_root)
    print("提示：操作具体 req 请先 cd 进对应 worktree 再跑 skill；主仓视角不默选某个 req。")


def render_timeline(timeline_state: dict, repo_root: Path) -> None:
    """Render --timeline 全局视图（vp-7）。"""
    active = timeline_state["active"]
    closed = timeline_state["closed"]
    cancelled = timeline_state["cancelled"]
    total_archived = timeline_state["total_archived"]
    truncated = timeline_state["truncated"]
    milestone_only = timeline_state["milestone_only"]

    print()
    title = "📅 项目时间线"
    if milestone_only:
        title += "（仅里程碑 ⭐）"
    print(title)
    print()

    # Active
    print("═══ Active ═══")
    if not active:
        print("  （无进行中需求）")
    else:
        for item in active:
            meta = item["meta"]
            req_id = meta.get("id", item["req_dir"].name)
            req_name = meta.get("name", "")
            stage = meta.get("stage", 0)
            stage_name = STAGE_NAMES.get(stage, "?")
            ms = " ⭐" if item.get("is_milestone") else ""
            tasks = list_tasks(item["req_dir"])
            print(f"🔄{ms} {req_id} · {req_name}（Stage {stage} {stage_name}）")
            if tasks:
                done = sum(1 for t in tasks if t.get("meta", {}).get("status") == "已完成")
                print(f"   ↳ {done}/{len(tasks)} tasks")
            else:
                print("   ↳ 0/0 tasks")

    print()

    # Closed
    shown_total = len(closed) + len(cancelled)
    if shown_total == 0 and total_archived > 0:
        print(f"═══ Closed/Cancelled（过滤后无匹配，共 {total_archived} 条 archived）═══")
    else:
        label = f"═══ Closed（显示 {len(closed)} / 总 {total_archived - len(cancelled)}）═══"
        print(label)
    if not closed:
        if total_archived == 0:
            print("  （无已关闭需求）")
    else:
        for item in closed:
            meta = item["meta"]
            req_id = meta.get("id", item["req_dir"].name)
            req_name = meta.get("name", "")
            ms = " ⭐" if item.get("is_milestone") else ""
            cd = item.get("close_date")
            date_str = cd.strftime("%Y-%m-%d") if cd else "?"
            tasks = list_tasks(item["req_dir"])
            task_count_str = f"{len(tasks)} tasks" if tasks else "0 tasks"
            print(f"✅{ms} {req_id} · {req_name}（关闭 {date_str} · {task_count_str}）")

    print()

    # Cancelled
    if cancelled or any(i for i in [] if False):  # placeholder
        print(f"═══ Cancelled（显示 {len(cancelled)}）═══")
        for item in cancelled:
            meta = item["meta"]
            req_id = meta.get("id", item["req_dir"].name)
            req_name = meta.get("name", "")
            cd = item.get("close_date")
            date_str = cd.strftime("%Y-%m-%d") if cd else "?"
            print(f"❌ {req_id} · {req_name}（取消 {date_str}）")
        print()

    if truncated > 0:
        print(f"...还有 {truncated} 条 archived 未显示，用 --since YYYY-MM-DD 或 --all 看全部")
        print()

    print("──")
    print("过滤参数：--since YYYY-MM-DD | --module <name> | --milestone | --all（取消 limit）")
    if timeline_state["warnings"]:
        print(f"⚠️  {len(timeline_state['warnings'])} warnings（meta 解析问题）")


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
    parser.add_argument(
        "--timeline", action="store_true",
        help="全局时间线视图：active + closed + cancelled 全量按时间倒序（vp-7）"
    )
    parser.add_argument("--since", default=None, help="(timeline) 仅显示关闭时间 >= YYYY-MM-DD 的 archived")
    parser.add_argument("--module", default=None, help="(timeline) 仅显示涉及该 module 的 req")
    parser.add_argument("--milestone", action="store_true", help="(timeline) 仅显示 CONTEXT 路线节标 ⭐ 的 req")
    parser.add_argument("--limit", type=int, default=20, help="(timeline) archived 总数限制 (默认 20)")
    parser.add_argument("--all", action="store_true", help="(timeline) 取消 limit，显示全部 archived")
    args = parser.parse_args()

    if args.repo_root:
        repo_root = Path(args.repo_root)
    else:
        repo_root = find_repo_root()

    if args.timeline:
        limit = None if args.all else args.limit
        timeline_state = get_timeline_state(
            repo_root, cwd=Path.cwd(), strict=False,
            since=args.since, module=args.module,
            milestone_only=args.milestone, limit=limit,
        )
        render_timeline(timeline_state, repo_root)
        return

    state = get_overall_state(repo_root, cwd=Path.cwd(), strict=False)

    if args.summary:
        render_summary(state, repo_root)
        return

    render_status(state, repo_root)


if __name__ == "__main__":
    main()
