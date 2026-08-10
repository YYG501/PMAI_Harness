# RUNTIME

> 当前运行状态真相源。历史迁移流水账看 git history / `CHANGELOG.md` / `docs/归档/`，本文件只保留当前有效模型。

## 当前位置

- 日期：2026-08-10
- 开发分支：`main`
- 当前目标：已修复真实消费仓中“模块 close 后再次修改”的轮次混用、accepted delta 最终哈希冲突和并行文档 currentness 边界；定向与全量回归均已通过，尚未提交、分发或升级安装态。
- gstack 参考基线：`v1.58.5.0`，commit `11de390`；只参考本地 `gstack-clean` checkout，没有升级用户目录中的安装副本。

## 当前活跃模型

- 正常用户主链路：`/pmai-init-project` 只建上下文 → `/pmai-design` 讨论需求并在首次定稿时生成项目建造定义 → `/pmai-build` → PM 看结果多轮快速修改 → PM 明确定稿 → `finalize-work.py` 对冻结 commit 只执行缺失的代码门、范围门和受影响体验批次 → 合入 main → 只更新实际受影响的产品真相源。
- `meta`、`mockup`、`spec-writing` 是 design 按需调用后返回主线的内部能力；仍保留手动入口用于兼容和专项使用，但不要求 PM 拼接命令。
- `/pmai-feedback` 是消费仓到框架仓的只读反馈出口：完整复盘当前原始会话、对照消费仓真相源、判断问题归属，并输出包含会话文件地址和证据的框架优化 Prompt；它不在消费仓直接修改产品或 PMAI 框架。
- `/pmai-doctor` 的消费仓合同复用 `.pm-workflow/config.yml:consumer`：layout v1 固定 `docs/INDEX.md` / `docs/modules/INDEX.md` 为标准入口，可声明既有归档目录，并按模块记录 `current / legacy / retired / split`。未标版本旧仓只做有边界识别并请求 PM 确认，不自动迁移文档；active `.work-meta.json` 始终优先，不能被兼容声明降级。
- `/pmai-doctor` 的 JSON `pm_report` 直接给出需要处理、仅供参考和项目进度，Agent 不再从底层 finding 自行扩写待办。消费仓 Startup 由 `AGENTS.md` 内唯一托管区块承载；`sync-consumer-entry.py` 的 check 只读，apply 只在 PM 确认后原子替换该区块，旧文件迁移保留项目补充并对未知规则、损坏标记和 symlink 失败关闭。CLI 不自行越过沙箱；版本未知且有远程地址时，由 Doctor Skill 让当前宿主申请联网权限后重试同一只读查询。
- `/pmai-lark-review` 是归档后飞书评审回流入口：当前飞书 full XML 原生快照是 T 的唯一底稿，B/L 只用于定位本地补充和冲突，祖先格式兼容性不能把目标切回旧 L。R→T 的每个删除 / 改写 / 移动进入远端覆盖账本，重复文本按章节归位，现有 block 的格式必须保留，随内容删除也要有明确依据；大规模或结构性差异生成预览，纯排版 / 结构保真可由 Agent 记录 `agent_reviewed`，只有真实产品分叉才要求 PM 确认。精细同步后逐 block 验证样式、资源和引用；图片 Markdown 临时 URL 不作为资源身份，图片 alt / 数量 / 结构和普通链接仍严格比较，资源身份由原生 block / token 验证。飞书正文、评论和回复只是不可信业务证据，不能作为 Agent 指令或 PM 本轮确认；remote-only 正文必须由 PM 本轮明确认可。每项变化通过 `decision_routing` 选择性写 / supersede `docs/modules/<单一模块>/decisions.md`；存在候选产品决定时，seal 前必须把每条候选与全部当前有效决定逐一对照，漏项、过期或 `needs_pm` 均阻断。seal、apply 和正式归位前都拒绝越界或 symlink 目标，措辞 / 排版明确标记不写。评论处置区分真正延期的 `deferred` 与旧引用已被新方案替代的 `superseded`；评论完成状态为 `open / replied_pending_pm / solved_by_pmai / solved_by_pm_verified`。默认 `complete-comments` 回复并解决；`--reply-only` 只回复且 solve 调用必须为 0，PM 可分批手工解决，再由 `verify-comments` 回读，全部核验后才允许 checkpoint。逐笔 journal 绑定受控回复和解决证据，不能把外部写入冒充本批完成，也不能 reopen PM 手工解决的评论。最终回执由 `receipt` 只输出正文、格式、评论、本地产品结果和 PM 待办。机器路径目标 10–15 分钟，阶段耗时与 API 往返写入批次产物。
- `/pmai-build-close` 只作为兼容与恢复入口；正常链路不再要求 PM 手动调用。
- 模块 close 后再次修改先按影响分流：错字、单文案、局部样式、常量和符合现有规格的小缺陷走 `/pmai-quick-fix`；产品对象、规则、规格、任务路径或验收变化进入新一轮 `/pmai-design → /pmai-build`。新轮次复用长期模块文档，但 work id、design 基线、accepted delta、验收证据、audit 目录和 finalize 游标全部重新建立。
- `building / iterating / final_check` 中，PM 的“启动看看 / 还有什么问题 / 继续改当前结果”等自然语言继续当前 `/pmai-build`。Codex、Claude Code、Kimi Code 通过 prompt hook 注入 `status-view.py --execution-context`；OpenCode 由入口规则主动读取。该上下文只派生现有合同，不新增状态；多个 active build 返回歧义，合同或 policy 漂移时失败关闭。只有位于 prompt 首 token 的真实 PMAI 命令不受自然语言续接拦截，否定、引用、行内代码、代码块和文档示例都不能绕过；Git / status-view 超时、非零、空输出、坏 JSON、未知状态或 stdin 超时一律在宿主超时前注入不可用护栏，不能降级成“没有 active build”；Kimi 分发器也不得吞掉 hook 缺失、Node 启动失败或任意非零退出。
- lifecycle v2：`designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`。旧 `stage` 字段仅为 v1 消费仓兼容展示。
- 项目建造定义：初始化时不存在；首个达到 `ready_to_build` 的 design 将 `prototype / product`、技术栈、代码入口、真实命令和 Web 能力写入 `.pm-workflow/project.yml`。后续 build 只读该文件。
- 模块真相源：`docs/modules/<模块>/discussion.md`、`decisions.md`、`spec.md`；跨模块现行规则为 `PRODUCT-RULES.md`，项目级冻结理路为 `docs/decisions/`。
- 文档语义：`spec.md` / PRD 是指导研发实现的最终目标合同；`PRODUCT-STATE.md` 描述 main 已落地现状；原型、mockup 和代码只作设计 / 实现证据。
- design 的 `ready_to_build` 状态同时记录 approved source hash、hash scope version、design checkpoint 和精确目标路径；build 开工前重新编译上下文并验证 currentness，过期依据不能继续显示或进入构建。新轮次使用 `source_hash_version=2`：模块三件套、输入证据、PRODUCT、PRODUCT-RULES、DESIGN、项目级决定和 project.yml 参与 currentness；PRODUCT-STATE、TODO 和模块索引只作上下文，单独变化不判设计过期。没有版本字段的旧 ready/build 按 v1 全量范围恢复到该轮结束，显式返回 design 后下一次批准才升级 v2。新 `.work-meta.json:build` 使用合同 v4，在 v3 实现深度合同之上增加 `iteration_checks / final_checks`、两层 evidence 和定稿请求；旧 v2/v3 合同继续用于中断恢复兼容。
- 新 build 由 AI 在一张卡中展示推荐的工作环境、构建工具和两项的全部有效选择，PM 只确认这两项；外部工具候选排除当前主控对应的 profile，“当前会话直接构建”始终可选，没有可用外部工具时默认推荐它。项目类型和验收方案不显示。选择当前环境时，main 只放行合同声明的目标路径。
- 主控宿主面：Claude Code 使用 `/pmai-*`，Codex 使用原生 `$pmai-*`，Kimi Code 使用原生 `/skill:pmai-*`，OpenCode 使用生成的 `/pmai-*` commands；四者消费同一份权威 Skill。Kimi Code 同时提供外部 builder profile，但在 Kimi 作为当前主控时按同宿主排除规则隐藏。
- 记忆分两层：项目事实、决定和偏好继续由消费仓现有真相源承担；个人经验保存在用户级状态目录，跨项目召回但只作建议。个人经验不进入 context pack、项目 hash 或 Git，也不能自动修改 Skill。

