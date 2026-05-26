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

### 2026-05-26 — D-iv v0.3 patch F1：req-stage-gate 续跑模式概念收敛

- `skills/req-stage-gate/SKILL.md` 续跑模式段顶部加 TL;DR 1 句话答案（"PM 只敲 1 次，AI 自动续跑 stage 1→6"）；详细规则（2 个退出条件 / 不是退出条件 / 核心边界 15 行）折叠进 `<details>`；保留"PM chat 输出格式"段不折叠（AI 执行指引，不能藏）
- 修审计 F1：新手 PM 在 35 行铺垫中找"敲一次还是每 stage 敲一次"的答案，TL;DR 直接 1 行给出
- 无新增测试（纯文档结构调整）；测试基线 460/0 持平

### 2026-05-25 — D-iv v0.3 patch：新手 PM 视角审计 3 BLOCKER 直修

**触发**：subagent 模拟新手 PM 走完整 init→new-req→stage-gate→task→close 流程，报 3 BLOCKER + 3 FRICTION。3 BLOCKER 已 verify 为真，本次直修。

**改动**：
- `skills/task-confirm/SKILL.md` 顶部指针删「执行前确认闸门 label」（与 body 行 23-25 delta-3 §2.3「不再设确认闸门」自相矛盾，原是 vp-8 后期加指针时未同步 body）
- 5 个用户面 SKILL Preamble 段（new-req / req-stage-gate / task-confirm / close-task / close-req）加 `python3 .claude/scripts/status-view.py --banner-only --skill X || true` —— banner 真在 body 里调用，不只是顶部 prose 指针
- 2 个 SKILL（init-project / task-execute）用字面值 `echo "━━━ PMAI ► ..."` —— init-project 是项目级（生成器仓内跑、无 active req），task-execute 入口前置阶段尚未 cd 到 task worktree
- `scripts/status-view.py:render_banner_only` 无 active req 文案由「先跑 /new-req」改通用「<项目级 / 无 active req>」（对 /init-project 不再误导）
- 7 SKILL 退出文案补 `▶ Next Up` 关键词（task-confirm 行 206 ▶️→▶ + new-req 步骤 5 handoff + req-stage-gate 退出 + task-execute 步骤 12 通过分支 + close-task Phase 1→2 + close-req Phase 1→2 + close-req Phase 2 终态）
- `close-task` Phase 1→2 / `close-req` Phase 1→2 切窗口给完整可复制命令（"窗口还开着直接切 / 窗口已关用 cd + claude" 两条路径）
- `skills/req-stage-gate/SKILL.md` stage 6→7 blocked 错误信息扩展「废弃 task 三步」可复制命令链（mv 到 tasks/discarded/ + 改 task-plan.md `## 变更记录` + 加 task 文件「废弃理由」段），堵 PM 手动跳 task 时 metadata 不一致风险
- `skills/_shared/pm-view/banner-rules.md` 新加 §3.0 适用范围 —— §3 3 硬规则**只管 AskUserQuestion picker 形式**闸门（GUI 选项卡片），续跑模式 + chat 自由对话走常规形态不受 §3 约束（4 行判定表覆盖典型场景）。修 D-iv vp-7/8 上线后留下的"§3 vs 续跑模式互斥" tension
- `skills/req-stage-gate/SKILL.md` Stage 1→2 分流 B `gstack-slug` 解析改 fail-loud —— 旧 `SLUG="unknown"` silent fallback 让 PM 误以为"没探测到 office-hours 产物"（实际是 slug 没解析对）；新代码拆三态 (I) slug 失败显式告 PM 原因 (II) slug OK 找到 (III) slug OK 没找到
- `tests/test-banner-label.sh` 新增 T6-T10（7 SKILL body 真调 banner / 退出处含 ▶ Next Up / task-confirm 不矛盾 / §3.0 适用范围 / slug fail-loud）防回归

**业务仓需注意**：
- 同步后每个 SKILL 入口都会打 banner（`━━━ PMAI ► SKILL ▸ <stage> ━━━`），PM 切窗口回来不再"失忆"
- `/close-task` Phase 1 完成后 chat 输出有完整 cd 命令；`/close-req` 同
- 跳 task 三步走（不再是含糊的"从 task-plan.md 删除该条"）
- **未新建** `/cancel-task` skill —— PM 实际跳 task 频率不高，三步手动可接受；若消费仓验证发现频繁要跳，再开新 vp 做 skill
- **§3 适用范围**：以前 vp-7/8 引导 SKILL 顶部写「闸门 label 按 §3」是过度承诺；现在明确只 AskUserQuestion picker 形式才走 §3，chat 自由对话不受约束。SKILL.md 顶部 prose 指针该词原文不动（仍引用 §3），但消费方应按 §3.0 适用范围判定
- **office-hours slug fail-loud**：消费仓若没装 gstack 或本项目未 gstack 注册，跑到 Stage 1→2 office-hours 分流时会显式报错（不再误说"没探测到产物"），PM 看到 stderr 原文知道是 slug 解析失败、直接走指定路径 / 切结构化批判分流

