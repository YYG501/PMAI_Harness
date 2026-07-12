#!/usr/bin/env python3
"""Compile adaptive acceptance checks for prototype or product builds."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from _lib.project_definition import ProjectDefinitionError, load_project_definition


def path_under(path: str, root: str) -> bool:
    normalized_path = path.strip("/")
    normalized_root = root.strip("/")
    return normalized_root in {"", "."} or normalized_path == normalized_root or normalized_path.startswith(normalized_root + "/")


def definition_ui_selected(definition: dict, paths: list[str]) -> bool:
    if definition.get("web", {}).get("enabled") is not True:
        return False
    if not paths:
        return True
    entrypoints = definition["implementation"]["entrypoints"]
    return any(path_under(path, root) for path in paths for root in entrypoints)


def compile_profile(args: argparse.Namespace) -> dict:
    repo_root = Path(args.repo_root).expanduser().resolve()
    paths = list(dict.fromkeys(args.path or []))
    definition_path = Path(args.project_definition).expanduser()
    definition_path = definition_path if definition_path.is_absolute() else repo_root / definition_path
    try:
        definition = load_project_definition(definition_path)
    except ProjectDefinitionError as exc:
        raise SystemExit(str(exc)) from exc
    target = definition["project"]["type"]
    has_ui = definition_ui_selected(definition, paths)
    configured_commands = definition["commands"]
    checks: list[dict] = []
    if target == "prototype":
        if has_ui:
            checks.append({"name": "browser-smoke", "purpose": "用主动浏览器能力确认原型可访问", "command": None})
        checks.append({"name": "coverage", "purpose": "逐项核对建造依据、页面和状态覆盖", "command": None})
        if has_ui:
            checks.extend(
                [
                    {"name": "visual", "purpose": "对照 DESIGN.md 检查视觉一致性", "command": None},
                    {"name": "behavior", "purpose": "用主动浏览器走通关键任务和异常路径", "command": None},
                ]
            )
    else:
        checks.append({"name": "scope-coverage", "purpose": "逐项核对规格与真实实现", "command": None})
        for name, key in (("tests", "test"), ("typecheck", "typecheck"), ("build", "build")):
            if key in configured_commands:
                checks.append(
                    {
                        "name": name,
                        "purpose": f"运行 project.yml 声明的 {name} 检查",
                        "command": configured_commands[key],
                    }
                )
        if has_ui:
            checks.extend(
                [
                    {"name": "browser-smoke", "purpose": "用主动浏览器能力确认真实产品 UI 可访问", "command": None},
                    {"name": "visual", "purpose": "检查 UI 与现有设计基线一致", "command": None},
                    {"name": "behavior", "purpose": "用主动浏览器走通真实产品关键任务", "command": None},
                ]
            )
        if args.data_migration:
            checks.append({"name": "migration", "purpose": "验证迁移、回滚和兼容读取", "command": None})
        if args.security_sensitive:
            checks.append({"name": "security", "purpose": "验证权限、安全和越权边界", "command": None})

    deduped: list[dict] = []
    seen: set[str] = set()
    for check in checks:
        if check["name"] not in seen:
            seen.add(check["name"])
            deduped.append(check)
    return {
        "schema_version": 1,
        "target": {"kind": target, "paths": paths},
        "required_checks": deduped,
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--repo-root", default=".")
    result.add_argument("--project-definition", required=True)
    result.add_argument("--path", action="append", default=[])
    result.add_argument("--data-migration", action="store_true")
    result.add_argument("--security-sensitive", action="store_true")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    print(json.dumps(compile_profile(args), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
