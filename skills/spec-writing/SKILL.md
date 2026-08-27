---
name: pmai-spec-writing
description: |
  已确认产品内容的规格成文器：把闭合决定编译为模块规格、PRD、功能需求、功能描述、功能规格或评审稿，也补差和整体优化既有规格。内容由通用模块与可叠加 Profile 组成，完整 PRD 使用唯一 Preset。模块对象、规则、信息结构、任务路径、权限或关键交互未决时返回 design；定位、目标用户、价值、AI 必要性、平台边界或 MVP 前提未决时返回 proposal。
  触发词：根据已确认方案写 PRD / 把已拍板内容整理成规格 / 补全或优化现有规格 / 规范既有 PRD / 生成研发评审稿。
---

# /pmai-spec-writing · 规格文档成文器

## 入口护栏

执行本 skill 前先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止，只引导 PM 先发 `/pmai-init-project`。

若由 `/pmai-lark-review` 携带当前评审批次调用，先完整读取 `skills/lark-review/references/lifecycle-handoff.md`。当本次产物是 review.json 绑定的正式规格时，实际输出改为同批次 `target.md`：只写正文、不带 frontmatter，lint 和文字检查针对 target；不得同时修改正式规格。target 改变后同步更新 `resolutions.json:target` 的派生依据。

所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 执行。runtime 不支持时退化为简短编号问题，没拿到明确答案前不落盘 PM 视图文档。

## 核心模型

spec-writing 只负责把**已经确认的产品决定**编译成可实现、可评审、可验收的规格。它不在写作阶段替 PM 补产品决定。

```text
内容 = 通用内容模块 + 可叠加 Profile
形态 = Preset
```

执行时按需读取：

- [`references/content-modules.md`](references/content-modules.md)：通用内容模块，回答“必须讲清什么”。
- [`references/enterprise-platform-profile.md`](references/enterprise-platform-profile.md)：企业平台领域补充。
- [`references/ai-product-profile.md`](references/ai-product-profile.md)：AI 产品领域补充。
- [`references/full-prd-preset.md`](references/full-prd-preset.md)：唯一完整 PRD Preset，只决定章节编排。
- [`templates/prd.md.tmpl`](templates/prd.md.tmpl)：唯一完整 PRD 模板。

Profile 是可叠加检查项，不是新文档类型：

- 企业平台只加载企业平台 Profile；
- AI 产品只加载 AI Profile；
- 企业 AI 平台同时加载两份；
- 不创建或维护第三个“企业 AI 平台 Profile”。

4 列表只在复杂管理后台中作为**可选动作索引**，不承担完整需求。信息模型、动作详情、异常与空状态、验收标准不能被索引替代。

## 路由边界

入口归属只看决定是否闭合，不看 PM 是否说了“写 PRD”：

- 定位、目标用户、价值链、AI 必要性、平台/应用边界或 MVP 假设未决 → `/pmai-proposal`。
- 模块对象、关系、规则、信息结构、任务路径、权限或关键交互未决 → `/pmai-design`。
- 已有明确依据，只需整理、重排、补已知事实或改写 → 本 skill。
- 纯文字顺句、去 AI 味，且不改结构与内容 → `/pmai-humanize`。
- 产品方向介绍、一页纸或汇报材料 → `/pmai-doc-writing`。

“补需求 / 把需求补完整”默认仍需产品决定，先按缺口层级路由；“按已确认内容补文档 / 重排结构 / 改文风”才是规格补差。不得用默认值替 PM 补齐产品模型。

## Proposal gate（先于文档目标）

任何调用方在选择“模块规格 / 功能型规格 / 既有规格补差”、确认产物路径或修改规格文件前，统一先运行：

```bash
python3 "$PMAI_HOME/scripts/proposal-contract.py" status "$REPO_ROOT"
```

按返回状态处理：

- `accepted`：读取合同指向的当前 Proposal 和固定下游交接；产品回答、边界和 MVP 约束只继承、不改写；
- `equivalent_baseline`：读取完整等价产品基线，继续判断本次文档目标；
- `required`：新项目的产品级依据不完整，停止 spec-writing，返回 `/pmai-proposal`；不得先选文档目标、创建模块规格或用代码现状补齐产品基线；
- `invalid`：当前 Proposal 或 `PRODUCT.md` 已漂移，停止 spec-writing，返回 `/pmai-proposal` 生成完整新版本；不得继续改写规格。

