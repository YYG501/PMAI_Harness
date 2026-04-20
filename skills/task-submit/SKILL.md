---
name: task-submit
description: |
  向 PM 呈交 task 验收信息包，根据 task 类型调整展示内容，等待 PM 决策。
---

# /task-submit

## When To Use

- Orchestrator 在 task 状态变为「待验收」后调用

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-submit"
```

## Workflow

### 步骤 1：读取 task 文件

读取当前待验收的 task 文件，提取全部信息。

### 步骤 2：判断 task 类型

- **UI 类**：审查工具包含 `/design-review` 或 task 描述涉及前端/页面/组件
- **非 UI 类**：其他 task

### 步骤 3：组装验收信息

**UI 类 task 展示：**

```
═══════════════════════════════════════
📋 Task 验收：task-NNN-<slug>
═══════════════════════════════════════

🔗 验收 URL: http://localhost:<port>

📝 改动摘要：
[从执行日志提取]

🔍 自审结果：
[从自审记录提取每个工具的结果]

✅ 验收清单：
- [ ] 条件 1
- [ ] 条件 2

📄 文档偏差：
[偏差内容或"无偏差"]

请验收：通过 / 打回（附反馈）
═══════════════════════════════════════
```

**非 UI 类 task 展示：**

```
═══════════════════════════════════════
📋 Task 验收：task-NNN-<slug>
═══════════════════════════════════════

📝 改动摘要：
[从执行日志提取]

📂 代码变更：
[关键 diff 摘要或测试结果]

🔍 自审结果：
[从自审记录提取]

✅ 验收清单：
- [ ] 条件 1
- [ ] 条件 2

📄 文档偏差：
[偏差内容或"无偏差"]

请验收：通过 / 打回（附反馈）
═══════════════════════════════════════
```

### 步骤 4：等待 PM 决策

**PM 说"通过"：**

```bash
python3 .claude/scripts/task-transition.py "<task-file>" --to 已完成
```

然后提示 orchestrator 运行 `/close-task`。

**PM 说"打回"：**

1. 记录 PM 反馈到 task 文件的「PM 反馈」section：
   ```markdown
   ### 反馈 N - [YYYY-MM-DD]
   **问题描述：** [PM 的原话]
   **要求修改：** [具体修改要求]
   **处理结果：** 待处理
   ```

2. 转换状态回执行中：
   ```bash
   python3 .claude/scripts/task-transition.py "<task-file>" --to 执行中 --note "PM 打回：<反馈摘要>"
   ```

3. 提示 suborchestrator 重新进入 task worktree 修复。

## Rules

- 验收信息从 task 文件各 section 提取，不要编造内容
- PM 的反馈原话记录，不要改写
- 打回时 --note 参数必须提供，否则 task-transition.py 会拒绝
- UI 类 task 的 dev server 应该还在运行，确认 URL 可访问
