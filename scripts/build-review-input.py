#!/usr/bin/env python3
"""Build a review input bundle for a task.

PM 视图 / 工程视图拆两文件后，gstack 的 `/plan-design-review` 这类 skill
天然只读 PM 指过去的那个文件——而视觉 token 全在 .engineering.md。结果是
review 评了 IA 层但碰不到像素层（example-consumer-app task-003 已观测到）。

本脚本按"约定"把和某次 review 相关的全部内容拼成一份 bundle 文件，PM
直接对 bundle 跑 review skill，一次喂全。

约定（REVIEW_CONVENTIONS）按 review 类型固化：
- design：PM 视图全文 + 工程视图 §7（plan-review 沉淀）+ §8（视觉规范）
            + 项目级 docs/DESIGN.md
- eng：    PM 视图 §功能清单/§跨功能/§验收 + 工程视图 §3-§6
            + 项目级 docs/modules/*.md（如有）
- dx：     PM 视图全文 + 工程视图 §5（实现指引）

Bundle 是派生 artifact，写到 .runs/review-input-<task>-<review>.md；
源文件不变，PM 视图主文件路径不暴露给 review skill。
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REVIEW_CONVENTIONS: dict[str, dict] = {
    "design": {
        "purpose": "/plan-design-review 输入 — IA + 视觉 token + 动效 全覆盖",
        "pm_view": "*",
        "engineering_section_keywords": [
            "plan-design-review",  # §7 plan-review 沉淀
            "视觉规范",            # §8 视口/视觉规范
        ],
        "project_files": ["docs/DESIGN.md"],
    },
    "eng": {
        "purpose": "/plan-eng-review 输入 — 架构 + 数据流 + 测试 全覆盖",
        "pm_view_section_keywords": [
            "功能清单",
            "跨功能产品规则",
            "验收清单",
        ],
        "engineering_section_keywords": [
            "启动前必读",
            "功能清单工程版",
            "实现指引",
            "易错点",
        ],
        "project_dirs": ["docs/modules"],
    },
    "dx": {
        "purpose": "/plan-devex-review 输入 — 开发体验",
        "pm_view": "*",
        "engineering_section_keywords": ["实现指引"],
    },
}


def find_repo_root() -> Path:
    try:
        return Path(
            subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], text=True
            ).strip()
        )
    except Exception:
        return Path.cwd()


def extract_sections_by_keyword(content: str, keyword: str) -> list[tuple[str, str]]:
    """Return all top-level (## ) sections whose heading line contains keyword.

    Returns list of (heading_label, full_section_text). heading_label is the text
    after `## ` on the heading line (used for review-source anchor).
    """
    pattern = re.compile(
        r"^(##\s+([^\n]*)\n)(.*?)(?=^##\s|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    out: list[tuple[str, str]] = []
    for m in pattern.finditer(content):
        head_line = m.group(1)
        head_label = m.group(2).strip()
        body = m.group(3)
        if keyword in head_line:
            out.append((head_label, (head_line + body).rstrip() + "\n"))
    return out


def source_anchor(kind: str, file: str, section: str | None = None) -> str:
    """Emit a review-source anchor as HTML comment.

    Format: <!-- review-source: <kind>, file=<file>[, section=<section>] -->
    Review skill / sediment-back AI quotes anchors to route conclusions back
    to the correct source file.
    """
    bits = [f"review-source: {kind}", f"file={file}"]
    if section:
        bits.append(f"section={section}")
    return f"<!-- {', '.join(bits)} -->"


def gather_pm_view(content: str, conv: dict, pm_filename: str) -> str:
    if conv.get("pm_view") == "*":
        anchor = source_anchor("pm-view", pm_filename)
        return f"# === PM 视图（全文）===\n\n{anchor}\n\n{content.rstrip()}\n"

    keywords = conv.get("pm_view_section_keywords", [])
    if not keywords:
        return ""

    parts: list[str] = ["# === PM 视图（章节子集）===\n"]
    for kw in keywords:
        sections = extract_sections_by_keyword(content, kw)
        if sections:
            for label, sec in sections:
                anchor = source_anchor("pm-view", pm_filename, label)
                parts.append(f"\n{anchor}\n{sec}")
        else:
            parts.append(f"\n> ⚠️ PM 视图未找到包含 `{kw}` 的章节标题\n")
    return "\n".join(parts) + "\n"


def gather_engineering(content: str, conv: dict, eng_filename: str) -> str:
    if conv.get("engineering") == "*":
        anchor = source_anchor("engineering", eng_filename)
        return f"# === 工程视图（全文）===\n\n{anchor}\n\n{content.rstrip()}\n"

    keywords = conv.get("engineering_section_keywords", [])
    if not keywords:
        return ""

    parts: list[str] = ["# === 工程视图（章节子集）===\n"]
    for kw in keywords:
        sections = extract_sections_by_keyword(content, kw)
        if sections:
            for label, sec in sections:
                anchor = source_anchor("engineering", eng_filename, label)
                parts.append(f"\n{anchor}\n{sec}")
        else:
            parts.append(f"\n> ⚠️ 工程视图未找到包含 `{kw}` 的章节标题\n")
    return "\n".join(parts) + "\n"


def gather_project_anchors(repo: Path, conv: dict) -> str:
    parts: list[str] = []
    for rel in conv.get("project_files", []):
        ap = repo / rel
        if ap.is_file():
            anchor = source_anchor("project-doc", rel)
            parts.append(
                f"# === 项目级文档：`{rel}` ===\n\n{anchor}\n\n"
                f"{ap.read_text(encoding='utf-8').rstrip()}\n"
            )
        else:
            parts.append(f"\n> ⚠️ 项目级文档不存在：`{rel}`（约定要求读，跳过）\n")

    for rel in conv.get("project_dirs", []):
        ap = repo / rel
        if ap.is_dir():
            for f in sorted(ap.glob("*.md")):
                rel_path = str(f.relative_to(repo))
                anchor = source_anchor("project-doc", rel_path)
                parts.append(
                    f"# === 项目级文档：`{rel_path}` ===\n\n{anchor}\n\n"
                    f"{f.read_text(encoding='utf-8').rstrip()}\n"
                )
        else:
            parts.append(f"\n> ⚠️ 项目级目录不存在：`{rel}`（跳过）\n")

    return "\n".join(parts)


def build_bundle(pm_view_path: Path, review: str) -> tuple[str, list[str]]:
    """Returns (bundle_text, warnings)."""
    if not pm_view_path.exists():
        sys.exit(f"Error: PM view file not found: {pm_view_path}")
    if pm_view_path.name.endswith(".engineering.md"):
        sys.exit("Error: pass PM-view file (.md), not .engineering.md")

    conv = REVIEW_CONVENTIONS[review]
    eng_view_path = pm_view_path.with_name(pm_view_path.stem + ".engineering.md")
    repo = find_repo_root()

    warnings: list[str] = []

    header = [
        f"# Review Input Bundle — {pm_view_path.stem}",
        "",
        "> 派生 artifact，由 `scripts/build-review-input.py` 拼装；不要直接编辑。",
        "> 原始内容请改 PM 视图主文件 / 工程合同；改完重跑本脚本。",
        "",
        f"**Review type**: `{review}`（{conv['purpose']}）",
        f"**Source PM view**: `{pm_view_path.name}`",
        f"**Source engineering view**: `{eng_view_path.name}`"
        + ("" if eng_view_path.exists() else "（**缺失**）"),
        "",
        "## ⚓ Source Anchors（review skill 必读）",
        "",
        "本 bundle 拼自多个源文件。每个章节前的 HTML 注释",
        "`<!-- review-source: <kind>, file=<path>[, section=<heading>] -->`",
        "标记该段内容来自哪个源文件 / 哪个章节。",
        "",
        "**给 review 输出沉淀回源文件**用的：每条 decision / finding 必须明示",
        "对应 source anchor（kind + file + section），下游沉淀脚本 / AI 据此",
        "把结论写回正确的源文件，不要把视觉 token 写到 PM 视图、也不要把 IA",
        "决策塞进工程合同。",
        "",
        "**Kind 说明**：",
        "- `pm-view` → 写回 PM 视图主文件（IA / 交互 / 文案）",
        "- `engineering` → 写回工程合同 `.engineering.md`（视觉 token / 易错点 / plan-review 沉淀）",
        "- `project-doc` → 写回 `docs/DESIGN.md` 或 `docs/modules/*.md`（项目级共享合同）",
        "",
        "---",
        "",
    ]

    body: list[str] = []

    # PM view
    body.append(
        gather_pm_view(
            pm_view_path.read_text(encoding="utf-8"), conv, pm_view_path.name
        )
    )

    # Engineering view
    if eng_view_path.exists():
        body.append(
            gather_engineering(
                eng_view_path.read_text(encoding="utf-8"), conv, eng_view_path.name
            )
        )
    else:
        warnings.append(f"engineering view missing: {eng_view_path}")
        body.append(
            f"# === 工程视图 ===\n\n> ⚠️ 工程视图缺失：`{eng_view_path.name}`\n"
            f"> 视觉 token / 易错点 / plan-review 沉淀全部不可用。\n"
        )

    # Project anchors
    anchors = gather_project_anchors(repo, conv)
    if anchors:
        body.append(anchors)

    return "\n".join(header) + "\n\n".join(body), warnings


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build a review input bundle for a task (PM 视图 + 工程视图按约定章节 + 项目级文档)"
    )
    parser.add_argument("task_file", help="Path to PM view task file (.md, 不是 .engineering.md)")
    parser.add_argument(
        "--review",
        required=True,
        choices=sorted(REVIEW_CONVENTIONS.keys()),
        help="Review 类型（决定按哪套约定拼章节）",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="Override 输出路径；默认 .runs/review-input-<task>-<review>.md",
    )
    args = parser.parse_args()

    pm_view = Path(args.task_file).resolve()
    bundle_text, warnings = build_bundle(pm_view, args.review)

    repo = find_repo_root()
    out = (
        Path(args.out).resolve()
        if args.out
        else repo / ".runs" / f"review-input-{pm_view.stem}-{args.review}.md"
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(bundle_text, encoding="utf-8")

    for w in warnings:
        print(f"⚠️  {w}", file=sys.stderr)
    print(out)


if __name__ == "__main__":
    main()
