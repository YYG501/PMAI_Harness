# RUNTIME

> 当前运行状态真相源。历史迁移流水账看 git history / `CHANGELOG.md` / `docs/归档/`，本文件只保留当前有效模型。

## 当前位置

- 日期：2026-08-06
- 开发分支：`main`
- 当前目标：Harness 第一优先级的运行时护栏、验证可信度、失败恢复与 CI 环境可重复性已完成；继续以真实消费仓验证无缺陷正常路径 P95 是否接近 10 分钟。
- gstack 参考基线：`v1.58.5.0`，commit `11de390`；只参考本地 `gstack-clean` checkout，没有升级用户目录中的安装副本。

## 当前活跃模型

- 正常用户主链路：`/pmai-init-project` 只建上下文 → `/pmai-design` 讨论需求并在首次定稿时生成项目建造定义 → `/pmai-build` → PM 看结果多轮快速修改 → PM 明确定稿 → `finalize-work.py` 对冻结 commit 只执行缺失的代码门、范围门和受影响体验批次 → 合入 main → 只更新实际受影响的产品真相源。
- `meta`、`mockup`、`spec-writing` 是 design 按需调用后返回主线的内部能力；仍保留手动入口用于兼容和专项使用，但不要求 PM 拼接命令。
- `/pmai-feedback` 是消费仓到框架仓的只读反馈出口：完整复盘当前原始会话、对照消费仓真相源、判断问题归属，并输出包含会话文件地址和证据的框架优化 Prompt；它不在消费仓直接修改产品或 PMAI 框架。
- `/pmai-lark-review` 是归档后飞书评审回流入口：先把发布基线 B、采集时本地 L、采集时飞书 R 固定为只读证据，归位出唯一可写目标 T，再读取未解决评论的完整回复并按整批最高影响接回 quick-fix、active build 迭代或 design/build；正文作者 / 认可状态无法由 revision 证明时整批只问一次，批次在项目私有 context cache 中跨轮恢复。T 写回后先归位决定，再精细同步同一篇文档并继续实现，验证完成后以受控回执处理本批评论。普通正文同步仍走 `/pmai-lark-sync`。
- `/pmai-build-close` 只作为兼容与恢复入口；正常链路不再要求 PM 手动调用。
- lifecycle v2：`designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`。旧 `stage` 字段仅为 v1 消费仓兼容展示。
- 项目建造定义：初始化时不存在；首个达到 `ready_to_build` 的 design 将 `prototype / product`、技术栈、代码入口、真实命令和 Web 能力写入 `.pm-workflow/project.yml`。后续 build 只读该文件。
- 模块真相源：`docs/modules/<模块>/discussion.md`、`decisions.md`、`spec.md`；跨模块现行规则为 `PRODUCT-RULES.md`，项目级冻结理路为 `docs/decisions/`。
- 文档语义：`spec.md` / PRD 是指导研发实现的最终目标合同；`PRODUCT-STATE.md` 描述 main 已落地现状；原型、mockup 和代码只作设计 / 实现证据。
- design 的 `ready_to_build` 状态同时记录 approved source hash、design checkpoint 和精确目标路径；build 开工前重新编译上下文并验证 currentness，过期依据不能继续显示或进入构建。新 `.work-meta.json:build` 使用合同 v4，在 v3 实现深度合同之上增加 `iteration_checks / final_checks`、两层 evidence 和定稿请求；旧 v2/v3 合同继续用于中断恢复兼容。
- 新 build 由 AI 在一张卡中展示推荐的工作环境、构建工具和两项的全部有效选择，PM 只确认这两项；外部工具候选排除当前主控对应的 profile，“当前会话直接构建”始终可选，没有可用外部工具时默认推荐它。项目类型和验收方案不显示。选择当前环境时，main 只放行合同声明的目标路径。
- 主控宿主面：Claude Code 使用 `/pmai-*`，Codex 使用原生 `$pmai-*`，Kimi Code 使用原生 `/skill:pmai-*`，OpenCode 使用生成的 `/pmai-*` commands；四者消费同一份权威 Skill。Kimi Code 同时提供外部 builder profile，但在 Kimi 作为当前主控时按同宿主排除规则隐藏。
- 记忆分两层：项目事实、决定和偏好继续由消费仓现有真相源承担；个人经验保存在用户级状态目录，跨项目召回但只作建议。个人经验不进入 context pack、项目 hash 或 Git，也不能自动修改 Skill。

