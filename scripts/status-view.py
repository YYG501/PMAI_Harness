#!/usr/bin/env python3
"""Global status overview for PM AI Workflow — 纯 render 层。

扫描 / parse / 聚合逻辑全部走 `_lib.state.get_overall_state()`（v3 §1 #2
要求；否则 status-view 与 skill-preamble 双轨复现"AI 各自 grep raw / PM
看视觉视图"的真相源漂移）。

本文件只做：
- 选用 active work 渲染策略（0 个 / 1 个 / 多个）
- 单个工作项的字段格式（stage 名 / icon / 下一步建议）
- quick-fix 段
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

# 让 _lib 可以 import（status-view.py 自身在 scripts/，_lib 是同级子目录）
_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.state import (  # noqa: E402
    get_current_stage_banner,
    get_overall_state,
    get_timeline_state,
)
from _lib.stages import STAGE_NAMES, MAX_STAGE  # noqa: E402  ( F13 单一真相源)


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


def render_summary(state: dict, repo_root: Path) -> None:
    """One-line active work overview for preamble output."""
    active = state["active_work"]
    if not active:
        print("📭 暂无 active work")
        return
    parts = []
    for req in active:
        meta = req["meta"]
        req_id = meta.get("id", "?")
        stage = meta.get("stage", 0)
        parts.append(f"{req_id}:{STAGE_NAMES.get(stage, '?')}")
    print("📋 active work: " + " / ".join(parts))


def render_banner_only(state: dict, repo_root: Path, skill: str) -> None:
    """M2 /  : 输出当前 active work 的 stage banner 一行。

    格式按 `skills/_shared/pm-view/banner-rules.md` §1.1。
    无 active work → 输出占位 banner（PM 知道当前没有进行中的工作）。
    """
    active = state["active_work"]
    if not active:
        # 项目级 skill（init-project / design 等）跑在无 active work 状态是预期的。
        print("━━━ PMAI ► " + skill + " ▸ <项目级 / 无 active work> ━━━")
        return
    # 取第一个 active work（典型场景：单 PM 同时 1-2 个工作）
    req_view = active[0]
    work_dir = req_view["work_dir"]
    try:
        banner = get_current_stage_banner(work_dir, skill=skill)
    except Exception as exc:  # noqa: BLE001
        print(f"━━━ PMAI ► {skill} ▸ banner 渲染失败: {exc} ━━━")
        return
    print(banner)


def _product_oneliner(repo_root: Path) -> str:
    """PRODUCT-STATE.md 的产品现状一句话（产品轴 lead 用）；读不到返回空串。

    六步重构：播报主轴从内部 stage 编号转成「你的产品现在长什么样 + 在做什么」。
    产品定位一句话从 PRODUCT-STATE.md 取（根目录或 docs/）；无则 lead 留空、退回当前工作轴。
    """
    for cand in (repo_root / "PRODUCT-STATE.md", repo_root / "docs" / "PRODUCT-STATE.md"):
        if not cand.exists():
            continue
        try:
            for line in cand.read_text(encoding="utf-8").splitlines():
                s = line.strip()
                if not s or s[0] in "#<>|" or s.startswith("---"):
                    continue
                return s[:80]
        except OSError:
            pass
    return ""


def render_narrative(state: dict, repo_root: Path) -> None:
    """M5 /  : AI 可直接念的进度叙述（产品轴）。

    范围（codex C-4 降级）：当前 active work / 当前 stage / 产物文件 / 最近 transition；
    **不到小节级**（如「§四」/ commit hash 全文 不写，伪精确）。

    无 active work → 输出"目前没有 active work"，**不编造**（review R7 防幻觉）。
    """
    active = state["active_work"]
    if not active:
        print("目前没有 active work。可以发 /pmai-design 设计新功能，或发 /pmai-init-project 起新项目。")
        return

    # 单个工作场景：直接念
    if len(active) == 1:
        req = active[0]
        meta = req["meta"] or {}
        req_id = req["work_dir"].name
        stage = meta.get("stage", 0)
        stage_name = STAGE_NAMES.get(int(stage), f"stage {stage}") if stage else "未知"
        # 不写 commit hash / 时间细节；只点 stage 状态
        prod = _product_oneliner(repo_root)
        prod_line = f"你的产品：{prod}\n" if prod else ""
        print(
            f"{prod_line}当前在做 {req_id}（{stage_name} 阶段）。"
            f"\n下一步：{suggest_next_action(req)}"
        )
        return

    # 多个工作场景：产品轴 lead + 列各工作概况
    prod = _product_oneliner(repo_root)
    if prod:
        print(f"你的产品：{prod}")
    print(f"目前有 {len(active)} 个 active work：")
    for req in active:
        meta = req["meta"] or {}
        req_id = req["work_dir"].name
        stage = meta.get("stage", 0)
        stage_name = STAGE_NAMES.get(int(stage), f"stage {stage}") if stage else "未知"
        print(f"  - {req_id}：{stage_name} 阶段")
    print("\n下一步：发 /pmai-status 看详细；推进时按具体工作选择 /pmai-design、/pmai-build 或 /pmai-close。")


def render_health_check(repo_root: Path) -> None:
    """项目级产品文档体检：缺则输出 1 段 hint，齐全则静默。

    背景：sync 框架后老项目可能缺 GSD §8 /  新增的产品级文档
    （PRODUCT-RULES.md / TODO.md）。「读侧容错」纪律（个别脚本读不到
    不阻塞）——但 PM 在 session 起始播报里需要被告知
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

    if not (docs_dir / "PRODUCT.md").exists():
        if (docs_dir / "CONTEXT.md").exists():
            missing.append(
                ("docs/PRODUCT.md", "可能漏跑 migrate-context-to-project.py — docs/CONTEXT.md 还在")
            )
        else:
            missing.append(("docs/PRODUCT.md", "项目级文档主真相源；跑 /pmai-init-project 或 /pmai-strategy 起新建"))

    if not (docs_dir / "PRODUCT-RULES.md").exists():
        missing.append(("docs/PRODUCT-RULES.md", "GSD §8 新增的产品规则文档"))

    if not (docs_dir / "TODO.md").exists():
        missing.append(("docs/TODO.md", "PM 待办池"))

    if not missing:
        return

    print()
    print("💡 项目体检：缺以下产品级文档")
    for path, hint in missing:
        print(f"  - {path}（{hint}）")
    print("  补法：发 /pmai-strategy（skill 会按场景引导补全）")


