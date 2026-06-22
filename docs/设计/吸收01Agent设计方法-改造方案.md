# 吸收 ExampleAgentProject 设计方法 · 框架瘦身改造方案 (v2)

> **状态**：草稿 / §0 已于 2026-06-21 解锁（开放问题 ①A·完全解锁；§0 降为"待验证诊断"，结论与解法均可被 review 推翻——见 §0 解锁声明 + `docs/设计/工作方法论与工作流-总纲.md`）
> **日期**：2026-06-19
> **作者**：PM + AI
> **背景**：ExampleAgentProject 是 PMAI 的练兵消费仓。它在框架外自由生长三周，用**几个 skill** 就工作得不错。本方案的方向经多轮讨论已**从"往框架里加方法(纯加法)"反转为"把框架瘦身到 ExampleAgentProject 证明能用的量级 + 借鉴它的工作模式 + 补几个真实缺口"**。
> **一句话**：**砍框架的过度设计(仪式)、借 ExampleAgentProject 的工作模式(三件套 / design-card / spec-polish / mock)、补三个真实缺口(跨 req 记忆 / 规格质量 / worktree 隔离)。**

---

## §0 原始痛点（PM + AI 共写）

> **【2026-06-21 解锁声明 · 元前提锁已解除】**
> 本节原标注"后续 review 不可反向修改"。复盘发现：**这把锁是后续一连串浅设计的共同根因**——一旦"框架过度设计"这个判断不可质疑，所有"砍"都自带正当性，对抗思考从制度上被压制。开放问题 ① 已 PM 拍板 **A·完全解锁**：§0 整体降为"**一个待验证的诊断**"，连"框架过度设计"判断本身都可质疑；诊断方向（框架薄在设计方法）大体对，但**具体结论与解法均可被本次及后续 review 推翻**。
> **护栏**：解锁同时立 `skills/_shared/anti-cut-check.md`（对抗三问 + 对称判别尺）为减法决策强制门，挡"矫枉过正"——砍错的捞回、砍对的（7-stage 流水线 / task 状态机 / 逐层转写链）别捞回。
> **已被解锁后对抗三问翻案的结论**：
> - §改:105"决策收家（折叠 `docs/decisions/` 进 PRODUCT-RULES、3 家减 2 家）" = **同构错第 6 处**，已撤（见总纲开放 5·已拍 B：理路单独冻结落点）。
> - §0.4 第 2 条"不重建真相源治理"随之部分失效——理路拆家就是对真相源做的必要重建。
> 详见 `docs/设计/工作方法论与工作流-总纲.md`。

### §0.1 痛点

1. **框架过度设计**。ExampleAgentProject 用几个 skill 就做得不错，反衬框架 28 个 skill + task 状态机 + 多阶段流水线是过度的；PM 觉得入口太多、早期会被流程锁住创造力。
2. **信息模型无家可归**。框架六步从范围确认直接跳 build，中间没有"先把信息模型理清"这一步；对信息密集的卡 / 页(框架自称的强场景)会建错→PM 说"不对"→打补丁返工。
3. **规格文档写得不满意**（PM 列的 4 条，见 §0.2 表）：分不清原型 / 规格、术语不统一、多余的原型 / 设计解释、review 原型时规格信息被悄悄删掉(drift)。
4. **跨 req 没记忆**。一个 req 里拍过的重要决策、定过的概念 / 术语，讨论别的 req 时 AI 不知道，逼 PM 重复说。
5. **脱离框架丢了 worktree 隔离**。ExampleAgentProject 自由建、没开分支 / worktree，一堆活堆在 main 上没提交——框架的隔离恰恰是它该留的内核。

### §0.2 触发场景（ExampleAgentProject 实证）

