# PMAI v2 不变式

> 本文件只写当前有效的机器与流程约束。历史状态机、固定审计链和旧目录规则看 Git / `docs/archive/`，不得作为 active 入口复用。

## I-INIT：初始化

- **I-INIT1**：初始化只建立产品上下文脊柱、资料目录、host 配置和 Git 基线。
- **I-INIT2**：初始化不得询问或写入 `prototype / product`，不得决定技术栈和框架。
- **I-INIT3**：初始化不得创建 `.pm-workflow/project.yml`、代码、`prototype/`、mockup 看板、dev server 或端口配置。
- **I-INIT4**：gstack/browser 不是初始化依赖；缺失不能阻塞项目建立。
- **I-INIT5**：全新项目初始化完成后的唯一下一步是 `/pmai-proposal`；不得在 Proposal 完成前创建模块工作。
- **I-INIT6**：`--allow-existing` 只接住无同名目标的资料目录；任何模板或配置冲突必须在首次写入前停止。骨架完成后必须继续核验接入前资料，不能由脚本提前宣布 Proposal 或 design。

## I-PROP：产品方向基线

- **I-PROP1**：正常主链是 `init → proposal → design → spec-writing → build`；spec-writing 可由 design 自动调用，但不得省略规格编译。
- **I-PROP2**：新项目默认必须完成 Proposal；成熟项目只有在定位、用户、核心问题与价值、产品边界、MVP / 当前产品结果都完整，且 `PRODUCT.md` 显式记录至少一个真实仓内依据路径和 PM 确认日期、`PRODUCT.md` 与全部依据均已提交且无漂移、机器状态为 `equivalent_baseline` 时，才可跳过。
- **I-PROP3**：一旦进入 Proposal，必须产出可独立评审的完整版本，不得以 brief、摘要、大纲或普通介绍稿代替。
- **I-PROP4**：已确认 Proposal 正文及 `PRODUCT.md` 的当前版本、定位、核心问题与价值、用户、边界和 MVP 基线不可独立漂移；产品方向变化必须新建完整版本并显式 supersede 当前版本，正文 hash、产品基线 hash、版本关系与机器合同原子同步。术语等非产品基线章节仍可由其 owner 正常更新。
- **I-PROP5**：design、spec-writing、build、doc-writing 和 record 只读消费 Proposal；产品定位、目标用户、核心价值、职责边界、MVP 证明目标或关键成立前提变化时必须回 Proposal。
- **I-PROP6**：当前 Proposal 及其交接摘要参与下游 currentness；Proposal 变化后，旧 design/build 依据不得继续有效。

## I-PD：项目建造定义

- **I-PD1**：新项目的项目类型、技术栈、代码入口和运行命令只以 `.pm-workflow/project.yml` 为真相源。
- **I-PD2**：`project.yml` 只在首个达到 `ready_to_build` 的 design 定稿时生成；探索未定稿时保持缺失。
- **I-PD3**：`project.type` 只允许 `prototype / product`；技术栈必须写在 `implementation.stack`，不得混用。
- **I-PD4**：root、entrypoints 和 definition source 必须是仓库相对路径，禁止绝对路径和 `..`。
- **I-PD5**：`web.enabled=true` 必须同时声明真实 start command、ready path 和 ports。
- **I-PD6**：修改 type、framework 或 root 必须有 PM 明确确认，并递增 design revision、更新 source hash。
- **I-PD7**：`.pm-workflow/config.yml` 只保存 builder profile 等执行器偏好，不得重复 project definition。

## I-MOD：模块事实与状态

- **I-MOD1**：模块长期知识只在 `discussion.md / decisions.md / spec.md`；`.work-meta.json` 只保存工作状态和 build contract。
- **I-MOD2**：`status=active` 的模块 `.work-meta.json` 才代表进行中的工作。
- **I-MOD3**：`requirements/active|closed` 不是状态真相源。
- **I-MOD4**：旧 `stage` 只作无 lifecycle 项目的兼容展示，不是 v2 推进或收尾门。
- **I-MOD5**：同一 work id 同时存在于 main 与 attached build worktree 时，以元数据声明所属分支的 build worktree 副本为权威。

## I-LC：统一生命周期

- **I-LC1**：prototype 和 product 共用 `designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`。
- **I-LC2**：design 提交 current `ready_to_build` 和 `project.yml` 后才能进入 build；`build-contract start` 必须硬校验，不能补造状态或临时选择类型、技术栈和框架。
- **I-LC3**：PM 看结果期间只走快速迭代；PM 请求定稿后，build 冻结 implementation commit、运行一次 final checks、形成验收就绪快照，再自动落地主线和编译文档。`/pmai-build-close` 只兼容恢复。
- **I-LC4**：实现 commit、accepted delta 或 final evidence 变化会使验收就绪快照失效；accepted delta 和 PM 新反馈同时清除定稿请求。
- **I-LC5**：模块规格在 design 定稿时描述最终目标；landed 后按符合 / accepted delta / 漏实现 / 无依据实现对账，只有 accepted delta 可改目标。现状文档只根据已经 landed 的 main 事实更新；文档失败不得重复 merge。

## I-ACC：自适应验收

