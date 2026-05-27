<!-- /autoplan restore point: <LOCAL_GSTACK_HOME>/projects/PM-AI-Workflow/main-autoplan-restore-20260426-120923.md -->

> ⚠️ **历史文档（2026-05-06 部分内容已被覆盖）**：本文档记录的是 v3.5 阶段的初始改造决定，其中"reviewer 内部循环到 PASS"的设计已在 2026-05-06 改为"reviewer 一轮一停 + PM 三选一决策"模式。最新设计以 `skills/req-analysis/SKILL.md` + `memory/project_stage2_reviewer.md` 为准；本文档作为历史记录保留，未决问题闸门、双 skill 切分、orchestrator 职责等其他部分仍生效。

# Stage 2 / Stage 3 独立 skill 改造计划

## Context

**项目定位**：PM 单人**工程化**工作流框架（非简化版，非团队 SOP；CLAUDE.md 第一行的"单人 PM 工具"表述将随项目演化更新——它指的是"单人使用的工程化框架"，不是"简版个人工具"）。10 章 solution.md / 第一性原理 4 层框架 / 强制 reviewer 闸门 是工程化定位的体现，不是 over-engineering。

**问题来源**：经过几个真实 req 实际跑下来，stage 2/3 的体验有摩擦——
- Stage 2 内联段膨胀到 60+ 行（reviewer 调用 + 未决问题闸门 + 答题循环），跟 `req-stage-gate` 的"调度"职责混在一起。PM 改这一段时认知负担高
- Stage 3 内联段只有 2 行（"读 analysis.md → 写 solution.md → 调 plan-ceo-review"），太单薄，PM 实际写 solution.md 时没有结构指引，每次靠 LLM 即兴生成结构，章节漂移

**改造动机**：把"写文档"职责从 orchestrator 抽到独立 skill，**职责切分**：
- 子 skill 负责"读输入 → 写产出 → 内部跑完 reviewer 循环（仅 stage 2）→ 把 PASS 契约交回"
- orchestrator 负责"调度子 skill → 走未决问题闸门 → 推进 stage"

旧仓 `pm-ai-workflow-template/.claude/skills/` 里有两份成熟资产：
- `requirement-analysis/SKILL.md`（343 行）— stage 2，自带第一性原理 4 层框架、固定 10 章结构、批判性自检清单
- `solution-design/SKILL.md`（273 行）— stage 3，自带 10 章 solution.md 结构、Mermaid 架构图模板、写作规则、模块优先级排序框架

本次改造：把这两份旧 skill 改造后引入新仓，`req-stage-gate` 退化为纯调度器。**不直接搬**——旧 skill 跟新仓在路径、闸门、reviewer 三处冲突，必须先对齐。

预期结果：
- `skills/req-analysis/SKILL.md` 新建（基于旧 `requirement-analysis` 改造）
- `skills/req-solution/SKILL.md` 新建（基于旧 `solution-design` 改造）
- `skills/req-stage-gate/SKILL.md` 修改：Stage 1→2 / Stage 2→3 两段从"内联流程"替换为"调用对应 skill + 走闸门/确认"

---

## 职责切分（核心决定）

跟现有 `task-plan` 的模式对齐：**子 skill 写文档 + 内部循环（含 reviewer），调度 skill 接手闸门和推进。**

**关键契约（明确边界，避免后续状态机跨文件漂移）**：

```
req-stage-gate
  ├─ 调 /pmai-req-analysis（异步等待返回；返回时 = 隐含 reviewer PASS 契约）
  ├─ grep analysis.md 的 ## 未决问题 section → 走闸门
  └─ PM 答完 → 推进 stage 2

req-analysis（自包含）
  ├─ 读 brief.md（输入）
  ├─ 写 analysis.md（产出，含 10 章 + ## 未决问题 section）
  ├─ 调 analysis-reviewer
  ├─ NEEDS_REVISION → 改 analysis.md → 重调（循环到 PASS）
  └─ skill 退出 = 契约保证 reviewer 已 PASS

req-stage-gate（stage 2→3）
  ├─ 调 /req-solution
  ├─ 调 /plan-ceo-review（讨论性 review，结果贴 chat）
  └─ 走确认门 → 推进 stage 3

req-solution（自包含）
  ├─ 读 analysis.md（输入）
  ├─ Discovery 缺口提问（可选，stage 3 没未决问题硬规则）
  ├─ 写 solution.md（产出，含 10 章 + Mermaid + 7.2 模块说明）
  └─ skill 退出（不调 reviewer，stage 3 review 在 orchestrator）
```

