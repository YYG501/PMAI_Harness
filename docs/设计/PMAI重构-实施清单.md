# PMAI 重构 · 实施清单

> **状态**：实施层 / 2026-05-29 / 配套 [`PMAI重构方向-office-hours收敛.md`](./PMAI重构方向-office-hours收敛.md)（方向真相源）。
> **来源**：对着仓库现状（`skills/` / `scripts/` / `hooks/` / `templates/`）的 4 维 grounded 分析。
> **怎么读**：本文是"现有资产逐项去留 + gstack 怎么接 + worktree 怎么走"。**最该先看 §5「PM 必须拍的决策清单」**——其余表都是在等这几条拍了之后才动手。
> **标记**：★ = 结构决策，必须 PM 拍板（不允许 AI 自决，见 memory「结构决策类中间产物必须 PM 拍板」）。

---

## §1 skill / stage 去留（23 skill + 7-stage）

### 砍

| 资产 | 现职责 | 怎么处理 | ★ |
|---|---|---|---|
| **7-stage 状态机**（`_lib/stages.py`） | 固定 7 段前置流水线 + 每段全文确认门 | **坍缩成方向稿 §2.3 六步**；PRD 从 stage 3 后移到第⑥步。`STAGE_NAMES`/`STAGE_OUTPUT_FILES`/banner「Stage N/7」全重写或删 | ★ |
| **req-stage-gate** | 7-stage 编排器/主推进引擎 | **整体砍**（没 stage 边界就没它）。有用部分（speed mode 结构决策前置、worktree 残留检测）并入六步对应环节 / `next` 入口 | ★ |

### 降 AI 后台（保留能力，移出 PM 主视图）

| 资产 | 怎么变 | ★ |
|---|---|---|
| **req-analysis** | 取消强制 stage；10 章 analysis.md 不再每 req 强产；"深问"能力保留为 new-req 里 AI 后台帮 PM 想清楚（轻量讨论稿，不固化 10 章、不强制 reviewer 链）。**留薄判断接口、别变纯文档机器人** | ★ |
| **implementation-design** | 新六步里无独立位置——**产品口径的"实现文档"= task-plan 的详细范围清单+决策页（PM 拍板）**；本 skill 管的**工程 HOW（组件拆分/状态管理/mock 数据结构/mock 边界）一律降 AI 后台，不产正式文档、不 PM 逐行确认**。**砍 SIMP 机制**（它把交互裁成占位壳=视觉上限被压低根因）。只留极薄"多 task 数据一致性/mock 边界"作 build 后台 context | ★ |
| **task-spec** | PM 不再手敲、不再过确认门；降为 AI build 前后台自动生成的内部执行依据；三区里"PM 确认区"失效（范围已在第②步确认）。留作异常恢复入口 | ★ |
| **task-confirm** | worktree fork 逻辑保留、AI 后台**自动建**（PM 零窗口切换、完全不感知）；**随阶段 0 早上**（2026-05-29 D8 PM 拍早上）、但走 spike 验证。留作异常恢复入口 | ★ |
| **close-task** | merge/归档/清 worktree 逻辑保留但 AI 后台自动跑（demo 确认后自动链）；两阶段切窗口体感取消。留作异常恢复入口 | ★ |
| **task-verify** | 落两件事：① **行为审**——②派生的验收流程驱动 gstack `/browse` 自动走（确定性、每 build 跑、产证据，PM 既有机制背后本就是 gstack browser）；② 它本身就是**呈交闸门**（PM 一句话 pass/打回，唯一拍板点，架在三道审证据之上）。自测说明来源从 task md 改为第②步范围清单派生 | |

### 改造（保留 PM 主路径，但语义/时序变）

