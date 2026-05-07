---
name: task-submit
description: |
  向 PM 呈交 task 验收信息包，根据 task 类型调整展示内容，等待 PM 决策。
  **默认路径不再被 PM 直接调用**——task-execute 步骤 11/12 已合并本 skill 的呈交+决策逻辑（2026-05-07）。
  本 skill 现在的角色是 PM 手动兜底入口：窗口被关 / context 丢失 / IDE 重启后想重新呈交时使用。
---

# /task-submit

## When To Use

- **默认路径**（推荐）：不需要 PM 手动调；task-execute commit + 转「待验收」后**自动**进入步骤 11/12 呈交+决策。
- **兜底入口**（PM 手动）：异常情况下使用——
  - 新窗口被关后 PM 重新打开窗口想看验收信息
  - task-execute 异常退出但 task 已转「待验收」
  - PM 想重新审视一次验收信息包

> 默认路径与本 skill 逻辑等价；切口在 task-execute 步骤 10 commit 之后是否退出 skill。

## 拆两文件约定（必读）

本 skill 处理拆两文件的 task 产物（PM-VIEW-RULES §二）：
- **PM 视图主文件**（`.md`）：✅ 验收清单（PM 走查）/ 📁 历史档案（执行日志、PM 反馈）
- **工程合同**（`.engineering.md`）：§9 工程层验收清单（agent 自动化校验）/ §10 文档偏差表 / §11 自审记录

submit 阶段的信息聚合：
- 主路径展示 → 取 PM 视图 §✅ 验收清单
- 工程层验收（grep / 单测 / 引用稳定性等）→ 取工程合同 §9 工程层验收清单（作为补充信息）
- 文档偏差 → **跨两处读取**（PM 视图历史档案 + 工程合同 §10）
- 自审记录 → 从工程合同 §11 取
- **PM 反馈写入主文件**（`.md` 的 📁 历史档案 → PM 反馈 section）；**禁止**写入工程合同

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-submit"
```

## Workflow

### 步骤 1：读取 task 两文件

1. 读取 PM 视图主文件（`.md`）：
   - 「📌 任务卡」（含状态、模块、worktree、dev server）
   - 「📐 产物预览」（判断 task 类型）
   - 「✅ 验收清单」（PM 走查主路径）
   - 「📁 历史档案」（执行日志最新一轮、文档偏差、PM 反馈历史）

2. 读取工程合同（`.engineering.md`）：
   - 「§1 元信息扩展」（推荐 review 工具）
   - 「§9 工程层验收清单」（agent 自动化校验，作为补充）
   - 「§10 文档偏差」（工程层偏差）
   - 「§11 自审记录」（最新一轮自审结论）

3. 工程合同存在性校验（兼容旧格式）：

   ```bash
   ENG_FILE="${TASK_FILE%.md}.engineering.md"
   if [ ! -f "$ENG_FILE" ]; then
     echo "⚠️  工程合同缺失（旧格式 task，按单文件兼容模式继续）：$ENG_FILE"
     HAS_ENG=false
   else
     HAS_ENG=true
   fi
   ```

   - `HAS_ENG=true`：按上述两文件聚合
   - `HAS_ENG=false`：兼容模式——所有信息从主文件读（旧 task 把执行日志 / 文档偏差 / 自审记录 / 推荐 review 工具都放在主文件）

### 步骤 2：判断 task 类型

按以下任一信号判定为 UI 类（任一命中即 UI）：

- task 描述涉及前端/页面/组件/界面/UI/view/component
- 工程合同 §1「推荐 review 工具」字段含 `/design-review` 或 `/qa`
- PM 视图「📐 产物预览」section 含 ASCII 线框图（不是「无」或大纲）

其余视为非 UI 类。

### 步骤 3：组装验收信息

**UI 类 task 展示**（信息聚合自两文件）：

```
═══════════════════════════════════════
📋 Task 验收：task-NNN-<slug>
═══════════════════════════════════════

🔗 验收 URL: http://localhost:<port>

📝 改动摘要：
[从 PM 视图主文件「📁 历史档案 → 执行日志」最新一轮提取]

🔍 自审结果：
[从工程合同 §11「自审记录」最新一条提取]

✅ 验收清单（PM 主路径走查）：
- [ ] 条件 1
- [ ] 条件 2
[从 PM 视图「✅ 验收清单」逐条列出]

📄 文档偏差（跨两文件）：
PM 视图：[历史档案中的偏差或"无"]
工程合同：[§10 偏差表内容或"无偏差"]

📊 工程层验收（agent 自动化校验，参考信息）：
[从工程合同 §9 工程层验收清单提取]

请验收：通过 / 打回（附反馈）
═══════════════════════════════════════
```

**非 UI 类 task 展示**：

```
═══════════════════════════════════════
📋 Task 验收：task-NNN-<slug>
═══════════════════════════════════════

