#!/usr/bin/env python3
"""Pre-commit gate: 拦截 docs/ 顶层新增文件不在归位约定白名单内。

防消费仓 docs/ 顶层积累错位 / 重复 / 过期文件（参考 CLAUDE.md 「## 根目录与 docs/ 归位约定」）。

逻辑：
  对每个 staged 的新增 `docs/<basename>.md`（不含 docs/modules/, docs/archive/, 子目录文件）：
    1. 在静态白名单（docs/ 顶层索引）→ 跳过
    2. 在 .docs-toplevel-allow 自定义白名单（每行一个 basename，#开头注释）→ 跳过
    3. 否则拦下 + 提示三种归位路径

退出码：
  0 = 全部 OK 或无 docs/ 顶层新增 staged
  1 = 至少一个错位文件 — PM 须确认归位

Escape hatch:
  - `git commit --no-verify`（git 内置）
  - PM 想长期放行：把 basename 加进 `.docs-toplevel-allow`

被调用方：`.git/hooks/pre-commit`（由 init-project / install-hooks 安装）。

测试模式：`--from-paths file1 file2 ...` 跳过 git diff，直接用给定的路径列表。
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

# docs/ 顶层只保留索引；项目主文件放仓库根目录。
STATIC_ALLOW = {
    "INDEX.md",
    "CONTEXT.md",  # 老项目兼容（migrate-context-to-project.py 跑前）
}


def load_repo_allow(repo_root: Path) -> set[str]:
    """读 .docs-toplevel-allow（PM 自定义白名单），缺则空 set。"""
    f = repo_root / ".docs-toplevel-allow"
    if not f.exists():
        return set()
    out = set()
    for line in f.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        out.add(line)
    return out


def get_staged_added() -> list[str]:
    """git staged 新增（A）文件列表。"""
    result = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=A"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line]


def filter_toplevel_docs(paths: list[str]) -> list[str]:
    """只留 docs/<basename>.md 顶层 .md 新增。

    排除：
      - docs/modules/... 子目录
      - docs/archive/... 子目录
      - 任意 docs/<子目录>/... 子目录文件（深度 ≥ 2）
      - 非 .md 文件（图片等）
    """
    out = []
    for p in paths:
        parts = p.split("/")
        if len(parts) != 2:
            continue  # 不是 docs/<file> 形式（depth 2 — top level）
        if parts[0] != "docs":
            continue
        if not parts[1].endswith(".md"):
            continue
        out.append(parts[1])  # 只留 basename
    return out


def check(repo_root: Path, paths: list[str]) -> int:
    toplevel = filter_toplevel_docs(paths)
    if not toplevel:
        return 0

    repo_allow = load_repo_allow(repo_root)
    allowed = STATIC_ALLOW | repo_allow

    violators = sorted(set(toplevel) - allowed)
    if not violators:
        return 0

    print(
        "❌ pre-commit: docs/ 顶层新增文件不在归档约定白名单内：",
        file=sys.stderr,
    )
    for v in violators:
        print(f"    docs/{v}", file=sys.stderr)
    print(
        "\n   按 CLAUDE.md 「## 根目录与 docs/ 归位约定」归位：",
        file=sys.stderr,
    )
    print(
        "     • 模块级讨论 / 决策 / 规格 → docs/modules/<模块>/",
        file=sys.stderr,
    )
    print(
        "     • PRD / 功能需求 / 功能描述 / 功能规格 / 功能评审稿 → docs/modules/<按内容命名>.md",
        file=sys.stderr,
    )
    print(
        "     • 过程档案 / 一次性 review / 临时分析 / 被取代旧文件 → docs/archive/",
        file=sys.stderr,
    )
    print(
        "     • 产品定位 / 现状 / 规则 / 视觉 / 待办主文件 → 仓库根目录",
        file=sys.stderr,
    )
    print(
        "     • 确为项目级业务概览（如 ops-platform-unification.md）→ 把 basename 加进 .docs-toplevel-allow 放行",
        file=sys.stderr,
    )
    print(
        "\n   救火绕过：git commit --no-verify",
        file=sys.stderr,
    )
    return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--from-paths",
        nargs="*",
        default=None,
        help="跳过 git diff，直接用给定路径列表（测试模式）",
    )
    parser.add_argument(
        "--repo-root",
        default=None,
        help="仓根路径（默认自动检测 git rev-parse）",
    )
    args = parser.parse_args()

    if args.repo_root:
        repo_root = Path(args.repo_root).resolve()
    else:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            print("⚠️  非 git 仓，跳过 docs/ 顶层检测", file=sys.stderr)
            return 0
        repo_root = Path(result.stdout.strip())

    if args.from_paths is not None:
        paths = args.from_paths
    else:
        paths = get_staged_added()

    return check(repo_root, paths)


if __name__ == "__main__":
    sys.exit(main())
