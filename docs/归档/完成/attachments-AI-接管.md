# D-iii：attachments AI 接管（Model 2 — helper-based）(v2)

> **状态**：草稿 v2（Codex outside voice Round 1 反转 v1 prose-only → helper-based）
> **日期**：2026-05-25
> **作者**：PM + AI + Codex (outside voice)
> **历史文件名**：`attachments-体验优化.md` → 落地后改名为 `attachments-AI-接管.md`
> **版本史**：v0 stub → v1 prose-only（10 Claude finding 全 ACCEPT 后 Codex 命中 11 critical/high finding 集体指向根因 = 应该 helper 化）→ **v2 helper-based**（当前；同 D-i v4 Round 3 整体反转剧情）

---

## §0 原始痛点（v1 已锁，**不可反向修改**）

> §0.1 / §0.2 / §0.3 / §0.4 全部沿用 v1（PM 已 §0 共写）。v2 没改 §0，只改 §1+ 方案主体。

### §0.1 痛点（1-3 句）

PM 完全不知道现仓 attachments 机制存在 + 不知道路径 + 不知道如何上传。两个现 trigger（PM 主动提 / AI 写产出前扫）都是 **reactive**，永远 silent 直到 PM "知道该说"，但 PM 没在任何 chat 里看到过提示就永远学不到机制存在。

根本性：现状机制选 "PM 管 `attachments/` 目录"（工程视角，要求 PM 学路径约定 + 文件名前缀），但 PM 视角应是 "我跟你说我有什么材料"，AI 后台搞定 cp + 命名 + 引用。**PM 视角 vs 工程视角错配**（与 D-i v4 "office-hours snapshot" 同结构决策）。

### §0.2 触发场景

| # | 场景描述 | 实证证据 |
|---|---|---|
| 1 | PM 起 req → 走 worktree → 跑 stage-gate → 全程没看到任何 chat 提到 attachments，永远不知道这个机制存在 | **EVIDENCE**：PM 表述（本会话）"目前就是不知道如何把附件上传，上传到什么位置，以及是否后续的阶段，能够读取到这些附件" |
| 2 | 现 trigger 1 要 PM 主动说 "我有附件" 才告诉路径 → PM 不知道该说就永远不知道路径 | **EVIDENCE**：`docs/归档/完成/attachments-机制.md` §三：trigger 1 = "PM 主动提"，AI 仅在 PM 提了之后才告诉路径 |
| 3 | 现 trigger 2 silent 扫描，空目录永远不输出 → PM 没体感任何反馈 | **EVIDENCE**：同上 §三 trigger 2 = "AI 写产出时主动扫"，空目录跳过、不打扰 PM |
| 4 | PM 视角应是"跟 AI 描述材料"（同 D-i v4 office-hours 是 "PM 跟 AI 讨论需求"），不该是"管理 worktree 子目录的文件 system 操作" | **EVIDENCE**：PM 拍方向 A = mental model 切 Model 2（AI 接管，PM 不感知 attachments/ 目录） |

### §0.3 根因

**两层根因**：

1. **机制层根因**：attachments 机制选 PM 自管目录（工程视角），要求 PM 学路径约定 + 文件名前缀。**PM 单人生产力工具不该让用户学 filesystem 约定**。
2. **discoverability 根因**：两个 trigger 都 reactive，**没有 proactive announcement**。PM 自始至终在任何 chat 里看不到 attachments 路径，就永远学不到机制存在。

### §0.4 不解决什么

| # | 衍生 / 假设场景 | 为什么不解决 |
|---|---|---|
| 1 | attachments 内文件版本管理 | git 自然 diff 即可（沿用 `attachments-机制.md` §九） |
| 2 | attachments 大小限制 / git LFS 接入 | hard cap 50MB（**v2 §1.4 加入**，C10 命中）；超大 PM 自外部引用 |
| 3 | 跨 req 共享材料（多 req 用一份）| PM 自己复制到各 req 的 attachments/（同 §九 接受重复） |
| 4 | AI 跨 req 检索历史 attachments | 用 `grep -r` 即可，不进框架（同 §九） |
| 5 | 自动 OCR / binary 解析 | gstack 工具栈 / Read 工具原生不在范围（同 §九） |
| 6 | attachments 子目录结构 | 文件名前缀 + 引用 section 足够定位（同 §九） |
| 7 | 砍掉现 trigger 2 | **保留作 fallback**（E5 决议）|
| 8 | hardcode 触发词 | PM 拍：AI first-principle 识别 |
| 9 | "问 PM 是否覆盖" 在每次命名冲突 | 自动追加 `-2` / `-3` 后缀 |
| 10 | "PM 提交意图后 AI 反问是否上传"（避免误识别）| trade：破"一次回话搞定"体感 |
| 11 | **prose-only 5 SKILL 各 inline 路径**（v1 方向）| **Codex Round 1 命中**：file system 操作 / state 管理 / cross-design 协调靠模型记忆漂；改 helper-based（v2 §1.4） |
| 12 | **Bash cp 方案** | C7 命中：`~` 展开 / 空格 / `-2` 拼接 / 目录创建脆；helper 用 Python `shutil.copy2` + `Path.expanduser` |
| 13 | **引用 section 作为状态真相源** | C3 / C8 命中：真相源 = `.req-meta.json:attachments_seen`；引用 section 仅 PM 可见展示 |
| 14 | **size pre-commit warn 作 fail-open** | C10 命中：hard cap `MAX_FILE_SIZE_MB = 50` 在 helper 里 raise，不依赖 pre-commit |

---

## §1 方案概述（v2 helper-based）

### §1.1 一句话

PM chat "我有 X 在路径 Y" → AI 调 `_lib.attachments.copy_attachment(req_dir, src, stage_prefix, hint)` helper → helper 后台 `shutil.copy2 + denylist + size cap + 命名 + .req-meta.json:attachments_seen append` + chat 一行确认。**PM 完全不感知 `attachments/` 目录**（IDE 里仍能看到，但心智操作里不去碰）+ **helper 是状态真相源**（与 D-i v4 `_lib.state.{get,set}_stage_source` 同款 helper-based 架构）。

