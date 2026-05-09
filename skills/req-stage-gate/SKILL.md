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

# worktree 残留检测（informational，不阻塞推进；有问题仅打印警告供 PM 处理）
python3 "$REPO_ROOT/.claude/scripts/check-worktree-residue.py" || true
```

读取 `$ACTIVE_REQ_STAGE` 确定当前 stage。

如果 worktree 残留检测报警，先把警告原文展示给 PM 一句话说明（"发现 N 个 worktree 残留/冲突，已贴上方"），PM 可选择立刻清理或继续推进。不当 gate（参见 I-RT5 的范围）。

## Stage 过渡逻辑

### Stage 1 → 2（感受问题 → 需求分析）

1. 检查 `brief.md` 存在且有内容
2. **brief 二次确认门**（新对话首次进入 worktree 时的入口闸）：

   `/new-req` 在主对话写完 brief.md 后就 handoff 退场，PM 在 worktree 内新对话里第一次跑 `/req-stage-gate` 时，先做一次 brief 二次确认——给 PM 重新审视 brief.md 的机会，再启动重的 `/req-analysis`。

   AI 重新读一遍 `brief.md`，给一句话摘要 + 对话式确认（v2 风格）：

   ```
   ✅ brief.md
      <$ACTIVE_REQ_DIR/brief.md 绝对路径>

   📋 一句话摘要
      <新对话重新读出来的核心内容，一行>

   ——这份 brief 就这样定吗？OK 我开始做需求分析；想改的说哪里。
   ```

   **PM 回答的内部分流**（不列 A/B 字母）：
   - PM 说「OK / 通过 / 没问题 / 定了」等 → 继续步骤 3 调 `/req-analysis`
   - PM 提具体修改 → 按 PM 指示改 `brief.md`，改完后**只输出"已改完"二次摘要**（同一份模板，"一句话摘要"段填新内容），不贴全文

3. **调用 `/req-analysis`**
   - skill 内部完成：读 brief + CONTEXT、第一性原理 4 层分析、写 analysis.md（含 10 章 + `## 未决问题` section）、调 analysis-reviewer 一次后把报告原文贴 chat，让 PM 三选一（AI 改 / PM 自改 / 接受现状）
   - skill 返回 = **PM 已看过 reviewer 报告原文 + 已显式做出处理决定**；返回值带 `review_outcome ∈ {PASS, ACCEPTED_WITH_ISSUES}`
   - **orchestrator 不重调 reviewer**；如 `review_outcome=ACCEPTED_WITH_ISSUES`，stage-gate 在最终推进确认门加一行知会："⚠️ analysis 评审 NEEDS_REVISION，PM 已显式接受继续推进"——但**不阻塞**推进
4. **未决问题闸门（Stage 2 → 3 推进的硬约束）：**

   调用 lint 脚本：

   ```bash
   python3 .claude/scripts/check-open-questions.py "$ACTIVE_REQ_DIR/analysis.md"
   ```

   - **退出码 1**（有未答）→ 确认门进入"答题模式"，stdout 给出未答题号 + 行号：
     ```
     ✅ analysis.md 已写入
        <$ACTIVE_REQ_DIR/analysis.md 绝对路径>

     📋 一句话摘要
        <本次分析的核心结论，一行>

     ⚠️ 这份 analysis 留了 <N> 个未决问题需要你先回答——推进到下一步前必须先答完，不能跳过。

     要怎么处理？
      - 我逐题问你（推荐，答完我把答案写回 analysis.md）
      - 你想先改 analysis 某段（说哪里）
     ```
     **不允许**提供"直接推进"选项——这是硬规则，没有例外也没有 FORCE 逃生舱
   - **退出码 0**（全部已答 / section 写"本 req 无未决问题" / section 不存在）→ 确认门进入"推进模式"：
     ```
     ✅ analysis.md 已写入
        <$ACTIVE_REQ_DIR/analysis.md 绝对路径>

     📋 一句话摘要
        <本次分析的核心结论，一行>

     [若 review_outcome=ACCEPTED_WITH_ISSUES 加一行：]
     ⚠️ 这份 analysis 评审标了"可以继续但有待改进"，你之前显式接受了，继续推进。

     ——这份 analysis 就这样定吗？OK 我推进到方案设计；想改的说哪里。
     ```
     （所有 req 默认都走方案设计阶段，不再提供"跳过"选项）

