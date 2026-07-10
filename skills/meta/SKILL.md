---
name: pmai-meta
description: |
  PMAI 产品元思考：当目标不清、方案像补丁、旧范式冲突、产品模型不稳，或 PM 说“不合理 / 感觉不对 / 只是复述”时，产生危险前提、反例、替代模型与推荐判断，再返回 design 主线。
  触发词：只是复述 / 没新思路 / 不够深入 / 帮我深想 / 不合理 / 感觉不对 / 本质是什么问题 / 第一性原理 / 找盲区 / 反方 / 对抗分析。
---

# /pmai-meta · 产品元思考与判断模型

## 入口护栏

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止并引导 PM 先发 `/pmai-init-project`。

执行前完整读取：

- `references/product-meta-thinking.md`
- `references/problem-framing.md`
- `references/product-idea-framing.md`
- `references/pmai-workflow-decision.md`
- `references/thinking-toolbox.md`
- `references/词表与句式.md`
- `skills/_shared/context-reconstruction.md`
- `skills/_shared/decision-policy.md`
- 涉及 gstack 时再读 `skills/_shared/gstack-integration.md`

## 定位

meta 是 design 按需调用的内部产品判断能力，也保留手动入口。它不生成平行流程、不替代 design 成文、不把用户的话换一种说法后冒充洞察。

它不是升维分析输出器。gstack office-hours 和 grillme 只提供反讨好、追问与反例纪律，不 runtime 调 gstack 代替 PMAI 自己的判断模型。

合格的 meta 至少新增下面三类内容中的两类，并且必须包含最危险前提：

- 一个原讨论里没有说出的判断；
- 一个会推翻当前方向的反例或证据；
- 一个在对象、责任、状态、权限、真相源、判断标准或验证路径上真正不同的模型。

如果没有产生新判断、反例或取舍，视为失败，继续读上下文或回到 design 直接执行，不输出空泛总结。

## 何时自动触发

- 目标用户、要改变的判断或成功标准说不清；
- 当前方案是在旧页面 / 旧分类上不断加字段、加提示、加例外；
- 对象、责任、状态、统计、权限或真相源互相打架；
- 新需求可能推翻已生效决定；
- 页面到底服务信息查看、任务执行还是判断决策不清；
- PM 第一次说“不合理”“感觉不对”“只是复述”“帮我深想”。

小文案、明确机械动作、可由当前事实唯一推出的选择不需要 meta，直接返回下游。

## 主流程

### 1. 先恢复确定性上下文

优先使用 design 已生成的 context pack；没有或输入已变化时重新编译。先读 active / superseded 决定、当前事实、未决问题和相关实现，能从文件回答的绝不问 PM。

### 2. 把问题改写成判断句

```text
这轮要判断的是：是否 / 如何 / 何时 <做某件事>，以便 <谁> 做出 <哪个判断或动作>。
```

然后区分：

- 事实；
- 约束；
- 真相源；
- 假设。

### 3. 主动挑战前提

必须给出：

```text
最危险的前提：<一句话>。
反例：<什么真实场景或证据会让它失败>。
如果 <证据/情况> 成立，当前方向应改成 <什么>。
```

找不到危险前提通常说明这不是 meta 问题，直接返回 design。

### 4. 只问会改变模型的问题

缺少 PM 判断时一题一问，并带推荐答案与业务依据。短答只在后果不清时追问一次；连续两次没有新信息，就把它标为未验证假设，不继续消耗 PM。

不得把每个 finding 变成问题。按 `decision-policy`：机械项自动处理，可逆偏好给推荐并继续，只有真实产品模型岔路才立即让 PM 拍。

### 5. Alternatives 只在真实岔路时出现

“真实岔路”是指两个方向会改变对象、责任、状态、权限、真相源、页面任务、成功标准或验证路径。此时给 2–3 个替代模型，每个写成立条件、代价和推荐，然后停住让 PM 选择。

如果只是同一模型下的文案、布局、密度或实现偏好，不强制凑 2–3 个方案；直接给推荐并返回 design。视觉/交互真实岔路交给 mockup，不在 meta 里换皮。

### 6. 返回 design 和决策上下文

固定输出：

```text
## 当前判断
<这轮真正要判断什么，以及当前推荐>

## 隐含前提
- 事实：
- 约束：
- 真相源：
- 假设：

## 最危险前提
<一句话>

## 反例
<会推翻当前方向的场景或证据>

## 替代模型
- <只有存在真实产品模型岔路时列 2–3 个；否则写“无真实模型岔路”>

## 代价与推荐
<推荐方向、放弃什么、为什么>

## 返回 design
<要补进对象 / 动作 / 状态 / 权限 / 页面 / 异常路径的具体结论>
```

由 design 把分析过程写进 `discussion.md`；只有 PM 已明确拍板的结论才进入 `decisions.md`。meta 自身不另建文档、不改 `spec.md`、不推进 build 状态。

## 多视角与多 Agent

“多视角”默认指同一主控从多个角度压测，不冒充多个独立 Agent。只有 PM 明确要求多 Agent 时才使用 runtime 的 multi-agent 能力；不可用时明确说明退化。多视角最多选择 2–5 个互补视角，不为数量凑观点。

## 与其它能力的边界

- 模块对象、动作、状态、权限、页面和规格：返回 `/pmai-design`。
- 视觉或交互模型的可视化岔路：返回 design 后自动调用 `/pmai-mockup`。
- 模块规格 / 功能型规格成文：返回 design 后自动调用 `/pmai-spec-writing`。
- 产品介绍、方向 memo：交 `/pmai-doc-writing`。
- PMAI skill / workflow 反馈：交 `/pmai-skill-improve`。
- 功能锚点稳定后的实现：交 `/pmai-build`。

## Rules

- 不复述；必须产生新判断、危险前提、反例或真实取舍。
- 第一次发现补丁味或收到 PM 质疑就回根因，不继续在旧方案上修字句。
- alternatives 不是仪式：只有真实产品模型岔路才强制 2–3 个方向。
- 不把每个 finding 变成 PM 问题；按共用 decision policy 推进。
- 结论回到 design 和既有决策账本，不生成第二条流程。
- 外部方法只作为问法和压测素材，PMAI 产品判断模型仍是前台合同。
