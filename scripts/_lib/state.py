"""State reader — single authority for reading PM-AI-Workflow runtime state.

跨 skill 统一读层：把 req / 聚合视图的读取从各处 grep + jq
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
- 单文件 reader（`read_req_meta`）默认 strict=True 抛
  `StateReadError(path, reason)`；调用方可显式传 strict=False 拿 None / {}。
- 聚合扫描（`list_active_reqs` / `get_overall_state`）默认 tolerant，单条目
  解析失败时不抛，把 `{path, reason}` 累积到返回值的 `warnings` 数组。

active req 探测算法：以 `git worktree list` 为权威（与 skill-preamble.sh 一
致），不假设 worktree 一定在 `<repo>/.worktrees/`。
"""

from __future__ import annotations
import json
import os
import subprocess
import tempfile
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

TASK_FORMAT_V3_MARKER = "task_format: single-typed-v3"


def detect_format(pm_view: Path) -> Literal["v1", "v2", "v3"]:
    """三态判别—— 塌缩后仓里同时存在 3 种 task 格式：

    - **v2** 双文件（在飞旧 task）：存在 `.engineering.md` 同名文件。
    - **v3** 新单文件 typed contract：无 `.engineering.md` + 头部有 `task_format` 标记。
    - **v1** 老单文件（历史，薄 PM 视图）：无 `.engineering.md` + 无标记。

    不能再用「无 .engineering.md = v1」—— v3 也无 `.engineering.md`，靠
    `task_format` 标记区分 v1 / v3。
    """
    eng = engineering_path(pm_view)
    if eng.exists():
        return "v2"
    try:
        head = pm_view.read_text(encoding="utf-8")[:600]
    except OSError:
        return "v1"
    if TASK_FORMAT_V3_MARKER in head:
        return "v3"
    return "v1"


def engineering_path(pm_view: Path) -> Path:
    """task-001-foo.md → task-001-foo.engineering.md"""
    stem = pm_view.stem
    return pm_view.parent / f"{stem}.engineering.md"


# ============================================================================
# Field parsing (v1 + v2 双兼容)
# ============================================================================

