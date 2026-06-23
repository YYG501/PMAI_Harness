"""Attachments helper —  Model 2 AI 接管层。

设计源：设计文档（生成器仓） ，落地后归档为
设计文档（已归档于生成器仓）。

PM mental model：PM 在 chat 自然描述 "我有 X 在路径 Y"，AI 后台 cp + 命名 +
归入 docs/inputs/attachments/ + 登记到 .req-meta.json:attachments_seen +
caller SKILL 在 stage 产出文档末尾追加 `## 📎 参考材料` 引用。

与  _lib.state.{get,set}_stage_source 同款 helper-based 架构。
状态真相源 = .req-meta.json:attachments_seen（与  stage{N}_source 字段
共住同一份 meta），不是 stage 产出文档里的 ## 📎 参考材料 section（该 section
仅作 PM 可见展示）。

调用流（caller SKILL 视角）::

    +-----------------------------------------------------------+
    |  PM chat: "我有份 X 在 ~/Downloads/foo.pdf，重点是 Y"        |
    +-----------------------------------------------------------+
                            |
                            v
    +-----------------------------------------------------------+
    |  caller SKILL: trigger 0 LLM 识别上传意图                    |
    |                       |                                    |
    |   from _lib.attachments import copy_attachment             |
    |   r = copy_attachment(req_dir, Path("~/Downloads/foo.pdf"),|
    |                       stage_prefix="req-plan",             |
    |                       hint="Y 重点")                         |
    +-----------------------------------------------------------+
                            |
                            v
    +-----------------------------------------------------------+
    |  helper 6 步                                                |
    |    1. src.expanduser().resolve() + 校验 is_file             |
    |    2. _check_sensitive(src) → SensitivePathError            |
    |    3. size > MAX_FILE_SIZE_MB → FileSizeError                |
    |    4. _next_available_name → 冲突 -2/-3 后缀                 |
    |    5. shutil.copy2 落盘 docs/inputs/attachments/<新名>       |
    |    6. register_attachment → .req-meta.json 登记              |
    +-----------------------------------------------------------+
                            |
                            v
    +-----------------------------------------------------------+
    |  CopyResult(new_name, abs_path, size_mb, pending_inject)   |
    |  caller chat 一行确认；后续按需渲染 ## 📎 参考材料 引用     |
    +-----------------------------------------------------------+

非典型场景：
- B 分支 office-hours 选源期间 caller SKILL **不调** copy_attachment
  （走 _lib.state.set_stage_source， 路径，不归档为 attachment）
- standalone /pmai-prd-writing 模式 caller SKILL **不调** copy_attachment
  （standalone 不绑 req → 不入 req attachments_seen）
"""

from __future__ import annotations

import re
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, TypedDict

from .state import read_req_meta, write_json_atomic


# ============================================================================
# 安全配置（v2 §0.4.11-14, Codex C6 + C10）
# ============================================================================

# 敏感路径 denylist —— src 路径正则匹配命中即 raise SensitivePathError。
# 经验值；消费仓发现新 case 扩展（v2 §5.1.2 待验）。
# 大小写不敏感（IGNORECASE）。
SENSITIVE_PATH_PATTERNS: list[str] = [
    r"/\.env\b",            # .env / .env.local / .env.production
    r"/\.ssh/",             # SSH keys / known_hosts / config
    r"/\.aws/",             # AWS credentials / config
    r"/\.gnupg/",           # GPG keys / trustdb
    r"/\.netrc\b",          # netrc credentials
    r"/\.npmrc\b",          # npm auth tokens
    r"/\.pypirc\b",         # PyPI upload credentials
    r"/Library/Keychains/", # macOS keychain
    # 注：`/private/var/` 不在 denylist —— macOS `tempfile.TemporaryDirectory()`
    # 默认 resolve 到 `/private/var/folders/...`（合法用户临时目录），加这条会
    # 误伤所有走 tempfile 的合法 case。系统级私有目录（`/private/var/db/` /
    # `/private/var/root/`）由 OS file permission 自然防（PM 也读不到）。
    r"token",               # 模糊：.token / oauth-token / api-token / token.txt
    r"credential",          # 模糊：credentials.json / *.credential
    r"secret",              # 模糊：secret.json / secrets/
    r"password",            # 模糊
]

