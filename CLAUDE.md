# PM-AI-Workflow（生成器）

**目的**：开发 PM AI 工作流框架的生成器。最终输出是一份给 PM 单人使用的 LLM 协作工作流模板。

**服务对象**：PM 单人生产力工具。不为团队 SOP 或基础设施设计。

**旧仓位置**：`${LEGACY_REPO_ROOT}`
**旧仓只作只读参考**，不复用其 stage / skill / hook / task-bootstrap 流程。本仓存在的目的就是重做一版，回避旧仓的设计问题。

**开发流程**：普通软件项目方式（讨论需求 → 设计 → 实现 → 测试 → 提交）。不导入旧框架的任何流程系统。

**当前状态**：v3.5 实施全部收口（阶段 1 + 2 + 3 + 4 + 4.5a-f；5/6/7/8/9 废弃/跳过）。生成器骨架（scripts / skills / templates / tests）齐全，269 单测 0 失败。下一步重点是端到端验证（拿生成器跑通真实项目）+ 后续基于实证决定 TODOS 里的 TD-1/2/3/4 探测档延迟项。

**v3.5 实施进度 / 当前位置**：见 [`RUNTIME.md`](./RUNTIME.md)（运行时状态 / 新窗口续接入口；进度跟踪 + 已知坑 + 下一步指针）。

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
