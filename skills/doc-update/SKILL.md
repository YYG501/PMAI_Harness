---
name: pmai-doc-update
description: Use when task 已完成、PM 已通过验收、需要在 close-task 合并前处理文档偏差或把 task 功能清单沉淀进模块规格。
---

# Doc Update — 文档偏差修复 / 模块规格沉淀

## When To Use

`/pmai-doc-update` 支持两种调用模式：

1. **对账模式（reconciliation mode）**：task 文件的偏差记录有内容（不是"无偏差"），需要在合并前更新原始文档。偏差记录跨两处：PM 视图主文件 `## 📁 历史档案` + 工程合同 `## 10. 文档偏差` 表。
2. **沉淀模式（settlement mode）**：由 `/pmai-close-task` 在 task 验收通过后调用，把 PM 视图 task 的「📋 功能清单」增量沉淀进 `docs/modules/<module>.md`。

## task 文件读取约定（必读）

本 skill 读 task 文件的偏差记录 / 模块字段：

- **v3 单文件 typed contract**：task 是一个物理文件 `task-NNN-<slug>.md`，三区由 region 标记界定——
  - PM 确认区「📌 任务卡」：`**所属模块**` / `**所属模块章节**` 字段
  - 审计区「📋 文档偏差」表：**单一一处**偏差记录（文档偏差 / 业务偏差合并）；指向任意 prd / implementation-design / module / DESIGN / PROJECT 等文档
- **v2 旧双文件 task**（在飞旧 task）：PM 视图主文件（`.md`）含「📋 功能清单」/「📁 历史档案 → 业务层偏差」/「📌 任务卡」模块字段；工程合同（`.engineering.md`）含「§10 文档偏差」/「§4 功能清单工程版」/「§1 元信息扩展」。
- **v1 旧单文件**：偏差在主文件「## 文档偏差」section；模块字段是 `**所属模块：**` 头部字段。

**对账模式**：
- v3 —— 偏差记录只在审计区「📋 文档偏差」一处读取，分别对账到各偏差指向的原始文档。
- v2 —— 跨两文件读取偏差记录（PM 视图「📁 历史档案 → 业务层偏差」+ 工程合同 §10）。

**沉淀模式（已是死路径，见步骤 0.5）**：历史上只读 PM 视图「📋 功能清单」沉淀进 module spec。v3 task 无独立「📋 功能清单」section（功能清单已移 prd.md），沉淀模式不再被 close-task 触发。

## Required Inputs

按 `_shared/pm-view/input-flow.md` 中 **Stage 7.2 doc-update** 段执行：

1. 🟢 task 文件（PM 调用时传入）—— v3 单文件 typed contract；v2 旧 task 为 PM 视图主文件 + 成对工程合同
2. 🟢 `docs/modules/<本 task 模块>.md`（对账目标）
3. 🟢 task 文件偏差表 —— v3：审计区「📋 文档偏差」；v2：工程合同 §10 + PM 视图「📁 历史档案 → 业务层偏差」
4. 🟢 **task worktree 改动代码**（步骤 1.6 模块规格对账，逐行核对实际实现是否匹配——不读代码就不能对账；读法同 Stage 7.1 close-task：≤3 文件全读，多文件分批）
5. 🟡 偏差涉及的原文（前后 5 行）。**支持任何 req / 项目级文档**：
   - 项目级：`docs/PROJECT.md` / `docs/DESIGN.md` / `docs/modules/INDEX.md` / `docs/modules/*.md` / `CLAUDE.md`
   - req 级：**stage 2 真相源**（A 分支 `requirements/active/<req>/analysis.md` / B 分支 `requirements/active/<req>/stage2-office-hours.md`，路径由 `_lib.state.get_stage_source(req_dir, 2)` 解析）/ `prd.md` / `implementation-design.md`（在飞旧 req 若仅有 `solution.md` / `solution.engineering.md` 则按旧文件名读）

## 位置定位原则（必读）

doc-update 涉及的长期文档（`docs/modules/*.md` / `prd.md` / `docs/DESIGN.md` / `docs/PROJECT.md`）通常几千行。**建议优先走"多重 grep + 章节级局部读"**——保险性 ≥ 全读，且系统化、可重复；不到必要时不 Read 全文。

