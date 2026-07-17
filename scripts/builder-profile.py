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
import shutil
import sys
from pathlib import Path
from typing import Any

from _lib.project_definition import ProjectDefinitionError, load_project_definition


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
    target_profiles: dict[str, str] = {}
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

        if indent == 2 and key.endswith("_profile"):
            parsed = str(parse_scalar(value))
            if key == "default_profile":
                default_profile = parsed
            elif key in {"prototype_profile", "product_profile"}:
                target_profiles[key.removesuffix("_profile")] = parsed
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

    return {
        "default_profile": default_profile,
        "target_profiles": target_profiles,
        "profiles": profiles,
    }


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
    if executor not in EXECUTOR_BINARIES:
        raise SystemExit(f"builder profile 使用了不受支持的 executor: {executor}")

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


CURRENT_HOSTS = {
    "claude-code",
    "codex",
    "cursor-agent",
    "kimi-code",
    "opencode",
    "unknown",
}


def profile_matches_current_host(profile: dict[str, Any], current_host: str) -> bool:
    return current_host != "unknown" and profile.get("executor") == current_host


def native_selection(reason: str) -> dict[str, Any]:
    return {
        "builder_profile": "native",
        "executor": "native",
        "display": "当前会话直接构建",
        "builder": {"model": "runtime", "thinking": "adaptive"},
        "selection_reason": reason,
    }


def native_list_row() -> dict[str, Any]:
    return {
        "name": "native",
        "executor": "native",
        "display": "当前会话直接构建",
        "default": False,
        "available": True,
    }


def cmd_list(args: argparse.Namespace) -> None:
    config_path = Path(args.config)
    if not config_path.exists():
        print(
            json.dumps(
                {
                    "default_profile": "",
                    "current_host": args.current_host,
                    "profiles": [native_list_row()],
                },
                ensure_ascii=False,
            )
        )
        return
    config = load_builder_config(config_path)
    rows = [native_list_row()]
    for name, profile in config["profiles"].items():
        if profile_matches_current_host(profile, args.current_host):
            continue
        available = profile_available(profile)
        if args.available_only and not available:
            continue
        rows.append(
            {
                "name": name,
                "executor": profile.get("executor"),
                "display": profile_display(name, profile),
                "default": name == config["default_profile"],
                "available": available,
            }
        )
    print(
        json.dumps(
            {
                "default_profile": config["default_profile"],
                "current_host": args.current_host,
                "profiles": rows,
            },
            ensure_ascii=False,
        )
    )


def cmd_resolve(args: argparse.Namespace) -> None:
    profile_name = args.profile
    if profile_name == "native":
        builder: dict[str, Any] = {"model": "runtime", "thinking": "adaptive"}
        if args.model:
            builder["model"] = args.model
        if args.thinking:
            builder["thinking"] = args.thinking
        print(
            json.dumps(
                {
                    "builder_profile": "native",
                    "executor": "native",
                    "display": "当前会话直接构建",
                    "builder": builder,
                },
                ensure_ascii=False,
            )
        )
        return
    config = load_builder_config(Path(args.config))
    profile_name = profile_name or config["default_profile"]
    if not profile_name:
        raise SystemExit("builder.default_profile 为空，请明确指定 --profile")
    profile = config["profiles"].get(profile_name)
    if profile is not None and profile_matches_current_host(profile, args.current_host):
        raise SystemExit(
            f"构建工具不能与当前主控相同: {profile_display(profile_name, profile)}"
        )
    resolved = resolve_profile(config, profile_name, args.model, args.thinking)
    print(json.dumps(resolved, ensure_ascii=False))


EXECUTOR_BINARIES = {
    "claude-code": "claude",
    "codex": "codex",
    "cursor-agent": "cursor-agent",
    "opencode": "opencode",
}


def profile_available(profile: dict[str, Any]) -> bool:
    executor = profile.get("executor")
    binary = EXECUTOR_BINARIES.get(str(executor))
    return bool(binary and shutil.which(binary))


def cmd_recommend(args: argparse.Namespace) -> None:
    """Recommend an available profile before the PM confirms the build card."""

    if args.project_definition:
        try:
            definition = load_project_definition(Path(args.project_definition).expanduser())
        except ProjectDefinitionError as exc:
            raise SystemExit(str(exc)) from exc
        target = definition["project"]["type"]
    else:
        # Hidden legacy `auto` alias only. Active callers must pass project.yml.
        target = args.target
    config_path = Path(args.config)
    if not config_path.exists():
        print(
            json.dumps(
                native_selection("旧消费仓没有 builder 配置，推荐当前会话直接构建"),
                ensure_ascii=False,
            )
        )
        return
    config = load_builder_config(config_path)
    profiles = config["profiles"]
    preferred = config.get("target_profiles", {}).get(target) or config["default_profile"]
    candidates = []
    if preferred:
        candidates.append(preferred)
    candidates.extend(name for name in profiles if name not in candidates)
    selected = next(
        (
            name
            for name in candidates
            if name in profiles
            and not profile_matches_current_host(profiles[name], args.current_host)
            and profile_available(profiles[name])
        ),
        None,
    )
    if selected:
        resolved = resolve_profile(config, selected, None, None)
        if selected == preferred:
            resolved["selection_reason"] = f"仓库为 {target} build 配置的默认档位可用"
        elif preferred in profiles and profile_matches_current_host(
            profiles[preferred], args.current_host
        ):
            resolved["selection_reason"] = (
                f"首选档位与当前主控 {args.current_host} 相同，已改用 {selected}"
            )
        else:
            resolved["selection_reason"] = f"首选档位不可用，推荐仓库内可用的 {selected}"
    else:
        resolved = native_selection("没有可用的外部构建工具，推荐当前会话直接构建")
    print(json.dumps(resolved, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    list_cmd = sub.add_parser("list", help="list configured builder profiles for diagnostics")
    list_cmd.add_argument("config")
    list_cmd.add_argument("--available-only", action="store_true")
    list_cmd.add_argument("--current-host", required=True, choices=sorted(CURRENT_HOSTS))
    list_cmd.set_defaults(func=cmd_list)

    resolve = sub.add_parser("resolve", help="resolve a profile into executor + builder snapshot")
    resolve.add_argument("config")
    resolve.add_argument("--profile")
    resolve.add_argument("--model")
    resolve.add_argument("--thinking")
    resolve.add_argument("--current-host", required=True, choices=sorted(CURRENT_HOSTS))
    resolve.set_defaults(func=cmd_resolve)

    recommend = sub.add_parser("recommend", help="recommend an available profile for PM confirmation")
    recommend.add_argument("config")
    recommend.add_argument("--project-definition", required=True)
    recommend.add_argument("--current-host", required=True, choices=sorted(CURRENT_HOSTS))
    recommend.set_defaults(target=None)
    recommend.set_defaults(func=cmd_recommend)

    # Backward-compatible internal alias for callers installed before the
    # confirmation-card flow. New skills must call `recommend`, not `auto`.
    auto = sub.add_parser("auto", help=argparse.SUPPRESS)
    auto.add_argument("config")
    auto.add_argument("--target", required=True, choices=("prototype", "product"))
    auto.add_argument("--current-host", choices=sorted(CURRENT_HOSTS), default="unknown")
    auto.set_defaults(project_definition=None)
    auto.set_defaults(func=cmd_recommend)

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
