# PMAI 产品意义与目标

> **状态**：产品定位真相源。人读 README 时应能找到；AI 读 CLAUDE.md 时必须按本文判断流程取舍。
> **日期**：2026-07-10

---

## 一句话定位

PMAI 是面向 PM 的 **产品上下文统一层**。

它的目标不是替代 Claude Design、design-html 或 Claude Code 去抢第一版原型，而是让 AI 在每次协作时都知道：

- 这个产品是什么。
- 已有文档说了什么。
- 已有原型和真实产品现在是什么样。
- 哪些需求、页面、对象、规则已经确认。
- 这次新需求会影响哪些已有上下文。
- 构建结果定稿并进入主线后，如何把真实产品事实、规格和决定整体对齐。

---

## 要解决的真实问题

PMAI 最初要解决的核心问题不是"快速画一个原型"，而是 **上下文不统一**。

在真实 PM 工作里，上下文会散在多个地方：

- 和 AI 的多轮讨论。
- `PROJECT.md` / `DESIGN.md` / `PRODUCT-RULES.md` / `ROADMAP.md`。
- 每个模块的 discussion、decisions、spec，以及原型和反馈记录。
- Claude Design / design-html / Claude Code 产出的原型。
- PM 看 prototype 或真实 product 后的反馈和取舍。
- 代码仓、worktree、测试结果、验收证据和 landed 后文档结果。

如果这些上下文不能统一，AI 就会在新需求里反复失忆：某一屏原型可能很好，但它不知道这个页面属于哪个模块、哪些字段是产品对象的一部分、哪些只是 mock、哪些决策已经被 PM 确认、最后 PRD 应该怎么写给决策者看。

PMAI 的价值就是把这些东西接起来。

---

## Claude Design 带来的关键启发

Claude Design 强，不是因为它用了一个本质不同的 Claude 模型，而是因为它把同一个模型放进了更适合设计探索的工作台。

关键差异是：

```text
Claude 模型
  + 设计型任务 framing
  + 可视化工作台
  + 文件化设计资产
  + 极短反馈回路
  + 默认以界面为输出
  + 允许发散和产品 critique
```

而 PMAI 旧流程更像：

```text
Claude 模型
  + 规格文档流
  + 状态机
  + worktree
  + task / spec / confirm / execute
  + 工程安全约束
```

同一个模型，在设计工作台里会更像设计师；在规格流程里会更像执行工程师。前者天然适合探索，后者天然适合收敛、追踪、沉淀和落地。

这条判断直接改变 PMAI 的改造方向：

- 不能用重规格流程去抢第一版原型探索。
- 应该吸收 Claude Design 的短反馈回路：更快看到原型，看着原型改。
- 应该允许 Claude Design、design-html、Claude Code 都成为原型来源。
- PMAI 的主价值应放在方向进入持续构建之后：统一设计依据、构建对象、反馈、验收证据、主线事实和后续模块继承。

一句话：

> PMAI 不和 Claude Design 正面对打。Claude Design 越强，越应该被 PMAI 当作高质量原型来源接进来。

---

## PMAI 不是什么

PMAI 不应该和 Claude Design 比"谁更快从粗想法生成漂亮原型"。

Claude Design 这类工具更适合早期发散：

```text
想法
  -> 产品 critique
  -> 多方向探索
  -> 快速可视化原型
  -> 看图快速修改
```

PMAI 更适合在方向逐渐明确后接管上下文、边界、文档和可持续迭代：

```text
加载现有产品上下文
  -> design 讨论并形成建造依据
  -> build prototype 或真实 product
  -> PM 看结果并多轮修改
  -> PM 明确定稿
  -> 最终检查并合入 main
  -> 基于 main 对账规格目标并更新产品现状文档
  -> 进入后续模块工作
```

所以 PMAI 的非目标是：

- 不做通用设计工作台。
- 不追求首版原型生成速度超过专门设计工具。
- 不把完整 PRD 放在探索之前当重门，也不在 merge 前把目标要求写成已经落地。
- 不为团队 SOP、CI 平台、多租户基础设施设计。
- 不让 PM 管理 worktree、build 执行合同、执行器细节。

---

## 目标用户和强场景

PMAI 的主要用户是单人 PM，尤其是要持续推进一个复杂业务产品的人。

强场景包括：

