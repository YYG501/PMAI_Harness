# RUNTIME

> 当前运行状态真相源。历史迁移流水账看 git history / `CHANGELOG.md` / `docs/归档/`，本文件只保留当前有效模型。

## 当前位置

- 日期：2026-07-12
- 开发分支：`codex/unified-build-lifecycle`
- 当前目标：v2 口径统一与项目建造定义重构已完成实现和全量回归，等待 PM 决定是否提交与分发。
- gstack 参考基线：`v1.58.5.0`，commit `11de390`；只参考本地 `gstack-clean` checkout，没有升级用户目录中的安装副本。

## 当前活跃模型

- 正常用户主链路：`/pmai-init-project` 只建上下文 → `/pmai-design` 讨论需求并在首次定稿时生成项目建造定义 → `/pmai-build` → PM 看结果多轮修改 → PM 明确定稿 → 自动最终检查、合入 main、主线后文档编译和一致性检查。
- `meta`、`mockup`、`spec-writing` 是 design 按需调用后返回主线的内部能力；仍保留手动入口用于兼容和专项使用，但不要求 PM 拼接命令。
- `/pmai-build-close` 只作为兼容与恢复入口；正常链路不再要求 PM 手动调用。
- lifecycle v2：`designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`。旧 `stage` 字段仅为 v1 消费仓兼容展示。
- 项目建造定义：初始化时不存在；首个达到 `ready_to_build` 的 design 将 `prototype / product`、技术栈、代码入口、真实命令和 Web 能力写入 `.pm-workflow/project.yml`。后续 build 只读该文件。
- 模块真相源：`docs/modules/<模块>/discussion.md`、`decisions.md`、`spec.md`；跨模块现行规则为 `PRODUCT-RULES.md`，项目级冻结理路为 `docs/decisions/`。
- 文档语义：`spec.md` / PRD 是指导研发实现的最终目标合同；`PRODUCT-STATE.md` 描述 main 已落地现状；原型、mockup 和代码只作设计 / 实现证据。
- `.work-meta.json:build` 使用合同 v2，记录 build target、approved source hash、design revision、accepted deltas、implementation commit、required checks、证据和 docs status。
- 新 build 由 AI 推荐工作环境和构建工具，PM 只确认这两项；项目类型和验收方案不显示。选择当前环境时，main 只放行合同声明的目标路径。

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

## 兼容与边界

- 合同 v1 继续可读；已有消费仓不批量重写，下次 design 定稿时生成 `project.yml`。
- 不新增 decisions JSONL 或第二套状态机；context pack 只编译现有真相源。
- 目标规格在 design 定稿时生成；描述已落地现状的文档在 merge 后更新，不因文档失败回滚已落地主线实现。
- gstack 只是方法参考与可选证据生产工具，不成为 PMAI 的状态、决定或收尾权威。
- `/pmai-record`、`/pmai-quick-fix`、`/pmai-build-cancel`、`/pmai-status` 继续作为轻量旁路，不分叉完整 build 生命周期。

## 当前验证

- 新增和改造的 context pack、acceptance profile、build contract、landing、文档影响地图、status、关键 Skill 路由与 skill-eval targeted tests 已通过。
- 完整 `tests/run-all.sh` 已通过：`444 passed / 0 failed`。用例数下降来自固定审计链、工程结构探测/注入资产及其测试的正式退役，不是漏跑；本轮新增规格目标 currentness 回归。

## 下一步

- 当前工作树尚未提交、未 push、未发布，也没有修改用户目录中的 PMAI 安装副本。
- PM 确认后再单独决定 commit、合入 main 与隔离分发；installed upgrade 仍是后续独立动作。
