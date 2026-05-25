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

## 当前位置（2026-05-25）

**D-iv M1 init-project 一气呵成落地中**（批 1，6 个 vp，~4.8h 总；当前 vp-1 + vp-2 已落，vp-3 verify pass）

设计文档 `docs/设计/入口与全流程体验顺畅性.md` v0.2（plan-eng-review Round 1 完整跑过：claude 9 finding + codex outside voice 7 finding，16 ACCEPT；最大改动是 codex C-1 砍掉 M3 整模块 —— `req-stage-gate` 续跑模式已是默认行为，M3 痛点 NULL）。批 1 ship 后批 2（M2 banner + M4 askuser + M5 session 播报）按 PM 拍板再启。

**已落（commits 6df9cf4 + dcf5802）**：

- **vp-1**：`skills/init-project/SKILL.md` 重写 4 阶段（A 参数 5 步 + brownfield 检测 → B 骨架 → C QUESTIONING @读 `_shared/project-questioning.md` + Decision gate + atomic commit → D Next Up 只汇总）+ 顶部 ASCII 流程图 + 失败兜底速查（R10/R11）；`scripts/init-project.sh` 删 echo "下一步：/new-req"（保留非交互参数化 CLI 入口 invariant）
- **vp-2**：新建 `skills/_shared/project-questioning.md`（253 行，单一真相源 —— §1-§10 含提问纪律 / 问题库 / 写作规则 / Decision gate 模板 / 6 节检查 / atomic commit）+ `/project-solution` SKILL.md 238→158 行（瘦身 33%）改 @读 + 加 4 场景判断框架 + frontmatter 更新；init-project SKILL.md 阶段 C 内嵌 Decision gate 选项副本改为 @读 §6.2 引用
- **vp-3**：阶段 D「只汇总不 commit」由 vp-1 SKILL.md 已写对，verify pass，无单独 commit

**测试基线**：`bash tests/run-all.sh` **425 / 0**（D-iii v2 落地基线维持，vp-1/vp-2 无回归）。

**剩余 vp**：

- **vp-4**：文档同步 ← **进行中**（README 快速开始改单步 / Skill 汇总表移 `/init-project` / RUNTIME 更新 / CHANGELOG）
- **vp-5a**：自动化测试（`test-brownfield-detect.sh` / `test-no-duplicate-questioning.sh` / `test-shared-files-exist.sh`，期望基线 425 → 428）
- **vp-5b**：PM 手动端到端验收 + measure-tthw 计时 + 4 场景对比一致性
- **vp-6**：`/project-solution` 4 场景定位强化（frontmatter / When To Use 重写；vp-2 已加 4 场景框架，vp-6 细化场景特定提问顺序）

**下一步**：vp-4 完成（RUNTIME + CHANGELOG）→ vp-5a 自动化测试 → vp-6 → vp-5b PM 验收 → 批 1 完毕 → PM 拍板批 2 是否启 / 何时启。

---

## 历史阶段（已完成）

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
- **vp-2 + vp-3**：`req-stage-gate` Stage 1→2 重写为合二为一选择门 + 分流 A（结构化批判 `/req-analysis`）/ B（YC office-hours 式 + bridge snapshot 复制）；B 分支 resume 协议（PM 中断 chat 去跑 office-hours → 任意句式回话 AI 接住 → snapshot + helper 写元数据）
- **vp-2b**：`/new-req` 砍选项 1（"自跑 /office-hours 整理 brief"）；office-hours 边界单点收敛到 Stage 2 stage-gate 入口
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

> 继续 PM-AI-Workflow。读 RUNTIME.md「当前位置」确认 D-iv M1 vp-1+vp-2 已落（425/0），告诉我下一步要做什么（vp-4 / vp-5a / vp-5b / vp-6 / 批 2）。

AI 收到后应该：
1. 读本文件「当前位置」确认 D-iv M1 当前进度（vp-1/vp-2 已落 / vp-3 verify pass / vp-4-6 剩余）
2. 等 PM 给具体方向（接着跑剩余 vp / 跑消费仓验证 / 启批 2 / 暂停）
3. 不擅自启新阶段
