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
from _lib.stages import LIFECYCLE_NAMES, STAGE_NAMES, MAX_STAGE  # noqa: E402  ( F13 单一真相源)


def _lifecycle(meta: dict) -> str:
    build = meta.get("build")
    if isinstance(build, dict) and build.get("lifecycle_state"):
        return str(build["lifecycle_state"])
    return str(meta.get("lifecycle_state") or "")


def _docs_status(meta: dict) -> str:
    build = meta.get("build")
    if isinstance(build, dict):
        return str(build.get("docs_status") or "")
    return ""


def _progress_name(meta: dict) -> str:
    lifecycle = _lifecycle(meta)
    if lifecycle in LIFECYCLE_NAMES:
        return LIFECYCLE_NAMES[lifecycle]
    return STAGE_NAMES.get(int(meta.get("stage", 0) or 0), "未知")


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
    for work in active:
        meta = work["meta"]
        work_id = meta.get("id", "?")
        parts.append(f"{work_id}:{_progress_name(meta)}")
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
    work_view = active[0]
    work_dir = work_view["work_dir"]
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


def _git_status_lines(repo_root: Path) -> list[str]:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo_root), "status", "--short", "--untracked-files=all"],
            check=False,
            text=True,
            capture_output=True,
        )
    except Exception:
        return []
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line.strip()]


def _dirty_module_names(status_lines: list[str]) -> list[str]:
    names: list[str] = []
    seen: set[str] = set()
    for line in status_lines:
        path = line[3:] if len(line) > 3 else line
        path = path.strip()
        if path.startswith("docs/modules/"):
            parts = path.split("/")
            if len(parts) >= 3 and parts[2] and parts[2] not in seen:
                seen.add(parts[2])
                names.append(parts[2])
    return names


def _work_display_name(work_view: dict) -> str:
    meta = work_view["meta"] or {}
    name = str(meta.get("name") or "").strip()
    work_id = str(meta.get("id") or "").strip()
    if name and name != "?":
        return name
    if work_id and work_id != "?":
        return work_id
    return work_view["work_dir"].name


def _stage_status_text(stage: int, lifecycle: str = "") -> str:
    if lifecycle == "designing":
        return "正在讨论并收敛建造依据。"
    if lifecycle == "ready_to_build":
        return "设计已定，可以开始构建。"
    if lifecycle == "building":
        return "正在构建指定对象。"
    if lifecycle == "iterating":
        return "正在看结果并做多轮修改。"
    if lifecycle == "final_check":
        return "已经定稿，正在做最终检查。"
    if lifecycle in {"landed", "documenting"}:
        return "实现已进入主线，正在更新正式文档。"
    if lifecycle == "complete":
        return "本轮已经完成。"
    if stage <= 1:
        return "还在设计讨论。"
    if stage == 2:
        return "等待实现或正在实现。"
    if stage == 3:
        return "正在复审。"
    if stage >= 4:
        return "等待收尾。"
    return "状态不明确。"


def _work_priority(work_view: dict) -> tuple[int, str]:
    meta = work_view["meta"] or {}
    lifecycle = _lifecycle(meta)
    lifecycle_priority = {
        "landed": 0,
        "documenting": 0,
        "final_check": 1,
        "iterating": 2,
        "building": 3,
        "ready_to_build": 4,
        "designing": 5,
    }
    if lifecycle in lifecycle_priority:
        return lifecycle_priority[lifecycle], _work_display_name(work_view)
    stage = int(meta.get("stage", 0) or 0)
    if stage >= 4:
        priority = 0
    elif stage == 3:
        priority = 1
    elif stage == 2:
        priority = 2
    else:
        priority = 3
    return priority, _work_display_name(work_view)


def _is_generator_repo(repo_root: Path) -> bool:
    """The PMAI framework repo is not a consumer project."""
    return (repo_root / "scripts" / "init-project.sh").exists()


