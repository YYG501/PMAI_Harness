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
  -> proposal 澄清产品为什么成立、值得先投什么
  -> design 讨论并形成建造依据
  -> spec-writing 编译已确认规格
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
- 不用完整 PRD 替代产品方向与模块探索，也不在 merge 前把目标要求写成已经落地。
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

## 旁路入口职责

产品推进与框架运维必须使用不同入口，避免同名 status 让 PM 无法判断自己看到的是产品进度还是安装状态：

- `/pmai-status` 只恢复产品进度、当前模块和唯一下一步。
- `/pmai-doctor` 只读诊断全局框架、宿主入口，以及当前消费仓的文档归位、mockups、正式实现入口和活动工作是否符合已安装版本；机器结果直接区分 PM 需要处理的检查项与仅供参考的信息，不能由 Agent 从底层 warning 二次猜测。消费仓 `AGENTS.md` 只允许在 PM 确认后同步带标记的 PMAI Startup 托管区块，项目自定义内容必须保留，未知旧规则或不安全文件形态必须停止。沙箱内无法确认远程版本时，由当前宿主申请联网权限后重跑只读远程查询；未授权或仍失败才报告暂时无法确认。其它修复或迁移同样必须再次确认。
- `/pmai-upgrade` 只执行已经确认的全局框架升级。

CLI 不再提供 `pmai status`。框架与消费仓健康检查统一使用 `pmai doctor --check`，产品进度只通过对话入口 `/pmai-status` 查看。

这些场景里，首版原型只是其中一步。更难的是：新需求不能脱离旧上下文，原型不能只停留在图，确认后的内容必须变成文档和后续实现依据。

---

## 理想协作流程

### 1. 项目初始化

初始化不是开始做功能，而是搭好产品上下文骨架：

- `PRODUCT.md`：产品定位、用户、术语、核心对象。
- `DESIGN.md`：设计基线、页面模式、组件和交互约定。
- `PRODUCT-RULES.md`：跨模块都要遵守的产品规则。
- `TODO.md`：后续模块工作候选队列。

初始化完成后，新项目唯一下一步是 `/pmai-proposal`。初始化不创建代码、prototype、mockup 看板或 dev server，也不要求 PM 在没有产品方案时先选项目类型和技术栈。

### 2. Product Proposal 澄清产品方向

Proposal 位于 design 上游，回答“这个产品为什么成立、值得先投什么”，形成产品级用户、问题、产品回答、价值、职责边界和 MVP 证明目标。新项目默认完成 Proposal；成熟资料目录或已有代码库只有在接入流程核验这些内容已经完整，在 `PRODUCT.md` 记录真实仓内依据与 PM 确认日期，并且产品基线与依据均已提交且无漂移、机器状态为 `equivalent_baseline` 时才可跳过。

一旦进入 Proposal，就必须形成一份可独立评审的完整 Product Proposal，不能用 brief、方向摘要、竞品报告或普通介绍稿代替。Proposal 定稿后同步精简基线到 `PRODUCT.md`，下游 design、spec-writing、build、doc-writing 和 record 只读消费；方向变化时创建完整新版本并明确取代旧版，不能原地改写历史版本。

### 3. 新需求开始

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

Proposal 提供产品级判断，模块 brief 只界定本轮目标；两者都不替代具体模块探索。完整 PRD 在模块决定闭合后由 spec-writing 编译，不提前冻结未知项。

### 4. design 讨论和内部能力编排

`/pmai-design` 是需求讨论前台。它先恢复旧决定和相关实现，再按真实未知项理清真问题、对象关系、动作、状态、权限、页面和异常路径。

- 产品模型不稳、补丁味或 PM 说“感觉不对”时，内部调用 `meta` 产出产品判断模型。
- 存在真实信息结构、任务路径或交互岔路时，内部调用 `mockup`；没有真实岔路只给一套推荐稿。
- 决定闭合后，内部调用 `spec-writing` 把已确认决定编译为规格。