## 已实现

- Harness 第一阶段五项 P1 已下沉为运行时硬门：host `_shared` 只按明确所有权替换；brownfield 初始化写入前列全同名冲突；attached build worktree 的所属分支副本压住 main 旧状态；build 必须消费 current `ready_to_build + project.yml` 且拒绝路径、类型、入口和 revision 漂移；cancel 要求 main 干净、只提交状态删除，并在提交失败时恢复原状态。
- Harness 验证入口已失败关闭：每个 suite 有独立进程组超时，缺失 / 重复摘要、零用例、摘要与退出码矛盾都会计为失败；全量入口实际运行静态 skill eval，并明确显示 session runner / judge 的 pass、fail、skip。`PMAI_REQUIRE_SESSION_EVALS=1` 可将外部评测能力缺失升级为硬门。
- 初始化与 CI 不再借用开发机隐含环境：`init-project.sh` 在写目标目录前预检 Git author / committer 身份，初始 commit 失败保留 Git 原始错误和恢复命令；GitHub Actions 显式配置测试身份，负向内容断言只依赖系统自带 `grep`，runner 缺少 `rg` 不会假绿。
- 生命周期恢复已补齐：`ready_to_build` 正向进入 `building`；landing 状态、计时、暂存或 main commit 失败时 abort 半合并态并保留隔离环境；legacy close commit 失败恢复 `.work-meta.json`；待清理队列原子更新、损坏时失败关闭，cleanup 可从 cwd 阻断恢复且重复执行幂等。
- 新增 `context-pack.py`：design、build、恢复、最终检查和文档更新共用确定性上下文，并区分 active / superseded / 冲突决定、未决问题和输入 hash；项目定义存在时只从其中的 entrypoints 取实现上下文。
- 新增共用 `decision-policy`：机械项自动处理，可逆偏好给推荐并推进，产品模型岔路和 one-way door 立即让 PM 拍板；问句和讨论草稿不得成为决定。
- `build-contract.py` 新 build 继续使用合同 v4：`validate-final-currentness` 重新校验 design hash、accepted deltas、批准路径和 project.yml；真实 Git implementation commit 在每轮 `commit` 时立即阻断批准范围外路径。`request-finalization` 仍是 final evidence 和 `review-ready` 硬门；PM 新反馈用 `resume-iteration` 回快速车道。prototype 继续固化不可 exception 的 `prototype-boundary`。
- prototype / product 验收 profile schema v2 同时编译 `iteration_checks / final_checks`。新 Web build 只生成一个不可 exception 的 `browser-acceptance`，一次持续浏览器 chain 覆盖受影响流程的 smoke、visual、behavior；旧合同的三项浏览器证据继续兼容恢复。
- `final-validation.py` 对定稿请求绑定的 implementation commit 创建 detached validation worktree，在 `implementation.root` 运行命令；只对文本完全相同的 test/typecheck/build 去重，生产构建硬门不变。
- `finalize-work.py` 按 v4 lifecycle 只补缺失机械项，并用绑定 commit/source hash 的 audit 游标从语义检查、`final_check / landed / documenting` 准确续跑；只提交当前模块状态和 audit 目录，合入后输出 main 模块恢复位置。coverage、prototype boundary、迁移和安全等语义判断不伪装成自动通过。
- `build-timing.py` 自动记录 currentness、final-validation、browser-acceptance、semantic-validation、landing、documentation；统一 runner 完成前校验适用阶段都有 pass 且没有 running。真实 build/browser 缺陷、PM 新反馈、merge 冲突、未跟踪路径碰撞和文档碰撞把旧尝试标为 `exited` 或启动新尝试，不显示成 10 分钟成功。
- 新增 `prototype-boundary.py`：从 baseline 到候选实现扫描批准范围外改动、数据库 migration、生产基础设施、密钥配置、真实鉴权和外部副作用信号；静态信号无缺口后仍要求 AI 明确完成语义复核，artifact 才能写 `pass`。
- 新增 `project-definition.py` 和严格 schema validator；路径、类型、技术栈、Web 运行配置与 revision 变更全部 fail-closed。
- `project-type.py` 保留为兼容包装器：优先读新 `project.yml`，再读旧 config 和旧 `auto-detected: system` marker。
- 初始化脚本不再接收 project type，不创建代码、prototype、mockup 看板、dev server 或 gstack 依赖。
- 固定 build 审计编排和 coverage reviewer 已退出活跃链路；v4 只认 adaptive iteration/final checks 与对应 evidence。
- Web final checks 必须有 active browser-acceptance；旧合同仍要求 active browser-smoke。gstack 可由其它可验证 browser 适配器替代，不能 exception 掉浏览器能力。
- builder profile 按项目定义、配置、本机可用性和当前主控推荐；Claude Code、Codex、Kimi Code、Cursor Agent、OpenCode 都可作为外部执行器，当前主控对应的同名工具不进入候选，但当前会话直接构建始终可选；旧消费仓缺少 `kimi-code` profile 时由 `builder-profile.py` 运行时补齐，不改写项目配置；Gemini CLI 已退出构建工具面。验收 profile 仍后台生成，不进入开工卡。
- 自动 landing 在 merge 前检查 incoming path 与 main 未跟踪文件交集；merge 冲突保留 `final_check`，文档失败保留 `landed/docs_pending`，续跑不重复 merge，清理失败继续进入待清理队列。
- 文档影响地图只在 landed 后生成：默认更新 PRODUCT-STATE，accepted delta 才加入 spec、decisions 和明确受影响真相源；landed diff 已改文档自动 covered，未受影响文档不进入清单。
- spec-writing landed 对账固定分为符合、accepted delta、漏实现、无依据实现；只有 accepted delta 修改规格目标，漏实现保留为实现缺口。
- design、meta、mockup、spec-writing、build、build-close 与消费仓 AGENTS / CLAUDE 模板已按统一链路重构。
- 新增 `evals/cases/*.json`、`evals/touchfiles.json` 和 `scripts/skill-eval.py`；静态案例可作为提交门，session runner / LLM judge 缺失时明确 skip，require 模式明确 fail。
- Codex 只暴露 `~/.codex/skills/pmai-*` 原生 skills；不再生成会在 Desktop 显示为 `prompts:pmai-*` 的 custom prompts。install / upgrade 清理旧 prompt 文件，doctor / status 不再生成或检查它们；Claude Code skills 与 OpenCode commands 保持原入口。
- Kimi Code 通过 `$KIMI_CODE_HOME/skills/pmai-*` 暴露原生 `/skill:pmai-*`；用户级 `config.toml` 中只维护 PMAI 标记的 hooks 区块，全局分发器在普通仓 no-op，并把生成器仓 / 消费仓分别路由到已有护栏。install / upgrade / uninstall / doctor / status 已覆盖 Kimi 宿主面。
- design 直接必读 AskUser 共享规则，首题前收敛真实决策并报告总量，用业务结果提问；跨日、模型切换或会话恢复时重读当前 skill 与必读规则。context pack 消费后单独召回个人经验候选，按适用性、去重和独立检查价值自适应选择，不设正常条数上限；高信号纠偏闭合后自动归位。项目事实回项目真相源，跨项目经验进入用户级存储，已有 Skill 规则未执行只留执行失败证据。跨模块设计只留下一个明确 build 入口，相同建造方案重复写入 `project.yml` 保持完整文件不变。
- context pack 对旧消费仓自动写入 Git 本地 exclude，不再制造未跟踪缓存；build 在创建环境前阻断批准目标路径上的既有脏改动，同时保留无关 WIP。
- context pack 只把 D 编号模块决定和真实产品规则编入 active；共同理由、否过方案、待复核、变更记录与注释模板不再伪装成决定，已确认标题也不再误报未决。
- 新增 `scripts/current-session.py` 和 `/pmai-feedback`：Codex 通过 `CODEX_THREAD_ID` 精确定位 active / archived 原始 JSONL，校验会话唯一性、session ID 与 cwd 归属；Skill 完整读取会话并区分消费仓产品问题、执行偏差、Skill 缺口、框架合同缺口、宿主限制和证据不足，最后生成带消费仓路径、会话 ID、原始文件路径及证据的框架交接 Prompt。公开 `/pmai-skill-improve` 已移除，历史 `skill-feedback/` 资料继续保留。
- 新增 `scripts/lark-review.py` 和 `/pmai-lark-review`：采集同一 revision 的 Markdown / with-ids XML、历史发布版和完整分页评论，输出三方 diff 与可靠定位；B/L/R 快照只读，独立 T 经 resolutions 账本 seal 后才可原子写入正式规格。批次写入 Git 已忽略的 `.pm-workflow/context/lark-review/`，中断后可恢复，完成后才清理。正文 revision 只证明变化，不证明作者或认可；缺少 PM 本轮明确依据时一次展示整批差异并统一确认。采集结束和 apply 前复核本地正文、远端 revision 与稳定评论围栏；apply 后先正式归位决定 / accepted delta，精细同步写前重新 fetch 并以 apply plan revision 作为首笔 expected revision。评论由 `complete-comment` 受控回复 / 解决 / 回读，`comment-actions.json` 绑定本批操作；checkpoint / reopen 只消费回执，不能用自由填写的作者身份把 PM 手工操作冒充系统完成。文档身份、历史 revision、分页 envelope / token、并发变化或 checkpoint 冲突时失败关闭，且不提供 force；旧版缺基线文档只做 legacy 降级并要求 PM 明确归位。
- 飞书 frontmatter 回写改为补丁指定顶层标量、保留嵌套 YAML / 注释 / 正文并原子替换；发布后只有文档身份、写操作返回 revision、回读 revision 一致且本地发送源未变化时才建立新基线，避免绑定错文档、旧 revision 或本地并发版本。

