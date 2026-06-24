#!/usr/bin/env python3
"""migrate-context-v4.py — 消费仓 docs/CONTEXT.md 5 节 → v5 6 节迁移

老 5 节（v3/v4 之前）:
  ## 项目名称 / ## 项目描述 / ## 技术栈 / ## 约束条件 / ## 已知风险

新 6 节（v5）:
  ## 项目名称 / ## 产品定位 / ## 用户画像 / ## 产品路线 / ## 技术栈 / ## 业务术语表

迁移规则：
- 项目名称: 保留
- 项目描述 -> 产品定位（提示 PM 是否合并）
- 技术栈: 保留
- 约束条件 -> 非空时提示 PM 归并到「产品定位」末段，原段保留打 TODO
- 已知风险 -> 非空时提示 PM 归到模块 discussion/decisions 或 docs/TODO.md，原段保留打 TODO
- 新增节（用户画像 / 产品路线 / 业务术语表）: 空骨架

不自动 commit，输出 diff 让 PM 审。

用法:
  python3 scripts/migrate-context-v4.py <消费仓路径>
"""
import re
import sys
from pathlib import Path


SECTION_HEADERS_OLD = ["项目名称", "项目描述", "技术栈", "约束条件", "已知风险"]
SECTION_HEADERS_NEW = ["项目名称", "产品定位", "用户画像", "产品路线", "技术栈", "业务术语表"]


def parse_sections(content: str) -> dict:
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
    """Body has substantial content (not just HTML comments / empty / placeholder)."""
    stripped = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL).strip()
    return len(stripped) > 0 and not stripped.startswith("{{") and stripped not in ["", "TBD", "待补充"]


def build_v5_context(old_sections: dict, project_name: str) -> tuple[str, list[str]]:
    """Build v5 CONTEXT content from old sections. Returns (new_content, migration_notes)."""
    notes = []
    out = []
    out.append("# 项目背景\n")

    # ## 项目名称 — 保留
    out.append("## 项目名称\n")
    name_body = old_sections.get("项目名称", "").strip()
    if is_substantial(name_body):
        out.append(name_body)
        out.append("")
    else:
        out.append(project_name)
        out.append("")

    # ## 产品定位 — 从「项目描述」迁移
    out.append("## 产品定位\n")
    desc_body = old_sections.get("项目描述", "").strip()
    if is_substantial(desc_body):
        out.append("<!-- 2-4 句：是什么 / 解决什么 / 给谁用 / 长期硬约束（可省）；精简模式 = 1 句话定性 -->")
        out.append("<!-- TODO(v5 migration): 下文从老「项目描述」节迁移，请 PM 审阅并按需重写为产品定位四要素 -->")
        out.append(desc_body)
        out.append("")
        notes.append("产品定位: 从老「项目描述」节迁移内容（待 PM 重写为产品定位四要素）")
    else:
        out.append("<!-- 2-4 句：是什么 / 解决什么 / 给谁用 / 长期硬约束（可省）；精简模式 = 1 句话定性 -->")
        out.append("")
        notes.append("产品定位: 老「项目描述」节为空，新节为空骨架")

    # ## 用户画像 — 新增空骨架
    out.append("## 用户画像\n")
    out.append("<!-- 起手 1 个主角色即可（精简模式）；后续 discussion / decisions / spec / PRD 出现新角色 AI 会催你补 -->")
    out.append("")
    out.append("| 角色 | 描述 | 关键诉求 |")
    out.append("|---|---|---|")
    out.append("")
    notes.append("用户画像: v5 新增节（空骨架，待 PM stage 3 后填）")

    # ## 产品路线 — 新增空骨架
    out.append("## 产品路线\n")
    out.append("<!-- 里程碑形式（宣告性 ≠ 约束）；精简模式 = \"计划中\" 1 条；close-work 时可追加里程碑（标 ⭐ 可被 status-view --milestone 筛到） -->")
    out.append("")
    out.append("### 已完成")
    out.append("")
    out.append("### 计划中")
    out.append("")
    notes.append("产品路线: v5 新增节（空骨架，待 PM stage 3 后填）")

    # ## 技术栈 — 保留
    out.append("## 技术栈\n")
    tech_body = old_sections.get("技术栈", "").strip()
    if is_substantial(tech_body):
        out.append(tech_body)
        out.append("")
        notes.append("技术栈: 保留老内容")
    else:
        out.append("<!-- 主要语言 / 前端 / 后端 / 部署；精简模式 = 1 条主语言或框架 -->")
        out.append("")
        notes.append("技术栈: 老节为空，新节为空骨架")

    # ## 业务术语表 — 新增空骨架
    out.append("## 业务术语表\n")
    out.append("<!-- 每条 ≤30 字；精简模式 = 1 条核心业务词；后续 discussion / decisions / spec / PRD 出现新词 AI 会催你补 -->")
    out.append("")
    out.append("| 术语 | 说明 |")
    out.append("|---|---|")
    out.append("")
    notes.append("业务术语表: v5 新增节（空骨架，待 PM stage 3 后填）")

    # 老约束条件 / 已知风险节如有非空内容 -> 加 TODO 段保留（PM 决定怎么处理）
    constraint_body = old_sections.get("约束条件", "").strip()
    if is_substantial(constraint_body):
        out.append("---")
        out.append("")
        out.append("<!-- TODO(v5 migration): 老「约束条件」节内容保留如下，建议 PM 归并到「产品定位」末段「长期硬约束」一并写，然后删除本块。-->")
        out.append("## 约束条件（v5 migration TODO）\n")
        out.append(constraint_body)
        out.append("")
        notes.append("约束条件（migration TODO）: 老内容保留，PM 应归并到产品定位末段后手动删本块")

    risk_body = old_sections.get("已知风险", "").strip()
    if is_substantial(risk_body):
        out.append("---")
        out.append("")
        out.append("<!-- TODO(v5 migration): 老「已知风险」节内容保留如下，建议 PM 归到相关模块 discussion.md / decisions.md（待处理风险进 docs/TODO.md）或丢弃，然后删除本块。-->")
        out.append("## 已知风险（v5 migration TODO）\n")
        out.append(risk_body)
        out.append("")
        notes.append("已知风险（migration TODO）: 老内容保留，PM 应归到模块讨论/决策或 docs/TODO.md 后手动删本块")

    return "\n".join(out).rstrip() + "\n", notes