def suggest_next_action(req_view: dict) -> str:
    """Suggest what PM should do next. req_view 是 state['active_work'][i].
    四步：1 设计 / 2 build / 3 复审 / 4 沉淀（MAX_STAGE=4）。"""
    meta = req_view["meta"]
    stage = meta.get("stage", 0)

    # 设计（≤1）：定 / 细化模块规格
    if stage <= 1:
        return f"继续{STAGE_NAMES.get(stage, '设计')}：发 /pmai-design 细化模块规格"

    # build（2）：对模块 spec 直建 + 三道审 + PM 验收
    if stage == 2:
        return "build 阶段：发 /pmai-build <模块> 对着 spec 建"

    # 复审（3）
    if stage == 3:
        return "复审阶段：继续 /pmai-build 的复审与验收；通过后发 /pmai-close"

    # 沉淀（≥4 = MAX_STAGE）
    if stage >= 4:
        return "沉淀阶段：运行 /pmai-close 沉淀产品现状 + 收尾当前工作"

    return "运行 /pmai-status 查看详情"


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


def _render_single_req(req_view: dict) -> None:
    meta = req_view["meta"]
    req_id = meta.get("id", "?")
    req_name = meta.get("name", "?")
    stage = meta.get("stage", 0)
    stage_name = STAGE_NAMES.get(stage, "?")
    work_dir = req_view["work_dir"]

    print(f"当前工作：{req_id}（{req_name}）")
    print(f"Stage：{stage} - {stage_name}")
    print(f"Worktree：{work_dir.parent.parent.parent}")
    print()

    print(f"下一步：{suggest_next_action(req_view)}")


def render_status(state: dict, repo_root: Path) -> None:
    active = state["active_work"]

    if not active:
        print("📭 没有活跃工作。运行 /pmai-design 设计新功能。")
        render_quickfix_section(repo_root)
        return

    if len(active) == 1:
        req_view = active[0]
        meta = req_view["meta"]
        req_id = meta.get("id", "?")
        req_name = meta.get("name", "?")
        stage = meta.get("stage", 0)
        stage_name = STAGE_NAMES.get(stage, "?")
        print(f"当前工作：{req_id}（{req_name}）")
        print(f"Stage：{stage} - {stage_name}")
        print()

        render_quickfix_section(repo_root)

        print(f"下一步：{suggest_next_action(req_view)}")
        return

    print(f"📚 {len(active)} 个 active work 并行：")
    print()
    for idx, req_view in enumerate(active):
        if idx > 0:
            print("─" * 60)
        _render_single_req(req_view)
        print()

    render_quickfix_section(repo_root)
    print("提示：操作具体工作请先 cd 进对应 worktree 再跑 skill；主仓视角不默选某个工作。")


