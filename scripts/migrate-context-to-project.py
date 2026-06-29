#!/usr/bin/env python3
"""migrate-context-to-project.py — 消费仓一次性迁移：旧项目级文档 → PRODUCT.md

框架把项目级文档统一命名为 PRODUCT.md（与 PRODUCT-STATE.md / PRODUCT-RULES.md
三兄弟对齐）。历史上这个文件用过两个旧名：
  - 更早：docs/CONTEXT.md（撞 GSD 的 phase 级命名，错层）
  - 上一版：docs/PROJECT.md（"项目"口径，但装的是产品定位/用户/术语 —— 名实不符）

框架同步只同步 scripts/skills/templates/agents，不碰业务实例文档 —— 已有
消费仓需跑本脚本一次：
  1. git mv 旧名（CONTEXT.md 或 PROJECT.md）→ PRODUCT.md
  2. 修业务文档（CLAUDE.md / docs/ / requirements/ 下 git-tracked 的 .md）
     里对旧名的引用
不碰 .claude/（框架同步资产，已随同步更新为 PRODUCT.md）。

幂等：已是 PRODUCT.md 时安全跳过改名，仅扫剩余引用。
新建的消费仓（init-project 起手即 PRODUCT.md）跑本脚本是 no-op。
"""
import subprocess
import sys
from pathlib import Path

# 旧名 → 新名，按优先级（CONTEXT 更老，PROJECT 上一版）
OLD_NAMES = ["CONTEXT.md", "PROJECT.md"]
NEW_NAME = "PRODUCT.md"


def main() -> None:
    root = Path(
        subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"], text=True
        ).strip()
    )
    docs = root / "docs"
    new = docs / NEW_NAME
    existing_old = [n for n in OLD_NAMES if (docs / n).exists()]

    # 1. 文件改名
    if existing_old and new.exists():
        print(
            f"⚠️  docs/{NEW_NAME} 与旧名 {', '.join('docs/' + n for n in existing_old)} "
            "同时存在 —— 人工合并后重跑",
            file=sys.stderr,
        )
        sys.exit(1)
    if existing_old:
        old = existing_old[0]
        subprocess.run(
            ["git", "-C", str(root), "mv", f"docs/{old}", f"docs/{NEW_NAME}"],
            check=True,
        )
        print(f"✓ docs/{old} → docs/{NEW_NAME}")
    elif new.exists():
        print(f"ℹ️  已是 docs/{NEW_NAME}，跳过改名")
    else:
        print(f"ℹ️  无旧名文档（可能尚未跑 direction）—— 仅扫引用")

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
        new_text = text
        for old in OLD_NAMES:
            new_text = new_text.replace(old, NEW_NAME)
        if new_text != text:
            f.write_text(new_text, encoding="utf-8")
            patched += 1
            print(f"✓ 修引用: {rel}")

    print(f"完成（{patched} 个文件修引用）。请 git diff 审查后 commit。")


if __name__ == "__main__":
    main()