| 资产 | 怎么变 | ★ |
|---|---|---|
| **init-project** | 保留主入口；产物并入新脊柱：DESIGN.md 升级成"N 条正向视觉约束"（非禁止项清单）；新增 PRODUCT-STATE.md；建 `prototype/` 一等位置 | ★ |
| **new-req** | 保留主入口；下游不再 brief→analysis→PRD 前置链，改为：@读 PRODUCT-STATE + 跑主原型 → 第②步范围确认。第②步走**三条上坡路**（直奔清单 / 收范围对话 / 视觉变体探，按 PM 状态 AI 临场判断，见方向稿 §2.3.1）→ 选定方向 → 深化成**实现文档（详细范围清单 + 关键决策页）**。brief 留作轻量入口稿（需求一句话+给谁看+demo 成功标准），不驱动重 analysis | ★ |
| **prd-writing** | **保留（终点交付物）但彻底改时序+口径**：stage 3 前置门 → 第⑥步沉淀（原型确认后反向出）。PRD 恒按真实系统口径写、不从 mock 反推（权限/审批从 brief 锁）；内含"原型覆盖范围"表。standalone 跨模块入口保留 | ★ |
| **task-plan** | 保留 PM 主确认地位，重定位：task = PM 确认方向的阶段单元（非工程 ticket；**名字保留 `task`、不改"demo"——mode=system 时建的是真实功能、task 是 mode 中立词**）。承接第②步——**产出结构化范围清单（页面/字段/按钮/tab/状态/做不做）= 第④步覆盖审计锚点 + 一页关键决策（岔路+拍了什么+为什么，喂第⑥步反向 PRD）**。加字段：执行深度/PM 确认什么/不做什么/并行性 | ★ |
| **task-execute** | **新模型第③步 build 核心载体**：直接在 `prototype/` 用 Claude Code 在栈内建（零录入）；强制 @读 DESIGN.md 后动手；build 后**自动跑三道机器审**——覆盖审计（**独立新鲜视角 agent** 拿清单 vs 代码硬 diff、非自审）+ 视觉门（gstack `/design-review` 只截图不改）+ 行为审（②派生验收流程驱动 `/browse` 走确定性路径）——合成一份给 PM；再走**体验迭代三收口**（AI 主动批量 flag·PM 拍 / 停在 demo 成功标准+闸门 / 磨不动上抛回②）。验收呈交闸门保留（PM 唯一决策点） | ★ |
| **task-status** | 保留主入口；展示主轴从「Stage N/7、推进」改成「我产品现在长什么样」（产品现状摘要 + 主原型状态 + 本次增量）。`status-view.py` + CLAUDE.md M5 播报跟着改产品轴 | ★ |
| **close-req** | **保留并升级为第⑥步「沉淀」载体**。沉淀拆两档：**每 req 必做**（更新 PRODUCT-STATE.md + merge 主原型回 main，保持脊柱最新；PRODUCT-STATE 只在此刻写 = 防腐）；**按需交付**（反向出可评审 PRD：真系统口径、多源合成——结构←原型+清单 / 规则←brief+决策页，可一次覆盖多 req，避免琐碎 req 硬产没人看的 PRD） | ★ |
| **_shared** | 写作规则/askuser/banner 锚点等普适纪律保留；`input-flow.md`「Stage N 输入清单」重写成六步；banner「Stage N/7」改产品/原型轴；doc-strictness 删被砍文档行 | |

### 合并

| 资产 | 并入哪 | ★ |
|---|---|---|
| **task-submit** | 已合进 task-execute 步骤 11/12；留作异常重呈交兜底 | |
| **doc-update** | 对账模式并入 close-req 沉淀原子动作；沉淀模式（已死路径）废 | |

### 保留不动（与流程正交）

`project-solution`（方向层维护，与"上下文脊柱"天然吻合，仅厘清 PROJECT vs PRODUCT-STATE 边界 ★）、`codebase-audit`（brownfield 一次性入口，现状档对齐到 PRODUCT-STATE）、`quick-fix`、`skill-improve`（框架维护 meta）、`cancel-req`、`publish-to-lark`（交付物分发管道）、`pmai-upgrade`（分发基础设施）。

