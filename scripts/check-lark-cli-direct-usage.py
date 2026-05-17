#!/usr/bin/env python3
"""Lint：扫禁止直接调用 `lark-cli` 子进程的位置。

按 docs/执行中/gsd-借鉴-实施方案.md v3 §1 #1 落地：lark-cli 子进程调用必须
走 `scripts/_lib/lark_adapter.py` 统一封装，否则未来 fix（cwd workaround /
scope 名换代 / JSON shape 变化）会跨多处重复踩雷。

扫三类 pattern（避免误中错误信息字符串、文档教学段、changelog 提及等）：

  P1  "lark-cli"     —— 双引号字面量（argv list 头部）
  P2  'lark-cli'     —— 单引号字面量（同上）
  P3  subprocess.*lark-cli  —— 同一行里既出现 subprocess 又出现 lark-cli

scan 范围：scripts/ + skills/ + tests/

allowlist：
  - scripts/_lib/lark_adapter.py 自身（adapter 实现）
  - tests/helpers/fake-lark-cli.sh（adapter 的测试 shim）
  - tests/test-lark-adapter.sh / tests/test-lark-cli-lint.sh（测试本身）
  - SKILL.md 等文档里"lark-cli docs/api/auth 的命令行教学段"——通过行级
    pattern 豁免（grep `^[^#]*\blark-cli\s+(docs|api|auth)\b`），允许给 PM
    讲解命令行用法的句子但不允许给 AI 当 argv 使用
  - 任何含 `lint-skip-lark-cli` 注释的行（紧急逃生口）

用法：python3 scripts/check-lark-cli-direct-usage.py [<repo-root>]
exit code：0 干净；1 有违规
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


SCAN_DIRS = ("scripts", "skills", "tests")
SCAN_SUFFIXES = (".py", ".sh", ".md", ".bash")

# 文件级 allowlist（相对 repo root）
ALLOWLISTED_FILES = {
    "scripts/_lib/lark_adapter.py",
    "scripts/check-lark-cli-direct-usage.py",  # 本文件 self-reference
    "tests/helpers/fake-lark-cli.sh",
    "tests/test-lark-adapter.sh",
    "tests/test-lark-cli-lint.sh",
}

# 行级豁免：含此 marker 的行不报
LINE_LINT_SKIP = "lint-skip-lark-cli"

# 行级 doc-teaching 豁免（命令行教学段；要求 lark-cli 后面紧跟 docs/api/auth 子命令名）
DOC_TEACHING_RE = re.compile(r"\blark-cli\s+(docs|api|auth)\b")

# P1 / P2 / P3
P_DOUBLE = re.compile(r'"lark-cli"')
P_SINGLE = re.compile(r"'lark-cli'")
P_SUBPROCESS = re.compile(r"subprocess[^\n]*lark-cli")


def is_doc_teaching_line(line: str) -> bool:
    """True if the line is plain prose / shell example mentioning lark-cli."""
    if LINE_LINT_SKIP in line:
        return True
    # Markdown 教学段：lark-cli docs/api/auth ...（命令行直接示例）
    if DOC_TEACHING_RE.search(line):
        # 但若同一行还含 "lark-cli" / 'lark-cli'（字符串字面量），仍要警告
        if not (P_DOUBLE.search(line) or P_SINGLE.search(line)):
            return True
    return False


def scan_file(path: Path) -> list[tuple[int, str, str]]:
    """Return [(lineno, pattern_name, line), ...] for offending lines."""
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return []
    findings: list[tuple[int, str, str]] = []
    for lineno, line in enumerate(text.splitlines(), 1):
        if is_doc_teaching_line(line):
            continue
        if P_DOUBLE.search(line):
            findings.append((lineno, 'P1 "lark-cli"', line.rstrip()))
            continue
        if P_SINGLE.search(line):
            findings.append((lineno, "P2 'lark-cli'", line.rstrip()))
            continue
        if P_SUBPROCESS.search(line):
            findings.append((lineno, "P3 subprocess+lark-cli", line.rstrip()))
    return findings


def main() -> int:
    repo_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.cwd()

    violations: list[tuple[Path, int, str, str]] = []
    for d in SCAN_DIRS:
        root = repo_root / d
        if not root.exists():
            continue
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            if path.suffix not in SCAN_SUFFIXES:
                continue
            rel = str(path.relative_to(repo_root))
            if rel in ALLOWLISTED_FILES:
                continue
            for lineno, ptn, line in scan_file(path):
                violations.append((path.relative_to(repo_root), lineno, ptn, line))

    if not violations:
        print("✓ check-lark-cli-direct-usage: 干净，所有 lark-cli 子进程调用走 _lib/lark_adapter.py")
        return 0

    print(f"✗ check-lark-cli-direct-usage: 发现 {len(violations)} 处直接调用 / 字面量：", file=sys.stderr)
    for rel, lineno, ptn, line in violations:
        print(f"  {rel}:{lineno}  [{ptn}]  {line}", file=sys.stderr)
    print("", file=sys.stderr)
    print(
        "请改走 `from _lib.lark_adapter import ...`（version / auth_status /\n"
        "auth_check / docs_create_from_markdown / docs_update_from_markdown /\n"
        "api_json）。若是给 PM 看的命令行教学段，确认行里有"
        " `lark-cli (docs|api|auth) ...` 形式即可。\n"
        "紧急逃生口：行尾加 `# lint-skip-lark-cli` 注释。",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
