<!-- /autoplan restore point: <LOCAL_GSTACK_HOME>/projects/PM-AI-Workflow/main-autoplan-restore-20260520-183348.md -->
# task-spec 重构（delta-3 · 双文件塌缩 + 啰嗦点收口）(v2)

> **状态**：v2（2026-05-21）—— v1 经 /plan-eng-review 包复核修订（§X Round 2）：6 finding 落地 —— §2.8 保留单文件 PM-确认区 tamper-hash（A2，推翻 v1「hash 整组删」）、§3 ownership 表补 close-req/doc-update（A3）、§2.5 build-execution-prompt.py 写死抽执行区（P1-perf）、vp-11 补 in-flight 旧 req e2e + tamper-hash 测试（T2/T3）、措辞精度（F6）。最小落地包 = **delta-2+3+4+7+8**（delta-7 经 codex#4 拉入，见 umbrella §8）。§X Round 1/2 = review 历史。
> **日期**：2026-05-21
> **作者**：PM + AI
> **来源**：`管线重构-GSD-review.md` §4 delta-3 + §4.1 五个啰嗦点 + §8 实施顺序第 2 步；`PRD-solution-对调.md` v1.1 §2.2 / §X F11；`实现设计视图-HOW安家.md` v1 §4.1。最小落地包 = delta-2+3+4+8。

---

## §0 原始痛点（PM + AI 共写，后续 review **不可反向修改**）

> ⚠️ 本节经 **PM + AI 共写、2026-05-20 锁定**。后续任何 review / autoplan / dual voice 都**不能**给本节加东西、不能重新定义范围；如需改 §0，PM 显式 v0 → v1 重开。
> 锁定依据：`管线重构-GSD-review.md` §4.1 的 5 个啰嗦点（PM 已在 §4.2 判 delta-3 通过、明示「①②③ 全改」）。

### §0.1 痛点（1-3 句）

`task-spec` 是 v3.5 管线最重的 skill（748 行 / 13 步）。重的根来源是「PM 视图 + 工程合同」**双文件**设计：为保两文件同步，长出 hash 写入 / reconcile / lazy-sync / 强制落盘一整套机器（步骤 9 / 10.5 / 11.0 / 12.5 / 12.6）；再叠加 PM 反馈三类分流（往两文件不同 section 投递）和与 `task-confirm` 背靠背重叠的确认门 —— task-spec 成了「机制重于内容」的反例。

### §0.2 触发场景

> delta-3 的痛点既有 dogfood 背书（PM 在 ChatBuilder 完整跑 GSD 后 review 得出 §4.1 五啰嗦点），又有 delta-2/4/8 的**结构连带**（双文件的两层内容被上移后，双文件失去地基）。证据为仓内可查的 SKILL 行号 + 一次实证事故。

| # | 场景描述 | 证据（仓内可查 / 实证）|
|---|---|---|
| 1 | 双文件 hash / reconcile / lazy-sync / 落盘机器占据 task-spec 近半篇幅 | `task-spec/SKILL.md` 步骤 9（346-396）/ 10.5 hash 自检（442-453）/ 11.0（524-534）/ 12.5（665-691）/ 12.6（693-717）；`_shared/pm-view/input-flow.md` §9.6 |
| 2 | delta-2 把 PM 视图内容（功能清单 / 验收 / 决策 / 产物预览 / 占位字典 / 自测说明）全部上移 PRD → 双文件的「PM 视图」一侧被掏空，双文件设计失去存在理由 | `PRD-solution-对调.md` v1.1 §2.2 routing 表（10 个 section 去向）|
| 3 | PM 反馈三类分流（正向规则 / 反向约束 / 决策记录）规则隐式、AI 执行率低、PM 错分 | `task-spec/SKILL.md` 步骤 5（112-156）、`input-flow.md` §9.4；`管线重构-GSD-review.md` §4.1① |
| 4 | task-spec 步骤 12 定稿确认门 + task-confirm 步骤 3 启动确认门 = PM 背靠背撞两个门 | `task-spec/SKILL.md`:560-663 +「步骤 13 推 task-confirm」；`task-confirm/SKILL.md`:140 |
| 5 | 强制落盘（步骤 12.6）是框架层 git plumbing，被写成 ~25 行 skill prose | `task-spec/SKILL.md`:693-717；实证事故：2026-05-09 task-005 三个状态变更弹窗文案偏差，因 4 轮 revise 全停在 working tree 没 commit、`task-confirm` fork 拿到 first-gen v1 |

### §0.3 根因（解决什么底层 mechanism）

`task-spec` 在 delta-2 之前必须独自同时持有 req 级 **WHAT**（PM 视图）和 **HOW**（工程合同）—— 双文件是它「一个 skill 扛两层」的产物，与 `PRD-solution-对调.md` §0.1 给 `req-solution` 修过的反模式同形。双文件一旦成立，hash 同步 / reconcile / lazy-sync / 落盘是**连带必然**的机器，三类分流是「往两文件不同 section 投递」的连带规则。

根因 = **task-spec 的双文件设计**。delta-2（WHAT 上移 PRD）+ delta-8（HOW 上移 `implementation-design.md`）抽走两层后，双文件失去地基 —— task-spec 该塌缩成单文件，连带机器随之消失。

### §0.4 不解决什么（防膨胀）

| 衍生 / 假设场景 | 为什么不在本文档 |
|---|---|
| PRD / project-solution / prd-writing 本身 | = delta-2+4（`PRD-solution-对调.md`）|
| req 级实现设计视图 `implementation-design.md` | = delta-8（`实现设计视图-HOW安家.md`）|
| 批量 vs lazy 写 task spec 的时机 | `管线重构-GSD-review.md` §3.1 已定 lazy（两模式都不批量写死），不在 delta-3 重议 |
| task-spec / task-execute agent 化 | `管线重构-GSD-review.md` §6.1 已定 planning 类不 agent 化 |
| task-execute / close-task 工作流重构 | delta-3 只在「双文件→单文件」连带面上改它们的**文件处理**，不重构其工作流 |
| modulespec 维护 | = D13（已落地）|

→ review 中任何 finding 指向以上场景的，默认 DEFER（除非 PM 显式接受拉进 §0）。

---

## §1 要定的设计问题（逐题过）

| # | 设计问题 | 状态 |
|---|---|---|
| Q1 | **单文件塌缩** —— delta-2 抽走 WHAT 后，task-spec 产 1 个文件还是 2 个？单文件是什么性质（PM 视图 / 工程合同 / 混合）？文件名 / lint 归属 | ✓ 已定（见 §2.1）|
| Q2 | **②hash 机器去向** —— 双文件 hash / reconcile / lazy-sync 整组怎么处理？步骤 12.6 强制落盘「移到框架 hook」具体落哪 | ✓ 已定（见 §2.2）|
| Q3 | **③单一确认门** —— task-spec 步骤 12 + task-confirm 步骤 3 两个门合并后归哪个 skill？另一个 skill 怎么退化 | ✓ 已定（见 §2.3）|
| Q4 | **①三类分流简化 + ⑤same-req 反馈 lane** —— 三类分流简化成什么二分？delta-2+4 §X F11 已推翻「⑤自动消」，同 req 内 task 间反馈走哪条 lane | ✓ 已定（见 §2.4）|
| Q5 | **上下游契约重定义** —— task-spec 读什么、写什么（PRD + implementation-design + ...）？砍哪些步骤？连带改哪些 skill / 脚本 / 模板 | ✓ 已定（见 §2.5）|

