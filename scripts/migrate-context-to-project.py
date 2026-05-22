#!/usr/bin/env python3
"""migrate-context-to-project.py — 消费仓一次性迁移：docs/CONTEXT.md → docs/PROJECT.md

框架把项目级文档 CONTEXT.md 改名为 PROJECT.md（与 GSD 的命名层级对齐 ——
GSD 的 CONTEXT.md 是 phase 级、PROJECT.md 是项目级；我们原来用 CONTEXT.md
装项目级内容，撞名错层）。

框架同步只同步 scripts/skills/templates/agents，不碰业务实例文档 —— 已有
消费仓需跑本脚本一次：
  1. git mv docs/CONTEXT.md → docs/PROJECT.md
  2. 修业务文档（CLAUDE.md / docs/ / requirements/ 下 git-tracked 的 .md）
     里的 CONTEXT.md 引用
不碰 .claude/（框架同步资产，已随同步更新为 PROJECT.md）。

幂等：已是 docs/PROJECT.md 时安全跳过改名，仅扫剩余引用。
新建的消费仓（init-project 起手即 PROJECT.md）跑本脚本是 no-op。
"""
import subprocess
import sys
from pathlib import Path


def main() -> None:
    root = Path(
        subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], text=True
        ).strip()
    )
    ctx = root / "docs" / "CONTEXT.md"
    proj = root / "docs" / "PROJECT.md"

    # 1. 文件改名
    if ctx.exists() and proj.exists():
        print(
            "⚠️  docs/CONTEXT.md 与 docs/PROJECT.md 同时存在 —— 人工合并后重跑",
            file=sys.stderr,
        )
        sys.exit(1)
    if ctx.exists():
        subprocess.run(
            ["git", "-C", str(root), "mv", "docs/CONTEXT.md", "docs/PROJECT.md"],
            check=True,
        )
        print("✓ docs/CONTEXT.md → docs/PROJECT.md")
    elif proj.exists():
        print("ℹ️  已是 docs/PROJECT.md，跳过改名")
    else:
        print("ℹ️  无 docs/CONTEXT.md（可能尚未跑 project-solution）—— 仅扫引用")

    # 2. 修业务文档引用（git-tracked 的 .md，排除 .claude/ —— 那是框架同步资产）
    tracked = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "*.md"], text=True
    ).splitlines()
    patched = 0
    for rel in tracked:
        if rel.startswith(".claude/"):
            continue
        f = root / rel
        if not f.exists():
            continue
        text = f.read_text(encoding="utf-8")
        if "CONTEXT.md" in text:
            f.write_text(text.replace("CONTEXT.md", "PROJECT.md"), encoding="utf-8")
            patched += 1
            print(f"✓ 修引用: {rel}")

    print(f"完成（{patched} 个文件修引用）。请 git diff 审查后 commit。")


if __name__ == "__main__":
    main()