**测试基线**：`bash tests/run-all.sh` **460 / 0**（前 455/0 + 本次新增 5 case；无回归）

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

### 2026-05-25 — fix: cleanup-pending-worktrees.sh L245 潜伏 unbound variable bug

**症状**：`tests/test-cleanup-pending.sh` C7 safety case fail —— 当存在 unsafe pending entry 时，脚本应 `exit 1` 并报警 "有未清理项保留..."，实际 exit 0 且警告残缺。

**根因**：L245 `echo "⚠️ 有未清理项保留在 $PENDING_FILE。请人工检查。"` —— `$PENDING_FILE` 紧跟中文句号 "。"（U+3002 UTF-8 三字节 e3 80 82），bash 在某些 locale 下 parse `$VAR` 时把后续 UTF-8 字节当变量名一部分，触发 `set -u` 抛 `PENDING_FILE�: unbound variable`；但因为该 `echo` 在 `if [ "$FAIL" -gt 0 ]` 分支内，错误吞掉后脚本 fall-through 到 fi 结束自然 exit 0（应该 exit 1）。

**潜伏时长**：bug 由 fcdf01e（2026-04-26）引入，但当时所有 test case 都走 happy path（FAIL=0 不进入此分支）；35cf17f（2026-05-25 harden workflow safety boundaries）加 C7 case 第一次造 FAIL>0 场景才暴露。

**修法**：`$PENDING_FILE` → `${PENDING_FILE}` 显式终结变量名边界。1 字符改动。

**测试基线**：`bash tests/run-all.sh` **455 / 0**（C7 修复 + 上条 task-status fix 2 个新 case 都过；不再有 pre-existing fail）。

---

### 2026-05-25 — fix: task 状态查询 vs v4.5 task md 单分支独占的 inconsistency

**问题**：v4.5 设计 task-confirm fork 后 `git rm` task md 从 req 分支（搬到 task 分支独家），但 `list_tasks()` 和 `/task-execute` 入口的 find 命令都只扫 req 分支视角，导致：

- **dangerous default**：`/task-status` 在 req 窗口扫不到已 fork 的 task → 错误推荐 `/close-req`；如果 PM 信了会**误关一个还有 task 待执行的 req**
- PM 在 req 窗口 `ls tasks/` 看不到 task md → AI 误判 "task 还没产" → 让 PM 重跑 `/task-spec` 浪费时间
- `/task-execute task-NNN`（短 ID）模式 find 扫不到 task-* worktree → 在已 confirm 的 task 上误报 "0 个匹配"

PM 在 example-consumer-app 真实跑出来证实了 `/task-status` 漏报 task-002，决定直接修而非起 D-v 设计 doc。

**修法**（example-consumer-app AI 给的 A 方案 ≈ 扫描机制扩展）：

- `scripts/_lib/state.py:list_tasks(req_dir, repo_root=None)`：加可选 repo_root 参数；传入时扫 `.worktrees/task-*/requirements/active/<req-id>/tasks/` 合并去重，同 task-id 优先 task 分支版（active 状态优于 req 分支 archived 状态）；不传 repo_root 保持旧行为（向后兼容）
- `scripts/_lib/state.py:get_overall_state()` 内部调用改传 repo_root（所有 status-view render_* 入口自动受益）
- `scripts/status-view.py` render_timeline 两处直接 list_tasks 调用补传 repo_root
- `skills/task-execute/SKILL.md` 入口步骤 1：短 ID + 无参两种模式的 find 命令扩到 `.worktrees/task-*/requirements/active`；加 v4.5 注释说明 fork 后 task md 在 task 分支独家
- `scripts/_lib/state_test.py:TestListTasks` 加 2 case：worktree_fallback_finds_task_branch_only_md / task_branch_md_preferred_over_req_branch

**业务仓需注意**：同步本修后 `/task-status` 在 req 窗口能正确看到已 fork 待执行的 task；可信任 status-view 给出的"下一步"建议（之前 PM 必须 `git worktree list` 手工核对）。

**测试基线**：`bash tests/run-all.sh` **454 pass / 1 fail**。fail 是 `test-cleanup-pending.sh` C7 safety case，**pre-existing**（stash 本次改动后跑仍 fail，与本次无关，另行追踪）。本次新增 2 case 全过（worktree_fallback_finds_task_branch_only_md / task_branch_md_preferred_over_req_branch）。

---

### 2026-05-25 — D-iv ship 后审计修复（漏改指针 + 死链 + 文档基线对齐）

新窗口连续大改后的隐性问题扫查（PM 主动发起），修以下 3 处：

- **askuser-rules 指针漏改**：vp-10 批量加指针时只覆盖 7 个核心 SKILL，遗漏 `skill-improve` + `task-submit`（两者都用 AskUserQuestion 走 PM 决策）。按 `_shared/pm-view/askuser-rules.md` §3.1 模板补齐 SKILL.md 顶部 blockquote。
- **死链 2 处**：
  - `RUNTIME.md` L18 写 `docs/设计/入口与全流程体验顺畅性.md` —— 实际已 `git mv` 到 `docs/归档/完成/`
  - `scripts/_lib/stages.py` L32 注释引 `docs/设计/Stage2-分析方式选择-office-hours.md` —— 实际归档为 `office-hours-跨stage1-2集成.md`
