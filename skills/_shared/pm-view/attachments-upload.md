# attachments AI 接管（trigger 0 LLM 识别）

> **caller**：主路径 SKILL（next / design / build / prd-writing / close）。  
> **目标目录**：`docs/inputs/attachments/`。  
> **状态登记**：当前模块 `docs/modules/<模块>/.work-meta.json:attachments_seen`。

## §1 PM 视角 mental model

PM 在 chat 任何位置自然描述"我有 X 在路径 Y，重点是 Z" → AI 后台归档 + 命名 + 状态登记 + 引用追加 → chat 一行确认。PM 不需要学习文件系统约定。

## §2 caller SKILL 行为约定

### §2.1 trigger 0 识别

PM chat 同时含以下两元素 → caller AI 自动识别为"上传附件"意图：

1. 一个或多个绝对路径：macOS `/Users/...` 或 `~/...`。
2. 关联描述：PM 在描述这是材料 / 给 AI 看的内容。

AI 不确信时，反问一句：`是否要把 <path> 归档进本需求的参考材料？`，PM 答确认后才调 helper。

### §2.2 禁用例外

1. `prd-writing` standalone 模式不绑定当前模块工作时，不写当前模块 `.work-meta.json`；PM 可使用外部引用。
2. 当前还没有模块目录 / `.work-meta.json` 时，只做轻量预检并记录待处理列表；等模块创建后批量归档。
3. PM 给的是仓库内已有 source-of-truth 路径时，不复制为附件；直接按来源文件读取。

### §2.3 AI 触发后的 helper 调用

```python
from _lib.attachments import copy_attachment
from pathlib import Path

result = copy_attachment(
    work_dir=Path(ACTIVE_WORK_DIR),          # docs/modules/<模块>
    src=Path("~/Downloads/foo.pdf"),
    stage_prefix="spec",                  # 见 §3
    hint="第 3 页痛点列表",
)
# result.new_name == "docs/inputs/attachments/spec-foo.pdf"
```

helper 内部：

1. 展开并校验源路径。
2. 拒绝敏感路径。
3. 拒绝超过 50MB 文件。
4. 同名冲突自动加 `-2` / `-3`。
5. 复制到 `docs/inputs/attachments/<new_name>`。
6. 登记 `.work-meta.json:attachments_seen`。

### §2.4 chat 输出（PM 视图）

单附件：

```text
已归档（docs/inputs/attachments/<new_name>），<hint>。继续。
```

多附件：

```text
已归档：
- docs/inputs/attachments/<new_name 1> — <hint 1>
- docs/inputs/attachments/<new_name 2> — <hint 2>
继续。
```

禁词：
- 不输出 `cp` / `shutil` / `Path` 等命令名。
- 不输出源文件绝对路径全文。
- 不输出 `attachments_seen` / `pending_inject` 等字段名。
- 不输出 `已 register` / `已 copy` 等工程动词，用"已归档"。

### §2.5 helper 异常 chat 报错

| 异常 | chat 文案 |
|---|---|
| `FileNotFoundError` | `路径不可读：<src>。重新提路径，或检查是否已移动 / 改名。` |
| `SensitivePathError` | `路径含敏感关键词，拒纳：<src>。请确认是否要走这份材料，或换路径。` |
| `FileSizeError` | `文件 X MB 超 50MB 上限。建议外部引用（贴 URL）或拆小。` |

## §3 阶段前缀映射

| 场景 | helper stage_prefix |
|---|---|
| design / 模块规格 | `spec` |
| build | `build` |
| 复审 | `review` |
| 反向 PRD | `prd` |
| close | `close` |

找不到当前模块上下文时，不调 helper，提示 PM 在需求流程内重提。

## §4 替换 / 删除

替换：

```python
from _lib.attachments import replace_attachment
result = replace_attachment(
    work_dir,
    old_filename="docs/inputs/attachments/spec-foo.pdf",
    new_src=Path("~/Downloads/foo-v2.pdf"),
)
```

chat：`已替换 docs/inputs/attachments/spec-foo.pdf 为新内容。继续。`

删除：

```python
from _lib.attachments import remove_attachment
remove_attachment(work_dir, filename="docs/inputs/attachments/spec-foo.pdf")
```

chat：`已删 docs/inputs/attachments/spec-foo.pdf 及对应引用。继续。`

## §5 引用 section 渲染规则

`## 📎 参考材料` section 仅作 PM 可见展示，状态真相源是 `.work-meta.json:attachments_seen`。

```markdown
## 📎 参考材料

- `docs/inputs/attachments/<name 1>` — <hint 1>
- `docs/inputs/attachments/<name 2>` — <hint 2>
```

渲染规则：

- 按 `registered_at` 时间升序。
- 已有 section 时只 append 新行，不重复整段。
- 当前阶段产出还没生成时，只登记；后续写产物时主动补 section。

## §6 trigger 2 静默扫描

trigger 2 保留作 fallback：AI 写产出前扫 `docs/inputs/attachments/`，发现未登记文件时主动问 PM 是否纳入，并要求 PM说明重点。

```python
import os
from _lib.attachments import is_seen, register_attachment

for entry in os.scandir(repo_root / "docs" / "inputs" / "attachments"):
    rel = f"docs/inputs/attachments/{entry.name}"
    if entry.is_file() and not is_seen(work_dir, rel):
        # 问 PM "要不要纳入？说明重点"
        ...
```

## §7 失败兜底

| 场景 | helper 行为 | caller 行为 |
|---|---|---|
| 源路径不可读 | `FileNotFoundError` | chat 报错 + 让 PM 重提 |
| 命中 denylist | `SensitivePathError` | chat 报错 + 让 PM 确认 / 换路径 |
| 超 50MB | `FileSizeError` | chat 报错 + 建议外部引用 / 拆小 |
| `.work-meta.json` 不存在 | `StateReadError` | chat 报错 + 让 PM 在当前工作流程内重提 |
| 磁盘满 / 权限 | `OSError` | chat 报错 + 让 PM 处理 |

所有失败必须 fail-loud，不静默吞。
