"""Read, validate, and write `.pm-workflow/project.yml` without PyYAML.

The file is intentionally a small, closed YAML subset: nested mappings plus
scalar lists.  Keeping the parser here makes the project-definition contract
available in a zero-dependency PMAI install while still failing closed on
ambiguous or unsupported YAML.
"""

from __future__ import annotations

import hashlib
import json
import re
import shlex
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any


SCHEMA_VERSION = 1
VALID_PROJECT_TYPES = {"prototype", "product"}
STACK_KEYS = ("language", "runtime", "framework", "package_manager")
COMMAND_KEYS = {"install", "build", "test", "typecheck"}


class ProjectDefinitionError(ValueError):
    """Raised when project.yml is missing, malformed, or semantically invalid."""


def _strip_comment(line: str) -> str:
    in_single = False
    in_double = False
    for index, char in enumerate(line):
        if char == "'" and not in_double:
            in_single = not in_single
        elif char == '"' and not in_single:
            in_double = not in_double
        elif char == "#" and not in_single and not in_double:
            return line[:index]
    return line


def _scalar(value: str) -> Any:
    value = value.strip()
    if not value:
        raise ProjectDefinitionError("空标量必须写成嵌套 mapping，不能留空。")
    if value == "{}":
        return {}
    if len(value) >= 2 and value[0] == value[-1] == '"':
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError as exc:
            raise ProjectDefinitionError(f"双引号标量不是合法 JSON 字符串：{value}") from exc
        if not isinstance(parsed, str):
            raise ProjectDefinitionError("双引号标量必须解析为字符串。")
        return parsed
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    if value in {"true", "false"}:
        return value == "true"
    if value in {"null", "~"}:
        return None
    if re.fullmatch(r"-?[0-9]+", value):
        return int(value)
    return value


def parse_yaml_subset(text: str) -> dict[str, Any]:
    """Parse PMAI's closed project.yml subset."""

    lines: list[tuple[int, str, int]] = []
    for number, raw in enumerate(text.splitlines(), 1):
        if "\t" in raw:
            raise ProjectDefinitionError(f"第 {number} 行包含 tab；project.yml 只能用空格缩进。")
        clean = _strip_comment(raw).rstrip()
        if not clean.strip():
            continue
        indent = len(clean) - len(clean.lstrip(" "))
        if indent % 2:
            raise ProjectDefinitionError(f"第 {number} 行缩进必须是 2 的倍数。")
        lines.append((indent, clean.strip(), number))

    def parse_block(index: int, indent: int) -> tuple[Any, int]:
        if index >= len(lines) or lines[index][0] != indent:
            raise ProjectDefinitionError("YAML 嵌套结构缺少内容。")
        is_list = lines[index][1].startswith("- ")
        container: Any = [] if is_list else {}
        while index < len(lines):
            current_indent, content, number = lines[index]
            if current_indent < indent:
                break
            if current_indent > indent:
                raise ProjectDefinitionError(f"第 {number} 行出现无父节点的缩进。")
            if is_list:
                if not content.startswith("- "):
                    raise ProjectDefinitionError(f"第 {number} 行混用了 list 和 mapping。")
                item = content[2:].strip()
                if not item or ":" in item:
                    raise ProjectDefinitionError(
                        f"第 {number} 行只允许标量列表，不支持嵌套对象列表。"
                    )
                container.append(_scalar(item))
                index += 1
                continue
            if content.startswith("- ") or ":" not in content:
                raise ProjectDefinitionError(f"第 {number} 行不是合法 mapping。")
            key, raw_value = content.split(":", 1)
            key = key.strip()
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]*", key):
                raise ProjectDefinitionError(f"第 {number} 行 key 不合法：{key!r}。")
            if key in container:
                raise ProjectDefinitionError(f"第 {number} 行 key 重复：{key}。")
            raw_value = raw_value.strip()
            index += 1
            if raw_value:
                container[key] = _scalar(raw_value)
            else:
                if index >= len(lines) or lines[index][0] <= indent:
                    raise ProjectDefinitionError(f"第 {number} 行 {key} 缺少嵌套内容。")
                container[key], index = parse_block(index, lines[index][0])
        return container, index

    if not lines:
        raise ProjectDefinitionError("project.yml 为空。")
    result, end = parse_block(0, lines[0][0])
    if lines[0][0] != 0 or end != len(lines) or not isinstance(result, dict):
        raise ProjectDefinitionError("project.yml 顶层必须是无缩进 mapping。")
    return result