---

## §2 gstack 接入六步

**核心判断：六步里只有第③步「视觉门」是方向稿明确点名强制编排的 gstack（`design-review`）。其余都是"按需手动 / 可选编排 / 当参考"——别给每步硬塞一个 gstack，那会重新堆出正要砍的流程税。**

| 步 | gstack skill | 接法 | 频率 |
|---|---|---|---|
| ① 产品现状（建 DESIGN.md） | **design-consultation** | init-project 里可选编排，出 DESIGN.md 初稿（也可手写） | 项目级一次性 |
| ② 确认范围层·收范围对话 | **office-hours** | PM 手动调，仅需求模糊时（**不强制编排**，否则变流程税）。它帮想清楚，不是范围清单生成器 | 偶发 |
| ② 确认范围层·视觉变体探 | **design-shotgun** | 第②步第三条上坡路：文字岔路掰不清/PM 想用眼睛挑时，出几版便宜静态草图给 PM 挑方向（= Claude Design「只看不导」在范围确认期的承接；**不录入** prototype/，挑定回清单）。AI 临场判断该出才出 | 偶发 |
| ③ build 视觉门 | **design-review** ✅ | **PMAI build skill 内部强制编排**：起 dev server 后跑；**只跑审计+截图（Phase 1-6），不自动跑 Fix Loop（Phase 7-11）**——出口是 PM 一句话 pass/打回（保住 PM 拍板点） | 每 req build 后 |
| ③ build 视觉灵感（可选） | **design-shotgun** | PM 手动调，探索期当"只看不导"参考（= Claude Design 在 gstack 内的等价；**不录入** prototype/） | 探索期偶发 |
| ④ 覆盖审计（存在） | **非 gstack** | 本体 = **独立新鲜视角 agent** 拿清单 vs 代码硬 diff（对标 analysis-reviewer、非自审）。gstack `qa-only` 仅在想补功能证据（health score/截图）时**可选**跑，只报不改 | 每 build（agent）/ 可选（qa-only） |
| ④ 行为审（行为） | **/browse** | ②范围清单派生的**验收流程**驱动 `/browse` 走确定性路径（PM 既有机制，背后本就是 gstack browser）；每 build 自动。区别于 `/qa` 的 AI 探索。**system mode 有真 auth 时先 `setup-browser-cookies` 导 cookie 才能测登录后** | 每 build |
| ⑤ 体验层迭代（外观/手感） | **qa（手动探索）** | 视觉门 findings 喂 AI **主动批量 flag**、PM 勾改；`/qa` 的 AI 乱点找没想到的 bug = PM 有疑问才**手动**跑（非固定编排） | 迭代时 |
| ⑤/build 排查 | **investigate** | AI 自主按需（撞不明 bug），不进固定编排（同"根因优先"） | 按需 |
| ⑥ 沉淀 / 交付 | **make-pdf（可选）** | 沉淀本身 PMAI 自有（close-req + prd-writing）、design-review 截图复用为 PRD 素材；**PRD 要拿去评审 → `make-pdf` 出发布级 PDF**（页码/TOC/水印，和 publish-to-lark 并列两条分发口） | 交付时 |

**不接入**（专指"给 PM 的原型六步"不用，生成器仓自己开发仍可用）：`design-html`（生成 gstack 自家静态 HTML，非 prototype 的 Next.js 栈，录入=跨栈幻觉）、`plan-eng-review`/`plan-ceo-review`/`plan-design-review`（工程深度已后台化，PM 主视图不碰架构评审）、`review`（生产 PR 门）、`ship`/`land-and-deploy`/`canary`/`benchmark`/`setup-deploy`（PMAI 不部署生产）、`connect-chrome`（headless 已够）；**`spec`**（5 阶段→GitHub issue，与 ② 范围确认重叠，已选自有的"三条上坡路→req-plan"，不双轨）、**`context-save`/`context-restore`**（与脊柱+状态机重叠）。（注：`document-generate` 原列此处，2026-05-29 复盘改判 → **standalone 按需 + 必读脊柱**，PM 要做产品介绍文档，见 §7.D。）

