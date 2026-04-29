"""Task metadata parser — v1/v2 兼容层。

Single source of truth for reading task metadata from PM view (task.md) and
optionally engineering contract (task.engineering.md).

V1 format (legacy):  **状态：** 待确认  / **分支：** task-001-xxx
V2 format (current): | **状态** | 待确认 |  / | **分支** | task-001-xxx |

Sections like "文档偏差" / "自审记录" exist in PM view (v1) or engineering
contract §10/§11 (v2). read_section auto-discovers across both files.

约束（spot-check #1 / #3）：
- 字段值要求**半角管道符** `|`，不支持中文 `｜`（fullwidth）
- v2 表格行格式：`| **字段名** | 值 |`，空 cell 返回 None（caller 自行判 None）
- section heading 要求**标准格式** `## N. <name>` 或 `## <name>`，
  点后必须有空格；不支持 `## 10.<name>` / `## 10。<name>` / `## 10) <name>`
"""

from __future__ import annotations
from pathlib import Path
from typing import Literal, Optional, TypedDict
import re


# ============================================================================
# Format detection
# ============================================================================

def detect_format(pm_view: Path) -> Literal["v1", "v2"]:
    """v2 = 存在 .engineering.md 同名文件；v1 = 仅 PM 视图单文件。"""
    eng = engineering_path(pm_view)
    return "v2" if eng.exists() else "v1"


def engineering_path(pm_view: Path) -> Path:
    """task-001-foo.md → task-001-foo.engineering.md"""
    stem = pm_view.stem
    return pm_view.parent / f"{stem}.engineering.md"


# ============================================================================
# Field parsing (v1 + v2 双兼容)
# ============================================================================

# v1: **状态：** 待确认
V1_FIELD_RE = re.compile(r"^\*\*(.+?)：\*\*\s*(.+?)\s*$", re.MULTILINE)

# v2: | **状态** | 待确认 |
V2_FIELD_RE = re.compile(
    r"^\|\s*\*\*(.+?)\*\*\s*\|\s*([^\|]+?)\s*\|\s*$",
    re.MULTILINE,
)


def parse_field(text: str, field_name: str) -> Optional[str]:
    """从文本中提取字段值。v2 优先，v1 fallback。

    空值（cell 内容仅空格）视为 None，不返回空字符串——避免 caller 把空当有效值。
    """
    for m in V2_FIELD_RE.finditer(text):
        if m.group(1).strip() == field_name:
            value = m.group(2).strip()
            return value if value else None
    for m in V1_FIELD_RE.finditer(text):
        if m.group(1).strip() == field_name:
            value = m.group(2).strip()
            return value if value else None
    return None


class TaskMeta(TypedDict, total=False):
    status: Optional[str]
    branch: Optional[str]
    worktree: Optional[str]
    dev_server: Optional[str]
    created_at: Optional[str]
    review_tools: Optional[str]
    module: Optional[str]
    module_section: Optional[str]


def get_task_status(pm_view: Path) -> Optional[str]:
    return parse_field(pm_view.read_text(encoding="utf-8"), "状态")


def get_task_branch(pm_view: Path) -> Optional[str]:
    return parse_field(pm_view.read_text(encoding="utf-8"), "分支")


def get_task_worktree(pm_view: Path) -> Optional[str]:
    return parse_field(pm_view.read_text(encoding="utf-8"), "worktree")


def get_task_meta(pm_view: Path) -> TaskMeta:
    """一次性读所有常用字段。"""
    text = pm_view.read_text(encoding="utf-8")
    return TaskMeta(
        status=parse_field(text, "状态"),
        branch=parse_field(text, "分支"),
        worktree=parse_field(text, "worktree"),
        dev_server=(
            parse_field(text, "dev server") or parse_field(text, "开发服务器")
        ),
        created_at=parse_field(text, "创建时间"),
        review_tools=(
            parse_field(text, "审查工具") or parse_field(text, "review_tools")
        ),
        module=parse_field(text, "所属模块"),
        module_section=parse_field(text, "所属模块章节"),
    )


def parse_status_from_text(text: str) -> Optional[str]:
    """从文本片段提取状态值（不要求是完整 task 文件）。

    用于 hook 检测 Edit 的 old_string / new_string。
    """
    return parse_field(text, "状态")


# ============================================================================
# Section parsing (跨 PM 视图 + 工程合同)
# ============================================================================

def read_section(
    pm_view: Path,
    section_name: str,
) -> tuple[bool, Optional[str]]:
    """跨文件查找 section。

    优先级：先工程合同（v2），未命中再 PM 视图。
    支持新格式带数字编号（## 10. 文档偏差）和旧格式（## 文档偏差）。

    返回 (found, content)。
    Content 含 section heading 之后到下一个 ## heading 之前的全部内容。

    Caller 决定 found=False 时如何处理。
    """
    heading_re = re.compile(
        rf"^##\s+(?:\d+\.\s+)?{re.escape(section_name)}\s*$",
        re.MULTILINE,
    )

    # 1. 工程合同优先
    eng = engineering_path(pm_view)
    if eng.exists():
        content = _extract_section(eng.read_text(encoding="utf-8"), heading_re)
        if content is not None:
            return (True, content)

    # 2. PM 视图（v1 / v2 退化）
    content = _extract_section(pm_view.read_text(encoding="utf-8"), heading_re)
    if content is not None:
        return (True, content)

    return (False, None)


def _extract_section(text: str, heading_re: re.Pattern) -> Optional[str]:
    m = heading_re.search(text)
    if not m:
        return None
    start = m.end()
    next_m = re.search(r"^##\s+", text[start:], re.MULTILINE)
    end = start + next_m.start() if next_m else len(text)
    return text[start:end].strip()


def has_meaningful_content(content: Optional[str]) -> bool:
    """除注释和空白外是否有实质字符。"""
    if not content:
        return False
    cleaned = re.sub(r"<!--.*?-->", "", content, flags=re.DOTALL)
    lines = [l for l in cleaned.splitlines() if l.strip()]
    return len(lines) > 0


# ============================================================================
# CLI entry (供 bash 调用)
# ============================================================================

def _cli():
    import sys
    if len(sys.argv) < 3:
        print(
            "usage: python3 -m _lib.task_parser <fn> <pm_view> [args...]",
            file=sys.stderr,
        )
        sys.exit(2)

    fn = sys.argv[1]
    pm_view = Path(sys.argv[2])

    if not pm_view.exists():
        print(f"task file not found: {pm_view}", file=sys.stderr)
        sys.exit(1)

    if fn == "get_status":
        print(get_task_status(pm_view) or "")
    elif fn == "get_branch":
        print(get_task_branch(pm_view) or "")
    elif fn == "get_worktree":
        print(get_task_worktree(pm_view) or "")
    elif fn == "get_meta":
        import json
        print(json.dumps(get_task_meta(pm_view), ensure_ascii=False))
    elif fn == "read_section":
        if len(sys.argv) < 4:
            print(
                "usage: read_section <pm_view> <section_name>",
                file=sys.stderr,
            )
            sys.exit(2)
        section_name = sys.argv[3]
        found, content = read_section(pm_view, section_name)
        if not found:
            sys.exit(3)  # 让 bash caller 通过 exit code 区分
        print(content or "")
    elif fn == "detect_format":
        print(detect_format(pm_view))
    else:
        print(f"unknown fn: {fn}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    _cli()
