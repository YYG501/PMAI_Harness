# CHANGELOG

PM-AI-Workflow 生成器仓的演进记录。本文件**只记影响下游业务仓的改动**——
`scripts/` / `skills/` / `templates/` / `agents/` / `hooks/` 等同步到业务仓的内容；
不记 `tests/` / `docs/归档/` / `RUNTIME.md` / `TODOS.md` / `INVARIANTS.md`
等仅生成器仓内部用的文件。

> **入口**：业务仓续 active req 或起新 req 前，先看顶部"已发布版本"段确认是否需要
> 跑同步流程（`框架同步-SOP.md`）。
>
> **写作约定**：
> - 时间倒序；最新在顶部
> - 每条形如 `<commit-short-sha> <type>(<scope>): <一句摘要>`
> - 重大改动追加详细说明（影响范围 / 迁移指引）
> - 仅记影响业务仓的改动；纯生成器内部改动可省略

---

## 已发布版本

### 2026-05-09 — I-DC1 文档落盘 gate（task-005 文案偏差事故根因修复）

**事故**：ExampleConsumerApp task-005 三个状态变更弹窗 + 导入弹窗的实施文案与 PM 视图终态偏差。根因是 task-spec 跑了 4 轮 revise + 1 次 reconcile，全部停在 req 分支 working tree 没 commit；task-confirm 通过 `git worktree add -b ... <REQ_BRANCH>` fork 时取的是 req 分支 HEAD commit（first-gen v1），把 PM 改了 4 次的版本完全跳过，executor 按 v1 实施。

**修复**：把 I-AD5「dispatch 前 task worktree 必须 clean」推广到文档级 dispatch 边界，立 I-DC1 三道防线。

- 新增 `scripts/_lib/dirty-check.sh`：`list_doc_dirty` / `auto_commit_docs` 共享 helper（pathspec 严格隔离）
- `scripts/create-task-worktree.sh` 加 pre-fork dirty gate：fork 之前 auto-commit 本 task 的 PM 视图主文件 + 工程合同
- `scripts/req-transition.py` 加 pre-transition gate：forward 推进时 auto-commit active req 范围内（含 `docs/DESIGN.md`）的未 commit 文档；rollback 不触发
- `skills/task-spec/SKILL.md` 新增步骤 12.6：reconcile 出口处由 skill 自身 commit task md 两文件到 req 分支（首道防线，PM 不感知；commit 字样列入步骤 12 chat 禁词清单）
- `INVARIANTS.md` 立 I-DC1（60→61 条），主索引加 `I-DC` 行
- 新测试套 `tests/test-pre-dispatch-doc-gate.sh`（10 条用例覆盖三道防线）

**业务仓需注意**：

- 同步后 task-spec 步骤 12 PM 一句"OK"会自动 commit 两文件到 req 分支，commit message 模板 `task-NNN-<slug>: spec sealed (hash <12chars>)`；PM chat 输出禁词扩充 `commit` / `已落盘` / `git log` / commit hash / commit message
- task-confirm fork 前若 req 分支 working tree 仍 dirty（task-spec 12.6 应该已处理，未触发说明走过 fallback），脚本 stderr 输出 `⚠️ I-DC1 pre-fork gate` 警告 + 自动落盘后再 fork；SKILL 要求 AI 把警告原文转给 PM 一句话说明
- req-transition forward 推进若 active req / DESIGN.md 仍 dirty，脚本 auto-commit + stderr 警告，commit message 模板 `req: stage <N>→<N+1> seal docs`；rollback 行为不变
- 既有 close-task.sh 行 185 的 req worktree dirty check 仍保留（fail-late 兜底层）；I-DC1 把多数场景在更早阶段消化，close 时该 check 应永远 silent

### 2026-05-09 — DX 审计本轮收尾 + 3 项 gap 补丁

**主线**：`/gstack-devex-review` 活体审计第一轮（4.7/10）→ 9 项 P0 + 横向 2 入口 + P1-4/6 落地后第二轮活体审计（5.6/10，+0.9）。本轮收尾 + 修剩余 3 项 gap。