### §1.2 PM 体感 walkthrough

```
[Stage 2 req-stage-gate 跑到一半，AI 在需求讨论]

PM: 我有份用户访谈，在 ~/Downloads/interview-2026-05.pdf，重点是第 3 页痛点列表。

AI: 已归档（attachments/analysis-interview-2026-05.pdf），重点已记。继续。
```

后台 PM 不感知：
1. AI 调 `_lib.attachments.copy_attachment(req_dir, Path("~/Downloads/interview-2026-05.pdf"), stage_prefix="analysis", hint="第 3 页痛点列表")`
2. helper 校验源可读 / 不在 denylist / 不超 size cap → `shutil.copy2` 到 `$ACTIVE_REQ_DIR/attachments/analysis-interview-2026-05.pdf`
3. helper `register_attachment` append 到 `.req-meta.json:attachments_seen`
4. caller SKILL（req-analysis / stage-gate）写 stage 2 真相源时 → 末尾 `## 📎 参考材料` section 渲染一行
5. chat 一行确认

**后续 stage 自动继承**（input-flow.md 各 stage "按需读 attachments/" 规则保持不变）。

### §1.3 AI 触发识别（first-principle，无 hardcode）

PM chat 同时含两元素 → AI 自动识别为 "上传附件" 意图：

1. **一个或多个绝对路径**：macOS `/Users/...` 或 `~/...`
2. **关联描述**：典型 "我有份 X" / "看这个 [路径]" / "重点是" / "材料在 [路径]"

判断由 LLM prose 做（不用关键词列表）。AI 不确信 → chat 反问 "是否归档？"。

**禁用例外**（**v2 新加**）：

- **req-stage-gate Stage 1→2 B 分支 office-hours 选源期间** → trigger 0 **禁用**（C4 cross-design 冲突）：B 分支 "我自己指定路径" 输入的是 office-hours 设计稿源材料，**不**归档为 attachment，走 `set_stage_source(req_dir, 2, 'stage2-office-hours.md', tool='office-hours', origin=<原绝对路径>)` 路径（已落 D-i v4）
- **standalone `/prd-writing` 模式** → trigger 0 **不启**（D4 决议，PM 拍）

### §1.4 helper 设计（v2 核心）

新建 `scripts/_lib/attachments.py`：

