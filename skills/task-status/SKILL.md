---
name: task-status
description: |
  全局状态总览：展示当前 req/task 状态、最后事件和下一步建议。
---

# /task-status

## When To Use

- PM 随时调用，查看当前工作状态

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-status"
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
5. 统计多 task 摘要：执行中 / 待启动 / 已完成
6. 输出格式化状态总览

### 步骤 2：展示结果

将 status-view.py 的输出展示给 PM。多 task 摘要第一行必须使用：

```text
📋 task 概览: 执行中 N1 / 待启动 N2 / 已完成 N3
```

其中「待启动」指状态为「待执行」且 worktree 已建的 task；「执行中」覆盖 AI 实现期 + PM 验收期（commit 不切状态，PM 通过呈交块时直接转「已完成」）。

逐 task 提示规则：

- 扫到「待执行」状态且 worktree 已建的 task，输出：
  ```text
  等待 PM 在新窗口启动（跑 /task-execute task-NNN）
  ```
- 扫到「执行中」状态 task，输出：
  ```text
  执行中：在对应 task 窗口实现 / 验收（可跑 /task-submit 重新查看呈交块）
  ```

输出格式示例：

```
当前 Req：req-002-review-system（stage 6 - task 执行）
📋 task 概览: 执行中 2 / 待启动 1 / 已完成 1
Task 状态：
  ✅ task-001 数据模型 — 已完成
  🔄 task-002 API 接口 — 执行中（实现中，最后活动：自审 - /qa pass）
  🔄 task-003 前端组件 — 执行中（已 commit 待 PM 验收，可跑 /task-submit 看呈交块）
  ⏳ task-004 导出入口 — 待执行：等待 PM 在新窗口启动（跑 /task-execute task-004）
下一步：处理执行中 task，或启动待启动 task
```

如果没有活跃 req：

```
📭 没有活跃的需求。运行 /new-req 开始一个新需求。
```

## Rules

- 不修改任何状态，纯只读操作
- 可以在任何位置调用（主仓、req worktree、task worktree）
- status-view.py 会自动找到主仓根目录
