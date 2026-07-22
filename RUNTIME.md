# RUNTIME

> 当前运行状态真相源。历史迁移流水账看 git history / `CHANGELOG.md` / `docs/归档/`，本文件只保留当前有效模型。

## 当前位置

- 日期：2026-07-22
- 开发分支：`main`
- 当前目标：统一生命周期继续以真实消费仓会话收口；build contract v4 已拆开快速迭代与定稿验收，Kimi Code 也已按宿主原生 `/skill:pmai-*` 入口接成一等主控；新增 `/pmai-feedback`，把消费仓当前会话中的流程卡点转成交给框架仓的可追溯优化 Prompt。
- gstack 参考基线：`v1.58.5.0`，commit `11de390`；只参考本地 `gstack-clean` checkout，没有升级用户目录中的安装副本。

## 当前活跃模型

- 正常用户主链路：`/pmai-init-project` 只建上下文 → `/pmai-design` 讨论需求并在首次定稿时生成项目建造定义 → `/pmai-build` → PM 看结果多轮快速修改 → PM 明确定稿 → 冻结 commit 并统一运行一次 final checks → 形成验收就绪快照、合入 main、主线后文档编译和一致性检查。
- `meta`、`mockup`、`spec-writing` 是 design 按需调用后返回主线的内部能力；仍保留手动入口用于兼容和专项使用，但不要求 PM 拼接命令。
- `/pmai-feedback` 是消费仓到框架仓的只读反馈出口：完整复盘当前原始会话、对照消费仓真相源、判断问题归属，并输出包含会话文件地址和证据的框架优化 Prompt；它不在消费仓直接修改产品或 PMAI 框架。
- `/pmai-build-close` 只作为兼容与恢复入口；正常链路不再要求 PM 手动调用。
- lifecycle v2：`designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`。旧 `stage` 字段仅为 v1 消费仓兼容展示。
- 项目建造定义：初始化时不存在；首个达到 `ready_to_build` 的 design 将 `prototype / product`、技术栈、代码入口、真实命令和 Web 能力写入 `.pm-workflow/project.yml`。后续 build 只读该文件。
- 模块真相源：`docs/modules/<模块>/discussion.md`、`decisions.md`、`spec.md`；跨模块现行规则为 `PRODUCT-RULES.md`，项目级冻结理路为 `docs/decisions/`。
- 文档语义：`spec.md` / PRD 是指导研发实现的最终目标合同；`PRODUCT-STATE.md` 描述 main 已落地现状；原型、mockup 和代码只作设计 / 实现证据。
- design 的 `ready_to_build` 状态同时记录 approved source hash、design checkpoint 和精确目标路径；build 开工前重新编译上下文并验证 currentness，过期依据不能继续显示或进入构建。新 `.work-meta.json:build` 使用合同 v4，在 v3 实现深度合同之上增加 `iteration_checks / final_checks`、两层 evidence 和定稿请求；旧 v2/v3 合同继续用于中断恢复兼容。
- 新 build 由 AI 在一张卡中展示推荐的工作环境、构建工具和两项的全部有效选择，PM 只确认这两项；外部工具候选排除当前主控对应的 profile，“当前会话直接构建”始终可选，没有可用外部工具时默认推荐它。项目类型和验收方案不显示。选择当前环境时，main 只放行合同声明的目标路径。
- 主控宿主面：Claude Code 使用 `/pmai-*`，Codex 使用原生 `$pmai-*`，Kimi Code 使用原生 `/skill:pmai-*`，OpenCode 使用生成的 `/pmai-*` commands；四者消费同一份权威 Skill。Kimi 本轮只作为主控，不新增外部 builder。
- 记忆分两层：项目事实、决定和偏好继续由消费仓现有真相源承担；个人经验保存在用户级状态目录，跨项目召回但只作建议。个人经验不进入 context pack、项目 hash 或 Git，也不能自动修改 Skill。

## 已实现