**不允许的反模式**（CEO subagent F2 揪出的潜在矛盾）：
- ❌ orchestrator 重复调 reviewer（重调浪费、且让 PASS 状态隐式跨文件）
- ❌ skill 内部走确认门（确认门是 orchestrator 职责）
- ❌ skill 内部调 req-transition.py（推进命令是 orchestrator 职责）

| 职责 | req-analysis（新） | req-solution（新） | req-stage-gate（改） |
|---|---|---|---|
| 读 brief / analysis 上下文 | ✅ | ✅ | — |
| 第一性原理分析 / 写 analysis.md | ✅ | — | — |
| 模块/分期/架构 / 写 solution.md | — | ✅ | — |
| 调 analysis-reviewer 直到 PASS | ✅（**完整循环在 skill 内部跑完**） | — | — |
| 调 /plan-ceo-review | — | — | ✅（review 是讨论，留在调度） |
| 未决问题闸门（Q&A 答题）| — | — | ✅ |
| 确认门 + 推进命令 | — | — | ✅ |

子 skill 的退出条件：文档已写、reviewer PASS（仅 stage 2，PASS 报告也展示给 PM 让它知道评过）。退出后控制权回到 `req-stage-gate`，**orchestrator 不重复调 reviewer**（隐式信任 skill 退出契约 = PASS），由它读文档判断未决问题状态、跑 review、走确认门。

---

## 改造细节 1：`skills/req-analysis/SKILL.md`（stage 2 新建）

### 命名 & 触发

```yaml
---
name: req-analysis
description: |
  Stage 2：读 brief.md 做第一性原理批判性分析，写 analysis.md（10 章固定结构 + ## 未决问题 section），
  内部循环调 analysis-reviewer 直到 PASS。由 /pmai-req-stage-gate 在 stage 1→2 时调用。
---
```

### 段落结构（约 180 行，按以下顺序）

1. **Preamble**（≈3 行）— 与 task-plan 一致：source skill-preamble.sh + echo SKILL 名。
2. **When To Use**（≈3 行）— "Orchestrator 在 stage 1→2 调用（由 /pmai-req-stage-gate 触发）"。
3. **Role 角色设定**（≈8 行）— 从旧仓 §Role 摘核心 5 条特质 + 1 条核心信条 + 5 条行为准则。砍掉旧仓的"务实主义者""透明化不确定性"展开，简洁化。
4. **Required Inputs**（≈4 行）—
   - `$ACTIVE_REQ_DIR/brief.md`（必需）
   - `$REPO_ROOT/docs/CONTEXT.md`（如存在）
   - `$REPO_ROOT/docs/prd.md`（如存在）
5. **First Principles Analysis 框架**（≈30 行）— 旧仓 4 层全保留：问题解构 / 假设清洗 / 从零重建 / 约束验证。这是 stage 2 的核心方法论，价值高。**标注为"内部推理，不直接展示给 PM，但必须影响 analysis.md 输出"**。
6. **Workflow**（≈30 行）—
   - 步骤 1：读输入文档建立基线
   - 步骤 2：执行第一性原理 4 层（内部推理）
   - 步骤 3：写 `$ACTIVE_REQ_DIR/analysis.md`，必须含下方 §Analysis Structure 的 10 章 + `## 未决问题` section
   - 步骤 4：**强制调 analysis-reviewer**（搬现 req-stage-gate 第 35–55 行的 Agent 调用样例 + 处理逻辑）
   - 步骤 5：**reviewer 循环（完整在 skill 内部跑完）**：
     - reviewer 返回 NEEDS_REVISION → 把报告贴 chat 给 PM 看 → 按建议改 analysis.md → 回步骤 4 重调
     - reviewer 返回 PASS → 把 PASS 报告贴 chat 给 PM 看（让 PM 知道评过）→ skill 结束
     - **退出契约**：skill 返回主流程时，analysis.md 已经过 reviewer PASS。orchestrator 不需要也不应该重调
   - 步骤 6（**硬禁止项**）：
     - ❌ skill 内部展示推进选项（A 进 stage 3 / B 修改 / C 跳）— 这是 orchestrator 闸门职责
     - ❌ skill 内部展示未决问题答题模式 — 闸门在 orchestrator
     - ❌ skill 内部调 req-transition.py — 推进命令在 orchestrator
     - ❌ skill 内部跳过 reviewer 循环（"快速通道"、"简单 req 跳过 reviewer" 等都禁止）
