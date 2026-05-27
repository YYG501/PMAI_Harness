---
name: pmai-project-solution
description: |
  项目级方向规划入口：PM 主动调用，定 / 改项目顶层方向（产品定位 / 用户 / 路线 / 技术栈 / 术语 + roadmap）。
  **4 个独立调用场景**：
    A 项目方向重做（跑过几个 req 后发现产品定位偏了）
    B 产品路线规划（主动校准 PROJECT 6 节 + 重新排 roadmap，含季度 / 半年节奏）
    C 老板 / 市场新方向（外部输入逼着改路线）
    D brownfield 接入定方向（紧接 /pmai-codebase-audit 后跑）
  内部逻辑：场景判断 + @读 _shared/project-questioning.md 跑讨论（提问顺序场景特定）。
  不占 req stage、不走 req-stage-gate。
---

# /pmai-project-solution

## When To Use

PM 主动调用，**4 个独立场景**：

- **A 项目方向重做**：跑过几个 req 后发现产品定位偏了，重新定方向
- **B 产品路线规划**：主动校准 PROJECT 6 节 + 重新排 roadmap（含季度 / 半年节奏 / 老项目首次补全）
- **C 老板 / 市场新方向**：外部输入逼着改路线
- **D brownfield 接入定方向**：紧接 `/pmai-codebase-audit` 之后跑

> **不在 scope**：
> - greenfield 首次起新项目 → 走 `/pmai-init-project`（一气呵成 4 阶段；阶段 C 内嵌方向讨论按同款 `_shared/project-questioning.md` 跑）
> - req 级 analysis / PRD / spec → 走 `/pmai-req-stage-gate`
> - 老项目同步兜底 → 走 `/pmai-new-req` mini-fill（不在本 skill 范围）

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: project-solution"
```

## 与 init-project 的关系

| | `/pmai-init-project` | `/pmai-project-solution` |
|---|---|---|
| 干什么 | 起新项目（4 阶段一气呵成；含方向讨论）| 定 / 改项目方向（4 场景之一）|
| 何时 | 创建新项目时（一次性）| 重做 / 规划 / 新方向 / brownfield 接入 |
| 在哪跑 | 生成器仓 | 业务仓 |
| 跑几次 | 一次 | N 次（按场景需要）|

**共享提问真相源**：两个 skill 都 @读 `skills/_shared/project-questioning.md`（提问法 / 问题库 / 写作规则 / Decision gate / 6 节检查）。**场景特定逻辑**（输入态判断 / 提问顺序）留各自 SKILL.md。

## 产出

- `docs/PROJECT.md` —— 项目顶层方案，6 节（按 `$PMAI_HOME/templates/PROJECT.md.tmpl`）
- `docs/ROADMAP.md` —— 计划态 req 队列（按 `$PMAI_HOME/templates/ROADMAP.md.tmpl`）

**单文件，不产工程孪生** —— 不产 `solution.engineering.md` 之类的工程合同。项目级方向只用 PM 视角写。

## Workflow

> 4 段：场景判断 + 段 1 讨论 + 段 2 输出 + 确认门。

---

### 段 0 · 场景判断（加，细化）

调用前先判断场景：

| 场景 | 触发 | 输入态 | **提问顺序**（按 _shared §3 问题库挑用，**场景特定**）|
|---|---|---|---|
| **A 重做** | PM 主动说"方向偏了 / 要重做" | `docs/PROJECT.md` 已有内容 | (1) **痛点诊断**（旧 PROJECT 哪几节失效 / 为什么偏）→ (2) 产品定位（重定）→ (3) 用户画像（重定，可能换主角色）→ (4) 业务术语表（如有新术语）→ (5) roadmap 重排（旧未做 req 重新评估保留 / 砍）|
| **B 产品路线规划** | PM 主动说"产品路线规划 / 季度规划 / 半年规划"，或老项目首次补 `docs/ROADMAP.md` | `docs/PROJECT.md` 已有；`ROADMAP.md` 历史可有可无（首次补则跳过步骤 1）| (1) **过去 roadmap 完成度回顾**（哪些 ship / 哪些砍；首次补无历史则跳过）→ (2) roadmap：**先扫 `requirements/closed/` 列全部 req-NNN 作 done 行回填**（按 `_shared/project-questioning.md` §5.2 写法），再问 PM 新 req 队列（planned 行）—— ROADMAP 是历史 + 未来一张表，漏 done 行不算齐 → (3) 业务术语表增量（如有新业务）—— **跳过产品定位 / 用户画像 / 技术栈**（默认稳定）|
| **C 老板新方向** | PM 主动说"老板 / 客户给了新方向" | `docs/PROJECT.md` 已有 | (1) **新方向 vs 现 PROJECT 差异点**（PM 自述新方向 + AI 对比现 PROJECT 找冲突）→ (2) 产品定位（如有变 → 改）→ (3) 用户画像（如有变 → 改，可能换主角色）→ (4) roadmap（新 req 队列）|
| **D brownfield 接入** | 紧接 `/pmai-codebase-audit` 之后 | `docs/代码现状档.md` 已生成（7 维度）| (0) **全文读 `docs/代码现状档.md`**（必读，AI 不准跳）→ (1) 产品定位（**从 codebase 反推 + PM 确认**）→ (2) 用户画像（从代码层级 / API 角色反推 + PM 补）→ (3) 技术栈（**从代码现状档抄**，PM 确认）→ (4) 业务术语表（**从 model / API 命名反推 + PM 补**）→ (5) roadmap（PM 给）|

**通用约束**（所有 4 场景）：

- 步骤 2 提问全部走 `_shared/project-questioning.md` §2 提问纪律（分批 / 追问 / 收敛 / 编号作答）+ §3 问题库（话术挑用）
- 步骤 3 未决问题闸门必跑（_shared §4）
- 步骤 8 Decision gate（_shared §6）必走，不能 PM 答"OK"直接落（Decision gate label 模糊检测，review M2 落地后强制）

### 段 1 · 讨论方向

#### 步骤 1：读已有输入

- `docs/PROJECT.md`（已有内容 / 或 `/pmai-init-project` 已建的空骨架）
- `CLAUDE.md`（看注入的项目背景 / 工程结构约束档位）
- `docs/代码现状档.md`（如存在 —— brownfield 场景；`/pmai-codebase-audit` 先扫码产出的 7 维度现状档）—— 存在 → 全文读，作为讨论实况语境

#### 步骤 2：分批提问 PM

**@读 `skills/_shared/project-questioning.md` §2 提问纪律 + §3 问题库**，按段 0 场景的提问顺序问 PM。

可选 —— **PM 自跑外部 review**：项目方向需要更激进第二视角时，建议 PM 自跑 `/office-hours`（值不值得做）或 `/plan-ceo-review`（挑战范围）。本 skill 不自动调它们。

#### 步骤 3：未决问题闸门

**@读 `skills/_shared/project-questioning.md` §4 未决问题闸门**。暂存文件路径：`docs/.project-solution-open-questions.md`。

### 段 2 · 输出

#### 步骤 4：写 docs/PROJECT.md

**@读 `skills/_shared/project-questioning.md` §5.1 PROJECT.md 5 节写作规则 + §5.4 PM 视图规则**。

#### 步骤 5：写 docs/ROADMAP.md

**@读 `skills/_shared/project-questioning.md` §5.2 ROADMAP.md 写作规则 + §5.3 ROADMAP 唯一规划视图说明**。

### 确认门

#### 步骤 6：开场问模式（场景特定，留 SKILL.md）

```
📝 准备写项目方向（docs/PROJECT.md + docs/ROADMAP.md）。

