# 关键脚本不变式

> **目的**：为 6 个涉及数据完整性的关键脚本明确定义不变式（invariants）。
> 每个不变式都是一条"无论如何都不能违反"的规则。
> 实现和测试都围绕这些不变式展开。

---

## 主索引（速查）

按字母前缀分组，共 60 条不变量。详细定义见下方对应 section。

| 前缀 | 出处 section | 范围 | 一句话主旨 |
|---|---|---|---|
| **I-G** (1-5) | [通用](#通用不变式所有脚本共享) | 全局 | 半完成防御 / 错误吞掉禁止 / 前置条件 / 归档 commit / 写检查 |
| **I-CT** (1-8) | [close-task.sh](#close-tasksh) | task close 流程 | 状态/前置/merge/归档顺序 + 事件流证明状态机推进（CT7-8） |
| **I-CR** (1-9) | [close-req.sh](#close-reqsh) | req close 流程 | stage 7 / task 全闭 / merge main 顺序 + ancestor 验证 |
| **I-CA** (1-6) | [cancel-req.sh](#cancel-reqsh) | req 废弃流程 | 不 merge main / 全 task 先清 / 幂等 |
| **I-CB** (1-8, 10) | [check-branch.sh](#check-branchsh) | PreToolUse hook | 路径归一化 / 白名单 / fail-closed / read-only + task 状态硬 gate（CB10） |
| **I-AD** (1-5) | [exec-adapters](#exec-adaptersshcodexsh--cursor-agentsh) | 外部执行器 | 启动前状态校验 / diff 范围 / clean dispatch（AD5） |
| **I-DC** (1) | [文档落盘 gate](#文档落盘-gateidc1) | task-spec / task-confirm / req-transition | dispatch 前 working tree 文档必须 clean（auto-commit 兜底） |
| **I-RV** (1-3) | [review 工具](#review-工具推荐而非强制) | review 推荐 | AI 不自跑 / 事件不当 gate / 不 fake append |
| **I-TT** (1-3,5-7) | [task-transition.py](#task-transitionpy) | task 状态转换 | 2 主转换 + 1 失败回退 / D0 并行 / 原子性 |
| **I-RT** (1-8) | [req-transition.py](#req-transitionpy) | req stage 转换 | 逐级推进 / stage 3-4 可跳 / stage 7 不可回退 |

> **已废弃**：~~I-TT4~~（打回不切状态，详见 §I-TT1）；~~I-PR1~~（旧 plan-review hard gate，被 I-RV2 撤销）。

---

## 通用不变式（所有脚本共享）

- **I-G1**：任何多步操作，中间任一步失败都不能留下"半完成状态"。要么完全成功，要么可以安全重试
- **I-G2**：不能用 `|| true` 吞掉关键步骤的失败（commit、merge、mv 等）。只有真正可容忍的清理步骤（rm 临时文件等）才能吞错
- **I-G3**：前置条件必须在改变任何状态**之前**验证完成。先检查再动手
- **I-G4**：所有"归档"都必须是 committed 状态（git tracked），不能只是 cp 到目录里
- **I-G5**：任何写操作都假设它可能失败，必须显式检查返回值

---

## close-task.sh

**目的**：PM 通过验收后，将 task 分支合并回 req 分支并清理。

### 不变式

- **I-CT1**：task 文件的状态必须是"已完成"才能 close
- **I-CT2**：前置条件必须全部满足：
  - task 分支必须存在
  - req 分支必须存在（从 .req-meta.json 读取）
  - req worktree 必须存在
  - task worktree 必须 clean（无未 commit 改动）
- **I-CT3**：merge 到 req 分支必须成功，且通过 `merge-base --is-ancestor` 验证 task HEAD 已进入 req 分支
- **I-CT4**：归档文件（.runs/\*.json、events/\*.jsonl）必须 commit 到 req 分支后，才能删除原件
- **I-CT5**：只有在 merge 成功且归档已 commit 后，才能删除 task 分支和 task worktree
- **I-CT6**：任何前置条件失败 → exit 1，不能 "跳过并继续"
- **I-CT7**：**事件流必须证明状态机完整推进**。merge 前审计 `.runs/events/<task>.jsonl`：必须存在 `待执行→执行中`、`执行中→已完成` 两条 `status_changed` 事件，以及至少一条 `execution_started` 或 `execution_manual_completed`。任何一条缺失 → 拒绝 merge 并保留数据（对「agent 跳过状态机一口气写完多个 task」的结构性防御）。事件文件不存在一律视为违规（fail-closed）
- **I-CT8**：**task 分支上每个 code commit 的时间戳必须晚于首次 `status_changed(*, 执行中)` 事件时间戳**。早于该时间的 commit 说明"先写代码再补流程"，拒绝 merge

### 守卫点
- 状态检查：line ~22-27
- 前置条件：line ~88-122
- 事件流审计（I-CT7/I-CT8）：merge 执行前
- Merge 验证：line ~131-135
- 归档 commit：line ~140-170
- 清理：只在 `MERGE_OK=true` 之后

---

## close-req.sh

**目的**：req 的所有 task 都已关闭后，将 req 分支合并回 main 并归档。

### 不变式

- **I-CR1**：req stage 必须是 7
- **I-CR2**：req 下所有 task 状态必须是"已完成"（或已 cancelled）
- **I-CR3**：req 分支必须存在。如果不存在，拒绝 close（可能是用户想 cancel-req 而不是 close-req）
- **I-CR4**：req worktree 必须存在
- **I-CR5**：**所有状态改动必须先 commit 到 req 分支**（requirements/active → closed 的移动、meta.status=closed），再 merge 到 main
- **I-CR6**：merge 到 main 必须成功且通过 ancestor 验证
- **I-CR7**：清理顺序必须是：req 分支上 commit → merge → 删分支 → 删 worktree。每步失败都必须硬退出，不能吞错
- **I-CR8**：close 成功后，main 分支上应该有：
  - req 分支的所有代码/文档提交
  - req 目录在 requirements/closed/
  - meta.status = closed
- **I-CR9**：close 失败不能留下半完成状态（已 merge 但未归档、已删分支但目录还在 active/）

### 守卫点
- 前置检查：line ~19-52
- req 分支操作（移目录+改 meta+commit）：line ~54-88
- 切 main + merge：line ~90-105
- 清理（只在 merge 成功后）：line ~107-122

---

## cancel-req.sh

**目的**：PM 废弃 req，不合并到 main，清理所有状态。

### 不变式

- **I-CA1**：cancel 不 merge 到 main，main 零污染
- **I-CA2**：req 下所有活跃 task（执行中）的 worktree 和分支必须清理
- **I-CA3**：必须在所有 task 清理完成后才清理 req 本身
- **I-CA4**：req 目录必须移到 requirements/closed/（保留记录），meta.status = cancelled
- **I-CA5**：Cancel 失败留下的残留（worktree、分支）必须能重新运行脚本清理干净（幂等）
- **I-CA6**：cancel 后 PM 能从 `/task-status` 看到这个 req 已 cancelled

### 守卫点
- task 清理循环：line ~31-57
- req 分支/worktree 清理：line ~66-76
- 归档移动 + meta 更新：line ~78-95

---

## check-branch.sh

**目的**：PreToolUse hook，拦截非法的 Edit/Write 操作。

### 不变式

- **I-CB1**：所有路径归一化必须基于 **MAIN_REPO_ROOT**，不是当前 worktree toplevel。这样绝对路径和相对路径得到一致的 gate 判断
- **I-CB2**：目标文件所在的"有效分支"是它所在 worktree 的分支，不一定是当前 shell 的分支。必须按 `.worktrees/<branch>/` 前缀推导
- **I-CB3**：**白名单模式**：main 分支上默认拒绝所有写入，只放行白名单路径（.claude/、CLAUDE.md、requirements/active/、requirements/closed/、.runs/、.worktrees/、.dev-port、init 时的 docs）
- **I-CB4**：task 分支（`task-*`）不能写 docs/（文档改动走 req 分支）
- **I-CB5**：req 分支（`req-*`）不能直接写 prototypes/ 代码（代码改动走 task 分支）
- **I-CB6**：task 文件的"状态"字段 和 .req-meta.json 的"stage"字段 禁止直接编辑（必须走 transition 脚本）
- **I-CB7**：hook 失败或无法判断 → 默认拒绝（fail-closed），不放行
- **I-CB8**：hook 本身不能修改任何文件（read-only 验证逻辑）
- **I-CB10**：**task worktree 写入时，task 状态字段必须为「执行中」**。状态为「待执行/已完成」或字段读不到一律 deny。这是对 Claude 实例越权写 task 代码的结构性防御（hook 侧）。豁免范围：task 文件本身的写入（执行日志/自审记录/文档偏差 section 填写需要放行）+ `.runs/`/`.worktrees/` 运行时元数据。注：「执行中」覆盖 AI 实现期 + PM 验收期 — 验收期 AI 收 PM 打回反馈仍可写代码（task 状态全程不切，PM 通过才转「已完成」）

### 守卫点
- 路径归一化：line ~39-102
- 有效分支推导：line ~114-125
- Gate 0（task 状态直改）：case ~162-180
- Gate 1（req stage 直改）：case ~182-193
- Gate 2（不在这里，合并到 Gate 3）
- Gate 3（main 白名单）：line ~197-230
- Gate 4（worktree 作用域）：line ~232-250

---

## exec-adapters/*.sh （codex.sh / cursor-agent.sh）

**目的**：调外部执行器（Codex、Cursor-Agent）跑 task 代码。Adapter 在独立进程中运行，Claude Code 的 PreToolUse hook 管不到其写操作——adapter 是「外部执行器越权」的唯一防御点。

### 不变式

- **I-AD1**：**adapter 启动前必须校验 task 状态 == 执行中**。非执行中直接 exit 1，不调用执行器。避免 Claude hook 盲区（Codex 在 workspace-write 下的 fs 操作不经 hook）
- **I-AD2**：**adapter 退出后必须校验 worktree diff 范围**。task 分支上新增/修改的文件路径必须全部落在 task 文件 `执行范围` / `文件范围（机器校验）` section 声明的 allowlist 内；v3 task 必须使用执行区的 `文件范围（机器校验）`。allowlist 缺失或越界 → 记 `execution_failed` 事件，返回非零 exit code，让 orchestrator 触发 `--fail-execution`
- **I-AD3**：adapter 不得 `git add` / `git commit` / `git checkout`——改动保持 unstaged，commit 权归 orchestrator
- **I-AD4**：adapter 前置/后置校验失败时必须追加 `execution_failed` 事件到事件流（便于事后审计与统计）
- **I-AD5**：**dispatch 前 task worktree 必须 clean**（无 untracked、无未 commit 改动）。dirty 时由上层（task-execute）hard exit 1，**不**进 adapter、**不** rollback、**不** `--fail-execution`，把处理权交还 PM。理由：codex / cursor-agent 的 stop 是软停，已派发的 sandbox shell 子进程会延迟落盘可能覆盖手改；失败回滚基线是 HEAD，未 commit 改动会被 git restore 清掉。事故案例：2026-04-27 PM 手改字段后 codex 后续延迟落盘把字段写回，working tree 没 commit 没法 git diff 找回

### 守卫点
- 启动前状态校验：adapter 第一段
- 退出后 diff 校验：adapter 末尾，基于 `git -C $TASK_WORKTREE diff --name-only HEAD`
- Dispatch 前 working tree clean：task-execute SKILL.md 步骤 3b 开头（pre-dispatch checkpoint gate）

---

## 文档落盘 gate（I-DC1）

**目的**：把 I-AD5 的"dispatch 前 working tree 必须 clean"原则推广到**文档级 dispatch 边界**——凡是把 PM 写的文档从 working tree fork / merge / transition 给下游消费的地方，都要保证文档已 commit 到对应分支。事故背景：2026-05-09 task-005（ExampleConsumerApp）三个状态变更弹窗 + 导入弹窗的文案与 PM 视图终态偏差——根因是 task-spec 在 req worktree 跑了 4 轮 revise + 1 次 reconcile，全部停在 working tree 没 commit；task-confirm 通过 `git worktree add -b ... <REQ_BRANCH>` fork 时取的是 req 分支 HEAD commit（first-gen v1），把 PM 改了 4 次的版本完全跳过，executor 按 v1 实施。memory `feedback_codex_pre_dispatch_checkpoint.md` 总结的"事后 commit 救不回延迟落盘"是普适原则，不止 codex dispatch 适用。

### 不变式

- **I-DC1**：**文档级 dispatch 边界（git worktree fork / req-transition stage 切换）之前，working tree 内对应文档必须落盘到 git 分支**。三道防线，任一触发即视为 I-DC1 被守住：
  1. **task-spec 步骤 12.6**（首道防线，PM 不感知）：reconcile 出口处由 skill 自身把 task md 两文件（PM 视图主文件 + 工程合同）commit 到 req 分支。
  2. **create-task-worktree.sh pre-fork gate**（兜底）：fork 前检查 req 分支 working tree 中本 task 两文件是否 dirty，dirty 时 auto-commit + stderr 警告（pathspec 严格限定本 task 范围，不卷入其他改动）。task-confirm SKILL 必须把警告原文转给 PM 一句话说明。
  3. **req-transition.py pre-transition gate**（兜底）：forward 推进时把 active req 范围内（`requirements/active/<req>/` + `docs/DESIGN.md`）的未 commit 改动 auto-commit，commit 失败则 exit 1 拒绝推进。rollback 不触发（不是 dispatch）。

  原则：auto-commit pathspec **永远精确限定**到本次 dispatch 涉及的文档范围；从不 `git add -A`，避免把 PM 在 working tree 里飘的其他改动（譬如手改的 prototype 代码）误捆进文档 commit。

### 守卫点

- task-spec 步骤 12.6：`skills/task-spec/SKILL.md`（reconcile 出口处调 `auto_commit_docs`）
- create-task-worktree pre-fork gate：`scripts/create-task-worktree.sh`（"I-DC1 Pre-fork dirty gate" 段）
- req-transition pre-transition gate：`scripts/req-transition.py` `seal_req_docs_before_transition`
- 共享 helper：`scripts/_lib/dirty-check.sh`（`list_doc_dirty` / `auto_commit_docs`）

---

## review 工具（推荐而非强制）

**目的**：所有 review 工具（`/plan-eng-review` `/plan-design-review` `/plan-ceo-review` `/plan-devex-review` `/review` `/qa` `/design-review` 等 gstack skill）一律由 PM 手动调用；AI 只在产物生成后列出推荐清单，不替 PM 跑。事故背景：AI 自跑容易"假执行"——尤其依赖 browse 的 `/qa` `/design-review`，曾出现声称跑了但只手工对照文档的伪审查（参见 memory `feedback_skill_must_actually_invoke.md`）。

### 不变式

- **I-RV1**：AI 在产物生成（solution.md / task-plan.md / task 文件）后必须输出"推荐 review 工具"区块，但不得自动调用——这三处 review 是 PM 在产物生成后的常规检视入口。**task 实现完毕的呈交验收块例外**：推荐 review 仅作为验收信息块**末尾**的辅助提示（"⚙️ 可选深度审查"），PM 自取所需，不再是 commit 前必经步骤——PM 可直接通过/打回，也可任意时刻自跑 `/review` `/qa` `/design-review`。
- **I-RV2**：`review_completed` / `plan_review_completed` 事件由 PM 跑完后口述结论、AI 机械 append，作为审计记录。**事件流不当任何状态机硬 gate**：缺事件不阻止 task-confirm 启动、不阻止「执行中→已完成」转换。
- **I-RV3**：AI 不得"先 append 后跑"或"跳过 PM 直接 append"事件（违反"skill 必须实际调用，不能凭记忆模拟"）。append 必须发生在 PM 明确报告 review 结果之后。

### 守卫点

- 推荐区块：
  - solution.md：req-solution SKILL.md 退出契约 + Rules
  - task-plan.md：task-plan SKILL.md 步骤 5
  - task 文件：task-spec SKILL.md 步骤 8（写完 task 文件后）
  - task 实现完毕：task-execute SKILL.md 步骤 11 验收信息块末尾「⚙️ 可选深度审查」（不是必经步骤；PM 自取所需）
- 事件 append：PM 报告结果后 AI 调 `task-events.py append --type review_completed/plan_review_completed --tool <name> --result <pass|fail>`
- 查询接口：`task-events.py check-reviews|check-plan-reviews`（informational，永远 exit 0）

---

## task-transition.py

**目的**：Task 状态转换的单一入口。

### 不变式

- **I-TT1**：只允许 2 种主合法转换 + 1 种受限失败回退：
  - 待执行→执行中（task-confirm 启动）
  - 执行中→已完成（PM 验收通过；触发 §review/§task-transition 校验）
  - 执行中→待执行（受限：仅 --fail-execution / --cancel-manual 路径，普通 --to 拒绝）

  **打回不切状态**：PM 打回时 task 留在「执行中」，AI 收反馈直接继续修，不再走 transition。
- **I-TT2**：~~v1 串行强制~~ **D0 并行允许（v4 plan §8 A0 修订）**：同 req 下允许多个 task 同时处于执行中。原 serial 校验已 no-op 化保留 hook 在 task-transition.py:check_serial_constraint，未来如需恢复可恢复
- **I-TT3**：执行中→已完成 必须满足：
  - 文档偏差 section 已填（或"无偏差"）
  - 自审记录 section 有内容（commit 前 AI 写的 placeholder + PM 验收阶段任意时刻可补的 review 条目均算）
  - review 事件流不做覆盖校验（review 工具改为 PM 自跑推荐项；见 §review 工具）
- ~~**I-TT4**~~：（已废弃 — 不再有打回 transition；PM 打回直接写反馈到 PM 视图历史档案，task 状态保持「执行中」）
- **I-TT5**：状态字段的写入必须成功才算转换成功。写入失败必须 exit 1 且不追加事件
- **I-TT6**：每次转换必须在事件流追加 status_changed 事件
- **I-TT7**：转换失败时 task 文件状态字段必须保持原值（原子性）

### 守卫点
- VALID_TRANSITIONS 表：line ~16-21
- check_serial_constraint：line ~84-100
- check_preconditions：line ~103-152
- update_field 写入：line ~228-232（必须检查 count > 0）
- append_event：只在写入成功后调用

---

## req-transition.py

**目的**：Req stage 转换的单一入口。

### 不变式

- **I-RT1**：正向转换必须逐级推进（不能跨级，除非 stage 4 自动跳过）
- **I-RT2**：所有 req 默认都必须经过 stage 3（方案设计）；只有 stage 4 在 `docs/DESIGN.md` 已有实质内容时可由 `req-transition.py --to 5` 自动跳过
- **I-RT3**：每个 stage 正向推进时必须验证前一 stage 的产出文件存在
- **I-RT4**：Stage 7 不可回退（merge 到 main 不可逆）
- **I-RT5**：Stage 6 回退必须校验所有 task 已关闭/取消（有活跃 task 时禁止回退）
- **I-RT6**：回退不能跳级也不能越界（不能回到 < 1）
- **I-RT7**：转换成功必须更新 .req-meta.json 的 stage 和 stage_history
- **I-RT8**：写入 .req-meta.json 必须原子（写失败时文件保持原值）
- **I-RT9**（D-i v4，2026-05-25）：stage N 真相源由 `.req-meta.json:stage{N}_source` 字段定义（req 内相对路径）。`req-transition.py` 前置校验 + 下游 SKILL 读 stage N 真相源时**必须**走 `_lib.state.get_stage_source(req_dir, n)` helper（**不得**直接 hardcode 文件名）；helper 在字段缺失时降级 `stages.py:STAGE_OUTPUT_FILES[n]` 默认产物（兼容旧 req）。配套字段：`stage{N}_tool`（产生工具名，e.g. `req-analysis` / `office-hours`）+ `stage{N}_source_origin`（B 分支可选，外部源原始绝对路径，追溯用）。**stage 2 已落地双分支**（A=analysis.md / B=stage2-office-hours.md）；其他 stage 暂未启用双源契约，按 helper fallback 走默认产物即可。
- **I-RT10**（D-iii v2，2026-05-25）：req attachments 状态真相源由 `.req-meta.json:attachments_seen` 数组定义（条目 schema：`{name, src_origin, hint, stage_prefix, registered_at}`）。caller SKILL 上传 / 读 / 删 / 替换 attachments **必须**走 `_lib.attachments` helper（`copy_attachment` / `register_attachment` / `list_attachments_seen` / `is_seen` / `remove_attachment` / `replace_attachment`），**不得**直接 Bash `cp` / 直接写 `.req-meta.json` 该字段。helper 强制两道安全边界：① `SENSITIVE_PATH_PATTERNS` denylist（命中 → `SensitivePathError`，拒纳 `.env` / `.ssh/` / `token` / `credential` 等敏感路径）；② `MAX_FILE_SIZE_MB = 50` hard cap（命中 → `FileSizeError`，不依赖 pre-commit warn fail-open）。stage 产出文档末尾 `## 📎 参考材料` section 仅作 PM 可见展示，不作状态真相源。**Stage 1→2 B 分支 office-hours 选源期间** `trigger 0` 禁用（C4 cross-design 冲突防护），PM 给的绝对路径走 `_lib.state.set_stage_source(tool='office-hours', origin=...)` 路径，不调 attachments helper。

### 守卫点
- validate_forward：line ~120-160
- validate_rollback：line ~162-185
- save_meta：line ~43-49
- stage_history 追加：line ~207

---

---

## 命名约定（2026-05-06 FM8 清理后）

代码中涉及 task 标识的三个层级，含义不同，不可互换：

| 概念 | 形式 | 用途 | 推荐变量名 |
|---|---|---|---|
| **task_stem** | `task-001-do-something` | 完整文件名 stem（含描述）；用作目录名、worktree branch、commit message | `task_stem` / `TASK_STEM` |
| **short_id** | `task-001` | 仅 task-NNN 部分；用作 PM CLI 简写、`.pending-manual-<id>.json` 文件名、PM 提示文案 | `short_id` / `TASK_SHORT_ID` |
| **task_id**（JSON 字段名） | 同 short_id | 仅在 `.pending-manual-*.json` schema 里出现；保留向后兼容 | 不在新代码引入，仅 JSON schema |

**反模式**：把 `task_file.stem`（=stem 含义）起名 `task_id` —— v1 时期遗留，2026-05-06 已清理。新代码应用 `task_stem`，不要复用 `task_id`。

---

## 修复策略

基于上述不变式，修复原则：

1. **先检查，再动手**：所有前置条件在 `set -e` 之后、任何文件操作之前完成
2. **使用 `exit 1` 而不是 `|| true`**：只有真正的清理步骤（如 `rm -f .tmp`）才能吞错
3. **用 `git merge-base --is-ancestor` 验证 merge 效果**：不要相信 merge 命令的 exit code
4. **归档必须 commit**：任何 cp 之后必须 git add + git commit，否则视为未归档
5. **白名单 > 黑名单**：对 main 分支等关键资源，默认拒绝，显式放行
6. **幂等性**：cancel/cleanup 类脚本必须允许重新运行（存在则清理，不存在跳过但不报错）

## 测试策略

为每个不变式写一个反例测试：故意构造违反该不变式的场景，验证脚本正确拒绝而不是破坏数据。

测试文件在 `tests/` 目录，详见 `tests/README.md`。