| # | 场景 | 实证 |
|---|---|---|
| 1 | 信息密集卡(能力匹配卡)信息模型没理清就建→反复重做 | 能力匹配卡多轮"重做/第二轮/第三轮"提交；记忆明示"产品库/能力匹配多轮返工" |
| 2 | 框架"范围确认直跳 build"撑不住→PM 脱离框架手长 design-card | ExampleAgentProject `.claude/skills/design-card/` 框架外自建；框架 RUNTIME 2026-05-29 自述"框架用着不顺、第一版原型不如直接给 AI" |
| 3 | 规格 4 问 | 见 §4：分不清原型/规格、术语不统一、多余原型解释、review 删规格 |
| 4 | 跨 req 无记忆 | ExampleAgentProject 靠 MEMORY 索引每会话加载才记住决策；框架无此续接 |
| 5 | 丢 worktree 隔离 | ExampleAgentProject 11 天工作堆在 main 未提交 |

### §0.3 根因

框架把力气全花在**流程 / 状态 / 安全的仪式**上(task 机器、多阶段、确认环节)，却**薄在设计方法 / 文档手艺**——而后者正是 ExampleAgentProject 趟出来、PM 真正需要的。**改造 = 砍仪式、借方法、补缺口、留隔离内核。**

### §0.4 不解决什么（防 review 拉回）

| # | 不做 | 为什么 |
|---|---|---|
| 1 | 不删框架代码 / 测试 / 不变量 | 瘦身 = **缩小活跃入口**，用不上的 skill 进 dormant、保留可逆，不破坏框架积累 |
| 2 | ~~不重建真相源治理~~【2026-06-21 部分撤销】 | 原因不再成立：开放 5 拍板**理路拆家**=对真相源的必要重建（理路→`docs/decisions/` 冻结、跨模块规则→PRODUCT-RULES、单模块→模块 decisions）。其余真相源仍只对齐措辞、不大改 |
| 3 | 不把信息设计 / 完整规格做成每 req 必跑 | 撞反文档税；深度自适应、PM 在场拍 |
| 4 | 不要重型 driver、不升格 AI 自动 review | 守 I-RV1；PM 手动调 skill |

---

## §1 方案概述

### §1.1 改造后的 PM 流程（TO-BE，已锁）

```
起项目:只建骨架、不锁流程 → 自由探索/试方向(AI 放开手)
   ↓ (方向清晰、PM 准备好)
/design「一句话」                                    ← 不开 worktree
   ↓ 讨论 = 动文档(自动带上历史决策 + 术语,不让你重复说)   ┐
   ↓ /design 本身就是通用 design-card:理清信息模型      ├ 都在 main 上直接动文档
   ↓ → /mockup:据讨论生成多个 mock 方案(借 design-shotgun)给 PM 选 / 确认  │
   ↓ 产出/演进 模块三件套(discussion→decisions→spec)      ┘
   ├─ 小改:直接改,不开 worktree、不走流程
   └─ 大需求 → /build:开分支 + worktree(选工具)→ 建 → 看原型挑错改(review loop)
   ↓
/close:规格定稿(就地升版)、决策/术语回写基线、文档自动归位、有 worktree 则 merge
```

**体感**：入口少(~7)；命令不变多；早期不被流程锁；讨论 + 小改都直接动、零隔离仪式；只有大需求才开 worktree；收尾拿到能评审的真规格。

### §1.2 三条结构决定（已锁）

1. **不分"模块"和"req"两层文档**。唯一组织单位 = **功能模块**(按 ExampleAgentProject 一模块一文件夹三件套)。**req 退化成纯动作**(新开 or 重做一个模块)，不是文档层；req 的内容全落进模块三件套 + 项目基线。
2. **/design = 通用 design-card**(见 §4)。它既能新开模块，也能重做模块。
3. **重做模块 = 就地演进同一文件夹**(版本信息 + 变更日志 + 决策记录 supersede + git)，**不 per-版本开新文件夹**；只有"模块身份本身变了"才另起 + 归档旧的(例外)。

---

## §2 活跃 skill 入口（~7）+ dormant

**瘦身原则**：缩小 PM 面对的活跃入口；用不上的 skill **不删、进 dormant**(保留测试 / 不变量 / 代码，可重新激活)。

### 活跃集