**为什么不读全文更保险**：
- grep 系统化：关键字命中 = 100% 不漏
- AI 全文注意力扫描概率化：几千行长文上漏看是真实风险
- 几千行 token 中只有改动位置周边 ±50 行真正进入起草决策，其余 99% 是被读但没用的 token

**唯一例外**：步骤 8 rewrite mode 整段重写场景。

### A. 找位置（保险机制）

#### A.1 反转 task：5 重 grep

被反转的决策（如 `D15` / `行展开 ▸/▾`）通常已被多处长期文档沉淀过。从 task PM 视图主文件 §🎯 关键产品决策 / §业务层偏差 提取关键字后，跑 5 套 grep：

1. **D 项编号**：`grep -rn 'D15\|D19' requirements/active/<req>/ docs/`
2. **章节锚点**：`grep -rn '§1A\|§3\.8\|§5\.3' requirements/active/<req>/ docs/`
3. **反转术语**：`grep -rn '行展开\|▸/▾' requirements/active/<req>/ docs/`
4. **同义词**（task md §业务层偏差表里 PM 写的术语）：按表逐个 grep
5. **章节级扫描兜底**：每个目标长期文档跑 `grep -n '^### \|^#### '` 列章节目录，肉眼复核有无可疑命中

→ 5 套结果合并去重 → 位置清单（每条含 `file:line` + 章节锚点）

#### A.2 沉淀模式（非反转 / 增量沉淀）

task md §所属模块章节字段直接给章节锚点：

```bash
grep -n '^### <module chapter>' docs/modules/<module>.md
```

一击即中，连多重都不用。

### B. 起草改动：Read 章节级局部范围

定位到每处命中后，Read 命中所在的章节级范围（章节标题行 → 下一个同级标题前）：

```bash
# 例：grep 定位到 §3.8 在 line 301，下一个 ^### 在 line 350
# Read line 301-349
```

通常每处 30-100 行。**避免以"看周边上下文"为名 Read 全文**——章节范围已经包含起草所需的全部上下文（原文风格 / 段落完整性 / 字段口径）；除非你判断本次确实需要跨章节才能起草，否则不读全文。

### C. 失败兜底

如果 5 重 grep 都没命中但 task md 明示某文档需要改 → 报错并停下，让 PM 决定：
- 是 task md 关键字遗漏（PM 补关键字后重试）
- 是 task md 误判该文档需要改（PM 改 task md 后重试）

**避免在没有命中时直接 Read 全文 fallback**——这会让"位置定位原则"形同虚设；先回到 PM 决策（可能是关键字遗漏）再走下一步。

## Workflow

### 步骤 0.5：~~沉淀风险判断~~（已删）

close-task 永不调 doc-update settlement → 本步骤入口不会被触发。`/pmai-doc-update` 仅由
**(1)** close-req 步骤 1.5 调（走步骤 8 rewrite mode），或 **(2)** PM 主动 `/pmai-doc-update <module>` 调对账模式。
两条入口都不需要 v1+v2 杂交判断（rewrite 是聚合模式天然处理；对账是 PM 显式定向，无 sediment 风险）。

### 步骤 1：读取 task 文件（三态格式分流）

1. 判别 task 格式：
   ```bash
   TASK_FORMAT=$(python3 "$(git rev-parse --show-toplevel)/.claude/scripts/_lib/state.py" detect_format "$TASK_FILE")
   ```

2. **`v3`（新单文件 typed contract）**：正常路径，**不报告警**——
   - 从 PM 确认区「📌 任务卡」读 `**所属模块**` / `**所属模块章节**` 字段
   - 从审计区「📋 文档偏差」表读偏差记录（对账模式用，**单一一处**；文档偏差 / 业务偏差合并，指向任意 prd / implementation-design / analysis / DESIGN / module / PROJECT 等）