- **基线状态漂移**：`RUNTIME.md` L37 停留在 vp-12 commit 前的「期望 ~446，待跑」未完成态；实测 446/0 后改为「实测无回归」与 L129 / INDEX / CHANGELOG L105 对齐。

**业务仓需注意**：4 文件改动小范围，按 `框架同步-SOP.md` 跟随主仓 sync 即可。`skill-improve` + `task-submit` SKILL.md 同步后 PM 视觉上多 1 行 blockquote；功能上 agent 调 AskUser 严格按 §1 3 硬规则走。

**测试基线**：`bash tests/run-all.sh` **446/0**（实测无回归；4 文件改动均非测试覆盖路径）。

---

### 2026-05-25 — D-iv 入口与全流程体验顺畅性 ship 收尾（设计文档归档）

D-iv 批 1 + 批 2 全包技术 vp（vp-1 ~ vp-12，**vp-9 砍**）落地完毕：

- M1 init-project 一气呵成（vp-1 ~ vp-6）
- M2 banner + Decision gate label（vp-7 + vp-8）
- M4 AskUser 严格化（vp-10）
- M5 session 起始播报（vp-11）
- 批 2 文档同步（vp-12）

**收尾动作**：

- 设计文档 `docs/设计/入口与全流程体验顺畅性.md` 加「已落地状态」段（7 commits + 测试基线 446/0 + PM 验收清单）
- `git mv docs/设计/入口与全流程体验顺畅性.md → docs/归档/完成/入口与全流程体验顺畅性.md`
- `docs/INDEX.md` 设计/段砍 D-iv 行 + 归档/完成/段加 D-iv 行
- `RUNTIME.md`「当前位置」改为 D-iv ship + 下一步同步消费仓 + PM 自验收

**PM 验收清单**（同步消费仓后跑；不阻塞 ship）：

- [ ] PM 本仓外起测试项目跑 `/init-project` 端到端
- [ ] PM 跑 `bash scripts/measure-tthw.sh` 计时（期望 ≤ 30 分钟）
- [ ] PM 跑 `/project-solution` 4 场景对比一致性
- [ ] PM 同步到 ExampleConsumerApp 跑真实 req 验 banner / Decision gate / askuser / narrative
- [ ] 验收 finding 回头开 D-iv v0.3 patch vp（如有）

**业务仓需注意**：同步本 ship 时按 `框架同步-SOP.md` 走；vp-1 ~ vp-12 累计 14 个文件改动 + 4 个新文件，建议同步前 grep 现状对比预期差异。

---

### 2026-05-25 — D-iv M1 批 2（M2 + M4 + M5）vp-7~vp-12 全包落地

批 1（M1 init-project 一气呵成）ship 完后**接着 ship 批 2**（横切普推 banner / askuser / session 播报）。**M3 砍后（codex C-1）批 2 5 个 vp**：vp-7/vp-8 M2 + vp-10 M4 + vp-11 M5 + vp-12 文档同步。注：**不引入 `--auto` 或 chain flag**（M3 砍 + codex C-2）。

**vp-7：M2 banner-rules.md + status-view 复用**（T7）

- 新建 `skills/_shared/pm-view/banner-rules.md`（M2 + Decision gate label 单一真相源）：
  - §1 阶段 banner 格式（`━━━ PMAI ► <SKILL> ▸ Stage <N>/<T>: <Name> ━━━`；纯 ASCII 80 字符固定宽度）
  - §2 Next Up 块格式（`## ▶ Next Up — <command> <hint>`）
  - §3 Decision gate label 3 硬规则（M3 砍后整合 M2）：label=动作描述 / description=一句话 / 留守选项 Loop 回路 + 禁用模糊词 "OK"/"Proceed"/"Continue"
  - §4 实施指南 + 失败兜底
- 改 `scripts/_lib/state.py`：暴露 `get_current_stage_banner(req_dir, skill)` 函数（按 banner-rules.md §1.1 格式 + STAGE_NAMES 中文 stage 名）
- 改 `scripts/status-view.py`：加 `--banner-only` 模式 + `--skill` 参数 + `render_banner_only()` 函数（active req → banner / 无 active req → 占位 banner）

**vp-8：M2 banner + Decision gate label 全仓落地**（T8）

- 7 个核心 SKILL 顶部加 banner-rules 指针块（最小改动，不重写 SKILL.md 整体）：`init-project` / `new-req` / `req-stage-gate` / `task-confirm` / `task-execute` / `close-task` / `close-req`
- 新建 `tests/test-banner-label.sh`（5 cases）：
  - T1 7 个核心 SKILL 都引用 banner-rules.md
  - T2 banner-rules.md 含 §3 3 硬规则
  - T3 banner-rules.md 含禁用模糊词清单（OK / Proceed / Continue）
  - T4 `_lib/state.py` 暴露 `get_current_stage_banner`
  - T5 `status-view.py` 含 `--banner-only` 模式

