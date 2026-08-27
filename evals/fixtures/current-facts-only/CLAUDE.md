# PMAI E2E Fixture

## 框架规则（不要修改此区域）

**会话开始时必须执行：**

1. 读取本文件了解项目上下文。
2. 运行 `PMAI_PREAMBLE_READ_ONLY=1; export PMAI_PREAMBLE_READ_ONLY; source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"; unset PMAI_PREAMBLE_READ_ONLY` 只读检测当前工作位置。
3. Claude Code / Codex 运行 `bash "${PMAI_HOME:-$HOME/.pmai}/scripts/install-project-hooks.sh" --check` 只读检查项目 hooks；缺失或漂移时先向 PM 报告，得到确认后才运行不带 `--check` 的同一命令刷新，不能只按配置文件存在就声称已更新。
4. 运行当前主控的 status 入口了解当前模块和下一步：Claude Code 使用 `/pmai-status`，Codex 使用 `$pmai-status`。

框架、宿主入口或当前消费仓的文件归位、原型/实现入口与活动工作是否健康，只在 PM 要求诊断时使用 `/pmai-doctor`（Codex：`$pmai-doctor`）。它不属于正常产品推进循环，默认只读；升级、修复和文件迁移必须另行确认。

> Claude Code 与 Codex 是完整主控。Kimi Code、OpenCode 和 Cursor Agent 只由 `/pmai-build` 作为外部 Builder 调用，不解析本文的 PMAI Skill，也不推进 lifecycle、验收或 landing。

---

### 角色定义（单窗口模型）

| 角色 | 职责 |
|---|---|
| PM | 决策、确认、验收。不写代码。默认一个窗口 |
| 驱动 AI | PM 这个窗口里的 AI：恢复上下文、推进 design、派发 build、呈交结果、多轮修改并在 PM 定稿后自动收尾 |
| 构建工具 | `/pmai-build` 根据项目定义、消费仓配置和本机可用性推荐的建造能力；PM 在开工卡中确认或调整 |

### 状态与文件真相源

当前活跃架构只认模块目录：

- 模块状态：`docs/modules/<模块>/.work-meta.json`
- 模块讨论：`docs/modules/<模块>/discussion.md`
- 模块决策：`docs/modules/<模块>/decisions.md`
- 模块规格：`docs/modules/<模块>/spec.md`
- 功能型规格文档：`docs/modules/<按内容命名>.md`
- 当前 Product Proposal 合同：`.pm-workflow/proposal.json`
- Product Proposal 正文与版本索引：`docs/proposals/<slug>-vN.md` / `docs/proposals/INDEX.md`
- 项目现状：`PRODUCT-STATE.md`
- 跨模块规则：`PRODUCT-RULES.md`
- 视觉规范：`DESIGN.md`
- 文档索引：`docs/INDEX.md`
- 项目建造定义：`.pm-workflow/project.yml`（首个可建造 design 才生成；代码根与入口以其中 `implementation` 为准）
- 输入材料：`docs/inputs/<类别>/`（材料按类型留存；当前模块引用记录在模块 `.work-meta.json`）
- 工程文档：`docs/engineering/`（README/API/CLI/架构/how-to/tutorial/reference；INDEX.md 是接回索引）

不要创建 `requirements/active|closed`、`task-plan.md` 或 `tasks/task-NNN.md`。历史仓库里如果还有这些文件，只作归档/迁移证据，不作为新流程入口。

### 路径原则

- 不写死机器绑定路径：项目文档、业务代码、prompt 记录和框架规则里，不得写死 `/Users/<某人>/...` 这类本地路径。需要定位文件时，用 `PMAI_HOME` / `REPO_ROOT` / `MAIN_REPO_ROOT` / `BUILD_DIR` 等运行时变量和仓内相对路径组合；PM 上传本机材料时可临时读取其路径，但不要把源路径全文沉淀进产品文档或代码。

### 工作分档

| 档 | 什么时候 | 怎么走 | 收尾 |
|---|---|---|---|
| 轻 | typo、链接、格式、很小代码修补 | 代码走 `/pmai-quick-fix`；纯文档记录可在 main 由 `/pmai-record` 归位 | 需要沉淀长期基线时 `/pmai-record` |
| 中 | 一个模块内的完整讨论 / 规格演进 | 已有 active design 直接继续 `/pmai-design`；上下文不清时先用 `/pmai-status` 只读恢复 | 可先停住；下次仍继续 design，不用 record 收尾 |
| 重 | 需要实际建原型或真实产品能力 | `/pmai-design` 定稿并自动固定建造依据 → `/pmai-build <模块或文档>` → 看结果多轮修改 | PM 明确定稿后自动最终检查、合入 main、更新正式文档 |
| 产品级 | 新产品立项，或定位、用户、价值、边界、MVP 需要重判 | `/pmai-proposal` 完整澄清并同步精简产品基线 | 回到 `/pmai-design` 设计第一个或原来的模块 |