**要点**：① Claude Design「只看不导」在 gstack 内等价 = design-shotgun/design-html，**只看灵感、绝不录入**；② design 三件套分工别混：design-consultation=写 DESIGN.md（项目级一次性）/ design-review=视觉门（每 req build 后，强制）/ design-shotgun=多变体灵感（探索期可选）；③ **分工已定**（防重叠）：覆盖审计 = 独立新鲜视角 agent 查"建全没"（非 gstack）/ 视觉门 `design-review` 查"长得对不对"/ 行为审 = 验收流程驱动 `/browse` 查"跑得通不通"（确定性）/ `qa` 的 AI 探索 = 手动找没想到的 bug / `task-verify` = PM 拍板闸门（架在前三道证据之上）；④ 全走 `/browse`（headless），禁 `mcp__claude-in-chrome__*`。⑤ **按需 skill = AI 临场判断、有信号才建议**（不机械弹菜单、不全静默；"何时建议"写成 **pattern 沉淀**=触发信号+建议话术，不写阈值脚本——同"判断不机械化"纪律）。⑥ **`plan-tune`** = 调建议频率的旋钮（每条建议可设永远问/永不问/一次性），AI 提烦了 PM 自调。⑦ **可选按需**：`scrape`（抓真实内容填 mock、让 demo 更真）/ `codex`（build 卡住或要对抗式第二意见）；`ios-design-review`/`ios-qa`/`ios-fix` 仅 **iOS 原型**才用（web 默认用不上）。（gstack v1.52.0.0，53 skill 全扫过；新纳入 = make-pdf + setup-browser-cookies + plan-tune。）

---

## §3 worktree / 分支模型

**关键澄清（解了"单一主原型 vs worktree 各自一份 prototype/"的表面矛盾）**：三层 main/req/task **物理结构基本不动**（隔离+merge+清理是成熟资产，复用不重写）。"单一主原型不留 fork"是 **PRODUCT-STATE 这层产品概念的约束，不是 git 物理约束**——req/task worktree 里那份 prototype/ 是同一条主原型的**"在途未确认快照"**，确认后 merge 回 main 就并回单主线，**从不并存两份已确认主原型**。两者不矛盾。

| 层 | PM 可见 | 用途 | 建 / 收尾 |
|---|---|---|---|
| **main** | ✅ | 唯一【已确认主原型】+ PRODUCT-STATE.md + docs 基线 + closed/ 归档 | 项目 init 建，永不删；只被 req merge 进来 |
| **req worktree** | ✅（逻辑上） | 本 req 在途主原型快照 + req 文档 + 已确认 task 汇集 | new-req PM 二确后建；close-req 沉淀+merge 回 main 后删 |
| **task worktree** | ❌ 后台 | 单 task 的执行/快改/可失败沙盒（自带 dev server 端口） | task-plan 确认后 AI 自动建（**D10：按执行深度——document/light 不 fork、在 req worktree 改；demo-deep+ 或并行才 fork**）；确认后自动 merge→req 并删 |

**与现状差异**：① `prototypes/`（复数）→ 收敛为单一 `prototype/`（单数）并升格一等概念（CLAUDE.md 必读 + PRODUCT-STATE 引用）；② task-confirm 手动开窗口/切 cwd 那套体感税 → 后台化（PM 只看 demo + 三选项）；③ banner/Next Up/status 不再播报 worktree 路径/分支/stage → 反转成产品视图；④ close-req 职责扩成沉淀原子动作。

---

## §4 基础设施（hooks / scripts / templates）

