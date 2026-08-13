#!/usr/bin/env python3
"""Validate, inspect, or write the design-approved PMAI project definition."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from _lib.project_definition import (
    ProjectDefinitionError,
    load_project_definition,
    render_project_definition,
    source_sha256,
    validate_project_definition,
)


def definition_path(repo_root: Path) -> Path:
    return repo_root.expanduser().resolve() / ".pm-workflow" / "project.yml"


def build_plan(data: dict[str, object]) -> dict[str, object]:
    """Return only the durable construction plan, excluding decision metadata."""

    return {
        "project": data["project"],
        "implementation": data["implementation"],
        "commands": data["commands"],
        "web": data["web"],
    }


def cmd_validate(args: argparse.Namespace) -> int:
    data = load_project_definition(
        definition_path(Path(args.repo_root)), strict_execution=True
    )
    print(json.dumps(data, ensure_ascii=False, indent=2))
    return 0


def cmd_type(args: argparse.Namespace) -> int:
    data = load_project_definition(definition_path(Path(args.repo_root)))
    print(data["project"]["type"])
    return 0


def cmd_write(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).expanduser().resolve()
    output = definition_path(repo_root)
    source = Path(args.source)
    source_path = source if source.is_absolute() else repo_root / source
    if not source_path.is_file():
        raise ProjectDefinitionError(f"definition.source 不存在：{source_path}")

    commands = {
        key: value
        for key, value in {
            "install": args.install_command,
            "build": args.build_command,
            "test": args.test_command,
            "typecheck": args.typecheck_command,
        }.items()
        if value
    }
    web = {"enabled": bool(args.web_start)}
    if args.web_start:
        web.update(
            {
                "start": args.web_start,
                "ready_path": args.web_ready_path,
                "ports": args.web_port,
            }
        )
    existing = load_project_definition(output) if output.exists() else None
    if existing:
        initial_revision = existing["definition"]["design_revision"]
        initial_decided_at = existing["definition"]["decided_at"]
    else:
        initial_revision = args.design_revision if args.design_revision is not None else 1
        initial_decided_at = args.decided_at or datetime.now(timezone.utc).astimezone().isoformat(
            timespec="seconds"
        )
    data = validate_project_definition(
        {
            "schema_version": 1,
            "definition": {
                "source": source_path.relative_to(repo_root).as_posix(),
                "source_hash": source_sha256(source_path),
                "design_revision": initial_revision,
                "decided_at": initial_decided_at,
            },
            "project": {"type": args.project_type},
            "implementation": {
                "root": args.root,
                "entrypoints": args.entrypoint,
                "stack": {
                    "language": args.language,
                    "runtime": args.runtime,
                    "framework": args.framework,
                    "package_manager": args.package_manager,
                },
            },
            "commands": commands,
            "web": web,
        },
        strict_execution=True,
    )

    if existing and build_plan(existing) == build_plan(data):
        print(json.dumps(existing, ensure_ascii=False, indent=2))
        return 0

    if existing:
        if not args.allow_redefinition:
            raise ProjectDefinitionError(
                "修改既有项目建造方案必须有 PM 明确确认，并传 --allow-redefinition。"
            )
        minimum = existing["definition"]["design_revision"] + 1
        revision = args.design_revision if args.design_revision is not None else minimum
        if revision < minimum:
            raise ProjectDefinitionError(f"design_revision 必须至少递增到 {minimum}。")
        data["definition"] = {
            "source": source_path.relative_to(repo_root).as_posix(),
            "source_hash": source_sha256(source_path),
            "design_revision": revision,
            "decided_at": args.decided_at
            or datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        }
        data = validate_project_definition(data, strict_execution=True)

    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.name}.tmp")
    temporary.write_text(render_project_definition(data), encoding="utf-8")
    temporary.replace(output)
    print(json.dumps(data, ensure_ascii=False, indent=2))
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    for name, func in (("validate", cmd_validate), ("show", cmd_validate), ("type", cmd_type)):
        command = sub.add_parser(name)
        command.add_argument("repo_root", nargs="?", default=".")
        command.set_defaults(func=func)

    write = sub.add_parser("write")
    write.add_argument("repo_root")
    write.add_argument("--source", required=True)
    write.add_argument("--type", dest="project_type", choices=("prototype", "product"), required=True)
    write.add_argument("--root", required=True)
    write.add_argument("--entrypoint", action="append", required=True)
    write.add_argument("--language", required=True)
    write.add_argument("--runtime", required=True)
    write.add_argument("--framework", required=True)
    write.add_argument("--package-manager", required=True)
    write.add_argument("--install-command")
    write.add_argument("--build-command")
    write.add_argument("--test-command")
    write.add_argument("--typecheck-command")
    write.add_argument("--web-start")
    write.add_argument("--web-ready-path", default="/")
    write.add_argument("--web-port", action="append", type=int, default=[])
    write.add_argument("--design-revision", type=int)
    write.add_argument("--decided-at")
    write.add_argument("--allow-redefinition", action="store_true")
    write.set_defaults(func=cmd_write)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        return args.func(args)
    except (ProjectDefinitionError, ValueError) as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
