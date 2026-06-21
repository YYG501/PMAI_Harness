# Dormant Skills 清单（框架瘦身 v2）

> **状态**：草稿 / 配套《吸收 ExampleAgentProject 设计方法 · 框架瘦身改造方案 v2》§2
> **日期**：2026-06-19
> **作者**：PM + AI

## 这份清单是什么

框架瘦身的方向是**缩小 PM 面对的活跃入口**（从 28 个 skill 收到 ~7 个），而不是删功能。瘦身原则：

> **dormant = 保留不删、默认不用、可随时重新激活。**

dormant 的 skill 仍留在框架里——它们的 SKILL.md、references、脚本、测试、不变量**全部保留**，不删一行代码。只是：

- **PM 面前不出现**：日常工作只用活跃集（`/init-project` / `/design` / `/mock` / `/build` / `/close` / `/publish-to-lark` / `/status`）。
- **默认不主动触发**：AI 不在常规流程里调它们。
- **可重新激活**：以后真需要（如并行多 task），把对应 skill 拉回活跃集即可，状态机 / 脚本原地就能用。

这样既砍掉了过度设计的仪式感，又不破坏框架三周积累的工程化资产（隔离 / 真相源治理 / 三道审 / 不变量）。瘦身是**可逆**的。

> **【2026-06-21 强制门】新增任何 dormant / 合并 / collapse 条目前，先过对抗三问**（@读 `skills/_shared/anti-cut-check.md`）：逐条答 (a) 丢了什么 (b) 对所有需求类型成立吗 (c) 是不是把内核当仪式砍了，用对称判别尺判一次，**三行自答附在该条目下**。本清单自身就暴露了漏这道门的代价——当年"req-analysis 并入主干第①②问""决策收家"等条目正是没过门才砍错（同构错 6 处，见 `docs/设计/工作方法论与工作流-总纲.md` §0）。判别尺两边都用：砍错的捞回（如 req-analysis 探索内核），砍对的（7-stage / task 机器）别捞。

---

## 为什么这些进 dormant（按组）

### A 组 · task 状态机全套

`task-plan` / `task-spec` / `task-confirm` / `task-execute` / `task-verify` / `task-submit` / `close-task`

- **为何 dormant**：task 机器是为"并行多 task、PM 逐个看 demo 验收"设计的多阶段流水线。ExampleAgentProject 用几个 skill 就做得不错，反衬这套 task 状态机对单人 PM、串行推进是过度的——入口多、要记中间状态、撞反文档税。瘦身后单位是**功能模块**（不是 task），推进靠 `/design`（设计）+ `/build`（建）+ `/close`（收尾）三步走通，不需要 task 卡 / task 状态切换。
- **何时重新激活**：真要**并行多 task**（同时推进好几片互不阻塞的工作、各自独立看 demo）时，把 task-* 拉回活跃集。
- **⚠️ 关键依赖（别 dormant 错）**：活跃的 `/build` **复用了 task-execute 底下的两件无状态资产**——`exec-adapter`（可插拔执行器，实体脚本在 `scripts/exec-adapters/{codex,cursor-agent,gemini,manual}.sh`）和 `build-audits.py`（三道审编排）。dormant **不等于删除或移走这些脚本**：`scripts/` 下的实体脚本必须保持可达，`/build` 才能跑。dormant 的只是 task-execute 的**状态机入口**，不是它底下的工具脚本。

### B 组 · req 阶段驱动 / 异常恢复薄壳

`req-stage-gate`、`next`

- **为何 dormant**：这两个是老的"需求推进主驱动 / 阶段闸门"。瘦身后 req 退化成纯动作（新开 / 重做一个模块），不再是带阶段状态机的文档层；主驱动已搬到 `/design`（开工）和 `/close`（收尾）。`/pmai-next`（推进到下一步）和 `req-stage-gate`（阶段闸门 / 异常恢复薄壳）失去主路径职责。
- **何时重新激活**：窗口被关 / 流程卡住 / 状态不一致时作兜底恢复入口；或重新启用 task 状态机时配套拉回。
- 注：`next` 不在改造方案 §2 明列的 dormant 清单里，但它是 req 阶段驱动的一部分，随 `req-stage-gate` 一起进 dormant（活跃集的 design / build / close / mock 均不引用 `/pmai-next`，已核）。

### C 组 · 后台辅助 / 深问帮想（并入活跃 skill 或按需）

`implementation-design`、`spec-polish`、`doc-update`（注：`req-analysis` 已于 2026-06-21 **删除**、非 dormant——见下）