```python
"""Attachments helper — D-iii v2 Model 2 AI 接管层。

设计源：docs/设计/attachments-体验优化.md (D-iii v2)。
同 D-i v4 _lib.state.{get,set}_stage_source 模式 —— PM chat 描述材料 →
caller SKILL 调本 helper → helper 内部完成 cp + 命名 + 状态登记 + 安全检查。
"""

from __future__ import annotations
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, TypedDict

from .state import read_req_meta, StateReadError


# ============================================================================
# 安全配置（v2 §0.4.14, C6 + C10）
# ============================================================================

# 敏感路径 denylist（caller raise ValueError）—— 经验值，消费仓发现新 case 扩展
SENSITIVE_PATH_PATTERNS = [
    r"/\.env\b",
    r"/\.ssh/",
    r"/\.aws/",
    r"/\.gnupg/",
    r"/\.netrc",
    r"/\.npmrc",
    r"/\.pypirc",
    r"/Library/Keychains/",
    r"/private/var/",
    r"token",          # 模糊匹配，含 .token / oauth-token / api-token / token.txt
    r"credential",     # 同上 — credential / credentials.json
    r"secret",         # secret.json / secrets/
    r"password",
]

# hard cap：单文件 > MAX_FILE_SIZE_MB → helper raise ValueError（C10）
# pre-commit hook warn 阈值是 10MB；此处 hard cap 设 50MB（v2 §5.1.3 待验）
MAX_FILE_SIZE_MB = 50


# ============================================================================
# Errors
# ============================================================================


class AttachmentError(Exception):
    """attachments helper 统一异常基类。"""


class SensitivePathError(AttachmentError):
    """源路径命中 SENSITIVE_PATH_PATTERNS denylist。"""


class FileSizeError(AttachmentError):
    """源文件超 MAX_FILE_SIZE_MB hard cap。"""


# ============================================================================
# Types
# ============================================================================


class AttachmentSeenEntry(TypedDict):
    name: str            # req 内相对路径（如 analysis-interview.pdf）
    src_origin: str      # PM 给的源绝对路径（追溯用）
    hint: Optional[str]  # PM 给的"重点"描述
    stage_prefix: str    # 上传时 stage 前缀（brief / analysis / prd / task-NNN / impl / task-plan / close）
    registered_at: str   # ISO 8601 UTC


class CopyResult(TypedDict):
    new_name: str         # `<stage 前缀>-<源 basename>` 或带 -N 后缀
    abs_path: Path        # $ACTIVE_REQ_DIR/attachments/<new_name>
    size_mb: float
    pending_inject: bool  # 当前 stage 产出文档不存在 → 不追加引用 section；caller 后续渲染


# ============================================================================
# helper API
# ============================================================================


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _check_sensitive(src: Path) -> None:
    src_str = str(src.resolve())
    for pattern in SENSITIVE_PATH_PATTERNS:
        if re.search(pattern, src_str, re.IGNORECASE):
            raise SensitivePathError(
                f"路径含敏感关键词 ({pattern})，拒纳：{src}"
            )


def _next_available_name(attachments_dir: Path, base_name: str, ext: str) -> str:
    """冲突 -2 / -3 / ... 后缀生成（C7 deterministic）。"""
    candidate = f"{base_name}{ext}"
    if not (attachments_dir / candidate).exists():
        return candidate
    counter = 2
    while True:
        candidate = f"{base_name}-{counter}{ext}"
        if not (attachments_dir / candidate).exists():
            return candidate
        counter += 1


def copy_attachment(
    req_dir: Path,
    src: Path,
    stage_prefix: str,
    hint: Optional[str] = None,
) -> CopyResult:
    """复制源文件到 req attachments/ 目录 + 登记到 attachments_seen。

    Args:
        req_dir: req 目录绝对路径
        src: PM 给的源路径（支持 ~ 展开）
        stage_prefix: stage 前缀（brief / analysis / prd / task-NNN / impl / task-plan / close）
        hint: PM 给的"重点"描述（追溯用）

    Returns: CopyResult

    Raises:
        FileNotFoundError: src 不存在 / 不可读
        SensitivePathError: src 在 SENSITIVE_PATH_PATTERNS denylist
        FileSizeError: src 超 MAX_FILE_SIZE_MB hard cap
    """
    # 1. expanduser + 校验可读
    src = src.expanduser().resolve()
    if not src.exists() or not src.is_file():
        raise FileNotFoundError(f"源路径不可读：{src}")

    # 2. 敏感路径 denylist（C6）
    _check_sensitive(src)

    # 3. Size hard cap（C10）
    size_bytes = src.stat().st_size
    size_mb = size_bytes / (1024 * 1024)
    if size_mb > MAX_FILE_SIZE_MB:
        raise FileSizeError(
            f"文件 {size_mb:.1f}MB 超 hard cap {MAX_FILE_SIZE_MB}MB：{src}"
        )

    # 4. 命名 + 冲突 -2 后缀
    attachments_dir = req_dir / "attachments"
    attachments_dir.mkdir(exist_ok=True)
    base_name = f"{stage_prefix}-{src.stem}"
    new_name = _next_available_name(attachments_dir, base_name, src.suffix)
    dst = attachments_dir / new_name

    # 5. shutil.copy2 保留 mtime（C7 Python 而非 Bash cp）
    shutil.copy2(src, dst)

    # 6. attachments_seen append（C3 真相源）
    register_attachment(
        req_dir,
        filename=new_name,
        src_origin=str(src),
        hint=hint,
        stage_prefix=stage_prefix,
    )

    # 7. 判断当前 stage 产出文档是否存在 → 决定 pending_inject
    pending_inject = not _stage_doc_exists(req_dir, stage_prefix)

    return CopyResult(
        new_name=new_name,
        abs_path=dst,
        size_mb=size_mb,
        pending_inject=pending_inject,
    )


def _stage_doc_exists(req_dir: Path, stage_prefix: str) -> bool:
    """判断当前 stage 产出文档是否存在（C5 pending reference fix）。

    stage_prefix → 期望文档：
        brief → brief.md
        analysis → analysis.md / stage2-office-hours.md (D-i v4 B 分支)
        prd → prd.md
        impl → implementation-design.md
        task-plan → task-plan.md
        task-NNN → tasks/task-NNN-*.md (任一)
        close → close-report.md
    """
    mapping = {
        "brief": [req_dir / "brief.md"],
        "analysis": [req_dir / "analysis.md", req_dir / "stage2-office-hours.md"],
        "prd": [req_dir / "prd.md"],
        "impl": [req_dir / "implementation-design.md"],
        "task-plan": [req_dir / "task-plan.md"],
        "close": [req_dir / "close-report.md"],
    }
    if stage_prefix.startswith("task-") and stage_prefix != "task-plan":
        # task-NNN 走 glob
        tasks_dir = req_dir / "tasks"
        return bool(list(tasks_dir.glob(f"{stage_prefix}-*.md"))) if tasks_dir.exists() else False
    candidates = mapping.get(stage_prefix, [])
    return any(p.exists() for p in candidates)


def register_attachment(
    req_dir: Path,
    filename: str,
    src_origin: Optional[str] = None,
    hint: Optional[str] = None,
    stage_prefix: str = "unknown",
) -> None:
    """append 到 .req-meta.json:attachments_seen 列表。

    Raises:
        StateReadError: .req-meta.json 不存在或解析失败
    """
    meta = read_req_meta(req_dir, strict=True)
    assert meta is not None
    seen: list[AttachmentSeenEntry] = meta.get("attachments_seen", [])
    seen.append(
        AttachmentSeenEntry(
            name=filename,
            src_origin=src_origin or "",
            hint=hint,
            stage_prefix=stage_prefix,
            registered_at=_now_iso(),
        )
    )
    meta["attachments_seen"] = seen
    meta_file = req_dir / ".req-meta.json"
    meta_file.write_text(
        json.dumps(meta, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def list_attachments_seen(req_dir: Path) -> list[AttachmentSeenEntry]:
    """返回 attachments_seen 列表（旧 req 无字段 → 空列表）。"""
    meta = read_req_meta(req_dir, strict=False) or {}
    return meta.get("attachments_seen", [])


def is_seen(req_dir: Path, filename: str) -> bool:
    """trigger 2 改造：判断 filename 是否已 register。"""
    return any(a["name"] == filename for a in list_attachments_seen(req_dir))


def remove_attachment(req_dir: Path, filename: str) -> None:
    """rm attachment 文件 + 从 attachments_seen 移除。

    用于 PM 说 "删 X"（D6 删除路径）。
    """
    dst = req_dir / "attachments" / filename
    if dst.exists():
        dst.unlink()
    meta = read_req_meta(req_dir, strict=True)
    assert meta is not None
    seen = meta.get("attachments_seen", [])
    meta["attachments_seen"] = [a for a in seen if a["name"] != filename]
    meta_file = req_dir / ".req-meta.json"
    meta_file.write_text(
        json.dumps(meta, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def replace_attachment(
    req_dir: Path,
    old_filename: str,
    new_src: Path,
) -> CopyResult:
    """PM 说 "把 X 换成 Y"：rm 旧 + cp 新（保留旧 filename 不变，引用 section 不动）。

    stage_prefix 沿用旧条目（保持文件名一致性）。
    """
    seen = list_attachments_seen(req_dir)
    old_entry = next((a for a in seen if a["name"] == old_filename), None)
    if not old_entry:
        raise FileNotFoundError(f"attachments_seen 中找不到 {old_filename}")

    # rm 旧（同时清 attachments_seen 条目）
    remove_attachment(req_dir, old_filename)

    # cp 新（保留旧 filename，不重新命名）
    new_src = new_src.expanduser().resolve()
    if not new_src.exists():
        raise FileNotFoundError(f"新源不可读：{new_src}")
    _check_sensitive(new_src)
    size_bytes = new_src.stat().st_size
    size_mb = size_bytes / (1024 * 1024)
    if size_mb > MAX_FILE_SIZE_MB:
        raise FileSizeError(f"新源 {size_mb:.1f}MB 超 cap {MAX_FILE_SIZE_MB}MB")

    dst = req_dir / "attachments" / old_filename
    shutil.copy2(new_src, dst)
    register_attachment(
        req_dir,
        filename=old_filename,
        src_origin=str(new_src),
        hint=old_entry.get("hint"),
        stage_prefix=old_entry.get("stage_prefix", "unknown"),
    )
    return CopyResult(
        new_name=old_filename,
        abs_path=dst,
        size_mb=size_mb,
        pending_inject=not _stage_doc_exists(req_dir, old_entry.get("stage_prefix", "unknown")),
    )
```

