"""task_parser 双兼容单测。

运行：
    cd ${REPO_ROOT}
    PYTHONPATH=scripts python3 -m unittest scripts._lib.task_parser_test -v

11 原测试 + 8 spot-check 补充 = 19 条。
"""

import os
import subprocess
import tempfile
import unittest
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


# CLI subprocess env helper（保证测试用的 PYTHONPATH 与父进程一致）
_CLI_ENV = {**os.environ, "PYTHONPATH": str(Path(__file__).resolve().parent.parent)}


# ============================================================================
# 11 原测试
# ============================================================================


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

    def test_section_terminated_by_horizontal_rule(self):
        """fixture 里用 `---` 作 section 分隔符——content 应在 `---` 处截断。"""
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(
                "# Task\n\n"
                "## 文档偏差\n无偏差\n\n---\n\n"
                "## 自审记录\nfilled\n"
            )

            found, content = read_section(pm, "文档偏差")
            self.assertTrue(found)
            self.assertIn("无偏差", content)
            self.assertNotIn("自审", content)
            self.assertNotIn("---", content)  # 截断在 --- 之前

    def test_empty_section_terminated_by_hr_returns_empty(self):
        """空 section 后接 `---` → content strip 后为空 → has_meaningful_content False。"""
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(
                "# Task\n\n"
                "## 文档偏差\n\n\n---\n\n"
                "## 自审记录\nfilled\n"
            )

            found, content = read_section(pm, "文档偏差")
            self.assertTrue(found)
            self.assertEqual(content, "")  # strip 后为空
            self.assertFalse(has_meaningful_content(content))


class TestCLIExitCodes(unittest.TestCase):
    """spot-check #2: CLI 入口的 exit code 校验。"""

    def test_cli_get_status_v2(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V2_TASK_MD)
            result = subprocess.run(
                ["python3", "-m", "_lib.task_parser", "get_status", str(pm)],
                capture_output=True,
                text=True,
                env=_CLI_ENV,
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout.strip(), "待确认")

    def test_cli_read_section_not_found_exit3(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V1_TASK_MD)
            result = subprocess.run(
                [
                    "python3",
                    "-m",
                    "_lib.task_parser",
                    "read_section",
                    str(pm),
                    "不存在的_section",
                ],
                capture_output=True,
                text=True,
                env=_CLI_ENV,
            )
            self.assertEqual(result.returncode, 3)

    def test_cli_missing_file_exit1(self):
        result = subprocess.run(
            [
                "python3",
                "-m",
                "_lib.task_parser",
                "get_status",
                "/nonexistent/task.md",
            ],
            capture_output=True,
            text=True,
            env=_CLI_ENV,
        )
        self.assertEqual(result.returncode, 1)


if __name__ == "__main__":
    unittest.main()