def render_timeline(timeline_state: dict, repo_root: Path) -> None:
    """Render --timeline 全局视图。"""
    active = timeline_state["active"]
    closed = timeline_state["closed"]
    cancelled = timeline_state["cancelled"]
    total_archived = timeline_state["total_archived"]
    truncated = timeline_state["truncated"]

    print()
    print("📅 项目时间线")
    print()

    # Active
    print("═══ Active ═══")
    if not active:
        print("  （无进行中工作）")
    else:
        for item in active:
            meta = item["meta"]
            req_id = meta.get("id", item["work_dir"].name)
            req_name = meta.get("name", "")
            stage = meta.get("stage", 0)
            stage_name = STAGE_NAMES.get(stage, "?")
            print(f"🔄 {req_id} · {req_name}（{stage_name}）")

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
            print("  （无已关闭工作）")
    else:
        for item in closed:
            meta = item["meta"]
            req_id = meta.get("id", item["work_dir"].name)
            req_name = meta.get("name", "")
            cd = item.get("close_date")
            date_str = cd.strftime("%Y-%m-%d") if cd else "?"
            print(f"✅ {req_id} · {req_name}（关闭 {date_str}）")

    print()

    # Cancelled
    if cancelled or any(i for i in [] if False):  # placeholder
        print(f"═══ Cancelled（显示 {len(cancelled)}）═══")
        for item in cancelled:
            meta = item["meta"]
            req_id = meta.get("id", item["work_dir"].name)
            req_name = meta.get("name", "")
            cd = item.get("close_date")
            date_str = cd.strftime("%Y-%m-%d") if cd else "?"
            print(f"❌ {req_id} · {req_name}（取消 {date_str}）")
        print()

    if truncated > 0:
        print(f"...还有 {truncated} 条 archived 未显示，用 --since YYYY-MM-DD 或 --all 看全部")
        print()

    print("──")
    print("过滤参数：--since YYYY-MM-DD | --module <name> | --all（取消 limit）")
    if timeline_state["warnings"]:
        print(f"⚠️  {len(timeline_state['warnings'])} warnings（meta 解析问题）")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="PM AI Workflow Status View",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
示例:
  status-view.py                          当前工作概览
  status-view.py --summary                一行 active work 概览
  status-view.py --timeline               全局时间线（active + closed + cancelled）
  status-view.py --timeline --module auth 只看 auth 模块相关工作
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
        "--summary", action="store_true", help="Print one-line active work overview"
    )
    parser.add_argument(
        "--timeline", action="store_true",
        help="全局时间线视图：active + closed + cancelled 全量按时间倒序"
    )
    parser.add_argument("--since", default=None, help="(timeline) 仅显示关闭时间 >= YYYY-MM-DD 的 archived")
    parser.add_argument("--module", default=None, help="(timeline) 仅显示涉及该 module 的工作")
    parser.add_argument("--limit", type=int, default=20, help="(timeline) archived 总数限制 (默认 20)")
    parser.add_argument("--all", action="store_true", help="(timeline) 取消 limit，显示全部 archived")
    parser.add_argument(
        "--banner-only", action="store_true",
        help="(M2/ ) 仅输出当前 active work 的 stage banner 一行（按 banner-rules.md §1.1 格式）"
    )
    parser.add_argument(
        "--skill", default="REQ-STAGE-GATE",
        help="(--banner-only) 调用方 skill 名（如 STATUS / INIT-PROJECT），用于 banner 格式"
    )
    parser.add_argument(
        "--narrative", action="store_true",
        help="(M5/ ) 输出 AI 可直接念的进度叙述（当前 stage / 产物文件 / 最近 transition；不到小节级，codex C-4 范围降级）"
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
            limit=limit,
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


    if args.summary:
        render_summary(state, repo_root)
        render_health_check(repo_root)
        return

    render_status(state, repo_root)
    render_health_check(repo_root)


if __name__ == "__main__":
    main()
