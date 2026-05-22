# PM-AI-Workflow（生成器）

**目的**：开发 PM AI 工作流框架的生成器。最终输出是一份给 PM 单人使用的 LLM 协作工作流模板。

**服务对象**：PM 单人生产力工具。不为团队 SOP 或基础设施设计。

**旧仓位置**：`${LEGACY_REPO_ROOT}`
**旧仓只作只读参考**，不复用其 stage / skill / hook / task-bootstrap 流程。本仓存在的目的就是重做一版，回避旧仓的设计问题。

**开发流程**：普通软件项目方式（讨论需求 → 设计 → 实现 → 测试 → 提交）。不导入旧框架的任何流程系统。

**当前状态 / 进度**：生成器骨架（scripts / skills / templates / tests）齐全，框架功能完整。**当前进度、测试基线、下一步一律见 [`RUNTIME.md`](./RUNTIME.md)「当前位置」** —— 单一真相源；本文件不复制版本号 / 基线数字 / 阶段细节，避免漂移。

**主仓改完后同步到目标项目**：手动 SOP 见 [`框架同步-SOP.md`](./框架同步-SOP.md)（hotfix 阶段过渡，框架结构稳定后改自动化）。

---

## review/audit 类 skill 执行强制约束

跑 `/plan-ceo-review` `/plan-eng-review` `/plan-design-review` `/plan-devex-review` `/review` `/qa` `/qa-only` `/design-review` `/devex-review` `/autoplan` 等 review/audit 类 skill 时：

1. **完整跑官方 skill 的所有 required sections**（11/11，不是 5/11）
2. **禁止给 PM 出"A 简化 / B 中等 / C 完整"程度门** —— 把"是否偷工"推给 PM 是反模式
3. **跳过项必须给具体"不适用"原因**：消费仓没基础设施 / 项目无该需求 算具体；"PM 偏好简单"/"务实"/"skill 太重" 不算
4. **输出末尾标完整度**：例 `## REVIEW COMPLETE: 11/11 sections` 或 `## REVIEW PARTIAL: 8/11 (跳过项 + 具体原因)`
5. **禁把 BLOCKER finding 降级 WARNING** 避免显得苛刻 —— 保留原 severity
6. 真有 section 不适用 → 默认跑完整版，跑完在完整度标记里写原因；PM 觉得多余事后会让你砍

每次触发上述 skill 时，[`hooks/review-skill-guard.cjs`](./hooks/review-skill-guard.cjs) 通过 `.claude/settings.json` 注册的 UserPromptSubmit hook 自动注入完整约束清单。**hook 跟项目走（git 跟踪），换机器 clone 即生效；不依赖全局 `~/.claude/`**。

消费仓如果想享受同款保护：把 `hooks/review-skill-guard.cjs` + `.claude/settings.json` 的 hook 注册段复制过去即可（路径用 `$CLAUDE_PROJECT_DIR`，无需改）。后续考虑放进 `scripts/init-project.sh` 自动分发。

---

## 框架改动的文档同步

改动 `scripts/` / `skills/` / `templates/` / `agents/`（会同步到业务仓的内容）时，**同一个 commit** 里要一并：

1. `CHANGELOG.md`「未发布」段加条目 —— 业务仓靠它决定是否跑同步流程
2. 视情况更新 `RUNTIME.md`「当前位置 / 下一步」（设计 / 实现进度有推进时）
3. 设计文档状态变「已落地」→ `git mv` 到 `docs/归档/完成/` 并更新 `docs/INDEX.md`

测试基线 / 当前状态 / 下一步只在 `RUNTIME.md`「当前位置」写一处；CLAUDE.md / README.md 只放指针，不复制数字 —— 别处再出现基线数字即是漂移。

[`hooks/check-doc-currency.cjs`](./hooks/check-doc-currency.cjs)（`.claude/settings.json` 注册的 PreToolUse hook）在 `git commit` 时检查：动了框架资产但 CHANGELOG 没进本次提交 → 拦下并把提醒喂回。纯生成器内部改动（注释 / 测试微调 / 本仓自身工作流）确实不需要动文档时，commit message 加 `[skip-doc-check]` 跳过。
