"""state（前 task_parser）双兼容单测。

运行：
    cd ${REPO_ROOT}
    PYTHONPATH=scripts python3 -m unittest scripts._lib.state_test -v

原 task_parser 兼容读取 + req state 扩展 API 单测。
"""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from _lib.state import (
    detect_format,
    get_task_status,
    get_task_branch,
    get_task_meta,
    parse_status_from_text,
    read_section,
    has_meaningful_content,
    read_req_meta,
    read_task_meta,
    read_task_status,
    list_active_reqs,
    list_closed_reqs,
    list_cancelled_reqs,
    get_overall_state,
    StateReadError,
)


# Fixtures

V1_TASK_MD = """# Task 001: Test

**状态：** 待执行
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
| **状态** | 待执行 |
| **分支** | task-001-test |
| **worktree** | /path/to/wt |
| **创建时间** | 2026-04-29 |
"""

V3_TASK_MD = """# Task 001: Test

<!-- task_format: single-typed-v3 -->

| | |
|---|---|
| **状态** | 待执行 |
| **分支** | task-001-test |

## 📋 文档偏差
v3 文档偏差内容

## 🔍 自审记录
v3 自审记录内容
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

    def test_v3_when_typed_contract_marker(self):
        """：无 .engineering.md + 头部 task_format 标记 → v3。"""
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V3_TASK_MD)
            self.assertEqual(detect_format(pm), "v3")


class TestStatusParsing(unittest.TestCase):
    def test_v2_status(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V2_TASK_MD)
            self.assertEqual(get_task_status(pm), "待执行")

    def test_v1_status(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V1_TASK_MD)
            self.assertEqual(get_task_status(pm), "待执行")


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

    def test_v3_section_with_emoji_heading(self):
        """v3 单文件 typed contract：审计区标题带 emoji（## 📋 文档偏差 / ## 🔍 自审记录）。

        回归守护：§8  的 task.md.tmpl 用 emoji 标题，read_section 正则若
        不容忍 emoji 前缀 → 每个 v3 task close 转「已完成」都被拦。
        """
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V3_TASK_MD)

            found, content = read_section(pm, "文档偏差")
            self.assertTrue(found)
            self.assertIn("v3 文档偏差内容", content)

            found, content = read_section(pm, "自审记录")
            self.assertTrue(found)
            self.assertIn("v3 自审记录内容", content)

    def test_section_heading_with_parenthetical_suffix(self):
        """存量 task 标题带括号注释后缀（## 10. 文档偏差（…）） —— 也要匹配。"""
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(
                "# Task\n"
                "## 10. 文档偏差（execution agent 填写，工程层视角）\n"
                "带后缀标题的内容\n"
            )

            found, content = read_section(pm, "文档偏差")
            self.assertTrue(found)
            self.assertIn("带后缀标题的内容", content)

    def test_section_heading_not_overmatched(self):
        """正则不可过宽：`## 其他 文档偏差说明` 不是真审计段，不能误命中。"""
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(
                "# Task\n"
                "## 其他 文档偏差说明\n干扰说明段内容\n"
                "## 文档偏差\n真正的审计段内容\n"
            )
            found, content = read_section(pm, "文档偏差")
            self.assertTrue(found)
            self.assertIn("真正的审计段内容", content)
            self.assertNotIn("干扰说明段内容", content)


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
        text = "｜ **状态** ｜ 待执行 ｜"
        self.assertIsNone(parse_status_from_text(text))


class TestExceptionPaths(unittest.TestCase):
    """spot-check #2: 异常路径覆盖。"""

    def test_missing_file_raises(self):
        """文件不存在应抛 FileNotFoundError。"""
        with self.assertRaises(FileNotFoundError):
            get_task_status(Path("/nonexistent/task-001.md"))

    def test_duplicate_field_returns_first_match(self):
        """字段重复时返回第一次匹配。"""
        text = "**状态：** 待执行\n**状态：** 执行中"
        self.assertEqual(parse_status_from_text(text), "待执行")


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
                ["python3", "-m", "_lib.state", "get_status", str(pm)],
                capture_output=True,
                text=True,
                env=_CLI_ENV,
            )
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout.strip(), "待执行")

    def test_cli_read_section_not_found_exit3(self):
        with tempfile.TemporaryDirectory() as d:
            pm = Path(d) / "task-001-test.md"
            pm.write_text(V1_TASK_MD)
            result = subprocess.run(
                [
                    "python3",
                    "-m",
                    "_lib.state",
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
                "_lib.state",
                "get_status",
                "/nonexistent/task.md",
            ],
            capture_output=True,
            text=True,
            env=_CLI_ENV,
        )
        self.assertEqual(result.returncode, 1)