def _mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ProjectDefinitionError(f"{label} 必须是 mapping。")
    return value


def _text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ProjectDefinitionError(f"{label} 必须是非空字符串。")
    return value.strip()


def _relative_path(value: Any, label: str, *, allow_dot: bool = False) -> str:
    text = _text(value, label)
    if "\\" in text:
        raise ProjectDefinitionError(f"{label} 必须使用仓库相对 POSIX 路径。")
    path = PurePosixPath(text)
    if path.is_absolute() or ".." in path.parts:
        raise ProjectDefinitionError(f"{label} 禁止绝对路径或路径穿越：{text}")
    if text == "." and allow_dot:
        return text
    if text in {".", ""}:
        raise ProjectDefinitionError(f"{label} 不能是空路径。")
    return text


def _path_within(path: str, parent: str) -> bool:
    return parent == "." or path == parent or path.startswith(parent.rstrip("/") + "/")


def duplicate_root_prefix(command: str, root: str) -> tuple[int, int] | None:
    """Return the token slice that redundantly selects implementation.root."""

    if root == ".":
        return None
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError as exc:
        raise ProjectDefinitionError(f"命令 shell quoting 不合法：{command}: {exc}") from exc
    if not tokens:
        return None
    executable = PurePosixPath(tokens[0]).name
    option_names = {
        "npm": {"--prefix"},
        "pnpm": {"--dir", "-C"},
        "yarn": {"--cwd"},
    }.get(executable, set())
    for index, token in enumerate(tokens[1:], 1):
        if token in {"&&", ";", "||", "|"}:
            break
        if token in option_names and index + 1 < len(tokens):
            if tokens[index + 1].rstrip("/") == root.rstrip("/"):
                return index, index + 2
        for option in option_names:
            prefix = option + "="
            if token.startswith(prefix) and token[len(prefix) :].rstrip("/") == root.rstrip("/"):
                return index, index + 1
    if len(tokens) >= 3 and tokens[0] == "cd" and tokens[1].rstrip("/") == root.rstrip("/"):
        if tokens[2] in {"&&", ";"}:
            return 0, 3
    return None


def adapt_legacy_root_command(command: str, root: str) -> tuple[str, bool]:
    """Strip one exact duplicate cwd selector for an explicitly recovered legacy build."""

    match = duplicate_root_prefix(command, root)
    if match is None:
        return command, False
    tokens = shlex.split(command, posix=True)
    start, end = match
    adapted = tokens[:start] + tokens[end:]
    if not adapted:
        raise ProjectDefinitionError("legacy cwd adapter 移除重复 root 后命令为空。")
    return shlex.join(adapted), True


def validate_execution_semantics(data: dict[str, Any]) -> None:
    implementation = data["implementation"]
    root = str(implementation["root"])
    for index, entrypoint in enumerate(implementation["entrypoints"]):
        if not _path_within(str(entrypoint).rstrip("/"), root.rstrip("/")):
            raise ProjectDefinitionError(
                f"implementation.entrypoints[{index}] 必须位于 implementation.root 内："
                f"root={root} entrypoint={entrypoint}"
            )
    executable_commands = {
        **data["commands"],
        **({"web.start": data["web"]["start"]} if data["web"]["enabled"] else {}),
    }
    for name, command in executable_commands.items():
        if duplicate_root_prefix(str(command), root) is not None:
            raise ProjectDefinitionError(
                f"{name} 会从 implementation.root 执行，不能再次指定同一目录：{root}。"
            )