def _file_mentions_pmai(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return False
    return "PMAI" in text or "/pmai-" in text


def _has_pmai_project_marker(repo_root: Path) -> bool:
    """Detect whether a directory is already a PMAI consumer project.

    This is intentionally marker-based rather than "does docs/ exist": existing
    codebases often have their own docs directory, and those still need the
    init-project entry to choose the brownfield path.
    """
    docs_dir = repo_root / "docs"
    marker_paths = [
        repo_root / "PRODUCT.md",
        repo_root / "PRODUCT-STATE.md",
        docs_dir / "PRODUCT.md",
        docs_dir / "PRODUCT-STATE.md",
        docs_dir / "CONTEXT.md",
        repo_root / ".pm-workflow" / "config.yml",
        repo_root / ".codex" / "hooks.json",
    ]
    if any(path.exists() for path in marker_paths):
        return True
    return _file_mentions_pmai(repo_root / "AGENTS.md") or _file_mentions_pmai(
        repo_root / "CLAUDE.md"
    )


def is_uninitialized_project(repo_root: Path) -> bool:
    """True when a non-framework repo has no PMAI project markers yet."""
    return not _is_generator_repo(repo_root) and not _has_pmai_project_marker(repo_root)


def render_uninitialized_project_hint(repo_root: Path) -> None:
    print()
    print("💡 项目体检：这个目录还没有 PMAI 初始化")
    print("  下一步：发 /pmai-init-project。")
    print("  如果这是已有代码库，/pmai-init-project 会自动进入代码现状盘点；不需要手动改跑其它 skill。")
    print("  在完成初始化或接入前，其它 /pmai-* skill 不应继续写项目产物。")


def render_narrative(state: dict, repo_root: Path) -> None:
    """M5 /  : AI 可直接念的进度叙述（产品轴）。

    范围（codex C-4 降级）：当前 active work / 当前 stage / 产物文件 / 最近 transition；
    **不到小节级**（如「§四」/ commit hash 全文 不写，伪精确）。

    无进行中工作 → 输出"没有进行中的工作"；若工作区有未提交改动，
    优先提示"有一轮改动还没收口"，**不编造**（review R7 防幻觉）。
    """
    active = sorted(state["active_work"], key=_work_priority)
    dirty_lines = [] if _is_generator_repo(repo_root) else _git_status_lines(repo_root)
    if not active:
        if dirty_lines:
            dirty_modules = _dirty_module_names(dirty_lines)
            print("当前状态：有一轮改动还没收口")
            if dirty_modules:
                print()
                print("涉及模块：" + "、".join(dirty_modules))
            print()
            print("需要注意：当前有未提交改动，它们不是已经完成的稳定状态。")
            print("建议下一步：先把这轮改动固定到独立分支或提交点，再继续验证和收口。")
        else:
            print("当前状态：没有进行中的工作")
            print()
            print("建议下一步：发 /pmai-design 起一个模块工作。")
        return

    # 单个工作场景：直接念
    if len(active) == 1:
        work = active[0]
        meta = work["meta"] or {}
        stage = meta.get("stage", 0)
        lifecycle = _lifecycle(meta)
        stage_name = _progress_name(meta)
        # 不写 commit hash / 时间细节；只点 stage 状态
        prod = _product_oneliner(repo_root)
        prod_line = f"你的产品：{prod}\n" if prod else ""
        dirty_suffix = "，且主线工作区有未提交改动" if dirty_lines else ""
        print(
            f"当前状态：有 1 个进行中的工作{dirty_suffix}\n\n"
            f"{prod_line}正在处理：{_work_display_name(work)}。\n"
            f"状态：{_stage_status_text(int(stage or 0), lifecycle)}\n"
            f"当前步骤：{stage_name}。\n"
            f"下一步：{suggest_next_action(work)}"
        )
        if dirty_lines:
            print("\n需要注意：主线工作区有未提交改动，先确认这些改动是否属于当前工作。")
        return

    # 多个工作场景：产品轴 lead + 列各工作概况
    prod = _product_oneliner(repo_root)
    dirty_suffix = "，且主线工作区有未提交改动" if dirty_lines else ""
    print(f"当前状态：有 {len(active)} 个进行中的工作{dirty_suffix}")
    if prod:
        print()
        print(f"你的产品：{prod}")
    print()
    print("进行中的工作：")
    for idx, work in enumerate(active, 1):
        meta = work["meta"] or {}
        stage = meta.get("stage", 0)
        lifecycle = _lifecycle(meta)
        stage_name = _progress_name(meta)
        print()
        print(f"{idx}. {_work_display_name(work)}")
        print(f"   状态：{_stage_status_text(int(stage or 0), lifecycle)}")
        print(f"   当前步骤：{stage_name}。")
        print(f"   下一步：{suggest_next_action(work)}")
    if dirty_lines:
        print()
        print("需要注意：主线工作区有未提交改动，先处理这部分，再继续其它 build。")


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
    if _is_generator_repo(repo_root):
        return

    if is_uninitialized_project(repo_root):
        render_uninitialized_project_hint(repo_root)
        return

    docs_dir = repo_root / "docs"
    if not docs_dir.exists():
        return

    missing: list = []

    if not (repo_root / "PRODUCT.md").exists():
        if (docs_dir / "CONTEXT.md").exists():
            missing.append(
                ("PRODUCT.md", "可能漏跑 migrate-context-to-project.py — docs/CONTEXT.md 还在")
            )
        elif (docs_dir / "PRODUCT.md").exists():
            missing.append(("PRODUCT.md", "旧布局里还在 docs/PRODUCT.md；新布局应放仓库根目录"))
        else:
            missing.append(("PRODUCT.md", "项目级文档主真相源；未初始化跑 /pmai-init-project，已初始化重定方向跑 /pmai-direction"))

    for filename, hint in (
        ("PRODUCT-STATE.md", "产品现状 hub"),
        ("DESIGN.md", "视觉和交互基线"),
        ("PRODUCT-RULES.md", "跨模块产品规则文档"),
        ("TODO.md", "PM 待办池"),
    ):
        if not (repo_root / filename).exists():
            if (docs_dir / filename).exists():
                missing.append((filename, f"旧布局里还在 docs/{filename}；新布局应放仓库根目录"))
            else:
                missing.append((filename, hint))


    if not missing:
        return

    print()
    print("💡 项目体检：缺以下产品级文档")
    for path, hint in missing:
        print(f"  - {path}（{hint}）")
    print("  补法：未初始化发 /pmai-init-project；已初始化项目发 /pmai-direction 校准方向")


def suggest_next_action(work_view: dict) -> str:
    """Suggest what PM should do next. work_view 是 state['active_work'][i].
    四步：1 设计 / 2 build / 3 复审 / 4 沉淀（MAX_STAGE=4）。"""
    meta = work_view["meta"]
    stage = meta.get("stage", 0)
    lifecycle = _lifecycle(meta)

    lifecycle_actions = {
        "designing": "继续 /pmai-design，把产品问题讨论清楚",
        "ready_to_build": "继续 /pmai-build；框架会自动准备隔离环境和构建工具",
        "building": "继续当前 /pmai-build，等构建结果可查看",
        "iterating": "继续看构建结果并直接说要改哪里；定稿后框架会自动收尾",
        "final_check": "继续当前构建的最终检查；通过后自动进入主线",
        "landed": "实现已在主线，继续当前工作的正式文档更新",
        "documenting": "继续完成文档影响地图和一致性检查",
        "complete": "本轮已完成，可以开始下一个模块",
    }
    if lifecycle == "landed" and _docs_status(meta) == "failed":
        return "实现已经在主线；从上次失败处继续正式文档更新，不重复合并"
    if lifecycle in lifecycle_actions:
        return lifecycle_actions[lifecycle]

    # 设计（≤1）：定 / 细化模块规格
    if stage <= 1:
        return f"继续{STAGE_NAMES.get(stage, '设计')}：发 /pmai-design 细化模块规格"

    # build（2）：对模块 spec 直建 + 三道审 + PM 验收
    if stage == 2:
        return "当前进度：build；发 /pmai-build <模块> 对着 spec 建"

    # 复审（3）
    if stage == 3:
        return "当前进度：复审；继续 /pmai-build 看结果并修改，定稿后自动收尾"

    # v1 兼容：stage ≥4 对应 finalize / 沉淀
    if stage >= 4:
        return "当前进度：收尾；继续当前工作对齐主线事实与正式文档"

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


def _render_single_work(work_view: dict) -> None:
    meta = work_view["meta"]
    work_id = meta.get("id", "?")
    work_name = meta.get("name", "?")
    stage = meta.get("stage", 0)
    stage_name = _progress_name(meta)
    print(f"当前工作：{work_id}（{work_name}）")
    print(f"当前进度：{stage_name}")
    print()

    print(f"下一步：{suggest_next_action(work_view)}")


def render_status(state: dict, repo_root: Path) -> None:
    active = state["active_work"]

    if not active:
        print("📭 没有活跃工作。运行 /pmai-design 设计新功能。")
        render_quickfix_section(repo_root)
        return

    if len(active) == 1:
        work_view = active[0]
        meta = work_view["meta"]
        work_id = meta.get("id", "?")
        work_name = meta.get("name", "?")
        stage = meta.get("stage", 0)
        stage_name = _progress_name(meta)
        print(f"当前工作：{work_id}（{work_name}）")
        print(f"当前进度：{stage_name}")
        print()

        render_quickfix_section(repo_root)

        print(f"下一步：{suggest_next_action(work_view)}")
        return

    print(f"📚 {len(active)} 个 active work 并行：")
    print()
    for idx, work_view in enumerate(active):
        if idx > 0:
            print("─" * 60)
        _render_single_work(work_view)
        print()

    render_quickfix_section(repo_root)
    print("提示：继续某个工作时直接说模块名；框架会恢复对应环境，不需要手动切目录。")


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
            work_id = meta.get("id", item["work_dir"].name)
            work_name = meta.get("name", "")
            stage = meta.get("stage", 0)
            stage_name = STAGE_NAMES.get(stage, "?")
            print(f"🔄 {work_id} · {work_name}（{stage_name}）")

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
            work_id = meta.get("id", item["work_dir"].name)
            work_name = meta.get("name", "")
            cd = item.get("close_date")
            date_str = cd.strftime("%Y-%m-%d") if cd else "?"
            print(f"✅ {work_id} · {work_name}（关闭 {date_str}）")

    print()

    # Cancelled
    if cancelled or any(i for i in [] if False):  # placeholder
        print(f"═══ Cancelled（显示 {len(cancelled)}）═══")
        for item in cancelled:
            meta = item["meta"]
            work_id = meta.get("id", item["work_dir"].name)
            work_name = meta.get("name", "")
            cd = item.get("close_date")
            date_str = cd.strftime("%Y-%m-%d") if cd else "?"
            print(f"❌ {work_id} · {work_name}（取消 {date_str}）")
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

    if is_uninitialized_project(repo_root):
        if args.banner_only:
            print(f"━━━ PMAI ► {args.skill} ▸ 项目未初始化 ━━━")
        render_uninitialized_project_hint(repo_root)
        return

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
