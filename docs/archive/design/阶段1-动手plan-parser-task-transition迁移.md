# 阶段 1 动手 plan — parser + task-transition 迁移

> 实施 v3.5 实施计划阶段 1。修复 P0-1（task 卡在「执行中→待验收」）+ 建立 parser 基础设施供后续 4 处迁移复用。
>
> **估时 1 天**（含测试 + spot-check 补充）。
>
> 参考：`设计-新两文件格式对齐.md` §四 4.1 / 4.2。
>
> **已经过轻量 plan-eng-review spot-check（2026-04-29）**：7 处风险点（2 medium + 5 low）全部落进本文档。19 条测试用例（原 11 + 补 8）。

---

## 0. 前置准备

```bash
git status
# 确认工作区状态：当前 main 分支有未提交 watchdog 改动
# scripts/run-bg.sh / skills/task-execute/SKILL.md / tests/test-run-bg.sh
```

**前置动作**：
- 先 commit 或 stash 现有 watchdog 改动，避免与本阶段改动混在一起
- 创建分支 `req-parser-foundation`（或按 PM-AI-Workflow 现有分支约定）

---

## 1. parser API 签名

### 1.1 新增 `scripts/_lib/__init__.py`（空文件，让 module 可被 `python3 -m _lib.xxx` 调用）

### 1.2 新增 `scripts/_lib/_setup-pythonpath.sh`

> **spot-check #5 修正**：必须用 `source`（不是 `bash`）调用，否则 export 不会传到 caller。文档化避免误用。

```bash
#!/usr/bin/env bash
# 必须用 `source`（不是 `bash`）调用，否则 export 不会传到 caller。
# 设计要点：BASH_SOURCE[0] 指向本脚本路径（与 cwd 无关），所以从任何 cwd source 都能正确解析。
#
# 调用方约定：
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/_lib/_setup-pythonpath.sh"
#   STATUS=$(python3 -m _lib.task_parser get_status "$task_file")

# scripts/ 目录 = _lib/_setup-pythonpath.sh 的祖父目录
_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}$_SCRIPTS_DIR"
```

### 1.2.1 `_lib/` 命名空间约定（**spot-check #7 修正**）

`_lib/` 是后续多个阶段共用 utility 的目录。命名约定：

- **按职责命名**，不按阶段编号
- **基础层不 import 上层**（避免循环依赖）

预期文件：

| 文件 | 阶段 | 职责 |
|---|---|---|
| `task_parser.py` | 1 | task PM 视图 / 工程合同元数据解析 |
| `structure_schema.py` | 4.5 | 工程结构约束 schema 解析 |
| `derive_templates.py` | 4.5 | schema → 两份模板派生 |
| `req_meta.py`（可能）| 5 | req.meta.json 读写（如果引入）|

新加文件按此约定命名，避免冲突。

### 1.3 新增 `scripts/_lib/task_parser.py`

```python
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
    """从文本中提取字段值。v2 优先，v1 fallback。"""
    for m in V2_FIELD_RE.finditer(text):
        if m.group(1).strip() == field_name:
            return m.group(2).strip()
    for m in V1_FIELD_RE.finditer(text):
        if m.group(1).strip() == field_name:
            return m.group(2).strip()
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
```

---

## 2. 单元测试 — 11 条用例

### 新增 `scripts/_lib/task_parser_test.py`