# 单文件 hard cap（MB）。超 → FileSizeError，不依赖 pre-commit warn fail-open。
# pre-commit hook warn 阈值 10MB；hard cap 50MB 是经验值（v2 §5.1.3 待验）。
MAX_FILE_SIZE_MB: int = 50


# ============================================================================
# Errors
# ============================================================================


class AttachmentError(Exception):
    """attachments helper 统一异常基类。caller catch 此即覆盖全场景。"""


class SensitivePathError(AttachmentError):
    """源路径命中 SENSITIVE_PATH_PATTERNS denylist。

    Attributes:
        src: 命中的源路径
        pattern: 命中的 regex pattern（追溯）
    """

    def __init__(self, src: Path, pattern: str):
        self.src = src
        self.pattern = pattern
        super().__init__(f"路径含敏感关键词 ({pattern})，拒纳：{src}")


class FileSizeError(AttachmentError):
    """源文件超 MAX_FILE_SIZE_MB hard cap。

    Attributes:
        src: 超大的源路径
        size_mb: 实际大小（MB）
    """

    def __init__(self, src: Path, size_mb: float):
        self.src = src
        self.size_mb = size_mb
        super().__init__(
            f"文件 {size_mb:.1f}MB 超 hard cap {MAX_FILE_SIZE_MB}MB：{src}"
        )


# ============================================================================
# Types
# ============================================================================


class AttachmentSeenEntry(TypedDict, total=False):
    """`.req-meta.json:attachments_seen` 列表元素 schema。

    Fields:
        name: repo 内相对路径（如 `docs/inputs/attachments/analysis-interview.pdf`）—— 真相源
        src_origin: PM 给的源绝对路径（追溯用；replace 后会更新）
        hint: PM 给的"重点"描述（追溯用，可空）
        stage_prefix: 上传时 stage 前缀（命名时的 stage 上下文）
        registered_at: ISO 8601 UTC 登记时间
    """

    name: str
    src_origin: str
    hint: Optional[str]
    stage_prefix: str
    registered_at: str


class CopyResult(TypedDict):
    """`copy_attachment` 返回值 schema。

    Fields:
        new_name: 落盘后的 req 内相对路径（机械命名 + 冲突 -N 后缀后）
        abs_path: 落盘绝对路径
        size_mb: 文件大小（MB）
        pending_inject: True 表示当前 stage 产出文档不存在 → helper 仅 register
                        attachments_seen 不触发引用 section 渲染；caller SKILL
                        后续写产出时应主动读 attachments_seen 渲染。
    """

    new_name: str
    abs_path: Path
    size_mb: float
    pending_inject: bool


# ============================================================================
# Internal helpers
# ============================================================================


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _check_sensitive(src: Path) -> None:
    """raise SensitivePathError 如果 src 命中 denylist。"""
    src_str = str(src.resolve())
    for pattern in SENSITIVE_PATH_PATTERNS:
        if re.search(pattern, src_str, re.IGNORECASE):
            raise SensitivePathError(src, pattern)


def _validate_attachment_name(filename: str) -> str:
    """Return a safe relative attachment path under docs/inputs or raise."""
    if not isinstance(filename, str):
        raise AttachmentError("attachment filename 必须是字符串")
    if filename != filename.strip() or not filename:
        raise AttachmentError(f"非法 attachment filename：{filename!r}")
    if (
        "\x00" in filename
        or "\\" in filename
        or ".." in filename
        or Path(filename).is_absolute()
        or filename in {".", ".."}
    ):
        raise AttachmentError(f"非法 attachment filename：{filename!r}")
    p = Path(filename)
    if p.parts[:2] != ("docs", "inputs") or len(p.parts) < 4:
        raise AttachmentError(f"attachment filename 必须位于 docs/inputs/<类别>/：{filename!r}")
    return filename