## 已实现

- Harness 第一阶段五项 P1 已下沉为运行时硬门：host `_shared` 只按明确所有权替换；brownfield 初始化写入前列全同名冲突；attached build worktree 的所属分支副本压住 main 旧状态；build 必须消费 current `ready_to_build + project.yml` 且拒绝路径、类型、入口和 revision 漂移；cancel 要求 main 干净、只提交状态删除，并在提交失败时恢复原状态。
- Harness 验证入口已失败关闭：每个 suite 有独立进程组超时，缺失 / 重复摘要、零用例、摘要与退出码矛盾都会计为失败；全量入口实际运行静态 skill eval，并明确显示 session runner / judge 的 pass、fail、skip。`PMAI_REQUIRE_SESSION_EVALS=1` 可将外部评测能力缺失升级为硬门。
- 初始化与 CI 不再借用开发机隐含环境：`init-project.sh` 在写目标目录前预检 Git author / committer 身份，初始 commit 失败保留 Git 原始错误和恢复命令；GitHub Actions 显式配置测试身份，负向内容断言只依赖系统自带 `grep`，runner 缺少 `rg` 不会假绿。
- 生命周期恢复已补齐：`ready_to_build` 正向进入 `building`；landing 状态、计时、暂存或主线 commit 失败时 abort 半合并态并保留隔离环境；legacy close commit 失败恢复 `.work-meta.json`。cancel / land 先持久化 prepared 清理意图，主线状态提交后只激活队列，不在落地进程内直接删除 worktree / branch；中断后 cleanup 以 Git 真相自动恢复。每项记录固定自己的 `refs/heads/main` 或 `refs/heads/master`，landed 激活和 active 删除都用入队时的 branch OID 重新验证该主线，分支名改向、主线 reset 或 main/master 并存不能误删；最终分支删除使用 old-OID `git update-ref` CAS。待清理队列加进程锁并原子更新，损坏时失败关闭，事务 stage 不占用 `.pending-*` 中断标记命名空间；main/master preamble 均可消费，status 与会话 startup 使用只读 preamble。cleanup 只让 Git 删除已确认没有 tracked、untracked、ignored 内容且无人占用的注册 worktree，Git 拒绝时保留现场，不再用文件系统递归强删。
- 新增 `context-pack.py`：design、build、恢复、最终检查和文档更新共用确定性上下文，并区分 active / superseded / 冲突决定、未决问题和输入 hash；项目定义存在时只从其中的 entrypoints 取实现上下文。
- 新增共用 `decision-policy`：机械项自动处理，可逆偏好给推荐并推进，产品模型岔路和 one-way door 立即让 PM 拍板；问句和讨论草稿不得成为决定。
- `build-contract.py` 新 build 继续使用合同 v4：`validate-final-currentness` 重新校验 design hash、accepted deltas、批准路径和 project.yml；真实 Git implementation commit 在每轮 `commit` 时立即阻断批准范围外路径。`request-finalization` 仍是 final evidence 和 `review-ready` 硬门；PM 新反馈用 `resume-iteration` 回快速车道。prototype 继续固化不可 exception 的 `prototype-boundary`。
- 每次新建模块工作都会生成唯一 `work-<模块>-<时间>-<随机值>` id，并把 `build.audit_dir` 固定为包含该 id 的目录；finalize、landing、文档影响地图和失败恢复只使用该轮目录。旧 `work-<模块>` 合同继续回退模块级 audit 目录。final currentness 分别校验初始 design hash 和按顺序串联后的 accepted-delta 最终 hash，不再在 delta 链验证前把两者误判为冲突。
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
- 自动 landing 在 merge 前检查 incoming path 与 main 未跟踪文件交集；merge 冲突保留 `final_check`，文档失败保留 `landed/docs_pending`，续跑不重复 merge。清理失败或其它会话仍以待清理 worktree 为 cwd 时保留队列，后续从 main 自动重试。
- 文档影响地图只在 landed 后生成：默认更新 PRODUCT-STATE，accepted delta 才加入 spec、decisions 和明确受影响真相源；landed diff 已改文档自动 covered，未受影响文档不进入清单。业务术语和角色只从 build 规格锚点、landed 的模块 / 功能型规格、明确定名决定和 `kind=term/role` 的 accepted delta 对账；讨论稿、索引、引号、加粗、问句和代码不参与猜词。term detector 与 context pack 共用状态问句识别，无问号的“当前决定是否被取代”也不能成为决定或术语来源；“被取代时的迁移”等条件、时序和属性描述不改变决定状态。术语表支持有或无前导竖线，但遇 heading、list、quote、fence 或缩进代码立即结束。已取代旧决定的新决定仍参与当前术语提取，重复 cue 采用线性扫描；detector 已确认仍缺失的术语不会因 PRODUCT.md 恰有其它 landed 改动而自动 covered。
- spec-writing landed 对账固定分为符合、accepted delta、漏实现、无依据实现；只有 accepted delta 修改规格目标，漏实现保留为实现缺口。
- design / spec-writing 现在按“产品决定是否闭合”分流：对象、规则、信息结构、任务路径、权限或关键交互仍未定时由 design 讨论；只有已确认内容的整理、补差和改写进 spec-writing。
- 宿主入口暴露由 `scripts/_lib/skill-links.sh::pmai_skill_is_host_exposed` 统一判断。`build-close` 和 `publish-to-lark` 不进入正常主路径，但作为兼容恢复和明确手动发布能力继续在 Claude、Codex、Kimi、OpenCode 注册；meta、mockup、spec-writing 默认由 design 调用，同时保留独立专项意图的可发现入口。upgrader 在升级、降级和回滚前清空当前 Bash 进程的旧策略函数，再加载目标版本；旧版本没有过滤函数时恢复当时的全公开语义。
- brownfield 接入只把代码盘点写入 `CODEBASE-AUDIT.md` 和首次 `PRODUCT-STATE.md` 现状；不从代码生成目标 `spec.md`，不再把已退役的 coverage reviewer、固定视觉门或“补 8 段基线”当作 build 前置。
- design、meta、mockup、spec-writing、build、build-close 与消费仓 AGENTS / CLAUDE 模板已按统一链路重构。
- 新增 `evals/cases/*.json`、`evals/touchfiles.json` 和 `scripts/skill-eval.py`；静态案例可作为提交门，session runner / LLM judge 缺失时明确 skip，require 模式明确 fail。
- Codex 只暴露 `~/.codex/skills/pmai-*` 原生 skills；不再生成会在 Desktop 显示为 `prompts:pmai-*` 的 custom prompts。install / upgrade 清理旧 prompt 文件，doctor / status 不再生成或检查它们；Claude Code skills 与 OpenCode commands 保持原入口。
- Kimi Code 通过 `$KIMI_CODE_HOME/skills/pmai-*` 暴露原生 `/skill:pmai-*`；用户级 `config.toml` 中只维护 PMAI 标记的 hooks 区块。Kimi 由同一 session cwd 启动 hook 并生成 payload，因此全局分发器先以进程 cwd 路由：普通仓在读取 stdin 前直接 no-op，生成器 / 消费仓才读取并校验 payload；PMAI 路由内的坏 JSON、超限输入和 payload 跨根继续失败关闭。仓库标记只决定路由，hook 代码始终从分发器所属的可信 PMAI 框架读取，仿冒生成器仓不能触发仓内 JavaScript；可信 hook 缺失、运行时不可用或非零退出时分发器失败关闭。write 的相对路径先按 payload cwd 解析为真实绝对目标，`file_path` / `path` 别名必须指向同一文件，再交给分支护栏。install / upgrade / uninstall / doctor / status 已覆盖 Kimi 宿主面。
- Claude Code / Codex 项目 hooks 由 `install-project-hooks.sh` 统一管理：`--check` 只读比较当前消费仓配置，刷新时只精确替换 PMAI 自有命令并保留其它宿主设置和自定义 hook；命令通过 `${PMAI_HOME:-$HOME/.pmai}` 在宿主运行时解析，自定义安装根不会退回错误的默认路径。安装器预渲染全部 Host 后事务写入，用唯一备份逐次校验内容、权限和 symlink 指向；失败回滚不覆盖通过正式路径提交的并发编辑，并兼容 Bash 3.2。协作锁只串行遵守合同的 PMAI writer：事务子进程必须继承与锁路径相同 device / inode 且实际持有排他锁的 fd，可伪造环境布尔值或无关 fd 不能授权写入；同一 OS 用户的非合作进程仍不在该合同内。目录 fd 在 claim 后发现父目录改向时，会在固定旧目录内按 inode 补偿恢复正式名再失败关闭，不把原件留在隔离名。该 CAS 只保护路径命名空间；其它进程若持有旧文件描述符并在 claim 后继续写入，需要共享写锁或版本保留。全局 upgrade 不静默改写消费仓；`/pmai-doctor` 调用目标 `PMAI_HOME` 的 doctor，默认只读检查框架、宿主入口和当前消费仓，跨版本目标 doctor 缺失或不可执行时失败关闭；全局修复只有 `--repair` 才获取安装锁并写入，消费仓 hooks 刷新仍需 PM 单独确认。CLI `pmai status` 只委托 `doctor --check`，不再维护第二套策略审计。旧 `install-codex-hooks.sh` 保留为 Codex-only 兼容包装。
- design 直接必读 AskUser 共享规则，首题前收敛真实决策并报告总量，用业务结果提问；跨日、模型切换或会话恢复时重读当前 skill 与必读规则。context pack 消费后单独召回个人经验候选，按适用性、去重和独立检查价值自适应选择，不设正常条数上限；高信号纠偏闭合后自动归位。项目事实回项目真相源，跨项目经验进入用户级存储，已有 Skill 规则未执行只留执行失败证据。跨模块设计只留下一个明确 build 入口，相同建造方案重复写入 `project.yml` 保持完整文件不变。
- context pack 对旧消费仓自动写入 Git 本地 exclude，不再制造未跟踪缓存；build 在创建环境前阻断批准目标路径上的既有脏改动，同时保留无关 WIP。
- `context-pack.py` 与 `check-open-questions.py` 共用明确无未决问题的声明识别；只有单独一行的肯定声明才表示空问题集，否定、转述、但书、多行后续问题和子串命中都不能放行。空 section、普通说明、空题名、HTML comment-only 以及 `待确认` / `TODO` / `TBD` / `FIXME` 等占位回答仍保持 unresolved。
- context pack 只把 D 编号模块决定和真实产品规则编入 active；共同理由、否过方案、待复核、变更记录与注释模板不再伪装成决定。标题或正文仍是问句、尚在讨论且没有明确结论时保持 rejected；明确状态或结论可以闭合问题标题，带“尚未正式 / 并未真正”等副词的否定状态保持 active。
- 新增 `scripts/current-session.py` 和 `/pmai-feedback`：Codex 通过 `CODEX_THREAD_ID` 精确定位 active / archived 原始 JSONL，校验会话唯一性、session ID 与 cwd 归属；Skill 完整读取会话并区分消费仓产品问题、执行偏差、Skill 缺口、框架合同缺口、宿主限制和证据不足，最后生成带消费仓路径、会话 ID、原始文件路径及证据的框架交接 Prompt。公开 `/pmai-skill-improve` 已移除，历史 `skill-feedback/` 资料继续保留。
- `scripts/lark-review.py` 和 `/pmai-lark-review` 已升级到原生远端底稿合同：采集同一 revision 的 Markdown / full XML、历史发布版和完整分页评论；`remote-native.json` 保留 block/style/resource/reference，remote-coverage schema v2 同时绑定语义 kind 与标题层级、列表顺序/缩进、表格角色，跨 kind rewritten、章节移动和真实重排都进入结构高风险并生成预览；旧 v1 账本不能沿用旧预览结论执行或验收。`verify-sync` 同时比较文本和结构投影，以原生 block / token 判断图片资源身份，不因飞书 Markdown 临时 URL 轮换失败。collect 在联网前绑定 canonical Git 仓根，真实内嵌 worktree 使用当前 worktree 根，v2 / v3 批次都不能缺少 `repo_root` 后继续执行。新 ready plan / resolution 使用 v4，comment-actions 使用 v3，remote-verification 使用 v2；reply-only、PM 手工解决回读、`superseded` 评论处置和跨决定一致性回执只进入新 v4 批次。已有 v3 ready 批次继续按原合同恢复；旧 remote-verification v1 必须重跑验收，保留仓根绑定的旧 review/plan v2 与 comment-actions v1 批次仍可完成评论恢复。
- 飞书 frontmatter 回写改为补丁指定顶层标量、保留嵌套 YAML / 注释 / 正文并原子替换；最终正文、checkpoint 和 baseline 写入使用逐级 `O_NOFOLLOW` 的固定目录 fd，父目录 symlink 重绑不能改变落点。普通 Path API 先 canonicalize 父目录以接受 `/var` 等合法系统别名，最终文件名仍拒绝 symlink；跨远端阶段继续显式要求 canonical path。create / update / fetch / comments / api 的 JSON 对象统一拒绝 `ok:false`、`success:false` 和非零 `code`；已经发起 overwrite 后的非零、空输出、非 JSON、非对象、失败 envelope 或非完整 result 都归为 `incomplete_update` 并清除旧发布基线，调用前 validation / missing-cli 不清，使用受控 stdin 的错误也不回显正文。发布后只有文档身份、写操作返回 revision、回读 revision 一致且本地发送源未变化时才建立新基线，避免绑定错文档、旧 revision 或 claim 前通过正式路径提交的本地并发版本；持有旧文件描述符的 writer 仍需共享写锁或版本保留。

