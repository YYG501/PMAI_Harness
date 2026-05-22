---
name: implementation-design
description: |
  Stage 5（拆 task 前）：读 brief / analysis / prd.md / docs/PROJECT.md / docs/DESIGN.md，
  按 $REPO_ROOT/templates/implementation-design.md.tmpl 产出 req 级实现设计文档
  implementation-design.md（HOW：这个 req 用什么架构、照哪些现有代码写、为什么这么选）。
  由 /req-stage-gate 在 Stage 4→5 编排调用，task-plan 之前。
  产出经 PM 确认门审定架构决策表后放行。do NOT use to write PRD (WHAT) or task spec.
---

# /implementation-design

## When To Use

- Orchestrator 在 Stage 4→5 调用（由 `/req-stage-gate` 触发），**在 `/task-plan` 之前**。
- 每个 req 都跑 —— 它产出的 `implementation-design.md` 是 `task-spec` 的上游 HOW 源。

本 skill 承接原 `solution.engineering.md` 的 req 级 HOW 内容（delta-8）—— `req-solution`
退场后 req 级「这个 req 用什么架构、照哪些代码写」无家可归，本 skill 是它的新家。

## 性质：工程合同格式 + PM 经门审定

`implementation-design.md` 是**工程合同格式**的 artifact：

