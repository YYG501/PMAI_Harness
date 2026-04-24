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
2. 读取 `brief.md` + `docs/CONTEXT.md` + `docs/prd.md`
3. 做第一性原理分析：问题本质、用户真实需求、可行方案
4. 写 `analysis.md` 到 req 目录

   **analysis.md 必须包含的固定 section：**
   - `## 未决问题`（二级标题，逐题编号）——把 stage 2 分析过程中暴露出的、**必须由 PM 回答**的业务决定/政策/优先级问题全部列进来。每题格式：`### Q1: <问题标题>` + 题干 + 候选答案（如有）+ `**PM 回答：**`（初始留空占位）
   - 如果分析过程中**确实没有任何**需要 PM 回答的问题，该 section 下写一行 `（本 req 无未决问题）`——必须显式声明，不能省略 section

5. **强制调用 analysis-reviewer 做独立评审（硬规则，不可跳过）：**

   写完 analysis.md 初稿后，**必须**调用 Agent 工具，subagent_type 为 `analysis-reviewer`。这是第二视角独立评审，补 advisor 关闭后的盲点。

   调用示例：
   ```
   Agent(
     subagent_type="analysis-reviewer",
     description="Stage 2 analysis 独立评审",
     prompt="请评审以下 analysis.md：\n\n- analysis.md 绝对路径：$ACTIVE_REQ_DIR/analysis.md\n- brief.md 绝对路径：$ACTIVE_REQ_DIR/brief.md\n- docs/CONTEXT.md 绝对路径（如存在）：$REPO_ROOT/docs/CONTEXT.md\n\n按 agent 定义里的 4 条角度（摊隐藏业务决定 / 拆正交轴 / 边界清晰 / 未决问题完备）逐条评审，按规定格式输出。"
   )
   ```

   reviewer 返回评审报告后：
   - **NEEDS_REVISION** → 主线 AI 把报告贴在 chat 给 PM 看，然后**按 reviewer 给的"具体修改动作"修改 analysis.md**，修改完回到步骤 5 重新调 reviewer。循环直到 PASS
   - **PASS** → 把评审报告贴在 chat 给 PM 看（让 PM 知道评过），然后进入步骤 6 未决问题闸门

   **不允许的反模式**：
   - 跳过这一步直接去步骤 6（硬规则违反）
   - 把 reviewer 的 NEEDS_REVISION 结果藏起来不给 PM 看
   - 在 reviewer 未 PASS 的状态下开放 stage 3 推进选项

6. **未决问题闸门（Stage 2 → 3 推进的硬约束）：**

   在 analysis-reviewer 返回 PASS 后才进入这一步。grep `## 未决问题` section 下的 `**PM 回答：**` 条目：
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

     A) 确认，进入 stage 3（方案设计）
     B) 我要修改（说明改哪里）
     C) 跳过 stage 3 直接到 stage 5（后续 req 可选，first req 不建议）
     ```
     （first req 不显示 C 选项）

7. **PM 回答未决问题的处理：**
   - PM 选 A 后，逐题展示问题，PM 每回答一题，把答案写回 analysis.md 对应 `**PM 回答：**` 后面
   - 所有问题答完 → 重新 grep 验证 → 解锁推进选项 → 回到步骤 6 的"推进模式"
   - PM 在答题过程中临时想改 analysis 某段 → 允许中途切到 B（修改 analysis），改完后**必须回到步骤 5 重新调一次 analysis-reviewer**（analysis 改了就重评），再走步骤 6 闸门

推进命令（确认进入 stage 3 后才执行）：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 2
```

### Stage 2 → 3（需求分析 → 方案设计）

PM 选择进入 stage 3 时：
1. 读取 `analysis.md`，做系统分层、模块边界设计
2. 写 `solution.md` 到 req 目录
3. **自动调用 `/plan-ceo-review`** 审阅 solution.md（所有 req 都自动运行，不可跳过）
4. **确认门**：只给绝对路径（`$ACTIVE_REQ_DIR/solution.md`）+ 一句话摘要；**review 发现直接贴在 chat**（review 是讨论，不是文档产出）。问 PM：
   - PM 确认 → 推进到下一 stage
   - PM 提修改意见 → 修改 solution.md → 回到步骤 3 重新 review → 再次确认

PM 选择跳过 stage 3 时：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 5 --skip-stage 3
```

正常推进：
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

### Stage 5 → 6（task 拆分 → task 执行）

1. 检查 `task-plan.md` 存在
2. 检查 task 文件已创建
3. **gstack 质量审阅**（task-plan.md + task 文件生成后）：
   - **first req**：自动运行 `/plan-eng-review` 审阅 task-plan.md（工程视角：架构、拆分合理性、依赖）
   - **后续 req**：建议 PM "要不要跑 /plan-eng-review？"，PM 可跳过
4. 确认门（只给绝对路径 + 一句话摘要，不贴全文；eng-review 发现直接贴 chat）："Task 拆分完成，是否进入执行阶段？"

推进：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 6
```

### Stage 6 → 7（task 执行 → req close）

1. 检查所有 task 状态为「已完成」
2. 如果有未完成的 task，列出并提示 PM
3. 全部完成后，确认门："所有 task 已完成，是否关闭此需求？"

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
- **例外**：`/plan-ceo-review`、`/plan-eng-review` 等 review 工具的发现允许直接贴在 chat——review 是讨论内容，不是文档产出
- **未决问题闸门（硬规则）**：任何 stage 的产出文档如果含有"需要 PM 回答"的未决项，确认门必须先让 PM 答完再开放推进选项。不允许并列给出"直接推进"和"回答问题"两个选项让 PM 选——这会让 PM 绕过未回答的问题。目前最严格落地在 Stage 1→2（analysis.md 的 `## 未决问题` section），其他 stage 如有类似未决产出应比照处理
- 推进命令只能用 `req-transition.py`，不能手动改 `.req-meta.json`
- Stage 4 的 DESIGN.md 内容检测由 `req-transition.py` 自动处理
- 回退场景：PM 说要回到之前的 stage 时，使用 `--rollback` 参数
  ```bash
  python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to <target> --rollback
  ```