---

## §2 方案主体（v1 —— 据 §X Round 1 的 18 finding + UC-1 决议修订）

### §2.1 单文件 = typed contract（Q1 已定 · UC-1 修订）

task-spec 产 **1 个物理文件** `tasks/task-NNN-<slug>.md`（不恢复双文件；`.engineering.md` 后缀取消；§0 锁定不动）。它**不是**「无 lint 的纯执行合同」（v0 原表述经 UC-1 推翻），而是 **typed contract** —— 单文件内部明确分三区，各区有各自的 lint：

| 区 | 含哪些段 | lint |
|---|---|---|
| **PM 确认区** | 任务卡（10 秒理解，含 executor/model 元字段）/ task 级范围（改·不改）/ task 级验收清单（PM 走查）/ PM 反馈承接清单（§2.4）| **`check-doc-pm-view.py` scoped 模式** —— 只校验本区，仍守 PM-view 写作纪律（指代前缀 / 禁工程词 / 禁反向约束）|
| **执行区** | 启动前必读 / 实现规格 / 实现设计引用（HOW-ID 行 + task-scoped 占位值）/ 约束与易错 / task 级自测说明 / 工程层验收 / 状态转换说明 | 工程 contract 校验（字段格式 / section 完整性）；允许工程内容（字段名 / 像素 / 反向约束）|
| **审计区** | 文档偏差（executor 填）/ 自审记录（executor 填）/ 历史档案（执行日志·PM 反馈·plan-review 沉淀）| 不 lint；`task-transition.py` 的「→已完成」gate 读（§2.6）|

- **格式标记**：文件头部加 `<!-- task_format: single-typed-v3 -->`（三态判别用，§2.7）。
- **确认门契约**：PM 在确认门**必读且只需读 PM 确认区**；这三段必须能独立判 scope（不依赖执行区）。确认门文案明确「你确认的是 scope / 验收 / 反馈承接，不是逐条背书实现细节」。
- **为什么 typed 而非裸执行合同**（§X UC-1 / D3-1）：确认门是 PM 在整个 task 的唯一决策点（§2.3 已删 task-confirm 的门）。PM 确认区有 scoped lint = 门有机器兜底，不退化成盲签。
- **为什么仍单文件**：typed 三区是**文件内 section 边界**，不是两个物理文件 —— 无第二份可同步，hash/reconcile 仍整组消失（§2.2）。typed contract ≠ 双文件复活。

> 为什么不保留「薄双文件」：只要两个物理文件就还要 hash 同步 —— ②④ 病根没拔。单文件 + typed 三区两者兼得：拔 hash 病根 + 留 PM 确认区兜底。

### §2.2 hash 机器去向 + 落盘（Q2 已定 · D3-8 修订）

- **reconcile / lazy-sync 随双文件删除；hash 用途分离**（2026-05-21 eng-review A2 修订 v1「hash 整组删」）—— 步骤 9 双文件 hash 写入、步骤 11.0 / 12.5 reconcile 全消失，`input-flow.md` §9.6 整节作废，`finalize-review.py`（100% 服务双文件 hash）**整个脚本删除**（§2.5）。**但 hash 自检（步骤 10.5）不全删** —— 双文件**同步**用途没了，**binding-contract tamper 检测**用途保留为单文件最小 tamper-hash（确认门退出对 PM 确认区算、后续写入校验；见 §2.8）。
- **落盘留在 task-spec，不移 `create-task-worktree.sh`**（D3-8 修订 v0 原方案）—— §0 痛点⑤是「落盘被写成 ~25 行 skill prose」，**病根是 prose 啰嗦、不是落盘发生在 task-spec**。根因优先：把 25 行 prose 压成 **1 行 helper 调用** —— 现役 `_lib/dirty-check.sh` 的 `auto_commit_docs` 保留，task-spec 确认门后调一行 `auto_commit_docs "$REQ_WORKTREE" "<msg>" "$TASK_FILE"`（单文件，pathspec 一个文件）。
- **`create-task-worktree.sh` 的 I-DC1 pre-fork gate 保持「最后防线」语义不变**（不升主路径）—— 仍是异常兜底、触发仍告警。v0 把它升唯一机制 = fallback 当主路径（§X D3-8），废。
- **「PM 决策 = binding contract」纪律保留**（§X D3-9）—— 删的是 hash 这个机制，不是删「PM 在确认门判定保留的内容 AI 不得改」这条约束。revise 模式仍守：只改 PM 明确要求改的段落，不顺手 normalize 其他（memory `feedback_pm_decision_is_binding_contract`）。

### §2.3 单一确认门（Q3 已定 · D3-15 补充）

- 合并后的**单一 PM 确认门留 `task-spec`**（步骤 12，PM 读 PM 确认区定稿）。
- **`task-confirm` 退化为机械流程** —— 删步骤 3「是否确认启动此 task？」问句。保留：摘要展示（informational）、可选 executor 切换、**依赖 gate（步骤 4-pre，机器校验，必须保留）**、worktree fork。
- **executor 切换的呈现**（D3-15）：task-confirm 仍打印 executor 列表 + 「想换说一声」提示，但**不阻塞** —— PM 不响应即用默认继续。这是「机械流程 + 一次非阻塞告知」，与「退化为机械 fork」不矛盾。
- **task-spec 确认门前置依赖检查**（D3-15）：task-spec 步骤 12 确认门**前**扫一次本 task `## 依赖` 的 task 状态，有未完成依赖则在确认门 chat 先告知 PM「本 task 依赖 task-MMM 未完成，task-confirm 会拦下」—— 避免 PM 在「以为能启动」预期下被 task-confirm 依赖 gate 弹回。

### §2.4 relevance 二分 + 反馈承接清单（Q4 已定 · D3-12 补充）

**⑤ same-req 反馈 lane 保留**（`PRD-solution-对调.md` v1.1 §X F11 已证 close-req 反向对齐对「task-(N+1) 学 task-N」太晚）：task-spec 读前序「已完成」task 文件的 `## PM 反馈` 段。delta-3 **不依赖**尚未落地的 delta-7。

