---
name: pmai-meta
description: |
  PMAI 问题会诊：当 PM 觉得不对、感觉方案只是补丁、AI 只是在复述、缺少新思路，或需要在设计 / 写作 / build 前把真问题、前提、替代方向和下一步想清楚时使用。保留 /pmai-meta 命令名，但不要把它当成“升维分析输出器”；它先读资料、选择会诊路径、一题一问、挑战前提、给出替代方向并停住让 PM 选，最后才降回正确下游。
  触发词：grillme / grill me / 只是复述 / 没新思路 / 不够深入 / 继续问我 / 帮我深想 / 不合理 / 感觉不对 / 这东西到底改变了什么 / 本质是什么问题 / 第一性原理 / 升维 / 拔高 / 语义坐标 / 多角度看看 / 找盲区 / 反方 / 对抗分析 / 多 AI / multi ai / multiai。
---

# /pmai-meta · 问题会诊

> **它是什么**：PMAI 里处理“产品判断、工作流判断、材料根基判断”的问题会诊入口。
> **它不是什么**：不是高级分析段落生成器，不替 PM 拍板，不替代 `/pmai-design`、`/pmai-doc-writing`、`/pmai-spec-writing`、`/pmai-build`，也不把 skill / workflow 改造误交给 design。
> **金标准**：结束时 PM 拿到的不是一段复述，而是“这轮到底在判断什么、哪个前提最危险、有哪些可比较方向、PM 选了哪条、下一步交给谁”。

---

## 先读这些方法源

执行 `/pmai-meta` 时先读：

1. `references/problem-framing.md`：通用会话门禁，包含 Read Gate、One Question Gate、Premise Gate、Alternatives Gate、Coverage Gate、Handoff Gate。
2. `references/product-idea-framing.md`：产品想法会诊，处理“值不值得做、给谁、现状怎么凑合、最小切口是什么”。
3. `references/pmai-workflow-decision.md`：PMAI workflow / skill 决策，处理“调用现有、改现有、新建入口、还是不做”。
4. `references/thinking-toolbox.md`：思考工具箱，承接旧 meta 的升维、第一性原理、多视角压测、UI 信息 / 任务 / 判断层。

表达收口时再读 `references/词表与句式.md`。词表只用于最后表达校验，不承担思考流程。

涉及 gstack / grillme 或外部会诊式方法时，读 `skills/_shared/gstack-integration.md`：`/pmai-meta` 只做**方法吸收**，不 runtime 调 gstack，不把 gstack 输出当 PMAI 真相源。

---

## 入口判断

命中以下任一，就进入问题会诊，不要直接输出结论：

- PM 说“不合理 / 感觉不对 / 只是复述 / 没新思路 / 不够深入 / 继续问我 / 帮我深想 / grillme”。
- 当前卡点不是按钮、字段、文案小改，而是目标、前提、评价标准、产品方向、页面重心或表达停在功能层。
- 方案、稿子、页面已有锚点，但 PM 想判断“根上是否成立”，不是只挑局部问题。
- 设计 / 写作 / build 之前，AI 发现继续执行会在旧假设上打补丁。
- PMAI 自身的 skill、workflow、文档同步、真相源、入口归属说不清。

不命中时直接回到对应产出型 skill：小文案交 `/pmai-doc-writing`，模块结构交 `/pmai-design`，构建交 `/pmai-build`，不要强行深想。

---

## 三条会诊路径

后台先判断路径，不把路径名机械丢给 PM：

| 路径 | 何时使用 | 主要参考 | 合格产物 |
|---|---|---|---|
| 产品想法会诊 | PM 有新想法、产品方向、是否值得做的问题 | `product-idea-framing.md` | 目标用户、现状对手、需求证据、最小切口、替代方向、下一步验证 |
| PMAI workflow 决策 | skill / workflow / 文档同步 / 真相源 / 工具边界问题 | `pmai-workflow-decision.md` | 相关现状、四类方向、推荐方向、PM 拍板点、正确落点 |
| 已有材料压测 | 已有稿子、页面、规格、方案，需要判断根上是否成立 | `problem-framing.md` + `thinking-toolbox.md` | 真问题、危险前提、主要盲区、替代方向、是否回到成文 / 设计 / 停住 |

