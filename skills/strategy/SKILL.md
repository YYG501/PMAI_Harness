---
name: pmai-strategy
description: |
  项目方向校准 / 重做入口：项目跑起来之后，PM 主动回头**重定 / 校准已定的顶层方向**（产品定位 / 用户 / 路线 / 技术栈 / 术语 + TODO 待办池）。
  与起步定方向分工清楚：首次定方向走 /pmai-init-project（greenfield 起步）或 /pmai-codebase-audit（brownfield 接入）；本 skill 专管**事后回头改方向**，不重复起步那道门。
  **4 个独立调用场景**：
    A 项目方向重做（跑过几个 req 后发现产品定位偏了）
    B 产品路线规划（主动校准 PRODUCT 5 节 + 刷新 TODO 待办池，含季度 / 半年节奏）
    C 老板 / 市场新方向（外部输入逼着改路线）
    D brownfield 接入方向恢复（接入时 /pmai-codebase-audit 内联方向讨论被打断 / 想重定方向时手动补跑）
  内部逻辑：场景判断 + @读 _shared/project-questioning.md 跑讨论（提问顺序场景特定）。
  不占 req stage、不走 req-stage-gate。
  Always trigger when the user says 重定方向 / 校准方向 / 项目方向偏了 / 产品路线规划 / 季度规划 / 老板给了新方向 / 项目方向重做。
  do NOT use for 首次起项目定方向（那走 /pmai-init-project 或 /pmai-codebase-audit）。
---

# /pmai-strategy

> **一句话定位**：项目跑起来后回头**校准 / 重做顶层方向**（定位·用户·路线·术语）。首次起步定方向是 `/pmai-init-project`（greenfield）/ `/pmai-codebase-audit`（brownfield）的活；本 skill 专管**事后回头改**，不替它们做起步那道门。

> **PM 答题规则（M4）**：所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 四条硬规则走（空答 STOP / 没拿到答案禁止落盘 PRODUCT.md / TODO.md / runtime 退化保留 wait / 多决策拆开顺序问）。**Runtime 兜底**：本 skill 各门写的都是 picker 形态；runtime 不支持时 AI 按 §1.3 自动退化为编号列表，仍 wait。

## When To Use

PM 主动调用，**4 个独立场景**：

- **A 项目方向重做**：跑过几个 req 后发现产品定位偏了，重新定方向
- **B 产品路线规划**：主动校准 PRODUCT 5 节 + 刷新 TODO 待办池（含季度 / 半年节奏 / 老项目首次补全）
- **C 老板 / 市场新方向**：外部输入逼着改路线
- **D brownfield 接入方向恢复**：brownfield 接入的方向讨论已搬进 `/pmai-codebase-audit` step 4 内联跑（一气呵成）。本场景只在**异常恢复**时用——接入时方向讨论被打断没跑完（窗口关了 / context 丢了）、或现状档当时定的方向想重来。正常 brownfield 接入**不用**手敲本命令。

