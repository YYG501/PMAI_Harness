#!/usr/bin/env python3
"""Resolve executor + model for a task.

Field source (新两文件格式 → 旧单文件格式 fallback):
  - 优先读 <task>.engineering.md §1（**executor：** / **executor_model：**）
  - eng 文件不存在 → 退化读 PM 视图（旧 req-001 / req-002 / 单文件 task 兼容）

Inheritance chain (2 layers):
  executor: task field → settings.json executor.default → "claude-code"
  model:    task field → settings.json executor.models[<executor>] → null

Output: JSON {"executor": "...", "model": "...|null", "source_executor": "...",
               "source_model": "..."}
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

FIELD_RE = re.compile(r"^\*\*(.+?)：\*\*\s*(.*)$")
VALID_EXECUTORS = {"claude-code", "codex", "cursor-agent", "manual"}
# Default if settings.json doesn't specify allowlist
DEFAULT_CLAUDE_CODE_MODELS = {"opus", "sonnet", "haiku"}


def find_repo_root() -> Path:
    try:
        common = subprocess.check_output(
            ["git", "rev-parse", "--git-common-dir"], text=True
        ).strip()
        if common and common != ".git":
            return Path(common).resolve().parent
    except Exception:
        pass
    try:
        return Path(
            subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], text=True
            ).strip()
        )
    except Exception:
        return Path.cwd()


def read_task_fields(task_file: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    with task_file.open(encoding="utf-8") as fh:
        for idx, line in enumerate(fh):
            if idx >= 40:
                break
            m = FIELD_RE.match(line.strip())
            if m:
                fields[m.group(1).strip()] = m.group(2).strip()
    return fields


def derive_eng_path(pm_view: Path) -> Path:
    """<task>.md → <task>.engineering.md."""
    return pm_view.with_suffix(".engineering.md")


def load_settings(repo_root: Path) -> dict:
    settings_file = repo_root / ".claude" / "settings.json"
    if not settings_file.exists():
        return {}
    try:
        return json.loads(settings_file.read_text(encoding="utf-8"))
    except Exception:
        return {}


def die(msg: str, code: int = 1) -> None:
    print(msg, file=sys.stderr)
    sys.exit(code)


def resolve(task_file: Path) -> dict:
    eng_path = derive_eng_path(task_file)
    field_source = eng_path if eng_path.exists() else task_file
    fields = read_task_fields(field_source)
    repo_root = find_repo_root()
    settings = load_settings(repo_root)
    exec_cfg = settings.get("executor", {})

    # executor
    task_executor = fields.get("executor", "").strip()
    if task_executor:
        executor = task_executor
        source_executor = "task"
    else:
        executor = exec_cfg.get("default", "").strip()
        if executor:
            source_executor = "settings"
        else:
            executor = "claude-code"
            source_executor = "default"

    if executor not in VALID_EXECUTORS:
        die(
            f"错误：无效 executor「{executor}」\n"
            f"合法值：{' / '.join(sorted(VALID_EXECUTORS))}\n"
            f"修复：编辑 {task_file}，把 **executor：** 字段改为合法值之一"
        )

    # model
    task_model = fields.get("executor_model", "").strip()
    if task_model:
        model = task_model
        source_model = "task"
    else:
        models_map = exec_cfg.get("models", {}) or {}
        model = models_map.get(executor, "")
        source_model = "settings" if model else "default"
        if not model:
            model = None

    # Validate claude-code model against allowlist
    if executor == "claude-code" and model:
        allowlist = set(
            exec_cfg.get("claude_code_model_allowlist", list(DEFAULT_CLAUDE_CODE_MODELS))
        )
        if model not in allowlist:
            die(
                f"错误：claude-code 的 executor_model 只支持 "
                f"{' / '.join(sorted(allowlist))}\n"
                f"当前值：{model}\n"
                f"修复：\n"
                f"  - 如果你想用 {model}，把 **executor：** 改成 codex 或 cursor-agent\n"
                f"  - 或者清空 **executor_model：** 字段让 Agent tool 用默认 model"
            )

    return {
        "executor": executor,
        "model": model,
        "source_executor": source_executor,
        "source_model": source_model,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Resolve executor + model for task")
    parser.add_argument("task_file", help="Path to task file")
    parser.add_argument(
        "--field",
        choices=["executor", "model", "source_executor", "source_model"],
        help="Output a single field as plain text (instead of JSON)",
    )
    args = parser.parse_args()

    task_file = Path(args.task_file)
    if not task_file.exists():
        die(f"错误：task 文件不存在 {task_file}")

    result = resolve(task_file)

    if args.field:
        val = result.get(args.field)
        print("" if val is None else val)
    else:
        print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
