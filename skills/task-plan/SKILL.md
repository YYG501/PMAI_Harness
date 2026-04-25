---
name: task-plan
description: |
  Stage 5：读取分析和设计文档，拆分 task 规划并写 task-plan.md；不生成具体 task 文档。
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
6. `$REPO_ROOT/docs/modules/*.md`（已有模块规格，仅作为已有事实输入，不在本 skill 中生成或更新）

### 步骤 3：拆分 task

根据 analysis.md 和 solution.md 拆分成 `task-plan.md` 的 task 标题列表。

> **颗粒度核心规则**：一个 task = PM 能在一次原型 demo 里完整验收的功能单元。
>
> **业务模块 task**：一个 task 对应 1-N 条紧密相关的功能清单条目；紧密相关指同一个 user story 链条，或同一个页面区域可一次性 demo。不同 user story 链条即使在同一页面，也要拆成不同 task。
>
> **基础设施 task**：一个 task 对应一类完整可用的基础设施能力，例如项目脚手架、共用组件库、auth context、API client、构建配置。
>
> **端到端切片原则**：task MUST 按 user story 端到端切（前端 + 后端 + 数据层捆绑）；technical layering cuts are FORBIDDEN，不允许拆成“先数据层、再 UI、再联调”。

#### 3.1 基本原则

> **DX RU1 固定提示：业务模块 / 基础设施判定硬规则**
>
> 1. 每个 task 必须显式声明 `所属模块`，只能是一个或多个业务模块，或 `基础设施`。
> 2. 产出在任何业务页面/流程上直接可见时，必须归到对应业务模块。
> 3. 只有产出不在任何业务页面/流程上直接可见，才允许标 `基础设施`。
> 4. 基础设施 task 验收后不沉淀进 `docs/modules/<module>.md`；如需长期记录，由 PM 决定是否写入 `docs/CONTEXT.md` / `docs/DESIGN.md`。
>
> 基础设施识别示例：项目脚手架、共用 Button/Modal 组件库、API client、auth context、构建配置。反例：登录页的“会话管理 hook”服务于登录流程，应归登录页/账号模块。

- **原子性**：一个 task 完成一个独立的功能单元。
- **可验收**：有明确的、端到端可验证的验收依据（不是“代码结构变好”这种过程性标准）。
- **有序性**：task 之间有合理的执行顺序。
- **可归属**：每个业务功能 task 必须可归属到一个模块章节，并在 `task-plan.md` 中写清 `所属模块`；基础设施 task 必须符合上方硬规则。

#### 3.2 反模式（必须避免）

每次拆完先按下面 5 条反照一遍，命中任何一条就合并或重构该 task：

**反模式 A：纯重构前置 task**

> 例：为了后续 task 并行改同一大文件不冲突，先加一个“拆文件 + 引入 reducer”的纯结构 task。

- 问题：纯重构 task 没有业务验收点，却要跑完整 `/review + submit + close` 流程。
- 判断：如果后续 task 是串行执行的，merge 冲突不存在，前置重构的理由就不成立，合并进第一个相关 functional task。
- 如果后续 task 必须并行且冲突无法避免，优先调整方案或执行顺序，最后才考虑前置重构，并且必须明确它带有端到端行为验证点。

**反模式 B：横切质量 task**

> 例：把所有 UI 改造 task 的 a11y、1280px 响应式、埋点、i18n 剥出来最后统一做一个“质量收尾 task”。

- 问题：前面 UI task 会在没有这些质量维度的状态下过 `/qa` 和 `/design-review`，等于 review 半成品。
- 判断：a11y / 响应式 / performance / 埋点 / i18n 等跨所有 UI 的质量维度必须写进每个 UI task 的验收依据，不允许独立成 task。

**反模式 C：共生对拆成两个**

> 例：task A 定义纯函数签名，task B 改 Mock 数据以匹配签名。单独跑 A 只能用 stub 验证，单独跑 B 没有函数可调。

- 判断启发式：“单独跑完 A 后，能端到端验证到业务价值吗？”如果不能，合并 A 和 B。
- 典型共生对：纯函数层 + 对应 Mock/fixture；数据库 schema migration + ORM model 更新；新组件 + 首个调用方。

**反模式 D：同文件串行多 task（软约束）**

> 例：task 006/007/008 都改同一个详情页文件且串行，只为验收维度清晰就拆 3 个 task。

