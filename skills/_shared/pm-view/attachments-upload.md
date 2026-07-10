# attachments AI 接管（trigger 0 LLM 识别 + typed input）

> **caller**：主路径 SKILL（design / build / spec-writing / 自动 finalize；build-close 兼容恢复、record 仅在绑定现有模块工作时适用）。
> **目标目录**：`docs/inputs/<category>/`。
> **状态登记**：当前模块 `docs/modules/<模块>/.work-meta.json:attachments_seen`。
> **真实 helper**：`scripts/_lib/attachments.py`。helper 负责安全复制 / 命名 / 登记；LLM caller 负责根据 PM 描述和材料内容判断类别。

## §1 PM 视角 mental model

PM 在 chat 任何位置自然描述"我有 X 在路径 Y，重点是 Z" → AI 判断材料类型 → 后台归档 + 命名 + 状态登记 + 引用追加 → chat 一行确认。PM 不需要学习文件系统约定。

当前实现是**typed input + 模块引用登记**：

- 文件按类型归入 `docs/inputs/<category>/`。
- 当前模块 `.work-meta.json:attachments_seen` 登记本模块用过哪些材料。
- `attachments_seen` 是当前模块的引用清单，不是材料本体的唯一存放地。

## §2 类别判断

caller 先按 PM 描述和文件内容判断 `input_category`。目录名用英文 kebab，PM-facing 文案用中文。

| PM 说的材料类型 | input_category | 例子 |
|---|---|---|
| 用户访谈 / 客户反馈 / 调研记录 | `interviews` | 访谈录音转写、用户反馈表 |
| 竞品 / 参考产品 / 对标截图 | `competitors` | 竞品功能截图、对标分析 |
| 会议脑暴 / 内部讨论 | `brainstorming` | 白板截图、会议纪要 |
| 产品原文 / 旧 PRD / 业务说明 | `product-sources` | 旧需求文档、产品说明 |
| 信息模型 / 字段表 / 数据字典 | `info-models` | 字段清单、状态机图 |
| 行业参照 / 政策 / 外部资料 | `industry-references` | 行业报告、法规摘录 |
| 判不准但 PM 确认要归档 | `uncategorized` | 暂无法分类的材料 |

判不准时只问一句：`这份材料更像访谈、竞品、脑暴、产品原文、信息模型，还是行业参照？`

## §3 caller SKILL 行为约定

### §3.1 trigger 0 识别

PM chat 同时含以下两元素 → caller AI 自动识别为"上传附件"意图：

1. 一个或多个绝对路径：macOS `/Users/...` 或 `~/...`。
2. 关联描述：PM 在描述这是材料 / 给 AI 看的内容。

AI 不确信是否要归档时，反问一句：`是否要把 <path> 归档进本需求的参考材料？`，PM 答确认后才调 helper。

### §3.2 禁用例外

1. `spec-writing` 跨模块功能型规格文档 / 既有规格补差目标不绑定当前模块工作时，不写当前模块 `.work-meta.json`；PM 可使用外部引用。
2. `record` 只有绑定现有模块工作时才调 helper；项目级轻量记录不借本 helper 伪造模块附件。
3. 当前还没有模块目录 / `.work-meta.json` 时，只做轻量预检并记录待处理列表；等模块创建后批量归档。
4. PM 给的是仓库内已有 source-of-truth 路径时，不复制为附件；直接按来源文件读取。

### §3.3 AI 触发后的 helper 调用

```python
from _lib.attachments import copy_attachment
from pathlib import Path

result = copy_attachment(
    work_dir=Path(ACTIVE_WORK_DIR),        # docs/modules/<模块>
    src=Path("~/Downloads/foo.pdf"),
    stage_prefix="spec",                  # 见 §4
    hint="第 3 页痛点列表",
    input_category="interviews",          # 见 §2
)
# result.new_name == "docs/inputs/interviews/spec-foo.pdf"
```

helper 内部：

1. 展开并校验源路径。
2. 拒绝敏感路径。
3. 拒绝超过 50MB 文件。
4. 同名冲突自动加 `-2` / `-3`。
5. 复制到 `docs/inputs/<category>/<new_name>`。
6. 登记 `.work-meta.json:attachments_seen`。

### §3.4 chat 输出（PM 视图）

单附件：

```text
已归档到「访谈材料」（docs/inputs/interviews/<new_name>），<hint>。继续。
```

多附件：

