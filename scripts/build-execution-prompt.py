#!/usr/bin/env python3
"""Build execution prompt from task file.

Output: 6-section prompt for non-claude-code executors (codex / cursor-agent).
Same builder is used inline for claude-code path to keep prompt identical.

Sections:
  1. 元信息
  2. 启动前必读
  3. 执行范围 (allow + deny)
  4. 未处理的 PM 反馈
  5. 验收标准
  6. 写回职责
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

FIELD_RE = re.compile(r"^\*\*(.+?)：\*\*\s*(.*)$")


def read_frontmatter_fields(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for idx, line in enumerate(text.splitlines()):
        if idx >= 40:
            break
        m = FIELD_RE.match(line.strip())
        if m:
            fields[m.group(1).strip()] = m.group(2).strip()
    return fields


def extract_section(text: str, heading: str) -> str:
    """Return content between '## <heading>' and the next '## '."""
    pattern = re.compile(rf"^## {re.escape(heading)}.*$", re.MULTILINE)
    match = pattern.search(text)
    if not match:
        return ""
    start = match.end()
    next_section = re.search(r"^## ", text[start:], re.MULTILINE)
    body = text[start : start + next_section.start()] if next_section else text[start:]
    return body.strip()


def git_show_toplevel(worktree: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(worktree), "rev-parse", "--show-toplevel"], text=True
        ).strip()
    except Exception:
        return str(worktree)


def git_current_branch(worktree: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(worktree), "rev-parse", "--abbrev-ref", "HEAD"], text=True
        ).strip()
    except Exception:
        return "unknown"


def parse_preflight_reads(section_text: str) -> list[str]:
    """Parse ordered list items from 启动前必读 section."""
    items = []
    for line in section_text.splitlines():
        line = line.strip()
        m = re.match(r"^\d+\.\s*(.+)$", line)
        if m:
            items.append(m.group(1).strip())
    return items


def parse_scope(section_text: str) -> tuple[list[str], list[str]]:
    """Parse 执行范围 into (allowlist, denylist).

    Format:
      - 新建：[files]
      - 修改：[files]
      - 不动：[files]
    """
    allow: list[str] = []
    deny: list[str] = []
    current: str | None = None
    for line in section_text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("-"):
            continue
        body = stripped.lstrip("-").strip()
        if body.startswith("新建：") or body.startswith("新建:"):
            current = "allow"
            rest = body.split("：", 1)[1] if "：" in body else body.split(":", 1)[1]
            items = [x.strip() for x in rest.split(",") if x.strip()]
            allow.extend(items)
        elif body.startswith("修改：") or body.startswith("修改:"):
            current = "allow"
            rest = body.split("：", 1)[1] if "：" in body else body.split(":", 1)[1]
            items = [x.strip() for x in rest.split(",") if x.strip()]
            allow.extend(items)
        elif body.startswith("不动：") or body.startswith("不动:"):
            current = "deny"
            rest = body.split("：", 1)[1] if "：" in body else body.split(":", 1)[1]
            items = [x.strip() for x in rest.split(",") if x.strip()]
            deny.extend(items)
    return allow, deny


def parse_unprocessed_feedback(section_text: str) -> str:
    """Return feedback items not marked as processed.

    MVP: return raw section text. Future: filter by '[已处理]' / '[待处理]' markers.
    """
    if not section_text:
        return ""
    stripped = section_text.strip()
    if not stripped or stripped.startswith(">") or "无反馈" in stripped:
        return ""
    return stripped


def build_prompt(task_file: Path) -> str:
    text = task_file.read_text(encoding="utf-8")
    fields = read_frontmatter_fields(text)

    worktree = Path(fields.get("worktree", "")).expanduser() if fields.get("worktree") else task_file.parent.parent.parent
    worktree_root = git_show_toplevel(worktree) if worktree.exists() else str(worktree)
    branch = git_current_branch(Path(worktree_root)) if Path(worktree_root).exists() else "unknown"

    task_title_match = re.search(r"^#\s+Task.+$", text, re.MULTILINE)
    task_title = task_title_match.group(0).lstrip("#").strip() if task_title_match else task_file.stem

    description = extract_section(text, "任务描述")

    reads_section = extract_section(text, "启动前必读（按顺序，读完再执行）")
    reads = parse_preflight_reads(reads_section)

    scope_section = extract_section(text, "执行范围")
    allow, deny = parse_scope(scope_section)

    criteria = extract_section(text, "验收标准")

    feedback_section = extract_section(text, "PM 反馈")
    unprocessed_feedback = parse_unprocessed_feedback(feedback_section)

    out: list[str] = []

    # Section 1: 元信息
    out.append("# 执行上下文")
    out.append("")
    out.append(f"- task 文件（绝对路径）：{task_file.resolve()}")
    out.append(f"- task worktree：{worktree_root}")
    out.append(f"- 当前分支：{branch}")
    out.append(f"- task 标题：{task_title}")
    if description:
        out.append("")
        out.append("## 任务描述")
        out.append(description)
    out.append("")

    # Section 2: 启动前必读
    out.append("## 启动前必读（按顺序读完再动手）")
    if reads:
        for idx, item in enumerate(reads, 1):
            out.append(f"{idx}. {item}")
    else:
        out.append("（task 文件未列必读文档）")
    out.append("")

    # Section 3: 执行范围
    out.append("## 执行范围")
    out.append("")
    out.append("### 允许写入（allowlist）")
    if allow:
        for p in allow:
            out.append(f"- {p}")
    else:
        out.append("（task 文件未明确 allowlist，请参考任务描述判断）")
    out.append("")
    out.append("### 禁止写入（denylist）")
    out.append("- 任何 worktree 外的路径")
    out.append("- gitignore 匹配的生成物（`.next/`、`dist/`、`node_modules/` 等自动忽略）")
    if deny:
        for p in deny:
            out.append(f"- {p}（task 明列）")
    out.append("")

    # Section 4: 未处理 PM 反馈
    out.append("## 未处理的 PM 反馈")
    if unprocessed_feedback:
        out.append(unprocessed_feedback)
    else:
        out.append("（无待处理反馈）")
    out.append("")

    # Section 5: 验收标准
    out.append("## 验收标准（必须全部达成）")
    if criteria:
        out.append(criteria)
    else:
        out.append("（task 文件未列验收标准——请向 orchestrator 反馈）")
    out.append("")

    # Section 6: 写回职责
    out.append("## 写回职责（执行完成后必做）")
    out.append("")
    out.append("1. **更新 task 文件「执行日志」section**：改动摘要、新建/修改文件、验收情况")
    out.append("2. **更新 task 文件「文档偏差」section**：发现文档与现状不一致时逐条记录；完全一致填「无偏差」")
    out.append("")
    out.append("## 禁止事项")
    out.append("")
    out.append("- **禁止 `git add` / `git commit` / `git checkout`**——改动保持 unstaged，由 orchestrator 统一处理")
    out.append("- 禁止写 task worktree 外的任何路径")
    out.append("- 禁止修改未在 allowlist 中的文件（包括 `docs/`，除非 task 明列）")

    return "\n".join(out) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Build execution prompt from task file")
    parser.add_argument("task_file", help="Path to task file")
    args = parser.parse_args()

    task_file = Path(args.task_file)
    if not task_file.exists():
        print(f"Error: task file not found: {task_file}", file=sys.stderr)
        sys.exit(1)

    sys.stdout.write(build_prompt(task_file))


if __name__ == "__main__":
    main()