def validate_project_definition(
    data: dict[str, Any], *, strict_execution: bool = False
) -> dict[str, Any]:
    allowed_top = {"schema_version", "definition", "project", "implementation", "commands", "web"}
    unknown_top = sorted(set(data) - allowed_top)
    if unknown_top:
        raise ProjectDefinitionError("project.yml 含未知顶层字段：" + "、".join(unknown_top))
    if data.get("schema_version") != SCHEMA_VERSION:
        raise ProjectDefinitionError(f"schema_version 必须是 {SCHEMA_VERSION}。")

    definition = _mapping(data.get("definition"), "definition")
    unknown_definition = sorted(
        set(definition) - {"source", "source_hash", "design_revision", "decided_at"}
    )
    if unknown_definition:
        raise ProjectDefinitionError("definition 含未知字段：" + "、".join(unknown_definition))
    source = _relative_path(definition.get("source"), "definition.source")
    source_hash = _text(definition.get("source_hash"), "definition.source_hash")
    if not re.fullmatch(r"[0-9a-f]{64}", source_hash):
        raise ProjectDefinitionError("definition.source_hash 必须是 64 位小写 SHA-256。")
    revision = definition.get("design_revision")
    if not isinstance(revision, int) or isinstance(revision, bool) or revision < 1:
        raise ProjectDefinitionError("definition.design_revision 必须是正整数。")
    decided_at = _text(definition.get("decided_at"), "definition.decided_at")
    try:
        datetime.fromisoformat(decided_at.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ProjectDefinitionError("definition.decided_at 必须是 ISO-8601 时间。") from exc

    project = _mapping(data.get("project"), "project")
    unknown_project = sorted(set(project) - {"type"})
    if unknown_project:
        raise ProjectDefinitionError("project 含未知字段：" + "、".join(unknown_project))
    project_type = _text(project.get("type"), "project.type")
    if project_type not in VALID_PROJECT_TYPES:
        raise ProjectDefinitionError("project.type 必须是 prototype 或 product。")

    implementation = _mapping(data.get("implementation"), "implementation")
    unknown_implementation = sorted(set(implementation) - {"root", "entrypoints", "stack"})
    if unknown_implementation:
        raise ProjectDefinitionError(
            "implementation 含未知字段：" + "、".join(unknown_implementation)
        )
    root = _relative_path(implementation.get("root"), "implementation.root", allow_dot=True)
    entrypoints = implementation.get("entrypoints")
    if not isinstance(entrypoints, list) or not entrypoints:
        raise ProjectDefinitionError("implementation.entrypoints 必须是非空路径列表。")
    normalized_entrypoints = [
        _relative_path(value, f"implementation.entrypoints[{index}]")
        for index, value in enumerate(entrypoints)
    ]
    if len(set(normalized_entrypoints)) != len(normalized_entrypoints):
        raise ProjectDefinitionError("implementation.entrypoints 不能重复。")
    stack = _mapping(implementation.get("stack"), "implementation.stack")
    normalized_stack = {key: _text(stack.get(key), f"implementation.stack.{key}") for key in STACK_KEYS}
    unknown_stack = sorted(set(stack) - set(STACK_KEYS))
    if unknown_stack:
        raise ProjectDefinitionError("implementation.stack 含未知字段：" + "、".join(unknown_stack))

    commands = _mapping(data.get("commands"), "commands")
    unknown_commands = sorted(set(commands) - COMMAND_KEYS)
    if unknown_commands:
        raise ProjectDefinitionError("commands 含未知字段：" + "、".join(unknown_commands))
    normalized_commands = {key: _text(value, f"commands.{key}") for key, value in commands.items()}

    web_value = data.get("web", {"enabled": False})
    web = _mapping(web_value, "web")
    enabled = web.get("enabled")
    if not isinstance(enabled, bool):
        raise ProjectDefinitionError("web.enabled 必须是 true 或 false。")
    normalized_web: dict[str, Any] = {"enabled": enabled}
    if enabled:
        start = _text(web.get("start"), "web.start")
        if "{port}" not in start:
            raise ProjectDefinitionError("web.start 必须包含 {port} 占位符。")
        normalized_web["start"] = start
        ready_path = _text(web.get("ready_path"), "web.ready_path")
        if not ready_path.startswith("/"):
            raise ProjectDefinitionError("web.ready_path 必须以 / 开头。")
        normalized_web["ready_path"] = ready_path
        ports = web.get("ports")
        if not isinstance(ports, list) or not ports:
            raise ProjectDefinitionError("web.enabled=true 时 web.ports 必须是非空端口列表。")
        if any(not isinstance(port, int) or isinstance(port, bool) or not 1 <= port <= 65535 for port in ports):
            raise ProjectDefinitionError("web.ports 必须全部是 1-65535 的整数。")
        if len(set(ports)) != len(ports):
            raise ProjectDefinitionError("web.ports 不能重复。")
        normalized_web["ports"] = ports
        unknown_web = sorted(set(web) - {"enabled", "start", "ready_path", "ports"})
    else:
        unknown_web = sorted(set(web) - {"enabled"})
        if unknown_web:
            raise ProjectDefinitionError(
                "web.enabled=false 时不能保留 Web 运行字段：" + "、".join(unknown_web)
            )

    result = {
        "schema_version": SCHEMA_VERSION,
        "definition": {
            "source": source,
            "source_hash": source_hash,
            "design_revision": revision,
            "decided_at": decided_at,
        },
        "project": {"type": project_type},
        "implementation": {
            "root": root,
            "entrypoints": normalized_entrypoints,
            "stack": normalized_stack,
        },
        "commands": normalized_commands,
        "web": normalized_web,
    }
    if strict_execution:
        validate_execution_semantics(result)
    return result


def load_project_definition(path: Path, *, strict_execution: bool = False) -> dict[str, Any]:
    if not path.is_file():
        raise ProjectDefinitionError(
            f"缺少项目建造定义：{path}。请先完成 /pmai-design，让定稿的需求生成 project.yml。"
        )
    try:
        data = parse_yaml_subset(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ProjectDefinitionError(f"无法读取 {path}: {exc}") from exc
    return validate_project_definition(data, strict_execution=strict_execution)


def source_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _yaml_text(value: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_./{}:+-]+(?: [A-Za-z0-9_./{}:+-]+)*", value) and "#" not in value:
        return value
    return json.dumps(value, ensure_ascii=False)


def render_project_definition(data: dict[str, Any]) -> str:
    data = validate_project_definition(data, strict_execution=True)
    definition = data["definition"]
    implementation = data["implementation"]
    stack = implementation["stack"]
    lines = [
        f"schema_version: {SCHEMA_VERSION}",
        "",
        "definition:",
        f"  source: {_yaml_text(definition['source'])}",
        f"  source_hash: {definition['source_hash']}",
        f"  design_revision: {definition['design_revision']}",
        f"  decided_at: {_yaml_text(definition['decided_at'])}",
        "",
        "project:",
        f"  type: {data['project']['type']}",
        "",
        "implementation:",
        f"  root: {_yaml_text(implementation['root'])}",
        "  entrypoints:",
    ]
    lines.extend(f"    - {_yaml_text(path)}" for path in implementation["entrypoints"])
    lines.extend(["", "  stack:"])
    lines.extend(f"    {key}: {_yaml_text(stack[key])}" for key in STACK_KEYS)
    if data["commands"]:
        lines.extend(["", "commands:"])
        lines.extend(f"  {key}: {_yaml_text(value)}" for key, value in data["commands"].items())
    else:
        lines.extend(["", "commands: {}"])
    web = data["web"]
    lines.extend(["", "web:", f"  enabled: {'true' if web['enabled'] else 'false'}"])
    if web["enabled"]:
        lines.extend(
            [
                f"  start: {_yaml_text(web['start'])}",
                f"  ready_path: {_yaml_text(web['ready_path'])}",
                "  ports:",
            ]
        )
        lines.extend(f"    - {port}" for port in web["ports"])
    return "\n".join(lines) + "\n"
