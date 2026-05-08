---
name: req-stage-gate
description: |
  Req stage 边界推进：根据当前 stage 执行过渡逻辑，PM 确认后推进到下一 stage。
---

# /req-stage-gate

## When To Use

- Orchestrator 在每个 stage 完成后调用，推进到下一 stage

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: req-stage-gate"
```

读取 `$ACTIVE_REQ_STAGE` 确定当前 stage。

## Stage 过渡逻辑

### Stage 1 → 2（感受问题 → 需求分析）

1. 检查 `brief.md` 存在且有内容
2. **brief 二次确认门**（新对话首次进入 worktree 时的入口闸）：

   `/new-req` 在主对话写完 brief.md 后就 handoff 退场，PM 在 worktree 内新对话里第一次跑 `/req-stage-gate` 时，先做一次 brief 二次确认——给 PM 重新审视 brief.md 的机会，再启动重的 `/req-analysis`。

   AI 重新读一遍 `brief.md`，给一句话摘要 + A/B 闸门：

   ```
   📝 brief.md：`$ACTIVE_REQ_DIR/brief.md`

   一句话摘要：[新对话重新读出来的核心内容，一行]

   A) 确认，进入 stage 2（调用 /req-analysis）
   B) 我要修改（说明改哪里）
   ```

   - PM 选 A → 继续步骤 3 调 `/req-analysis`
   - PM 选 B → 按 PM 指示改 `brief.md`，改完回到本步骤重新出 A/B
   - **brief.md 修改完只输出"已改完，请确认"的二次摘要 + A/B**，不贴全文（参见本文末 `Rules` 的"确认门只给路径 + 一句话摘要"规则）

3. **调用 `/req-analysis`**
   - skill 内部完成：读 brief + CONTEXT、第一性原理 4 层分析、写 analysis.md（含 10 章 + `## 未决问题` section）、调 analysis-reviewer 一次后把报告原文贴 chat，让 PM 三选一（AI 改 / PM 自改 / 接受现状）
   - skill 返回 = **PM 已看过 reviewer 报告原文 + 已显式做出处理决定**；返回值带 `review_outcome ∈ {PASS, ACCEPTED_WITH_ISSUES}`
   - **orchestrator 不重调 reviewer**；如 `review_outcome=ACCEPTED_WITH_ISSUES`，stage-gate 在最终推进确认门加一行知会："⚠️ analysis 评审 NEEDS_REVISION，PM 已显式接受继续推进"——但**不阻塞**推进
4. **未决问题闸门（Stage 2 → 3 推进的硬约束）：**

   grep `## 未决问题` section 下的 `**PM 回答：**` 条目：
   - **若存在任何 `**PM 回答：**` 后面为空** → 确认门进入"答题模式"：
     ```
     📝 analysis.md 已写入：`$ACTIVE_REQ_DIR/analysis.md`

     一句话摘要：[本次分析的核心结论，一行]

     ⚠️ 本 analysis 有 N 个未决问题需要 PM 先回答，stage 3 暂不开放。

     A) 逐题回答（推荐，我会把答案写回 analysis.md 的 §未决问题）
     B) 修改 analysis（说明改哪里）
     ```
     **不允许**提供"直接进 stage 3"的选项——这是硬规则，没有例外也没有 FORCE 逃生舱
   - **若全部 `**PM 回答：**` 都已有内容**（或 section 明确写"本 req 无未决问题"）→ 确认门进入"推进模式"：
     ```
     📝 analysis.md 已写入：`$ACTIVE_REQ_DIR/analysis.md`

     一句话摘要：[本次分析的核心结论，一行]
     [若 review_outcome=ACCEPTED_WITH_ISSUES，加一行：⚠️ analysis 评审 NEEDS_REVISION，PM 已显式接受继续推进]

     A) 确认，进入 stage 3（方案设计）
     B) 我要修改（说明改哪里）
     C) 跳过 stage 3 直接到 stage 5（后续 req 可选，first req 不建议）
     ```
     （first req 不显示 C 选项）

