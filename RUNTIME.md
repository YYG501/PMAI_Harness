# RUNTIME

> 当前运行状态真相源。历史迁移流水账看 git history / `CHANGELOG.md` / `docs/归档/`，本文件只保留当前有效模型。

## 当前位置

- 日期：2026-08-23
- 开发分支：`main`
- 当前目标：Harness P1 与复杂度收口五个批次已经完成并分发到 `main`。本 checkout 已把固定版本的 `mattpocock/skills` Grill 方法落为 Design 访谈内核：以 design tree / frontier rounds 深挖模块未知项，同轮询问互不依赖的问题，依赖问题延后，事实由 Agent 调查；每题仍独立绑定 PM 答复与 D 编号，frontier 清空后必须取得并绑定 shared-understanding 收据。Proposal、三件套、context pack、spec-writing、ready / build 与 Lark 生命周期继续由 PMAI 自己负责，不引入第二套主链。
- gstack 参考基线：`v1.58.5.0`，commit `11de390`；只参考本地 `gstack-clean` checkout，没有升级用户目录中的安装副本。

## 当前活跃模型

- 正常用户主链路：`/pmai-init-project` 只建上下文骨架 → `/pmai-proposal` 完成产品级澄清 → `/pmai-design` 收敛模块决定并在首次定稿时生成项目建造定义 → `/pmai-spec-writing` 编译已确认规格 → `/pmai-build` → PM 看结果多轮快速修改 → PM 明确定稿 → `finalize-work.py` 对冻结 commit 只执行缺失的代码门、范围门和受影响体验批次 → 合入 main → 只更新实际受影响的产品真相源。spec-writing 通常由 design 自动调用，不要求 PM 手工拼接命令。
- `/pmai-design` 的提问推进采用 vendored `mattpocock/skills` Grill 快照：后台建立决定依赖树，每轮展示当前全部 frontier 问题并逐题给推荐；一条用户消息可以显式回答同轮多题，但不能跨 round、跨模块或替后置问题授权。frontier 清空后先向 PM 复述共识并取得独立 shared-understanding 确认，确认前不能写最终 `spec.md` 或进入 `ready_to_build`。这只替换 Design 的访谈内核，不替换 Proposal、文档、授权和 Build 生命周期。
- 新项目默认必须完成完整 Product Proposal；成熟项目只有在定位、用户、核心问题与价值、产品边界、MVP / 当前产品结果已经构成完整等价基线，且 `PRODUCT.md` 显式记录真实仓内依据与 PM 确认日期、`PRODUCT.md` 与依据文件均已提交且无漂移、机器状态为 `equivalent_baseline` 时才可跳过。一旦进入 Proposal 就必须完整产出；当前版本通过 `docs/proposals/`、`PRODUCT.md` 与 `.pm-workflow/proposal.json` 原子绑定，下游只读消费。
- `meta`、`mockup` 是 design 按需调用后返回主线的内部能力；spec-writing 是主链中的规格编译阶段，也通常由 design 自动调用。三者仍保留手动入口用于专项使用。
- UI 工作始终先读消费仓 `DESIGN.md`；它继续拥有产品体验、采用范围和共享组件 inventory。消费仓可在其中声明唯一、Git 跟踪的项目级设计系统 Skill：宿主能原生解析时调用，不能解析时完整读取同一仓内 `SKILL.md` 及 required references；未声明时沿用现有组件流程，声明缺失或不可访问时失败关闭。该插槽不新增设计系统安装器、版本管理器或平行生命周期。
- `/pmai-feedback` 是消费仓到框架仓的只读反馈出口：先固定当前原始会话快照，默认围绕 PM 当前反馈聚焦对账，只有证据冲突、不可逆风险、跨阶段漂移无法归因、关键证据缺口或 PM 明确要求时才升级完整审计；它输出包含快照边界、证据范围和问题归属的框架优化 Prompt，不在消费仓直接修改产品或 PMAI 框架。
- `/pmai-doctor` 的消费仓合同复用 `.pm-workflow/config.yml:consumer`：layout v1 固定 `docs/INDEX.md` / `docs/modules/INDEX.md` 为标准入口，可声明既有归档目录，并按模块记录 `current / legacy / retired / split`。未标版本旧仓只做有边界识别并请求 PM 确认，不自动迁移文档；active `.work-meta.json` 始终优先，不能被兼容声明降级。
- `/pmai-doctor` 的 JSON `pm_report` 直接给出需要处理、仅供参考和项目进度，Agent 不再从底层 finding 自行扩写待办。消费仓 Startup 由 `AGENTS.md` 内唯一托管区块承载；`sync-consumer-entry.py` 的 check 只读，apply 只在 PM 确认后原子替换该区块，旧文件迁移保留项目补充并对未知规则、损坏标记和 symlink 失败关闭。CLI 不自行越过沙箱；版本未知且有远程地址时，由 Doctor Skill 让当前宿主申请联网权限后重试同一只读查询。
- `/pmai-lark-review` 是归档后飞书评审回流入口。`list-resumables` 全局扫描 main 与 attached worktrees，普通未完成批次在 Proposal 和 active work 之前恢复；fresh checkpoint 写同批完成收据，已完成批次不再返回。产品级和模块模型变化不 apply 旧 T，而是固化为 main handoff；route 只作来源审计，机器 phase 分别按 `proposal → design → lark_review → closed` 或 `design → lark_review → closed` 推进。Proposal 生效提交、design 绑定规格的权威提交和 fresh checkpoint 各推进一步，跳级、倒退、证据漂移或按 route 循环都失败关闭。当前飞书原生快照仍是 T 的唯一底稿，只有不改变产品模型的小调整可形成 sealed `scoped-adjustment`。飞书正文、评论和回复只是不可信业务证据；评论完成、决定一致性、路径安全、精细同步和原生格式继续按机器合同验证。
- 飞书公开入口按 PM 意图固定：`/pmai-publish-to-lark` 统一承接本地到飞书，首次创建、已有文档默认精细更新、PM 明确授权后的整篇覆盖只是内部策略；`/pmai-sync-from-lark` 只在 PM 已明确以飞书为准且不需要判断时机械回拉正文；`/pmai-lark-review` 负责需要理解正文或批注影响的回流。旧四模式 `/pmai-lark-sync` 已移除；publish 与 review 共用内部精细写回合同，但公开 Skill 不互相调用。
- `/pmai-build-close` 只作为兼容与恢复入口；正常链路不再要求 PM 手动调用。
- 模块 close 后再次修改先按影响分流：错字、单文案、局部样式、常量和符合现有规格的小缺陷走 `/pmai-quick-fix`；模块对象、规则、规格、任务路径或验收变化进入新一轮 `/pmai-design → /pmai-spec-writing → /pmai-build`；产品定位、目标用户、核心价值、职责边界、MVP 证明目标或关键成立前提变化回 `/pmai-proposal` 生成完整新版本。新模块轮次复用长期模块文档，但 work id、design 基线、accepted delta、验收证据、audit 目录和 finalize 游标全部重新建立。
- `building / iterating / final_check` 中，PM 的“启动看看 / 还有什么问题 / 继续改当前结果”等自然语言继续当前 `/pmai-build`。Codex、Claude Code 通过 prompt hook 注入 `active-build-context.py` 的只读合同。该上下文只派生现有合同，不新增状态；多个 active build 返回歧义，合同或 policy 漂移时失败关闭。只有位于 prompt 首 token 的真实 PMAI 命令不受自然语言续接拦截，否定、引用、行内代码、代码块和文档示例都不能绕过；Git / build context 超时、非零、空输出、坏 JSON、未知状态或 stdin 超时一律在宿主超时前注入不可用护栏，不能降级成“没有 active build”。旧 Kimi managed hook 若尚未清理，分发器仍保持相同失败关闭语义，但这不构成当前主控承诺。
- canonical lifecycle：`designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`。旧 `stage` 仅由 normalization 边界投影为兼容展示，新写不再生成。
- 项目建造定义：初始化时不存在；首个达到 `ready_to_build` 的 design 将 `prototype / product`、技术栈、代码入口、真实命令和 Web 能力写入 `.pm-workflow/project.yml`。后续 build 只读该文件。
- 产品方向真相源：当前 `docs/proposals/<slug>-vN.md` 保存完整产品级判断，`PRODUCT.md` 保存同步后的精简基线，`.pm-workflow/proposal.json` 绑定当前版本与正文 hash；已确认 Proposal 不允许下游原地修改。
- 模块真相源：`docs/modules/<模块>/discussion.md`、`decisions.md`、`spec.md`；跨模块现行规则为 `PRODUCT-RULES.md`，项目级冻结理路为 `docs/decisions/`。
- 文档语义：Proposal 定义产品级用户、问题、价值、边界与 MVP；`spec.md` / PRD 是指导研发实现的最终目标合同；`PRODUCT-STATE.md` 描述 main 已落地现状；原型、mockup 和代码只作设计 / 实现证据。
- design 的 `ready_to_build` 状态同时记录 approved source hash、hash scope version、design checkpoint 和精确目标路径；build 开工前重新编译上下文并验证 currentness，过期依据不能继续显示或进入构建。当前 Proposal 与固定交接摘要参与 context pack 和 source hash；Proposal 换版会让旧 ready/build 依据失效。新轮次使用 `source_hash_version=2`：模块三件套、输入证据、PRODUCT、PRODUCT-RULES、DESIGN、项目级决定和 project.yml 参与 currentness；PRODUCT-STATE、TODO 和模块索引只作上下文，单独变化不判设计过期。没有版本字段的旧 ready/build 按 v1 全量范围恢复到该轮结束，显式返回 design 后下一次批准才升级 v2。新 `.work-meta.json:build` 使用合同 v5：保留 v4 的双车道验收语义，但 lifecycle 和 checks 都只写一个 canonical 位置；旧 v1-v4 继续用于中断恢复兼容。
- 产品模型决定另由同一 `.work-meta.json:decision_gates` 保存授权收据，不新增决定文件或生命周期：默认 sequential 问题仍一次只保留一个 pending gate；Design frontier round 可同时保留同一 `round_id` 的多个独立问题，同一用户消息由 Agent 逐题声明回答范围，每题分别 consume 到 D 编号。frontier 清空后的 shared-understanding 作为不产生 D 编号的独立收据，由最终 `spec.md` 写入门、staged 检查和 ready checkpoint 复核；后来新开的 frontier 会使旧确认失效。摘要不能迁移 gate 状态。旧、未开工 ready 缺收据时返回 `authorization_unverifiable` 并退回 Design；已进入 build 的旧工作不倒灌新收据。
- 新 build 由 AI 在一张卡中展示推荐的工作环境、构建工具和两项的全部有效选择，PM 只确认这两项；外部工具候选排除当前主控对应的 profile，“当前会话直接构建”始终可选，没有可用外部工具时默认推荐它。项目类型和验收方案不显示。选择当前环境时，main 只放行合同声明的目标路径。
- 宿主面分为两级：Claude Code 使用 `/pmai-*`、Codex 使用原生 `$pmai-*`，两者保留完整 Skill、项目 Hook、lifecycle、恢复、证据和 landing 主控能力；Kimi Code、OpenCode、Cursor Agent 只由 `/pmai-build` 选作外部 Builder。Builder prompt 明确禁止调用 PMAI Skill、推进 lifecycle、写验收通过或处理 landing；主控重新采集 Git diff、检查路径并决定后续状态。新 install / upgrade / init 不再生成 Kimi Skill/managed hooks 或 OpenCode commands/config；Doctor 只报告遗留资产并保留显式清理入口。
- 记忆分两层：项目事实、决定和偏好继续由消费仓现有真相源承担；个人经验保存在用户级状态目录，跨项目召回但只作建议。个人经验不进入 context pack、项目 hash 或 Git，也不能自动修改 Skill。

