---
name: pmai-direction
description: |
  项目方向校准：项目运行一段时间后，由 PM 主动重定产品方向或整理路线规划。用于产品定位、用户、边界、业务术语和待办池的顶层调整；首次起步 / 首次接入统一走 /pmai-init-project。
  触发词：方向重定 / 校准方向 / 项目方向偏了 / 产品路线规划 / 季度规划 / 半年规划 / 老板给新方向。
---

# /pmai-direction

## 入口护栏

执行本 skill 前先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止本 skill，只引导 PM 先发 `/pmai-init-project`。初始化或已有代码接入完成前，不要把未初始化包装成方向校准。

> **一句话定位**：项目跑起来后回头校准方向。它只处理两类 PM 意图：**方向重定**和**路线规划**。首次起步、首次接已有代码库都不走这里，统一走 `/pmai-init-project`。

> **PM 答题规则（M4）**：所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 四条硬规则走（空答 STOP / 没拿到答案禁止落盘 PRODUCT.md / TODO.md / runtime 退化保留 wait / 多决策拆开顺序问）。**Runtime 兜底**：runtime 不支持时 AI 按 §1.3 自动退化为编号列表，仍 wait。

## When To Use

PM 主动调用，只有两个主场景：

- **方向重定**：产品定位、用户、边界或关键业务概念变了。包括“方向偏了”、“要重做定位”、“老板 / 客户 / 市场给了新方向”。
- **路线规划**：接下来做什么、季度 / 半年节奏、待办池怎么整理。默认只刷新 `TODO.md` 和必要的业务术语，不重做产品定位。

