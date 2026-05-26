#!/usr/bin/env python3
"""check-index-lint.py — docs/modules/INDEX.md lint 校验

校验规则：
1. 每行简介 ≤30 字
2. 表格行格式正确（`| module | 简介 |`）
3. 不含"包含/含/由...组成"等功能列表词（INDEX 应写用途不写功能清单）
4. module 集合应与 docs/modules/*.md 一致（额外或缺失 module 报告但不致命）

用法：
  python3 scripts/check-index-lint.py <repo-root>
  python3 scripts/check-index-lint.py <repo-root> --exit-code  # 失败时 exit 1
"""
import argparse
import json
import re
import sys
from pathlib import Path


FORBIDDEN_PHRASES = ["包含", "由", "组成", "等功能", "等模块", "等组件"]
# Note: 单字「含」太严会误报「X（含 Y、Z）」这种合理短语，故只禁「包含」


def parse_index(path: Path) -> list:
    """Parse INDEX.md table rows. Returns [(module, brief, line_no)]."""
    rows = []
    if not path.exists():
        return rows
    for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        s = line.strip()
        if not s.startswith("|") or s.startswith("|---") or re.match(r"^\|[\s\-\|]+\|$", s):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if len(cells) != 2:
            continue
        module, brief = cells
        if module in ("模块", "module") or not module:
            continue
        rows.append((module, brief, line_no))
    return rows


def lint_row(module: str, brief: str, line_no: int) -> list:
    """Lint single row. Returns list of error dicts."""
    errors = []
    if len(brief) > 30:
        errors.append({"line": line_no, "module": module, "rule": "length", "msg": f"简介 {len(brief)} 字 > 30 字上限"})
    for phrase in FORBIDDEN_PHRASES:
        if phrase in brief:
            errors.append({"line": line_no, "module": module, "rule": "forbidden_phrase",
                          "msg": f"含禁用词「{phrase}」(INDEX 写用途不写功能清单)"})
            break  # 一行一个 phrase 错误足够
    if not brief:
        errors.append({"line": line_no, "module": module, "rule": "empty_brief", "msg": "简介为空"})
    return errors


def check_module_coverage(index_modules: set, modules_dir: Path) -> dict:
    """检查 INDEX 列出的 module 与 docs/modules/*.md 一致性。"""
    if not modules_dir.is_dir():
        return {"actual_modules": [], "missing_in_index": [], "extra_in_index": []}
    actual = {p.stem for p in modules_dir.glob("*.md") if p.stem != "INDEX"}
    return {
        "actual_modules": sorted(actual),
        "missing_in_index": sorted(actual - index_modules),
        "extra_in_index": sorted(index_modules - actual),
    }


def main():
    parser = argparse.ArgumentParser(description="Lint docs/modules/INDEX.md")
    parser.add_argument("repo_root", help="repository root path")
    parser.add_argument("--exit-code", action="store_true", help="exit 1 on errors")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()
    index_path = repo_root / "docs" / "modules" / "INDEX.md"
    modules_dir = repo_root / "docs" / "modules"

    if not index_path.exists():
        result = {"index_path": str(index_path), "exists": False, "errors": [], "coverage": None}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        if args.exit_code:
            sys.exit(1)
        return

    rows = parse_index(index_path)
    errors = []
    for module, brief, line_no in rows:
        errors.extend(lint_row(module, brief, line_no))

    index_modules = {m for m, _, _ in rows}
    coverage = check_module_coverage(index_modules, modules_dir)

    result = {
        "index_path": str(index_path),
        "exists": True,
        "row_count": len(rows),
        "errors": errors,
        "coverage": coverage,
        "passed": len(errors) == 0,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))

    if args.exit_code and not result["passed"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
