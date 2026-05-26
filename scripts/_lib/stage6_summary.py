"""Stage 6 入口总览（speed mode）— PM 单一真相源。

解析 implementation-design.md / task-plan.md / req-events.jsonl，渲染：
- 【AI 自决 N 件】（机械产出 — HOW-ID + 选择）
- 【PM 拍过 M 件结构决策】（HOW-ID / SIMP-ID / task-ID + 复述）
- 【task 拆分】（task-ID + title + 串行 / 并行）
- 【产物路径】（绝对路径）
- 【可选 review】 + 【PM 三选项】

被 `status-view.py --stage6-entry <req_dir>` 调用。

设计来源：discuss 2026-05-26 / speed mode（无独立设计文档，方案在
skills/req-stage-gate/SKILL.md「Speed Mode」段定）。
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class DecisionRow:
    """段 1 HOW 表 / 段 1.5 SIMP 表 / §一 task 表的单行抽象。"""

    id: str
    choice: str
    kind: str  # "结构" | "机械"
    note: str = ""  # SIMP 用「计划简化为」；task 用 title


@dataclass
class StageSummary:
    impl_design_path: Path
    task_plan_path: Path
    design_path: Path
    design_touched: bool

    how_mechanical: list[DecisionRow] = field(default_factory=list)
    how_structural: list[DecisionRow] = field(default_factory=list)
    simp_rows: list[DecisionRow] = field(default_factory=list)
    task_rows: list[DecisionRow] = field(default_factory=list)
    task_structural_ids: list[str] = field(default_factory=list)
    execution_mode: str = "未知"  # 串行 / 并行 / 混合 — 从 §二 流程文本启发式抓


# ---------- markdown table 解析（够用，不引第三方） ----------

_TABLE_DIVIDER_RE = re.compile(r"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)+\|?\s*$")


def _split_row(line: str) -> list[str]:
    """`| a | b | c |` → ['a', 'b', 'c']（首尾空 cell 丢掉）。"""
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


def _find_table(lines: list[str], header_match: callable) -> list[list[str]]:
    """找 header_match(header_cells) 返回 True 的表，返回数据行（list of cell list）。"""
    i = 0
    n = len(lines)
    while i < n - 1:
        line = lines[i]
        if line.lstrip().startswith("|"):
            header_cells = _split_row(line)
            next_line = lines[i + 1] if i + 1 < n else ""
            if _TABLE_DIVIDER_RE.match(next_line) and header_match(header_cells):
                # 从 i+2 起读数据行直到非 | 起始
                data: list[list[str]] = []
                j = i + 2
                while j < n:
                    cur = lines[j]
                    if not cur.lstrip().startswith("|"):
                        break
                    cells = _split_row(cur)
                    data.append(cells)
                    j += 1
                return data
        i += 1
    return []


# ---------- 段 1 HOW 表解析 ----------

def _parse_how_table(text: str) -> tuple[list[DecisionRow], list[DecisionRow]]:
    """段 1 架构决策表 → (机械 rows, 结构 rows)。

    表头：HOW-ID | 适用模块 / task 关键词 | 选择 | 备选 | 理由 | 约束失效条件 | 决策类型 | 来源
    兼容老 req 无「决策类型」列：全部按结构（保守）。
    """
    lines = text.splitlines()

    def is_how_header(cells: list[str]) -> bool:
        return any("HOW-ID" in c for c in cells)

    data = _find_table(lines, is_how_header)
    mechanical: list[DecisionRow] = []
    structural: list[DecisionRow] = []

    # 找表头取「决策类型」列索引（如果有）
    header_idx = -1
    for i, line in enumerate(lines):
        if line.lstrip().startswith("|") and "HOW-ID" in line:
            header_cells = _split_row(line)
            for k, c in enumerate(header_cells):
                if "决策类型" in c:
                    header_idx = k
                    break
            break

    for row in data:
        if not row or not row[0].strip():
            continue
        hid = row[0].strip()
        if not hid.startswith("HOW-") or "HOW-ID" in hid:
            continue  # 跳过模板占位 / 重复表头
        # 模板占位行：HOW-01 + 适用模块写 <模块名 / 关键词> → 跳过
        if len(row) > 1 and row[1].startswith("<") and row[1].endswith(">"):
            continue
        choice = row[2].strip() if len(row) > 2 else ""
        kind = ""
        if header_idx >= 0 and header_idx < len(row):
            kind = row[header_idx].strip()
        # 老 req 无「决策类型」列 → 默认结构（保守）
        if not kind or kind not in ("结构", "机械"):
            kind = "结构"
        d = DecisionRow(id=hid, choice=choice, kind=kind)
        if kind == "机械":
            mechanical.append(d)
        else:
            structural.append(d)
    return mechanical, structural


# ---------- 段 1.5 SIMP 表解析 ----------

def _parse_simp_table(text: str) -> list[DecisionRow]:
    """段 1.5 原型简化项 → SIMP rows（全部按结构）。"""
    lines = text.splitlines()

    def is_simp_header(cells: list[str]) -> bool:
        return any("SIMP-ID" in c for c in cells)

    data = _find_table(lines, is_simp_header)
    rows: list[DecisionRow] = []
    for row in data:
        if not row or not row[0].strip():
            continue
        sid = row[0].strip()
        if not sid.startswith("SIMP-") or "SIMP-ID" in sid:
            continue
        if len(row) > 1 and row[1].startswith("<") and row[1].endswith(">"):
            continue  # 模板占位
        note = row[3].strip() if len(row) > 3 else ""
        rows.append(DecisionRow(id=sid, choice=note, kind="结构", note=note))
    return rows


# ---------- task-plan §一 task 表解析 ----------

def _parse_task_table(text: str) -> tuple[list[DecisionRow], str]:
    """task-plan §一 task 表 → (rows, execution_mode 启发式)。

    表头：id | title | 所属模块 | 所属模块章节 | summary | order | risk | 决策类型
    老 req 无「决策类型」列 → 全部按结构（保守）。
    execution_mode 从 §二 文本启发式提取（含「串行」/「并行」）。
    """
    lines = text.splitlines()

    def is_task_header(cells: list[str]) -> bool:
        return cells and cells[0].strip().lower() == "id" and any("title" in c.lower() for c in cells)

    data = _find_table(lines, is_task_header)

    # 找表头列索引
    title_idx = -1
    kind_idx = -1
    for line in lines:
        if line.lstrip().startswith("|") and "id" in line.lower() and "title" in line.lower():
            header_cells = _split_row(line)
            for k, c in enumerate(header_cells):
                cl = c.strip().lower()
                if cl == "title":
                    title_idx = k
                if "决策类型" in c:
                    kind_idx = k
            break

    rows: list[DecisionRow] = []
    for row in data:
        if not row or not row[0].strip():
            continue
        tid = row[0].strip()
        if not tid.startswith("task-"):
            continue
        title = row[title_idx].strip() if title_idx >= 0 and title_idx < len(row) else ""
        kind = ""
        if kind_idx >= 0 and kind_idx < len(row):
            kind = row[kind_idx].strip()
        if not kind or kind not in ("结构", "机械"):
            kind = "结构"
        rows.append(DecisionRow(id=tid, choice=title, kind=kind, note=title))

    # 启发式抓 execution mode：扫 §二
    mode = "未知"
    in_section2 = False
    seen_serial = False
    seen_parallel = False
    for line in lines:
        if line.startswith("## 二"):
            in_section2 = True
            continue
        if in_section2 and line.startswith("## "):
            break
        if in_section2:
            if "串行" in line:
                seen_serial = True
            if "并行" in line:
                seen_parallel = True
    if seen_serial and seen_parallel:
        mode = "混合"
    elif seen_serial:
        mode = "串行"
    elif seen_parallel:
        mode = "并行"
    return rows, mode


# ---------- 主入口 ----------

def build_summary(req_dir: Path, repo_root: Path) -> StageSummary | None:
    """Build StageSummary from req_dir. None if req_dir not stage 5/6 entry-ready."""
    impl_path = req_dir / "implementation-design.md"
    plan_path = req_dir / "task-plan.md"
    design_path = repo_root / "docs" / "DESIGN.md"

    if not impl_path.exists() or not plan_path.exists():
        return None

    impl_text = impl_path.read_text(encoding="utf-8", errors="replace")
    plan_text = plan_path.read_text(encoding="utf-8", errors="replace")

    how_mech, how_struct = _parse_how_table(impl_text)
    simp_rows = _parse_simp_table(impl_text)
    task_rows, exec_mode = _parse_task_table(plan_text)
    task_struct_ids = [r.id for r in task_rows if r.kind == "结构"]

    # design_touched 启发式：git diff stage 4 入口至 HEAD 不好做（跨 stage history 复杂）
    # 简化：检查 docs/DESIGN.md 是否被本 req 改过 — 用 git log --grep req_id
    design_touched = False
    if design_path.exists():
        try:
            import subprocess
            req_id = req_dir.name
            out = subprocess.check_output(
                ["git", "-C", str(repo_root), "log", "--oneline", f"--grep={req_id}",
                 "--", str(design_path.relative_to(repo_root))],
                stderr=subprocess.DEVNULL, text=True, timeout=5,
            )
            design_touched = bool(out.strip())
        except Exception:
            design_touched = False

    return StageSummary(
        impl_design_path=impl_path,
        task_plan_path=plan_path,
        design_path=design_path,
        design_touched=design_touched,
        how_mechanical=how_mech,
        how_structural=how_struct,
        simp_rows=simp_rows,
        task_rows=task_rows,
        task_structural_ids=task_struct_ids,
        execution_mode=exec_mode,
    )


def render(summary: StageSummary) -> str:
    """渲染 stage 6 入口总览（PM 单一真相源）。"""
    lines: list[str] = []
    lines.append("═══════════════════════════════════════")
    lines.append("✅ Stage 4/5 完成，准备进 stage 6 task 执行")
    lines.append("═══════════════════════════════════════")
    lines.append("")

    # AI 自决（机械）
    if summary.how_mechanical:
        lines.append(f"【AI 自决 {len(summary.how_mechanical)} 件】（机械产出 / PRD 已硬约束）")
        for r in summary.how_mechanical:
            lines.append(f"  {r.id} {r.choice}")
        lines.append("")
    else:
        lines.append("【AI 自决 0 件】（本 req 所有架构决策都需 PM 拍板）")
        lines.append("")

    # PM 拍过（结构 + SIMP + task 结构）
    pm_count = len(summary.how_structural) + len(summary.simp_rows) + len(summary.task_structural_ids)
    lines.append(f"【PM 拍过 {pm_count} 件结构决策】")
    if not pm_count:
        lines.append("  （本 req 无结构决策，全是机械应用 PRD）")
    for r in summary.how_structural:
        lines.append(f"  {r.id} {r.choice}")
    for r in summary.simp_rows:
        lines.append(f"  {r.id} {r.note}")
    for tid in summary.task_structural_ids:
        # 找 title
        title = next((t.note for t in summary.task_rows if t.id == tid), "")
        lines.append(f"  {tid} {title}（拆分 / 合并 / 重排）")
    lines.append("")

    # task 拆分
    lines.append("【task 拆分】")
    if not summary.task_rows:
        lines.append("  （task-plan.md §一 task 表为空 — 不该到这里）")
    for t in summary.task_rows:
        lines.append(f"  {t.id} {t.note}")
    lines.append(f"  执行：{summary.execution_mode}")
    lines.append("")

    # 产物路径
    lines.append("【产物路径】")
    lines.append(f"  {summary.impl_design_path}")
    lines.append(f"  {summary.task_plan_path}")
    design_note = "本 req 改过" if summary.design_touched else "本 req 不改"
    lines.append(f"  {summary.design_path}（{design_note}）")
    lines.append("")

    # 可选 review
    lines.append("📊 可选 review（你自跑，跑完贴结论我帮你 append 事件）")
    lines.append("  /plan-eng-review     — 拆分合理性、依赖、并行性")
    lines.append("  /plan-design-review  — UI task 划分是否完整")
    lines.append("  /autoplan            — 上述 plan-* 的批量打包")
    lines.append("")

    # PM 三选
    lines.append("下一步：")
    lines.append("  ✓ 全部 ok 进 stage 6")
    lines.append("  ↺ 我要回看 [HOW-XX / SIMP-XX / task-XXX]")
    lines.append("  ✗ 回卷到 stage 4/5 重做")

    return "\n".join(lines)
