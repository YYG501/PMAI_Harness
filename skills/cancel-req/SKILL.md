---
name: pmai-cancel-req
description: |
  废弃当前 req：确认后清理所有 worktree 和分支，标记 cancelled，不 merge 到 main。
---

# /pmai-cancel-req

## When To Use

- PM 在任何 stage 调用，决定废弃当前需求

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: cancel-req"
```

## Workflow

### 步骤 1：确认废弃

向 PM 确认：

```
即将废弃需求：$ACTIVE_REQ（stage $ACTIVE_REQ_STAGE）

此操作会：
- 标记所有 task worktree/分支为待清理（杀 dev server、删 .runs/）
- 标记 req worktree/分支为待清理
- 标记为 cancelled 并移到 closed/
- 不会 merge 任何改动到 main
- 完成后需要回主仓跑一次 cleanup 才会真正删除 worktree/branch

确认废弃？（Y/N）
```

如果 PM 犹豫或不确定，建议 PM 运行 `/pmai-task-status` 先查看当前状态。

### 步骤 2：执行废弃

PM 确认后：

```bash
bash "$PMAI_HOME/scripts/cancel-req.sh" "$ACTIVE_REQ_DIR"
```

脚本自动执行：
1. 杀 dev server + 删 `.runs/` 原件 + 把每个 task worktree/branch 写入 pending
2. 切回 main 分支
3. 把 req worktree/branch 写入 pending
4. 标记 `.req-meta.json` 状态为 cancelled
5. 移动 req 目录到 `requirements/closed/`
6. **若该 req 已写过 prd.md**，建 `docs/prds/废弃/<req-name>.md` symlink 收口（范围确认 / build 阶段 cancel 时无 prd.md 自动 silent skip）
7. commit
8. 提示 PM：回主仓后跑 `bash scripts/cleanup-pending-worktrees.sh` 完成 worktree/branch 清理

### 步骤 3：确认结果

```
Req 已废弃：$ACTIVE_REQ
当前位置：主仓 main 分支
Main 分支未受影响（零污染）。

worktree 和 branch 待清理。请退出当前会话，回主仓后跑：
  bash scripts/cleanup-pending-worktrees.sh

运行 /pmai-new-req 开始新需求。
```

## Rules

- 必须先问 PM 确认，不能静默废弃
- 废弃不 merge 到 main，main 零污染
- 清理由 cancel-req.sh + cleanup-pending-worktrees.sh 统一处理，不要手动操作
- 废弃后 req 目录保留在 closed/ 中，status 为 cancelled
- worktree/branch 不会被 cancel-req.sh 立即删除（避免 PM 在被删 worktree 内调用导致 Stop hook posix_spawn ENOENT）；实际删除由 PM 在主仓 cwd 跑 cleanup 完成
