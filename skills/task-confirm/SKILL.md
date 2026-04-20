---
name: task-confirm
description: |
  PM 确认启动一个 task：展示摘要、创建 worktree、转换状态为执行中。
---

# /task-confirm

## When To Use

- PM 调用，参数是 task 文件路径（如 `/task-confirm tasks/task-001-login-ui.md`）

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-confirm"
```

## Workflow

### 步骤 1：读取 task 文件

读取 PM 指定的 task 文件，提取关键信息。

### 步骤 2：展示 task 摘要

向 PM 展示以下信息：

```
Task: task-NNN-<slug>
目标: [任务描述摘要]
验收标准:
  - [ ] 条件 1
  - [ ] 条件 2
依赖: [依赖列表或"无"]
审查工具: /qa, /design-review

确认启动此 task？（Y/N）
```

### 步骤 3：PM 确认后转换状态

PM 确认后，调用 task-transition.py 转换状态：

```bash
python3 .claude/scripts/task-transition.py "<task-file-absolute-path>" --to 执行中
```

脚本会自动检查 v1 串行约束（同 req 下不能有其他执行中/待验收的 task）。

### 步骤 4：创建 task worktree

从 `.req-meta.json` 读取 req 分支名，然后创建 task worktree：

```bash
bash .claude/scripts/create-task-worktree.sh "<task-file>" "<req-branch>"
```

脚本输出两行：第一行是 worktree 路径，第二行是端口号。

### 步骤 5：更新 task 文件

将 worktree 路径和端口号写入 task 文件的对应字段：

- `**worktree：**` → worktree 路径
- `**开发服务器：**` → `http://localhost:<port>`

### 步骤 6：提示执行

提示 suborchestrator 进入 task worktree 执行：

```
Task 已启动。

Worktree: <worktree-path>
端口: <port>

请在 task worktree 中运行 /task-execute 开始实现。
```

## Rules

- 必须在 req worktree 中执行（WORKTREE_TYPE 应为 req）
- task 文件路径如果是相对路径，基于当前 req worktree 解析
- 状态转换必须通过 task-transition.py，不能手动改状态字段
- v1 串行模式：同一 req 下只能有一个 task 在执行中或待验收
