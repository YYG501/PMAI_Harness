"""state（前 task_parser）双兼容单测。

运行：
    cd ${REPO_ROOT}
    PYTHONPATH=scripts python3 -m unittest scripts._lib.state_test -v

19 原测试（task_parser 时代）+ state 扩展 API 单测（末尾段）。
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
    read_task_events,
    read_task_plan,
    list_tasks,
    list_active_reqs,
    get_overall_state,
    discarded_task_ids,
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
        """delta-3 §2.7：无 .engineering.md + 头部 task_format 标记 → v3。"""
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

        回归守护：§8 delta-3 的 task.md.tmpl 用 emoji 标题，read_section 正则若
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
    """Create active req fixture under repo/requirements/active/<req_id>/"""
    req_dir = repo / "requirements" / "active" / req_id
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


class TestReadTaskEvents(unittest.TestCase):
    def test_missing_returns_empty(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(read_task_events(Path(d), "task-001"), [])

    def test_skip_bad_json_lines(self):
        with tempfile.TemporaryDirectory() as d:
            events_dir = Path(d) / ".runs" / "events"
            events_dir.mkdir(parents=True)
            (events_dir / "task-001.jsonl").write_text(
                '{"event":"a"}\n{not json}\n{"event":"b"}\n',
                encoding="utf-8")
            evs = read_task_events(Path(d), "task-001")
            self.assertEqual([e["event"] for e in evs], ["a", "b"])

    def test_tail_returns_last_n(self):
        with tempfile.TemporaryDirectory() as d:
            events_dir = Path(d) / ".runs" / "events"
            events_dir.mkdir(parents=True)
            (events_dir / "task-001.jsonl").write_text(
                '{"event":"a"}\n{"event":"b"}\n{"event":"c"}\n',
                encoding="utf-8")
            self.assertEqual(
                [e["event"] for e in read_task_events(Path(d), "task-001", tail=2)],
                ["b", "c"])


class TestReadTaskPlan(unittest.TestCase):
    def test_missing_returns_none(self):
        with tempfile.TemporaryDirectory() as d:
            req = Path(d) / "req-001"
            req.mkdir()
            self.assertIsNone(read_task_plan(req))

    def test_parses_planning_table(self):
        with tempfile.TemporaryDirectory() as d:
            req = Path(d) / "req-001"
            req.mkdir()
            (req / "task-plan.md").write_text(
                "# Plan\n"
                "| ID | 标题 |\n"
                "|---|---|\n"
                "| task-001 | 一 |\n"
                "| task-002 | 二 |\n"
                "\n## 变更记录\n"
                "| task-003 | 不应被解析 |\n",
                encoding="utf-8")
            plan = read_task_plan(req)
            ids = [t["id"] for t in plan["tasks"]]
            self.assertEqual(ids, ["task-001", "task-002"])


class TestListTasks(unittest.TestCase):
    def test_skips_engineering_md(self):
        with tempfile.TemporaryDirectory() as d:
            req = _make_req(Path(d), "req-001")
            (req / "tasks" / "task-001-demo.md").write_text(
                "# Task 001\n\n| **状态** | 执行中 |\n| **分支** | task-001-demo |\n",
                encoding="utf-8")
            (req / "tasks" / "task-001-demo.engineering.md").write_text(
                "engineering only\n", encoding="utf-8")
            tasks = list_tasks(req)
            self.assertEqual(len(tasks), 1)
            self.assertEqual(tasks[0]["id"], "task-001")

    def test_missing_tasks_dir_returns_empty(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(list_tasks(Path(d) / "no-such-req"), [])


class TestDiscardedTaskIds(unittest.TestCase):
    def test_picks_up_discarded_dir(self):
        with tempfile.TemporaryDirectory() as d:
            req = _make_req(Path(d), "req-001")
            (req / "tasks" / "discarded").mkdir()
            (req / "tasks" / "discarded" / "task-002-old.md").write_text("x")
            self.assertEqual(discarded_task_ids(req), {"task-002"})


class TestListActiveReqsTolerantAggregation(unittest.TestCase):
    def test_corrupt_meta_emits_warning_not_raise(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            _make_req(repo, "req-001")
            bad = repo / "requirements" / "active" / "req-bad"
            (bad).mkdir(parents=True)
            (bad / ".req-meta.json").write_text("{not json", encoding="utf-8")
            out = list_active_reqs(repo)
            ids = [i["meta"]["id"] for i in out["items"]]
            self.assertEqual(ids, ["req-001"])
            self.assertEqual(len(out["warnings"]), 1)

    def test_strict_aggregation_raises_on_corrupt(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            bad = repo / "requirements" / "active" / "req-bad"
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
    """建一个 main 仓 + 2 个 req worktree（req-001 / req-002）+ 1 个 task worktree（task-001 fork req-001）。

    返回 (main, req001_wt, task001_wt)。
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
    task001_wt = wt_root / "task-001-demo"
    _git(main, "worktree", "add", "-q", "-b", "req-001-demo", str(req001_wt))
    _git(main, "worktree", "add", "-q", "-b", "req-002-other", str(req002_wt))
    _git(main, "worktree", "add", "-q", "-b", "task-001-demo", str(task001_wt))

    # 在两个 req worktree 各放 active req（同名 id 模拟两 req 并行）
    _make_req(req001_wt, "req-001")
    _make_req(req002_wt, "req-002")
    return main, req001_wt, task001_wt


class TestListActiveReqsCwdAndWorktrees(unittest.TestCase):
    """v3 §1 #2 清单显式覆盖: multi active / task worktree cwd / 跨 worktree 去重。"""

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

    def test_cwd_in_task_worktree_finds_sibling_reqs(self):
        with tempfile.TemporaryDirectory() as d:
            main, _r1, t1 = _init_repo_with_worktrees(Path(d))
            out = list_active_reqs(main, cwd=t1)
            ids = sorted(i["meta"]["id"] for i in out["items"])
            # task worktree 自身 active/ 为空 → 从兄弟 req worktree 拿，应该看到两个 req
            self.assertEqual(ids, ["req-001", "req-002"])

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
    def test_pending_spec_diff(self):
        with tempfile.TemporaryDirectory() as d:
            repo = Path(d)
            req = _make_req(repo, "req-001")
            (req / "task-plan.md").write_text(
                "| ID | 标题 |\n|---|---|\n"
                "| task-001 | 一 |\n| task-002 | 二 |\n| task-003 | 三 |\n",
                encoding="utf-8")
            # spec 了 task-001
            (req / "tasks" / "task-001-demo.md").write_text(
                "# Task\n\n| **状态** | 已完成 |\n", encoding="utf-8")
            # discard 了 task-003
            (req / "tasks" / "discarded").mkdir()
            (req / "tasks" / "discarded" / "task-003-old.md").write_text("x")
            state = get_overall_state(repo)
            self.assertEqual(len(state["active_reqs"]), 1)
            r = state["active_reqs"][0]
            self.assertEqual(len(r["tasks"]), 1)
            self.assertEqual(
                [p["id"] for p in r["pending_spec"]], ["task-002"])
            self.assertEqual(r["discarded_ids"], ["task-003"])

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


if __name__ == "__main__":
    unittest.main()