**vp-10：M4 askuser-rules.md + 7 skill 加指针**（T9）

- 新建 `skills/_shared/pm-view/askuser-rules.md`（M4 单一真相源，gsd `#3018 failure mode` 照搬）：
  - §1 3 硬规则：① 空答/没答 → STOP wait next message 不重试不默认 ② 没拿到答案前禁止落盘 artifact ③ runtime 不支持时退化编号列表，仍 wait
  - §2 不在 scope：M4.1 / M4.2 / M4.3（禁逃生舱）
  - §3 实施指南（SKILL 顶部加引用 + 闸门类 AskUser 同时遵守 banner-rules §3）
- 7 个核心 SKILL 顶部加 askuser-rules 指针块（同 vp-8 7 个 SKILL）

**vp-11：M5 status-view --narrative + CLAUDE.md 章程**（T10）

- 改 `scripts/status-view.py`：加 `--narrative` 模式 + `render_narrative()` 函数
  - 范围降级（codex C-4）：当前 stage / 产物文件 / 最近 stage transition；**不到小节级**（不写「§四」/ commit hash 全文 / 「N 天前」相对时间）
  - 无 active req → 输出"目前没有 active req"，不编造（review R7 防幻觉）
- 改 `CLAUDE.md` 加章程章节「Session 起始播报」：
  - **PM 第一条 message 后**（codex C-3 校准描述：不是「PM 一开窗口」；LLM chat 模型固有限制）AI 必须先跑 `bash .claude/scripts/status-view.py --narrative` 输出播报，再回应 PM 请求
  - 生成器仓 vs 业务仓约束：本规则只在业务仓有 `.req-meta.json` 时生效
- 新建 `tests/test-narrative-mode.sh`（5 cases）：
  - T1 `--narrative` argparse 参数存在
  - T2 `render_narrative` 函数定义
  - T3 `render_banner_only` 函数定义（vp-7 同时验证）
  - T4 CLAUDE.md 含「Session 起始播报」章节 + 「PM 第一条 message 后」表述 + status-view.py --narrative 调用
  - T5 `render_narrative` 不含小节级 / commit hash / 「N 天前」字串（codex C-4 范围降级）

**vp-12：批 2 文档同步**（本条目；测试基线后置跑）

- `RUNTIME.md`「当前位置」批 2 落地（M3 砍批 2 5 vp 全完成）
- `CHANGELOG.md`「未发布」段加 vp-7~vp-12 条目（本条目）
- 跑 `tests/run-all.sh` 确认无回归

**业务仓需注意**：

- 同步后 7 个核心 SKILL 顶部多 2 行指针引用 `_shared/pm-view/banner-rules.md` + `askuser-rules.md`，PM 视觉上变化是 SKILL.md 前面多几行 markdown blockquote；功能上 agent 调 AskUserQuestion 严格按 askuser-rules.md §1 + Decision gate 按 banner-rules.md §3 走
- `status-view.py` 三个新模式：`--banner-only` / `--narrative` 不影响现有 list / summary / timeline 调用
- CLAUDE.md 加「Session 起始播报」章节：agent 在每个新 session 的 PM 第一条 message 后会先跑 narrative 播报；**不影响**当前 chat 内的后续 message

**M3 砍体现在批 2**：
- vp-9 整段砍（M3 闸门 Decision gate pattern 独立 vp → 合并到 vp-7/vp-8 M2 的 banner-rules.md §3）
- vp-12 描述**不含** `--auto` / chain flag / `auto_chain_active` 残留（codex C-2 文档自相矛盾修复完成）

**4 模块完整落地汇总**：M1（init-project 一气呵成）= vp-1 ~ vp-6 + M2（banner + Decision gate label）= vp-7 + vp-8 + M4（askuser 严格化）= vp-10 + M5（session 起始播报）= vp-11；批 2 文档同步 = vp-12；剩 vp-5b PM 手动验收 + vp-13 消费仓端到端 PM 手动跑（不可自动化）。

---

### 2026-05-25 — D-iv M1 vp-6：`/project-solution` 4 场景提问顺序细化

**vp-6 范围**（T6；review B1 + B 4 场景延伸）：vp-2 已经把 `/project-solution` SKILL.md 段 0 加了 4 场景判断**框架**（触发 / 输入态 / 提问顺序粗略描述）；vp-6 把提问顺序列**细化为具体的 5-7 步**，让实施时不需要每场景再想。

`skills/project-solution/SKILL.md`:

- frontmatter description 重写 4 场景描述（review B1 砍 E 后的 4 场景细化）：
  - A 项目方向重做（跑过几个 req 后发现产品定位偏了）
  - B 季度 / 半年规划（主动校准 PROJECT 6 节 + 重新排 roadmap）
  - C 老板 / 市场新方向（外部输入逼着改路线）
  - D brownfield 接入定方向（紧接 /codebase-audit 后跑）
