#!/usr/bin/env python3
"""Build execution prompt envelope for non-claude-code executors.

输出执行信封：task id / 路径 / worktree / 分支 / 固定执行指令 + task 文件「执行区」。

v3 单文件 typed contract（delta-3）：
  - task 文件单文件分三区（PM 确认区 / 执行区 / 审计区），由 region 标记界定。
  - 信封只抽 task 文件「执行区」（`<!-- region: EXEC begin -->` 到
    `<!-- region: EXEC end -->` 之间），inject 进 prompt。
  - 信封**不带** PM 确认区 / 审计区 —— 保持旧双文件「executor 只见工程内容」边界：
    PM 确认是 PM 的事、审计区是收尾的事，executor 拿到的就是实现依据。

为什么抽执行区而非整文件：
  - PM 确认区 / 审计区对 executor 是噪音，且 PM 确认区有 binding-contract 语义，
    不该进 executor 可改的实现 prompt。
  - 抽执行区靠 region 标记（稳定锚点），不靠 section 名 —— 模板章节改名不破。

v2 旧双文件 task（有 .engineering.md）：保留兼容读路径，信封列两文件路径，
  提示按工程合同 §3/§4/§5 读，不 splice 内容（两文件是 single source of truth）。

v1 旧单文件 task（无 .engineering.md + 无 task_format 标记）：退化版指令，
  信封只列文件路径，提示按旧 section 读必读 / 范围 / 验收。
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

from _lib.state import get_task_meta, engineering_path, detect_format


# region 标记（delta-3 单文件 typed contract 三区界定）
_EXEC_BEGIN = "<!-- region: EXEC begin -->"
_EXEC_END = "<!-- region: EXEC end -->"


def derive_eng_path(pm_view: Path) -> Path:
    """保留向后兼容名称——内部委托到 state.engineering_path。"""
    return engineering_path(pm_view)


def extract_exec_region(text: str) -> str | None:
    """抽 v3 单文件 typed contract 的「执行区」内容。

    返回 EXEC begin / end 标记之间的内容（去首尾空白）；未找到成对标记返回 None。
    """
    begin = text.find(_EXEC_BEGIN)
    if begin < 0:
        return None
    begin += len(_EXEC_BEGIN)
    end = text.find(_EXEC_END, begin)
    if end < 0:
        return None
    return text[begin:end].strip()


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


def build_prompt(task_file: Path) -> str:
    text = task_file.read_text(encoding="utf-8")
    # 用 _lib.state 三态兼容读字段
    meta = get_task_meta(task_file)
    fmt = detect_format(task_file)

    worktree_field = (meta.get("worktree") or "").strip()
    if worktree_field and worktree_field not in (
        "（执行时由 create-task-worktree.sh 填写）",
    ):
        worktree = Path(worktree_field).expanduser()
    else:
        worktree = task_file.parent.parent.parent
    worktree_root = git_show_toplevel(worktree) if worktree.exists() else str(worktree)
    branch = (
        git_current_branch(Path(worktree_root)) if Path(worktree_root).exists() else "unknown"
    )

    task_title_match = re.search(r"^#\s+Task.+$", text, re.MULTILINE)
    task_title = (
        task_title_match.group(0).lstrip("#").strip() if task_title_match else task_file.stem
    )

    out: list[str] = []
    out.append("# 执行上下文")
    out.append("")
    out.append(f"- task: {task_id_from_filename(task_file)}")
    out.append(f"- task 标题：{task_title}")

    if fmt == "v3":
        # v3 单文件 typed contract —— 信封 1 路径，inject「执行区」。
        out.append(f"- task 文件：{task_file.resolve()}")
        out.append(f"- task worktree：{worktree_root}")
        out.append(f"- 当前分支：{branch}")
        out.append("")
        out.append("# 执行指令")
        out.append("")
        out.append(
            "1. 下方「实现依据（执行区）」是 task 文件执行区原文 —— "
            "你的全部实现规格、设计引用、约束都在其中。"
        )
        out.append("2. 按执行区「🚦 启动前必读」逐条加载所列文档。")
        out.append(
            "3. 按执行区「🔧 实现规格」+「🧩 实现设计引用」实现，"
            "遵守「⚠️ 约束与易错」。"
        )
        out.append("4. 自审：对照执行区「✔️ 工程层验收」逐条勾选。")
        out.append(
            "5. 写回：在 task 文件「📁 历史档案 → 执行日志」追加执行报告；"
            "偏差写「📋 文档偏差」表。"
        )
        out.append("")
        out.append("# 写回与边界")
        out.append("")
        out.append(
            "- 改动保持 **unstaged**，禁止 `git add` / `git commit` / `git checkout`"
            "（由 orchestrator 统一处理）"
        )
        out.append("- 禁止写 task worktree 外的任何路径")
        out.append("- 执行区「📦 范围」未列入的产品区域 / 文件不要动、不要新建")
        out.append("- gitignore 匹配的生成物（`.next/`、`dist/`、`node_modules/` 等）自动忽略")
        out.append("")
        exec_region = extract_exec_region(text)
        out.append("# 实现依据（执行区）")
        out.append("")
        if exec_region:
            out.append(exec_region)
        else:
            out.append(
                "（⚠️ 未能在 task 文件中定位执行区 region 标记 —— "
                "请直接打开 task 文件读「执行区」全部 section。）"
            )
        return "\n".join(out) + "\n"

    # v2 / v1 旧格式 —— 兼容读路径，信封只列路径，不 splice 内容。
    eng_path = derive_eng_path(task_file)
    has_eng = fmt == "v2" and eng_path.exists()

    out.append(f"- PM 视图（业务真相）：{task_file.resolve()}")
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
    parser.add_argument("task_file", help="Path to task file (.md, single-file typed contract)")
    args = parser.parse_args()

    task_file = Path(args.task_file)
    if not task_file.exists():
        print(f"Error: task file not found: {task_file}", file=sys.stderr)
        sys.exit(1)

    sys.stdout.write(build_prompt(task_file))


if __name__ == "__main__":
    main()