- `8096be3` refactor(docs): P1-4 / P1-6 内容补丁
- `cb601b8` refactor(docs): P1-4 task-plan 硬约束节合并 + P1-6 STATUS → RUNTIME 改名
- `0579198` refactor(scripts): 防御性指令反模式 — req 编号扫描 / 未决问题闸门 抽脚本
- `34b1d4d` feat(skills): /skill-improve 雏形 + 消化 prd-writing 反馈 3 项 gap
- `ea2dc82` refactor(skills): PM-VIEW-RULES + 三个超大 SKILL.md 按消费方拆 references

**业务仓需注意**：

- `skills/_shared/PM-VIEW-RULES.md` 943 → 278 行 + 6 子文件 (`pm-view/{writing-rules,doc-strictness,section-order,checklist,input-flow,cross-skill}.md`)；12 个 skill 引用路径已改为指向具体子文件。**业务仓 sync 后**，模板里 `PM-VIEW-RULES §X` 引用号仍可用（主文件做索引），无须改业务仓产物。
- 三超大 SKILL.md 拆 references/：`task-execute` 911→539、`prd-writing` 756→315、`task-spec` 568→525。SKILL 主文件留 frontmatter + workflow 大纲 + 关键规则；详细 dispatch / acceptance handoff / writing rules / few-shots / impl-prose-merge 等进 references/。
- 新增 skill `/skill-improve`：消化 PM 反馈到对应 skill 的流程（read 反馈 → 对账现状 → PM 决策 → 改 SKILL → 归档到 `skill-feedback/<skill-name>-<date>.md`）。业务仓不需要直接装这个 skill；当 PM 想改进框架自身 skill 时调用。
- 新增 `scripts/_lib/req-num-resolver.sh`：封装 req 编号扫描（closed 目录 / active 目录 / git refs 三来源取 max）；`new-req` SKILL §步骤 1 改为单行 helper 调用。
- 新增 `scripts/check-open-questions.py`：未决问题闸门 lint（扫 `## 未决问题` section 下 `**PM 回答：**` 占位是否填）；`req-stage-gate` Stage 1→2 步骤 4 改为脚本调用 + exit code 路由。
- `task-plan` / `req-solution` 「硬禁止项 vs Rules」合并成单一 `## Rules`（含「禁止项」+「正向约束」两个 sub-bullet 组），与其它 skill 对齐。
- 错误信息加第三层「修复指引」：`task-transition.py` task 文件缺失时给路径 + 修复路径；`check-open-questions.py` 同。

### 2026-05-08 — 错误监控 + 状态机收敛 + DX 审计开始

- `8affee9` fix(audit): CT7 旧规范三步式兼容 + CT8 chore commit 豁免
- `3a4a98a` refactor(scripts): worktree 物理路径解析抽 `_lib/worktree.sh` helper
- `38313a9` feat(skills): task-plan 反模式扩容 + close-req 覆盖度判断 + INVARIANTS 主索引（60 条不变量速查）
- `95dca9e` feat(scripts): worktree 残留检测脚本 + 集成 req-stage-gate
- `2560cb8` refactor(docs): 归档 21 份历史设计档案到 docs/归档/完成/

**业务仓需注意**：

- `INVARIANTS.md` 加 60 条不变量主索引（按 I-G / I-CT / I-CR / I-CA / I-CB / I-AD / I-RV / I-TT / I-RT 前缀分组）。业务仓 sync 后续把 SKILL 里 `I-XX1` 引用都能在主索引里 30 秒定位。
- `task-plan` SKILL §2.2 反模式扩容到 5 条（A 纯前置 / B 横切质量 / C 共生对 / D 同文件串行 / E 模块归属）+ §2.4 拆分后自检 5 项 + 启发式 task 总数 > 7 / 单模块 > 3 触发审查。
- `close-req.sh` 加 doc-update 覆盖度自动判断（步骤 2a/2b）：扫所有 closed task 的 `## 文档偏差` section，发现 `<!-- SKIP_DOC_UPDATE` marker 且 `cleanup_status="pending"` → 阻止 close-req 推进。
- 新增 `scripts/check-worktree-residue.py`：检测编号冲突 / 孤儿 worktree；req-stage-gate Preamble 集成（不阻塞，警告供 PM 处理）。
- 新增 `scripts/_lib/worktree.sh`：branch ↔ worktree 物理路径解析 helper。

