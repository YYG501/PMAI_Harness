---
name: close-req
description: |
  Req 关闭：写 close-report、更新 PRD、merge 到 main、归档。
---

# /close-req

## When To Use

- Orchestrator 在 stage 7 调用
- 所有 task 必须已关闭

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: close-req"
```

## Workflow

### 步骤 1：写 close-report.md

在 req 目录写 `close-report.md`，内容包括：

```markdown
# Req Close Report: req-NNN-<slug>

## 需求概述
[从 brief.md 提取]

## 完成的 task
| Task | 摘要 |
|------|------|
| task-001-xxx | [从执行日志提取] |
| task-003-xxx | [从执行日志提取] |

<!-- 仅当 tasks/discarded/ 下有文件时输出本段 -->
<details>
<summary>已废弃 task（N 个）</summary>

| Task | 废弃理由 |
|------|----------|
| task-002-xxx | [从该 task 文件的「废弃理由」section 摘要] |

</details>

## 文档变更
[列出本次 req 修改过的文档]

## 遗留问题
[如有未解决的问题或后续建议]
```

**生成规则：**
- 遍历 `tasks/*.md` 填「完成的 task」表（这里只剩已完成态，因为 stage 7 guardrail 要求所有未关闭 task 都收尾）。
- 遍历 `tasks/discarded/*.md` 填废弃栏；为空时整个 `<details>` 块省略。
- 已废弃 task 编号断号是合规信号，不要为「整理顺序」而改号。

### 步骤 2：更新 PRD

检查本次 req 是否对产品功能有变化。如果有：
- 调用 `/prd-writing` 更新 `docs/prd.md`

如果无变化（如纯重构或 bugfix），跳过。

### 步骤 3：推进状态

```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 7
```

### 步骤 4：commit 所有改动

在 req worktree 中 commit 所有未提交的改动：

```bash
git add -A
git commit -m "close: req-NNN-<slug>"
```

### 步骤 5：执行关闭

```bash
bash .claude/scripts/close-req.sh "$ACTIVE_REQ_DIR"
```

脚本自动执行：
1. 校验 stage 为 7
2. 校验所有 task 已关闭
3. cd 到主仓，merge req 分支到 main
4. 把 req worktree + branch 写入 `.runs/pending-cleanup.json`（不立即删，避免父进程 cwd dangling）
5. 移动 req 目录到 `requirements/closed/`（在 req 分支上 commit 后随 merge 落地）
6. 更新 req 状态为 closed
7. 提示 PM：回主仓后跑 `bash scripts/cleanup-pending-worktrees.sh` 完成清理

### 步骤 6：确认结果

```
Req 已关闭：req-NNN-<slug>
当前位置：主仓 main 分支

worktree 和 branch 待清理。请退出当前会话，回主仓后跑：
  bash scripts/cleanup-pending-worktrees.sh

运行 /new-req 开始下一个需求。
```

## Rules

- 必须在 req worktree 中执行（先 commit，再调用 close-req.sh）
- close-req.sh 会自动 cd 到主仓执行 merge，不需要手动切换
- merge 到 main 后不可回退（stage 7 是终态）
- req 目录移到 closed/ 后保留完整记录
- worktree/branch 的实际删除由 PM 在主仓 cwd 跑 `cleanup-pending-worktrees.sh` 完成（避免 close 删自己脚下目录导致 Stop hook posix_spawn ENOENT）