## 兼容与边界

- 合同 v1 继续可读；已有消费仓不批量重写，下次 design 定稿时生成 `project.yml`。
- build contract 仍为 v4，project.yml schema 仍为 v1；旧 v2/v3/v4 的 browser-smoke / visual / behavior evidence 和恢复状态无需迁移，新 build 才采用 browser-acceptance 与统一 runner。旧 v4 已在 `final_check` 且没有 runner audit 时按原状态直接落地，不倒灌 timing 字段。
- 不新增 decisions JSONL 或第二套状态机；context pack 只编译现有真相源。
- 目标规格在 design 定稿时生成；描述已落地现状的文档在 merge 后更新，不因文档失败回滚已落地主线实现。
- gstack 只是方法参考与可选证据生产工具，不成为 PMAI 的状态、决定或收尾权威。
- `/pmai-record`、`/pmai-quick-fix`、`/pmai-build-cancel`、`/pmai-status` 继续作为产品侧轻量旁路，不分叉完整 build 生命周期；`/pmai-doctor` 是按需框架诊断旁路，不进入正常产品循环。
- doctor finding 以 `kind / blocking` 区分 `framework_managed_sync`、`legacy_compatible`、`compatibility_declaration_required`、`project_content_invalid` 和 advisory；只有 blocking finding 进入 `consumer_invalid`。旧中文索引等顶层文档必须由标准索引明确链接，不能替代 `docs/INDEX.md`；非空目录不要求 `.gitkeep`，空白模块文档不能作为兼容证据。
- 当前只有 Codex 的精确当前会话定位链路已经验证；其他宿主没有可验证的精确会话标识或定位适配时，`/pmai-feedback` 必须阻断，不能按文件修改时间或“最近会话”猜测。