### 2026-05-08 之前 — v3.5 实施全部收口

阶段 1 + 2 + 3 + 4 + 4.5（含 d 修订 + e patch + f sync 改造）完成；阶段 5/6/7/8/9 全部废弃 / 跳过。详细进度见 [`RUNTIME.md`](./RUNTIME.md) 「v3.5 实施进度」章节。

最近一次 v3.5 改造（2026-05-08）：状态机收敛 — 合并「待验收」入「执行中」 + 推荐 review 移到验收信息块末尾。

- task 状态从 5 态 → 4 态（待确认 / 执行中 / 已完成 / 已废弃；删「待验收」）<br/>  *（注：「待确认」于 2026-05-09 改名为「待执行」，避免与 task-spec 步骤 12 的"确认 task 内容"语义重叠）*
- 合法 transition 从 6 → 3
- PM 打回**不切状态**：写反馈到 PM 视图历史档案 + AI 续修 + 追加 fix commit
- 推荐 review 不再是 commit 前必经步骤；改作呈交块末尾「⚙️ 可选深度审查」辅助提示
- 影响范围：INVARIANTS.md（I-CB10 / I-CT7 / I-RV1-2 / I-TT1-4 / I-CA2）+ task-transition.py / audit-task-events.py / status-view.py / close-req.sh / req-transition.py / skill-preamble.sh + skills/{task-execute,task-submit,task-status,task-spec,req-stage-gate} + 8 个 test 文件 + fixture.sh

---

## 未发布

### 2026-05-25 — D-i v4：office-hours 跨 Stage 1+2 集成 + Stage 2 真相源路径契约（snapshot 复制方案）

**痛点**：office-hours 在 Stage 1（`/new-req` 选项 1）+ Stage 2（讨论方式选择）两处都被调用看起来不合理 —— 用户视角是"一次需求讨论"，不该是 stage 1 + stage 2 两次拧巴。Stage 2 下游契约硬绑 `analysis.md` 也让"工具 2 选 1"（结构化批判 vs YC office-hours）走不通。

**方案**（设计 `docs/归档/完成/office-hours-跨stage1-2集成.md` v4，落实 Codex outside voice + 3 轮 plan-eng-review 全 21 决议）：

1. **PM 视角"一次需求讨论"体验包装**（`req-stage-gate` Stage 1→2）：brief 二次确认 + 讨论方式选择门合二为一，分流 A（`/req-analysis` 结构化批判）/ B（office-hours snapshot）
2. **Stage 2 真相源路径契约**（双分支）：A 分支产 `analysis.md` + 不变；B 分支 AI snapshot 复制 office-hours 设计稿到 `$ACTIVE_REQ_DIR/stage2-office-hours.md`（req 自包含，进 git / CI / 跨机器 / 归档 / consumer 仓全维度），不引用仓外 `~/.gstack/` 路径
3. **`.req-meta.json` 加 3 字段**：`stage{N}_source`（req 内相对路径）+ `stage{N}_tool`（产生工具名）+ `stage{N}_source_origin`（B 分支可选，外部源原始绝对路径追溯）
4. **helper**：`_lib.state.get_stage_source(req_dir, n)` + `set_stage_source(...)`，`STAGE_OUTPUT_FILES` 字典 schema 不动（保留 `dict[int, str]` 作 fallback）
5. **req-transition.py:247 改 helper**（R3-C1 必修，B 分支才推得进 Stage 3）
6. **下游 SKILL 通用化**（9 处）：prd-writing / implementation-design / task-spec / doc-update / close-task 文案 / templates/task-plan.md.tmpl / templates/CLAUDE.md.tmpl / input-flow.md / req-stage-gate Stage 2→3 段
7. **`/new-req` 砍选项 1**：单一 AI 引导路径；PM 想用 office-hours 风格深挖讨论 → Stage 2 stage-gate 入口 B 分支承接

