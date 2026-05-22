#!/usr/bin/env python3
"""check-doc-pm-view.py — 启发式 lint，校验 PM 视图文档是否符合 PM-VIEW-RULES。

适用对象：PM 视图主文件（task-plan.md / tasks/task-NNN-*.md；在飞旧 req 的 solution.md）。
工程合同（*.engineering.md）跳过校验（允许所有工程内容）。

校验项（参 PM-VIEW-RULES §三 §七 §八）：
  Errors（强制）：
    - 像素值（如 24px / 420px）
    - 颜色码（如 #C9CDD4）
    - Tailwind 类（如 w-14 / py-5）
    - 工程词 / 中英混杂业务词（reducer / dispatch / props / hook / useState
      / admin / scope / CRUD / active / pending / null / undefined / schema
      / topContent / kebab / segmented control / event.stopPropagation 等；§3.8）
    - 反引号代码引用（`useState` / `getXxx()` / `field.attribute` 等；§3.8）
    - 数学符号（⊊ ⊆ ∩ ∪ 等；§3.8）
    - URL 参数字面量（如 tab=pools&view=dept；§3.8 反引号代码引用泛化）
    - 必填章节缺失

  Warnings（启发式）：
    - 显式反向约束词（"禁止" / "不允许" / "禁用"）
    - 隐式反向句式（"不出现 / 不展示 / 不通过 / 无任何 / 没有...入口" 等；§3.4）
    - UI 排版中文词（"第一行 / 第二行 / 两列 / 三项简化形态" 等；§5.2）
    - 中英混杂业务词（breakdown / mock / self-contained 等；§3.8）
    - 设计意图括号（（避免...） / （防止...） / （为了...）；§3.2）
    - UI 骨架代码块内括号注释（§🖼 页面 UI 骨架 / §📐 产物预览；建议人工判定是合法标识型还是非法释义型）

跳过区域：HTML 注释（<!-- -->）/ markdown 代码块（``` ```）
**例外**：UI 骨架（§🖼 / §📐）的代码块内仍然扫描"骨架内括号注释"规则（PM-VIEW-RULES §3.10）

用法:
  python3 scripts/check-doc-pm-view.py <doc-file>
  python3 scripts/check-doc-pm-view.py <doc-file> --strict   # 有 error 退出 1
"""

import argparse
import re
import sys
from pathlib import Path


