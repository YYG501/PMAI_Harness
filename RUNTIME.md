# RUNTIME（项目运行时状态）

> **职责**：当前进度 + 下一步入口 + 已知坑（运维入口；新窗口续接读这里）。
> **维护约定**：每完成一阶段更新本文件（~10 秒）；只留当前状态，已完成阶段的细节归档。
> **单一真相源**：测试基线 / 当前状态 / 下一步只在本文件「当前位置」写一处；CLAUDE.md / README.md 只放指针，不复制数字。
>
> 与 `README.md` / `CLAUDE.md` 的区分：
> - `README.md` = 产品介绍（一次写完，仓库门面）
> - `CLAUDE.md` = 项目章程（Claude Code agent 必读，行为规则 + 工程结构约束）
> - `RUNTIME.md`（本文件）= 运行时状态（动态更新；当前位置 + 已知坑 + 续接入口）

---

## 当前位置（2026-05-29）

**2026-05-29 — PMAI 重构方向（office-hours 收敛）：方案定盘、未实施**（PM 跑 `/gstack-office-hours` 诊断"框架用着不顺、出的第一版原型不如直接给 AI"；全程取证 + 5 视角对抗审 + 真实 A/B spike 收敛出重构方向。**这是方向性反转、范围远超单个 feature**）：

- **核心**：砍 7-stage 固定流水线 + 每段全文确认门 → 坍缩成**六步**（①上下文脊柱 ②范围确认 ③栈内 build ④三道审 ⑤体验迭代 ⑥沉淀）；想 / 建原型交 Claude Code 在栈内直连、零录入，PMAI 缩成**上下文脊柱 + 范围确认 + 沉淀**层。
- **真相源**：方向 = `docs/设计/PMAI重构方向-office-hours收敛.md`（§2.3.1 范围确认 / §2.3.2 复审沉淀 / 两不变量 / 证据 / 决议日志）；落地 = `docs/设计/PMAI重构-实施清单.md`（skill 去留 / gstack 接入 / worktree / 基础设施 / **D1-D10 全拍定** / §7 新 scope）；决策快照 memory `project_pmai_reshape_direction`。
- **关键决策（全 PM 拍板）**：D1 六步反转 · D2 task 降后台留名（mode 中立）· D3 PRODUCT-STATE = 现状层 hub · D4 实现深度 mode 按层挂靠（复用现成 `工程结构约束-{prototype,system,custom}`）· D5 prototype 默认 Next.js+shadcn · D6 实现文档 = per-req `req-plan.md` · D8 worktree 自动托管早上 + spike · 附件机制保留 + rewire · §7（站点爬·对齐线上·覆盖审计 checks-JSON·产物层 deliverables）。
- **状态**：方案纯设计；落地已起步（见下「重构落地进度」）。**测试基线 548 / 0**（实跑发现比旧记的 525/2 高且全绿，旧数字已过期，以此为准）。