### 主入口

- `/pmai-init-project` — 项目初始化统一入口：全新项目建底座，已有代码库自动盘点现状。
- `/pmai-proposal` — 产品级澄清与方向修订：完整论证用户、问题、产品回答、价值、边界、MVP 和演进条件；新项目默认先走，成熟项目只有已提交且通过机器核验的等价基线才可跳过。
- `/pmai-design "<一句话需求>"` — 起新功能 / 重做模块；按需自动调用 meta、mockup、spec-writing，提交建造依据。
- `/pmai-design <模块>` — 讨论、收范围、写模块三件套。
- `/pmai-build <模块或功能文档>` — 静默读取项目级构建类型和默认验收，在一张卡中展示推荐的工作环境、构建工具及全部有效选项；PM 一次确认后构建、迭代、最终检查并自动收尾。
- `/pmai-status` — 只读当前现状并建议下一步，不自动改变状态。
- `/pmai-doctor` — 按需只读检查全局框架、宿主入口，以及当前消费仓的文件归位、mockups、正式实现入口和活动工作；不代替 status，不自动升级、修复或迁移文件。
- 已有 `building / iterating / final_check` 时，“启动看看”“还有什么问题”“继续改当前结果”等自然语言继续当前 `/pmai-build`。先读取 `active-build-context.py` 并重新编译 context pack；除非 PM 明确开启无关新工作，否则不转成无范围通用 QA。多个 active build 只问模块，不猜。
- `/pmai-doc-writing` — 介绍型文档成文器；产品介绍、功能清单、优势说明、一页纸、汇报材料默认落 `docs/deliverables/`。
- `/pmai-record` — 无 active work 时补录 PM 已确认的 TODO、稳定术语、跨模块规则或项目级理路；不改 Proposal、模块规格、mockup 或代码。
- `/pmai-feedback` — 只读复盘当前完整会话，识别设计不一致与使用卡点，生成带原始会话文件地址的 PMAI 框架优化 Prompt；当前只有 Codex 的精确会话定位已验证，其它宿主不得猜测定位。
- `/pmai-lark-review` — 回收已发布飞书规格的正文修改和批注；普通未完成批次可跨 worktree 恢复，高影响变化生成 main handoff 并按 Proposal/design/lark-review 的机器 phase 接力，fresh checkpoint 后关闭。
- `/pmai-publish-to-lark` — 把本地 Markdown 发布或更新到飞书；首次创建，已有文档默认精细更新，只有明确要求时才整篇覆盖。
- `/pmai-sync-from-lark` — PM 已明确以飞书为准且不需要产品判断时，把飞书正文机械同步回本地。

### 确认门

- 按共用 decision policy 处理：机械项后台完成；可逆偏好由 AI 给推荐并推进；只有产品模型岔路、不可逆动作、AI 要改变 PM 已明确方向，以及 build 开工前的工作环境与构建工具需要 PM 拍。
- 不把是否调用 meta/mockup/spec-writing、项目类型、验收方案、保存依据或手动 close 变成每轮 build 问题。开工卡只显示工作环境和构建工具，但必须一次列出这两项的全部有效选择。
- PM 在看到构建结果后说“可以提交 / 定稿 / 可以合并”，即是合入 main 的明确授权，不二次确认。
- design 的模块产品决定题先登记 `.work-meta.json:decision_gates` 再展示；Design 可以用 `open-round` 登记同一 frontier 的多个独立问题，用户消息只绑定当时同一 round 的 pending 题，并由 `answer-round` 逐题声明回答范围；frontier 清空后必须再登记并消费 `shared-understanding` 确认，最终 `spec.md` 与 ready 会绑定该收据。Proposal 与阶段路由题仍登记 `.pm-workflow/context/decision-gates.json` 并逐题处理。答复写入决定或项目动作后分别 consume 到 D 编号、`proposal:draft`、`proposal:accept` 或 `route:<动作>`，并由 scoped checkpoint / ready / Proposal 原子提交复核。聊天摘要、旧答复和未展示的建议题没有授权能力；Proposal 原子提交涉及 `.pm-workflow/proposal.json` 或 `PRODUCT.md` 时必须有本轮 `proposal:accept` 收据。

### build 纪律

