---
name: req-solution
description: |
  Stage 3：读 brief.md / analysis.md + 项目级文档 + 原型代码，按 $REPO_ROOT/templates/solution.md.tmpl 生成 solution.md（PM 视图），按 $REPO_ROOT/templates/solution.engineering.md.tmpl 生成 solution.engineering.md（工程合同）。
  由 /req-stage-gate 在 stage 2→3 时调用；review 与推进交回调度 skill。
---

# /req-solution

## When To Use

- Orchestrator 在 stage 2→3 调用（由 `/req-stage-gate` 触发）
- 复杂需求场景（多个后端服务改造 / 新建基础设施 / 跨系统对齐 / >3 个功能模块）

简单需求（1-2 个模块、无新基础设施）也走此 skill。

## PM 视图规则（必读）

本 skill 生成的文档须遵守 `skills/_shared/PM-VIEW-RULES.md`（主索引）。具体读以下子文件：
- `_shared/pm-view/writing-rules.md`（§三 写作规则：明确指代 / 正向描述 / 禁工程词 / 禁像素颜色 / 禁反向约束）
- `_shared/PM-VIEW-RULES.md` §六（关键产品决策格式 — solution.md 必填章节）
- `_shared/pm-view/section-order.md`（§七 章节顺序：按 `$REPO_ROOT/templates/solution.md.tmpl` 锁定 13 章 PM 视图 + `solution.engineering.md.tmpl` 10 章工程合同）
- `_shared/pm-view/input-flow.md` §9.1 / §9.6（输入流 + 双文件 lazy sync — 首次生成两文件 + hash；PM 中途修改只动 PM 视图；stage-gate gate 通过时调本 skill 的 reconcile 模式对齐）

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

> **注意**：stage 3 没有强制 reviewer（不像 stage 2 的 analysis-reviewer）。stage 3 的 review 走 PM 自跑模式（/plan-ceo-review 等，由 stage-gate 输出推荐区块）。Discovery 阶段如果 PM 没回答关键缺口，不要硬写方案。

## 调用模式（_shared/pm-view/input-flow.md §9.6）

本 skill 有三种调用模式，由 stage-gate / 当前文件状态决定（步骤 1.5 显式判别）：

| 模式 | 触发条件 | 走哪些步骤 |
|---|---|---|
| **首次生成** | `solution.md` 不存在 | 步骤 0–6（完整流程）|
| **修改回流** | stage-gate 在确认门后 PM 选 B（修改）调入 | 步骤 0 / 3 / 5 / 5.5 / 6（**只**改 PM 视图，**不动**工程合同；hash 自然 stale）|
| **reconcile** | stage-gate 在 PM 选 A 之后、`req-transition.py --to 3` 之前调入，且 prompt 显式说 "reconcile 模式" | 跳到步骤 R（仅 reconcile 工程合同，不改 PM 视图）|

## Required Inputs

按 `_shared/pm-view/input-flow.md` 中 **Stage 4 req-solution** 段执行（first-gen / revise / reconcile 三模式 + PM 视图 / 工程合同两文件分别列）。

特别遵守：
- `input-flow.md` §9.3.1 prototype 读取强约束（>500 行禁整文件 Read）
- `_shared/pm-view/cross-skill.md` 第 1 条（PM 视图链路不读 .engineering.md）

## Workflow

### 步骤 0：读 PM 视图规则子文件（强制）

打开以下子文件（一次会话只读 1 次，跨步骤不重读）：
- `skills/_shared/pm-view/writing-rules.md`（§三 写作规则）
- `skills/_shared/PM-VIEW-RULES.md` §六（关键产品决策格式）
- `skills/_shared/pm-view/section-order.md`（§七 章节顺序）
- `skills/_shared/pm-view/input-flow.md`（§九 输入流，含 §9.6 双文件 lazy sync）

### 步骤 1：读取所有必读输入

按上方 Required Inputs 列出的文件**逐一读取**：
- 上游 stage 文档（brief / analysis）
- 项目级文档（CONTEXT / DESIGN / prd / modules / prototypes）