**改动**（vp-1 → vp-7，~5h）：

- **vp-1**：`scripts/_lib/state.py` 加 `get_stage_source` + `set_stage_source` helper；`scripts/_lib/stages.py` 改注释扩双用途说明（transition 校验 + helper fallback）
- **vp-2** + **vp-3**：`skills/req-stage-gate/SKILL.md` Stage 1→2 重写为合二为一选择门 + 分流 A/B；B 分支含 office-hours bridge（探测 `~/.gstack/projects/$SLUG/*-design-*.md` 按 mtime + PM 三选一 + resume 协议 + AI snapshot 复制 + helper 写元数据 + term-detector hook + 推进确认门）
- **vp-2b**：`skills/new-req/SKILL.md` 砍选项 1（"自跑 /office-hours 整理 brief"），步骤 4 简化为 AI 引导 + PM 自写两路径；office-hours 边界注释移到 Stage 2
- **vp-4**：下游 9 处改 helper / 通用术语：`skills/{prd-writing,implementation-design,task-spec,doc-update,close-task,req-stage-gate}/SKILL.md` + `skills/_shared/pm-view/input-flow.md` + `templates/{task-plan.md.tmpl,CLAUDE.md.tmpl}`
- **vp-4b**：`scripts/req-transition.py:247` 由 `STAGE_OUTPUT_FILES[current]` 改 `get_stage_source(req_dir, current)`（R3-C1 必修）
- **vp-5**：`INVARIANTS.md` 立 I-RT9（stage N 真相源契约 + `stage{N}_source` / `stage{N}_tool` / `stage{N}_source_origin` 字段定义）
- **vp-6**：`tests/test-stage-source-helper.sh` 新增 11 case（get/set helper unit + grep 静态校验）+ `tests/test-req-transition.sh` 加 3 case（D-i v4 R3-C1 B 分支推进 / B 分支缺 snapshot 拒绝 / 旧 req fallback 兼容）
- **vp-7**：`CHANGELOG.md` 未发布段 + `docs/INDEX.md` + 设计文档归档为 `docs/归档/完成/office-hours-跨stage1-2集成.md`

**测试基线**：`bash tests/run-all.sh` **412/0**（前基线 398/0；D-i v4 新增 14 case 全过 —— 设计预期 ≥ 405/0，超出）。

**业务仓需注意**：

- **`/new-req` 选项 1 已砍**：旧版"自跑 /office-hours 整理 brief"路径不再可用；PM 想用 office-hours 风格请在 Stage 2 `req-stage-gate` 入口 B 分支跑（office-hours 设计稿会被 AI snapshot 复制进 req）
- **新 req `.req-meta.json` 多 3 字段**（`stage2_source` / `stage2_tool` / `stage2_source_origin`）；旧 req（无字段）自动 fallback `analysis.md`，零迁移
- **B 分支产物文件名固定**：`$ACTIVE_REQ_DIR/stage2-office-hours.md`；多次跑 B 分支会覆盖（PM 主动选 = 主动覆盖）。`stage2_source_origin` 字段失效不影响 req 自包含性
- **下游 SKILL prose 改通用术语"stage 2 真相源"**：A 分支 PM 体感不变（仍读 analysis.md）；B 分支 PM 看到 chat 里 AI 提到的是 stage 2 真相源 + stage2-office-hours.md
- **resume 协议**（PM 中断 chat 去跑 office-hours 后通知 AI 续 snapshot）：vp-2 实施时 stage-gate 状态机已落，PM 用任意句式回话 AI 都能接住（给文件名 / 给绝对路径 / 仅说"跑完了" → AI 自己重新探测）
- **R3-H2 DEFER**（office-hours prose 语义契约）：v4 §5.1 待验项 —— 相信 LLM 全文喂消化（v0 时 PM 已 ACCEPT prd-writing LLM-based fact），消费仓真实 req 验证 §六 派生质量；如不行再引入规范化 schema contract

