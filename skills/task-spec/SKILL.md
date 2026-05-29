---
name: pmai-task-spec
description: |
  build 阶段后台环节：按 task-plan.md 为单个 task 后台自动生成单文件 typed contract（$PMAI_HOME/templates/task.md.tmpl）——
  作为 AI build 前的内部执行依据，读 req-plan.md（范围清单 WHAT + 决策页 WHY）。
  范围已在范围确认阶段拍板，所以本环节 PM 不手敲、不过确认门；生成后续跑 /pmai-task-confirm 准备 worktree。
  由 /pmai-next 在 build 阶段编排调用；PM 也可手动调作异常恢复入口（窗口丢失 / 想重新生成）。
---

# /pmai-task-spec

## When To Use

- build 阶段由 `/pmai-next` 编排调用，参数是 task id（如 `/pmai-task-spec task-001`）：为 task-plan.md 里的单行 task 后台生成内部执行依据
- 用于从 `task-plan.md` 中的单行 task 生成完整的 `tasks/task-NNN-<slug>.md`（单文件 typed contract）
- **异常恢复入口**：窗口被关 / context 丢失 / 想重新生成某个 task 文件时，PM 手动调

## 这是 build 阶段的后台环节（不是 PM 确认点）

范围 / 关键决策已在**范围确认阶段**（`req-plan.md` 范围清单 + 决策页）由 PM 拍板。本环节只是把 PM 已拍板的范围
**机器降为单个 task 的内部执行依据**——PM 不手敲、不逐行确认。生成完直接续跑 `/pmai-task-confirm` 准备 task 执行环境。

- **PM 确认门失效**：旧流程在生成后停下让 PM 审 task 文件再确认；现在范围②已确认，这道门取消，生成后台跑、直接续跑。
- **唯一 PM 拍板点在别处**：build 完三道审 + 体验迭代后的呈交闸门（pass / 打回）才是 PM 验收方向的地方，不在本环节。
- **异常恢复时**：PM 手动调本 skill 重新生成 task 文件后，仍是后台续跑 task-confirm，不插额外确认门。

## 单文件 typed contract

task-spec 产 **1 个物理文件** `tasks/task-NNN-<slug>.md`（不再产 `.engineering.md`）。
文件头部带 `<!-- task_format: single-typed-v3 -->` 标记，内部分三区：

| 区 | 含哪些段 | lint |
|---|---|---|
| **PM 确认区** | 任务卡（含 executor/model）/ task 级范围 / task 级验收清单 / PM 反馈承接清单 | `check-doc-pm-view.py` scoped 模式（只校验本区，守 PM-view 写作纪律）|
| **执行区** | 启动前必读 / 实现规格 / 工程 HOW 草拟（AI 后台写）/ 约束与易错 / 自测说明 / 工程层验收 / 状态转换说明 | 字段格式校验；允许工程内容 |
| **审计区** | 文档偏差 / 自审记录 / 历史档案 | 不 lint |

> 「PM 确认区」是模板里的物理分区名（按 `task.md.tmpl` region 标记），不代表本环节有 PM 确认门。
> 范围已在范围确认阶段拍板，本环节后台把该区内容按 req-plan 范围切片写好即可，PM 不逐行过门。

## PM 视图规则