**特别注意**：
- 项目级文档列为"必读"——AI 不得以"觉得不必要"为由跳过
- `prototypes/` 是反向校验源（PM-VIEW-RULES §9.3）：
  - 如发现原型与上游文档（analysis）描述不一致 → PM 视图以原型为准
  - 原型已删除 / 砍掉的工程概念（如 V4.1 的 `includeDescendants`）→ 不引入 PM 视图，归到工程合同的反向约束

### 步骤 1.5：判别调用模式

按上方"调用模式"表判别：

```bash
SOLUTION_PM="$ACTIVE_REQ_DIR/solution.md"
SOLUTION_ENG="$ACTIVE_REQ_DIR/solution.engineering.md"

if [ ! -f "$SOLUTION_PM" ]; then
  MODE=first-gen
elif grep -q '<已由 stage-gate 显式声明 reconcile>' /dev/null; then
  # stage-gate 在 prompt 里显式说 "reconcile 模式" → 走步骤 R
  MODE=reconcile
else
  MODE=revise
fi
```

> 实际判别由 AI 读 stage-gate 调用本 skill 时给的 prompt：
> - prompt 含 "reconcile 模式" 字样 → MODE=reconcile → 跳步骤 R
> - prompt 含 "PM 在确认门提了修改：…" → MODE=revise → 走步骤 3 / 5 / 5.5 / 6（只改 PM 视图）
> - 否则 + `solution.md` 不存在 → MODE=first-gen → 走完整流程

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

按 `$REPO_ROOT/templates/solution.md.tmpl` 生成 `$ACTIVE_REQ_DIR/solution.md`：

**章节顺序**（强制，由 PM-VIEW-RULES §七锁定）：
1. 📌 方案摘要
2. 📖 术语表（**必填章节**；无新增业务术语时写一行说明，不允许整章缺失）
3. 🎯 关键产品决策（**必填章节**，按 PM-VIEW-RULES §六格式）
4. 📦 交付物清单
5. 📐 数据模型与状态（PM 视角）
6. 🧩 模块职责与边界
7. 🖼 页面 UI 骨架
8. 📋 规格文档变更范围
9. 🔄 task 拆分预估
10. 🚧 风险与未决事项
11. ✅ 验收标准
12. 🔧 本轮实现深度变更（默认「无变更」，沿用项目级 CLAUDE.md「## 工程结构约束」；仅在本 req 改造代码架构时显式列变更项，自由文本）
13. 📁 历史档案（变更记录）

**「本轮实现深度变更」何时填**：
- 99% 的 req 都填「无变更」（本 req 沿用项目级深度配置）
- 仅当本 req 的产物会改变项目代码架构时填，例：
  - 把数据层从 mock 静态升级到真实 IndexedDB 持久化
  - 加完整 RBAC 权限矩阵（之前不做）
  - 把若干页面抽成 Template 公用（之前每页 self-contained）
- 不填「字段表」，写自由文本：「本 req 把 X 从 A 升级 / 降级到 B」
- close-req 会读这段，非「无变更」时提示 PM 是否同步到项目级 CLAUDE.md

**写作约束**（违反将由 PR 3 引入的 `check-doc-pm-view.py` 报错）：
- 每个名词带完整指代前缀（PM-VIEW-RULES §3.1）
- 不出现像素值 / 颜色码 / Emoji 视觉（§3.2）
- 不出现反向约束（"禁止 / 不允许"，§3.4）→ 这些进 solution.engineering.md
- 不出现工程词（reducer / dispatch / props / hook / TS 类型签名）→ 这些进 solution.engineering.md
- 数据模型用业务语言（"许可证状态" / "已开通用户数"），不写 schema / Record / discriminated union

### 步骤 4：写 solution.engineering.md（工程合同）

> **仅 first-gen 模式执行**。revise 模式跳过本步骤（不动工程合同，hash 自然 stale）。reconcile 模式走步骤 R。