### 2026-05-24 — 原型简化项登记机制 v2 落地（T1-T8 全包）

**痛点**：框架只有一份 req 级需求文档 `prd.md`，stage 3 是「评审用的完整真实需求」，close-req §2a 又把它「反向对齐成 as-built」。原型故意做得比 PRD 少的地方被 as-built 覆盖 —— 真实需求从评审文档消失。框架缺「原型故意简化」这个一等概念。

**方案**（设计 `docs/归档/完成/原型简化项-机制.md` v2，落实 plan-eng-review Round 1 全 16 决议）：`implementation-design.md` 加新段「段 1.5 · 原型简化项」（带稳定 `SIMP-ID`，stage 5 PM 确认门审定），按 PRD 锚点 join 下游消费链 task-spec / close-req / close-task。`adjustment` 事件 / `req-events.py` / close-req 现有覆盖逻辑完全不动。

**改动**（Lane A → Lane B/C，关键路径 worktree 并行 3.5-4h）：

- **T1**（templates/implementation-design.md.tmpl + skills/implementation-design/SKILL.md）：加段 1.5「原型简化项」（SIMP-ID schema + 表头 + 空态「无」）；SKILL.md 加 kind 1 登记引导（§2.1）+ Rules 定向豁免（段 1.5 允许写原型行为细节，scope delta 按定义不在 PRD）+ 扩 stage-5 确认门同时呈现架构决策表 + 段 1.5 摘要（D1）；自检从 4 段改 5 段
- **T2**（skills/task-spec/SKILL.md + templates/task.md.tmpl）：task-spec 步骤 6 加段 1.5 按 PRD 锚点 join 当前 task 逻辑（D5）—— 命中 → 实现规格 + PM 确认区·验收按简化后写 + 受影响验收项行内 `[SIMP-N]` 标签（D6）；task.md.tmpl §文档偏差区注释加 carve-out「已标记 SIMP-N 的不算偏差」（C3）
- **T3**（skills/close-req/SKILL.md §2a + close-report 模板）：§2a 改成两步顺序（D4）—— 先全部 adjustment overwrite → 再全部 simp 标注追加；锚点解析失败停下问 PM 不机械写错位（C5）；PRD 写回后跑 PM-view re-lint（D2 后置）；close-report 加「原型简化项」节（T8/C4）
- **T4**（skills/task-plan/SKILL.md §4.2 + templates/task-plan.md.tmpl）：§4.2 验收 GAP 清单加第三种处置「原型不实现（kind 2）→ 反向写回 implementation-design.md 段 1.5 SIMP-NN」（C1）；Required Inputs 补 `implementation-design.md`（C2）；task-plan.md.tmpl 修 stale `solution.md` 引用 → `prd.md + implementation-design.md`
- **T5**（scripts/check-doc-pm-view.py）：新增 `--simp-scope` 模式 —— implementation-design.md 段 1.5 scoped 校验（D2 源头约束），只校验段 1.5「真实需求」「原型本次计划简化为」「为什么简化」三个 PM 视图字段；其余段保持工程豁免不变；implementation-design SKILL.md 步骤 3.5 调用
- **T6**（skills/_shared/pm-view/input-flow.md）：Stage 5 task-plan 补 `implementation-design.md` 必读（C2）；Stage 6 task-spec 段 1.5 SIMP join 说明（C7）；§9.1.1 加「implementation-design.md 段 1.5 特殊读法」段（按 PRD 锚点 join，非 HOW-ID grep）
- **T7**（skills/close-task/SKILL.md Phase 1 步骤 1）：偏差分类「纠错 vs 计划外简化」（D3）—— 计划外简化停下问 PM 是否回填 implementation-design.md 段 1.5（C9 限定 close-time，已完成 task 不重生成）
- **T8**（scripts/derive-structure-templates.py → 派生 templates/工程结构约束-prototype.md）：「演示路径」深度指引补一句「本句覆盖路线默认范围 —— 不必为每个略过的 edge case 立 SIMP 行（C8 阈值：只登 PM 主动决策的决策级简化）」

