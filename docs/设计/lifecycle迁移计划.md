# Lifecycle 迁移计划（框架瘦身 v2 最深一层）

> **状态**：可执行计划 / 待 PM 审 + 高险项必跑测试
> **日期**：2026-06-19
> **作者**：AI（按「吸收 ExampleAgentProject 设计方法-改造方案 v2」§3/§5 + §Y 决议日志 `2026-06-19 文档全进 docs/ 一棵树` 一条派生）
> **范围**：lifecycle 机器（状态读写 / close 机器 / 写保护 hook / worktree 挂载 / 不变量 / 测试）。**只出计划、不盲改代码**。
> **基线**：当前 `bash tests/run-all.sh` = **588 / 0**（RUNTIME.md 2026-06-04 段）。
>
> **一句话**：取消 `requirements/active|closed/` 整棵树，把 req 的状态/文档/附件搬进 `docs/modules/<模块>/`（三件套 + `.req-meta`），`active/closed` 这对概念退化成「模块有没有在做的工作」；close 机器从「移目录到 closed/」改成「合并分支 + 清模块 `.req-meta`」；worktree 统一挂 `.worktrees/<分支>/`；main 写保护放宽。配套改/废若干 INVARIANT 与测试。

---

## 0. 读者须知 / 名词锁定

为避免「req / module / 状态」三层混淆（治规格 4 问之②术语不统一），先锁定本文用语：

| 词 | 本文含义 |
|---|---|
| **模块** | 唯一组织单位 = 一个功能模块；物理家 = `docs/modules/<模块>/`（三件套 + `.req-meta`）。 |
| **req** | 退化成**动作**（新开 / 重做一个模块），不再是文档层、不再是目录。脚本里 `req-*` 分支名仍保留作内部基础设施词。 |
| **`.req-meta`** | 模块**当前工作状态**文件（搬家后落 `docs/modules/<模块>/.req-meta.json`）。沿用 JSON schema（`id/name/branch/worktree/stage/stage_history/status`），但**语义收窄**：它描述「这个模块有没有在做的工作 + 在哪个分支/阶段」，不再是一个独立 req 实体的档案。 |
| **active / closed** | **不再是两个目录**。退化为模块的状态：模块有 `.req-meta` 且 `status=active`（或文件在场）= 在做工作；无 `.req-meta`（或 `status=closed`）= 没有在做的工作。 |
| **stage** | 内部状态标记（六步 1-4：范围确认/build/复审/沉淀），不变。沉淀=MAX_STAGE=4。 |

> **顶部声明**：本文是迁移**计划**（normative on 改什么、怎么验、回滚点）。具体代码改法在执行批次里给到行级锚点，但**实际 diff 以届时仓内代码为准**；若届时代码与本文锚点不一致，以代码为准、并回写本文。

---

## 1. 现状 → 目标（五个改动点逐条）

### ① 取消 `requirements/active|closed/` 树，`.req-meta` 搬进 `docs/modules/<模块>/`

**现状**：
- req 目录 = `requirements/active/<branch>/`（含 `.req-meta.json` / `brief.md` / `req-plan.md` / `tasks/` / `attachments/`），关闭后 `git mv` 到 `requirements/closed/<branch>/`。
- 状态读：`_lib/state.py` 的 `_collect_active_from()` 扫 `requirements/active/`、`_collect_archived_from()` 扫 `requirements/closed/`，按 `meta.status ∈ {active, closed, cancelled}` 分流。
- `create-req-headless.sh` 把 req 建在 `requirements/active/<branch>/`（在 req worktree 内）。
- `skill-preamble.sh` 第 101 行扫 `$root/requirements/active`。

**目标**：
- 模块文档家 = `docs/modules/<模块>/`：`discussion.md` / `decisions.md` / `spec.md` / `.req-meta.json`（+ 按需数据审计 json）。附件不进模块文件夹，按类型进 `docs/inputs/<类别>/`（见 §3 改造方案，本计划不展开附件迁移，仅留接口）。
- 「在做的工作」的真相源 = **扫 `docs/modules/*/.req-meta.json`，取 `status == active` 的**（取代扫 `requirements/active/` 目录）。
- 「没有在做的工作」= 模块 `.req-meta.json` 被删（或 `status` 标 closed）。**不再保留 closed/ 目录归档**——历史在 git log + 模块 `decisions.md` 的 supersede 记录里。