这道门适用于 PM 手动调用、design 内部调用和自动 finalize。spec-writing 只读取 Proposal 合同与正文，不新建或修改 Proposal。

## Active build gate（手动调用不得绕过变更链路）

PM 手动调用时，在选定文档目标后、读取或修改正式规格前，先检查主仓与 attached worktrees 是否存在 `ready_to_build / building / iterating / final_check`。只要本次文档覆盖任一已批准或 active build 的模块、功能或规范性来源，就停止普通成文路径，按变化层级返回原生命周期：

- 产品定位、用户、价值、职责边界、MVP 或关键成立前提变化 → `/pmai-proposal`；
- 对象、关系、动作、状态、权限、真相源、业务规则、信息结构、任务路径或关键交互变化 → `/pmai-design`，先按 design 的 replan 合同冻结旧候选；
- `ready_to_build` 尚未开工 → 返回 `/pmai-design` 重新编译并固定建造依据，不直接改已批准规格；
- 已进入 `building / iterating / final_check`，且只是在批准模块与当前任务内、不改变产品基线和模块模型的小范围行为或体验调整 → 回当前 `/pmai-build` 反馈循环，由 build 记录 accepted delta；spec-writing 不先改正式规格；
- 只改结构、排版或文风 → 等该 build 落地主线后再补差，避免无业务变化也使批准依据失效。

只有三类编排可以在 active work 相关规格上继续：`/pmai-lark-review` 已绑定并 seal 的受控批次、design 在进入 build 前的内部规格编译、以及 landed 后自动文档对账。它们分别遵守自己的 target / checkpoint / 四分支合同；手动调用不得冒充这些模式。

## 文档目标

| 目标 | 何时使用 | 产物 |
| --- | --- | --- |
| 模块规格 | design 拍板后；或 landed 后按 accepted delta 对账 | `docs/modules/<模块>/spec.md` |
| 功能型规格文档 | PM 要专题、跨模块、功能需求或评审稿 | `docs/modules/<按内容命名>.md` |
| 完整 PRD | PM 明确要 PRD、完整研发评审稿或跨角色交付合同 | 同上，套唯一完整 PRD Preset |
| 既有规格补差 | 已有 PRD/spec 要整体优化结构、内容或文风 | 原路径或 PM 指定路径 |

模块 `spec.md` 是 build 的权威目标合同。完整 PRD 是功能型规格文档的一种形态，不是第二套产品真相源；它从模块规格、当前有效决定和项目规则编译。

## 来源边界

输入按权威性分三类：

- **规范性来源**：相关 Product Proposal（如有）、`PRODUCT.md`、`PRODUCT-RULES.md`、PM 已确认决定、accepted deltas、已定稿模块 `spec.md`。它们决定最终范围和规则。
- **设计与实现证据**：mockup、原型、当前代码、landed diff、build contract 和验收证据。它们帮助理解结构、发现缺口，不能自行定义或缩小需求。
- **过程来源**：`discussion.md`、备选方案、否决理由和试错记录。它们用于追溯，不进入规格正文。

哪怕原型只是 mock 壳，规格也按最终产品目标写。已确认但未实现的需求必须保留；mock、占位、部分落地和未覆盖状态不写入正式规格正文。

## PM 视图与写作规则

产出前完整读取：

- `skills/_shared/PM-VIEW-RULES.md`；
- `_shared/pm-view/writing-rules.md`（通用 PM 文风与禁用表达的唯一正本）；
- `_shared/pm-view/doc-strictness.md`；
- `_shared/pm-view/cross-skill.md`；
- [`references/writing-rules.md`](references/writing-rules.md)（规格正文职责、来源对账与规格 4 问）；
- 按目标选读 [`references/few-shots.md`](references/few-shots.md)。

`_shared/PM-VIEW-RULES.md` §五的表格规则只在选择 4 列动作索引时适用。完整 PRD 并不因此默认使用 4 列表。

模块规格模仿 `few-shots.md` 顶部“大白话模块 spec 金标准”；完整 PRD 也使用同一套简要易懂语体，只增加内容模块，不切换成咨询报告或白皮书语言。

## 手动调用确认

