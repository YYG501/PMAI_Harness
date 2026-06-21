# build 段直建轻车道 + 对抗验证网 (v1)

> **状态**：草稿 v1 / **§0 已锁（2026-06-01）** / 待 review
> **日期**：2026-06-01
> **作者**：PM + AI
> **v0→v1**：§0 痛点按"读 GSD 真源码 + 向直建 AI 核对"后的实证重写——从"退回 GSD 精简层"（前提已证伪）改成"结构放错地方 = 用了 GSD 反模式的逐层转写链 + 缺了 GSD 的对抗验证网"。

---

## §0 原始痛点（PM + AI 共写，后续 review **不可反向修改**）

> ⚠️ 任何后续 review / autoplan 都不能给本节加东西、不能重定义痛点。

### §0.1 痛点（1-3 句）

从「范围确认完」到「PM 看到能反应的结果」，build 段垫了多个 AI 转写 pass（req-plan→task-plan→task-spec→execute），同一份 WHAT 被逐层重述。两个独立的痛：(1) **慢/贵/反馈慢**——单块 req 也必经 4 个串行 pass；(2) **会偏离 + 底料漏**——结构化底料（字段 schema / source / confidence / 就绪度关口映射）每过一跳就可能被磨损或静默丢，且没有一道「逐项钉」的机器关口兜底，**管线和直建都会漏**。PM 已用脚投票：绕过整套 task 流程直接建。

### §0.2 触发场景（实证）

| # | 场景 | 实证 |
|---|---|---|
| 1 | 正式管线跑到 task-001 合同就空转，PM 掉头直建 prototype/ | 消费仓 `ExampleAgentProject` req-001（`requirements/active/.../task-001-*.md` 存在但未驱动 build；真 build 在 `prototype/`）|
| 2 | **结构化字段静默漏**：`RequirementSlot.source+confidence` 在源/req-plan/task 验收清单**三处**都白纸黑字，直建定 `data.ts` 接口时漏掉 | workflow `wf_461ad10d` B路 S1 + **直建 AI 自认"漏了"**（2026-06-01 核对）|
| 3 | build 段夹 **4 个串行 AI pass**、同一 WHAT 转写 **3 遍** | workflow `wf_ee98a18b` C路 + `skills/next/SKILL.md` build 段 + `skills/task-spec/SKILL.md:265-300` |
| 4 | GSD 源码把"逐层再生成 per-task spec"当反模式，明文「**Plans Are Prompts** / implement without interpretation」；且配**强对抗 verifier** | workflow `wf_85033273`（读 `<LOCAL_HOME>/Desktop/Projects/gsd-ref` 真源码：`agents/gsd-planner.md:23,134`、`agents/gsd-verifier.md:21,26`）|

> 反证据归档：PMAI 自己的 GSD 调研档（`docs/归档/完成/GSD-参考调研.md`）**5 条核心说法 3 条假**（GSD≠3层；worktree/确认门非 PMAI 独有），**不可作为论据**；一切以 GSD 源码为准。

### §0.3 根因

**不是"PMAI 比 GSD 层多"，是"结构放错了地方"**：PMAI 用了 GSD 当反模式的**逐层转写链**（req-plan→task-plan→task-spec，同一意图转写 3 遍），又**缺了** GSD 真正的**对抗验证网**（验代码不验自述 / 字段级核 / 连线核 / 跨 req 集成审）。GSD 敢"单次转写→直接 execute"，正因为网强；PMAI 想砍转写却没那张网 → 必然复刻 source/confidence 那种静默漏。

### §0.4 不解决什么

| # | 不在范围 | 理由 |
|---|---|---|
| 1 | 删「拆 task」能力 | 多块大 req 拆 task 是真资产（早期方向采样，`wf_ee98a18b` D路）。本设计改 **opt-in**，不删 |
| 2 | "源 N 个 / 代码 M 个"表面数量差当漂移 | **已证假阳性**（owner 三类是 Q4 有据决策）；owner **不进** §0 实证 |
| 3 | 即时落档 / 从对话自动提取决策 | 另一话题；本设计不碰 |
| 4 | quick-fix 的 req 外旁路 | 不同层，不碰 |

---

## §1 方案概述