```text
已归档：
- 访谈材料：docs/inputs/interviews/<new_name 1> — <hint 1>
- 竞品参考：docs/inputs/competitors/<new_name 2> — <hint 2>
继续。
```

禁词：
- 不输出 `cp` / `shutil` / `Path` 等命令名。
- 不输出源文件绝对路径全文。
- 不输出 `attachments_seen` / `pending_inject` 等字段名。
- 不输出 `已 register` / `已 copy` 等工程动词，用"已归档"。

### §3.5 helper 异常 chat 报错

| 异常 | chat 文案 |
|---|---|
| `FileNotFoundError` | `路径不可读：<src>。重新提路径，或检查是否已移动 / 改名。` |
| `SensitivePathError` | `路径含敏感关键词，拒纳：<src>。请确认是否要走这份材料，或换路径。` |
| `FileSizeError` | `文件 X MB 超 50MB 上限。建议外部引用（贴 URL）或拆小。` |

## §4 产物前缀映射

helper 参数仍叫 `stage_prefix`，但当前语义是**产物前缀**，不是旧阶段编号。只允许以下值：

| 场景 | helper stage_prefix | 说明 |
|---|---|---|
| design / 模块规格 / build 继续读模块规格 | `spec` | 附件服务当前模块 `discussion.md` / `decisions.md` / `spec.md` |
| 反向 PRD / 功能型规格文档且绑定当前模块工作 | `prd` | 只在 caller 确认有模块工作目录时使用 |
| landed 后自动文档编译 | `close`（兼容字段） | 附件服务文档影响 / 沉淀检查 |
| caller 已确认可归档但产物类型暂不可判 | `unknown` | 兜底值；后续引用时必须补说明 |

不支持 `build` / `review` 作为前缀；build 和复审阶段仍围绕模块规格产物，使用 `spec`。找不到当前模块上下文时，不调 helper，提示 PM 在需求流程内重提或使用外部引用。

## §5 替换 / 删除

替换：

```python
from _lib.attachments import replace_attachment
result = replace_attachment(
    work_dir,
    old_filename="docs/inputs/interviews/spec-foo.pdf",
    new_src=Path("~/Downloads/foo-v2.pdf"),
)
```

chat：`已替换 docs/inputs/interviews/spec-foo.pdf 为新内容。继续。`

删除：

```python
from _lib.attachments import remove_attachment
remove_attachment(work_dir, filename="docs/inputs/interviews/spec-foo.pdf")
```

chat：`已删 docs/inputs/interviews/spec-foo.pdf 及对应引用。继续。`

## §6 引用 section 渲染规则

`## 参考材料` section 仅作 PM 可见展示，状态真相源是 `.work-meta.json:attachments_seen`。

```markdown
## 参考材料

- `docs/inputs/interviews/<name 1>` — <hint 1>
- `docs/inputs/competitors/<name 2>` — <hint 2>
```

渲染规则：

- 按 `registered_at` 时间升序。
- 已有 section 时只 append 新行，不重复整段。
- 当前产物还没生成时，只登记；后续写产物时主动补 section。

## §7 trigger 2 静默扫描

trigger 2 保留作 fallback：AI 写产出前扫 `docs/inputs/*/`，发现未登记文件时主动问 PM 是否纳入，并要求 PM 说明重点和类别。

```python
import os
from _lib.attachments import is_seen, register_attachment

for category in os.scandir(repo_root / "docs" / "inputs"):
    if not category.is_dir():
        continue
    for entry in os.scandir(category.path):
        rel = f"docs/inputs/{category.name}/{entry.name}"
        if entry.is_file() and not is_seen(work_dir, rel):
            # 问 PM "要不要纳入？归到哪类？说明重点"
            ...
```

## §8 失败兜底

| 场景 | helper 行为 | caller 行为 |
|---|---|---|
| 源路径不可读 | `FileNotFoundError` | chat 报错 + 让 PM 重提 |
| 命中 denylist | `SensitivePathError` | chat 报错 + 让 PM 确认 / 换路径 |
| 超 50MB | `FileSizeError` | chat 报错 + 建议外部引用 / 拆小 |
| `.work-meta.json` 不存在 | `StateReadError` | chat 报错 + 让 PM 在当前工作流程内重提 |
| 类别名非法 | `AttachmentError` | 换成合法类别名，或归到 `uncategorized` |
| 磁盘满 / 权限 | `OSError` | chat 报错 + 让 PM 处理 |

所有失败必须 fail-loud，不静默吞。