- 后台管理系统。
- B2B 工作台。
- CRM / 资产 / 权限 / 组织 / 审批这类多对象系统。
- 多个模块分批推进的大产品。
- 原型需要给决策者评审，但 PRD 也必须沉淀的项目。
- 前后多个需求之间存在对象、权限、流程、字段、设计模式继承关系的项目。

这些场景里，首版原型只是其中一步。更难的是：新需求不能脱离旧上下文，原型不能只停留在图，确认后的内容必须变成文档和后续实现依据。

---

## 理想协作流程

### 1. 项目初始化

初始化不是开始做功能，而是建立产品基线：

- `PRODUCT.md`：产品定位、用户、术语、核心对象。
- `DESIGN.md`：设计基线、页面模式、组件和交互约定。
- `PRODUCT-RULES.md`：跨模块都要遵守的产品规则。
- `TODO.md`：后续模块工作候选队列。

初始化完成后，AI 应能主动复述当前产品上下文，并把 PM 带到第一个 `/pmai-design`。初始化不创建代码、prototype、mockup 看板或 dev server，也不要求 PM 在没有需求方案时先选项目类型和技术栈。

### 2. 新需求开始

新需求不是从空白问题开始，而是先加载已有上下文：

```text
已有产品是什么？
已有模块和原型有哪些？
这次需求影响哪些对象 / 页面 / 规则？
哪些既有决策不能破坏？
项目是否已经有 design 定稿后的建造定义？
按该对象和本轮风险，默认验收需要覆盖什么？
哪些可以 mock？
哪些不能 mock，因为会误导决策？
```

前置文档只做轻量 brief。完整 PRD 不应该过早冻结探索。

### 3. design 讨论和内部能力编排

`/pmai-design` 是需求讨论前台。它先恢复旧决定和相关实现，再按真实未知项理清真问题、对象关系、动作、状态、权限、页面和异常路径。

- 产品模型不稳、补丁味或 PM 说“感觉不对”时，内部调用 `meta` 产出产品判断模型。
- 存在真实信息结构、任务路径或交互岔路时，内部调用 `mockup`；没有真实岔路只给一套推荐稿。
- 决定闭合后，内部调用 `spec-writing` 把已确认决定编译为规格。

这三项能力完成后都返回 design 主线，不让 PM 手动拼接命令。首个可建造 design 定稿时，AI 基于需求和已有代码推荐 `prototype / product`、技术栈、代码入口和真实运行命令；PM 一次确认后写入 `.pm-workflow/project.yml`。后续 design 默认复用，只有定义确实无法承载新需求时才重新校准。

### 4. 统一 build 和看结果修改

一次 build 只有一个主要对象：`prototype` 或 `product`，由 design 已提交的 `.pm-workflow/project.yml` 决定。两者走同一条生命周期，只切换验收工具与方法：

- prototype 看可启动性、任务路径、页面 / 弹窗、边界状态、视觉和交互行为；
- product 看仓库测试、typecheck / build、接口和数据行为、迁移兼容性，并按风险追加 UI、权限、安全或数据检查。

只要本轮包含 Web 页面，主动浏览器能力就是验收硬条件。gstack 可以缺席初始化，也可以由其它 browser/Playwright 适配器替代；但没有任何工具实际打开并操作页面时，UI final check 不能通过。

开工前 AI 根据项目定义、本机能力和当前主控推荐工作环境与构建工具，并在一张确认卡中同时列出两项的全部有效选择。外部构建工具候选排除当前主控对应的 profile，避免 Codex 再启动 Codex、Claude Code 再启动 Claude Code 或 OpenCode 再启动 OpenCode；当前会话亲自完成构建不是递归调用，因此“当前会话直接构建”始终可选。没有可用外部工具时，默认推荐当前会话直接构建。确认卡不展示项目类型、验收方案或内部合同。之后 PM 的体验始终是：看结果、指出哪里不对、AI 修改、再看。每轮修改先跑受影响的快速检查并尽快展示结果；候选版本在 PM 查看期间完成完整 required checks、规格覆盖和文档影响草案，形成绑定当前 source hash 与 implementation commit 的验收就绪快照。

worktree 的具体实现、build contract、source hash 和证据 JSON 都是后台基础设施，不形成第二条用户流程；PM 只看到可理解的“工作环境”和“构建工具”。

### 5. 自动落地主线和文档编译

PM 明确定稿后，同一个 finalize 复用未过期的验收就绪快照，不在 close 内首次发现产品缺口或补业务代码：

