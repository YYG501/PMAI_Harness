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

from _lib.state import (  # noqa: E402
    get_current_stage_banner,
    get_overall_state,
    get_timeline_state,
    list_tasks,
)
from _lib.stages import STAGE_NAMES  # noqa: E402  ( F13 单一真相源)
from _lib import stage6_summary  # noqa: E402  (speed mode)

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


def render_banner_only(state: dict, repo_root: Path, skill: str) -> None:
    """M2 /  : 输出当前 active req 的 stage banner 一行。

    格式按 `skills/_shared/pm-view/banner-rules.md` §1.1。
    无 active req → 输出占位 banner（PM 知道还没起 req）。
    """
    active = state["active_reqs"]
    if not active:
        # 项目级 skill（init-project / new-req 等）跑在无 active req 状态是预期的；
        # 不再硬编码"先跑 /pmai-new-req"指引（对 /pmai-init-project 反而误导）
        print("━━━ PMAI ► " + skill + " ▸ <项目级 / 无 active req> ━━━")
        return
    # 取第一个 active req（典型场景：单 PM 同时 1-2 个 req）
    req_view = active[0]
    req_dir = req_view["dir"]
    try:
        banner = get_current_stage_banner(req_dir, skill=skill)
    except Exception as exc:  # noqa: BLE001
        print(f"━━━ PMAI ► {skill} ▸ banner 渲染失败: {exc} ━━━")
        return
    print(banner)


def render_narrative(state: dict, repo_root: Path) -> None:
    """M5 /  : AI 可直接念的进度叙述。

    范围（codex C-4 降级）：当前 active req / 当前 stage / 产物文件 / 最近 transition；
    **不到小节级**（如「§四」/ commit hash 全文 不写，伪精确）。

    无 active req → 输出"目前没有 active req"，**不编造**（review R7 防幻觉）。
    """
    active = state["active_reqs"]
    if not active:
        print("目前没有 active req。可以发 /pmai-new-req 起新需求，或发 /pmai-init-project 起新项目。")
        return

    # 单 req 场景：直接念
    if len(active) == 1:
        req = active[0]
        meta = req["meta"] or {}
        req_id = req["req_dir"].name
        stage = meta.get("stage", 0)
        stage_name = STAGE_NAMES.get(int(stage), f"stage {stage}") if stage else "未知"
        tasks = req["tasks"]
        task_summary = ""
        if tasks:
            in_progress = sum(1 for t in tasks if (t["meta"] or {}).get("status") == "执行中")
            done = sum(1 for t in tasks if (t["meta"] or {}).get("status") == "已完成")
            task_summary = f"，共 {len(tasks)} 个 task（执行中 {in_progress}，已完成 {done}）"
        # 不写 commit hash / 时间细节；只点 stage 状态
        print(
            f"上次你做到 {req_id}，当前 stage {stage}/7：{stage_name}{task_summary}。"
            f"\n下一步：发 /pmai-req-stage-gate 推进，或继续当前 stage 工作。"
        )
        return

    # 多 req 场景：列各 req 概况
    print(f"目前有 {len(active)} 个 active req：")
    for req in active:
        meta = req["meta"] or {}
        req_id = req["req_dir"].name
        stage = meta.get("stage", 0)
        stage_name = STAGE_NAMES.get(int(stage), f"stage {stage}") if stage else "未知"
        print(f"  - {req_id}：stage {stage}/7（{stage_name}），{len(req['tasks'])} 个 task")
    print("\n下一步：发 /status-view 看详细，或 /pmai-req-stage-gate 推进具体 req。")