这三项能力完成后都返回 design 主线，不让 PM 手动拼接命令。若讨论触及产品定位、目标用户、核心价值、职责边界或 MVP 证明目标，design 暂停并返回 Proposal；Proposal 确认后重新检查模块决定。首个可建造 design 定稿时，AI 基于需求和已有代码推荐 `prototype / product`、技术栈、代码入口和真实运行命令；PM 一次确认后写入 `.pm-workflow/project.yml`。后续 design 默认复用，只有定义确实无法承载新需求时才重新校准。

规格内容采用“通用内容模块 + 可叠加 Profile”，文档形态由 Preset 决定。企业平台加载企业平台 Profile，AI 产品加载 AI Profile，企业 AI 平台叠加两份；完整 PRD 使用唯一完整 PRD Preset。Profile 增强领域内容，不创造新的文档类型；Preset 只决定章节编排，不创造第二套产品真相源。

### 5. 统一 build 和看结果修改

一次 build 只有一个主要对象：`prototype` 或 `product`，由 design 已提交的 `.pm-workflow/project.yml` 决定。两者走同一条生命周期，只切换验收工具与方法：

- prototype 把用户可见的任务路径、页面 / 弹窗、边界状态和操作反馈做成可交互结果；数据库、鉴权、外部集成、异步任务等底层能力默认模拟，不因规格描述最终目标就自动建成真实系统；
- product 看仓库测试、typecheck / build、接口和数据行为、迁移兼容性，并按风险追加 UI、权限、安全或数据检查。

规格与建造对象分工明确：`spec.md` / PRD 继续定义最终产品应该具备什么，build 的实现深度合同决定这一轮做到哪一层。原型的“完整”是已确认的用户可观察行为能够真实交互和验证，不是底层能力生产化；真实数据库、鉴权、外部副作用或生产基础设施只有在 active decision 明确批准 prototype real edge，或项目建造对象改为 `product` 后才能进入实现。

实现深度合同写入版本化 build contract，并在首次构建、每轮反馈修改和中断恢复时重新交给构建工具。prototype 候选定稿前必须通过不可 exception 的 `prototype-boundary`：候选 diff 只能在批准目标内，生产建设信号必须有决定依据，AI 还要明确完成一次语义复核。这样不依赖模型记住首轮 prompt。

只要本轮包含 Web 页面，主动浏览器能力就是验收硬条件。gstack 可以缺席初始化，也可以由其它 browser/Playwright 适配器替代；但没有任何工具实际打开并操作页面时，UI final check 不能通过。

开工前 AI 根据项目定义、本机能力和当前主控推荐工作环境与构建工具，并在一张确认卡中同时列出两项的全部有效选择。外部构建工具候选排除当前主控对应的 profile，避免 Codex 再启动 Codex、Claude Code 再启动 Claude Code、Kimi Code 再启动 Kimi Code 或 OpenCode 再启动 OpenCode；当前会话亲自完成构建不是递归调用，因此“当前会话直接构建”始终可选。没有可用外部工具时，默认推荐当前会话直接构建。确认卡不展示项目类型、验收方案或内部合同。外部 builder 只用于首次实现或大型重构；active build 内的文案、布局、按钮和局部交互由当前会话直接处理。

PM 看结果期间走快速迭代车道：复用同一个 dev server 和浏览器连接，每轮只做热更新、typecheck 与当前页面/受影响交互走查，完成后先回“已修改，可刷新查看”。build contract v5 把验收档案拆成 `iteration_checks / final_checks`，并只保留一个 build lifecycle 写入位置；PM 明确说“定稿 / 可以提交 / 可以合并”前，机器不允许写 final evidence 或生成 `review-ready`。小改 2–5 分钟、交互改动 5–10 分钟是 time-to-preview 目标和超时预警，不是阻断门。

worktree 的具体实现、build contract、source hash 和证据 JSON 都是后台基础设施，不形成第二条用户流程；PM 只看到可理解的“工作环境”和“构建工具”。

### 6. 自动落地主线和文档编译

PM 明确定稿后，合同冻结 PM 最后看到的 implementation commit，并只运行一次完整 final checks：project.yml 声明的 test/typecheck/production build 在 detached validation worktree 执行，不改写 active dev worktree 的构建缓存；完整浏览器验收继续复用现有 dev server 与浏览器连接。通过后形成验收就绪快照，再由同一个 finalize 确定性落地：