按 `$REPO_ROOT/templates/solution.engineering.md.tmpl` 生成 `$ACTIVE_REQ_DIR/solution.engineering.md`：

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
- **强制引用规则**：solution.md 已写过的内容（产品行为 / 用户场景 / 弹窗规范 / 验收标准 / 模块职责文字描述）→ 写"参见 solution.md §X.Y"，**禁止重抄**
- **章节深度按档位裁剪**：读 CLAUDE.md「工程结构约束」段的「文档输出深度指引」（由 `$REPO_ROOT/templates/工程结构约束-{档位}.md` 注入），按档位决定各章节展开深度
- **目标行数**：原型档下 ≤300 行（由 `scripts/check-engineering-doc-size.py` 在 stage 闸门校验，超限 stage-gate 报错）；custom/system 档不预设上限

**hash 写入**（PM-VIEW-RULES §9.6.2）：

```bash
PM_VIEW_HASH=$(shasum -a 256 "$ACTIVE_REQ_DIR/solution.md" | cut -c1-12)
# 写入工程合同顶部模板占位 {{PM_VIEW_HASH}} → 替换为 $PM_VIEW_HASH
```

写完后核对工程合同顶部 `<!-- synced_pm_view_hash: <12 字符> -->` 注释存在且与 PM 视图实际 hash 一致。

### 步骤 5：自检（按 `_shared/pm-view/checklist.md` §八 12 项）

写完后逐条检查 solution.md：

- [ ] 章节顺序符合 $REPO_ROOT/templates/solution.md.tmpl
- [ ] 所有名词带完整指代前缀
- [ ] 无像素值 / 颜色码 / Emoji 视觉
- [ ] 无反向约束（"禁止 / 不允许"）
- [ ] 无组件实现名（reducer / props / hook 等）
- [ ] 无设计意图解释（"避免 X" / "防止 Y"）
- [ ] 抽象动词都搭配具体效果
- [ ] 「关键产品决策」节已填（不允许空表）
- [ ] 「术语表」节已填或写了「本 req 无新增业务术语」（不允许整章缺失）；正文中出现 ≥2 次的业务专名都已录入（除非属于通用词或工程词）
- [ ] §🖼 UI 骨架代码块内的每个字都是 admin / 用户在屏幕上实际看见的字（PM-VIEW-RULES §3.10）：无默认值标注 / 无文档元注释 / 无设计意图词 / 无释义型括号 / 无折叠藏默认值；解释、注释、口径已剥离到骨架下方「关键交互说明」段

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

- **first-gen 模式**：写完两文件 + hash → skill 退出。
- **revise 模式**：只改了 PM 视图（工程合同 hash 现为 stale）→ skill 退出，告知 stage-gate "PM 视图已修订，工程合同保持 stale，等待 gate 通过时 reconcile"。

控制权交回 `/req-stage-gate`，由它输出推荐 review 区块 + 走确认门。

---

### 步骤 R：reconcile 模式（被 stage-gate 在 PM 选 A 之后调入）

**调用前置条件**：stage-gate prompt 显式说 "reconcile 模式"。

按 PM-VIEW-RULES §9.6.4 执行：

1. **算 hash**：
   ```bash
   PM_VIEW_HASH_NOW=$(shasum -a 256 "$ACTIVE_REQ_DIR/solution.md" | cut -c1-12)
   ```
2. **读工程合同顶部 `synced_pm_view_hash`**：
   ```bash
   PM_VIEW_HASH_OLD=$(grep -oE 'synced_pm_view_hash: [a-f0-9]{12}' "$ACTIVE_REQ_DIR/solution.engineering.md" | awk '{print $2}')
   ```
