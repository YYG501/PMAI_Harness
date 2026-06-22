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

## 当前位置（2026-06-22）

**框架瘦身改造（吸收 ExampleAgentProject 设计方法）已整体 merge 进 `main`**（merge commit `135c3f7`，2026-06-21；reshape/absorb-01agent 分支全部并入；CHANGELOG 整段仍在「未发布」、消费仓尚未打 tag 同步。设计源 `docs/设计/lifecycle迁移计划.md` + `docs/设计/工作方法论与工作流-总纲.md`）。本轮交付（已落地·已 merge）：

- **方向**：砍框架过度设计、借 ExampleAgentProject 工作模式（模块三件套 / design-card / spec-polish / mock）、补真实缺口；其中 **lifecycle 机器层重构** = 取消 `requirements/active|closed/` 整棵树，req 状态真相源迁到 `docs/modules/<模块>/.req-meta.json`（见 INVARIANTS 新增 **I-MOD1**）。
- **批 0-2（已完成）**：迁移脚本 `migrate-reqs-to-modules.py`（dry-run）+ `_lib/state.py` 双读→单读切真相源 + `check-branch.sh` GATE 1/2/3 路径迁移与 main 写保护放宽（`docs/**` 全放行、`prototype/` 仍拒绝、stage 字段仍走 req-transition）+ `create-req-headless.sh`/`skill-preamble.sh`/`worktree.sh cleanup` 路径切换 + fixture 双写桥接。
- **批 3（已完成·本轮·方案 A）**：`close-req.sh` 重写——close = 清模块 `.req-meta`（`git rm`），不再 `git mv active→closed`；有 worktree → merge 回 main（ancestor 验证 + I-CR9 回滚），无 worktree/无分支 → 直接 main 清 `.req-meta` 跳 merge。`cancel-req.sh` 同步改清模块 `.req-meta`（不 merge）。`symlink-prd.sh` + `pmai-sync-prds` PRD 源改 `docs/modules/<模块>/prd.md`。拆掉 fixture 的 `requirements/` 半边桥接（`fixture_create_req` 只建 `docs/modules/`、task 直落模块 tasks/）。连带修：`check-status-direct-edit.py`（pre-commit）+ `quick-fix.sh`（warn_active_reqs / is_redline_path）补 `docs/modules/*` 真相源；close-task / drift / pre-commit-hook / v4_T22 等 dormant·e2e 测试的 `requirements/active/` 路径假设改 `docs/modules/`。
- **批 4（已完成·本轮）**：INVARIANTS.md 对齐——I-CR1/3/4/5/8（close 方案 A·worktree 可选·stage 4 沉淀）、I-CA4（清模块 .req-meta）、I-CB3/5/6（main docs/** 放行·路径迁移）、I-DC1（seal 路径 docs/modules·task 两道防线 dormant）、I-RT4（stage 4 沉淀不可回退）、**新增 I-MOD1**；task/exec 系列（I-CT/I-TT/I-CB4/10/I-AD + I-DC1 task 防线）标 🟡dormant（代码保留·测试仍跑·并行多 task 恢复时复活）。
- **工作方法论纠错 A-D**（merge 含·6 条开放问题拍板后）：纠正 reshape「砍仪式补方法」浅设计——A 对抗三问强制门（`skills/_shared/anti-cut-check.md`）/ B 恢复 3 个正交决策家 + `build-audits.py` 锚点参数化 / C `/design` 三段式重构（探索→设计→写规格、删 `req-analysis` skill、诊断内核搬 `req-questioning.md`）/ D worktree·close 收口。新增 skill `design`/`mock`/`build`/`close`/`status` + 方法论 `info-design`/`req-questioning`/`anti-cut-check`。
- **规格语言风格标准**（merge 含）：两类产物两套风格 + 格式骨架统一（标题序号 / 规范节名 / 固定节用表格）+ 规格样例（轻 spec / 重 PRD / 同需求对照）。
- **测试基线 601 / 0 全绿**（lifecycle 批 0-2 后 588→599；批 3/4 零净回归→599；方法论纠错 A-D +2 build-audits override 用例→601；已随 merge 进 main）。
- **下一步**：① **消费仓同步决策**——CHANGELOG 整段仍「未发布」，本轮改动大（消费仓需重跑 `pmai install`/`upgrade`，在飞 req 跑 `migrate-reqs-to-modules.py --dry-run` 迁移）；是否打 tag 发布待 PM 拍。② **真 req build spike 端到端验证**（一直挂着的余债：视觉门 `/design-review` + 行为审 `/browse` 真实浏览器链路 + dev server 真复用 + worktree 自动托管 fork/merge/删闭环；编排 + 覆盖审计已在 spike 验过，差浏览器侧）。③ **迁移练兵**：拿消费仓 `ExampleAgentProject` 走一遍新 `docs/modules` 结构 + 分档沉淀逐痛核对。④ **余债**：批 5（timeline/status-view closed 视图，方案 A 下列表自然空）/ 批 6（附件迁移 I-RT10·与核心解耦）/ INVARIANTS I-RT2/I-RT5 仍写旧 stage 5/6 措辞（迁移遗留·非本批引入）/ close-task.sh 归档·事件路径仍 hardcode `requirements/active/`（dormant·下次激活 task 系列一并对齐）。

---

## 历史位置（2026-06-04）

**2026-06-04 — 分档运行 + 每档沉淀 + mock 变体治理 + 项目决策记录：四份设计落地**（PM「把已确定的设计直接落地实现 → 完整 review → 更新文档」）：

- **解 PM 在消费仓 `ExampleAgentProject` 实证的四痛**：①轻档（main 直接改 / 聊定直落，不进 req）漏沉淀 ②脊柱入口（PRODUCT-STATE 索引）看不到一半实存文档 ③成熟决策困在讨论稿、脊柱无指针 ④mock 探索变体集体孤儿找不回。根因：沉淀只有一个机器开火点 = close-req 末尾，而 PM 真实用法是**分档**的、最轻那档绕过唯一开火点 = 结构性失明。
- **落地的设计**（§0 锁 + §1 抠定 + Round1 review 0 真 High）：`分档运行与沉淀层`（umbrella）+ `文档治理与知识棘轮` + `项目奠基决策记录` + `stage编号清理与banner去号`（机械清理）。**build 直建轻车道未落地**——其 §X 4 条 High（信封↔task 状态机冲突 / close-task merge-back 崩 / 字段契约脊柱无归宿）动代码前必填、尚未在设计正文落定，本轮排除。
- **核心交付**：新 skill `/pmai-deposit`（轻档轻沉淀，skill 数 22→23）+ 四类分流单一真相源 `_shared/deposit-routing.md` + 项目决策记录冻结档（`decision-record.md.tmpl` + `_shared/decision-record.md` + 三触发点）+ mock 变体治理子系统（`gen-mock-board.py` + `mocks/` 脚手架）+ 文档地图（脊柱两层读取模型）+ 索引漂移检测 + `check-branch.sh` GATE 3 轻沉淀合法写入口（marker 门控 + mocks/decisions 豁免）。
- **PM 拍板项**：F2 = 新建 `/pmai-deposit`（vs 挂 quick-fix）；R5 = `docs/decisions/` + 类名「项目决策记录」。
- **review**：2 个独立对抗子 agent（闭痛+保真 / 机制可用性+防再绕开），强读代码 + 端到端走查。审出并修：project-solution 写 decisions 被 GATE 3 拦（→ decisions/* 设无条件可写 + 不写 PRODUCT-STATE 索引保防腐）、manifest 中英文 key 漂移（→ 钉英文 key + gen-mock-board 报警）、mocks/ 跨分支（→ close-req 退役改 main 做）、marker 悬挂（→ deposit 入口清陈旧）、2 个 stale stage-6 fixture（stage 清理 blast radius 漏网，→ 修断言）。
- **测试基线 588 / 0**（前 572/0 → 本轮 +mock 子系统 7 + GATE 3 沉淀分档 5 + 修 2 stale fixture）。**所有改动未 commit，工作树待 PM 总审**。
- **下一步**：① PM 总审本轮 diff + 决定是否 commit + 是否把 4 份落地设计 `git mv` 进 `docs/归档/完成/` ② **整理消费仓 `ExampleAgentProject` 让它能通过框架跑起来**（R4 迁移练兵：拿真实四痛场景走一遍分档沉淀逐痛核对）。memory `project_build_fidelity_two_causes` / `feedback_dont_design_around_bypass`。

---

**2026-05-31 — gstack-review 审 `reshape-office-hours` 全工作产出 + 修复**（PM 调 `/gstack-review`：5 specialist 并行 + Codex 跨模型对抗审，多源交叉确认）：

- **审出 4 个 P0（破坏 reshape 头号特性）+ 5 P1 + 6 P2，全部修复；后按 PM 授权处理 5 个 deferred 项。基线 543 → 579 →（退役 speed mode 删 14）565 →（build-audits +7）572/0**：
  - P0-1 沉淀死路：`close-req.sh` stage 门卡 `!= "7"`（六步沉淀=4）→ 永远关不掉 → 改 4 + fixture。
  - P0-2 脊柱没建：`init-project.sh` template case 默认 `*) continue` 跳过 PRODUCT-STATE/DESIGN → 补 case 铺到 `docs/`。
  - P0-3 外部执行器全崩：`_gate.sh` `$MAIN_REPO_ROOT/$HOME` 路径翻倍 + `$transition_py）` set-u unbound → BASH_SOURCE 解析 + `${}` + test-executors 进 run-all。
  - P0-4 迁移锁死旧 stage-4 active：no-op 跳过 + active stage∈{3,4} 歧义警告。
  - P1/P2：脊柱读路径 docs/ 前缀 + `$MAIN_REPO_ROOT`→`$REPO_ROOT` / task-plan.md.tmpl 六步对齐 / 多窗口 prose 收单窗口 / checks-diff 路径穿越+畸形+假无差异 / discard worktree 路径问 git / lock 失败告警 / status-view suggest_next_action 转六步。
- **复盘沉淀** memory `feedback_stage_refactor_review_blast_radius`（SKILL prose 改≠落地；审 stage 重构必查底层 .sh stage 门 + fixture + init case + 共享 gate）。
- **deferred 项（PM 授权 AI 判断后处理）**：① 退役 speed mode 子系统（坍缩后驱动 req-stage-gate 编排已删 → 残件 stage6_summary/--stage6-entry/决策类型列/test-speed-mode 全死，已清）② close-task ② 视觉段定位容错两种 DESIGN 结构（gstack 英文段 / 模板中文「一、视觉基调」）③ prototype-README 改 create-next-app 之后写（避目录冲突）④ deliverables-INDEX 确认已 lazy 创建、不改 ⑤ **build 三道审脚本级编排落地**（PM 让继续后做）：新增 `scripts/build-audits.py`（resolve 校验输入 + synthesize 收齐三道 + 合成 + 门禁），接线进 task-execute 步骤 7.3，回归 7 例。**剩真 req build spike 端到端验证**。

---

**2026-05-29 — PMAI 重构方向（office-hours 收敛）：方案定盘 → 已落地**（PM 跑 `/gstack-office-hours` 诊断"框架用着不顺、出的第一版原型不如直接给 AI"；全程取证 + 5 视角对抗审 + 真实 A/B spike 收敛出重构方向。**这是方向性反转、范围远超单个 feature**）：

- **核心**：砍 7-stage 固定流水线 + 每段全文确认门 → 坍缩成**六步**（①上下文脊柱 ②范围确认 ③栈内 build ④三道审 ⑤体验迭代 ⑥沉淀）；想 / 建原型交 Claude Code 在栈内直连、零录入，PMAI 缩成**上下文脊柱 + 范围确认 + 沉淀**层。
- **真相源**：方向 = `docs/设计/PMAI重构方向-office-hours收敛.md`（§2.3.1 范围确认 / §2.3.2 复审沉淀 / 两不变量 / 证据 / 决议日志）；落地 = `docs/设计/PMAI重构-实施清单.md`（skill 去留 / gstack 接入 / worktree / 基础设施 / **D1-D10 全拍定** / §7 新 scope）；决策快照 memory `project_pmai_reshape_direction`。
- **关键决策（全 PM 拍板）**：D1 六步反转 · D2 task 降后台留名（mode 中立）· D3 PRODUCT-STATE = 现状层 hub · D4 实现深度 mode 按层挂靠（复用现成 `工程结构约束-{prototype,system,custom}`）· D5 prototype 默认 Next.js+shadcn · D6 实现文档 = per-req `req-plan.md` · D8 worktree 自动托管早上 + spike · 附件机制保留 + rewire · §7（站点爬·对齐线上·覆盖审计 checks-JSON·产物层 deliverables）。
- **状态**：落地大体完成（六步引擎 + 22 skill 级联 + 执行器可插拔 + 并行 build/worktree lock + checks-diff 引擎 + 旧 req 迁移 + §7.A/B/C/D 全提交）。**2026-05-31 gstack-review 审当前分支全工作产出，审出并修 4 个 P0 + 全部 P1/P2**（见下「2026-05-31」段）。**测试基线 572 / 0**（旧记 533/548/525/579/565 全过期，以此为准）。

**重构落地进度（branch `reshape-office-hours`）**：
- ✅ 阶段1 增量脊柱：`PRODUCT-STATE.md.tmpl` / `req-plan.md.tmpl` / `DESIGN.md.tmpl` / `prototype-README.md.tmpl` 模板 + `coverage-reviewer` agent（均已提交、548 绿、尚未接线）
- ✅ plan-eng-review 跑完（PM 拍：自动托管 spike 加固复现 2026-04-22 事故 / 六步坍缩先迁移测试；落点进实施清单 §6）
- ✅ 六步坍缩盘点：stages.py（两 dict）+ req-transition.py（推进引擎）+ status-view/state（6+ 处 STAGE_NAMES）+ 7 个 stage 专属测试 全摸清
- ✅ **#9 六步坍缩引擎**（411b568）：`stages.py` 7-stage→四阶段（1 范围确认/2 build/3 复审/4 沉淀）+ `req-transition.py` 重写（MAX_STAGE=4、删 stage-4 跳过/prd-solution 前置/stage6-7 回退）+ 迁 3 测试套（删 8 个 7-stage 独有用例），**548→540 全绿、已提交**
- ✅ **#10 六步级联**（17710cd，workflow 19 agent + 收口）：砍 req-stage-gate→壳 / 新建 `skills/next` (/pmai-next 驱动) / 降后台 6 / 改造 7（init·new-req·task-plan·task-execute·task-status·close-req·prd-writing）/ 合并 2 / _shared 同步；迁删钉旧机制测试。**540→533 全绿、已提交**
- ✅ **#3 init-project / #4 new-req / #6 入口收敛+next**：随级联落地
- ✅ **已补**：attachments stage_prefix→req-plan rewire（helper 已动）；status-view `suggest_next_action` 转六步产品轴；banner `/{MAX_STAGE}`；§7.A/B/C/D。
- ✅ **build 三道审脚本级编排**：`scripts/build-audits.py`（resolve + synthesize）已固化「校验输入 + 收齐三道 + 合成一份 + 门禁」，接线进 task-execute 步骤 7.3（覆盖审计 agent / 视觉门 gstack skill 仍 LLM 调起，脚本管编排）。
- ⏳ **余下未做（唯一）**：build 三道审 + 自动托管的**真 req build spike 端到端验证**（脚本编排 + coverage-reviewer/design-review/task-verify 产 conformant 结果 + dev server 复用 timing，在真实需求上跑一遍验闭环）。
- ✅ **阶段2 核心押注已验证**：A/B spike `ExampleAgentProject-pathB`（Next.js15+React19+17 组件栈内真构建），PM 判"整体相近、Claude Code 配 skill 能逼近"（方向稿 §X-C）。build 纪律机制（DESIGN 正向约束+三道审+coverage-reviewer）已在级联实现。**非 blocker**（一度误列已纠）
- **#8 自动托管拆两半**：前半（自动建/merge/删省机械活）已 prose 化（task-confirm/close-task 降后台 + /pmai-next 驱动），端到端待真 req 跑；**后半（状态物化硬加固）防的 2026-04-22 并行多 task 串台，在六步顺序 demo 流程下大概率不复存在 → 先不做、并行多 task 才重启**（已记 TODOS v2）
- **⚠️ 消费仓同步**：attachments rewire / CLAUDE.md.tmpl 六步重写 / 旧 req 迁移脚本（`migrate-reqs-to-6step.py`，含 active stage∈{3,4} 歧义警告）均已落地；剩 build 三道审脚本级编排待补；在飞旧 req 同步前先跑一次迁移脚本解越界（见 TODOS）
- 详细任务看 TaskList（10 项完成 9，仅 #8 后半按判断"先不做"）

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

**下一步（2026-05-31 起）**：

review 修复 diff 已审、已提交（`e0792fa` 4 P0 + P1/P2 + deferred + `b3527fc` 二轮完整性缺口；工作树干净，基线 572/0）。

**build spike 部分验证完成（2026-05-31）**：搭最小消费沙盒（`/tmp/pmai-spike-sandbox`：脊柱 + req-plan 范围清单 9 项 + 真 Next.js prototype，**故意埋 1 个降级占位 + 2 个漏建**）跑了一遍六步「建」后半截编排：
- ✅ **resolve**：输入校验通过、建 `audits/`、打印三道 manifest、YAML block-list 端口解析对（3000/5173，且无 PyYAML 走手写 fallback）。
- ✅ **覆盖审计真跑**：`coverage-reviewer` agent **独立读码硬 diff**，准确揪出角色 tab 空 `onClick` = degraded、状态筛选 = missing、`/users/[id]` 详情页 = missing（built 6 / degraded 1 / missing 2），未被 task 描述带偏。
- ✅ **synthesize + gate**：合成 `synthesis.md`（PM 视图无工程黑话）+ 机器 summary 计数零误差 + gate 正确判 needs-review。
- ✅ **fail-loud 防漏跑**：藏掉 coverage.json → exit 2 + stderr 点名缺哪道，不静默合成。
- ✅ 回归 `test-build-audits.sh` 7/7 全绿。
- ⏳ **仍待真 req 验证**（本 spike 按「编排+覆盖审计真跑」档，未起浏览器）：视觉门 `/design-review` + 行为审 `/browse` 的**真实浏览器链路** + dev server 真复用 timing + worktree 自动托管 fork/merge/删闭环。本 spike 这两道用的是 conformant 造值，只验编排不验浏览器质量。

余下：
1. **真 req build spike（浏览器链路那半截）**：在一个真实需求上把视觉门 / 行为审用真 gstack 工具实跑 + dev server 真复用 + 自动托管闭环走一遍（编排 + 覆盖审计已验，差浏览器侧）。
2. 消费仓同步：在飞旧 req 先跑 `migrate-reqs-to-6step.py` 解越界（按歧义警告手工确认 active stage 3/4 的 req）。

**旧 speed mode = 已退役**（2026-05-31，PM 授权判断）：7-stage 优化，坍缩后驱动 `req-stage-gate` 编排已删，残件（`stage6_summary.py` / `--stage6-entry` / 决策类型列 / `test-speed-mode.sh`）全清。

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

> 继续 PM-AI-Workflow。读 RUNTIME.md「当前位置」——**框架瘦身改造（吸收 ExampleAgentProject 设计方法）已整体 merge 进 `main`**（merge `135c3f7`，2026-06-21）：lifecycle 迁移（取消 `requirements/` 树 → `docs/modules/<模块>/.req-meta.json`，新增 I-MOD1）+ 工作方法论纠错 A-D + 新 skill（design/mock/build/close/status）+ 方法论（info-design/req-questioning/anti-cut-check）+ 规格语言风格标准。**测试基线 601/0**，工作树干净。真相源：`docs/设计/lifecycle迁移计划.md` + `docs/设计/工作方法论与工作流-总纲.md`；更早的重构方向 `PMAI重构方向-office-hours收敛.md`（D1-D10）+ memory `project_pmai_reshape_direction`。下一步看「下一步」段：CHANGELOG 整段仍「未发布」（消费仓同步待决）/ 真 req build spike 浏览器链路 / ExampleAgentProject 迁移练兵。

AI 收到后应该：
1. 读本文件「当前位置」2026-06-22 段（reshape 瘦身改造 merge）确认现状；更早的重构方向决策见 2026-05-29 段 + 两份设计文档
2. 看「下一步」段决定做什么；merge 已进 main、工作树干净
3. **改框架资产先看 CHANGELOG 未发布段**了解已落地的近期改动，避免重复/冲突