# v1: **状态：** 待执行
# 只吞同一行内的空白；`\s*` 会跨换行，导致空字段误读成下一行字段名。
V1_FIELD_RE = re.compile(
    r"^\*\*(.+?)：\*\*[^\S\r\n]*(.*?)[^\S\r\n]*$",
    re.MULTILINE,
)

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
    标题前缀容忍：emoji（## 📋 文档偏差，v3 单文件 typed contract）、数字编号
    （## 10. 文档偏差，v2 工程合同）、无前缀（## 文档偏差，v1）；也容忍 section
    名后的括号注释后缀（## 10. 文档偏差（execution agent 填写）等存量 task）。

    返回 (found, content)。
    Content 含 section heading 之后到下一个 ## heading 之前的全部内容。

    Caller 决定 found=False 时如何处理。
    """
    # 前缀只容忍数字编号（10. ）或一组符号/emoji 图标（以空白与正文分隔）；
    # `[^\w\s]` 天然排除中文与字母数字（中文是 \w），故不会误吞 `## 其他 文档偏差`
    # 的「其他」。后缀只容忍空白 / 括号注释 / 行尾 —— 防误匹配 `## 文档偏差说明`。
    _prefix = r"(?:\d+\.\s+|[^\w\s]+\s+)?"
    heading_re = re.compile(
        rf"^##\s+{_prefix}{re.escape(section_name)}\s*(?:[（(].*)?$",
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


def write_json_atomic(path: Path, data: dict) -> None:
    """Atomically write JSON to `path` via a temp file in the same directory."""
    path = Path(path)
    tmp_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as fh:
            tmp_name = fh.name
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_name, path)
        tmp_name = None
        try:
            dir_fd = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except OSError:
            pass
    finally:
        if tmp_name:
            try:
                os.unlink(tmp_name)
            except FileNotFoundError:
                pass


def resolve_req_relative_path(
    req_dir: Path,
    value: object,
    field_name: str = "path",
) -> Path:
    """Resolve a metadata path that must remain inside `req_dir`.

    The stage-source contract stores req-relative paths only. Reject absolute
    paths, `..`, backslashes, empty segments and NULs before joining.
    """
    meta_file = req_dir / ".req-meta.json"
    if not isinstance(value, str):
        raise StateReadError(meta_file, f"{field_name} 必须是字符串")
    if value != value.strip() or not value:
        raise StateReadError(meta_file, f"{field_name} 非法路径：{value!r}")
    if "\x00" in value or "\\" in value:
        raise StateReadError(meta_file, f"{field_name} 非法路径：{value!r}")

    rel = Path(value)
    if rel.is_absolute() or any(part in ("", ".", "..") for part in rel.parts):
        raise StateReadError(meta_file, f"{field_name} 必须是 req 内相对路径：{value}")

    root = req_dir.resolve()
    resolved = (root / rel).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as e:
        raise StateReadError(meta_file, f"{field_name} 越过 req 目录：{value}") from e
    return resolved


def get_stage_source(req_dir: Path, stage_num: int) -> Path:
    """返回 stage N 的真相源**绝对路径**（路径契约）。

    解析优先级：
    1. `.req-meta.json` 的 `stage{N}_source` 字段（req 内**相对路径**） — 跨工具
       分流时由 caller 显式写入（见 `set_stage_source`）；此为权威解。
    2. fallback 到 `STAGE_OUTPUT_FILES[stage_num]`（stages.py 默认产物文件名）；
       覆盖：旧 req（v4 之前没写元数据字段）+ caller 没显式设置的 stage。

    返回值是 `req_dir / <relative>`，调用方应 `.exists()` 自检（本函数不读盘
    校验存在性，纯路径解析；保留调用方 vs `read_text()` 直抛 FileNotFound 的
    错误信息空间）。

    Raises:
        KeyError: stage_num 不在 `STAGE_OUTPUT_FILES` 字典里（六步里只有 stage 1
        有默认产物 req-plan.md；如 stage 2/3/4），且 `.req-meta.json` 也没有 `stage{N}_source` override。调用方应
        知道自己要 stage N 是否在默认表里 —— 这是契约错误不是数据错误。
    """
    meta = read_req_meta(req_dir, strict=False)
    field = f"stage{stage_num}_source"
    if meta and field in meta:
        return resolve_req_relative_path(req_dir, meta[field], field)
    # fallback — 默认产物文件名
    from .stages import STAGE_OUTPUT_FILES
    return (req_dir / STAGE_OUTPUT_FILES[stage_num]).resolve()


def get_current_stage_banner(req_dir: Path, skill: str = "REQ-STAGE-GATE") -> str:
    """返回 stage banner 字符串（M2）。

    格式：`━━━ PMAI ► <SKILL> ▸ <Name> ━━━`（去 stage 号，见 `_shared/pm-view/banner-rules.md` §1.1）。

    Args:
        req_dir: req 目录绝对路径（含 `.req-meta.json`）。
        skill: 调用方 skill 名（大写形态，如 `REQ-STAGE-GATE` / `INIT-PROJECT`）；
               默认 `REQ-STAGE-GATE`（最常见调用方）。

    Returns:
        固定格式 banner 字符串（不带尾部换行）。

    Raises:
        StateReadError: `.req-meta.json` 不存在 / 解析失败 / 缺 stage 字段。
        KeyError: stage 数不在 STAGE_NAMES（1-MAX_STAGE，六步=1-4）；理论上不会发生（状态机受 INVARIANTS 保护）。
    """
    meta = read_req_meta(req_dir, strict=True)
    assert meta is not None
    stage = meta.get("stage")
    if stage is None:
        raise StateReadError(req_dir / ".req-meta.json", "缺 stage 字段")
    from .stages import STAGE_NAMES
    stage_name = STAGE_NAMES[int(stage)]
    return f"━━━ PMAI ► {skill} ▸ {stage_name} ━━━"


def set_stage_source(
    req_dir: Path,
    stage_num: int,
    filename: str,
    tool: str,
    origin: Optional[str] = None,
) -> None:
    """写 stage N 的真相源元数据到 `.req-meta.json`（路径契约）。

    Args:
        req_dir: req 目录绝对路径（含 `.req-meta.json`）。
        stage_num: stage 序号（1-MAX_STAGE，六步=1-4）。
        filename: req 内**相对路径**（如 `analysis.md` / `stage2-office-hours.md`）；
                  caller 已确认文件在该路径下落盘。
        tool: 产生该产物的工具名（如 `req-questioning` / `office-hours`），追溯用。
        origin: 可选 — 外部源原始绝对路径。office-hours 分支 snapshot 复制后
                记 `~/.gstack/projects/<slug>/<file>` 原始 path（追溯，不参与
                解析）；A 分支无此字段。

    写入字段：
        - `stage{N}_source` = filename
        - `stage{N}_tool` = tool
        - `stage{N}_source_origin` = origin（仅 origin 非空时写入）

    Raises:
        StateReadError: `.req-meta.json` 不存在或 JSON 解析失败（与
        `read_req_meta(strict=True)` 一致）；caller 应在 req 已落盘后调用。
    """
    meta = read_req_meta(req_dir, strict=True)
    assert meta is not None  # strict=True 不会返回 None
    resolve_req_relative_path(req_dir, filename, f"stage{stage_num}_source")
    meta[f"stage{stage_num}_source"] = filename
    meta[f"stage{stage_num}_tool"] = tool
    if origin is not None:
        meta[f"stage{stage_num}_source_origin"] = origin
    meta_file = req_dir / ".req-meta.json"
    write_json_atomic(meta_file, meta)


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


# ---------------------------------------------------------------------------
# 真相源（lifecycle 迁移批 2，单读）：docs/modules/<模块>/.req-meta.json
#
# 新真相源 = docs/modules/*/.req-meta.json（lifecycle 迁移计划 ①）。批 0 曾双读
# 旧 requirements/active|closed/ + 新 docs/modules/*，批 2 已删旧扫描、原子切单读。
# dedup 仍在调用方 `_append` / `_dedup_archived` 里按 meta.id（缺则目录名）去重——
# 主仓 + 各 req worktree 可能各暴露同一 req 的模块文件夹，按 id 去重避免双算。
# ---------------------------------------------------------------------------

def _collect_from_modules(
    modules_dir: Path, warnings: list[dict], statuses: tuple[str, ...]
) -> list[tuple[Path, dict]]:
    """扫 docs/modules/*/.req-meta.json，返回 status ∈ statuses 的 [(module_dir, meta), ...]。

    真相源是模块文件夹（每个模块目录直接含 `.req-meta.json`，无 active/closed
    二级目录）。`statuses` 过滤所需状态集（active / closed / cancelled）。
    """
    if not modules_dir.exists():
        return []
    found: list[tuple[Path, dict]] = []
    for module_dir in sorted(modules_dir.iterdir()):
        if not module_dir.is_dir():
            continue
        meta_file = module_dir / ".req-meta.json"
        if not meta_file.exists():
            continue
        try:
            meta = json.loads(meta_file.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            warnings.append({"path": str(meta_file), "reason": str(e)})
            continue
        if meta.get("status") in statuses:
            found.append((module_dir, meta))
    return found


def list_active_reqs(
    repo_root: Path,
    cwd: Optional[Path] = None,
    strict: bool = False,
) -> dict:
    """扫主仓 + 所有 git worktree 上的 active req（按 id 去重）。

    cwd 行为：
    - cwd 在 req-* worktree（git 视角）→ 优先扫该 worktree 自身的
      docs/modules/*（批 2 单读真相源）；若有结果直接返回（cwd 唯一定 req 语义，
      与 skill-preamble.sh 一致）
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

    def _dedup_key(req_dir: Path, meta: dict) -> str:
        # 按 meta.id 去重（缺 id 才退回目录名）：主仓 + 各 req worktree 可能各暴露同一
        # req 的模块文件夹（module 目录名 ≠ req 分支名），不按 id 去重会被算两次。
        rid = meta.get("id") if isinstance(meta, dict) else None
        return rid if isinstance(rid, str) and rid else req_dir.name

    def _append(reqs: list[tuple[Path, dict]]) -> None:
        for req_dir, meta in reqs:
            key = _dedup_key(req_dir, meta)
            if key in seen:
                continue
            seen.add(key)
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
                # 批 2 单读：真相源只剩 docs/modules/*/.req-meta.json（status==active）。
                local = _collect_from_modules(
                    cwd_root / "docs" / "modules", warnings, ("active",)
                )
                if local:
                    _append(local)
                    if strict and warnings:
                        w = warnings[0]
                        raise StateReadError(Path(w["path"]), w["reason"])
                    return {"items": items, "warnings": warnings}
    # 主仓 + 所有 git worktree 上的 req-* 分支
    # 批 2 单读：真相源 = docs/modules/*/.req-meta.json（status==active）。旧
    # requirements/active/ 扫描已删（迁移脚本仍保留旧目录数据，本批只切机器读向）。
    _append(_collect_from_modules(repo_root / "docs" / "modules", warnings, ("active",)))
    for wt_branch, wt_path in _git_worktree_pairs(repo_root):
        if not wt_branch.startswith("req-"):
            continue
        _append(_collect_from_modules(wt_path / "docs" / "modules", warnings, ("active",)))

    if strict and warnings:
        w = warnings[0]
        raise StateReadError(Path(w["path"]), w["reason"])
    return {"items": items, "warnings": warnings}