PM 确认区遵守 `skills/_shared/PM-VIEW-RULES.md`（写作纪律：明确指代 / 正向描述 /
禁工程词 / 禁像素颜色 / 禁反向约束）。执行区允许所有工程内容，不跑 PM-view lint。
- `_shared/pm-view/writing-rules.md`（写作规则）—— 只约束 PM 确认区
- `_shared/pm-view/section-order.md`（章节顺序，按 `task.md.tmpl`）

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: task-spec"
```

## Required Inputs

| 输入 | 用途 |
|---|---|
| `task-plan.md` | task 元数据 + 全 task 视图（build 阶段范围清单拆出的 task）|
| `req-plan.md` | 范围确认阶段拍板的真相源 —— **范围清单（WHAT）** 挑当前 task 切片转写进执行区·实现规格 + PM 确认区·验收；**决策页（WHY）** 提供本 task 实现要遵守的关键产品决策 |
| `req-plan.md` 名词 | **本 req 临时词典** —— 写 task 内容时按本 req 引入的新业务实体 / 角色精确指代，禁同义词漂移 |
| `docs/PRODUCT-STATE.md` / `docs/DESIGN.md` / `docs/modules/` | 产品脊柱背景（产品现状 / 设计约定 / 模块现状）|
| `docs/PRODUCT-STATE.md ## 业务术语表`（若有）| **长期词典**（跨 req 已沉淀的稳定业务术语）—— 跟 req-plan 名词同时读：PRODUCT-STATE 是沉淀基线，req-plan 名词是本 req 新引入的临时词；两者并集 = 写 task 内容时的术语词典 |
| `docs/PRODUCT-RULES.md` | 跨功能产品行为规则 —— 读全部 `scope=全局` 规则 + 按当前 task 模块 / 功能关键词 grep 命中的 `scope=域限定` 规则（章节-grep；`scope=全局` 永远纳入、不漏跨功能规则）。命中的规则写进执行区·约束与易错 |
| 前序「已完成」task 的「PM 反馈」段 | same-req 反馈 lane（relevance 二分）|

> **工程 HOW 不再有独立上游文档**：组件怎么拆 / 状态怎么管 / mock 数据结构 / 调用怎么 mock 等工程 HOW
> **由本环节 AI 后台自己拟**，写进执行区·「工程 HOW 草拟」段，PM 不逐行确认。旧的独立工程设计文档已砍。

特别遵守 `input-flow.md` 章节匹配强约束（按章节 grep 局部读，不整文件 Read 大文件）。

## Workflow

### attachments AI 接管 hook（trigger 0 — 任何步骤期间生效）

PM 在 chat 描述 "我有 X 在 ~/Downloads/foo.pdf，重点 Y" → AI first-principle 识别 → 调 helper：

```python
from _lib.attachments import copy_attachment
result = copy_attachment(req_dir, Path("~/Downloads/foo.pdf"),
                        stage_prefix=f"task-{short_id}",  # 当前 task short_id，如 task-001
                        hint="Y 重点")
```

stage_prefix 按 task short_id（`task-001` / `task-042` 等）。chat 一行确认 `已归档（attachments/task-001-foo.pdf），Y 重点。继续。`（禁工程黑话）。

异常：`FileNotFoundError` / `SensitivePathError` / `FileSizeError` 三类 catch + chat 报错（fail-loud）。

**trigger 2 fallback**：写 task-NNN.md 前扫 `attachments/`，`is_seen(req_dir, filename)` 判定。

**引用 section 渲染**：写 task-NNN.md 时 `list_attachments_seen(req_dir)` 按 `registered_at` 升序渲染到文档物理末尾 `## 📎 参考材料` section。

**单一真相源**：`skills/_shared/pm-view/attachments-upload.md`。

### 步骤 1：校验 task-plan.md ↔ tasks/ 一致性

读 `$ACTIVE_REQ_DIR/task-plan.md` 的 task id 列表，扫 `$ACTIVE_REQ_DIR/tasks/task-NNN-*.md`。

校验差异：
- `task-plan.md` 有、`tasks/` 没有：提示这些 task 尚未生成内部执行依据。
- `tasks/` 有、`task-plan.md` 没有：提示这些 task 文件已脱离范围清单。

发现差异时先暂停，要求 PM 选择处理路径。

### 步骤 2：读取 task 元数据

从 `task-plan.md` 定位参数指定的 `<task-id>`，提取：id / 标题 / 所属模块 / 所属模块章节 /
summary / 依赖。找不到 → 停止并提示 PM 先修正 `task-plan.md`。