## 已实现

- Design Grill 适配已落到固定上游快照、方法文档和机器授权链：vendored `mattpocock/skills` 的 `grilling / grill-me / grill-with-docs / domain-modeling / prototype` 与 MIT 授权；`/pmai-design` 按 design tree 计算 frontier，同轮展示互不依赖的问题并把事实调查留给 Agent。`decision-gate.py` 新增 `open-round / answer-round` 和 `open-shared / confirm-shared / consume-shared`；同轮多题共享用户消息但独立保存选项或自由回答、D 编号和消费记录，部分答复继续阻断，旧共识不能覆盖后来 frontier，最终共识绑定 design checkpoint。Proposal 和其它阶段路由保持 sequential，PMAI 的三件套、spec-writing、ready / build 与 Lark 合同保持原边界。
- 复杂度收口批次二统一了仓库身份和宿主等级：`repo-kind.py` / `_lib/repo_identity.py` 唯一输出 `generator / consumer / uninitialized`，严格生成器 marker、防越界 symlink，普通 `docs/` 不会误判；preamble、status、Doctor 和 Kimi 遗留 dispatcher 复用该解析器，`PMAI_PROJECT_INITIALIZED` 只作兼容投影。install / upgrade 只管理 Claude/Codex Skill，init 只生成 Claude/Codex 项目配置；Doctor 将 Kimi/OpenCode 拆成 Builder readiness 与非阻断遗留报告，不 repair 旧主控资产。五个外部 adapter 统一注入 Builder-only 合同；新模板和生成器入口只承诺 Claude/Codex 完整主控。
- Harness 第一阶段五项 P1 已下沉为运行时硬门：host `_shared` 只按明确所有权替换；brownfield 初始化写入前列全同名冲突；attached build worktree 的所属分支副本压住 main 旧状态；build 必须消费 current `ready_to_build + project.yml` 且拒绝路径、类型、入口和 revision 漂移；cancel 要求 main 干净、只提交状态删除，并在提交失败时恢复原状态。
- Harness 验证入口已失败关闭：每个 suite 有独立进程组超时，缺失 / 重复摘要、零用例、摘要与退出码矛盾都会计为失败；写入 hook 无法解析输入、定位唯一路径、确认 Git 工作区或分支时拒绝写入。普通回归实际运行静态 skill eval 并明确显示 session skip；稳定版本发布门要求真实 runner 与独立 judge，以 evaluation ID、来源和完整证据复核绑定每次 session，缺能力、skip、自报通过或 judge 复用 runner run ID 都阻断发布。
- 新增 `skills/_shared/project-design-system.md`：design、mockup、build、quick-fix、mirror-site 共用同一跨宿主委托合同；build 给外部执行器的输入固定携带完整 `DESIGN.md`、设计系统名称、采用范围、Skill 名称和仓内路径。消费仓 Startup 托管区块携带相同规则，入口迁移器识别该职责并继续对未知旧 PMAI 规则失败关闭。
- 初始化与 CI 不再借用开发机隐含环境：`init-project.sh` 在写目标目录前预检 Git author / committer 身份，初始 commit 失败保留 Git 原始错误和恢复命令；GitHub Actions 显式配置测试身份，负向内容断言只依赖系统自带 `grep`，runner 缺少 `rg` 不会假绿。
- 生命周期恢复已补齐：`ready_to_build` 正向进入 `building`；landing 状态、计时、暂存或主线 commit 失败时 abort 半合并态并保留隔离环境；legacy close commit 失败恢复 `.work-meta.json`。cancel / land 先持久化 prepared 清理意图，主线状态提交后只激活队列，不在落地进程内直接删除 worktree / branch；中断后 cleanup 以 Git 真相自动恢复。每项记录固定自己的 `refs/heads/main` 或 `refs/heads/master`，landed 激活和 active 删除都用入队时的 branch OID 重新验证该主线，分支名改向、主线 reset 或 main/master 并存不能误删；最终分支删除使用 old-OID `git update-ref` CAS。待清理队列加进程锁并原子更新，损坏时失败关闭，事务 stage 不占用 `.pending-*` 中断标记命名空间；main/master preamble 均可消费，status 与会话 startup 使用只读 preamble。cleanup 只让 Git 删除已确认没有 tracked、untracked、ignored 内容且无人占用的注册 worktree，Git 拒绝时保留现场，不再用文件系统递归强删。
- 新增 `context-pack.py`：design、build、恢复、最终检查和文档更新共用确定性上下文，并区分 active / superseded / 冲突决定、未决问题和输入 hash；项目定义存在时只从其中的 entrypoints 取实现上下文。
- 新增共用 `decision-policy`：机械项自动处理，可逆偏好给推荐并推进，产品模型岔路和 one-way door 立即让 PM 拍板；问句和讨论草稿不得成为决定。
- `_lib/work_contract.py` 已成为唯一工作合同读取边界；`build-contract.py` 新 build 使用合同 v5。`validate-final-currentness` 重新校验 design hash、accepted deltas、批准路径和 project.yml；真实 Git implementation commit 在每轮 `commit` 时立即阻断批准范围外路径。`request-finalization` 仍是 final evidence 和 `review-ready` 硬门；PM 新反馈用 `resume-iteration` 回快速车道。prototype 继续固化不可 exception 的 `prototype-boundary`。
- 每次新建模块工作都会生成唯一 `work-<模块>-<时间>-<随机值>` id，并把 `build.audit_dir` 固定为包含该 id 的目录；finalize、landing、文档影响地图和失败恢复只使用该轮目录。旧 `work-<模块>` 合同继续回退模块级 audit 目录。final currentness 分别校验初始 design hash 和按顺序串联后的 accepted-delta 最终 hash，不再在 delta 链验证前把两者误判为冲突。
- prototype / product 验收 profile schema v3 同时编译 `iteration_checks / final_checks`，不再输出 `required_checks` 别名。新 Web build 只生成一个不可 exception 的 `browser-acceptance`，一次持续浏览器 chain 覆盖受影响流程的 smoke、visual、behavior；旧 v1-v4 合同运行时按实际旧检查名从同一 batch 派生证据并绑定同一摘要，不升级合同版本，coverage 仍单独证明。
- `final-validation.py` 对候选绑定的 implementation commit 创建 detached validation worktree，统一在 `implementation.root` 运行命令；新 project definition 机械拒绝 commands/web.start 重复选择 root，legacy recovery 只精确移除一次重复前缀并在 artifact 留痕。命令按项保存 exit code/log，test/typecheck 失败仍继续 build；只有前两项可由 PM 绑定当前 artifact 接受为 limited，production build 保持硬门。
- `finalize-work.py` 按 v4+ lifecycle 只补缺失机械项，并用 candidate binding、commit/source hash 和 audit 游标从语义检查、`final_check / landed / documenting` 准确续跑；统一 coverage helper 要求 checks-spec 机器 P0/P1 为零并逐项确认声明状态。runner 只提交当前模块状态和 audit 目录，合入后输出 main 模块恢复位置；prototype boundary、迁移和安全等其它语义判断不伪装成自动通过。
- 复杂度收口批次四已完成：`build-contract.py` 的 schema、transition、evidence 和可选 review adapter 已按职责拆到 `_lib`；核心 Build CLI 不直接依赖 Lark，Lark 只由 `review_evidence.py` 适配；原子写入实现明确遵守 ADR-004 威胁模型。`finalize-candidate.py` 现按批准目标树、已记录实现和 legacy recovery checkpoint 绑定 source/base commit、目标树摘要、source hash、明确来源与防篡改 digest，再启动可恢复 runner；后续无关 HEAD 不会替换批准目标相同的候选，也不要求人工修改 baseline。
- 复杂度收口批次五已实现：`skills/_shared/loop-contract.md` 统一 Proposal、Design、Build 每轮的恢复、目标、边界、最小动作、验证和路由顺序，并定义七种非持久动作；三条主链分别映射业务输入、允许动作、验证、重试、上游升级和完成出口，`build-close` 只执行 checkpoint 恢复。18 个固定消费仓场景锁定阶段、动作、去向和恢复规则；这些是确定性合同夹具，不是 Session Eval 或效果成功率证据。
- `build-timing.py` 自动记录 currentness、final-validation、browser-acceptance、semantic-validation、landing、documentation；统一 runner 完成前校验适用阶段都有 pass 且没有 running。真实 build/browser 缺陷、PM 新反馈、merge 冲突、未跟踪路径碰撞和文档碰撞把旧尝试标为 `exited` 或启动新尝试，不显示成 10 分钟成功。
- 新增 `prototype-boundary.py`：从 baseline 到候选实现扫描批准范围外改动、数据库 migration、生产基础设施、密钥配置、真实鉴权和外部副作用信号；静态信号无缺口后仍要求 AI 明确完成语义复核，artifact 才能写 `pass`。
- 新增 `project-definition.py` 和严格 schema validator；路径、类型、技术栈、Web 运行配置与 revision 变更全部 fail-closed。
- `project-type.py` 保留为兼容包装器：优先读新 `project.yml`，再读旧 config 和旧 `auto-detected: system` marker。
- 初始化脚本不再接收 project type，不创建代码、prototype、mockup 看板、dev server 或 gstack 依赖。
- 新增 `/pmai-proposal` 与 `proposal-contract.py`：新项目初始化后通过 required marker 强制进入完整 Proposal；当前版本固定在 `docs/proposals/`，机器合同校验路径、正文 hash、`PRODUCT.md` 同步、固定下游交接和显式 supersede 关系。context pack 编译当前 Proposal 与结构化 handoff；status 和 consumer doctor 区分 required / invalid / accepted。
- spec-writing 已重构为“通用内容模块 + 可叠加 Profile + 文档 Preset”：企业平台与 AI Product Profile 可独立或同时加载，不维护重复的企业 AI 平台 Profile；完整 PRD 使用唯一 Preset，4 列表只作复杂后台的可选动作索引。
- 已删除 `/pmai-direction`。产品方向纠正统一进入 Proposal；`/pmai-record` 只在没有 active work 且 Proposal 状态为 `accepted / equivalent_baseline` 时补录已经确认的待办、术语、跨模块规则、项目理路或有 main 证据的现状纠错，不得写 Proposal、模块三件套、构建状态或实现。
- 固定 build 审计编排和 coverage reviewer 已退出活跃链路；v5 只认 adaptive iteration/final checks 与对应 evidence，v1-v4 由兼容层恢复。
- Web final checks 必须有 active browser-acceptance；旧合同仍要求 active browser-smoke。gstack 可由其它可验证 browser 适配器替代，不能 exception 掉浏览器能力。
- builder profile 按项目定义、配置、本机可用性和当前主控推荐；Claude Code、Codex、Kimi Code、Cursor Agent、OpenCode 都可作为外部执行器，当前主控对应的同名工具不进入候选，但当前会话直接构建始终可选；旧消费仓缺少 `kimi-code` profile 时由 `builder-profile.py` 运行时补齐，不改写项目配置；Gemini CLI 已退出构建工具面。验收 profile 仍后台生成，不进入开工卡。
- 自动 landing 在 merge 前检查 incoming path 与 main 未跟踪文件交集；merge 冲突保留 `final_check`，文档失败保留 `landed/docs_pending`，续跑不重复 merge。清理失败或其它会话仍以待清理 worktree 为 cwd 时保留队列，后续从 main 自动重试。
- 文档影响地图只在 landed 后生成：schema v2 绑定 work/module、implementation/landed commit、base/head、source hash、accepted deltas 与 candidate tree/binding digest；每次文档恢复先 `ensure-current`，旧 schema 或任一绑定漂移时原子重建，不能因文件存在就复用。默认更新 PRODUCT-STATE，accepted delta 才加入 spec、decisions 和明确受影响真相源；landed diff 已改文档自动 covered，未受影响文档不进入清单。业务术语和角色只从 build 规格锚点、landed 的模块 / 功能型规格、明确定名决定和 `kind=term/role` 的 accepted delta 对账；讨论稿、索引、引号、加粗、问句和代码不参与猜词。term detector 与 context pack 共用状态问句识别，无问号的“当前决定是否被取代”也不能成为决定或术语来源；“被取代时的迁移”等条件、时序和属性描述不改变决定状态。术语表支持有或无前导竖线，但遇 heading、list、quote、fence 或缩进代码立即结束。已取代旧决定的新决定仍参与当前术语提取，重复 cue 采用线性扫描；detector 已确认仍缺失的术语不会因 PRODUCT.md 恰有其它 landed 改动而自动 covered。
- spec-writing landed 对账固定分为符合、accepted delta、漏实现、无依据实现；只有 accepted delta 修改规格目标，漏实现保留为实现缺口。
- design / spec-writing 现在按“产品决定是否闭合”分流：对象、规则、信息结构、任务路径、权限或关键交互仍未定时由 design 讨论；只有已确认内容的整理、补差和改写进 spec-writing。
- Claude/Codex 的宿主入口暴露由 `scripts/_lib/skill-links.sh::pmai_skill_is_host_exposed` 统一判断。`build-close` 不进入正常主路径但保留兼容恢复入口；`publish-to-lark`、`sync-from-lark` 和 `lark-review` 作为方向与判断责任明确的飞书专项能力继续在两个完整主控注册；meta、mockup、spec-writing 默认由 design 调用，同时保留独立专项意图的可发现入口。upgrader 在升级、降级和回滚前清空当前 Bash 进程的旧策略函数，再加载目标版本；即使降级到旧策略，也只重建 Claude/Codex 入口，不重新激活 Kimi/OpenCode 主控面。
- brownfield 接入只把代码盘点写入 `CODEBASE-AUDIT.md` 和首次 `PRODUCT-STATE.md` 现状；不从代码生成目标 `spec.md`，不再把已退役的 coverage reviewer、固定视觉门或“补 8 段基线”当作 build 前置。
- design、meta、mockup、spec-writing、build、build-close 与消费仓 AGENTS / CLAUDE 模板已按统一链路重构。
- 新增 `evals/cases/*.json`、`evals/touchfiles.json` 和 `scripts/skill-eval.py`；静态案例可作为提交门，session runner / LLM judge 缺失时明确 skip，require 模式明确 fail。
- Codex 只暴露 `~/.codex/skills/pmai-*` 原生 skills；不再生成会在 Desktop 显示为 `prompts:pmai-*` 的 custom prompts。install / upgrade 清理旧 prompt 文件，doctor / status 不再生成或检查它们。OpenCode commands 不再创建或刷新，遗留文件只诊断、显式清理。
- Kimi Code 不再暴露 PMAI Skill 或安装 managed hooks。遗留用户级分发器仍按进程 cwd 先路由、统一三态识别，并在 PMAI 仓对坏 JSON、超限输入、payload 跨根、Python/Node/可信 hook 缺失或非零退出保持失败关闭；普通仓读取 stdin 前 no-op。该代码只保护尚未清理的历史安装，不提供 Kimi 主控能力；Doctor 不 repair，uninstall 只删除 PMAI 托管资产。
- Claude Code / Codex 项目 hooks 由 `install-project-hooks.sh` 统一管理：`--check` 只读比较当前消费仓配置，刷新时只精确替换 PMAI 自有命令并保留其它宿主设置和自定义 hook；命令通过 `${PMAI_HOME:-$HOME/.pmai}` 在宿主运行时解析，自定义安装根不会退回错误的默认路径。安装器预渲染全部 Host 后事务写入，用唯一备份逐次校验内容、权限和 symlink 指向；失败回滚不覆盖通过正式路径提交的并发编辑，并兼容 Bash 3.2。协作锁只串行遵守合同的 PMAI writer：事务子进程必须继承与锁路径相同 device / inode 且实际持有排他锁的 fd，可伪造环境布尔值或无关 fd 不能授权写入；同一 OS 用户的非合作进程仍不在该合同内。目录 fd 在 claim 后发现父目录改向时，会在固定旧目录内按 inode 补偿恢复正式名再失败关闭，不把原件留在隔离名。该 CAS 只保护路径命名空间；其它进程若持有旧文件描述符并在 claim 后继续写入，需要共享写锁或版本保留。全局 upgrade 不静默改写消费仓；`/pmai-doctor` 调用目标 `PMAI_HOME` 的 doctor，默认只读检查框架、宿主入口和当前消费仓，跨版本目标 doctor 缺失或不可执行时失败关闭；全局修复只有 `--repair` 才获取安装锁并写入，消费仓 hooks 刷新仍需 PM 单独确认。CLI 只保留 `pmai doctor --check` 作为健康检查，不再提供 `pmai status`。旧 `install-codex-hooks.sh` 保留为 Codex-only 兼容包装。
- design 直接必读 AskUser 共享规则，首题前收敛真实决策并报告总量，用业务结果提问；跨日、模型切换或会话恢复时重读当前 skill 与必读规则。context pack 消费后单独召回个人经验候选，按适用性、去重和独立检查价值自适应选择，不设正常条数上限；高信号纠偏闭合后自动归位。项目事实回项目真相源，跨项目经验进入用户级存储，已有 Skill 规则未执行只留执行失败证据。跨模块设计只留下一个明确 build 入口，相同建造方案重复写入 `project.yml` 保持完整文件不变。
- decision gate 授权链已实现：`decision-gate.py` 与共享 library 管理展示题、用户答复候选、answer/consume/cancel 和 checkpoint；Claude/Codex 项目 hook 在 UserPromptSubmit 捕获答复、在权威决定写入和 commit 前阻断越权；Git pre-commit 与 ready 独立按变化 D 编号复核，context pack 编译可恢复摘要。确定性回归覆盖旧答复已消费、摘要建议题未展示、跨 gate 复用、缺收据 staged/ready 和旧 ready 退回；Session Eval 新增 `design-answer-binding-after-compaction`。
- context pack 对旧消费仓自动写入 Git 本地 exclude，不再制造未跟踪缓存；build 在创建环境前阻断批准目标路径上的既有脏改动，同时保留无关 WIP。
- `context-pack.py` 与 `check-open-questions.py` 共用明确无未决问题的声明识别；只有单独一行的肯定声明才表示空问题集，否定、转述、但书、多行后续问题和子串命中都不能放行。空 section、普通说明、空题名、HTML comment-only 以及 `待确认` / `TODO` / `TBD` / `FIXME` 等占位回答仍保持 unresolved。
- context pack 只把 D 编号模块决定和真实产品规则编入 active；共同理由、否过方案、待复核、变更记录与注释模板不再伪装成决定。标题或正文仍是问句、尚在讨论且没有明确结论时保持 rejected；明确状态或结论可以闭合问题标题，带“尚未正式 / 并未真正”等副词的否定状态保持 active。
- 新增 `scripts/current-session.py` 和 `/pmai-feedback`：Codex 通过 `CODEX_THREAD_ID` 精确定位 active / archived 原始 JSONL，校验会话唯一性、session ID 与 cwd 归属，并固定不会随 active 尾部增长的行 / 字节快照边界；Skill 默认聚焦 PM 当前反馈，必要时才升级完整快照审计，区分消费仓产品问题、执行偏差、Skill 缺口、框架合同缺口、宿主限制和证据不足，最后生成带消费仓路径、会话 ID、原始文件路径、快照及证据范围的框架交接 Prompt。公开 `/pmai-skill-improve` 已移除，历史资料统一保存在 `docs/归档/完成/skill-feedback/`。
- `scripts/lark-review.py` 和 `/pmai-lark-review` 已升级到原生远端底稿合同：`resolve-target` 将文档身份绑定到唯一规格与真实 active worktree；采集同一 revision 的 Markdown / full XML、历史发布版和完整分页评论，`remote-native.json` 保留 block/style/resource/reference，remote-coverage schema v2 同时绑定语义与原生结构。产品级和 active 模块模型变化可将旧批转为不可 apply 的 `handed_off`，必要证据复制到 main `.runs/lark-review-handoffs/`；`list-handoffs` 可按 route、模块和文档枚举，fresh batch checkpoint 用 `--closes-handoff` 收口。`verify-sync` 同时比较文本和结构投影，以原生 block / token 判断资源身份；collect 在联网前绑定 canonical Git 仓根。新 ready plan / resolution 使用 v4，comment-actions 使用 v3，remote-verification 使用 v2；reply-only、PM 手工解决回读、`superseded` 评论处置和跨决定一致性回执只进入新 v4 批次。已有 v3 ready 批次继续按原合同恢复；旧 remote-verification v1 必须重跑验收，保留仓根绑定的旧 review/plan v2 与 comment-actions v1 批次仍可完成评论恢复。
- 飞书 frontmatter 回写改为补丁指定顶层标量、保留嵌套 YAML / 注释 / 正文并原子替换；最终正文、checkpoint 和 baseline 写入使用逐级 `O_NOFOLLOW` 的固定目录 fd，父目录 symlink 重绑不能改变落点。普通 Path API 先 canonicalize 父目录以接受 `/var` 等合法系统别名，最终文件名仍拒绝 symlink；跨远端阶段继续显式要求 canonical path。create / update / fetch / comments / api 的 JSON 对象统一拒绝 `ok:false`、`success:false` 和非零 `code`；已经发起 overwrite 后的非零、空输出、非 JSON、非对象、失败 envelope 或非完整 result 都归为 `incomplete_update` 并清除旧发布基线，调用前 validation / missing-cli 不清，使用受控 stdin 的错误也不回显正文。发布后只有文档身份、写操作返回 revision、回读 revision 一致且本地发送源未变化时才建立新基线，避免绑定错文档、旧 revision 或 claim 前通过正式路径提交的本地并发版本；持有旧文件描述符的 writer 仍需共享写锁或版本保留。

