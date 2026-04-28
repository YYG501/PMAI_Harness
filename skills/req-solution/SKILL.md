---
name: req-solution
description: |
  Stage 3：读 brief.md / analysis.md + 项目级文档 + 原型代码，按 templates/solution.md.tmpl 生成 solution.md（PM 视图），按 templates/solution.engineering.md.tmpl 生成 solution.engineering.md（工程合同）。
  由 /req-stage-gate 在 stage 2→3 时调用；review 与推进交回调度 skill。
---

# /req-solution

## When To Use

- Orchestrator 在 stage 2→3 调用（由 `/req-stage-gate` 触发）
- 复杂需求场景（多个后端服务改造 / 新建基础设施 / 跨系统对齐 / >3 个功能模块）

简单需求（1-2 个模块、无新基础设施）也走此 skill。

## PM 视图规则（必读）

本 skill 生成的文档须遵守 `skills/_shared/PM-VIEW-RULES.md`。
特别注意：
- **§三 PM 视图写作规则**（明确指代 / 正向描述 / 禁工程词 / 禁像素颜色 / 禁反向约束）
- **§六 关键产品决策格式**（solution.md 必填章节）
- **§七 章节顺序约束**（按 `templates/solution.md.tmpl` 锁定的 11 章 PM 视图 + `templates/solution.engineering.md.tmpl` 的 10 章工程合同）
- **§九 输入流约束**（必读上游 stage 文档 + 项目级文档；输入清单见下方 Required Inputs）

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: req-solution"
```

## 接口契约（与 req-stage-gate 的边界）

| 维度 | 本 skill 负责 | orchestrator (req-stage-gate) 负责 |
|---|---|---|
| 写 solution.md（PM 视图）| ✅ | ❌ |
| 写 solution.engineering.md（工程合同）| ✅ | ❌ |
| Discovery 缺口提问 | ✅（写文档前的小 Q&A） | ❌ |
| 输出"推荐 review 工具"区块 | ❌ | ✅（列推荐，不自动调任何 review） |
| 走推进确认门 | ❌ | ✅ |
| 调 req-transition.py | ❌ | ✅ |

**退出契约**：本 skill 返回时，`solution.md` + `solution.engineering.md` 两文件都已经过 PM 简单确认（Discovery 阶段缺口已答）。orchestrator 接手输出推荐 review 区块 + 走确认门。

> **注意**：stage 3 没有 reviewer 硬循环（不像 stage 2 的 analysis-reviewer）。stage 3 的 Discovery 阶段如果 PM 没回答关键缺口，不要硬写方案。

## Required Inputs

按 `PM-VIEW-RULES.md §9.1` 表格执行。

### 写 solution.md（PM 视图）必读

**上游 stage 文档**：
- `$ACTIVE_REQ_DIR/brief.md`
- `$ACTIVE_REQ_DIR/analysis.md`

**项目级文档**（仓库存在则**必读**）：
- `$REPO_ROOT/docs/CONTEXT.md`
- `$REPO_ROOT/docs/DESIGN.md`
- `$REPO_ROOT/docs/prd.md`
- `$REPO_ROOT/docs/modules/*.md`
- `$REPO_ROOT/prototypes/`（按相关性扫现有页面 / 组件，做反向校验）

**不读**：任何 `.engineering.md`（防止工程内容渗透 PM 视图）

### 写 solution.engineering.md（工程合同）必读

- `$ACTIVE_REQ_DIR/analysis.md`
- `$REPO_ROOT/docs/DESIGN.md` / `docs/prd.md` / `docs/modules/*.md` / `prototypes/`
- 上游 `.engineering.md`（如有）

## Workflow

### 步骤 0：读 PM-VIEW-RULES.md（强制）

打开 `skills/_shared/PM-VIEW-RULES.md`，重点理解 §三 / §六 / §七 / §九。

### 步骤 1：读取所有必读输入

按上方 Required Inputs 列出的文件**逐一读取**：
- 上游 stage 文档（brief / analysis）
- 项目级文档（CONTEXT / DESIGN / prd / modules / prototypes）

**特别注意**：
- 项目级文档列为"必读"——AI 不得以"觉得不必要"为由跳过
- `prototypes/` 是反向校验源（PM-VIEW-RULES §9.3）：
  - 如发现原型与上游文档（analysis）描述不一致 → PM 视图以原型为准
  - 原型已删除 / 砍掉的工程概念（如 V4.1 的 `includeDescendants`）→ 不引入 PM 视图，归到工程合同的反向约束

### 步骤 2：Discovery（补问缺口）

读 `analysis.md`，识别以下关键决策是否已确认：

- 分期策略是否明确？（有几期、各期边界）
- 技术架构关键依赖是否已知？
- 有无影响全局的约束未在 analysis 中体现？

有缺口 → **先编号提问 PM**，等 PM 答完再写方案：

```
方案设计前需要补充以下信息：
1. <问题 1>
2. <问题 2>
请用 `1A 2C` 格式回复，或直接说明。
```

> Discovery 缺口与 stage 2 的 `## 未决问题` section 不同：stage 2 的是 PM 必须 commit 到 analysis.md 的业务决定；stage 3 的 Discovery 缺口是临时澄清，答完后融入 solution.md / solution.engineering.md 正文。

### 步骤 3：写 solution.md（PM 视图）

按 `templates/solution.md.tmpl` 生成 `$ACTIVE_REQ_DIR/solution.md`：

**章节顺序**（强制，由 PM-VIEW-RULES §七锁定）：
1. 📌 方案摘要
2. 🎯 关键产品决策（**必填章节**，按 PM-VIEW-RULES §六格式）
3. 📦 交付物清单
4. 📐 数据模型与状态（PM 视角）
5. 🧩 模块职责与边界
6. 🖼 页面 UI 骨架
7. 📋 规格文档变更范围
8. 🔄 task 拆分预估
9. 🚧 风险与未决事项
10. ✅ 验收标准
11. 📁 历史档案（变更记录）

**写作约束**（违反将由 PR 3 引入的 `check-doc-pm-view.py` 报错）：
- 每个名词带完整指代前缀（PM-VIEW-RULES §3.1）
- 不出现像素值 / 颜色码 / Emoji 视觉（§3.2）
- 不出现反向约束（"禁止 / 不允许"，§3.4）→ 这些进 solution.engineering.md
- 不出现工程词（reducer / dispatch / props / hook / TS 类型签名）→ 这些进 solution.engineering.md
- 数据模型用业务语言（"许可证状态" / "已开通用户数"），不写 schema / Record / discriminated union

### 步骤 4：写 solution.engineering.md（工程合同）

按 `templates/solution.engineering.md.tmpl` 生成 `$ACTIVE_REQ_DIR/solution.engineering.md`：

**章节顺序**（按模板锁定）：
1. 数据结构定义
2. 派生状态规则（代码层）
3. 组件实现路径
4. Mock 数据改造清单
5. 关键算法消费规则
6. 易错点 / 反向约束
7. plan-review 沉淀
8. autoplan 修订点 / 决策表
9. a11y / 视口 / 视觉规范细则
10. 工程层验收清单

**写作约束**：
- 允许所有工程内容（TS 类型 / 字段名 / 像素 / 颜色 / 反向约束 / autoplan 输出原文等）
- 唯一原则：不重复 PM 视图已有的功能行为描述

### 步骤 5：自检（按 PM-VIEW-RULES §八 8 项）

写完后逐条检查 solution.md：

- [ ] 章节顺序符合 templates/solution.md.tmpl
- [ ] 所有名词带完整指代前缀
- [ ] 无像素值 / 颜色码 / Emoji 视觉
- [ ] 无反向约束（"禁止 / 不允许"）
- [ ] 无组件实现名（reducer / props / hook 等）
- [ ] 无设计意图解释（"避免 X" / "防止 Y"）
- [ ] 抽象动词都搭配具体效果
- [ ] 「关键产品决策」节已填（不允许空表）

任一项未通过 → 修复后重新自检。

### 步骤 5.5：自动跑启发式 lint

人工自检之后，调用 `check-doc-pm-view.py` 做机器校验作为兜底：

```bash
python3 "$REPO_ROOT/.claude/scripts/check-doc-pm-view.py" "$ACTIVE_REQ_DIR/solution.md"
```

处理输出：

- **0 errors + 0 warnings**：可以进入步骤 6 退出 skill
- **有 warnings**：向 PM 展示 warnings，PM 决定是否修
- **有 errors**：逐条修复后回到步骤 3 重写违规章节，再重跑 lint；连续 3 次 lint 仍有 error 时停下询问 PM（避免无限循环）

lint 不强制阻塞，但 errors 留着进入步骤 6 的，必须在向 PM 展示文件路径时**显式告知**有几个未修复 errors + 一句话原因。

工程合同 (`solution.engineering.md`) 不跑 lint（lint 脚本会自动跳过 `.engineering.md`）。

### 步骤 6：skill 结束

写完两文件 → skill 退出。控制权交回 `/req-stage-gate`，由它输出推荐 review 区块 + 走确认门。

## 硬禁止项

- ❌ skill 内部走推进确认门（A 进 stage 4 / B 修改）
- ❌ skill 内部自动调任何 review 工具（review 由 orchestrator 列推荐、PM 自跑，I-RV1）
- ❌ skill 内部调 req-transition.py
- ❌ 自动产出 task-plan.md / 模块规格 / 原型代码
- ❌ 在 solution.md 中嵌入工程内容（reducer / 字段 schema / 像素 / 反向约束）→ 这些必须进 solution.engineering.md
- ❌ 跳过项目级文档的"必读"（CONTEXT / DESIGN / prd / modules / prototypes）

---

## 文档结构

PM 视图章节顺序见 `templates/solution.md.tmpl`（由 PM-VIEW-RULES §七锁定）。
工程合同章节顺序见 `templates/solution.engineering.md.tmpl`。

本 skill **不在内部维护章节定义**——所有章节约束的单一真相源是模板文件 + PM-VIEW-RULES。

---

## 写作规则

参见 `PM-VIEW-RULES.md §三`（PM 视图写作规则）。

要点摘录：
- 先结论，后规则；短句，动作先行
- 同一信息只在一处主写；其他处引用功能名称，不重复展开
- 名词必须带指代前缀（"在「具体页面 - 区域」对什么对象做什么"）
- 抽象动词必须搭配具体效果

---

## Few-shots

读取 `.claude/skills/req-solution/references/few-shots.md` 获取各章节完整示例。

> 注：references/few-shots.md 当前是 PRD 风格章节示例。PR 2/3 阶段会更新为新模板章节示例（"📌 方案摘要" / "🎯 关键产品决策" / 等）。在更新前，引用 few-shots 仅作语言风格参考，章节结构以 templates/solution.md.tmpl 为准。

---

## 模块优先级排序框架（写「📐 数据模型与状态」/「🧩 模块职责与边界」时使用）

拿到功能模块清单后，按以下顺序选第一个要做的模块：

1. **核心链路优先** — 没有这个模块，其他模块无法演示完整业务流
2. **能建立设计范式的模块优先** — 包含列表页 + 详情页 + 创建页三种类型，做完后其他模块可复用
3. **依赖最少的模块优先** — 不依赖其他未实现模块的数据或状态

三条都满足的模块，优先做。只满足第一条的，也要优先做。

---

## 阶段 3 边界

- **允许产出**：
  - `$ACTIVE_REQ_DIR/solution.md`（PM 视图）
  - `$ACTIVE_REQ_DIR/solution.engineering.md`（工程合同）
- **允许动作**：模块划分、系统边界、分期计划、优先级排序、Discovery 缺口提问
- **禁止顺手推进**：不要自动开始 task 拆分，不要直接创建原型页面，不要走推进确认门
- **禁止自动调 review**（I-RV1）：所有 `/plan-*-review` 工具由 orchestrator 列推荐、PM 自跑
- **退出条件**：两文件都已写、Discovery 缺口已答完。控制权交回 /req-stage-gate
