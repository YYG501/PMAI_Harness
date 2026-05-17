"""State reader — single authority for reading PM-AI-Workflow runtime state.

跨 skill 统一读层：把 task / req / events / 聚合视图的读取从各处 grep + jq
+ 散落的 json.load 收敛到一个 lib。`status-view.py` 反向 dogfood 本 lib，
避免双轨"AI grep raw / PM 看视觉视图"的真相源漂移。

历史：本文件由 `_lib/task_parser.py`（task 元数据 v1/v2 兼容层）扩展 + 改名
而来，原 API 全部保留（detect_format / parse_field / get_task_*  / read_section
/ has_meaningful_content）。新增 API 见下方"State (req / events / overall)"段。

V1 format (legacy):  **状态：** 待执行  / **分支：** task-001-xxx
V2 format (current): | **状态** | 待执行 |  / | **分支** | task-001-xxx |

Sections like "文档偏差" / "自审记录" exist in PM view (v1) or engineering
contract §10/§11 (v2). read_section auto-discovers across both files.

约束（spot-check #1 / #3）：
- 字段值要求**半角管道符** `|`，不支持中文 `｜`（fullwidth）
- v2 表格行格式：`| **字段名** | 值 |`，空 cell 返回 None（caller 自行判 None）
- section heading 要求**标准格式** `## N. <name>` 或 `## <name>`，
  点后必须有空格；不支持 `## 10.<name>` / `## 10。<name>` / `## 10) <name>`

错误契约：
- 单文件 reader（`read_req_meta` / `read_task_meta`）默认 strict=True 抛
  `StateReadError(path, reason)`；调用方可显式传 strict=False 拿 None / {}。
- 聚合扫描（`list_active_reqs` / `get_overall_state`）默认 tolerant，单条目
  解析失败时不抛，把 `{path, reason}` 累积到返回值的 `warnings` 数组。

active req 探测算法：以 `git worktree list` 为权威（与 skill-preamble.sh 一
致），不假设 worktree 一定在 `<repo>/.worktrees/`。
"""

from __future__ import annotations
import json
import subprocess
from pathlib import Path
from typing import Literal, Optional, TypedDict
import re


# ============================================================================
# Errors
# ============================================================================


class StateReadError(Exception):
    """Single-file reader 在 strict 模式下抛的统一异常。

    Attributes:
        path: 出错文件的路径（用于 PM 在 chat 里追溯）
        reason: 人话失败原因（缺文件 / 非法 JSON / 缺字段等）
    """

    def __init__(self, path: Path, reason: str):
        self.path = Path(path)
        self.reason = reason
        super().__init__(f"{reason}: {self.path}")


# ============================================================================
# Format detection
# ============================================================================

def detect_format(pm_view: Path) -> Literal["v1", "v2"]:
    """v2 = 存在 .engineering.md 同名文件；v1 = 仅 PM 视图单文件。"""
    eng = engineering_path(pm_view)
    return "v2" if eng.exists() else "v1"


def engineering_path(pm_view: Path) -> Path:
    """task-001-foo.md → task-001-foo.engineering.md"""
    stem = pm_view.stem
    return pm_view.parent / f"{stem}.engineering.md"


# ============================================================================
# Field parsing (v1 + v2 双兼容)
# ============================================================================

# v1: **状态：** 待执行
V1_FIELD_RE = re.compile(r"^\*\*(.+?)：\*\*\s*(.+?)\s*$", re.MULTILINE)

# v2: | **状态** | 待执行 |
V2_FIELD_RE = re.compile(
    r"^\|\s*\*\*(.+?)\*\*\s*\|\s*([^\|]+?)\s*\|\s*$",
    re.MULTILINE,
)