3. **`v2`（旧双文件 task）**：在飞旧 task，兼容模式继续（`echo "ℹ️  检测到旧格式 task（双文件），兼容模式继续"`）——
   - PM 视图主文件：「📌 任务卡」模块字段 + `## 📋 功能清单` + `## 📁 历史档案 → 业务层偏差` 表
   - 工程合同（`${TASK_FILE%.md}.engineering.md`）：`## 10. 文档偏差` 表（工程层偏差，指向 DESIGN / module / PROJECT 等）

4. **`v1`（旧单文件）**：兼容模式——偏差检查只读主文件 `## 文档偏差` section；模块字段是 `**所属模块：**` `**所属模块章节：**` 头部字段（旧版用 `：**` 不是表格）。

5. 如果 `**所属模块**` = `基础设施`，按 Q1 + Q4 boundary table 判定为基础设施 task：跳过模块规格沉淀，返回 success。输出：

   ```text
   基础设施 task：跳过 docs/modules 沉淀，继续 close-task。
   ```

### 步骤 1.5：分流偏差（对账模式）

扫描 task 文件偏差记录（v3：审计区「📋 文档偏差」单一一处；v2：跨 PM 视图「📁 历史档案 → 业务层偏差」+ 工程合同 §10 两处；v1：主文件「## 文档偏差」），按文档类型分流：

| 偏差指向 | 进入步骤 | 处理模式 |
|---|---|---|
| `docs/modules/<module>.md` 功能清单表格 | 1.6 | 模块规格对账（行级精确）|
| 其他 req / 项目级文档（brief / analysis / prd / DESIGN / PROJECT / CLAUDE）| 步骤 2 | 通用对账（按行读原文 + 生成 Edit + PM 逐条确认）|
| 无任何偏差 | 跳到 步骤 1.7 | 仅做沉淀模式 |

### 步骤 1.6：模块规格对账（对账模式保留）

A. 按"位置定位原则"找位置 + Read 章节范围（**建议不读全文**）：
   - 偏差指向章节明确 → `grep -n '^### <chapter>' docs/modules/<module>.md` 拿章节起始行 + Read 章节范围（到下一个 `^### ` 之前）
   - 偏差需要先定位 → 跑反转 task 5 重 grep（位置定位原则 §A.1）或字段名 grep
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

沉淀模式由 `/pmai-close-task` 在 task acceptance 后调用；它不要求「文档偏差」section 有内容。

#### 1.7.1 复合 key 匹配

每条功能用 composite key 匹配（**只读 PM 视图主文件**，不读工程合同）：

- `belonging module chapter`：取自 PM 视图主文件「📌 任务卡」表格的 `**所属模块章节**` 字段
- `level-3 feature name`：取自 PM 视图 `## 📋 功能清单` 内 section header `### N · 功能名`
- 在 module spec 中定位 `### [module chapter]`：先 `grep -n '^### [module chapter]' docs/modules/<module>.md` 拿起始行号，Read 该章节起到下一个 `^### ` 之间的范围（**建议不读全文**），再在范围内查找 `#### N · [feature name]`

跨模块 task 的 `**所属模块章节**` 必须使用 `模块A:章节X, 模块B:章节Y` 格式。沉淀时按每个 `模块:章节` 组合分别匹配对应 `docs/modules/<module>.md`。

**禁止**沉淀工程合同 §4 功能清单工程版（含字段名 / props / reducer action 等工程层细节）——这些只在 task 工程合同内保留，不进入 module spec。

**功能块内容范围**（`_shared/PM-VIEW-RULES.md` §5.1：4 列表格 + 续行 rowspan + 需求描述列内联编号）：

ADD / MODIFY 操作时，整个 H4 功能块按下述结构复制 / 对账：

- `#### N · [功能名]` 标题
- 可选 `> **使用角色**：[角色名]` section 级 blockquote
- 4 列表格：`| 二级功能 | 三级功能 | 使用角色 | 需求描述 |`，含全部数据行（含续行前 3 格留空的 rowspan 段）
- 表后可选 `> **注**：...` blockquote

不复制 task PM 视图的 `📐 产物预览` / `🚦 跨功能产品规则` / `✅ 验收清单` 等其它 section——这些是 task 局部内容，不进 module spec。