**vp-5 解散（D7）**：测试折进各 T 自验，不堆独立测试 bucket。

**测试基线**：`bash tests/run-all.sh` **398/0**（无回归），新增 `--simp-scope` 正负向手动验证通过。

**业务仓需注意**：

- sync 后新跑 `/implementation-design` 自动产 5 段（含段 1.5）；旧 req 的 implementation-design.md 不强制回填，下次 revise 时按新模板。
- task-spec 现在按 PRD 锚点 join 段 1.5 SIMP 行 —— 业务仓 PRD §六章节命名应稳定（功能名级），否则 close-req §2a 锚点解析会失败 stop 问 PM。
- close-task Phase 1 现在多一步「偏差分类问 PM」 —— 计划外简化偏差才停，纠错偏差走原路径不打断（PM 体感同前）。
- 「原型本次实现」字段名已改「原型本次计划简化为」（C6 诚实命名）；段 1.5 模板与 SIMP 行参考 v2 设计文档 `docs/归档/完成/原型简化项-机制.md`。
- `task-plan.md.tmpl` 依赖从 `brief + analysis + solution.md` 改为 `brief + analysis + prd + implementation-design.md`；旧 task-plan 不强制回填。

### 2026-05-22 — 飞书发布兼容修复：§七 / §五 / §八 表格与列表格式

- `017b665` fix(prd-writing): §七 验收标准去引用块嵌复选框 + §5.1 多平台用户角色表 HTML→管道表格；publish-to-lark 加 HTML `<table>` 预检警告
- `6780f48` fix(prd-writing): §八 角色权限清单 / 原型列改造 + publish-to-lark 支持 `<!-- lark:no-merge -->` 标记

**背景**：飞书发布工具（lark-cli）只认 GFM 管道表格 / 标准 markdown，对若干结构会"悄悄塌掉"——发出来缺内容却不报错。prd-writing 原本多处要求用 HTML `<table>` 写带合并单元格的表，并断言"飞书识别 HTML 表格"——**该断言为假**。本次全面改造为管道表格：

1. **§七 验收标准**：`> - [ ]`（引用块嵌复选框列表）→ 普通项目符号（`**Story X**` 加粗 + `-`）。
2. **§五 5.1 用户角色（多平台 4 列表）**：HTML `<table>` → 管道表格 + 续行留空，跨行合并交给 publish-to-lark 的合并子系统。
3. **§八 角色权限清单**：HTML `<table>` → 管道表格。权限矩阵是「数据表」——空单元格 = 无权限（独立数据），与合并子系统「空 = 续行」语义冲突，因此整表不合并：「一级功能」列每行重复写全名，表前加 `<!-- lark:no-merge -->` 标记让 publish-to-lark 跳过该表合并。
4. **§六 原型列**：取消「原型」表格列。close-req 回填原型截图时作为独立图片放进 §6.X「原型」节，不塞进表格单元格（截图 + rowspan 的合并表无法干净发布）。

**新增 publish-to-lark 能力**：

- `<!-- lark:no-merge -->`：表前加此注释 → 该表跳过启发式合并、原样发布（按表格顺序与文档 table block 下标对齐；数量对不上则忽略全部标记并警告）。
- HTML `<table>` 预检：正文含裸 `<table>` → 打印警告 + 行号（不阻断发布）。

改动：`skills/prd-writing/SKILL.md`、`templates/req-prd.md.tmpl`、`skills/prd-writing/references/few-shots.md`、`skills/publish-to-lark/SKILL.md`、`scripts/publish-to-lark.py`。

**业务仓需注意**：

- sync 后新跑 prd-writing 生成的 §七 / §五 / §八 自动用新格式；已生成的 PRD 实例不强制回填，下次 rewrite 时收敛，或手动改后重发飞书。
- 权限矩阵类表（§八）发布前必须在表前保留 `<!-- lark:no-merge -->` 注释，否则空单元格会被错误合并。
- publish-to-lark 发布时若正文仍含 HTML `<table>`（旧 PRD）会打印警告 + 行号，提示改管道表格。

