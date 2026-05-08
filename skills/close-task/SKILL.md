---
name: close-task
description: |
  Task 关闭：对齐 task 文档与原型、检查文档偏差、归档运行时数据、merge 分支、清理 worktree。
---

# /close-task

### 执行位置（v4.5 req worktree 集中关闭）

- `/close-task` 在 **req worktree** cwd 内运行（不在 task worktree，也不在主仓）。
- task worktree 验收通过后，PM 关掉 task 窗口，切到 req 窗口跑 `/close-task task-NNN`。
- `close-task.sh` 在 req worktree cwd 校验 fail-fast；不在 req worktree 直接 exit 1。
- merge → 删 task worktree → 删 task branch 一气呵成；不再走 `pending-cleanup.json` 中转。

## When To Use

- 在 **req 窗口**（cwd = req worktree）调用，PM 通过验收后
- Task 状态必须为「已完成」

## 拆两文件约定（必读）

本 skill 处理拆两文件的 task 产物（`_shared/PM-VIEW-RULES.md` §二）：
- **PM 视图主文件**：`task-NNN-<slug>.md`（PM 决策、功能清单、验收清单、历史档案）
- **工程合同**：`task-NNN-<slug>.engineering.md`（实现细节、易错点、plan-review 沉淀、文档偏差工程层、自审记录）

close-task 阶段：
- **文档偏差检查跨两文件**：PM 视图的执行日志 + 工程合同的 §10 文档偏差表都要读
- **归档时成对处理**：PM 视图 + 工程合同必须一起归档 / merge / 清理，不允许只动一份

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: close-task"
```

## --skip-doc-update flag（A1 紧急逃生舱）

PM activates by calling close-task with `--skip-doc-update` flag。

Reason is REQUIRED。If PM does not provide reason, refuse with exit non-zero and message:

```text
Error: --skip-doc-update requires a reason. Usage: /close-task --skip-doc-update "<reason>"
```

On valid invocation:

1. Skip the `/doc-update` call entirely。
2. Write into task 文件「文档偏差」section this EXACT marker (on one line):
   ```html
   <!-- SKIP_DOC_UPDATE: reason="<PM-provided reason>" created_at="<ISO 8601 timestamp>" cleanup_status="pending" -->
   ```
3. Immediately after marker, append this cleanup TODO block:
   ```markdown
   ## 人工 Cleanup TODO（A1 决议，doc-update 被 skip）
   - [ ] 手动运行 /doc-update --task <task-id> 沉淀功能清单进 docs/modules/<module>.md
   - [ ] cleanup 完成后，把上方 SKIP_DOC_UPDATE marker 的 cleanup_status 从 "pending" 改为 "done"
   - [ ] 重跑 /req-stage-gate 验证半 close 解除
   ```
4. Continue all other close steps (merge branch, clean worktree, state machine update)。
5. Output at end:
   ```text
   task-NNN 已半 close（doc-update 被 skip）。需要人工 cleanup TODO 完成后才能推 stage 6→7。请运行 /doc-update 手动沉淀该 task 的功能清单。
   ```
6. Exit with code 0 (close-task itself succeeded; doc-update was intentionally skipped)。

## Workflow

### 步骤 0：task 文档 ↔ 原型对齐（v4.5 新增）

**目的**：PM 验收通过 ≠ task md 自动跟原型代码一致。task-execute 反馈循环故意只改原型代码，task md 业务字段（§🎯/§📐/§📋/§✅）在反馈循环里不跟——所有对齐工作集中到本步骤 batch 处理。close-task 前补齐对账，避免 task md 进入 req 分支后跟代码不符。

**执行位置**：cwd 在 req worktree（agent 跨进 task worktree 读代码 + 写 task md，全部用 `git -C $TASK_WORKTREE` 或绝对路径）。

#### 0.1 加载对照源

agent 读两边内容：

- **task PM 视图主文件**（在 task worktree 里）：
  - `## 🎯 关键产品决策`（决策反转 / 备选方案推翻情况）
  - `## 📐 产物预览`（ASCII / 原型示意）
  - `## 📋 功能清单`（业务规则逐条）
  - `## ✅ 验收清单`（PM 走查清单）
  - `## 📁 历史档案 → 执行日志`：所有执行报告的「**文档对齐预告**」字段汇总（task-execute 反馈循环里 AI 已经预告会变的段，作为对齐线索，**优先扫描这些**）