7. **Analysis Structure**（≈25 行）— 10 章固定结构（旧仓 §Analysis File Persistence Guard 上面那段 10 章）：
   1. 需求动机溯源（Why）
   2. 现状总结（As-Is）
   3. 合理性审视（Should）
   4. 可行性论证（Can）
   5. 关键决策确认（已确认 / 待确认 / 假设）
   6. 风险与代价分析（做 / 不做 / 做错三维矩阵）
   7. 拟采取方案（推荐 + 备选 + 取舍理由）
   8. 范围边界（In Scope / Out of Scope）
   9. 依赖与约束
   10. 验收口径
   - 加 `## 未决问题` section（与现 req-stage-gate 第 32–33 行格式一致：`### Q1: <标题>` + 题干 + 候选答案 + `**PM 回答：**` 占位；无问题时显式写"本 req 无未决问题"）
8. **Critical Questions Checklist**（≈12 行）— 旧仓 §Critical Questions Checklist 全搬：需求层面 / 方案层面 / 风险层面 共 9 条自检项。
9. **Output Rules**（≈10 行）— 砍掉旧仓与新仓冲突的几条：
   - **保留**：第一性原理推导论证、代价透明、批判性原则（每个需求至少一条值得商榷之处）、待确认问题逐一列出禁摘要、用户回答必须立即回写
   - **删除**：`user-context/user_preferences.md` 对齐（新仓没这套）、"如无调整可继续下一阶段"等跳过引导（与未决问题闸门冲突，但本 skill 本来就不做闸门）
10. **Common Mistakes**（≈10 行）— 旧仓 §Common Mistakes 8 条全搬。
11. **阶段 2 边界**（≈6 行）— 简洁版：
    - 允许产出：`$ACTIVE_REQ_DIR/analysis.md`
    - 允许动作：第一性原理分析、提出未决问题、调 analysis-reviewer
    - 禁止：自动产出 solution.md / task-plan.md、走确认门、推进 stage、提供"带假设前进"逃生舱

### 与旧仓的差异点（必须改的）

| 点 | 旧仓 | 新 skill |
|---|---|---|
| 输入文件 | `docs/input.md` | `$ACTIVE_REQ_DIR/brief.md` |
| 输出文件 | `docs/analysis.md` | `$ACTIVE_REQ_DIR/analysis.md` |
| 未决问题格式 | "待确认问题"独立区块 + 关键决策表"待确认/已确认" | `## 未决问题` section + `### Q1:` + `**PM 回答：**` 占位（与新仓现有规则一致） |
| reviewer 调用 | 无 | 步骤 4 强制调，循环到 PASS |
| 阶段 2 结束模板 | 旧 §阶段 2 结束模板（两步确认 + 推进选项） | **删除**（确认/推进留给 req-stage-gate） |
| 带假设前进规则 | 旧 §阶段 2 退出条件鼓励 `[假设: ...]` | **删除**（违反 memory `feedback_open_questions_gate` 不留逃生舱） |
| user-context 偏好对齐 | 有 | 删除（新仓没有 personal-preference 系统） |

---

## 改造细节 2：`skills/req-solution/SKILL.md`（stage 3 新建）

### 命名 & 触发

```yaml
---
name: req-solution
description: |
  Stage 3：读 analysis.md 做系统分层、模块边界、分期计划，写 solution.md（10 章固定结构 + Mermaid 架构图）。
  由 /pmai-req-stage-gate 在 stage 2→3 时调用；review 与推进交回调度 skill。
---
```

