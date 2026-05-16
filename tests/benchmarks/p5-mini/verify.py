#!/usr/bin/env python3
"""
P5-mini verify: 跑单个 case 或全部 case 的 patch 校验 + apply + 比对 expected.

用法:
    python verify.py case-01           # 跑单个 case
    python verify.py                   # 跑全部 case，汇总报告

每个 case 目录结构:
    case-XX/
        input/    {modulespec.md, quickfix-log.md, commit-diff.md}
        actual/   patches.json          (AI 推理输出)
        expected/ modulespec.md         (人工预期)
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from dataclasses import dataclass, field
from typing import List


HERE = Path(__file__).resolve().parent


@dataclass
class CaseResult:
    case_id: str
    passed: bool
    fail_reasons: List[str] = field(default_factory=list)
    n_patches: int = 0
    n_unique_ok: int = 0
    n_overlap: int = 0
    diff_preview: str = ""


def split_frontmatter(text: str) -> tuple[str, str]:
    """返回 (frontmatter_block_含分隔符, body)。无 frontmatter 时第一段空。"""
    m = re.match(r"\A(---\n.*?\n---\n)(.*)\Z", text, re.DOTALL)
    if not m:
        return "", text
    return m.group(1), m.group(2)


def parse_commit_context(commit_diff_md: str) -> dict:
    """从 commit-diff.md 末尾的 context 段拉 req-id / after commit。"""
    out = {}
    m = re.search(r"req-id:\s*(\S+)", commit_diff_md)
    if m:
        out["req"] = m.group(1)
    m = re.search(r"last_modified_commit after:\s*(\S+)", commit_diff_md)
    if m:
        out["commit"] = m.group(1)
    return out


def rewrite_frontmatter(modulespec: str, ctx: dict) -> str:
    """把 modulespec 顶部 frontmatter 的 last_modified_req / last_modified_commit 改写为 ctx 值。
    这是 v3.2 §3.1 设计的"程序自动维护"的部分，AI patches 不处理 frontmatter。"""
    fm, body = split_frontmatter(modulespec)
    if not fm:
        return modulespec
    fm = re.sub(
        r"last_modified_req:\s*\S+",
        f"last_modified_req: {ctx.get('req', '?')}",
        fm,
    )
    fm = re.sub(
        r"last_modified_commit:\s*\S+",
        f"last_modified_commit: {ctx.get('commit', '?')}",
        fm,
    )
    return fm + body


def apply_patches(modulespec: str, patches: list) -> tuple[str, List[str], int, int]:
    """
    顺序应用 patches。返回 (final, fail_reasons, n_unique_ok, n_overlap)。

    校验:
      - old 在当前 modulespec 中恰好出现 1 次
      - old 至少包含 1 个 \n
      - 应用之后下一个 patch 的 old 仍能找到（否则视为重叠/相互覆盖）
    """
    fails: List[str] = []
    unique_ok = 0
    overlaps = 0
    current = modulespec
    for i, p in enumerate(patches):
        old = p.get("old", "")
        new = p.get("new", "")
        intent = p.get("intent", f"patch[{i}]")

        if "\n" not in old:
            fails.append(f"{intent}: old 不含换行（约束 2：至少 1 行）")
            continue

        n = current.count(old)
        if n == 0:
            # 可能是被前面的 patch 改掉了 → 视作重叠
            fails.append(f"{intent}: old 在当前 modulespec 中不存在（被前置 patch 覆盖或本就不存在）")
            overlaps += 1
            continue
        if n > 1:
            fails.append(f"{intent}: old 在 modulespec 中出现 {n} 次（约束 1：必须恰好 1 次）")
            continue

        unique_ok += 1
        current = current.replace(old, new, 1)

    return current, fails, unique_ok, overlaps


def normalize(s: str) -> str:
    """对比前规范化：去尾部空白 + 统一 EOF 换行。"""
    lines = [line.rstrip() for line in s.splitlines()]
    out = "\n".join(lines)
    return out.rstrip("\n") + "\n"


def make_diff_preview(actual: str, expected: str, n_context: int = 3) -> str:
    """简短 diff，给 fail case 看 — 自己实现避免依赖 difflib 的 ndiff 信息密度低。"""
    import difflib
    diff = difflib.unified_diff(
        expected.splitlines(keepends=True),
        actual.splitlines(keepends=True),
        fromfile="expected",
        tofile="actual",
        n=n_context,
    )
    return "".join(diff)[:2000]


def run_case(case_dir: Path) -> CaseResult:
    case_id = case_dir.name
    result = CaseResult(case_id=case_id, passed=False)

    patches_path = case_dir / "actual" / "patches.json"
    if not patches_path.exists():
        result.fail_reasons.append(f"actual/patches.json 不存在（推理未跑）")
        return result

    try:
        data = json.loads(patches_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        result.fail_reasons.append(f"patches.json 非法 JSON: {e}")
        return result

    patches = data.get("patches", None)
    if not isinstance(patches, list):
        result.fail_reasons.append("JSON 缺少 patches 数组")
        return result

    result.n_patches = len(patches)

    modulespec_in = (case_dir / "input" / "modulespec.md").read_text(encoding="utf-8")
    commit_diff = (case_dir / "input" / "commit-diff.md").read_text(encoding="utf-8")
    expected = (case_dir / "expected" / "modulespec.md").read_text(encoding="utf-8")

    intermediate, fails, unique_ok, overlaps = apply_patches(modulespec_in, patches)
    result.n_unique_ok = unique_ok
    result.n_overlap = overlaps
    result.fail_reasons.extend(fails)

    ctx = parse_commit_context(commit_diff)
    final = rewrite_frontmatter(intermediate, ctx)

    if normalize(final) == normalize(expected):
        result.passed = True
    else:
        if not result.fail_reasons:
            result.fail_reasons.append("patches 全部应用但 final ≠ expected（语义偏差或漏改）")
        result.diff_preview = make_diff_preview(normalize(final), normalize(expected))

    return result


def main(argv: List[str]) -> int:
    if len(argv) > 1:
        targets = [HERE / argv[1]]
    else:
        targets = sorted(HERE.glob("case-*"))

    results: List[CaseResult] = []
    for case_dir in targets:
        if not case_dir.is_dir():
            continue
        r = run_case(case_dir)
        results.append(r)

    n = len(results)
    n_pass = sum(1 for r in results if r.passed)
    pct = (n_pass / n * 100) if n else 0

    print()
    print("=" * 72)
    print(f"P5-mini results: {n_pass}/{n} pass ({pct:.0f}%)")
    print("=" * 72)
    for r in results:
        mark = "✓" if r.passed else "✗"
        print(f"  {mark} {r.case_id}  patches={r.n_patches}  uniq_ok={r.n_unique_ok}  overlap={r.n_overlap}")
        for reason in r.fail_reasons:
            print(f"      - {reason}")
        if r.diff_preview and not r.passed:
            print("      --- diff preview (expected vs actual) ---")
            for line in r.diff_preview.splitlines()[:30]:
                print(f"      {line}")
            print("      --- end preview ---")
    print()
    return 0 if n_pass == n else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