def get_overall_state(
    repo_root: Path,
    cwd: Optional[Path] = None,
    strict: bool = False,
) -> dict:
    """聚合视图：所有 active req。

    `status-view.py` 直接消费此函数作为渲染输入（dogfood）。

    返回结构：
    {
      "active_reqs": [
        {
          "req_dir": Path,
          "meta": dict,             # .req-meta.json 全部字段
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
        out.append({
            "req_dir": req_dir,
            "meta": meta,
        })
    return {"active_reqs": out, "warnings": warnings}


# ============================================================================
# Archived reqs (closed / cancelled) + Timeline 
# ============================================================================


def _dedup_archived(
    pairs: list[tuple[Path, dict]], want_status: str
) -> list[dict]:
    """从 [(module_dir, meta), ...] 取 status==want_status 的，按 meta.id（缺则目录名）去重。

    主仓 + 各 req worktree 可能各暴露同一 req 的模块文件夹，按 id 去重避免双算
    （同 list_active_reqs 的 _dedup_key 逻辑）。
    """
    seen: set[str] = set()
    out: list[dict] = []
    for req_dir, meta in pairs:
        if meta.get("status") != want_status:
            continue
        rid = meta.get("id") if isinstance(meta, dict) else None
        key = rid if isinstance(rid, str) and rid else req_dir.name
        if key in seen:
            continue
        seen.add(key)
        out.append({"req_dir": req_dir, "meta": meta})
    return out


def list_closed_reqs(repo_root: Path, strict: bool = False) -> dict:
    """扫 docs/modules/* 拿 status='closed' 的 req（不含 cancelled）。

    批 2 单读：真相源只剩 docs/modules/*/.req-meta.json。旧 requirements/closed/
    扫描已删。注：方案 A/B（close 后删 .req-meta vs 留 status=closed）是批 3 的事，
    本批只切读向——若批 3 选方案 A，closed/cancelled 列表自然为空（无文件可读）。
    """
    warnings: list[dict] = []
    pairs = _collect_from_modules(
        repo_root / "docs" / "modules", warnings, ("closed",)
    )
    items = _dedup_archived(pairs, "closed")
    if strict and warnings:
        w = warnings[0]
        raise StateReadError(Path(w["path"]), w["reason"])
    return {"items": items, "warnings": warnings}


def list_cancelled_reqs(repo_root: Path, strict: bool = False) -> dict:
    """扫 docs/modules/* 拿 status='cancelled' 的 req。批 2 单读（同 list_closed_reqs）。"""
    warnings: list[dict] = []
    pairs = _collect_from_modules(
        repo_root / "docs" / "modules", warnings, ("cancelled",)
    )
    items = _dedup_archived(pairs, "cancelled")
    if strict and warnings:
        w = warnings[0]
        raise StateReadError(Path(w["path"]), w["reason"])
    return {"items": items, "warnings": warnings}


def _get_close_date(meta: dict):
    """从 meta 拿 close / cancel 时间，fallback stage_history 最后项。"""
    from datetime import datetime
    for key in ("closed_at", "cancelled_at"):
        if meta.get(key):
            try:
                return datetime.fromisoformat(
                    meta[key].replace("Z", "+00:00")
                ).replace(tzinfo=None)
            except Exception:
                pass
    history = meta.get("stage_history", [])
    if history:
        last = history[-1]
        if last.get("entered_at"):
            try:
                return datetime.fromisoformat(
                    last["entered_at"].replace("Z", "+00:00")
                ).replace(tzinfo=None)
            except Exception:
                pass
    return None


def get_timeline_state(
    repo_root: Path,
    cwd: Optional[Path] = None,
    strict: bool = False,
    since: Optional[str] = None,
    module: Optional[str] = None,
    limit: Optional[int] = 20,
) -> dict:
    """全局 req 时间线视图（active + closed + cancelled）。

    参数:
        since: ISO date YYYY-MM-DD; 仅返回 close/cancel 时间 >= since 的 archived
        module: 仅返回涉及该 module 的 req（meta.modules / meta.name 包含）
        limit: archived (closed + cancelled) 总数限制（None = 无上限）

    返回:
      {
        "active": [...],
        "closed": [...],   # 时间倒序
        "cancelled": [...],# 时间倒序
        "total_archived": int,  # 过滤前总数
        "truncated": int,       # 被 limit 截断的数量
        "warnings": [...],
      }
    每个 item: {req_dir, meta, close_date (datetime or None)}
    """
    from datetime import datetime

    warnings: list[dict] = []

    # active
    active_result = list_active_reqs(repo_root, cwd, strict=False)
    warnings.extend(active_result.get("warnings", []))
    active_items = active_result["items"]

    # closed + cancelled
    closed_result = list_closed_reqs(repo_root, strict=False)
    warnings.extend(closed_result.get("warnings", []))
    closed_items = closed_result["items"]

    cancelled_result = list_cancelled_reqs(repo_root, strict=False)
    warnings.extend(cancelled_result.get("warnings", []))
    cancelled_items = cancelled_result["items"]

    def enrich(item):
        item["close_date"] = _get_close_date(item["meta"])
        return item

    active_items = [enrich(i) for i in active_items]
    closed_items = [enrich(i) for i in closed_items]
    cancelled_items = [enrich(i) for i in cancelled_items]

    # 过滤 since
    if since:
        try:
            since_date = datetime.fromisoformat(since)
        except ValueError as e:
            raise ValueError(f"--since 必须是 ISO 日期 YYYY-MM-DD: {e}")
        closed_items = [
            i for i in closed_items
            if i.get("close_date") and i["close_date"] >= since_date
        ]
        cancelled_items = [
            i for i in cancelled_items
            if i.get("close_date") and i["close_date"] >= since_date
        ]

    # 过滤 module（meta.name 含 module 关键词或 meta.modules 列表含）
    if module:
        def match_module(item):
            meta = item["meta"]
            modules_list = meta.get("modules", [])
            if module in modules_list:
                return True
            if module.lower() in meta.get("name", "").lower():
                return True
            return False
        closed_items = [i for i in closed_items if match_module(i)]
        cancelled_items = [i for i in cancelled_items if match_module(i)]
        active_items = [i for i in active_items if match_module(i)]

    # 时间倒序
    closed_items.sort(key=lambda i: i.get("close_date") or datetime.min, reverse=True)
    cancelled_items.sort(key=lambda i: i.get("close_date") or datetime.min, reverse=True)

    # limit (split 80/20 closed/cancelled)
    total_archived = len(closed_items) + len(cancelled_items)
    truncated = 0
    if limit is not None and limit > 0 and total_archived > limit:
        c_limit = min(len(closed_items), int(limit * 0.8) or 1)
        x_limit = max(0, limit - c_limit)
        truncated = total_archived - (c_limit + x_limit)
        closed_items = closed_items[:c_limit]
        cancelled_items = cancelled_items[:x_limit]

    return {
        "active": active_items,
        "closed": closed_items,
        "cancelled": cancelled_items,
        "total_archived": total_archived,
        "truncated": truncated,
        "warnings": warnings,
    }


# ============================================================================
# CLI entry (供 bash 调用)
# ============================================================================

def _print_doctor(repo_root: Path, req_arg: Optional[str]) -> int:
    """`python3 -m _lib.state doctor [<req>]`

    打印：当前 repo_root / cwd / active req 探测结果 / 指定 req 的 meta
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