### 2026-05-22 — §8 后续收尾：DX 修复 + close-task 默认收尾 + modulespec 收敛 + CONTEXT→PROJECT 改名

- `6b2ce8c` refactor: docs/CONTEXT.md → docs/PROJECT.md 全量改名
- `57a6c4e` refactor(module-spec): 模板收敛 9→5 章 — 砍 req 级章节，活文档只留模块级内容
- `1e76be5` fix(dx): 统一入口脚本帮助/错误 — status-view 加示例段、init-project 缺参加命令骨架
- `f47f2fd` fix(dx): DX 诊断 4 修 — sed 元字符 / TTHW 工具误拷 / 正则过宽 / 中文 slug
- `bc979ce` fix(read_section): 标题正则容忍 emoji 前缀 — 修 v3 task close 被拦
- `07a3a09` feat(close-task): 验收通过后默认走收尾 — 逐条确认门改「默认走 / 必要才问」
- `07bf1c9` fix(init-project): skill 复制改递归 — 修 references/ 子目录漏拷

**⚠️ 一次性迁移（CONTEXT.md → PROJECT.md 改名）**：

框架把项目级文档 `docs/CONTEXT.md` 改名为 `docs/PROJECT.md`（与 GSD 命名层级对齐——GSD 的 `CONTEXT.md` 是 phase 级、`PROJECT.md` 才是项目级，原命名撞名错层）。已有消费仓 sync 后需跑一次 `scripts/migrate-context-to-project.py`：`git mv docs/CONTEXT.md docs/PROJECT.md` + 修业务文档（CLAUDE.md / docs/ / requirements/ 下 git-tracked 的 .md）里的 `CONTEXT.md` 引用，不碰 `.claude/`（框架同步资产已随同步更新）。幂等——已是 `PROJECT.md` 或新建仓跑本脚本是 no-op。详见 `框架同步-SOP.md` §4.10。

**业务仓需注意**：

- close-task：PM 验收通过后默认直接走完收尾（DESIGN / PRODUCT-RULES 提升、文档偏差对齐等），仅在「代码可能做错 / 需回退代码 / 范围变了」时才单独找 PM 确认；收尾末尾给汇总 + PM 总审 diff。
- modulespec 模板从 9 章收敛到 5 章：活文档只留模块级内容，req 级章节移除。已有消费仓的 modulespec 实例不强制回填，下次 close-req rewrite 时自然收敛。
- `init-project.sh` skill 复制改为递归（`cp -R`），修复 `references/` 子目录漏拷——此前 sync 出的消费仓 skill 可能缺 references/ 子文件，建议 sync 后抽查 `.claude/skills/*/references/`。
- read_section（`_lib/state.py`）标题正则现容忍 emoji 前缀——使用 emoji 标题的 v3 task 文件不再在 close 时被误拦。

### 2026-05-22 — GSD-review 管线重构全包

`31769a6` feat(gsd-review): §8 管线重构全包落地 — delta-2/3/4/7/8/9 + delta-1/5/6

**主线**：umbrella `docs/归档/完成/管线重构-GSD-review.md` §8 六步顺序全实施，替换旧 solution 双文件管线，接入 stage 3 PRD、req 级事件流、req 级实现设计、task 单文件 typed contract、跨功能产品规则和 brownfield codebase-audit。

**影响范围**：

- 新增 `scripts/req-events.py`：`decision` / `adjustment` 两类 req 级事件，落 `requirements/active/<reqid>/req-events.jsonl`。
- `req-solution` 退场，新增 `/project-solution`；`/prd-writing` 前移到 stage 3，产 req 级 `prd.md`。
- 新增 `/implementation-design` + `templates/implementation-design.md.tmpl`，stage 5 拆 task 前产 req 级 HOW。
- `task-spec` 从双文件改成单文件 typed contract（PM 确认区 / 执行区 / 审计区三区 + `task_format` 标记）。
- 新增 `templates/PRODUCT-RULES.md.tmpl`，升级 `DESIGN.md.tmpl`；close-task 支持 PRODUCT-RULES selective promote，req-stage-gate stage 4 每 req 必跑 gap-check。
- 新增 `/codebase-audit` brownfield 入口；close-req 步骤 2a 改为读 req-events adjustment，把 PRD 反向对齐为 as-built。
- 删除旧 solution / task engineering 双文件模板与 reconcile/hash 相关机制；`req-transition.py` 对在飞旧 req 保留文件存在性兼容（有 `solution.md` 且无 `prd.md` 时走旧 stage 3 判别）。

