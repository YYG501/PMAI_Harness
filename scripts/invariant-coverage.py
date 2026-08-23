#!/usr/bin/env python3
"""Check the Harness evidence index embedded in INVARIANTS.md.

The invariant prose remains the only source of truth. The embedded JSON is an
auditable index that links selected invariants to existing guards, deterministic
tests, and session cases without defining a second lifecycle or policy.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
MARKER_RE = re.compile(
    r"<!-- BEGIN PMAI HARNESS COVERAGE JSON -->\s*```json\s*"
    r"(?P<payload>.*?)\s*```\s*"
    r"<!-- END PMAI HARNESS COVERAGE JSON -->",
    re.DOTALL,
)
INVARIANT_RE = re.compile(r"\*\*(I-[A-Z]+[0-9]+)\*\*")
VALID_STATUSES = {"deterministic-only", "session-gap", "session-verified"}


class CoverageError(RuntimeError):
    pass


def relative_path(repo_root: Path, raw: Any, label: str) -> Path:
    if not isinstance(raw, str) or not raw.strip():
        raise CoverageError(f"{label} 必须是非空字符串")
    path = Path(raw)
    if path.is_absolute() or ".." in path.parts:
        raise CoverageError(f"{label} 必须是仓内相对路径: {raw}")
    resolved = (repo_root / path).resolve()
    try:
        resolved.relative_to(repo_root.resolve())
    except ValueError as exc:
        raise CoverageError(f"{label} 越出仓库: {raw}") from exc
    if not resolved.exists():
        raise CoverageError(f"{label} 指向不存在路径: {raw}")
    return resolved


def read_index(source: Path) -> tuple[set[str], dict[str, Any]]:
    try:
        text = source.read_text(encoding="utf-8")
    except OSError as exc:
        raise CoverageError(f"无法读取 {source}: {exc}") from exc
    invariant_ids = set(INVARIANT_RE.findall(text))
    match = MARKER_RE.search(text)
    if not match:
        raise CoverageError("INVARIANTS.md 缺少 Harness coverage JSON 区块")
    try:
        payload = json.loads(match.group("payload"))
    except json.JSONDecodeError as exc:
        raise CoverageError(f"Harness coverage JSON 不合法: {exc}") from exc
    if not isinstance(payload, dict):
        raise CoverageError("Harness coverage JSON 顶层必须是对象")
    return invariant_ids, payload


def validate(source: Path, repo_root: Path) -> tuple[int, int, int]:
    invariant_ids, payload = read_index(source)
    if payload.get("schema_version") != SCHEMA_VERSION:
        raise CoverageError(f"schema_version 必须为 {SCHEMA_VERSION}")
    prefixes = payload.get("scope_prefixes")
    if not isinstance(prefixes, list) or any(not isinstance(item, str) for item in prefixes):
        raise CoverageError("scope_prefixes 必须是字符串数组")
    entries = payload.get("invariants")
    if not isinstance(entries, dict):
        raise CoverageError("invariants 必须是对象")

    scoped_ids = {
        invariant_id
        for invariant_id in invariant_ids
        if any(invariant_id.startswith(prefix) for prefix in prefixes)
    }
    mapped_ids = set(entries)
    unknown = sorted(mapped_ids - invariant_ids)
    missing = sorted(scoped_ids - mapped_ids)
    if unknown:
        raise CoverageError(f"coverage 包含未知不变量: {unknown}")
    if missing:
        raise CoverageError(f"coverage 缺少不变量: {missing}")

    session_gap = 0
    for invariant_id in sorted(scoped_ids):
        entry = entries[invariant_id]
        if not isinstance(entry, dict):
            raise CoverageError(f"{invariant_id} 必须映射为对象")
        guards = entry.get("guard")
        tests = entry.get("tests")
        session_cases = entry.get("session_cases")
        status = entry.get("status")
        if not isinstance(guards, list) or not guards:
            raise CoverageError(f"{invariant_id}.guard 必须是非空数组")
        if not isinstance(tests, list) or not tests:
            raise CoverageError(f"{invariant_id}.tests 必须是非空数组")
        if not isinstance(session_cases, list) or any(
            not isinstance(item, str) or not item.strip() for item in session_cases
        ):
            raise CoverageError(f"{invariant_id}.session_cases 必须是字符串数组")
        if status not in VALID_STATUSES:
            raise CoverageError(f"{invariant_id}.status 不支持: {status}")
        if status == "session-gap":
            session_gap += 1
        for index, raw in enumerate(guards, 1):
            relative_path(repo_root, raw, f"{invariant_id}.guard[{index}]")
        for index, raw in enumerate(tests, 1):
            relative_path(repo_root, raw, f"{invariant_id}.tests[{index}]")
        for index, case_id in enumerate(session_cases, 1):
            if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", case_id):
                raise CoverageError(f"{invariant_id}.session_cases[{index}] id 不合法: {case_id}")
            relative_path(repo_root, f"evals/cases/{case_id}.json", f"{invariant_id}.session_cases[{index}]")

    return len(scoped_ids), len(mapped_ids), session_gap


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="INVARIANTS.md")
    parser.add_argument("--repo-root", default=None)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = Path(args.source).expanduser().resolve()
    repo_root = Path(args.repo_root).expanduser().resolve() if args.repo_root else source.parent
    try:
        scoped, mapped, session_gap = validate(source, repo_root)
    except CoverageError as exc:
        print(f"FAIL invariant-coverage: {exc}")
        return 1
    print(f"PASS invariant-coverage: scoped={scoped} mapped={mapped} session_gap={session_gap}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
