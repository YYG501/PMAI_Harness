---
name: req-solution
description: |
  Stage 3：读 analysis.md 做系统分层、模块边界、分期计划，写 solution.md（10 章固定结构 + Mermaid 架构图）。
  由 /req-stage-gate 在 stage 2→3 时调用；review 与推进交回调度 skill。
---

# /req-solution

## When To Use

- Orchestrator 在 stage 2→3 调用（由 `/req-stage-gate` 触发）
- 复杂需求场景（多个后端服务改造 / 新建基础设施 / 跨系统对齐 / >3 个功能模块）

简单需求（1-2 个模块、无新基础设施）也走此 skill，但 7.2 模块说明可以精简——核心是给 task-plan stage 5 提供可消费的模块清单。

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: req-solution"
```

读取 `$ACTIVE_REQ_DIR/analysis.md` 作为输入，写 `$ACTIVE_REQ_DIR/solution.md` 作为产出。

## 接口契约（与 req-stage-gate 的边界）

| 维度 | 本 skill 负责 | orchestrator (req-stage-gate) 负责 |
|---|---|---|
| 写 solution.md | ✅ | ❌ |
| Discovery 缺口提问 | ✅（写文档前的小 Q&A） | ❌ |
| 调 /plan-ceo-review | ❌ | ✅（review 是讨论性的，结果贴 chat） |
| 走推进确认门 | ❌ | ✅ |
| 调 req-transition.py | ❌ | ✅ |

**退出契约**：本 skill 返回时，`$ACTIVE_REQ_DIR/solution.md` 已经过 PM 简单确认（Discovery 阶段缺口已答）。orchestrator 接手跑 /plan-ceo-review + 走确认门。

> **注意**：stage 3 没有 reviewer 硬循环（不像 stage 2 的 analysis-reviewer），review 由 orchestrator 调 /plan-ceo-review 处理。stage 3 也没有"未决问题闸门"硬规则——但 Discovery 阶段如果 PM 没回答关键缺口，不要硬写方案。

## Required Inputs

1. `$ACTIVE_REQ_DIR/analysis.md`（必需，stage 2 产出）
2. `$ACTIVE_REQ_DIR/brief.md`（必需，stage 1 产出）
3. `$REPO_ROOT/docs/CONTEXT.md`（如存在）
4. `$REPO_ROOT/docs/DESIGN.md`（如存在）

## Workflow

### 步骤 0：Discovery（读 analysis.md，补问缺口）

读 `analysis.md`，识别以下关键决策是否已确认：

- 分期策略是否明确？（有几期、各期边界是什么）
- 技术架构关键依赖是否已知？（如依赖系统是否支持所需能力）
- 有无影响全局的约束未在 analysis 中体现？

有缺口 → **先编号提问 PM**，等 PM 答完再写方案。提问格式：

```
方案设计前需要补充以下信息：
1. <问题 1>
2. <问题 2>
请用 `1A 2C` 格式回复，或直接说明。
```

> 这跟 stage 2 的 `## 未决问题` section 不同：stage 2 的是 PM 必须 commit 到 analysis.md 的业务决定；stage 3 的 Discovery 缺口是临时澄清，答完后融入 solution.md 正文，不单独 section。

### 步骤 1：写 solution.md

按下方 §文档结构 生成完整 `$ACTIVE_REQ_DIR/solution.md`，语言风格对齐下方 §写作规则与 `references/few-shots.md`。

### 步骤 2：skill 结束

写完 solution.md → skill 退出。控制权交回 `/req-stage-gate`，由它跑 /plan-ceo-review + 走确认门。

### 硬禁止项

- ❌ skill 内部走推进确认门（A 进 stage 4 / B 修改）
- ❌ skill 内部调 /plan-ceo-review（review 在 orchestrator）
- ❌ skill 内部调 req-transition.py
- ❌ 自动产出 task-plan.md / 模块规格 / 原型代码

---

## 文档结构（必须完整输出）

### 摘要

1-3 句话：本方案旨在解决什么问题、覆盖什么范围、属于哪个迭代。放在文档最顶部，不编号。

### 一、文档版本信息

| 字段 | 值 |
| --- | --- |
| 文档版本号 | V |
| 创建日期 | |
| 编写人 | |
| 产品版本号 | V |
| 对应原型版本号 | V（如无则留空） |

### 二、变更日志

表格：时间 / 版本号 / 对应原型版本 / 变更人 / 主要变更内容

### 三、名词解释

表格（术语 / 缩略词 | 说明）；无则写"无"。

### 四、需求分析

#### 4.1 问题陈述（Problem Statement）

自然语言段落，每段写一个现象及其影响。直接来源于 `analysis.md` + `brief.md`，保留关键原话。不要压缩成一句摘要——要让读者感受到问题的真实范围。

#### 4.2 解决方案（Proposed Solution）

1-3 句话，说明本次做什么来解决上述问题。来源：`analysis.md` 的已确认决策。

#### 4.3 成功指标（Success Criteria）

3-5 条 bullet，每条一句可验证结果。使用"所有……均……""无……时……返回……""……后立即……"等句式；不写"提升体验"等无法验证的描述。

#### 4.4 方案价值（Impact）

3-5 条 bullet，格式：`动词短语：具体结果`。说明此方案对业务/运营/商业化的价值，回答"为什么值得做"。来源：`analysis.md` 的目标解读。

### 五、用户与场景