- 允许所有工程内容（TS 类型 / 字段名 / 像素 / 颜色 / 反向约束）。
- **不跑 PM-view lint** —— `check-doc-pm-view.py` 跳过本文件（同它已跳过 `.engineering.md`）。
- **有 PM 确认门** —— 产出后由 `/req-stage-gate` 走确认门，PM 审定**架构决策表**
  （选择 / 备选 / 理由）才放行。架构决策表含「这个 req 用什么架构、为什么这么选」，
  AI 单方面定再注入 task 与框架内核「PM 在环里」冲突。确认门展示架构决策表「选择」列
  摘要 + 文件路径，PM 可下钻全文，不必逐字背工程细节。

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: implementation-design"
```

## 接口契约（与 req-stage-gate 的边界）

| 维度 | 本 skill 负责 | orchestrator (req-stage-gate) 负责 |
|---|---|---|
| 写 `implementation-design.md` | ✅ | ❌ |
| 产出失败 / 重跑 | ✅（报告失败原因） | ❌ |
| 走 PM 确认门（审架构决策表） | ❌ | ✅ |
| 输出推荐 review 区块 | ❌ | ✅ |
| 调 req-transition.py | ❌ | ✅ |

**退出契约**：本 skill 返回时，`implementation-design.md` 已写完。orchestrator 接手走
PM 确认门（审架构决策表），通过后再调 `/task-plan`。

## Required Inputs

逐一读取：

| 输入 | 用途 |
|---|---|
| `$ACTIVE_REQ_DIR/prd.md` | req 级功能规格（WHAT）—— HOW 据此设计，不重抄 WHAT |
| `$ACTIVE_REQ_DIR/analysis.md` | 需求分析 —— 技术依赖 / 约束 |
| `$ACTIVE_REQ_DIR/brief.md` | 原始诉求（轻量背景）|
| `$REPO_ROOT/docs/PROJECT.md` | 项目级背景（技术栈 / 产品定位）|
| `$REPO_ROOT/docs/DESIGN.md` | **组件 inventory** —— §2 文件·模式索引据此写「复用现有组件 X」，与 stage 4 gap-check 读同一份 |
| `$REPO_ROOT/docs/modules/`（如存在）| 现有模块规格 —— 照哪些现有代码写 |

## Workflow

### 步骤 1：读取所有必读输入

按上方 Required Inputs 逐一读取。**特别注意**：
- `docs/DESIGN.md` 的组件 inventory 是「照哪些现有组件写」的权威来源 —— stage 4
  gap-check 已先更新过 inventory（每 req 必跑组件复用关口），本 skill 读到的是更新后的。
  §2 文件·模式索引据 inventory 写「复用现有组件 X」；inventory 没有的才标新建。
- `prd.md` 是 WHAT —— 本文件只补 HOW，不重复 PRD 的功能行为描述（引用，不重抄）。

### 步骤 2：按归宿表产出 implementation-design.md

按 `$REPO_ROOT/templates/implementation-design.md.tmpl` 生成
`$ACTIVE_REQ_DIR/implementation-design.md`，4 段结构：

| 段 | 内容 | 承接来源 |
|---|---|---|
| 段 1 · 架构决策表 | 这个 req 用什么架构 / 数据结构 / 派生状态规则 | 原 solution.engineering ch1 + ch2 |
| 段 2 · 文件·模式索引 | 照哪些现有代码 / 组件 / 模式写；mock 改造；关键算法消费规则 | 原 ch3 + ch4 + ch5 |
| 段 3 · 约束与验收 | 易错点 / 反向约束 + 工程层验收清单 | 原 ch6 + ch10 |
| 段 4 · 审计与修订记录 | plan-review 沉淀 + 修订留痕 | 原 ch7（ch8 autoplan 噪音不留；ch9 视觉规范 → DESIGN.md）|

**可消费 schema（强制）** —— 段 1 / 段 2 每条 HOW 是一行，带稳定字段：

- **`HOW-ID`**：稳定行级锚（段 1 用 `HOW-01..`，段 2 用 `HOW-10..`）。一旦分配**不复用、不重排**——
  `task-spec` 按 ID 引用，不靠章节标题 grep。
- **适用模块 / 适用 task 关键词**：`task-spec` 据此（按 `input-flow.md §9.1.1` 章节-grep）挑出
  当前 task 相关的 HOW 行。
- **决策内容**：
  - 段 1 每行**必带**「选择 / 备选 / 理由 / 约束失效条件」—— 允许写「无非平凡备选」，**不留空**
    （§0「为什么这么选」就是 HOW 缺口，默认空大段 = 没满足 §0）。
  - 段 2 每行写文件路径 / 模式 + 复用 / 新建标注。
- **来源**：承接自 `solution.engineering` 哪章，或「新增」。

### 步骤 3：自检

- [ ] 4 段齐全；段 1 / 段 2 每条 HOW 行带 `HOW-ID` + 适用关键词
- [ ] 段 1 每行「选择 / 备选 / 理由 / 约束失效条件」都填了（备选可写「无非平凡备选」，但不空）
- [ ] 段 2 的「复用现有组件」与 `docs/DESIGN.md` 组件 inventory 对得上
- [ ] 不重复 PRD 的 WHAT（功能行为描述用引用，不重抄）
- [ ] 像素 / 视觉规范细则没塞进来（那归 `docs/DESIGN.md`）

### 步骤 4：skill 结束

写完 `implementation-design.md` → skill 退出。控制权交回 `/req-stage-gate`，由它走 PM
确认门（审架构决策表），通过后调 `/task-plan`。

产出失败（输入缺失 / PRD 未定稿等）→ 报告失败原因，不硬写。

## Rules

**禁止项**：
- ❌ 写 WHAT（功能行为 / 用户场景 / 验收标准）—— 那是 PRD，本文件引用不重抄
- ❌ 拆 task —— 那是 `/task-plan`
- ❌ 把视觉规范细则（像素 / 颜色 / 字号 / 视口断点 / a11y）写进本文件 —— 归 `docs/DESIGN.md`
- ❌ 段 1 架构决策行留空「备选 / 理由」
- ❌ skill 内部走 PM 确认门 / 调 req-transition.py（归 orchestrator）
- ❌ 把本文件拆成 GSD 式多文件 —— 单文件 4 段（主 AI 一气写完，无 agent 边界）

## 阶段 5 边界（拆 task 前）

- **允许产出**：`$ACTIVE_REQ_DIR/implementation-design.md`
- **允许动作**：读上游 + 项目级文档、设计 req 级架构 / 文件·模式索引 / 约束
- **禁止顺手推进**：不拆 task、不走确认门、不调 review
- **退出条件**：`implementation-design.md` 已写完，控制权交回 `/req-stage-gate`

## 文档结构

段结构 + 可消费 schema 的单一真相源 = `$REPO_ROOT/templates/implementation-design.md.tmpl`。
本 skill 不在内部复制章节定义。