**保留不动**：`check-doc-currency` / `review-skill-guard`（正好保视觉门被完整跑）/ `check-sync-asset-jargon` / `check-open-questions`。
**改造 ★**：`_lib/state.py`（聚合轴转产品/原型）、`status-view.py`（产品视图三件套）、`check-prd-hierarchy.py`（PRD 后移、允许从代码抽的路由锚点）、`check-doc-pm-view.py`（适用面扩到范围清单+PRODUCT-STATE）、`check-req-doc-drift`（真相源集合换成 DESIGN+PRODUCT-STATE，守"不改基准"红线）、`check-docs-toplevel.py`（白名单加 PRODUCT-STATE/prototype）、`check-project-sections.py`（随 §5.4 归宿）、`pre-commit.tmpl`、`CLAUDE.md.tmpl`（入口/六步/M5/必读硬规则全重写）。
**降级后台 ★**：`check-task-scope.py` / `check-status-direct-edit.py`（若 task 砍则连 task-transition 一起砍）/ `check-worktree-residue.py`。
**新增模板 ★**：`PRODUCT-STATE.md.tmpl`（根目录单文件，## 节切分，AI 必读，带"只在沉淀时更新"防腐说明）、**`req-plan.md.tmpl`**（per-req「实现文档」一份两节：范围清单节=结构化表/覆盖审计锚点 + 决策页节=岔路+拍了什么+为什么/decision packet 雏形喂反向 PRD；概念名"实现文档"、文件名走英文 `req-plan.md`）、**主原型脚手架 + 说明**（`prototype/`，**名字保留**；**脚手架按 mode 每层派生**——prototype=mock 管线 / system=真 DB·API·RBAC 管线 / custom=按层混搭；含 DESIGN.md 升级版 + 样板页）。
**新增 agent ★**：`coverage-reviewer`（白纸视角覆盖审计——拿范围清单 vs build 代码 diff、报建了/丢了/降级占位，对标现有 `analysis-reviewer`，非 gstack、不参与 build 防自审盲区）。
**附件机制（保留核心 + rewire）★**：`_lib/attachments.py` 核心（trigger-0 PM 视图识别 + copy/register + `.req-meta.json:attachments_seen` + 📎参考材料引用 + 敏感路径拦截 + 50MB 上限）**正交于 stage 机器、原样保留**。rewire 两处：① `stage_prefix` 映射 + `_stage_doc_exists` 从旧 7-stage 锚点（brief/analysis/impl/task-plan/close/task-NNN）改成新六步锚点（主要落 `req-plan`）；② `attachments-upload.md` caller 清单从 7 个旧 stage skill 改成新主路径（new-req / ②范围确认 / task-plan / prd-writing standalone），砍掉·降后台的 skill（req-stage-gate / req-analysis / implementation-design / task-spec）的禁用例外清理。
**随决策定 ★**：`工程结构约束-{prototype,system}.md`（§5.8 实现程度 mode 承接位置）、`task.md.tmpl`（拆成「PM 范围清单 + AI 后台合同」）、`implementation-design.md.tmpl`（倾向砍独立文档）、`PROJECT/DESIGN/PRODUCT-RULES.md.tmpl`（§5.4 归宿）。

---

## §5 ⭐ PM 必须拍的决策清单（接下来真正要你做的）