### 段落结构（约 200 行，按以下顺序）

1. **Preamble**（≈3 行）— 同上。
2. **When To Use**（≈5 行）— "Orchestrator 在 stage 2→3 调用（由 /pmai-req-stage-gate 触发）" + 旧仓的"复杂需求才需要"提示（多服务/新基础设施/>3 模块）。
3. **Required Inputs**（≈5 行）—
   - `$ACTIVE_REQ_DIR/analysis.md`（必需）
   - `$ACTIVE_REQ_DIR/brief.md`（必需）
   - `$REPO_ROOT/docs/CONTEXT.md`（如存在）
   - `$REPO_ROOT/docs/DESIGN.md`（如存在）
4. **Workflow**（≈20 行）—
   - 步骤 0 Discovery：读 analysis.md，识别分期 / 架构关键依赖 / 全局约束 是否已明确，有缺口先编号提问 PM（这是 stage 3 内部的小 Q&A，跟 stage 2 的未决问题不同——stage 3 没有"未决问题闸门"硬规则，但 PM 没回答前不要硬写方案）
   - 步骤 1：按下方 §文档结构 写完整 `$ACTIVE_REQ_DIR/solution.md`
   - 步骤 2：skill 结束，控制权交回 /pmai-req-stage-gate（由它跑 /plan-ceo-review + 走确认门）
   - **禁止项**：禁止 skill 内部走确认门、调 req-transition.py
5. **文档结构**（≈100 行）— 旧仓 §文档结构 10 章原样搬，路径调整：
   1. 摘要
   2. 文档版本信息
   3. 变更日志
   4. 名词解释
   5. 需求分析（4.1 问题陈述 / 4.2 解决方案 / 4.3 成功指标 / 4.4 方案价值）
   6. 用户与场景（5.1 角色 / 5.2 用户故事 / 5.3 非目标）
   7. 技术架构（6.1 架构概述 + Mermaid / 6.2 集成点 / 6.3 安全与隐私）
   8. 功能范围与约束（7.1 模块清单 / 7.2 各模块说明 / 7.3 非功能性要求）
   9. 分期计划
   10. 风险与假设（9.1 技术风险 / 9.2 约束与假设）
   - 7.2 节的"各模块功能说明"模板原样搬（包含页面 / 核心功能点 / In Scope / Out of Scope / 验收口径）—— task-plan stage 5 拆 task 时会指向这里。
6. **写作规则**（≈8 行）— 旧仓 §写作规则 全搬。
7. **模块优先级排序框架**（≈8 行）— 旧仓 §模块优先级排序框架 全搬（核心链路 / 设计范式 / 依赖最少）。
8. **阶段 3 边界**（≈6 行）— 简洁版同 req-analysis 风格。

### 与旧仓的差异点

| 点 | 旧仓 | 新 skill |
|---|---|---|
| 输入文件 | `docs/analysis.md` + `docs/input.md` | `$ACTIVE_REQ_DIR/analysis.md` + `$ACTIVE_REQ_DIR/brief.md` |
| 输出文件 | `docs/solution.md` | `$ACTIVE_REQ_DIR/solution.md` |
| 阶段 3 结束模板 | 旧 §阶段 3 结束模板（两步确认） | **删除**（交回 /pmai-req-stage-gate） |
| Few-shots 引用 | 旧 `references/few-shots.md` | **搬过来** → `skills/req-solution/references/few-shots.md`。理由：项目走工程化方向，需要稳定的输出粒度，canonical example 约束 LLM；PM=作者=用户，"等用户 complain" 不是有效反馈回路。skill 末尾加一行：`读取 .claude/skills/req-solution/references/few-shots.md 获取各章节示例` |
| `/plan-eng-review` `/plan-design-review` 提示 | 旧 §模块优先级排序框架末尾"可选工具" | 保留 |

---

## 改造细节 3：`skills/req-stage-gate/SKILL.md` 修改

只动两段，其它不动。

### Stage 1 → 2 段（替换 24–92 行）

替换为：