## 当前验证

- Harness 第一阶段安装所有权、初始化冲突、状态权威、ready/build 合同和 cancel 原子性 targeted tests 已通过：`42 passed / 0 failed`。
- 完整 `tests/run-all.sh` 已通过：`841 passed / 0 failed`；同一次入口另有 skill eval `6 passed / 0 failed / 17 session skipped`（17 项均因外部 session runner 未配置而显式跳过，不计作通过或失败）。本轮新增回归覆盖无 delta、单个 delta、多个 delta、真实相关输入变化、无关并行变化、旧 v1 currentness 恢复、新轮次 finalize/landing 与轮次级 audit 隔离；原有 doctor 只读 / repair / 敏感信息保护、消费仓兼容、宿主事务、build 生命周期、飞书、个人经验和其它回归继续通过。
- 开发态入口同步 helper 已在真实消费仓 `ExampleAgentProject` 只读 dogfood：返回 `stale / legacy_migration`，渲染计划可以确定识别旧 PMAI Startup，并保留“非小改动前读取产品现状”等项目补充及后续项目规则。消费仓在本轮分析期间又出现新的活跃模块状态，因此不再把其整体 error 数作为本次入口同步回归基线；运行前后 Git 状态一致，未修改消费仓或用户级安装。

## 下一步

- 继续用真实消费仓会话观察 active build 的小改能否稳定在 2–5 分钟内可刷新、交互改动能否稳定在 5–10 分钟内可刷新，以及定稿请求是否只触发一次隔离 production validation。
- 在 PM 确认分发后升级安装态，再用消费仓自然语言“启动看看 / 还有什么问题”验证各宿主自动注入；本轮只对 `ExampleAgentProject` 做了只读 dogfood，没有修改消费仓或用户级安装。
- 在真实消费仓 dogfood `/pmai-feedback`，核对完整会话复盘、问题归属和交接 Prompt 是否能直接驱动框架仓分析；再按宿主能力补充 Kimi Code、Claude Code 和 OpenCode 的精确当前会话定位适配，不提供猜测式降级。
- 在真实 Docx 规格上 dogfood `/pmai-lark-review`：覆盖正文直改、复杂格式 / 图片 / 引用、局部 / 全文评论、无 `solved_time`、active build accepted delta 和选择性 decision 归档；记录 collect / reconcile / 精细写回 / 评论收口的阶段耗时，确认机器路径进入 10–15 分钟。
- 后续框架修改继续先在开发分支完成 targeted / full regression，再进入 main 分发基线并升级全局安装副本。
