#!/usr/bin/env python3
"""Resolve the project-level PMAI build type.

The source of truth is `.pm-workflow/project.yml:project.type`. Legacy
consumer repos may fall back to `.pm-workflow/config.yml:project.type` and
then the `auto-detected: ...` marker in CLAUDE.md. The helper never guesses
from the current request or changed paths.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from _lib.project_definition import ProjectDefinitionError, load_project_definition


VALID_TYPES = {"prototype", "product"}
LEGACY_TYPE_MAP = {
    "prototype": "prototype",
    "system": "product",
}


def strip_comment(line: str) -> str:
    in_single = False
    in_double = False
    for idx, char in enumerate(line):
        if char == "'" and not in_double:
            in_single = not in_single
        elif char == '"' and not in_single:
            in_double = not in_double
        elif char == "#" and not in_single and not in_double:
            return line[:idx]
    return line


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1]
    return value


def configured_type(config_path: Path) -> str | None:
    if not config_path.is_file():
        return None

    in_project = False
    saw_project = False
    for raw_line in config_path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw_line).rstrip()
        if not line.strip() or ":" not in line:
            continue
        indent = len(line) - len(line.lstrip(" "))
        key, value = line.strip().split(":", 1)
        key = key.strip()
        value = value.strip()
        if indent == 0:
            in_project = key == "project"
            saw_project = saw_project or in_project
            continue
        if in_project and indent == 2 and key == "type":
            project_type = unquote(value)
            if project_type not in VALID_TYPES:
                raise SystemExit(
                    f"{config_path}: project.type 必须是 prototype 或 product，当前是 {project_type or '<empty>'}。"
                )
            return project_type

    if saw_project:
        raise SystemExit(f"{config_path}: project.type 缺失；请明确写为 prototype 或 product。")
    return None


def legacy_type(claude_path: Path) -> str | None:
    if not claude_path.is_file():
        return None
    match = re.search(
        r"auto-detected:\s*(prototype|system|custom|unknown)\b",
        claude_path.read_text(encoding="utf-8"),
    )
    if not match:
        return None
    legacy = match.group(1)
    mapped = LEGACY_TYPE_MAP.get(legacy)
    if mapped:
        return mapped
    raise SystemExit(
        "旧项目的工程结构标记无法唯一确定项目类型。请在 "
        ".pm-workflow/config.yml 增加 project.type: prototype 或 project.type: product。"
    )


def resolve_project_type(repo_root: Path) -> str:
    repo_root = repo_root.expanduser().resolve()
    project_path = repo_root / ".pm-workflow" / "project.yml"
    if project_path.exists():
        try:
            return str(load_project_definition(project_path)["project"]["type"])
        except ProjectDefinitionError as exc:
            raise SystemExit(str(exc)) from exc
    config_path = repo_root / ".pm-workflow" / "config.yml"
    project_type = configured_type(config_path)
    if project_type:
        return project_type
    project_type = legacy_type(repo_root / "CLAUDE.md")
    if project_type:
        return project_type
    raise SystemExit(
        "项目尚未生成 PMAI 建造定义。请先完成 /pmai-design，由定稿需求生成 "
        ".pm-workflow/project.yml；build 不会按本轮需求临时猜测。"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo_root", nargs="?", default=".")
    args = parser.parse_args(argv)
    try:
        print(resolve_project_type(Path(args.repo_root)))
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(f"❌ {exc.code}", file=sys.stderr)
            return 1
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