## 兼容与边界

- 合同 v1 继续可读；已有消费仓不批量重写，下次 design 定稿时生成 `project.yml`。
- build contract 当前为 v5，project.yml schema 仍为 v1；新 build 只在 build 内写 lifecycle，只写 `final_checks`，不再生成旧 `stage`、顶层 build lifecycle 或 `required_checks`。旧 v1-v4 由统一 normalization 与 runtime adapter 兼容，不批量重写合同或 project.yml；既有新鲜 evidence 和恢复状态无需迁移，缺失旧浏览器项时才从一次 browser batch 映射实际合同要求。旧 v4 已在 `final_check` 且没有 runner audit 时按原状态直接落地，不倒灌 timing 字段。
- 不新增 decisions JSONL 或第二套状态机；context pack 只编译现有真相源。
- 目标规格在 design 定稿时生成；描述已落地现状的文档在 merge 后更新，不因文档失败回滚已落地主线实现。
- gstack 只是方法参考与可选证据生产工具，不成为 PMAI 的状态、决定或收尾权威。
- `/pmai-record`、`/pmai-quick-fix`、`/pmai-build-cancel`、`/pmai-status` 继续作为产品侧轻量旁路，不分叉完整 build 生命周期；`/pmai-doctor` 是按需框架诊断旁路，不进入正常产品循环。
- doctor finding 以 `kind / blocking` 区分 `framework_managed_sync`、`legacy_compatible`、`compatibility_declaration_required`、`project_content_invalid` 和 advisory；只有 blocking finding 进入 `consumer_invalid`。旧中文索引等顶层文档必须由标准索引明确链接，不能替代 `docs/INDEX.md`；非空目录不要求 `.gitkeep`，空白模块文档不能作为兼容证据。
- 当前只有 Codex 的精确当前会话定位链路已经验证；其他宿主没有可验证的精确会话标识或定位适配时，`/pmai-feedback` 必须阻断，不能按文件修改时间或“最近会话”猜测。