def _validate_stage_prefix(stage_prefix: str) -> str:
    """Restrict stage_prefix to a filename-safe token used in generated names."""
    if not isinstance(stage_prefix, str):
        raise AttachmentError("stage_prefix 必须是字符串")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", stage_prefix):
        raise AttachmentError(f"非法 stage_prefix：{stage_prefix!r}")
    if ".." in stage_prefix:
        raise AttachmentError(f"非法 stage_prefix：{stage_prefix!r}")
    return stage_prefix


def _attachment_path(req_dir: Path, filename: str) -> Path:
    """Resolve `docs/inputs/<类别>/<filename>` from repo root and enforce boundary."""
    safe_name = _validate_attachment_name(filename)
    repo_root = _repo_root_from_req_dir(req_dir)
    inputs_dir = (repo_root / "docs" / "inputs").resolve()
    dst = (repo_root / safe_name).resolve()
    try:
        dst.relative_to(inputs_dir)
    except ValueError as e:
        raise AttachmentError(f"attachment 路径越过 docs/inputs/：{filename!r}") from e
    return dst


def _repo_root_from_req_dir(req_dir: Path) -> Path:
    """Infer repo root from docs/modules/<module> req_dir."""
    req_dir = req_dir.resolve()
    if len(req_dir.parents) >= 3 and req_dir.parent.name == "modules" and req_dir.parent.parent.name == "docs":
        return req_dir.parent.parent.parent
    return req_dir.parent


def _next_available_name(
    attachments_dir: Path, base_name: str, ext: str
) -> str:
    """同名冲突时返回 `<base>-2.ext` / `<base>-3.ext` / ... 直到不冲突。

    Args:
        attachments_dir: 已 mkdir 的 docs/inputs/attachments/ 目录
        base_name: 候选基名（不含扩展名，如 `analysis-foo`）
        ext: 扩展名（含点，如 `.pdf`）；可空字符串

    Deterministic：相同输入相同输出（C7 防 race）。
    """
    candidate = f"{base_name}{ext}"
    if not (attachments_dir / candidate).exists():
        return candidate
    counter = 2
    while True:
        candidate = f"{base_name}-{counter}{ext}"
        if not (attachments_dir / candidate).exists():
            return candidate
        counter += 1


def _stage_doc_exists(req_dir: Path, stage_prefix: str) -> bool:
    """判断当前 stage 产出文档是否存在（C5 pending reference fix）。

    stage_prefix → 期望文档映射（六步）：
        req-plan → req-plan.md（②范围确认主产物，替代旧 brief/analysis/prd 前置链）
        prd      → prd.md（按需 PRD，prd-writing standalone）
        close    → close-report.md（沉淀收尾，如有）
        — 旧 7-stage 锚点 brief / analysis / impl 保留，兼容在飞旧 req —

    返回 False 表示产出文档还没生成 → CopyResult.pending_inject=True，caller
    后续写产出时应读 attachments_seen 渲染引用 section（不能假设此刻可追加）。
    """
    mapping = {
        # 六步锚点（主要落 req-plan）
        "req-plan": [req_dir / "req-plan.md"],
        "prd": [req_dir / "prd.md"],            # 按需 PRD（prd-writing standalone）
        "close": [req_dir / "close-report.md"],  # 沉淀收尾（如有）
        # 旧 7-stage 锚点（只读兼容，不作为新产物）
        "brief": [req_dir / "brief.md"],
        "analysis": [
            req_dir / "analysis.md",
            req_dir / "stage2-office-hours.md",
        ],
    }
    candidates = mapping.get(stage_prefix, [])
    return any(p.exists() for p in candidates)


def _write_meta(req_dir: Path, meta: dict) -> None:
    """原子风格写 .req-meta.json（与 _lib.state 模块 set_stage_source 同款）。"""
    meta_file = req_dir / ".req-meta.json"
    write_json_atomic(meta_file, meta)


# ============================================================================
# Public API
# ============================================================================