> **不在 scope**：
> - 首次起步 / 首次接入 → 走 `/pmai-init-project`。它会自动判断全新项目 / 资料目录 / 已有代码库。
> - 已有代码库接入中断 → 回 `/pmai-init-project` 续跑；如果已经有 `docs/CODEBASE-AUDIT.md` 且 PM 明确要重扫 / 恢复现状盘点，也由 `/pmai-init-project` 读取内部盘点子流程处理。
> - 模块设计 / build / 功能型规格文档 → 走 `/pmai-design`、`/pmai-build`、`/pmai-spec-writing`；完整 build 的正式沉淀由 landed 后自动文档编译完成。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: direction"
```

如果 preamble 提示当前目录还没有 PMAI 初始化，停止本 skill，引导 PM 先发 `/pmai-init-project`。不要把未完成初始化包装成“方向校准”。

## 与 init-project 的关系

| | `/pmai-init-project` | `/pmai-direction` |
|---|---|---|
| 干什么 | 项目初始化统一入口：全新项目建底座，已有代码库自动盘点现状 | 已接入项目的方向重定 / 路线规划 |
| 何时 | 首次起步 / 首次接入时（一次性） | 项目跑起来后，按需多次 |
| 在哪跑 | 任意 cwd 发起，落到目标业务仓 | 已接入的业务仓 |
| 跑几次 | 一次 | N 次（按场景需要） |

**共享提问真相源**：本 skill @读 `skills/_shared/project-questioning.md`（提问法 / 问题库 / 写作规则 / Decision gate / 5 节检查）。**场景特定逻辑**（输入态判断 / 提问顺序）留在本文件。

## 产出

- `PRODUCT.md` —— 项目顶层方向，5 节（方向重定时会改；路线规划默认不重写定位）
- `TODO.md` —— PM 待办池（无序，只记 PM 主动提过 / 讨论过的事）
- `docs/decisions/<日期>-<slug>.md` —— **按需**：本轮方向讨论若产出了项目级理路（护城河 / 机制整体 / 演进），冻一份项目决策记录留作历史坐标。纯微调不冻。

**单文件，不产工程孪生** —— 不产 `solution.engineering.md` 之类的工程合同。项目级方向只用 PM 视角写。

## Workflow

> 4 段：意图判断 + 讨论方向 + 输出 + 确认门。

---

### 段 0 · 判断 PM 意图

调用前先判断这次是哪一类：

| 意图 | 触发 | 输入态 | 提问顺序（按 _shared §3 问题库挑用） |
|---|---|---|---|
| **方向重定** | PM 说“方向偏了 / 要重定 / 定位不对 / 老板或客户给了新方向” | `PRODUCT.md` 已有内容 | (1) 先问旧方向哪里失效 / 新方向从哪来 → (2) 产品定位 → (3) 用户画像 → (4) 产品边界 → (5) 业务术语表 → (6) 刷新 TODO 待办池 |
| **路线规划** | PM 说“产品路线规划 / 季度规划 / 半年规划 / 接下来做什么 / 整理待办” | `PRODUCT.md` 已有；`TODO.md` 可有可无 | (1) 问 PM 现在想做什么，记进 TODO 待办池 → (2) 如出现新业务概念，补业务术语表。默认跳过产品定位 / 用户画像 / 产品边界 |

判断不清时，只问一个澄清问题：“你这次是要重定产品方向，还是只整理接下来做什么？”

**通用约束**：

- 提问全部走 `_shared/project-questioning.md` §2 提问纪律（分批 / 追问 / 收敛 / 编号作答）+ §3 问题库（话术挑用）。
- 未决问题闸门必跑（_shared §4）。
- Decision gate 必走（_shared §6），不能 PM 答“OK”直接落。

### 段 1 · 讨论方向

#### 步骤 1：读已有输入

- `PRODUCT.md`（当前方向）
- `TODO.md`（当前待办池，如存在）
- `CLAUDE.md`（项目背景 / host 协作约束）
- `docs/decisions/`（如本轮问“为什么当初这么定”，按需读相关决策记录，不全量淹没）

如果发现 `docs/CODEBASE-AUDIT.md` 存在且 `PRODUCT.md` / `TODO.md` 明显没完成，先提示：“这个项目像是已有代码接入没完成，应该回 `/pmai-init-project` 续跑接入，而不是做方向校准。”PM 明确说要基于现状档重做方向时，再按“方向重定”继续。

#### 步骤 2：分批提问 PM

按段 0 的意图选择提问顺序。

可选 —— **PM 自跑第二视角**：项目方向需要更多视角时，先按问题选择工具：想沉淀新想法、找盲区 / 反方挑战 / 多角度看当前方向 → 建议 PM 跑 `/pmai-meta`，由 meta 判断走产品想法会诊还是已有材料压测；想做外部经营视角挑战 → PM 自跑 `/plan-ceo-review`。本 skill 不自动调它们。

#### 步骤 3：未决问题闸门

**@读 `skills/_shared/project-questioning.md` §4 未决问题闸门**。暂存文件路径：`docs/.project-solution-open-questions.md`。

### 段 2 · 输出

#### 步骤 4：写 / 改 PRODUCT.md

**方向重定**：按 `_shared/project-questioning.md` §5.1 PRODUCT.md 5 节写作规则 + §5.4 PM 视图规则更新 `PRODUCT.md`。

**路线规划**：默认不重写产品定位 / 用户画像 / 产品边界；只有 PM 明确说这些也变了，才升级为“方向重定”。技术栈变化进入下一次 design 的 project definition 重校准，不写进 `PRODUCT.md`。

#### 步骤 5：写 / 改 TODO.md

**@读 `skills/_shared/project-questioning.md` §5.2 TODO.md 写作规则 + §5.3 TODO 是 PM 待办池说明**。

硬规则：
- 只记 PM 主动提过 / 讨论过想做的事。
- 不从代码、竞品、历史归档反推填充。
- 不替 PM 排顺序。

### 确认门

#### 步骤 6：开场问模式

prose 头部：

```text
准备校准项目方向（PRODUCT.md + TODO.md）。
```

AskUserQuestion：
- `question`: "用哪种模式起手？"
- `options`:
  - `label`: `最简版`
    `description`: `只改本轮必须改的方向和待办，几分钟搞定`
  - `label`: `详细版`
    `description`: `按 PRODUCT 模板各节注释里的规范长度补齐`
  - `label`: `混合`
    `description`: `各节 PM 临场决定`

Runtime 不支持 AskUserQuestion 时按 `_shared/pm-view/askuser-rules.md §1.3` 退化编号列表。

#### 步骤 7：5 节齐不齐检查

**方向重定**：@读 `skills/_shared/project-questioning.md` §7 5 节齐不齐检查。

**路线规划**：如果本轮没有改 `PRODUCT.md`，只检查 `TODO.md` 是否按 PM 的待办落好；不强行补 PRODUCT 5 节。

#### 步骤 8：Decision gate 确认门 + PM 定稿

**@读 `skills/_shared/project-questioning.md` §6 Decision gate 模板 + §8 PM 定稿展示模板**。

PM 选「创建 / 更新方向文档」+ 定稿后：

- 先走步骤 8.5（按需冻决策记录），再 atomic commit（两者进同一个 commit）。

#### 步骤 8.5：按需冻项目决策记录

本轮方向讨论若产出了**项目级理路**——护城河论证 / 几个机制怎么整体咬合 / 关键交互理念推导 / v2 演进方向（不是单条术语、不是 TODO 条目）——**@读 `skills/_shared/decision-record.md`** 判门槛。

有实质理路 → 向 PM 提一句“这轮定了 <一句话理路>，冻一份项目决策记录留底，好吗”，PM 点头 → 按 `$PMAI_HOME/templates/decision-record.md.tmpl` 写 `docs/decisions/<日期>-<slug>.md`。

纯微调 / 只整理 TODO → silent skip 本步。

> **本 skill 不写 PRODUCT-STATE**：direction 不是 PRODUCT-STATE 的 sanctioned 写口（防腐铁律只认 landed 后自动文档编译 + `/pmai-record`）。冻结的决定记录靠 `/pmai-design` 进场按需扫 `docs/decisions/` 发现。

#### 步骤 8.6：atomic commit + 引导下一步

- **@读 §9 atomic commit**：`git commit -m "docs: project direction settled"`（含 PRODUCT.md / TODO.md / 本轮若冻的 decisions/）
- 退出前提醒 PM TODO 待办池里有哪些待办，不替 PM 定下一个该做啥 + 引导下一步：

```text
项目方向已校准。下一步：
  · 要开始做某个功能 → /pmai-design
  · 只是先记着 → 到这里结束