📝 改动摘要：
[从 PM 视图主文件执行日志提取]

📂 代码变更：
[关键 diff 摘要或测试结果]

🔍 自审结果：
[从工程合同 §11 自审记录提取]

✅ 验收清单（PM 主路径走查）：
- [ ] 条件 1
- [ ] 条件 2

📄 文档偏差（跨两文件）：
PM 视图：[执行日志中的偏差或"无"]
工程合同：[§10 偏差表内容或"无偏差"]

📊 工程层验收（agent 自动化校验，参考信息）：
[从工程合同 §9 提取]

请验收：通过 / 打回（附反馈）
═══════════════════════════════════════
```

### 步骤 3.5：在本窗口直接呈交 PM 验收（v4 单窗口 lifecycle）

进入「待验收」后，不提示 PM 回主窗口。当前新窗口直接汇总验收包并等待 PM 决策。

必须补充三类信息：

1. **Diff 摘要**：从 req 分支到当前 HEAD。
   ```bash
   git diff --stat <req-branch>..HEAD
   ```
2. **PM 已跑的 review（如有）**：列出 task-execute 阶段 PM 实际跑过并 append 到事件流的工具及结论，例如 `/review pass, /qa pass`；PM 全跳时写 `（PM 选择不跑 review）`。事件流缺事件不阻塞验收（I-RV2）。
3. **PM 决策入口**：明确让 PM 在本窗口选择通过或打回。

**走查时引导 PM 反推 req / 项目级文档偏差**：

PM 看原型 / 看 diff 时，如果发现 brief / analysis / solution（PM 视图）/ prd / module 规格 等上游文档**写错或需修订**，提醒 PM 在 task PM 视图「📁 历史档案 → 业务层偏差」表填一行（默认空时多数 task 不需要填）。close-task 调 /doc-update 时会扫这段 + 工程合同 §10，呈交 PM 逐条确认改原文。

不要让 PM 把这种偏差只在对话里说而不落到表里——会丢。

输出格式：

```text
Diff: N 文件 +X -Y 行 / review: <工具列表> 结论 → PM 通过/打回？
```

### 步骤 4：等待 PM 决策

**PM 说"通过"：**

```bash
python3 .claude/scripts/task-transition.py "<task-file>" --to 已完成
```

然后提示 PM 切到 req 窗口（v4.5：close-task 必须在 req worktree 跑，不能在 task 窗口）：

```text
✅ task-NNN 状态已转「已完成」。

请关闭本（task）窗口，切到 req 窗口运行：
  /close-task task-NNN
```

**PM 说"打回"：**

1. 记录 PM 反馈到 **PM 视图主文件**的「📁 历史档案 → PM 反馈」section（**禁止**写入工程合同）：
   ```markdown
   ### 反馈 N - [YYYY-MM-DD]
   **问题描述：** [PM 的原话]
   **要求修改：** [具体修改要求]
   **分类（PM-VIEW-RULES §9.4）**：[正向规则 / 反向约束 / 决策记录]
   **处理结果：** 待处理
   ```

   分类规则（参 PM-VIEW-RULES §9.4）：
   - 正向规则（"统一用 X" / "全文用 Y"）→ 后续 task 同步入「跨功能产品规则」
   - 反向约束（"禁用 X" / "不要 Y"）→ 后续 task 同步入工程合同 §6 易错点 / 禁止项
   - 决策记录（"二审改 X" / "重做为 Y"）→ 后续 task 同步入「关键产品决策」备选方案列

2. 转换状态回执行中：
   ```bash
   python3 .claude/scripts/task-transition.py "<task-file>" --to 执行中 --note "PM 打回：<反馈摘要>"
   ```

3. 输出给 PM，并继续在本窗口修复：

   ```text
   task-execute 收到打回后，会先按 DX RU3 分流策略判断本次反馈是「行为修订」还是「Bug 修复」，并明确告知你判断结果。如判断错误，回复 "wrong" 切换分流。（分流策略权威定义见 skills/task-execute/SKILL.md §PM 反馈分流策略）
   ```

4. 应用 stage 5/6 PM 反馈分流策略（引用 `skills/task-execute/SKILL.md §PM 反馈分流策略`），然后继续修复并重新走自审与验收。

## Rules

- 验收信息从 task 文件各 section 提取，不要编造内容
- PM 的反馈原话记录，不要改写
- 打回时 --note 参数必须提供，否则 task-transition.py 会拒绝
- UI 类 task 的 dev server 应该还在运行，确认 URL 可访问
- 验收 / 打回修复在当前 task worktree 窗口完成；PM 通过验收后转「已完成」，并提示 PM 切到 req 窗口跑 `/close-task task-NNN`（v4.5：close-task 不能在 task 窗口跑）
