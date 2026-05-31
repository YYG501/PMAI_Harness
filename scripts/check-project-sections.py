#!/usr/bin/env python3
"""check-project-sections.py — PRODUCT.md 5 节状态检测器

被 req-stage-gate skill 在 stage 3→4 闸门调用，检测 docs/PRODUCT.md 5 节
（项目名称 / 产品定位 / 用户画像 / 技术栈 / 业务术语表）
是否为空骨架（HTML 注释占位 / 无实质内容）。

复用 req-transition.py:78-92 check_design_md_has_content() 模式。

返回 JSON：
{
  "project_path": "/path/to/PROJECT.md",
  "exists": true,
  "sections": {
    "项目名称": {"present": true, "substantial": true},
    "产品定位": {"present": true, "substantial": false},  // 只有 HTML 注释
    "用户画像": {"present": false, "substantial": false},  // 节缺失
    ...
  },
  "empty_sections": ["产品定位", "用户画像", "技术栈", "业务术语表"],
  "all_filled": false  // 5 节全 substantial
}

用法：
  python3 scripts/check-project-sections.py <repo-root>
  python3 scripts/check-project-sections.py <repo-root> --section 产品定位  # 检查单节
"""
import argparse
import json
import re
import sys
from pathlib import Path


REQUIRED_SECTIONS = [
    "项目名称",
    "产品定位",
    "用户画像",
    "技术栈",
    "业务术语表",
]


def parse_sections(content: str) -> dict:
    """Parse ## sections into {header: body}."""
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


def is_substantial(body: str, section: str) -> bool:
    """检测节 body 是否含实质内容（非 HTML 占位 / 非空表格 / 非空骨架）。"""
    # 去掉 HTML 注释
    stripped = re.sub(r"<!--.*?-->", "", body, flags=re.DOTALL).strip()
    # 去掉空 markdown 表格头（| --- | 这类）
    stripped = re.sub(r"^\|[\s\-\|]+\|\s*$", "", stripped, flags=re.MULTILINE).strip()
    # 去掉空表头（如 | 角色 | 描述 | 关键诉求 |）但保留有数据行的
    lines = [ln for ln in stripped.splitlines() if ln.strip()]
    # 如果只有表头（含 |）没有数据行，视为空
    table_only = all("|" in ln for ln in lines) if lines else False
    has_data_row = any(
        "|" in ln and not all(c.strip() in {"", "-", "角色", "描述", "关键诉求", "术语", "说明"} for c in ln.split("|"))
        for ln in lines
        if not re.match(r"^\|[\s\-\|]+\|$", ln)
    )

    # 项目名称特殊：占位 {{PROJECT_NAME}} 或为空 = 不 substantial
    if section == "项目名称":
        return bool(stripped) and "{{" not in stripped and stripped != ""

    # 产品定位 / 技术栈：去 HTML 注释后非空即可
    if section in ("产品定位", "技术栈"):
        return bool(stripped) and "{{" not in stripped

    # 用户画像 / 业务术语表：必须有数据行（不止表头）
    if section in ("用户画像", "业务术语表"):
        return has_data_row

    return bool(stripped)


def check_project(repo_root: Path, target_section: str = None) -> dict:
    """检测 PRODUCT 5 节状态。"""
    project_path = repo_root / "docs" / "PRODUCT.md"
    result = {
        "project_path": str(project_path),
        "exists": project_path.exists(),
        "sections": {},
        "empty_sections": [],
        "all_filled": False,
    }

    if not project_path.exists():
        result["empty_sections"] = list(REQUIRED_SECTIONS)
        return result

    content = project_path.read_text(encoding="utf-8")
    sections = parse_sections(content)

    targets = [target_section] if target_section else REQUIRED_SECTIONS
    for sec in targets:
        present = sec in sections
        substantial = present and is_substantial(sections[sec], sec)
        result["sections"][sec] = {"present": present, "substantial": substantial}
        if not substantial:
            result["empty_sections"].append(sec)

    if not target_section:
        result["all_filled"] = len(result["empty_sections"]) == 0

    return result


def main():
    parser = argparse.ArgumentParser(description="Check PROJECT.md 5 sections state")
    parser.add_argument("repo_root", help="repository root path")
    parser.add_argument("--section", help="check only specific section", default=None)
    parser.add_argument("--exit-code", action="store_true",
                        help="exit 0 if all_filled, 1 if any empty (for shell scripts)")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    if not repo_root.is_dir():
        print(json.dumps({"error": f"repo not found: {repo_root}"}, ensure_ascii=False), file=sys.stderr)
        sys.exit(2)

    result = check_project(repo_root, args.section)
    print(json.dumps(result, ensure_ascii=False, indent=2))

    if args.exit_code:
        sys.exit(0 if result.get("all_filled", False) else 1)


if __name__ == "__main__":
    main()