**关键语义反转**：旧模型「一个 req = 一个目录，关闭=移目录」。新模型「一个模块=一个长期文件夹，工作开始=写 `.req-meta`，工作结束=清 `.req-meta`」。模块文件夹**不随 close 消失**（spec.md/decisions.md 是长期真相源），消失的只是 `.req-meta` 这层工作状态。

### ② worktree 统一挂 `.worktrees/<分支>/`

**现状**：已基本如此。`create-req-worktree.sh:51` = `${PM_AI_WORKTREE_BASE:-${REPO_ROOT}/.worktrees}/${BRANCH}`；`check-branch.sh` 按 `.worktrees/<branch>/` 前缀推导有效分支；`worktree.sh` 的 `cleanup_stale_worktrees` 用 `${PM_AI_WORKTREE_BASE:-<repo>/.worktrees}/<stem>`。
- **唯一不统一处**：`worktree.sh:cleanup_stale_worktrees` 枚举孤儿 worktree 时遍历 `requirements/{active,closed}/*/tasks/` 当真相源（见第 89 行 `for state_dir in .../requirements/active .../requirements/closed`）。这条**依赖 requirements/ 树**，①取消后会失效。

**目标**：worktree 挂载点不变（已对）；把 `cleanup_stale_worktrees` 的枚举真相源从 `requirements/{active,closed}/*` 换成 `docs/modules/*/.req-meta.json` 的 `branch` 字段（+ task dormant，task 分支枚举本轮可砍或留 no-op）。

### ③ main 写保护放宽（check-branch.sh 白名单）

**现状**：`check-branch.sh` GATE 3 白名单（第 270-303 行）：
- `.claude/*` `CLAUDE.md` `.gitignore` `README.md` → 放行
- `requirements/active/*` `requirements/closed/*` → 放行（给 close/cancel 在 main 动 requirements/）
- `.runs/*` `.worktrees/*` `.dev-port` → 放行
- `mocks/*` → 放行
- `docs/decisions/*` → 放行
- `docs/PRODUCT.md` `docs/DESIGN.md` `docs/modules/*` → **首次创建可写，已 commit 后拒绝**（git log 判断）
- deposit marker 在场时额外放行 `docs/PRODUCT-STATE.md` `docs/PRODUCT-RULES.md` `docs/TODO.md` `docs/modules/*`

**目标**（§5「main 写保护放宽」+ 红线「放开的是 main 直接改文档/小代码」）：
- **放行 `docs/**` 全部**（文档讨论/小改在 main 直接动，这是「讨论=无 worktree」「小改直接改」的前提）。删掉 `docs/modules/*` 的「已 commit 后拒绝」逻辑、删掉 deposit marker 门控（deposit skill 进 dormant）。
- **删掉 `requirements/active|closed/*` 白名单条目**（①取消后该路径不存在）。
- **放行 `docs/modules/*/.req-meta.json` 的写**（状态文件在 main 上由 `/design` 开工时写、`/close` 清掉）——但**状态字段仍走 transition 脚本**（GATE 2 保留，见 §4）。
- **prototype 代码仍要分支隔离**：放宽只针对 `docs/` 与框架元数据。`prototype/`（或 brownfield 代码目录）在 main 上**仍默认拒绝**——大需求才开 worktree build。小代码改在 main 放行的边界 = **PM 手动 quick-edit 时不挂 hook 不现实**，故 GATE 3 对 prototype 代码维持拒绝，「小改直接改」靠 PM 在 main 上改文档 / 改不被 hook 拦的小配置；真要改 prototype 代码走 /build 开 worktree。

> **放宽程度（明确边界，治 R3）**：
> - ✅ main 放行：`docs/**`（含 modules 三件套 + `.req-meta.json` 非状态字段）、`.claude/*`、`CLAUDE.md`、`.gitignore`、`README.md`、`mocks/*`、`.runs/*`、`.worktrees/*`、`.dev-port`。
> - ❌ main 仍拒绝：`prototype/**` 及任何业务代码目录（走 worktree）；`docs/modules/*/.req-meta.json` 的 **stage 字段**（走 req-transition）。
> - 这是单人 PM 场景下「自由度↑、保留一道防误写业务代码」的折中（R3 PM 需确认是否接受）。

### ④ close 机器：「移目录到 closed/」→「合并分支 + 清模块 `.req-meta`」