```python
"""task_parser 双兼容单测。"""

import unittest
import tempfile
from pathlib import Path

from _lib.task_parser import (
    detect_format,
    get_task_status,
    get_task_branch,
    get_task_meta,
    parse_status_from_text,
    read_section,
    has_meaningful_content,
)


# Fixtures

V1_TASK_MD = """# Task 001: Test

**状态：** 待确认
**分支：** task-001-test
**worktree：** /path/to/wt
**创建时间：** 2026-04-29

## 文档偏差
v1 文档偏差内容

## 自审记录
v1 自审记录内容
"""

V2_TASK_MD = """# Task 001: Test

| | |
|---|---|
| **状态** | 待确认 |
| **分支** | task-001-test |
| **worktree** | /path/to/wt |
| **创建时间** | 2026-04-29 |
"""

V2_TASK_ENG = """# Task 001: Test — 工程合同

## 1. 启动前必读
...

## 10. 文档偏差

v2 工程合同 文档偏差内容

## 11. 自审记录

v2 自审记录内容
"""


class TestDetectFormat(unittest.TestCase):
    def test_v2_when_engineering_exists(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            eng = Path(d) / "task-001-test.engineering.md"
            pm.write_text(V2_TASK_MD)
            eng.write_text(V2_TASK_ENG)
            self.assertEqual(detect_format(pm), "v2")

    def test_v1_when_only_pm_view(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V1_TASK_MD)
            self.assertEqual(detect_format(pm), "v1")


class TestStatusParsing(unittest.TestCase):
    def test_v2_status(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V2_TASK_MD)
            self.assertEqual(get_task_status(pm), "待确认")

    def test_v1_status(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V1_TASK_MD)
            self.assertEqual(get_task_status(pm), "待确认")


class TestBranchParsing(unittest.TestCase):
    def test_v2_branch(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V2_TASK_MD)
            self.assertEqual(get_task_branch(pm), "task-001-test")

    def test_v1_branch(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V1_TASK_MD)
            self.assertEqual(get_task_branch(pm), "task-001-test")


class TestReadSection(unittest.TestCase):
    def test_v2_section_in_engineering(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            eng = Path(d) / "task-001-test.engineering.md"
            pm.write_text(V2_TASK_MD)
            eng.write_text(V2_TASK_ENG)
            
            found, content = read_section(pm, "文档偏差")
            self.assertTrue(found)
            self.assertIn("v2 工程合同", content)

    def test_v1_section_in_pm_view(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V1_TASK_MD)
            
            found, content = read_section(pm, "文档偏差")
            self.assertTrue(found)
            self.assertIn("v1 文档偏差内容", content)

    def test_section_not_found(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V1_TASK_MD)
            
            found, content = read_section(pm, "不存在的_section")
            self.assertFalse(found)
            self.assertIsNone(content)

    def test_v2_falls_back_to_pm_view_when_engineering_missing_section(self):
        """v2 工程合同没有该 section → 退化到 PM 视图找。"""
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            eng = Path(d) / "task-001-test.engineering.md"
            pm.write_text(V2_TASK_MD + "\n## 文档偏差\nfallback content\n")
            eng.write_text("# Task 001\n## 1. 别的 section\n...")
            
            found, content = read_section(pm, "文档偏差")
            self.assertTrue(found)
            self.assertIn("fallback content", content)


class TestHasMeaningfulContent(unittest.TestCase):
    def test_empty(self):
        self.assertFalse(has_meaningful_content(""))
        self.assertFalse(has_meaningful_content(None))
    
    def test_only_comment(self):
        self.assertFalse(has_meaningful_content("<!-- placeholder -->"))
    
    def test_real_content(self):
        self.assertTrue(has_meaningful_content("- F-001 实际内容"))


class TestParseStatusFromText(unittest.TestCase):
    """hook 用：从文本片段提取状态。"""
    def test_v2_table_row(self):
        text = "| **状态** | 执行中 |"
        self.assertEqual(parse_status_from_text(text), "执行中")
    
    def test_v1_inline(self):
        text = "**状态：** 执行中"
        self.assertEqual(parse_status_from_text(text), "执行中")


# ============================================================================
# Spot-check 修正：边界 / 异常 / CLI 测试（issue 1, 2, 3）
# ============================================================================

class TestV2FieldBoundaries(unittest.TestCase):
    """spot-check #1: V2_FIELD_RE 边界情况。"""
    
    def test_empty_cell_returns_none(self):
        """空 cell 应返回 None（caller 自行判）。"""
        text = "| **状态** | |"
        self.assertIsNone(parse_status_from_text(text))
    
    def test_fullwidth_pipe_not_supported(self):
        """中文管道符 ｜ 不支持，返回 None（约束已文档化）。"""
        text = "｜ **状态** ｜ 待确认 ｜"
        self.assertIsNone(parse_status_from_text(text))


class TestExceptionPaths(unittest.TestCase):
    """spot-check #2: 异常路径覆盖。"""
    
    def test_missing_file_raises(self):
        """文件不存在应抛 FileNotFoundError。"""
        with self.assertRaises(FileNotFoundError):
            get_task_status(Path("/nonexistent/task-001.md"))
    
    def test_duplicate_field_returns_first_match(self):
        """字段重复时返回第一次匹配。"""
        text = "**状态：** 待确认\n**状态：** 执行中"
        self.assertEqual(parse_status_from_text(text), "待确认")


class TestSectionEdgeCases(unittest.TestCase):
    """spot-check #2/#3: section 边界情况。"""
    
    def test_section_at_eof(self):
        """section 在 EOF（无下一个 ## heading）应抓到全部到末尾。"""
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text("# Task\n\n## 文档偏差\nlast section content")
            
            found, content = read_section(pm, "文档偏差")
            self.assertTrue(found)
            self.assertIn("last section content", content)
    
    def test_section_with_h3_subheading_does_not_split(self):
        """section 含 ### 子标题不应被截断；遇到下一个 ## 才截断。"""
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(
                "# Task\n\n## 文档偏差\n### 子标题\n包含子标题的内容\n\n## 下一个 section\n"
            )
            
            found, content = read_section(pm, "文档偏差")
            self.assertTrue(found)
            self.assertIn("### 子标题", content)
            self.assertIn("包含子标题的内容", content)
            self.assertNotIn("下一个 section", content)
    
    def test_heading_without_dot_space_does_not_match(self):
        """spot-check #3: `## 10.文档偏差`（点后无空格）应**不匹配**（保守设计）。"""
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text("# Task\n\n## 10.文档偏差\n点后无空格\n")
            
            found, content = read_section(pm, "文档偏差")
            self.assertFalse(found)  # 当前是预期行为，模板要求 `## N. <name>`


