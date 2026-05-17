#!/usr/bin/env python3
"""Build execution prompt envelope for non-claude-code executors.

输出薄信封：task id / 两个文件绝对路径 / worktree / 分支 / 固定执行指令。
不再 inject 任何文件内容；执行者按指令自己读 PM 视图 + 工程合同。

为什么不 splice 文件内容：
  - 文件是 single source of truth；splice 出的副本会和文件 drift（lazy sync 框架已承认这点）
  - splice 设计耦合 section 名 → 模板章节改名就破，正是历史 bug 来源
  - cursor-agent / codex 都有 Read 工具，按路径读文件是它们的本职

旧格式 task（无 .engineering.md）走退化版指令：信封只列 PM 视图路径，提示按旧 section 读必读 / 范围 / 验收。
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# 让 _lib 可以 import（build-execution-prompt.py 自身在 scripts/，_lib 是同级子目录）
_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.state import get_task_meta, engineering_path


def derive_eng_path(pm_view: Path) -> Path:
    """保留向后兼容名称——内部委托到 state.engineering_path。"""
    return engineering_path(pm_view)


def git_show_toplevel(worktree: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(worktree), "rev-parse", "--show-toplevel"], text=True
        ).strip()
    except Exception:
        return str(worktree)


def git_current_branch(worktree: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(worktree), "rev-parse", "--abbrev-ref", "HEAD"], text=True
        ).strip()
    except Exception:
        return "unknown"


def task_id_from_filename(pm_view: Path) -> str:
    m = re.match(r"^(task-\d+)", pm_view.stem)
    return m.group(1) if m else pm_view.stem


def build_prompt(pm_view: Path) -> str:
    text = pm_view.read_text(encoding="utf-8")
    # 用 _lib.state 双兼容 v1/v2 读字段（替换原 read_frontmatter_fields）
    meta = get_task_meta(pm_view)

    worktree_field = (meta.get("worktree") or "").strip()
    if worktree_field and worktree_field not in (
        "（执行时由 create-task-worktree.sh 填写）",
    ):
        worktree = Path(worktree_field).expanduser()
    else:
        worktree = pm_view.parent.parent.parent
    worktree_root = git_show_toplevel(worktree) if worktree.exists() else str(worktree)
    branch = (
        git_current_branch(Path(worktree_root)) if Path(worktree_root).exists() else "unknown"
    )

    task_title_match = re.search(r"^#\s+Task.+$", text, re.MULTILINE)
    task_title = (
        task_title_match.group(0).lstrip("#").strip() if task_title_match else pm_view.stem
    )

    eng_path = derive_eng_path(pm_view)
    has_eng = eng_path.exists()

    out: list[str] = []
    out.append("# 执行上下文")
    out.append("")
    out.append(f"- task: {task_id_from_filename(pm_view)}")
    out.append(f"- task 标题：{task_title}")
    out.append(f"- PM 视图（业务真相）：{pm_view.resolve()}")
    if has_eng:
        out.append(f"- 工程合同（实现真相）：{eng_path.resolve()}")
    else:
        out.append("- 工程合同：（不存在 — 旧格式 task，所有信息都在 PM 视图）")
    out.append(f"- task worktree：{worktree_root}")
    out.append(f"- 当前分支：{branch}")
    out.append("")

    out.append("# 执行指令")
    out.append("")
    if has_eng:
        out.append("1. **完整读** PM 视图与工程合同两个文件（路径在上方）。")
        out.append("2. 按工程合同 §3「启动前必读」逐条加载所列文档。")
        out.append(
            "3. 按工程合同 §4「功能清单工程版」+ §5「实现指引」实现，"
            "遵守 §6「易错点 / 禁止项」与 §7「review 沉淀」。"
        )
        out.append(
            "4. 自审：PM 视图「✅ 验收清单（PM 走查）」+ 工程合同 §9「工程层验收清单」。"
        )
        out.append(
            "5. 写回：PM 视图「📁 历史档案 - 执行日志」追加执行报告；"
            "工程层偏差写工程合同 §10「文档偏差」。"
        )
    else:
        out.append("1. **完整读** PM 视图文件（路径在上方）。")
        out.append("2. 按 PM 视图「启动前必读」逐条加载所列文档。")
        out.append("3. 按「任务描述 / 执行范围 / 验收标准」实现。")
        out.append("4. 自审：对照 PM 视图「验收标准」逐条勾选。")
        out.append(
            "5. 写回：在 PM 视图「执行日志」section 追加执行报告；"
            "偏差写「文档偏差」section。"
        )
    out.append("")

    out.append("# 写回与边界")
    out.append("")
    out.append(
        "- 改动保持 **unstaged**，禁止 `git add` / `git commit` / `git checkout`"
        "（由 orchestrator 统一处理）"
    )
    out.append("- 禁止写 task worktree 外的任何路径")
    if has_eng:
        out.append(
            "- 不在 PM 视图「📦 范围 - 改」列出的产品区域不要动；"
            "工程合同未列入的文件不要新建"
        )
    else:
        out.append("- 严守 PM 视图「执行范围」声明的 allowlist；未在 allowlist 的文件不要动")
    out.append("- gitignore 匹配的生成物（`.next/`、`dist/`、`node_modules/` 等）自动忽略")

    return "\n".join(out) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Build execution prompt envelope")
    parser.add_argument("task_file", help="Path to task PM view (.md, not .engineering.md)")
    args = parser.parse_args()

    pm_view = Path(args.task_file)
    if not pm_view.exists():
        print(f"Error: task file not found: {pm_view}", file=sys.stderr)
        sys.exit(1)

    sys.stdout.write(build_prompt(pm_view))


if __name__ == "__main__":
    main()