def parse_field(text: str, field_name: str) -> Optional[str]:
    """从文本中提取字段值。v2 优先，v1 fallback。

    空值（cell 内容仅空格）视为 None，不返回空字符串——避免 caller 把空当有效值。
    """
    for m in V2_FIELD_RE.finditer(text):
        if m.group(1).strip() == field_name:
            value = m.group(2).strip()
            return value if value else None
    for m in V1_FIELD_RE.finditer(text):
        if m.group(1).strip() == field_name:
            value = m.group(2).strip()
            return value if value else None
    return None


class TaskMeta(TypedDict, total=False):
    status: Optional[str]
    branch: Optional[str]
    worktree: Optional[str]
    dev_server: Optional[str]
    created_at: Optional[str]
    review_tools: Optional[str]
    module: Optional[str]
    module_section: Optional[str]


def get_task_status(pm_view: Path) -> Optional[str]:
    return parse_field(pm_view.read_text(encoding="utf-8"), "状态")


def get_task_branch(pm_view: Path) -> Optional[str]:
    return parse_field(pm_view.read_text(encoding="utf-8"), "分支")


def get_task_worktree(pm_view: Path) -> Optional[str]:
    return parse_field(pm_view.read_text(encoding="utf-8"), "worktree")


def get_task_meta(pm_view: Path) -> TaskMeta:
    """一次性读所有常用字段。"""
    text = pm_view.read_text(encoding="utf-8")
    return TaskMeta(
        status=parse_field(text, "状态"),
        branch=parse_field(text, "分支"),
        worktree=parse_field(text, "worktree"),
        dev_server=(
            parse_field(text, "dev server") or parse_field(text, "开发服务器")
        ),
        created_at=parse_field(text, "创建时间"),
        review_tools=(
            parse_field(text, "审查工具") or parse_field(text, "review_tools")
        ),
        module=parse_field(text, "所属模块"),
        module_section=parse_field(text, "所属模块章节"),
    )


def parse_status_from_text(text: str) -> Optional[str]:
    """从文本片段提取状态值（不要求是完整 task 文件）。

    用于 hook 检测 Edit 的 old_string / new_string。
    """
    return parse_field(text, "状态")


# ============================================================================
# Section parsing (跨 PM 视图 + 工程合同)
# ============================================================================

def read_section(
    pm_view: Path,
    section_name: str,
) -> tuple[bool, Optional[str]]:
    """跨文件查找 section。

    优先级：先工程合同（v2），未命中再 PM 视图。
    支持新格式带数字编号（## 10. 文档偏差）和旧格式（## 文档偏差）。

    返回 (found, content)。
    Content 含 section heading 之后到下一个 ## heading 之前的全部内容。

    Caller 决定 found=False 时如何处理。
    """
    heading_re = re.compile(
        rf"^##\s+(?:\d+\.\s+)?{re.escape(section_name)}\s*$",
        re.MULTILINE,
    )

    # 1. 工程合同优先
    eng = engineering_path(pm_view)
    if eng.exists():
        content = _extract_section(eng.read_text(encoding="utf-8"), heading_re)
        if content is not None:
            return (True, content)

    # 2. PM 视图（v1 / v2 退化）
    content = _extract_section(pm_view.read_text(encoding="utf-8"), heading_re)
    if content is not None:
        return (True, content)

    return (False, None)


def _extract_section(text: str, heading_re: re.Pattern) -> Optional[str]:
    """提取 section 内容。终结条件：下一个 ## heading 或 markdown horizontal rule（---）。

    fixture 里 section 用 `---` 作为分隔符（PM 视图惯例），所以 `---` 也算 section 边界。
    """
    m = heading_re.search(text)
    if not m:
        return None
    start = m.end()
    # 终结：下一个 ## heading 或 ---（horizontal rule）
    next_m = re.search(r"^(##\s+|-{3,}\s*$)", text[start:], re.MULTILINE)
    end = start + next_m.start() if next_m else len(text)
    return text[start:end].strip()