class TestCLIExitCodes(unittest.TestCase):
    """spot-check #2: CLI 入口的 exit code 校验。"""
    
    def test_cli_get_status_v2(self):
        import subprocess
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V2_TASK_MD)
            result = subprocess.run(
                ["python3", "-m", "_lib.task_parser", "get_status", str(pm)],
                capture_output=True, text=True,
                env={"PYTHONPATH": str(Path(__file__).parent.parent)},
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout.strip(), "待确认")
    
    def test_cli_read_section_not_found_exit3(self):
        import subprocess
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V1_TASK_MD)
            result = subprocess.run(
                ["python3", "-m", "_lib.task_parser",
                 "read_section", str(pm), "不存在的_section"],
                capture_output=True, text=True,
                env={"PYTHONPATH": str(Path(__file__).parent.parent)},
            )
            self.assertEqual(result.returncode, 3)
    
    def test_cli_missing_file_exit1(self):
        import subprocess
        result = subprocess.run(
            ["python3", "-m", "_lib.task_parser",
             "get_status", "/nonexistent/task.md"],
            capture_output=True, text=True,
            env={"PYTHONPATH": str(Path(__file__).parent.parent)},
        )
        self.assertEqual(result.returncode, 1)


if __name__ == "__main__":
    unittest.main()
```

**测试用例统计**：
- 原 11 条 + 新增 8 条 = **19 条**
- 新增覆盖：V2 边界（2）/ 异常路径（2）/ section 边界（3）/ CLI exit code（3）— 共 8 条扎实补充

### 跑测试

```bash
cd ${REPO_ROOT}
PYTHONPATH=scripts python3 -m unittest scripts._lib.task_parser_test -v
# 期望：11+ tests passed
```

---

## 3. task-transition.py 迁移 diff 草案

修改文件：`scripts/task-transition.py`，行 ~200-220 段（`elif current == "执行中" and target == "待验收":` 块）。

### 顶部 import 加：

```python
import sys
from pathlib import Path

# 让 _lib 可以 import（task-transition.py 自身就在 scripts/，_lib 是同级子目录）
_SCRIPTS_DIR = str(Path(__file__).parent.resolve())
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.task_parser import read_section, has_meaningful_content
```

### 替换 `执行中 → 待验收` 段（line 200-220 大概范围）：

**Before**（当前代码，在 `elif current == "执行中" and target == "待验收":` 块内）：

```python
elif current == "执行中" and target == "待验收":
    # 1. 文档偏差 section 已填
    if not has_section_content(text, "文档偏差"):
        # Check for "无偏差"
        doc_section = re.search(
            r"^## 文档偏差.*?(?=^## |\Z)", text, re.MULTILINE | re.DOTALL
        )
        if doc_section and "无偏差" not in doc_section.group():
            print(
                "Error: 文档偏差 section 未填写。请填写文档偏差或写'无偏差'。",
                file=sys.stderr,
            )
            sys.exit(1)

    # 2. 自审记录 section 有内容
    if not has_section_content(text, "自审记录"):
        print(
            "Error: 自审记录 section 为空。请至少完成一次自审并记录结果。",
            file=sys.stderr,
        )
        sys.exit(1)

    # review 工具改为 PM 自跑推荐项；事件流仍可能含 review_completed
    # 作为审计记录，但不再做覆盖校验。
