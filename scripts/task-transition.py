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

from _lib.task_parser import read_section, has_meaningful_content

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

VALID_TRANSITIONS = {
    "待确认": ["执行中"],
    "执行中": ["待验收", "待确认"],  # 待确认 = --fail-execution / --cancel-manual 回退
    "待验收": ["已完成", "执行中"],  # 执行中 = PM 打回
    "已完成": [],
    "已废弃": [],  # 终态：从 {待确认, 执行中, 待验收} 经 --discard 进入；不可回流
}

# `执行中 → 待确认` is only reachable via --fail-execution or --cancel-manual;
# plain --to 待确认 from 执行中 is rejected.
RESTRICTED_TRANSITIONS = {("执行中", "待确认")}

# 状态可经 --discard 转入「已废弃」的允许集合
DISCARDABLE_FROM = {"待确认", "执行中", "待验收"}

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

    if current == "待确认" and target == "执行中":
        # v1 串行强制
        check_serial_constraint(task_file)

    elif current == "执行中" and target == "待验收":
        # 修复 P0-1：用 _lib.task_parser.read_section 跨文件查找。
        # 新格式（v2）：section 在 task.engineering.md 的 §10 / §11
        # 旧格式（v1）：section 在 PM 视图（task.md）
        # parser 自动按"工程合同优先 → PM 视图 fallback"查找。

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

        # review 工具改为 PM 自跑推荐项；事件流仍可能含 review_completed
        # 作为审计记录，但不再做覆盖校验。

    elif current == "待验收" and target == "执行中":
        # PM 打回需要 note
        if not note:
            print(
                "Error: PM 打回必须提供反馈。使用 --note 参数。",
                file=sys.stderr,
            )
            sys.exit(1)


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
    task_file: Path, current: str, target: str, note: str | None, via: str = "normal"
) -> None:
    """Execute the state transition and write event.

    `via` controls precondition bypass:
      - normal: full precondition check
      - fail-execution: skips 待验收 precondition check (failure回退)
      - cancel-manual: same as fail-execution
    """
    text = read_text(task_file)
    if via == "normal":
        check_preconditions(task_file, current, target, text, note)

    # FM7 fix (v4 plan §8 A0): I-CT7 fail-closed 完整性 — 状态写和事件追加的伪事务性
    original_text = text
    new_text, count = update_field(text, "状态", target)
    if count == 0:
        print("Error: 无法更新状态字段。", file=sys.stderr)
        sys.exit(1)
    save_text(task_file, new_text)
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
    """Handle --fail-execution: normalize failure fallback to 待确认."""
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
    do_transition(task_file, current, "待确认", note, via="fail-execution")
    print(f"✅ 执行失败已回退：执行中 → 待确认（{reason}）")


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
    do_transition(task_file, current, "待确认", "PM 放弃 manual", via="cancel-manual")
    print(f"✅ Manual 放弃：标记已删除，状态回到 待确认")


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
        meta_file = task_file.parent.parent / ".req-meta.json"
        if meta_file.exists():
            try:
                req_branch = json.loads(meta_file.read_text(encoding="utf-8")).get("branch", "")
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

    # 1.5. 成对处理工程合同（如存在）— PR 2 拆两文件约定
    eng_file = task_file.with_suffix(".engineering.md") \
        if task_file.suffix == ".md" else None
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
      2. 状态值 ∈ VALID_TRANSITIONS keys（5 合法态）

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
            f"  合法 5 态：{' / '.join(valid_states)}\n"
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


def main() -> None:
    parser = argparse.ArgumentParser(description="Task status transition")
    parser.add_argument("task_file", help="Path to task file")
    parser.add_argument("--to", dest="target", help="Target status (normal transition)")
    parser.add_argument("--note", help="Note (required for PM rejection)")
    # Special-purpose flags
    parser.add_argument(
        "--fail-execution",
        action="store_true",
        help="Fail currently-executing task (执行中 → 待确认). Requires --reason.",
    )
    parser.add_argument(
        "--reason",
        help="Failure classification or description (used with --fail-execution)",
    )
    parser.add_argument(
        "--cancel-manual",
        action="store_true",
        help="PM 放弃 manual task: delete pending marker + 转回待确认",
    )
    parser.add_argument(
        "--discard",
        action="store_true",
        help="废弃 task：移到 tasks/discarded/、清理 worktree+分支、commit。"
             "源状态 ∈ {待确认, 执行中, 待验收}；已完成不可。需 --reason，"
             "非交互场景加 --yes 跳过 confirm。",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="跳过 --discard 的 confirm prompt（用于自动化场景）",
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
        help="Strict header-fields validation: 状态 字段可解析 + 值在合法 5 态。"
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
    if target not in valid:
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

    # Clean up manual marker on transition to 待确认 (decisive policy)
    if target == "待确认":
        pf = pending_manual_path(task_file)
        if pf.exists():
            pf.unlink()

    do_transition(task_file, current, target, args.note)
    print(f"✅ Task 状态转换: {current} → {target}")
    if args.note:
        print(f"   备注: {args.note}")


if __name__ == "__main__":
    main()
