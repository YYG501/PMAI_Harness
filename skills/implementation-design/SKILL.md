---
name: pmai-implementation-design
description: |
  build 阶段的 AI 后台辅助：在 prototype/ 里建之前，AI 后台快速想清楚工程 HOW
  （组件怎么拆 / 状态怎么管 / mock 数据结构 / mock 边界 / 多 task 数据一致性），
  作为 build 的内部 context。不产正式文档、不走 PM 确认门、不让 PM 逐行确认。
  产品口径的"实现文档"（范围清单 WHAT + 决策页 WHY，PM 拍板）是 task-plan 的职责，不是这里。
  由 /pmai-next 在 build 阶段按需后台调用。do NOT use 写范围清单 / 决策页 / PRD（那是 task-plan / prd-writing）。
---

# /pmai-implementation-design

## 性质：build 阶段的 AI 后台辅助（不产正式文档）

这个 skill 在六步里**没有独立位置**，也**不产正式文档**。

PM 拍板的"实现文档"——**详细范围清单（WHAT）+ 一页关键决策（WHY）**——是 `task-plan` 的产出（`req-plan.md`），由 PM 拍板。本 skill 只管 PM **不需要逐行确认**的那一层：build 前 AI 在后台快速把工程 HOW 想清楚——组件怎么拆 / 状态怎么管 / mock 数据结构长什么样 / mock 到真系统的边界在哪 / 多个 task 之间数据怎么保持一致。

这层是 **AI 后台 context**：它指导 AI 在 `prototype/` 里怎么建，但**不落成正式 artifact**、**不进 PM 视图**、**不走确认门**。PM 关心的是范围对不对、体验顺不顺（task-plan 的范围清单 + build 后的复审兜底），不关心 reducer 怎么拆。

> **承接历史**：旧 7-stage 链里有个独立的 `implementation-design.md` 工程文档（含架构决策表 + 原型简化项 SIMP 段 + 文件模式索引）。六步收敛后**这个独立文档被砍**：
> - 它的「这个 req 用什么架构 / 数据结构」属于工程 HOW → 降本 skill 的 AI 后台、不产文档。
> - 它的「原型故意做得比需求少」的 SIMP 简化项机制**整体砍掉**——SIMP 把交互裁成占位壳，正是原型视觉上限被压低的根因之一（见重构方向稿 §1.3）。build 后的覆盖审计（独立视角 agent 对照范围清单硬 diff）才是治"丢字段 / 降级占位"的正确机制，不靠 build 前预先登记简化项。
> - 它承载的「PM 该拍板的 scope 决策」上移到 `task-plan` 的范围清单 + 决策页（PM 拍板）。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: implementation-design"
```

## When To Use

- `/pmai-next` 推进到 build 阶段时，AI 在动手建 `prototype/` 之前**按需**后台跑一遍：把工程 HOW 想清楚。
- 简单需求（PM 思路清、改动 localized）**可跳过**——没有"每个 req 必跑"的硬流程。判断标准：AI 是否需要先把组件 / 状态 / mock 边界想清楚才不至于建乱。需要 → 跑；不需要 → 直接建。
- **不**用来写范围清单 / 决策页（那是 `task-plan` 的 `req-plan.md`），**不**用来写 PRD（那是 `prd-writing`）。

## Required Inputs

后台想 HOW 时读这些（都是已有产物，不新建）：

| 输入 | 用途 |
|---|---|
| `$ACTIVE_REQ_DIR/req-plan.md` | **本 req 的范围清单（WHAT）+ 决策页（WHY）**——PM 已拍板的范围，HOW 据此设计，不重抄 WHAT |
| `$REPO_ROOT/docs/DESIGN.md` | **组件 inventory / 视觉约定**——「照哪些现有组件写」的权威来源；build 强制 @读它 |
| `$REPO_ROOT/PRODUCT-STATE.md` | **产品现状脊柱**——当前功能 / 主原型现状 / mock-真状态位，治失忆 |
| `$REPO_ROOT/PRODUCT-RULES.md`（如存在）| 跨 req 沉淀的业务规则 / 权限语义 |
| `$REPO_ROOT/prototype/` | 主原型现有代码——照哪些现有代码 / 模式写 |

读不到 `req-plan.md`（范围还没确认）→ 不硬想 HOW，提示先回到范围确认（`/pmai-next`）。

## Workflow

### attachments AI 接管 hook

PM 在 chat 描述 "我有 X 在 ~/Downloads/foo.pdf，重点 Y" → AI first-principle 识别 → 调 helper：

```python
from _lib.attachments import copy_attachment
result = copy_attachment(req_dir, Path("~/Downloads/foo.pdf"),
                        stage_prefix="build", hint="Y 重点")
