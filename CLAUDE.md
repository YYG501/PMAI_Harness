# PM-AI-Workflow（生成器）

**目的**：开发 PM AI 工作流框架的生成器。最终输出是一份给 PM 单人使用的 LLM 协作工作流模板。

**产品定位真相源**：[`PRODUCT.md`](./PRODUCT.md)。AI 判断流程取舍时必须按该文档：PMAI 是面向 PM 的产品上下文统一层，不是首版原型生成器；核心目标是统一产品文档、原型、反馈和决策上下文，并在原型确认后反向沉淀可评审 PRD / decision packet。

**服务对象**：PM 单人生产力工具。不为团队 SOP 或基础设施设计。

**旧仓位置**：`${LEGACY_REPO_ROOT}`
**旧仓只作只读参考**，不复用其 stage / skill / hook / task-bootstrap 流程。本仓存在的目的就是重做一版，回避旧仓的设计问题。

**开发流程**：普通软件项目方式（讨论需求 → 设计 → 实现 → 测试 → 提交）。不导入旧框架的任何流程系统。

**当前状态 / 进度**：生成器骨架（scripts / skills / templates / tests）齐全，框架功能完整。**当前进度、测试基线、下一步一律见 [`RUNTIME.md`](./RUNTIME.md)「当前位置」** —— 单一真相源；本文件不复制版本号 / 基线数字 / 阶段细节，避免漂移。

**框架分发与全局安装**（2026-05-26 v1.1 落地）：

- 本仓现已通过 GitHub remote `git@github.com:YYG501/PMAI_Workflow.git` 分发
- `pmai install` 一次全局安装到 `~/.pmai/` + symlink 当前 skill 到 `~/.claude/skills/pmai-*` / `~/.codex/skills/pmai-*`（任意 cwd 可调 `/pmai-init-project`）
- **仅全局安装**：skill 只装 host skill dirs，不往项目里拷副本；项目里只放 host 配置 / 状态资产（`.claude/settings.json` / `.codex/hooks.json` / `.work-meta.json`）。旧 `--local`（项目实体副本）已移除——和全局并存会让 `/pmai-*` 命令重复且副本陈旧；遗留副本用 `pmai uninstall --local <dir>` 清理
- 升级 `pmai upgrade`（main）/ `pmai upgrade --stable`（tag）/ `pmai upgrade --to v0.x.0`（pin）
- 安装和升级以 `README.md`、`bin/pmai`、`bin/pmai-doctor` 为当前真相源。
- 老的手动同步 SOP：[`框架同步-SOP.md`](./docs/归档/废弃/框架同步-SOP.md) **DEPRECATED + 已归档**（pmai install/upgrade 承接；`pmai sync` 落地后彻底退役）

---

## review/audit 类 skill 执行强制约束

跑 `/plan-ceo-review` `/plan-eng-review` `/plan-design-review` `/plan-devex-review` `/review` `/qa` `/qa-only` `/design-review` `/devex-review` `/autoplan` 等 review/audit 类 skill 时：

1. **完整跑官方 skill 的所有 required sections**（11/11，不是 5/11）
2. **禁止给 PM 出"A 简化 / B 中等 / C 完整"程度门** —— 把"是否偷工"推给 PM 是反模式
3. **跳过项必须给具体"不适用"原因**：消费仓没基础设施 / 项目无该需求 算具体；"PM 偏好简单"/"务实"/"skill 太重" 不算
4. **输出末尾标完整度**：例 `## REVIEW COMPLETE: 11/11 sections` 或 `## REVIEW PARTIAL: 8/11 (跳过项 + 具体原因)`
5. **禁把 BLOCKER finding 降级 WARNING** 避免显得苛刻 —— 保留原 severity
6. 真有 section 不适用 → 默认跑完整版，跑完在完整度标记里写原因；PM 觉得多余事后会让你砍

每次触发上述 skill 时，[`hooks/review-skill-guard.cjs`](./hooks/review-skill-guard.cjs) 通过 `.claude/settings.json` / `.codex/hooks.json` 注册的 UserPromptSubmit hook 自动注入完整约束清单。**hook 配置跟项目走（git 跟踪），脚本本体来自本仓或已安装的 `~/.pmai/`；不依赖全局 `~/.claude/`**。

消费仓由 `scripts/init-project.sh` 自动生成 `.claude/settings.json` 和 `.codex/hooks.json`。已有 I-mini 消费仓缺 Codex hooks 时，在项目根运行 `bash ~/.pmai/scripts/install-codex-hooks.sh` 补装；Codex 首次看到新增 hook 时可能要求信任确认。

---

## 框架改动的文档同步

改动 `scripts/` / `skills/` / `templates/` / `agents/`（会同步到业务仓的内容）时，**同一个 commit** 里要一并：

1. `CHANGELOG.md`「未发布」段加条目 —— 业务仓靠它决定是否跑同步流程
2. 视情况更新 `RUNTIME.md`「当前位置 / 下一步」（设计 / 实现进度有推进时）
3. 设计文档状态变「已落地」→ `git mv` 到 `docs/归档/完成/` 并更新 `docs/INDEX.md`

测试基线 / 当前状态 / 下一步只在 `RUNTIME.md`「当前位置」写一处；CLAUDE.md / README.md 只放指针，不复制数字 —— 别处再出现基线数字即是漂移。

[`hooks/check-doc-currency.cjs`](./hooks/check-doc-currency.cjs)（`.claude/settings.json` / `.codex/hooks.json` 注册的 PreToolUse(Bash) hook）在 `git commit` 时检查：动了框架资产但 CHANGELOG 没进本次提交 → 拦下并把提醒喂回。纯生成器内部改动（注释 / 测试微调 / 本仓自身工作流）确实不需要动文档时，commit message 加 `[skip-doc-check]` 跳过。

---

## Session 起始播报（M5 / D-iv M1 vp-11）

**PM 第一条 message 后（任何内容），AI 必须先跑** `bash .claude/scripts/status-view.py --narrative` **输出播报**，再回应 PM 的具体请求。

- **触发**：每个新 chat session 的 PM 第一条 user message。**AI 不会在 PM 没说话前自动播报**（LLM chat 模型固有限制；codex C-3 校准）。
- **目的**：PM 切窗口 / 隔天回来时不用主动问"我在哪"，AI 主动结构化报告当前 active work / 当前模块 / 下一步建议。
- **数据源**：`status-view.py --narrative` 内部走 `.work-meta.json` + `_lib.state.get_overall_state()`，严格基于现有字段；不写小节级、commit hash 全文或相对时间这种伪精确内容。
- **失败兜底**（无 active work）：直接输出"目前没有 active work。可以发 /pmai-design 起一个模块工作，或发 /pmai-init-project 起新项目"，**不编造**。

**生成器仓 vs 业务仓**：本规则只在业务仓有 `.work-meta.json` 时生效；生成器仓自己开发跑无意义（没有 PM 视图 active work），跳过即可。

播报示例：

```
当前没有 active work。
下一步：发 /pmai-design 起一个模块工作，或发 /pmai-status 查看产品现状。
```

PM 视图规则约束：见 `_shared/PM-VIEW-RULES.md` + `_shared/pm-view/banner-rules.md`（M2 banner / Decision gate label）+ `_shared/pm-view/askuser-rules.md`（M4 AskUser 答题规则）。