### 步骤 2.5：产品脊柱文档强制 echo（不依赖 LLM 自觉 Read）

prose 警告「AI 不得以'觉得不必要'为由跳过」是无效防御。Bash `cat` 把基础必读全文 echo 进 transcript：

```bash
SOURCES=(
  "$ACTIVE_REQ_DIR/task-plan.md"            # task 元数据 + 全 task 视图
  "$ACTIVE_REQ_DIR/req-plan.md"             # 范围确认拍板的范围清单 + 决策页（本 req 真相源）
  "$REPO_ROOT/docs/PRODUCT-STATE.md"        # 产品现状 + 业务术语表（长期词典）
  "$REPO_ROOT/docs/PRODUCT-RULES.md"        # 跨功能产品行为规则，全文读取 scope=全局 规则
  "$REPO_ROOT/docs/modules/INDEX.md"        # 模块索引（定位涉及模块主功能规格文件）
)

for f in "${SOURCES[@]}"; do
  if [ -f "$f" ]; then
    echo "════════════════════════════════════════════════════════════════"
    echo "FORCE READ: $f"
    echo "════════════════════════════════════════════════════════════════"
    cat "$f"
    echo "════════════════════════════════════════════════════════════════"
    echo "END $f"
    echo "════════════════════════════════════════════════════════════════"
  else
    echo "ℹ️  $f 不存在，跳过"
  fi
done
```

**不在 echo 范围**（按 `input-flow.md` 章节-grep 切片读，避免大文件污染 context）：
- `req-plan.md` 范围清单细项：按"所属模块 / 功能 / task 标题关键词"匹配范围清单相关条目 grep 局部读（决策页通常较短，上面已全文 echo）
- `docs/DESIGN.md` / 涉及模块 spec：按需 grep 局部读
- `docs/PRODUCT-RULES.md` 的 `scope=域限定` 规则：按当前 task 模块 / 功能关键词 grep 命中后局部读（`scope=全局` 段在上面 echo 时已全文读取）
- 前序「已完成」task 的「PM 反馈」段：grep `^### 反馈` / `^## .*PM 反馈` 命中行后局部读

### 步骤 3：消化已 echo 输入 + 按既有强约束读 slice-read 项

步骤 2.5 已把 task-plan / req-plan / PRODUCT-STATE / PRODUCT-RULES / modules/INDEX 全文 echo 进 transcript。本步骤补：
- `req-plan.md` 范围清单是 WHAT（范围确认拍板的「有什么 / 做不做」）；决策页是 WHY（关键产品决策）。两者分工：实现规格从范围清单切片转写，实现要遵守的产品决策从决策页挑。
- 工程 HOW（怎么实现）不来自上游文档——由本环节 AI 后台按 DESIGN.md 约定 + 现有原型代码自己拟，写进执行区·「工程 HOW 草拟」段。

### 步骤 4：基础设施 task 走简化路径

`所属模块` 为 `基础设施` 时：`所属模块章节` 留空；执行区·实现规格填可执行的脚手架要求；
PM 确认区·验收清单必须填可验证条件；告知 PM「本 task 不触发 module 规格 merge」。

### 步骤 5：收集前序 PM 反馈，按 relevance 二分

扫前序「已完成」task 文件的「PM 反馈」段（按 `input-flow.md`：grep `^### 反馈`
/ `^## .*PM 反馈` 命中行后局部读，**不整文件 Read**）。同 req 内 + closed/ 下旧 task 都扫。

每条反馈按 **relevance 二分**（不是三类 sentiment 分流 —— 单文件后投递地址只有一个）：

| relevance | 判别 | 处理 |
|---|---|---|
| **适用当前 task** | 反馈涉及的模块 / 功能落在当前 task 范围内 | 写进执行区·约束与易错段（标来源 task）|
| **不适用** | 反馈涉及别的模块 / 功能 | 留在原 task 文件不动 |

relevance 具体可判（模块 / 功能是否落在当前 task 范围），不需解读语气。