5. **PM 回答未决问题的处理**：
   - PM 选"逐题问你"分支后，逐题展示问题，PM 每回答一题，把答案写回 analysis.md 对应 `**PM 回答：**` 后面
   - 所有问题答完 → 重跑 `check-open-questions.py` 验证（退出码 0）→ 解锁推进选项 → 回到步骤 4 的"推进模式"
   - PM 在答题过程中临时想改 analysis 某段 → 允许中途切到"改 analysis"分支 → 改完后**回到步骤 3 重调 /req-analysis**（analysis 改过，reviewer 必须重跑一次；由 /req-analysis 步骤 4-5 的"调一次 + 三选一"机制保证），再走步骤 4 闸门

推进命令（确认进入 stage 3 后才执行）：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 2
```

### Stage 2 → 3（需求分析 → 方案设计）

PM 选择进入 stage 3 时：

1. **调用 `/req-solution`**
   - skill 内部完成：Discovery 缺口提问（如有）、写 solution.md（含 10 章 + Mermaid + 7.2 各模块说明）、跑 lint 并让 PM 在 skill 内完成所有 warning 决策
   - skill 返回时 solution.md 已落盘、所有 warnings 已 PM 处理完毕（详见 `req-solution/SKILL.md` 步骤 5.5：warnings 在 skill 内闭环，**不**传递给 stage-gate 二次显示）

1.5 **review 触发前 reconcile**（输出推荐 review 区块**前**必跑，PM 不感知；`_shared/pm-view/input-flow.md` §9.6.1 / §9.6.5 review 触发行为）：

调用 `/req-solution`（reconcile 模式）：比对 `solution.md` 当前 hash 与 `solution.engineering.md` 顶部 `synced_pm_view_hash` →
- 一致 → no-op，立即进入步骤 2
- stale → 重派生 PM 视图驱动章节、刷新 hash、追加变更记录 → 完成后进入步骤 2

理由：步骤 2 给 PM 看的"推荐 review"区块默认 PM 会跑 `/plan-eng-review` 等 review skill，review 必须双读 PM 视图 + 工程合同两文件已同步状态（input-flow §9.1 stage 4 review 模式）。stale 工程合同会让 review 出噪声 finding（例如找出"已被 PM 视图删除的旧概念"）。

2. **输出确认门**（一份完整模板，把产物落地 / 摘要 / 可选 review / 确认问句拼成单次输出；不分两轮发）：

   ```
   ✅ solution.md 已写入
      <$ACTIVE_REQ_DIR/solution.md 绝对路径>

   📋 一句话摘要
      <一行核心决策摘要——本次方案的关键选择 / 重做范围 / 决策数 等>

   📊 可选 review（你自跑，跑完贴结论我帮你 append 事件）
      /plan-ceo-review     — 战略：范围与产品野心
      /plan-eng-review     — 架构、数据流、边界
      /plan-design-review  — 交互与视觉层问题
      /autoplan            — 上述 plan-* 的批量打包

      跑哪几个你定，全跳也行。

   ——这份方案就这样定吗？OK 我就把方案设计阶段定下来，进入下一步（设计系统建立）；想改的地方说哪里。
   ```

   **模板要点**：
   - 三段标题用 emoji 锚点（✅ / 📋 / 📊）让 PM 视线快速分段
   - 路径独立缩进，不挤标题行
   - **不显示** `.engineering.md` 文件名 / hash 值 / "reconcile 同步" / "行数 lint" / "进入 stage 3"等工程黑话（PM 视角只关心 PM 视图主文件 + 下一阶段名称；详见 `task-spec/SKILL.md` 步骤 12 上方禁词清单，本闸门同样适用）
   - **禁止再加 ⚠️ lint 待办 / lint warnings 摘要等"传话块"**：lint 处理已在 /req-solution 内闭环，PM 在 stage-gate 不需要再看一遍自己几秒前的决策（这种二次显示用了 PM 不熟悉的内部术语—"骨架 / 合法屏幕字 / 退出时已确认的处理方式"—只会让 PM 困惑而无 actionable 内容）
   - 确认问句对话式：「这份方案就这样定吗？OK 我就……；想改的说哪里。」不列 A/B 字母选项也不列"放弃"

   PM 跑完任一 review 后报告结论 → AI 调 `task-events.py append` 记 `plan_review_completed`（task 文件不存在时此处可省略，仅做口述确认）；事件流仅作审计记录，不当 gate（I-RV1/I-RV2）。

3. **PM 回答的内部分流**（chat 不列 A/B 选项；按 PM 自然语言意图）：
   - PM 说「OK / 通过 / 没问题 / 定了」等 → 走"确认"分支：进入 3.5 reconcile safety net + 3.6 行数 lint（PM 看不到这两步，AI 内部默默跑），再 `req-transition.py --to 3`
   - PM 提具体修改意见 → 走"修改"分支：回步骤 1 调 `/req-solution`（**revise 模式**：prompt 含 "PM 在确认门提了修改：…"；skill 只改 PM 视图、不动工程合同、hash 留 stale）→ 自动回到步骤 1.5（review 触发前 reconcile，hash 自然 stale）→ 重新输出步骤 2 完整模板（PM 可决定要不要再跑一遍 review，此时双文件已对齐）→ 再次询问
   - PM 说「放弃这个 req / 不做了」 → 走"放弃"分支：提示 PM 跑 `/cancel-req`（**chat 模板里不主动列出此选项**，PM 主动提才走）

3.5 **reconcile safety net**（`_shared/pm-view/input-flow.md` §9.6 gate-pass 兜底；正常情况下应是 no-op，因为步骤 1.5 已对齐）：

调用 `/req-solution` 进入 **reconcile 模式**：

```
/req-solution（reconcile 模式）