3. **一致** → no-op，输出 "reconcile: no-op（PM 视图未变）"，结束
4. **不一致** → 进入派生流程：
   a. **再读必读输入**：`analysis.md` + 上游 `.engineering.md`（如有）+ `docs/DESIGN.md` / `docs/prd.md` / `docs/modules/*.md` / `prototypes/`
   b. **比对 PM 视图 diff**：用 `git diff` 看 PM 视图自上次 hash 以来变了哪些章节（如果文件未提交则用 chat 上下文里 PM 描述的修改范围）
   c. **重派生 PM 视图驱动章节**（PM-VIEW-RULES §9.6.3）：§1 数据结构 / §2 派生状态 / §3 组件路径 / §4 mock / §5 算法 / §6 易错点（PM 视图反向条目派生部分）/ §10 工程层验收清单
   d. **不动独立来源章节**：§7 plan-review 沉淀 / §8 autoplan 输出 / §9 a11y/视口/视觉（DESIGN.md 派生部分）；如发现独立章节里引用的功能名 / 章节号已被 PM 视图修改，**只改引用、不改主体**
   e. **更新 hash**：把工程合同顶部 `synced_pm_view_hash` 改为 `$PM_VIEW_HASH_NOW`
   f. **追加变更记录**：在工程合同末尾追加 `<!-- reconcile <YYYY-MM-DD HH:MM>: <旧 hash> → <新 hash>; 变更范围: <一行说明> -->`；同步在 `solution.md` 末尾「📁 历史档案」加一行 `<YYYY-MM-DD> reconcile：solution.engineering.md 已对齐 PM 视图（<旧 hash> → <新 hash>）`
5. **自检**（PM-VIEW-RULES §9.6.6）：hash 12 字符 / 与 PM 视图一致 / PM 视图驱动章节无旧概念残留 / 独立来源章节未被误改
6. **输出 reconcile 完成信号**：
   ```
   ✅ solution.engineering.md reconcile 完成
   - hash: <旧> → <新>
   - 变更章节：[列出更新的 §]
   - 独立来源章节未动：§7 / §8 / §9
   ```
7. skill 退出，控制权回 stage-gate（由 stage-gate 跑 `req-transition.py --to 3`）

**硬约束**：reconcile 模式禁止改 PM 视图主文件内容（除「📁 历史档案」append 一行外）。

## 硬禁止项

- ❌ skill 内部走推进确认门（A 进 stage 4 / B 修改）
- ❌ skill 内部自动调任何 review 工具（review 由 orchestrator 列推荐、PM 自跑，I-RV1）
- ❌ skill 内部调 req-transition.py
- ❌ 自动产出 task-plan.md / 模块规格 / 原型代码
- ❌ 在 solution.md 中嵌入工程内容（reducer / 字段 schema / 像素 / 反向约束）→ 这些必须进 solution.engineering.md
- ❌ 跳过项目级文档的"必读"（CONTEXT / DESIGN / prd / modules / prototypes）
- ❌ revise 模式（PM 在确认门提修改后调入）顺手重写工程合同 → 必须保持 stale，等 gate 通过后由 reconcile 模式统一对齐
- ❌ reconcile 模式动 PM 视图主文件内容（仅允许在「📁 历史档案」append 一行 reconcile 记录）
- ❌ 任何模式下手动改工程合同顶部 `synced_pm_view_hash`

---

## 文档结构

PM 视图章节顺序见 `$REPO_ROOT/templates/solution.md.tmpl`（由 PM-VIEW-RULES §七锁定）。
工程合同章节顺序见 `$REPO_ROOT/templates/solution.engineering.md.tmpl`。

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

> 注：references/few-shots.md 当前是 PRD 风格章节示例。PR 2/3 阶段会更新为新模板章节示例（"📌 方案摘要" / "🎯 关键产品决策" / 等）。在更新前，引用 few-shots 仅作语言风格参考，章节结构以 $REPO_ROOT/templates/solution.md.tmpl 为准。

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
  - `$ACTIVE_REQ_DIR/solution.engineering.md`（工程合同，含 `synced_pm_view_hash` 注释）
- **允许动作**：模块划分、系统边界、分期计划、优先级排序、Discovery 缺口提问、reconcile（gate 后调入时）
- **禁止顺手推进**：不要自动开始 task 拆分，不要直接创建原型页面，不要走推进确认门
- **禁止自动调 review**（I-RV1）：所有 `/plan-*-review` 工具由 orchestrator 列推荐、PM 自跑
- **退出条件**：
  - first-gen：两文件已写 + hash 已写、Discovery 缺口已答完
  - revise：PM 视图已修订（工程合同保持 stale）
  - reconcile：工程合同已与 PM 视图对齐、hash 已刷新
  控制权交回 /req-stage-gate
