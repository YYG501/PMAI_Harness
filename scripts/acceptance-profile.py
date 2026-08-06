#!/usr/bin/env python3
"""Compile adaptive acceptance checks for prototype or product builds."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from _lib.delivery_policy import delivery_policy_for, delivery_policy_hash
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
    delivery_policy = delivery_policy_for(target)
    has_ui = definition_ui_selected(definition, paths)
    configured_commands = definition["commands"]
    iteration_checks: list[dict] = []
    final_checks: list[dict] = []
    if "typecheck" in configured_commands:
        iteration_checks.append(
            {
                "name": "typecheck",
                "purpose": "快速确认本轮修改仍通过类型检查",
                "command": configured_commands["typecheck"],
            }
        )
    if has_ui:
        iteration_checks.append(
            {
                "name": "current-page",
                "purpose": "只走查 PM 当前查看的页面和本轮受影响交互",
                "command": None,
            }
        )
    if target == "prototype":
        final_checks.append(
            {
                "name": "prototype-boundary",
                "purpose": "确认本轮仍是可交互原型，未越界建设真实系统",
                "command": None,
            }
        )
        for name, key in (("tests", "test"), ("typecheck", "typecheck"), ("build", "build")):
            if key in configured_commands:
                final_checks.append(
                    {
                        "name": name,
                        "purpose": f"在冻结提交上运行 project.yml 声明的 {name} 检查",
                        "command": configured_commands[key],
                    }
                )
        if has_ui:
            final_checks.append(
                {
                    "name": "browser-acceptance",
                    "purpose": "在一个持续浏览器会话中批量验证受影响流程的可访问性、视觉和行为",
                    "command": None,
                }
            )
        final_checks.append({"name": "coverage", "purpose": "逐项核对建造依据、页面和状态覆盖", "command": None})
    else:
        final_checks.append({"name": "scope-coverage", "purpose": "逐项核对规格与真实实现", "command": None})
        for name, key in (("tests", "test"), ("typecheck", "typecheck"), ("build", "build")):
            if key in configured_commands:
                final_checks.append(
                    {
                        "name": name,
                        "purpose": f"在冻结提交上运行 project.yml 声明的 {name} 检查",
                        "command": configured_commands[key],
                    }
                )
        if has_ui:
            final_checks.append(
                {
                    "name": "browser-acceptance",
                    "purpose": "在一个持续浏览器会话中批量验证受影响流程的可访问性、视觉和行为",
                    "command": None,
                }
            )
        if args.data_migration:
            final_checks.append({"name": "migration", "purpose": "验证迁移、回滚和兼容读取", "command": None})
        if args.security_sensitive:
            final_checks.append({"name": "security", "purpose": "验证权限、安全和越权边界", "command": None})

    def dedupe(checks: list[dict]) -> list[dict]:
        result: list[dict] = []
        seen: set[str] = set()
        for check in checks:
            if check["name"] not in seen:
                seen.add(check["name"])
                result.append(check)
        return result

    iteration_checks = dedupe(iteration_checks)
    final_checks = dedupe(final_checks)
    return {
        "schema_version": 2,
        "target": {"kind": target, "paths": paths},
        "delivery_policy": delivery_policy,
        "delivery_policy_hash": delivery_policy_hash(delivery_policy),
        "iteration_checks": iteration_checks,
        "final_checks": final_checks,
        # Compatibility alias for older build hosts. New hosts consume final_checks.
        "required_checks": final_checks,
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