| # | 决策 | 选项 | 牵动 |
|---|---|---|---|
| **D1** | **砍 7-stage、坍缩成六步**（整个重构的核心反转） | 认 / 不认 / 部分 | 一切 |
| **D2** | **task 概念**：彻底砍，还是降级为 AI 后台 demo 单元 | 砍 / 降后台 | task.md / check-status / task-transition / check-task-scope 一整串 |
| **D3** | **docs 三件套（PROJECT/DESIGN/PRODUCT-RULES）归宿** | 合并进 PRODUCT-STATE / 保留为被引用明细 | PROJECT/PRODUCT-RULES 模板 + check-project-sections |
| **D4** | **§5.8 实现程度 mode 承接位置** | A 写进 PRODUCT-STATE / B 8 字段表并入某节 / C 项目级+req级拆开 | 工程结构约束模板 + derive/detect 脚本 |
| **D5** | **prototype/ 默认技术栈** | AI 默认推荐（Next.js?） / PM init 时选 | 主原型脚手架 + init-project |
| **D6** | **范围清单落盘** | 独立文件 / 并入 PRD 原型覆盖范围表 / 嵌 PRODUCT-STATE | 新模板形态 + lint 接入 |
| **D7** | **入口命令** | 是否引入 `/pmai-next` 统一驱动六步（接管 stage-gate 被砍后的推进）；最终收敛哪几条 | next/status 入口 + CLAUDE.md |
| **D8** | **worktree 后台化批次** | 阶段 0 只做"PM 视图不显示" / 自动托管（建 merge 删）何时上（VP4 重改动） | task-confirm/close-task 后台化节奏 |
| **D9** | **mock→真系统重写** = 一个 task 还是独立 req | 倾向独立 req（跨多 task、改地基、要重走范围+沉淀） | 不变量 B 措辞 + task 拆分 |
| **D10** | **document/demo-light task 要不要 fork worktree** | 倾向 document 不 fork（在 req worktree 改）、demo-deep+ 才 fork | 省 worktree 开销 vs 一致性 |
| **D11**（已锁，仅记） | **prototype/ 单一性、不留 fork** = 前稿 §0.4 #4 PM binding | 默认严格执行；若 build 真撞到需 A/B 才重拍 | — |

> 建议：**先拍 D1**（认不认这个反转），认了再按 D2-D10 逐条过。D11 已锁，列在这只为提醒它是 binding。
>
> **2026-05-29 讨论已拍定（从待议移出，见方向稿 §2.3.1）**：第②步范围确认 = 一个目的地、三条上坡路（直奔清单 / 收范围对话 / 视觉变体探）——认；视觉探针为可选档（AI 判断该出才出）——同意；关键决策页落盘留底（喂反向 PRD）——要；"实现文档" = 详细范围清单 + 决策页（产品口径、PM 拍板），工程 HOW 降 AI 后台——认。→ 详见下条 D3-D6 拍定。
>
> **2026-05-29 D3-D6 拍定**：**D3** PRODUCT-STATE = 现状层 hub（装当前功能/主原型现状/mock-真状态位/索引），指向 PROJECT/PRODUCT-RULES/DESIGN、**不合并**（动静分离=防腐）；**D4** 实现程度 mode **按层走、三层挂靠**——详细指引留 `工程结构约束-{prototype,system,custom}`（现成）／当前 mock-真状态进 PRODUCT-STATE 状态位／本轮深化决策在②决策页；mode 只管 build 深度，**PRD 恒真系统口径**（不变量 B）；**D5** prototype/ 默认 **Next.js+TS+Tailwind+shadcn**、init 可改（主原型脚手架据此具体）；**D6**「实现文档」= **独立 per-req 文件 `req-plan.md`**（范围清单节 + 决策页节），沉淀后内容分流（现状→PRODUCT-STATE／规则→PRODUCT-RULES／WHAT+WHY→PRD）+ 归档，**不嵌 PRODUCT-STATE、不并入 PRD**。决策页 promote 跨功能规则进 PRODUCT-RULES（接现有 close-task promote）。
>
> **2026-05-29 D2 + D7 拍定**：**D2** task **降 AI 后台**（不砍）——保留为 PM 确认方向的阶段单元、spec/confirm/close 机器全转后台 PM 不感知；**名字保留 `task`**（mode=system 时建真实功能、task 是 mode 中立词），连带定下"**PM 视图标签一律 mode 中立**"。**D7** PM 主循环收敛 **4 条**：`init` / `new-req` / **`next`**（推进六步、接管 stage-gate，先说再动）/ `status`；**按需 PRD = `prd-writing` standalone**（不进主循环、不新造命令）；情景命令（quick-fix/cancel-req/publish-to-lark/codebase-audit/pmai-upgrade）保留、不进主循环。
>
> **2026-05-29 D8 拍定**：worktree 自动托管**不押后**——PM 拍早上、随阶段 0（砍冗余+藏显示）一起做（窗口切换是最烦的体感税，半截 fix 没意义）。代价：阶段 0 不再纯零风险，自动托管动 merge/删/residue + dispatch-clean 事故区，**必须先真实 req spike 验证再固化（这步不能省）**。**澄清**：自动的是 task-confirm/close-task 的 worktree 机器（fork/merge/删/切窗口）；**PM 呈交闸门验收（pass/打回）保留、绝不自动**——丢的是杂活、不是控制权。
>
> **2026-05-29 D9 + D10 拍定**：**D9** mock→真（层级深化）默认**独立 req**（跨多页/改地基、要重走范围确认+沉淀；最好专门 req 别混加功能；真·localized 单点 mock→真 才当 task）。**D10** task fork worktree **按执行深度**：document（纯文档）不 fork、demo-light 默认不 fork、demo-deep+ fork（隔离/dev server/可失败）；**并行多 task 则一律 fork**。与 D8 咬合：轻 task 不 fork = 自动托管要建/删的 worktree 更少、开销更低。