> **不在 scope**：
> - greenfield 首次起新项目 → 走 `/pmai-init-project`（一气呵成 4 阶段；阶段 C 内嵌方向讨论按同款 `_shared/project-questioning.md` 跑）
> - brownfield 首次接入定方向 → 走 `/pmai-codebase-audit`（一气呵成：扫码产现状档 → PM 过目 → step 4 内联方向讨论，同款 `_shared/project-questioning.md`）。本 skill 场景 D 只兜接入方向讨论被打断的异常恢复
> - req 级范围确认 / 按需 PRD / 沉淀 → 走 `/pmai-new-req` 起需求、`/pmai-next` 推进六步（`req-stage-gate` 已降为异常恢复壳）
> - 老项目同步兜底 → 走 `/pmai-new-req` mini-fill（不在本 skill 范围）

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: strategy"
```

## 与 init-project 的关系

| | `/pmai-init-project` | `/pmai-strategy` |
|---|---|---|
| 干什么 | 起新项目（4 阶段一气呵成；含方向讨论）| 定 / 改项目方向（4 场景之一）|
| 何时 | 创建新项目时（一次性）| 重做 / 规划 / 新方向 / brownfield 接入 |
| 在哪跑 | 生成器仓 | 业务仓 |
| 跑几次 | 一次 | N 次（按场景需要）|

**共享提问真相源**：两个 skill 都 @读 `skills/_shared/project-questioning.md`（提问法 / 问题库 / 写作规则 / Decision gate / 5 节检查）。**场景特定逻辑**（输入态判断 / 提问顺序）留各自 SKILL.md。

## 产出

- `docs/PRODUCT.md` —— 项目顶层方案，5 节（按 `$PMAI_HOME/templates/PRODUCT.md.tmpl`）
- `docs/TODO.md` —— PM 待办池（无序，按 `$PMAI_HOME/templates/TODO.md.tmpl`）
- `docs/decisions/<日期>-<slug>.md` —— **按需**：本轮方向讨论若产出了项目级理路（护城河 / 机制整体 / 演进），冻一份项目决策记录留作历史坐标（见确认门步骤 8.5）。纯微调不冻。

**单文件，不产工程孪生** —— 不产 `solution.engineering.md` 之类的工程合同。项目级方向只用 PM 视角写。

## Workflow

> 4 段：场景判断 + 段 1 讨论 + 段 2 输出 + 确认门。

---

### 段 0 · 场景判断（加，细化）

调用前先判断场景：

| 场景 | 触发 | 输入态 | **提问顺序**（按 _shared §3 问题库挑用，**场景特定**）|
|---|---|---|---|
| **A 重做** | PM 主动说"方向偏了 / 要重做" | `docs/PRODUCT.md` 已有内容 | (1) **痛点诊断**（旧 PRODUCT 哪几节失效 / 为什么偏）→ (2) 产品定位（重定）→ (3) 用户画像（重定，可能换主角色）→ (4) 业务术语表（如有新术语）→ (5) 刷新 TODO 待办池（旧待办 PM 自己评估保留 / 划掉，AI 不替排序）|
| **B 产品路线规划** | PM 主动说"产品路线规划 / 季度规划 / 半年规划"，或老项目首次补 `docs/TODO.md` | `docs/PRODUCT.md` 已有；`TODO.md` 可有可无 | (1) 刷新 TODO 待办池：**问 PM 现在想做啥记进待办池**（AI 不扫 `requirements/closed/` 反推历史、不排序，按 `_shared/project-questioning.md` §5.2 写法）→ (2) 业务术语表增量（如有新业务）—— **跳过产品定位 / 用户画像 / 技术栈**（默认稳定）|
| **C 老板新方向** | PM 主动说"老板 / 客户给了新方向" | `docs/PRODUCT.md` 已有 | (1) **新方向 vs 现 PRODUCT 差异点**（PM 自述新方向 + AI 对比现 PRODUCT 找冲突）→ (2) 产品定位（如有变 → 改）→ (3) 用户画像（如有变 → 改，可能换主角色）→ (4) 刷新 TODO 待办池（PM 给的新待办）|
| **D brownfield 方向恢复** | 接入时 `/pmai-codebase-audit` step 4 内联方向讨论被打断 / 想重定方向（正常接入不走这）| `docs/CODEBASE-AUDIT.md` 已生成（7 维度）| (0) **全文读 `docs/CODEBASE-AUDIT.md`**（必读，AI 不准跳）→ (1) 产品定位（**从 codebase 反推 + PM 确认**）→ (2) 用户画像（从代码层级 / API 角色反推 + PM 补）→ (3) 技术栈（**从代码现状档抄**，PM 确认）→ (4) 业务术语表（**从 model / API 命名反推 + PM 补**）→ (5) 刷新 TODO 待办池（PM 给，AI 不反推填充）|

**通用约束**（所有 4 场景）：

- 步骤 2 提问全部走 `_shared/project-questioning.md` §2 提问纪律（分批 / 追问 / 收敛 / 编号作答）+ §3 问题库（话术挑用）
- 步骤 3 未决问题闸门必跑（_shared §4）
- 步骤 8 Decision gate（_shared §6）必走，不能 PM 答"OK"直接落（Decision gate label 模糊检测，review M2 落地后强制）

### 段 1 · 讨论方向

#### 步骤 1：读已有输入

- `docs/PRODUCT.md`（已有内容 / 或 `/pmai-init-project` 已建的空骨架）
- `CLAUDE.md`（看注入的项目背景 / 工程结构约束档位）
- `docs/CODEBASE-AUDIT.md`（如存在 —— brownfield 场景；`/pmai-codebase-audit` 先扫码产出的 7 维度现状档）—— 存在 → 全文读，作为讨论实况语境

#### 步骤 2：分批提问 PM

**@读 `skills/_shared/project-questioning.md` §2 提问纪律 + §3 问题库**，按段 0 场景的提问顺序问 PM。

可选 —— **PM 自跑外部 review**：项目方向需要更激进第二视角时，建议 PM 自跑 `/office-hours`（值不值得做）或 `/plan-ceo-review`（挑战范围）。本 skill 不自动调它们。

#### 步骤 3：未决问题闸门

**@读 `skills/_shared/project-questioning.md` §4 未决问题闸门**。暂存文件路径：`docs/.project-solution-open-questions.md`。

### 段 2 · 输出

#### 步骤 4：写 docs/PRODUCT.md

**@读 `skills/_shared/project-questioning.md` §5.1 PRODUCT.md 5 节写作规则 + §5.4 PM 视图规则**。

#### 步骤 5：写 docs/TODO.md

**@读 `skills/_shared/project-questioning.md` §5.2 TODO.md 写作规则 + §5.3 TODO 是 PM 待办池说明**。

### 确认门

#### 步骤 6：开场问模式（场景特定，留 SKILL.md）

prose 头部：
```
📝 准备写项目方向（docs/PRODUCT.md + docs/TODO.md）。
```

AskUserQuestion：
- `question`: "用哪种模式起手？"
- `options`:
  - `label`: `最简版`
    `description`: `产品定位 1 句话 / 1 个主角色 / 1 条术语起手，几分钟搞定（推荐 trivial 项目）`
  - `label`: `详细版`
    `description`: `按 PRODUCT 模板各节注释里的规范长度填`
  - `label`: `混合`
    `description`: `各节 PM 临场决定`

**PM 答题处理**：
- 选 `最简版` / 输 `1` / 输 "最简 / 简版 / 快" → 精简模式：每节 1 条起手即接受
- 选 `详细版` / 输 `2` / 输 "详细 / 完整 / 详版" → 详细模式：按 PRODUCT 模板各节注释里的规范长度
- 选 `混合` / 输 `3` → 各节 PM 临场决定

Runtime 不支持 AskUserQuestion 时按 `_shared/pm-view/askuser-rules.md §1.3` 退化编号列表。

> **fast-path**：精简模式下 trivial 项目不被前置仪式拖住 —— 产品定位一句话、用户画像一个角色、术语表一条，起手即可过门。

#### 步骤 7：5 节齐不齐检查

**@读 `skills/_shared/project-questioning.md` §7 5 节齐不齐检查**。

#### 步骤 8：Decision gate 确认门 + PM 定稿

**@读 `skills/_shared/project-questioning.md` §6 Decision gate 模板 + §8 PM 定稿展示模板**。

PM 选「创建 PRODUCT.md」+ 定稿后：

- 先走步骤 8.5（按需冻决策记录），再 atomic commit（两者进同一个 commit）。

#### 步骤 8.5：按需冻项目决策记录（本轮有实质理路才做）

本轮方向讨论若产出了**项目级理路**——护城河论证 / 几个机制怎么整体咬合 / 关键交互理念推导 / v2 演进方向（不是单条术语、不是 5 节里的离散填空）——**@读 `skills/_shared/decision-record.md`** 判门槛（纯微调不冻），有实质理路 → 向 PM 提一句「这轮定了 <一句话理路>，冻一份项目决策记录留底，好吗」，PM 点头 → 按 `$PMAI_HOME/templates/decision-record.md.tmpl` 写 `docs/decisions/<日期>-<slug>.md`（理路节 + 当时事实摘要带日期 + 指针）。**纯微调 / 无跨文件理路 → silent skip 本步**。

> **本 skill 不写 PRODUCT-STATE 索引**：strategy 不是 PRODUCT-STATE 的 sanctioned 写口（防腐铁律只认 close-req + `/pmai-deposit`）。冻的决策记录靠 `/pmai-new-req` 起步直接扫 `docs/decisions/` 发现（+ PRODUCT-STATE 已有指向 `docs/decisions/` 的通用索引），不需要本 skill 逐条挂索引。`docs/decisions/` 在 main 上可写（冻结档豁免，见 `check-branch.sh`）。

#### 步骤 8.6：atomic commit + 引导下一步

- **@读 §9 atomic commit**：`git commit -m "docs: project direction settled"`（含 PRODUCT.md / TODO.md / 本轮若冻的 decisions/）
- 退出前提醒 PM TODO 待办池里有哪些待办（按 §5.3），不替 PM 定下一个该做啥 + 引导下一步：

```
项目方向定稿。下一步：运行 /pmai-new-req 开始第一个需求。
```

## Rules

**禁止项**：

- ❌ 走 req stage / 调 `req-transition.py` / 调 `/pmai-req-stage-gate` —— 本 skill 是项目级，不占 req stage
- ❌ 产工程孪生文件（`solution.engineering.md` 之类）—— 单文件，只写 PM 视角
- ❌ 自动调 `/office-hours` / `/plan-ceo-review` —— 这两个由 PM 可选自跑
- ❌ 设 analysis-reviewer 式第二视角强制评审 —— 项目方向第二视角由 PM 自跑 `/plan-ceo-review`
- ❌ 对 `docs/PRODUCT.md` 直接跑未决问题闸门 —— PRODUCT.md 无 `## 未决问题` section；必须对 `docs/.project-solution-open-questions.md` 暂存文件跑（@读 §4）
- ❌ PM chat 出现工程黑话（hash / reconcile / stale / 步骤编号）—— 给 PM 看的话只用 PM 视图语言
- ❌ **重复 `_shared/project-questioning.md` 的提问法 / 5 组话术 / 写作规则**（必漂移；真相源单一）

**必做项**：

- ✅ 段 0 显式判断场景（A/B/C/D）；不判断就走 D（brownfield 接入兜底，最保守）
- ✅ 段 1 @读 `_shared/project-questioning.md` §2-§4 跑提问 + 闸门
- ✅ 段 2 @读 §5 跑写作
- ✅ 确认门 @读 §6 Decision gate + §7 检查 + §8 PM 定稿 + §9 atomic commit
- ✅ 步骤 6 精简 / 详细模式选择保留（场景特定，不属 `_shared`）

## 边界

- **允许产出**：`docs/PRODUCT.md`、`docs/TODO.md`、`docs/decisions/<日期>-<slug>.md`（本轮有实质理路时按需冻）、暂存文件 `docs/.project-solution-open-questions.md`
- **允许动作**：分批提问、未决问题闸门、Decision gate、5 节检查、确认门、按需冻决策记录、atomic commit
- **禁止顺手推进**：不自动起 req、不调 `/pmai-new-req`、不产任何 req 级文档
- **退出条件**：`docs/PRODUCT.md` 5 节全填、`docs/TODO.md` 已写、未决问题闸门已过、Decision gate 选了「创建 PRODUCT.md」、PM 已定稿、atomic commit 已落