- **①三类 sentiment 分流 → relevance 二分**：「正向规则 / 反向约束 / 决策记录」三类是双文件投递地址的产物，单文件后失去意义。新二分轴 = **relevance**：「适用当前 task」→ 写进执行区「约束与易错」段；「不适用」→ 留原 task 文件 `## PM 反馈` 段不动。relevance 具体可判（模块 / 功能是否落在当前 task 范围），不是 sentiment（要解读语气）—— ① 的「规则隐式 / AI 执行率低 / PM 错分」三毛病一起消。
- **「不适用」必须可观测**（§X D3-12 —— v0 让它对 PM 黑盒）：PM 确认区加 **「PM 反馈承接清单」**段，每条前序反馈一行：来源 task / 原文摘要 / relevance（适用·不适用）/ 处理结果（承接·不适用）/ 一句理由。确认门摘要输出「承接 X 条 / 不适用 Z 条（来自 task-NNN）」，PM 一眼可见、可纠误判。
- **跨模块反馈 = 已知 gap**（§X D3-12）：现役 lane 是同模块 grep（`task-spec/SKILL.md` 同模块匹配），装不下「反馈留在模块 A 的 task、却约束模块 B」的情形。relevance 二分**不解决**这个 —— 凡属「全项目跨功能产品行为规则」的跨模块反馈，**DEFER 到 delta-9**（2026-05-21 改：原指 delta-7；经 delta-7/delta-9 设计会话查清其本质是项目级产品规则、非 req 级事件 → 落 delta-9 `PRODUCT-RULES.md`，close-task selective promote、常驻供后续 task 读）。「孤儿反馈终态」问题随之消解 —— 项目级规则常驻、不随 req 失效。
- 决策备选 + 理由的体系化归宿（delta-7 `decision` 事件）属 delta-7；close-req 反向对齐 PRD 属 delta-6 —— 三者不同层、不冲突。

### §2.5 上下游契约 + 完整 blast radius（Q5 已定 · D3-3 修订）

**task-spec 重定义后的输入集**：

| 输入 | 处理 |
|---|---|
| `task-plan.md` | 留 —— task 元数据 |
| `prd.md`（delta-2）| 替代 `solution.md` —— req 级 WHAT；挑当前 task 切片 |
| `implementation-design.md`（delta-8）| 替代 `solution.engineering.md` —— 按 `HOW-ID` + 适用关键词挑当前 task 相关行 |
| `docs/CONTEXT.md` / `docs/DESIGN.md` / `docs/modules/` | 留 —— 项目级 |
| 前序「已完成」task 的 `## PM 反馈` 段 | 留 —— same-req 反馈 lane（§2.4）|
| `analysis.md` | **⚪ 按需 lazy fallback**（D3-18 修订 v0 的「砍」）—— 不默认读；PRD 切片不足时 task-spec 声明式回读 analysis 对应章节并在 chat 告知 PM「PRD 此切片不足，已回读 analysis §X」|
| `brief.md` | 砍 —— 被 analysis 消化两层，下游价值近零 |
| `prototypes/` | 砍 —— 产物预览已移 PRD |

**完整 blast radius**（§X D3-3 —— v0 仅列 7 个，实测 grep 出 19 个；**(v0 漏)** 标注 v0 缺失项）：

| 消费者 | 改动 |
|---|---|
| `task-spec` | 核心重写（§2.1-§2.4 / §2.6 / §2.8）|
| `task-confirm` | 删拆两文件约定 + 成对校验 + 步骤 3 PM 门；步骤 1.4 行数 lint 整步删（随 `check-engineering-doc-size.py` 退场）|
| `task-execute` | **(v0 漏)** 改「拆两文件约定」必读段 + 步骤 1 成对校验 + §2/§3「分文件读」改「单文件分区读」|
| `task-submit` | **(v0 漏)** 验收聚合从双文件改单文件 typed 区锚点 |
| `task-verify` | **(v0 漏)** task 级自测说明仍在 task 文件执行区（task-spec 从 PRD 派生写入，D3-5）—— `task-verify` 读取锚点同步 |
| `close-task` | merge 回 req 分支从两文件改一文件 |
| `close-req` / `doc-update` | **(v0 漏)** 从 task 读功能清单 / 偏差的输入契约改 typed 区锚点 |
| `create-task-worktree.sh` | v4.5「fork 后删两文件」改删一文件；I-DC1 pre-fork gate pathspec 单文件化（语义不变，§2.2）|
| `build-execution-prompt.py` | 执行信封 2 路径 → 1 路径；**「1 路径」= 抽取 task 单文件的「执行区」进信封**（2026-05-21 eng-review P1-perf），不塞整文件 —— executor 信封不带 PM 确认区 / 审计区，保持旧双文件「executor 只见工程内容」边界 |
| `resolve-executor.py` | **(v0 漏)** executor/model 字段源从 `.engineering.md` 改单文件 PM 确认区·任务卡；`FIELD_RE` 改用 `state.py:parse_field`（去掉自带 v1-only 解析器）|
| `_lib/state.py` | **(v0 漏)** `detect_format` 改三态（§2.7）；`read_section` 单文件查找 |
| `task-transition.py` | **(v0 漏)** §10/§11 gate 改单文件内查找（§2.6 critical）；`--discard` 成对 `git mv` 改单文件 |
| `check-doc-pm-view.py` | 加 **scoped 模式**：对 task 文件只校验 PM 确认区（不是整文件跳过，UC-1）|
| `check-engineering-doc-size.py` | **整脚本删除**（§X D3-13 —— solution 分支 delta-2+4 已剥、task 分支 delta-3 剥，剥完空壳）|
| `finalize-review.py` | **整脚本删除** —— 100% 服务双文件 hash |
| `check-task-scope.py` / `audit-task-events.py` / `check-req-doc-drift.sh` | **(v0 漏)** 去 `.engineering.md` 的 allowlist / 豁免集 / drift 排除项 |
| `derive-structure-templates.py` | **(v0 漏)** 删「`task-NNN.engineering.md ≤200 行`」prose |
| 模板 | `task.md.tmpl` + `task.engineering.md.tmpl` 合并为单一 `task.md.tmpl`（typed 三区，§2.6）|
| `_shared` | `PM-VIEW-RULES.md` §二 / §9.6 作废；`input-flow.md` §9.4 改写（**前三类** sentiment → relevance 二分；视觉规范第四类归 close-task **不动**，D3-17）/ §9.6 删；`section-order.md` §七 重定 |
| references | `task-spec/references/few-shots.md` 大部分随章节移 PRD → 迁 `prd-writing` references；`engineering-impl-prose-merge.md` 的 B 层源从 `solution.md` 改 `implementation-design.md` |

**task-spec 步骤精简**（现 13 步 → 约 9 步）：删步骤 0（读 PM 视图规则子文件）/ 0.5 reconcile 模式 / 9 写工程合同+hash / 10.5 hash 自检 / 11.0 reconcile / 12.5 reconcile；步骤 6 重写（读 PRD + implementation-design）；步骤 7/7.5 改为「派生 task-scoped 自测说明 + 占位值写入执行区」（不再产 req 级主表，但保持 task 文件自包含，D3-5/D3-9）；步骤 8/9 合并为写单文件三区；步骤 10 拆解见 §2.8；步骤 12.6 压成 1 行（§2.2）。

### §2.6 双文件 21-section → 单文件 typed contract 归宿表（D3-7）

照 delta-8 §3.4 先例，逐 section 定归宿（vp-1 动手前据实际模板复核）。`task.md.tmpl` 10 段 + `task.engineering.md.tmpl` 11 段：

