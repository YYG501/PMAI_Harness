#!/usr/bin/env python3
"""校验 `.engineering.md` 工程合同行数是否在档位约束内（v2 实施）。

读 CLAUDE.md「工程结构约束」段判断档位（prototype/custom/system），按档位
对应的「文档输出深度指引」检查行数：

- prototype 档:
  - solution.engineering.md ≤300 行
  - task-NNN.engineering.md ≤200 行
- custom / system 档: 不检查（v2 §五.4 决策——等真实项目实证后再写规则）

挂载点:
- req-stage-gate skill 在 stage 3→5 闸门时跑（针对 solution.engineering.md）
- task-confirm skill 在确认门跑（针对 task-NNN.engineering.md）

用法:
    # 校验单个文件
    python3 scripts/check-engineering-doc-size.py <path-to-.engineering.md>
    # 校验整个 req 目录下的所有 .engineering.md
    python3 scripts/check-engineering-doc-size.py --req-dir <req-dir>

退出码:
    0 = 全部通过 / 档位非 prototype（不检查）
    1 = 有文件超限
    2 = 用法错 / 找不到 CLAUDE.md
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# 行数上限（仅 prototype 档生效；其他档不检查）
LIMITS_PROTOTYPE = {
    "solution.engineering.md": 300,
    "task.engineering.md": 200,  # task-NNN.engineering.md 一律按这个上限
}


def find_repo_root() -> Path:
    """优先用 git rev-parse 找仓根；失败时按 cwd 向上找 CLAUDE.md。"""
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], stderr=subprocess.DEVNULL
        )
        return Path(out.decode("utf-8").strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    cur = Path.cwd().resolve()
    while cur != cur.parent:
        if (cur / "CLAUDE.md").exists():
            return cur
        cur = cur.parent
    print("Error: 找不到仓根（无 git 也无 CLAUDE.md）", file=sys.stderr)
    print(
        "  修复：在业务仓根目录（含 CLAUDE.md）跑本脚本；"
        "或显式传 --req-dir 指向 $ACTIVE_REQ_DIR。",
        file=sys.stderr,
    )
    sys.exit(2)


def detect_gear(repo_root: Path) -> str:
    """从 CLAUDE.md「工程结构约束」段提档位。

    - 优先读 `<!-- auto-detected: <gear> -->` 标记
    - 找不到时读 `## 工程结构约束（<title>（<gear>））` 标题
    - 都找不到 → unknown
    """
    claude_md = repo_root / "CLAUDE.md"
    if not claude_md.exists():
        return "unknown"
    text = claude_md.read_text(encoding="utf-8", errors="replace")

    m = re.search(r"<!--\s*auto-detected:\s*(prototype|custom|system|unknown)\b", text)
    if m:
        return m.group(1)

    m = re.search(r"##\s*工程结构约束（[^（）]*（(prototype|custom|system)）", text)
    if m:
        return m.group(1)

    return "unknown"


def count_lines(path: Path) -> int:
    return len(path.read_text(encoding="utf-8", errors="replace").splitlines())


def classify_file(path: Path) -> str | None:
    """返回 'solution' / 'task' / None"""
    name = path.name
    if name == "solution.engineering.md":
        return "solution"
    if re.match(r"^task-[\w-]+\.engineering\.md$", name):
        return "task"
    return None


def check_file(path: Path, gear: str) -> tuple[bool, str]:
    """返回 (passed, message)。"""
    if gear != "prototype":
        return (True, f"  ⏭ {path.name} (档位 {gear} 不检查)")

    kind = classify_file(path)
    if kind is None:
        return (True, f"  ⏭ {path.name} (非 .engineering.md)")

    limit = LIMITS_PROTOTYPE["solution.engineering.md"] if kind == "solution" else LIMITS_PROTOTYPE["task.engineering.md"]
    actual = count_lines(path)

    if actual > limit:
        return (
            False,
            f"  ❌ {path.name} : {actual} 行 > {limit} 行上限\n"
            f"     原因: 工程合同膨胀（多半是重抄了 PM 视图内容）\n"
            f"     修法: 把 PM 视图已写过的部分改写为「参见 solution.md §X.Y」引用；裁剪到 ≤{limit} 行",
        )
    return (True, f"  ✅ {path.name} : {actual}/{limit} 行")


def find_eng_files(req_dir: Path) -> list[Path]:
    """收集 req 目录下所有 .engineering.md（含 tasks/ 子目录）。"""
    files: list[Path] = []
    sol = req_dir / "solution.engineering.md"
    if sol.exists():
        files.append(sol)
    tasks_dir = req_dir / "tasks"
    if tasks_dir.exists():
        files.extend(sorted(tasks_dir.glob("*.engineering.md")))
    return files


def main() -> int:
    parser = argparse.ArgumentParser(
        description="校验 .engineering.md 工程合同行数（v2 文档输出深度指引）"
    )
    parser.add_argument("paths", nargs="*", help="要校验的 .engineering.md 文件路径")
    parser.add_argument(
        "--req-dir",
        type=str,
        help="校验整个 req 目录下的所有 .engineering.md（solution + tasks/*）",
    )
    args = parser.parse_args()

    if not args.paths and not args.req_dir:
        parser.error("必须指定 paths 或 --req-dir")

    repo_root = find_repo_root()
    gear = detect_gear(repo_root)

    targets: list[Path] = []
    if args.req_dir:
        req_dir = Path(args.req_dir).resolve()
        if not req_dir.is_dir():
            print(f"Error: --req-dir 不存在: {req_dir}", file=sys.stderr)
            print(
                "  修复：检查路径拼写；"
                "active req 目录应在 requirements/active/req-NNN-<slug>/。",
                file=sys.stderr,
            )
            return 2
        targets.extend(find_eng_files(req_dir))
    for p in args.paths:
        targets.append(Path(p).resolve())

    if not targets:
        print("⏭ 无 .engineering.md 文件待校验")
        return 0

    print(f"档位: {gear}")
    if gear != "prototype":
        print(f"⏭ 档位非 prototype（{gear}），不做行数校验（v2 §五.4：等真实 {gear} 项目实证后再约束）")
        return 0

    failed = 0
    for path in targets:
        if not path.exists():
            print(f"  ⚠️  {path}: 不存在，跳过")
            continue
        passed, msg = check_file(path, gear)
        print(msg)
        if not passed:
            failed += 1

    if failed:
        print(f"\n❌ {failed} 个文件超限。修法见上方提示；裁剪后重跑本脚本。", file=sys.stderr)
        return 1

    print("\n✅ 全部通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
