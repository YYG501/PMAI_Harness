---
name: close-task
description: |
  Task 关闭：检查文档偏差、归档运行时数据、merge 分支、清理 worktree。
---

# /close-task

## When To Use

- Orchestrator 在 PM 通过验收后调用
- Task 状态必须为「已完成」

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: close-task"
```

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
5. 删除 task 分支
6. 清理 task worktree
7. 杀掉 dev server 进程
8. 清理 `.runs/` 原件

### 步骤 3：确认结果

脚本成功后，提示：

```
Task 已关闭：<task-title>

下一步：
- 如有下一个待确认 task，运行 /task-confirm 启动
- 如所有 task 已完成，运行 /req-stage-gate 推进到 stage 7
```

## Rules

- 必须在 task 状态为「已完成」时才能关闭
- 文档偏差必须在关闭前处理（close-task.sh 会做二次检查）
- 不要手动执行 merge/删分支/清 worktree，全部由 close-task.sh 处理
- 关闭后 orchestrator 回到 req worktree 继续工作