- **`req-analysis`（深问帮想）【2026-06-21 已删，非 dormant】**：上一轮写"并入 `/design` 信息设计主干第 ① ② 问"是**同构错**（①②问是信息呈现起点、不是问题探索；把"探索能力"内核当"强制闸门"形态一起砍了，见总纲 §0 第 1 处）。**纠正（开放2·已拍 B）**：诊断内核**真搬**进 `skills/_shared/req-questioning.md`，成 `/design` **段①探索**（escape-hatch 默认放行、闻味才 push、砍外部 demand 三问、融 office-hours 对话诊断）。req-analysis skill 目录已删、不保留 dormant。
- **`implementation-design`（后台想工程 HOW）**：build 前后台快速想清楚组件怎么拆 / 状态怎么管 / mock 数据结构。瘦身后这个职责由 `/build` 内部按需做（PM 选工具后建之前），不单独成 skill / 不走确认门。
- **`spec-polish`（磨文）**：**逻辑已并入唯一的写规格 skill `/design`**——磨文字成了写规格的收口步。ExampleAgentProject 的 spec-polish 9 条文字纪律的**操作正本**已在 `_shared/info-design.md` §四「磨文字 · 收口纪律」（`/design` 写规格时 `@读`、逐条扫）；逐条对账 + 框架原本缺的三条细则在 `_shared/pm-view/writing-rules.md` §3.13。框架里**本来就没有 spec-polish 这个 skill 目录**（它在 ExampleAgentProject 仓）；这里列它是为了明确"它的纪律去哪了"——不另起一个磨文 skill，纪律进 `_shared` 单一真相源（三处不并存：info-design 给操作口诀、§3.13 给对账细则、writing-rules 给禁用清单）。
- **`doc-update`（文档偏差处理）**：task 完成后处理文档偏差 / 把功能清单沉淀进模块规格。瘦身后这个价值并入 `/close` 的沉淀步（文档自动归位 + 老规格 vs 新原型对账）。
- **何时重新激活**：implementation-design 在某需求特别复杂、想单独跑一道工程预想时可手动调；doc-update 随 task 状态机一起恢复。（`req-analysis` 已删，深问能力常驻 `/design` 段①探索，无需"重新激活"。）

### D 组 · 小改快捷路径

`quick-fix`

- **为何 dormant**：quick-fix 是"不走 req/task 流程的 PM 审批快捷修复"。瘦身后 **main 写保护放宽**——小改直接在 main 上改、不开 worktree、不走审批，所以 quick-fix 的"建临时 worktree + 审批 + ff-only 合入"那套仪式不再需要。quick-fix 里**真正有价值的"一致性扫一下"**已变成任何编辑自带的轻行为（写规格 skill 收口顺手跑的一致性扫描，见改造方案 §4）。
- **何时重新激活**：如果以后想恢复"小改也走审批留痕"的纪律，拉回 quick-fix。

### E 组 · 项目级方向 / brownfield 接入（按需，非全 dormant）

`project-solution`、`codebase-audit`、`align-to-live`、`scrape-prototype`

- **`project-solution`（项目级方向规划）**：⚠️ **不是纯 dormant，是"按需主动入口"**。它不进日常推进流程，但**活跃的 `/init-project` 明确推荐它**——init 只建骨架 + 一句话定位，PM 想"把项目方向系统过透（定位 / 用户 / 角色 / 路线全过一遍）"时主动调 `/pmai-project-solution`；AI 在 init 诊断到已有 PMAI 脚手架时也优先推荐它重做方向。所以它**保留可主动调用**，不该被当成"激活才能用"。
- **`codebase-audit`（brownfield 接入扫码）**：已有代码库接入框架时产出代码现状档。新项目用不到，已有项目接入才用——`/init-project` 在 A 步诊断到源码时优先推荐它。**按需保留可调**。
- **`align-to-live`（对齐线上真实产品）/ `scrape-prototype`（站点爬原型）**：这两个是 brownfield 的两条专门 diff 轴（原型对齐现实 / 照某站重建）。普通新项目用不到；PM 手动调或 `/design` 范围确认里 AI 判断该对齐 / 该爬时建议。**按需保留可调**。
- **小结**：E 组**严格说不是"默认不用"而是"按需用、不进日常流程"**——它们不在 ~7 个活跃集里占位，但都保留可主动调用、且被活跃 skill（主要是 `/init-project`）作为分支推荐。落地时别把它们的入口砍死。

---

## 框架自身维护留用（不算业务活跃集，也不 dormant）

`pmai-upgrade`（升级框架）、`skill-improve`（消化 skill 反馈）——这两个是框架自身的维护工具，跟业务推进无关，PM 维护框架时随时用，不在瘦身范围内。

---

## 未在改造方案 §2 明列、需 PM 核的边角

| skill | 现状 | 建议 |
|---|---|---|
| `cancel-req` | 废弃当前 req（清 worktree / 分支、标 cancelled、不 merge）。改造方案 §2 dormant 清单未提 | 随 req 流程弱化一起进 dormant（活跃集里"废弃"靠直接删 worktree / 分支 + `/close` 不 merge 即可）；**留给 PM 核**是否要保留一个显式"废弃"入口 |
| `next` | 老 req 推进主驱动，已被 /design + /close 取代 | 随 B 组（req 阶段驱动）进 dormant，作异常恢复薄壳 |
| `task-status` / `task-submit` / `task-verify` | task 状态机配套（status 总览 / 呈交 / 验收）| 随 A 组 task-* 全套一起 dormant。**注：活跃集的 `/status` 是新建的轻量 `pmai-status`（复用 `status-view.py`），不是这个 `task-status`** |

---

## 活跃集对照（瘦身后 PM 面对的入口）

| skill | 作用 |
|---|---|
| `/init-project` | 起项目骨架（只建脊柱、不锁流程） |
| `/design` | 唯一写规格 skill（信息设计 + 三件套 + 磨文收口） |
| `/mock` | 据讨论生成多 mock 变体给 PM 选 |
| `/build` | 大需求才用（PM 选工具 + 选要不要 worktree）|
| `/close` | 收尾沉淀（决策 / 术语回写 + 对账 + 归位 + merge）|
| `/publish-to-lark` | 文档发飞书 |
| `/status` | 现状视图（轻量 `pmai-status`，复用 `status-view.py`；可选）|

> dormant 的 skill 都不在这张表里占位；但 E 组（project-solution / codebase-audit / align-to-live / scrape-prototype）保留**按需主动调**，主要被 `/init-project` / `/design` 作为分支推荐。