**业务仓需注意**：

- 同步后新 req 走 `analysis.md → prd.md → DESIGN/PRODUCT-RULES gap-check → implementation-design.md → task-plan.md → task 单文件 typed contract`。
- 在飞旧 req 可按文件存在性兼容继续跑完，但不建议新建旧 `solution.md`。
- 同步前后应按 `框架同步-SOP.md` 跑 Python import 冒烟和 `bash tests/run-all.sh`；当前生成器基线 395/0（`_lib.state_test` 57/0）。

### 2026-05-21 — accept 闸门 + evidence-repair

- `bd1f1a3` feat(task-transition): accept 闸门 + evidence-repair 命令
- `f37c83f` fix(task-transition): /review 跟进 — 接住 UnicodeDecodeError + repair-evidence 分支守卫

**修复**：

- `task-transition.py` 的「执行中→已完成」前移执行证据校验：事件流必须有 `execution_started` 或 `execution_manual_completed`，否则拒绝验收并提示先走 `/task-execute`。
- 新增受支持的 `--repair-evidence` 路径，用于 close-task 审计发现历史证据缺失但 PM 已确认真实完成时，受控补记带 `repaired` 标记的执行事件。
- 执行事件判定抽到 `scripts/_lib/events.py`，同时覆盖坏行 / 非法 UTF-8 / 分支已不存在等守卫。

**业务仓需注意**：

- 同步后不能再通过手改状态把未走执行通道的 task 直接验收为已完成。
- evidence repair 是审计修复口，不是常规工作流；必须保留理由和 PM 认定。

### 2026-05-21 — publish-to-lark 覆盖发布 frontmatter 泄漏修复

`bc9ab3f` fix(publish-to-lark): adapter 发送前剥离 frontmatter — 覆盖发布不再把 frontmatter 当正文

**缺陷**：`publish-to-lark` 把 markdown 开头的 YAML frontmatter（`---` 包裹的元数据块）当正文发给飞书——飞书不剥离 frontmatter，它会渲染成一段正文。覆盖发布结构上必然中招：首次发布回填的 `lark_doc_id` 就在 frontmatter 里，覆盖路径正是靠它触发的。

**修复**：frontmatter 拆分收口到 `scripts/_lib/lark_adapter.py` 的 `parse_frontmatter`（单一实现，`publish-to-lark.py` 改为 import 复用，删本地重复正则）；新增 `_markdown_body_path`，`docs_create_from_markdown` / `docs_update_from_markdown` 发送前统一剥掉 frontmatter 只发正文（与已有的 cwd workaround 同属「lark-cli markdown 发送怪癖」收口）。

**业务仓需注意**：

- 同步后 `publish-to-lark` 首次发布与覆盖发布都只发正文，本地 markdown 文件不改动。
- 此前已发布、顶部残留 frontmatter 段的飞书文档，重新跑一次发布即被覆盖修正。
- 影响文件：`scripts/_lib/lark_adapter.py` + `scripts/publish-to-lark.py` + `skills/publish-to-lark/SKILL.md`。

> （PM 完成 main 上的下一项改动后，先把 commit 加到这里；准备 sync 业务仓时再上提到「已发布版本」段，并在业务仓 sync commit 里引用本段。）

---

## 关联文档

- `RUNTIME.md` — 当前运行时状态 / 续接入口
- `框架同步-SOP.md` — 生成器 → 业务仓 hotfix 同步流程
- `INVARIANTS.md` — 框架不变量清单
- `docs/归档/完成/DX-AUDIT-2026-05-08.md` — 2026-05-08 DX 审计档案