stage-gate 在 stage 2→3 PM 已确认 solution.md，gate-pass 兜底 reconcile：
- 比对 solution.md 当前 hash 与 solution.engineering.md 顶部 synced_pm_view_hash
- 一致 → no-op（预期路径：步骤 1.5 已对齐）
- 不一致 → 重派生 PM 视图驱动章节、刷新 hash、追加变更记录（异常路径：1.5 后 PM 又改了 PM 视图但跳过了 1.5 重跑）
完成后输出 "reconcile 完成"信号，控制权回 stage-gate
```

skill 返回 reconcile 完成 / no-op 后，stage-gate 跑步骤 3.6 行数 lint，再跑 `req-transition.py --to 3`。

3.6 **行数 lint**（v2 文档输出深度指引硬约束；PM 看不到这一步，除非 lint 报超限需要决策）：

```bash
python3 .claude/scripts/check-engineering-doc-size.py --req-dir "$ACTIVE_REQ_DIR"
```

- **退出 0** → 直接进推进；
- **退出 1（有文件超限）** → stage-gate **不直接硬阻塞**，给 PM 一个对话式弹窗（不列 A/B/C 字母）：

  ```
  ⚠️ 工程版方案文档超出长度上限（实测 <N> 行 / 上限 300 行）

  超限通常是 AI 把 PM 视图内容重抄到工程版了——把这部分压回引用通常就修好。

  要怎么办？
   - 让我裁剪重写超限段落（推荐）
   - 你自己改完，告诉我让我再 lint 一次
   - 接受超限直接推进（说一下理由，我记到文件注释里作存档）

  你选哪种？
  ```

  **PM 回答的内部分流**（按自然语言意图，不列字母）：
   - PM 说「裁剪 / 让你改 / 推荐那个」等 → 调 /req-solution（reconcile 模式）+ prompt 含 "lint 报超限：N 行；按强制引用规则裁剪 §X / §Y" → 完成后回来重跑 lint（最多 3 次循环，仍超限时停下问 PM）
   - PM 说「我改完了 / 我自己改 / 改好了再 lint」 → 等 PM 改完，回 3.6 重跑 lint
   - PM 说「接受超限 / 强制推进，理由是 X」 → 在 `solution.engineering.md` 末尾追加 `<!-- OVERRIDE-DOCSIZE: <YYYY-MM-DD> reason: <PM 理由> -->`，记入 `req-meta.json` 的 `overrides` 字段后放行

推进（reconcile + lint 完成后）：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 3
```

### Stage 3 → 4（方案设计 → 设计系统建立）

1. 检查 `docs/DESIGN.md` 是否已有实质内容
2. **已有内容**：对话式问 PM：

   ```
   🎨 设计系统已存在（docs/DESIGN.md 有内容）

   这次需要更新设计系统吗？
    - 不用，直接跳到 task 规划
    - 要更新（说一下哪里要改）
   ```

   - PM 说「不用 / 不需要 / 跳过」 → 直接推进到 stage 5
     ```bash
     python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 5
     ```
   - PM 提具体修改意图 → 进入 stage 4

3. **无内容（空骨架）**：直接进入 stage 4，无需问 PM