**重构落地进度（branch `reshape-office-hours`）**：
- ✅ 阶段1 增量脊柱：`PRODUCT-STATE.md.tmpl` / `req-plan.md.tmpl` / `DESIGN.md.tmpl` / `prototype-README.md.tmpl` 模板 + `coverage-reviewer` agent（均已提交、548 绿、尚未接线）
- ✅ plan-eng-review 跑完（PM 拍：自动托管 spike 加固复现 2026-04-22 事故 / 六步坍缩先迁移测试；落点进实施清单 §6）
- ✅ 六步坍缩盘点：stages.py（两 dict）+ req-transition.py（推进引擎）+ status-view/state（6+ 处 STAGE_NAMES）+ 7 个 stage 专属测试 全摸清
- ✅ **#9 六步坍缩引擎**（411b568）：`stages.py` 7-stage→四阶段（1 范围确认/2 build/3 复审/4 沉淀）+ `req-transition.py` 重写（MAX_STAGE=4、删 stage-4 跳过/prd-solution 前置/stage6-7 回退）+ 迁 3 测试套（删 8 个 7-stage 独有用例），**548→540 全绿、已提交**
- ✅ **#10 六步级联**（17710cd，workflow 19 agent + 收口）：砍 req-stage-gate→壳 / 新建 `skills/next` (/pmai-next 驱动) / 降后台 6 / 改造 7（init·new-req·task-plan·task-execute·task-status·close-req·prd-writing）/ 合并 2 / _shared 同步；迁删钉旧机制测试。**540→533 全绿、已提交**
- ✅ **#3 init-project / #4 new-req / #6 入口收敛+next**：随级联落地
- ⏳ **余下未做**：#5 藏显示 banner/status 转**完整产品轴**（现 /7→/4 半步）；#7 砍冗余剩余（req-stage-gate 已砍，其余纯过程税）；attachments.py 的 stage_prefix→req-plan rewire（skill prose 已指、helper 未动）；build 三道审的**脚本级接线**（prose 已写、coverage-reviewer/browse 编排未脚本化）
- ⛔ **#8 自动托管 spike**：加固版（复现+挡 2026-04-22 事故）需 careful 专注一段
- ⛔ **阶段2 build 纪律**：按设计"新机制先 spike"，需**真实消费仓 req** 验 design 约定逼近视觉 —— 非自动可完成，待真 req + PM
- **⚠️ 消费仓暂勿同步**（CHANGELOG 已标）：attachments rewire / 三道审脚本接线 / 藏显示 / spike 未完，旧 req 越界
- 详细任务看 TaskList（#1/#3/#4/#6/#9/#10 done）

---

**2026-05-27 — 同步资产内部编号清理 + hook 防回归**（PM 看到 close-task SKILL.md 「D13 不调 doc-update」追问"这里 d13 是啥"触发；反向暴露所有同步资产积累了同类生成器内部知识债）：

- 清理 58 文件：删 `D13` / `D-iii v2` / `delta-N` / `vp-N` / `polish-N` / `R3-C1` 等内部编号；改 `docs/归档/完成/` / `docs/设计/` 归档路径死链；删 commit hash 短引用
- 改造原则：删内部编号但**保留 WHY 信息**（"D13 final, 不调 doc-update" → "不调 doc-update（推迟到 close-req 末聚合）"）
- 保留：`INVARIANTS I-AD1` / `I-CT7` 等稳定 anchor；同 SKILL 内部 §章节引用
- hook 防回归：`hooks/check-sync-asset-jargon.cjs`（git commit 时扫 staged + 行命中 pattern 拦下）
- memory 沉淀：`feedback_sync_asset_no_internal_ids.md`（同型 `feedback_pm_chat_no_engineering_jargon` 的资产层延伸）
- **测试基线 525 / 2**（pre-existing stale test 2 个跟本次清理无关：`test-init-project.sh T1/T2` 在 init-project 重构为 symlink 后没同步）

---

**Speed mode — PRD 拍板后 stage 4/5 自动推 + 结构决策门 + stage 6 入口总览**（消费仓 ExampleConsumerApp req-008 实证驱动；PM 否决 gsd 式 8 开关方案，选「1 个默认 mode + 严格清单」方向）：

