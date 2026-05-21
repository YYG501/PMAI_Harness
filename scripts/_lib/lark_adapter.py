"""lark-cli adapter — 单一入口封装，避免散落的 lark-cli 调用重复踩相同 bug。

按 docs/执行中/gsd-借鉴-实施方案.md v3 §1 #1 落地：
- 唯一允许直接 spawn `lark-cli` 子进程的代码位置（其他位置由 lint 拦截）
- 强制封装 cwd workaround：lark-cli 对 `@<绝对路径>` 的 markdown 处理有 bug，
  必须 `cwd=markdown.parent` + `@./<filename>`；adapter API 接 `Path` 类型，
  禁止接 `@...` 字符串
- 强制封装 frontmatter 剥离：lark-cli / 飞书不识别 YAML frontmatter，直接发
  原文件会把 `---\n...\n---` 块当正文渲染。docs_* 发送前统一剥掉 frontmatter，
  只发正文（与 cwd workaround 同属"lark-cli markdown 发送怪癖"收口）
- API surface ~6 核心：version / auth_status / auth_check(scopes) /
  docs_create_from_markdown / docs_update_from_markdown / api_json；
  另导出 parse_frontmatter（frontmatter 拆分单一实现，publish-to-lark 复用）
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

import json
import re
import subprocess
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Optional


MIN_LARK_CLI_VERSION = (1, 0, 27)


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
        if not line or line.lstrip().startswith("#") or ":" not in line:
            continue
        k, v = line.split(":", 1)
        fm[k.strip()] = v.strip()
    return fm, m.group(2)


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
            "--markdown", f"@./{send_path.name}",
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
    markdown_path: Path, *, doc_id: str, mode: str = "overwrite"
) -> None:
    """`lark-cli docs +update` 覆盖模式（adapter 内部强制 cwd workaround）。

    None 语义：
    - 子进程失败 → 抛 LarkAdapterError("subprocess")
    - 成功 → 返回 None（lark-cli 该子命令 stdout 不带稳定 JSON）
    """
    _validate_markdown_arg(markdown_path)
    if not doc_id:
        raise LarkAdapterError("validation", "doc_id 不能为空")
    with _markdown_body_path(markdown_path) as send_path:
        cmd = [
            "lark-cli", "docs", "+update",
            "--doc", doc_id,
            "--markdown", f"@./{send_path.name}",
            "--mode", mode,
        ]
        _run(cmd, cwd=send_path.parent, check=True)


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