---

## §6 映射到落地阶段（方向稿 §4）

- **阶段 0（先 ship）**：砍 §1「砍/合并」类的纯过程税（req-stage-gate 暂可留壳）；worktree PM 视图隐藏（banner/status/Next Up 改产品轴）；**worktree 自动托管（AI 自动建/merge/删、PM 零窗口切换）随本批早上**（2026-05-29 D8）——但它动 merge/删/residue + dispatch-clean 事故区，**先真实 req spike 验证再固化（不能省）**；入口收敛只定方向。砍冗余/藏显示不依赖待拍决策、可立即动；自动托管走 spike。
- **阶段 1（薄脊柱）**：新增 PRODUCT-STATE.md.tmpl + 范围清单模板 + prototype/ 脚手架；init-project/new-req 改造。**依赖 D3/D4/D5/D6**。
- **阶段 2（build 纪律）**：task-execute 改造成栈内 build + design 约定 + 覆盖审计 + design-review 视觉门。**先用一个真实 req spike 验证 design 约定能否逼近视觉**（方向稿 §C 回退点）。
- **阶段 3（沉淀）**：close-req 升级成沉淀原子动作 + prd-writing 后移。**依赖 D2/D9**。

**纪律**：每个新机制先用一个真实 req spike 验证再固化；第一个 spike 只接 design-review 这一个 gstack 编排点，验 pass/打回闭环顺不顺，再决定要不要把 qa/qa-only/design-consultation 也编排进来。

**plan-eng-review 落点（2026-05-29，PM 拍 2 条 + 工程侧自决项）**：
- **自动托管 spike 验收硬标准（PM 拍）**：除 happy-path（自动建/merge/删），**必须复现并挡住 2026-04-22 worktree 边界折断 / task 代码串台事故**——采纳 TODOS 久 deferred 的「v2 状态物化」（worktree lock / chmod 物理约束让 agent 越不了界）作加固，spike 通过 = 真证明事故不重演。**这把 TODOS「v2 状态物化」从 deferred 拉进阶段0 自动托管批一起落地**。
- **六步坍缩先迁移测试再坍（PM 拍）**：坍 `stages.py` 前先盘点 7-stage 专属测试（test-speed-mode / test-stage-source-helper / stages 相关），哪些删、哪些改成测六步，**保 525 测试网全程不断**（先迁移再坍、不留中间无网期）。符合"测试不能省"一贯原则。
- **工程侧自决（不烦 PM）**：① 覆盖审计的 checks+diff 分清「静态读码 diff（coverage-reviewer agent）」vs「跑起来截图 diff（browse，像 prototype-live-align）」——两者抓不同病，实现时明确各管哪层；② PRODUCT-STATE 漂移是上下文保真的单点失效——缓解不靠额外 hook（违防腐），而是把「更新 PRODUCT-STATE」焊进 close-req 沉淀原子动作、沉淀时绕不过；③ 每 build 跑 browse（视觉门+行为审+覆盖审计）有 dev server + 截图延迟——三道审复用同一次 dev server 起停、别各起各的。