```
### Stage 1 → 2（感受问题 → 需求分析）

1. 检查 `brief.md` 存在且有内容
2. **调用 /pmai-req-analysis**
   - skill 内部完成：读 brief + CONTEXT、第一性原理分析、写 analysis.md（含 10 章 + ## 未决问题 section）、循环调 analysis-reviewer 到 PASS
   - skill 返回 = 契约保证 analysis.md 已 PASS。**orchestrator 不重复调 reviewer**
3. **未决问题闸门**（保留现 §6 / §7 全部逻辑）
   - grep `## 未决问题` section 下 `**PM 回答：**` 占位
   - 有空 → 答题模式（A 逐题答 / B 修改 analysis）
   - 全填 → 推进模式（A 进 stage 3 / B 修改 / C 跳到 stage 5 后续 req 可选）
   - PM 选 B 修改 → 回步骤 2 重调 /pmai-req-analysis（analysis 改了 reviewer 在 skill 内重评，orchestrator 仍不参与 reviewer）
4. PM 答完 / 确认推进 → 执行推进命令：
    python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 2
```

净减少 ~40 行内联代码，但**关键改善是职责切分**：reviewer 循环 + analysis.md 写作完全在 req-analysis 内部，orchestrator 只读 PASS 契约 + 走闸门 + 推进。状态机不再跨 2 个文件。

### Stage 2 → 3 段（替换 94–112 行）

替换为：

```
### Stage 2 → 3（需求分析 → 方案设计）

PM 选择进入 stage 3 时：
1. **调用 /req-solution**
   - skill 内部完成：Discovery 缺口提问（如有）、写 solution.md（含 10 章 + Mermaid）
2. **自动调用 /plan-ceo-review** 审阅 solution.md（所有 req 都自动运行，不可跳过）
3. **确认门**：只给绝对路径（$ACTIVE_REQ_DIR/solution.md）+ 一句话摘要；review 发现直接贴 chat
   - PM 确认 → 推进到下一 stage
   - PM 提修改意见 → 回步骤 1 重调 /req-solution → 再 review → 再确认
4. PM 选择跳过 stage 3 时：
    python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 5 --skip-stage 3
   正常推进时：
    python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 3
```

净增约 4 行（增加调 /req-solution 的步骤 1）。

### 不动的段

Stage 3→4 / Stage 4 / Stage 4→5 / Stage 5→6 / Stage 6→7 / Rules 段全部保留原样。

---

## 关键文件路径

需要新建：
- `${REPO_ROOT}/skills/req-analysis/SKILL.md`
- `${REPO_ROOT}/skills/req-solution/SKILL.md`
- `${REPO_ROOT}/skills/req-solution/references/few-shots.md`（从旧仓复制）

需要修改：
- `${REPO_ROOT}/skills/req-stage-gate/SKILL.md`（替换 Stage 1→2、Stage 2→3 两段）

参考资产（只读 + 搬运目标）：
- `${LEGACY_REPO_ROOT}/.claude/skills/requirement-analysis/SKILL.md`（改造为 `skills/req-analysis/SKILL.md`）
- `${LEGACY_REPO_ROOT}/.claude/skills/solution-design/SKILL.md`（改造为 `skills/req-solution/SKILL.md`）
- `${LEGACY_REPO_ROOT}/.claude/skills/solution-design/references/few-shots.md`（**直接 copy** 到 `skills/req-solution/references/few-shots.md`）

复用约定：
- 参照 `skills/task-plan/SKILL.md` 的 frontmatter / Preamble / "由 /pmai-req-stage-gate 触发" 措辞，保持新仓 skill 风格一致
- 参照 `agents/analysis-reviewer.md` 的输入路径约定（`$ACTIVE_REQ_DIR/analysis.md`、`$ACTIVE_REQ_DIR/brief.md`）

---

## 已避开的反模式（来自 memory）

- `feedback_no_tool_replaces_skill` — 不用 advisor / 单一 subagent 替代 skill 流程；reviewer 在 skill 内部循环，不替代 skill
- `feedback_open_questions_gate` — 不引入"带假设前进"逃生舱；闸门留在 req-stage-gate
- `feedback_confirmation_gates` — 子 skill 不展示文档全文给 PM；确认门由 req-stage-gate 给绝对路径 + 一句话
- `project_stage2_reviewer` — analysis-reviewer 强制调用保留，PASS 才解锁后续

---

## Verification

人工验证步骤（无自动化测试，新仓 tests/ 没有 stage 2/3 e2e 测试用例）：

1. **手工跑一个测试 req**：
   - `/pmai-new-req "测试 stage 2/3 skill 改造"` → 进 stage 1，写 brief.md
   - `/pmai-req-stage-gate` → 应触发 /pmai-req-analysis
2. **检查 stage 2**：
   - analysis.md 含 10 章 + `## 未决问题` section
   - skill 自动调用 analysis-reviewer，输出评审报告
   - 故意让 analysis 缺一条未决问题 → reviewer 应返回 NEEDS_REVISION → 主线按建议改 → 重调 reviewer 直到 PASS
   - PASS 后 skill 退出，req-stage-gate 接管 → 走未决问题闸门