```
讨论清楚 → 主 AI 出一份【自包含实现方案】（进 req 前定稿；契约/底料当数据内嵌 + mock 视觉目标）
   → 进 req（req worktree = 并行隔离单元，保留）
        ├─ 单块 req（默认）→ 直建轻车道：执行者可选(main AI / codex·cursor·gemini / manual)直接照方案建，不拆 task
        └─ 多块大 req（opt-in）→ 拆 task（薄 task = 方案的执行 step）
   → 建完过【对抗验证网】（验代码不验自述 + 字段级核 + 连线核；跨 req 集成审在 close-req）
   → 沉淀（反馈 promote 挪到 req 级）
```

**两条铁律**：
1. **方案 = 契约，不是脚本**：pin 决策/底料（本就不该即兴），HOW 全放开；AI 仍可 flag 错契约（保留它改"工位"那种判断力）。
2. **砍转写必须同时建网**：只砍不建 = source/confidence 事故复刻。

---

## §2 与现有机制的关系（含关键现状事实，引 file:line）

### 现状事实（落地摩擦比预想小 —— workflow `wf_2bdd0fea` 摸排）
- **stage 机已允许直建**：4 阶段（`_lib/stages.py:24-29`），**stage 2→3（build→复审）无任何文件前置门**（`req-transition.py:165-175`，闸门靠 PM 验收）。单块不建 task 文件也能推进。
- **task.md 早是单文件**（typed-v3，`task.md.tmpl:3`）——"双文件"是 reshape 前历史，**已砍**。要砍的是 **task-spec 这个 per-task 转写 pass + task-confirm + per-task worktree**，不是双文件。
- **执行者可选已落地**：`exec-adapters/{codex,cursor-agent,gemini,manual}.sh` + task 卡 executor 字段（`task.md.tmpl:54`），只是 **per-task 锚**。
- **req worktree 已是并行单元**：`create-req-worktree.sh` 从 main 独立建分支；adapter 对"task 还是 req worktree"无感知（`codex.sh:23`），换路径即可在 req worktree 跑。
- **coverage-reviewer 已具 GSD verifier 三要素里两个**：白纸反自审（`coverage-reviewer.md:12-14`）+ 三态骨架（`:39-43`）+ 双引纪律（`:111`）；差"深度（字段级/连线）"和"锚点"。

### 保留 / 改 / 砍 / 建

| 动作 | 对象 | 锚点 |
|---|---|---|
| **保留** | req worktree（并行单元）、覆盖审计锚 req-plan、视觉门锚 DESIGN、close-req 现状沉淀 | — |
| **改** | req-plan + impl-design → 一份自包含实现方案；自测说明/文件范围从 task-spec 重锚到实现方案；拆 task 改 opt-in；exec-adapter dispatch 从 per-task 重锚 req-build | 见 §3-B/D |
| **砍** | **task-spec + task-plan（两跳转写都砍）**、task-confirm（per-task worktree 仪式）、单块强制拆 task | 见 §3-A/D |
| **建（PMAI 现缺）** | 对抗验证网：字段级核 + 连线(Wired)核 + 跨 req 集成审 | 见 §3-C |

---

## §3 实施清单（4 条工作流，待 §0 锁后细化 vp 估时）

### A. 叉口 + task-plan 退役（拆/不拆决策挪进实现方案）
- **task-plan 作为独立 skill/artifact 退役**——它本身就是第二跳转写（把 req-plan 范围再列一遍成 task 列表）。砍它 + 砍 task-spec = 只剩一份实现方案、单次转写（GSD 形态）。顺手清掉 `task-plan/SKILL.md:320` 那个"stage 6"旧漂移。
- 「拆/不拆」决策门**前移到写实现方案时**（new-req/范围确认收口处）一道 PM 决策门，复用现「AI 倾向 + PM 拍板」模板。结构决策 PM 拍（[[feedback_structure_decisions_need_pm]]）。
- `.req-meta.json` 加 `build_lane: split|direct`；`next/SKILL.md:75-85` build 段按它分流。
- **保住 task-plan 的拆分判断力**：5 条拆分反模式 + 「task 数 >7 显式给理由」（[[feedback_task_split_antipatterns]]）搬进实现方案「执行计划」节，仅多块时当护栏，别弄丢。
- req stage transition **不用改**（stage 2→3 无文件门）。

