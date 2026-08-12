# PM-AI-Workflow（生成器）

**目的**：开发 PM AI 工作流框架的生成器。最终输出是一份给 PM 单人使用的 LLM 协作工作流模板。

**产品定位真相源**：[`PRODUCT.md`](./PRODUCT.md)。AI 判断流程取舍时必须按该文档：PMAI 是面向 PM 的产品上下文统一层，不是首版原型生成器；核心目标是统一产品文档、prototype / product、反馈、决定、验收和主线事实，并在 PM 定稿后自动落地主线、再整体编译正式文档。

**服务对象**：PM 单人生产力工具。不为团队 SOP 或基础设施设计。

**旧仓位置**：`<旧版 PMAI 仓库路径>`
**旧仓只作只读参考**，不复用其 stage / skill / hook / task-bootstrap 流程。本仓存在的目的就是重做一版，回避旧仓的设计问题。

**开发流程**：普通软件项目方式（讨论需求 → 设计 → 实现 → 测试 → 提交）。不导入旧框架的任何流程系统。

**当前状态 / 进度**：生成器骨架（scripts / skills / templates / tests）齐全，框架功能完整。**当前进度、测试基线、下一步一律见 [`RUNTIME.md`](./RUNTIME.md)「当前位置」** —— 单一真相源；本文件不复制版本号 / 基线数字 / 阶段细节，避免漂移。

**框架分发与全局安装**（2026-05-26 v1.1 落地）：

- 本仓现已通过 GitHub remote `git@github.com:YYG501/PMAI_Workflow.git` 分发
- `pmai install` 一次全局安装到 `~/.pmai/`，并把全部公开 Skill 链接到 `~/.claude/skills/pmai-*` 与 `~/.codex/skills/pmai-*`。Codex 不生成重复 custom prompts。
- **仅全局安装**：主控 Skill 只装 Claude Code / Codex host skill dirs，不往项目里拷副本；项目里只放主控配置 / 状态资产（`.claude/settings.json` / `.codex/hooks.json` / `.work-meta.json`）。Kimi Code、OpenCode 和 Cursor Agent 仅作为外部 Builder，不安装 PMAI 主控入口。旧 `--local`（项目实体副本）已移除；遗留副本用 `pmai uninstall --local <dir>` 清理。
- 升级 `pmai upgrade`（main）/ `pmai upgrade --stable`（tag）/ `pmai upgrade --to v0.x.0`（pin）
- 安装和升级以 `README.md`、`bin/pmai`、`bin/pmai-doctor` 为当前真相源。
- 老的手动同步 SOP：[`框架同步-SOP.md`](./docs/归档/废弃/框架同步-SOP.md) **DEPRECATED + 已归档**（pmai install/upgrade 承接；`pmai sync` 落地后彻底退役）

## 项目原则

- **不写死机器绑定路径**：框架代码、模板、skill 文档、prompt 示例和生成到消费仓的规则里，不得写死 `/Users/<某人>/...` 这类本地路径。需要定位文件时，用运行时变量（`PMAI_HOME` / `REPO_ROOT` / `MAIN_REPO_ROOT` / `BUILD_DIR`）和仓内相对路径组合；PM 上传本机材料时可临时读取其路径，但不得沉淀进框架规则或业务代码。

---

## review/audit 类 skill 执行强制约束

跑 `/plan-ceo-review` `/plan-eng-review` `/plan-design-review` `/plan-devex-review` `/review` `/qa` `/qa-only` `/design-review` `/devex-review` `/autoplan` 等 review/audit 类 skill 时：

1. **完整跑官方 skill 的所有 required sections**（11/11，不是 5/11）
2. **禁止给 PM 出"A 简化 / B 中等 / C 完整"程度门** —— 把"是否偷工"推给 PM 是反模式
3. **跳过项必须给具体"不适用"原因**：消费仓没基础设施 / 项目无该需求 算具体；"PM 偏好简单"/"务实"/"skill 太重" 不算
4. **输出末尾标完整度**：例 `## REVIEW COMPLETE: 11/11 sections` 或 `## REVIEW PARTIAL: 8/11 (跳过项 + 具体原因)`
5. **禁把 BLOCKER finding 降级 WARNING** 避免显得苛刻 —— 保留原 severity
6. 真有 section 不适用 → 默认跑完整版，跑完在完整度标记里写原因；PM 觉得多余事后会让你砍

每次触发上述 skill 时，[`hooks/review-skill-guard.cjs`](./hooks/review-skill-guard.cjs) 自动注入完整约束清单。Claude Code / Codex 的 hook 配置跟项目走（`.claude/settings.json` / `.codex/hooks.json`，git 跟踪）。Kimi/OpenCode 旧主控入口只保留诊断与清理兼容，不再安装、升级或用于新消费仓。

