# PMAI v2 不变式

> 本文件只写当前有效的机器与流程约束。历史状态机、固定审计链和旧目录规则看 Git / `docs/archive/`，不得作为 active 入口复用。

## I-INIT：初始化

- **I-INIT1**：初始化只建立产品上下文脊柱、资料目录、host 配置和 Git 基线。
- **I-INIT2**：初始化不得询问或写入 `prototype / product`，不得决定技术栈和框架。
- **I-INIT3**：初始化不得创建 `.pm-workflow/project.yml`、代码、`prototype/`、mockup 看板、dev server 或端口配置。
- **I-INIT4**：gstack/browser 不是初始化依赖；缺失不能阻塞项目建立。
- **I-INIT5**：初始化完成后的正常入口只有 `/pmai-design`。

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

## I-LC：统一生命周期

- **I-LC1**：prototype 和 product 共用 `designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`。
- **I-LC2**：design 提交建造依据后才能进入 build；build 不临时补选类型、技术栈或框架。
- **I-LC3**：build 候选在 PM 定稿前完成验收就绪快照；PM 定稿后由 build 自动校验快照、落地主线和编译文档，`/pmai-build-close` 只兼容恢复。
- **I-LC4**：实现 commit、accepted delta 或 evidence 变化会使验收就绪快照失效。
- **I-LC5**：模块规格在 design 定稿时描述最终目标；landed 后按符合 / accepted delta / 漏实现 / 无依据实现对账，只有 accepted delta 可改目标。现状文档只根据已经 landed 的 main 事实更新；文档失败不得重复 merge。

## I-ACC：自适应验收

- **I-ACC1**：唯一活跃验收链是 `acceptance-profile.py → build.acceptance.required_checks/evidence`。
- **I-ACC2**：required checks 按 project definition、目标入口和风险生成，不存在适用于所有 build 的固定检查组合。
- **I-ACC3**：证据必须绑定当前 approved source hash 与 implementation commit。
- **I-ACC4**：Web required checks 必须有 `status=pass` 且 `active_browser_smoke=true` 的主动浏览器证据。
- **I-ACC5**：v2 不允许用 exception 跳过 browser-smoke；行为检查 fail 也不能放行。
- **I-ACC6**：非 Web product build 不要求 prototype、dev port 或浏览器。
- **I-ACC7**：contract v1 validator 只承担历史 close 兼容，不得被新流程调用或展示。
- **I-ACC8**：v2 只有完整 required evidence 通过 `review-ready` 后才能记录 PM 定稿；`final_check` 不首次跑完整验收或修改业务代码。

## I-BR / I-CB：分支与写入边界

- **I-BR1**：运行态只创建和识别 `build-*` 隔离分支。
- **I-BR2**：不得新建 `req-*` 或通用 `work-*` 工作分支。
- **I-CB1**：路径判断基于 `MAIN_REPO_ROOT`，不得被当前 cwd/worktree 误导。
- **I-CB2**：main 默认拒绝业务代码写入；根目录产品脊柱、`docs/**`、`mockups/**` 和 PMAI 状态文件按白名单处理。
- **I-CB3**：v2 `mode=main` 只允许写合同声明的 target paths。
- **I-CB4**：hook 无法判断时 fail-closed，且 hook 本身只读。
- **I-CB5**：完整 build 的业务实现只能落在已确认的当前环境或 `build-*` worktree。

## I-CR：自动 finalize 与恢复

- **I-CR1**：finalize 前必须有有效 build contract、最终 implementation commit、绑定同一 commit/hash 的验收就绪快照、PM 定稿记录和全部 required evidence。
- **I-CR2**：worktree 模式先在 build 分支提交实现，再 merge main；main 模式只处理合同声明路径。
- **I-CR3**：merge 必须做 ancestor 验证；冲突时保留 `final_check` 和隔离环境。
- **I-CR4**：实现 landed 后对账目标规格并编译现状文档；失败记录 `landed/docs_pending`，恢复时不重复 merge。
- **I-CR5**：完成后模块三件套保留，临时 `.work-meta.json` 按收尾合同清理。
- **I-CR6**：`close-work.sh` / `/pmai-build-close` 只作为旧合同和中断恢复入口，不构成正常用户主链。
- **I-CR7**：worktree 清理失败若不影响已落地实现，必须进入安全待清理队列，不得阻塞 landed 后文档编译。

## I-CA：取消

- **I-CA1**：cancel 不把 build 分支实现 merge 到 main。
- **I-CA2**：cancel 清理临时状态，不删除已经进入 main 的模块长期文档。
- **I-CA3**：cancel 和待清理 worktree 操作必须幂等。
- **I-CA4**：存在无法安全隔离的脏改时停止，不能自动丢弃用户工作。

## I-DOC：文档归位

- **I-DOC1**：`PRODUCT-RULES.md` 只保存跨模块当前有效的产品行为规则。
- **I-DOC2**：单模块决定进入模块 `decisions.md`；奠基理路进入 `docs/decisions/`。
- **I-DOC3**：`PRODUCT-STATE.md` 只保存当前产品事实，不兼职历史索引。
- **I-DOC4**：自动 finalize 与 `/pmai-record` 共用六类归位模型，不得维护平行分类。