5. **PM 回答未决问题的处理：**
   - PM 选 A 后，逐题展示问题，PM 每回答一题，把答案写回 analysis.md 对应 `**PM 回答：**` 后面
   - 所有问题答完 → 重新 grep 验证 → 解锁推进选项 → 回到步骤 4 的"推进模式"
   - PM 在答题过程中临时想改 analysis 某段 → 允许中途切到 B（修改 analysis）→ 改完后**回到步骤 3 重调 /req-analysis**（analysis 改过，reviewer 必须重跑一次；由 /req-analysis 步骤 4-5 的"调一次 + 三选一"机制保证），再走步骤 4 闸门

推进命令（确认进入 stage 3 后才执行）：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 2
```

### Stage 2 → 3（需求分析 → 方案设计）

PM 选择进入 stage 3 时：

1. **调用 `/req-solution`**
   - skill 内部完成：Discovery 缺口提问（如有）、写 solution.md（含 10 章 + Mermaid + 7.2 各模块说明）
   - skill 返回时 solution.md 已落盘
2. **输出"推荐 review 工具"区块给 PM**（不自动调任何 review）：

   ```
   ✅ solution.md 已写入：$ACTIVE_REQ_DIR/solution.md

   可选 review（PM 自行选跑，跑完把结论贴回这里我帮你 append 事件）：
     /plan-ceo-review     — 战略：范围与产品野心
     /plan-eng-review     — 架构、数据流、边界
     /plan-design-review  — 交互与视觉层问题
     /autoplan            — 上述 plan-* 的批量打包

   跑哪几个由你决定，全跳也可以。
   ```

   PM 跑完任一 review 后报告结论 → AI 调 `task-events.py append` 记 `plan_review_completed`（task 文件不存在时此处可省略，仅做口述确认）；事件流仅作审计记录，不当 gate（I-RV1/I-RV2）。
3. **确认门**：只给绝对路径（`$ACTIVE_REQ_DIR/solution.md`）+ 一句话摘要；review 结果（如有）直接贴 chat。问 PM：
   - PM 确认 → 进入 **3.5 reconcile 步骤**，再推进
   - PM 提修改意见 → 回步骤 1 调 `/req-solution`（**revise 模式**：prompt 含 "PM 在确认门提了修改：…"；skill 只改 PM 视图、不动工程合同、hash 留 stale）→ 改完后重新输出推荐区块（PM 可决定要不要再跑一遍 review）→ 再次确认

3.5 **reconcile 步骤**（PM-VIEW-RULES §9.6，PM 选确认后、`req-transition.py` 之前必跑）：

调用 `/req-solution` 进入 **reconcile 模式**：

```
/req-solution（reconcile 模式）

stage-gate 在 stage 2→3 PM 已确认 solution.md，进入 reconcile：
- 比对 solution.md 当前 hash 与 solution.engineering.md 顶部 synced_pm_view_hash
- 不一致 → 重派生 PM 视图驱动章节、刷新 hash、追加变更记录
- 一致 → no-op
完成后输出 "reconcile 完成"信号，控制权回 stage-gate
```

skill 返回 reconcile 完成 / no-op 后，stage-gate 跑步骤 3.6 行数 lint，再跑 `req-transition.py --to 3`。

3.6 **行数 lint**（v2 文档输出深度指引硬约束）：

```bash
python3 .claude/scripts/check-engineering-doc-size.py --req-dir "$ACTIVE_REQ_DIR"
```

- **退出 0** → 直接进推进；
- **退出 1（有文件超限）** → stage-gate **不直接硬阻塞**，而是给 PM 选项：

  ```
  ⚠️ solution.engineering.md 超过原型档行数上限（实测 N 行 / 上限 300 行）
  超限通常意味着 AI 重抄了 PM 视图内容（参见 lint 输出的修法）。

  A) 调 /req-solution（reconcile 模式）让 AI 裁剪重写超限段落（推荐）
  B) PM 自己改文件后回来选 A/C
  C) 接受超限，强制推进（请说明理由，记到 `[OVERRIDE-DOCSIZE]` 注释里）

  请选 A / B / C：
  ```

  - PM 选 A → 调 /req-solution（reconcile 模式）+ prompt 含 "lint 报超限：N 行；按强制引用规则裁剪 §X / §Y" → 完成后回来重跑 lint（最多 3 次循环，仍超限时停下问 PM）
  - PM 选 B → 等 PM 改完，回 3.6 重跑 lint
  - PM 选 C → 在 `solution.engineering.md` 末尾追加 `<!-- OVERRIDE-DOCSIZE: <YYYY-MM-DD> reason: <PM 理由> -->`，记入 `req-meta.json` 的 `overrides` 字段后放行

PM 选择跳过 stage 3 时（不调 /req-solution，也不跑 reconcile / lint）：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 5 --skip-stage 3
```