| 类 | skill | 作用 |
|---|---|---|
| 生命周期 | **/init-project**(轻)| 起项目骨架、不锁流程；早期自由探索；方向清晰后"纳入结构"(立第一个模块)。吸收原 brownfield 接入 |
| | **/design** | = **唯一的写规格 skill**(见 §4):判新开/重做模块、加载基线、跑通用 design-card 信息设计、产/演进模块三件套。**只动文档、不开 worktree** |
| | **/mockup** | **据讨论内容(信息模型设计结论)生成 mock 页面**给 PM 提前确认设计(取代规格里画 ASCII)。**借 gstack `/design-shotgun`:一次生成多个方案变体让 PM 选** + 看版留存。**轻量、不开 worktree**，建在框架 `mocks/` + `gen-mock-board.py` 底子上 |
| | **/build**(灵活·仅大需求)| **PM 选工具**(Claude Code / Codex / cursor / 手动，复用 exec-adapter)**+ 选要不要开 worktree** → 建 → review loop |
| | **/close** | 规格反向定稿、决策/术语回写基线、文档自动归位、有 worktree 则 merge 回 main |
| 工具 | **/publish-to-lark** | 文档发飞书(ExampleAgentProject 原用 lark-cli + 重发法，这是其 skill 版)|
| | **/status**(可选)| 现状视图 + 开窗"我在哪 / 最近决策"(不要也行，开窗播报 + 读文档可替)|

### dormant（保留不删、默认不用）

`task-*` 全套(task-plan/spec/confirm/execute/verify/submit/close-task)、`req-stage-gate`、`req-analysis`、`implementation-design`、`deposit`、`doc-update`、`quick-fix`、`spec-polish`(逻辑已并入写规格 skill)、`project-solution`、`codebase-audit`、`align-to-live`、`scrape-prototype`。
**框架自身维护留用**：`/pmai-upgrade`、`/skill-improve`。

> **task 专门说明**：保留在框架、不删，只是暂不用；以后要并行多 task 再激活。

---

## §3 文档体系（借 ExampleAgentProject 整套）

唯一组织单位 = 功能模块。三层文档：

### 项目级（开 /design 时按需加载 = 跨 req 记忆，见 §6）
- **定位 + 业务术语表** `PRODUCT.md`、**现状** `PRODUCT-STATE.md`、**设计基线** `DESIGN.md`、**遗留** `TODO.md`
- **项目级基线** `PRODUCT-RULES.md` —— 跨模块的**规则 + 关键决策 + 奠基理路**(把原 `docs/decisions/` 折叠进来、删那个单独文件夹；**决策的家从 3 个减到 2 个**)
- (索引是 `PRODUCT-STATE` 的一个节、不另起文件；方法论在 `/design` skill 里、不每仓复制)

### 模块级 —— 每模块一文件夹（`docs/modules/<模块>/`，文件名英文）= 那个模块的一切
- `discussion.md`(讨论底稿:收集信息 + 讨论；拍定就上移、不再当真相)
- `decisions.md`(决策记录:**本模块**决策——结论 + 为什么 + 否过什么 + supersede 删除线)
- `spec.md`(规格·唯一真相源；信息模型 + 规则 + 字段口径 + 状态机 + 文案)
- `.req-meta`(**当前工作状态**:在做的分支 / 阶段——req 状态搬进模块文件夹、不另立 `requirements/` 树)
- (按需)数据审计 / 导出 json

> **决策两个家（从 3 减到 2）**：模块决策 → 模块 `decisions.md`；跨模块/全局的规则·决策·理路 → 项目级 `PRODUCT-RULES.md`。
> **框架连带改动(最深的一处)**：`docs/modules/<m>.md`(单文件)→ `docs/modules/<模块>/`(文件夹)；**取消 `requirements/active|closed/` 整棵树**——doc/附件/状态全不在那。连带要瘦 close 机器(`close-req.sh` / `req-transition` / I-CR·I-RT 建在 requirements/ 上)；本方案最深改动,按 lifecycle 迁移单独走、必跑测试(task 已 dormant、req 已弱化,方向一致)。