- **vp-1**：`templates/implementation-design.md.tmpl` 段 1 HOW 表加「决策类型」列（结构 / 机械）+ 填写规则注释（备选≥2 个有效 → 结构；"—"/「已硬约束」→ 机械；拿不准默认结构）；段 1.5 SIMP 全表标注"视作结构决策"
- **vp-2**：`templates/task-plan.md.tmpl` §一 task 表加「决策类型」列 + 填写规则（合并 / 拆开 / 重排 order / 反模式 A 命中 → 结构）
- **vp-3**：`skills/req-stage-gate/SKILL.md` 顶部加 `## Speed Mode（默认行为）` 段；Stage 4 步骤 4C 加 speed 自动续条件（gap-check 无新缺 + DESIGN 不改 → 跳完整确认门）；Stage 4→5 步骤 5a-gate 改 speed 行为（扫段 1 HOW + 段 1.5 SIMP 逐行 prompt 结构决策）；Stage 5→6 全段重写（扫 task 表逐行 prompt → 调 stage6-entry 出总览 → PM 三选 ✓ / ↺ / ✗）
- **vp-4**：`scripts/_lib/stage6_summary.py` 新建（~280 行）+ `scripts/status-view.py --stage6-entry <REQ_DIR>` CLI 入口 + 从 req_dir 反推 worktree repo_root（跨仓 DESIGN.md 路径不错位）
- **vp-5**：`tests/test-speed-mode.sh` 新增 13 case（argparse / 模块函数 / 模板列 / SKILL 段 / fixture 全机械 / 全结构 / 老 req 兼容 / SIMP 归位 / 结构 task / CLI exit / Stage 4 文案 / Stage 5→6 调用）；`tests/test-implementation-design.sh` 更新 stage-gate wiring 校验为 speed mode 关键文案
- **vp-6**：`CHANGELOG.md` 未发布段加条目 + 本 RUNTIME 段更新

**测试基线**：`bash tests/run-all.sh` **516 / 0**（前 460/0 → speed mode 主体批次 vp-1~vp-6 +13 case → 512/0 → vp-7/8 +4 case → 516/0；无回归）。**2026-05-27 后**：基线推到 **525 / 2**（同步资产清理后跑出 2 个 pre-existing stale test，跟清理无关）。

**PM 视角变化**（用 req-008 跑下来对比）：操作次数从 ~7 次降到 ~6 次（数量差不多），但**质量大变** —— 0 次低价值"看了，过"门、N 次结构决策被前置到决策当下问、stage 6 入口给一次性总览（自决项 + PM 拍过项 + task 拆分 + 产物路径，PM 一眼判断是否进 task 执行）。

**vp-7/8 增量（同日批次）**：
- **vp-7** `skills/task-spec/SKILL.md` 步骤 11 改"续跑 /pmai-task-confirm"，PM 不再手动贴命令；`skills/task-confirm/SKILL.md` When To Use 段加续跑触发分支。失败兜底走旧手动调 escape hatch
- **vp-8** `skills/task-plan/SKILL.md` 加步骤 3.5 "PM 拍板执行模式（结构决策门）"：AI 默认推断 + 主动 prompt PM 拍串行 / 并行 / 混合；`templates/task-plan.md.tmpl` §二 加显式 `**执行模式（PM 拍板）**` 标记 + 注释扩展
- **触发**：req-008 PM 反馈 (a) 多一道 "复制 /pmai-task-confirm" 仪式（task-confirm 是机械流程不该 fork）(b) 临时问"几个 task 可以并行" 暴露 AI 自决"串行"未经 PM 拍板

---

**下一步（2026-05-29 起 — 重构落地）**：

1. **`/plan-eng-review` 审重构落地顺序 + 风险**（方案大，动手前审最稳；重点盯：D8 自动托管 spike = 动 merge/删/residue + dispatch-clean 事故区 / 覆盖审计吸收 checks-JSON 的改造面 / 阶段 0「砍冗余」具体边界）。
2. **阶段 0**（方向稿 §4）：砍冗余（工程双合同 / 同范围重复 / 琐碎 req 全套 / 机器废气 —— 稳赚独立、可立即动）+ worktree PM 视图隐藏 + 自动托管 spike + 入口收敛定方向（init / new-req / next / status）。
3. 下一个真实 req 用新 build 路径（栈内 + design 约定 + 三道审 + 覆盖审计）当 **build spike**。

