---
name: status
description: |
  全局状态总览：展示当前 req/task 状态、最后事件和下一步建议。
---

# /status

## When To Use

- PM 随时调用，查看当前工作状态

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: status"
```

## Workflow

### 步骤 1：调用 status-view.py

```bash
python3 .claude/scripts/status-view.py
```

脚本自动：
1. 找到主仓根目录
2. 扫描 `requirements/active/` 找活跃 req
3. 读取 req 的 stage 和 task 状态
4. 读取执行中 task 的最后事件
5. 输出格式化状态总览

### 步骤 2：展示结果

将 status-view.py 的输出直接展示给 PM。输出格式示例：

```
当前 Req：req-002-review-system（stage 6 - task 执行）
Task 状态：
  ✅ task-001 数据模型 — 已完成
  🔄 task-002 API 接口 — 执行中（最后活动：自审 - /qa pass）
  ⏳ task-003 前端组件 — 待确认
下一步：等待 task-002 自审完成后验收
```

如果没有活跃 req：

```
📭 没有活跃的需求。运行 /new-req 开始一个新需求。
```

## Rules

- 不修改任何状态，纯只读操作
- 可以在任何位置调用（主仓、req worktree、task worktree）
- status-view.py 会自动找到主仓根目录
