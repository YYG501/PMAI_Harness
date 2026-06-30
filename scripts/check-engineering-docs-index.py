#!/usr/bin/env python3
"""Pre-commit gate: ensure docs/engineering documents are indexed.

gstack document side paths are temporary until PMAI adopts their output. Once an
engineering document is committed under docs/engineering/, it must be listed in
docs/engineering/INDEX.md so future agents can find it through the document map.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def get_staged_engineering_docs() -> list[str]:
    result = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=AM"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return []
    return [line for line in result.stdout.splitlines() if line]


def filter_engineering_docs(paths: list[str]) -> list[str]:
    out: list[str] = []
    for raw in paths:
        path = raw.strip().replace("\\", "/")
        if not path.startswith("docs/engineering/"):
            continue
        if not path.endswith(".md"):
            continue
        if Path(path).name == "INDEX.md":
            continue
        out.append(path)
    return sorted(set(out))


def is_indexed(path: str, index_text: str) -> bool:
    rel = path.removeprefix("docs/engineering/")
    name = Path(path).name
    stem = Path(path).stem
    return rel in index_text or name in index_text or stem in index_text


def check(repo_root: Path, paths: list[str]) -> int:
    docs = filter_engineering_docs(paths)
    if not docs:
        return 0

    index_path = repo_root / "docs" / "engineering" / "INDEX.md"
    if not index_path.is_file():
        print("❌ pre-commit: docs/engineering/INDEX.md 不存在。", file=sys.stderr)
        print("   采用工程文档前，请先按 $PMAI_HOME/templates/engineering-INDEX.md.tmpl 补建索引。", file=sys.stderr)
        return 1

    try:
        index_text = index_path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"❌ pre-commit: 无法读取 docs/engineering/INDEX.md: {exc}", file=sys.stderr)
        return 1

    missing = [path for path in docs if not is_indexed(path, index_text)]
    if not missing:
        return 0

    print("❌ pre-commit: 工程文档已接回 docs/engineering/，但未登记到 docs/engineering/INDEX.md：", file=sys.stderr)
    for path in missing:
        print(f"    {path}", file=sys.stderr)
    print("\n   修复：把上述文档追加到 docs/engineering/INDEX.md 后再提交。", file=sys.stderr)
    print("   gstack /document-generate 或 /document-release 的临时输出不算 PMAI 真相源；采用后必须接回并补索引。", file=sys.stderr)
    return 1


def main() -> int:
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
            return 0
        repo_root = Path(result.stdout.strip())

    paths = args.from_paths if args.from_paths is not None else get_staged_engineering_docs()
    return check(repo_root, paths)


if __name__ == "__main__":
    sys.exit(main())