1. 校验未决产品问题、最终 commit 和验收就绪快照仍一致；
2. 提交实现并合入 main；
3. 复用 build 阶段的文档影响草案，并用 main 的 landed diff、build contract 和 accepted deltas 校准；
4. 按“符合 / accepted delta / 漏实现 / 无依据实现”对账模块规格，只让 accepted delta 改写最终目标；
5. 更新产品现状、跨模块规则、术语、设计基线、TODO、mockup 清单和索引；
6. 做一致性检查并提交文档同步。

模块 `spec.md` 和 PRD 描述已确认的最终产品目标，是研发实现和验收合同；`PRODUCT-STATE.md` 等现状文档才只描述 main 已经存在的事实。原型、mockup 和代码是证据，不得反向缩小规格。merge 冲突保留可恢复的 `final_check`；文档失败保留 `landed/docs_pending`，修复时不重复 merge。`/pmai-build-close` 只作为兼容与恢复入口。

---

## 核心能力目标

PMAI 应形成 5 个核心能力。

### 1. Product Context Spine

项目持续维护一套可被每次工作读取的产品脊柱：

- 当前产品定位。
- 已有模块和页面。
- 已有原型。
- 设计基线。
- 产品规则。
- 最近确认的决策。
- 本次需求可能影响范围。

### 2. Deterministic Context Pack

design、build、恢复、最终检查和文档更新共用同一份编译上下文：当前目标与 build 对象、权威事实、相关源码 / 原型证据、active / superseded 决定、未决问题、输入 hash、design revision 和实现 commit。它只编译现有真相源，不另建决定账本。

### 3. Unified Build Loop

prototype 和 product 共用 `designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`。验收就绪快照是 `iterating` 内部的候选门，不新增 PM 可见状态；AI 推荐工作环境和构建工具，PM 一次确认，之后 PM 看结果多轮修改，框架处理证据失效和恢复。

### 4. Adaptive Acceptance And Post-Land Docs

验收随 build 对象和风险自适应，证据绑定当前 source hash 与 implementation commit；工具受限只能记 exception，不能伪装 pass。实现进入 main 后对账目标规格与实现，更新已落地现状，并要求每个对象、动作、状态、权限、页面和术语都有正确文档落点。

### 5. Continuity Across Modules

多个模块工作之间要连续：

- 后续模块工作继承前序对象模型和设计基线。
- 新构建结果不应无意推翻旧决策。
- 大后台可以按用户、角色、部门、资产等模块分批做。
- 每个模块工作以可看结果和当前规格为确认单元，不让 PM 管理工程 ticket。

---

## 成功标准

PMAI 成功时，PM 的体验应该是：

- "我不用每次重新解释产品。"
- "AI 知道已有文档和已有原型。"
- "我给一个新需求，AI 会先基于上下文讨论，而不是从零猜。"
- "不管这次建的是原型还是真实产品，我都能看着结果改。"
- "开工前我只确认工作环境和构建工具，不需要每轮重新选项目类型或验收方案。"
- "我说可以提交后，AI 会完成检查、合入主线并把正式文档整体对齐。"
- "大系统可以一个模块一个模块地做，不会一口气全做乱。"
- "我做决策，AI 管执行细节。"

如果 PM 主要感受到的是复制命令、确认中间规格、管理 worktree、等待执行合同，那么流程就偏离了本文定位。

---

## 对当前框架改造的含义

后续改造应以本文为准：

- design 是需求讨论主入口；meta、mockup、spec-writing 按需后台调用并返回主线。
- 初始化只建立上下文；首个可建造 design 生成唯一 `.pm-workflow/project.yml`，其中分开记录建造对象与技术栈。
- prototype 与 product 共用同一构建、迭代、定稿和收尾链路，只切换验收适配器。
- build contract、worktree 细节和验收证据后台化；工作环境与构建工具由 AI 推荐、PM 一次确认。
- 模块规格在 design 定稿时形成最终目标合同；landed 后只有 accepted delta 能修改目标，漏实现不得反向删需求。
- `PRODUCT-STATE.md` 等现状文档只在实现落入 main 后更新；过程和历史进入 Git 与 decisions。
- `/pmai-build-close` 不再是正常用户必经命令，只保留兼容与恢复。
- Claude Design / design-html / Claude Code 等仍可作为原型或构建能力来源，PMAI 负责统一上下文、验收和后续事实沉淀。