### §1.5 stage 前缀映射 + caller 推断

| stage | 当前 stage 产出 | helper 调用 stage_prefix |
|---|---|---|
| 1 (new-req / req-stage-gate Stage 1→2 入口) | brief.md | `brief` |
| 2 A 分支 (req-analysis) | analysis.md | `analysis` |
| 2 B 分支 (req-stage-gate office-hours) | stage2-office-hours.md | `analysis`（与 A 分支统一前缀）—— 但 **B 分支选源期间 trigger 0 禁用**（§1.3） |
| 3 (prd-writing) | prd.md | `prd` |
| 4 (DESIGN.md，项目级) | — 不在 req attachments | （不调 helper） |
| 5a (implementation-design) | implementation-design.md | `impl` |
| 5b (task-plan) | task-plan.md | `task-plan` |
| 6 (task-spec / task-execute) | tasks/task-NNN-*.md | `task-NNN`（按当前 task short_id） |
| 7 (close-task / close-req) | close-report.md | `close` |

caller SKILL 在 prose 内取 `$ACTIVE_REQ_STAGE` + 当前 task short_id 推 stage_prefix。**standalone /prd-writing 模式不调 helper**（D4 边界）。

### §1.6 office-hours 源材料 vs attachments 边界（C4）

`req-stage-gate` Stage 1→2 B 分支 "选源材料" 子流程（§1.2 PM 三选一：用第 N 份 / 跑新 / 我自己指定路径 / 切回 A）期间，**trigger 0 禁用**。PM 给的绝对路径走 D-i v4 office-hours snapshot 路径（`set_stage_source(req_dir, 2, 'stage2-office-hours.md', tool='office-hours', origin=<原绝对路径>)`），**不**调 `copy_attachment`。

SKILL prose 明示：B 分支 3B / 3B-resume / 3B-snapshot 子步骤期间 attachments-upload.md trigger 0 暂停；B 分支完成（5B 推进确认门 PM OK）后恢复。

### §1.7 多附件 batch / 替换 / 删除 / 冲突

helper 直接 cover（§1.4 API）：

- **多附件 batch**：caller SKILL 顺序调 `copy_attachment` N 次；chat 一次输出 bullet 列表
- **替换**：caller 调 `replace_attachment(req_dir, old_filename, new_src)` → helper rm 旧 + cp 新（保留旧文件名 + attachments_seen 行不变）
- **删除**：caller 调 `remove_attachment(req_dir, filename)` → helper rm + 清 attachments_seen 行
- **同名冲突**：helper 内部 `_next_available_name` 自动追加 `-2` / `-3` 后缀

### §1.8 trigger 2 静默扫描保留 + helper 联动（C3 / C8）

trigger 2 改用 `_lib.attachments.is_seen(req_dir, filename)` 判断已注册 —— 状态真相源是 `.req-meta.json:attachments_seen`，**不**依赖引用 section（旧机制要求每 stage 只列本 stage 引用过的，跨 stage 不一致 → 不能作真相源）。**Codex C8 顺势化解**。

PM 真手动 cp 进 attachments/（绕过 chat 走旧路径）→ trigger 2 扫到不在 `attachments_seen` 中的文件 → 主动问 PM "要不要纳入？说明重点"（与旧 trigger 2 行为一致）；PM 答 OK 后 caller 调 `register_attachment` 补登记。

### §1.9 引用 section 仅作 PM 可见展示（D6 / C8）

helper cp 后 caller SKILL 在当前 stage 产出文档末尾追加 `## 📎 参考材料` 引用一行 —— 但这是 **PM 可见展示** 不是状态真相源。**真相源 = `.req-meta.json:attachments_seen`**。

**C5 pending reference fix**：

- helper `CopyResult.pending_inject = True` → 当前 stage 产出文档**还没生成**（如 PM 在 chat 中部给路径，AI 还没写 analysis.md）→ helper **不**尝试追加（避免假设文件存在）
- caller SKILL 后续写当前 stage 产出文档时，**主动读 `list_attachments_seen(req_dir)` + 渲染**所有 `pending_inject` 状态的条目到 `## 📎 参考材料` section
- 已渲染过的条目下次不重复（caller 按 attachments_seen 顺序渲染 + 去重）

### §1.10 Stage 1 dirty worktree fix（C1）

new-req 步骤 4.5 commit pathspec **扩** `attachments/`（如目录存在且非空）：

```bash
# scripts/new-req/SKILL.md 步骤 4.5 commit 范围扩
git add "$REQ_REL/brief.md" "$REQ_REL/.req-meta.json" "$REQ_REL/tasks"
if [ -d "$REQ_DIR/attachments" ] && [ -n "$(ls -A "$REQ_DIR/attachments" 2>/dev/null)" ]; then
  git add "$REQ_REL/attachments"
fi
git commit -m "stage 1 brief: req-NNN-<slug>"
```

后续 stage 同款（如 req-analysis 步骤 ... 写 analysis.md 时 caller commit 范围扩 attachments/）。

I-DC1 dispatch 前 working tree 必须 clean 边界 → 不破。

### §1.11 PM 视角 vs IDE 可见性

attachments/ 在 git tracked → PM IDE 仍能看到目录。**目标不是藏起来，是 PM 心智里不去碰** —— 所有上传 / 改名 / 删除通过 chat 让 AI 调 helper。