# ---- Forbidden patterns ----
FORBIDDEN_PATTERNS = {
    "pixel_value": (
        re.compile(r"\b\d{1,4}px\b"),
        "像素值",
        "error",
    ),
    "color_hex": (
        re.compile(r"#[0-9A-Fa-f]{3}(?:[0-9A-Fa-f]{3})?\b"),
        "颜色码",
        "error",
    ),
    "tailwind_class": (
        re.compile(r"\b(?:w|h|m|mt|mb|ml|mr|mx|my|p|pt|pb|pl|pr|px|py|gap|space)-\d+\b"),
        "Tailwind 类（如 w-14 / py-5）",
        "error",
    ),
    "engineering_term": (
        re.compile(
            r"\b(?:"
            # React hooks / 状态机词（原有）
            r"reducer|dispatch|useState|useReducer|useMemo|useEffect|"
            r"useCallback|useRef|React\.memo|discriminated\s+union|"
            # 中英混杂业务词（§3.8 中英混杂业务词）
            r"admin|scope|CRUD|"
            # 中英混杂状态字面量（§3.8 中英混杂状态字面量）
            r"active|pending|null|undefined|"
            # 数据结构 / 实现词（§3.8 中英混杂数据结构 / 实现词）
            r"schema|props|hook|topContent|kebab|segmented\s+control|"
            # 事件 / 方法引用（§3.2 组件实现名）
            r"event\.stopPropagation"
            r")\b"
        ),
        "工程词 / 中英混杂业务词（§3.8）",
        "error",
    ),
    "backtick_code_ref": (
        re.compile(r"`[^`\n]+`"),
        "反引号代码引用（§3.8：反引号包裹的代码 / 字段 / API 名一律不出现在 PM 视图）",
        "error",
    ),
    "math_set_notation": (
        re.compile(r"[⊊⊆⊇⊋∩∪]"),
        "数学符号（§3.8：用业务语言替换，如「两者交集」/「完全包含且至少少一个」）",
        "error",
    ),
    "reverse_constraint": (
        re.compile(r"(禁止|不允许|不准|禁用|不得)"),
        "反向约束词（§3.4：建议改为正向描述或挪到工程合同）",
        "warning",
    ),
    "implicit_reverse": (
        re.compile(
            r"(?:"
            # 显式动词反向
            r"不出现|不展示|不通过|不保留|不再保留|不再展示|不再持有|"
            # "无任何 / 没有任何"
            r"无任何|没有任何|"
            # "没有 X 入口/按钮/操作/菜单/跳转/提示"
            r"没有[^，。；,;.\n]{0,12}(?:入口|按钮|操作|菜单|跳转|提示|内容|功能|展示)"
            r")"
        ),
        "隐式反向句式（§3.4：建议改正向描述或挪到工程合同——'没有 X' / '不出现 X' 等于 '禁止 X' 的软化版）",
        "warning",
    ),
    "ui_layout_word": (
        re.compile(
            r"(?:"
            # 第 N 行 / 第 N 列
            r"第\s*[一二三四五六七八九十1234567890]+\s*[行列]|"
            # N 行紧凑/展示/结构/形态/布局
            r"[两三四五]\s*[行列](?:紧凑|展示|结构|形态|布局)|"
            # N 项 简化/展示/结构/形态
            r"[两三四五六]\s*项(?:简化|展示|结构|形态)|"
            # "三项" 后接「：」/「，」描述（含义为"三个段"）
            r"[两三四五六]\s*项[：，；]"
            r")"
        ),
        "UI 排版中文词（§5.2：'换 UI 还成立'判别——行号/列数/项数属 layout 描述，应在「📐 产物预览」骨架体现而不是 §📋 文字）",
        "warning",
    ),
    "mid_english_business_word": (
        re.compile(
            r"\b(?:breakdown|mock|self[-\s]?contained)\b",
            re.IGNORECASE,
        ),
        "中英混杂业务词（§3.8：breakdown→明细 / mock→模拟 / self-contained→各自独立）",
        "warning",
    ),
    "design_intent_paren": (
        re.compile(r"（\s*(?:避免|防止|确保|为了|以防|快速识别|更可信|无意义|更好地|防范)"),
        "设计意图括号（§3.2：解释'为什么'移到「🎯 关键产品决策」共同理由或工程合同；PM 视图只描述系统行为）",
        "warning",
    ),
    "url_param_literal": (
        re.compile(r"\b[a-z][a-z0-9_]*=[a-z0-9_-]+(?:&[a-z][a-z0-9_]*=[a-z0-9_-]+)+\b"),
        "URL 参数字面量（§3.8：query string 是工程层细节，PM 视图只描述跳转结果——'详情页直接打开 X 视图'）",
        "error",
    ),
}

# UI skeleton paren annotation: full-width brackets inside UI skeleton fenced
# code blocks (PM-VIEW-RULES §3.10) — warning only; PM/AI judges legitimate
# (CSV/分钟) vs. illegitimate (基于 X / 多 Y 场景).
# UI 骨架 section heading 涵盖：
#   - tasks/task-NNN.md 的 `## 📐 产物预览`
#   - 在飞旧 req solution.md 的 `## 🖼 页面 UI 骨架`
UI_PAREN_PATTERN = re.compile(r"（[^）\n]{2,}）")
UI_HEADING_PATTERN = re.compile(r"^##\s+(?:🖼|📐)")
ANY_H2_PATTERN = re.compile(r"^##\s+")

# History archive sections are metadata logs (reconcile hash entries / 变更记录 /
# auto-generated reconcile entries) — exempt from PM 视图 content rules. Pattern
# 涵盖 §📁 历史档案 / 变更记录 顶层节及其内嵌内容。
HISTORY_HEADING_PATTERN = re.compile(r"^##\s+(?:📁\s*)?(?:历史档案|变更记录)")

# §📦 范围 / §✅ 验收清单 sections allow reverse phrasing as natural form:
#   - §📦 范围: scope-change description (e.g., "本 task 移除 X / 不再保留 Y")
#     intrinsically describes what's removed, not 反向约束 of system behavior.
#   - §✅ 验收清单: verification list naturally uses "verify X doesn't appear"
#     (e.g., "不出现英文字段名" / "不出现「至 YYYY-MM-DD」"). PM 走查 friendly form.
# Skip implicit_reverse / reverse_constraint within these sections only;
# other rules (反引号 / 工程词 / mid-English 等) still apply.
REVERSE_EXEMPT_HEADING_PATTERN = re.compile(r"^##\s+(?:📦\s*范围|✅\s*验收清单)")