### mock —— 设计确认 + 探索（**做成 /mockup skill**；借 ExampleAgentProject + gstack `/design-shotgun` + 框架 `mocks/`）
**/mockup skill**:据讨论内容(信息模型设计结论)**生成 mock 页面**，给 PM **提前确认设计**(取代框架在规格里画 ASCII)，确认了再定稿规格 / 进 build。**借 gstack `/design-shotgun`——一次生成多个 mock 方案变体让 PM 选**；看版留存(不挑定的不删、manifest 登记)；原型本身也是"活 mock"，看着改。轻量、不开 worktree。建在框架 `mocks/` + `gen-mock-board.py` 底子上(实施时读 design-shotgun 借其多变体生成法)。

### 附件 / 素材 —— `docs/inputs/<类别>/`，自动归类（借 ExampleAgentProject）
PM 上传的附件 / 素材**按类型自动归位**到 `docs/inputs/<类别>/`(访谈 / 竞品调研 / 会议脑暴 / 产品原文 / 信息模型 / 行业参照…,类别随项目长),AI 上传时判类型归位——**不再按 req 作用域塞 `requirements/<req>/attachments/`**。保留安全预检(敏感路径 denylist + 大小上限),去掉 per-req 作用域 + stage_prefix。

### 自动归档（治 §0.1 痛点"散乱在根目录"）
每份文档有钉死的家，沉淀时 AI **自动归位**到模块文件夹 / 基线，**根目录不留游离文档**。把 ExampleAgentProject 的产出路由做成默认自动，不靠 PM 事后收拾。

---

## §4 写规格 skill（唯一一个）+ 规格 4 问的治法 + 格式结合

**写规格 = 1 个 skill**(spec-polish、prd-writing 都不单独)。它干全套:**理结构(信息设计)→ 写(骨架)→ 磨文字(原 spec-polish 9 条变收口步)→ 冷读自检**；兼容**正向**(设计期，/design 调)/**反向**(build 后定稿，/close 调)/**重做**(就地演进)/**卡片 vs 非卡片**(主干 + 分支)。"理结构 ⊥ 磨文字"边界靠 skill 内部纪律守(磨时别动结构)。

### 通用 design-card：7 步拆成普适主干 + 卡片分支
- **普适主干**(任何 req):①谁看·下游倒逼结构 ②决策与动作边界(三身份:AI 建议/已确认/待确认) ③信息从哪来·派生 4 环(来源→生成→变更→重算) ⑥状态 ⑦文案。
- **卡片/页面特化分支**(信息密集 UI 才加):④一行的原子粒度 ⑤卡面 vs 抽屉。
- **深度自适应**:信息密集走全套；后端规则/流程/小改走主干轻过。**AI 提议深度、PM 拍**(不自动、不变重闸门)。

### 结合后的格式（PRD 格式 ↔ 当前规格格式）
对比后取舍：

| 取自 | 内容 |
|---|---|
| **ExampleAgentProject 10 章骨架为主干** | 摘要/版本信息/变更日志/名词解释/概述/用户与场景/**六信息模型(派生 4 环·框架最缺)**/业务规则/核心动作(按对象灵活)/验收/附件 |
| **框架 writing-rules** | L1-L6 语言指纹 + 8 类禁用清单 + UI 指代 + cross-ref + 抽象动词规则 → **reconcile 进写规格 skill 的写作纪律**(与 spec-polish 9 条逐条对账合并、不两套并存) |

### 通用灵活：骨架是菜单、不是死模板（PM 强调，核心要求）

这个唯一的规格 skill **必须通用、兼容多种情况**——10 章骨架是**可选菜单 + 自适应形式**，不是逐章必填的死模板：

- **§六信息模型:按需出现**——信息密集的功能(卡 / 多对象页)才写；简单功能不需要、省掉。
- **§八功能需求 / 核心动作:形式自适应**——简单功能**一段话散文说清**即可；复杂功能用**功能表格**；纯算法 / 流程用**流程图 + 完整 prompt + 状态机**；按对象灵活(卡片按信息块 / 管理页按 CRUD / Agent 按处理环节)。
- **其余章节同理**:有就写、没有省掉(无术语则 §三从简、无非功能需求写"暂无")。
- **唯一判据 = 把需求讲清楚**；skill 先判这个功能需要哪些章 / 用什么形式，再写——**不硬套全 10 章、不硬塞表格**。
- **保留的是写作纪律**(禁 jargon / 术语统一 / 加粗短句 / 不嵌原型)，**放开的是章节与形式**。

