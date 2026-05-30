# 原型 demo 闭环与 task 流程重构（整体方案 v1）

> **状态**：整体方案 / 待 PM 锁定后拆实施批次
> **日期**：2026-05-28
> **作者**：PM + AI

---

## §0 原始痛点（PM + AI 共写，后续 review 不可反向改写）

PMAI 现在不像一个“想法来了 → 深入讨论 → 快速做出原型 / demo → 快速修改 → 把原型和文档交给决策者”的工具。PM 感觉方案讨论和确认阶段不够明确、不够深入，反而在原型 / demo 的实现、task 启动、验收和返工环节花费太多时间。

### §0.1 触发场景

| # | 场景 | PM 反馈 |
|---|---|---|
| 1 | 想法来了，希望快速看到可操作原型 / demo | “没有那种，一个想法来了，快速实现一个原型或者 demo，然后快速修改，最后把原型和文档传递给决策者那个感觉” |
| 2 | 上游讨论不够深入 | “我在方案讨论和确认的时候不够明确和深入” |
| 3 | 下游实现期占用 PM 太多 | “反而又在原型和 demo 的实现过程中，花费太多时间” |
| 4 | 手动命令太多 | PM 希望是“我选择 / 我确认”，而不是反复输入手动指令 |
| 5 | task-spec 体感变重 | `task-spec 是否多余` 是导致慢的因素之一，但不是根因 |
| 6 | 大系统不能一次做完 | 大后台不能一次实现用户、角色、部门、资产；应按 req 分批，每个 req 内再按 task 分阶段确认 |

### §0.2 根因判断

当前流程把主线设计成“需求文档 → task 拆分 → task 执行安全闭环”。这对生产式实现安全，但对想法验证和 demo 决策不顺：

- 上游缺少围绕“决策者要判断什么 / demo 成功标准 / 哪些可假不可误导”的强讨论。
- 中游文档没有明确区分“真实需求”与“本轮原型覆盖范围”。
- 下游 task 生命周期把 PM 暴露在 task-spec、task-confirm、task-execute、close-task 等工程动作里。
- task 被实现成工程生命周期单位，而不是 PM 可确认的 demo 单元。

---

## §1 总体决议

### §1.1 不新增 slice，不做双 lane

本方案不引入 `slice` 概念，也不新增独立的 Prototype Sprint lane。最终模型保持一套流程：

```text
项目初始化
  → 建项目级上下文和默认规则

新需求
  → req
  → PRD
  → design 对齐（docs/DESIGN.md + req 级设计决策）
  → implementation-design
  → task-plan
  → task demo loop
  → PRD 回填 + decision packet
```

区别只在粒度：

- `req`：一个业务增量，例如“用户管理第一批”。
- `task`：req 内一个 PM 可看 demo 并确认的阶段性单元，例如“用户列表 demo”“新增 / 编辑用户 demo”。
- `task-contract`：AI 内部执行合同，PM 不确认。

### §1.2 task 的新定义

`task` 不再是 PM 视角的工程 ticket，而是：

> 一个 PM 能通过 demo 判断“方向对不对 / 范围对不对 / 是否继续”的阶段性交付单元。

task 拆分的目的不是给工程排票，而是：

- 防止一个 req 一次产出太多内容，PM 全部要返工。
- 让一个模块可以分阶段确认。
- 让前一个 task 的反馈能影响后续 task。
- 让大系统通过多个 req、多个 task 逐步成形。

### §1.3 task-spec 的新定位

`task-spec` 不删除，但从 PM 主路径移走。

新规则：

```text
每个 task 都自动生成 AI 内部 task-contract。
PM 不确认 task-contract。
PM 只确认 task-plan 和 demo。
```

复杂度不决定是否生成合同，只决定合同深度：