---

## §7 复盘追加的新 scope（2026-05-29，forward-looking、非阶段 0）

> 复盘三问（流程 / worktree / gstack）+ 检查既有 `prototype-live-align` skill 后追加。**这些是后续 scope、不进阶段 0**，先记下防将来各搞各的、又长成税。

**A. 站点爬原型（#2，定位 = B）**：`browse` 把目标站**每页每弹窗**走一遍（截图 + 结构）当**参考** → 在 `prototype/` 栈内**重建近似**。**不是无损拷贝**（跨栈重建必然近似，同"只看不导"/"无损录入幻觉"）。引擎 = gstack `browse`（+ `scrape` 抓数据）。新 PMAI skill / 编排。

**B. 对齐线上（第四条 diff 轴）**：参照物 = **线上真实产品**（并列：覆盖审计 = vs 范围清单 / 视觉门 = vs DESIGN / 行为审 = vs 验收 / **对齐线上 = vs 线上真实产品**）。brownfield 关键——原型先对齐现实、再在上面设计改动（= PM 最初"原型与真实线上产品对齐"诉求）。实现 = **#2 的"对齐模式"**（checks 来自爬线上）+ codebase-audit + PRODUCT-STATE 保鲜一家。**吸收既有 `prototype-live-align` skill**（PM 自跑的雏形、内核对）：拆解吸收、**不整块移植**。

**C. 覆盖审计引擎升级（吸收 alignment-plan JSON）**：范围清单从 markdown → 可编译成**机器可检 checks**（吸收 `prototype-live-align` 的 `<module>.json` schema：页面 / `must_have_text` / `must_check_buttons` 带 disabled 态 / `must_cover_states`）。覆盖审计从"肉眼逐项打勾" → "**精确 diff**"。**统一引擎 `checks-spec + diff`**：checks 从范围清单派生 = 覆盖审计 / 从爬线上派生 = 对齐线上（同一引擎、两个参照物）。checks **不让 PM 手写 JSON** → 三条上坡路 AI 辅助产出。`prototype-live-align` 的约束（禁 native alert/confirm 用包装组件、mock-only、四态覆盖、sticky 横滚）**上迁 DESIGN.md + 工程结构约束**（项目级、不锁死在 skill 里）；它的 Plan + 闸门已 = ② + 呈交闸门（验证纪律对）。

**D. 产物层（deliverables）管理模型**：PM 要做产品介绍 / PPT / 图片等产物——管理靠**一条通道、不枚举能力**：① 任何产物生成（skill 或临场"生成 X"）**第一步 `@读脊柱`**（PRODUCT-STATE → 主原型/DESIGN/PRODUCT-RULES）当 context pack（写进 CLAUDE.md，新 skill 白嫖、临场也照此）；② 落点 `deliverables/`（产品级、住 main）+ `INDEX.md` 登记；③ **skill = 固化的临场**（默认临场生成，反复用 / 要统一格式才固化成 skill，同 `scrape→skillify`）；④ 产物 skill 统一命名（`make-*`）进 INDEX、**别建插件框架**。连带：`document-generate` 从"不接入"改 **standalone 按需 + 必读脊柱**；PPT / 图片（gstack 无现成）走外部工具 / 未来自建 skill——**只要在仓库跑、读脊柱就懂产品**。

---

**End of PMAI 重构 · 实施清单 v1**