---

## §2 与现役机制的关系（v2 helper-based）

| 现役 mechanism | v2 关系 | 改动 |
|---|---|---|
| **`scripts/_lib/attachments.py`**（新建）| **新建** | `copy_attachment / register_attachment / list_attachments_seen / is_seen / remove_attachment / replace_attachment` + `SENSITIVE_PATH_PATTERNS` denylist + `MAX_FILE_SIZE_MB` hard cap + `_stage_doc_exists` pending fix |
| `scripts/_lib/state.py` | **加 attachments_seen 字段约定** | 同 D-i v4 stage{N}_source 模式 |
| `skills/_shared/pm-view/attachments-upload.md`（新建）| **新建** | trigger 0 LLM 识别 prose + caller 调 helper 模式 + multi-batch / 替换 / 删除 / 冲突 / 失败兜底 / stage 前缀映射表 + office-hours C4 边界 |
| `skills/new-req/SKILL.md` 步骤 4.4 + 4.5 | **改** | trigger 0 inline 段（PM 拍 D2 = A） + commit pathspec 扩 attachments/（C1） |
| `skills/req-analysis/SKILL.md` 步骤 3.7 | **改** | trigger 0 inline 段 + caller pending inject 渲染 |
| `skills/prd-writing/SKILL.md` | **新加 hook 段** | trigger 0 inline 段（v1 §2 表 fact-check 失误已修） |
| `skills/task-spec/SKILL.md` | **新加 hook 段** | trigger 0 inline 段 |
| **`skills/implementation-design/SKILL.md`**（C2 新加）| **新加 hook 段** | trigger 0 inline 段 |
| **`skills/task-plan/SKILL.md`**（C2 新加）| **新加 hook 段** | trigger 0 inline 段 |
| `skills/req-stage-gate/SKILL.md` Stage 1→2 B 分支 | **加 trigger 0 disable prose**（C4） | B 分支 3B / 3B-resume / 3B-snapshot 期间 trigger 0 禁用 |
| `_shared/pm-view/input-flow.md` | **不变**（"按需读" 规则保留）| 0 |
| `PM-VIEW-RULES.md` 主索引 | **加 1 行** | attachments-upload.md 子文件指针（D5） |
| `scripts/create-req-headless.sh` | **不变** | attachments/ 由 helper 在 cp 时 mkdir，无需 create-req 预建 |
| **`templates/req-prd.md.tmpl`** "九、附件（可选）" | **修一致命名**（C9） | 改为 `## 📎 参考材料` 与其他 stage 统一 |
| **`templates/task.md.tmpl`** | **不变** | 已是 `## 📎 参考材料` |
| `docs/归档/完成/attachments-机制.md` | **加 v2 升级指针段** | 1 段说明 v2 helper-based 升级 |
| `INVARIANTS.md` | **加 I-RT10** | attachments_seen 字段不变式（与 I-RT9 同款 helper-only 约束） |

---

## §3 实施清单

| vp | 任务 | 估时 |
|---|---|---|
| **vp-1** | `scripts/_lib/attachments.py` 新建（§1.4 全套 helper + `SENSITIVE_PATH_PATTERNS` + `MAX_FILE_SIZE_MB` + `_stage_doc_exists`）| 45 min |
| **vp-2** | `skills/_shared/pm-view/attachments-upload.md` 新建（trigger 0 LLM 识别 prose + caller 调 helper 模式 + multi-batch / 替换 / 删除 / 冲突 / 失败兜底 / stage 前缀映射 + office-hours C4 边界 + standalone D4 边界）| 30 min |
| **vp-3** | 7 个 stage SKILL 加 trigger 0 inline 段（PM 拍 D2 = A）：new-req / req-analysis / prd-writing / task-spec / req-stage-gate / **implementation-design** / **task-plan**（最后 2 个 C2 新增）| 50 min |
| **vp-3b** | new-req 步骤 4.5 commit pathspec 扩 `attachments/`（C1 fix；其他 stage caller commit 时同款扩） | 10 min |
| **vp-3c** | req-stage-gate Stage 1→2 B 分支 3B / 3B-resume / 3B-snapshot 子步骤期间 trigger 0 disable prose（C4 fix） | 10 min |
| **vp-4** | `tests/test-attachments-helper.sh` 新建 — 11 个 case：<br>① unit: `copy_attachment` 成功（机械命名 + 冲突 -2 + attachments_seen append + pending_inject 判定）<br>② unit: SensitivePathError 触发（`.env` / `.ssh/` / `token` 等典型 case）<br>③ unit: FileSizeError 触发（>50MB）<br>④ unit: `register_attachment` + `list_attachments_seen` round-trip<br>⑤ unit: `is_seen` 兼容 旧 req（无 attachments_seen 字段 → 空列表）<br>⑥ unit: `remove_attachment`（rm 文件 + 清 seen 行）<br>⑦ unit: `replace_attachment`（保留旧 filename + attachments_seen 更新）<br>⑧ unit: `Path.expanduser` 处理 `~/x.pdf`<br>⑨ unit: 含空格文件名 `~/Downloads/foo bar.pdf` 不炸<br>⑩ **integration regression**（**REGRESSION RULE iron rule**）：现有 PM 手动 cp 进 attachments/ → trigger 2 改造（is_seen 判定）下仍能被识别<br>⑪ integration: office-hours B 分支选源期间不误调 helper（grep + scenario test） | 60 min |
| **vp-5** | `templates/req-prd.md.tmpl` 修 "九、附件（可选）" → `## 📎 参考材料`（C9 一致命名）| 5 min |
| **vp-6** | `PM-VIEW-RULES.md` 加 attachments-upload.md 主索引 1 行（D5）+ `INVARIANTS.md` 加 I-RT10（attachments_seen 字段不变式 + denylist + hard cap 边界） | 10 min |
| **vp-7** | 文档同步：`CHANGELOG.md` 未发布段 + `RUNTIME.md` 「当前位置」 + `docs/INDEX.md` + 落地后 `git mv docs/设计/attachments-体验优化.md docs/归档/完成/attachments-AI-接管.md` + `docs/归档/完成/attachments-机制.md` 加 "v2 helper 化升级指针" 段 | 15 min |

