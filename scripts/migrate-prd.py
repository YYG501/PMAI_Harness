#!/usr/bin/env python3
"""migrate-prd.py — 消费仓 docs/prd.md → v5 CONTEXT + modules 迁移（vp-1a）

按 D1 决议（v5 §2.9）：vp-1 砍 docs/prd.md 前先做 vp-1a 消费仓 prd 内容
迁移（AI 辅助迁移脚本 + PM 审 diff）。

原 docs/prd.md 4 section 归宿（v5 体系）:
  ## 产品概述  -> docs/CONTEXT.md `## 产品定位` 节
  ## 功能清单  -> docs/modules/<m>.md 对应模块（+ docs/modules/INDEX.md 简介）
  ## 用户画像  -> docs/CONTEXT.md `## 用户画像` 节
  ## 产品路线  -> docs/CONTEXT.md `## 产品路线` 节

不自动 commit，输出 diff 让 PM 审。每个 patch 写到 .v5-draft 临时文件。

用法:
  python3 scripts/migrate-prd.py <消费仓路径>
"""
import re
import sys
from pathlib import Path


def parse_md_sections(content: str) -> dict:
    """Parse markdown ## sections into {header: body_lines}."""
    sections = {}
    current_header = None
    current_body = []
    for line in content.splitlines():
        m = re.match(r"^##\s+(.+?)\s*$", line)
        if m:
            if current_header is not None:
                sections[current_header] = "\n".join(current_body).rstrip()
            current_header = m.group(1).strip()
            current_body = []
        else:
            if current_header is not None:
                current_body.append(line)
    if current_header is not None:
        sections[current_header] = "\n".join(current_body).rstrip()
    return sections


def is_substantial(body: str) -> bool:
    """Body has substantial content (not HTML comments / empty / placeholder)."""
    stripped = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL).strip()
    stripped = re.sub(r"^\|[\s\-\|]+\|\s*$", "", stripped, flags=re.MULTILINE).strip()
    return len(stripped) > 0 and not stripped.startswith("{{")


def append_to_context_section(context_content: str, target_section: str, append_body: str, note: str) -> str:
    """在 CONTEXT.md 指定 ## section 末尾追加内容。如 section 不存在，追加到末尾。"""
    pattern = rf"^(## {re.escape(target_section)}\s*\n)(.*?)(?=^##\s+|\Z)"
    m = re.search(pattern, context_content, re.MULTILINE | re.DOTALL)
    if not m:
        # section 不存在，追加到文件末尾
        return context_content.rstrip() + f"\n\n## {target_section}\n\n<!-- TODO(v5 migration): {note} -->\n{append_body}\n"
    # section 存在，在 body 末尾插入
    existing_body = m.group(2).rstrip()
    new_body = existing_body + f"\n\n<!-- TODO(v5 migration): {note} -->\n{append_body}\n"
    return context_content[:m.start(2)] + new_body + context_content[m.end(2):]


def main():
    if len(sys.argv) < 2:
        print(f"用法: python3 {sys.argv[0]} <消费仓路径>", file=sys.stderr)
        sys.exit(2)

    repo_root = Path(sys.argv[1]).resolve()
    if not repo_root.is_dir():
        print(f"❌ 消费仓路径不存在: {repo_root}", file=sys.stderr)
        sys.exit(2)

    prd_path = repo_root / "docs" / "prd.md"
    if not prd_path.exists():
        print(f"⚠️  消费仓无 docs/prd.md（{prd_path}）", file=sys.stderr)
        print("   该消费仓可能是新 init 项目（v5 init 不再创建 prd.md），无需迁移。")
        sys.exit(0)

    prd_content = prd_path.read_text(encoding="utf-8")
    prd_sections = parse_md_sections(prd_content)

    print(f"📂 消费仓: {repo_root}")
    print(f"📄 docs/prd.md: {prd_path}（{len(prd_content)} bytes）")
    print(f"📊 检测到 {len(prd_sections)} 个 ## 节: {list(prd_sections.keys())}")
    print()

    # CONTEXT.md 状态
    context_path = repo_root / "docs" / "CONTEXT.md"
    if not context_path.exists():
        print(f"❌ docs/CONTEXT.md 不存在，先跑 migrate-context-v4.py 创建 v5 6 节结构", file=sys.stderr)
        sys.exit(1)
    context_content = context_path.read_text(encoding="utf-8")
    context_draft = context_content

    actions = []  # 累积本次迁移动作

    # 1. 产品概述 → CONTEXT 产品定位
    overview = prd_sections.get("产品概述", "")
    if is_substantial(overview):
        context_draft = append_to_context_section(
            context_draft, "产品定位", overview,
            "从老 docs/prd.md ## 产品概述节迁移；PM 审阅后建议重写为产品定位四要素"
        )
        actions.append("产品概述 → CONTEXT 产品定位（追加 TODO 段）")

    # 2. 用户画像 → CONTEXT 用户画像
    portrait = prd_sections.get("用户画像", "")
    if is_substantial(portrait):
        context_draft = append_to_context_section(
            context_draft, "用户画像", portrait,
            "从老 docs/prd.md ## 用户画像节迁移；PM 审阅后建议整理为 3 列表格"
        )
        actions.append("用户画像 → CONTEXT 用户画像（追加 TODO 段）")

    # 3. 产品路线 → CONTEXT 产品路线
    roadmap = prd_sections.get("产品路线", "")
    if is_substantial(roadmap):
        context_draft = append_to_context_section(
            context_draft, "产品路线", roadmap,
            "从老 docs/prd.md ## 产品路线节迁移；PM 审阅后归入 ### 已完成 / ### 计划中 + 标 ⭐"
        )
        actions.append("产品路线 → CONTEXT 产品路线（追加 TODO 段）")

    # 4. 功能清单 → 不自动 patch modules/，提示 PM
    features = prd_sections.get("功能清单", "")
    if is_substantial(features):
        actions.append(
            "功能清单（自动迁移有难度）→ 提示 PM 手动拆分到 docs/modules/<module>.md 各自模块；"
            "原内容保留在 docs/prd.md，由后续 vp-1 砍 prd.md 时归档"
        )

    if not actions:
        print("✅ docs/prd.md 4 个 section 都为空 / 占位，无需迁移。可直接走 vp-1 砍 prd.md。")
        sys.exit(0)

    # 写 .v5-draft
    draft_path = context_path.with_suffix(".md.v5-prd-migration-draft")
    draft_path.write_text(context_draft, encoding="utf-8")

    print("📝 CONTEXT.md 草稿已写到:")
    print(f"   {draft_path}")
    print()
    print("📋 迁移动作：")
    for action in actions:
        print(f"   - {action}")
    print()
    print("👀 请 PM 审 diff:")
    print(f"   diff {context_path} {draft_path}")
    print()
    print("✅ 满意 → 手动覆盖 CONTEXT.md + 处理 docs/prd.md 功能清单（如有）：")
    print(f"   mv {draft_path} {context_path}")
    print(f"   # 如功能清单有内容，手动拆分到 docs/modules/<module>.md")
    print(f"   # vp-1 阶段会砍 docs/prd.md 引用 + 删文件")
    print()
    print("❌ 不满意 → 修改 .v5-prd-migration-draft 后再覆盖，或:")
    print(f"   rm {draft_path}")
    print()
    print("⚠️  本脚本不自动 commit，PM 审完手动 git add + commit")


if __name__ == "__main__":
    main()
