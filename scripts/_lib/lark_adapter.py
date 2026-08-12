"""lark-cli adapter — 单一入口封装，避免散落的 lark-cli 调用重复踩相同 bug。

按 docs/执行中/gsd-借鉴-实施方案.md v3 §1 #1 落地：
- 唯一允许直接 spawn `lark-cli` 子进程的代码位置（其他位置由 lint 拦截）
- 强制封装 markdown 输入：lark-cli 的 `@file` 只接受 cwd 下相对路径；adapter
  固定 `cwd=markdown.parent` 的目录身份，并通过 `--content -` 从受控 stdin 发送
  已读取正文，避免子进程再次按 pathname 打开可被替换的文件
- 强制封装 frontmatter 剥离：lark-cli / 飞书不识别 YAML frontmatter，直接发
  原文件会把 `---\n...\n---` 块当正文渲染。docs_* 发送前统一剥掉 frontmatter，
  只发正文（与 cwd workaround 同属"lark-cli markdown 发送怪癖"收口）
- API surface：version / auth_status / auth_check(scopes) /
  docs_create_from_markdown / docs_update_from_markdown / docs_fetch /
  drive_comments_page / drive_comment_replies_page /
  drive_comment_reply_create / drive_comment_set_solved / api_json；
  另导出 parse_frontmatter / write_frontmatter / replace_markdown_body
  （保留原 YAML 的 frontmatter 单一实现）
- 故障语义统一：可恢复用返回值 `(ok, detail)`；硬错抛 `LarkAdapterError`

调用方约定：
    >>> from _lib.lark_adapter import (
    ...     version, auth_status, auth_check,
    ...     docs_create_from_markdown, docs_update_from_markdown, api_json,
    ...     LarkAdapterError,
    ... )

doctor 子命令：`python3 -m _lib.lark_adapter doctor` 自检 version + auth_status
+ auth_check（默认 docx:document:write_only scope）。
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import subprocess
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Optional

from _lib.atomic_file import (
    AtomicFileError,
    bind_directory_fd,
    ensure_no_recovery_state_at,
    read_text_for_update,
    replace_text_if_unchanged,
    replace_text_if_unchanged_at,
)
from _lib.markdown_frontmatter import (
    FRONTMATTER_KEY_RE as _FRONTMATTER_KEY_RE,
    FRONTMATTER_RE as _FRONTMATTER_RE,
    parse_frontmatter,
)


MIN_LARK_CLI_VERSION = (1, 0, 27)
MIN_IM_MARKDOWN_CLI_VERSION = (1, 0, 58)


class LarkAdapterError(Exception):
    """硬错（lark-cli 未装 / 子进程崩 / 返回非 JSON 等）。

    Attributes:
        kind: 错误类别（"missing_cli" / "subprocess" / "non_json" /
            "incomplete_update" / "validation"）
        detail: 人话失败原因（含子进程 stderr / 输出片段）
    """

    def __init__(self, kind: str, detail: str):
        self.kind = kind
        self.detail = detail
        super().__init__(f"[{kind}] {detail}")


@dataclass(frozen=True)
class _RegularSnapshot:
    data: bytes
    mode: int
    device: int
    inode: int


def _absolute_lexical_path(path: Path) -> Path:
    if not path.is_absolute():
        path = Path.cwd() / path
    return Path(os.path.normpath(str(path)))


def _snapshot_regular_at(directory_fd: int, name: str, *, display_path: Path) -> _RegularSnapshot:
    file_fd = -1
    try:
        file_fd = os.open(
            name,
            os.O_RDONLY
            | os.O_NOFOLLOW
            | os.O_NONBLOCK
            | getattr(os, "O_CLOEXEC", 0),
            dir_fd=directory_fd,
        )
        file_stat = os.fstat(file_fd)
        if not stat.S_ISREG(file_stat.st_mode):
            raise LarkAdapterError(
                "validation",
                f"markdown 必须是普通文件，不能是 symlink、FIFO 或目录: {display_path}",
            )
        chunks: list[bytes] = []
        while True:
            chunk = os.read(file_fd, 1024 * 1024)
            if not chunk:
                break
            chunks.append(chunk)
        return _RegularSnapshot(
            data=b"".join(chunks),
            mode=stat.S_IMODE(file_stat.st_mode),
            device=file_stat.st_dev,
            inode=file_stat.st_ino,
        )
    except LarkAdapterError:
        raise
    except FileNotFoundError as exc:
        raise LarkAdapterError("validation", f"markdown 文件不存在: {display_path}") from exc
    except OSError as exc:
        raise LarkAdapterError(
            "validation",
            f"markdown 必须是无 symlink 的可读普通文件: {display_path}",
        ) from exc
    finally:
        if file_fd >= 0:
            os.close(file_fd)


def _same_snapshot(left: _RegularSnapshot, right: _RegularSnapshot) -> bool:
    return (
        left.device == right.device
        and left.inode == right.inode
        and left.mode == right.mode
        and left.data == right.data
    )


class BoundMarkdown:
    """Bind one markdown path to a canonical directory and regular-file identity."""

    def __init__(
        self,
        path: Path,
        directory_fd: int,
        *,
        directory_device: int,
        directory_inode: int,
        initial_snapshot: _RegularSnapshot,
        initial_text: str,
    ) -> None:
        self.path = path
        self._directory_fd = directory_fd
        self._directory_device = directory_device
        self._directory_inode = directory_inode
        self._initial_snapshot = initial_snapshot
        self.initial_text = initial_text
        self._closed = False

    @classmethod
    def open(cls, path: Path) -> "BoundMarkdown":
        if not isinstance(path, Path):
            raise LarkAdapterError(
                "validation",
                f"markdown 参数必须是 Path（不接 @... 字符串）：got {type(path).__name__}",
            )
        lexical_path = _absolute_lexical_path(path)
        try:
            canonical_parent = lexical_path.parent.resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise LarkAdapterError(
                "validation",
                f"markdown 父目录不可访问: {lexical_path.parent}",
            ) from exc
        bound_path = canonical_parent / lexical_path.name
        flags = (
            os.O_RDONLY
            | getattr(os, "O_DIRECTORY", 0)
            | getattr(os, "O_CLOEXEC", 0)
            | os.O_NOFOLLOW
        )
        directory_fd = -1
        try:
            directory_fd = os.open(bound_path.parent, flags)
            directory_device, directory_inode = bind_directory_fd(
                bound_path.parent,
                directory_fd,
            )
            ensure_no_recovery_state_at(
                directory_fd,
                parent=bound_path.parent,
                destination_name=bound_path.name,
            )
            first = _snapshot_regular_at(
                directory_fd,
                bound_path.name,
                display_path=lexical_path,
            )
            second = _snapshot_regular_at(
                directory_fd,
                bound_path.name,
                display_path=lexical_path,
            )
            if not _same_snapshot(first, second):
                raise LarkAdapterError(
                    "concurrent_update",
                    f"markdown 绑定期间发生变化，拒绝使用混合快照: {lexical_path}",
                )
            bind_directory_fd(bound_path.parent, directory_fd)
            try:
                initial_text = first.data.decode("utf-8")
            except UnicodeDecodeError as exc:
                raise LarkAdapterError(
                    "validation",
                    f"markdown 不是合法 UTF-8 文本: {lexical_path}",
                ) from exc
            binding = cls(
                bound_path,
                directory_fd,
                directory_device=directory_device,
                directory_inode=directory_inode,
                initial_snapshot=first,
                initial_text=initial_text,
            )
            directory_fd = -1
            return binding
        except LarkAdapterError:
            raise
        except AtomicFileError as exc:
            raise _lark_atomic_error(exc) from exc
        except OSError as exc:
            raise LarkAdapterError(
                "validation",
                f"markdown 父目录不可安全访问: {lexical_path.parent}",
            ) from exc
        finally:
            if directory_fd >= 0:
                os.close(directory_fd)

    @property
    def directory_fd(self) -> int:
        self._ensure_open()
        return self._directory_fd

    @property
    def file_device(self) -> int:
        return self._initial_snapshot.device

    @property
    def file_inode(self) -> int:
        return self._initial_snapshot.inode

    def _ensure_open(self) -> None:
        if self._closed:
            raise LarkAdapterError("validation", f"markdown 目录绑定已关闭: {self.path}")

    def verify_directory(self) -> None:
        self._ensure_open()
        try:
            device, inode = bind_directory_fd(self.path.parent, self._directory_fd)
        except AtomicFileError as exc:
            raise _lark_atomic_error(exc) from exc
        if (device, inode) != (self._directory_device, self._directory_inode):
            raise LarkAdapterError(
                "concurrent_update",
                f"markdown 父目录身份已变化，拒绝继续: {self.path.parent}",
            )

    def read_text(self, *, expected_text: str | None = None) -> str:
        self.verify_directory()
        first = _snapshot_regular_at(
            self._directory_fd,
            self.path.name,
            display_path=self.path,
        )
        second = _snapshot_regular_at(
            self._directory_fd,
            self.path.name,
            display_path=self.path,
        )
        if not _same_snapshot(first, second):
            raise LarkAdapterError(
                "concurrent_update",
                f"markdown 读取期间发生变化，拒绝使用混合快照: {self.path}",
            )
        if (first.device, first.inode) != (self.file_device, self.file_inode):
            raise LarkAdapterError(
                "concurrent_update",
                f"markdown 文件身份已变化，拒绝切换到其它文件: {self.path}",
            )
        self.verify_directory()
        try:
            text = first.data.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise LarkAdapterError(
                "validation",
                f"markdown 不是合法 UTF-8 文本: {self.path}",
            ) from exc
        if expected_text is not None and text != expected_text:
            raise LarkAdapterError(
                "concurrent_update",
                f"markdown 已变化，拒绝发送或覆盖混合版本: {self.path}",
            )
        return text

    def close(self) -> None:
        if self._closed:
            return
        os.close(self._directory_fd)
        self._closed = True


@contextmanager
def bind_markdown(path: Path) -> Iterator[BoundMarkdown]:
    binding = BoundMarkdown.open(path)
    try:
        yield binding
    finally:
        binding.close()


# ============================================================================
# 子进程封装
# ============================================================================

def _run(
    cmd: list[str],
    *,
    cwd: Optional[Path] = None,
    cwd_fd: int | None = None,
    input_data: str | bytes | None = None,
    check: bool = False,
):
    """spawn lark-cli 子进程。

    None 语义：
    - lark-cli 不在 PATH → 抛 LarkAdapterError("missing_cli", ...)
    - check=False 时非 0 退出码不抛，返回 CompletedProcess 给 caller 判
    - check=True 时非 0 退出码抛 LarkAdapterError("subprocess", ...)
    """
    inherited_fd = -1
    preexec_fn = None
    try:
        if isinstance(input_data, bytes):
            try:
                input_text = input_data.decode("utf-8")
            except UnicodeDecodeError as exc:
                raise LarkAdapterError(
                    "validation",
                    "lark-cli stdin 必须是合法 UTF-8 文本",
                ) from exc
        else:
            input_text = input_data
        run_cwd = str(cwd) if cwd else None
        pass_fds: tuple[int, ...] = ()
        if cwd_fd is not None:
            if cwd is None:
                raise LarkAdapterError("validation", "cwd_fd 必须同时提供显示目录")
            if os.name != "posix" or not callable(getattr(os, "fchdir", None)):
                raise LarkAdapterError(
                    "validation",
                    f"当前系统无法通过目录 fd 固定 lark-cli cwd: {cwd}",
                )
            inherited_fd = os.dup(cwd_fd)
            inherited_stat = os.fstat(inherited_fd)
            if not stat.S_ISDIR(inherited_stat.st_mode):
                raise LarkAdapterError(
                    "validation",
                    f"lark-cli cwd_fd 不是目录: {cwd}",
                )

            # subprocess 的 pathname cwd 不能可靠表示 macOS 上已绑定的目录 fd。
            # 在单线程 CLI 子进程 exec 前直接 fchdir，避免重新解析可被改向的路径。
            def enter_bound_directory() -> None:
                os.fchdir(inherited_fd)

            run_cwd = None
            pass_fds = (inherited_fd,)
            preexec_fn = enter_bound_directory
        res = subprocess.run(
            cmd,
            cwd=run_cwd,
            pass_fds=pass_fds,
            preexec_fn=preexec_fn,
            input=input_text,
            capture_output=True,
            text=True,
        )
    except LarkAdapterError:
        raise
    except FileNotFoundError as exc:
        if cwd_fd is not None and exc.filename not in {None, cmd[0]}:
            raise LarkAdapterError(
                "validation",
                f"已绑定的 lark-cli cwd 不可访问: {cwd}",
            ) from exc
        raise LarkAdapterError(
            "missing_cli",
            "lark-cli 未在 PATH，安装见 https://github.com/larksuite/lark-cli",
        ) from exc
    except subprocess.SubprocessError as exc:
        raise LarkAdapterError(
            "validation",
            f"无法进入已绑定目录并启动 lark-cli: {cwd or Path.cwd()}",
        ) from exc
    except OSError as exc:
        raise LarkAdapterError(
            "validation",
            f"无法在已绑定目录中启动 lark-cli: {cwd or Path.cwd()}",
        ) from exc
    finally:
        if inherited_fd >= 0:
            os.close(inherited_fd)
    if check and res.returncode != 0:
        failure_detail = (res.stderr or res.stdout).strip()
        if input_text is not None:
            failure_detail = "子进程输出已隐藏（命令使用受控 stdin，避免正文泄漏）"
        raise LarkAdapterError(
            "subprocess",
            f"{' '.join(cmd)} 失败 (rc={res.returncode}): "
            f"{failure_detail}",
        )
    return res


def _parse_version(s: str) -> Optional[tuple[int, int, int]]:
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", s)
    if not m:
        return None
    return tuple(int(x) for x in m.groups())  # type: ignore[return-value]


# ============================================================================
# Frontmatter
# ============================================================================

_FRONTMATTER_KEY_NAME_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_.-]*")
_LINE_BREAK_RE = re.compile(r"[\r\n\v\f\x1c-\x1e\x85\u2028\u2029]")


def _atomic_replace(
    path: Path | BoundMarkdown,
    text: str,
    *,
    expected_text: str,
    require_canonical_path: bool = False,
) -> None:
    """通过固定目录 fd 和原子 no-replace CAS 替换目标。"""
    try:
        if isinstance(path, BoundMarkdown):
            path.verify_directory()
            replace_text_if_unchanged_at(
                path.directory_fd,
                parent=path.path.parent,
                destination_name=path.path.name,
                text=text,
                expected_text=expected_text,
                expected_device=path.file_device,
                expected_inode=path.file_inode,
            )
            path.verify_directory()
            return

        target = _absolute_lexical_path(path) if require_canonical_path else path
        replace_text_if_unchanged(
            target,
            text,
            expected_text=expected_text,
            require_canonical_path=require_canonical_path,
        )
    except AtomicFileError as exc:
        raise _lark_atomic_error(exc) from exc


def _lark_atomic_error(exc: AtomicFileError) -> LarkAdapterError:
    kind = (
        "concurrent_update"
        if exc.kind in {"concurrent_update", "recovery_required"}
        else "validation"
    )
    return LarkAdapterError(kind, str(exc))


def _read_atomic_text(
    path: Path | BoundMarkdown,
    *,
    require_canonical_path: bool,
) -> str:
    if isinstance(path, BoundMarkdown):
        return path.read_text()
    target = _absolute_lexical_path(path) if require_canonical_path else path
    try:
        return read_text_for_update(
            target,
            require_canonical_path=require_canonical_path,
        )
    except AtomicFileError as exc:
        raise _lark_atomic_error(exc) from exc


def _patch_frontmatter_text(
    text: str,
    updates: dict[str, object],
    removals: set[str],
) -> str:
    """只修改指定顶层标量 key，原样保留未知 YAML、注释与嵌套块。"""
    if set(updates) & removals:
        raise LarkAdapterError("validation", "frontmatter key 不能同时更新和删除")
    for key, value in updates.items():
        if (
            _FRONTMATTER_KEY_NAME_RE.fullmatch(str(key)) is None
            or _LINE_BREAK_RE.search(str(value)) is not None
        ):
            raise LarkAdapterError("validation", f"不安全的 frontmatter 标量: {key}")

    match = _FRONTMATTER_RE.match(text)
    if match:
        lines = match.group(1).splitlines()
        body = match.group(2)
    else:
        lines = []
        body = text

    output: list[str] = []
    seen: set[str] = set()
    for line in lines:
        key_match = _FRONTMATTER_KEY_RE.match(line)
        key = key_match.group(1) if key_match else None
        if key in removals:
            seen.add(key)
            continue
        if key in updates:
            if key not in seen:
                output.append(f"{key}: {updates[key]}")
                seen.add(key)
            continue
        output.append(line)
    for key, value in updates.items():
        if key not in seen:
            output.append(f"{key}: {value}")

    frontmatter = "\n".join(output)
    return f"---\n{frontmatter}\n---\n" + body


def write_frontmatter(
    path: Path | BoundMarkdown,
    fm: dict[str, object],
    body: str,
    *,
    expected_text: str | None = None,
    require_canonical_path: bool = False,
) -> None:
    """以补丁方式写 frontmatter；保留未知 YAML，并拒绝覆盖并发正文修改。"""
    original = _read_atomic_text(
        path,
        require_canonical_path=require_canonical_path,
    )
    if expected_text is not None and original != expected_text:
        raise LarkAdapterError(
            "concurrent_update",
            f"frontmatter 回写前文件已变化，拒绝覆盖: {path}",
        )
    current_fm, current_body = parse_frontmatter(original)
    if current_body != body:
        raise LarkAdapterError(
            "concurrent_update",
            f"frontmatter 回写使用了过期正文，拒绝覆盖: {path}",
        )
    updates = {
        key: value
        for key, value in fm.items()
        if current_fm.get(key) != str(value)
    }
    removals = set(current_fm) - set(fm)
    if not updates and not removals:
        return
    patched = _patch_frontmatter_text(original, updates, removals)
    _atomic_replace(
        path,
        patched,
        expected_text=original,
        require_canonical_path=require_canonical_path,
    )


def replace_markdown_body(
    path: Path | BoundMarkdown,
    body: str,
    *,
    expected_text: str | None = None,
    require_canonical_path: bool = False,
) -> None:
    """原子替换正文，逐字保留已有 frontmatter。"""
    original = _read_atomic_text(
        path,
        require_canonical_path=require_canonical_path,
    )
    if expected_text is not None and original != expected_text:
        raise LarkAdapterError(
            "concurrent_update",
            f"正文写入前文件已变化，拒绝覆盖: {path}",
        )
    match = _FRONTMATTER_RE.match(original)
    prefix = original[: match.start(2)] if match else ""
    _atomic_replace(
        path,
        prefix + body,
        expected_text=original,
        require_canonical_path=require_canonical_path,
    )


def markdown_body_hash(body: str) -> str:
    """计算忽略换行风格和首尾空行的稳定正文 SHA-256。"""
    canonical = body.replace("\r\n", "\n").replace("\r", "\n").strip("\n") + "\n"
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


# ============================================================================
# Public API: 自检
# ============================================================================

def version() -> Optional[tuple[int, int, int]]:
    """`lark-cli --version` → (major, minor, patch)。

    None 语义：
    - 进程跑了但输出里没有 N.N.N → 返回 None（caller 自己判要不要 hard fail）
    - lark-cli 不在 PATH → 抛 LarkAdapterError("missing_cli")
    """
    res = _run(["lark-cli", "--version"], check=False)
    combined = (res.stdout or "") + (res.stderr or "")
    return _parse_version(combined)


def auth_status() -> tuple[bool, str]:
    """`lark-cli auth status` → (ok, detail)。

    ok=False 时 detail 含 stderr/stdout 内容，便于上层拼"详情: ..."。
    """
    res = _run(["lark-cli", "auth", "status"], check=False)
    if res.returncode == 0:
        return True, (res.stdout or "").strip()
    return False, (res.stderr or res.stdout or "").strip()


def auth_check(scopes: list[str]) -> tuple[bool, str]:
    """`lark-cli auth check --scope "<space-joined scopes>"` → (ok, detail)。

    scope 名称必须是 lark-cli ≥1.0.27 的精确子 scope（如
    `docx:document:write_only`），不是 v1 的粗 scope。
    """
    if not scopes:
        raise LarkAdapterError("validation", "auth_check 需要至少 1 个 scope")
    res = _run(
        ["lark-cli", "auth", "check", "--scope", " ".join(scopes)],
        check=False,
    )
    if res.returncode == 0:
        return True, (res.stdout or "").strip()
    return False, (res.stderr or res.stdout or "").strip()


# ============================================================================
# Public API: 文档
# ============================================================================

def _validate_markdown_arg(path: Path | BoundMarkdown) -> None:
    """强制 markdown 参数是 Path / BoundMarkdown，禁止 caller 传 `@...` 字符串。"""
    if not isinstance(path, (Path, BoundMarkdown)):
        raise LarkAdapterError(
            "validation",
            "markdown 参数必须是 Path 或 BoundMarkdown（不接 @... 字符串）："
            f"got {type(path).__name__}",
        )


@contextmanager
def _markdown_binding(
    markdown: Path | BoundMarkdown,
) -> Iterator[BoundMarkdown]:
    _validate_markdown_arg(markdown)
    if isinstance(markdown, BoundMarkdown):
        markdown.verify_directory()
        yield markdown
        return
    with bind_markdown(markdown) as binding:
        yield binding


def _markdown_body(markdown: BoundMarkdown) -> str:
    """读取同一绑定文件的稳定正文，剥掉 lark-cli 不识别的 frontmatter。"""
    raw = markdown.read_text(expected_text=markdown.initial_text)
    _, body = parse_frontmatter(raw)
    return body


def _run_markdown_command(
    binding: BoundMarkdown,
    cmd: list[str],
    *,
    body: str,
    check: bool = True,
):
    """从内存快照发送正文；cmd/异常只含 `--content -`，不泄漏正文。"""
    binding.verify_directory()
    res = _run(
        cmd,
        cwd=binding.path.parent,
        cwd_fd=binding.directory_fd,
        input_data=body,
        check=check,
    )
    return res


def _markdown_output_error(kind: str, label: str) -> LarkAdapterError:
    """Do not surface stdout from commands that received document content on stdin."""
    return LarkAdapterError(
        kind,
        f"{label}；子进程输出已隐藏（命令使用受控 stdin，避免正文泄漏）",
    )


def _is_failure_envelope(payload: dict) -> bool:
    """Recognise the failure fields emitted by lark-cli and raw Lark APIs."""
    return (
        payload.get("ok") is False
        or payload.get("success") is False
        or payload.get("code") not in (None, 0)
    )


def _failure_envelope_detail(payload: dict) -> str:
    for key in ("error", "message", "msg"):
        value = payload.get(key)
        if isinstance(value, (str, int, float, bool)) and str(value).strip():
            return str(value).strip()
    markers: list[str] = []
    if payload.get("ok") is False:
        markers.append("ok=false")
    if payload.get("success") is False:
        markers.append("success=false")
    if payload.get("code") not in (None, 0):
        markers.append(f"code={payload.get('code')}")
    return ", ".join(markers) or "未提供错误详情"


def docs_create_from_markdown(
    markdown_path: Path | BoundMarkdown, *, title: str, target: dict
) -> dict:
    """`lark-cli docs +create` → 解析后的 JSON dict（adapter 内部强制 cwd workaround）。

    target schema：
    - {"kind": "wiki",   "token": "<wiki-node-token>"}
    - {"kind": "folder", "token": "<folder-token>"}

    返回 lark-cli 原 JSON（caller 自己从 data.doc_id / data.document.document_id
    等不同 schema 字段里挑）。

    None 语义：
    - 子进程失败 → 抛 LarkAdapterError("subprocess")
    - 返回非 JSON → 抛 LarkAdapterError("non_json")
    - 不合法 target.kind → 抛 LarkAdapterError("validation")
    """
    _validate_markdown_arg(markdown_path)
    kind = target.get("kind")
    token = target.get("token")
    if not token or kind not in ("wiki", "folder"):
        raise LarkAdapterError(
            "validation", f"target 不合法: {target!r}（kind 应为 wiki/folder）"
        )

    with _markdown_binding(markdown_path) as binding:
        body = _markdown_body(binding)
        cmd = [
            "lark-cli", "docs", "+create",
            "--title", title,
            "--content", "-",
            "--doc-format", "markdown",
        ]
        if kind == "wiki":
            cmd.extend(["--wiki-node", token])
        else:
            cmd.extend(["--folder-token", token])
        res = _run_markdown_command(binding, cmd, body=body)
    try:
        payload = json.loads(res.stdout)
    except json.JSONDecodeError:
        raise _markdown_output_error("non_json", "lark-cli docs +create 返回非 JSON")
    if not isinstance(payload, dict):
        raise _markdown_output_error(
            "non_json",
            "lark-cli docs +create 返回的 JSON 顶层不是对象",
        )
    if _is_failure_envelope(payload):
        raise _markdown_output_error(
            "subprocess",
            "lark-cli docs +create 返回失败 envelope",
        )
    return payload


def docs_update_from_markdown(
    markdown_path: Path | BoundMarkdown,
    *,
    doc_id: str,
    mode: str = "overwrite",
    revision_id: Optional[int] = None,
) -> dict:
    """`lark-cli docs +update` 覆盖模式（adapter 内部强制 cwd workaround）。

    只有 `data.result=success` 视为完整成功；无返回、partial_success 或 failed
    都抛错，避免调用方建立无法证明的发布基线。
    """
    _validate_markdown_arg(markdown_path)
    if not doc_id:
        raise LarkAdapterError("validation", "doc_id 不能为空")
    with _markdown_binding(markdown_path) as binding:
        body = _markdown_body(binding)
        cmd = [
            "lark-cli", "docs", "+update",
            "--doc", doc_id,
            "--content", "-",
            "--doc-format", "markdown",
            "--command", mode,
        ]
        if revision_id is not None:
            cmd.extend(["--revision-id", str(revision_id)])
        res = _run_markdown_command(binding, cmd, body=body, check=False)
    if res.returncode != 0:
        raise _markdown_output_error(
            "incomplete_update",
            f"lark-cli docs +update 退出码非零 (rc={res.returncode})",
        )
    if not res.stdout.strip():
        raise LarkAdapterError(
            "incomplete_update",
            "lark-cli docs +update 未返回可验证的成功结果",
        )
    try:
        payload = json.loads(res.stdout)
    except json.JSONDecodeError:
        raise _markdown_output_error(
            "incomplete_update",
            "lark-cli docs +update 返回非 JSON",
        )
    if not isinstance(payload, dict):
        raise _markdown_output_error(
            "incomplete_update",
            "lark-cli docs +update 返回的 JSON 顶层不是对象",
        )
    if _is_failure_envelope(payload):
        raise _markdown_output_error(
            "incomplete_update",
            "lark-cli docs +update 返回失败 envelope",
        )
    data = payload.get("data")
    result = data.get("result") if isinstance(data, dict) else None
    if result != "success":
        raise _markdown_output_error(
            "incomplete_update",
            "lark-cli docs +update 未完整成功",
        )
    return payload


def _json_command(cmd: list[str], *, label: str) -> dict:
    """运行一个返回 JSON 的 lark-cli 命令并统一错误语义。"""
    res = _run(cmd, check=True)
    try:
        payload = json.loads(res.stdout)
    except json.JSONDecodeError:
        raise LarkAdapterError(
            "non_json",
            f"{label} 返回非 JSON: {res.stdout[:300]}",
        )
    if not isinstance(payload, dict):
        raise LarkAdapterError("non_json", f"{label} 返回的 JSON 顶层不是对象")
    if _is_failure_envelope(payload):
        raise LarkAdapterError(
            "subprocess",
            f"{label} 返回失败 envelope: {_failure_envelope_detail(payload)}",
        )
    return payload


def docs_fetch(
    doc: str,
    *,
    doc_format: str = "markdown",
    detail: str = "simple",
    revision_id: Optional[int] = None,
    identity: str = "user",
) -> dict:
    """读取飞书文档正文和 revision，返回 lark-cli 原始 JSON。"""
    if not doc:
        raise LarkAdapterError("validation", "docs_fetch 的 doc 不能为空")
    if doc_format not in ("xml", "markdown", "im-markdown"):
        raise LarkAdapterError("validation", f"不支持的 doc_format: {doc_format}")
    if detail not in ("simple", "with-ids", "full"):
        raise LarkAdapterError("validation", f"不支持的 detail: {detail}")
    if identity not in ("user", "bot"):
        raise LarkAdapterError("validation", f"不支持的 identity: {identity}")
    if doc_format == "im-markdown":
        current = version()
        if current is None or current < MIN_IM_MARKDOWN_CLI_VERSION:
            minimum = ".".join(str(value) for value in MIN_IM_MARKDOWN_CLI_VERSION)
            actual = "无法解析" if current is None else ".".join(str(value) for value in current)
            raise LarkAdapterError(
                "validation",
                f"docs_fetch(im-markdown) 需要 lark-cli >= {minimum}，当前为 {actual}",
            )

    cmd = [
        "lark-cli", "docs", "+fetch",
        "--doc", doc,
        "--doc-format", doc_format,
        "--detail", detail,
        "--as", identity,
        "--format", "json",
    ]
    if revision_id is not None:
        cmd.extend(["--revision-id", str(revision_id)])
    return _json_command(cmd, label="lark-cli docs +fetch")


def drive_comments_page(
    file_token: str,
    *,
    page_token: Optional[str] = None,
    is_solved: bool = False,
    need_relation: bool = True,
    identity: str = "user",
) -> dict:
    """按明确的 solved 状态读取一页 Docx 评论，避免依赖 CLI 默认值。"""
    if not file_token:
        raise LarkAdapterError("validation", "评论 file_token 不能为空")
    params: dict[str, object] = {
        "file_token": file_token,
        "file_type": "docx",
        "page_size": 100,
        "user_id_type": "open_id",
        "is_solved": is_solved,
    }
    if need_relation:
        params["need_relation"] = True
    if page_token:
        params["page_token"] = page_token
    cmd = [
        "lark-cli", "drive", "file.comments", "list",
        "--params", json.dumps(params, ensure_ascii=False, separators=(",", ":")),
        "--as", identity,
        "--format", "json",
    ]
    return _json_command(cmd, label="lark-cli drive file.comments list")


def drive_comment_replies_page(
    file_token: str,
    comment_id: str,
    *,
    page_token: Optional[str] = None,
    identity: str = "user",
) -> dict:
    """读取一页评论回复，用于补齐 comment.has_more 的截断内容。"""
    if not file_token or not comment_id:
        raise LarkAdapterError("validation", "回复查询需要 file_token 和 comment_id")
    params: dict[str, object] = {
        "file_token": file_token,
        "file_type": "docx",
        "comment_id": comment_id,
        "page_size": 100,
        "user_id_type": "open_id",
    }
    if page_token:
        params["page_token"] = page_token
    cmd = [
        "lark-cli", "drive", "file.comment.replys", "list",
        "--params", json.dumps(params, ensure_ascii=False, separators=(",", ":")),
        "--as", identity,
        "--format", "json",
    ]
    return _json_command(cmd, label="lark-cli drive file.comment.replys list")


def drive_comment_reply_create(
    file_token: str,
    comment_id: str,
    text: str,
    *,
    identity: str = "user",
) -> dict:
    """为一条 Docx 评论创建文本回复，并返回 lark-cli 原始 JSON。"""
    if not file_token or not comment_id:
        raise LarkAdapterError("validation", "回复创建需要 file_token 和 comment_id")
    if not isinstance(text, str) or not text.strip():
        raise LarkAdapterError("validation", "回复正文不能为空")
    if identity not in ("user", "bot"):
        raise LarkAdapterError("validation", f"不支持的 identity: {identity}")
    escaped_text = text.replace("<", "&lt;").replace(">", "&gt;")
    params = {
        "file_token": file_token,
        "file_type": "docx",
        "comment_id": comment_id,
        "user_id_type": "open_id",
    }
    data = {
        "content": {
            "elements": [
                {
                    "type": "text_run",
                    "text_run": {"text": escaped_text},
                }
            ]
        }
    }
    cmd = [
        "lark-cli", "drive", "file.comment.replys", "create",
        "--params", json.dumps(params, ensure_ascii=False, separators=(",", ":")),
        "--data", json.dumps(data, ensure_ascii=False, separators=(",", ":")),
        "--as", identity,
        "--format", "json",
    ]
    return _json_command(cmd, label="lark-cli drive file.comment.replys create")


def drive_comment_set_solved(
    file_token: str,
    comment_id: str,
    *,
    is_solved: bool,
    identity: str = "user",
) -> dict:
    """切换单条 Docx 评论的解决状态，并返回 lark-cli 原始 JSON。"""
    if not file_token or not comment_id:
        raise LarkAdapterError("validation", "评论状态写入需要 file_token 和 comment_id")
    if identity not in ("user", "bot"):
        raise LarkAdapterError("validation", f"不支持的 identity: {identity}")
    params = {
        "comment_id": comment_id,
        "file_token": file_token,
        "file_type": "docx",
    }
    cmd = [
        "lark-cli", "drive", "file.comments", "patch",
        "--params", json.dumps(params, ensure_ascii=False, separators=(",", ":")),
        "--data", json.dumps(
            {"is_solved": is_solved}, ensure_ascii=False, separators=(",", ":")
        ),
        "--as", identity,
        "--format", "json",
    ]
    return _json_command(cmd, label="lark-cli drive file.comments patch")


def api_json(
    method: str, path: str,
    *,
    params: Optional[dict] = None,
    data: Optional[dict] = None,
) -> dict:
    """`lark-cli api <METHOD> <PATH> [--params ...] [--data ...]` → 解析后的 JSON dict。

    None 语义：
    - 子进程失败 → 抛 LarkAdapterError("subprocess")
    - 返回非 JSON → 抛 LarkAdapterError("non_json")
    """
    cmd = ["lark-cli", "api", method, path]
    if params:
        cmd.extend(["--params", json.dumps(params)])
    if data:
        cmd.extend(["--data", json.dumps(data)])
    return _json_command(cmd, label=f"lark-cli api {method} {path}")


# ============================================================================
# CLI entry
# ============================================================================


def _print_doctor() -> int:
    """`python3 -m _lib.lark_adapter doctor`"""
    print("lark-adapter doctor")
    print("-" * 40)

    # 1. version
    try:
        ver = version()
    except LarkAdapterError as e:
        print(f"version       : FAIL  {e}")
        print("\n建议：安装 lark-cli。")
        return 1
    if ver is None:
        print("version       : FAIL  (无法解析输出)")
        return 1
    ver_s = ".".join(str(x) for x in ver)
    min_s = ".".join(str(x) for x in MIN_LARK_CLI_VERSION)
    if ver < MIN_LARK_CLI_VERSION:
        print(f"version       : FAIL  {ver_s} < 最低要求 {min_s}")
        print(f"\n建议：升级 lark-cli ≥ {min_s}。")
        return 1
    print(f"version       : OK    {ver_s} (≥ {min_s})")

    # 2. auth_status
    ok, detail = auth_status()
    if ok:
        print("auth_status   : OK")
    else:
        print(f"auth_status   : FAIL  {detail}")
        print("\n建议：运行 `lark-cli auth login`（详见 lark-shared skill）。")
        return 1

    # 3. auth_check (default scope)
    scopes = ["docx:document:write_only"]
    ok, detail = auth_check(scopes)
    if ok:
        print(f"auth_check    : OK    scopes={scopes}")
    else:
        print(f"auth_check    : WARN  缺少 scope (可能是 token metadata 误报): {detail}")
        print(f"\n建议：如真缺权限跑 `lark-cli auth login --scope \"{' '.join(scopes)}\"`。")
        # warn 不算硬失败，doctor 仍返回 0

    return 0


def _cli():
    import sys
    if len(sys.argv) < 2:
        print(
            "usage: python3 -m _lib.lark_adapter <fn> [args...]\n"
            "  fns: doctor / version / auth_status",
            file=sys.stderr,
        )
        sys.exit(2)
    fn = sys.argv[1]
    if fn == "doctor":
        sys.exit(_print_doctor())
    if fn == "version":
        try:
            ver = version()
        except LarkAdapterError as e:
            print(str(e), file=sys.stderr)
            sys.exit(1)
        if ver is None:
            sys.exit(1)
        print(".".join(str(x) for x in ver))
        return
    if fn == "auth_status":
        ok, detail = auth_status()
        print(detail)
        sys.exit(0 if ok else 1)
    print(f"unknown fn: {fn}", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    _cli()