```

**After**：

```python
elif current == "执行中" and target == "待验收":
    # parser 跨文件查找（v1: PM 视图；v2: 工程合同 §10/§11）
    
    # 1. 文档偏差
    found, content = read_section(task_file, "文档偏差")
    if not found:
        print(
            "Error: 文档偏差 section 未找到（PM 视图与工程合同均无此 section）。",
            file=sys.stderr,
        )
        sys.exit(1)
    if not has_meaningful_content(content) and "无偏差" not in (content or ""):
        print(
            "Error: 文档偏差 section 未填写。请填写文档偏差或写'无偏差'。",
            file=sys.stderr,
        )
        sys.exit(1)
    
    # 2. 自审记录
    found, content = read_section(task_file, "自审记录")
    if not found:
        print(
            "Error: 自审记录 section 未找到（PM 视图与工程合同均无此 section）。",
            file=sys.stderr,
        )
        sys.exit(1)
    if not has_meaningful_content(content):
        print(
            "Error: 自审记录 section 为空。请至少完成一次自审并记录结果。",
            file=sys.stderr,
        )
        sys.exit(1)

    # review 工具改为 PM 自跑推荐项；事件流仍可能含 review_completed
    # 作为审计记录，但不再做覆盖校验。
```

**关键变化**：
- `task_file` 变量已是 PM 视图路径（task.md），`read_section` 内部自动找 `.engineering.md`
- 不再用 `text` 变量做 regex 匹配——改用 parser 函数
- `has_section_content(text, name)` 这个老 helper 阶段 1 暂时保留（如果它在 task-transition.py 别处还有用），未来阶段 2 全量替换时再删

---

## 4. 验证步骤

### 4.1 单元测试

```bash
cd ${REPO_ROOT}
PYTHONPATH=scripts python3 -m unittest scripts._lib.task_parser_test -v
# 期望：11+ tests passed
```

### 4.2 现有 task-transition 测试

```bash
bash tests/test-task-transition.sh
# 期望：所有现有测试通过（v1 fixture 仍工作）
```

### 4.3 手动 e2e 验证（关键 — 修复 P0-1 验证）

```bash
mkdir -p /tmp/test-task
cat > /tmp/test-task/task-001-test.md <<'EOF'
# Task 001: Test

| | |
|---|---|
| **状态** | 执行中 |
| **分支** | task-001-test |
EOF

cat > /tmp/test-task/task-001-test.engineering.md <<'EOF'
# Task 001: Test — 工程合同

## 10. 文档偏差
无偏差

## 11. 自审记录
2026-04-29 PM 自跑 /qa 通过
EOF

PYTHONPATH=scripts python3 scripts/task-transition.py /tmp/test-task/task-001-test.md --to 待验收
echo "Exit: $?"
# 期望：exit 0（修复前会失败 — section 找不到）

# 反向：工程合同 §10 是空的 → 应该报错
cat > /tmp/test-task/task-001-test.engineering.md <<'EOF'
# Task 001: Test — 工程合同

## 10. 文档偏差

## 11. 自审记录
内容
EOF
PYTHONPATH=scripts python3 scripts/task-transition.py /tmp/test-task/task-001-test.md --to 待验收
echo "Exit: $?"
# 期望：exit 1 + 错误消息"文档偏差 section 未填写"

rm -rf /tmp/test-task
```

### 4.4 跨 worktree 跑 e2e（**spot-check #4 修正**）

模拟从 task worktree cwd 调用 main repo 的 task-transition.py：

```bash
mkdir -p /tmp/fake-task-wt
cd /tmp/fake-task-wt   # 模拟 task worktree cwd（任意非 main repo 的目录）

mkdir -p /tmp/test-task-2
cat > /tmp/test-task-2/task-001-test.md <<'EOF'
# Task 001: Test

| | |
|---|---|
| **状态** | 执行中 |
EOF

cat > /tmp/test-task-2/task-001-test.engineering.md <<'EOF'
# Task 001: Test — 工程合同

## 10. 文档偏差
无偏差

## 11. 自审记录
内容
EOF

# 从 fake task worktree 跑 main repo 的 task-transition.py
PYTHONPATH=${REPO_ROOT}/scripts \
  python3 ${REPO_ROOT}/scripts/task-transition.py \
  /tmp/test-task-2/task-001-test.md --to 待验收
echo "Exit: $?"
# 期望：exit 0
# 验证 __file__ 解析跨 cwd 工作（_lib import 不依赖 cwd）

cd -
rm -rf /tmp/fake-task-wt /tmp/test-task-2
```

---

## 5. 提交节点（两个 commit）

### Commit 1: parser + 测试

```bash
git checkout -b req-parser-foundation  # 或按现有分支约定

