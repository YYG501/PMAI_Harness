---
name: doc-update
description: Use when task 已完成、PM 已通过验收、需要在 close-task 合并前处理文档偏差或把 task 功能清单沉淀进模块规格。
---

# Doc Update — 文档偏差修复 / 模块规格沉淀

## When To Use

`/doc-update` 支持两种调用模式：

1. **对账模式（reconciliation mode）**：task 文件的偏差记录有内容（不是"无偏差"），需要在合并前更新原始文档。偏差记录跨两处：PM 视图主文件 `## 📁 历史档案` + 工程合同 `## 10. 文档偏差` 表。
2. **沉淀模式（settlement mode）**：由 `/close-task` 在 task 验收通过后调用，把 PM 视图 task 的「📋 功能清单」增量沉淀进 `docs/modules/<module>.md`。

## 拆两文件约定（必读）

本 skill 处理拆两文件的 task 产物（PM-VIEW-RULES §二）：
- **PM 视图主文件**（`.md`）：「📋 功能清单」/「📁 历史档案」/「📌 任务卡」中的 `**所属模块**` `**所属模块章节**` 字段
- **工程合同**（`.engineering.md`）：「§10 文档偏差」/「§4 功能清单工程版」/「§1 元信息扩展」

**沉淀模式**只读 **PM 视图主文件**的「📋 功能清单」沉淀进 module spec。**禁止**把工程合同 §4 功能清单工程版（含字段名 / props / reducer action 等工程层细节）沉淀进 `docs/modules/<module>.md`——这些细节只在 task 工程合同内保留。

**对账模式**：跨两文件读取偏差记录（PM 视图历史档案 + 工程合同 §10），分别对账到对应原始文档。

## Required Inputs