| 旧 section | 归宿 |
|---|---|
| PM视图·任务卡 | → PM 确认区·任务卡 |
| PM视图·关键产品决策 / 产物预览 / 占位字典(主表) / 功能清单 / 跨功能产品规则 | 已移 PRD（delta-2 §2.2）|
| PM视图·范围 | req 级移 PRD；task 级（这个 task 改哪）→ PM 确认区·task 级范围 |
| PM视图·验收清单 | req 级移 PRD §七；task 级 → PM 确认区·task 级验收 |
| PM视图·自测说明 | 主表移 PRD §七；task-spec 派生 **task-scoped 自测说明** → 执行区（task-verify 读，D3-5）|
| PM视图·历史档案 | → 审计区·历史档案 |
| 工程合同·元信息扩展（executor/model）| → PM 确认区·任务卡内字段（`resolve-executor.py` 改读这里）|
| 工程合同·状态转换说明 / 启动前必读 / 功能清单工程版 / 实现指引 | → 执行区（功能清单工程版与 PM视图功能清单切片转写合并为「实现规格」）|
| 工程合同·易错点/禁止项 / a11y·视口·视觉规范细则 | → 执行区·约束与易错（像素细则若体量大，vp-1 按 delta-8 §3.4 同款判断分流 DESIGN.md）|
| 工程合同·工程层验收清单 | → 执行区·工程层验收 |
| 工程合同·plan-review 沉淀 | → 审计区·历史档案（review 事件 append 保留，§2.3 步骤 11.1/11.2）|
| 工程合同·文档偏差 / 自审记录 | → 审计区（`task-transition.py`「执行中→已完成」gate 读，D3-4）|

→ 单文件模板**必须保留「文档偏差」「自审记录」两 section**，否则 `task-transition.py` 的「执行中→已完成」gate 失去锚点、对所有新 task 必败（§X D3-4）。task-scoped 占位值表内联进执行区·实现设计引用（executor 不跨文件回查 PRD，§X D3-9）。

### §2.7 旧格式兼容 + detect_format 三态（D3-6）

塌缩后仓里同时存在 **3 种 task 格式**：

| 格式 | 判别信号 |
|---|---|
| v1 老单文件（历史，薄 PM 视图）| 无 `.engineering.md` + 无 `task_format` 标记 |
| v2 双文件（在飞旧 task）| 有 `.engineering.md` |
| v3 新单文件 typed contract | 无 `.engineering.md` + 头部有 `<!-- task_format: single-typed-v3 -->` |

- `_lib/state.py` 的 `detect_format` 从二值改 **三态** —— 不能再用「无 `.engineering.md` = v1」（v3 也无 `.engineering.md`），靠 `task_format` 标记区分 v1 / v3。
- `task-confirm` / `task-execute` 的兼容模式文案按三态分流：v2 双文件 →「检测到旧格式 task（双文件），兼容模式继续」（中性，不说「缺失」）；v3 新单文件缺 `.engineering.md` 是正常 → **不报告警**。
- **在飞旧 v2 task 不回迁** —— 跑完旧的；`task-confirm` / `task-execute` / `close-task` 保留 v2 双文件兼容读路径。

### §2.8 guard 替换表（D3-9 —— 删 guard 不留静默漂移）

| 删掉的 guard | 原本拦什么 | v1 替换 |
|---|---|---|
| hash 自检（步骤 10.5）| AI 偷改 PM 决策保留的内容 | **保留为单文件最小 tamper-hash**（2026-05-21 eng-review A2，推翻 v1「换 prose」）—— 确认门退出对 **PM 确认区**算 hash、后续任何写入校验；不含双文件 reconcile / lazy-sync。机械 guard 守 binding-contract（对齐 memory `feedback_pm_decision_is_binding_contract`「确认门退出必算 hash 自检」）；revise prose 约束「只改 PM 要求改的、不顺手 normalize」作补充 |
| reconcile（11.0 / 12.5）| 双文件失同步 | 无需 —— 单文件无第二份 |
| 占位字典完整性闸门（10.7）| ASCII 占位词字典漏登记 → executor 无契约 | task-scoped 占位值内联进执行区（§2.6）；executor 不跨文件回查 |
| PM-view lint 整文件（10.5）| PM 视图写作违规 | `check-doc-pm-view.py` **scoped 模式** —— 改成只校验 PM 确认区（§2.1 / UC-1）|
| 字段校验（10.6）| 假执行产物（blockquote frontmatter / 非法状态值）| **保留** —— typed contract 仍需要 |
| 工程合同行数 lint（task-confirm 1.4）| PM 视图内容被重抄进工程合同 | 删 —— 单文件无「两文件重抄」问题，lint 失去存在理由（§X D3-13）|

**步骤 10 自检的 130 行 PM-view 纪律拆解**（§X D3-14）：步骤 10.A/10.B 的「实证高频违例区对照表」是 PM-view 写作纪律 —— vp-1 按区拆：**收窄到 PM 确认区**的（指代前缀 / 禁工程词 / 禁反向约束）随 scoped lint 保留；**只对实现规格才有意义**的（禁 UI 排版词等）对执行区**删**（执行区允许工程内容）。

---

## §3 实施清单（v1 —— vp 重新拆分，D3-11）

| vp | 改什么 | 依据 |
|---|---|---|
| vp-1 | **typed contract 模板** —— `task.md.tmpl` + `task.engineering.md.tmpl` 合并为单一 `task.md.tmpl`，三区结构（PM 确认区 / 执行区 / 审计区）+ `task_format` 标记 + §2.6 归宿表逐 section 落位；`section-order.md` §七 重定 | §2.1 §2.6（D3-1/D3-7）|
| vp-2 | **task-spec 删机器** —— 删 hash/reconcile/lazy-sync（步骤 9 hash / 10.5 hash 自检 / 11.0 / 12.5）；步骤 8/9 合并写单文件三区；落盘压成 1 行 `auto_commit_docs`（§2.2）；步骤 10 自检按 §2.8 拆 10.A/10.B | §2.2 §2.8（D3-8/D3-9/D3-14）|
| vp-3 | **task-spec 上游 reader 重写**（吸收 delta-2+4 vp-4b + delta-8 vp-3）—— 步骤 6 重写为读 `prd.md` 挑切片 + `implementation-design.md` 按 HOW-ID 挑行；步骤 7/7.5 改为派生 task-scoped 自测说明 + 占位值写入执行区 | §2.5 §2.6（D3-3/D3-5）|
| vp-4 | **relevance 二分 + 反馈承接清单** —— 步骤 5 改 relevance 二分；PM 确认区加「PM 反馈承接清单」；确认门摘要「承接X/不适用Z」；`input-flow.md` §9.4 前三类改写（视觉规范第四类不动）| §2.4（D3-12/D3-17）|
| vp-5 | **单一确认门** —— 删 task-confirm 步骤 3 PM 门；executor 切换非阻塞化；task-spec 步骤 12 加前置依赖检查 | §2.3（D3-15）|
| vp-6 | **scoped lint** —— `check-doc-pm-view.py` 加 scoped 模式（对 task 文件只校验 PM 确认区）| §2.1 §2.8（D3-1）|
| vp-7 | **detect_format 三态 + 旧格式兼容** —— `_lib/state.py` `detect_format` 三态、`read_section` 单文件查找；`task-confirm` / `task-execute` 兼容文案三态分流 | §2.7（D3-6）|
| vp-8 | **生命周期消费者迁移** —— `task-execute`（拆两文件约定 + §2/§3 分区读重写）/ `task-submit` / `task-verify` / `close-task` / `close-req` / `doc-update` / `create-task-worktree.sh` / `build-execution-prompt.py` 全切单文件 typed 区 | §2.5（D3-3/D3-5）|
| vp-9 | **运行时脚本迁移** —— `task-transition.py`（§10/§11 gate 单文件 + `--discard`）/ `resolve-executor.py`（字段源 + 复用 `state.py` 解析）/ `check-task-scope.py` / `audit-task-events.py` / `check-req-doc-drift.sh` 去双文件假设 | §2.5（D3-3/D3-4）|
| vp-10 | **死脚本 / references 清算** —— 删 `check-engineering-doc-size.py`（+ task-confirm 步骤 1.4）/ `finalize-review.py`；`derive-structure-templates.py` 删 task.engineering 行数 prose；`PM-VIEW-RULES.md` §二/§9.6 + `input-flow.md` §9.6 作废；references 清理（few-shots.md / engineering-impl-prose-merge.md）| §2.5（D3-13）|
| vp-11 | **测试 + SOP** —— test matrix（见下）；`框架同步-SOP.md` 补 delta-3 迁移段 + PM operator breadcrumb；明确新基线数 | §3 §5（D3-10）|