字段定义、计算口径、边界规则等都内联在需求描述列的编号项里，**不存在独立的「字段口径」表块**——见到这种独立表说明 task 用了已被废弃的格式，按 `_shared/PM-VIEW-RULES.md` §5.1 + §5.5 提示 PM 先修 task。

旧格式兼容（task 仍含 3 列表 `| 二级功能 | 三级功能 | 使用角色 |` + 表外数字编号 / 4 块结构）：保留原样照搬到 module，不强制转新格式；后续 task 用新格式时按上述结构复制。两格式可在同一 module spec 内并存。

#### 1.7.2 四种情况处理逻辑

逐条比较 task 功能清单与 module 规格：

| 情况 | 处理 |
|------|------|
| Item in task list but NOT in module spec | **ADD**：静默执行，PM 已在 task acceptance 中确认；完成后输出 summary line |
| Content identical | **SKIP**：不写入 |
| Content different | **MODIFY**：进位置清单审核门（步骤 3-6）；PM 审清单后落盘，PM 在 IDE 审实际改动 |
| Item in module spec but NOT in task list | **LEAVE UNCHANGED**：保留，不删除 |

ADD/SKIP/LEAVE UNCHANGED 不打断 PM；只有 MODIFY 进位置清单审核门。

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

对每条偏差，**先按"位置定位原则"找位置**（grep 偏差关键字 / 章节标题 / 字段名 拿命中行号），再 Read 命中所在章节级范围（**建议不读全文**）。理解：

- 原文的语言风格（中文/英文、正式/口语、用词习惯）
- 原文的格式（markdown 表格、列表、段落）
- 原文的信息密度（简洁还是详细）

### 步骤 3：生成位置清单 + 精简 before/after（对账模式）

对每条偏差 **AI 内部起草** 完整 old_string/new_string，但**主对话只展示位置清单 + 1-3 行精简 before/after**——不贴完整 diff 文本：

```text
计划改动 N 处（PM 请审核）：

1. <file>:<line>（§<chapter>）
   旧：<1-2 行原状摘要>
   新：<1-2 行新状摘要>

2. <file>:<line>（§<chapter>）
   加：<1-2 行新增摘要>
   （或：删：<1-2 行删除摘要> / 旧→新：<对照>）

...

PM 选择：全部通过 / 删除条 K / 调整条 K 范围 / 全部驳回
```

样例：

```text
计划改动 5 处（PM 请审核）：

1. docs/modules/<module>/functions-v4.1.md §1A
   旧：行展开 ▸/▾ 章节（H4 表 + 实现指引 ~50 行）
   新：行点击跳转章节（H4 表 + task-003 反转历史 blockquote）

2. requirements/active/<req>/prd.md §四 需求分析
   加：⚠️ task-003 PM 验收后反转 marker（保留原决策划掉）

3. requirements/active/<req>/prd.md §六 功能需求
   加：⚠️ task-003 反转后适用范围缩窄说明（仅详情页 Tab 1 池树内部）

4. requirements/active/<req>/prd.md §七 验收标准
   加：验收清单行展开走查项作废 + D16 跳转走查项标已落地

5. requirements/active/<req>/tasks/task-NNN-*.md §所属模块章节
   旧：产品列表页 - 行展开明细
   新：产品列表页 - 行点击跳转
```

**精简 before/after 的取材**：
- 改动方向（旧→新 / 加 / 删 / 标作废）
- 关键内容关键词（如"反转 marker" / "适用范围缩窄"），不是完整段落
- 每条 ≤ 3 行；超过表示这处改动是结构性重写，应当回到步骤 0.5 评估是否走半 close

**为什么不贴完整 diff**：
- 主对话贴 N 处完整 diff 是 doc-update token 主要来源
- 精简 before/after 已足以让 PM 识别改动方向 + 决策"通过 / 调整 / 驳回"
- 完整行级细节由 PM 在落盘后选择性核对（步骤 6 可选环节）

**AI 内部仍要起草完整 old_string/new_string**——只是主对话只贴摘要；步骤 5 调 Edit 工具落盘时用完整内容。

### 步骤 4：等 PM 审核位置清单（对账模式）