1. task PM 视图主文件路径（PM 调用时传入的）。
2. **必须存在的成对工程合同**：`<task-stem>.engineering.md`，缺则报错并 `exit 1`。
3. 对账模式：偏差涉及的原始文档（docs/solution.md、docs/DESIGN.md、docs/modules/*.md 等）。
4. 沉淀模式：从 PM 视图主文件读取 `**所属模块**` / `**所属模块章节**` 字段（在「📌 任务卡」表格中）+ `## 📋 功能清单` section。

## Workflow

### 步骤 1：读取 task 两文件

1. 工程合同存在性校验（兼容旧格式）：
   ```bash
   ENG_FILE="${TASK_FILE%.md}.engineering.md"
   if [ ! -f "$ENG_FILE" ]; then
     echo "⚠️  工程合同缺失（旧格式 task，按单文件兼容模式继续）：$ENG_FILE"
     HAS_ENG=false
   else
     HAS_ENG=true
   fi
   ```

   - `HAS_ENG=false`：兼容模式——偏差检查只读主文件 `## 文档偏差` section；沉淀模式从主文件 `**所属模块：**` `**所属模块章节：**` 头部字段（旧版用 `：**` 不是表格）+ `## 功能清单` section

2. 从 **PM 视图主文件**读取：
   - 「📌 任务卡」表格中的 `**所属模块**` / `**所属模块章节**` 字段
   - `## 📋 功能清单` section（沉淀模式用）
   - `## 📁 历史档案` 中的偏差记录（对账模式用，PM 走查时记录的偏差）

3. 从 **工程合同**读取：
   - `## 10. 文档偏差` 表（对账模式用，agent 在执行中发现的工程层偏差）

4. 如果 `**所属模块**` = `基础设施`，按 Q1 + Q4 boundary table 判定为基础设施 task：跳过模块规格沉淀，返回 success。输出：

   ```text
   基础设施 task：跳过 docs/modules 沉淀，继续 close-task。
   ```

### 步骤 1.5：判断是否涉及模块规格功能清单（对账模式保留）

跨两处偏差源检查是否有指向 `docs/modules/<module>.md` 功能清单表格的偏差：
- PM 视图主文件「📁 历史档案」中的偏差记录
- 工程合同 §10 文档偏差表

- **有模块规格偏差**：进入步骤 1.6
- **无模块规格偏差**：跳到步骤 2

### 步骤 1.6：模块规格对账（对账模式保留）

A. 读取偏差涉及的模块规格全文（`docs/modules/<module>.md`）
B. 读取最终实现的代码（task worktree 的关键文件）
C. 对照功能清单表格，逐行核对实际实现是否匹配
D. 生成修改方案（行级别精确操作）：
   - 功能清单表格的行级更新（修改需求描述以匹配最终实现）
   - 实现指引 section 的更新（组件选择、状态处理变化）
   - 新增行（PM 迭代中追加的功能点）
   - 删除行（PM 确认不做的功能点）
E. 向 PM 展示对账结果，逐条确认后执行

对账仍遵循最小修改原则：只改偏差涉及的行和 section，不重写整个模块规格。

### 步骤 1.7：模块规格沉淀（settlement mode）

沉淀模式由 `/close-task` 在 task acceptance 后调用；它不要求「文档偏差」section 有内容。

#### 1.7.1 复合 key 匹配

每条功能用 composite key 匹配（**只读 PM 视图主文件**，不读工程合同）：

- `belonging module chapter`：取自 PM 视图主文件「📌 任务卡」表格的 `**所属模块章节**` 字段
- `level-3 feature name`：取自 PM 视图 `## 📋 功能清单` 内 section header `### N · 功能名`
- 在 module spec 中定位 `### [module chapter]`，再查找其下 `#### N · [feature name]`

跨模块 task 的 `**所属模块章节**` 必须使用 `模块A:章节X, 模块B:章节Y` 格式。沉淀时按每个 `模块:章节` 组合分别匹配对应 `docs/modules/<module>.md`。

**禁止**沉淀工程合同 §4 功能清单工程版（含字段名 / props / reducer action 等工程层细节）——这些只在 task 工程合同内保留，不进入 module spec。

#### 1.7.2 四种情况处理逻辑

逐条比较 task 功能清单与 module 规格：

| 情况 | 处理 |
|------|------|
| Item in task list but NOT in module spec | **ADD**：静默执行，PM 已在 task acceptance 中确认；完成后输出 summary line |
| Content identical | **SKIP**：不写入 |
| Content different | **MODIFY**：展示 diff，PM confirms each item 后再修改 |
| Item in module spec but NOT in task list | **LEAVE UNCHANGED**：保留，不删除 |

ADD/SKIP/LEAVE UNCHANGED 不打断 PM；只有 MODIFY 需要展示 diff 并逐条确认。

#### 1.7.3 多模块 atomic merge（A3）

多模块任务必须用 git temp branch 收集所有 module merges，避免留下部分成功状态：

1. 记录当前 req 分支名和 HEAD。
2. Create temp branch：从当前 req 分支创建临时分支，例如 `doc-update-settle/<task-id>-<timestamp>`。
3. Merge each module one by one：在临时分支上逐个写入对应 `docs/modules/<module>.md`，每个模块独立完成 ADD/SKIP/MODIFY/LEAVE UNCHANGED。
4. Any failure → delete temp branch → block close-task + error report；当前 req 分支保持原 HEAD，不留下中间写入状态。
5. All success → 将当前 req 分支 fast-forward 到临时分支结果（把 temp branch 的完整沉淀结果落回 current branch）→ delete temp branch。

#### 1.7.4 Summary line + diff link（DX RU4）

沉淀完成后必须输出一行摘要，包含新增数量、目标文件和 diff 入口：

```text
已沉淀 N 条新增进 docs/modules/<module>.md (查看 diff: git diff HEAD~1 -- docs/modules/<module>.md)
```

如果涉及多个模块，逐个模块输出 summary line。

### 步骤 2：读取原文（对账模式）

对每条偏差，读取对应文档的原文上下文（前后各 5 行），理解：

- 原文的语言风格（中文/英文、正式/口语、用词习惯）
- 原文的格式（markdown 表格、列表、段落）
- 原文的信息密度（简洁还是详细）

### 步骤 3：生成修改方案（对账模式）

对每条偏差生成精确的 Edit 操作，向 PM 展示：

```text
文档修改方案（共 N 处）

修改 1/N:
  文件: docs/solution.md
  行号: 592
  原文: "用户列表显示 10 个字段（姓名、邮箱、角色...）"
  改为: "用户列表显示 8 个字段（姓名、邮箱、角色...，移除了 X 和 Y）"
  原因: [来自文档偏差记录]

PM 请逐条确认：全部通过 / 逐条批注 / 全部驳回
```

### 步骤 4：等 PM 确认（对账模式）

- PM 说“全部通过” → 执行所有修改。
- PM 对某条有意见 → 按 PM 意见调整后重新展示。
- PM 说“不改” → 跳过该偏差；若沉淀模式仍需执行，不得跳过沉淀。

### 步骤 5：执行修改

执行对账模式或沉淀模式的已确认修改：

- 对账模式：用 Edit 工具逐条修改（不用 Write），只改偏差涉及的具体行。
- 沉淀模式：按 1.7 的复合 key 和 atomic merge 规则更新 `docs/modules/*.md`。

### 步骤 6：完成

修改完成后返回给 orchestrator，允许继续运行 `close-task.sh` 的后续 merge / cleanup。

## Failure Handling（DB2）

ALL failures block close-task。失败时必须停止并返回错误报告；PM 修复 underlying issue 后，重新运行 `/close-task`，`/close-task` 会 auto-resumes doc-update，从上次失败的 task 重新执行沉淀/对账。

错误信息必须包含：

- `文件`：具体失败文件，例如 `docs/modules/account.md`
- `failure type`：只能使用 `write-file` / `content-conflict` / `key-match-failure` / `internal-bug`
- `recovery path`：PM 需要怎么修，例如“修正 task 的 **所属模块章节：** 后重跑 /close-task”或“手动解决 module spec 冲突后重跑 /close-task”

推荐格式：

```text
doc-update failed; close-task blocked
文件: docs/modules/account.md
failure type: key-match-failure
recovery path: 修正 task.md 的 **所属模块章节：** 或 module spec 的 ### 章节标题后，重新运行 /close-task；系统会自动续跑 doc-update。
```

## Rules

**最小修改原则（强制）：**

- 只改偏差记录或 task 功能清单沉淀涉及的内容，不改任何其他部分。
- 对账模式用 Edit 工具的 old_string → new_string，精确替换。
- 沉淀模式只在目标 module chapter 下 ADD/MODIFY 匹配的三级功能块。
- old_string 必须从文档中实际读取，不能凭记忆。

**风格一致原则（强制）：**

- 读取原文前后 5 行，匹配语言风格。
- 原文用中文 → 修改用中文；原文用英文 → 修改用英文。
- 原文是表格 → 修改在表格内；原文是段落 → 修改在段落内。
- 不引入原文没有的格式。

**禁止：**

- 不重写整个 section。
- 不“顺手”优化文档其他部分。
- 不改排版、不加注释。
- 不修改 docs/ 以外的文件。
- 沉淀失败时不得继续 close-task。