- **task 改动的代码文件**（task md §📦 范围 → 改 字段列出的路径）：
  - 全文 Read（不超过 3 个文件就全读；多文件时按对齐相关性分批读）

```bash
TASK_WORKTREE="$REPO_ROOT/.worktrees/$TASK_BRANCH"
TASK_PM_VIEW="$TASK_WORKTREE/<task-md 相对路径>"
# 改动文件清单从 §📦 范围 → 改 提取
```

#### 0.2 语义对齐扫描

agent 对每条 §🎯 / §📐 / §📋 / §✅ 描述，跟实际代码做语义比对，输出**不一致项**（每项一行，附 task md 行号 + 代码 file:line）。

**扫描优先级**：
1. **优先**：执行日志「文档对齐预告」字段提到的所有段（这些是 AI 反馈循环里已经预告会变的，命中率高）
2. **覆盖**：四个段全量扫一遍兜底（防止预告遗漏 / 反馈中提到但未预告的段）

输出格式：

```text
对齐扫描（共 N 处差异）：

1. task md §📋 #3 描述：「...」
   代码 path/file.tsx:LXX 实际：「...」
   建议：[改 task md 对齐代码 / 改代码对齐 task md]

2. ...
```

**N = 0 → 直接进步骤 1**，本步骤跳过。

#### 0.3 PM 三选一决议（每条逐条）

呈交 PM（AskUserQuestion 或 prose），每条三选一：

- **Y**：改 task md 对齐实际原型（最常见——原型迭代过、md 没跟上）
  - agent 用 Edit 改 `$TASK_PM_VIEW`，改后展示 git diff，PM 满意进下一条
- **R**：改代码对齐 task md（少见——原型实现偏离了 task md 契约）
  - agent **不能自己改代码**。提示 PM：「这条对齐意味着回退原型。建议关闭 close-task，回 task 窗口跑 /task-execute 重做后再 close。确认要在 close-task 阶段直接改代码吗？」
  - PM 坚持要在本阶段改 → 视为退出 close-task 流程，agent 输出"请回 task 窗口重做"并 exit
- **skip**：本条不重要忽略（agent 不动 task md，进下一条）

#### 0.4 patch 后 commit 到 task 分支

所有 Y 项 patch 完成后，统一在 task worktree 里 commit：

```bash
git -C "$TASK_WORKTREE" add "<task-md 相对路径>"
git -C "$TASK_WORKTREE" commit -m "task-NNN close-prep: PM 视图与原型对齐"
```

理由：task md 改动在 task 分支落地后，步骤 2 的 merge 会自然带进 req 分支作为最终历史。

#### 0.5 fail-fast 与边界

- **N = 0 或全 skip**：close-task **不阻塞**（PM 决策权，不强制对齐）。
- **PM 选 R 但又要在本阶段改代码**：agent 输出"请回 task 窗口跑 /task-execute"并 exit；不让 close-task 蜕变成 mini task-execute。
- **patch 失败 / git commit 失败**：close-task 阻塞，提示 PM 人工修复后重跑。

**与步骤 1 / 1.5 的边界**：

| 步骤 | 性质 | 对照源 |
|---|---|---|
| **0**（本节）| task md 描述 ↔ 原型代码 | task md §🎯 §📐 §📋 §✅ + 执行日志「文档对齐预告」 vs 实际改动文件 |
| 1 | task 实证发现的项目级文档偏差 | task md §历史档案/§10 vs brief/analysis/solution/module spec |
| 1.5 | PM 反馈中的视觉规范沉淀 | task md PM 反馈分类=视觉规范 vs docs/DESIGN.md |

性质不同，串行处理不合并。

### 步骤 1：检查文档偏差（跨两文件 / 兼容旧格式）

兼容性判断：
```bash
ENG_FILE="${TASK_FILE%.md}.engineering.md"
[ -f "$ENG_FILE" ] && HAS_ENG=true || HAS_ENG=false
```

读取偏差记录：