**总估时**：~3.5h（vp-1 / vp-2 部分并行 → 实际 ~2.75h；vp-3 / vp-3b / vp-3c 串行 ~1h；vp-4 并行 ~1h；vp-5 ~ vp-7 ~30min）

**测试基线**：当前 412/0；落地后预期 ≥ 423/0（vp-4 加 11 case）

---

## §4 砍掉的机制清单（防 review 加回来）

| 机制 | 为什么砍 |
|---|---|
| **v1 prose-only 方案**（5 SKILL 各 inline） | **Codex Round 1 命中**（11 finding 集体根因）：file system 操作 / state 管理 / cross-design 协调靠模型记忆漂；helper-based 是 D-i v4 同款现仓约定 |
| **Bash cp + `~` 展开 + `-2` 拼接** | C7：Python `shutil.copy2 + Path.expanduser` 解决；deterministic suffix 在 `_next_available_name` |
| **引用 section 作为状态真相源** | C3 / C8：状态真相源 = `.req-meta.json:attachments_seen`；引用 section 仅 PM 可见展示 |
| **trigger 0 在 stage-gate B 分支选源期间启用** | C4：与 D-i v4 office-hours 源材料选择冲突，必须禁用 |
| **trigger 0 在 standalone `/prd-writing` 启用** | D4 决议：standalone 不绑 req → 不入 req attachments/ |
| **size pre-commit warn 作 fail-open 兜底** | C10：`MAX_FILE_SIZE_MB = 50` 在 helper 里 raise，不依赖 pre-commit |
| **"AI 识别 PM 上传意图后立即追加引用 section"** | C5：stage 产出文档可能不存在；改 helper 仅 register + caller SKILL 后续按 attachments_seen 列表渲染 |
| **C9 `req-prd.md.tmpl` "九、附件（可选）"** | 与其他 stage `## 📎 参考材料` 不一致 → 修一致命名 |
| **沿用 v1 §2 表 "prd-writing / task-spec 同款升级"** | D1 fact-check：现仓无 hook 可"升级"；v2 是"新加" |
| **attachments_seen 字段不走 `_lib/state.py`** | C3：现仓约定 `.req-meta.json` 读写走 helper；v2 helper 化后属 attachments.py 领域 |

---

## §5 风险与待验

### §5.1 待验项

1. **LLM 识别准确性**：trigger 0 LLM prose 判断 PM "上传意图"。**DEFER 同款 D-i v4 R3-H2**（D10 决议）—— 相信 LLM 全文喂消化，消费仓真实 req 验证。如不行再引入 LLM eval framework（独立 D-* 设计）。
2. **`SENSITIVE_PATH_PATTERNS` denylist 覆盖度**：经验值列 14 个 pattern，可能漏 case（如 OAuth token cache `~/.cache/` / docker 镜像）。消费仓使用后扩展。
3. **`MAX_FILE_SIZE_MB = 50` 阈值是否合适**：pre-commit warn 阈值 10MB，hard cap 50MB 是经验值；可能要消费仓调整。
4. **替换语义识别准确性**：LLM 识别"把 X 换成 Y" 中 X 指代旧文件 → caller 调 `replace_attachment(req_dir, old_filename, ...)` 时 old_filename 来源 = caller 在 chat 内 anchor `list_attachments_seen` 列表 + LLM 判断。消费仓验证。

### §5.2 风险

| R# | 风险 | 缓解 |
|---|---|---|
| R1 | helper denylist 漏敏感路径（如 OAuth token cache 在 `~/.cache/`，gcloud config 在 `~/.config/gcloud/`）| §5.1.2 消费仓发现新 case 扩 patterns；helper fail-loud：raise SensitivePathError，chat 报错给 PM |
| R2 | Python `shutil.copy2` 在异常 filesystem（NFS / case-insensitive HFS+）出错 | helper 抛 OSError；caller SKILL chat 报错给 PM |
| R3 | `attachments_seen` 累积大列表（长 req 多次上传同文件不同版本）| 接受；`list_attachments_seen` O(N)，N 实际 ≤ 几十不算性能 |
| R4 | C5 修复后 `pending_inject` 标记下次 stage 渲染时漏 | caller SKILL 按 `list_attachments_seen` 顺序渲染 + section 内已存在 anchor name 不重复 |
| R5 | C9 修 `req-prd.md.tmpl` 影响在飞旧 req | 不动旧 req `prd.md`；只改 template；caller 渲染按实际 section name |
| R6 | C4 office-hours 与 attachments 边界 prose 在 SKILL 内忘标 | vp-4 ⑪ scenario test 验证；vp-3c 显式 prose 段 |
| R7 | helper `_stage_doc_exists` 误判（如 B 分支 PM 选源前 analysis.md 不存在 → pending_inject=True，但 B 分支不调 attachments helper）| §1.6 C4 边界已 cover：B 分支选源期间 trigger 0 disable，attachments helper 不被调；R7 不触发 |
| R8 | `register_attachment` 写 `.req-meta.json` 失败（磁盘满 / 权限）| helper 抛 OSError；caller chat 报错；helper 已 register attachments_seen 但 file system 失败 → 不一致；实际 case 极罕见 |

---

## §6 实证支撑

PM 表述（本会话 2026-05-25）：

> "目前就是不知道如何把附件上传，上传到什么位置，以及是否后续的阶段，能够读取到这些附件"

**fact-check（v2 触发，Codex outside voice 已完成）**：