### 规格 4 个问题的治法（这是写规格 skill 的验收标准）

| PM 提的问题 | 根因 | 治法 |
|---|---|---|
| **1. 分不清原型 / 规格，忘了规格要指导实现** | 把规格写成"描述原型现状" | **取 ExampleAgentProject、不取框架**:**框架 §六的 ASCII 原型节去掉**(它既是混淆源、又是多余原型解释)；**设计确认改为提前用 mock 页面**(见 §3)，**规格只留 normative 文字 + 引用那个 mock**，顶部钉"本规格是权威定义、与原型不一致以规格为准、没说清先确认"；每写一条自检"这是定义需求(规格)，还是描述原型(删)?" |
| **2. 术语不统一** | 无强制收口 | §三名词解释 + 框架 **L6 名词锁定**(列全→grep 近义词→替换) + **项目级术语表自动加载**(§6)；收口 grep 残留 |
| **3. 多余的原型 / 设计解释** | 把"为什么"和"原型样子"塞进规格 | **靠三件套分工甩出去**:"为什么"→决策记录、"原型样子"→DESIGN/原型件、规格只留 normative；叠框架禁用清单(禁 UI 实现术语/禁元描述) + spec-polish"只写最终事实、不写实现层 don't" |
| **4. review 原型时规格信息被悄悄删(drift)** | 规格 ↔ 原型 漂移、同步时丢内容 | **一致性扫描**(见下) |

### 一致性扫描（治问题 4 + 接 quick-fix 的价值；做成轻行为，不升格强制门）
借框架现成件(quick-fix 偏差扫描 + `check-state-index-drift.py`)，做成**写规格 skill 自带、任何编辑顺手跑**的轻行为:
1. **触发**:改了原型 或 改了规格。
2. **扫**:把改动(某字段/规则/概念)grep 相关文档(规格 ↔ 原型 ↔ DESIGN ↔ 术语表)。
3. **flag(不静默吞)**:① "规格说 X、原型现在 Y → 哪个对?" ② **"这条规格在原型里找不到对应了 → 有意删(同步删规格) 还是漏实现(补回)?"**(治问题 4 关键) ③ "改了术语 → 近义词要不要统一"。
4. **close 同步那一刻做老规格 vs 新原型对账**:不盲目重写，每条对不上的都 flag"确认删 / 还是漏"、PM 拍——**根除"规格信息被 review 悄悄删掉"**。

实现 = 轻量脚本(仿 `check-state-index-drift.py`)+ skill 收口调；**不升格强制门**(守 I-RV1)。

---

## §5 worktree / 分支 / build 规则（已锁）

- **讨论(任何 req)= 文档 → 无 worktree、无分支**(直接在 main 上动)。
- **小改 = 直接改 → 无 worktree、无分支**。
- **只有大需求 → 开分支 + worktree 来 build**，完了 merge 回 main；**worktree 统一挂 `.worktrees/<分支>/`**(repo 根下单一挂载目录,框架和 ExampleAgentProject 本就这样)。
- **main 写保护放宽**(允许直接改文档 / 小代码；这是"小改直接改、quick-fix 进 dormant"的前提)。
- **/build 灵活**:PM 选工具(exec-adapter) + 选要不要 worktree。
- quick-fix 的"一致性扫一下"价值 → 变成任何编辑自带的轻行为(见 §4)，不靠 quick-fix skill。

---

## §6 跨 req 记忆（A：决策 + 术语，不让 PM 重复说）—— 已核实两边实情

**实情**：框架消费仓续接全在**仓内 doc + 开窗播报**(PRODUCT-STATE / PRODUCT-RULES / 模块 `decisions.md` / PRODUCT.md 业务术语表 / TODO)；**`/design` 开场(原 new-req 步骤 3.0)已 @读 PRODUCT-STATE + PRODUCT-RULES + 扫相关决策**——**读侧基本齐了**。ExampleAgentProject 用的是 Claude Code 原生记忆(`~/.claude/projects/.../memory/`)，**机器本地、不在仓、不随仓走**——**不照搬**(跟框架可移植 / --local / 多 host 冲突；不建 MEMORY 子系统)。