1. 校验定稿请求、未决产品问题、最终 commit 和验收就绪快照仍一致；
2. 提交实现并合入 main；
3. 实现 landed 后，用 main 的 landed diff、build contract 和 accepted deltas 生成准确的文档影响地图；
4. 按“符合 / accepted delta / 漏实现 / 无依据实现”对账模块规格，只让 accepted delta 改写最终目标；
5. 更新产品现状、跨模块规则、术语、设计基线、TODO、mockup 清单和索引；
6. 做一致性检查并提交文档同步。

模块 `spec.md` 和 PRD 描述已确认的最终产品目标，是研发实现和验收合同；`PRODUCT-STATE.md` 等现状文档才只描述 main 已经存在的事实。原型、mockup 和代码是证据，不得反向缩小规格。merge 冲突保留可恢复的 `final_check`；文档失败保留 `landed/docs_pending`，修复时不重复 merge。`/pmai-build-close` 只作为兼容与恢复入口。

正式规格发布到飞书后发生的二次评审，不是脱离主链路的文档搬运：PMAI 先全局恢复 main 与 attached worktree 中未 checkpoint 的普通批次，再按文档身份绑定当前权威规格。发布基线 B、采集时本地 L、采集时飞书 R 始终是只读证据，系统先生成独立目标版 T，再按最高影响分流。普通文字修正和已批准范围内的小调整只有完成归位的 T 能写回正式规格；产品方向或模块模型变化则把旧批冻结成 main handoff，旧 T 永不写回。handoff 的 route 只记录来源，机器 phase 决定唯一入口：产品级按 `proposal → design → lark_review → closed`，模块级按 `design → lark_review → closed`；Proposal 生效提交、design 权威规格提交和 fresh checkpoint 分别推进一段，不能靠文字判断跳级。这样跨会话或旧工作环境退役后仍能恢复原评审，也不会循环回 Proposal 或把方向变化降级成 accepted delta。验证完成后只解决已完成评论，不能让飞书成为另一套产品真相源。

---

## 核心能力目标

PMAI 应形成 6 个核心能力。

### 1. Versioned Product Proposal

新项目在模块设计前形成完整产品级判断；成熟项目复用完整等价基线。当前 Proposal 通过版本、正文 hash、`PRODUCT.md` 产品基线 hash 和取代关系保持不可漂移，并把固定交接摘要编进下游上下文。产品方向纠正生成完整新版本，让旧 design/build 依据失效，而不是把方向变化伪装成模块决定或轻量补录；术语等非产品基线章节仍可由各自 owner 正常更新。

### 2. Product Context Spine

项目持续维护一套可被每次工作读取的产品脊柱：

- 当前产品定位。
- 已有模块和页面。
- 已有原型。
- 设计基线。
- 产品规则。
- 最近确认的决策。
- 本次需求可能影响范围。

### 3. Deterministic Context Pack

design、build、恢复、最终检查和文档更新共用同一份编译上下文：当前 Proposal 及交接摘要、当前目标与 build 对象、权威事实、相关源码 / 原型证据、active / superseded 决定、未决问题、输入 hash、design revision 和实现 commit。它只编译现有真相源，不另建决定账本。

### 4. Unified Build Loop

prototype 和 product 共用 `designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`。快速迭代和定稿验收是 `iterating` 内部的两条执行车道，不新增 PM 可见状态：PM 看结果多轮修改时不跑完整验收，PM 请求定稿后才冻结 commit、生成验收就绪快照；框架处理证据失效和恢复。

### 5. Adaptive Acceptance And Post-Land Docs

验收随 build 对象和风险自适应，快速与最终证据分层，final evidence 绑定定稿请求、当前 source hash 与 implementation commit；工具受限只能记 exception，不能伪装 pass。实现进入 main 后对账目标规格与实现，更新已落地现状，并要求每个对象、动作、状态、权限、页面和术语都有正确文档落点。

### 6. Continuity Across Modules