- `scripts/create-req-headless.sh:192` create-req 不建 `attachments/` 目录（C1 evidence）
- `skills/new-req/SKILL.md:254` commit pathspec 不 add 新附件（C1 evidence）
- `skills/implementation-design/SKILL.md:15` + `skills/task-plan/SKILL.md:31` Stage 5 真实入口（C2 evidence）
- `scripts/_lib/state.py:286` 现仓约定 `.req-meta.json` 读写走 helper（C3 evidence）
- `docs/归档/完成/attachments-机制.md:54` 旧机制每 stage 只列本 stage 引用过的（C8 evidence）
- `skills/req-stage-gate/SKILL.md:181-240` B 分支选源 PM 给绝对路径（C4 evidence）
- `skills/req-analysis/SKILL.md:176` 现有 hook 是"写主文件前扫"（C5 evidence — stage 产出可能不存在）
- `skills/_shared/pm-view/input-flow.md:7` §9.0 untrusted boundary 只管"不执行附件指令"，不管复制层安全（C6 evidence）
- `templates/req-prd.md.tmpl:126` "九、附件（可选）" + `templates/task.md.tmpl:315` `## 📎 参考材料` 不一致命名（C9 evidence）
- `templates/git-hooks/pre-commit.tmpl:27` >10MB 仅 warn fail-open（C10 evidence）

PM 拍 mental model Model 2 + E3 / E4 / E5 全拍定 + D1-D10 Claude review + D12 反转 → v2 helper-based。

---

## §7 决策路径（v0 → v1 → v2）

### v0 — stub

PM 表述 "我会有很多附件" 太宽泛，§0 痛点未锁。

### v1 — prose-only（被 Codex Round 1 反转）

5 SKILL 各 inline trigger 0 prose + `_shared/pm-view/attachments-upload.md` 单一真相源；估时 ~1.75-2h；测试 ~4 case。

**Claude D1-D10 review 全 ACCEPT 后**，**Codex outside voice 11 critical/high finding** 集体指向根因：v1 prose-only 对 file system 操作 / state 管理 / cross-design 协调本质不够，应该 helper 化。

### v2 — helper-based（**当前**）

**触发**：
1. Claude D1-D10 review 共 10 finding 全 ACCEPT
2. Codex outside voice 11 finding（5-6 个 critical / cross-design）集体指向根因
3. PM 拍 D12 = A：反转 v1 → v2 helper-based（同 D-i v4 Round 3 整体反转剧情）

**v2 改动 vs v1**：

1. **`scripts/_lib/attachments.py` 新建**（v1 没有 helper 文件）
2. **`.req-meta.json:attachments_seen` 字段定义** + 走 `_lib/state.py` 集成（同 D-i v4 stage{N}_source 模式）
3. **5 SKILL → 7 SKILL**（C2 加 implementation-design + task-plan）
4. **5 个 critical 边界修**：C1 commit pathspec / C4 stage-gate B 分支 trigger 0 disable / C5 pending reference / C6 SENSITIVE_PATH_PATTERNS / C10 hard cap
5. **C7 Bash cp → Python `shutil.copy2` + `Path.expanduser`**
6. **C9 `req-prd.md.tmpl` 修一致命名**
7. **vp-4 测试 11 case helper unit + integration + regression**
8. **`INVARIANTS.md` 加 I-RT10**（attachments_seen 字段约束）

**v2 估时**：~3.5h（vs v1 ~1.75h）
**v2 测试基线**：≥ 423/0（vs v1 ~416/0）

**v2 架构红利**（v1 没有）：

- 与 D-i v4 `_lib.state.{get,set}_stage_source` 同款 helper-based 架构（一致性）
- file system 操作 / 安全检查 / state 管理在 Python 代码层确定性（不靠 LLM prose 漂）
- vp-4 unit test 直接验 helper 行为（比 prose grep 强）
- denylist / hard cap 在 helper 内部硬卡（fail-loud），不依赖 SKILL prose 提示

---

## §X Review Findings

> Round 1（Claude D1-D10 + Codex 11 finding）全集；锁定 21 个 ACCEPT + 1 DEFER。

### Round 1 — 2026-05-25 — Claude plan-eng-review (D1-D10)

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| F-S0-1 | Medium | v1 §2 prd-writing / task-spec 现仓无 attachments hook | §0.2.4 | grep skills/{prd-writing,task-spec}/SKILL.md | **ACCEPT A**（D1）— v2 §2 修，标"新加" |
| F-A1 | Medium | 5 SKILL 怎么"引用" attachments-upload.md 单一真相源 | DRY | prior learning | **ACCEPT A**（D2）— inline 完整段 + 链；v2 仍保留（caller SKILL 调 helper） |
| F-A2 | Medium | trigger 0 / trigger 2 优先级 race | §0.3 | prose race | **ACCEPT A**（D3）— `.req-meta.json:attachments_seen` 颁证；v2 helper 内一致 |
| F-A3 | Medium | standalone 模式 stage 前缀无 ACTIVE_REQ_STAGE | §0.4 | prd-writing:35-43 | **ACCEPT A**（D4）— standalone 不启 trigger 0 |
| F-A4 | Low | PM-VIEW-RULES 主索引未列 attachments-upload.md | DRY 索引 | grep | **ACCEPT A**（D5）— 加 1 行 |
| F-C1 | Medium | §1.6 anchor 跟 D3 决议未同步 | DRY 一致 | grep | **ACCEPT A**（D6）— anchor=attachments_seen；v2 helper 化后顺势 |
| F-C2 | Medium | §1.4 步骤 5 section 插入位置 prose 不明 | edge case | grep | **ACCEPT A**（D7）— 物理末尾追加；v2 §1.9 helper 控制（C5 fix 补） |
| F-C3 | Medium | size check 缺独立 step | edge case | v1 §1.4 步骤 1-6 | **ACCEPT A**（D8）— v2 helper 内 + hard cap（C10） |
| F-T1 | High | vp-4 测试拆分严重不足 + missing regression | REGRESSION RULE | v1 §3 vp-4 "~4 case" | **ACCEPT A**（D9）— v2 vp-4 拆 11 case 含 regression |
| F-T2 | High | trigger 0 LLM 识别无 [→EVAL] | §5.1.1 | 现仓无 LLM eval framework | **ACCEPT A**（D10）— DEFER 同 D-i v4 R3-H2 |

### Round 1 — 2026-05-25 — Codex outside voice (C1-C11)