```

chat 一行确认 `已归档（attachments/build-foo.pdf），Y 重点。继续。`（禁工程黑话）。

异常 catch：`FileNotFoundError` / `SensitivePathError` / `FileSizeError` → chat 报错（fail-loud）。

**单一真相源**：`skills/_shared/pm-view/attachments-upload.md`。

### 步骤 1：读已有产物，消化范围 + 现状

读上面 Required Inputs。重点：
- `req-plan.md` 范围清单是 PM 拍板的 WHAT —— HOW 只补"怎么建"，不重复 WHAT。
- `DESIGN.md` 组件 inventory 是「照哪些现有组件写」的权威来源——能复用的复用，inventory 没有的才新建。
- `PRODUCT-STATE.md` + `prototype/` 给当前现状——知道原型现在长什么样，才知道这个 req 是加 / 改 / 重写哪块。

### 步骤 2：后台想清工程 HOW（不落正式文档）

针对本 req 的范围，AI 在后台把这几件想清楚（**作为 build 的内部 context，不写成正式 artifact、不给 PM 逐行确认**）：

- **组件怎么拆**：复用 `DESIGN.md` inventory 里哪些组件；要新建哪些；怎么组合。
- **状态怎么管**：本 req 涉及的状态 / 派生状态规则放哪、怎么流动。
- **mock 数据结构**：原型用什么数据形状；字段命名按 `req-plan.md` / `PRODUCT-RULES.md` 的业务实体精确指代，不同义词漂移。
- **mock 边界**：哪些是 mock 壳、哪些打通真逻辑（按当前 mode / `PRODUCT-STATE.md` 状态位）；mock→真的边界在哪。
- **多 task 数据一致性**：若本 req 拆多个 task 并行建，它们共享的 mock 数据 / 类型定义怎么对齐，避免各建各的。

想清楚后**直接进 build**（在 `prototype/` 里用 Claude Code 建），把这层 HOW 当 build 的指导，而不是先产一份文档再照着建。

### 步骤 3：skill 结束

后台 HOW 想清 → 控制权交回 `/pmai-next`，进入 build。本 skill 不写文件、不走确认门、不调状态机。

范围未确认（缺 `req-plan.md`）→ 不硬想，提示先回范围确认，退出。

## Rules

**禁止项**：
- ❌ 产正式 `implementation-design.md` 文档——六步里这个独立文档已砍，HOW 只做 build 的后台 context
- ❌ 写范围清单 / 决策页（WHAT + WHY）——那是 `task-plan` 的 `req-plan.md`，PM 拍板
- ❌ 写 PRD（功能行为 / 业务规则 / 权限语义）——那是 `prd-writing`，按真实系统口径
- ❌ 走 PM 确认门 / 让 PM 逐行确认工程 HOW——PM 不关心组件怎么拆、reducer 怎么写
- ❌ 重建被砍的「原型简化项 / SIMP」机制——build 后的覆盖审计（独立视角 agent 对照范围清单硬 diff）才治残版 / 降级占位，不靠 build 前预先登记简化
- ❌ 把视觉规范细则（像素 / 颜色 / 字号 / 视口断点）当 HOW 产出——那归 `docs/DESIGN.md`
- ❌ 在 PM 视图里出现工程黑话（reducer / dispatch / 组件树 / 状态机内部名）——这层不进 PM 视图，真要跟 PM 说一句就用 PM 听得懂的话

## 边界（build 阶段后台）

- **允许动作**：读已有产物（`req-plan.md` / `DESIGN.md` / `PRODUCT-STATE.md` / `prototype/`）、在后台想清工程 HOW 指导 build
- **禁止顺手做**：不产正式文档、不拆 task、不走确认门、不调复审 / 状态机、不登记简化项
- **退出条件**：HOW 想清，控制权交回 `/pmai-next` 进 build；范围未确认则提示先回范围确认
