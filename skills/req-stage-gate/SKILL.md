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
5. 确认门（贴出 analysis.md 全文）：
   - **first req**：直接提示进入 stage 3
   - **后续 req**：询问 PM "是否进入 stage 3（方案设计），还是跳过直接到 stage 5？"

推进命令：
```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 2
```

### Stage 2 → 3（需求分析 → 方案设计）

PM 选择进入 stage 3 时：
1. 读取 `analysis.md`，做系统分层、模块边界设计
2. 写 `design.md` 到 req 目录
3. **gstack 质量审阅**（design.md 写完后）：
   - **first req**：自动运行 `/plan-ceo-review` 审阅 design.md（CEO 视角：挑战方案假设、范围合理性）
   - **后续 req**：建议 PM "要不要跑 /plan-ceo-review？"，PM 可跳过
4. 确认门（贴出 design.md 全文）："方案设计完成，是否继续？"

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
4. 确认门（贴出 task-plan.md 全文）："Task 拆分完成，是否进入执行阶段？"

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
- **确认门必须把该 stage 的完整产出文档贴给 PM 看**（analysis.md / design.md / task-plan.md 全文），不只是摘要。PM 不应该需要自己去 worktree 路径里找文件
- 推进命令只能用 `req-transition.py`，不能手动改 `.req-meta.json`
- Stage 4 的 DESIGN.md 内容检测由 `req-transition.py` 自动处理
- 回退场景：PM 说要回到之前的 stage 时，使用 `--rollback` 参数
  ```bash
  python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to <target> --rollback
  ```