**旧 speed mode 下一步（同步 ExampleConsumerApp + 端到端验收）= 暂缓**：7-stage 正被坍缩成六步，speed mode 是 7-stage 的优化，待重构阶段 0 落地后重估是否还需独立验收（不擅自废，PM 拍）。

---

## 历史阶段（已完成）

**2026-05-25 — D-iv 入口与全流程体验顺畅性全包 ship**（设计文档归档 `docs/归档/完成/入口与全流程体验顺畅性.md`；M3 砍后 M1+M2+M4+M5 共 11 vp 全过；plan-eng-review Round 1 16 finding ACCEPT，codex C-1 砍 M3）：

- **批 1 M1 init-project 一气呵成**（commits 6df9cf4 + dcf5802 + 39cb81f + fe1b7ac + f8c1c90）：vp-1 4 阶段重写 + vp-2 `_shared/project-questioning.md` 单一真相源 + vp-3/4 README 单步 + vp-5a 3 测试 11 cases + vp-6 `/pmai-project-solution` 4 场景细化
- **批 2 M2 banner + M4 askuser + M5 播报**：vp-7 `banner-rules.md` + `_lib/state.py` + `status-view.py --banner-only` + vp-8 7 SKILL 加指针 + ~~vp-9 砍~~ + vp-10 `askuser-rules.md` + vp-11 `status-view.py --narrative` + CLAUDE.md「Session 起始播报」
- **测试基线**：446 / 0（vp-7 + vp-8 + vp-10 + vp-11 实测加 10 cases）

**2026-05-25 — D-iii v2：attachments AI 接管全包**（helper-based，commit 1eb3480 + 9644046 + 6df9cf4 + dcf5802）

- **vp-1**：`scripts/_lib/attachments.py` 新建（~370 行）—— `copy_attachment` / `register_attachment` / `list_attachments_seen` / `is_seen` / `remove_attachment` / `replace_attachment` + `SENSITIVE_PATH_PATTERNS` 12 patterns denylist + `MAX_FILE_SIZE_MB = 50` hard cap
- **vp-2**：`skills/_shared/pm-view/attachments-upload.md` 新建（~230 行）—— trigger 0 LLM 识别 prose 单一真相源 + caller 调 helper 模式
- **vp-3 + vp-3b + vp-3c**：7 stage SKILL 加 trigger 0 inline 段 + `new-req` commit pathspec 扩 attachments/（C1）+ `req-stage-gate` B 分支 trigger 0 disable（C4）
- **vp-4**：`tests/test-attachments-helper.sh` 13 case
- **vp-5**：`templates/req-prd.md.tmpl` 新加 `## 📎 参考材料`
- **vp-6**：`PM-VIEW-RULES.md` 加 §10 索引行 + `INVARIANTS.md` 立 **I-RT10**

**累计 helper-based 升级**（D-i v4 + D-iii v2）：`.req-meta.json` 4 个 helper 化字段（`stage{N}_source` / `stage{N}_tool` / `stage{N}_source_origin` / `attachments_seen`），全部走 `_lib/state.py` + `_lib/attachments.py` 读写。

**消费仓验证待项**（与 D-iv M1 vp-5b 一起跑）：① LLM trigger 0 识别准确性 ② `SENSITIVE_PATH_PATTERNS` 覆盖度 ③ `MAX_FILE_SIZE_MB = 50` 阈值。

---

**2026-05-25 — D-i v4：office-hours 跨 Stage 1+2 集成全包** —— 设计 `docs/归档/完成/office-hours-跨stage1-2集成.md` v4（Codex outside voice + 3 轮 plan-eng-review 全 21 决议；snapshot 复制方案 + 体验包装层）+ 实施 vp-1 → vp-7：

