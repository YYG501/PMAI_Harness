# 设计：skill 读取清单收敛

**目的**：
- task-spec 痛点场景单次读取量 ~45%（8008 → ~4400）
- task-plan 省 ~24%；prd-writing 省 ~38%；req-solution 省 ~19%
- 消除 task-spec lint 失败 round-trip
- doc-update 补 task worktree 代码必读（修对账 bug，非节省）

**范围**：4 个 skill（req-solution / task-plan / task-spec / prd-writing）+ 模板 task.md.tmpl + PM-VIEW-RULES.md + close-req SKILL.md 步骤 1 模板 + doc-update 必读补全。task-execute 不在范围（实现参考非反向校验，保留整文件读）。
**作者**：AI 协作生成，PM YYG501 reviewed
**日期**：2026-05-07

---

## 1. 背景

### 1.1 触发问题

PM 报告：跑 `/task-spec` 改 task-001（revise 模式）耗时长。AI 自描述读了 PM-VIEW-RULES + brief + analysis + solution + 工程合同 + 模块文档 + page.tsx 关键段；首次 lint 因头部"状态"字段格式错重写。PM 实际改动小（替换两个占位 + Drawer + 筛选 + 按钮联动）。

### 1.2 实测验证（req-003 task-001 revise 模式模拟）

按 task-spec/SKILL.md 步骤逐行计算 AI 实际 Read 行为：

| 阶段 | 实际加载行 |
|---|---|
| 步骤 0 PM-VIEW-RULES.md | 715 |
| 步骤 1 task-plan.md | 208 |
| 步骤 3 必读输入（brief 127 + analysis 427 + solution 846 + task-001 自身 402 + task-002 327 + CONTEXT 33 + DESIGN 585 + prd 81 + modules INDEX 97 + functions-v4.1 563 + functions 41 + products/[id]/page.tsx **2000** [Read default limit 截断] + products/page.tsx 632）| 6561 |
| 步骤 8 task.md.tmpl 模板 | 262 |
| 步骤 10.5/10.6 lint 失败重读模板 | 262 |
| **合计** | **~8008 行** |

PM 实际写出 ~100 行 PM 视图差异 + ~50-150 行代码改动。**读写比 ~50:1**。

> 注：`solution.engineering.md` (1220) / `task-001.engineering.md` (222) / `task-002.engineering.md` 在 PM 视图链路本来就不读（PM-VIEW-RULES §9.1 line 53），不计入实测。

---

## 2. 根因

### 2.1 必读清单"广撒网"防御副作用

PM-VIEW-RULES §9.1 把项目级文档列为"必读"是为了堵 AI"觉得不必要"绕过流程的反模式（memory: `feedback_no_tool_replaces_skill`）。副作用：AI 倾向整文件 Read 所有列出的文件。

### 2.2 prototype 整文件 Read 是最大头

prototype `page.tsx` 2776 行被 Read default limit 截到 2000 行——单个文件占总读取的 26%。"按相关性扫"措辞 AI 不能精准执行，倾向全文 Read 候选文件。

### 2.3 lint 失败 round-trip 占 ~20% 时间

AI 第一次写 task PM 视图时倾向参考 `closed/` 下旧 v1 格式（标题下方加 frontmatter），被步骤 10.6 字段校验拦截 → 重读模板 + 重写 + 重跑校验。framework 兜住了正确性，但每次 round-trip 30-60s。

### 2.4 章节匹配未落地为 grep 操作

SKILL.md 多处写"按章节匹配"/"按相关性扫"——这些自然语言指令 AI 解读为"先全文读再挑章节"。

---

## 3. 范围