### B. 自包含实现方案（req-plan 升级 = 设计+实现合一的唯一 per-req 文档）
- **一份文档，不分两份**：per-req **不再分「设计方案」「实现方案」**——同一份里上半是设计（范围 / 决策 / 契约 / 视觉目标），下半是实现（工程 HOW / 执行计划）。分两份 = 又一跳转写。**项目级设计理路**（护城河 / 交互理路）另有家：决策记录冻结档 + DESIGN.md，不挤进 per-req。
- req-plan 现两节（范围清单 WHAT + 关键决策 WHY，`req-plan.md.tmpl:11-38`）新增四节：**契约/字段 schema**（新，"底料当数据"落点）、**工程 HOW/文件·模式**（蓝本 = DEPRECATED 的 `implementation-design.md.tmpl:26-90` 字段结构）、**mock 视觉目标**（新，三处都没有；挂 `attachments/` 上传图）、**执行计划**（承接退役的 task-plan：单块直建 / 或拆这几块+顺序·并行+反模式自检+验收映射，仅多块写）。
- **硬约束**：req-plan 受 `check-doc-pm-view.py` 管（禁工程词）→ 合并后须像 task.md 那样切 **PM 视图区 / 工程区 region + scoped lint**（`task-spec/SKILL.md:30-46` 现成模式），否则契约表全被判违规。
- 自测说明派生源 `task-spec/SKILL.md:194` + 文件范围 `:218` 改指实现方案。

### C. 对抗验证网（建网）
- **扩 coverage-reviewer**（不另起重叠 agent）：重锚到实现方案契约段（`coverage-reviewer.md:18-25`）；三态加第四态 **Wired（建了但没接数据源/没被调用）**；契约声明字段（source/confidence/key_link）从"不查值/连线"禁区**部分放出**（`:28-43`）。
- **扩 schema**：`build-audits.py:15` 的 `coverage.json` 从 `{name,status,note}` 扩字段级（`fields:[{name,expected_source,actual_source,wired}]`），连带 `:128-136` + `:218-224`。
- **新增跨 req 集成审**：新 agent `integration-reviewer`（仿 `analysis-reviewer.md` 结构），挂 `close-req` Phase 1 合回前——无现成件，必须新建。

### D. 重锚 per-task 机制到 req-build 层 + blast radius（**真正工作量在这**）
- **A 路（PM 已选）= 复用「轻量信封」当网载体**。信封 = **build 运行时记录 + 网锚**，定死如下：
  - **是什么**：~60 行壳，只装网锚节（状态 / 文件范围 allowlist / 自测说明 / 文档偏差 / 自审 / 反馈）+ 一行指向实现方案；**删掉转写节**（实现规格 / 工程 HOW 回实现方案）。accept 闸门、越界保护、行为审锚点随它白捡、不重建。
  - **存哪 + 为什么独立文件**：`requirements/active/<req>/tasks/<...>.md`，在 **req worktree**（非 per-task fork）。**独立文件、不折进实现方案**——它是运行时记录（build 入口出生、建造全程被状态机改写），实现方案是钉死契约（不可被运行时改写），职能/生命周期不同（同 GSD 的 PLAN.md vs SUMMARY/VERIFICATION 分法）。
  - **单块也留 1 个**：它就是「这个 req 的 build 记录」，1:1，PM 无感。省掉它 = 把 accept 闸门重建到 req 层（req-events）= B 路代价；A 路就是用这一个文件白捡闸门。
  - **多块 = 列一次到位、建按序增量**：信封从实现方案「执行计划」派生，可 build 入口一次性全建（状态都 = 待执行）；但**建**按序——建块 1 → demo → PM 确认方向 → 建块 2（早期方向采样 = 多块的价值，全一次性建完就丢了）。
  - **并行才隔离**：执行计划标「并行」的块同时建、各自 per-chunk worktree（**仅此一处 worktree 回来**，= GSD wave 模型）；单块 / 串行多块共用 req worktree。即"砍 per-task worktree"准确说 = 单块 / 串行不用，**并行多块按需各自隔离**。
- exec-adapter dispatch 重锚：`executor-dispatch.md:52-162`（`TASK_WORKTREE`→`REQ_WORKTREE`）、`resolve-executor.py` / `build-execution-prompt.py` 入参从 task-file→实现方案。
- `_gate.sh`（三 adapter 共用）：`adapter_precheck` task 状态→req stage；`adapter_postcheck` allowlist 从 task scope→实现方案/req 范围（或收口到对抗网）。
- `create-req-worktree.sh` **吸收** task worktree 的 symlink/端口/lock 三样（`_setup-deps.sh:28,76` + `create-task-worktree.sh:119`）。
- 反馈 promote 挪 close-req：§1.6（PRODUCT-RULES）并进 close-req 步骤 2（已在写 RULES）；§1.5（DESIGN）在 close-req 新开一步；**前置**：建一个 **req 级反馈承接处**替代 per-task「历史档案→PM 反馈」段。