**每条反馈都写进 PM 确认区·「PM 反馈承接清单」**（一行：来源 task / 原文摘要 /
relevance / 处理结果 / 一句理由）—— 让「不适用」可被事后查到、可纠误判。无前序反馈 →
写「无前序 PM 反馈」。

> **跨模块反馈 = 已知 gap**：属「全项目跨功能产品行为规则」的反馈，relevance 二分装不下 ——
> 由 close-task 把它沉淀到 `docs/PRODUCT-RULES.md`；task-spec 不在此处理。

### 步骤 6：从 req-plan.md 范围清单挑切片 + 决策页挑相关决策

**`req-plan.md` 范围清单（WHAT）**：按"所属模块 / 功能 / task 标题关键词"匹配范围清单的相关条目
（`input-flow.md` 章节 grep 局部读）。挑出当前 task 切片：
- 范围清单里当前 task 该交付的页面 / 字段 / 按钮 / tab / 状态 / 交互 → 转写为执行区·实现规格（task 级可执行规格）
- 范围清单里当前 task 的验收信号 / 「做不做」边界 → 转写为 PM 确认区·task 级验收清单（含明确划出去的「不做什么」）

**`req-plan.md` 决策页（WHY）**：挑出影响当前 task 实现的关键产品决策（跨 task 共享口径 / 权限语义 / 业务规则），
写进执行区·约束与易错段（标来源决策），让 executor 按 PM 拍板的口径实现，不从 mock 随手反推规则。

**工程 HOW 草拟（AI 后台）**：组件怎么拆 / 状态怎么管 / mock 数据结构 / 调用怎么 mock 等，
本环节 AI 按 DESIGN.md 约定 + 现有原型代码自己拟，写进执行区·「工程 HOW 草拟」段。
task-execute 只读 task 单文件、不跨文件回查，所以工程 HOW 必须在此拟全。这是 AI 后台产物，PM 不逐行确认。

**只引用、转写，不大段复制原文**。

### 步骤 7：派生 task-scoped 自测说明 + 占位值（UI task 必做，非 UI task 跳过）

task-spec 从 `req-plan.md` 范围清单的验收信号派生 **task-scoped 自测说明**写进执行区·自测说明段
（让 task 文件对 task-verify 自包含）：
- 每个 task 涉及的页面路径 → 1 条主路径流程（"打开 /X → 期望 ..."）
- 自动追加冷启动 smoke 作为最后一条流程
- 非 UI task → 自测说明段填「无（[类型] task）」

如本 task 含 UI 占位词，把 task-scoped 占位值表内联进执行区·「工程 HOW 草拟」段
（executor 不跨文件回查原型节）。

### 步骤 8：写单文件 typed contract（三区）

按 `$PMAI_HOME/templates/task.md.tmpl` 生成 `$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md`。

**模板替换**：`{{TASK_NUMBER}}` / `{{TASK_NAME}}` / `{{TASK_SLUG}}` / `{{REVIEW_TOOLS}}` /
`{{CREATED_DATE}}` / `{{REQ_ID}}` / `{{REQ_SLUG}}`；保留 `<!-- task_format: single-typed-v3 -->`
标记 + 三区 region 标记。

**三区写作约束**：
- **PM 确认区**（任务卡 / 范围 / 验收清单 / PM 反馈承接清单）：守 PM-view 写作纪律 ——
  每个名词带完整指代前缀；不出现像素 / 颜色 / Emoji 视觉；不出现反向约束；不出现工程词。
  （这是写作纪律，不代表 PM 在本环节过门——范围已在范围确认阶段拍板。）
- **执行区**（实现规格 / 工程 HOW 草拟 / 约束与易错 / 自测说明 / 工程层验收 / 启动前必读 /
  文件范围（机器校验）/ 状态转换说明）：允许所有工程内容（TS 类型 / 字段名 / 像素 / 颜色 / 反向约束）。
  `## 🗂️ 文件范围（机器校验）` 必须填仓根相对路径或 glob，供 executor fail-closed 校验；
  没有新建/修改/禁止项时对应行写「无」，不要留占位说明。