消费仓由 `scripts/init-project.sh` 自动生成 `.claude/settings.json` 与 `.codex/hooks.json`。项目级配置不会被全局升级静默改写：在消费仓运行 `pmai doctor --check` 做统一只读诊断；也可分别用 `install-project-hooks.sh --check` 和 `install-hooks.sh --check` 定位 Claude / Codex 与 Git hook 漂移。PM 确认后才运行对应安装器的不带 `--check` 模式刷新。Codex 首次看到新增 hook 时可能要求信任确认。

---

## 框架改动的文档同步

改动 `scripts/` / `skills/` / `templates/` / `hooks/`（会进入全局安装，并可能改变生成的消费仓入口或运行行为）时，**同一个 commit** 里要一并：

1. `CHANGELOG.md`「未发布」段加条目 —— 发布和升级时靠它判断影响范围
2. 视情况更新 `RUNTIME.md`「当前位置 / 下一步」（设计 / 实现进度有推进时）
3. 设计文档状态变「已落地」→ `git mv` 到 `docs/归档/完成/` 并更新 `docs/INDEX.md`

测试基线 / 当前状态 / 下一步只在 `RUNTIME.md`「当前位置」写一处；CLAUDE.md / README.md 只放指针，不复制数字 —— 别处再出现基线数字即是漂移。

[`hooks/check-doc-currency.cjs`](./hooks/check-doc-currency.cjs)（`.claude/settings.json` / `.codex/hooks.json` 注册的 PreToolUse(Bash) hook）在 `git commit` 时检查：动了框架资产但 CHANGELOG 没进本次提交 → 拦下并把提醒喂回。纯生成器内部改动（注释 / 测试微调 / 本仓自身工作流）确实不需要动文档时，commit message 加 `[skip-doc-check]` 跳过。

---

## 产品主链与文档边界

- 正常主链是 `init → proposal → design → spec-writing → build`。`spec-writing` 通常由 design 在决定闭合后自动调用，不要求 PM 手工编排。
- 新项目初始化后默认进入完整 Product Proposal；成熟项目只有在定位、用户、核心问题与价值、产品边界、MVP / 当前产品结果已经构成完整等价基线，且 `PRODUCT.md` 显式记录真实仓内依据与 PM 确认日期、`PRODUCT.md` 与依据均已提交且无漂移、机器状态为 `equivalent_baseline` 时才可跳过。
- 一旦进入 Proposal，必须生成可独立评审的完整版本。已确认 Proposal 只供下游读取；产品方向变化由 `/pmai-proposal` 新建完整版本并 supersede 旧版，design、spec-writing、build、doc-writing 和 record 都不得原地修改。
- 产品方向变化回 Proposal；模块对象、规则、任务路径、权限或关键交互变化回 design；`/pmai-record` 只在没有 active work 时补录已经确认的待办、术语、跨模块规则、项目理路或有 main 证据的现状纠错。
- spec-writing 的内容模型是“通用内容模块 + 可叠加 Profile”，文档形态由 Preset 决定。企业平台与 AI 产品分别加载对应 Profile，企业 AI 平台叠加两者；完整 PRD 使用唯一完整 PRD Preset，不另造企业 AI 平台专用 Profile 或第二套真相源。

---

## Session 起始播报（M5 / D-iv M1 vp-11）

**PM 第一条 message 后（任何内容），AI 必须先跑** `python3 "$HOME/.pmai/scripts/status-view.py" --narrative` **输出播报**，再回应 PM 的具体请求。

- **触发**：每个新 chat session 的 PM 第一条 user message。**AI 不会在 PM 没说话前自动播报**（LLM chat 模型固有限制；codex C-3 校准）。
- **目的**：PM 切窗口 / 隔天回来时不用主动问"我在哪"，AI 主动结构化报告当前 active work / 当前模块 / 下一步建议。
- **数据源**：`status-view.py --narrative` 内部走 `.work-meta.json` + `_lib.state.get_overall_state()`，严格基于现有字段；不写小节级、commit hash 全文或相对时间这种伪精确内容。
- **失败兜底**：未初始化目录由 `status-view.py` 先提示 `/pmai-init-project`；已初始化但无 active work 时，按 Proposal 合同给唯一下一步：新项目方向待澄清则提示 `/pmai-proposal`，已有当前 Proposal 或完整等价产品基线才提示 `/pmai-design`，**不编造**。

**生成器仓 vs 业务仓**：本规则只在业务仓有 `.work-meta.json` 时生效；生成器仓自己开发跑无意义（没有 PM 视图 active work），跳过即可。

播报示例：

```
当前没有 active work。
下一步：先按当前 Proposal 状态继续 /pmai-proposal 或 /pmai-design；需要只读恢复产品现状时发 /pmai-status。
```

PM 视图规则约束：见 `_shared/PM-VIEW-RULES.md` + `_shared/pm-view/banner-rules.md`（M2 banner / Decision gate label）+ `_shared/pm-view/askuser-rules.md`（M4 AskUser 答题规则）。