- PM 说"全部通过" → 进步骤 5 落盘
- PM 说"删除条 K" / "驳回条 K" → 从清单移除该条，**重新展示更新后的清单**让 PM 复核
- PM 说"调整条 K 范围"（如"K 只标作废不要删整段"） → AI 按反馈调整内部草稿，**重新展示该条的动作摘要**，PM 确认后进步骤 5
- PM 说"全部驳回" → 跳过对账模式；若沉淀模式仍需执行，不得跳过沉淀

### 步骤 5：执行修改 + 输出位置摘要

执行已审核通过的修改：

- 对账模式：用 Edit 工具逐条修改（不用 Write），只改偏差涉及的具体行
- 沉淀模式：按 1.7 的复合 key 和 atomic merge 规则更新 `docs/modules/*.md`

落盘完成后**输出位置摘要**（不贴 diff 文本）：

```text
已改 N 处：
- <file> §<chapter>
- <file> §<chapter>
...
```

PM 在步骤 4 已审过 before/after，**默认无需再审**——直接进入 close-task 后续。如需核对实际行级改动：跑 `git diff` 或在 IDE 看 source control diff（步骤 6 可选环节）。

### 步骤 6：可选核对 + 不满意时局部二次 patch

**默认路径**：步骤 4 PM 已审过 before/after，落盘即视为完成——直接返回 orchestrator，继续 close-task 后续 merge / cleanup。**步骤 6 默认 silent skip**，AI 不强制提示 PM 去 IDE 审。

**触发条件**：仅当 PM 主动核对（自己跑 `git diff` / 在 IDE 看 source control diff）发现某处实际改动跟步骤 4 展示的 before/after 不一致 / 摘要简化漏了细节，PM 在对话里指出（如「§3.8 那段改回去」/「§1A 缺一句 X」）。

**触发后流程（局部二次 patch）**：
- Read 对应文件那一段（命中行 ±30 行，不重读全文）
- 起草新的 old_string/new_string + Edit 落盘
- **不重新走步骤 3-4 完整审议**（已审通过位置的局部精修，不是新增改动）
- 落盘后输出"已修订 <file> §<chapter>"

**回到步骤 3 的边界**：PM 反馈实质是"增加新位置"（如"§5.5 也要标作废"）→ 属于步骤 3 范围，把新位置加入清单 + 重审

**循环上限**：同条 3 轮内未对齐 → AI 主动停下问 PM「是否升级处理：task md 是否需要补充信息 / 反转关键字是否齐全」

无 PM 触发时（默认）：返回 orchestrator，允许继续运行 `close-task.sh` 的后续 merge / cleanup。

### 步骤 8：rewrite mode（close-req 步骤 1.5 默认调用路径）

<!-- rewrite mode 是 close-req 步骤 1.5 聚合 close-task 偏差的默认调用路径。
     不再要求 ≥2 SKIP marker（marker 整套已废弃）；任何 close-req 步骤 1.5 聚合都默认调本步骤。
     输出契约：返回 REWRITE_COVERED_FILES + REWRITE_COVERED_MODULES，
     供 close-req 步骤 2a 作 metric。 -->

**触发条件**：close-req 步骤 1.5 聚合各 closed task 偏差后，对每个目标文档默认调用 rewrite mode（PM 显式选 patch 时走对账模式）。**不要求** ≥2 SKIP marker（SKIP marker 整套已废弃）。

**输入契约**：

```yaml
target_doc: docs/modules/<module>/<file>.md   # 一次一个目标文档
contributing_tasks:                            # 所有改了该目标文档的 closed task
  - task_file: tasks/task-NNN-<slug>.md        # task 文件路径（v3 单文件 typed contract）
    deviation: |                               # v3：task 审计区「📋 文档偏差」表（合并一处）
      <表格内容或「无」>
    module_chapter: <所属模块章节字段>
    # —— v2 旧双文件 task 兼容字段（task_file 为 v2 时按下列拆字段喂）——
    engineering: tasks/task-NNN-<slug>.engineering.md  # 工程合同（v2 才有）
    business_deviation: |                      # v2：PM 视图「📁 历史档案 → 业务层偏差」表
      <表格内容或「无偏差」>
    engineering_deviation: |                   # v2：工程合同 §10 偏差表
      <表格内容或「无偏差」>
affected_chapters: [§X, §Y, ...]               # 聚合所有 contributing_tasks 的章节
quickfix_baseline: <当前目标文档全文>           # 含 quickfix 旁路改动（git working tree）
```