**方案 = 在框架已有基础上补两处回写，不建子系统(决策按 §3 的 2 个家走)：**

| | 读侧 | 写侧(要补) |
|---|---|---|
| **决策** | 已有:/design 开场读 PRODUCT-RULES + 相关模块 `decisions.md` | **补**:/close 沉淀加一问"本 req 拍的决策里有没有后续 req 该知道的?属于某模块→进模块 `decisions.md`;跨模块/全局→进 `PRODUCT-RULES`"(现框架沉淀只收"整体意图"、单条决策会漏在 closed req 里) |
| **术语** | **补**:/design 开场读清单加上 `PRODUCT.md` 业务术语表(设计讨论用既有词) | **补**:/close 沉淀加"本 req 新定义的概念/术语→回写 `PRODUCT.md` 业务术语表"(现框架沉淀不收术语) |

- **规模兜底**:PRODUCT-RULES / 术语表攒长了再加"一行索引 + 按需读"——借 ExampleAgentProject MEMORY.md 的**索引形态**、不借它**机器本地机制**，先不急。
- **一句话**:读侧已齐，真缺的是**两处回写**(决策页里的重要决策、req 里新造的术语)没沉进 `/design` 会读到的家。补这两处 = 解决"别让我重复说"。

---

## §7 全程红线

1. 嫁接的方法论文本**落 `_shared/`，不内嵌进单个 SKILL**(防漂移)。
2. PM 话术**翻译掉** 7 步法 / 4 环 / 三身份等内部术语。
3. **不新增 PRODUCT-STATE / 基线写口**(只 close-req + 沉淀那刻写)。
4. **不引入 `.engineering.md` 类双文件**。
5. **不升格 AI 自动 review**(冷读 / 一致性扫描都是 silent 自检或并入已有审，不做强制门)。
6. **瘦身 = 缩小活跃集，不删代码**(dormant 可逆)。

---

## §8 风险与待验

- **R1 通用 design-card 深度自适应**：AI 提议深度准不准、会不会该走全套时轻过了。待验：拿 ExampleAgentProject 真实 req 反跑。
- **R2 writing-rules ↔ spec-polish reconcile**：逐条对账合并、不两套并存，工作量偏大、易遗漏。
- **R3 main 写保护放宽**：放开直接写换来自由，但丢一道防误写——单人 PM 可接受，需确认。
- **R4 dormant 的边界**：哪些真 dormant、哪些还被活跃 skill 间接依赖(如 exec-adapter 被 /build 用)，落地前要核依赖、别 dormant 错。
- **R5 就地演进 vs 另起的判据**："还是同一个东西吗"靠人判，边界模糊时要 PM 拍。

---

## §X Review Findings

（待 review）

---