- **审计区**（文档偏差 / 自审记录 / 历史档案）：保留模板骨架，executor 执行期填。
  ⚠️ **「文档偏差」「自审记录」两 section 必须保留** —— `task-transition.py`「执行中→已完成」
  gate 读它们。

**写头部前必查**（错一项步骤 9 字段校验会拦截重写）：
- [ ] 标题 `# Task NNN: ...` 下方只有 `<!-- task_format -->` 标记，**无** frontmatter 段
- [ ] 状态字段在 `## 📌 任务卡` 表格里（`| **状态** | 待执行 |`）
- [ ] 状态值是 4 态之一：待执行 / 执行中 / 已完成 / 已废弃
- [ ] 不用中文引号（`「」`）包字段；依赖列表是结构化 `- task-NNN (说明)`

### 步骤 9：自检 + lint + 字段校验

#### 9.A 机器抓不到的语义判断（必查 —— 只针对 PM 确认区）

- [ ] PM 确认区每个名词带完整指代前缀；抽象动词搭配具体效果
- [ ] task 级范围 / 验收能独立判 scope（不依赖执行区内容）
- [ ] PM 反馈承接清单每条 relevance 判定正确（模块 / 功能确实落在 / 不落在 task 范围）

#### 9.B 执行区完整性（必查）

- [ ] 实现规格覆盖 req-plan 范围清单切片的所有交付项；工程 HOW 草拟拟全本 task 的实现要点
- [ ] 文件范围（机器校验）已列出本 task 允许新建/修改的仓根相对路径或 glob；不允许 executor 写的路径列入「不动」
- [ ] 文档偏差 / 自审记录两 section 骨架在（gate 锚点）

#### 9.C scoped PM-view lint（机器兜底）

```bash
python3 "$PMAI_HOME/scripts/check-doc-pm-view.py" \
  "$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md"
```

scoped 模式只校验 PM 确认区（执行区 / 审计区允许工程内容、自动跳过）。处理输出：
- 0 errors + 0 warnings → 进步骤 10
- 有 warnings → 每条**显式判定**（要么修，要么记一句理由）；禁止默默 ack
- 有 errors → 回步骤 8 重写违规章节，再重跑；连续 3 次仍有 error 停下询问 PM

#### 9.D 字段校验（防假执行产物）

```bash
python3 "$PMAI_HOME/scripts/task-transition.py" \
  "$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md" --validate-fields-only
```

退出 1 → 按 stderr 回步骤 8 重写 task 文件头部（任务卡表格 `| **状态** | 待执行 |`、
无 frontmatter 段、状态值合法），再回步骤 9 全跑一遍。

### 步骤 10：后台落盘 + 续跑 /pmai-task-confirm（不停 PM）

> **本环节不设 PM 确认门**：范围 / 决策已在范围确认阶段（`req-plan.md`）由 PM 拍板。
> task 文件是 build 阶段的内部执行依据，自检 + lint + 字段校验通过即后台落盘，不停下让 PM 审。
> PM 验收方向的唯一拍板点在 build 完三道审 + 体验迭代后的呈交闸门。

自检通过后，把 task 文件 commit 到 req 分支（保证 task-confirm fork 时取到终态，
非 working tree stale 版本）：

```bash
source "$PMAI_HOME/scripts/_lib/dirty-check.sh"
TASK_FILE="$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md"
auto_commit_docs "$REQ_WORKTREE" "task-NNN-<slug>: spec sealed" "$TASK_FILE"
```

`auto_commit_docs` 在文件与 HEAD 一致时静默 noop；pathspec 严格限定本 task 单文件，
不卷入其他 working tree 改动。commit 失败 → 不推 task-confirm，把错误原文给 PM（异常恢复）。