**现状**（`close-req.sh`）：
1. 校验 stage==4 + 所有 task 关闭 + req 分支存在 + worktree 存在 + cwd 不在 worktree 内。
2. 在 req worktree 内 `git mv requirements/active/<req>` → `requirements/closed/<req>`，改 `meta.status=closed`，建 `docs/prds/` symlink，commit 到 req 分支。
3. 切 main、`git merge <req-branch>`，ancestor 验证。
4. 删 worktree + 删分支 + 兜底清孤儿。

**目标**：
1. 校验 stage==4（沉淀）+ （task dormant，下面 §4 决定 task 校验去留）+ 分支存在 + （**仅当有 worktree 时**校验 worktree/cwd）。
2. **删掉 `git mv active→closed` 步骤**。改为：在 main 上（或有 worktree 时在 worktree 内）确保模块三件套（`docs/modules/<模块>/`）已落盘 → **删除该模块的 `.req-meta.json`**（或改 `status=closed`，二选一见下）→ commit。
3. **有 worktree → merge 回 main**（保留 ancestor 验证）；**无 worktree（小需求/讨论直接在 main 改的）→ 跳过 merge，直接在 main commit「清 `.req-meta`」**。
4. 删 worktree + 删分支（仅当存在）+ 兜底清孤儿（按新真相源）。
5. 决策/术语回写（§6 跨 req 记忆）：close 时把本轮重要决策落模块 `decisions.md` / `PRODUCT-RULES.md`、新术语落 `PRODUCT.md`——这是 skill 层（`/close` SKILL.md）的活，不是 close 脚本的活，但脚本要保证这些文档已 commit（沿用 I-DC1 思路）。

> **「删 `.req-meta`」vs「改 status=closed」二选一（PM 拍）**：
> - **方案 A（删文件）**：最干净，「没有在做的工作」= 文件不在。但丢了「这个模块上次做到 stage 4」的痕迹（git log 里有）。`list_active_reqs` 等于扫不到 = active。
> - **方案 B（status=closed 留文件）**：保留痕迹，`_collect_*` 按 status 分流（与现状 `_lib/state.py` 改动最小）。但模块文件夹里长期躺一个 `status=closed` 的 `.req-meta`，语义噪音。
> - **推荐 A**：契合「模块文件夹是长期真相源，`.req-meta` 只是临时工作状态层」的设计。closed/cancelled 的历史视图（`get_timeline_state` / status-view 的 closed/cancelled 段）改为读 git log 或直接砍掉（消费仓单人 PM 用不到时间线归档视图）。**此决定影响面大（连带 §4 的 timeline 不变量与 status-view 测试），列为高险待 PM 拍。**

### ⑤ 哪些 INVARIANT 改/废 + 哪些 test 改（详见 §4 / §5）

见下。

---

## 2. 受影响文件清单（grep 实测）

引用 `requirements/active|closed` 的脚本（`grep -rln`）：

| 文件 | 角色 | 本轮处置 |
|---|---|---|
| `scripts/_lib/state.py` | 状态读层（`_collect_active_from` / `_collect_archived_from` / `list_active_reqs` / `list_closed_reqs` / `list_cancelled_reqs` / `get_timeline_state` / `list_tasks`） | **核心改**：扫 `docs/modules/*/.req-meta.json` 取代扫 `requirements/active|closed/` |
| `scripts/close-req.sh` | close 机器 | **核心改**：删 active→closed 移动、改清 `.req-meta`、worktree 可选 |
| `scripts/cancel-req.sh` | cancel 机器 | **核心改**：删 active→closed 移动、改清 `.req-meta`（cancel = 不 merge + 清状态）|
| `scripts/check-branch.sh` | 写保护 hook | **核心改**：GATE 3 放宽（③）、删 requirements 白名单、改 GATE 1/4/5 的 `requirements/*/tasks/` 路径（task dormant 后这些路径退化） |
| `scripts/create-req-headless.sh` | req 建立 | **核心改**：建在 `docs/modules/<模块>/` 而非 `requirements/active/<branch>/`；产物从 brief.md 改三件套骨架 |
| `scripts/_lib/worktree.sh` | 孤儿清理 | **改**：`cleanup_stale_worktrees` 枚举真相源换 `docs/modules/*` |
| `scripts/skill-preamble.sh` | 开工加载 + active 探测 | **改**：第 101 行 active 探测路径 |
| `scripts/_lib/req-num-resolver.sh` | req 编号分配 | **核查**：若按 `requirements/active|closed/` 数已有 req 编号 → 改按 `docs/modules/*` 或 git branch 数 |
| `scripts/_lib/symlink-prd.sh` | `docs/prds/` 收口 symlink | **核查/可能砍**：PRD 收口 symlink 假设 closed/<req>/prd.md 路径；模块化后 prd 在哪要重定（或 dormant，prd-writing 已 dormant）|
| `scripts/check-req-doc-drift.sh`（test）| drift 检测测试 | **改测试** |
| `scripts/check-task-scope.py` | task 范围校验（task dormant）| **dormant 连带**：task 全套 dormant，本脚本不在活跃路径，**留着不改**（避免 dormant 错，R4）|
| `scripts/check-worktree-residue.py` | worktree 残留检测 | **核查** requirements 引用 |
| `scripts/close-task.sh` | task close（dormant）| **不改**（dormant）|
| `scripts/req-events.py` | 事件流（task dormant 相关）| **核查**，大概率不改 |
| `scripts/quick-fix.sh`（dormant）| | **不改** |
| `scripts/migrate-reqs-to-6step.py` | 旧迁移脚本 | **参考先例**，不改 |