# ============================================================================
# state 扩展 API 单测（v3 §1 #2 实施）
# ============================================================================


REQ_META_OK = {
    "id": "req-001", "name": "demo", "branch": "req-001-demo",
    "stage": 6, "status": "active",
}


def _make_req(repo: Path, req_id: str, status: str = "active",
              stage: int = 6) -> Path:
    """Create req fixture under repo/docs/modules/<req_id>/（批 2 单读真相源）。

    批 2 起真相源 = docs/modules/<模块>/.req-meta.json。这里模块目录名直接用
    req_id（测试不关心模块名派生，只验扫描/聚合/去重逻辑）。
    """
    req_dir = repo / "docs" / "modules" / req_id
    (req_dir / "tasks").mkdir(parents=True)
    meta = {**REQ_META_OK, "id": req_id, "name": req_id,
            "branch": f"{req_id}-demo", "stage": stage, "status": status}
    (req_dir / ".req-meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    return req_dir


class TestReadReqMeta(unittest.TestCase):
    def test_strict_missing_raises(self):
        with self.assertRaises(StateReadError):
            read_req_meta(Path("/nonexistent/req"), strict=True)

    def test_tolerant_missing_returns_none(self):
        self.assertIsNone(read_req_meta(Path("/nonexistent/req"), strict=False))

    def test_corrupt_strict_raises(self):
        with tempfile.TemporaryDirectory() as d:
            req = Path(d) / "req-001"
            req.mkdir()
            (req / ".req-meta.json").write_text("{not json", encoding="utf-8")
            with self.assertRaises(StateReadError):
                read_req_meta(req, strict=True)

    def test_corrupt_tolerant_returns_none(self):
        with tempfile.TemporaryDirectory() as d:
            req = Path(d) / "req-001"
            req.mkdir()
            (req / ".req-meta.json").write_text("{not json", encoding="utf-8")
            self.assertIsNone(read_req_meta(req, strict=False))

    def test_happy_returns_dict(self):
        with tempfile.TemporaryDirectory() as d:
            req = _make_req(Path(d), "req-001")
            meta = read_req_meta(req)
            self.assertEqual(meta["id"], "req-001")
            self.assertEqual(meta["status"], "active")


class TestReadTaskMetaStatus(unittest.TestCase):
    def test_strict_missing_raises(self):
        with self.assertRaises(StateReadError):
            read_task_meta(Path("/nonexistent/task.md"), strict=True)

    def test_tolerant_missing_returns_none(self):
        self.assertIsNone(read_task_meta(Path("/nope.md"), strict=False))
        self.assertIsNone(read_task_status(Path("/nope.md"), strict=False))


class TestListActiveReqsTolerantAggregation(unittest.TestCase):
    def test_corrupt_meta_emits_warning_not_raise(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            _make_req(repo, "req-001")
            bad = repo / "docs" / "modules" / "坏模块"
            (bad).mkdir(parents=True)
            (bad / ".req-meta.json").write_text("{not json", encoding="utf-8")
            out = list_active_reqs(repo)
            ids = [i["meta"]["id"] for i in out["items"]]
            self.assertEqual(ids, ["req-001"])
            self.assertEqual(len(out["warnings"]), 1)

    def test_strict_aggregation_raises_on_corrupt(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            bad = repo / "docs" / "modules" / "坏模块"
            bad.mkdir(parents=True)
            (bad / ".req-meta.json").write_text("{not json", encoding="utf-8")
            with self.assertRaises(StateReadError):
                list_active_reqs(repo, strict=True)

    def test_skip_non_active_status(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            _make_req(repo, "req-001", status="closed")
            _make_req(repo, "req-002", status="active")
            ids = [i["meta"]["id"]
                   for i in list_active_reqs(repo)["items"]]
            self.assertEqual(ids, ["req-002"])


def _git(repo: Path, *args: str) -> str:
    """run git -C <repo> <args>，返回 stdout（仅在 unit test setup 内使用）。"""
    return subprocess.check_output(
        ["git", "-C", str(repo), *args],
        text=True, stderr=subprocess.DEVNULL,
    ).strip()


def _init_repo_with_worktrees(root: Path) -> tuple[Path, Path, Path]:
    """建一个 main 仓 + 2 个 req worktree（req-001 / req-002）。

    返回 (main, req001_wt, req002_wt)。
    """
    main = root / "main"
    main.mkdir()
    _git(main, "init", "-q")
    _git(main, "config", "user.email", "t@e")
    _git(main, "config", "user.name", "t")
    (main / "seed.md").write_text("seed")
    _git(main, "add", ".")
    _git(main, "commit", "-q", "-m", "seed")

    wt_root = root / "wts"
    wt_root.mkdir()
    req001_wt = wt_root / "req-001-demo"
    req002_wt = wt_root / "req-002-other"
    _git(main, "worktree", "add", "-q", "-b", "req-001-demo", str(req001_wt))
    _git(main, "worktree", "add", "-q", "-b", "req-002-other", str(req002_wt))

    # 在两个 req worktree 各放 active req（同名 id 模拟两 req 并行）
    _make_req(req001_wt, "req-001")
    _make_req(req002_wt, "req-002")
    return main, req001_wt, req002_wt


class TestListActiveReqsCwdAndWorktrees(unittest.TestCase):
    """v3 §1 #2 清单显式覆盖: multi active / req worktree cwd / 跨 worktree 去重。"""

    def test_multi_active_across_worktrees_deduped(self):
        with tempfile.TemporaryDirectory() as d:
            main, _r1, _t1 = _init_repo_with_worktrees(Path(d))
            out = list_active_reqs(main)
            ids = sorted(i["meta"]["id"] for i in out["items"])
            self.assertEqual(ids, ["req-001", "req-002"])

    def test_cwd_in_req_worktree_returns_only_that_req(self):
        with tempfile.TemporaryDirectory() as d:
            main, r1, _t1 = _init_repo_with_worktrees(Path(d))
            out = list_active_reqs(main, cwd=r1)
            ids = [i["meta"]["id"] for i in out["items"]]
            self.assertEqual(ids, ["req-001"])  # cwd 唯一定 req，不要被 req-002 干扰

    def test_main_repo_active_dedupes_against_worktree(self):
        """主仓 + req worktree 都暴露同 id 时，basename 去重只保留一份。"""
        with tempfile.TemporaryDirectory() as d:
            main, r1, _t1 = _init_repo_with_worktrees(Path(d))
            # main 也放一份 req-001（实际场景：用户先在 main 写 brief 然后 fork worktree）
            _make_req(main, "req-001")
            out = list_active_reqs(main)
            ids_count = {i["meta"]["id"]: 0 for i in out["items"]}
            for i in out["items"]:
                ids_count[i["meta"]["id"]] += 1
            self.assertEqual(ids_count.get("req-001"), 1)


class TestGetOverallState(unittest.TestCase):
    def test_returns_active_req_items_only(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            _make_req(repo, "req-001")
            state = get_overall_state(repo)
            self.assertEqual(len(state["active_reqs"]), 1)
            r = state["active_reqs"][0]
            self.assertEqual(r["meta"]["id"], "req-001")
            self.assertEqual(set(r.keys()), {"req_dir", "meta"})

    def test_tolerant_no_active_returns_empty(self):
        with tempfile.TemporaryDirectory() as d:
            state = get_overall_state(Path(d))
            self.assertEqual(state["active_reqs"], [])
            self.assertEqual(state["warnings"], [])


class TestCLINewSubcommands(unittest.TestCase):
    def test_cli_read_req_meta_strict_missing_exit1(self):
        result = subprocess.run(
            ["python3", "-m", "_lib.state",
             "read_req_meta", "/nonexistent/req"],
            capture_output=True, text=True, env=_CLI_ENV)
        self.assertEqual(result.returncode, 1)

    def test_cli_list_active_reqs_empty_repo(self):
        with tempfile.TemporaryDirectory() as d:
            result = subprocess.run(
                ["python3", "-m", "_lib.state", "list_active_reqs", d],
                capture_output=True, text=True, env=_CLI_ENV)
            self.assertEqual(result.returncode, 0)
            payload = json.loads(result.stdout)
            self.assertEqual(payload["items"], [])
            self.assertEqual(payload["warnings"], [])


# ---------------------------------------------------------------------------
# 真相源单读（lifecycle 迁移批 2）：docs/modules/<模块>/.req-meta.json 是唯一真相源，
# 旧 requirements/active|closed/ 扫描已删。
# ---------------------------------------------------------------------------

def _make_module(repo: Path, module: str, req_id: str,
                 status: str = "active", stage: int = 2) -> Path:
    """在 repo/docs/modules/<module>/ 建一个带 .req-meta.json 的模块（真相源）。"""
    module_dir = repo / "docs" / "modules" / module
    module_dir.mkdir(parents=True)
    meta = {"id": req_id, "name": module, "branch": f"{req_id}-{module}",
            "stage": stage, "status": status}
    (module_dir / ".req-meta.json").write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    return module_dir


class TestModulesSingleRead(unittest.TestCase):
    """批 2 单读：docs/modules/* 真相源被 list_active/closed/cancelled 读到；
    旧 requirements/active|closed/ 已不再被扫描。"""

    def test_active_read_from_modules_only(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            _make_module(repo, "能力匹配卡", "req-010", status="active")
            ids = [i["meta"]["id"] for i in list_active_reqs(repo)["items"]]
            self.assertEqual(ids, ["req-010"])

    def test_active_two_modules_listed(self):
        """两个独立模块（不同 id）→ 各一条。"""
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            _make_module(repo, "能力匹配卡", "req-001", status="active")
            _make_module(repo, "待办", "req-002", status="active")
            ids = sorted(i["meta"]["id"] for i in list_active_reqs(repo)["items"])
            self.assertEqual(ids, ["req-001", "req-002"])

    def test_legacy_requirements_active_ignored(self):
        """批 2 后旧 requirements/active/ 不再被扫描（只有 docs/modules 的算 active）。"""
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            # 旧布局（应被忽略）
            old = repo / "requirements" / "active" / "req-900-legacy"
            old.mkdir(parents=True)
            (old / ".req-meta.json").write_text(
                json.dumps({"id": "req-900", "name": "legacy", "status": "active"}),
                encoding="utf-8")
            # 新布局
            _make_module(repo, "新模块", "req-001", status="active")
            ids = [i["meta"]["id"] for i in list_active_reqs(repo)["items"]]
            self.assertEqual(ids, ["req-001"])  # req-900 不进列表

    def test_modules_skip_non_active_for_active_list(self):
        """docs/modules 里 status=closed 的不进 active 列表。"""
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            _make_module(repo, "已收尾", "req-020", status="closed")
            _make_module(repo, "在做", "req-021", status="active")
            ids = [i["meta"]["id"] for i in list_active_reqs(repo)["items"]]
            self.assertEqual(ids, ["req-021"])

    def test_closed_read_from_modules(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            _make_module(repo, "收尾模块", "req-030", status="closed", stage=4)
            ids = [i["meta"]["id"] for i in list_closed_reqs(repo)["items"]]
            self.assertEqual(ids, ["req-030"])

    def test_cancelled_read_from_modules(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            _make_module(repo, "废弃模块", "req-040", status="cancelled")
            ids = [i["meta"]["id"] for i in list_cancelled_reqs(repo)["items"]]
            self.assertEqual(ids, ["req-040"])

    def test_legacy_requirements_closed_ignored(self):
        """批 2 后旧 requirements/closed/ 不再被扫描。"""
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            old = repo / "requirements" / "closed" / "req-001-x"
            old.mkdir(parents=True)
            (old / ".req-meta.json").write_text(
                json.dumps({"id": "req-001", "name": "x", "status": "closed"}),
                encoding="utf-8")
            self.assertEqual(list_closed_reqs(repo)["items"], [])

    def test_corrupt_module_meta_emits_warning_not_raise(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            bad = repo / "docs" / "modules" / "坏模块"
            bad.mkdir(parents=True)
            (bad / ".req-meta.json").write_text("{not json", encoding="utf-8")
            out = list_active_reqs(repo)
            self.assertEqual(out["items"], [])
            self.assertEqual(len(out["warnings"]), 1)

    def test_module_without_meta_ignored(self):
        """docs/modules 下纯文档模块（无 .req-meta.json）不算 req。"""
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            doc_only = repo / "docs" / "modules" / "纯文档"
            doc_only.mkdir(parents=True)
            (doc_only / "spec.md").write_text("# spec", encoding="utf-8")
            self.assertEqual(list_active_reqs(repo)["items"], [])


if __name__ == "__main__":
    unittest.main()