| 做 | 不做 |
|---|---|
| P0 头部状态字段加固 | 砍 DESIGN / brief / analysis / CONTEXT / prd 必读 |
| P1 prototype > 500 行强制 grep + 局部读 | task-spec revise 触发条件门（→ TODOS 延迟项）|
| P2 solution.md / 同模块 task 章节 grep | modules/* INDEX 索引化（first-gen 保留全部）|

### 3.1 不做项理由

- **不砍 DESIGN**：DESIGN 是 PM 反馈第四类（视觉规范）的沉淀地（PM-VIEW-RULES §9.4），PM 视图 skill 引用产品级规则需要它。memory `feedback_skill_must_actually_invoke` 中 task-002 R6 案例验证：DESIGN 不读会复踩同样视觉决策坑
- **不砍 brief/analysis/CONTEXT/prd**：项目级背景必读，砍掉触发 AI 闭门造车反模式
- **不砍 modules/* 全部**：INDEX 完整性不可保证；first-gen 阶段需要全局复用判断
- **不做 revise 触发条件门**：需要 git log 机制（mtime 不可靠）；优先纯写法约束，机制延迟

---

## 4. 改动清单

### 4.1 P0：头部状态字段加固

**`templates/task.md.tmpl`** line 1-8

将现有 HTML 注释升级，加"❌ 反例区"：

```markdown
<!-- ⚠️ 标题下方禁止加 frontmatter 段落。

  ✅ 正确：状态在 ## 📌 任务卡 表格里
    | **状态** | 待确认 |

  ❌ 错误（AI 常踩）：
    > 状态：「待启动」          ← 中文引号 + blockquote
    **状态：** 待执行            ← 标题下方 frontmatter 段
    | **状态** | 待启动 |        ← 派生显示标签当字段值

  合法状态值（5 态）：待确认 / 执行中 / 待验收 / 已完成 / 已废弃
  closed/ 下旧 task 是 v1 历史格式，新 task 不参考。
-->
```

**`skills/task-spec/SKILL.md` 步骤 8**

在"模板替换"段前加显式 6 项 checklist：

```markdown
**写头部前必查 6 项**（错一项 step 10.6 字段校验会拦截重写）：
- [ ] 标题 `# Task NNN: ...` 下方**无** frontmatter 段（无 `**Req：**` / `**状态：**` / `**创建日期：**` 等）
- [ ] 状态字段在 `## 📌 任务卡` 表格里（`| **状态** | 待确认 |`）
- [ ] 状态值是 5 态之一（不要写"待启动"/"待执行"——是派生显示标签）
- [ ] 不用中文引号（`「」` / `『』`），不用 blockquote 包字段
- [ ] 依赖列表是结构化 `- task-NNN (说明)`，不是自然语言
- [ ] **依据**：`closed/` 下旧 task 是 v1 历史格式，**不参考**（first-gen 首次写无 v1 干扰，本项可跳）
```

### 4.2 P1：prototype grep 强约束

**`skills/_shared/PM-VIEW-RULES.md`** §9.3 加子章节：

```markdown
#### 9.3.1 prototype 读取强约束（>500 行禁止整文件 Read）

prototype 文件 > 500 行 → **禁止** 整文件 Read。读法：

1. 先列**上游工程概念清单**（从 brief / analysis / solution / task-plan 中提取字段名 / 控件名 / 状态名 / 操作名）
2. 对每个概念在 prototype 范围内 grep：
   `grep -nE "<概念>" prototypes/<相关文件>`
3. **grep 命中**：Read offset = 命中行 -10, limit = 30
4. **grep 不命中**：列出已搜关键词清单 + 追问 PM「这个概念是否真不存在于原型里」。**禁止** AI 自行判定为"已砍掉"——可能是 false negative（关键词中英文不一致："额度" vs "quota" vs "allocation"；控件用 className 而非语义命名；概念名拆词等）。判断留给 PM。

例外：< 500 行的小 prototype 文件可全文 Read。

**理由**：原型 page.tsx 经常 2000+ 行，整文件 Read 浪费 90% 上下文。grep 命中段直接局部读；grep 不命中**不能**机械判为"原型已砍掉"——这种判断是 prose-as-judgment，需要 PM 拍板（参见 memory `feedback_judgment_pattern_not_mechanization`）。
```

**4 个 SKILL.md**（`req-solution` / `task-plan` / `task-spec` / `prd-writing`）

各加一行引用（**仅反向校验场景**）：

```markdown
**prototypes/ 反向校验按 `PM-VIEW-RULES.md §9.3.1` 执行（>500 行禁整文件 Read）**
```

> **task-execute 不应用本约束**：task-execute 步骤 2.1 的 prototype 读法是「参考已有组件结构与布局模式」（写新页面"长一样"），属于**实现参考**而非反向校验，需要全局结构感 → 保留整文件读，不在本次收敛范围。

### 4.3 P2：solution.md / 同模块 task 章节 grep

**`skills/_shared/PM-VIEW-RULES.md`** §9.1 表格下方加：

```markdown
#### 9.1.1 "按章节匹配"操作语义（强约束）

表格中标"按章节匹配"的文件 → **禁止** 整文件 Read。读法：

1. `grep -nE "^### .*(<关键词1>|<关键词2>)" <文件>` 命中相关章节标题
2. 按命中行号 + 下一个同级或更高级 header 之间的区间 offset/limit Read
3. 关键词从当前 task 标题 / 所属模块 / 功能名提取

适用文件：solution.engineering.md / 同模块 task-*.md（`## PM 反馈` 段）。

**solution.md（PM 视图）特殊**——逃生口：
- **first-gen 模式**：整文件读（顶端核心产物，需要全局视野）
- **revise 模式**：按 §🎯 / §📦 / §✅ 章节 grep 局部读
```

**`skills/task-spec/SKILL.md`** 步骤 5：

```markdown
扫描同模块已完成 task 的 PM 反馈条目（**只读 `## PM 反馈` 段，不读 task 文件其他章节**）：

1. `grep -nE "^## PM 反馈" tasks/task-*.md` 命中 section header
2. 按命中行号 + 下一个 `^## ` 之间的区间 offset/limit Read
```

**`skills/task-spec/SKILL.md`** 步骤 6（**仅 revise 模式生效**）：

```markdown
拉取相关 solution 内容（revise 模式按章节匹配，first-gen 整文件读）：

- **first-gen**：整文件 Read solution.md
- **revise**：`grep -nE "^### .*(<task-标题关键词>|<模块名>)" solution.md` 命中相关章节，按命中行号 offset/limit 局部读
```

**`skills/task-spec/SKILL.md`** 步骤 0.5 表 revise 行加注：

```markdown
revise 子集中的步骤 3 / 5 / 6 全部按 `PM-VIEW-RULES.md §9.3.1` / `§9.1.1` 强约束执行。**不允许** AI 在 revise 模式下"觉得 revise 是改 PM 视图"绕过 grep 走整文件读。
```

### 4.4 PM-VIEW-RULES.md §9.1 扩展为全 stage 权威清单

把 §9.1 当前仅 4 行 PM 视图 skill 的表扩展为本设计文档第 §10 节的 19 个 skill 全清单。落地到 PM-VIEW-RULES.md 后，§9.1 成为框架内"哪个 skill 该读什么"的**单一权威来源**。

**理由**：今天没有跨 stage 统一规范，各 SKILL.md 自行写"必读输入"，散乱且难维护。把 §10 表落地到 PM-VIEW-RULES.md §9.1 之后，每个 SKILL.md 只需引用"按 §9.1 中本 skill 对应行/段执行"，避免规则漂移。

**落地动作**（按顺序）：

1. **patch §10 全表到 PM-VIEW-RULES.md §9.1**：替换现有 line 516-524 的 4 行 PM 视图 skill 表为本设计文档 §10 全 19 skill 清单 + **7 条**跨 skill 共享原则
2. **task-execute SKILL.md 步骤 2 追加 prototype 读取规则**：明确"prototypes/ 是实现参考（写新页面"长一样"），全文 Read，**不应用 §9.3.1 反向校验 grep 约束**"——避免 §9.3.1 误覆盖 task-execute
3. **各 PM 视图 skill 的 SKILL.md "必读输入" 段改为引用 §9.1**：`req-analysis` / `req-solution` / `task-plan` / `task-spec` / `prd-writing` 的 `## Required Inputs` 段统一改为 "按 `PM-VIEW-RULES.md §9.1` 中本 skill 对应行/段执行"
4. **close-req SKILL.md 步骤 1 模板**（**已落地，无需再做**）：「## 需求概述 [从 brief.md 提取]」→「[从 solution.md §📌 方案摘要提取]」，与 §10 Stage 7.3 一致；brief 是 stage 1 初稿，close-req 时已被演化
5. **doc-update 加注 worktree 代码必读**：SKILL.md 步骤 1.6 line 99-101 已有"读取最终实现的代码"，但未列入"必读输入"——同步 §10 Stage 7.2 的 R14 改动后需补一行"必读输入"清单
6. **轻量 skill 不动**：以下 6 个 skill 的 SKILL.md "必读输入" 段（如有）**不引用** §9.1，独立维护：
   - **横切型**（无 stage 编号）：cancel-req / task-status / publish-to-lark / quick-fix
   - **stage 0 / 入口型**：init-project / new-req（虽在 §10 Stage 0 单列，但因不产 PM 视图文档，不进 §9.1 主表）

---

## 5. 测试策略

### 5.1 回归
现有 269 单测必须 0 失败。

### 5.2 实测验证
在 req-003 worktree 跑一次 `/task-spec task-001`（revise），抓 transcript：
- 预期总读取量 ~4400 行（从 ~8008 降，省 ~45%）
- 验证 lint 一次通过（P0）
- 验证 prototype 仅 grep 命中段（~150 行 vs 2000 行）
- 验证 DESIGN 仅 grep 相关章节（~80 行 vs 585 行）

**算账**：8008 - (2000-150) prototype - (846-150) solution - (327-30) 同模块 task - (585-80) DESIGN grep - (632-100) products/page grep = 8008 - 1850 - 696 - 297 - 505 - 532 = **4128** —— P0 消除一次 lint round-trip 再省 262 行 → **~3866**；保守上浮 ~14% 缓冲不确定性（grep 关键词偶尔超 30 行 / 边界 case 多读相邻段 / AI 偶尔补 offset 续读）→ **~4400**

### 5.3 反例验证
构造一个故意写错头部 frontmatter 的 task，验证步骤 10.6 字段校验更早抓住（让 AI 在写完前自查 6 项 checklist 发现错误）。

---

## 6. 风险与缓解

| # | 风险 | 概率 | 缓解 |
|---|---|---|---|
| R1 | prototype grep 关键词选不对，反向校验漏看 | 中 | §9.3.1 强制"先列上游工程概念清单"步骤；grep 不命中**不机械判为已砍**，列关键词清单追问 PM 拍板 |
| R2 | 章节标题写法不统一，grep 漏匹配 | 低 | PM-VIEW-RULES §七已锁定章节顺序；现有 lint 检查标题格式 |
| R3 | AI 在重做时绕过 grep 强约束 | 低 | SKILL.md 措辞从"建议"改"禁止"；归到 `feedback_no_tool_replaces_skill` 类反模式监控 |
| R4 | P0 头部加固改动模板影响新 task 格式 | 低 | 仅改 HTML 注释 + SKILL.md 断言，不改章节内容 |
| R5 | 收敛后实测节省 < 30% | 中 | 优先级"消除 lint round-trip" + "省 prototype 整文件"，达成则 30%+ 必然 |
| R6 | grep 强约束在不擅长 grep 的 LLM 上失效 | 低 | Claude / GPT 都有原生 grep tool；SKILL.md 给具体命令 |

---

## 7. 验收信号

- ✅ task-spec revise 一次通过 lint，无 round-trip
- ✅ transcript 显示 prototype 读取从 2000 行 → ~150 行（grep 命中段）
- ✅ solution.md 读取从 846 行 → ~150 行（章节匹配）
- ✅ 同模块 task PM 视图读取从 319 行 → ~30 行（PM 反馈段）
- ✅ 269 单测 0 失败
- ✅ 总读取量 ≤ 4500 行（task-spec revise 痛点场景）

---

## 8. 推进顺序

1. **P0 单独提交**（30 分钟）→ 立即跑一次 task-spec 看 lint 是否一次通过
2. **P1 + P2 一起提交**（1.5 小时）→ 跑回归 269 单测 → 实测 transcript → 提交
3. **更新文档**（30 分钟）：
   - `STATUS-v3.5实施.md` 加进度条
   - `TODOS.md` 把 P3（revise 触发条件门 / modules INDEX 索引化）记录为延迟项
   - `MEMORY.md` 加 `feedback_skill_reading_convergence` 一条（"必读清单收敛优先纯写法约束，不动防御性设计"）

总工时 ~3 小时，分 2-3 个 commit 落地。

---

## 9. 收敛覆盖（按 stage 维度）

| Stage | Skill | 当前 | 收敛后 | 省 | 主要改动 |
|---|---|---|---|---|---|
| 4 | req-solution（first-gen）| ~9500 | ~7650 | 19% | P1 prototype |
| 5 | task-plan | ~10500 | ~7940 | 24% | P1 + R4 brief⚪ + R5 DESIGN⚪ |
| 6 | task-spec（first-gen）| ~7600 | ~4300 | 43% | P0+P1+P2 + R6 DESIGN grep |
| 6 | **task-spec（revise，痛点场景）**| **~8008** | **~4400** | **45%** | **P0+P1+P2 + R6 DESIGN grep** |
| 6.6 | task-execute | ~5500 | ~5500 | **0%** | **不应用**（实现参考非反向校验）|
| 7.2 | doc-update | — | — | 修 bug | R14 补 worktree 代码必读 |
| 7.3 | close-req | — | — | 减误读 | brief 改用 solution §📌（避免初稿污染）|
| 7.4 | prd-writing | ~12000 | ~7500 | 38% | P1 + R15 tasks 三章节 grep |

**痛点场景**（task-spec revise）省 **45%**；其他 PM 视图链路 stage 19-38% 不等（视应用了哪些改动）。task-execute 0%（不应用）。doc-update / close-req 不为节省，是修 bug + 修设计冗余。

---

## 10. 全 stage 必读清单（权威表）

> **落地目标**：本节内容直接 patch 到 `skills/_shared/PM-VIEW-RULES.md` §9.1，成为框架内"哪个 skill 该读什么"的**单一权威来源**。各 SKILL.md "必读输入" 段改为引用 "按 §9.1 第 N 行执行"，避免规则漂移。
>
> **替代关系**：§9.1 现有 4 行 PM 视图 skill 表（PM-VIEW-RULES.md line 516-524）将由本 §10 全 19 个 skill 表**完全替代**。当本表与 §9.1 旧表 / 各 SKILL.md 现行措辞不一致时（如 req-analysis 实际不读 prototypes / DESIGN / modules，§9.1 旧表却列必读；如 task-spec 把 brief/analysis 从必读降为 ⚪），**以本表为准**——这些差异是 P0+P1+P2 收敛后的明确设计选择，不是漂移。

### 图例
- 🟢 全文必读
- 🟡 章节 grep（按 §9.3.1 / §9.1.1 强约束）
- ⚪ 按需 lazy（写不出来回查）
- ❌ 显式不读

### Stage 0：项目初始化

| skill | 文件 | 等级 |
|---|---|---|
| init-project | PM 输入（项目名 / 目录），无大文件 | — |
| new-req | PM-VIEW-RULES §四 brief 严格度行 | 🟢 |

### Stage 2：req-analysis
- 🟢 `brief.md`
- 🟢 `docs/CONTEXT.md`（如存在）
- 🟢 `docs/prd.md`（如存在 → **必读**，分析新需求必须基于已有产品规格基线，避免重复设计 / 与已有功能冲突）

### Stage 3：req-stage-gate
- 仅 `$ACTIVE_REQ_STAGE` 元数据 + advisor 调用，无大文件读

### Stage 4：req-solution

**first-gen / PM 视图**（~7650 行收敛后）
- 🟢 `PM-VIEW-RULES.md`（步骤 0，仅 1 次/会话）
- 🟢 `brief.md` / `analysis.md`
- 🟢 `docs/CONTEXT.md` / `docs/DESIGN.md` / `docs/prd.md`
- 🟢 `docs/modules/INDEX.md` + 全部 `docs/modules/*.md`
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- ❌ 任何 `.engineering.md`

**first-gen / 工程合同**
- 🟢 `analysis.md` / `docs/DESIGN.md` / `docs/modules/<本 req 涉及模块>.md`
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- ⚪ 上游 `.engineering.md`

**revise（PM 视图）**
- 🟢 `solution.md` 主文件 + chat 中 PM 修改要求
- ⚪ 其他全部按需

**reconcile**
- 🟢 `solution.md` + `solution.engineering.md` hash + `git diff`
- 🟡 hash 不一致才扩大读：`analysis.md` / `DESIGN.md` / 当前模块 / `prototypes/<相关>`（§9.3.1）

### Stage 5：task-plan
- 🟢 `PM-VIEW-RULES.md`（步骤 0）
- 🟢 `analysis.md` / `solution.md`（PM 视图）
- ⚪ `brief.md`（按需——已被 analysis / solution 消化两层；偶尔回查初衷）
- 🟢 `docs/CONTEXT.md` / `docs/prd.md`
- ⚪ `docs/DESIGN.md`（按需——视觉决策不影响 task 拆分粒度，仅在拆边界涉及视觉差异时回查）
- 🟢 `docs/modules/INDEX.md` + 全部 `docs/modules/*.md`
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- ❌ `solution.engineering.md` / 任何 `.engineering.md`

### Stage 6：task-spec

**first-gen / PM 视图**（~4300 行收敛后）
- 🟢 `PM-VIEW-RULES.md`（步骤 0，不重读）
- 🟢 `task-plan.md`（取本 task 行 + 自检与状态摘要）
- 🟢 `solution.md` PM 视图（**first-gen 整文件读，§9.1.1 逃生口**）
- 🟢 `docs/CONTEXT.md` / `docs/prd.md` / `docs/modules/<本 task 模块>.md`
- 🟡 `docs/DESIGN.md`（按 task 涉及功能 grep 相关章节，§9.1.1）—— PM 视图禁像素颜色，仅引用产品级视觉决策稀疏，不全文读
- 🟡 同模块已完成 `task-*.md` 仅 grep `## PM 反馈` 段（§9.1.1）
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- ⚪ `brief.md` / `analysis.md`
- ❌ 任何 `.engineering.md`

**first-gen / 工程合同**
- 🟢 `docs/DESIGN.md` / `docs/modules/<本 task 模块>.md`
- 🟡 `analysis.md` 工程层段 / `solution.engineering.md` 章节匹配（§9.1.1）
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- ⚪ 同模块已完成 `task-*.engineering.md`

**revise / PM 视图（痛点场景，~4400 行收敛后）**
- 🟢 `task-NNN.md` 主文件 + chat 中 PM 修改要求
- 🟡 `solution.md` 章节 grep（§9.1.1 revise 模式）
- 🟡 同模块 `task-*.md` `## PM 反馈` 段（§9.1.1）
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- 🟢 `docs/CONTEXT.md` / `docs/prd.md` / `docs/modules/<本 task 模块>.md`
- 🟡 `docs/DESIGN.md`（同 first-gen，按 task 涉及功能 grep，§9.1.1）
- ⚪ `brief.md` / `analysis.md`
- ❌ 任何 `.engineering.md`

**reconcile**：已收敛过 — 不动

### Stage 6.5：task-confirm
- 🟢 本 task 两文件（成对校验）
- 🟢 依赖 task 状态

### Stage 6.6：task-execute
- 🟢 本 task 两文件（PM 视图 + 工程合同）
- 🟢 工程合同 §3 启动前必读列表（逐个读）
- 🟢 `docs/DESIGN.md`（**强制 cat 全文，保留**——task-001 反模式 evidence）
- 🟢 `docs/modules/<本 task 模块>.md`
- 🟢 `prototypes/<相关页面>`（**实现参考，不应用 §9.3.1**，全文 Read）

### Stage 6.7：task-submit
- 🟢 本 task 两文件

### Stage 7.1：close-task
- 🟢 本 task 两文件
- 🟢 task worktree 改动代码（≤3 文件全读，多文件分批）
- 🟢 `docs/DESIGN.md`（步骤 1.5 视觉规范类 PM 反馈第四类反推沉淀，参见 §9.4）

### Stage 7.2：doc-update
- 🟢 本 task PM 视图主文件
- 🟢 `docs/modules/<本 task 模块>.md`
- 🟢 工程合同 §10 文档偏差表
- 🟢 task worktree 改动代码（步骤 1.6 模块规格对账，逐行核对实际实现是否匹配——不读代码就不能对账；读法同 Stage 7.1 close-task：≤3 文件全读，多文件分批）
- 🟡 偏差涉及的原文（前后 5 行）

### Stage 7.3：close-req
- 🟡 `solution.md` §📌 方案摘要（步骤 1 close-report 需求概述源；**不读 brief.md**——brief 是 stage 1 初稿，close-req 时已被 7 个 stage 演化推翻，用初稿写关闭报告 = 写已被推翻的初衷）
- 🟢 `tasks/*.md` 遍历摘要
- 🟡 `solution.md` §🔧 实现深度变更段（步骤 2c 项目级同步判定）
- 🟡 `$REPO_ROOT/CLAUDE.md` 「## 工程结构约束」段（步骤 2c 比对项）
- 🟡 `tasks/discarded/*.md` 摘要

### Stage 7.4：prd-writing（~7500 行收敛后）
- 🟢 `brief.md` / `analysis.md` / `solution.md`
- 🟡 `tasks/task-*.md` 遍历——`grep -nE "^## (📋 功能清单|🎯 关键产品决策|✅ 验收清单)" tasks/*.md` 命中三段后局部读（§9.1.1）。任务卡 / 历史档案 / PM 反馈对 PRD 价值低，不读
- 🟢 `docs/CONTEXT.md` / `docs/DESIGN.md` / `docs/prd.md` / `docs/modules/INDEX.md`
- 🟢 `docs/modules/<本 req 涉及模块>.md`
- 🟡 `prototypes/<相关页面>`（§9.3.1）
- ⚪ 其他 `docs/modules/*.md`
- ❌ 任何 `.engineering.md`

### Stage 7.5：project-prd-update
- 🟢 本 req `prd.md`
- 🟢 `docs/prd.md`

### 轻量 skill（不在收敛范围）

> **落地说明**：以下 skill 没有 §九 输入流约束段（不是 PM 视图产出 skill），其 SKILL.md "必读输入" 段**不引用** §9.1 主表，独立维护。本分组仅作清单备查，不进 §9.1 主表。

| skill | 必读 |
|---|---|
| cancel-req | 仅 req 元数据 |
| task-status | 仅 stage / task 状态 + 最后事件 |
| publish-to-lark | 仅参数指定的目标文档 |
| quick-fix | 🟢 参数指定文档 / ⚪ 关联文档 |

### 跨 skill 共享原则

1. **`.engineering.md` 仅工程合同链路读**：PM 视图 skill（req-analysis / req-solution PM / task-plan / task-spec PM / prd-writing）一律 ❌ 不读任何 `.engineering.md`（PM-VIEW-RULES §9.1 / §9.2）
2. **`docs/DESIGN.md` 在 PM 视图链路保留必读但分级**（按 §10 各 skill 行）：
   - `req-solution` PM 视图 / 工程合同：🟢 全文必读（方案设计需视觉规范基线）
   - `task-spec` PM 视图（first-gen + revise）：🟡 章节 grep（按 task 涉及功能 grep 相关章节，§9.1.1）—— PM 视图禁像素颜色，仅引用产品级视觉决策稀疏
   - `task-spec` 工程合同：🟢 全文必读
   - `task-plan`：⚪ 按需（视觉决策不影响 task 拆分粒度）
   - `task-execute`：🟢 强制 cat 全文（视觉一致性护身符）
   - `close-task`：🟢 全文必读（PM 反馈第四类反推沉淀目标）
   - `prd-writing`：🟢 全文必读
   - **不可整体砍**：DESIGN 是 PM 反馈第四类（视觉规范）沉淀地（§9.4），不同 skill 按不同强度引用
3. **`prototypes/` 反向校验场景按 §9.3.1 grep 强约束**：仅 task-execute 例外（实现参考全文读）
4. **章节匹配场景按 §9.1.1 grep 强约束**：solution.md 在 first-gen 整文件读 / revise grep
5. **`PM-VIEW-RULES.md` 步骤 0 读 1 次/会话，后续步骤不重读**
6. **PM 反馈四类分流的读取分工**（PM-VIEW-RULES §9.4）：
   - `task-spec` 读"同模块已完成 task 的 PM 反馈"前三类（正向规则 / 反向约束 / 决策记录）→ 落到当前 task 对应章节
   - `close-task` 步骤 1.5 读"本 task 的 PM 反馈"第四类（视觉规范）→ 反推沉淀到 `docs/DESIGN.md`
   - `prd-writing` **不读** `## PM 反馈` 段（PM 反馈是 task 级反馈条目，PRD 级关心的是最终交付的功能 / 决策 / 验收）；prd-writing 读 task PM 视图的 `^## (📋 功能清单|🎯 关键产品决策|✅ 验收清单)` 三段是另一个目的（抽功能需求），与 §9.4 PM 反馈分流读法**不同读法 / 不同来源段**，不冲突
7. **closed/ 旧 task 读取边界**：扫描 `requirements/closed/**/tasks/*.md` 时，**只读 `## PM 反馈` 段**抽反馈条目；**不读**顶部 frontmatter / 元信息段落 / 任务卡表格的字段布局（v1 历史格式，新 task 按 v2 模板生成；混读会触发 task-spec 步骤 10.6 字段校验拦截重写）

8. **§9.1.1 grep 不命中 fallback**（防"0 行读"丢失视觉一致性引用）：当 task 关键词 grep 不命中文件章节时按 fallback 读：
   - `docs/DESIGN.md`：读「页面模板」+「动效规范」+「间距系统」三个通用章节（约 100-150 行）
   - `solution.engineering.md`：读 §1 数据结构 + §2 派生状态 + §6 易错点（约 200 行）
   - `tasks/task-*.md`（prd-writing 三章节遍历）：追问 PM 该 task 是否真无可写入 PRD 的内容
   - 同模块 `task-*.md` `## PM 反馈` 段：0 命中 = 无反馈，跳过即可（不 fallback）

   **理由**：grep 不命中 ≠ 内容真不需要。DESIGN 章节按通用规则命名（颜色 / 字体 / 间距 / 模板 / 动效），不会按 task 业务关键词命名 — 但通用模板 / 动效会被 PM 视图章节稀疏引用。预设 fallback 章节把判断收敛到设计期，避免每次都追问 PM。

---

## 附录 A：实测数据来源

worktree：`<LOCAL_WORKTREE>/req-003-tenant-console-redesign-v2`
req：`req-003-tenant-console-redesign-v2`
task：`task-001-tab1-allocation-view`（revise 模式）
模块：产品访问管理

文件大小快照（截至 2026-05-07）：

| 文件 | 行数 |
|---|---|
| brief.md | 127 |
| analysis.md | 427 |
| task-plan.md | 208 |
| solution.md | 846 |
| solution.engineering.md | 1220 |
| task-001.md | 402 |
| task-001.engineering.md | 222 |
| task-002.md | 327 |
| docs/CONTEXT.md | 33 |
| docs/DESIGN.md | 585 |
| docs/prd.md | 81 |
| docs/modules/INDEX.md | 97 |
| 当前模块 functions-v4.1.md | 563 |
| 当前模块 functions.md | 41 |
| prototypes/products/[productId]/page.tsx | 2776 |
| prototypes/products/page.tsx | 632 |
| skills/_shared/PM-VIEW-RULES.md | 715 |
| templates/task.md.tmpl | 262 |

---

## 附录 B：延迟项登记（→ TODOS.md）

| ID | 项 | 触发条件 |
|---|---|---|
| TD-X1 | task-spec revise 触发条件门（步骤 5/6 用 git log 比对，跳过过期数据）| 实测 transcript 显示 P0+P1+P2 后 revise 仍超 5000 行 |
| TD-X2 | modules/* INDEX 索引化 | INDEX 完整性机制落地后 |
| TD-X3 | 基于实测 transcript 二次审视激进收敛 | P0+P1+P2 节省 < 30% |
