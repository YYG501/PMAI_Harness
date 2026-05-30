# GSD 参考调研笔记

> 调研对象：`<LOCAL_HOME>/Desktop/Projects/gsd-ref/`（get-shit-done-cc，一个 npm 包形态的 spec-driven AI 工作流框架）
> 调研目的：对照 PM-AI-Workflow 当前设计，找出可借鉴的机制和应该保留的差异
> 调研日期：2026-05-19
> 调研触发：PM 思考 "solution 做厚 vs 做薄" 时希望参考 GSD 怎么处理

---

## 一、一句话结论

GSD 跟 PM-AI-Workflow **定位高度相似**（README L.56-67 作者明说"单人开发者工具、反对 50 人工程组织那套"），但在两个独立维度上做了不同选择：

| 取舍维度 | GSD | PM-AI-Workflow |
|---|---|---|
| 任务拓扑要不要显式维护 | ✅ ROADMAP.md 是核心抓手 | ❌ 不维护，需求来一个做一个 |
| 技术设计资产要不要长期沉淀 | ❌ phase 级即用即弃 | ✅ DESIGN.md + docs/modules/ 项目级长期沉淀 |

GSD 强在「**把任务流当一等公民**」；PM-AI-Workflow 强在「**把产品设计资产当一等公民**」。

两者**都有业务上下文**（GSD 的 PROJECT.md ≈ PM-AI 的 CLAUDE.md / docs/prd.md），**都支持迭代加新单位**。

---

## 二、层级对应

### 项目级层级

| GSD | PM-AI-Workflow | 状态 |
|---|---|---|
| ROADMAP.md（phase 拓扑）+ REQUIREMENTS.md | — | PM-AI 没有，**不需要补**（上下文驱动场景） |
| Milestone（一次迭代的容器） | — | PM-AI 没有，**未来大模块时可能需要** |
| PROJECT.md（业务上下文） | CLAUDE.md / docs/prd.md | 都有，角色对应 |
| — | DESIGN.md（项目级视觉规范） | PM-AI 独有，**GSD 完全没有** |
| — | docs/modules/（模块规格沉淀） | PM-AI 独有，**GSD 完全没有** |
| codebase/architecture.md（map-codebase 产物） | — | 0→1 项目用，PM-AI 用 N→N+1 模式不需要 |

### 一个工作单位内的层级

| GSD | PM-AI-Workflow | 备注 |
|---|---|---|
| phase | **req** | 角色对应 |
| discuss-phase（灰色地带决策） | **req-analysis**（含强制 analysis-reviewer） | PM-AI 拆得更细，多 reviewer 防御 |
| （并入 plan-phase） | **req-solution**（PM 视图 + 工程合同双文件） | PM-AI 独立成一层 |
| plan-phase（任务拆分）| **task-plan**（含反模式 5 条自检 + GAP 编号） | 对应 |
| （并入 plan-phase 的 plan 列表）| **task-spec**（PM 视图 + 工程合同 + 引用） | PM-AI 独立成一层 |
| — | **task-confirm**（启动前确认门） | PM-AI 独有 |
| execute-phase | **task-execute** | 对应 |
| verify-work | （并入 close-req）| GSD 单独，PM-AI 合并 |
| complete-milestone / ship | **close-req** | 对应 |

**关键差异**：PM-AI 把 GSD 的 3 层（discuss + plan + execute）拆成 6 层。决策点更密集 = PM 介入更多 = 流程更慢但更可控。跟 [[feedback_pm_decision_is_binding_contract]] 一致。

---

## 三、Skill 数量对照

| | GSD | PM-AI-Workflow |
|---|---|---|
| 命令/skill 数 | 67 commands + 90 workflows | 19 skills |
| 体量 | 重 | 轻 |
| 适用场景 | 项目从 0→1 全周期 | PM 单人在已有产品上迭代 |