**vp-11 test matrix**（D3-10 —— 修 v0 的自相矛盾）：

| 测什么 | 动作 |
|---|---|
| typed contract 模板 | `task.md.tmpl` 三区齐 + `task_format` 标记；scoped lint 只校验 PM 确认区 |
| task-spec 单文件产出 | 产 1 个 `task-NNN-<slug>.md`、**断言不生成 `.engineering.md`**、无 hash 注释 |
| relevance 二分 | fixture：前序 task 含 `## PM 反馈`，新 task「PM 反馈承接清单」列「承接 / 不适用」各条 |
| **task-transition gate（D3-4 回归）** | 单文件含「文档偏差」「自审记录」→ `--to 已完成` 通过；缺则 fail |
| **task-verify UAT（D3-5 回归）** | 单文件执行区含 task-scoped 自测说明 → `task-verify` 不 skip |
| detect_format 三态 | v1 老单文件 / v2 双文件 / v3 新单文件 各判对 |
| 单一确认门 | stage 6 全程 PM 门计数 = 1；`task-confirm` 无 PM 门问句 |
| 落盘 | task-spec 确认门后 `auto_commit_docs` 落盘；pre-fork gate 仅异常触发 |
| **旧 v2 双文件兼容（IRON 回归）** | 旧 v2 task → `task-confirm` / `task-execute` / `close-task` 兼容跑完 |
| grep residual | **生产路径**断言无 `.engineering.md` / `synced_pm_view_hash` 生成；legacy 兼容代码 + 测试 fixture 的 `.engineering.md` 引用集中可数（与上一条**不同 grep**）|
| dead suites | `test-engineering-doc-size.sh` 全删、`test-reconcile-pm-view-immutability.sh` 删；逐一标改/删：`test-task-spec.sh` / `test-fixture-v2.sh` / `test-executors.sh` / `test-close-task.sh` / `test-pre-dispatch-doc-gate.sh` / `e2e/test-full-task-loop.sh` / `helpers/fixture.sh` |
| **单文件 tamper-hash（A2 回归）** | 确认门退出对 PM 确认区算 hash；后续写入若改动 PM 确认区 → 校验失败报错（binding-contract 机械 guard）|
| **in-flight 旧 req e2e（T2 / IRON 回归）** | 完整旧 req fixture（旧 solution.md + 旧 task 双文件 + solution.engineering.md）跑过 delta-2+3+4+7+8 同步后框架 → 走到 close 成功 |
| baseline | 明确新基线数（现 269）|

**落地顺序 + 跨 delta 文件 ownership**（D3-2 / D3-13 / D3-16）：

实际落地包 = delta-2+3+4+8，三个 delta 都改 `task-spec`。**delta-3 独占 task-spec 重写**，delta-2+4 vp-4b（切 `prd.md`）+ delta-8 vp-3（读 `implementation-design`）**并入 delta-3 vp-3**，不对 task-spec 做三次独立改动。

| 文件 | ownership |
|---|---|
| `task-spec` | delta-3 独占重写（吸收 **delta-2+4 vp-4b 的 task-spec 切片** + delta-8 vp-3；2026-05-21 eng-review F6 精确措辞 —— vp-4b 其余消费者 task-plan / close-req / status-view 等仍归 delta-2+4）|
| `check-engineering-doc-size.py` | delta-2+4 剥 solution 分支 → delta-3 **删整脚本**（vp-10）|
| `test-reconcile-pm-view-immutability.sh` | **delta-3 删整 suite**；delta-2+4 只剥其 solution 侧用例、不删整 suite（中间态 task 双文件仍在、task 侧覆盖仍有效）—— 2026-05-21 eng-review T1 已对齐 delta-2+4 vp-7 |
| `test-engineering-doc-size.sh` | delta-2+4 剥 solution 侧用例 → delta-3 删整 suite（随 `check-engineering-doc-size.py` 退场，vp-10）—— A3 补登 |
| `task.engineering.md.tmpl` | delta-3 vp-1 **删**；delta-8 vp-4 对它的引用标 obsolete |
| `build-execution-prompt.py` | delta-3 vp-8 改 1 路径（= 抽执行区，§2.5）；delta-8 §2 / vp-4 的「2 路径」措辞 v2 已作废 |
| `close-req` | delta-2+4 vp-4b 切 solution→prd 读；delta-3 §2.5 改 task 文件读为 typed 区锚点 —— **两 delta 顺序改不同部分**（2026-05-21 eng-review A3 补登）|
| `doc-update` | delta-2+4 vp-4b 切 solution→prd 读；delta-3 §2.5 改 task 读为 typed 区锚点 —— 同上（A3 补登）|

**⚠️ 连带：delta-8 v1 需 v1→v2**（§X D3-2 / D3-16）—— delta-8 `实现设计视图-HOW安家.md` v1 是已定稿文档，其 §1/§2/§3/§4.1 + D8-3/D8-5 决议**全部假设 task-spec 写进双文件 `task.engineering.md`**。delta-3 单文件 typed contract 推翻这个前提。delta-8 必须 v1→v2：所有「自包含 `task.engineering.md`」措辞改为「单文件 typed contract 的执行区」；「`build-execution-prompt.py` 2 路径零改」改 1 路径；vp-4 test matrix「2 路径」断言作废；delta-8 vp-3 并入 delta-3 vp-3。delta-3 落地前 delta-8 须先 v2。