---

## §4 砍掉的机制清单（防 review 加回）
- 不删拆 task（改 opt-in）。
- 不为快砍覆盖审计（反而要扩成对抗网）。
- 单块 req 下不跑 task-plan task 列表 / task-spec / task-confirm。
- owner 类表面差异不当漂移处理。

---

## §5 风险与待验

| # | 风险 / 待验 | 处理 |
|---|---|---|
| R1（已决）| 直建 lane 怎么落 | **PM 选 A 路**（2026-06-01）：复用轻量信封当网载体，砍转写不砍网。理由 = 信封 ≈ 网的现成载体（accept 闸门 / allowlist / 行为审锚点）；B 路要在 req 层重建这张网、易建弱、blast radius 更大 |
| R2 | 覆盖审计能否真逮 source/confidence | 取决于实现方案契约到字段级 + coverage 逐字段 diff（vp-C）。拿 ExampleAgentProject source/confidence 当回归用例 |
| R3 | req-plan 合并后 lint 误杀契约 | 切 region + scoped lint（§3-B 硬约束）|
| **R4（blast radius 中心）** | 套 [[feedback_stage_refactor_review_blast_radius]]：真改在底层不在 prose | 必须逐条动：**`INVARIANTS.md` 五组（I-AD/I-DC/I-CT/I-CB/I-TT）大半绑 per-task，要重写/废弃**；`task-transition.py` 状态机；`check-branch.sh` CB4/5/10 hook；`close-task.sh` merge-back 仪式；`_gate.sh`/`check-task-scope.py`/`audit-task-events.py` 三件 per-task 验证；`init-project.sh:168-173` task.md case；**task-plan 退役**（skill + `task-plan.md.tmpl` + `test-task-plan.sh` 改/删）；**run-all.sh 里 ~18 个 per-task 测试**（test-task-spec/plan/executors/close-task/check-branch/e2e 等）|
| R5 | 绿网失真 | 改完确认测试**真在 `run-all.sh:7-79`**；**勿被 `.worktrees/codex-orchestrator-plan/` 旧副本误导** |
| R6 | 并行多 req 落地代价 | merge + 沉淀走串行/单写口（防腐铁律已护 PRODUCT-STATE）；借 GSD「executor 不写共享态、orchestrator merge 时写」|

---

## §6 实证支撑
- workflow `wf_ee98a18b`（管线诊断）、`wf_461ad10d`（合同 vs 实建）、`wf_85033273`（GSD 真源码）、`wf_2bdd0fea`（落地接线摸排，本文件 file:line 来源）。
- 直建 AI 核对回答（2026-06-01）；消费仓 `ExampleAgentProject` 真文件；GSD `gsd-ref` 真源码。

---

## §X Review Findings（Round 1 — 2026-06-01 · 4 维度 workflow review `wf_ee68bf36`，强读现有代码 + 对抗验证）

> 全 EVIDENCE/verdict 见 workflow `wf_ee68bf36` 输出。下表为确认项（过对抗验证、severity 已校准）。**4 条 High = 设计未就绪、动代码前必填的硬洞**；6 条「设计已覆盖」+ 2 条否决不录。