| 执行深度 | PM 视角 | 内部合同深度 |
|---|---|---|
| `demo-light` | 快速看可点 demo | demo 目标、页面路径、可假数据、主路径验收 |
| `demo-deep` | 接近真实流程的 demo | 数据结构、mock/API 边界、状态流转、异常路径 |
| `production` | 可进入正式实现 | 完整 scope gate、测试、close-task、文档偏差机制 |
| `document` | 文档 / 决策包类 task | 输入、输出章节、验收读法、回填规则 |

### §1.4 design 阶段保留，但拆成两层

design 阶段不能删。删掉 design 会让 demo 快起来，但后续每个 task 都可能长得不一致，也会失去组件复用和视觉基线。

新流程里的 design 分两层：

| 层级 | 文件 / 位置 | 何时处理 | PM 怎么参与 |
|---|---|---|---|
| 项目级设计基线 | `docs/DESIGN.md` | 项目初始化时建立；每个 req 开始时做 gap-check | 初始化时主确认；新 req 只确认新增组件 / 设计方向变化 |
| req 级设计决策 | `implementation-design.md` 摘要 + task-plan demo 描述 | PRD 后、task-plan 前 | 只拍影响范围、成本、真实性、视觉方向的结构决策 |

所以新需求不是 `PRD → implementation-design` 直接跳过设计，而是：

```text
PRD
  → 对齐 docs/DESIGN.md：已有组件 / 缺口 / 是否新增模式
  → 形成 req 级设计决策摘要
  → implementation-design 记录 HOW
  → task-plan 拆 demo task
```

### §1.5 implementation-design 保留但后台化

`implementation-design.md` 不删除。它解决 req 级 HOW：

- 数据策略和 mock 边界。
- 组件 / 页面 / 路由复用策略。
- 设计基线和组件复用在本 req 的落地策略。
- 多个 task 之间的数据模型一致性。
- 哪些内容真实实现、哪些模拟、哪些简化。

但 PM 不再全文确认它。PM 只拍会影响范围、成本、真实性或决策误读的结构决策。

---

## §2 项目初始化流程

项目初始化和新需求不是同一件事。

```text
项目初始化 = 建项目级上下文和工作规则
加新需求 = 在已有项目上下文里跑一个 req/demo 闭环
```

### §2.1 初始化目标

初始化不做功能 demo、不拆 task、不生成 task-plan。

初始化只回答：

- 这个项目是什么。
- 服务谁。
- 长期业务对象和术语是什么。
- 技术和设计基线是什么。
- 后续 req 默认怎么进入。
- 原型默认做到什么深度。
- worktree 和 task-contract 默认怎么处理。

### §2.2 初始化分流

`/pmai-init-project` 入口先识别项目状态：

| 项目状态 | 行为 |
|---|---|
| 全新项目 | 建项目定位、技术栈、设计基线、初始 roadmap，可选生成项目骨架 |
| 已有代码项目 | 先读代码 / 路由 / 组件 / 文档，反推项目基线 |
| 已初始化项目补缺 | 只补缺失的 PROJECT / DESIGN / PRODUCT-RULES / ROADMAP |
| 旧版 PMAI 升级 | 迁移文档和 workflow 默认规则，不启动新 req |

### §2.3 初始化产物

| 文件 | 作用 |
|---|---|
| `docs/PROJECT.md` | 项目定位、用户、术语、技术栈、长期非目标 |
| `docs/DESIGN.md` | 设计基线、布局密度、组件 inventory、默认交互模式 |
| `docs/PRODUCT-RULES.md` | 跨 req 都要遵守的产品规则 |
| `docs/ROADMAP.md` | 候选 req 队列，不拆 task |
| workflow defaults | req/task/demo/worktree/task-contract 默认规则 |

初始化结束时，PM 只看到摘要和选择：

```text
项目初始化完成。

已建立：
- PROJECT.md
- DESIGN.md
- PRODUCT-RULES.md
- ROADMAP.md
- workflow defaults

建议第一个 req：用户管理第一批

下一步：
A. 现在开始第一个 req
B. 先调整项目基线
C. 停在初始化完成
```

