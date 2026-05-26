#!/usr/bin/env python3
"""Single entrypoint for task status transitions."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# 让 _lib 可以 import（task-transition.py 自身在 scripts/，_lib 是同级子目录）
_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.state import read_section, has_meaningful_content
from _lib.events import (
    has_execution_event,
    load_events_strict,
    append_execution_event_internal,
    write_status_change_and_exec_event_atomic,
    BOUND_DISPATCH_EVENT_MAP,
)

# 兼容两种 task 元信息格式：
#   旧版（段落）：**字段：** 值
#   新版（任务卡表格）：| **字段** | 值 |
FIELD_RE_OLD = re.compile(r"^\*\*(.+?)：\*\*\s*(.*)$")
FIELD_RE_NEW = re.compile(r"^\|\s*\*\*(.+?)\*\*\s*\|\s*(.*?)\s*\|.*$")


def _parse_field_line(line: str) -> tuple[str, str] | None:
    """Try both old paragraph format and new task-card table format.
    Return (field_name, value) or None."""
    stripped = line.strip()
    m = FIELD_RE_OLD.match(stripped)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    m = FIELD_RE_NEW.match(stripped)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    return None


# Backward compatibility alias for any callers that reference FIELD_RE directly
FIELD_RE = FIELD_RE_OLD

# Task 状态机：
#
#   待执行 ──/task-confirm──▶ 执行中 ──PM 验收──▶ 已完成 (终态)
#     │                        │
#     │     --fail-execution / └──执行失败回退──▶ 待执行
#     │     --cancel-manual
#     └──────────┬─────────────┘
#                └────--discard────▶ 已废弃 (终态)
#
# 「执行中→已完成」验收（check_preconditions）除文档偏差/自审记录外，还要求
# 事件流含 execution 事件（accept 闸门）—— I-CT7 在 close-task 兜底。
VALID_TRANSITIONS = {
    "待执行": ["执行中"],
    "执行中": ["已完成", "待执行"],  # 待执行 = --fail-execution / --cancel-manual 回退
    "已完成": [],
    "已废弃": [],  # 终态：从 {待执行, 执行中} 经 --discard 进入；不可回流
}

# `执行中 → 待执行` is only reachable via --fail-execution or --cancel-manual;
# plain --to 待执行 from 执行中 is rejected.
RESTRICTED_TRANSITIONS = {("执行中", "待执行")}

# 状态可经 --discard 转入「已废弃」的允许集合
DISCARDABLE_FROM = {"待执行", "执行中"}

SCRIPTS_DIR = Path(__file__).resolve().parent
EVENTS_SCRIPT = SCRIPTS_DIR / "task-events.py"


def find_main_repo_root() -> Path:
    """Resolve real repo root (not a worktree)."""
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


def pending_manual_path(task_file: Path) -> Path:
    """Locate the .pending-manual-<short_id>.json file in main repo's .runs/."""
    repo = find_main_repo_root()
    task_stem = task_file.stem
    short_id_match = re.match(r"^(task-\d+)", task_stem)
    short_id = short_id_match.group(1) if short_id_match else task_stem
    return repo / ".runs" / f".pending-manual-{short_id}.json"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def save_text(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def read_fields(task_file: Path) -> dict[str, str]:
    """Read task header fields. Tolerates both formats:
      - Old paragraph: **字段：** 值
      - New task-card table: | **字段** | 值 |

    Reads the first 40 lines to cover both layouts (new format puts the
    task-card table around line 13-22 after the title and intro block).
    """
    fields: dict[str, str] = {}
    with task_file.open(encoding="utf-8") as fh:
        for idx, line in enumerate(fh):
            if idx >= 40:
                break
            parsed = _parse_field_line(line)
            if parsed:
                name, value = parsed
                fields[name] = value
    return fields


def update_field(text: str, field: str, value: str) -> tuple[str, int]:
    """Replace a header field's value. Tries old paragraph format first,
    then falls back to new task-card table format. Returns (new_text, count)."""
    # Old paragraph format: **字段：** 值
    pattern_old = re.compile(
        rf"(^[ \t]*\*\*{re.escape(field)}：\*\*\s*).*$", re.MULTILINE
    )
    text_new, count = pattern_old.subn(rf"\g<1>{value}", text, count=1)
    if count > 0:
        return text_new, count

    # New task-card table format: | **字段** | 值 |
    pattern_new = re.compile(
        rf"(^\|\s*\*\*{re.escape(field)}\*\*\s*\|\s*).+?(\s*\|.*)$",
        re.MULTILINE,
    )
    return pattern_new.subn(rf"\g<1>{value}\g<2>", text, count=1)


def has_section_content(text: str, section_name: str) -> bool:
    """Check if a markdown section has non-template content."""
    pattern = re.compile(
        rf"^## {re.escape(section_name)}.*$", re.MULTILINE
    )
    match = pattern.search(text)
    if not match:
        return False

    # Get content between this section and the next
    start = match.end()
    next_section = re.search(r"^## ", text[start:], re.MULTILINE)
    if next_section:
        content = text[start : start + next_section.start()]
    else:
        content = text[start:]

    # Strip template lines and check for real content
    lines = [
        l.strip()
        for l in content.strip().split("\n")
        if l.strip()
        and not l.strip().startswith(">")
        and not l.strip().startswith("| 文档位置")
        and not l.strip().startswith("|---")
        and not l.strip().startswith("### 自审 1 - [")
        and not l.strip().startswith("### 执行报告 - [")
        and not l.strip().startswith("### 反馈 1 - [")
        and not l.strip().startswith("**工具：**")
        and not l.strip().startswith("**结果：**")
        and not l.strip().startswith("**详细发现：**")
        and not l.strip().startswith("**遗留问题：**")
        and not l.strip().startswith("**改动摘要：**")
        and not l.strip().startswith("**问题描述：**")
        and not l.strip().startswith("**要求修改：**")
        and not l.strip().startswith("**处理结果：**")
        and l.strip() != "无"
        and l.strip() != "---"
    ]
    return len(lines) > 0


def find_sibling_tasks(task_file: Path) -> list[tuple[Path, str]]:
    """Find other task files in the same req directory and their statuses."""
    tasks_dir = task_file.parent
    result = []
    for tf in sorted(tasks_dir.glob("task-*.md")):
        if tf == task_file:
            continue
        fields = read_fields(tf)
        status = fields.get("状态", "")
        result.append((tf, status))
    return result


def check_serial_constraint(task_file: Path) -> None:
    # I-TT2 放宽 D0 并行允许 (v4 plan §8 A0)
    pass


def check_preconditions(
    task_file: Path, current: str, target: str, text: str, note: str | None
) -> None:
    """Check preconditions for a state transition."""

    if current == "待执行" and target == "执行中":
        # v1 串行强制
        check_serial_constraint(task_file)

    elif current == "执行中" and target == "已完成":
        # 「待验收」状态已合并到「执行中」：commit + 呈交 + PM 验收
        # 全程 task 状态保持「执行中」；PM 通过呈交块时统一在此 transition 校验。
        # 修复 P0-1：用 _lib.state.read_section 跨文件查找。
        #  三态：
        #   v3 新单文件 typed contract：section 在 task.md 审计区（## 📋 文档偏差 / ## 🔍 自审记录）
        #   v2 双文件：section 在 task.engineering.md 的 §10 / §11
        #   v1 老单文件：section 在 PM 视图（task.md）
        # read_section 自动按"工程合同优先（v2）→ PM 视图 fallback（v1/v3）"查找。

        # 1. 文档偏差 section
        found, content = read_section(task_file, "文档偏差")
        if not found:
            print(
                "Error: 文档偏差 section 未找到（PM 视图与工程合同均无此 section）。",
                file=sys.stderr,
            )
            sys.exit(1)
        # 允许"无偏差"或有实质内容
        if not has_meaningful_content(content) and "无偏差" not in (content or ""):
            print(
                "Error: 文档偏差 section 未填写。请填写文档偏差或写'无偏差'。",
                file=sys.stderr,
            )
            sys.exit(1)

        # 2. 自审记录 section
        found, content = read_section(task_file, "自审记录")
        if not found:
            print(
                "Error: 自审记录 section 未找到（PM 视图与工程合同均无此 section）。",
                file=sys.stderr,
            )
            sys.exit(1)
        if not has_meaningful_content(content):
            print(
                "Error: 自审记录 section 为空。请至少完成一次自审并记录结果。",
                file=sys.stderr,
            )
            sys.exit(1)

        # 3. accept 闸门（I-CT7 核心校验前移）：事件流须证明执行器被触发过。
        #    无 execution 事件 = /task-execute 从未跑过 → 拒绝验收。
        #    事件流缺失/不可读/含坏行 = 无法确认 → fail-closed（与 I-CT7 同口径）。
        events_file = (
            find_main_repo_root() / ".runs" / "events" / f"{task_file.stem}.jsonl"
        )
        events, problems = load_events_strict(events_file)
        if not has_execution_event(events):
            if problems:
                print(
                    "Error: accept 闸门 —— 无法确认执行器被触发过（fail-closed）：\n"
                    + "\n".join(f"  - {p}" for p in problems)
                    + "\n  事件流是 task 真实性的唯一凭据，读不到就不放行。",
                    file=sys.stderr,
                )
            else:
                print(
                    "Error: accept 闸门 —— 事件流缺少 execution 事件"
                    "（execution_started / execution_manual_completed）。\n"
                    "  说明 dispatch 通路没真跑过。合规出路（按场景选）：\n"
                    "\n"
                    "    • Work 还没做：回新会话跑 /task-execute <task-id> 让 dispatch 真发射。\n"
                    "\n"
                    "    • Work 已手做完（worktree 有 task commit）+ PM 拍板补登：\n"
                    "      python3 $HOME/.pmai/scripts/task-transition.py <task-file> \\\n"
                    "          --register-manual-completion --reason \"<为何手做、PM 拍板>\"\n"
                    "      （会写带 repaired:true 标记的 execution_manual_completed，"
                    "不动状态。\n"
                    "       完成后重跑本 transition 即可。）\n"
                    "\n"
                    "    • 整 task 放弃：python3 $HOME/.pmai/scripts/task-transition.py "
                    "<task-file> --discard --reason \"<...>\"\n"
                    "\n"
                    "  ⚠️ 禁止用 task-events.py append --type execution_started 绕过 —— "
                    "已加 CLI 黑名单。",
                    file=sys.stderr,
                )
            sys.exit(1)

        # review 工具改为 PM 自跑推荐项；事件流仍可能含 review_completed
        # 作为审计记录，但不再做覆盖校验。


def append_event(
    task_file: Path, from_status: str, to_status: str, note: str | None
) -> subprocess.CompletedProcess[str]:
    """Append a status_changed event to the event stream."""
    cmd = [
        sys.executable,
        str(EVENTS_SCRIPT),
        "append",
        str(task_file),
        "--type",
        "status_changed",
        "--from-status",
        from_status,
        "--to-status",
        to_status,
    ]
    if note:
        cmd.extend(["--note", note])
    return subprocess.run(cmd, capture_output=True, text=True)


def do_transition(
    task_file: Path,
    current: str,
    target: str,
    note: str | None,
    via: str = "normal",
    bound_event_alias: str | None = None,
    bound_event_payload: dict | None = None,
) -> None:
    """Execute the state transition and write event.

    `via` controls precondition bypass:
      - normal: full precondition check; 「待执行→执行中」时 bound_event_alias 必填
      - fail-execution: skips 已完成 precondition check (failure 回退到待执行)
      - cancel-manual: same as fail-execution
      - dispatch-bound: 跑 normal preconditions 但已自带 bound_event_alias

    `bound_event_alias` ∈ BOUND_DISPATCH_EVENT_MAP keys ("started" / "manual-waiting")。
    指定时，状态变更与 dispatch 事件一次原子写入（修复 B：堵"状态变了但 dispatch 没跑"的悬空窗口）。
    """
    text = read_text(task_file)
    if via in ("normal", "dispatch-bound"):
        check_preconditions(task_file, current, target, text, note)
        # 修复 B：「待执行→执行中」必须物化绑定 dispatch 事件
        if current == "待执行" and target == "执行中" and bound_event_alias is None:
            print(
                "Error: 「待执行→执行中」transition 必须通过 --bound-to-execution-event "
                "物化绑定 dispatch 事件（修复 B）。\n"
                "  防止 dispatch 没真跑就把状态推到执行中、事件流成为"
                "「状态变了但无执行证据」悬空态。\n"
                "  合规调用方：/task-execute skill 的 dispatch 节点（自动传该 flag）。\n"
                "  AI 故障恢复路径见 --register-manual-completion。",
                file=sys.stderr,
            )
            sys.exit(1)

    if bound_event_alias is not None and bound_event_alias not in BOUND_DISPATCH_EVENT_MAP:
        print(
            f"Error: --bound-to-execution-event 值「{bound_event_alias}」非法。"
            f"合法值：{', '.join(sorted(BOUND_DISPATCH_EVENT_MAP))}",
            file=sys.stderr,
        )
        sys.exit(1)

    # 重试场景：状态已经在 target（dispatch §3b 第二次跑进来）+ bound 事件给了。
    # 不需要 transition，仅 emit dispatch 事件（保留与历史行为一致：每次 dispatch
    # 调用都记一笔 execution_started/manual_waiting）。
    if current == target and bound_event_alias is not None:
        try:
            event_type = BOUND_DISPATCH_EVENT_MAP[bound_event_alias]
            append_execution_event_internal(
                task_file,
                event_type,
                payload=bound_event_payload,
                note=note,
            )
        except Exception as exc:
            print(f"Error: dispatch event write failed: {exc}", file=sys.stderr)
            sys.exit(1)
        return

    # FM7 fix (v4 plan §8 A0): I-CT7 fail-closed 完整性 — 状态写和事件追加的伪事务性
    original_text = text
    new_text, count = update_field(text, "状态", target)
    if count == 0:
        print("Error: 无法更新状态字段。", file=sys.stderr)
        sys.exit(1)
    save_text(task_file, new_text)

    if bound_event_alias is not None:
        # 原子写：status_changed + dispatch exec event（一次 fh.write）
        try:
            write_status_change_and_exec_event_atomic(
                task_file,
                current,
                target,
                bound_event_alias,
                note=note,
                exec_payload=bound_event_payload,
            )
        except Exception as exc:
            save_text(task_file, original_text)
            print(f"Error: atomic event write failed: {exc}", file=sys.stderr)
            sys.exit(1)
    else:
        result = append_event(task_file, current, target, note)
        if result.returncode != 0:
            save_text(task_file, original_text)
            output = (result.stderr or result.stdout or "").strip()
            if output:
                print(f"Error: append_event failed: {output}", file=sys.stderr)
            else:
                print("Error: append_event failed.", file=sys.stderr)
            sys.exit(1)


def cmd_fail_execution(task_file: Path, reason: str) -> None:
    """Handle --fail-execution: normalize failure fallback to 待执行."""
    fields = read_fields(task_file)
    current = fields.get("状态", "")
    if current != "执行中":
        print(
            f"Error: --fail-execution requires current status to be 执行中, got {current}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Clean up any stale pending-manual marker
    pf = pending_manual_path(task_file)
    if pf.exists():
        pf.unlink()

    note = f"执行失败回退：{reason}"
    do_transition(task_file, current, "待执行", note, via="fail-execution")
    print(f"✅ 执行失败已回退：执行中 → 待执行（{reason}）")


def cmd_cancel_manual(task_file: Path) -> None:
    """Handle --cancel-manual: PM gives up on manual task."""
    fields = read_fields(task_file)
    current = fields.get("状态", "")
    pf = pending_manual_path(task_file)
    if current != "执行中":
        print(
            f"Error: --cancel-manual 要求当前状态为 执行中，实际 {current}",
            file=sys.stderr,
        )
        sys.exit(1)
    if not pf.exists():
        print(
            f"Error: 找不到 manual 标记文件 {pf}。"
            f"只有当前正在 manual 等待的 task 可以 cancel。",
            file=sys.stderr,
        )
        sys.exit(1)

    pf.unlink()
    do_transition(task_file, current, "待执行", "PM 放弃 manual", via="cancel-manual")
    print(f"✅ Manual 放弃：标记已删除，状态回到 待执行")


def _now_iso() -> str:
    from datetime import datetime, timezone
    return datetime.now(timezone.utc).isoformat()


def cmd_discard(task_file: Path, reason: str, yes: bool) -> None:
    """Handle --discard: PM 废弃 task。

    流程（fail-closed 顺序）：
      1. 校验源状态 ∈ DISCARDABLE_FROM；已完成显式引导
      2. confirm prompt（除 --yes）展示要丢的 worktree / 分支 / uncommitted / unmerged
      3. git mv tasks/<f>.md tasks/discarded/<f>.md（在 req worktree 内）
      4. 在新位置改状态字段为「已废弃」+ 追加 `## 废弃理由` section
      5. append_event status_changed
      6. git worktree remove --force <task-worktree>
      7. git branch -D <task-branch>
      8. git add -A && commit 到 req 分支
    """
    fields = read_fields(task_file)
    current = fields.get("状态", "")

    if current == "已完成":
        print(
            "Error: 已完成 task 不能 discard。代码已合并到 req 分支，"
            "如需撤销请新开 task revert，或用 /cancel-req 整体取消 req。",
            file=sys.stderr,
        )
        sys.exit(1)
    if current not in DISCARDABLE_FROM:
        print(
            f"Error: 当前状态「{current}」不可 discard。"
            f"合法源状态: {', '.join(sorted(DISCARDABLE_FROM))}",
            file=sys.stderr,
        )
        sys.exit(1)

    if not reason or not reason.strip():
        print("Error: --discard 必须提供 --reason \"<一句话>\"", file=sys.stderr)
        sys.exit(1)
    reason = reason.strip()

    # 推断分支名（与 create-task-worktree.sh 一致：文件 stem，加 task- 前缀如未带）
    task_stem = task_file.stem
    branch = task_stem if task_stem.startswith("task-") else f"task-{task_stem}"

    repo_root = find_main_repo_root()
    try:
        req_worktree_root = Path(
            subprocess.check_output(
                ["git", "-C", str(task_file.parent), "rev-parse", "--show-toplevel"],
                text=True,
            ).strip()
        )
    except Exception as exc:
        print(f"Error: 无法定位 req worktree: {exc}", file=sys.stderr)
        sys.exit(1)

    # 防呆：禁止在 task worktree 内调 --discard（commit 会落到 task 分支）
    if req_worktree_root == (repo_root / ".worktrees" / branch).resolve() or \
       req_worktree_root.name == branch:
        print(
            f"Error: 检测到当前在 task worktree ({branch}) 内调用 --discard。"
            f"请回到 req worktree 或主仓再执行，避免 commit 落到 task 分支。",
            file=sys.stderr,
        )
        sys.exit(1)

    task_worktree = repo_root / ".worktrees" / branch
    has_worktree = task_worktree.exists()
    has_branch = (
        subprocess.run(
            ["git", "-C", str(repo_root), "show-ref", "--verify", "--quiet",
             f"refs/heads/{branch}"],
            capture_output=True,
        ).returncode
        == 0
    )

    # 收集要丢的（informational）
    uncommitted = 0
    unmerged = 0
    if has_worktree:
        try:
            out = subprocess.check_output(
                ["git", "-C", str(task_worktree), "status", "--porcelain"],
                text=True,
            )
            uncommitted = len([l for l in out.splitlines() if l.strip()])
        except Exception:
            pass
    if has_branch:
        # 走 state.read_req_meta（v3 §1 #2 实施：跨 skill 读统一走 _lib.state）
        from _lib.state import read_req_meta as _read_req_meta
        try:
            meta = _read_req_meta(task_file.parent.parent, strict=False) or {}
            req_branch = meta.get("branch", "")
            if req_branch:
                out = subprocess.check_output(
                    ["git", "-C", str(repo_root), "rev-list", "--count",
                     f"{req_branch}..{branch}"],
                    text=True, stderr=subprocess.DEVNULL,
                )
                unmerged = int(out.strip() or "0")
        except Exception:
            pass

    # 展示 + confirm
    print(f"将废弃 task: {task_file.name}")
    print(f"  当前状态: {current}")
    print(f"  废弃理由: {reason}")
    print(f"  task 分支: {branch} ({'存在' if has_branch else '不存在'})")
    if has_worktree:
        try:
            wt_disp = task_worktree.relative_to(repo_root)
        except ValueError:
            wt_disp = task_worktree
        print(f"  task worktree: {wt_disp}")
        print(f"  未提交改动: {uncommitted} 项 (将随 worktree --force 一并丢弃)")
    else:
        print(f"  task worktree: 无")
    if has_branch and unmerged > 0:
        print(f"  未合并 commit: {unmerged} 个 (将随 branch -D 一并丢弃)")

    if not yes:
        try:
            answer = input("确认废弃？输入 yes 继续: ").strip().lower()
        except EOFError:
            answer = ""
        if answer != "yes":
            print("已取消。", file=sys.stderr)
            sys.exit(1)

    # 1. git mv 到 discarded/
    discarded_dir = task_file.parent / "discarded"
    discarded_dir.mkdir(exist_ok=True)
    new_task_file = discarded_dir / task_file.name

    try:
        rel_from = task_file.relative_to(req_worktree_root)
        rel_to = new_task_file.relative_to(req_worktree_root)
    except ValueError as exc:
        print(f"Error: task 文件不在 req worktree 内: {exc}", file=sys.stderr)
        sys.exit(1)

    mv_result = subprocess.run(
        ["git", "-C", str(req_worktree_root), "mv", str(rel_from), str(rel_to)],
        capture_output=True, text=True,
    )
    if mv_result.returncode != 0:
        print(f"Error: git mv 失败: {mv_result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)

    # 1.5. v2 旧双文件兼容：成对 git mv 工程合同。
    # ：v3/v1 单文件只 mv 一个；v2 双文件才有 .engineering.md 需成对 mv。
    # 按 detect_format 分流 —— v2 才进本分支（其判别信号即 .engineering.md 存在）。
    from _lib.state import detect_format as _detect_format
    eng_file = None
    if task_file.suffix == ".md" and _detect_format(task_file) == "v2":
        eng_file = task_file.with_suffix(".engineering.md")
    if eng_file and eng_file.exists():
        new_eng_file = discarded_dir / eng_file.name
        try:
            eng_rel_from = eng_file.relative_to(req_worktree_root)
            eng_rel_to = new_eng_file.relative_to(req_worktree_root)
        except ValueError:
            eng_rel_from = eng_rel_to = None

        if eng_rel_from and eng_rel_to:
            eng_mv = subprocess.run(
                ["git", "-C", str(req_worktree_root), "mv",
                 str(eng_rel_from), str(eng_rel_to)],
                capture_output=True, text=True,
            )
            if eng_mv.returncode != 0:
                # 尝试回滚主文件 mv
                subprocess.run(
                    ["git", "-C", str(req_worktree_root), "mv",
                     str(rel_to), str(rel_from)],
                    capture_output=True,
                )
                print(
                    f"Error: 工程合同 git mv 失败（已回滚主文件 mv）: "
                    f"{eng_mv.stderr.strip()}",
                    file=sys.stderr,
                )
                sys.exit(1)

    # 2. 改状态字段 + 追加废弃理由 section（在新位置）
    text = read_text(new_task_file)
    new_text, count = update_field(text, "状态", "已废弃")
    if count == 0:
        # 回滚 git mv
        subprocess.run(
            ["git", "-C", str(req_worktree_root), "mv", str(rel_to), str(rel_from)],
            capture_output=True,
        )
        print("Error: 无法更新状态字段。", file=sys.stderr)
        sys.exit(1)

    discard_section = (
        f"\n\n---\n\n## 废弃理由\n\n"
        f"**时间：** {_now_iso()}\n"
        f"**理由：** {reason}\n"
    )
    new_text = new_text.rstrip() + discard_section
    save_text(new_task_file, new_text)

    # 3. append_event（事件流位置由 task stem 决定，文件移动后不变）
    result = append_event(new_task_file, current, "已废弃", f"discard: {reason}")
    if result.returncode != 0:
        output = (result.stderr or result.stdout or "").strip()
        print(f"⚠️ 事件追加失败（继续）: {output}", file=sys.stderr)

    # 4. 清理 task worktree
    if has_worktree:
        wt_result = subprocess.run(
            ["git", "-C", str(repo_root), "worktree", "remove", "--force",
             str(task_worktree)],
            capture_output=True, text=True,
        )
        if wt_result.returncode != 0:
            import shutil
            try:
                shutil.rmtree(task_worktree)
            except Exception:
                pass
            subprocess.run(
                ["git", "-C", str(repo_root), "worktree", "prune"],
                capture_output=True,
            )

    # 5. 删 task 分支
    if has_branch:
        br_result = subprocess.run(
            ["git", "-C", str(repo_root), "branch", "-D", branch],
            capture_output=True, text=True,
        )
        if br_result.returncode != 0:
            print(
                f"⚠️ 删除 task 分支 {branch} 失败（继续）: {br_result.stderr.strip()}",
                file=sys.stderr,
            )

    # 6. commit 到 req 分支
    subprocess.run(
        ["git", "-C", str(req_worktree_root), "add", "-A"],
        capture_output=True,
    )
    commit_msg = f"discard: {task_stem} — {reason}"
    commit_result = subprocess.run(
        ["git", "-C", str(req_worktree_root), "commit", "-m", commit_msg],
        capture_output=True, text=True,
    )
    if commit_result.returncode != 0:
        err = commit_result.stderr.strip() or commit_result.stdout.strip()
        print(f"⚠️ commit 失败（请手动 commit）: {err}", file=sys.stderr)

    print(f"⏭ Task 已废弃: {task_stem}")
    print(f"   理由: {reason}")
    print(f"   归档到: tasks/discarded/{task_file.name}")
    if has_worktree:
        print(f"   worktree 已清理: {task_worktree.name}")
    if has_branch:
        print(f"   分支已删: {branch}")


def cmd_get_status(task_file: Path) -> None:
    """Print the current task status field to stdout. Used by gate scripts
    (check-branch.sh, exec-adapters/*.sh, /task-execute preamble) so no one
    re-implements the regex."""
    fields = read_fields(task_file)
    current = fields.get("状态", "")
    if not current:
        print("Error: 无法读取 task 状态字段。", file=sys.stderr)
        sys.exit(1)
    print(current)


def cmd_validate_fields_only(task_file: Path) -> None:
    """Strict header-fields validation. Used by task-spec / task-confirm post-write
    gate so a malformed task file can't reach /task-execute.

    Checks:
      1. 状态 字段能被 _parse_field_line 解析（段落或任务卡表格格式之一）
      2. 状态值 ∈ VALID_TRANSITIONS keys（4 合法态）

    Exit 0 on pass; exit 1 with diagnostic on fail. Used by `task-spec` step 10.6
    to fail-close when AI writes blockquote frontmatter / illegal status values
    (e.g. "「待启动」", "PENDING") that survive heuristic lint."""
    fields = read_fields(task_file)
    current = fields.get("状态", "")
    if not current:
        print(
            "Error: 无法在 task 文件前 40 行解析出「状态」字段。\n"
            "  合法格式二选一：\n"
            "    段落：  **状态：** <值>\n"
            "    表格：  | **状态** | <值> |\n"
            "  禁止 blockquote (`> 状态：...`) 或自创格式。",
            file=sys.stderr,
        )
        sys.exit(1)
    valid_states = sorted(VALID_TRANSITIONS.keys())
    if current not in VALID_TRANSITIONS:
        print(
            f"Error: 状态字段值「{current}」非法。\n"
            f"  合法 4 态：{' / '.join(valid_states)}\n"
            f"  常见误用：「待启动」是 status-view.py 的派生显示标签，"
            f"不是状态字段存储值。",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"✅ 字段校验通过：状态 = {current}")


def cmd_snooze_manual(task_file: Path, days: int) -> None:
    """Handle --snooze-manual --days N: suppress manual preamble reminder."""
    from datetime import datetime, timedelta, timezone

    pf = pending_manual_path(task_file)
    if not pf.exists():
        print(f"Error: 找不到 manual 标记文件 {pf}", file=sys.stderr)
        sys.exit(1)

    try:
        data = json.loads(pf.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"Error: 无法解析 manual 标记文件：{exc}", file=sys.stderr)
        sys.exit(1)

    until = datetime.now(timezone.utc) + timedelta(days=days)
    data["snoozed_until"] = until.isoformat()
    pf.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"✅ Manual 提醒暂缓 {days} 天（至 {until.date()}）")


def cmd_repair_evidence(task_file: Path, reason: str, yes: bool) -> None:
    """Handle --repair-evidence: 受支持地补记缺失的 execution 证据。

    用于 task 已在「已完成」、但事件流缺 execution 事件、导致 close-task 的
    I-CT7 被挡的情形（多为 accept 闸门上线前的遗留 task）。只补一条带
    repaired 标记的 execution_manual_completed，不改状态、不做任意事件合成。
    强制 --reason + PM 交互认定（--yes 跳过，用于自动化）。
    """
    fields = read_fields(task_file)
    current = fields.get("状态", "")
    if current != "已完成":
        print(
            f"Error: --repair-evidence 仅用于「已完成」的 task（close-task I-CT7 被挡），"
            f"当前状态「{current}」。\n"
            "  「执行中」的 task 请走 /task-execute（含 manual 模式）补 execution 事件。",
            file=sys.stderr,
        )
        sys.exit(1)

    if not reason or not reason.strip():
        print(
            "Error: --repair-evidence 必须提供 --reason \"<为何该 task 的 work 真实完成>\"",
            file=sys.stderr,
        )
        sys.exit(1)
    reason = reason.strip()

    repo_root = find_main_repo_root()
    events_file = repo_root / ".runs" / "events" / f"{task_file.stem}.jsonl"
    events, _ = load_events_strict(events_file)
    if has_execution_event(events):
        print(
            "Error: 事件流已含 execution 事件，无需 repair。",
            file=sys.stderr,
        )
        sys.exit(1)

    # 适用窗口校验（plan-eng-review WARNING-2 / 设计 §5）：repair-evidence 只对
    # close-task 尚未跑完、可重跑的 task 有意义。close-task 成功后会删 task 分支，
    # 分支不在 = 已 close，repair 无意义（往已归档/已清理的 .runs/ 写无意义事件）。
    task_stem = task_file.stem
    branch = task_stem if task_stem.startswith("task-") else f"task-{task_stem}"
    branch_exists = subprocess.run(
        ["git", "-C", str(repo_root), "show-ref", "--verify", "--quiet",
         f"refs/heads/{branch}"],
        capture_output=True,
    ).returncode == 0
    if not branch_exists:
        print(
            f"Error: task 分支 {branch} 不存在 —— close-task 可能已跑完（分支已删）。\n"
            "  --repair-evidence 仅用于 close-task 尚未跑完、可重跑的 task。",
            file=sys.stderr,
        )
        sys.exit(1)

    print(
        "⚠️  evidence-repair —— 受支持的「审计证据补记」命令。\n"
        f"    task : {task_file.name}\n"
        f"    理由 : {reason}\n"
        "    将补记一条带 repaired=true 标记的 execution_manual_completed 事件，"
        "不改状态。\n"
        "    仅在你确认该 task 的 work 真实完成时使用 —— 它让 close-task 的 I-CT7 放行。",
        file=sys.stderr,
    )
    if not yes:
        try:
            answer = input(
                "确认该 task 的 work 真实完成、据实补记证据？输入 yes 继续: "
            ).strip().lower()
        except EOFError:
            answer = ""
        if answer != "yes":
            print("已取消。", file=sys.stderr)
            sys.exit(1)

    note = f"evidence-repair（retroactive，PM 认定 work 真实完成）：{reason}"
    try:
        append_execution_event_internal(
            task_file,
            "execution_manual_completed",
            payload={"repaired": True},
            note=note,
        )
    except Exception as exc:
        print(f"Error: 事件补记失败: {exc}", file=sys.stderr)
        sys.exit(1)

    print(
        f"✅ evidence-repair 完成：已向 {task_file.name} 事件流补记 "
        "execution_manual_completed（repaired=true）。现在可重跑 close-task。"
    )


def cmd_emit_from_pending(task_file: Path) -> None:
    """Handle --emit-from-pending: dispatch §3a manual resume 合规通路。

    要求 PENDING_FILE 存在（manual.sh adapter 在 §3b 派发时写）。写一条
    execution_manual_completed 事件（无 repaired 标记，因为是合规通路），
    删 PENDING_FILE，不改状态。后续 step 4 自审 → PM 验收 → 已完成。

    给 /task-execute skill §3a manual resume 通路调用，不是 PM 直接敲。
    """
    fields = read_fields(task_file)
    current = fields.get("状态", "")
    if current != "执行中":
        print(
            f"Error: --emit-from-pending 仅用于「执行中」的 task，"
            f"当前状态「{current}」。\n"
            "  此通路是 /task-execute §3a manual resume 用，需要先经 dispatch "
            "派发到执行中。",
            file=sys.stderr,
        )
        sys.exit(1)

    pf = pending_manual_path(task_file)
    if not pf.exists():
        print(
            f"Error: --emit-from-pending 要求 PENDING_FILE 存在（{pf}）。\n"
            "  PENDING_FILE 由 manual.sh adapter 在 dispatch §3b 派发时写。\n"
            "  如果 task work 是 AI 自己用 Edit/Write 做完的（没走过 manual 通路），\n"
            "  应当用 --register-manual-completion --reason \"<...>\" 而不是这个命令。",
            file=sys.stderr,
        )
        sys.exit(1)

    repo_root = find_main_repo_root()
    events_file = repo_root / ".runs" / "events" / f"{task_file.stem}.jsonl"
    events, _ = load_events_strict(events_file)
    if has_execution_event(events):
        print(
            "Error: 事件流已含 execution event（accept 闸门已可通过），无需 emit。",
            file=sys.stderr,
        )
        sys.exit(1)

    # 读 PENDING_FILE 拿 baseline_sha 等元数据写进 event payload
    try:
        pending_data = json.loads(pf.read_text(encoding="utf-8"))
    except Exception:
        pending_data = {}
    payload: dict = {}
    if "baseline_sha" in pending_data:
        payload["baseline_sha"] = pending_data["baseline_sha"]
    if "started_at" in pending_data:
        payload["pending_started_at"] = pending_data["started_at"]

    try:
        append_execution_event_internal(
            task_file,
            "execution_manual_completed",
            payload=payload if payload else None,
        )
    except Exception as exc:
        print(f"Error: 事件写入失败: {exc}", file=sys.stderr)
        sys.exit(1)

    pf.unlink()
    print(
        f"✅ manual resume 完成：已向 {task_file.name} 事件流写入 "
        "execution_manual_completed。PENDING_FILE 已清理。"
    )


def cmd_register_manual_completion(
    task_file: Path, reason: str, yes: bool
) -> None:
    """Handle --register-manual-completion: AI 故障恢复合规通路。

    场景：task 状态=执行中、事件流缺 exec event、但 worktree 已有 task commit。
    多发于「AI 进 /task-execute 后入口前置 transition 了但没跑 dispatch、自己用
    Edit/Write 把代码做完」的故障。

    强制 --reason；写一条带 {repaired:true, reason, by:manual-completion-register}
    payload 的 execution_manual_completed；不改状态。完成后走正常 PM 验收呈交。

    给 AI 在故障恢复路径调用，不是 PM 直接敲。
    """
    fields = read_fields(task_file)
    current = fields.get("状态", "")
    if current != "执行中":
        print(
            f"Error: --register-manual-completion 仅用于「执行中」的 task，"
            f"当前状态「{current}」。\n"
            "  «已完成» 状态用 --repair-evidence；«待执行» 状态请走 /task-execute。",
            file=sys.stderr,
        )
        sys.exit(1)

    if not reason or not reason.strip():
        print(
            "Error: --register-manual-completion 必须提供 --reason "
            "\"<为何 work 真实手做完、为何没走 dispatch>\"",
            file=sys.stderr,
        )
        sys.exit(1)
    reason = reason.strip()

    repo_root = find_main_repo_root()
    events_file = repo_root / ".runs" / "events" / f"{task_file.stem}.jsonl"
    events, _ = load_events_strict(events_file)
    if has_execution_event(events):
        print(
            "Error: 事件流已含 execution event（accept 闸门已可通过），无需 register。\n"
            "  如果你在故障调查中看到这条，说明前面某次 dispatch 已留下证据。",
            file=sys.stderr,
        )
        sys.exit(1)

    # 验证 worktree 真有 task commit（防止"work 还没做"也来 register 走过场）
    task_stem = task_file.stem
    branch = task_stem if task_stem.startswith("task-") else f"task-{task_stem}"
    task_worktree = repo_root / ".worktrees" / branch
    has_commit = False
    if task_worktree.exists():
        try:
            # 看分支与其 merge-base 之间有没有 commit
            log_out = subprocess.check_output(
                ["git", "-C", str(task_worktree), "log", "--oneline", "-1",
                 "--", "."],
                text=True,
            ).strip()
            has_commit = bool(log_out)
        except Exception:
            has_commit = False
    if not has_commit:
        print(
            f"Error: task worktree {task_worktree} 未发现任何 commit。\n"
            "  register-manual-completion 要求 work 真实已 commit；\n"
            "  如果 work 还没做，请走 /task-execute 而不是 register。",
            file=sys.stderr,
        )
        sys.exit(1)

    print(
        "⚠️  register-manual-completion —— AI 故障恢复合规通路。\n"
        f"    task : {task_file.name}\n"
        f"    理由 : {reason}\n"
        "    将写一条带 repaired=true 标记的 execution_manual_completed 事件，\n"
        "    不改状态。完成后走正常 PM 验收呈交。",
        file=sys.stderr,
    )
    if not yes:
        try:
            answer = input(
                "确认 work 真实手做完成（worktree commit 已查证）且 PM 拍板补登？"
                "输入 yes 继续: "
            ).strip().lower()
        except EOFError:
            answer = ""
        if answer != "yes":
            print("已取消。", file=sys.stderr)
            sys.exit(1)

    note = f"register-manual-completion（AI 故障恢复，PM 拍板）：{reason}"
    try:
        append_execution_event_internal(
            task_file,
            "execution_manual_completed",
            payload={"repaired": True, "by": "manual-completion-register"},
            note=note,
        )
    except Exception as exc:
        print(f"Error: 事件写入失败: {exc}", file=sys.stderr)
        sys.exit(1)

    print(
        f"✅ register-manual-completion 完成：已向 {task_file.name} 事件流写入 "
        "execution_manual_completed（repaired=true）。\n"
        "现在可继续走 PM 验收呈交（task-submit → task-transition --to 已完成）。"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Task status transition")
    parser.add_argument("task_file", help="Path to task file")
    parser.add_argument("--to", dest="target", help="Target status (normal transition)")
    parser.add_argument("--note", help="Note (required for PM rejection)")
    # Special-purpose flags
    parser.add_argument(
        "--fail-execution",
        action="store_true",
        help="Fail currently-executing task (执行中 → 待执行). Requires --reason.",
    )
    parser.add_argument(
        "--reason",
        help="Failure classification or description (used with --fail-execution)",
    )
    parser.add_argument(
        "--cancel-manual",
        action="store_true",
        help="PM 放弃 manual task: delete pending marker + 转回待执行",
    )
    parser.add_argument(
        "--discard",
        action="store_true",
        help="废弃 task：移到 tasks/discarded/、清理 worktree+分支、commit。"
             "源状态 ∈ {待执行, 执行中}；已完成不可。需 --reason，"
             "非交互场景加 --yes 跳过 confirm。",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="跳过 --discard / --repair-evidence 的 confirm prompt（用于自动化场景）",
    )
    parser.add_argument(
        "--repair-evidence",
        action="store_true",
        dest="repair_evidence",
        help="受支持地补记缺失的 execution 证据：用于已是「已完成」、但事件流缺 "
             "execution 事件、被 close-task I-CT7 挡下的 task。补一条带 repaired "
             "标记的 execution_manual_completed，不改状态。需 --reason，"
             "非交互场景加 --yes。",
    )
    parser.add_argument(
        "--bound-to-execution-event",
        dest="bound_event_alias",
        choices=sorted(BOUND_DISPATCH_EVENT_MAP.keys()),
        help="「待执行→执行中」transition 必填（修复 B）：与 dispatch 事件原子绑定写入。"
             "started = 普通 executor 派发；manual-waiting = executor=manual 派发。"
             "给 /task-execute skill 的 dispatch 节点调用。",
    )
    parser.add_argument(
        "--executor",
        help="--bound-to-execution-event 的 payload 字段：executor 名（claude-code / "
             "codex / cursor-agent / manual）",
    )
    parser.add_argument(
        "--executor-model",
        dest="executor_model",
        help="--bound-to-execution-event 的 payload 字段：executor model",
    )
    parser.add_argument(
        "--baseline-sha",
        dest="baseline_sha",
        help="--bound-to-execution-event 的 payload 字段：dispatch 时的 baseline HEAD",
    )
    parser.add_argument(
        "--emit-from-pending",
        action="store_true",
        dest="emit_from_pending",
        help="dispatch §3a manual resume 合规通路：PENDING_FILE 存在时补一条 "
             "execution_manual_completed，删 PENDING_FILE，不改状态。"
             "给 /task-execute skill 调用。",
    )
    parser.add_argument(
        "--register-manual-completion",
        action="store_true",
        dest="register_manual_completion",
        help="AI 故障恢复合规通路（修复 C）：task 状态=执行中、事件流缺 exec event、"
             "worktree 已有 task commit 时，写带 repaired 标记的 "
             "execution_manual_completed，不改状态。需 --reason，非交互场景加 --yes。",
    )
    parser.add_argument(
        "--snooze-manual",
        action="store_true",
        help="暂缓 manual 提醒 N 天，不改状态。与 --days 配合使用",
    )
    parser.add_argument(
        "--get-status",
        action="store_true",
        help="Print current task status to stdout (used by gate scripts).",
    )
    parser.add_argument(
        "--validate-fields-only",
        action="store_true",
        help="Strict header-fields validation: 状态 字段可解析 + 值在合法 4 态。"
             "task-spec 写完后跑，挡住 blockquote / 派生标签等自创格式。",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=3,
        help="Days to snooze manual reminder (default 3)",
    )
    args = parser.parse_args()

    task_file = Path(args.task_file).resolve()
    if not task_file.exists():
        print(f"Error: task file not found: {task_file}", file=sys.stderr)
        print(
            "  修复：检查路径拼写；task 文件应位于 "
            "$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md。"
            "若 task 还没生成，先在 req worktree 跑 /task-spec <task-id>。",
            file=sys.stderr,
        )
        sys.exit(1)

    # Dispatch
    if args.fail_execution:
        if not args.reason:
            print("Error: --fail-execution requires --reason", file=sys.stderr)
            sys.exit(1)
        cmd_fail_execution(task_file, args.reason)
        return

    if args.cancel_manual:
        cmd_cancel_manual(task_file)
        return

    if args.discard:
        if not args.reason:
            print("Error: --discard requires --reason \"<一句话>\"", file=sys.stderr)
            sys.exit(1)
        cmd_discard(task_file, args.reason, args.yes)
        return

    if args.repair_evidence:
        cmd_repair_evidence(task_file, args.reason or "", args.yes)
        return

    if args.emit_from_pending:
        cmd_emit_from_pending(task_file)
        return

    if args.register_manual_completion:
        cmd_register_manual_completion(task_file, args.reason or "", args.yes)
        return

    if args.snooze_manual:
        cmd_snooze_manual(task_file, args.days)
        return

    if args.get_status:
        cmd_get_status(task_file)
        return

    if args.validate_fields_only:
        cmd_validate_fields_only(task_file)
        return

    # Normal transition
    if not args.target:
        print("Error: --to <status> required for normal transitions", file=sys.stderr)
        sys.exit(1)

    fields = read_fields(task_file)
    current = fields.get("状态", "")
    if not current:
        print("Error: 无法读取 task 状态字段。", file=sys.stderr)
        sys.exit(1)

    target = args.target
    valid = VALID_TRANSITIONS.get(current, [])
    # Dispatch retry 放行：状态已=target（执行中→执行中）+ bound 事件给了 →
    # 单独 emit dispatch event 不算 state transition
    is_dispatch_retry = (
        current == target == "执行中" and args.bound_event_alias is not None
    )
    if target not in valid and not is_dispatch_retry:
        print(
            f"Error: 非法状态转换: {current} → {target}。"
            f"合法目标: {', '.join(valid) if valid else '无（终态）'}",
            file=sys.stderr,
        )
        sys.exit(1)

    # Block restricted transitions from going through plain --to
    if (current, target) in RESTRICTED_TRANSITIONS:
        print(
            f"Error: 非法状态转换: {current} → {target} 不能通过 --to 触发。"
            f"请用 --fail-execution --reason <text> 或 --cancel-manual。",
            file=sys.stderr,
        )
        sys.exit(1)

    # Clean up manual marker on transition to 待执行 (decisive policy)
    if target == "待执行":
        pf = pending_manual_path(task_file)
        if pf.exists():
            pf.unlink()

    # 修复 B: 「待执行→执行中」必须传 --bound-to-execution-event；组装 dispatch payload
    bound_event_payload: dict | None = None
    if args.bound_event_alias:
        bound_event_payload = {}
        if args.executor:
            bound_event_payload["executor"] = args.executor
        if args.executor_model:
            bound_event_payload["model"] = args.executor_model
        if args.baseline_sha:
            bound_event_payload["baseline_sha"] = args.baseline_sha
        if not bound_event_payload:
            bound_event_payload = None

    do_transition(
        task_file, current, target, args.note,
        bound_event_alias=args.bound_event_alias,
        bound_event_payload=bound_event_payload,
    )
    print(f"✅ Task 状态转换: {current} → {target}")
    if args.note:
        print(f"   备注: {args.note}")


if __name__ == "__main__":
    main()
