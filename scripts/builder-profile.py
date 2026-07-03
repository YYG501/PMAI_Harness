#!/usr/bin/env python3
"""Read PMAI builder profiles from .pm-workflow/config.yml.

This intentionally parses only the small YAML subset used by
templates/pm-workflow.config.yml.tmpl: builder.default_profile and
builder.profiles.<name> scalar fields. Keeping it stdlib-only lets consumer
repos use the helper without installing PyYAML.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


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


def parse_scalar(value: str) -> Any:
    value = value.strip()
    if value in ("true", "True"):
        return True
    if value in ("false", "False"):
        return False
    if value in ("null", "Null", "~"):
        return None
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    try:
        return int(value)
    except ValueError:
        return value


def load_builder_config(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise SystemExit(f"找不到配置文件: {path}")

    default_profile = ""
    profiles: dict[str, dict[str, Any]] = {}
    in_builder = False
    in_profiles = False
    current_profile = ""

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = strip_comment(raw_line).rstrip()
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip(" "))
        text = line.strip()
        if ":" not in text:
            continue
        key, value = text.split(":", 1)
        key = key.strip()
        value = value.strip()

        if indent == 0:
            in_builder = key == "builder"
            in_profiles = False
            current_profile = ""
            continue
        if not in_builder:
            continue

        if indent == 2 and key == "default_profile":
            default_profile = str(parse_scalar(value))
            continue
        if indent == 2 and key == "profiles":
            in_profiles = True
            current_profile = ""
            continue
        if not in_profiles:
            continue
        if indent == 4 and not value:
            current_profile = key
            profiles[current_profile] = {}
            continue
        if indent == 6 and current_profile:
            profiles[current_profile][key] = parse_scalar(value)

    return {"default_profile": default_profile, "profiles": profiles}


def profile_display(name: str, profile: dict[str, Any]) -> str:
    label = str(profile.get("label") or name)
    model = str(profile.get("display_model") or profile.get("model") or "")
    thinking = str(profile.get("thinking") or "")
    if model and thinking:
        return f"{label}（{model}, {thinking}）"
    if model:
        return f"{label}（{model}）"
    return label


def resolve_profile(
    config: dict[str, Any],
    profile_name: str,
    model_override: str | None,
    thinking_override: str | None,
) -> dict[str, Any]:
    profiles = config["profiles"]
    if profile_name not in profiles:
        raise SystemExit(f"找不到 builder profile: {profile_name}")

    profile = dict(profiles[profile_name])
    overrides: dict[str, bool] = {}
    if model_override:
        profile["model"] = model_override
        profile.pop("display_model", None)
        overrides["model"] = True
    if thinking_override:
        profile["thinking"] = thinking_override
        overrides["thinking"] = True
    if overrides:
        profile["overrides"] = overrides

    executor = profile.get("executor")
    if not isinstance(executor, str) or not executor:
        raise SystemExit(f"builder profile 缺少 executor: {profile_name}")

    return {
        "builder_profile": profile_name,
        "executor": executor,
        "display": profile_display(profile_name, profile),
        "builder": {
            key: value
            for key, value in profile.items()
            if key not in ("label", "executor")
        },
    }


def cmd_list(args: argparse.Namespace) -> None:
    config = load_builder_config(Path(args.config))
    rows = []
    for name, profile in config["profiles"].items():
        rows.append(
            {
                "name": name,
                "executor": profile.get("executor"),
                "display": profile_display(name, profile),
                "default": name == config["default_profile"],
            }
        )
    print(json.dumps({"default_profile": config["default_profile"], "profiles": rows}, ensure_ascii=False))


def cmd_resolve(args: argparse.Namespace) -> None:
    config = load_builder_config(Path(args.config))
    profile_name = args.profile or config["default_profile"]
    if not profile_name:
        raise SystemExit("builder.default_profile 为空，请明确指定 --profile")
    resolved = resolve_profile(config, profile_name, args.model, args.thinking)
    print(json.dumps(resolved, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    list_cmd = sub.add_parser("list", help="list builder profiles for PM choice")
    list_cmd.add_argument("config")
    list_cmd.set_defaults(func=cmd_list)

    resolve = sub.add_parser("resolve", help="resolve a profile into executor + builder snapshot")
    resolve.add_argument("config")
    resolve.add_argument("--profile")
    resolve.add_argument("--model")
    resolve.add_argument("--thinking")
    resolve.set_defaults(func=cmd_resolve)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.func(args)
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(f"❌ {exc.code}", file=sys.stderr)
            return 1
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
