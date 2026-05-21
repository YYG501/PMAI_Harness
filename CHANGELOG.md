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