> v3 单文件 typed contract 下偏差合并为审计区「📋 文档偏差」一处 → `deviation` 单字段；
> v2 旧 task 仍跨 PM 视图 / 工程合同两处 → `business_deviation` + `engineering_deviation`
> 两字段。doc-update 按 `task_file` 的格式（detect_format）选读哪组字段。

**流程**：

1. 读目标文档全文 + 所有 contributing_tasks 的偏差表（v3：`deviation`；v2：两 deviation 字段）
2. AI 起草新版整段（替换 affected_chapters，保持目录结构 / 表格风格 / 锚点 ID 不变）
3. PM 审 diff（默认逐章节批准；PM 可主动选 "all-at-once" 跳过逐章节）
4. 写入目标文档
5. **旧 SKIP marker 兼容**：若 contributing_tasks 含旧 `<!-- SKIP_DOC_UPDATE: ... cleanup_status="pending" -->` 残留，rewrite 完成时把 marker `cleanup_status` 改 `"done"` 留作 audit trail；新写的 task 文件无 marker 跳过本步

**输出契约**（返回给 close-req 步骤 1.5）：

```yaml
status: success | rejected
rewrite_covered_files: [docs/modules/<module>.md, ...]   # 本次 rewrite 实际改的目标文档
rewrite_covered_modules: [<module-name>, ...]            # 对应模块名
rejected_chapters: [§X, ...]                             # PM 拒绝 rewrite 的章节（仅 status=rejected）
```

close-req 步骤 1.5 收到 output 后回填 close-report.md `## 文档变更` 段 + 作步骤 2a metric。

**PM 拒绝处理**：

- PM 拒绝任一章节的 rewrite → 返回 `status=rejected`，让 close-req 步骤 1.5 决定是 retry 还是降级 patch mode（**不再有 skip 选项**）
- 不在 rewrite mode 内做"半重写"——要么全章节通过，要么退回让 close-req 重新拍

**与对账模式（步骤 1.5/1.6/2-5）的边界**：

| 模式 | 触发 | 适用场景 |
|---|---|---|
| 对账模式 | PM 显式调 `/pmai-doc-update <module>` OR close-req 步骤 1.5 PM 选 patch | 单 task 单文档单段，按行精确替换 |
| rewrite mode（本步骤） | close-req 步骤 1.5 默认（主路径） | 任何 close-req 聚合（含单 task 单 req），整段重写比按行 patch 简洁 |

**为什么不在对账模式里做（默认）**：对账模式按行精确替换，多 task 跨章节累积时 patch 顺序冲突难解；rewrite 整段写比按行打补丁更稳。rewrite 升为默认是为了节省 §0.1 痛点的 N 次启动成本累加 —— rewrite 是 close-req 末一次性聚合，启动成本只算 1 次。

## Failure Handling（DB2）

ALL failures block close-task。失败时必须停止并返回错误报告；PM 修复 underlying issue 后，重新运行 `/pmai-close-task`，`/pmai-close-task` 会 auto-resumes doc-update，从上次失败的 task 重新执行沉淀/对账。

错误信息必须包含：

- `文件`：具体失败文件，例如 `docs/modules/account.md`
- `failure type`：只能使用 `write-file` / `content-conflict` / `key-match-failure` / `internal-bug`
- `recovery path`：PM 需要怎么修，例如“修正 task 的 **所属模块章节：** 后重跑 /pmai-close-task”或“手动解决 module spec 冲突后重跑 /pmai-close-task”

推荐格式：

```text
doc-update failed; close-task blocked
文件: docs/modules/account.md
failure type: key-match-failure
recovery path: 修正 task.md 的 **所属模块章节：** 或 module spec 的 ### 章节标题后，重新运行 /pmai-close-task；系统会自动续跑 doc-update。
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
