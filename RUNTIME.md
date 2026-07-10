# RUNTIME

> 当前运行状态真相源。历史迁移流水账看 git history / `CHANGELOG.md` / `docs/归档/`，本文件只保留当前有效模型。

## 当前位置

- 日期：2026-07-10
- 开发分支：`codex/unified-build-lifecycle`
- 当前目标：统一构建链路已按最新 PM 反馈收口到“项目类型项目级定义、默认验收后台化、只确认环境与工具”，实现与验证已完成；等待决定是否分发。
- gstack 参考基线：`v1.58.5.0`，commit `11de390`；只参考本地 `gstack-clean` checkout，没有升级用户目录中的安装副本。

## 当前活跃模型

- 正常用户主链路：`/pmai-design` 讨论并形成建造依据 → `/pmai-build` 构建指定对象 → PM 看结果多轮修改 → PM 明确定稿 → 自动最终检查、合入 main、主线后文档编译和一致性检查。
- `meta`、`mockup`、`spec-writing` 是 design 按需调用后返回主线的内部能力；仍保留手动入口用于兼容和专项使用，但不要求 PM 拼接命令。
- `/pmai-build-close` 只作为兼容与恢复入口；正常链路不再要求 PM 手动调用。
- lifecycle v2：`designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`。旧 `stage` 字段仅为 v1 消费仓兼容展示。
- build target：项目初始化时在 `.pm-workflow/config.yml:project.type` 定义 `prototype` 或 `product`；每次 build 只读，不按本轮需求推断，生命周期相同，只切换后台验收适配器。
- 模块真相源：`docs/modules/<模块>/discussion.md`、`decisions.md`、`spec.md`；跨模块现行规则为 `PRODUCT-RULES.md`，项目级冻结理路为 `docs/decisions/`。
- `.work-meta.json:build` 使用合同 v2，记录 build target、approved source hash、design revision、accepted deltas、implementation commit、required checks、证据和 docs status。
- 新 build 由 AI 推荐工作环境和构建工具，PM 只确认这两项；项目类型和验收方案不显示。选择当前环境时，main 只放行合同声明的目标路径。

## 已实现

- 新增 `context-pack.py`：design、build、恢复、最终检查和文档更新共用确定性上下文，并区分 active / superseded / 冲突决定、未决问题和输入 hash。
- 新增共用 `decision-policy`：机械项自动处理，可逆偏好给推荐并推进，产品模型岔路和 one-way door 立即让 PM 拍板；问句和讨论草稿不得成为决定。
- `build-contract.py` 升级为合同 v2：accepted delta 或新 implementation commit 会使旧证据失效；`validate-land` 拒绝 source hash / commit 不匹配的陈旧证据。
- 新增 prototype / product 验收 profile；iterating 只跑受影响快检，final_check 才跑完整 required checks。
- 新增 `project-type.py`：读取项目级类型并兼容旧 `CLAUDE.md` marker；新项目初始化只接受 `prototype / product`，`product` 在内部复用 system 工程结构模板。
- builder profile 从自动最终选择改为“按配置和可用性推荐 → PM 确认或调整”；验收 profile 仍后台生成，不进入开工卡。
- 新增自动 landing 和恢复：merge 冲突保留 `final_check` 与隔离环境；文档失败保留 `landed/docs_pending`，续跑不重复 merge。
- 新增 landed 后文档影响地图，要求对象、动作、状态、权限、页面、术语和受影响文件都有 covered 或明确 no-change。
- design、meta、mockup、spec-writing、build、build-close 与消费仓 AGENTS / CLAUDE 模板已按统一链路重构。
- 新增 `evals/cases/*.json`、`evals/touchfiles.json` 和 `scripts/skill-eval.py`；静态案例可作为提交门，session runner / LLM judge 缺失时明确 skip，require 模式明确 fail。

## 兼容与边界

- 合同 v1 继续可读；已有消费仓不批量重写，下次 design / build 时渐进进入 v2。
- 不新增 decisions JSONL 或第二套状态机；context pack 只编译现有真相源。
- 正式文档不在 merge 前更新，不因文档失败回滚已落地主线实现。
- gstack 只是方法参考与可选证据生产工具，不成为 PMAI 的状态、决定或收尾权威。
- `/pmai-record`、`/pmai-quick-fix`、`/pmai-build-cancel`、`/pmai-status` 继续作为轻量旁路，不分叉完整 build 生命周期。

## 当前验证

- 新增和改造的 context pack、acceptance profile、build contract、landing、文档影响地图、status、关键 Skill 路由与 skill-eval targeted tests 已通过。
- 完整 `tests/run-all.sh` 已通过：`465 passed / 0 failed`。

## 下一步

- 如需分发，推送当前分支并合入 main。
- 合入后再升级用户目录中的 PMAI 安装副本；当前没有执行该动作。