**实施顺序**：delta-2+4 地基（建 `prd.md` / req-stage-gate 换芯）→ delta-8 vp-1/vp-2（建 `implementation-design` 模板 + skill）→ **delta-3 全部 vp**（task-spec 一次性重写吸收两个上游 reader）→ delta-8 v2 收尾（文档回写 + 残留引用清理）。

---

## §4 砍掉 / 不做的机制清单（防 review 回写）

1. ❌ 不保留双文件 —— task-spec 产单文件 typed contract（②④ 的根）
2. ❌ 不保留 reconcile / lazy-sync —— 随双文件删除；**hash 自检保留为单文件最小 tamper-hash**（2026-05-21 eng-review A2：守 binding-contract 的机械 guard，仅删双文件同步用途，见 §2.8）；**砍机制不砍 binding-contract 纪律**（PM 决策不可改，§2.2 / D3-9）
3. ❌ 不保留三类 sentiment 分流 —— 改 relevance 二分（§2.4）
4. ❌ task 文件不**整体**跳过 lint —— 执行区不跑 PM-view lint，但 **PM 确认区跑 scoped PM-view lint**（UC-1 修订 v0「完全不 lint」的错误表述）
5. ❌ task-spec 不再产 req 级产物预览 / 占位字典主表 / 自测说明主表 —— 已移 PRD（delta-2）；但 task-spec **仍派生 task-scoped 自测说明 + 占位值**进执行区（D3-5/D3-9 —— task 文件对 task-verify / executor 自包含）
6. ❌ task-confirm 不再设独立 PM 确认门 —— 单一门在 task-spec；但**依赖 gate 保留**（§2.3）
7. ❌ 不砍 same-req 反馈 lane 寄望 close-req —— `PRD-solution-对调.md` §X F11 已证「对后续 task 太晚」
8. ❌ 落盘不移 `create-task-worktree.sh` 当唯一机制 —— 留 task-spec（压成 1 行 helper），pre-fork gate 保持最后防线语义（D3-8 修订 v0）

→ 任何 review finding 想恢复以上任一条，必须 PM 显式更新 §0 并 v1 → v2。

---

## §5 风险与待验

- **task-spec 行数核实** —— `管线重构-GSD-review.md` §4.1 / §7 诊断记「1100+ 行」，**实测 748 行**；vp 估时按 748。
- **typed contract 的 scoped lint 边界** —— `check-doc-pm-view.py` scoped 模式靠区段标记定位 PM 确认区边界；待验：区段标记被写错时 lint 范围会漂。vp-6 测试覆盖。
- **delta-8 连带 v2** —— delta-3 单文件推翻 delta-8 v1 的双文件假设；delta-8 必须 v1→v2 且先于 delta-3 落地，否则 delta-8 vp-3 执行者拿失效指令。已登记 §3 ownership 表。
- **跨模块反馈 gap** —— relevance 二分 + 同模块 grep 装不下跨模块反馈；**DEFER 到 delta-9**（2026-05-21 改自 delta-7）：属「全项目跨功能产品行为规则」的 → delta-9 close-task selective promote 到 `PRODUCT-RULES.md`。「孤儿反馈终态」问题消解 —— 项目级规则常驻、不随 req 失效。
- **§2.6 归宿表逐 section 核实** —— 21-section 归宿是 review 逐条判定，vp-1 动手前用实际模板复核（尤其工程合同 a11y/视觉规范段实际体量、是否分流 DESIGN.md）。
- **三态兼容期** —— 仓里同时 v1/v2/v3 三格式；`detect_format` 三态 + 兼容文案三态分流是 IRON 回归重点。
- **本设计需先于实施定稿** —— delta-3 是最小落地包 delta-2+3+4+8 成员，与 `PRD-solution-对调.md` / `实现设计视图-HOW安家.md` 同一前置约束。

---

## §X Review Findings（autoplan / dual voice 输出落这里）

> 每条 finding 按 `_模板-方案.md` §X 格式。**PAIN_LINK = NONE 且 EVIDENCE = ASSUMED 的 finding 默认 DEFER**。

### Round 1 — 2026-05-21 — /gstack-autoplan（6 voices：CEO Codex+Claude · Eng Codex+Claude · DX Codex+Claude）

> **review 范围**：delta-3 v0（§0 已 PM 锁定）。`管线重构-GSD-review.md` §4.1 + `PRD-solution-对调.md` v1.1 + `实现设计视图-HOW安家.md` v1 视为锁定上下文。
> **设计评分**：CEO 4-6.5/10 · Eng 4-4.5/10 · DX 4-6/10。**结论**：§0 成立；§1-§5 非 implementation-ready（与 delta-2+4 v0 / delta-8 v0 同档）。需据本表 17 ACCEPT + 1 User Challenge 决议修订成 v1。三相 6 声收敛度异常高 —— 单文件该是 typed contract / blast radius 漏 consumer / 撞 delta-8，两模型独立落到同一批。