def has_meaningful_content(content: Optional[str]) -> bool:
    """除注释和空白外是否有实质字符。"""
    if not content:
        return False
    cleaned = re.sub(r"<!--.*?-->", "", content, flags=re.DOTALL)
    lines = [l for l in cleaned.splitlines() if l.strip()]
    return len(lines) > 0


# ============================================================================
# State (req / events / overall)
# ============================================================================

# Wrapper around get_task_meta（旧 API 名称 → 新 API 名称的语义对齐）。
# read_task_meta / read_task_status 是新增 API surface；内部委托到原实现，
# 加上 strict 错误契约。

# v2 修订 EVIDENCE 节录：active req 探测必须走 worktree-list（与
# skill-preamble.sh 一致），不能假设 worktree 一定在 <repo>/.worktrees/。


def _git_worktree_pairs(repo_root: Path) -> list[tuple[str, Path]]:
    """`git -C <repo> worktree list --porcelain` → [(branch, path), ...]。

    None 语义：repo 不是 git 仓 / git 未安装 → 返回空列表（不抛）。
    """
    try:
        out = subprocess.check_output(
            ["git", "-C", str(repo_root), "worktree", "list", "--porcelain"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return []
    pairs: list[tuple[str, Path]] = []
    cur_path: Optional[str] = None
    cur_branch: Optional[str] = None
    for raw in out.splitlines() + [""]:
        line = raw.rstrip()
        if line.startswith("worktree "):
            cur_path = line[len("worktree "):]
            cur_branch = None
        elif line.startswith("branch refs/heads/"):
            cur_branch = line[len("branch refs/heads/"):]
        elif line == "":
            if cur_path and cur_branch:
                pairs.append((cur_branch, Path(cur_path)))
            cur_path = None
            cur_branch = None
    return pairs


def read_req_meta(req_dir: Path, strict: bool = True) -> Optional[dict]:
    """读 req 元数据（`.req-meta.json`）。

    None 语义：
    - strict=False 且 meta 不存在 → 返回 None
    - strict=False 且 JSON 解析失败 → 返回 None
    - strict=True（默认）任一失败 → 抛 StateReadError

    >>> # read_req_meta(Path("/nope"), strict=False) is None
    """
    meta_file = req_dir / ".req-meta.json"
    if not meta_file.exists():
        if strict:
            raise StateReadError(meta_file, ".req-meta.json 不存在")
        return None
    try:
        return json.loads(meta_file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        if strict:
            raise StateReadError(meta_file, f"读取/解析失败：{e}") from e
        return None


def read_task_meta(pm_view: Path, strict: bool = True) -> Optional[TaskMeta]:
    """读 task 元数据（PM 视图头部字段）。

    None 语义：
    - strict=False 且文件不存在 → 返回 None
    - strict=True 且文件不存在 → 抛 StateReadError
    - 文件存在但字段缺失 → 返回 TaskMeta（字段值为 None），不抛

    >>> # read_task_meta(Path("/nope"), strict=False) is None
    """
    if not pm_view.exists():
        if strict:
            raise StateReadError(pm_view, "task 文件不存在")
        return None
    return get_task_meta(pm_view)


def read_task_status(pm_view: Path, strict: bool = False) -> Optional[str]:
    """读 task 状态字段。

    None 语义：
    - 文件不存在且 strict=False → None；strict=True → StateReadError
    - 字段缺失 / 空值 → 永远返回 None（v2 字段空 cell 设计）

    默认 strict=False（status-view summary 等场景大量 task 文件可能在
    fixture 异常时漏 cell，不应一处坏全停）。
    """
    if not pm_view.exists():
        if strict:
            raise StateReadError(pm_view, "task 文件不存在")
        return None
    return get_task_status(pm_view)


def read_task_events(
    repo_root: Path, task_id: str, tail: Optional[int] = None
) -> list[dict]:
    """读 task 事件流（`<repo_root>/.runs/events/<task_id>.jsonl`）。

    注意：事件文件不在 task 文件夹下，而在 repo root `.runs/events/`，
    因此参数是 repo_root + task_id，不是 task path。

    None 语义：
    - 事件文件不存在 → 返回 [] （事件流自然空，不算错）
    - 单行 JSON 坏 → 跳过该行不计入（事件流 append-only，宽容）
    - tail=N → 仅返回最末 N 条

    >>> # read_task_events(Path("/nope"), "task-001") == []
    """
    events_file = repo_root / ".runs" / "events" / f"{task_id}.jsonl"
    if not events_file.exists():
        return []
    try:
        raw = events_file.read_text(encoding="utf-8")
    except OSError:
        return []
    events: list[dict] = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(ev, dict):
            events.append(ev)
    if tail is not None and tail >= 0:
        events = events[-tail:]
    return events


_PLAN_ROW_RE = re.compile(r"^\|[^|]*?(task-\d{3,})[^|]*\|\s*([^|]*?)\s*\|")


def read_task_plan(req_dir: Path) -> Optional[dict]:
    """读 task-plan.md 计划表，返回 {tasks: [{id, title}, ...]}。

    解析仅限 task-plan.md 中第一个 `## ` heading 之前的区域（避免误命中
    `## 变更记录` / `## 执行顺序与并行性` 等段落里出现的 task id）。

    None 语义：
    - task-plan.md 不存在 → 返回 None（PM 还没规划 / 该 req 不走 task-plan）
    - 表存在但无合法行 → 返回 {"tasks": []}
    """
    plan_file = req_dir / "task-plan.md"
    if not plan_file.exists():
        return None
    try:
        content = plan_file.read_text(encoding="utf-8")
    except OSError:
        return None
    head = content.split("\n## ", 1)[0]
    seen: set[str] = set()
    tasks: list[dict] = []
    for line in head.splitlines():
        m = _PLAN_ROW_RE.match(line)
        if not m:
            continue
        tid = m.group(1).strip()
        if tid in seen:
            continue
        seen.add(tid)
        tasks.append({"id": tid, "title": m.group(2).strip()})
    return {"tasks": tasks}


def list_tasks(req_dir: Path) -> list[dict]:
    """列 req 目录下 task 文件（已 spec 过的，含 PM 视图字段）。

    返回 [{path: Path, id: str, meta: TaskMeta}, ...]，按 task id 排序。
    跳过 `.engineering.md` 副本与 `discarded/` 子目录。

    None 语义：
    - tasks/ 不存在 → 返回 []
    """
    tasks_dir = req_dir / "tasks"
    if not tasks_dir.exists():
        return []
    out: list[dict] = []
    for f in sorted(tasks_dir.glob("task-*.md")):
        if f.name.endswith(".engineering.md"):
            continue
        meta = get_task_meta(f)
        m = re.match(r"(task-\d{3,})", f.stem)
        tid = m.group(1) if m else f.stem
        out.append({"path": f, "id": tid, "meta": meta})
    return out


def discarded_task_ids(req_dir: Path) -> set[str]:
    """tasks/discarded/ 下的 task id 集合。目录不存在 → 空集。"""
    discarded_dir = req_dir / "tasks" / "discarded"
    if not discarded_dir.exists():
        return set()
    ids: set[str] = set()
    for f in discarded_dir.glob("task-*.md"):
        m = re.match(r"(task-\d{3,})", f.stem)
        if m:
            ids.add(m.group(1))
    return ids


def _collect_active_from(
    active_dir: Path, warnings: list[dict]
) -> list[tuple[Path, dict]]:
    """扫单个 requirements/active/ 目录，返回 [(req_dir, meta), ...]。"""
    if not active_dir.exists():
        return []
    found: list[tuple[Path, dict]] = []
    for req_dir in sorted(active_dir.iterdir()):
        if not req_dir.is_dir():
            continue
        meta_file = req_dir / ".req-meta.json"
        if not meta_file.exists():
            continue
        try:
            meta = json.loads(meta_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            warnings.append({"path": str(meta_file), "reason": str(e)})
            continue
        if meta.get("status") == "active":
            found.append((req_dir, meta))
    return found


def list_active_reqs(
    repo_root: Path,
    cwd: Optional[Path] = None,
    strict: bool = False,
) -> dict:
    """扫主仓 + 所有 git worktree 上的 active req（按 id 去重）。

    cwd 行为：
    - cwd 在 req-* / task-* worktree（git 视角）→ 优先扫该 worktree 自身的
      requirements/active/；若有结果直接返回（cwd 唯一定 req 语义，与
      skill-preamble.sh 一致）
    - cwd=None 或 main → 扫主仓 + 所有 `git worktree list` 拿到的 req-*

    返回：{"items": [{"req_dir": Path, "meta": dict}, ...], "warnings": [...]}
    （tolerant 默认；strict=True 时遇到 warning 抛 StateReadError）。

    None 语义：repo 无 git → items=[]、warnings=[]（与 skill-preamble fallback
    一致：没有 worktree-list 就当只有主仓自己）。
    """
    warnings: list[dict] = []
    items: list[dict] = []

    def _branch_of(p: Path) -> str:
        try:
            return subprocess.check_output(
                ["git", "-C", str(p), "branch", "--show-current"],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
        except Exception:
            return ""

    seen: set[str] = set()

    def _append(reqs: list[tuple[Path, dict]]) -> None:
        for req_dir, meta in reqs:
            if req_dir.name in seen:
                continue
            seen.add(req_dir.name)
            items.append({"req_dir": req_dir, "meta": meta})

    # cwd 落在某个 worktree → 让 cwd 优先
    if cwd is not None:
        try:
            cwd_root = Path(
                subprocess.check_output(
                    ["git", "-C", str(cwd), "rev-parse", "--show-toplevel"],
                    text=True,
                    stderr=subprocess.DEVNULL,
                ).strip()
            )
        except Exception:
            cwd_root = None
        if cwd_root is not None:
            br = _branch_of(cwd_root)
            if br.startswith("req-"):
                local = _collect_active_from(
                    cwd_root / "requirements" / "active", warnings
                )
                if local:
                    _append(local)
                    if strict and warnings:
                        w = warnings[0]
                        raise StateReadError(Path(w["path"]), w["reason"])
                    return {"items": items, "warnings": warnings}
            if br.startswith("task-"):
                # task worktree 自身 active/ 一般为空，去 req worktree 找
                for wt_branch, wt_path in _git_worktree_pairs(repo_root):
                    if wt_branch.startswith("req-"):
                        local = _collect_active_from(
                            wt_path / "requirements" / "active", warnings
                        )
                        if local:
                            _append(local)
                if items:
                    if strict and warnings:
                        w = warnings[0]
                        raise StateReadError(Path(w["path"]), w["reason"])
                    return {"items": items, "warnings": warnings}

    # 主仓 + 所有 git worktree 上的 req-* 分支
    _append(_collect_active_from(repo_root / "requirements" / "active", warnings))
    for wt_branch, wt_path in _git_worktree_pairs(repo_root):
        if not wt_branch.startswith("req-"):
            continue
        _append(_collect_active_from(wt_path / "requirements" / "active", warnings))

    if strict and warnings:
        w = warnings[0]
        raise StateReadError(Path(w["path"]), w["reason"])
    return {"items": items, "warnings": warnings}


def get_overall_state(
    repo_root: Path,
    cwd: Optional[Path] = None,
    strict: bool = False,
) -> dict:
    """聚合视图：所有 active req + 各 req 下 task 状态 + 计划/已废弃统计。

    `status-view.py` 直接消费此函数作为渲染输入（dogfood）。

    返回结构：
    {
      "active_reqs": [
        {
          "req_dir": Path,
          "meta": dict,             # .req-meta.json 全部字段
          "tasks": [                # tasks/ 下已 spec 的 task
            {"id", "path", "meta", "last_event"}
          ],
          "planned": [{"id", "title"}, ...],         # task-plan.md 顺序
          "discarded_ids": [...],
          "pending_spec": [{"id", "title"}, ...],    # planned 但未 spec 且非 discarded
        }, ...
      ],
      "warnings": [{"path", "reason"}, ...]
    }

    错误契约：默认 tolerant；strict=True 时 list_active_reqs 内任一 warning
    抛 StateReadError（聚合层不再额外收集别处错）。
    """
    raw = list_active_reqs(repo_root, cwd=cwd, strict=strict)
    warnings = list(raw["warnings"])
    out: list[dict] = []
    for item in raw["items"]:
        req_dir = item["req_dir"]
        meta = item["meta"]
        tasks = list_tasks(req_dir)
        discarded = discarded_task_ids(req_dir)
        plan = read_task_plan(req_dir)
        planned = plan["tasks"] if plan else []
        specced_ids = {t["id"] for t in tasks}
        pending_spec = [
            p for p in planned
            if p["id"] not in specced_ids and p["id"] not in discarded
        ]
        enriched_tasks: list[dict] = []
        for t in tasks:
            last_event = None
            evs = read_task_events(repo_root, t["path"].stem, tail=1)
            if evs:
                last_event = evs[-1]
            enriched_tasks.append({**t, "last_event": last_event})
        out.append({
            "req_dir": req_dir,
            "meta": meta,
            "tasks": enriched_tasks,
            "planned": planned,
            "discarded_ids": sorted(discarded),
            "pending_spec": pending_spec,
        })
    return {"active_reqs": out, "warnings": warnings}


# ============================================================================
# CLI entry (供 bash 调用)
# ============================================================================

def _print_doctor(repo_root: Path, req_arg: Optional[str]) -> int:
    """`python3 -m _lib.state doctor [<req>]`

    打印：当前 repo_root / cwd / active req 探测结果 / 指定 req 的 meta + task
    列表 + warning。PM 在 chat 复制粘贴跑，定位"为什么 active req 不一致"。
    """
    import sys

    print(f"repo_root: {repo_root}")
    print(f"cwd:       {Path.cwd()}")

    state = get_overall_state(repo_root, cwd=Path.cwd(), strict=False)
    print(f"active req 数量: {len(state['active_reqs'])}")
    for item in state["active_reqs"]:
        meta = item["meta"]
        rd = item["req_dir"]
        print(f"  - {meta.get('id', '?')} ({meta.get('name', '?')})"
              f"  stage={meta.get('stage', '?')}  status={meta.get('status', '?')}")
        print(f"    dir={rd}")
        print(f"    tasks={len(item['tasks'])}  "
              f"planned={len(item['planned'])}  "
              f"pending_spec={len(item['pending_spec'])}  "
              f"discarded={len(item['discarded_ids'])}")

    if state["warnings"]:
        print("WARNINGS:")
        for w in state["warnings"]:
            print(f"  - {w['path']}: {w['reason']}")

    if req_arg:
        # 精确诊断单个 req
        target: Optional[dict] = None
        for item in state["active_reqs"]:
            if item["meta"].get("id") == req_arg or item["req_dir"].name == req_arg:
                target = item
                break
        if target is None:
            print(f"\n指定的 req `{req_arg}` 未在 active 列表中。", file=sys.stderr)
            return 3
        print(f"\n=== req `{req_arg}` 明细 ===")
        print(json.dumps({
            "meta": target["meta"],
            "tasks": [
                {
                    "id": t["id"],
                    "status": (t["meta"] or {}).get("status"),
                    "branch": (t["meta"] or {}).get("branch"),
                } for t in target["tasks"]
            ],
            "planned": target["planned"],
            "pending_spec": target["pending_spec"],
            "discarded_ids": target["discarded_ids"],
        }, ensure_ascii=False, indent=2))
    return 0


def _cli():
    import sys
    if len(sys.argv) < 2:
        print(
            "usage: python3 -m _lib.state <fn> [args...]\n"
            "  fns: get_status / get_branch / get_worktree / get_meta /\n"
            "       read_section / detect_format / read_req_meta /\n"
            "       list_active_reqs / get_overall_state / doctor",
            file=sys.stderr,
        )
        sys.exit(2)

    fn = sys.argv[1]

    # 聚合 / state-level 子命令：参数不是 task pm_view
    if fn == "doctor":
        # doctor [<req-id>]  — repo_root 由 cwd 推导（取 git common-dir 的父）
        repo_root = Path.cwd()
        try:
            common = subprocess.check_output(
                ["git", "rev-parse", "--git-common-dir"],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
            if common:
                repo_root = (Path(common).resolve().parent
                             if common != ".git"
                             else Path.cwd())
        except Exception:
            pass
        req_arg = sys.argv[2] if len(sys.argv) > 2 else None
        sys.exit(_print_doctor(repo_root, req_arg))

    if fn == "read_req_meta":
        if len(sys.argv) < 3:
            print("usage: read_req_meta <req_dir>", file=sys.stderr)
            sys.exit(2)
        req_dir = Path(sys.argv[2])
        try:
            meta = read_req_meta(req_dir, strict=True)
        except StateReadError as e:
            print(str(e), file=sys.stderr)
            sys.exit(1)
        print(json.dumps(meta, ensure_ascii=False))
        return

    if fn == "list_active_reqs":
        # list_active_reqs [<repo_root>]
        repo_root = Path(sys.argv[2]) if len(sys.argv) > 2 else Path.cwd()
        out = list_active_reqs(repo_root, cwd=Path.cwd(), strict=False)
        print(json.dumps({
            "items": [
                {"req_dir": str(i["req_dir"]), "meta": i["meta"]}
                for i in out["items"]
            ],
            "warnings": out["warnings"],
        }, ensure_ascii=False))
        return

    if fn == "get_overall_state":
        repo_root = Path(sys.argv[2]) if len(sys.argv) > 2 else Path.cwd()
        out = get_overall_state(repo_root, cwd=Path.cwd(), strict=False)
        # 仅打印结构化摘要，不打 last_event 全文（避免 stdout 过长）
        print(json.dumps({
            "active_reqs": [
                {
                    "req_dir": str(r["req_dir"]),
                    "meta": r["meta"],
                    "task_count": len(r["tasks"]),
                    "pending_spec_count": len(r["pending_spec"]),
                } for r in out["active_reqs"]
            ],
            "warnings": out["warnings"],
        }, ensure_ascii=False))
        return

    # 以下是原 task_parser 单文件 reader（pm_view 必填）
    if len(sys.argv) < 3:
        print(f"usage: python3 -m _lib.state {fn} <pm_view> [args...]",
              file=sys.stderr)
        sys.exit(2)
    pm_view = Path(sys.argv[2])

    if not pm_view.exists():
        print(f"task file not found: {pm_view}", file=sys.stderr)
        sys.exit(1)

    if fn == "get_status":
        print(get_task_status(pm_view) or "")
    elif fn == "get_branch":
        print(get_task_branch(pm_view) or "")
    elif fn == "get_worktree":
        print(get_task_worktree(pm_view) or "")
    elif fn == "get_meta":
        print(json.dumps(get_task_meta(pm_view), ensure_ascii=False))
    elif fn == "read_section":
        if len(sys.argv) < 4:
            print(
                "usage: read_section <pm_view> <section_name>",
                file=sys.stderr,
            )
            sys.exit(2)
        section_name = sys.argv[3]
        found, content = read_section(pm_view, section_name)
        if not found:
            sys.exit(3)  # 让 bash caller 通过 exit code 区分
        print(content or "")
    elif fn == "detect_format":
        print(detect_format(pm_view))
    else:
        print(f"unknown fn: {fn}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    _cli()