选 A 才进入 `/pmai-new-req`。初始化不能把第一个需求混进同一段流程。

### §2.4 初始化 worktree 规则

初始化阶段默认只用 main worktree：

```text
main worktree
  → 写项目级文档
  → 写 workflow defaults
  → commit 项目基线
```

初始化阶段不创建 task worktree。已有代码项目可以临时扫描，但 PM 心智仍是“项目初始化”，不是“功能 task 执行”。

---

## §3 新需求流程

### §3.1 PM 使用路径

新需求从一句话开始：

```text
/pmai-new-req "用户管理第一批"
```

AI 不马上写代码，先深问本 req：

- 这次 req 给谁看。
- 决策者要判断什么。
- demo 通过的标准是什么。
- 哪些可以用假数据。
- 哪些不能假，假了会误导。
- 哪些明确不在本 req 做。

### §3.2 PRD v0：真实需求 + 原型覆盖范围

`prd.md` 保留，且是 PM 主读文档。它必须新增“原型覆盖范围”：

| PRD 内容 | 原型本轮状态 | 说明 |
|---|---|---|
| 用户列表 | 原型实现 | 可搜索、可筛选、可查看状态 |
| 新增用户 | 原型实现 | 表单可提交到 mock 数据 |
| 角色分配 | 简化实现 | 只展示角色字段，不实现权限生效 |
| 部门树 | 模拟数据 | 用固定部门数据 |
| 批量导入 | 本轮不实现 | 放到后续 req |
| 资产关联 | 后续 req | 不在用户管理第一批里 |

允许状态：

- `原型实现`
- `简化实现`
- `模拟数据`
- `本轮不实现`
- `后续 req`

这保证 PRD 可以写完整真实需求，同时明确本轮 demo 覆盖到哪里。

### §3.3 design 对齐：项目级设计基线 + 本 req 设计缺口

PRD 后必须进入 design 对齐，不直接拆 task。

本步骤做三件事：

1. 读取 `docs/DESIGN.md`，确认本 req 应复用哪些已有布局、组件、交互模式。
2. 判断本 req 是否需要新增组件 / 新页面模式 / 新交互模式。
3. 把影响 PM 判断的设计决策提出来问，不把完整设计细节推给 PM。

PM 看到的应该是设计决策摘要，而不是设计系统全文：

```text
本 req 有 2 个设计点需要你拍：

1. 用户详情用抽屉还是独立页面？
A. 抽屉：列表上下文保留，适合快速查看
B. 独立页面：信息容量更大，适合后续接日志 / 权限 / 资产

2. 部门选择用普通下拉还是树形选择？
A. 普通下拉：最快，适合 demo-light
B. 树形选择：更接近真实后台，但本 req 不做部门管理
```

设计对齐结果进入两处：

- `docs/DESIGN.md`：如果确实新增长期组件 / 模式，更新 inventory。
- `implementation-design.md`：记录本 req 如何复用 / 新增 / 简化这些设计选择。

### §3.4 implementation-design：AI 内部 req 级策略

AI 自动生成 `implementation-design.md`，但 PM 只看结构决策摘要。

示例：

```text
有 2 个实现决策需要你拍：

1. 用户数据要不要本地保存？
A. 固定 mock 数据，最快，适合看页面结构
B. 本地可新增 / 编辑，适合验证管理流程

2. 部门字段怎么处理？
A. 固定部门下拉
B. 做部门树选择，但部门管理本身不做
```

PM 不需要读 HOW 全文。

### §3.5 task-plan：PM 确认的拆分主文档

`task-plan.md` 是 PM 第二个主确认文档。它按 demo 阶段拆 task：