- 段 0 场景判断表「提问顺序」列从粗略一句话改为**完整 5-7 步顺序**：
  - A 重做: 痛点诊断 → 定位 → 用户 → 路线 → 业务术语 → roadmap 重排
  - B 季度规划: 过去 roadmap 回顾 → 产品路线（新里程碑）→ roadmap → 业务术语增量（跳过定位 / 用户 / 技术栈）
  - C 新方向: 新方向 vs 现 PROJECT 差异 → 定位 → 用户 → 路线 → roadmap
  - D brownfield: 全文读 `docs/代码现状档.md` → 定位（codebase 反推 + PM 确认）→ 用户 → 路线 → 技术栈（codebase 抄）→ 业务术语 → roadmap
- 段 0 加通用约束（所有 4 场景都跑步骤 2 / 步骤 3 / 步骤 8 _shared 引用）

`skills/_shared/project-questioning.md`:

- §10.2 `vp-6 细化` placeholder 改为 `vp-6 已细化` + 加 4 场景顺序速查（指向 SKILL.md 段 0 完整表，避免双份维护）

**测试基线**：`bash tests/run-all.sh` **436/0**（无回归）。

**业务仓需注意**：

- `/project-solution` 4 场景全部走同一份 `_shared/project-questioning.md`（话术库 + 写作规则 + Decision gate 共享），但**提问顺序按场景定**（SKILL.md 段 0 表）
- D brownfield 场景必须先有 `docs/代码现状档.md`（`/codebase-audit` 产物），否则 step 0 失败
- A/B/C 场景前置须有 `docs/PROJECT.md`（greenfield 首次起项目要走 `/init-project` 一气呵成，不走 `/project-solution`）

**批 1（M1）至此 6 个 vp 全部完成**：vp-1（SKILL.md 4 阶段）+ vp-2（_shared 抽取）+ vp-3（阶段 D verify）+ vp-4（文档同步）+ vp-5a（自动化测试 +11 cases）+ vp-6（4 场景细化）；vp-5b PM 手动验收待 PM 自跑。

---

### 2026-05-25 — D-iv M1 vp-5a：3 个自动化测试套件落地（防回归）

**vp-5a 范围**（T5a；review T1 落实）：

- `tests/test-brownfield-detect.sh`（3 cases）：
  - T1 `init-project.sh` 已存在空目录 → 退出非 0 + stderr 含「目标目录已存在」
  - T2 `init-project.sh` 已存在含 `.git` 目录 → 同 T1（脚本不区分是否含 git，都拒）
  - T3 `init-project SKILL.md` 阶段 A 含 brownfield 描述 + `/codebase-audit` 引导 + 「两层都拦」接口约定（review C-7）
- `tests/test-no-duplicate-questioning.sh`（4 cases）：
  - T1 Decision gate 模板话术「我会开始写 .planning/PROJECT.md」只在 `_shared/project-questioning.md` 一处
  - T2 6 节齐不齐**完整调用代码块**（`PROJECT_STATE=$(python3 ...`）不出现在 `init-project` / `project-solution`（_shared + new-req legacy mini-fill 各持一份合法）
  - T3 `check-open-questions.py --require-section` 完整调用代码块只在 `_shared` 一处
  - T4 问题库典型话术「这个项目要解决什么核心问题」只在 `_shared` 一处
- `tests/test-shared-files-exist.sh`（4 cases）：
  - T1 `skills/_shared/project-questioning.md` 存在 + 含 §6 Decision gate + §5 写作规则
  - T2 `skills/_shared/PM-VIEW-RULES.md` 存在（7 个 skill 引用，防 R10）
  - T3 `skills/_shared/pm-view/` 目录存在 + 含 `.md` 子文件
  - T4 **前向链接完整性**：所有 SKILL.md 里 `@读 _shared/<path>.md` 引用 → 对应文件必须存在
- 3 个测试加进 `tests/run-all.sh`（test-init-project.sh 之后；test-tthw-smoke.sh 之前）

**测试基线**：`bash tests/run-all.sh` **425/0 → 436/0**（设计预期 +3，实际 +11；超出）。

**业务仓需注意**：

- 3 个新测试**仅检查框架自身一致性**（grep + assert 静态校验 + brownfield e2e），不依赖业务仓环境
- 未来改动 `_shared/project-questioning.md` 时，T4 引用完整性会自动验证（删了被引用的文件 → test fail）
- 改动 `init-project` / `project-solution` SKILL.md 时，T1/T2/T3 自动防止"反向把 _shared 内容复制回 SKILL.md"

---

### 2026-05-25 — D-iv M1 vp-3 + vp-4：阶段 D verify pass + 文档同步（README / RUNTIME / CHANGELOG）

**vp-3**（阶段 D 改"只汇总不 commit"）：vp-1 SKILL.md 已写对（"PROJECT.md / roadmap.md + commit 已在阶段 C 完成。阶段 D 只做终态输出"），verify pass，无单独 commit。

**vp-4**（文档同步，T4）：

