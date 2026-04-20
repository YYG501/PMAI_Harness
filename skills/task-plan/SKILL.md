---
name: task-plan
description: |
  Stage 5：读取分析和设计文档，更新模块规格，拆分 task 并生成 task 文件。
---

# /task-plan

## When To Use

- Orchestrator 在 stage 5 调用（由 `/req-stage-gate` 触发）

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-plan"
```

## Workflow

### 步骤 1：读取输入文档

读取以下文档（按优先级）：

1. `$ACTIVE_REQ_DIR/analysis.md`（必需）
2. `$ACTIVE_REQ_DIR/design.md`（如有）
3. `$REPO_ROOT/docs/DESIGN.md`（设计系统）
4. `$REPO_ROOT/docs/CONTEXT.md`（项目背景）
5. `$REPO_ROOT/docs/prd.md`（已有 PRD）
6. `$REPO_ROOT/docs/modules/*.md`（已有模块规格）

### 步骤 2：更新模块规格

根据分析和设计，为涉及的每个模块更新或创建 `docs/modules/<module>.md`：

- 已有模块：更新受影响的部分
- 新模块：创建新的模块规格文件

模块规格内容包括：接口定义、数据模型、依赖关系、约束条件。

### 步骤 3：拆分 task

根据 analysis.md 和 design.md 拆分成可执行的 task 列表。每个 task 应该：

- **原子性**：一个 task 完成一个独立的功能单元
- **可验收**：有明确的验收标准
- **有序性**：task 之间有合理的执行顺序

### 步骤 4：写 task-plan.md

在 req 目录写 `task-plan.md`，包含：

- task 列表总览（编号、名称、简述、依赖）
- 执行顺序建议
- 风险和注意事项

### 步骤 5：生成 task 文件

为每个 task 从模板创建文件。读取 `$REPO_ROOT/templates/task.md.tmpl`，替换占位符后写入 `$ACTIVE_REQ_DIR/tasks/task-NNN-<slug>.md`。

替换规则：
- `{{TASK_NUMBER}}` → 三位数编号（001, 002, ...）
- `{{TASK_NAME}}` → 任务名称
- `{{TASK_BRANCH}}` → `task-NNN-<slug>`
- `{{CREATED_DATE}}` → 当前日期 YYYY-MM-DD
- `{{REVIEW_TOOLS}}` → 根据 task 类型按下表决定

填写 task 文件的各 section：
- **启动前必读**：列出该 task 需要读的文档
- **任务描述**：引用相关文档，不复制原文
- **执行范围**：新建/修改/不动的文件列表
- **验收标准**：可验证的 checklist
- **依赖**：依赖的其他 task 或外部资源

所有 task 初始状态为「待确认」。

### 步骤 6：向 PM 展示

展示 task-plan.md 摘要，列出所有 task 的编号、名称、验收标准概要。

等待 PM 确认后，由 `/req-stage-gate` 推进到 stage 6。

## Rules

- task 编号三位数，从 001 开始
- 不复制文档原文到 task 文件，只引用文档路径和 section
- 每个 task 必须有至少一条验收标准
- task-plan.md 和 task 文件都写在 req 目录下（req worktree 中）

## 审查工具默认值

按 task 类型为每个 task 填写「审查工具」字段的默认值：

| task 类型 | 审查工具默认值 | 说明 |
|----------|---------------|------|
| 纯后端（API、数据层、脚本） | `/review` | 只需代码审查 |
| 纯 UI（只改样式、文案、布局） | `/qa, /design-review` | 代码改动少，重点是功能和视觉 |
| 全栈新功能（前端+后端） | `/review, /qa, /design-review` | 三个维度都需要 |
| 纯配置/文档 | `(无)` | 不需要自审，orchestrator 直接检查 |
| 重构（不改行为，只改结构） | `/review` | 重点防止回归 |

PM 在 `/task-confirm` 时可以调整这个字段：
- 小改动想快点过：删掉某些工具
- 关键安全敏感改动：确保有 /review
- 纯脚手架代码：全删掉

task-transition.py 会校验「审查工具」字段列出的所有工具都有 review_completed 事件，才允许转为「待验收」。如果字段为空，跳过自审校验。
