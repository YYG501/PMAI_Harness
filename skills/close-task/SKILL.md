---
name: close-task
description: |
  Task 关闭：检查文档偏差、归档运行时数据、merge 分支、清理 worktree。
---

# /close-task

### 执行位置（v4 单窗口 lifecycle）

- `/close-task` 现在在 task worktree 的新窗口里运行。
- 当前 `cwd` 通常是 task worktree。
- `close-task.sh` 脚本会自行处理 cd 到 main repo，PM 无需关心目录切换。

## When To Use

- 新窗口在 PM 通过验收后调用
- Task 状态必须为「已完成」

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: close-task"
```

## --skip-doc-update flag（A1 紧急逃生舱）

PM activates by calling close-task with `--skip-doc-update` flag。

Reason is REQUIRED。If PM does not provide reason, refuse with exit non-zero and message:

```text
Error: --skip-doc-update requires a reason. Usage: /close-task --skip-doc-update "<reason>"
```

On valid invocation:

1. Skip the `/doc-update` call entirely。
2. Write into task 文件「文档偏差」section this EXACT marker (on one line):
   ```html
   <!-- SKIP_DOC_UPDATE: reason="<PM-provided reason>" created_at="<ISO 8601 timestamp>" cleanup_status="pending" -->
   ```
3. Immediately after marker, append this cleanup TODO block:
   ```markdown
   ## 人工 Cleanup TODO（A1 决议，doc-update 被 skip）
   - [ ] 手动运行 /doc-update --task <task-id> 沉淀功能清单进 docs/modules/<module>.md
   - [ ] cleanup 完成后，把上方 SKIP_DOC_UPDATE marker 的 cleanup_status 从 "pending" 改为 "done"
   - [ ] 重跑 /req-stage-gate 验证半 close 解除
   ```
4. Continue all other close steps (merge branch, clean worktree, state machine update)。
5. Output at end:
   ```text
   task-NNN 已半 close（doc-update 被 skip）。需要人工 cleanup TODO 完成后才能推 stage 6→7。请运行 /doc-update 手动沉淀该 task 的功能清单。
   ```
6. Exit with code 0 (close-task itself succeeded; doc-update was intentionally skipped)。

## Workflow

### 步骤 1：检查文档偏差

读取 task 文件的「文档偏差」section：

- **有偏差记录**：先调用 `/doc-update` 处理偏差，等 `/doc-update` 完成后再继续
- **无偏差 / 偏差已处理**：继续下一步

### 步骤 2：执行关闭

调用 close-task.sh：

```bash
bash .claude/scripts/close-task.sh "<task-file-absolute-path>"
```

脚本自动执行：
1. 校验 task 状态为「已完成」
2. 检查文档偏差（二次检查，有未处理偏差会阻塞）
3. 归档 `.runs/` 到 req 目录的 `tasks/_archived/`
4. merge task 分支到 req 分支
5. 把 task worktree + branch 写入 `.runs/pending-cleanup.json`（不立即删，避免父进程 cwd dangling）
6. 杀掉 dev server 进程
7. 清理 `.runs/` 原件
8. 提示 PM：回主仓后跑 `bash scripts/cleanup-pending-worktrees.sh` 完成清理

### 步骤 3：确认结果

脚本成功后，提示：

```
Task 已关闭：<task-title>

worktree 和 branch 待清理。请退出当前会话，回主仓后跑：
  bash scripts/cleanup-pending-worktrees.sh

下一步：
- 如有下一个待启动 task，关闭本窗口，去主窗口运行 /task-spec → /task-confirm
- 如所有 task 已完成，去主窗口运行 /req-stage-gate 推进到 stage 7
```

## Rules

- 必须在 task 状态为「已完成」时才能关闭
- 文档偏差必须在关闭前处理（close-task.sh 会做二次检查）
- 不要手动执行 merge/删分支/清 worktree，全部由 close-task.sh 和 cleanup-pending-worktrees.sh 处理
- 关闭后 orchestrator 回到 req worktree 继续工作；worktree/branch 的实际删除由 PM 在主仓 cwd 跑 cleanup 完成（避免 close 删自己脚下目录导致 Stop hook posix_spawn ENOENT）

## 末尾轻量 auto-chain（DX RU6）

After close-task completes (full close or half-close), agent checks `task-plan.md`:

- If `PENDING > 0`, output:

  ```text
  ✅ task-NNN 已 close（本窗口已结束）。
  关掉本窗口，去主窗口启下一个 task：建议 task-XXX（title，所属模块: [...]）。
  在主窗口跑 /task-spec task-XXX → /task-confirm tasks/task-XXX-*.md
  ```

  D0 并行下不能在当前 task worktree 窗口直接启动下一个 task；下一个 task 必须回主窗口走 `/task-spec` → `/task-confirm`。

- If `PENDING == 0`, output:

  ```text
  ✅ task-NNN 已 close。
  本 req 所有 task 已 close（含半 close）。可在主窗口运行 /req-stage-gate 推进 stage 7。
  ```