| Task | Demo 目标 | PM 要确认什么 | 深度 | 不做什么 |
|---|---|---|---|---|
| task-001 用户列表 | 看用户列表、搜索、筛选、状态展示 | 列表信息是否够决策者判断 | demo-light | 不做真实后端 |
| task-002 新增 / 编辑用户 | 新增用户、编辑基础信息 | 表单字段和流程是否合理 | demo-deep | 不做权限生效 |
| task-003 用户详情 | 查看用户详情、状态、部门、角色 | 信息组织是否清楚 | demo-light | 不做操作日志 |
| task-004 决策包整理 | 汇总 demo、限制、后续建议 | 是否能发给决策者 | document | 不写生产实现计划细节 |

PM 确认：

- task 是否拆得合适。
- 顺序是否合适。
- 每个 task 的 demo 目标是否清楚。
- 每个 task 的执行深度是否合适。

PM 不确认每个 task-contract。

### §3.6 task demo loop

每个 task 执行时：

```text
AI 生成内部 task-contract
  → 创建 task worktree
  → 实现 demo
  → 启动 dev server
  → 自动跑 UAT / QA / design checks
  → PM 看 demo
  → PM 通过 / 打回 / 调整范围
```

PM 看到的是：

```text
task-001 用户列表 demo 已可看

Demo:
http://localhost:3101/users

本轮你重点看：
1. 列表字段是否够用
2. 搜索和筛选是否符合后台用户管理习惯
3. 状态展示是否能支持后续运营判断

自动检查：
- 页面可打开
- 搜索流程通过
- 设计检查发现 1 个轻微问题，已修

请选择：
A. 确认 task-001，继续 task-002
B. 我要修改
C. 调整本 task 范围
```

PM 打回时直接说反馈，AI 记录反馈、改 demo、重跑检查、重新呈交。PM 不改 task-spec，不跑 close-task。

### §3.7 req 收尾：PRD 回填 + Decision Packet

所有 task 确认后，AI 反向更新文档：

| 文件 | 回填内容 |
|---|---|
| `prd.md` | 用真实 demo 替换计划性原型描述，更新原型覆盖范围，标注模拟 / 简化 / 本轮不实现 |
| `decision-packet.md` | demo 地址、操作路径、截图/录屏占位、验证了什么、不能误读什么、未决问题、后续 req 建议 |

PM 最终确认：

```text
这个包可以给决策者。
```

确认后 req 才 close / merge / archive。

---

## §4 worktree 模型

### §4.1 PM 心智模型

PM 只需要理解三层：

| 层级 | PM 是否感知 | 作用 |
|---|---|---|
| main worktree | 偶尔感知 | 已确认、已关闭的主线 |
| req worktree | 逻辑上感知 | 当前需求的 PRD、task-plan、decision packet、已确认 task 成果 |
| task worktree | 默认不感知 | AI 内部执行沙盒 |

PM 不应该再被要求：

- 手动切 task worktree。
- 复制 `/pmai-task-confirm`。
- 开新窗口跑 `/pmai-task-execute`。
- 在 task 窗口和 req 窗口之间来回 close。

### §4.2 task worktree 生命周期

```text
task-plan 确认
  → AI 生成 task-contract
  → AI 创建 task worktree
  → AI 实现 / 快改
  → PM 确认 demo
  → AI merge task worktree → req worktree
  → AI 删除 task worktree
  → 自动进入下一个 task
```

task worktree 是草稿区 / 执行区 / 快改区。req worktree 只收已确认 task 成果。main 只收已关闭 req。

### §4.3 为什么不默认直接改 req worktree

不建议默认在 req worktree 里直接做 task，因为：

- task demo 可能做坏。
- PM 可能连续打回多轮。
- 下一个 task 是否基于半成品继续会变模糊。

所以默认：

```text
task worktree = 可失败、可快改
req worktree = 已确认成果集合
main = 已关闭需求集合
```

### §4.4 并行 task

默认串行，除非 task-plan 明确可并行。

并行时 AI 可创建多个 task worktree，但 PM 仍只看到 demo 队列和确认项，不需要自己管理分支。

---

## §5 文档职责

