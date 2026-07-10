#!/usr/bin/env python3
"""Compile adaptive acceptance checks for prototype or product builds."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def package_scripts(repo_root: Path) -> dict[str, str]:
    path = repo_root / "package.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    scripts = data.get("scripts") if isinstance(data, dict) else None
    return {str(key): str(value) for key, value in scripts.items()} if isinstance(scripts, dict) else {}


def package_runner(repo_root: Path) -> str:
    if (repo_root / "pnpm-lock.yaml").exists():
        return "pnpm"
    if (repo_root / "yarn.lock").exists():
        return "yarn"
    return "npm"


def script_command(runner: str, script: str) -> str:
    return f"{runner} {script}" if runner == "yarn" else f"{runner} run {script}"


def ui_detected(repo_root: Path, paths: list[str], override: str) -> bool:
    if override == "yes":
        return True
    if override == "no":
        return False
    # `Sources/` is intentionally not a UI hint: Swift packages and service
    # repositories commonly use it for CLIs or backend code. Native UI targets
    # must opt in with --ui yes until a native acceptance adapter is configured.
    hints = ("prototype/", "app/", "pages/", "src/components/", "src/app/")
    if paths:
        return any(path.startswith(hints) for path in paths)
    return any((repo_root / hint.rstrip("/")).exists() for hint in hints)


def compile_profile(args: argparse.Namespace) -> dict:
    repo_root = Path(args.repo_root).expanduser().resolve()
    paths = list(dict.fromkeys(args.path or []))
    checks: list[dict] = []
    if args.target == "prototype":
        checks.extend(
            [
                {"name": "browser-smoke", "purpose": "确认原型可启动并能进入页面", "command": None},
                {"name": "coverage", "purpose": "逐项核对建造依据、页面和状态覆盖", "command": None},
                {"name": "visual", "purpose": "对照 DESIGN.md 检查视觉一致性", "command": None},
                {"name": "behavior", "purpose": "走通关键任务和异常路径", "command": None},
            ]
        )
    else:
        scripts = package_scripts(repo_root)
        runner = package_runner(repo_root)
        checks.append({"name": "scope-coverage", "purpose": "逐项核对规格与真实实现", "command": None})
        for name, candidates in (
            ("tests", ("test", "test:unit", "test:ci")),
            ("typecheck", ("typecheck", "type-check", "check-types")),
            ("build", ("build",)),
        ):
            selected = next((candidate for candidate in candidates if candidate in scripts), None)
            if selected:
                checks.append(
                    {
                        "name": name,
                        "purpose": f"运行仓库已有 {name} 检查",
                        "command": script_command(runner, selected),
                    }
                )
        if len(checks) == 1:
            checks.append(
                {
                    "name": "repository-checks",
                    "purpose": "运行仓库文档中声明的现有验证命令",
                    "command": None,
                }
            )
        if ui_detected(repo_root, paths, args.ui):
            checks.extend(
                [
                    {"name": "browser-smoke", "purpose": "确认真实产品 UI 可访问", "command": None},
                    {"name": "visual", "purpose": "检查 UI 与现有设计基线一致", "command": None},
                    {"name": "behavior", "purpose": "走通真实产品关键任务", "command": None},
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
        "target": {"kind": args.target, "paths": paths},
        "required_checks": deduped,
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--repo-root", default=".")
    result.add_argument("--target", required=True, choices=("prototype", "product"))
    result.add_argument("--path", action="append", default=[])
    result.add_argument("--ui", choices=("auto", "yes", "no"), default="auto")
    result.add_argument("--data-migration", action="store_true")
    result.add_argument("--security-sensitive", action="store_true")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    print(json.dumps(compile_profile(args), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