由 design、受控 lark-review 批次或自动 finalize 调用时跳过本节；调用方已确定目标和默认路径，并且已经通过上面的 active build 路由。

PM 手动调用时，先做决定闭合性预判。未闭合就按“路由边界”返回上游，不先问文档格式。闭合后依次确认：

1. **文档目标**：模块规格 / 完整 PRD / 轻量功能型规格 / 既有规格补差。
2. **产物路径**：默认路径或 PM 指定路径。
3. **输入清单**：先列推荐清单，再让 PM 确认加减。

推荐输入：

| 场景 | 输入 |
| --- | --- |
| 模块规格 | discussion/decisions + context pack + impact map 点名真相源；landed 对账再读最终实现、diff 与验收结论 |
| 当前工作完整 PRD/功能规格 | Product Proposal（如有且相关）+ PRODUCT.md + PRODUCT-RULES.md + modules INDEX + 涉及模块 spec/decisions；现状与实现只作证据 |
| 指定跨模块文档 | 上述项目级来源 + PM 指定模块子集，不读无关旧工作 |
| 既有规格补差 | 原文 + 涉及范围的 module spec/decisions 与项目规则 |

PM 已明确覆盖模块、路径或输入时直接复用，不重复提问。

## 附件接管

模块规格或绑定当前工作的功能型规格启用 trigger 0。PM 在对话中提供材料绝对路径和用途时，按 `_shared/pm-view/attachments-upload.md` 调用：

```python
from _lib.attachments import copy_attachment

result = copy_attachment(
    work_dir,
    source_path,
    stage_prefix="spec",  # 功能型规格文档使用 "prd"
    hint=hint,
    input_category=input_category,
)
```

写文档前按 trigger 2 扫描 `docs/inputs/*/`；引用过的附件按 `.work-meta.json:attachments_seen` 和 `registered_at` 升序渲染到文档末尾“参考材料”。跨模块独立文档和既有补差默认不写 `.work-meta.json`。

## 模块规格流程 S1-S6

### S1 核对结论闭合

确认 context pack、`discussion.md` 和 `decisions.md` 没有会改变产品模型的未回答问题。landed 对账还要确认 accepted deltas 均有 PM 接受证据。产品级缺口返回 Proposal，模块级缺口返回 design。

### S2 建立内容覆盖矩阵

完整读取 `content-modules.md`，提炼对象、动作、状态、权限/数据、页面、异常路径和验收。根据已确认事实加载 Profile：

- 多租户、组织、身份、权限、配置、版本、发布、审计或外部接入出现任一信号 → 读取企业平台 Profile，按风险选取相关检查；出现两项以上或平台治理是主任务时执行完整交付检查；
- Agent、生成式判断、人工确认、评测或 AI 失败降级 → AI Profile；
- 同时满足 → 两份都读。

每个对象要能追到动作与状态；每个动作要能追到角色/权限、入口、结果和异常。Profile 是否适用可以从事实唯一推出时自动处理；只有不同选择会实质改变范围且材料无法判断时才问 PM。

### S3 抽取骨架

按需要选择内容模块。复杂功能优先使用：

```text
信息模型 -> 核心动作 -> 异常与空状态 -> 验收标准
```

再补模块定位、业务规则、页面/交互口径、边界与非目标。简单规则文档不强加空章节。章节顺序同时遵守 `_shared/pm-view/section-order.md` 的 `spec.md` 约束。

### S4 写入模块规格

写入 `docs/modules/<模块>/spec.md`。正文只保留当前有效目标；被替代方案和迭代过程留在 Git 与 `decisions.md`。变更日志每条只写改了什么，通常 20 字内、最多 30 字。

### S5 语言把关

按 `_shared/pm-view/writing-rules.md` 统一文风，再按 `references/writing-rules.md` 核对规格正文职责，并参考 `few-shots.md` 的模块规格样例。Profile 不改变语体。

### S6 自检

必须完成：

- 通用模块覆盖检查 + 适用 Profile 的交付检查；
- `references/writing-rules.md` 的“规格 4 问自检”；
- `_shared/pm-view/checklist.md`；
- 按 `_shared/pm-view/writing-rules.md` 做禁用表达机械扫描与一次冷读。

**多视角冷读（可选）**：PM 明确想找盲区或压测已有材料时，可调用 `/pmai-meta <规格路径>`；它不替代本 skill 成文，也不作为默认定稿门。