| 文档 | 保留 | PM 是否主读 | 职责 |
|---|---|---|---|
| `docs/PROJECT.md` | 是 | 初始化阶段主读 | 项目定位、用户、术语、技术栈 |
| `docs/DESIGN.md` | 是 | 初始化阶段主读，后续摘要 | 设计基线、组件 inventory |
| `docs/PRODUCT-RULES.md` | 是 | 初始化阶段主读，后续按需 | 跨 req 产品规则 |
| `docs/ROADMAP.md` | 是 | 是 | req 队列，不拆 task |
| `prd.md` | 是 | 是 | req 真实需求 + 原型覆盖范围 |
| `implementation-design.md` | 是 | 否，只看结构决策摘要 | req 级 HOW，保证 task 间一致 |
| `task-plan.md` | 是 | 是 | task 拆分、demo 目标、PM 要确认什么、执行深度 |
| `task-contract` | 是 | 否 | AI 内部执行合同，每个 task 自动生成 |
| `decision-packet.md` | 新增 | 是 | 可交给决策者的 demo + 文档包 |

---

## §6 入口与状态

### §6.1 PM 常用入口

最终 PM 常用入口应收敛为：

```text
/pmai-init-project
/pmai-new-req "一句话需求"
/pmai-next
/pmai-status
```

`/pmai-next` 根据当前状态自动推进：该问问题就问，该写 PRD 就写，该跑 task 就跑，该给 demo 就给 demo。

以下入口保留为内部或异常恢复入口：

```text
/pmai-task-spec
/pmai-task-confirm
/pmai-task-execute
/pmai-close-task
```

### §6.2 新需求之间的边界

第一批 req 做完后，新需求仍从 `/pmai-new-req` 开始。大后台按 req 分批：

```text
req-001 用户管理第一批
req-002 角色权限第一批
req-003 部门组织第一批
req-004 资产管理第一批
```

如果当前还有未关闭 req，AI 先问：

```text
当前还有 req-001 未关闭。
你是要：
A. 继续 req-001
B. 先关闭 req-001
C. 另开 req-002
```

这是选择，不是手动命令。

---

## §7 实施批次

### VP0：锁定方案文档与术语

- 更新本文档。
- 更新 docs/INDEX。
- 明确“不引入 slice / 不做双 lane / task = demo 确认单元”。

验收：PM 认可整体流程和术语。

### VP1：PRD 原型覆盖范围

- 更新 `prd-writing` skill。
- 更新 PRD 模板。
- 新增覆盖范围表 lint。

验收：新 req 的 PRD 能同时表达真实需求和本轮原型覆盖范围。

### VP1.5：design 对齐阶段补回主流程

- 明确 `docs/DESIGN.md` 在初始化和新 req 中的职责。
- 在 PRD 后、implementation-design 前增加 design gap-check。
- 新 req 只向 PM 呈现新增组件 / 新页面模式 / 新交互方式等结构设计决策。
- 设计对齐结果写回 `docs/DESIGN.md` inventory 和 `implementation-design.md`。

验收：新 req 不会跳过设计阶段；PM 不读设计系统全文，但会拍影响 demo 和后续一致性的设计决策。

### VP2：task-plan 改成 demo task 计划

- 更新 `task-plan` skill 和模板。
- 增加 `执行深度`、`PM 要确认什么`、`不做什么`、`并行性` 字段。
- `task` 保持现有编号体系，不新增 slice。

验收：PM 只看 task-plan 就能判断怎么分阶段看 demo。

### VP3：task-contract 内部化

- 每个 task 自动生成内部 contract。
- PM 不再确认 task-spec。
- task-contract 深度由 task-plan 的执行深度决定。

验收：PM 不手动跑 `/pmai-task-spec`，AI 仍有足够执行依据。

### VP4：task demo 自动执行与 worktree 托管

- AI 自动创建 task worktree。
- 自动执行、启动 demo、跑检查。
- PM 只看 demo 和三选项。
- 通过后自动 merge task → req 并清理 worktree。

