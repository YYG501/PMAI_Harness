---
name: cancel-req
description: |
  废弃当前 req：确认后清理所有 worktree 和分支，标记 cancelled，不 merge 到 main。
---

# /cancel-req

## When To Use

- PM 在任何 stage 调用，决定废弃当前需求

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: cancel-req"
```

## Workflow

### 步骤 1：确认废弃

向 PM 确认：

```
即将废弃需求：$ACTIVE_REQ（stage $ACTIVE_REQ_STAGE）

此操作会：
- 关闭所有该 req 下的 task（杀 dev server、清 worktree/分支）
- 清理 req worktree 和分支
- 标记为 cancelled 并移到 closed/
- 不会 merge 任何改动到 main

确认废弃？（Y/N）
```

如果 PM 犹豫或不确定，建议 PM 运行 `/status` 先查看当前状态。

### 步骤 2：执行废弃

PM 确认后：

```bash
bash .claude/scripts/cancel-req.sh "$ACTIVE_REQ_DIR"
```

脚本自动执行：
1. 清理所有 task worktree 和分支（含杀 dev server）
2. 切回 main 分支
3. 清理 req worktree 和分支
4. 标记 `.req-meta.json` 状态为 cancelled
5. 移动 req 目录到 `requirements/closed/`
6. commit

### 步骤 3：确认结果

```
Req 已废弃：$ACTIVE_REQ
当前位置：主仓 main 分支
Main 分支未受影响（零污染）。

运行 /new-req 开始新需求。
```

## Rules

- 必须先问 PM 确认，不能静默废弃
- 废弃不 merge 到 main，main 零污染
- 清理由 cancel-req.sh 统一处理，不要手动操作
- 废弃后 req 目录保留在 closed/ 中，status 为 cancelled
