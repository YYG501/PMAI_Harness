# 关键脚本不变式

> **目的**：为 6 个涉及数据完整性的关键脚本明确定义不变式（invariants）。
> 每个不变式都是一条"无论如何都不能违反"的规则。
> 实现和测试都围绕这些不变式展开。

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

### 守卫点
- 状态检查：line ~22-27
- 前置条件：line ~88-122
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
- **I-CA2**：req 下所有活跃 task（执行中/待验收）的 worktree 和分支必须清理
- **I-CA3**：必须在所有 task 清理完成后才清理 req 本身
- **I-CA4**：req 目录必须移到 requirements/closed/（保留记录），meta.status = cancelled
- **I-CA5**：Cancel 失败留下的残留（worktree、分支）必须能重新运行脚本清理干净（幂等）
- **I-CA6**：cancel 后 PM 能从 `/status` 看到这个 req 已 cancelled

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

### 守卫点
- 路径归一化：line ~39-102
- 有效分支推导：line ~114-125
- Gate 0（task 状态直改）：case ~162-180
- Gate 1（req stage 直改）：case ~182-193
- Gate 2（不在这里，合并到 Gate 3）
- Gate 3（main 白名单）：line ~197-230
- Gate 4（worktree 作用域）：line ~232-250

---

## task-transition.py

**目的**：Task 状态转换的单一入口。

### 不变式

- **I-TT1**：只允许 4 种合法转换：待确认→执行中、执行中→待验收、待验收→已完成、待验收→执行中
- **I-TT2**：待确认→执行中 必须满足：v1 串行强制（同 req 下无其他 task 处于执行中/待验收）
- **I-TT3**：执行中→待验收 必须满足：
  - 文档偏差 section 已填（或"无偏差"）
  - 自审记录 section 有内容
  - 事件流中 `review_completed` 事件覆盖审查工具字段列出的所有工具
  - 哨兵值（`(无)`、`无`、空等）当作"无需审查"，不要求对应事件
- **I-TT4**：待验收→执行中 必须提供 --note 参数（PM 打回必须有反馈）
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

- **I-RT1**：正向转换必须逐级推进（不能跨级，除非明确 skip-stage）
- **I-RT2**：Stage 3 和 4 可跳过，但规则不同：
  - Stage 3：非首次 req + PM 显式决定
  - Stage 4：DESIGN.md 已有内容时问 PM
- **I-RT3**：每个 stage 正向推进时必须验证前一 stage 的产出文件存在
- **I-RT4**：Stage 7 不可回退（merge 到 main 不可逆）
- **I-RT5**：Stage 6 回退必须校验所有 task 已关闭/取消（有活跃 task 时禁止回退）
- **I-RT6**：回退不能跳级也不能越界（不能回到 < 1）
- **I-RT7**：转换成功必须更新 .req-meta.json 的 stage 和 stage_history
- **I-RT8**：写入 .req-meta.json 必须原子（写失败时文件保持原值）

### 守卫点
- validate_forward：line ~120-160
- validate_rollback：line ~162-185
- save_meta：line ~43-49
- stage_history 追加：line ~207

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
