---
name: pmai-task-submit
description: |
  向 PM 呈交 task 验收信息包，根据 task 类型调整展示内容，等待 PM 决策。
  **默认路径不再被 PM 直接调用**——task-execute 步骤 11/12 已合并本 skill 的呈交+决策逻辑。
  本 skill 现在的角色是 PM 手动兜底入口：窗口被关 / context 丢失 / IDE 重启后想重新呈交时使用。
  task 状态全程是「执行中」（旧「待验收」已合并到「执行中」），commit 不切状态，PM 通过呈交块时统一转「已完成」。
---

# /pmai-task-submit

> **PM 答题规则（M4）**：所有 AskUserQuestion 调用（呈交块决策：通过完成 / 退回继续打磨）按 `_shared/pm-view/askuser-rules.md` §1 3 硬规则走（空答 STOP / 没拿到答案禁止切 task 状态为「已完成」/ runtime 退化保留 wait）。**禁止默认走 recommend 分支 / 禁止逃生舱**。

## When To Use

- **默认路径**（推荐）：不需要 PM 手动调；task-execute commit 后**自动**进入步骤 11/12 呈交+决策（commit 不切状态）。
- **兜底入口**（PM 手动）：异常情况下使用——
  - 新窗口被关后 PM 重新打开窗口想看验收信息
  - task-execute 已 commit 但 chat 中呈交块丢失
  - PM 想重新审视一次验收信息包
  - PM 在「执行中」期间已跑过若干 review，想刷新呈交块看最新自审/事件流

> 默认路径与本 skill 逻辑等价；切口在 task-execute 步骤 10 commit 之后是否退出 skill。
> 状态前置：task 必须处于「执行中」（commit 已发生，已组装过呈交块）。「已完成」/「待执行」状态不应进入此 skill。

## 单文件 typed contract 约定（必读）

本 skill 处理 task 的单文件 typed contract —— 一个物理文件 `task-NNN-<slug>.md`，三区由 region 标记界定。submit 阶段的信息聚合锚点：

| 验收信息 | v3 单文件锚点 |
|---|---|
| 验收清单（PM 走查） | PM 确认区「✅ 验收清单」 |
| 工程层验收（grep / 单测 / 引用稳定性） | 执行区「✔️ 工程层验收」 |
| 改动摘要 | 审计区「📁 历史档案 → 执行日志」最新一轮 |
| 文档偏差 | 审计区「📋 文档偏差」表（单一一处） |
| 自审记录 | 审计区「🔍 自审记录」最新一条 |
| 推荐 review 工具 | PM 确认区「📌 任务卡 → 审查工具」字段 |
| 写 PM 反馈（打回时） | 审计区「📁 历史档案 → PM 反馈」 |

**旧 v2 双文件 task 兼容**：在飞旧 task 仍是「PM 视图主文件 `.md` + 工程合同 `.engineering.md`」；本 skill 保留 v2 兼容读路径（见步骤 1）—— 验收清单 / 历史档案在 PM 视图，§9 工程层验收 / §10 文档偏差 / §11 自审记录在工程合同。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: task-submit"
```

## Workflow

### 步骤 1：读取 task 文件（三态格式分流）

1. 判别 task 格式：

   ```bash
   TASK_FORMAT=$(python3 "$(git rev-parse --show-toplevel)/.claude/scripts/_lib/state.py" detect_format "$TASK_FILE")
   ```

2. **`v3`（新单文件 typed contract）**：正常路径，**不报告警**（task 文件本身是单文件，无 `.engineering.md` 属正常）。从 task 文件单文件三区聚合：
   - PM 确认区「📌 任务卡」（状态、模块、worktree、dev server、审查工具）/「✅ 验收清单」（PM 走查主路径）
   - 执行区「✔️ 工程层验收」（agent 自动化校验，作为补充）
   - 审计区「📋 文档偏差」表 /「🔍 自审记录」最新一条 /「📁 历史档案」（执行日志最新一轮、PM 反馈历史）

3. **`v2`（旧双文件 task）**：在飞旧 task，按兼容模式继续：

   ```bash
   ENG_FILE="${TASK_FILE%.md}.engineering.md"
   echo "ℹ️  检测到旧格式 task（双文件），兼容模式继续：$ENG_FILE"
   ```

   - PM 视图主文件（`.md`）：「📌 任务卡」/「📐 产物预览」/「✅ 验收清单」/「📁 历史档案」（执行日志、文档偏差、PM 反馈历史）
   - 工程合同（`.engineering.md`）：「§1 元信息扩展」推荐 review 工具 /「§9 工程层验收清单」/「§10 文档偏差」/「§11 自审记录」

4. **`v1`（旧单文件）**：兼容模式——所有信息从主文件读（旧 task 把执行日志 / 文档偏差 / 自审记录 / 推荐 review 工具都放在主文件）。

### 步骤 2：判断 task 类型

按以下任一信号判定为 UI 类（任一命中即 UI）：

- task 描述涉及前端/页面/组件/界面/UI/view/component
- 「审查工具」字段含 `/design-review` 或 `/qa`（v3：PM 确认区「📌 任务卡」字段；v2：工程合同 §1）
- 执行区「🧪 自测说明」段非空且非「无」（v2：PM 视图「📐 产物预览」含 ASCII 线框图）

其余视为非 UI 类。

### 步骤 3：组装验收信息

**UI 类 task 展示**（信息聚合自两文件）：

```
═══════════════════════════════════════
📋 Task 验收：task-NNN-<slug>
═══════════════════════════════════════