## §Y 决议日志（PM 与 AI 共审）

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-06-19 | **方向反转**:从"往框架加(纯加法/8+8+8 缺口地图/三批)"→"**瘦身 + 借鉴 ExampleAgentProject + 补真实缺口**" | 全文 |
| 2026-06-19 | scope = 3 件 + 给框架瘦身 | §1/§2 |
| 2026-06-19 | ~~设计拍 AI 自动判触发~~ / ~~设计拍做成单独 skill~~ → **/design 本身 = 通用 design-card**(PM 手动调、深度自适应) | §1/§4 |
| 2026-06-19 | 信息模型设计结论**写进规格文件**(模块三件套)，不另起文件 | §3/§4 |
| 2026-06-19 | ~~deposit 第⑤类"经验→记忆"~~ → 砍；真需求是**跨 req 决策 + 术语统一记忆**(回写基线 + 开 req 自动加载) | §6 |
| 2026-06-19 | **不分模块和 req**:唯一单位 = 功能模块；req = 动作(新开/重做) | §1.2/§3 |
| 2026-06-19 | 重做模块 = **就地演进同一文件夹**(版本+变更日志+supersede+git)，非 per-版本新文件夹；身份变了才另起(例外) | §1.2 |
| 2026-06-19 | **借 ExampleAgentProject 整套**:三件套 + design-card + spec-polish + mock(都是轻的好东西，不砍) | §3/§4 |
| 2026-06-19 | worktree 规则:讨论=文档无 worktree、小改直接改、只大需求开 worktree；**main 写保护放宽** | §5 |
| 2026-06-19 | /build 灵活:PM 选工具 + 选要不要 worktree | §2/§5 |
| 2026-06-19 | **task 保留不删、默认不用(dormant)** | §2 |
| 2026-06-19 | **写规格 = 1 个 skill**:design-card 写规格 + prd-writing + spec-polish 合一 = /design 核心 + /close 复用 | §4 |
| 2026-06-19 | quick-fix / doc-update / spec-polish 等进 dormant(不删)；瘦身 = 缩小活跃集 | §2 |
| 2026-06-19 | 规格 4 问(分不清原型规格 / 术语不统一 / 多余原型解释 / review 删规格)= 写规格 skill 验收标准；治法见 §4 | §0/§4 |
| 2026-06-19 | 格式结合 = ExampleAgentProject 10 章骨架(尤其 §六信息模型)+ 框架 writing-rules reconcile + 不嵌原型 + 为什么进决策记录 + 一致性扫描 | §4 |
| 2026-06-19 | 框架 §六 ASCII 原型节去掉，设计确认改为**提前用 mock 页面**;规格只留 normative + 引用 mock | §1.1/§3/§4 |
| 2026-06-19 | **写规格 skill 必须通用灵活**:骨架是菜单不是死模板——信息模型按需出现、功能需求散文或表格自适应、唯一判据=讲清楚;保留写作纪律、放开章节与形式 | §4 |
| 2026-06-19 | **生成 mock 做成独立 skill /mockup**:据讨论生成 mock 页面给 PM 提前确认设计;**借 gstack design-shotgun 一次生成多变体让 PM 选**;轻量不开 worktree、建在 mocks/ 底子上(区别于 /build 真实现) | §1.1/§2/§3 |
| 2026-06-19 | **记忆方案核实定稿**:框架读侧已齐(/design 开场已读 PRODUCT-RULES + 相关模块 decisions.md)，**不照搬 ExampleAgentProject 机器本地的 Claude Code 记忆**(不建子系统);只补两处回写——决策→模块 decisions.md / PRODUCT-RULES、新术语→PRODUCT.md 业务术语表;/design 开场读清单补术语表 | §6 |
| 2026-06-19 | **/new-req 改名 `/design`** | §1/§2/§4 |
| 2026-06-19 | **close-req 改名 `/close`**(去 -req、与 /design 一致；脚本/不变量名不动) | §1/§2 |
| 2026-06-19 | **命名统一英文**:模块三件套 → `discussion.md` / `decisions.md` / `spec.md`(文件名英文、prose 仍中文) | §3 |
| 2026-06-19 | **决策的家 3→2**:删 `docs/decisions/` 折进 `PRODUCT-RULES`(项目级:跨模块规则+决策+理路);模块决策在模块 `decisions.md` | §3/§6 |
| 2026-06-19 | §3 删掉照搬 ExampleAgentProject 的 `_方法论/` + `索引.md`(方法论在 skill、索引是 PRODUCT-STATE 一节) | §3 |
| 2026-06-19 | **文档全进 `docs/` 一棵树、取消 `requirements/` 树**:模块三件套 + `.req-meta`(工作状态)进 `docs/modules/<模块>/`;附件按类型自动归类进 `docs/inputs/<类别>/`(借 ExampleAgentProject);worktree 统一挂 `.worktrees/<分支>/`。连带:close/lifecycle 机器要瘦(单独迁移、跑测试) | §3/§5 |
| 2026-06-19 | A 类小决策按推荐定:PRODUCT-RULES 保留名(范围写清)、/status 保留、PRODUCT-RULES 由冻结转活(supersede 留痕)、req 仅作内部基础设施词(用户面只 /design /close) | §1/§2/§6 |

---

**End of 吸收 ExampleAgentProject 设计方法 · 框架瘦身改造方案 v2**