- build 的功能锚点是 design 已提交的模块 `spec.md` 或功能型规格文档，不是 task 文件；开工和关键恢复点先编译 context pack。
- 一次 build 只有一个主要对象：`prototype` 或 `product`，由首个可建造 design 定稿后生成的 `.pm-workflow/project.yml` 定义。技术栈、代码入口和运行命令也只从该文件读取；build 不临时猜。
- 新 build 由 AI 推荐独立/当前工作环境和构建工具，并在同一张卡列出全部有效选项；外部构建工具排除当前主控对应的 profile，“当前会话直接构建”始终可选，外部工具均不可用时推荐它。PM 一次确认后执行；项目类型和默认验收不展示。选择当前环境时，main 只放行 v2 合同声明的目标路径。小改仍走 `/pmai-quick-fix`。
- `.work-meta.json:build` 中的 contract v5 记录唯一 build lifecycle、target、source hash、design revision、accepted deltas、implementation commit、`iteration_checks / final_checks`、两层 evidence、定稿请求和 docs status；v1-v4 仅由统一兼容读取层用于旧 build 恢复。
- 每轮修改由当前会话优先处理，只跑热更新、typecheck 和当前页面走查，保留同一 dev server 与浏览器连接并立即回“已修改，可刷新查看”；外部 builder 只用于首次实现或大型重构。只有当前批准模块与任务内、且不改变产品基线或模块模型的小范围调整可写 accepted delta，并让旧证据和定稿请求失效；产品级变化回 Proposal，模块模型变化回 design。
- PM 明确请求定稿后，才冻结 commit、在 validation worktree 运行一次 production build 和完整 final checks，再通过 `review-ready`。2–5 / 5–10 分钟是 time-to-preview 预警目标，不是阻断门。
- prototype 验收覆盖可启动性、任务路径、页面/弹窗、边界状态、视觉和行为；product 验收覆盖现有测试、typecheck/build、接口数据、迁移兼容，并按需追加 UI、权限与安全检查。
- active build 的查看和问题检查只对账现有 spec、active decisions、accepted deltas、批准路径与当前 acceptance lane。prototype 的 `simulate_by_default` 不列为缺口，规格已有要求不重新包装成开放问题；product 仍按 production implementation 检查。
- 证据必须绑定当前 source hash 和 implementation commit；limited/skipped/blocked 不能伪装 pass。
- PM 定稿后的 final_check 只校验同一 source hash / implementation commit / finalization request 的验收就绪快照，不首次补实现或重跑完整验收；通过后先合入 main，再基于 landed diff 生成文档影响地图并更新正式文档。文档失败保留 `landed/docs_pending`，纯清理失败进入待清理队列，续跑不重复 merge。
- 只有发生中断续跑、merge 冲突后重试或 `landed/docs_pending` 文档恢复时，AI 才读取 `/pmai-build-close` 兼容入口；正常协作和 PM 定稿后都不要求 PM 手动调用。
- 使用外部构建工具前，PM 已确认的工作环境必须 clean；失败默认保留半成品，禁止自动 restore/clean，换工具需重新确认。

### Review 工具

AI 可以推荐 review / QA / design-review 工具，但不替 PM 假执行。PM 主动调用 review 类工具时，AI 按当前模块和改动对象推断评审目标；推断失败只问一个澄清问题。

### gstack 旁路文档接回

PM 或 AI 调用 gstack `/document-generate` / `/document-release` 后，先判断文档类型，再接回 PMAI 文档地图：

- 工程文档（README/API/CLI/架构说明/how-to/tutorial/reference）→ 落 `docs/engineering/`，同步更新 `docs/engineering/INDEX.md`，回执接回路径。
- 产品介绍 / 功能清单 / 优势说明 / 一页纸 / 汇报材料 → 不用 gstack 旁路承接，转 `/pmai-doc-writing`。
- Product Proposal → 不用 gstack 旁路承接，转 `/pmai-proposal`。
- PRD / 功能需求 / 功能描述 / 功能规格 / 功能评审稿 / 模块规格 → 不用 gstack 旁路承接，转 `/pmai-spec-writing` 或 `/pmai-design`。

只引用 `~/.gstack/...`、浏览器下载目录或临时路径不算 PMAI 已接收；采用后的文件必须落进本仓并补索引。

### Subagent 使用边界

Subagent 适合一次性读文件、第二视角评审、独立查询；不适合长期协调、跨 turn 等待、替代 skill 主流程。任何会启动后台长跑执行器的动作，都由驱动 AI 负责收口。

### 文档位置