🔗 验收 URL: http://localhost:<port>

📝 改动摘要：
[从「📁 历史档案 → 执行日志」最新一轮提取]

🔍 自审结果：
[从「🔍 自审记录」最新一条提取；如 PM 已跑 review，附 review_completed 事件结论]

✅ 验收清单（PM 主路径走查）：
- [ ] 条件 1
- [ ] 条件 2
[从「✅ 验收清单」逐条列出]

📄 文档偏差：
[「📋 文档偏差」表内容或"无"]

📊 工程层验收（agent 自动化校验，参考信息）：
[从「✔️ 工程层验收」提取]

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
[从「📁 历史档案 → 执行日志」最新一轮提取]

📂 代码变更：
[关键 diff 摘要或测试结果]

🔍 自审结果：
[从「🔍 自审记录」最新一条提取；如 PM 已跑 review，附 review_completed 事件结论]

✅ 验收清单（PM 主路径走查）：
- [ ] 条件 1
- [ ] 条件 2

📄 文档偏差：
[「📋 文档偏差」表内容或"无"]

📊 工程层验收（agent 自动化校验，参考信息）：
[从「✔️ 工程层验收」提取]

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

PM 看原型 / 看 diff 时，如果发现 prd / implementation-design / analysis / module 规格 等上游文档**写错或需修订**，提醒 PM 在 task 文件「📋 文档偏差」表填一行（v3 在审计区；v2 旧 task 业务层偏差填 PM 视图「📁 历史档案 → 业务层偏差」、工程层填工程合同 §10）。默认空时多数 task 不需要填。**close-req 步骤 1.5** 会聚合本 req 所有 closed task 的偏差，按目标文档调 doc-update rewrite mode 一次性沉淀。

不要让 PM 把这种偏差只在对话里说而不落到表里——会丢。

输出格式：

```text
Diff: N 文件 +X -Y 行 → PM 通过/打回？
```

### 步骤 4：等待 PM 决策

**PM 说"通过"：**

```bash
python3 "$PMAI_HOME/scripts/task-transition.py" "<task-file>" --to 已完成
```

`task-transition.py` 在「执行中→已完成」入口校验文档偏差 + 自审记录非空（I-TT3）。

然后提示 PM 启动 close-task（按 [banner-rules §2.5 内容禁忌](../_shared/pm-view/banner-rules.md#25-内容禁忌pm-facing-输出禁工程黑话与内部原理) — 不写 Phase 1/2、不写 merge / worktree / auto-chain）：

```text
✅ task-NNN 状态已转「已完成」。

下一步：在本（task）窗口运行：
  /pmai-close-task task-NNN

本次 close 收尾在当前窗口做完（文档对齐 + 视觉规范沉淀），完成后会提示你切到 req 窗口再跑一次 /pmai-close-task 完成清理。
```

**PM 说"打回"：**

> 打回**不切状态** — task 全程是「执行中」，AI 直接基于反馈继续修，不再走 `--to 执行中` 回退（该 transition 已删除，I-TT4 废弃）。

1. 记录 PM 反馈到 task 文件「📁 历史档案 → PM 反馈」section（v3 在审计区；v2 写 PM 视图主文件、**禁止**写入工程合同）：
   ```markdown
   ### 反馈 N - [YYYY-MM-DD]
   **问题描述：** [PM 的原话]
   **要求修改：** [具体修改要求]
   **处理结果：** 待处理
   ```

   PM 反馈留在本段不归类。后续同 req 的 task 由 task-spec 按 relevance 二分（适用 / 不适用）承接进新 task 的「PM 反馈承接清单」；视觉规范类 / 全项目跨功能产品规则由 close-task 收尾时按目标 promote。

2. 输出给 PM，并继续在本窗口修复：

   ```text
   收到打回。本轮按反馈循环规则只改原型代码，task md 业务字段对齐统一交给 close-task §0 batch 处理。如反馈描述模糊到无法实施，会用 AskUserQuestion 问澄清细节。（规则权威定义见 skills/task-execute/SKILL.md §反馈循环规则）
   ```

3. 应用反馈循环规则（权威定义见 `skills/task-execute/SKILL.md §反馈循环规则`）：本轮 AI 只改原型代码 + 在执行报告写「文档对齐预告」，不动 task md 业务字段。

4. 修复完毕后**追加 fix commit**（保留主 commit + fix commit 的 diff 历史；commit message 模板：`task-NNN fixup: <一句话>`）；重新呈交（重新走步骤 3-4）。

## Rules

- 验收信息从 task 文件各 section 提取，不要编造内容
- PM 的反馈原话记录，不要改写
- 打回**不走 transition**（task 状态保持「执行中」），仅写反馈到 task 文件「📁 历史档案 → PM 反馈」（v3 审计区 / v2 PM 视图）+ AI 修代码 + 追加 fix commit
- UI 类 task 的 dev server 应该还在运行，确认 URL 可访问
- 验收 / 打回修复在当前 task worktree 窗口完成；PM 通过验收后转「已完成」，并提示 PM 在本（task）窗口跑 `/pmai-close-task task-NNN` 启动 Phase 1（close-task 是两阶段调用，Phase 1 在 task 窗口对齐 + commit，Phase 2 切到 req 窗口 merge + 清理）
- 推荐 review 仅作验收信息块末尾的「⚙️ 可选深度审查」辅助提示，PM 自取所需；AI 不得自动跑（I-RV1）；PM 报告结果后才 append 事件（I-RV3）
