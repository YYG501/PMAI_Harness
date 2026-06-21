#!/usr/bin/env python3
"""索引漂移检测：docs/ 顶层实存文档 vs PRODUCT-STATE 索引（治痛②"脊柱入口看不到实存文档"）。

背景（「分档运行与沉淀层」设计 F6）：沉淀时"顺手补索引"只治沉淀新建的文档；
PM 纯手动新建的 docs/ 野文档仍会漏挂。本检测独立扫一遍，把"实存但 PRODUCT-STATE
索引没引到"的顶层文档报出来，由 new-req 起步顺带跑、提示 PM 是否补挂（不阻塞、advisory）。

判定：扫 docs/ 顶层 *.md（不含已知核心、不含点开头、不含归档/requirements），
      若其文件名在 docs/PRODUCT-STATE.md 全文里找不到提及 → 算"未挂索引"。

输出：每行一个未挂索引的文件相对路径 + 末尾一句话汇总。
退出码：恒 0（advisory，调用方 `|| true`）。无 PRODUCT-STATE / 无 docs → 静默 0。
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

# docs/ 顶层永远已知的核心真相源（CLAUDE.md 文档位置表里列着，不算野文档）
KNOWN_CORE = {
    "PRODUCT.md",
    "PRODUCT-STATE.md",
    "PRODUCT-RULES.md",
    "DESIGN.md",
    "TODO.md",
}


def find_repo_root(start: str | None) -> Path:
    """优先用传入路径；否则 git 推导主仓根（兼容 worktree）。"""
    if start:
        p = Path(start).resolve()
        if p.is_dir():
            return p
    try:
        common = subprocess.check_output(
            ["git", "rev-parse", "--git-common-dir"], text=True, stderr=subprocess.DEVNULL
        ).strip()
        if common and common != ".git":
            return Path(common).resolve().parent
    except Exception:
        pass
    try:
        return Path(
            subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], text=True, stderr=subprocess.DEVNULL
            ).strip()
        )
    except Exception:
        return Path.cwd()


def main() -> int:
    repo_root = find_repo_root(sys.argv[1] if len(sys.argv) > 1 else None)
    docs_dir = repo_root / "docs"
    state_md = docs_dir / "PRODUCT-STATE.md"

    if not docs_dir.is_dir() or not state_md.is_file():
        return 0  # 没有现状档 / 没有 docs → 无漂移可言

    try:
        state_text = state_md.read_text(encoding="utf-8")
    except OSError:
        return 0

    drifted: list[str] = []
    for md in sorted(docs_dir.glob("*.md")):
        name = md.name
        if name in KNOWN_CORE or name.startswith("."):
            continue
        # 文件名（含/不含 .md）在现状档全文出现过 → 算已被索引提及
        stem = md.stem
        if name in state_text or stem in state_text:
            continue
        drifted.append(f"docs/{name}")

    if not drifted:
        return 0

    print("⚠️ 索引漂移：以下 docs/ 顶层文档实存，但 docs/PRODUCT-STATE.md 索引没引到——")
    for rel in drifted:
        print(f"  • {rel}")
    print(f"（{len(drifted)} 份未挂索引。沉淀时可顺手补进 PRODUCT-STATE 索引节，或归档/删除。）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
