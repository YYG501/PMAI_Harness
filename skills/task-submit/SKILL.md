---
name: task-submit
description: |
  向 PM 呈交 task 验收信息包，根据 task 类型调整展示内容，等待 PM 决策。
---

# /task-submit

## When To Use

- 新窗口在 task 状态变为「待验收」后调用，直接向 PM 呈交验收并处理通过/打回

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-submit"
```

## Workflow

### 步骤 1：读取 task 文件

读取当前待验收的 task 文件，提取全部信息。

### 步骤 2：判断 task 类型

按以下任一信号判定为 UI 类（任一命中即 UI）：

- task 描述涉及前端/页面/组件/界面/UI/view/component
- 「推荐 review 工具」字段含 `/design-review` 或 `/qa`
- 「产物预览」section 含 ASCII 线框图（不是「无」或大纲）

其余视为非 UI 类。

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

### 步骤 3.5：在本窗口直接呈交 PM 验收（v4 单窗口 lifecycle）

进入「待验收」后，不提示 PM 回主窗口。当前新窗口直接汇总验收包并等待 PM 决策。

必须补充三类信息：

1. **Diff 摘要**：从 req 分支到当前 HEAD。
   ```bash
   git diff --stat <req-branch>..HEAD
   ```
2. **PM 已跑的 review（如有）**：列出 task-execute 阶段 PM 实际跑过并 append 到事件流的工具及结论，例如 `/review pass, /qa pass`；PM 全跳时写 `（PM 选择不跑 review）`。事件流缺事件不阻塞验收（I-RV2）。
3. **PM 决策入口**：明确让 PM 在本窗口选择通过或打回。

输出格式：

```text
Diff: N 文件 +X -Y 行 / review: <工具列表> 结论 → PM 通过/打回？
```

### 步骤 4：等待 PM 决策

**PM 说"通过"：**

```bash
python3 .claude/scripts/task-transition.py "<task-file>" --to 已完成
```

然后在本窗口直接运行：

```text
/close-task
```

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

3. 输出给 PM，并继续在本窗口修复：

   ```text
   task-execute 收到打回后，会先按 DX RU3 分流策略判断本次反馈是「行为修订」还是「Bug 修复」，并明确告知你判断结果。如判断错误，回复 "wrong" 切换分流。（分流策略权威定义见 skills/task-execute/SKILL.md §PM 反馈分流策略）
   ```

4. 应用 stage 5/6 PM 反馈分流策略（引用 `skills/task-execute/SKILL.md §PM 反馈分流策略`），然后继续修复并重新走自审与验收。

## Rules

- 验收信息从 task 文件各 section 提取，不要编造内容
- PM 的反馈原话记录，不要改写
- 打回时 --note 参数必须提供，否则 task-transition.py 会拒绝
- UI 类 task 的 dev server 应该还在运行，确认 URL 可访问
- v4 单窗口 lifecycle：验收、通过 close、打回修复都在当前 task worktree 新窗口完成
