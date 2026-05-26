"""publish-to-lark 续行 rowspan 合并逻辑 — find_desc_group_ranges 单测。

确认续行 rowspan markdown 发布到飞书时,需求描述列的多行 group 被正确识别为
单个合并范围(后续 merge_desc_group_with_content 会把非锚点 cell 的内容拷贝到
锚点 cell + 清空原 cell + 调 merge_table_cells 实现"合并为一个单元格"语义)。

运行:
    cd ${REPO_ROOT}
    python3 tests/test-publish-to-lark-rowspan-merge.py -v
"""

import importlib.util
import unittest
from pathlib import Path

# scripts/publish-to-lark.py 文件名含连字符,无法 import,用 importlib 加载
SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts"
SPEC = importlib.util.spec_from_file_location(
    "publish_to_lark", SCRIPTS_DIR / "publish-to-lark.py"
)
publish_to_lark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publish_to_lark)

find_desc_group_ranges = publish_to_lark.find_desc_group_ranges


class FindDescGroupRangesTest(unittest.TestCase):
    """find_desc_group_ranges: 末列(需求描述)的合并范围识别。

    锚点行 = 任一前 N-1 列非空; 续行 = 前 N-1 列全空。
    单行 group 不合并; 多行 group 才合并。
    """

    def test_rowspan_single_group_3_rows(self):
        """续行 rowspan 3 行 — 标准 prd.md 写法,应识别为单个 range。"""
        grid = [
            ["列表", "查看", "角色A", "1. 第一条规则"],
            ["", "", "", "2. 第二条规则"],
            ["", "", "", "3. 第三条规则"],
        ]
        ranges = find_desc_group_ranges(grid, existing=set())
        self.assertEqual(len(ranges), 1)
        self.assertEqual(ranges[0]["row_start_index"], 0)
        self.assertEqual(ranges[0]["row_end_index"], 3)
        self.assertEqual(ranges[0]["column_start_index"], 3)
        self.assertEqual(ranges[0]["column_end_index"], 4)

    def test_multiple_groups_in_one_table(self):
        """同一表格里两个 row group,各自合并不串台。"""
        grid = [
            ["列表", "查看", "角色A", "1. 规则 A1"],
            ["", "", "", "2. 规则 A2"],
            ["操作", "创建", "角色B", "1. 规则 B1"],
            ["", "", "", "2. 规则 B2"],
            ["", "", "", "3. 规则 B3"],
        ]
        ranges = find_desc_group_ranges(grid, existing=set())
        self.assertEqual(len(ranges), 2)
        # group 1: rows 0-1
        self.assertEqual(ranges[0]["row_start_index"], 0)
        self.assertEqual(ranges[0]["row_end_index"], 2)
        # group 2: rows 2-4
        self.assertEqual(ranges[1]["row_start_index"], 2)
        self.assertEqual(ranges[1]["row_end_index"], 5)

    def test_single_row_group_not_merged(self):
        """无续行的单行 group 不应该合并(防误合并)。"""
        grid = [
            ["列表", "查看", "角色A", "1. 单条规则"],
            ["操作", "创建", "角色B", "1. 另一条规则"],
        ]
        ranges = find_desc_group_ranges(grid, existing=set())
        self.assertEqual(len(ranges), 0)

    def test_empty_grid_no_crash(self):
        """空 grid 不崩。"""
        self.assertEqual(find_desc_group_ranges([], existing=set()), [])

    def test_single_column_no_merge(self):
        """单列表格(cols < 2)不参与本逻辑。"""
        grid = [["单列"], [""], [""]]
        ranges = find_desc_group_ranges(grid, existing=set())
        self.assertEqual(ranges, [])

    def test_existing_conflict_filtered(self):
        """与 existing(前 N-1 列已 merge 的 cell)冲突的 range 被过滤。

        现实场景:前 N-1 列合并范围已被 find_merge_ranges 注册到 existing 后,
        本函数应跳过那些 row × col 已被标记的格。但 desc col 在末列,与前 N-1
        列合并的 (row, col<N-1) 不会冲突 —— 本测试构造一个人造冲突验证过滤逻辑。
        """
        grid = [
            ["列表", "查看", "角色A", "1. 第一条"],
            ["", "", "", "2. 第二条"],
        ]
        # 人造一个 existing 集合,声称 row 0 col 3 已被合并 → 应过滤掉本 range
        existing = {(0, 3)}
        ranges = find_desc_group_ranges(grid, existing=existing)
        self.assertEqual(ranges, [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