- **vp-1**：`_lib.state.get_stage_source` + `set_stage_source` helper（stages.py STAGE_OUTPUT_FILES 保留 `dict[int, str]` schema 作 fallback；新增 `stage{N}_source` / `stage{N}_tool` / `stage{N}_source_origin` 字段契约）
- **vp-2 + vp-3**：`req-stage-gate` Stage 1→2 重写为合二为一选择门 + 分流 A（结构化批判 `/pmai-req-analysis`）/ B（YC office-hours 式 + bridge snapshot 复制）；B 分支 resume 协议（PM 中断 chat 去跑 office-hours → 任意句式回话 AI 接住 → snapshot + helper 写元数据）
- **vp-2b**：`/pmai-new-req` 砍选项 1（"自跑 /office-hours 整理 brief"）；office-hours 边界单点收敛到 Stage 2 stage-gate 入口
- **vp-4**：下游 9 处改 helper / 通用术语"stage 2 真相源"（prd-writing / implementation-design / task-spec / doc-update / close-task 文案 / templates 双 + input-flow.md + req-stage-gate Stage 2→3）
- **vp-4b**：`req-transition.py:247` 由 `STAGE_OUTPUT_FILES[current]` 改 `get_stage_source(req_dir, current)`（R3-C1 必修，否则 B 分支推不进 Stage 3）
- **vp-5**：`INVARIANTS.md` 立 **I-RT9**（stage N 真相源契约 + 3 字段定义；其他 stage 暂未启用双源，按 helper fallback 走默认产物）
- **vp-6**：`tests/test-stage-source-helper.sh` 新增 11 case（unit + grep 静态校验）+ `tests/test-req-transition.sh` 加 3 case（B 分支推进 / 缺 snapshot 拒绝 / 旧 req fallback）

**测试基线**：`bash tests/run-all.sh` **412 / 0**（前 398/0；D-i v4 新增 14 case 全过 —— 设计预期 ≥ 405/0，**超出**）。

**v4 反转点**（vs v3 引用方案）：PM 提问 "office-hours 产出到底会不会变" → AI fact-check 现仓 office-hours SKILL.md 确认文件名带 datetime 戳 + Supersedes 是新文件链、生成后冻结 → 推翻 v1 "office-hours 上游会变" 错误前提 → Codex outside voice 同步命中 "v3 引用 `~/.gstack/` 不进 git/CI/跨机器" → v3 整体反转回 v0 复制方向 + 加体验包装层。

**待验项**：
- **R3-H2 DEFER**（v4 §5.1.1）：office-hours prose 派生 prd.md §六层级实际效果 —— 相信 LLM 全文喂消化能力，**消费仓真实 req 验证**；如不行再引入规范化 schema contract
- **R3-H3 PARTIALLY ACCEPT**（v4 §5.1.2）：resume 协议状态机细节已写进 vp-2，真实 PM 跑过一次后再看是否要再加 chat 提示词约束

**v4 下一步**：已合并到当前位置「下一步」一起验证。

**2026-05-24 — 原型简化项登记机制 v2 全包**：设计 `docs/归档/完成/原型简化项-机制.md` v2 + 实施 T1-T8（8 个 touchpoint，关键路径 worktree 并行 3.5-4h）：

- **T1**：`implementation-design.md.tmpl` 加段 1.5「原型简化项」（SIMP-ID schema + 表头 + 空态「无」）+ SKILL.md kind 1 登记引导 + Rules 定向豁免 + 扩 stage-5 PM 确认门同时呈现架构决策表 + 段 1.5 摘要
- **T2**：task-spec SKILL.md 加段 1.5 按 PRD 锚点 join 当前 task 逻辑（命中 → 实现规格 + 验收按简化后写 + 受影响验收项行内 `[SIMP-N]` 标签）+ task.md.tmpl §文档偏差区 carve-out
- **T3**：close-req §2a 改两步顺序（先全部 adjustment overwrite → 再全部 simp 标注追加）+ 锚点解析失败停下问 PM + PRD 写回后 PM-view re-lint + close-report 加「原型简化项」节
- **T4**：task-plan §4.2 GAP 清单加第三种处置「原型不实现（kind 2）」+ Required Inputs 补 implementation-design.md + task-plan.md.tmpl 修 stale solution.md 引用
- **T5**：`scripts/check-doc-pm-view.py` 加 `--simp-scope` 模式（implementation-design.md 段 1.5 scoped 校验，源头约束 + 后置 PRD 校验同款 lint）
- **T6**：`_shared/pm-view/input-flow.md` Stage 5/6 补 implementation-design.md 段 1.5 输入说明
- **T7**：close-task Phase 1 步骤 1.1/1.2 偏差分类「纠错 vs 计划外简化」+ 计划外简化停下问 PM 回填 implementation-design.md 段 1.5（close-time 限定）
- **T8**：`derive-structure-templates.py` 「演示路径」深度指引补「路线默认范围由本句覆盖、只登决策级简化」+ 派生 `templates/工程结构约束-prototype.md`