- 新增 `context-pack.py`：design、build、恢复、最终检查和文档更新共用确定性上下文，并区分 active / superseded / 冲突决定、未决问题和输入 hash；项目定义存在时只从其中的 entrypoints 取实现上下文。
- 新增共用 `decision-policy`：机械项自动处理，可逆偏好给推荐并推进，产品模型岔路和 one-way door 立即让 PM 拍板；问句和讨论草稿不得成为决定。
- `build-contract.py` 新 build 使用合同 v4：`request-finalization` 是 final evidence 和 `review-ready` 的硬门；accepted delta 清除定稿请求，验收发现缺口后的修复 commit 自动重绑原定稿意图，PM 新反馈用 `resume-iteration` 回快速车道。prototype 继续固化 `interactive-simulation` 和不可 exception 的 `prototype-boundary`。
- prototype / product 验收 profile schema v2 同时编译实现深度、`iteration_checks` 和 `final_checks`。快速迭代只跑热更新、typecheck 与当前页面走查；外部 builder 只用于首次实现或大型重构。
- 新增 `final-validation.py`：对定稿请求绑定的 implementation commit 创建 detached validation worktree，运行 project.yml 的 test/typecheck/build，写结构化 artifact 后安全清理；不停止 active dev server，不改写其构建缓存。
- 新增 `build-timing.py`：记录 prepare、implement、fast-check、preview、final-typecheck、production-build、browser-acceptance、documentation 阶段和 time-to-preview；2–5 / 5–10 分钟只预警，不阻断 PM 查看。
- 新增 `prototype-boundary.py`：从 baseline 到候选实现扫描批准范围外改动、数据库 migration、生产基础设施、密钥配置、真实鉴权和外部副作用信号；静态信号无缺口后仍要求 AI 明确完成语义复核，artifact 才能写 `pass`。
- 新增 `project-definition.py` 和严格 schema validator；路径、类型、技术栈、Web 运行配置与 revision 变更全部 fail-closed。
- `project-type.py` 保留为兼容包装器：优先读新 `project.yml`，再读旧 config 和旧 `auto-detected: system` marker。
- 初始化脚本不再接收 project type，不创建代码、prototype、mockup 看板、dev server 或 gstack 依赖。
- 固定 build 审计编排和 coverage reviewer 已退出活跃链路；v4 只认 adaptive iteration/final checks 与对应 evidence。
- Web final checks 必须有 active browser-smoke；gstack 可由其它 browser/Playwright 适配器替代，不能 exception 掉浏览器能力。
- builder profile 按项目定义、配置、本机可用性和当前主控推荐；开工卡一次列出有效环境与工具，当前主控不再作为外部执行器候选，但当前会话直接构建始终可选；Gemini CLI 已退出构建工具面。验收 profile 仍后台生成，不进入开工卡。
- 新增自动 landing 和恢复：merge 冲突保留 `final_check` 与隔离环境；文档失败保留 `landed/docs_pending`，续跑不重复 merge；运行进程或缓存导致的 worktree 清理失败进入安全待清理队列，不阻塞文档阶段。
- 文档影响地图在验收就绪候选阶段先生成草案，landed 后按 main 事实完成覆盖；对象、动作、状态、权限、页面、术语和受影响文件都必须 covered 或明确 no-change，最终提交自动纳入影响地图本身。
- spec-writing landed 对账固定分为符合、accepted delta、漏实现、无依据实现；只有 accepted delta 修改规格目标，漏实现保留为实现缺口。
- design、meta、mockup、spec-writing、build、build-close 与消费仓 AGENTS / CLAUDE 模板已按统一链路重构。
- 新增 `evals/cases/*.json`、`evals/touchfiles.json` 和 `scripts/skill-eval.py`；静态案例可作为提交门，session runner / LLM judge 缺失时明确 skip，require 模式明确 fail。
- Codex 只暴露 `~/.codex/skills/pmai-*` 原生 skills；不再生成会在 Desktop 显示为 `prompts:pmai-*` 的 custom prompts。install / upgrade 清理旧 prompt 文件，doctor / status 不再生成或检查它们；Claude Code skills 与 OpenCode commands 保持原入口。
- Kimi Code 通过 `$KIMI_CODE_HOME/skills/pmai-*` 暴露原生 `/skill:pmai-*`；用户级 `config.toml` 中只维护 PMAI 标记的 hooks 区块，全局分发器在普通仓 no-op，并把生成器仓 / 消费仓分别路由到已有护栏。install / upgrade / uninstall / doctor / status 已覆盖 Kimi 宿主面。
- design 直接必读 AskUser 共享规则，首题前收敛真实决策并报告总量，用业务结果提问；跨日、模型切换或会话恢复时重读当前 skill 与必读规则。context pack 消费后单独召回个人经验候选，按适用性、去重和独立检查价值自适应选择，不设正常条数上限；高信号纠偏闭合后自动归位。项目事实回项目真相源，跨项目经验进入用户级存储，已有 Skill 规则未执行只留执行失败证据。跨模块设计只留下一个明确 build 入口，相同建造方案重复写入 `project.yml` 保持完整文件不变。
- context pack 对旧消费仓自动写入 Git 本地 exclude，不再制造未跟踪缓存；build 在创建环境前阻断批准目标路径上的既有脏改动，同时保留无关 WIP。
- context pack 只把 D 编号模块决定和真实产品规则编入 active；共同理由、否过方案、待复核、变更记录与注释模板不再伪装成决定，已确认标题也不再误报未决。
- 新增 `scripts/current-session.py` 和 `/pmai-feedback`：Codex 通过 `CODEX_THREAD_ID` 精确定位 active / archived 原始 JSONL，校验会话唯一性、session ID 与 cwd 归属；Skill 完整读取会话并区分消费仓产品问题、执行偏差、Skill 缺口、框架合同缺口、宿主限制和证据不足，最后生成带消费仓路径、会话 ID、原始文件路径及证据的框架交接 Prompt。公开 `/pmai-skill-improve` 已移除，历史 `skill-feedback/` 资料继续保留。