- `README.md` § 快速开始 1：从 `bash scripts/init-project.sh ...` 直调 CLI 改为「PM 主动入口走 `/init-project` skill 一气呵成 4 阶段」（保留非交互 CLI 作 `measure-tthw` / smoke / 批量自动化的入口 invariant；review C-5）
- `README.md` § 完整 Skill 命令汇总：
  - `/init-project` 从「框架内部（PM 不直接用）」组**移到「启动新工作」组顶**（review B2）+ 加"(只在生成器仓里跑)"标记
  - `/project-solution` 描述更新为「项目方向规划：4 个独立场景（重做 / 季度规划 / 老板新方向 / brownfield 接入）」
  - 「框架内部」组留空（用 placeholder 行注明 `/init-project` 2026-05-25 后归入「启动新工作」）
- `RUNTIME.md`「当前位置」：D-iii v2 整段挪「历史阶段」，「当前位置」改写为 D-iv M1 vp-1/vp-2 落地 + vp-3 verify pass + 剩余 vp-4/5a/5b/6 清单
- `RUNTIME.md`「新窗口续接命令」：更新为 D-iv 进度（425/0 + vp 列表）
- `CHANGELOG.md`「未发布」段：本条目（vp-3 + vp-4 收尾）

**测试基线**：`bash tests/run-all.sh` **425/0**（无回归；文档改动不触动测试）。

---

### 2026-05-25 — D-iv M1 vp-2：`_shared/project-questioning.md` 抽取 + `/project-solution` 改 @读

**改造目标**：vp-1 让 `/init-project` 阶段 C 写为 `@读 _shared/project-questioning.md`，但该 `_shared` 文件还没创建（vp-1 commit 后 vp-2 commit 前手动跑 `/init-project` 阶段 C 会找不到 `_shared` 文件）。vp-2 创建该文件 + 把 `/project-solution` 现役 inline 提问法 / 写作规则改为 @读，让两个 skill 都引用同一份单一真相源。

**vp-2 范围**（M1 批 1 的第二个 vp；T2）：

- **新建** `skills/_shared/project-questioning.md`（253 行）：项目方向讨论的单一真相源
  - §1 调用方约定（init-project greenfield / project-solution 4 场景，调用方自己判断 + 自己排顺序）
  - §2 提问纪律（复用 `req-analysis` 提问法：分批 / 追问 / 收敛 / 编号作答）
  - §3 问题库（6 节 + 典型话术）
  - §4 未决问题闸门（暂存文件 `docs/.project-solution-open-questions.md` + `check-open-questions.py --require-section` + 禁逃生舱）
  - §5 写作规则（PROJECT.md 6 节模板 + roadmap.md 表头 + 产品路线节 vs roadmap 分工 + PM 视图规则）
  - §6 Decision gate 确认门（gsd Decision gate pattern 3 条硬规则 + AskUserQuestion 模板：「创建 PROJECT.md / 继续探索」+ Loop 回路）
  - §7 6 节齐不齐检查（`check-project-sections.py` + 禁逃生舱）
  - §8 PM 定稿展示模板
  - §9 atomic commit（gsd new-project Step 4 pattern：`docs: project direction settled`）
  - §10 调用方实现指南（§10.1 init-project greenfield / §10.2 project-solution 4 场景 vp-6 细化）
- **改** `skills/project-solution/SKILL.md`（238→158 行；瘦身 ~33%）：
  - frontmatter 更新（4 个独立调用场景 A/B/C/D；vp-6 后细化）
  - 加 § 段 0 场景判断（A 重做 / B 季度规划 / C 老板新方向 / D brownfield 接入）+ 提问顺序表（vp-6 细化）
  - 段 1 步骤 2/3 → @读 `_shared` §2/§3/§4
  - 段 2 步骤 4/5 → @读 `_shared` §5
  - 确认门步骤 7/8 → @读 `_shared` §6/§7/§8/§9
  - 步骤 6 精简 / 详细 / 混合模式选择保留（场景特定，不属 `_shared`）
  - Rules 加 ❌「重复 `_shared` 的提问法 / 5 组话术 / 写作规则」（必漂移）+ ✅ 段 0 场景判断
- **改** `skills/init-project/SKILL.md` 阶段 C 描述：把 inline Decision gate 选项副本改为「按 `_shared` §6.2，本 SKILL 不内嵌副本」（避免双份）

**单一真相源验证**：
- `Decision gate "创建 PROJECT.md / 继续探索"` 选项内容只在 `_shared/project-questioning.md:151-157` 一处定义；其他 SKILL 是说明性引用（不是 inline 副本）
- 6 节齐不齐检查 / 写作规则 / 提问纪律 / 问题库 / 未决问题闸门 全部只在 `_shared` 一处

**业务仓需注意**：
- `/project-solution` 行为不变（PM 视角依然走 4 段：场景判断 + 段 1 讨论 + 段 2 输出 + 确认门）；但内部走 @读 `_shared`，PM 不感知重构
- `/init-project` 阶段 C 现在可以跑（`_shared/project-questioning.md` 已存在）

**测试基线**：`bash tests/run-all.sh` **425/0**（无回归）。