GSD 80% 的命令是 PM-AI 场景**不需要**的：
- 探索类（explore / sketch / spike / capture / map-codebase / extract-learnings / ingest-docs / profile-user）
- 0→1 专门 phase（mvp-phase / ai-integration-phase / secure-phase / ui-phase / validate-phase / ultraplan-phase）
- 评审命令式（PM-AI 用 hook 注入约束更鲁棒）
- 知识图谱（graphify）
- 多工作流编排（thread / inbox / pause-work / resume-work — PM-AI 的 worktree 模式部分覆盖）
- ns-* 路由系统（19 个 skill 不需要分 namespace）

---

## 四、真正值得借鉴的 6 个 GSD 命令

剔除场景用不上的，真正值得参考的：

| GSD 命令 | 给 PM-AI 的启发 | 优先级 |
|---|---|---|
| **manager** | 多 task/req 仪表板（dashboard + 后台 agent + 60 秒自动刷新 + blocker 自动暴露 + 错误分类） | 🔥 高 |
| **audit-milestone** | 多 task close 后的跨 task 集成审查（PM-AI 当前 close-req 没有这层） | 🔥 高 |
| **autonomous** | 多 stage 自动跑完（PM-AI 的 req-stage-gate 续跑模式部分对应） | 中 |
| **resume-work / pause-work** | 跨会话上下文恢复（worktree 已部分实现） | 中 |
| **forensics** | 失败 workflow 事后诊断 | 低 |
| **extract-learnings** | 已完成 req 提取经验沉淀 | 低 |

---

## 五、PM-AI-Workflow 独有的能力（要保留，不被 GSD 牵走）

### 5.1 DESIGN.md + docs/modules/（GSD 完全没有）

GSD 是 phase 级 UI-SPEC（即用即弃，跨 phase 一致性靠手动参考前 phase）。

PM-AI 的项目级 DESIGN.md + docs/modules/ 是**核心资产**，example-consumer-app 这种长期演进的内部系统离不开这套。**不要为了向 GSD 看齐而砍掉**。

### 5.2 hook 式评审防御（比 GSD 命令式更鲁棒）

- GSD: PM 主动调用 `/code-review` `/ui-review`
- PM-AI: `review-skill-guard.cjs` 通过 UserPromptSubmit hook 自动注入完整 11/11 约束，AI 无法绕过偷工

跟 [[feedback_skill_must_actually_invoke]] / [[feedback_skill_reading_convergence]] 一脉相承。

### 5.3 多层 reviewer + stage gate

- analysis-reviewer 自定义 subagent（[[project_stage2_reviewer]]）
- req-stage-gate 续跑模式
- task-confirm 启动前确认门
- 未决问题强制闸门（[[feedback_open_questions_gate]]）

GSD 没有这层"决策强制暴露"机制。

### 5.4 PM 视图 + 工程合同双文件契约

- solution.md（PM 视图）+ solution.engineering.md（工程合同）
- task.md（PM 视图）+ task.engineering.md（工程合同）
- 双文件 lazy sync via hash + 引用代替重审（[[feedback_skill_reading_convergence]]）

GSD 是单文件 CONTEXT.md / PLAN.md，没有这层 PM/工程分离。

### 5.5 中文 PM 场景 + 飞书集成

- publish-to-lark + lark-* 整套
- 中文术语 / PM 视图禁工程黑话（[[feedback_pm_chat_no_engineering_jargon]]）

GSD 完全英文场景，无对应。

---

## 六、关键洞察

### 6.1 上下文驱动 ≠ 不维护上下文

之前推测"GSD 不维护项目上下文"是错的。GSD **有 PROJECT.md**（持续维护的业务上下文），还有三个明确更新触发点：
- phase transition 后：需求从 Active 移到 Validated
- milestone 完成后：完整重审 PROJECT.md
- 代码库更新后：项目状态和决策变化

**两者的区别不在"维护不维护上下文"，在"维护什么类型的上下文"**：
- GSD: 业务上下文（PROJECT.md）+ 任务拓扑（ROADMAP.md）
- PM-AI: 业务上下文（CLAUDE.md）+ 技术设计资产（DESIGN.md + docs/modules/）

### 6.2 GSD 也支持动态加 phase（之前推断错了）

`add-phase.md` + `autonomous.md` L.3 明确支持运行时动态加 phase / phase 重读。GSD 不是"一次拆完干完"的流水线。