mkdir -p scripts/_lib
# 创建：__init__.py / task_parser.py / task_parser_test.py / _setup-pythonpath.sh

# 跑测试
PYTHONPATH=scripts python3 -m unittest scripts._lib.task_parser_test -v

# 全绿后 commit
git add scripts/_lib/
git commit -m "feat(parser): shared task parser v1/v2 双兼容 + 11 单测覆盖

- scripts/_lib/task_parser.py: detect_format / parse_field / read_section / has_meaningful_content
- scripts/_lib/__init__.py: 让 module 可被 python3 -m _lib.task_parser 调用
- scripts/_lib/_setup-pythonpath.sh: bash caller PYTHONPATH wrapper
- scripts/_lib/task_parser_test.py: 11 测试覆盖 v1/v2 + 跨文件 + 退化"
```

### Commit 2: task-transition 迁移

```bash
# 改 scripts/task-transition.py（按 §3 的 diff）
# 跑测试
bash tests/test-task-transition.sh
# 跑手动 e2e（§4.3 + §4.4 跨 worktree）

# 全绿后 commit
git add scripts/task-transition.py
git commit -m "fix(task-transition): 用 read_section 跨文件查找替换旧 regex

修复 P0-1：新格式 task 卡在「执行中→待验收」。
section 已搬到 task.engineering.md §10/§11，老 regex \`^## 文档偏差\` 找不到。
parser 自动跨 PM 视图 + 工程合同查找。"
```

### Commit 顺序约束（**spot-check #6 修正**）

**两个 commit 必须保持顺序**：

- Commit 1（parser）必须**先于** Commit 2（task-transition）merge
- 回退时也要保持顺序：先 revert Commit 2，再 revert Commit 1
- **不允许只 revert Commit 1 留 Commit 2** —— 会导致 task-transition 找不到 `_lib.task_parser` 报错（破坏比 P0-1 更严重）
- 如果想完全回到 P0-1 修复前的状态：**两个 commit 一起 revert**

```bash
# 完整回退（如 P0-1 修复有问题想回滚）：
git revert <commit-2-task-transition-sha>
git revert <commit-1-parser-sha>
# 顺序很重要 — 反过来会有 conflict
```

---

## 6. 风险点 + 回退

| 风险 | 概率 | 应对 |
|---|---|---|
| PYTHONPATH 在不同 cwd 下行为不一致（hook 可能在 task worktree 跑）| 中 | 测试时从不同 cwd 跑一遍验证；必要时改用绝对路径 import |
| `read_section` 的 next heading 边界（section 在 EOF 时）| 低 | 已在 `_extract_section` 处理 `next_m if next_m else len(text)` |
| task-transition.py 内部其他用 `text = read_text(task_file)` 的地方 | 低 | 阶段 1 仅迁移 section 检查；其他字段（status / branch）阶段 2 再迁移 |
| 现存 v1 task 文件 | 低 | parser 双兼容，旧格式继续工作；阶段 3 fixture 才区分新老 |

**回退**：两个 commit 独立可 revert。最坏情况：

```bash
git revert <commit-2-task-transition>
# task-transition 回到旧逻辑，parser 留作 dead code 等阶段 2-3 用
```

---

## 7. 完成标准

- [ ] **19 条**单测全绿（11 原 + 8 spot-check 补充）
- [ ] tests/test-task-transition.sh 全绿
- [ ] 手动 e2e §4.3（v2 task + 工程合同 §10/§11）→ transition 成功
- [ ] 反向（§10 空内容）→ 报错正确
- [ ] 跨 worktree e2e §4.4 → cwd 不影响 import
- [ ] 两个 commit message 含 P0-1 引用，便于未来 trace
- [ ] commit 顺序约束已遵守（commit 1 先 merge）

---

## 8. 阶段 1 → 阶段 2 衔接

阶段 1 完成后，parser 已就位。阶段 2（剩余 4 处迁移）可立即跟进：

| 文件 | 改动 |
|---|---|
| `scripts/check-branch.sh` | 用 `python3 -m _lib.task_parser parse_status_from_text` 替换内嵌 python 段 |
| `scripts/close-req.sh` | 用 `python3 -m _lib.task_parser get_status` 检测 open task |
| `scripts/cancel-req.sh` | 用 `python3 -m _lib.task_parser get_branch` 枚举 task |
| `scripts/build-execution-prompt.py` | 用 `_lib.task_parser.get_task_meta` 替换 `FIELD_RE` |

阶段 1 验证通过 = 阶段 2 安全开始的前提。
