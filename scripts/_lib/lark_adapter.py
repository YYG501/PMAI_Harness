"""lark-cli adapter — 单一入口封装，避免散落的 lark-cli 调用重复踩相同 bug。

按 docs/执行中/gsd-借鉴-实施方案.md v3 §1 #1 落地：
- 唯一允许直接 spawn `lark-cli` 子进程的代码位置（其他位置由 lint 拦截）
- 强制封装 cwd workaround：lark-cli 对 `@<绝对路径>` 的 markdown 处理有 bug，
  必须 `cwd=markdown.parent` + `@./<filename>`；adapter API 接 `Path` 类型，
  禁止接 `@...` 字符串
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
import subprocess
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Optional


MIN_LARK_CLI_VERSION = (1, 0, 27)
MIN_IM_MARKDOWN_CLI_VERSION = (1, 0, 58)


class LarkAdapterError(Exception):
    """硬错（lark-cli 未装 / 子进程崩 / 返回非 JSON 等）。

    Attributes:
        kind: 错误类别（"missing_cli" / "subprocess" / "non_json" / "validation"）
        detail: 人话失败原因（含子进程 stderr / 输出片段）
    """

    def __init__(self, kind: str, detail: str):
        self.kind = kind
        self.detail = detail
        super().__init__(f"[{kind}] {detail}")


# ============================================================================
# 子进程封装
# ============================================================================

def _run(cmd: list[str], *, cwd: Optional[Path] = None, check: bool = False):
    """spawn lark-cli 子进程。

    None 语义：
    - lark-cli 不在 PATH → 抛 LarkAdapterError("missing_cli", ...)
    - check=False 时非 0 退出码不抛，返回 CompletedProcess 给 caller 判
    - check=True 时非 0 退出码抛 LarkAdapterError("subprocess", ...)
    """
    try:
        res = subprocess.run(
            cmd,
            cwd=str(cwd) if cwd else None,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        raise LarkAdapterError(
            "missing_cli",
            "lark-cli 未在 PATH，安装见 https://github.com/larksuite/lark-cli",
        )
    if check and res.returncode != 0:
        raise LarkAdapterError(
            "subprocess",
            f"{' '.join(cmd)} 失败 (rc={res.returncode}): "
            f"{(res.stderr or res.stdout).strip()}",
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

# markdown 开头的 YAML frontmatter：`---\n ... \n---`。
# 此正则是 frontmatter 拆分的单一定义 —— publish-to-lark 的回写逻辑也 import
# parse_frontmatter 复用，避免两份正则各自漂移。
_FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n?(.*)\Z", re.DOTALL)
_FRONTMATTER_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_.-]*):(.*)$")


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    """拆分 markdown 的 YAML frontmatter，返回 (frontmatter dict, 正文)。

    无 frontmatter → 返回 ({}, 原文本对象)。frontmatter 行按 `key: value` 浅解析：
    注释行（`#` 开头）/ 无冒号行跳过。值不做类型转换，统一当字符串。
    """
    m = _FRONTMATTER_RE.match(text)
    if not m:
        return {}, text
    fm: dict[str, str] = {}
    for line in m.group(1).splitlines():
        line = line.rstrip()
        match = _FRONTMATTER_KEY_RE.match(line)
        if not match:
            continue
        fm[match.group(1)] = match.group(2).strip()
    return fm, m.group(2)


def _atomic_replace(path: Path, text: str, *, expected_text: str) -> None:
    """同目录写临时文件后替换；目标在准备期间变化则拒绝覆盖。"""
    mode = path.stat().st_mode
    tmp = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix=f".{path.name}.frontmatter-",
        dir=path.parent,
        delete=False,
    )
    tmp_path = Path(tmp.name)
    try:
        tmp.write(text)
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp.close()
        os.chmod(tmp_path, mode)
        if path.read_text(encoding="utf-8") != expected_text:
            raise LarkAdapterError(
                "concurrent_update",
                f"frontmatter 回写前文件已变化，拒绝覆盖: {path}",
            )
        os.replace(tmp_path, path)
    finally:
        if not tmp.closed:
            tmp.close()
        tmp_path.unlink(missing_ok=True)


def _patch_frontmatter_text(
    text: str,
    updates: dict[str, object],
    removals: set[str],
) -> str:
    """只修改指定顶层标量 key，原样保留未知 YAML、注释与嵌套块。"""
    if set(updates) & removals:
        raise LarkAdapterError("validation", "frontmatter key 不能同时更新和删除")
    for key, value in updates.items():
        if not _FRONTMATTER_KEY_RE.match(f"{key}:") or "\n" in str(value):
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
    path: Path,
    fm: dict[str, object],
    body: str,
    *,
    expected_text: str | None = None,
) -> None:
    """以补丁方式写 frontmatter；保留未知 YAML，并拒绝覆盖并发正文修改。"""
    original = path.read_text(encoding="utf-8")
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
    _atomic_replace(path, patched, expected_text=original)


def replace_markdown_body(
    path: Path,
    body: str,
    *,
    expected_text: str | None = None,
) -> None:
    """原子替换正文，逐字保留已有 frontmatter。"""
    original = path.read_text(encoding="utf-8")
    if expected_text is not None and original != expected_text:
        raise LarkAdapterError(
            "concurrent_update",
            f"正文写入前文件已变化，拒绝覆盖: {path}",
        )
    match = _FRONTMATTER_RE.match(original)
    prefix = original[: match.start(2)] if match else ""
    _atomic_replace(path, prefix + body, expected_text=original)


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

def _validate_markdown_arg(path: Path) -> Path:
    """强制 markdown 参数是 Path（避免 caller 误传 `@...` 字符串绕开 cwd workaround）。"""
    if not isinstance(path, Path):
        raise LarkAdapterError(
            "validation",
            f"markdown 参数必须是 Path（不接 @... 字符串）：got {type(path).__name__}",
        )
    if not path.exists():
        raise LarkAdapterError("validation", f"markdown 文件不存在: {path}")
    return path


@contextmanager
def _markdown_body_path(markdown_path: Path):
    """yield 一个剥掉 YAML frontmatter 的 markdown 路径，供 lark-cli 发送。

    lark-cli / 飞书不会剥离 frontmatter —— 直接发原文件会把 `---\\n...\\n---`
    块当正文渲染（覆盖发布尤其必然：回写过 lark_doc_id 的文件一定带 frontmatter）。

    - 无 frontmatter → 直接 yield 原路径，不写临时文件（保持原 @./<name> 行为）。
    - 有 frontmatter → 在原文件**同目录**写临时文件（同目录是为了让正文里的相对
      路径，如内嵌图片引用，解析基准不变），yield 临时路径，退出时清理。
    """
    raw = markdown_path.read_text(encoding="utf-8")
    _, body = parse_frontmatter(raw)
    if body == raw:
        # 无 frontmatter：parse_frontmatter 原样返回，省一次写盘
        yield markdown_path
        return
    tmp = tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", suffix=".md",
        prefix=f".{markdown_path.stem}.lark-",
        dir=markdown_path.parent, delete=False,
    )
    try:
        tmp.write(body)
        tmp.close()
        yield Path(tmp.name)
    finally:
        Path(tmp.name).unlink(missing_ok=True)


def docs_create_from_markdown(
    markdown_path: Path, *, title: str, target: dict
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

    with _markdown_body_path(markdown_path) as send_path:
        cmd = [
            "lark-cli", "docs", "+create",
            "--title", title,
            "--content", f"@./{send_path.name}",
            "--doc-format", "markdown",
        ]
        if kind == "wiki":
            cmd.extend(["--wiki-node", token])
        else:
            cmd.extend(["--folder-token", token])
        res = _run(cmd, cwd=send_path.parent, check=True)
    try:
        return json.loads(res.stdout)
    except json.JSONDecodeError:
        raise LarkAdapterError(
            "non_json",
            f"lark-cli docs +create 返回非 JSON: {res.stdout[:300]}",
        )


def docs_update_from_markdown(
    markdown_path: Path,
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
    with _markdown_body_path(markdown_path) as send_path:
        cmd = [
            "lark-cli", "docs", "+update",
            "--doc", doc_id,
            "--content", f"@./{send_path.name}",
            "--doc-format", "markdown",
            "--command", mode,
        ]
        if revision_id is not None:
            cmd.extend(["--revision-id", str(revision_id)])
        res = _run(cmd, cwd=send_path.parent, check=True)
    if not res.stdout.strip():
        raise LarkAdapterError(
            "incomplete_update",
            "lark-cli docs +update 未返回可验证的成功结果",
        )
    try:
        payload = json.loads(res.stdout)
    except json.JSONDecodeError:
        raise LarkAdapterError(
            "non_json",
            f"lark-cli docs +update 返回非 JSON: {res.stdout[:300]}",
        )
    if not isinstance(payload, dict):
        raise LarkAdapterError("non_json", "lark-cli docs +update 返回的 JSON 顶层不是对象")
    if payload.get("ok") is False:
        error = payload.get("error") or payload.get("message") or payload
        raise LarkAdapterError("subprocess", f"lark-cli docs +update 返回失败 envelope: {error}")
    data = payload.get("data")
    result = data.get("result") if isinstance(data, dict) else None
    if result != "success":
        warnings = data.get("warnings") if isinstance(data, dict) else None
        raise LarkAdapterError(
            "incomplete_update",
            "lark-cli docs +update 未完整成功: "
            f"result={result or 'missing'}, warnings={warnings or []}",
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
    if payload.get("ok") is False:
        error = payload.get("error") or payload.get("message") or payload
        raise LarkAdapterError("subprocess", f"{label} 返回失败 envelope: {error}")
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
    res = _run(cmd, check=True)
    try:
        return json.loads(res.stdout)
    except json.JSONDecodeError:
        raise LarkAdapterError(
            "non_json",
            f"lark-cli api {method} {path} 返回非 JSON: {res.stdout[:200]}",
        )


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