def render_health_check(repo_root: Path) -> None:
    """项目级产品文档体检：缺则输出 1 段 hint，齐全则静默。

    背景：sync 框架后老项目可能缺 GSD §8 /  新增的产品级文档
    （PRODUCT-RULES.md / ROADMAP.md）。`框架同步-SOP.md` §4.10 说"读侧
    容错"——个别脚本读不到不阻塞，但 PM 在 session 起始播报里需要被告知
    缺什么，否则永远不知道要补。

    齐全则段不输出（新项目 0 噪音）；缺失才出 hint。

    生成器仓自身（根有 `scripts/init-project.sh`，framework 资产在根而非 `.claude/`）
    不是业务仓，跳过；只在业务仓里跑。
    """
    if (repo_root / "scripts" / "init-project.sh").exists():
        return

    docs_dir = repo_root / "docs"
    if not docs_dir.exists():
        return

    missing: list = []

    if not (docs_dir / "PROJECT.md").exists():
        if (docs_dir / "CONTEXT.md").exists():
            missing.append(
                ("docs/PROJECT.md", "可能漏跑 migrate-context-to-project.py — docs/CONTEXT.md 还在")
            )
        else:
            missing.append(("docs/PROJECT.md", "项目级文档主真相源；跑 /pmai-init-project 或 /pmai-project-solution 起新建"))

    if not (docs_dir / "PRODUCT-RULES.md").exists():
        missing.append(("docs/PRODUCT-RULES.md", "GSD §8 新增的产品规则文档"))

    if not (docs_dir / "ROADMAP.md").exists():
        missing.append(("docs/ROADMAP.md", "计划态 req 队列"))

    if not missing:
        return

    print()
    print("💡 项目体检：缺以下产品级文档")
    for path, hint in missing:
        print(f"  - {path}（{hint}）")
    print("  补法：发 /pmai-project-solution（skill 会按场景引导补全）")


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
                return f"执行中 {name}：实现 / 等待呈交 / PM 验收（可在 task 窗口跑 /pmai-task-submit 重新看呈交块）"
            if status == "待执行":
                return f"确认启动 {name}：运行 /pmai-task-confirm"

        all_done = bool(tasks) and all(
            (t["meta"] or {}).get("status") == "已完成" for t in tasks
        )
        if not all_done:
            return "运行 /pmai-task-status 查看详情"

        pending = req_view["pending_spec"]
        if pending:
            next_id = pending[0]["id"]
            tail = f"（还有 {len(pending)} 个未 spec）" if len(pending) > 1 else ""
            return f"task-plan 里还有未 spec 的 task：先运行 /pmai-task-spec {next_id}{tail}"

        return "所有 task 已完成，运行 /pmai-close-req 关闭需求"

    if stage == 7:
        return "Req 正在关闭中"

    return "运行 /pmai-task-status 查看详情"


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
    print(f"  完成手工实现后： /pmai-task-execute {sample_id}")
    print(
        f"  暂时不想管：     python3 $HOME/.pmai/scripts/task-transition.py "
        f"{sample_task} --snooze-manual --days 3"
    )
    print(
        f"  放弃该 task：    python3 $HOME/.pmai/scripts/task-transition.py "
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
    req_dir = req_view["req_dir"]

    print(f"Req：{req_id}（{req_name}）")
    print(f"Stage：{stage} - {stage_name}")
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
        print("📭 没有活跃的需求。运行 /pmai-new-req 开始一个新需求。")
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
        print(f"当前 Req：{req_id}（{req_name}）")
        print(f"Stage：{stage} - {stage_name}")
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
    """Render --timeline 全局视图。"""
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
            tasks = list_tasks(item["req_dir"], repo_root=repo_root)
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
            tasks = list_tasks(item["req_dir"], repo_root=repo_root)
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
    parser = argparse.ArgumentParser(
        description="PM AI Workflow Status View",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
示例:
  status-view.py                          当前所有 req / task 概览
  status-view.py --summary                一行任务概览
  status-view.py --timeline               全局时间线（active + closed + cancelled）
  status-view.py --timeline --module auth 只看 auth 模块相关 req
  status-view.py --timeline --all         时间线显示全部 archived
""",
    )
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
        help="全局时间线视图：active + closed + cancelled 全量按时间倒序"
    )
    parser.add_argument("--since", default=None, help="(timeline) 仅显示关闭时间 >= YYYY-MM-DD 的 archived")
    parser.add_argument("--module", default=None, help="(timeline) 仅显示涉及该 module 的 req")
    parser.add_argument("--milestone", action="store_true", help="(timeline) 仅显示 PROJECT 路线节标 ⭐ 的 req")
    parser.add_argument("--limit", type=int, default=20, help="(timeline) archived 总数限制 (默认 20)")
    parser.add_argument("--all", action="store_true", help="(timeline) 取消 limit，显示全部 archived")
    parser.add_argument(
        "--banner-only", action="store_true",
        help="(M2/ ) 仅输出当前 active req 的 stage banner 一行（按 banner-rules.md §1.1 格式）"
    )
    parser.add_argument(
        "--skill", default="REQ-STAGE-GATE",
        help="(--banner-only) 调用方 skill 名（如 REQ-STAGE-GATE / INIT-PROJECT），用于 banner 格式"
    )
    parser.add_argument(
        "--narrative", action="store_true",
        help="(M5/ ) 输出 AI 可直接念的进度叙述（当前 stage / 产物文件 / 最近 transition；不到小节级，codex C-4 范围降级）"
    )
    parser.add_argument(
        "--stage6-entry", default=None, metavar="REQ_DIR",
        help="(speed mode) 渲染 stage 6 入口总览（自决项 + PM 拍过的结构决策 + task 拆分 + 产物路径 + PM 三选项）"
    )
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

    if args.banner_only:
        render_banner_only(state, repo_root, args.skill)
        return

    if args.narrative:
        render_narrative(state, repo_root)
        render_health_check(repo_root)
        return

    if args.stage6_entry:
        req_dir = Path(args.stage6_entry).resolve()
        if not req_dir.is_dir():
            print(f"--stage6-entry 路径不存在或不是目录：{req_dir}", file=sys.stderr)
            sys.exit(2)
        # 从 req_dir 反推该 worktree / repo 的 root（消费仓 worktree 而非调用者 cwd）
        try:
            req_repo_root = Path(subprocess.check_output(
                ["git", "-C", str(req_dir), "rev-parse", "--show-toplevel"],
                text=True, stderr=subprocess.DEVNULL,
            ).strip())
        except Exception:
            req_repo_root = repo_root
        summary = stage6_summary.build_summary(req_dir, req_repo_root)
        if summary is None:
            print(
                f"req {req_dir.name} 不满足 stage 6 入口条件："
                f"implementation-design.md 或 task-plan.md 不存在",
                file=sys.stderr,
            )
            sys.exit(3)
        print(stage6_summary.render(summary))
        return

    if args.summary:
        render_summary(state, repo_root)
        render_health_check(repo_root)
        return

    render_status(state, repo_root)
    render_health_check(repo_root)


if __name__ == "__main__":
    main()
