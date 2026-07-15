# RUNTIME

> 当前运行状态真相源。历史迁移流水账看 git history / `CHANGELOG.md` / `docs/归档/`，本文件只保留当前有效模型。

## 当前位置

- 日期：2026-07-15
- 开发分支：`codex/unified-build-lifecycle`
- 当前目标：v2 统一生命周期和 design 交互收口保持稳定；项目记忆 / 个人经验两层边界与用户级自动召回已完成实现和全量回归，作为当前开发分支候选基线。
- gstack 参考基线：`v1.58.5.0`，commit `11de390`；只参考本地 `gstack-clean` checkout，没有升级用户目录中的安装副本。

## 当前活跃模型

- 正常用户主链路：`/pmai-init-project` 只建上下文 → `/pmai-design` 讨论需求并在首次定稿时生成项目建造定义 → `/pmai-build` → PM 看结果多轮修改 → PM 明确定稿 → 自动最终检查、合入 main、主线后文档编译和一致性检查。
- `meta`、`mockup`、`spec-writing` 是 design 按需调用后返回主线的内部能力；仍保留手动入口用于兼容和专项使用，但不要求 PM 拼接命令。
- `/pmai-build-close` 只作为兼容与恢复入口；正常链路不再要求 PM 手动调用。
- lifecycle v2：`designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`。旧 `stage` 字段仅为 v1 消费仓兼容展示。
- 项目建造定义：初始化时不存在；首个达到 `ready_to_build` 的 design 将 `prototype / product`、技术栈、代码入口、真实命令和 Web 能力写入 `.pm-workflow/project.yml`。后续 build 只读该文件。
- 模块真相源：`docs/modules/<模块>/discussion.md`、`decisions.md`、`spec.md`；跨模块现行规则为 `PRODUCT-RULES.md`，项目级冻结理路为 `docs/decisions/`。
- 文档语义：`spec.md` / PRD 是指导研发实现的最终目标合同；`PRODUCT-STATE.md` 描述 main 已落地现状；原型、mockup 和代码只作设计 / 实现证据。
- design 的 `ready_to_build` 状态同时记录 approved source hash、design checkpoint 和精确目标路径；build 开工前重新编译上下文并验证 currentness，过期依据不能继续显示或进入构建。`.work-meta.json:build` 使用合同 v2，继续记录 build target、design revision、accepted deltas、implementation commit、required checks、证据和 docs status。
- 新 build 由 AI 推荐工作环境和构建工具，PM 只确认这两项；项目类型和验收方案不显示。选择当前环境时，main 只放行合同声明的目标路径。
- 记忆分两层：项目事实、决定和偏好继续由消费仓现有真相源承担；个人经验保存在用户级状态目录，跨项目召回但只作建议。个人经验不进入 context pack、项目 hash 或 Git，也不能自动修改 Skill。

## 已实现