正常推进（reconcile + lint 完成后）：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 3
```

### Stage 3 → 4（方案设计 → 设计系统建立）

1. 检查 `docs/DESIGN.md` 是否已有实质内容
2. **已有内容**：**问 PM** "设计系统已有，这次需要更新吗？"
   - PM 说不用 → 跳到 stage 5
     ```bash
     python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 5
     ```
   - PM 说要更新 → 进入 stage 4
3. **无内容（空骨架）**：进入 stage 4

推进到 stage 4：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 4
```

### Stage 4（设计系统建立）

1. 调用 `/design-consultation`（gstack skill）建立 `docs/DESIGN.md`
2. PM 确认设计系统后，确认门："设计系统已建立，是否进入 task 规划？"

推进：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 5
```

### Stage 4 → 5（→ 模块规格 + task 拆分）

调用 `/task-plan` 执行 stage 5 工作。

推进：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 5
```

### Stage 5 → 6（task 规划 → task 执行）

1. 检查 `task-plan.md` 存在。
2. 检查 `task-plan.md` 包含 task 标题列表和 `## 变更记录` section。
3. **输出"推荐 review 工具"区块给 PM**（不自动调任何 review）：

   ```
   ✅ task-plan.md 已写入：$ACTIVE_REQ_DIR/task-plan.md

   可选 review（PM 自行选跑，跑完贴结论）：
     /plan-eng-review     — 拆分合理性、依赖、并行性
     /plan-design-review  — UI task 划分是否完整
     /autoplan            — 上述 plan-* 的批量打包

   跑哪几个由你决定，全跳也可以。具体 task 文件在 stage 6 的 /task-spec 阶段还会再次推荐 review。
   ```
4. 确认门（只给绝对路径 + 一句话摘要，不贴全文；review 结果（如有）直接贴 chat）："Task 规划完成，是否进入执行阶段？"
   - PM 确认 → 推进 stage 6。
   - PM 提修改意见 → 回 `/task-plan` 改 `task-plan.md` → 改完后重新输出推荐区块 → 再次确认。

> stage 5→6 只审阅 `task-plan.md`；具体 task 文件由 stage 6 的 `/task-spec` 逐个生成，写完后由 task-spec 步骤 8 再次输出推荐 review 区块。

推进：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 6
```

### Stage 6 → 7（task 执行 → req close）

1. Read `task-plan.md`, extract task id list, and exclude ids marked deleted in the `## 变更记录` section.
   - 变更记录 exclusion algorithm：解析 task-plan.md 文末 `## 变更记录`（如果存在），找到包含关键词 `删除` 的条目，从条目中提取 `task-001` / `task-002` 这类 task-id，并从 verification list 排除。
2. For each id verify:
   - `tasks/task-NNN-*.md` file exists。
   - task status is `「已完成」`。
   - task branch has been merged to req branch（等价于 `/close-task` 已跑完）。
   - task worktree has been cleaned up。
   - C2 half-close detection（CRITICAL）：如果 task 的 `## 文档偏差` section 同时含 `<!-- SKIP_DOC_UPDATE:` 字符串 AND `cleanup_status="pending"` 字符串（即 close-task 写入的 SKIP_DOC_UPDATE marker 且 cleanup 尚未完成），说明曾用 `close-task --skip-doc-update` 半关闭且 PM 还没补做沉淀；NOT treated as complete close，必须阻塞推进并列出 cleanup TODOs。`cleanup_status="done"` 视为已 cleanup（marker 保留作 audit trail），不阻塞。