3. **检查 stage 3**：
   - 答完未决问题 → 推进 stage 2→3 → 触发 /req-solution
   - solution.md 含 10 章 + Mermaid 架构图 + 7.2 各模块说明（task-plan 后续会读）
   - skill 退出 → req-stage-gate 跑 /plan-ceo-review → 走确认门
4. **回归检查**：
   - 跑 `bash tests/...`（如有相关脚本）确认 req-stage-gate 改动没有破坏 stage 5/6/7
   - 检查 `requirements/active/<req>/` 目录下 analysis.md / solution.md 实际内容
5. **edge case**：
   - "本 req 无未决问题" 路径走通（应该直接进入推进模式）
   - PM 在闸门里选 B 修改 analysis → 触发 reviewer 重评

---

## 不在本次改造范围

- 旧仓的 `personal-preference-capture` / `experience-capture` 等记忆系统（新仓刻意没引入）
- 新增 stage 2/3 的自动化测试用例（tests/ 现状没覆盖，本次改造不补；如出问题再加）
- task-plan / module-spec / prd-writing 的逻辑（这些不动）
- CLAUDE.md "PM 单人生产力工具" 表述更新（建议跟本次改造分开做一次单独 PR，更准确说明"单人 PM 工程化框架"定位）

---

# /autoplan Review Report

## Phase 1 — CEO Review (双 voice)

### CEO Premise Challenge（Step 0A）

| # | 隐含前提 | 判定 |
|---|---|---|
| P1 | req-stage-gate 现状"太重" | ⚠ 部分成立（60 行可接受） |
| P2 | 旧仓资产值得改造（>从零写） | ✅ 资产本身有价值 |
| P3 | 拆 skill 后职责更清晰 | ⚠ 可质疑（增加跨文件状态） |
| P4 | task-plan 模式可类比 | ⚠ 部分（task-plan 无 reviewer 回路） |
| P5 | 10 章 solution.md 对单人 PM 有价值 | ❌ **强可质疑**（项目定位单人 PM，10 章是跨团队 SOP 模板） |
| P6 | stage 3 应保留 plan-ceo-review | ✅ 但需校准（每 req 强制 review 是否过重） |

### CEO 双 voice 共识表

| Dimension | Claude Subagent | Codex | Consensus |
|---|---|---|---|
| 1. Premises valid? | NO（F1/F6） | NO（项 1） | **CONFIRMED**：拆 3 skill 前提不成立 |
| 2. Right problem to solve? | reframe（option D） | reframe（templates only） | **CONFIRMED**：问题应重定义 |
| 3. Scope calibration correct? | TOO BIG（10→5 章） | TOO BIG（10→5–6 章） | **CONFIRMED**：solution.md 章节砍半 |
| 4. Alternatives sufficiently explored? | NO（D 被默杀） | NO（templates 方案缺席） | **CONFIRMED**：替代方案被忽略 |
| 5. Competitive/market risks covered? | N/A | N/A | N/A（PM 单人工具，无市场风险） |
| 6. 6-month trajectory sound? | bad | bad（5 个后悔场景） | **CONFIRMED**：6 月后会想合回去 |

**6 维度 5 个 CONFIRMED 全部为负**。这是罕见的强否定共识。

### CODEX SAYS (CEO — strategy challenge)