路径可以切换：产品想法如果已经有页面稿，转压测；压测发现缺的是 PM 判断，转一题一问；workflow 决策发现其实是模块结构问题，才回 `/pmai-design`。

---

## 必须产出五件事

问题会诊的输出不是“分析段落”，必须收敛到五件事：

1. **本轮判断**：这轮到底在判断什么，不要停在 PM 一开始给的解法。
2. **前提账本**：哪些是已读资料或 PM 已确认的事实，哪些只是 PM / AI 的假设。
3. **危险前提**：哪个前提错了，当前方向就要改；什么证据能推翻它。
4. **替代方向**：至少 2 个可比较走法；不能只有“建议这样做”。
5. **下一步落点**：回到 `/pmai-design`、`/pmai-doc-writing`、`/pmai-spec-writing`、`/pmai-build`、`/pmai-skill-improve`，或明确停住。

如果无法给出五件事，说明还没问够，继续按 `problem-framing.md` 的门禁追问。

---

## 主流程

### 0. Read Gate：先读再问

先找能回答问题的上下文，不让 PM 重复讲已经拍过的东西：

- 项目级：`PRODUCT.md`、`PRODUCT-STATE.md`、`PRODUCT-RULES.md`、`DESIGN.md`。
- 模块级：`docs/modules/<模块>/discussion.md`、`decisions.md`、`spec.md`、`.work-meta.json`。
- 材料级：PM 本轮给的稿子、方案、页面、mockup、原型路径或外部材料。
- PMAI workflow：相关 `skills/<skill>/SKILL.md` 和 references、`README.md`、`CHANGELOG.md`、`tests/` 里对应回归。

能从资料查到的，不问 PM；读不到但会改变判断的，才问。

### 1. 选路径，但别把路径名丢给 PM

后台分型只用于选问法：

| 后台类型 | 处理方式 |
|---|---|
| 新想法 / 方向不清 | 产品想法会诊，先问现状对手和需求证据 |
| PM 说方案不对 | 先做根因诊断，禁止继续修补原方案 |
| 有明确稿子 / 方案 / 页面 | 先压测；若缺的是 PM 判断，转回访谈 |
| PMAI skill / workflow 边界不清 | 先读相关 skill，再做 workflow 决策 |
| 只是表达高级感 | 用工具箱里的升维 / 词表，但先确认它服务哪个判断 |

对 PM 只说业务话：现在卡在“要不要做 / 给谁用 / 怎么说 / 页面服务哪个判断 / 哪个前提不稳”，不要说“我进入 A 模式 / B 模式”。

### 2. One Question Gate：一题一问

每次只问一个会改变判断的问题。问题要满足：

- 具体，不抽象。
- 带一个推荐默认答案，帮助 PM 快速拍。
- 用业务语言，不暴露 “lens / toolbox / stage / 多 agent 类型”等内部词。
- 问完就停，等 PM 回答；不要把 3 个问题塞进一段话。

### 3. 按路径选择关键问题

不要机械全问。按场景选 2-4 个最关键问题。通用问题：

1. 现在没有它，PM 或用户怎么凑合？
2. 这轮到底要改变谁的哪个判断？
3. 哪个前提如果错了，整个方案就不成立？
4. 最小值得做的版本是什么？
5. 不做 / 晚做会损失什么，做了会挤掉什么？
6. 6 个月后它失败，最可能败在哪里？

如果 PM 的第一答很泛，必须按 `problem-framing.md` 追问到具体人、具体场景、具体代价或具体反例。

产品想法会诊优先看 `product-idea-framing.md`；PMAI workflow 决策优先看 `pmai-workflow-decision.md`。不要拿产品想法的问题硬问 skill 边界，也不要拿 PMAI 内部分类硬套普通产品想法。

### 4. Premise Gate

给方向前，必须点名一个最危险前提：

```text
这轮最危险的前提是：<一句话>。
如果 <证据或情况> 成立，那我们现在的方向就该改。
```

如果找不到危险前提，就说明问题可能很小，不该继续问题会诊；回到直接执行。

