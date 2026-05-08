---
name: task-submit
description: |
  向 PM 呈交 task 验收信息包，根据 task 类型调整展示内容，等待 PM 决策。
  **默认路径不再被 PM 直接调用**——task-execute 步骤 11/12 已合并本 skill 的呈交+决策逻辑（2026-05-07）。
  本 skill 现在的角色是 PM 手动兜底入口：窗口被关 / context 丢失 / IDE 重启后想重新呈交时使用。
  task 状态全程是「执行中」（2026-05-08「待验收」已合并到「执行中」），commit 不切状态，PM 通过呈交块时统一转「已完成」。
---

# /task-submit

## When To Use

- **默认路径**（推荐）：不需要 PM 手动调；task-execute commit 后**自动**进入步骤 11/12 呈交+决策（commit 不切状态）。
- **兜底入口**（PM 手动）：异常情况下使用——
  - 新窗口被关后 PM 重新打开窗口想看验收信息
  - task-execute 已 commit 但 chat 中呈交块丢失
  - PM 想重新审视一次验收信息包
  - PM 在「执行中」期间已跑过若干 review，想刷新呈交块看最新自审/事件流

> 默认路径与本 skill 逻辑等价；切口在 task-execute 步骤 10 commit 之后是否退出 skill。
> 状态前置：task 必须处于「执行中」（commit 已发生，已组装过呈交块）。「已完成」/「待确认」状态不应进入此 skill。

## 拆两文件约定（必读）

本 skill 处理拆两文件的 task 产物（`_shared/PM-VIEW-RULES.md` §二）：
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
[从工程合同 §11「自审记录」最新一条提取；如 PM 已跑 review，附 review_completed 事件结论]

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

──────────────────────────────────────
⚙️ 可选深度审查（PM 自取所需，非必跑）：
  /review              — 代码审查 task 分支 vs req 分支的 diff
  /qa                  — 功能测试 dev server（需 browse；UI task 推荐）
  /design-review       — 对照 DESIGN.md 检查视觉一致性（需 browse；UI task 推荐）
跑完贴结论我会机械追加自审记录 + append 事件（I-RV3）。
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
[从工程合同 §11 自审记录提取；如 PM 已跑 review，附 review_completed 事件结论]

✅ 验收清单（PM 主路径走查）：
- [ ] 条件 1
- [ ] 条件 2

📄 文档偏差（跨两文件）：
PM 视图：[执行日志中的偏差或"无"]
工程合同：[§10 偏差表内容或"无偏差"]

📊 工程层验收（agent 自动化校验，参考信息）：
[从工程合同 §9 提取]

请验收：通过 / 打回（附反馈）

──────────────────────────────────────
⚙️ 可选深度审查（PM 自取所需，非必跑）：
  /review              — 代码审查 task 分支 vs req 分支的 diff
跑完贴结论我会机械追加自审记录 + append 事件（I-RV3）。
═══════════════════════════════════════
```

### 步骤 3.5：在本窗口直接呈交 PM 验收（v4 单窗口 lifecycle）

commit 完成后（task 状态仍是「执行中」），不提示 PM 回主窗口。当前新窗口直接汇总验收包并等待 PM 决策。

必须补充三类信息：

1. **Diff 摘要**：从 req 分支到当前 HEAD。
   ```bash
   git diff --stat <req-branch>..HEAD
   ```
2. **PM 已跑的 review（如有，仅在事件流非空时显示）**：读 `task-events.py list --type review_completed`；有事件就在「🔍 自审结果」末尾追加（如 `/review pass`），无事件不显示——默认路径下 PM 还没决定跑不跑，不预设"PM 选择不跑"的描述。事件流缺事件不阻塞验收（I-RV2）。
3. **PM 决策入口**：明确让 PM 在本窗口选择通过或打回。

**走查时引导 PM 反推 req / 项目级文档偏差**：

PM 看原型 / 看 diff 时，如果发现 brief / analysis / solution（PM 视图）/ prd / module 规格 等上游文档**写错或需修订**，提醒 PM 在 task PM 视图「📁 历史档案 → 业务层偏差」表填一行（默认空时多数 task 不需要填）。close-task 调 /doc-update 时会扫这段 + 工程合同 §10，呈交 PM 逐条确认改原文。

不要让 PM 把这种偏差只在对话里说而不落到表里——会丢。

输出格式：

```text
Diff: N 文件 +X -Y 行 → PM 通过/打回？
```

### 步骤 4：等待 PM 决策

**PM 说"通过"：**

```bash
python3 .claude/scripts/task-transition.py "<task-file>" --to 已完成
```

`task-transition.py` 在「执行中→已完成」入口校验文档偏差 + 自审记录非空（I-TT3）。

然后提示 PM 切到 req 窗口（v4.5：close-task 必须在 req worktree 跑，不能在 task 窗口）：

```text
✅ task-NNN 状态已转「已完成」。