引用 `.req-meta` 的脚本额外项：`migrate-reqs-to-6step.py`（先例）、`_lib/attachments.py`（附件，本轮留接口不动）。

**新增脚本**：`scripts/migrate-reqs-to-modules.py`（一次性把在飞 `requirements/active/*` 搬进 `docs/modules/<模块>/`，仿 `migrate-reqs-to-6step.py` 写法：`--dry-run` + 幂等 + 歧义区列出让 PM 拍）。

---

## 3. INVARIANT 逐条处置

> 原则（红线 6 + §0.4-1）：**瘦身 = 缩小活跃集、不删不变量积累**。task 全套 dormant，其不变量（I-CT/I-TT/I-CB10/I-AD/I-DC 的 task 部分）**保留不删、标 dormant**，未来并行多 task 再激活。本轮只动「req 生命周期 + 写保护 + close 机器」直接相关的几条。

| INVARIANT | 现状主旨 | 处置 | 险级 |
|---|---|---|---|
| **I-G1~I-G5** | 通用：半完成防御 / 不吞错 / 先检查 / 归档 commit / 写检查 | **不变**（仍适用新 close 机器；新机器同样要满足）| 低 |
| **I-CR1** | close 前 req stage 必须 7（注：实际代码已是 4=沉淀，文档 anchor 仍写 7） | **保留语义、文档对齐**：close 前 stage==4（沉淀）。措辞从「stage 7」改「stage 4 沉淀」。| 低 |
| **I-CR2** | req 下所有 task 必须关闭/cancelled | **改/弱化**：task dormant，无 task 时该校验恒真（现 `check_all_tasks_closed` 见 tasks 目录不存在即 return True,[]）。**保留代码**（无 task 自动通过），文档标注「task dormant 时空过」。| 低 |
| **I-CR3** | req 分支必须存在，否则拒绝 close | **改**：小需求/讨论无 worktree、无分支也要能 close（= 直接在 main 清 `.req-meta`）。从「分支不存在就拒绝」改「分支不存在 → 视为无 worktree 路径，跳过 merge，仅清状态」。**改不变量语义**。| **高** |
| **I-CR4** | req worktree 必须存在 | **改**：同 I-CR3，worktree 可选。| **高** |
| **I-CR5** | 所有状态改动先 commit 到 req 分支再 merge main | **改**：有 worktree 走旧路径（先 commit 再 merge）；无 worktree 直接在 main commit。措辞改「有 worktree 时」。| 中 |
| **I-CR6** | merge main 必须成功 + ancestor 验证 | **保留**（仅在有 worktree merge 路径生效）。| 低 |
| **I-CR7** | 清理顺序 commit→merge→删分支→删 worktree | **保留**（有 worktree 路径）；无 worktree 路径只 commit。| 低 |
| **I-CR8** | close 后 main 有 req 代码/文档 + 目录在 closed/ + status=closed | **改**：删「目录在 closed/」「status=closed」两条断言（方案 A 删 `.req-meta`）；改为「模块三件套已在 main + 模块 `.req-meta` 已清」。**改不变量内容**。| **高** |
| **I-CR9** | close 失败不留半完成 | **保留**（新机器同样要满足；回滚点见 §6）。| 低 |
| **I-CA1~I-CA6** | cancel：不 merge / 全 task 先清 / 移 closed/ / 幂等 | **改 I-CA4**（移 closed/ → 清 `.req-meta`）；I-CA1/2/3/5/6 保留（task 部分 dormant 时空过）。| 中 |
| **I-CB1~I-CB2** | 路径归一化 / 有效分支推导 | **不变**（worktree 挂载点不变）。| 低 |
| **I-CB3** | main 白名单（含 `requirements/active|closed/`）| **改**：白名单内容按 §1③ 重写——删 requirements 条目、加 `docs/**`、删 modules 已 commit 拒绝、删 deposit marker 门控。**改不变量内容**。| **高** |
| **I-CB4** | task 分支不能写 docs/ | **dormant 连带**：task dormant，保留代码不删，标 dormant。| 低 |
| **I-CB5** | req 分支不能写 prototypes/ 代码 | 注：代码注释说此拦截已删（六步 req worktree 可直接改 prototype）。**核查**：文档 anchor I-CB5 与代码已不符，本轮**对齐文档**（标注已退役或语义变更）。| 中 |
| **I-CB6** | task 状态 / stage 字段禁止直改（走 transition）| **保留 stage 部分**（GATE 2 对 `docs/modules/*/.req-meta.json` 仍拦 stage 直改）；task 状态部分 dormant。**改路径**：GATE 1/2 的匹配从 `requirements/*/...` 改 `docs/modules/*/...`。| 中 |
| **I-CB7** | fail-closed | **不变**。| 低 |
| **I-CB8** | hook read-only | **不变**。| 低 |
| **I-CB10** | task worktree 写入要 status==执行中 | **dormant 连带**：保留代码、标 dormant。| 低 |
| **I-AD1~I-AD5** | 外部执行器（task build）| **dormant 连带**（/build 仍可能用 exec-adapter，但 task 状态机部分 dormant）。**核查 R4**：/build 是否复用 adapter——若复用，I-AD2 的「diff 范围按 task 文件 allowlist」在无 task 模型下要重定义或放宽。**列为待核**。| 中 |
| **I-DC1** | dispatch 前文档落盘（task-spec/task-confirm/req-transition 三道防线）| **改**：task-spec/task-confirm 两道防线 dormant（task dormant）；`req-transition.py` 的 `seal_req_docs_before_transition` 防线**保留但改路径**（从 `requirements/active/<req>/` + `docs/DESIGN.md` 改 `docs/modules/<模块>/` + 项目基线 docs）。close 时文档落盘沿用此思路。| 中 |
| **I-RV1~I-RV3** | review 推荐非强制 / AI 不自跑 | **不变**（红线 5 守 I-RV1；一致性扫描是 silent 自检不升格门）。| 低 |
| **I-TT1~I-TT7** | task 状态转换 | **dormant 连带**：全保留、标 dormant。| 低 |
| **I-RT1~I-RT8** | req stage 转换（逐级 / stage7 不可回退等）| **保留**（六步状态机不变，仍按 stage 1-4 推进）。**唯一连带**：`seal_req_docs_before_transition` 路径（见 I-DC1）。I-RT4「stage 7 不可回退」文档 anchor 对齐 stage 4。| 低 |
| **I-RT9** | stage N 真相源由 `stage{N}_source` 定义 | **保留**（`.req-meta.json` 搬家但 schema 不变；`get_stage_source` 仍 `req_dir / <relative>`，`req_dir` 现指 `docs/modules/<模块>/`）。| 低 |
| **I-RT10** | attachments 状态真相源 + helper + 安全边界 | **改**：附件从 per-req `attachments/` 改 `docs/inputs/<类别>/`（§3 改造方案）。`_lib/attachments.py` 的 `stage_prefix` / per-req 作用域要重做。**保留安全边界**（denylist + 50MB cap，红线/§3 明确保留）。**本计划只留接口、不展开附件迁移**（建议拆独立小批，见 §5 批 6）。| 中 |