---

### 2026-05-25 — D-iv M1 vp-1：`/init-project` skill 一气呵成 4 阶段重写（批 1 起手）

**改造目标**：`/init-project` 从"调 shell 脚本 + 提示 PM 下一步发 `/project-solution`"两步分裂入口，升级为 PM 主动一气呵成 4 阶段入口（参数 → 骨架 → 方向讨论 → Next Up）。

**vp-1 范围**（M1 批 1 的第一个 vp；T1）：

- 重写 `skills/init-project/SKILL.md`：
  - 顶部加 4 阶段 ASCII 流程图（review B3）
  - 阶段 A 明确 5 步参数顺序：项目名 → 落地路径 → **brownfield 检测闸门** → 一句话背景 → 项目意图（review A3）
  - **brownfield 接口约定**（review C-7）：skill 阶段 A 拒已存在目录 + 提示 `/codebase-audit`；脚本继续拒（两层都拦）
  - 阶段 B 用 Bash 调 `init-project.sh`（脚本作骨架构建器；non-interactive 入口 invariant 仍保留，review C-5）
  - 阶段 C @读 `_shared/project-questioning.md` 跑讨论（**vp-2 创建该 `_shared` 文件**）+ Decision gate 二选一 + atomic commit `docs: project direction settled`（review A5）
  - 阶段 D 只汇总不 commit（输出 Next Up 块格式）
  - 失败兜底速查（R10 init-project.sh 失败 / `_shared` 缺失；R11 PM 中途停清理）
- `scripts/init-project.sh`：
  - 删 `--help` 段末「成功后: cd <target-dir> / /new-req」echo + 加说明本脚本作 skill 阶段 B 调用 / 非交互 CLI 保留
  - 删脚本末尾 `下一步：cd $TARGET_DIR / 运行 /new-req` echo（入口语义已迁移到 `/init-project` skill）

**业务仓需注意**：
- 新建项目走 `/init-project` skill（**只在生成器仓里跑**，业务仓的 `/init-project` 不分发）—— skill 内嵌 4 阶段 agent 流程
- `init-project.sh` 仍是非交互参数化 CLI（`measure-tthw` / smoke / 批量自动化照旧调用，不受影响）
- vp-1 完成后 `_shared/project-questioning.md` 尚未创建 → vp-2 立刻接上；vp-1 commit 后 vp-2 commit 前 PM 不应该手动跑 `/init-project`（阶段 C 会找不到 `_shared` 文件）

**测试基线**：`bash tests/run-all.sh` **425/0**（无回归；`test-inject-structure.sh` "init-project SKILL 询问项目意图" case PASS 维持）。

---

### 2026-05-25 — D-iii v2：attachments AI 接管（helper-based，Model 2 — PM 不感知 attachments/ 目录）

**痛点**：PM 完全不知道现仓 attachments 机制（commit 65329d0 v0 落地）存在 —— 不知道路径 / 不知道如何上传 / 不知道后续 stage 能否读取。现有 trigger 1 / 2 都是 reactive（PM 主动提 / AI 写产出前扫），永远 silent 直到 PM "知道该说"，但 PM 没在任何 chat 看到过提示就永远学不到机制存在。根因 = **PM 视角 vs 工程视角错配**（与 D-i v4 "office-hours snapshot" 同款决策剧情）。

**方案**（设计 `docs/归档/完成/attachments-AI-接管.md` v2，落实 Codex outside voice Round 1 11 critical/high finding + Claude D1-D10 共 21 finding）：

1. **`scripts/_lib/attachments.py` 新建 helper-based 接管层**（与 D-i v4 `_lib.state.{get,set}_stage_source` 同款架构）：
   - `copy_attachment` / `register_attachment` / `list_attachments_seen` / `is_seen` / `remove_attachment` / `replace_attachment` 全套 API
   - **`SENSITIVE_PATH_PATTERNS` denylist**（12 个 pattern：`.env` / `.ssh/` / `.aws/` / `token` / `credential` 等）→ 命中 raise `SensitivePathError`
   - **`MAX_FILE_SIZE_MB = 50` hard cap** → 命中 raise `FileSizeError`，不依赖 pre-commit warn fail-open
   - Python `shutil.copy2` + `Path.expanduser()`（不靠 Bash cp）
2. **`.req-meta.json:attachments_seen` 字段约定** —— 状态真相源（与 D-i v4 `stage{N}_source` 同 meta）；引用 section 仅作 PM 可见展示
3. **`skills/_shared/pm-view/attachments-upload.md` 新建**单一真相源 prose（trigger 0 LLM 识别 + caller 调 helper + multi-batch / 替换 / 删除 / 冲突 / 失败兜底 + stage 前缀映射 + office-hours C4 边界）
4. **7 stage SKILL 加 trigger 0 inline 段**：new-req / req-analysis / prd-writing / task-spec / req-stage-gate / **implementation-design** / **task-plan**（最后两个 Codex C2 新增）
5. **`req-stage-gate` Stage 1→2 B 分支 trigger 0 disable**（C4 cross-design 冲突防护）：B 分支选 office-hours 源材料期间 PM 给的绝对路径走 `set_stage_source(tool='office-hours', origin=...)`（D-i v4 路径），**不**调 attachments helper
6. **`new-req` 步骤 4.5 commit pathspec 扩 `attachments/`**（C1 fix 破 I-DC1 dispatch 前 working tree 必须 clean 边界）
7. **`INVARIANTS.md` 立 I-RT10**（attachments_seen 字段 + helper-only + denylist + hard cap + B 分支 trigger 0 disable 边界）