请关闭本（task）窗口，切到 req 窗口运行：
  /close-task task-NNN
```

**PM 说"打回"：**

> 打回**不切状态** — task 全程是「执行中」，AI 直接基于反馈继续修，不再走 `--to 执行中` 回退（该 transition 在 2026-05-08 删除，I-TT4 废弃）。

1. 记录 PM 反馈到 **PM 视图主文件**的「📁 历史档案 → PM 反馈」section（**禁止**写入工程合同）：
   ```markdown
   ### 反馈 N - [YYYY-MM-DD]
   **问题描述：** [PM 的原话]
   **要求修改：** [具体修改要求]
   **分类（`_shared/pm-view/input-flow.md` §9.4）**：[正向规则 / 反向约束 / 决策记录]
   **处理结果：** 待处理
   ```

   分类规则（参 `_shared/pm-view/input-flow.md` §9.4）：
   - 正向规则（"统一用 X" / "全文用 Y"）→ 后续 task 同步入「跨功能产品规则」
   - 反向约束（"禁用 X" / "不要 Y"）→ 后续 task 同步入工程合同 §6 易错点 / 禁止项
   - 决策记录（"二审改 X" / "重做为 Y"）→ 后续 task 同步入「关键产品决策」备选方案列

2. 输出给 PM，并继续在本窗口修复：

   ```text
   收到打回。本轮按反馈循环规则只改原型代码，task md 业务字段对齐统一交给 close-task §0 batch 处理。如反馈描述模糊到无法实施，会用 AskUserQuestion 问澄清细节。（规则权威定义见 skills/task-execute/SKILL.md §反馈循环规则）
   ```

3. 应用反馈循环规则（权威定义见 `skills/task-execute/SKILL.md §反馈循环规则`）：本轮 AI 只改原型代码 + 在执行报告写「文档对齐预告」，不动 task md 业务字段。

4. 修复完毕后**追加 fix commit**（保留主 commit + fix commit 的 diff 历史；commit message 模板：`task-NNN fixup: <一句话>`）；重新呈交（重新走步骤 3-4）。

## Rules

- 验收信息从 task 文件各 section 提取，不要编造内容
- PM 的反馈原话记录，不要改写
- 打回**不走 transition**（task 状态保持「执行中」），仅写反馈到 PM 视图历史档案 + AI 修代码 + 追加 fix commit
- UI 类 task 的 dev server 应该还在运行，确认 URL 可访问
- 验收 / 打回修复在当前 task worktree 窗口完成；PM 通过验收后转「已完成」，并提示 PM 切到 req 窗口跑 `/close-task task-NNN`（v4.5：close-task 不能在 task 窗口跑）
- 推荐 review 仅作验收信息块末尾的「⚙️ 可选深度审查」辅助提示，PM 自取所需；AI 不得自动跑（I-RV1）；PM 报告结果后才 append 事件（I-RV3）