#### 5.1 用户角色（User Personas）

表格（角色名 | 描述 | 与本功能的关系）。来源：`analysis.md` 的用户与场景。

#### 5.2 用户故事（User Stories）

格式：`作为 <角色>，我希望能 <动作>，以便 <价值>。`

全程使用中文，不混用英文关键词。每条 Story 下附 AC（验收条件）bullet list。Story 数量 3-6 条，覆盖核心场景和关键边界（无权限/有权限/变更权限后等）。AC 只写结果状态（"按钮置灰""返回 403"），不写操作步骤。

#### 5.3 非目标（Non-Goals）

bullet list，每条一句。来源：`brief.md` 的 Out of Scope 与 `analysis.md` 的非目标。

### 六、技术架构

#### 6.1 架构概述（Architecture Overview）

必须包含 Mermaid flowchart，描述核心数据流（用户操作 → 服务/校验 → 结果）。图后用编号列表补充关键流程说明。

#### 6.2 集成点（Integration Points）

表格（系统 | 集成说明）；列出本方案新增或改造的依赖系统。

#### 6.3 安全与隐私（Security & Privacy）

bullet list；写明安全约束（token 策略、隔离机制、后端强制校验等）。无安全关注点则写"暂无"。

### 七、功能范围与约束

#### 7.1 功能模块清单

表格（一级功能 | 二级功能 | 模块说明 | 优先级）。

粒度到二级功能即可，不写三级细节；目的是让业务/客户快速理解范围，不暴露实现细节。

#### 7.2 各模块功能说明

**必须输出此节。** 为 7.1 清单里每个一级功能模块创建一个 `####` 子节，格式如下（每个模块重复一次）：

```
#### [模块名]

**包含页面：**
- [页面名称]

**核心功能点：**
- [功能点：一句话]

**本期 In Scope：**
- [明确要做的]

**本期 Out of Scope（本批不做）：**
- [明确不做的]

**验收口径：**
- [可验证的结果状态]
```

> 阶段 5 的 task 里"读取 docs/solution.md#[模块名]"指向的就是这里。模块名必须与 7.1 表格的一级功能列完全一致。**本节是 task-plan 真正消费的，必须填写完整。**

#### 7.3 非功能性要求

按维度逐条写明（性能、可用性、安全、向后兼容、可观测性等）。无则写"暂无"。

### 八、分期计划

表格：阶段 | 业务目标 | 功能模块 | 计划迭代 | 负责团队 | 对应 breakdown PRD

写法规则：

- "业务目标"列必填：回答"这一期做完，用户/业务得到什么"
- 若 breakdown PRD 尚未创建，填"待创建 - [模块名] breakdown"
- 每期必须有明确的计划迭代（如 V2.3）

### 九、风险与假设

#### 9.1 技术风险

表格（风险 | 影响 | 概率（高/中/低） | 对策）

#### 9.2 约束与假设

bullet list，分两类写：

- **技术约束**：改造必须遵守的限制（"改造不影响现有任务逻辑"）
- **系统假设**：方案依赖的前提条件（"假设 RBAC 支持新增 action 权限"）

### 十、附件（如有）

直接输出内容（分类表 / 字段字典 / 枚举值等）；无此章节则不写。

---

## 写作规则（全篇遵守）

- 先结论，后规则；短句，动作先行
- 禁止写"支持/优化/提升体验"，必须写明"怎么做 + 规则/限制"
- 同一信息只在一处主写；其他处引用功能名称，不重复展开
- 术语统一使用三、名词解释中定义的名词，不另行解释
- 4.3 成功指标必须可验证；每条对应一个可测试的结果状态
- 用户故事 AC 只写结果状态，不写操作步骤
- 八、分期计划每期必须有"业务目标"，不只是功能模块列表

---

## Few-shots

读取 `.claude/skills/req-solution/references/few-shots.md` 获取各章节完整示例（基于"导出/下载/分享权限控制收口"真实案例）。

文件目录：

- 摘要示例
- 4.1 问题陈述示例
- 4.4 方案价值示例
- 4.3 成功指标示例
- 5.2 用户故事示例
- 6.1 Mermaid 架构图示例
- 7.1 功能模块清单示例
- 八、分期计划示例
- 九、风险与假设示例

---

## 模块优先级排序框架

拿到功能模块清单后，按以下顺序选第一个要做的模块：

1. **核心链路优先** — 没有这个模块，其他模块无法演示完整业务流
2. **能建立设计范式的模块优先** — 包含列表页 + 详情页 + 创建页三种类型，做完后其他模块可复用
3. **依赖最少的模块优先** — 不依赖其他未实现模块的数据或状态

三条都满足的模块，优先做。只满足第一条的，也要优先做。

**可选工具**：solution.md 完成后，可用 `/plan-eng-review` 检查架构、`/plan-design-review` 检查交互与视觉层问题。这些是 PM 在 stage 3 期间可手动触发的辅助工具，不是 skill 内部强制流程。

---

## 阶段 3 边界

- **允许产出**：`$ACTIVE_REQ_DIR/solution.md`
- **允许动作**：模块划分、系统边界、分期计划、优先级排序、Discovery 缺口提问
- **禁止顺手推进**：不要自动开始 task 拆分，不要直接创建原型页面，不要走推进确认门
- **退出条件**：solution.md 已写、Discovery 缺口已答完。控制权交回 /req-stage-gate（由它跑 /plan-ceo-review + 走确认门）
