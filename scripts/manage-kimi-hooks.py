#!/usr/bin/env python3
"""Install, check, or remove the PMAI-managed Kimi Code hook block.

Kimi Code currently stores hooks in the user-level config.toml.  PMAI keeps
its entries inside a marked block so install/upgrade/uninstall can update only
the fields it owns without parsing or rewriting provider credentials.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Python < 3.11 fallback
    tomllib = None


START_MARKER = "# >>> PMAI managed Kimi Code hooks >>>"
END_MARKER = "# <<< PMAI managed Kimi Code hooks <<<"
MANAGED_BLOCK = f'''{START_MARKER}
[[hooks]]
event = "PreToolUse"
matcher = "Edit|Write"
command = "bash \\"${{PMAI_HOME:-$HOME/.pmai}}/scripts/kimi-hook-dispatch.sh\\" write"
timeout = 10

[[hooks]]
event = "PreToolUse"
matcher = "Bash"
command = "bash \\"${{PMAI_HOME:-$HOME/.pmai}}/scripts/kimi-hook-dispatch.sh\\" bash"
timeout = 10

[[hooks]]
event = "UserPromptSubmit"
command = "bash \\"${{PMAI_HOME:-$HOME/.pmai}}/scripts/kimi-hook-dispatch.sh\\" prompt-review"
timeout = 8

[[hooks]]
event = "UserPromptSubmit"
command = "bash \\"${{PMAI_HOME:-$HOME/.pmai}}/scripts/kimi-hook-dispatch.sh\\" prompt-build"
timeout = 8
{END_MARKER}
'''

BLOCK_RE = re.compile(
    rf"(?ms)^{re.escape(START_MARKER)}\n.*?^{re.escape(END_MARKER)}\n?"
)


def default_config() -> Path:
    kimi_home = os.environ.get("KIMI_CODE_HOME")
    if kimi_home:
        return Path(kimi_home).expanduser() / "config.toml"
    return Path.home() / ".kimi-code" / "config.toml"


def validate_toml(text: str, label: str) -> None:
    if tomllib is None:
        return
    try:
        tomllib.loads(text)
    except Exception as exc:  # tomllib raises TOMLDecodeError, kept portable here
        raise ValueError(f"{label} 不是有效 TOML: {exc}") from exc


def remove_block(text: str) -> tuple[str, int]:
    starts = text.count(START_MARKER)
    ends = text.count(END_MARKER)
    if starts != ends or starts > 1:
        raise ValueError("Kimi config 中的 PMAI hook marker 不完整或重复")
    if starts == 0:
        return text, 0
    cleaned = BLOCK_RE.sub("", text)
    return cleaned.rstrip() + ("\n" if cleaned.strip() else ""), 1


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    old_mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.pmai-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp_name, old_mode)
        os.replace(tmp_name, path)
    finally:
        try:
            os.unlink(tmp_name)
        except FileNotFoundError:
            pass


def cmd_install(path: Path) -> int:
    if not path.exists():
        print(f"SKIPPED: Kimi config 不存在：{path}")
        return 0
    original = path.read_text(encoding="utf-8")
    validate_toml(original, str(path))
    base, _ = remove_block(original)
    merged = (base.rstrip() + "\n\n" if base.strip() else "") + MANAGED_BLOCK
    validate_toml(merged, "加入 PMAI hooks 后的 Kimi config")
    if merged == original:
        print(f"OK: Kimi hooks 已是最新版：{path}")
        return 0
    atomic_write(path, merged)
    print(f"INSTALLED: Kimi hooks：{path}")
    return 0


def cmd_check(path: Path) -> int:
    if not path.exists():
        print(f"MISSING: Kimi config 不存在：{path}")
        return 1
    original = path.read_text(encoding="utf-8")
    try:
        validate_toml(original, str(path))
        base, count = remove_block(original)
    except ValueError as exc:
        print(f"INVALID: {exc}")
        return 2
    expected = (base.rstrip() + "\n\n" if base.strip() else "") + MANAGED_BLOCK
    if count == 1 and original == expected:
        print(f"OK: Kimi hooks 与当前 PMAI 一致：{path}")
        return 0
    print(f"DRIFT: Kimi hooks 缺失或不是当前版本：{path}")
    return 1


def cmd_remove(path: Path) -> int:
    if not path.exists():
        print(f"SKIPPED: Kimi config 不存在：{path}")
        return 0
    original = path.read_text(encoding="utf-8")
    cleaned, count = remove_block(original)
    if count == 0:
        print(f"OK: Kimi config 没有 PMAI hook block：{path}")
        return 0
    validate_toml(cleaned, "移除 PMAI hooks 后的 Kimi config")
    atomic_write(path, cleaned)
    print(f"REMOVED: Kimi hooks：{path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "check", "remove"))
    parser.add_argument("--config", type=Path, default=default_config())
    args = parser.parse_args()
    try:
        if args.action == "install":
            return cmd_install(args.config)
        if args.action == "check":
            return cmd_check(args.config)
        return cmd_remove(args.config)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