- 判断：同文件 + 串行的 task，必须在 task-plan.md 的“风险”里显式写出“拆多个 vs 合并”的成本权衡结论。
- 没写权衡理由而拆多个的，默认合并。

**反模式 E：业务功能 task 没有模块归属**

> 例：task “实现产品访问管理列表页” 标 `所属模块: 基础设施`。

- 问题：业务功能不沉淀进 module 规格，living doc 会残缺。
- 判断逻辑：产出在任何业务页面/流程上直接可见，就必须归到对应业务模块；标 `基础设施` 只能用于真正横切且不可直接由业务页面验收的能力。
- 典型错误示例：登录流程、列表筛选、批量导出、权限提示、详情页状态展示都不是基础设施。

#### 3.3 task 数量启发式

- 单 req 总 task 数 > 7 时，立即回头按 3.2 审查。不是硬上限，但经验上超过 7 往往踩中反模式 A/B/C。
- 单模块软上限 = 3 tasks。单个模块被拆成超过 3 个 task 时，必须回头审查是否把同一页面区域或同一 user story 链条拆得过细。

#### 3.4 拆分后自检清单

给每个 task 问以下 5 个问题，任何一个答“是”或“不满足”就返回 3.2 处理：

1. [ ] 这个 task 的验收依据是否只有“代码结构变好/重构完成”这种过程性描述？（反模式 A）
2. [ ] 这个 task 描述的工作是否应该是其他某个 task 的验收标准的一部分？（反模式 B）
3. [ ] 这个 task 单独跑完后，能不能独立端到端验证到业务价值？（反模式 C）
4. [ ] 这个 task 和另一个 task 改同一文件且串行，task-plan 里是否写了成本权衡结论？（反模式 D）
5. [ ] 所有 task 的模块归属是否满足硬规则？业务功能 task 是否真的归到了业务模块章节，而不是图省事标成 `基础设施`？（反模式 E）

### 步骤 4：写 task-plan.md

在 req 目录写 `task-plan.md`。内容只包含 task 标题列表，不生成具体 task 文档。

必含内容：

- task 标题列表：`id` / `title` / `所属模块` / `所属模块章节` / 一句话 summary / order / risk。
- 执行顺序：按 PM 最容易连续验收的顺序排列，标明必要依赖。
- 风险：只写会影响拆分、验收或并行的真实风险；命中反模式 D 或单模块超过 3 个 task 时写明权衡。
- **变更记录** section：固定放在文末，供 PM 中途新增、修改、删除 task 时手写记录。
- **反模式自检声明**：显式写一段“已按步骤 3.2 的 5 条反模式自检过，命中情况说明”。

`task-plan.md` 的列表建议格式：

```markdown
| id | title | 所属模块 | 所属模块章节 | summary | order | risk |
|----|-------|----------|--------------|---------|-------|------|
| task-001 | 登录主流程 | 账号模块 | 登录与会话 | 用户完成账号密码登录并看到错误反馈 | 1 | 无 |

## 变更记录

- （暂无）
```

### 步骤 5：PM 确认 task-plan.md → /req-stage-gate advances to stage 6

向 PM 展示 `task-plan.md` 摘要，列出所有 task 的 id、标题、所属模块、顺序和主要风险。

确认门：

- PM 确认 → `/req-stage-gate` 推进到 stage 6。
- PM 要求修改 → 修改 `task-plan.md` 后重新展示。

进入 stage 6 后，具体 task 文档由 stage 6 的 `/task-spec <task-id>` 按 `task-plan.md` 逐个生成。

## Rules

- task 编号三位数，从 001 开始，格式 `task-001`。
- Stage 5 只写 `task-plan.md`，不创建 `tasks/task-NNN-*.md`。
- 不在本 skill 中创建或更新 `docs/modules/*.md`；模块规格由 task 验收后的 `/doc-update` 沉淀。
- task-plan.md 写在 req 目录下（req worktree 中）。
- 拆完 task 必须跑步骤 3.4 自检；任何一条命中就返回 3.2 合并或重构，不能直接进入步骤 4。
- task 总数超过 7 时，必须在 task-plan.md 里显式列出每个 task 的存在理由。
- 单模块超过 3 个 task 时，必须在 task-plan.md 风险列或风险 section 写明为什么不合并。