## 当前验证

- 本轮关键定向基线：decision-gate `15/15`、status-view `19/19`、active-build-context `7/7`、active-build-guard `18/18`、narrative-mode `9/9`、context-pack `15/15`、legacy-recovery `15/15`、ready-contract `7/7`、doctor-skills `42/42`、init-project-codex-compat `24/24`、Kimi host `23/23`、OpenCode host `8/8`、lark-entry-routing `6/6`、lark-review `73/73`、publish-to-lark-e2e `20/20`、lark-adapter `40/40`、project-design-system `7/7`、mockup-quality `3/3`、mock-board `14/14`、consumer-doctor `26/26`、private-onboarding `4/4`、check-branch `21/21`、repo-kind `6/6`、exec-adapters `16/16`、skill-link-ownership `8/8`、skill-eval 合同 `6/6`、Loop Contract `4/4`；发布门在 runner / judge 均缺失时返回 2 并明确列出两项缺失能力，schema `25` 个案例与 static eval `7/7` 通过。
- 当前完整 `tests/run-all.sh` 基线为 `1021 passed / 0 failed`。本轮新增 Design frontier round、同轮多题独立授权、部分回答恢复、shared-understanding 收据，以及模块与项目级 PM 决定授权收据、压缩恢复防复用、Proposal 写入 / 接受 / commit / ready 授权 checkpoint、mockup 设计依据编译、桌面与窄屏视觉验收、质量证据漂移失效、需求 / 轮次 / 方向看版组织与最新优先排序回归，均已纳入全量编排；普通开发回归中的 skill eval 为 `7 passed / 0 failed / 18 session skipped`，只形成静态与确定性合同基线，不构成稳定版本证据；`v*` tag 或手动稳定发布仍必须通过配置真实 runner 与独立 judge 的 `tests/run-release-gate.sh`，任何 session skip 都会阻断。稳定核心发布门默认跳过可选 Lark 假环境套件，但日常全量回归仍保留这些套件。
- 早于 Proposal 合同的既有 active work 已有显式恢复合同：v1-v4 active build 绑定 PM 确认、Git checkpoint、authority 内容 hash，并分别保存旧 design 起点、合同保存终点、历史 delta 重放终点与一致性结论，再从当前确认点续接；旧 active design 保留原轮身份，历史 `ready_to_build` 退回 `designing` 重新确认目标。新工作和 v5 build 仍不能借此绕过 Proposal。
- 开发态入口同步 helper 已在真实消费仓 `ExampleAgentProject` 只读 dogfood：返回 `stale / legacy_migration`，渲染计划可以确定识别旧 PMAI Startup，并保留“非小改动前读取产品现状”等项目补充及后续项目规则。消费仓在本轮分析期间又出现新的活跃模块状态，因此不再把其整体 error 数作为本次入口同步回归基线；运行前后 Git 状态一致，未修改消费仓或用户级安装。