### 6.3 真正的痛点在落地阶段的基础设施

PM 真正缺的不是新概念（roadmap / milestone / wave），是落地阶段的**基础设施**：

| 缺口 | 影响 |
|---|---|
| dashboard | PM 必须实时盯 task 进度 |
| 后台 agent | task 是 inline 跑，PM 无法离开 |
| blocker 自动暴露 | AI 可能静默吞掉灰色地带 |
| 验收 AI 自演替身 | PM 必须手点 14 GAP |

补这 4 件能让 PM 从"每 task 盯一次"减到"开 dashboard 出问题手机震"。**这才是 PM 真正要的"轻介入"形态**。

### 6.4 solution 厚薄不是关键，req 粒度才是

PM 担心"大模块 solution 会膨胀" → 根因是 **req 粒度太大**，不是 solution 写法。

GSD 的 granularity 配置（coarse 3-5 phase / standard 5-8 / fine 8-12）就是在控制 phase/req 粒度。PM-AI 可以参考引入 **req 粒度判据**（比如 solution 超过 1-2 屏 / 验收 GAP 超过 15 条 → 该拆）。

### 6.5 借鉴机制不要照搬形式

GSD 是给"写代码场景"的（作者 "I don't write code"）。PM-AI-Workflow 还有产品决策 / 原型档 / 中文 PM 沟通 / 飞书集成这些 GSD 没有的诉求。

借鉴**机制**（分层失效协议 / dashboard / blocker 协议 / 模块文档触发更新），不要照搬**形式**（命令名 / 文档名 / 67 个命令的体量）。

---

## 七、下一步可行动项

按 PM 真实痛点排序：

1. **跑一次 GSD**（在独立空仓里）—— 验证 dashboard / autonomous / manager 的真实体感（PM 已倾向先实操再决策）
2. **补 manager 等价物**（多 task 仪表板 + 后台 agent + blocker 自动暴露）—— PM 真正缺的落地基础设施
3. **补 audit-milestone 等价物**（多 task close 后跨 task 集成审查）—— 当前 close-req 缺这层
4. **建立 solution → task 失效协议**（参考 GSD 的 has_plans=true → 强制 replan 机制）—— 当前手动 SOP，可自动化
5. **建立 req 粒度判据**（参考 GSD granularity 控制）—— 大模块来时不会一头扎进超大 req
6. **未来大模块时再决定要不要 Milestone 层** —— 现在留口子（.req-meta.json 加 milestone 字段），不提前实现

---

## 八、关联记忆

- [[project_stage2_reviewer]] — analysis-reviewer 是 PM-AI 独有的防御性 reviewer
- [[feedback_skill_must_actually_invoke]] — review skill 必须真发起调用，对应 GSD 缺的 hook 防御
- [[feedback_pm_decision_is_binding_contract]] — PM-AI 6 层决策点拆分的设计动因
- [[feedback_skill_reading_convergence]] — 双文件 PM 视图 + 工程合同的契约依据
- [[feedback_pm_chat_no_engineering_jargon]] — PM-AI 中文 PM 场景，区别于 GSD 英文工程师场景
- [[project_d13_in_progress]] — hook 注入约束机制的来源

---

## 九、调研覆盖范围

本笔记覆盖：
- ✅ GSD 6 命令主循环（new-project / discuss-phase / plan-phase / execute-phase / verify-work / ship）
- ✅ GSD manager.md（dashboard 编排）完整
- ✅ GSD autonomous.md 开头（自动跑模式）
- ✅ GSD 67 个 commands 功能分类
- ✅ GSD 4 层架构（Roadmap / Milestone / Phase / Plan）
- ✅ GSD 动态加 phase 机制（add-phase / insert-phase）
- ✅ GSD UI-SPEC（phase 级，非项目级）
- ✅ GSD codebase 映射机制（map-codebase）

未深入：
- ⏸ GSD 实际跑一次的体感（PM 计划独立空仓实操验证）
- ⏸ GSD ns-* 路由系统的实现细节
- ⏸ GSD 与外部工具（GitHub / Linear）集成