def copy_attachment(
    req_dir: Path,
    src: Path,
    stage_prefix: str,
    hint: Optional[str] = None,
) -> CopyResult:
    """复制源文件到 docs/inputs/attachments/ + 登记到 `.req-meta.json:attachments_seen`。

    Args:
        req_dir: req 目录绝对路径（含 `.req-meta.json`）
        src: PM 给的源路径（支持 `~` / `~user` 展开）
        stage_prefix: stage 前缀（req-plan / prd / close；旧 brief / analysis / impl
                      仍兼容）—— 决定命名前缀 + pending 判定
        hint: PM 给的"重点"描述（追溯用，可空）

    Returns:
        CopyResult(new_name, abs_path, size_mb, pending_inject)

    Raises:
        FileNotFoundError: src 不存在或不是 file
        SensitivePathError: src 命中 SENSITIVE_PATH_PATTERNS denylist
        FileSizeError: src 超 MAX_FILE_SIZE_MB hard cap
        StateReadError: `.req-meta.json` 不存在或解析失败（register_attachment 抛）

    >>> # copy_attachment(Path("/req"), Path("~/foo.pdf"), "req-plan", "重点 X")
    """
    stage_prefix = _validate_stage_prefix(stage_prefix)

    # 1. expanduser + 校验可读
    src = src.expanduser().resolve()
    if not src.exists() or not src.is_file():
        raise FileNotFoundError(f"源路径不可读：{src}")

    # 2. 敏感路径 denylist
    _check_sensitive(src)

    # 3. Size hard cap
    size_bytes = src.stat().st_size
    size_mb = size_bytes / (1024 * 1024)
    if size_mb > MAX_FILE_SIZE_MB:
        raise FileSizeError(src, size_mb)

    # 4. 命名 + 冲突 -2 后缀
    repo_root = _repo_root_from_req_dir(req_dir)
    attachments_dir = repo_root / "docs" / "inputs" / "attachments"
    attachments_dir.mkdir(parents=True, exist_ok=True)
    base_name = f"{stage_prefix}-{src.stem}"
    basename = _next_available_name(attachments_dir, base_name, src.suffix)
    new_name = f"docs/inputs/attachments/{basename}"
    dst = _attachment_path(req_dir, new_name)

    # 5. shutil.copy2 保留 mtime（C7 Python，不靠 Bash cp）
    shutil.copy2(src, dst)

    # 6. attachments_seen 登记（C3 真相源）
    register_attachment(
        req_dir,
        filename=new_name,
        src_origin=str(src),
        hint=hint,
        stage_prefix=stage_prefix,
    )

    # 7. 判断当前 stage 产出文档是否存在 → pending_inject 标记（C5）
    pending_inject = not _stage_doc_exists(req_dir, stage_prefix)

    return CopyResult(
        new_name=new_name,
        abs_path=dst,
        size_mb=size_mb,
        pending_inject=pending_inject,
    )


def register_attachment(
    req_dir: Path,
    filename: str,
    src_origin: Optional[str] = None,
    hint: Optional[str] = None,
    stage_prefix: str = "unknown",
) -> None:
    """append 到 `.req-meta.json:attachments_seen` 列表。

    Args:
        req_dir: req 目录绝对路径
        filename: repo 内相对路径（如 `docs/inputs/attachments/analysis-foo.pdf`）—— 真相源 key
        src_origin: PM 给的源绝对路径（追溯用，可空）
        hint: PM 给的"重点"描述（追溯用，可空）
        stage_prefix: 上传时 stage 前缀（追溯用）

    Raises:
        StateReadError: `.req-meta.json` 不存在或解析失败
    """
    filename = _validate_attachment_name(filename)
    stage_prefix = _validate_stage_prefix(stage_prefix)
    meta = read_req_meta(req_dir, strict=True)
    assert meta is not None  # strict=True 保证非 None
    seen: list = meta.get("attachments_seen", [])
    entry: AttachmentSeenEntry = {
        "name": filename,
        "src_origin": src_origin or "",
        "hint": hint,
        "stage_prefix": stage_prefix,
        "registered_at": _now_iso(),
    }
    seen.append(entry)
    meta["attachments_seen"] = seen
    _write_meta(req_dir, meta)


def list_attachments_seen(req_dir: Path) -> list[AttachmentSeenEntry]:
    """返回 attachments_seen 列表。

    None 语义：
    - `.req-meta.json` 不存在 → 返回 []（与旧 req 兼容）
    - meta 无 `attachments_seen` 字段 → 返回 []（旧 req 兼容；caller 后续
      append 时会创建该字段）
    """
    meta = read_req_meta(req_dir, strict=False) or {}
    return meta.get("attachments_seen", [])