| # | Severity | Finding 摘要 | PAIN_LINK | EVIDENCE | 决议 |
|---|---|---|---|---|---|
| D3-1 | Critical | 单文件被定为「无 lint 执行合同」（§2.1），PM 唯一确认门（§2.3 还删了 task-confirm 的门）退化成盲签工程文档 —— 6 voice 全部命中 | §0.1 | `check-doc-pm-view.py:189,206`、`task-spec重构.md:69-71` | **ACCEPT（UC-1 PM 决议 2026-05-21）** —— 单文件改 typed contract：内部分「PM 确认区」(任务卡/范围/验收/反馈承接) +「执行区」；`check-doc-pm-view.py` 改 scoped 模式只校验 PM 确认区；不恢复双文件 |
| D3-2 | Critical | delta-3 单文件 vs **已定稿** delta-8 v1 双文件正面冲突；delta-8 D8-3/D8-5 critical 决议依赖「自包含 `task.engineering.md`」| §0.3 | `实现设计视图-HOW安家.md:53,76,144,203` | **ACCEPT** —— §3/§5 登记冲突；vp 纳入 delta-8 文档回写；delta-8 标记需 v1→v2 |
| D3-3 | Critical | blast radius 漏 live consumers：`task-execute`（最重）/ `task-submit` / `doc-update` / `close-req` / `task-transition.py` / `resolve-executor.py` / `_lib/state.py` / `check-req-doc-drift.sh` / `audit-task-events.py` / `check-task-scope.py` / `finalize-review.py` / `derive-structure-templates.py` | §0.3 | `task-execute/SKILL.md:17,221,395`、`task-submit:24`、`resolve-executor.py:82-84`、`state.py:64`、`finalize-review.py:150-163` | **ACCEPT** —— §2.5 连带清单补全 13+ 项；`finalize-review.py` 判删除 |
| D3-4 | Critical | `task-transition.py`「执行中→已完成」gate 跨文件读 §10 文档偏差 / §11 自审记录；单文件后 section 归宿不明 → `--to 已完成` 对所有新 task 必败 | §0.3 | `task-transition.py:210-235`、`state.py:160-191` | **ACCEPT** —— gate section 改单文件内查找；单文件模板必须保留「自审记录」「文档偏差」section |
| D3-5 | Critical | `task-verify` 读 task 文件 `## 🧪 自测说明`；delta-2 把它移 PRD + delta-3 删步骤 7.5 → 新 UI task 的 UAT 退化成 no-op | §0.3 | `task-verify/SKILL.md:29,55,70`、`task-execute/SKILL.md:455,477` | **ACCEPT** —— delta-3↔delta-2 衔接面：`task-verify` 读取源同步迁移到 PRD / task typed section |
| D3-6 | Critical | 新单文件 vs v1 老单文件不可区分（`detect_format` 靠「无 `.engineering.md`」判 v1）→ 迁移后误判 + 误导错误信息 | §0.3 | `state.py:64-67`、`task-confirm/SKILL.md:35-48`、`task-execute/SKILL.md:223` | **ACCEPT** —— 单文件加显式格式标记（`<!-- task_format: ... -->`）；`detect_format` 改三态（v1 老单文件 / v2 双文件 / delta-3 新单文件）|
| D3-7 | Critical | 缺「双文件 21-section → 单文件归宿表」；vp-5 模板合并无逐 section 映射 = 无法实施 | §0.3 | `task.engineering.md.tmpl`（11 章）、`task.md.tmpl`（10 章）、delta-8 §3.4 先例 | **ACCEPT** —— §2.5 加逐 section 归宿表（照 delta-8 §3.4），含 executor 元信息字段去向 |
| D3-8 | High | 落盘从 task-spec 步骤 12.6 移 `create-task-worktree.sh` pre-fork gate = fallback 当主路径；gate 现役是「异常告警」语义，扩大裸奔窗口 | §0.2.5 | `create-task-worktree.sh:69-95`、`task-confirm/SKILL.md:184` | **ACCEPT** —— 改方案：落盘留 task-spec 确认门后一步，25 行 prose 压成 1 行 helper 调用（痛点是 prose 啰嗦不是归属错）；pre-fork gate 留最后防线 |
| D3-9 | High | 删 hash 自检 / reconcile / 占位闸门后无等价错误面 → 静默漂移；binding-contract 纪律（PM 决策不可改）非双文件特有 | §0.3 | `task-spec/SKILL.md:424,444,478`、memory `feedback_pm_decision_is_binding_contract` | **ACCEPT** —— §2 补 validation replacement table；§4 注明「砍机制不砍 binding-contract 纪律」；revise 仍守「只改 PM 要改的、不顺手 normalize」|
| D3-10 | High | vp-8 test matrix 自相矛盾（IRON 兼容 vs「无 `.engineering.md` residual」同一 grep 表达不了）+ 漏列会失败 suite | §0.3 | `tests/run-all.sh:21,40,53`、`test-task-spec.sh` / `test-fixture-v2.sh` / `test-close-task.sh` / `test-pre-dispatch-doc-gate.sh` / `e2e/test-full-task-loop.sh` | **ACCEPT** —— 生产新格式断言「不生成 `.engineering.md`」、legacy adapter/test 集中保留引用；逐 suite 标改/删 |
| D3-11 | Medium | vp 颗粒度过载：vp-1（重写+读PRD+读impl-design+删hash+删term-detector+删UAT）/ vp-6（10+消费者）/ vp-8 都超载 | §0.3 | `task-spec重构.md:148,153,155` | **ACCEPT** —— 拆细（vp-1→纯删 / 跨-delta reader 吸收 / 功能迁移 三条）|
| D3-12 | Medium | relevance「不适用」反馈对 PM 黑盒；同模块 grep 装不下跨模块反馈 | §0.1 | `task-spec重构.md:91`、`task-spec/SKILL.md:120-122`（同模块 grep）| **ACCEPT** —— 加「PM 反馈承接清单」（source/relevance/处理结果/理由）；确认门摘要「承接X/延后Y/不适用Z」；跨模块反馈传播标 DEFER→delta-7 |
| D3-13 | Medium | `check-engineering-doc-size.py`：delta-2+4 剥 solution 分支、delta-3 剥 task 分支 → 空壳无人认领删除 | §2.5 | `PRD-solution-对调.md:229`（F17）、`check-engineering-doc-size.py`、`task-confirm/SKILL.md:49-74` | **ACCEPT** —— delta-3 负责删整个脚本 + task-confirm 步骤 1.4 整步删（单文件无「两文件重抄」问题，行数 lint 失去存在理由）|
| D3-14 | Medium | 步骤 10 的 130 行 PM-view 自检纪律（10.A/10.B）§2.5 一个「留(精简)」带过、无删/留清单 | §0.1 | `task-spec/SKILL.md:397-422` | **ACCEPT** —— vp 显式拆 10.A/10.B 哪几条删、哪几条收窄到「PM 确认区」段 |
| D3-15 | Medium | task-confirm 退化机械 fork 后：依赖 gate（步骤 4-pre）必须保留；executor 切换是非阻塞交互需说清呈现；建议 task-spec 确认门前置依赖检查 | §0.2.4 | `task-confirm/SKILL.md:142-168`、§2.3 | **ACCEPT** —— §2.3 澄清依赖 gate 保留、executor 切换「机械+一次非阻塞告知」；§2.5 步骤 12 加前置依赖检查 |
| D3-16 | Medium | `build-execution-prompt.py`：delta-3 改 1 路径 vs delta-8 说「2 路径零改」+ delta-8 vp-4 test 断言 2 路径会失败 | §0.3 | `task-spec重构.md:137`、`实现设计视图-HOW安家.md:78,154` | **ACCEPT** —— 并入 D3-2 的 delta-8 回写；delta-8 §2/vp-4 的「2 路径零改」措辞作废 |
| D3-17 | Low | `input-flow.md` §9.4 是「四类」分流（第四类视觉规范归 close-task 消费）；delta-3 §2.5 误写「三类」| §2.5 | `input-flow.md` §9.4 | **ACCEPT** —— 精确为「前三类」，视觉规范第四类保持不动 |
| D3-18 | Low | §2.5 砍 `brief`/`analysis`：`analysis` 应保留为按需 lazy fallback（PRD 切片不足时声明式回读并告知 PM），不是砍 | §2.5 | `input-flow.md:96-97`（现役已标 ⚪）| **ACCEPT** —— `analysis` 改「⚪ 按需 lazy fallback」；`brief` 砍保留 |

**汇总**：ACCEPT 18 条（D3-1 经 UC-1 PM 决议 ACCEPT；D3-2~D3-18）/ DEFER 0 / 待决 0。

**User Challenge UC-1（typed contract）**：PM 2026-05-21 决议 —— 单文件改 typed contract（内部分 PM 确认区 + 执行区，scoped lint 只校验 PM 确认区，不恢复双文件）。见 §Y。

### Round 2 — 2026-05-21 — /gstack-plan-eng-review（delta-2+3+4+8 包复核 · 含 codex outside-voice）