验收：PM 不手动切 task worktree，不跑 task-confirm / close-task 主路径。

### VP5：PRD 回填 + Decision Packet

- 扩展 close-req。
- 读取 task 反馈和执行结果。
- 回填 PRD 原型覆盖范围。
- 生成 `decision-packet.md`。

验收：PM 能直接把 `decision-packet.md` 发给决策者。

### VP6：`/pmai-next` 和 status-view 收敛

- 增加可机器消费的 next action。
- 修正当前 stage 6 待执行 task 总是提示 task-confirm 的问题。
- 让 PM 通过 `/pmai-next` 推动主流程。

验收：PM 不需要记忆内部命令链。

---

## §8 风险与约束

| 风险 | 约束 / 缓解 |
|---|---|
| AI 内部 task-contract 不经 PM 确认后跑偏 | PM 确认 task-plan；task demo 可打回；task-contract 只承接已确认 task-plan |
| implementation-design 后台化后重大 HOW 自决 | 结构决策摘要必须停下问 PM；只是不让 PM 全文读 HOW |
| PRD 写太全导致 demo 显得漏做 | PRD 必须有原型覆盖范围表 |
| task worktree 内部化后状态不可见 | status-view 必须显示 task demo 状态、URL、是否待 PM 确认 |
| 自动 close/merge 出错 | 内部命令保留为异常恢复入口；失败时暴露具体恢复动作 |
| demo 被误当生产实现 | decision packet 必须标注“可复用 / 需重写 / 仅演示” |

---

## §9 明确不做

| 不做 | 原因 |
|---|---|
| 不引入 slice | PM 已明确希望直接用 task |
| 不做 Prototype Sprint 独立 lane | 会增加入口选择成本；本方案保持一套 req 流程 |
| 不删除 PRD | PRD 是最终交付给决策者和后续实现的必要文档 |
| 不删除 implementation-design | 它保证多个 task 的实现策略一致 |
| 不让 PM 确认 task-spec | 这是原型阶段体感慢的核心来源之一 |
| 不让 PM 手动管理 task worktree | worktree 是隔离机制，不是 PM 工作流 |
| 不在初始化阶段拆 task | 初始化只建项目级上下文和规则 |

---

## §10 验收标准

方案落地后，真实新 req 应满足：

1. PM 从一句话需求进入深问，而不是直接 task/spec。
2. PRD 同时写真实需求和原型覆盖范围。
3. PRD 后有明确 design 对齐，新增组件 / 新页面模式 / 新交互方式会让 PM 拍板。
4. PM 确认 task-plan，而不是确认 task-spec。
5. 每个 task 都有 demo URL / 重点确认项 / 自动检查摘要。
6. PM 打回后 AI 快改，不要求 PM 操作 worktree。
7. task 通过后自动进入下一个 task。
8. req 结束后 PRD 被回填，生成 decision packet。
9. PM 常用入口不超过 init / new-req / next / status。

---

## §Y 决议日志

| 日期 | 决议 | 触发 / 上下文 |
|---|---|---|
| 2026-05-28 | 不新增 slice，直接用 task | PM 问“直接用 task 可以吗” |
| 2026-05-28 | task-spec 改为 AI 内部 task-contract，且每个 task 都生成 | PM 指出“如果复杂才生成”不明确 |
| 2026-05-28 | implementation-design 保留但后台化 | PM 问“implementdesign 不要了？” |
| 2026-05-28 | 项目初始化和新需求流程分开 | PM 指出两者应该不同 |
| 2026-05-28 | worktree 由 AI 内部托管，PM 不手动切 task worktree | PM 关心实施后的用户流程和 worktree 问题 |
| 2026-05-28 | design 阶段不删除，改为项目级 DESIGN + req 级 design 对齐 | PM 指出流程里像是把 design 阶段删掉了 |

---

*下一步：PM 锁定本文档方向后，按 VP1 → VP2 → VP3 → VP4 → VP5 → VP6 实施。*