# ---- Required sections by document type ----
REQUIRED_SECTIONS = {
    "solution": [
        "方案摘要",
        "术语表",
        "关键产品决策",
        "交付物清单",
        "数据模型与状态",
        "模块职责与边界",
        "页面 UI 骨架",
        "规格文档变更范围",
        "task 拆分预估",
        "风险与未决事项",
        "验收标准",
    ],
    "task-plan": [
        "拆分摘要",
        "Task 列表",
        "执行顺序与并行性",
        "风险",
        "自检与状态摘要",
    ],
    # v2 / v1 双文件 / 老单文件 task（在飞旧 task）
    "task": [
        "任务卡",
        "关键产品决策",
        "产物预览",
        "功能清单",
        "范围",
        "验收清单",
    ],
}

# delta-3 §2.1：v3 单文件 typed contract 的 PM 确认区必填章节。
# 关键产品决策 / 产物预览 / 功能清单 已移 prd.md（delta-2），不在 task 文件。
REQUIRED_SECTIONS_V3_TASK = [
    "任务卡",
    "范围",
    "验收清单",
    "PM 反馈承接清单",
]

# v3 typed contract 标记 + PM 确认区 region 标记（scoped lint 用，delta-3 vp-6）
TASK_FORMAT_V3_MARKER = "task_format: single-typed-v3"
V3_REGION_PM_CONFIRM_BEGIN = "region: PM-CONFIRM begin"
V3_REGION_PM_CONFIRM_END = "region: PM-CONFIRM end"


def detect_doc_type(path: Path) -> str:
    name = path.name
    if name == "solution.md":
        return "solution"
    if name == "task-plan.md":
        return "task-plan"
    if name.startswith("task-") and name.endswith(".md") and not name.endswith(".engineering.md"):
        return "task"
    return "unknown"


def is_engineering_file(path: Path) -> bool:
    """工程合同性质文件 —— 允许所有工程内容，跳过 PM-view lint。

    含 `*.engineering.md` 与 `implementation-design.md`（delta-8：req 级实现设计
    是工程合同格式 artifact，允许 TS 类型 / 字段 / 像素 / 反向约束）。
    """
    return (
        path.name.endswith(".engineering.md")
        or path.name == "implementation-design.md"
    )