- 新增 `context-pack.py`：design、build、恢复、最终检查和文档更新共用确定性上下文，并区分 active / superseded / 冲突决定、未决问题和输入 hash；项目定义存在时只从其中的 entrypoints 取实现上下文。
- 新增共用 `decision-policy`：机械项自动处理，可逆偏好给推荐并推进，产品模型岔路和 one-way door 立即让 PM 拍板；问句和讨论草稿不得成为决定。
- `build-contract.py` 升级为合同 v2：accepted delta 或新 implementation commit 会使旧证据失效；`validate-land` 拒绝 source hash / commit 不匹配的陈旧证据。
- 新增 prototype / product 验收 profile；iterating 只跑受影响快检，final_check 才跑完整 required checks。
- 新增 `project-definition.py` 和严格 schema validator；路径、类型、技术栈、Web 运行配置与 revision 变更全部 fail-closed。
- `project-type.py` 保留为兼容包装器：优先读新 `project.yml`，再读旧 config 和旧 `auto-detected: system` marker。
- 初始化脚本不再接收 project type，不创建代码、prototype、mockup 看板、dev server 或 gstack 依赖。
- 固定 build 审计编排和 coverage reviewer 已退出活跃链路；v2 只认 adaptive required checks/evidence。
- Web required checks 必须有 active browser-smoke；gstack 可由其它 browser/Playwright 适配器替代，但 v2 不能 exception 掉浏览器能力。
- builder profile 从自动最终选择改为“按项目定义、配置和可用性推荐 → PM 确认或调整”；验收 profile 仍后台生成，不进入开工卡。
- 新增自动 landing 和恢复：merge 冲突保留 `final_check` 与隔离环境；文档失败保留 `landed/docs_pending`，续跑不重复 merge。
- 新增 landed 后文档影响地图，要求对象、动作、状态、权限、页面、术语和受影响文件都有 covered 或明确 no-change。
- spec-writing landed 对账固定分为符合、accepted delta、漏实现、无依据实现；只有 accepted delta 修改规格目标，漏实现保留为实现缺口。
- design、meta、mockup、spec-writing、build、build-close 与消费仓 AGENTS / CLAUDE 模板已按统一链路重构。
- 新增 `evals/cases/*.json`、`evals/touchfiles.json` 和 `scripts/skill-eval.py`；静态案例可作为提交门，session runner / LLM judge 缺失时明确 skip，require 模式明确 fail。
- Codex 只暴露 `~/.codex/skills/pmai-*` 原生 skills；不再生成会在 Desktop 显示为 `prompts:pmai-*` 的 custom prompts。install / upgrade 清理旧 prompt 文件，doctor / status 不再生成或检查它们；Claude Code skills 与 OpenCode commands 保持原入口。
- design 直接必读 AskUser 共享规则，首题前收敛真实决策并报告总量，用业务结果提问；跨日、模型切换或会话恢复时重读当前 skill 与必读规则。context pack 消费后单独召回最多 3 条个人经验，高信号纠偏闭合后自动归位；项目事实回项目真相源，跨项目经验进入用户级存储，已有 Skill 规则未执行只留执行失败证据。跨模块设计只留下一个明确 build 入口，相同建造方案重复写入 `project.yml` 保持完整文件不变。
- context pack 对旧消费仓自动写入 Git 本地 exclude，不再制造未跟踪缓存；build 在创建环境前阻断批准目标路径上的既有脏改动，同时保留无关 WIP。
- context pack 只把 D 编号模块决定和真实产品规则编入 active；共同理由、否过方案、待复核、变更记录与注释模板不再伪装成决定，已确认标题也不再误报未决。

## 兼容与边界

- 合同 v1 继续可读；已有消费仓不批量重写，下次 design 定稿时生成 `project.yml`。
- 不新增 decisions JSONL 或第二套状态机；context pack 只编译现有真相源。
- 目标规格在 design 定稿时生成；描述已落地现状的文档在 merge 后更新，不因文档失败回滚已落地主线实现。
- gstack 只是方法参考与可选证据生产工具，不成为 PMAI 的状态、决定或收尾权威。
- `/pmai-record`、`/pmai-quick-fix`、`/pmai-build-cancel`、`/pmai-status` 继续作为轻量旁路，不分叉完整 build 生命周期。

## 当前验证

- 新增和改造的 context pack、acceptance profile、build contract、landing、文档影响地图、status、关键 Skill 路由、design 决策收敛、project definition 幂等与个人经验 targeted tests 已通过。
- 完整 `tests/run-all.sh` 已通过：`459 passed / 0 failed`。相比上一轮 `451 passed / 0 failed` 新增 8 条个人经验回归，覆盖缺库 fail-open、自动合并、执行失败归位、召回上限、取代 / 遗忘、使用反馈、项目权威隔离和 CLI 控制；原有 lifecycle 与 design 回归继续通过。

## 下一步

- 继续用真实消费仓会话观察 design 决策收敛、ready currentness、目标范围交接、长会话规则刷新和个人经验召回是否稳定。
- 后续框架修改继续先在开发分支完成 targeted / full regression，再进入 main 分发基线并升级全局安装副本。