> 不要按原计划批准。它把"PM 单人生产力工具"推向了"流程框架工程化"，核心风险是**用结构复杂度解决提示质量问题**。

关键发现：
1. **拆 3 个 skill 的前提没被证明** — "Stage 2 内联 60 行" 不等于必须拆。"净减少 40 行" 是错误指标，行数减少不代表用户路径/失败排查/上下文切换减少
2. **solution.md 10 章过重** — 推荐 6 章：要解决的问题 / 决策与取舍 / 最小可行方案 / 范围边界 / 实现拆分 / 风险与未决问题。task-plan 真正消费的只是 7.2 模块说明，不要把整份跨团队 SOP 文档拖进来
3. **"等 PM complain" 是 fake signal** — 单人用户不会正式 complain，只会绕过流程/少用/手写。建议：保留 1 个**短 canonical example**约束 solution.md 粒度，否则 LLM 易写成企业架构文档
4. **6 个月后悔场景**：
   - PM 小需求也被迫生成 10 章 analysis+solution → 跳过 stage 2/3，框架名义完整实际废弃
   - 文档越来越像"给团队审批看的"，背离 CLAUDE.md 单人定位
   - 3 skill 职责边界变成调试成本（analysis 坏？闸门坏？reviewer 标准坏？solution 模板过重？）
   - 旧仓的 ceremony 重新带回新仓
   - plan-ceo-review 对每个 req 强制 → 把轻量工具变成每步被审的流程系统
5. **替代方案被默杀**：不拆 skill 只重构内联块；只新增 templates/analysis.md + templates/solution.md；只增强 stage 3；渐进模板（5 节默认/10 节展开）；reviewer 留在 orchestrator；先 3 个真实 req dry run 再决定

**Codex 推荐**：先不新建 req-analysis / req-solution。Stage 2 内联块重排，stage 3 加轻量 solution.md 模板默认 5–6 节，复杂 req 再展开。3 个真实 req 验证后再决定是否拆 skill。

### CLAUDE SUBAGENT (CEO — strategic independence)

> The plan is **directionally reasonable but over-engineered for a single-PM tool**.

| # | 发现 | 严重度 | 建议 |
|---|---|---|---|
| F1 | Stage 3 拆分是 indirection 不是 simplification（inline 2 行 vs 新 skill 200 行；req-stage-gate 净增 4 行） | **HIGH** | Stage 3 留 inline，把 10 章结构搬到 `templates/solution.md`（数据非代码），req-stage-gate 内联读模板路径 |
| F2 | Plan 内部矛盾：§职责切分说 reviewer 在 req-analysis，§改造细节 3 step 2 说 "reviewer 调用 + 处理逻辑搬过来" — reviewer 到底在哪？ | MEDIUM | 解决矛盾。建议 reviewer 在子 skill，orchestrator 只信 PASS 契约 |
| F3 | 10 章 solution.md 给单人 PM 太重（版本表、变更日志、glossary、集成点、安全隐私、非功能、分期负责团队 — 全是跨团队对齐的 artifact） | **HIGH** | 砍到 5 章：摘要 / 用户场景 / 技术架构（含 Mermaid + 模块清单）/ 功能模块（7.2 task-plan 真正消费的）/ 风险分期。skill 从 200→100 行 |
| F4 | "Wait until PM complains" 是 fake signal — 用户=作者 | MEDIUM | 要么现在 copy（cheap），要么删除该行；别假装有反馈回路 |
| F5 | 3 skill 间状态耦合：req-analysis 写文件 → req-stage-gate grep 未决问题 → req-solution 读 analysis。format 改一处三处变 | MEDIUM | 在每个 sub-skill 顶部写 5 行 contract："我写文件 X 含章节 Y 格式 Z；调用方 grep Q 验证"，让接口可见 |
| F6 | Option D（只拆 stage 2，stage 3 留 inline）在 plan 里被默杀 | **HIGH** | 显式评估 Option D。很可能是答案 |

**Subagent 推荐**：Option D。提取 req-analysis only，加 5 章 templates/solution.md，stage 3 留 inline。比当前 plan 省 ~150 行 + 一个 skill 文件。stage 3 inline 增长到 30+ 行再考虑拆分。