| # | Severity | Finding | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| **C1** | **Critical** | Stage 1 上传 dirty worktree → 破 I-DC1 handoff | §0.3 + Codex | create-req-headless.sh:192 + new-req:254 | **ACCEPT**（v2 vp-3b §1.10） |
| **C2** | **Critical** | 漏 Stage 5 真实入口 implementation-design / task-plan | §0.2 | implementation-design:15 + task-plan:31 | **ACCEPT**（v2 vp-3，7 SKILL 总数）|
| **C3** | **Critical** | attachments_seen 没落到 _lib/state.py + schema 迁移 + 测试 | DRY + I-RT9 | state.py:286 | **ACCEPT**（v2 vp-1 attachments.py + state.py 集成）|
| **C4** | **Critical** | trigger 0 与 D-i v4 office-hours 源材料选择冲突 | cross-design | req-stage-gate:181 + :240 | **ACCEPT**（v2 vp-3c + §1.6）|
| **C5** | **High** | "产出文档末尾追加" 假设文件存在 | edge case | v1 §1.4 步骤 5 + req-analysis:176 | **ACCEPT**（v2 §1.9 pending_inject + caller 渲染）|
| **C6** | **High** | 文件复制安全边界缺失（敏感文件 denylist）| security | §9.0 | **ACCEPT**（v2 vp-1 SENSITIVE_PATH_PATTERNS）|
| **C7** | **High** | Bash cp 方案太脆 | code quality | v1 §1.4 步骤 4 | **ACCEPT**（v2 vp-1 Python shutil + expanduser）|
| **C8** | **High** | 引用 section 作为状态在现规范下不成立 | mechanism design | attachments-机制.md:54 + input-flow:56 | **ACCEPT**（v2 §1.8 / §1.9 attachments_seen 真相源）|
| **C9** | **Medium** | 模板事实不对（req-prd.md.tmpl 命名不一致）| consistency | req-prd.md.tmpl:126 + task.md.tmpl:315 | **ACCEPT**（v2 vp-5）|
| **C10** | **Medium** | size 策略 fail-open | reliability | pre-commit.tmpl:27 | **ACCEPT**（v2 vp-1 MAX_FILE_SIZE_MB=50 hard cap）|
| **C11** | **High** | vp-4 测试不证明关键风险 | test coverage | grep tests/run-all.sh | **ACCEPT**（v2 vp-4 11 case 全覆盖含 office-hours 排除 + commit pathspec + 敏感路径 + 空格 + 替换 + regression）|

**汇总**：

- **ACCEPT 21 条**：Claude D1-D10 共 10 + Codex C1-C11 共 11
- **DEFER 1 条**：F-T2 LLM eval framework
- **CLOSE / SUPERSEDED 0 条**：所有 finding 在 v2 化解或保留决议

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-24 | v0 stub 创建（D4 Round 2 B 分组）| 等 §0 共写 |
| 2026-05-25 | PM 拍 mental model A（Model 2 AI 接管，PM 不感知 attachments/ 目录）| 切方向 |
| 2026-05-25 | E3 / E4 / E5 拍定（多附件 batch 顺序 cp / 自动 -2 后缀 / trigger 2 保留作 fallback）| v1 设计完整 |
| 2026-05-25 | 命名机制 = 候选 a 机械（`<stage 前缀>-<源 basename>`）| 减交互回合 |
| 2026-05-25 | §0 锁定 + v1 prose-only 方案主体展开 | 待 plan-eng-review |
| 2026-05-25 | plan-eng-review Round 1 — Claude D1-D10 全 ACCEPT | 10 finding ACCEPT |
| 2026-05-25 | Codex outside voice — 11 critical/high finding 集体指向根因 = helper 化 | v1 → v2 整体反转触发 |
| 2026-05-25 | **PM 拍 D12 = A：反转 v1 → v2 helper-based**（同 D-i v4 Round 3 剧情）| v2 重写方案主体 |
| 2026-05-25 | **v2 锁定**（helper-based + 21 ACCEPT + 1 DEFER）| 估时 ~3.5h；测试 ≥ 423/0 |

---

**End of D-iii：attachments AI 接管 v2**

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | — | — |
| Codex Review | `/codex review` | Independent 2nd opinion | 1 | issues_found | 11 findings (4 Critical / 4 High / 2 Medium / 1 High test) → 反转 v1 → v2 helper-based；全 ACCEPT |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 | CLEAR (PLAN) | 21 issues / 3 critical gaps（全 surface 在 v2 §5.2）；ACCEPT 21 / DEFER 1 |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | — |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 | — | — |

- **CODEX**: 11 findings (C1 Stage 1 dirty worktree / C2 漏 Stage 5 入口 / C3 attachments_seen 没 helper 化 / C4 office-hours 冲突 / C5 stage 产出文档不存在 / C6 敏感文件 denylist / C7 Bash cp 脆 / C8 引用 section 不是真相源 / C9 模板事实 / C10 size fail-open / C11 测试不足)；**集体指向根因 = v1 应 helper 化** → v2 整体反转
- **CROSS-MODEL**: Claude D2-D10 倾向 prose-based / Codex 反推 helper-based → PM 拍 D12 = A 同 D-i v4 Round 3 整体反转剧情；attachments_seen 字段应同 stage{N}_source 走 _lib/state.py helper
- **UNRESOLVED**: 0（DEFER F-T2 LLM eval framework 已在 v2 §5.1.1，非 unresolved）
- **VERDICT**: ENG CLEARED — v2 锁定 / 可进实施。下一步 vp-1 → vp-7（~3.5h 估时）+ vp-4 测试 11 case（基线 412/0 → 预期 ≥ 423/0）
- **REVIEW COMPLETE: 11/11 sections**（CLAUDE.md 项目级强制约束完整跑：Preamble / Design Doc Check / Step 0 Scope Challenge / Section 1 Architecture (4 finding) / Section 2 Code Quality (3 finding) / Section 3 Tests (coverage diagram + 11 gap) / Section 4 Performance (0 finding) / Outside Voice Codex (11 finding) / Required outputs / Implementation Tasks JSONL / Completion + Review Log + Dashboard + Plan File Review Report。**0 跳过项 / 0 BLOCKER 降级**）