- **I-ACC1**：唯一活跃验收链是 `acceptance-profile.py → build.acceptance.iteration_checks/final_checks → 两层 evidence`；`required_checks` 只作 final checks 的旧 host 兼容别名。
- **I-ACC2**：iteration/final checks 按 project definition、目标入口和风险生成，不存在适用于所有 build 的固定检查组合。
- **I-ACC3**：iteration evidence 与 final evidence 分开；final evidence 必须绑定定稿请求、当前 approved source hash 与 implementation commit。
- **I-ACC4**：Web final checks 必须有 `status=pass` 且 `active_browser_smoke=true` 的主动浏览器证据。
- **I-ACC5**：v2 不允许用 exception 跳过 browser-smoke；行为检查 fail 也不能放行。
- **I-ACC6**：非 Web product build 不要求 prototype、dev port 或浏览器。
- **I-ACC7**：contract v1 validator 只承担历史 close 兼容，不得被新流程调用或展示。
- **I-ACC8**：v4 在 PM `request-finalization` 前拒绝 final evidence 和 `review-ready`；完整 final evidence 通过后才能记录 PM 定稿，`final_check` 不首次跑完整验收或修改业务代码。
- **I-ACC9**：project.yml 声明的定稿 test/typecheck/build 在冻结 commit 的 detached validation worktree 执行，不停止 active dev server，不改写其构建缓存。

## I-BR / I-CB：分支与写入边界

- **I-BR1**：运行态只创建和识别 `build-*` 隔离分支。
- **I-BR2**：不得新建 `req-*` 或通用 `work-*` 工作分支。
- **I-CB1**：路径判断基于 `MAIN_REPO_ROOT`，不得被当前 cwd/worktree 误导。
- **I-CB2**：main 默认拒绝业务代码写入；根目录产品脊柱、`docs/**`、`mockups/**` 和 PMAI 状态文件按白名单处理。
- **I-CB3**：v2 `mode=main` 只允许写合同声明的 target paths。
- **I-CB4**：hook 无法判断时 fail-closed，且 hook 本身只读。
- **I-CB5**：完整 build 的业务实现只能落在已确认的当前环境或 `build-*` worktree。
- **I-CB6**：active build 的 dev server 与浏览器连接跨反馈轮次保留；小改不得因 production validation 重启或重建。

## I-CR：自动 finalize 与恢复

- **I-CR1**：finalize 前必须有有效 build contract、绑定最终 implementation commit 的定稿请求、同一 commit/hash 的验收就绪快照、PM 定稿记录和全部 final evidence。
- **I-CR2**：worktree 模式先在 build 分支提交实现，再 merge main；main 模式只处理合同声明路径。
- **I-CR3**：merge 必须做 ancestor 验证；冲突或 landing 状态 / commit 写入失败时必须退出半合并态，保留 `final_check` 和隔离环境，重跑不得重复验收提交或 merge。
- **I-CR4**：实现 landed 后对账目标规格并编译现状文档；失败记录 `landed/docs_pending`，恢复时不重复 merge。
- **I-CR5**：完成后模块三件套保留，临时 `.work-meta.json` 按收尾合同清理。
- **I-CR6**：`close-work.sh` / `/pmai-build-close` 只作为旧合同和中断恢复入口，不构成正常用户主链。
- **I-CR7**：worktree 清理失败若不影响已落地实现，必须进入安全待清理队列，不得阻塞 landed 后文档编译；队列更新必须原子替换，损坏队列不得按空队列覆盖，重复 cleanup 必须幂等。

## I-CA：取消

- **I-CA1**：cancel 不把 build 分支实现 merge 到 main。
- **I-CA2**：cancel 清理临时状态，不删除已经进入 main 的模块长期文档。
- **I-CA3**：cancel 和待清理 worktree 操作必须幂等。
- **I-CA4**：cancel 开始前 main 必须无未提交改动；cancel commit 只能包含当前模块 `.work-meta.json` 的删除，不能自动丢弃或顺带提交用户工作。

## I-DOC：文档归位

- **I-DOC1**：`PRODUCT-RULES.md` 只保存跨模块当前有效的产品行为规则。
- **I-DOC2**：单模块决定进入模块 `decisions.md`；奠基理路进入 `docs/decisions/`。
- **I-DOC3**：`PRODUCT-STATE.md` 只保存当前产品事实，不兼职历史索引。
- **I-DOC4**：`/pmai-record` 只在 `ACTIVE_WORK_COUNT=0` 时补录已经确认的待办、术语、跨模块规则、项目级理路或有 main 证据的现状纠错；不得写模块三件套、Proposal、构建状态或实现。
- **I-DOC5**：spec-writing 的内容由通用模块与可叠加 Profile 组成，文档形态由 Preset 决定；企业平台与 AI Profile 可以叠加，完整 PRD Preset 不构成第二套产品真相源。

## I-TEST：验证可信度

- **I-TEST1**：全量测试中的每个 suite 必须有独立超时；超时后终止该 suite 的进程组并记为失败。
- **I-TEST2**：suite 缺失唯一 `Passed / Failed` 摘要、摘要与退出码矛盾或报告零用例时必须失败关闭，不得静默按 0 计数。
- **I-TEST3**：全量入口必须实际运行静态 skill eval，并明确报告 session runner / judge 的通过、失败与跳过数量；要求 session gate 时，缺少外部 runner / judge 必须失败。
