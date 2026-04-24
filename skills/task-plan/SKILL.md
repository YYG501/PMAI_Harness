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
2. `$ACTIVE_REQ_DIR/solution.md`（如有）
3. `$REPO_ROOT/docs/DESIGN.md`（设计系统）
4. `$REPO_ROOT/docs/CONTEXT.md`（项目背景）
5. `$REPO_ROOT/docs/prd.md`（已有 PRD）
6. `$REPO_ROOT/docs/modules/*.md`（已有模块规格）

### 步骤 2：生成模块规格

读取 `$REPO_ROOT/templates/module.md.tmpl`，为涉及的每个模块生成或更新 `docs/modules/<module>.md`：

**输入：**
- `$ACTIVE_REQ_DIR/analysis.md`（必需）
- `$ACTIVE_REQ_DIR/solution.md`（如有）
- `$REPO_ROOT/docs/DESIGN.md`（设计系统，重点读取可用组件清单和项目共享组件）
- `$REPO_ROOT/docs/CONTEXT.md`（项目背景）
- 已有模块规格（如有，作为修订输入）

**生成要求：**
- 按模板结构逐节填写，不跳过硬约束和验收标准
- 功能清单表格按页面/区域分组，需求描述必须写动作+规则+限制，禁止"支持/优化/提升体验"
- 实现指引 section：用 Glob 扫描项目已有页面和组件，填写推荐组件和参考页面，标注 DESIGN.md 中的组件规范
- 交互状态覆盖表：每个页面/弹窗的 Loading/Empty/Error 处理
- 已有模块：merge 新内容到现有 section，不覆盖未变更部分
- 新模块：从模板完整生成

### 步骤 2.5：PM 确认模块规格

向 PM 展示每个模块规格的完整功能清单表格。PM 可以：
- 确认 → 进入步骤 3（拆 task）
- 要求修改 → 修改后重新展示

### 步骤 3：拆分 task

根据 analysis.md 和 solution.md 拆分成可执行的 task 列表。

#### 3.1 基本原则

- **原子性**：一个 task 完成一个独立的功能单元
- **可验收**：有明确的、**端到端可验证**的验收标准（不是"代码结构变好"这种过程性标准）
- **有序性**：task 之间有合理的执行顺序

#### 3.2 反模式（必须避免）

每次拆完先按下面 4 条反照一遍，命中任何一条就合并或重构该 task：

**反模式 A：纯重构前置 task**

> 例：为了后续 task 并行改同一大文件不冲突，先加一个"拆文件 + 引入 reducer"的纯结构 task。

- 问题：纯重构 task 没有业务验收点，却要跑完整 `/review + submit + close` 流程
- 判断：如果后续 task 是**串行**执行的，merge 冲突不存在，前置重构的理由就不成立——合并进第一个相关的 functional task
- 如果后续 task 必须**并行**且冲突无法避免，优先调整方案或执行顺序，最后才考虑前置重构（并且必须明确它带有端到端行为验证点，比如"拆完后页面在 X 操作下表现和之前一致"通过 /qa 验收）

**反模式 B：横切质量 task**

> 例：把所有 UI 改造 task 的 a11y、1280px 响应式、埋点、i18n 剥出来最后统一做一个"质量收尾 task"。

- 问题：前面 UI task 会在没有这些质量维度的状态下过 `/qa` 和 `/design-review`——等于 review 了半成品，还要 review 第二遍
- 判断：**a11y / 响应式 / performance / 埋点 / i18n** 等跨所有 UI 的质量维度必须写进**每个 UI task 的验收标准**，不允许独立成 task
- 如果 PM 真的想单独跑一次总体 a11y 扫描，那是验收阶段的事，不是 stage 5 拆出来的 task

**反模式 C：共生对拆成两个**

> 例：task A 定义纯函数签名，task B 改 Mock 数据以匹配签名。单独跑 A 只能用 stub 验证，单独跑 B 没有函数可调——必须一起做完才能端到端确认数据层就位。

- 判断启发式：**"单独跑完 A 后，能端到端验证到业务价值吗？"** 如果不能，合并 A 和 B
- 典型共生对：纯函数层 + 对应的 Mock/fixture；数据库 schema migration + ORM model 更新；新组件 + 首个调用方
- 合并后任务略大（验收项更多），但避免"改完 A 就搁置，等 B 才能联调"的人造断点

**反模式 D：同文件串行多 task（软约束）**

> 例：task 006/007/008 都改同一个 1495 行详情页文件且串行，只为验收维度清晰就拆 3 个 task。

- 问题：CC 执行每个 task 要跑完整 `preflight / review / qa / design-review / submit / close` 流程——拆 3 个意味着流程开销 ×3
- 判断：同文件 + 串行的 task，必须在 task-plan.md 的"风险和注意事项"里**显式写出**"拆多个 vs 合并"的成本权衡结论：
  - 验收粒度细（不拆合并回退难）→ 保持拆分
  - 三个改动共用大量 state/context → 合并
  - 没写权衡理由而拆多个的 → 默认合并
- 这是软约束，允许反例，但必须**有理由写出来**

#### 3.3 task 数量启发式

对一个约 7-10 小时 CC 规模的 req（典型业务 req），**task 数量 > 7 时，立即回头按 3.2 审查**。不是硬上限，但经验上超过 7 往往踩中反模式 A/B/C。

#### 3.4 拆分后自检清单

给每个 task 问以下 4 个问题，任何一个答"是"就返回 3.2 处理：

1. [ ] 这个 task 的验收标准是否只有"代码结构变好/重构完成"这种过程性描述？（反模式 A）
2. [ ] 这个 task 描述的工作是否**应该是**其他某个 task 的验收标准的一部分？（反模式 B）
3. [ ] 这个 task 单独跑完后，能不能独立端到端验证到业务价值？（反模式 C）
4. [ ] 这个 task 和另一个 task 改同一文件且串行，task-plan 里是否写了成本权衡结论？（反模式 D）

### 步骤 4：写 task-plan.md

在 req 目录写 `task-plan.md`，包含：

- task 列表总览（编号、名称、简述、依赖）
- 执行顺序建议
- 风险和注意事项
- **反模式自检声明**：显式写一段"已按步骤 3.2 的 4 条反模式自检过，命中情况说明"。若命中过反模式 D（同文件串行多 task），在"风险和注意事项"里必须写出"拆多个 vs 合并"的成本权衡结论和保留拆分的理由——没有权衡理由就不允许拆

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

所有 task 初始状态为「待确认」。`executor` 默认填 `claude-code`，`executor_model` 留空（PM 在 /task-confirm 时可以交互式切换执行者，见 task 模板的 inline 提示）。**不做 routing**——不分析任务内容推测执行者。

### 步骤 6：向 PM 展示

展示 task-plan.md 摘要，列出所有 task 的编号、名称、验收标准概要。

等待 PM 确认后，由 `/req-stage-gate` 推进到 stage 6。

## Rules

- task 编号三位数，从 001 开始
- 不复制文档原文到 task 文件，只引用文档路径和 section
- 每个 task 必须有至少一条验收标准
- task-plan.md 和 task 文件都写在 req 目录下（req worktree 中）
- **拆完 task 必须跑步骤 3.4 自检**，任何一条命中就返回 3.2 合并或重构，不能直接进入步骤 4。命中的 task 没处理就不允许向 PM 展示
- **task 数量超过 7 时必须在 task-plan.md 里显式列出每个 task 的存在理由**——证明不是踩反模式 A/B/C 拆多的。PM 有权要求合并

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