def main():
    if len(sys.argv) < 2:
        print(f"用法: python3 {sys.argv[0]} <消费仓路径>", file=sys.stderr)
        sys.exit(2)

    repo_root = Path(sys.argv[1]).resolve()
    if not repo_root.is_dir():
        print(f"❌ 消费仓路径不存在: {repo_root}", file=sys.stderr)
        sys.exit(2)

    context_path = repo_root / "docs" / "CONTEXT.md"
    if not context_path.exists():
        print(f"⚠️  消费仓无 docs/CONTEXT.md（{context_path}）", file=sys.stderr)
        print("   该消费仓可能是新 init 项目，v5 init 已直接落 6 节模板。无需迁移。")
        sys.exit(0)

    old_content = context_path.read_text(encoding="utf-8")
    old_sections = parse_sections(old_content)

    print(f"📂 消费仓: {repo_root}")
    print(f"📄 CONTEXT.md: {context_path}")
    print(f"📊 检测到 {len(old_sections)} 个 ## 节: {list(old_sections.keys())}")
    print()

    # 已经是 v5 6 节结构？跳过
    new_section_count = sum(1 for h in SECTION_HEADERS_NEW if h in old_sections)
    if new_section_count == 6:
        print("✅ CONTEXT.md 已是 v5 6 节结构，无需迁移。")
        sys.exit(0)

    project_name = old_sections.get("项目名称", "").strip() or repo_root.name
    new_content, notes = build_v5_context(old_sections, project_name)

    # 写到临时文件 让 PM 看 diff
    new_path = context_path.with_suffix(".md.v5-draft")
    new_path.write_text(new_content, encoding="utf-8")

    print(f"📝 v5 草稿已写到: {new_path}")
    print()
    print("📋 迁移说明：")
    for note in notes:
        print(f"   - {note}")
    print()
    print("👀 请 PM 审 diff:")
    print(f"   diff {context_path} {new_path}")
    print()
    print("✅ 满意 → 手动覆盖:")
    print(f"   mv {new_path} {context_path}")
    print()
    print("❌ 不满意 → 修改 .v5-draft 后再覆盖，或:")
    print(f"   rm {new_path}")
    print()
    print("⚠️  本脚本不自动 commit，PM 审完手动 git add + commit")


if __name__ == "__main__":
    main()