想填详细版（按完整规范），还是最简版（产品定位 1 句话 / 1 个主角色 / 1 条术语 起手）？
最简版几分钟搞定，以后起 req 时还能接着补。
```

- PM 答「最简 / 简版 / 快」→ 精简模式：每节 1 条起手即接受
- PM 答「详细 / 完整 / 详版」→ 详细模式：按 PROJECT 模板各节注释里的规范长度
- PM 答「混合」→ 各节 PM 临场决定

> **fast-path**：精简模式下 trivial 项目不被前置仪式拖住 —— 产品定位一句话、用户画像一个角色、术语表一条，起手即可过门。

#### 步骤 7：5 节齐不齐检查

**@读 `skills/_shared/project-questioning.md` §7 5 节齐不齐检查**。

#### 步骤 8：Decision gate 确认门 + PM 定稿

**@读 `skills/_shared/project-questioning.md` §6 Decision gate 模板 + §8 PM 定稿展示模板**。

PM 选「创建 PROJECT.md」+ 定稿后：

- **@读 §9 atomic commit**：`git commit -m "docs: project direction settled"`
- 退出前向 PM 说明 ROADMAP 是唯一规划视图（按 §5.3）+ 引导下一步：

```
项目方向定稿。下一步：运行 /pmai-new-req 开始第一个需求。
```

## Rules

**禁止项**：

- ❌ 走 req stage / 调 `req-transition.py` / 调 `/pmai-req-stage-gate` —— 本 skill 是项目级，不占 req stage
- ❌ 产工程孪生文件（`solution.engineering.md` 之类）—— 单文件，只写 PM 视角
- ❌ 自动调 `/office-hours` / `/plan-ceo-review` —— 这两个由 PM 可选自跑
- ❌ 设 analysis-reviewer 式第二视角强制评审 —— 项目方向第二视角由 PM 自跑 `/plan-ceo-review`
- ❌ 对 `docs/PROJECT.md` 直接跑未决问题闸门 —— PROJECT.md 无 `## 未决问题` section；必须对 `docs/.project-solution-open-questions.md` 暂存文件跑（@读 §4）
- ❌ PM chat 出现工程黑话（hash / reconcile / stale / 步骤编号）—— 给 PM 看的话只用 PM 视图语言
- ❌ **重复 `_shared/project-questioning.md` 的提问法 / 5 组话术 / 写作规则**（必漂移；真相源单一）

**必做项**：

- ✅ 段 0 显式判断场景（A/B/C/D）；不判断就走 D（brownfield 接入兜底，最保守）
- ✅ 段 1 @读 `_shared/project-questioning.md` §2-§4 跑提问 + 闸门
- ✅ 段 2 @读 §5 跑写作
- ✅ 确认门 @读 §6 Decision gate + §7 检查 + §8 PM 定稿 + §9 atomic commit
- ✅ 步骤 6 精简 / 详细模式选择保留（场景特定，不属 `_shared`）

## 边界

- **允许产出**：`docs/PROJECT.md`、`docs/ROADMAP.md`、暂存文件 `docs/.project-solution-open-questions.md`
- **允许动作**：分批提问、未决问题闸门、Decision gate、6 节检查、确认门、atomic commit
- **禁止顺手推进**：不自动起 req、不调 `/pmai-new-req`、不产任何 req 级文档
- **退出条件**：`docs/PROJECT.md` 6 节全填、`docs/ROADMAP.md` 已写、未决问题闸门已过、Decision gate 选了「创建 PROJECT.md」、PM 已定稿、atomic commit 已落