| 文档 | 路径 | 说明 |
|---|---|---|
| 产品基线 | `PRODUCT.md` | 当前 Proposal、产品定位、核心问题与价值、用户、边界、MVP Case、业务术语表 |
| Product Proposal | `docs/proposals/` | 产品级完整论证、当前版本与历史取代关系 |
| 产品现状 | `PRODUCT-STATE.md` | 当前产品长什么样、做到哪、哪些真哪些 mock |
| 视觉规范 | `DESIGN.md` | 颜色、字体、组件、交互规范 |
| 跨模块规则 | `PRODUCT-RULES.md` | 全项目产品行为规则 |
| 文档索引 | `docs/INDEX.md` | 消费仓文档入口，说明各类材料去哪找 |
| 模块索引 | `docs/modules/INDEX.md` | 模块上下文与功能型规格文档索引 |
| 模块三件套 | `docs/modules/<模块>/discussion.md` / `decisions.md` / `spec.md` | 讨论、决策、规格 |
| 功能型规格文档 | `docs/modules/<按内容命名>.md` | PRD、功能需求、功能描述、功能规格、功能评审稿 |
| 项目决策档案 | `docs/decisions/` | 重大项目级决策 / 理路冻结档，默认不写 |
| 输入材料 | `docs/inputs/<类别>/` | PM 上传 / 调研 / 竞品 / 旧文档等材料；当前模块引用记录在模块 `.work-meta.json` |
| 工程文档 | `docs/engineering/` | README、API、CLI、架构说明、how-to、tutorial、reference；旁路接回后登记 `INDEX.md` |
| 探索变体 | `mockups/` | 探索期 mock，看版与退役记录 |
| 待办池 | `TODO.md` | PM 真说过想做但未开工的事项 |
| 介绍型材料 | `docs/deliverables/` | 产品介绍、产品功能清单、产品优势说明、一页纸等，默认 Markdown |

## 项目背景

一个用于验证产品经理确认发布前变更的内部工作台，先证明单条变更从提出到确认的完整流程。

## 项目建造定义

初始化不提前决定项目类型、技术栈或代码目录。全新项目先由 `/pmai-proposal`
完成产品级澄清；首个可建造需求再在 `/pmai-design`
定稿后生成 `.pm-workflow/project.yml`，其中记录 `prototype / product`、技术栈、
代码入口和真实运行命令；`/pmai-build` 只读取该文件，不临时猜测。

## 文档治理（读取策略）

**文档入口分两层**：

- **必读核心** = `PRODUCT-STATE.md`：进项目就读，是当前产品现状 hub。
- **文档索引** = `docs/INDEX.md`：要找 Product Proposal、模块、功能型规格文档、输入材料、项目决策档案、介绍型材料时先看这里。

新建任何文档前，对照 `$PMAI_HOME/templates/文档地图.md` 判断归位。

## 根目录与 docs/ 归位约定

✅ 仓库根目录放 PM 和 AI 每次进项目都要认的项目脊柱：

- `AGENTS.md`
- `CLAUDE.md`
- `PRODUCT.md`
- `PRODUCT-STATE.md`
- `DESIGN.md`
- `PRODUCT-RULES.md`
- `TODO.md`

✅ 顶层 `docs/` 只放资料索引和会增长的文档集合：

- `INDEX.md`
- `modules/`
- `proposals/`
- `decisions/`
- `inputs/`
- `engineering/`
- `deliverables/`
- `archive/`

❌ 不在顶层：

| 文件类型 | 归位 |
|---|---|
| 产品定位 / 现状 / 规则 / 视觉 / 待办主文件 | 仓库根目录 |
| 模块级讨论 / 决策 / 规格 | `docs/modules/<模块>/` |
| Product Proposal 当前版与历史版本 | `docs/proposals/<slug>-vN.md`，索引在 `docs/proposals/INDEX.md` |
| PRD / 功能需求 / 功能描述 / 功能规格 / 功能评审稿 | `docs/modules/<按内容命名>.md` |
| 一次性 review / 临时分析 / scratch | `docs/archive/` |
| PM 上传材料 / 调研材料 | `docs/inputs/<类别>/` |
| README / API / CLI / 架构说明 / how-to / tutorial / reference | `docs/engineering/` |
| 产品介绍 / 功能清单 / 优势说明 / 一页纸 | `docs/deliverables/` |
| 项目级理路冻结档 | `docs/decisions/<日期>-<slug>.md` |
| 探索期 mock 变体 | `mockups/` |

写新文档前 AI 自问 3 题：

1. 这是长期真相源、过程档案、输入材料，还是按需产物？
2. 读者下次会从哪个入口找它？
3. 如果放顶层 `docs/`，是否会和根目录项目脊柱竞争真相源？
