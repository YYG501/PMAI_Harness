---
name: pmai-cancel
description: |
  放弃当前进行中的模块工作：确认后不合并工作分支，清除模块的活跃状态，并将关联隔离分支标记为待清理。
---

# /pmai-cancel

> 本 skill 是当前工作的退出口。它不判断需求是否“正确”，只在 PM 明确说这轮不要继续时，把活跃状态清掉，避免后续 `/pmai-status` / `/pmai-status` 继续把它当进行中工作。
>
> PM 视图规则按 `_shared/pm-view/banner-rules.md` 和 `_shared/pm-view/askuser-rules.md`：先确认，再执行；PM 未确认前不写文件、不 commit、不清理。

## When To Use

- PM 明确说当前工作不要继续、废弃、取消、放弃。
- 当前模块已有 `.work-meta.json` 活跃状态，需要清掉。
- 不用于完成收尾；完成并沉淀走 `/pmai-close`。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: cancel"

python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill CANCEL || true
```

## Workflow

### 步骤 1：确认放弃

先向 PM 确认：

```text
即将放弃当前工作：$ACTIVE_WORK（当前阶段：$ACTIVE_WORK_STAGE_NAME）

此操作会：
- 不合并当前工作分支
- 清掉模块的活跃状态文件
- 把关联的隔离工作区标记为待清理
- 如果已有 PRD，会在废弃区保留入口

确认放弃？（Y/N）
```

PM 犹豫或不确定时，建议先运行 `/pmai-status` 看清当前状态。

### 步骤 2：执行放弃

PM 确认后：

```bash
bash "$PMAI_HOME/scripts/cancel-work.sh" "$ACTIVE_WORK_DIR"
```

脚本真实行为：

1. 切回 main，并拒绝污染 main 上无关改动。
2. 删除当前模块在 main 上的 `.work-meta.json`（如果存在），清掉“正在做”的状态。
3. 把关联 worktree/branch 写入 `.runs/pending-cleanup.json`，不立即删除，避免当前会话 cwd 失效。

### 步骤 3：提示清理

```text
当前工作已放弃。

▶ Next Up：
  回主仓后运行：
    bash scripts/cleanup-pending-worktrees.sh

  新功能 / 重做模块：发 /pmai-design
  已完成要沉淀：发 /pmai-close
```

## Rules

- 必须先问 PM 确认，不能静默放弃。
- 放弃不 merge 当前工作分支。
- 不写 `status=cancelled`；新模型的语义是清掉活跃状态。
- 不手动删除 worktree/branch；只通过 `cancel-work.sh` 写 pending，再由 `cleanup-pending-worktrees.sh` 清理。
- PM 面前说“当前工作 / 模块工作”，不要再使用旧流程名。