### 5. Alternatives Gate

任何结论前必须给 2-3 个可比较方向。常见替代方向：

- 做小：只做最小能验证判断的版本。
- 换对象：服务另一个角色、场景或决策。
- 换页面重心：从信息展示改成判断 / 动作 / 风险控制。
- 先验证：先拿材料、原型或人工流程验证前提。
- 先不做：记录原因和触发条件，避免伪需求进入 build。

PMAI workflow 决策还必须包含“调用现有 / 改现有 / 新建入口 / 先不做”里的至少两个真实选项。PM 没拍前，不把某个方向写成最终方案。

**硬门禁**：Alternatives 输出后必须停住让 PM 选。可以给推荐默认答案，但不能推荐完继续写最终结论、不能直接路由下游、不能直接改文件。

### 6. Coverage Gate

输出最终结论前问：

```text
我感觉关键问题已经覆盖了。还有没有一个没问到、但会改变判断的点？
```

PM 说有，就继续追问；PM 说没有，再收束。

### 7. Handoff Gate

最后只输出这些：

```text
## 本轮判断
<一句话：真问题 / 判断标准 / 根因>

## 推荐方向
<方向 + 为什么>

## 被排除方向
- <方向>：<为什么先不走>

## 仍需 PM 拍板
- <问题，如无则写“无”>

## 下一步
<回到哪个 skill 或明确停住>
```

不要输出空泛总结，不生成长期产品文档。文档成文仍交给 `/pmai-design`、`/pmai-doc-writing` 或 `/pmai-spec-writing`；skill 反馈消化交给 `/pmai-skill-improve`。

---

## 工具箱怎么用

旧 `/pmai-meta` 的能力全部保留，但位置变了：

- **升维 / 换高度**：当表达停在功能层，或页面 / 文案不清楚服务哪个判断时用。
- **第一性原理**：当前方案依赖旧惯例、竞品类比或“大家都这么做”时用。
- **多视角压测**：已有稿子、方案、页面或规格草案，需要找盲区和根因时用。
- **UI 三层问法**：页面到底是信息展示、任务执行还是判断决策说不清时用。

这些工具只在问题会诊里服务“真问题 / 前提 / 替代方向 / 下一步”。禁止把工具箱章节当成前台模板逐项输出。

---

## 与其它 skill 的边界

- `/pmai-design`：负责模块结构、信息模型、状态、动作、规格三件套。Meta 只负责把问题模型想清楚；只有产品模块结构问题才回 design。
- `/pmai-doc-writing`：负责产品方向、介绍、定位、标题、对外表达成文。Meta 只给重定位结论和判断标准。
- `/pmai-spec-writing`：负责功能型规格文档和模块规格成文。Meta 不写完整 PRD。
- `/pmai-build`：只在功能锚点稳定后执行。Meta 可以帮判断锚点稳不稳，但不进入默认 build 门。
- `/pmai-skill-improve`：负责把 PM 对 skill 的反馈消化进 SKILL.md / references / tests / feedback archive。Meta 只判断“该改哪个 skill / 是否该新建 / 是否该先不做”。

一句话：Meta 让“要解决什么、为什么这样、还有哪些方向”变清楚；下游 skill 才把它写成文档、规格、原型或 skill 改造。

---

## 反模式

- PM 说“不合理”，AI 继续在原方案上加字段、加提示、加解释。
- 没问 PM 关键判断，就输出一段“本质是……”的分析。
- 把外部会诊式方法、grillme 或 gstack 当成要直接调用的 runtime，而不是吸收到 PMAI 问题会诊纪律里。
- 只给一个推荐方向，没有替代方向和被排除方向。
- Alternatives 后没有停住，推荐完就继续写最终方案或路由下游。
- workflow / skill 边界问题没读现有 skill，就建议新建 skill。
- 把 skill / workflow 改造误交给 `/pmai-design`。
- 用“升维 / 第一性原理 / 多视角”当章节标题给 PM 看。
- 把 PM 的话整理得更顺，但没有新增判断、前提挑战或下一步落点。
- 把问题会诊产物写成长期文档，越过 design / doc-writing / spec-writing / skill-improve。