| # | Sev | Finding | 决议 |
|---|---|---|---|
| F-B1 | High | 落地顺序没拍死 → 三份显式排序 ①build ②文档治理 ③决策记录(随出口②带出)，别并行开工 | ACCEPT — 头部加落地序（不动已锁 §0）|
| F-B2 | **High** | 信封「一次性全建/状态待执行」与 I-CT7/CT8 事件流审计冲突：audit_ct8 按 `task分支..req分支` diff，单块直建无 task 分支→无法 diff；A 路「accept 闸门白捡」前提(独立 task 分支+per-task 事件)被 §3-D 自己拆掉 | ACCEPT — §3-D 必须裁定信封走不走 task 状态机；这决定 A 路到底是白捡还是大改 |
| F-B3 | **High** | close-task.sh merge-back 整条硬依赖 per-task worktree+分支；单块直建无 task 分支 → `close-task.sh:105-108` 直接 exit 1 崩（"协调式替换半落地破坏现流程"实锤）| ACCEPT — 加「直建无 merge-back」分支 或 adjustment-promote 挪 close-req |
| F-B4 | **High** | 底料字段级契约「进脊柱」无归宿：PRODUCT-STATE 实现深度表只到层级、装不下字段 schema；契约随 req 归档进不主动翻的 closed/ → 下个 req 仍复刻 source/confidence 漏（架空招牌承诺）| ACCEPT — 定字段级契约的脊柱家(PRODUCT-STATE 加节/索引 docs/modules) 或 §0.4 显式声明「契约只在途有效」|
| F-B5 | Med | 越权写防线 GATE5/adapter_precheck 锚 task「执行中」，直建 lane 不触发；§3-D「越界白捡」与威胁模型矛盾（注：GATE5 今天对 req worktree 本已 no-op，非新洞）| ACCEPT — §3-D 显式回答谁挡越权，或承认单块不需要+给理由 |
| F-B6 | Med | integration-reviewer(跨 req 集成审)= 镀金、离 §0 实证痛最远、单块直建无 wave | ACCEPT-DEFER — 字段级+Wired 先做绑 spike；集成审 DEFER 到真出现并行多块 req |
| F-B7 | Med | 在飞 req 迁移未定义：build_lane 缺失 fallback 未定 + 三态兼容不认 lane 切换（注：ExampleAgentProject req-001 实已 closed，补丁=一行）| ACCEPT — 加 R7：存量 req build_lane 缺失默认 split |
| F-B8 | Med | create-req-worktree 吸收端口：derive_task_port 按 task-NNN 算，req 级无 task 号 + 并行 chunk 不能撞 | ACCEPT — §3-D 补 req/chunk 端口算法 |
| F-B9 | Med | req-plan 升级六节 vs `req-plan.md.tmpl:6`「不装工程」冲突；scoped lint 只认 task_format 触发 → req-plan 复用要扩 lint 触发 + 头部 prose 要重写 | ACCEPT — §3-B/R3 落到 lint 触发条件 + 改 tmpl 头部 prose |
| F-B10 | Med | 反馈承接：task-spec 前序反馈 relevance 二分(same-req lane)依赖 per-task 段、直建断裂；chunk 间反馈(块1→块2 build 进行时)不能等 close-req 聚合 | ACCEPT — §3-D 拆 close 级一次性 promote vs chunk 间实时承接 |
| F-B11 | Med | 契约/schema/HOW 塞 req-plan → PM 认知负担升；丢了 `tmpl:6`「契约不用逐行确认」承诺 | ACCEPT — 写明契约 PM 不逐行确认 + PM 视图区在前 |
| F-B12 | Med | 「信封」撞名：`build-execution-prompt.py` 已用「执行信封」= 另一概念；纯内部资产禁进 PM chat | ACCEPT — 换名(build 记录/req 工作单)，命名属结构决策待 PM 拍 |
| F-B13 | Low | §3-A 拆/不拆门「一道 PM 决策门」没显式挂「仅多块」→ 照字面落地每 req 上税 | ACCEPT — :85 改「AI 倾向 direct + 单块自动跳过、仅多块 PM 拍」|
| F-B14 | Low | 「mock 视觉目标」可能让 PM 以为范围确认期要拍死视觉 | ACCEPT — 标明=可选方向锚，非必拍死规格 |

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-06-01 | PM 选「直建 + 覆盖审计逐项钉」方向 | 不回管线 |
| 2026-06-01 | owner 假阳性撤出 §0 实证 | 实证用 source/confidence |
| 2026-06-01 | 读 GSD 真源码 → §0 v0→v1 重写 | 叙事改"结构放错地方 + 缺对抗网"；GSD 调研档标"勿引" |
| 2026-06-01 | **R1 选 A 路**：直建复用轻量信封当网载体（非 B 路另起入口）| §3-D 锚定最小改动面，accept 闸门白捡 |
| 2026-06-01 | **task-plan 退役**：拆/不拆决策挪进实现方案，拆分逻辑变「执行计划」节（仅多块写）| 少 1 skill + 1 artifact + 1 跳转写；反模式自检不丢 |
| 2026-06-01 | **信封设计定死**：独立文件(运行时记录,非折进方案,build 入口出生) / 单块也留 1 个 / 多块"列"一次到位·"建"按序增量 / 仅并行块各自隔离(per-chunk worktree) | §3-D |
| 2026-06-01 | **per-req 一份文档（甲）**：设计+实现合一，不分「设计方案/实现方案」两份；项目级设计理路另有家（决策记录/DESIGN）| §3-B |
| 2026-06-01 | **§0 锁定** | review 不可再改 §0 |

---

**End of build 段直建轻车道 + 对抗验证网 v1**
