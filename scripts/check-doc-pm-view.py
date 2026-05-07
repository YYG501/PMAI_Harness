#!/usr/bin/env python3
"""check-doc-pm-view.py — 启发式 lint，校验 PM 视图文档是否符合 PM-VIEW-RULES。

适用对象：PM 视图主文件（solution.md / task-plan.md / tasks/task-NNN-*.md）。
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
    - 必填章节缺失

  Warnings（启发式）：
    - 反向约束词（"禁止" / "不允许" / "禁用"）
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
        "反向约束词（建议改为正向描述或挪到工程合同）",
        "warning",
    ),
}

# UI skeleton paren annotation: full-width brackets inside UI skeleton fenced
# code blocks (PM-VIEW-RULES §3.10) — warning only; PM/AI judges legitimate
# (CSV/分钟) vs. illegitimate (基于 X / 多 Y 场景).
# UI 骨架 section heading 涵盖：
#   - solution.md 的 `## 🖼 页面 UI 骨架`
#   - tasks/task-NNN.md 的 `## 📐 产物预览`
UI_PAREN_PATTERN = re.compile(r"（[^）\n]{2,}）")
UI_HEADING_PATTERN = re.compile(r"^##\s+(?:🖼|📐)")
ANY_H2_PATTERN = re.compile(r"^##\s+")

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
    "task": [
        "任务卡",
        "关键产品决策",
        "产物预览",
        "功能清单",
        "范围",
        "验收清单",
    ],
}


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
    return path.name.endswith(".engineering.md")


def lint(path: Path) -> tuple[list[str], list[str]]:
    """Return (errors, warnings)."""
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")

    errors: list[str] = []
    warnings: list[str] = []

    # Iterate lines, skip HTML comments and code blocks
    in_html_comment = False
    in_code_block = False
    in_ui_section = False  # tracks §🖼 页面 UI 骨架 section for §3.10 paren rule
    for ln, line in enumerate(lines, 1):
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

        # §🖼 section tracking (only outside code blocks; ## headings never appear inside)
        if not in_code_block and ANY_H2_PATTERN.match(line):
            in_ui_section = bool(UI_HEADING_PATTERN.match(line))

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

        for key, (pattern, desc, severity) in FORBIDDEN_PATTERNS.items():
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
        return 2

    if is_engineering_file(path):
        print(f"⏭  跳过 {path.name}：工程合同允许所有工程内容（PM-VIEW-RULES §四）")
        return 0

    doc_type = detect_doc_type(path)
    if doc_type == "unknown":
        print(
            f"⚠️  未识别的 PM 视图文件类型: {path.name}\n"
            f"   仅校验 solution.md / task-plan.md / tasks/task-NNN-*.md。",
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
