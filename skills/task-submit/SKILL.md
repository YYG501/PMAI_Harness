---
name: pmai-task-submit
description: |
  向 PM 呈交一个 task 的验收信息包，等待 PM 拍板（通过 / 退回继续打磨）。
  **默认路径不再被 PM 直接调用**——task-execute 的呈交闸门已合并本 skill 的呈交 + 决策逻辑，build 完会自动呈交。
  本 skill 现在只是 PM 手动兜底入口：窗口被关 / context 丢失 / IDE 重启后想重新呈交一次时使用。
  task 全程处于「执行中」（没有单独的「待验收」），build commit 不切状态；PM 在呈交块拍「通过」时统一转「已完成」。
---

# /pmai-task-submit

> **本 skill 的归属**：呈交 + PM 拍板逻辑已合并进 `skills/task-execute/SKILL.md` 的呈交闸门。正常 build 流程不会进这里——build 完成后会在同一个窗口自动汇总验收包等 PM 决策。本 skill 只在那个呈交块**丢了**（窗口被关 / context 丢失 / IDE 重启）需要重新呈交时手动跑。语义与 task-execute 呈交闸门完全等价。

> **PM 答题规则**：呈交块的拍板（通过完成 / 退回继续打磨）走 `_shared/pm-view/askuser-rules.md` §1 四条硬规则（空答 STOP / 没拿到答案不准把 task 切「已完成」/ runtime 退化时保留等待 / 多个决策拆开顺序问）。**禁止默认替 PM 选「通过」、禁止给 PM 绕过选项**。呈交块用 picker 形态；runtime 不支持 picker 时按 §1.3 自动退化成编号列表，仍然等 PM 答。

## When To Use

- **默认路径**（推荐，无需手动调）：build commit 后由 task-execute 呈交闸门**自动**呈交 + 等 PM 决策（commit 不切状态）。
- **兜底入口**（PM 手动调）：异常情况——
  - 新窗口被关后 PM 重新打开想再看一次验收信息
  - build 已 commit 但 chat 里的呈交块丢了
  - PM 想重新审视一次验收信息包
  - PM 在「执行中」期间已跑过若干 review，想刷新呈交块看最新自审 / 事件

> 状态前置：task 必须已经是「执行中」（build commit 已发生、已组装过一次呈交块）。「已完成」/「待执行」的 task 不该进这里。

## task 文件读取约定（必读）

一个 task 是一个物理文件 `task-NNN-<slug>.md`，分三区（PM 确认区 / 执行区 / 审计区），由 region 标记界定。呈交时的信息聚合锚点：

| 验收信息 | 文件锚点 |
|---|---|
| 验收清单（PM 走查主路径） | PM 确认区「✅ 验收清单」 |
| 工程层验收（grep / 单测 / 引用稳定性，参考信息） | 执行区「✔️ 工程层验收」 |
| 改动摘要 | 审计区「📁 历史档案 → 执行日志」最新一轮 |
| 文档偏差 | 审计区「📋 文档偏差」表（单一一处） |
| 自审记录 | 审计区「🔍 自审记录」最新一条 |
| 推荐 review 工具 | PM 确认区「📌 任务卡 → 审查工具」字段 |
| PM 退回反馈（打回时写入） | 审计区「📁 历史档案 → PM 反馈」 |

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: task-submit"
```

## Workflow

### 步骤 1：读取 task 文件

判别 task 格式：

```bash
TASK_FORMAT=$(python3 "$(git rev-parse --show-toplevel)/.claude/scripts/_lib/state.py" detect_format "$TASK_FILE")
```

- **单文件 typed contract**（当前格式）：正常路径，**不报告警**（没有 `.engineering.md` 是正常的）。从三区聚合：
  - PM 确认区「📌 任务卡」（状态、模块、worktree、dev server、审查工具）/「✅ 验收清单」
  - 执行区「✔️ 工程层验收」（agent 自动化校验，作为补充）
  - 审计区「📋 文档偏差」表 /「🔍 自审记录」最新一条 /「📁 历史档案」（执行日志最新一轮、PM 反馈历史）
- **旧双文件 task**（兼容读路径）：在飞的老 task 仍是「PM 视图主文件 `.md` + 工程合同 `.engineering.md`」。验收清单 / 历史档案在 PM 视图主文件；工程层验收 / 文档偏差 / 自审记录在工程合同。
- **旧单文件 task**（兼容）：所有信息从主文件读（执行日志 / 文档偏差 / 自审记录 / 推荐 review 工具都在主文件里）。

### 步骤 2：判断 task 类型

按以下任一信号判定为 UI 类（任一命中即 UI）：

- task 描述涉及前端 / 页面 / 组件 / 界面 / UI / view / component
- 「审查工具」字段含 `/design-review` 或 `/qa`
- 执行区「🧪 自测说明」段非空且非「无」

其余视为非 UI 类。

### 步骤 3：组装验收信息

**UI 类 task 展示**：

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

请验收：通过 / 退回（附反馈）

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

请验收：通过 / 退回（附反馈）

──────────────────────────────────────
⚙️ 可选深度审查（PM 自取所需，非必跑）：
  /review              — 代码审查 task 分支 vs req 分支的 diff
跑完贴结论我会机械追加自审记录 + append 事件（I-RV3）。
═══════════════════════════════════════
```

### 步骤 3.5：在本窗口直接呈交 PM 验收