def lint(path: Path) -> tuple[list[str], list[str]]:
    """Return (errors, warnings).

    delta-3 vp-6 scoped 模式：v3 单文件 typed contract（头部含 task_format 标记）
    只校验「PM 确认区」（`region: PM-CONFIRM` begin/end 之间）；执行区 / 审计区
    允许工程内容、不跑 PM-view lint。
    """
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")

    errors: list[str] = []
    warnings: list[str] = []

    # delta-3：v3 typed contract task 文件走 scoped 模式
    is_v3_scoped = (
        TASK_FORMAT_V3_MARKER in text and detect_doc_type(path) == "task"
    )
    in_pm_confirm = False  # 仅 v3 scoped 模式用；非 v3 文件全程视为 True

    # Iterate lines, skip HTML comments and code blocks
    in_html_comment = False
    in_code_block = False
    in_ui_section = False  # tracks §🖼 页面 UI 骨架 section for §3.10 paren rule
    in_history_section = False  # tracks §📁 历史档案 / 变更记录 — exempt all rules
    in_reverse_exempt_section = False  # tracks §📦 范围 / §✅ 验收清单 — exempt reverse rules
    for ln, line in enumerate(lines, 1):
        # v3 scoped：先检测 PM 确认区 region 标记（标记本身是 HTML 注释，须在注释跳过前判）
        if is_v3_scoped:
            if V3_REGION_PM_CONFIRM_BEGIN in line:
                in_pm_confirm = True
                continue
            if V3_REGION_PM_CONFIRM_END in line:
                in_pm_confirm = False
                continue
            if not in_pm_confirm:
                continue  # 执行区 / 审计区 —— 跳过 PM-view lint

        # HTML comment tracking (multi-line aware)
        if in_html_comment:
            if "-->" in line:
                in_html_comment = False
            continue
        if "<!--" in line and "-->" not in line:
            in_html_comment = True
            continue
        if "<!--" in line and "-->" in line:
            # Inline comment — skip the commented portion
            line = re.sub(r"<!--.*?-->", "", line)

        # Section tracking (only outside code blocks; ## headings never appear inside)
        if not in_code_block and ANY_H2_PATTERN.match(line):
            in_ui_section = bool(UI_HEADING_PATTERN.match(line))
            in_history_section = bool(HISTORY_HEADING_PATTERN.match(line))
            in_reverse_exempt_section = bool(REVERSE_EXEMPT_HEADING_PATTERN.match(line))

        # Code block tracking
        if line.strip().startswith("```"):
            in_code_block = not in_code_block
            continue
        if in_code_block:
            # Inside a fenced block, skip global rules — but still apply the
            # §3.10 paren rule when within §🖼 (UI skeleton boxes live here).
            if in_ui_section:
                for m in UI_PAREN_PATTERN.finditer(line):
                    snippet = line.strip()
                    if len(snippet) > 80:
                        snippet = snippet[:80] + "..."
                    warnings.append(
                        f"L{ln}: §🖼 骨架代码块内括号注释（PM-VIEW-RULES §3.10：人工判合法标识型 vs 非法释义型）: '{m.group(0)}' — {snippet}"
                    )
            continue

        # 历史档案 section is metadata (reconcile log / 变更记录) — exempt from all rules
        if in_history_section:
            continue

        for key, (pattern, desc, severity) in FORBIDDEN_PATTERNS.items():
            # §📦 范围 / §✅ 验收清单 allow reverse phrasing as natural form
            # (scope-change describes 移除 / 验收 describes 不出现 X)
            if in_reverse_exempt_section and key in ("reverse_constraint", "implicit_reverse"):
                continue
            for m in pattern.finditer(line):
                snippet = line.strip()
                if len(snippet) > 80:
                    snippet = snippet[:80] + "..."
                msg = f"L{ln}: {desc}: '{m.group(0)}' — {snippet}"
                if severity == "error":
                    errors.append(msg)
                else:
                    warnings.append(msg)

    # Required sections check
    doc_type = detect_doc_type(path)
    if is_v3_scoped:
        required = REQUIRED_SECTIONS_V3_TASK
    else:
        required = REQUIRED_SECTIONS.get(doc_type, [])
    if required:
        # Collect all headings (## or ### or deeper)
        headings = re.findall(r"^#{2,4}\s+(.*?)\s*$", text, re.MULTILINE)
        for sec in required:
            if not any(sec in h for h in headings):
                errors.append(f"缺少必填章节: '{sec}'（PM-VIEW-RULES §七）")

    return errors, warnings


def main() -> int:
    parser = argparse.ArgumentParser(
        description="启发式 lint：校验 PM 视图文档是否符合 PM-VIEW-RULES"
    )
    parser.add_argument("file", help="PM 视图文档路径")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="有 error 时 exit 1（默认 exit 0 不阻塞）",
    )
    args = parser.parse_args()

    path = Path(args.file)
    if not path.exists():
        print(f"❌ 文件不存在: {path}", file=sys.stderr)
        print(
            "   修复：检查路径拼写；PM 视图文件应位于 "
            "$ACTIVE_REQ_DIR/{task-plan.md,tasks/task-NNN-*.md}。",
            file=sys.stderr,
        )
        return 2

    if is_engineering_file(path):
        print(
            f"⏭  跳过 {path.name}：工程合同格式文件允许所有工程内容"
            "（PM-VIEW-RULES §四；implementation-design.md 同此豁免）"
        )
        return 0

    doc_type = detect_doc_type(path)
    if doc_type == "unknown":
        print(
            f"⚠️  未识别的 PM 视图文件类型: {path.name}\n"
            f"   仅校验 task-plan.md / tasks/task-NNN-*.md（在飞旧 req 的 solution.md 仍兼容）。",
            file=sys.stderr,
        )
        return 0

    errors, warnings = lint(path)

    print(f"📋 PM-View Lint: {path}")
    print(f"   文档类型: {doc_type}")
    print()

    if errors:
        print(f"❌ Errors ({len(errors)}):")
        for e in errors:
            print(f"   {e}")
        print()
    if warnings:
        print(f"⚠️  Warnings ({len(warnings)}):")
        for w in warnings:
            print(f"   {w}")
        print()
    if not errors and not warnings:
        print("✅ 全部校验通过。")
        return 0

    if args.strict and errors:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