1. **PM 视图主文件** 的 `## 📁 历史档案` 区域（新格式）或 `## 文档偏差` section（旧格式）— PM 走查时记录的偏差
2. **工程合同** 的 `## 10. 文档偏差` 表（仅 `HAS_ENG=true`）— agent 在执行中发现的工程层偏差

判断：
- **任一处有偏差记录**：先调用 `/doc-update` 处理偏差（doc-update 会按相同兼容模式读两文件 / 单文件并按规则沉淀），等 `/doc-update` 完成后再继续
- **所有偏差源都无偏差 / 偏差已处理**：继续下一步

### 步骤 1.5：视觉规范反馈反推 DESIGN.md（`_shared/pm-view/input-flow.md` §9.4 第四类）

扫本 task PM 视图的 `## 📁 历史档案 → ### PM 反馈` 区域，对**分类=「视觉规范」**的条目逐条沉淀到 `$REPO_ROOT/docs/DESIGN.md`，避免视觉规范反馈进 task-local sink（task-001 R6 9 项视觉问题修了但没沉淀的反模式）。

#### 1.5.1 前置检查

```bash
DESIGN_MD="$MAIN_REPO_ROOT/docs/DESIGN.md"
if [ ! -f "$DESIGN_MD" ]; then
  echo "ℹ️  $REPO_ROOT/docs/DESIGN.md 不存在，跳过视觉规范沉淀。"
  echo "   建议 PM 后续手动建立 DESIGN.md 作为项目级视觉规范单一来源（gstack /design-consultation 可生成）。"
  # 直接进入步骤 2
fi
```

#### 1.5.2 扫描候选反馈

Read 本 task PM 视图主文件的 PM 反馈 section，提取候选：
- 分类含 `视觉规范` 的反馈条目
- 处理结果**不**含「已沉淀 DESIGN.md」备注的（避免重复处理）

候选数 = N。

**N = 0 → 直接进入步骤 2**，本步骤跳过。

#### 1.5.3 AI 起草增量（每条反馈一次）

读 `docs/DESIGN.md` 现有章节结构（`grep '^## \|^### \|^#### ' docs/DESIGN.md`），按反馈内容定位：

- **已有章节增量**：找最匹配的 `### N.M` 子条目（如 `9.2 输入框` / `9.11 弹窗模式`），起草补充段落（< 30 行）
- **新建子条目**：现有无对应位置，起草新 `### N.M+1` 子条目（< 60 行）

呈交 PM 的格式：

```markdown
反馈 K：[反馈 1 行摘要]
建议章节：docs/DESIGN.md `### 9.X.Y [章节名]`（已有章节增量 / 新子条目）
新增内容草稿：
[draft markdown 全文]
```

#### 1.5.4 PM 三选一决策（每条逐条问）

呈交 PM 一个三选一（AskUserQuestion 或 prose）：

- **Y-rule**：内容正确 + 应作项目级长期规范 → AI 用 Edit patch `docs/DESIGN.md`（不 commit）
- **Y-task-note**：本 task 特殊不作通用规则 → 保留在 task PM 反馈，标处理结果「task-only」
- **N**：AI 误分类（业务/流程反馈被错标视觉规范）→ 改 task PM 反馈的分类字段为正确类型，按该类型原规则走

**禁止**：silent commit `docs/DESIGN.md`。设计 SoT 改动必须 PM 显式审 diff。commit 由 PM 在 close-task 完成后自己跑（commit message 模板：`docs(DESIGN): 沉淀 task-NNN 反馈 — [摘要]`）。

#### 1.5.5 Y-rule patch 后的二次确认

每条 Y-rule patch 完成后：

1. AI 输出 `git -C $REPO_ROOT diff docs/DESIGN.md` 让 PM 看
2. PM 满意 → AI 用 Edit 把本条 PM 反馈的「处理结果」改为「已处理」+ 备注「已沉淀 DESIGN.md §X.Y」
3. PM 要求修改 → AI 重 patch 重 diff，循环到 PM 满意（无循环上限，但 3 次还无法对齐时 AI 主动停下问 PM 是否改成 Y-task-note 或 N）

#### 1.5.6 完成后进步骤 2

所有 N 条视觉规范反馈处理完毕（标 Y-rule / Y-task-note / N），DESIGN.md 改动**未 commit**（步骤 3 提示 PM 自己 commit），进入步骤 2。

**与步骤 1 文档偏差检查的边界**：
- 步骤 1 处理"客观文档偏差"（字段名错 / 流程描述错）→ `/doc-update` 对账
- 步骤 1.5 处理"主观视觉规范沉淀"（PM 判断哪些反馈应作项目级长期规范）→ AI 起草 + PM 三选一
- 性质不同，串行处理不合并

### 步骤 2：执行关闭

调用 close-task.sh（cwd 必须是 req worktree）：

```bash
bash .claude/scripts/close-task.sh "<task-file-absolute-path>"
```

脚本自动执行：
1. 校验 cwd 在 req worktree 内（不在则 fail-fast）
2. 校验 task 状态为「已完成」
3. 检查文档偏差（二次检查，有未处理偏差会阻塞）
4. merge task 分支 → req 分支
5. 归档 `.runs/` 到 req worktree 的 `tasks/_archived/` 并 commit 到 req 分支
6. **直接删** task worktree + task branch（一步关完）
7. 杀掉 dev server 进程
8. 清理 `.runs/` 原件
9. 追加 `task_closed` 事件

### 步骤 3：确认结果

脚本成功后，提示：

```
Task 已关闭：<task-title>