**续跑 task-confirm**：commit 成功后**不让 PM 手动贴 `/pmai-task-confirm <path>`**。
AI chat 出一行轻量过场，然后直接续跑 `/pmai-task-confirm` 的 workflow（同一 chat 内 Read
`skills/task-confirm/SKILL.md` 按其 step 1-N 执行；不 fork 新窗口、不要求 PM 重敲命令）：

```
✅ task 内部执行依据已就绪，准备 task 执行环境（worktree fork + 启动指令）...
```

接着按 task-confirm SKILL 跑（PM 体感 = build 推进时直接看到 worktree 路径 + Next Up 新窗口命令，不再多一道手敲命令）。

> **为什么续跑而非停下确认**：task 文件是 build 阶段的内部执行依据，范围已在范围确认拍板；
> task-confirm 自身也不设确认门。这两道旧确认仪式都已机器降为后台续跑。
>
> **退出条件**：task-confirm workflow 跑完（worktree 已 fork + Next Up 已输出）→ chat 自然停在
> "去新窗口跑 /pmai-task-execute" 的引导上，不进 task 执行（task 执行天然在新窗口里 PM 重新触发）。
>
> **失败兜底（异常恢复）**：commit 失败 / task-confirm 内部任一步骤报错 → 把错误原文给 PM，
> **不**继续续跑；PM 修复后可手动调 `/pmai-task-confirm <path>`。

### 步骤 11：binding-contract 纪律（后台改写也守）

task 文件后台落盘后，本环节对 PM 已拍板内容仍守不篡改纪律：

- **PM 在范围确认拍板的范围 / 决策**：本环节只能转写、切片，**不得加码或删改** PM 已拍板的范围。
  实现规格 / 验收清单必须忠实于 `req-plan.md` 范围清单 + 决策页，AI"代码合法 / 风格统一"压力不能凌驾 PM 拍板。
- **重新生成时**（异常恢复 PM 重调本 skill）：按同一份 `req-plan.md` 重新切片，不夹带 PM 没拍板的新范围。

## Rules

- 一次只生成一个 task 的**一个文件**（单文件 typed contract）；不支持批量生成。
- 不再产 `.engineering.md`；不写 hash 注释 / reconcile 元数据（单文件无第二份可同步）。
- 不编辑其他 task 文件；不创建 / 修改 `docs/modules/*.md`；不修改 `task-plan.md`。
- 不复制 req-plan.md 大段原文，只引用 + 转写为 task 级可验收内容。
- **本环节不设 PM 确认门**：范围已在范围确认阶段拍板；task 文件后台落盘后直接续跑 `/pmai-task-confirm`。
- 工程 HOW 由本环节 AI 后台拟（无独立上游工程文档），PM 不逐行确认。
- 基础设施 task 必须说明：`本 task 不触发 module 规格 merge`。
- AI 不得自动调任何 review skill；review 是 build 完三道审 + 体验迭代阶段的事，不在本环节。
- **relevance 二分强制**：前序 PM 反馈按 relevance（适用 / 不适用）二分；每条都登记进 PM 反馈承接清单。
- **跳过产品脊柱"必读"被禁止**：PRODUCT-STATE / DESIGN / req-plan / modules 存在则必读。
- **binding-contract 纪律保留**：删的是双文件 hash 同步机器，不是删「PM 在范围确认拍板的范围 AI 不得加码或删改」。
- **单文件模板必须保留「文档偏差」「自审记录」section**：否则 `task-transition.py`
  「执行中→已完成」gate 失锚点、对所有新 task 必败。
- **强制落盘**：步骤 10 必须 commit task 文件到 req 分支再续跑 task-confirm。

## 文档结构

三区结构 + 章节顺序的单一真相源 = `$PMAI_HOME/templates/task.md.tmpl`（含每段填写
规则注释）。本 skill 不在内部复制章节定义。章节顺序另见
`_shared/pm-view/section-order.md`。