3. All satisfied → confirmation gate: "所有 task 已完成并关闭，是否关闭此需求？"
4. Not satisfied → list which tasks are missing which steps。

缺失项输出格式：

```text
Stage 6 → 7 blocked: 以下 task 尚未完整关闭

- task-001:
  - missing task file: 请运行 /task-spec task-001 或从 task-plan.md 删除该条
- task-002:
  - status is 执行中: 请在 task 窗口完成 PM 验收（task-submit 呈交块）+ /close-task
  - task branch not merged to req branch: 请运行 /close-task
- task-003:
  - task worktree still exists: 请确认 /close-task 清理完成
- task-004:
  - half-close detected: 文档偏差 section 含 SKIP_DOC_UPDATE marker 且 cleanup_status="pending"；请完成 cleanup TODO（手动跑 /doc-update 沉淀功能清单），将 marker 的 cleanup_status 改为 "done"，再重跑 /req-stage-gate
```

边界情况：

- task in task-plan.md but task file not yet generated → judgment fails，prompt PM to run `/task-spec <task-id>` or remove it from `task-plan.md`。
- Infrastructure tasks → same close requirement；doc-update 会 auto-skips module merge，但仍必须完成 `/close-task` 的 branch merge 和 worktree cleanup。
- task 文件存在但不在 task-plan.md，且未在 `## 变更记录` 中说明 → 不作为关闭条件来源；提示 PM 校验是否需要补回 task-plan.md 或删除孤儿 task 文件。

推进：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 7
```

然后调用 `/close-req`。

## Rules

- 每个 stage 结束必须显式问 PM 确认，不能自动跳过确认门
- **确认门只给绝对路径 + 一句话变更摘要，不贴文档全文。** PM 的 IDE 已经挂在 worktree 上，文件在左侧目录树里可见，不需要把内容贴回 chat
- **确认门格式**：
  ```
  📝 <filename> 已写入：`$ACTIVE_REQ_DIR/<filename>`

  一句话摘要：[最新变更或核心内容，一行]

  A) 确认，进入 stage <N+1>
  B) 我要修改（请说明改哪里）
  ```
- **review 工具一律 PM 自跑**（I-RV1）：stage-gate 在产物写完后只输出推荐清单，不自动调任何 `/plan-*-review` / `/review` / `/qa` / `/design-review`。PM 跑完任一 review 后口述结论，AI 调 `task-events.py append` 机械记录事件作为审计痕迹；事件流不当 gate
- **stage 2→3 双文件 reconcile**（PM-VIEW-RULES §9.6）：PM 选确认后、`req-transition.py --to 3` 之前必跑 `/req-solution`（reconcile 模式）对齐 `solution.engineering.md`；revise 模式时只改 PM 视图、工程合同保持 stale
- review 结果（PM 跑完贴回 chat 的）允许直接贴 chat——review 是讨论内容，不是文档产出
- **未决问题闸门（硬规则）**：任何 stage 的产出文档如果含有"需要 PM 回答"的未决项，确认门必须先让 PM 答完再开放推进选项。不允许并列给出"直接推进"和"回答问题"两个选项让 PM 选——这会让 PM 绕过未回答的问题。目前最严格落地在 Stage 1→2（analysis.md 的 `## 未决问题` section），其他 stage 如有类似未决产出应比照处理
- 推进命令只能用 `req-transition.py`，不能手动改 `.req-meta.json`
- Stage 4 的 DESIGN.md 内容检测由 `req-transition.py` 自动处理
- 回退场景：PM 说要回到之前的 stage 时，使用 `--rollback` 参数
  ```bash
  python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to <target> --rollback
  ```