| # | Severity | Finding 摘要 | 决议 |
|---|---|---|---|
| A2 | P2 | §2.8 把 binding-contract guard 从 hash 自检降级为 prose；memory `feedback_pm_decision_is_binding_contract` 记「确认门退出必算 hash 自检」为该机制 | **ACCEPT（PM 决议）** —— §2.8 / §2.2 / §4 保留**单文件最小 tamper-hash**（确认门退出对 PM 确认区算、后续写入校验；不含双文件 reconcile）|
| A3 | P3 | §3 跨-delta ownership 表漏 close-req / doc-update（被 delta-2+4 + delta-3 两 delta 改）| **ACCEPT** —— §3 ownership 表补 close-req / doc-update / test-engineering-doc-size.sh，完整性扫一遍 |
| F6 | P3 | §3「delta-2+4 vp-4b 并入 delta-3 vp-3」措辞易读成整个 vp-4b 并入（实际只 task-spec 切片）| **ACCEPT** —— §3 改为「vp-4b 的 task-spec 切片」|
| T2 | P2 | 缺 in-flight 旧 req 端到端回归 —— 三份文档各测一片兼容、无 e2e | **ACCEPT（IRON）** —— vp-11 test matrix 加完整旧 req e2e |
| T3 | P2 | A2 决议产生新测试需求（单文件 tamper-hash）| **ACCEPT** —— vp-11 test matrix 加 tamper-hash 回归 |
| P1-perf | P3 | §2.5 build-execution-prompt.py「1 路径」未写明塞整文件还是抽执行区 | **ACCEPT** —— §2.5 写死「1 路径 = 抽取执行区」，executor 信封不带 PM 确认区 / 审计区 |

**汇总**：6 ACCEPT；0 待决。A2 推翻 v1 §2.8「hash 自检换 prose」。最小落地包扩 delta-7（codex#4，见 umbrella §8）。文档 v1 → v2。

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-20 | 文档创建（AI 起草 v0）；§0 待 PM 共写锁定；§1 五个设计问题待逐题过；§2 已填 v0 推荐答案 | — |
| 2026-05-20 | §0 经 PM 确认锁定（「痛点没有问题」）；§1 五题 PM 确认按 v0 推荐收口 —— Q1 单文件执行合同、Q2 hash 整组删 + 落盘移 `create-task-worktree.sh` pre-fork gate、Q3 单一门留 task-spec、Q4 relevance 二分 + 保留 same-req 反馈 lane、Q5 读 prd.md + implementation-design.md 砍 brief/analysis/prototypes | §0 不可再反向修改；§2 为收口方案；delta-3 v0 进入可 review 状态 |
| 2026-05-21 | /gstack-autoplan 6-voice review 完成（§X Round 1）—— 18 finding：7 critical / 3 high / 6 medium / 2 low；评分 CEO 4-6.5 · Eng 4-4.5 · DX 4-6。三相 6 声强收敛 | §1-§5 非 implementation-ready，待修订 v1 |
| 2026-05-21 | §X D3-2~D3-18 共 17 条 ACCEPT；D3-1 转 User Challenge UC-1（typed contract）待 PM 决策 | 下一步 PM 决 UC-1 → 据 §X 修订 v1 |
| 2026-05-21 | UC-1 PM 决议：单文件改 **typed contract** —— 内部分「PM 确认区」(任务卡/范围/验收/反馈承接) +「执行区」(实现规格/易错点/工程验收)，`check-doc-pm-view.py` 改 scoped 模式只校验 PM 确认区；不恢复双文件、§0 不动 | D3-1 ACCEPT；§X 18 finding 全决议，下一步据 §X 修订 v1 |
| 2026-05-21 | v1 修订完成：§1-§5 据 §X Round 1（18 finding 全决议）改写 —— typed contract 三区结构（§2.1/§2.6）、落盘留 task-spec（§2.2）、反馈承接清单（§2.4）、blast radius 补全 19 项 + detect_format 三态（§2.5/§2.7）、guard 替换表（§2.8）、vp 重拆为 11 条、登记 delta-8 需 v1→v2 | 文档 v0 → v1 |
| 2026-05-21 | /plan-eng-review 包复核（§X Round 2）：6 finding 全 ACCEPT —— §2.8 保留单文件 tamper-hash（A2 推翻 v1「hash 整组删」）、§3 ownership 补 close-req/doc-update（A3）、§2.5 信封抽执行区（P1-perf）、vp-11 补 e2e + tamper-hash 测试（T2/T3）、措辞精度（F6）。最小落地包扩 delta-7 → delta-2+3+4+7+8 | 文档 v1 → v2 |
| 2026-05-21 | 连带：delta-9 设计完成 → §2.4 / §5 跨模块反馈「DEFER 到 delta-7」改指 **delta-9**（跨功能产品行为规则 → close-task selective promote 到 `PRODUCT-RULES.md`）；孤儿反馈终态问题消解。最小落地包 → delta-2+3+4+7+8+9 | §2.4 / §5 re-point（连带 reference 修正，不升版本）|

---

**End of task-spec 重构（delta-3）v2**

---

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` (via /autoplan) | Scope & strategy | 1 | issues_open | 4-6.5/10 — §0 成立；§1-§5 范围漏 consumer、撞 delta-8、3 处实质决策推给实施期 |
| Eng Review | `/plan-eng-review` | Architecture & tests | 2 | issues_open | R1 (autoplan v0): 18 finding；R2 (2026-05-21 包复核): 6 finding 全决议（A2 保留 tamper-hash / A3 / F6 / T2 / T3 / P1-perf）→ v1→v2 |
| DX Review | `/plan-devex-review` (via /autoplan) | Operator experience | 1 | issues_open | 4-6/10 — 确认门盲签、格式迁移错误信息误导、删 guard 后静默漂移、反馈 lane 黑盒 |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | — | skipped — 无 UI scope（重构 skill / 模板 / 脚本，不建界面）|

- **CROSS-MODEL**：6 voices（Codex ×3 + Claude subagent ×3），收敛度异常高 —— 两模型独立落到同一批 critical（单文件应 typed contract / blast radius 漏 consumer / 撞已定稿 delta-8）。memory `feedback_autoplan_preread_existing_skill` 应用：6 个 dual-voice prompt 全部强制前置读实际 repo skill + 脚本，故 finding 全带 file:line。
- **CROSS-PHASE THEME**：「单文件不该裸成无 lint 执行合同」在 CEO / Eng / DX 三相独立出现 → 高置信信号，转 User Challenge UC-1。「blast radius 漏 consumer」CEO + Eng 双相命中。「撞 delta-8」三相命中。
- **UNRESOLVED**：0 —— Round 1：D3-1 经 UC-1 PM 决议 ACCEPT + D3-2~D3-18 共 18 ACCEPT；Round 2：6 finding（含 codex outside-voice）全决议。
- **VERDICT**：delta-3 v2 —— 经 autoplan(v0→v1) + /plan-eng-review 包复核(v1→v2)，§0 成立、两轮 finding 全落地、0 待决。**ENG 待 delta-2+3+4+7+8 整包复跑 /plan-eng-review 确认**再实施。最小落地包 = **delta-2+3+4+7+8**。