**改动**（vp-1 → vp-7，~3.5h）：

- **vp-1**：`scripts/_lib/attachments.py` 新建（~370 行 Python：6 API + 2 异常 + 2 helper + denylist + hard cap）
- **vp-2**：`skills/_shared/pm-view/attachments-upload.md` 新建（~230 行 prose 单一真相源）
- **vp-3**：7 SKILL 加 trigger 0 段（new-req 完整段 + 6 SKILL 精简段 + 链 attachments-upload.md）
- **vp-3b**：`new-req/SKILL.md` 步骤 4.5 commit pathspec 加动态 attachments/ add（C1 fix）
- **vp-3c**：`req-stage-gate/SKILL.md` B 分支 trigger 0 disable prose（C4 fix）
- **vp-4**：`tests/test-attachments-helper.sh` 新增 **13 case**（unit + integration + regression + 静态 grep；含 trigger 2 regression for is_seen 改造）
- **vp-5**：`templates/req-prd.md.tmpl` 新加 `## 📎 参考材料`（保留 "九、附件（可选）" PRD 内置章节体系不动；两者并存语义清晰，比强行改名更对）
- **vp-6**：`skills/_shared/PM-VIEW-RULES.md` 加 §10 主索引行 + `INVARIANTS.md` 立 I-RT10
- **vp-7**：`CHANGELOG.md` 未发布段 + `RUNTIME.md`「当前位置」+ `docs/INDEX.md` + 设计文档归档 `git mv docs/设计/attachments-体验优化.md docs/归档/完成/attachments-AI-接管.md` + `docs/归档/完成/attachments-机制.md` 加 v2 升级指针段

**测试基线**：`bash tests/run-all.sh` **425 / 0**（前基线 412/0；D-iii v2 新增 13 case 全过 —— 设计预期 ≥ 423/0，**超出**）。

**v1 → v2 反转触发点**（同 D-i v4 Round 3 剧情）：

- Claude plan-eng-review D1-D10 共 10 finding 全 ACCEPT 后
- **Codex outside voice 11 critical/high finding** 集体指向根因 = v1 prose-only 应 helper 化（C1 Stage 1 dirty / C2 漏 Stage 5 入口 / C3 attachments_seen 没 helper 化 / C4 office-hours 冲突 / C5 stage 产出文档不存在 / C6 敏感文件 denylist / C7 Bash cp 脆 / C8 引用 section 不是真相源 / C9 模板事实 / C10 size fail-open / C11 测试不足）
- PM 拍 D12 = A：反转 v1 → v2 helper-based

**业务仓需注意**：

- **PM mental model 切 Model 2**：PM 完全不感知 `attachments/` 目录；想上传材料 → 在 chat 自然说 "我有 X 在路径 Y，重点 Z" → AI 后台搞定（与 D-i v4 office-hours snapshot 同款交互）
- **现有 trigger 1 / 2 保留作 fallback**：PM 真手动 cp 进 attachments/ 时 trigger 2 仍能识别（用 `is_seen` 判定基于 `attachments_seen` 真相源）
- **B 分支选 office-hours 源材料期间** trigger 0 禁用 —— PM 在 B 分支给绝对路径不会被误归档为 attachment
- **`/prd-writing` standalone 模式不启 trigger 0** —— standalone 不绑 req → 不入 req attachments/；想给独立 PRD 附件 PM 走手动 / 他路径
- **`.req-meta.json` 多 1 个字段**（`attachments_seen` 列表）；旧 req 无字段自动空列表 fallback，零迁移
- **hard cap 50MB**：超大文件 helper raise `FileSizeError`，chat 报错让 PM 走外部引用或拆小
- **敏感路径 denylist**：12 个 pattern（`.env` / `.ssh/` / `.aws/` / `token` / `credential` 等）→ PM 给 `~/.ssh/id_rsa` 类路径会被 helper 拒纳；消费仓发现新 case 扩 pattern

**待验项**（消费仓真实 req 验证）：

- **LLM 识别准确性**（同 D-i v4 R3-H2 DEFER）：trigger 0 LLM prose 判断 PM "上传意图" 准确性，相信 LLM + 消费仓真实 req 验证；如不行再独立 D-* 设计引入 LLM eval framework
- **`SENSITIVE_PATH_PATTERNS` 覆盖度**：经验值 12 pattern，可能漏 case（OAuth token cache / gcloud config 等）；消费仓使用后扩展
- **`MAX_FILE_SIZE_MB = 50` 是否合适**：经验值；可能要消费仓调整

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