```

## Rules

**禁止项**：

- 走活跃模块工作流 —— 本 skill 是项目级，不占模块工作阶段。
- 产工程孪生文件（`solution.engineering.md` 之类）—— 单文件，只写 PM 视角。
- 自动调 `/pmai-meta` / `/plan-ceo-review` —— 第二视角由 PM 可选自跑。
- 设 analysis-reviewer 式第二视角强制评审 —— 项目方向第二视角只在 PM 要求时启用，不做默认门。
- 对 `PRODUCT.md` 直接跑未决问题闸门 —— PRODUCT.md 无 `## 未决问题` section；必须对 `docs/.project-solution-open-questions.md` 暂存文件跑（@读 §4）。
- PM chat 出现工程黑话（hash / reconcile / stale / 步骤编号）—— 给 PM 看的话只用 PM 视图语言。
- 重复 `_shared/project-questioning.md` 的提问法 / 5 组话术 / 写作规则。

**必做项**：

- 段 0 显式判断“方向重定 / 路线规划”。
- 段 1 @读 `_shared/project-questioning.md` §2-§4 跑提问 + 闸门。
- 段 2 @读 §5 跑写作。
- 确认门 @读 §6 Decision gate + §7 检查 + §8 PM 定稿 + §9 atomic commit。
- 步骤 6 精简 / 详细模式选择保留（场景特定，不属 `_shared`）。

## 边界

- **允许产出**：`PRODUCT.md`、`TODO.md`、`docs/decisions/<日期>-<slug>.md`（本轮有实质理路时按需冻）、暂存文件 `docs/.project-solution-open-questions.md`。
- **允许动作**：分批提问、未决问题闸门、Decision gate、5 节检查、确认门、按需冻决策记录、atomic commit。
- **禁止顺手推进**：不自动进入 `/pmai-design`、不产任何模块工作文档。
- **退出条件**：本轮涉及的 PRODUCT / TODO 改动已定稿、未决问题闸门已过、Decision gate 已确认、PM 已定稿、atomic commit 已落。
