#!/usr/bin/env python3
"""Block mixed build-target + docs/mockups commits outside automatic finalize."""

from __future__ import annotations

import os
import subprocess
import sys


ALLOW_ENV = "PMAI_ALLOW_MIXED_DELIVERY"
ALLOW_VALUE = "build-close"


def run_git(args: list[str]) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            ["git", *args],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError:
        return None


def staged_files() -> list[str]:
    root = run_git(["rev-parse", "--show-toplevel"])
    if root is None or root.returncode != 0:
        return []

    result = run_git(["diff", "--cached", "--name-only", "--diff-filter=ACMRD"])
    if result is None or result.returncode != 0:
        return []

    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def has_prefix(paths: list[str], prefixes: tuple[str, ...]) -> bool:
    return any(path == prefix.rstrip("/") or path.startswith(prefix) for path in paths for prefix in prefixes)


def examples(paths: list[str], prefixes: tuple[str, ...], limit: int = 4) -> list[str]:
    matched = [path for path in paths if any(path == prefix.rstrip("/") or path.startswith(prefix) for prefix in prefixes)]
    return matched[:limit]


def main() -> int:
    if os.environ.get(ALLOW_ENV) == ALLOW_VALUE:
        return 0

    paths = staged_files()
    if not paths:
        return 0

    prototype_prefixes = ("prototype/", "Sources/")
    docs_prefixes = ("docs/modules/",)
    mockup_prefixes = ("mockups/",)

    has_prototype = has_prefix(paths, prototype_prefixes)
    has_docs = has_prefix(paths, docs_prefixes)
    has_mockups = has_prefix(paths, mockup_prefixes)

    if not has_prototype or not (has_docs or has_mockups):
        return 0

    print("❌ 这次暂存内容是混合交付，不能直接提交。", file=sys.stderr)
    print("", file=sys.stderr)
    print("它同时包含主原型改动和模块文档 / mockup 改动：", file=sys.stderr)
    for label, prefixes in (
        ("主原型", prototype_prefixes),
        ("模块文档", docs_prefixes),
        ("mockup", mockup_prefixes),
    ):
        matched = examples(paths, prefixes)
        if matched:
            print(f"  {label}:", file=sys.stderr)
            for path in matched:
                print(f"    - {path}", file=sys.stderr)
    print("", file=sys.stderr)
    print("请回到 /pmai-build：PM 定稿后会自动完成最终检查、合入主线和主线后的文档同步。", file=sys.stderr)
    print(f"统一 finalize 内部会用 {ALLOW_ENV}={ALLOW_VALUE} 放行；普通提交不要手动绕过。", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