**v2 测试基线**：`bash tests/run-all.sh` **398 / 0**（已被 D-i v4 推到 412 / 0）；vp-5 解散（D7）测试折进各 T 自验。

**v2 前置**（2026-05-22 GSD 管线重构全包）：delta-1..9 全包落地（umbrella `docs/归档/完成/管线重构-GSD-review.md`），含 delta-7 req 级事件流、delta-2+4 PRD/solution 对调、delta-8 implementation-design、delta-3 task-spec 单文件 typed contract、delta-9 跨功能产品规则。

**v2 消费仓验证待做**（接 D-i v4 下一步一起跑）：①  漏登简化项频率（§5.1）② 计划外简化频率（§5.2）③ PRD 锚点漂移频率（§5.6）。

---

## 已知坑

当前无活跃的实施期已知坑 —— §8 全包已测 395/0。历史 v3.5 实施期发现的坑（parser section 终结符 / 空 cell 返回值 / macOS bash 3.x 空数组 unbound 等）见 `docs/归档/完成/RUNTIME-历史-v3.5与skill收敛.md`。

跨会话的工作方式 / 反模式沉淀见 memory（`MEMORY.md` 索引）。

---

## 文档导航

| 文档 | 作用 |
|---|---|
| `RUNTIME.md`（本文件）| 当前进度 + 下一步 + 已知坑 |
| `CLAUDE.md` | 项目章程（行为规则 + 工程结构约束）|
| `CHANGELOG.md` | 影响业务仓的改动流水（同步决策入口）|
| `框架同步-SOP.md` | 生成器 → 业务仓 hotfix 同步流程 |
| `INVARIANTS.md` | 框架不变量清单 |
| `TODOS.md` | 待决清单 |
| `docs/INDEX.md` | docs/ 全导航（设计中 / 已落地 / 已废弃）|
| `docs/归档/完成/RUNTIME-历史-v3.5与skill收敛.md` | v3.5 九阶段 + skill 读取收敛实施历史（本文件瘦身前内容）|

---

## 新窗口续接命令

> 继续 PM-AI-Workflow。读 RUNTIME.md「当前位置」——**PMAI 重构方向（office-hours 收敛）方案已定盘**（两份设计文档 + memory `project_pmai_reshape_direction`，D1-D10 全拍定，**纯设计未实施**，基线仍 525/2）。下一步：`/plan-eng-review` 审落地 → 阶段 0（砍冗余 + 藏显示 + 自动托管 spike）。等 PM 给方向。

AI 收到后应该：
1. 读本文件「当前位置」2026-05-29 段 + 两份设计文档（方向 `PMAI重构方向-office-hours收敛.md` / 落地 `PMAI重构-实施清单.md`）确认重构方案与所有 D 决策
2. 等 PM 给具体方向：① 起 `/plan-eng-review` 审落地 ② 直接进阶段 0 砍冗余（稳赚独立）③ 别的事
3. **不擅自动代码**——重构是纯设计态，改动前先确认走哪一步