**新增不变量（可选，PM 拍）**：
- **I-MOD1（建议）**：模块工作状态真相源 = `docs/modules/<模块>/.req-meta.json`，`status==active` = 在做工作；文件不存在 = 没有在做的工作。读写必须走 `_lib.state` helper（不直接 grep 目录树）。——把①的语义固化成不变量，防止后续又散落 grep。

---

## 4. 测试影响清单（哪些 test 要改）

> 基线 588/0。下面是**预计要动**的测试套。每批改完跑「该批相关套 + run-all 回归」。

| 测试套 | 为什么动 | 改法 |
|---|---|---|
| `test-close-req.sh` | close 机器重写（④）：现断言「移到 closed/」「status=closed」「stage!=4 拒绝」 | 重写断言：无 worktree 也能 close、close 后模块 `.req-meta` 被清/标 closed、merge 仅有 worktree 时。**高险**：I-CR3/4/8 改语义，这套大改。|
| `test-cancel-req.sh` | cancel 机器（I-CA4）改清状态 | 重写「移 closed/」断言为「清 `.req-meta`」。|
| `test-check-branch.sh` | GATE 3 白名单重写（③）。现有用例：`test_main_allows_requirements_active_brief`（放行 requirements/active）、`test_main_rejects_random_toplevel`、`test_main_allows_mocks_write`、`test_main_allows_decisions_write`、`test_main_rejects_product_state_without_marker`、`test_main_allows_product_state_with_marker`、`test_main_marker_blast_radius_limited` | 删/改：`requirements/active` 用例改 `docs/modules/*`；`product_state_without_marker`「拒绝」改「放行」（docs/** 全放行）+ 删 marker 用例；新增「main 放行 docs/modules 三件套」「main 仍拒绝 prototype 代码」「main 仍拒绝 stage 直改」用例。**高险**。|
| `test-state-lib.sh` | `_lib/state.py` 改扫描真相源（①）；`list_active_reqs` / `list_closed_reqs` / `list_cancelled_reqs` / `get_overall_state` / `get_timeline_state` 全改 | 重写 fixture（建 `docs/modules/*/.req-meta.json` 取代 `requirements/active/*`）。**高险，面最大**。|
| `test-status-view.sh` | status-view 消费 `_lib/state.py`（dogfood）；若方案 A 删 timeline closed/cancelled 段则连带 | 改 fixture + 若砍 timeline 段则删相关断言。|
| `test-req-transition.sh` | `seal_req_docs_before_transition` 路径改（I-DC1） | 改 fixture 路径 `requirements/active/<req>` → `docs/modules/<模块>`。|
| `test-pre-dispatch-doc-gate.sh` | I-DC1 三道防线 task 两道 dormant + req-transition 防线改路径 | 改/标 dormant。|
| `test-check-req-doc-drift.sh` | drift 检测引用 requirements | 改路径。|
| `test-cleanup-pending.sh` / worktree 相关 | `cleanup_stale_worktrees` 枚举真相源改（②） | 改 fixture。|
| `test-migrate-reqs.sh` | 旧 6step 迁移测试（不动）+ **新增** `test-migrate-reqs-to-modules.sh` | 新增迁移脚本测试套（仿现有）。|
| `tests/helpers/fixture.sh` | **公共 fixture**：`fixture_create_req` 建在 `requirements/active/<branch>/`（第 82 行）。**所有依赖它的测试套都连带** | **核心改**：`fixture_create_req` 改建 `docs/modules/<模块>/.req-meta.json`。改这一处会牵动 close/cancel/state/status/transition 等多套——**先评估是给 fixture 加新函数 `fixture_create_module` 平滑过渡，还是直接改 `fixture_create_req`**。**最高险：fixture 是测试地基。**|
| task 系列测试（`test-close-task.sh` / `test-task-*.sh` / `test-check-task-scope.sh` 等）| task dormant | **不改**（保留 + 仍跑，验证 dormant 代码未被误伤）。若 fixture 改动牵连到它们的 task 路径假设，**可能被动连带**——这是 fixture 改动的 blast radius，迁移时必查（参考 memory `feedback_stage_refactor_review_blast_radius`：SKILL prose 改≠落地，审 stage 重构必查底层 .sh + fixture + init case + 共享 gate）。|

**测试策略**：沿用 INVARIANTS.md「为每个不变量写反例测试」。改不变量 → 同步改反例。新增 I-MOD1 → 加反例（有人直接 grep requirements 目录树 = 应被审出 / 或脚本读不到模块状态时的行为）。

---

## 5. 分批顺序 + 每批测试验证 + 回滚点

> 总原则：**先纯加法/低险铺底（可与旧路径并存），再切真相源，最后删旧路径**。每批一个 git commit（在分支 `reshape/absorb-01agent`），commit 即回滚点。高险批必须 PM 审 + 跑全量 588 回归。

### 批 0（纯加法 / 低险）— 迁移脚本 + 双读兼容

**做**：
1. 写 `scripts/migrate-reqs-to-modules.py`（`--dry-run` + 幂等 + 歧义区列出；把在飞 `requirements/active/<branch>/` 搬 `docs/modules/<模块>/`，模块名由 PM 给 / 从 req name 派生）。**只写脚本，先不跑。**
2. `_lib/state.py` 的 `_collect_active_from` / `_collect_archived_from` 改成**双读**：既扫 `requirements/active|closed/`（旧），也扫 `docs/modules/*/.req-meta.json`（新），合并去重。**纯加法，旧测试全绿。**

**验证**：`test-state-lib.sh` + `test-migrate-reqs.sh`（新增套）+ run-all。预期 **588 + 新增 N / 0**，旧用例 0 回归。
**回滚点**：批 0 commit。出问题 `git revert`，双读是叠加，回滚无副作用。
**险级**：低（纯加法）。

### 批 1（低-中险）— check-branch GATE 3 放宽

**做**：`check-branch.sh` GATE 3：加 `docs/**` 全放行、删 modules 已 commit 拒绝、删 deposit marker 门控（保留 requirements 白名单条目暂不删，避免与批 2 耦合）。prototype 代码维持拒绝。
**验证**：`test-check-branch.sh`（改相关用例 + 新增 docs/modules 放行、prototype 拒绝、stage 直改拒绝用例）+ run-all。
**回滚点**：批 1 commit。
**险级**：中（写保护是安全面；但放宽方向只增放行不增拒绝，误伤面小）。**PM 审是否接受放宽程度（R3）。**

### 批 2（高险）— 切真相源到 docs/modules（核心）

**做**（一批做完、原子切）：
1. `fixture.sh`：改 `fixture_create_req`（或加 `fixture_create_module`）建 `docs/modules/<模块>/.req-meta.json`。
2. `create-req-headless.sh`：建在 `docs/modules/<模块>/`，产出三件套骨架（不再 brief.md + tasks/ + attachments/ 在 requirements/）。
3. `_lib/state.py`：把双读改成**单读 `docs/modules/*`**（删 requirements 扫描）。
4. `skill-preamble.sh`：active 探测路径改。
5. `worktree.sh:cleanup_stale_worktrees`：枚举真相源改。
6. `check-branch.sh` GATE 1/2/4/5 路径：`requirements/*/...` → `docs/modules/*/...`；删 GATE 3 的 requirements 白名单条目。
7. `req-transition.py:seal_req_docs_before_transition`：路径改。
8. 跑 `migrate-reqs-to-modules.py`（先 `--dry-run` 给 PM 看，PM 拍后实跑）迁在飞 req。

**验证**：`test-state-lib.sh` + `test-status-view.sh` + `test-req-transition.sh` + `test-check-branch.sh` + `test-pre-dispatch-doc-gate.sh` + **全量 run-all**（重点看 task 系列被动连带是否回归）。**改完跑全量、人审 diff。**
**回滚点**：批 2 commit（**这是最大回滚点**，切真相源是不可逆度最高的一批，commit 前 PM 必审 + 全绿）。
**险级**：**高**。fixture 是地基，blast radius 大，必走人审 + 全量测试。

### 批 3（高险）— close / cancel 机器重写

**做**：
1. `close-req.sh`：删 active→closed 移动；改清模块 `.req-meta`（方案 A/B 按 PM 拍）；worktree 可选（无 worktree 跳 merge，仅 main commit）；保留 ancestor 验证（有 worktree 时）+ 回滚点逻辑（I-CR9）。
2. `cancel-req.sh`：同步改 I-CA4（清状态取代移 closed/）。
3. `symlink-prd.sh`：核查 PRD 收口 symlink（prd-writing dormant → 大概率砍此调用或留 no-op）。
**验证**：`test-close-req.sh`（大改）+ `test-cancel-req.sh` + `test-symlink-prd.sh` + run-all。
**回滚点**：批 3 commit。
**险级**：**高**。改 I-CR3/4/5/8 + I-CA4 语义；close 机器是数据完整性核心（merge 回 main 不可逆）。必走人审 + 全量 + **手动跑一遍真实 close 场景**（有 worktree / 无 worktree 两条路）。

### 批 4（中险）— INVARIANTS.md + 文档对齐

**做**：按 §3 改 INVARIANTS.md（I-CR1/3/4/5/8、I-CA4、I-CB3/5/6、I-DC1、I-RT4 措辞、新增 I-MOD1）；标 dormant 不变量（task/exec 系列加 dormant 标注，不删）；更新 RUNTIME.md 测试基线 + CHANGELOG（影响消费仓的改动入口）。
**验证**：`test-product-rules.sh`（若校验 INVARIANTS 引用）+ grep 自检（INVARIANTS anchor 在脚本里还能找到对应）+ 一致性扫描（§4 改造方案：改了规格/代码 grep 相关，flag「不变量在代码找不到对应=有意删还是漏改」）。
**回滚点**：批 4 commit。
**险级**：中（文档为主，但 anchor 漂移会误导后续；走一致性扫描）。

### 批 5（中险，可选 / 待 PM 拍）— timeline / status-view closed 视图处置

**做**：若方案 A（删 `.req-meta`），处置 `get_timeline_state` / `list_closed_reqs` / `list_cancelled_reqs` / status-view 的 closed/cancelled 段——改读 git log 或直接砍（消费仓单人 PM 用不到归档时间线视图）。
**验证**：`test-state-lib.sh` + `test-status-view.sh` + run-all。
**回滚点**：批 5 commit。
**险级**：中。**强依赖批 3 的方案 A/B 决定**——若选方案 B（留 status=closed 文件）则本批基本不用动。

### 批 6（中险，独立小批）— 附件迁移（I-RT10）

**做**：`_lib/attachments.py` per-req `attachments/` → `docs/inputs/<类别>/` 自动归类；删 `stage_prefix` / per-req 作用域；**保留** denylist + 50MB cap 安全边界。
**验证**：`test-attachments-helper.sh` + run-all。
**回滚点**：批 6 commit。
**险级**：中。**与批 0-5 解耦，可最后单独走**（附件不阻塞 lifecycle 核心）。

---

## 6. 高险项汇总（必须 PM 审 + 跑全量测试）

1. **批 2 切真相源**（改 `fixture.sh` 地基 + `_lib/state.py` 单读 + 多脚本路径）：blast radius 最大，task 系列被动连带必查（memory `feedback_stage_refactor_review_blast_radius`）。
2. **批 3 close/cancel 重写**（改 I-CR3/4/5/8 + I-CA4 语义，merge 回 main 不可逆）：必手动跑有/无 worktree 两条真实 close 路径。
3. **批 1 main 写保护放宽**（I-CB3）：放开 `docs/**` 直接写、删 deposit marker 门控——R3「丢一道防误写」PM 需明确接受。
4. **方案 A vs B**（删 `.req-meta` vs status=closed）：影响 timeline/status-view/不变量断言面，PM 先拍再做批 3/5。
5. **I-AD2 在无 task 模型下的 diff 范围**（R4）：/build 若复用 exec-adapter，allowlist 按 task 文件的契约要重定义——落地前核 /build 是否真复用、别 dormant 错。

**回滚总策略**：每批一个 commit 在 `reshape/absorb-01agent` 分支，commit = 回滚点。批 0 双读是纯加法（最安全的过渡层），批 2 之前任何一批出问题都能 `git revert` 回双读状态而不丢数据。批 2/3 是不可逆度最高的两批，commit 前全绿 + PM 审 + 手动场景验证三重门。**迁移脚本一律 `--dry-run` 先给 PM 看再实跑**（仿 `migrate-reqs-to-6step.py` 的歧义区列出纪律）。

---

## 7. 待 PM 拍板清单

1. **方案 A（删 `.req-meta`）vs 方案 B（status=closed）**——决定批 3/5 形态。推荐 A。
2. **main 写保护放宽程度**（§1③ 边界表）是否接受（R3）。
3. **timeline / closed 归档视图**是否保留（若 A，倾向砍——消费仓单人 PM 用不到）。
4. **模块名从哪来**：迁移脚本 / `/design` 开工时模块名由 PM 给，还是从 req name 派生？影响 `migrate-reqs-to-modules.py` 与 `create-req-headless.sh`。
5. **task 系列彻底 dormant 的边界**（R4）：/build 复用 exec-adapter 时 I-AD 系列怎么算——本轮先核依赖、不 dormant 错。

---

**End of Lifecycle 迁移计划**