## 兼容与边界

- 合同 v1 继续可读；已有消费仓不批量重写，下次 design 定稿时生成 `project.yml`。
- 不新增 decisions JSONL 或第二套状态机；context pack 只编译现有真相源。
- 目标规格在 design 定稿时生成；描述已落地现状的文档在 merge 后更新，不因文档失败回滚已落地主线实现。
- gstack 只是方法参考与可选证据生产工具，不成为 PMAI 的状态、决定或收尾权威。
- `/pmai-record`、`/pmai-quick-fix`、`/pmai-build-cancel`、`/pmai-status` 继续作为轻量旁路，不分叉完整 build 生命周期。
- 当前只有 Codex 的精确当前会话定位链路已经验证；其他宿主没有可验证的精确会话标识或定位适配时，`/pmai-feedback` 必须阻断，不能按文件修改时间或“最近会话”猜测。

## 当前验证

- 新增和改造的 context pack、acceptance profile、build contract、landing、文档影响地图、status、关键 Skill 路由、design 决策收敛、project definition 幂等与个人经验 targeted tests 已通过。
- 完整 `tests/run-all.sh` 已通过：`485 passed / 0 failed`。新增回归覆盖 `/pmai-feedback` 的入口、只读合同、精确会话定位、失败关闭和旧公开 Skill 移除；Kimi 原生 Skill 命名、用户配置保留、全局 Hook 仓库分流、主控识别、安装生命周期和 doctor 自愈，以及 iteration/final 双车道、prototype 边界、landing/docs 恢复、design、个人经验与执行器回归继续通过。

## 下一步

- 继续用真实消费仓会话观察 active build 的小改能否稳定在 2–5 分钟内可刷新、交互改动能否稳定在 5–10 分钟内可刷新，以及定稿请求是否只触发一次隔离 production validation。
- 在真实消费仓 dogfood `/pmai-feedback`，核对完整会话复盘、问题归属和交接 Prompt 是否能直接驱动框架仓分析；再按宿主能力补充 Kimi Code、Claude Code 和 OpenCode 的精确当前会话定位适配，不提供猜测式降级。
- 后续框架修改继续先在开发分支完成 targeted / full regression，再进入 main 分发基线并升级全局安装副本。