推进到 stage 4：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 4
```

### Stage 4（设计系统建立）

1. 调用 `/design-consultation`（gstack skill）建立 `docs/DESIGN.md`
2. PM 确认设计系统后，对话式确认门：

   ```
   ✅ 设计系统已建立
      docs/DESIGN.md

   ——设计系统就这样定吗？OK 我推进到 task 规划；想改的说哪里。
   ```

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
3. **输出确认门**（一份完整模板，对齐 stage 2→3 风格）：

   ```
   ✅ task-plan.md 已写入
      <$ACTIVE_REQ_DIR/task-plan.md 绝对路径>

   📋 一句话摘要
      <共 N 个 task；业务模块 X 个 + 基础设施 Y 个；最长依赖链 …>

   📊 可选 review（你自跑，跑完贴结论我帮你 append 事件）
      /plan-eng-review     — 拆分合理性、依赖、并行性
      /plan-design-review  — UI task 划分是否完整
      /autoplan            — 上述 plan-* 的批量打包

      跑哪几个你定，全跳也行。具体 task 文件在下一阶段（task 执行）的 /task-spec 还会再推荐一次。

   ——这份 task 规划就这样定吗？OK 我推进到 task 执行阶段；想改的说哪里。
   ```

4. **PM 回答的内部分流**（不列字母）：
   - PM 说「OK / 通过 / 没问题 / 定了」等 → 推进 stage 6
   - PM 提具体修改意见 → 回 `/task-plan` 改 `task-plan.md` → 改完后重新输出步骤 3 完整模板 → 再次询问

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
3. All satisfied → 对话式确认门：

   ```
   ✅ 所有 task 已完成并关闭

   📋 一句话摘要
      <N 个 task 全部 close、worktree 全部清理>

   ——这个需求就关闭吗？OK 我推进到关闭流程；想再开新 task 说一声。
   ```

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
- **确认门标准格式**（v2，对话式；stage 2→3 已落地见上方步骤 2 模板，其他 stage 后续逐步对齐）：
  - emoji 锚点分段（✅ 路径 / 📋 摘要 / 📊 可选 review；条件块 ⚠️ lint 待办）
  - 路径独立缩进，不挤标题行
  - 文末用对话式问句结尾（如「这份方案就这样定吗？OK 我就……；想改的说哪里。」），**不列 A/B 字母选项**
  - **不主动列"放弃 req"选项**（PM 真要放弃直接说「放弃这个 req / cancel」，AI 提示走 `/cancel-req`）
- **PM chat 输出禁工程黑话**（与 `task-spec/SKILL.md` 步骤 12 上方禁词清单等价）：所有 stage 的确认门 / lint 弹窗 / 任何给 PM 看的 chat 文本里**严禁**出现 `hash` / 12 位 hash 值 / `synced_pm_view_hash` / `reconcile` / `reconcile 模式` / `stale` / `行数 lint` / `步骤 N.M` 内部编号 / `lazy sync` / `MODE=revise` 等内部状态机术语；解释段也禁出现 `.engineering.md` 文件名（路径行除外）。这些都是 AI 内部记账，PM 没有动作可做
- **review 工具一律 PM 自跑**（I-RV1）：stage-gate 在产物写完后只输出推荐清单，不自动调任何 `/plan-*-review` / `/review` / `/qa` / `/design-review`。PM 跑完任一 review 后口述结论，AI 调 `task-events.py append` 机械记录事件作为审计痕迹；事件流不当 gate
- **stage 2→3 双文件 reconcile**（`_shared/pm-view/input-flow.md` §9.6 / §9.6.5）：双触发点——
  - **review 触发前**（步骤 1.5，必跑）：每次 /req-solution 写完 solution.md 后、向 PM 输出"推荐 review"区块**前**先调 reconcile，确保 PM 跑 review 时双文件已同步（input-flow §9.6.1 review 触发行）；revise 后回到步骤 2 同样走 1.5
  - **gate-pass 兜底**（步骤 3.5，正常 no-op）：PM 选确认后、`req-transition.py --to 3` 之前再跑一次作为 safety net；revise 模式时只改 PM 视图、工程合同保持 stale，下一次步骤 1.5 / 3.5 时再 reconcile
  **两步 PM 都看不到**（AI 内部默默跑），不发"reconcile 完成"通知
- review 结果（PM 跑完贴回 chat 的）允许直接贴 chat——review 是讨论内容，不是文档产出
- **未决问题闸门（硬规则）**：任何 stage 的产出文档如果含有"需要 PM 回答"的未决项，确认门必须先让 PM 答完再开放推进选项。不允许并列给出"直接推进"和"回答问题"两个选项让 PM 选——这会让 PM 绕过未回答的问题。机器校验由 `scripts/check-open-questions.py` 承担：扫 `## 未决问题` section 下的 `**PM 回答：**` 占位，任一未填 → 退出 1。目前最严格落地在 Stage 1→2（analysis.md），其他 stage 如有类似未决产出 section 直接复用本脚本
- 推进命令只能用 `req-transition.py`，不能手动改 `.req-meta.json`
- Stage 4 的 DESIGN.md 内容检测由 `req-transition.py` 自动处理
- 回退场景：PM 说要回到之前的 stage 时，使用 `--rollback` 参数
  ```bash
  python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to <target> --rollback
  ```