下一步（在 req 窗口继续）：
- 如有下一个待启动 task，运行 /task-spec task-XXX → /task-confirm
- 如所有 task 已完成，运行 /req-stage-gate 推进到 stage 7
```

**额外提示（仅当步骤 1.5 patch 过 DESIGN.md 时）：**

如果步骤 1.5 沉淀了视觉规范反馈（PM 选 Y-rule 至少 1 条），req worktree 里的 `docs/DESIGN.md` 处于 uncommitted 状态。close-task.sh 不 auto commit 设计 SoT。close-task 完成后追加（仍在 req 窗口）：

```bash
git diff docs/DESIGN.md  # PM 二次审 diff
git add docs/DESIGN.md
git commit -m "docs(DESIGN): 沉淀 task-NNN 反馈 — [摘要]"
```

提示模板：

```
⚠️ 步骤 1.5 沉淀了 K 条视觉规范反馈到 docs/DESIGN.md（uncommitted）。
请在本（req）窗口审 git diff docs/DESIGN.md 并 commit。
建议 commit message: docs(DESIGN): 沉淀 task-NNN 反馈 — [一行摘要]
```

## Rules

- 必须在 task 状态为「已完成」时才能关闭
- 必须在 req worktree cwd 内运行（v4.5）；不在则 fail-fast
- **步骤 0 对齐**：N=0 或全 skip 不阻塞 close-task（PM 决策权）；PM 选 R 但要在本阶段改代码 → agent 拒绝并提示回 task-execute（不让 close-task 蜕变成 mini task-execute）
- 步骤 0 patch 必须 commit 到 task 分支（在 task worktree 内做），随步骤 2 merge 自然进 req 分支
- 文档偏差必须在关闭前处理（close-task.sh 会做二次检查；偏差检查跨 PM 视图主文件 + 工程合同两处）
- **PM 视图主文件 + 工程合同必须成对处理**：归档 / merge / 清理时两文件一起动，不允许只动一份
- 不要手动执行 merge/删分支/清 worktree，全部由 close-task.sh 处理
- close-task.sh 一步关完：merge → 归档 → 删 worktree → 删 branch；不再走 `.runs/pending-cleanup.json` 中转

> **注**：`close-task.sh` 脚本在 PR 3 阶段会改造为按"主文件 + .engineering.md"成对归档；当前 PR 2 阶段脚本仍按单文件处理，工程合同需要 PM 在 close 后手动确认归档（或等 PR 3）。

## 末尾轻量 auto-chain（DX RU6）

close-task 完成后（full close 或 half-close），agent 检查 `task-plan.md`：

- If `PENDING > 0`, output:

  ```text
  ✅ task-NNN 已 close。
  下一个待启动：task-XXX（title，所属模块: [...]）。
  在本（req）窗口直接跑 /task-spec task-XXX → /task-confirm
  ```

- If `PENDING == 0`, output:

  ```text
  ✅ task-NNN 已 close。
  本 req 所有 task 已 close（含半 close）。在本（req）窗口运行 /req-stage-gate 推进 stage 7。
  ```