build commit 已完成（task 状态仍是「执行中」），不提示 PM 回主窗口。当前窗口直接汇总验收包并等 PM 拍板。

补充三类信息：

1. **Diff 摘要**：从 req 分支到当前 HEAD。
   ```bash
   git diff --stat <req-branch>..HEAD
   ```
2. **PM 已跑的 review（如有，仅在事件流非空时显示）**：读 `task-events.py list --type review_completed`；有事件就在「🔍 自审结果」末尾追加（如 `/review pass`），无事件不显示——默认情况下 PM 还没决定跑不跑，不预设"PM 选择不跑"的描述。事件流缺事件不阻塞验收（I-RV2）。
3. **PM 决策入口**：明确让 PM 在本窗口选「通过」或「退回」。

**走查时引导 PM 反推上游文档偏差**：

PM 看原型 / 看 diff 时，如果发现 req-plan / PRODUCT-STATE / 模块规格 等上游文档**写错或需修订**，提醒 PM 在 task 文件「📋 文档偏差」表填一行（在审计区；旧双文件 task 业务层偏差填 PM 视图「📁 历史档案 → 业务层偏差」、工程层填工程合同）。默认空时多数 task 不需要填。**close-req 沉淀**会聚合本 req 所有已完成 task 的偏差，按目标文档一次性沉淀。

不要让 PM 把这种偏差只在对话里说而不落到表里——会丢。

输出格式：

```text
Diff: N 文件 +X -Y 行 → PM 通过/退回？
```

### 步骤 4：等待 PM 拍板（AskUserQuestion picker）

呈交块（步骤 3 输出）后，AI 调 AskUserQuestion：
- `question`: "task-NNN 验收？"
- `options`:
  - `label`: `通过`
    `description`: `task 转「已完成」，进 /pmai-close-task`
  - `label`: `退回`
    `description`: `task 保持「执行中」，AI 基于反馈继续打磨；说哪里要改`

**PM 选 `通过`**（或输 `1` / 输 "OK / 通过 / 没问题"）：

```bash
python3 "$PMAI_HOME/scripts/task-transition.py" "<task-file>" --to 已完成
```

`task-transition.py` 在「执行中→已完成」入口校验文档偏差 + 自审记录非空（I-TT3）。

然后提示 PM 启动 close-task（按 [banner-rules §2.5 内容禁忌](../_shared/pm-view/banner-rules.md#25-内容禁忌pm-facing-输出禁工程黑话与内部原理) — 不写内部阶段编号、不写 merge / worktree / auto-chain）：

```text
✅ task-NNN 状态已转「已完成」。

下一步：在本（task）窗口运行：
  /pmai-close-task task-NNN

这次收尾在当前窗口做完（文档对齐 + 视觉规范沉淀），完成后会提示你切到 req 窗口再跑一次 /pmai-close-task 做清理。
```

**PM 选 `退回`**（或输 `2` / 提具体反馈 / 输 "退回 / 改一下 / 不对"）：

> 退回**不切状态** — task 全程是「执行中」，AI 直接基于反馈继续打磨，不走任何状态回退（I-TT4 废弃）。

1. 记录 PM 反馈到 task 文件「📁 历史档案 → PM 反馈」section（在审计区；旧双文件 task 写 PM 视图主文件、**禁止**写入工程合同）：
   ```markdown
   ### 反馈 N - [YYYY-MM-DD]
   **问题描述：** [PM 的原话]
   **要求修改：** [具体修改要求]
   **处理结果：** 待处理
   ```

   PM 反馈留在本段不归类。后续同 req 的 task 由 task-spec 按 relevance 二分（适用 / 不适用）承接进新 task 的「PM 反馈承接清单」；视觉规范类 / 全项目跨功能产品规则由 close-task 收尾时按目标 promote。

2. 输出给 PM，并继续在本窗口打磨：

   ```text
   收到退回。本轮按反馈循环规则只改原型代码，task md 业务字段对齐统一交给 close-task batch 处理。如反馈描述模糊到无法实施，会用 AskUserQuestion 问澄清细节。（规则权威定义见 skills/task-execute/SKILL.md §反馈循环规则）
   ```

3. 应用反馈循环规则（权威定义见 `skills/task-execute/SKILL.md §反馈循环规则`）：本轮 AI 只改原型代码 + 在执行报告写「文档对齐预告」，不动 task md 业务字段。

4. 打磨完毕后**追加 fix commit**（保留主 commit + fix commit 的 diff 历史；commit message 模板：`task-NNN fixup: <一句话>`）；重新呈交（重新走步骤 3-4）。

## Rules

- 验收信息从 task 文件各 section 提取，不要编造内容
- PM 的反馈原话记录，不要改写
- 退回**不走 transition**（task 状态保持「执行中」），只写反馈到 task 文件「📁 历史档案 → PM 反馈」（审计区 / 旧双文件 task 写 PM 视图）+ AI 改代码 + 追加 fix commit
- UI 类 task 的 dev server 应该还在运行，确认 URL 可访问
- 验收 / 打磨都在当前 task worktree 窗口完成；PM 拍「通过」后转「已完成」，并提示 PM 在本（task）窗口跑 `/pmai-close-task task-NNN`（close-task 两段：先在 task 窗口对齐 + commit，再切到 req 窗口 merge + 清理）
- 推荐 review 仅作验收信息块末尾的「⚙️ 可选深度审查」辅助提示，PM 自取所需；AI 不得自动跑（I-RV1）；PM 报告结果后才 append 事件（I-RV3）