多个模块工作之间要连续：

- 后续模块工作继承前序对象模型和设计基线。
- 新构建结果不应无意推翻旧决策。
- 大后台可以按用户、角色、部门、资产等模块分批做。
- 每个模块工作以可看结果和当前规格为确认单元，不让 PM 管理工程 ticket。

---

## 成功标准

PMAI 成功时，PM 的体验应该是：

- "我不用每次重新解释产品。"
- "新项目先把为什么做、为谁做、先证明什么讲清楚，再讨论具体模块。"
- "AI 知道已有文档和已有原型。"
- "我给一个新需求，AI 会先基于上下文讨论，而不是从零猜。"
- "不管这次建的是原型还是真实产品，我都能看着结果改。"
- "开工前我只确认工作环境和构建工具，不需要每轮重新选项目类型或验收方案。"
- "我说可以提交后，AI 会完成检查、合入主线并把正式文档整体对齐。"
- "我在飞书 review 完规格后，AI 能把正文修改和批注接回本地规格与原型，不用我手工重述。"
- "大系统可以一个模块一个模块地做，不会一口气全做乱。"
- "我做决策，AI 管执行细节。"

如果 PM 主要感受到的是复制命令、确认中间规格、管理 worktree、等待执行合同，那么流程就偏离了本文定位。

---

## 对当前框架改造的含义

后续改造应以本文为准：

- 正常主链是 `init → proposal → design → spec-writing → build`；Proposal 负责产品级澄清，design 负责模块决定，spec-writing 负责把闭合决定编译成规格。
- 新项目默认完成完整 Proposal；成熟项目只有显式记录依据与 PM 确认日期、相关文件已提交且无漂移、通过机器门的完整等价产品基线才可跳过。一旦进入就必须完整产出，已确认版本仅供下游读取；方向纠正必须回 Proposal 新建版本并 supersede 旧版。
- design 是模块需求讨论主入口；meta、mockup、spec-writing 按需后台调用并返回主线。spec-writing 也保留明确专项意图下的手动入口。
- spec-writing 复用通用内容模块，按领域叠加企业平台 / AI Product Profile，并按文档需要选择 Preset；完整 PRD 是唯一 Preset，不是通用默认形态或第二套真相源。
- 一个 Skill 只有在承接独立用户意图时才注册为宿主入口；恢复和底层执行能力保留在框架内，由前台 Skill 自动调用，不要求 PM 记住或编排。meta、mockup、spec-writing 默认后台调用，但保留明确专项意图下的手动入口。
- 面向 PM 的上手文档只讲初始化、Proposal、design → build 和迷路时的 status，不把全部 Skill 铺成命令导航。
- 产品现状、框架诊断和升级分别由 `/pmai-status`、`/pmai-doctor`、`/pmai-upgrade` 承担，不允许重新混成两个 status。
- 初始化只建立上下文骨架；Proposal 建立产品级基线；首个可建造 design 生成唯一 `.pm-workflow/project.yml`，其中分开记录建造对象与技术栈。
- prototype 与 product 共用同一构建、迭代、定稿和收尾链路，只切换验收适配器。
- build contract、worktree 细节和验收证据后台化；工作环境与构建工具由 AI 推荐、PM 一次确认。
- active build 默认走当前会话快速迭代；定稿请求前不跑 production build，定稿后在隔离 validation worktree 对冻结提交统一验收一次。
- 模块规格在 design 定稿时形成最终目标合同；landed 后只有 accepted delta 能修改目标，漏实现不得反向删需求。
- `PRODUCT-STATE.md` 等现状文档只在实现落入 main 后更新；过程和历史进入 Git 与 decisions。
- `/pmai-record` 只在没有 active work 且 Proposal 状态为 `accepted / equivalent_baseline` 时补录已经确认的知识，不承担产品方向纠正、模块同步或 Proposal 修改。
- `/pmai-build-close` 不再是正常用户必经命令，只保留兼容与恢复。
- Claude Design / design-html / Claude Code 等仍可作为原型或构建能力来源，PMAI 负责统一上下文、验收和后续事实沉淀。