## 下一步

- 五个复杂度收口批次已完成：仓库身份、宿主等级、内部状态、Build 维护边界和主链 Loop Contract 都已有唯一来源。后续不再按收口批次新增架构层；当前已确认迁移 `ExampleAgentProject` 与 `ExampleConsumerApp`，保留各自既有 WIP，并只清理遗留 Kimi/OpenCode 主控资产。Session Eval、多 Agent 或动态工作流仍是独立决定。
- 在一个全新消费仓真实跑完 `init → proposal → design → spec-writing → build → finalize → main → 文档编译`，核对产品基线、规格编译、`project.yml`、隔离环境、自适应验收和落地闭环。
- 分别 dogfood 一次 Web product 与非 Web product：前者验证主动浏览器硬门，后者验证没有 prototype、dev port 或 browser 时仍可合法完成。
- 在真实消费仓 dogfood `/pmai-feedback` 的聚焦模式与完整审计升级各一次，记录完成时间，核对固定快照、问题归属和交接 Prompt 能否避免框架仓重复全文冷读；再按完整主控支持范围评估 Claude Code 的精确当前会话定位，不为仅 Builder 的 Kimi Code、OpenCode 建设主控 session locator，也不提供猜测式降级。
- 在真实 Docx 规格上 dogfood `/pmai-lark-review`：覆盖 active worktree 目标绑定、正文直改、复杂格式 / 图片 / 引用、Proposal / design handoff、sealed scoped adjustment 与 authority checkpoint；记录 collect / reconcile / 精细写回 / 评论收口的阶段耗时，确认机器路径进入 10–15 分钟。
- 后续框架修改继续先在开发分支完成 targeted / full regression，再进入 main 分发基线并升级全局安装副本。
