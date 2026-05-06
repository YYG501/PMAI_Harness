#!/usr/bin/env python3
"""把工程结构约束段注入到 CLAUDE.md（替换 {{STRUCTURE_CONSTRAINTS}} placeholder）。

供 init-project.sh 在模板复制后调用，按 PM 选定的 project_intent 决定写入内容：

    prototype  → 派生自 templates/工程结构约束-prototype.md，去掉 AUTO-GENERATED
                 顶部 marker，包一层 auto-detected marker
    system     → 同上 system
    custom     → 同上 custom（PM 自由编辑骨架，深度 prose 留空让 PM 写）
    unknown    → 占位提示 PM 跑 detect 或手动选

CLAUDE.md「## 工程结构约束」section 顶部已有 placeholder 注释解释档位行为
（templates/CLAUDE.md.tmpl）；本脚本仅替换 `{{STRUCTURE_CONSTRAINTS}}` 的具体内容。

用法：
    inject-structure-segment.py <claude.md path> <intent> [--framework-root <repo>]

退出码：
    0 = 注入成功
    1 = claude.md 不含 placeholder（已注入过 / 已被 PM 手填）
    2 = intent 非法 / 文件错
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def _detect_framework_root() -> Path:
    """优先 git rev-parse 找仓根；fallback 适配两种 layout：
      - 生成器仓：scripts/inject-structure-segment.py
      - 业务仓：.claude/scripts/inject-structure-segment.py（同步后路径）
    """
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=Path(__file__).resolve().parent,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if out:
            return Path(out)
    except Exception:
        pass
    return Path(__file__).resolve().parent.parent


VALID_INTENTS = {"prototype", "system", "custom", "unknown"}
PLACEHOLDER = "{{STRUCTURE_CONSTRAINTS}}"
AUTO_DETECTED_OPEN = "<!-- auto-detected: {intent} — PM 可改。删除本注释行后视为 PM 手填，框架不再覆盖。 -->"


def load_template(framework_root: Path, mode: str) -> str:
    """读派生模板，去掉 AUTO-GENERATED 顶部 marker 块（避免与 inject 自加的
    auto-detected marker 重复）。

    drop 规则：连续吞开头的 HTML 注释行 + 紧随的第一个空行。这对
    prototype / system / custom 三档模板都成立（每档前两行都是 <!-- --> 注释）。
    """
    path = framework_root / "templates" / f"工程结构约束-{mode}.md"
    if not path.exists():
        print(f"❌ 模板不存在: {path}", file=sys.stderr)
        sys.exit(2)
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    drop = 0
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("<!--"):
            drop += 1
            continue
        if stripped == "":
            drop += 1
            break
        break
    return "\n".join(lines[drop:]).lstrip()


def render_segment(intent: str, framework_root: Path) -> str:
    marker = AUTO_DETECTED_OPEN.format(intent=intent)
    if intent == "unknown":
        body = (
            "_待 PM 决定项目意图_。可选路径：\n"
            "- 运行 `python3 .claude/scripts/detect-project-structure.py` 看探测推荐\n"
            "- 或手动选 prototype / system / custom，重跑 init"
        )
        return f"{marker}\n\n{body}"
    if intent in {"prototype", "system", "custom"}:
        body = load_template(framework_root, intent)
        return f"{marker}\n\n{body}"
    raise ValueError(f"unreachable intent: {intent}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Inject 工程结构约束 segment into CLAUDE.md")
    parser.add_argument("claude_md", type=Path, help="目标 CLAUDE.md 路径")
    parser.add_argument(
        "intent",
        choices=sorted(VALID_INTENTS),
        help="项目意图：prototype / system / custom / unknown",
    )
    parser.add_argument(
        "--framework-root",
        type=Path,
        default=_detect_framework_root(),
        help="框架仓库根目录（默认本仓）",
    )
    args = parser.parse_args()

    if not args.claude_md.exists():
        print(f"❌ CLAUDE.md 不存在: {args.claude_md}", file=sys.stderr)
        return 2

    text = args.claude_md.read_text(encoding="utf-8")
    if PLACEHOLDER not in text:
        print(
            f"⚠️  {args.claude_md} 不含 {PLACEHOLDER}——可能已注入过，或被 PM 手填",
            file=sys.stderr,
        )
        return 1

    segment = render_segment(args.intent, args.framework_root)
    new_text = text.replace(PLACEHOLDER, segment, 1)
    args.claude_md.write_text(new_text, encoding="utf-8")
    print(f"✅ 工程结构约束段已注入: {args.claude_md} (intent={args.intent})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