### CEO Phase 关键观察

**强一致信号**：两个 voice 独立得出几乎相同结论：
- 不要拆 3 skill；至少 stage 3 不拆
- solution.md 必须砍章节（10→5–6）
- 引入 templates 比引入 skill 更对症
- 项目定位（单人 PM）和当前 plan（跨团队 SOP 模板）有冲突

**Premise gate 必须 PM 确认**——这是 autoplan 唯一不能自动决策的点。

---

## Phase 1 — Premise Gate Resolution（PM 拍板 2026-04-26）

PM 对 4 个澄清问题的回答：

| # | 问题 | PM 回答 | 影响 |
|---|---|---|---|
| Q1 | CLAUDE.md "单人 PM 工具"还准确吗？ | 是单人，但**朝工程化方向走** | CEO 关于"过重"的批评打折——10 章 / reviewer / 4 层框架是工程化定位 |
| Q2 | solution.md 的真实读者？是否砍章节？ | PM 自己 + 后续 stage 的 AI；**保留 10 章不要改** | F3（subagent）+ Codex 项 2 直接被否决 |
| Q3 | reviewer 在哪？PM 看完整对话还是只看 PASS 报告？ | **内部跑完** | F2 矛盾通过"reviewer 完全在 req-analysis 内"消解；orchestrator 不重调 |
| Q4 | 是真有痛点还是架构洁癖？ | **确实遇到问题了** | F6（Option D 是答案）+ Codex"先 dry run"被否决 |

**结果**：CEO 评审中**仍然采纳的 3 条**：
1. **F2 内部矛盾**（subagent）：reviewer 边界写死在 plan，§职责切分 + §改造细节 1 步骤 4-6 + §改造细节 3 已修订
2. **F5 状态耦合**（subagent）：新增 §职责切分下方的"关键契约"段，明示 3 skill 接口
3. **F4 fake signal**（subagent + Codex 项 3）：few-shots 改为**直接搬运**到 `skills/req-solution/references/few-shots.md`

**CEO 评审中被 PM 否决的部分**：F1（stage 3 不拆）、F3（10 章砍 5 章）、F6（Option D）、Codex 项 1（不拆 skill）、Codex 项 2（砍章节）、Codex 项 5（先 dry run 再决定）。

**autoplan 状态**：Phase 1 关闭。Phase 3 (Eng) / Phase 3.5 (DX) / Phase 4 (终审) 由 PM 选择跳过——Eng 评审主要看架构/测试/安全，本改造是 markdown 重构无新代码；DX 评审看 PM 用 skill 体验，已在 §职责切分讨论。

**修订后的 plan 是最终方案**，可进入实施。

---

## 实施完成记录（2026-04-26）

按修订后 plan 落地，4 个文件改动：

| 文件 | 操作 | 行数 |
|---|---|---|
| `skills/req-analysis/SKILL.md` | 新建 | 236 |
| `skills/req-solution/SKILL.md` | 新建 | 272 |
| `skills/req-solution/references/few-shots.md` | 复制（旧仓 → 新仓） | 139 |
| `skills/req-stage-gate/SKILL.md` | 修改 Stage 1→2 (-26 行) + Stage 2→3 (+3 行) | 200（原 226） |

**实施时和 plan 一致的关键点**：
- req-analysis 顶部加了 §接口契约 表，明示与 orchestrator 的边界
- req-analysis Workflow 步骤 5 写死"reviewer 完整循环在 skill 内部跑完"，步骤 6 列 6 条硬禁止项
- req-solution 顶部同样加 §接口契约 表
- req-stage-gate Stage 1→2 段从 4 步精简：调 /pmai-req-analysis（信任 PASS 契约）→ 闸门 → 答题处理 → 推进；不再内联 Role/reviewer 调用样例/4 层框架
- req-stage-gate Stage 2→3 段：调 /req-solution → /plan-ceo-review → 确认门 → 推进
- few-shots.md 直接 copy（139 行），skill 末尾引用 `.claude/skills/req-solution/references/few-shots.md`

**等待手工验证**：起一个测试 req 跑通 stage 1→2→3 全流程（计划在下次跑真实 req 时自然验证）。