模块规格到此结束，不套完整 PRD Preset。

## 功能型规格流程 P1-P3.8

### P1 加载最小真相源

绑定当前工作时，必须把 `PRODUCT-STATE.md`、`PRODUCT.md`、`PRODUCT-RULES.md`、`docs/modules/INDEX.md` 和涉及模块主 `spec.md` 的现存文件完整读入上下文。相关 Product Proposal 存在时一并读取。最终 build target 只按 contract paths/entrypoints 选读，不全文灌入大文件。

入口的 Proposal gate 已通过；本步直接按合同指向读取当前 Proposal，或按 `equivalent_baseline` 读取完整等价产品基线，不重复运行状态门。

跨模块文档或既有补差按手动确认清单读取，不绑定无关 active work。读取实现入口时遵守 `_shared/pm-view/input-flow.md` §9.3.1：大于 500 行不得整文件读取。

从输入中分出当前有效结论与缺口：

- 产品级前提缺口 → `/pmai-proposal`；
- 模块决定缺口 → `/pmai-design`；
- 文档结构或表达缺口 → 继续本流程。

### P2 选择内容、Profile 和形态

1. 从 `content-modules.md` 选择必要模块。
2. 按 S2 规则加载企业平台和/或 AI Profile。
3. PM 要完整 PRD 时读取 `full-prd-preset.md` 并套唯一模板；否则按阅读顺序组合内容模块。
4. 规则用分组规则，状态用定义与条件表，流程用叙述，字段用字段表，权限用矩阵。
5. 只有复杂管理后台动作很多、需要快速扫描时才建议 4 列动作索引。

内容决定写什么，Profile 决定补查什么，Preset 决定怎么排。不得把 Profile 写成另一套章节模板。

### P2.5 4 列动作索引确认（条件触发）

完整 PRD 本身不触发本步骤。只有 PM 手动新建文档并选择 4 列动作索引时：

1. 从 module spec 与当前有效决定提取动作组和核心动作；
2. 动作按同一业务维度组织，不用页面、Tab、弹窗、Drawer、面板或字段名充当层级；
3. 角色视角、字段、校验、状态联动和异常下沉到后续完整动作详情，不塞进索引；
4. 向 PM 展示“动作组 → 核心动作 → 使用角色”的命名底稿并等待确认；
5. 确认后生成索引，每个索引项必须在后文有动作详情。

索引标准结构：

| 动作组 | 核心动作 | 使用角色 | 详情位置或一句摘要 |
| --- | --- | --- | --- |

落地主线后的目标对账不重开本确认门。

### P3 成文

完整 PRD 使用 `templates/prd.md.tmpl`；轻量规格按选择的内容模块生成。完整动作至少写清目标与角色、触发与前置、输入与校验、处理规则、结果与状态变化、权限与数据范围、失败与恢复。

4 列动作索引只提供导航，不写完整字段、规则或异常。已确认设计资产只在有评审价值时作为附件引用，不现画 ASCII，不要求每个页面/弹窗配图。

### P3.5 lint

完整 PRD 或包含 4 列动作索引的文档必须运行：

```bash
python3 "$PMAI_HOME/scripts/check-prd-hierarchy.py" "$PRD_PATH"
```

保留现有三类合同：动作层级 UI 词、全篇描述风格、4 列表结构。退出码 `0` 继续；`1` 按输出修订并复跑；`2` 报文件读取错误。模块 `spec.md`、规则收口、状态说明、流程说明和字段口径文档不跑此 lint。

### P3.6 术语对账

反复出现或容易混淆的新业务术语在信息模型定义；数量较多时可在附件增加术语表。全文锁定同一称呼。不在本步直接修改 `PRODUCT.md`，由 landed 文档影响地图决定是否同步项目术语。

### P3.7 决策对账

检查背景/范围、信息模型、核心动作和 Profile 补充是否都能追到规范性来源。不存在依据的内容不是写作缺口：产品级返回 Proposal，模块级返回 design，不把候选默认为最终要求。

### P3.8 跨功能规则对账

发现跨模块产品行为规则时：