## 兼容与边界

- 合同 v1 继续可读；已有消费仓不批量重写，下次 design 定稿时生成 `project.yml`。
- build contract 仍为 v4，project.yml schema 仍为 v1；旧 v2/v3/v4 的 browser-smoke / visual / behavior evidence 和恢复状态无需迁移，新 build 才采用 browser-acceptance 与统一 runner。旧 v4 已在 `final_check` 且没有 runner audit 时按原状态直接落地，不倒灌 timing 字段。
- 不新增 decisions JSONL 或第二套状态机；context pack 只编译现有真相源。
- 目标规格在 design 定稿时生成；描述已落地现状的文档在 merge 后更新，不因文档失败回滚已落地主线实现。
- gstack 只是方法参考与可选证据生产工具，不成为 PMAI 的状态、决定或收尾权威。
- `/pmai-record`、`/pmai-quick-fix`、`/pmai-build-cancel`、`/pmai-status` 继续作为轻量旁路，不分叉完整 build 生命周期。
- 当前只有 Codex 的精确当前会话定位链路已经验证；其他宿主没有可验证的精确会话标识或定位适配时，`/pmai-feedback` 必须阻断，不能按文件修改时间或“最近会话”猜测。

## 当前验证

- Harness 第一阶段安装所有权、初始化冲突、状态权威、ready/build 合同和 cancel 原子性 targeted tests 已通过：`42 passed / 0 failed`。
- 完整 `tests/run-all.sh` 已通过：`575 passed / 0 failed`；同一次入口另有 skill eval `6 passed / 0 failed / 15 session skipped`（外部 runner 未配置，已显式报告）。新增回归覆盖无 Git 身份时初始化在写入前失败，以及 suite 超时与摘要失败关闭、`ready_to_build → building`、`final_check → merge → docs_pending → resume` 不重复验收 / 合入、main landing commit 失败回滚后重试、legacy close 状态恢复、cleanup 失败恢复 / 幂等和损坏队列保护；最终命令去重、浏览器验收、真实 worktree 合入、Harness 五项 P1、飞书评审、Kimi 原生 Skill 与 hooks、`/pmai-feedback`、design、个人经验和其它既有回归继续通过。

## 下一步

- 继续用真实消费仓会话观察 active build 的小改能否稳定在 2–5 分钟内可刷新、交互改动能否稳定在 5–10 分钟内可刷新，以及定稿请求是否只触发一次隔离 production validation。
- 在真实消费仓 dogfood `/pmai-feedback`，核对完整会话复盘、问题归属和交接 Prompt 是否能直接驱动框架仓分析；再按宿主能力补充 Kimi Code、Claude Code 和 OpenCode 的精确当前会话定位适配，不提供猜测式降级。
- 在真实 Docx 规格上 dogfood `/pmai-lark-review`：覆盖正文直改、局部 / 全文评论、回复后要求变化、active build accepted delta、精细回写与评论解决；确认飞书 Markdown 回读规范化不会让正常发布误降级，再决定是否扩展旧版 `/doc/` 兼容。
- 后续框架修改继续先在开发分支完成 targeted / full regression，再进入 main 分发基线并升级全局安装副本。