def is_seen(req_dir: Path, filename: str) -> bool:
    """trigger 2 改造判定：filename 是否已在 attachments_seen 列表。

    用法（trigger 2 SKILL prose）：
        AI 扫 docs/inputs/attachments/ 发现 `<file>`：
        - is_seen(req_dir, file) == True  → 跳过（已注册）
        - is_seen(req_dir, file) == False → 主动问 PM "要不要纳入？"
          PM 答 OK 后 caller 调 register_attachment 补登记。
    """
    filename = _validate_attachment_name(filename)
    return any(a.get("name") == filename for a in list_attachments_seen(req_dir))


def remove_attachment(req_dir: Path, filename: str) -> None:
    """rm attachment 文件 + 从 attachments_seen 移除条目。

    用法：PM 说 "删 X"（删除路径）。

    Note:
        - 文件不存在 → 静默跳过（删 → 文件本来就没了 = no-op，符合预期）
        - attachments_seen 条目不存在 → 同样静默跳过

    Raises:
        StateReadError: `.req-meta.json` 不存在或解析失败
    """
    filename = _validate_attachment_name(filename)
    dst = _attachment_path(req_dir, filename)
    if dst.exists():
        dst.unlink()
    meta = read_req_meta(req_dir, strict=True)
    assert meta is not None
    seen = meta.get("attachments_seen", [])
    meta["attachments_seen"] = [a for a in seen if a.get("name") != filename]
    _write_meta(req_dir, meta)


def replace_attachment(
    req_dir: Path,
    old_filename: str,
    new_src: Path,
) -> CopyResult:
    """PM 说 "把 X 换成 Y"：rm 旧文件 + cp 新源到旧文件名（保持引用不变）。

    设计选择：
    - 保留 old_filename 不重新命名 → 引用 section / docs 内的引用行不需要改
    - stage_prefix 沿用旧条目（保持文件名一致性）
    - 同款 denylist + size cap 检查

    Args:
        req_dir: req 目录绝对路径
        old_filename: attachments_seen 中已注册的旧文件名（如 `docs/inputs/attachments/analysis-foo.pdf`）
        new_src: 新源路径（PM 给的）

    Returns: CopyResult（new_name = old_filename，pending_inject 同 stage 判定）

    Raises:
        FileNotFoundError: old_filename 不在 attachments_seen 或 new_src 不存在
        SensitivePathError / FileSizeError: 新源 denylist / size cap 触发
    """
    old_filename = _validate_attachment_name(old_filename)
    seen = list_attachments_seen(req_dir)
    old_entry = next((a for a in seen if a.get("name") == old_filename), None)
    if not old_entry:
        raise FileNotFoundError(
            f"attachments_seen 中找不到 {old_filename}（PM 说替换的旧文件名）"
        )

    # 校验新源
    new_src = new_src.expanduser().resolve()
    if not new_src.exists() or not new_src.is_file():
        raise FileNotFoundError(f"新源不可读：{new_src}")
    _check_sensitive(new_src)
    size_bytes = new_src.stat().st_size
    size_mb = size_bytes / (1024 * 1024)
    if size_mb > MAX_FILE_SIZE_MB:
        raise FileSizeError(new_src, size_mb)

    # rm 旧（同时清 attachments_seen 条目）
    remove_attachment(req_dir, old_filename)

    # cp 新（保留旧 filename）
    dst = _attachment_path(req_dir, old_filename)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(new_src, dst)

    # 重新 register（用旧 stage_prefix）
    stage_prefix = old_entry.get("stage_prefix", "unknown")
    register_attachment(
        req_dir,
        filename=old_filename,
        src_origin=str(new_src),
        hint=old_entry.get("hint"),
        stage_prefix=stage_prefix,
    )

    return CopyResult(
        new_name=old_filename,
        abs_path=dst,
        size_mb=size_mb,
        pending_inject=not _stage_doc_exists(req_dir, stage_prefix),
    )