- 已有明确决定 → 在当前模块规格或功能规格中写清本次范围需要的规则，并在交接中列出项目级真相源影响；
- 没有确认依据 → 返回 design；若它实际改变定位、平台边界、AI 必要性或 MVP，则返回 Proposal；
- 术语应归 `PRODUCT.md`，跨模块规则应归 `PRODUCT-RULES.md`，视觉规范应归 `DESIGN.md`；spec-writing 只报告这些同步目标，不直接修改这三个项目级真相源，由 design 或 landed 文档对账按各自提交合同处理。

## 既有规格补差 C1-C5

1. **判类型**：功能规格留在本 skill；方向文档转 `/pmai-doc-writing`。
2. **读最小真相源**：原文 + 相关 module spec/decisions + 项目规则；不整仓乱读。
3. **出改稿计划**：结构问题、内容问题、文风问题。PM 已说“直接改”可跳过再次确认。
4. **重写**：允许重排和补已知事实，禁止新增未拍板规则；产品级缺口交 Proposal，模块级缺口交 design。
5. **收口**：完整 PRD 或含动作索引时跑 P3.5；最后按 `/pmai-humanize` 的表达层规则收口。落在 `docs/modules/<按内容命名>.md` 时同步 modules INDEX。

## Landed 后目标对账

实现进入 main 后，不把“代码现在是什么”直接改写成“产品应该是什么”。逐项只允许四种结果：

1. **符合**：实现与规格一致；规格正文不改，现状文档可更新。
2. **accepted delta**：PM 明确接受目标变化；核验依据后先更新决定，再修订规格。
3. **漏实现**：规格已有要求但最终实现缺失、只做 mock、占位或部分能力；保留规格并阻止文档对账完成。
4. **无依据实现**：代码存在规格和决定都没有的产品行为；不得升格为规格事实，返回 design 让 PM 决定接受、调整或移除。

只要本轮出现“漏实现”或“无依据实现”，立即停止正式文档写入：不修改 `PRODUCT-STATE.md`、`PRODUCT.md`、`PRODUCT-RULES.md`、`DESIGN.md`、模块 `spec.md` 或 `decisions.md`，只允许更新文档影响地图/审计证据并记录 `docs-fail`。现状档只能在所有对账项都有合法落点、文档收尾可以完成时更新；不能把“记录缺口”当作先改现状档的理由。

正文不写“已覆盖 / 未覆盖 / 部分落地 / mock 占位”。这些属于验收证据、影响地图或 `PRODUCT-STATE.md`。

## 写作与质检

通用文风统一遵守 [`_shared/pm-view/writing-rules.md`](../_shared/pm-view/writing-rules.md)；规格正文职责、来源对账和规格 4 问遵守 [`references/writing-rules.md`](references/writing-rules.md)。Profile 只增加内容检查，不改变语体。

Few-shots 按目标路由：

- 模块规格：读 [`references/few-shots.md`](references/few-shots.md) 顶部大白话金标准；
- 内容写法：读同一主题的规则、流程、字段、权限和动作详情对照；
- 完整 PRD：只参考章节与内容组织，不模仿旧重型语气；
- 企业平台与 AI 内容：以对应 Profile 的检查项为权威，few-shots 只作表达示例。

PRD 质检至少检查：

1. 信息模型是否先于动作，对象、关系、状态和权威来源是否明确；
2. 每个动作是否写清前置、输入、规则、结果、权限、失败与恢复；
3. 异常与空状态是否覆盖无数据、状态/权限变化、外部失败和并发冲突；
4. 验收是否能验证正常路径、边界和恢复；
5. Profile 要求是否完整且没有复制通用章节；
6. 4 列表是否只作动作索引，每项是否有完整详情；
7. 是否混入代码偶然行为、mock 覆盖状态、备选方案或未确认推测；
8. 完整 PRD lint、术语和文字冷读是否通过。

## 收尾

- 模块规格：写完、自检通过后交回 design 或自动 finalize；独立调用 spec-writing 不自行把模块推进到 `ready_to_build`，只有 design 在决定闭合、项目建造定义与 ready 授权完成后才能进入该状态。
- 绑定当前工作的功能型规格：提供产物路径、决策/规则对账落点和任何未决缺口，交回自动 finalize；不自带新的产品确认门。
- 跨模块功能型规格或既有补差：PM 确认后写入；落在 `docs/modules/` 时更新索引；手动调用不自动 commit。

功能型规格是规范性产物。landed 后仍按四分支对账，不由实现反向定义需求。
