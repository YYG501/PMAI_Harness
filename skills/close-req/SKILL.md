---
name: close-req
description: |
  Req 关闭：写 close-report、更新 PRD、merge 到 main、归档。
---

# /close-req

## When To Use

- Orchestrator 在 stage 7 调用
- 所有 task 必须已关闭

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: close-req"
```

## Workflow

### 步骤 1：写 close-report.md

在 req 目录写 `close-report.md`，内容包括：

```markdown
# Req Close Report: req-NNN-<slug>

## 需求概述
[从 brief.md 提取]

## 完成的 task
| Task | 摘要 |
|------|------|
| task-001-xxx | [从执行日志提取] |
| task-003-xxx | [从执行日志提取] |

<!-- 仅当 tasks/discarded/ 下有文件时输出本段 -->
<details>
<summary>已废弃 task（N 个）</summary>

| Task | 废弃理由 |
|------|----------|
| task-002-xxx | [从该 task 文件的「废弃理由」section 摘要] |

</details>

## 文档变更
[列出本次 req 修改过的文档]

## 遗留问题
[如有未解决的问题或后续建议]
```

**生成规则：**
- 遍历 `tasks/*.md` 填「完成的 task」表（这里只剩已完成态，因为 stage 7 guardrail 要求所有未关闭 task 都收尾）。
- 遍历 `tasks/discarded/*.md` 填废弃栏；为空时整个 `<details>` 块省略。
- 已废弃 task 编号断号是合规信号，不要为「整理顺序」而改号。

### 步骤 2a：产出 req 级 PRD（必做）

调用 `/prd-writing` 产出 `$ACTIVE_REQ_DIR/prd.md`（req 级 PRD，本 req 范围一次性产物，定稿后不再修订）。

**这一步无条件做**——req 级 PRD 描述的是"本 req 范围内做了什么、为谁做、怎么验收"，不管 req 性质是产品功能、文档基础设施还是重构，本 req 都有自己的范围需要规格化。如果 PM 明确说本 req 不需要 req 级 PRD（例如极小的 hotfix），需要在 close-report.md「文档变更」section 显式记录跳过理由。

### 步骤 2b：增量同步项目主 PRD（按需）

判断本 req 是否对产品功能有变化（新增模块 / 已有模块扩展 / 角色变更 / 路线推进）。

- **有变化**：调用 `/project-prd-update`，从步骤 2a 产出的 req 级 PRD 增量并入 `docs/prd.md`。
- **无变化**（纯文档基础设施 / 纯重构 / 纯 bugfix）：跳过，并在 close-report.md「文档变更」section 写一行说明（如"本 req 是文档基础设施增强，未改产品功能，docs/prd.md 不更新"）。

### 步骤 2c：检查 req 级实现深度变更，提示 PM 是否同步项目级（4.5d.3）

读 `$ACTIVE_REQ_DIR/solution.md` 的 `## 🔧 本轮实现深度变更` section。

- 内容是「无变更」/ 留空 / section 不存在（旧 req 兼容）→ 跳过本步
- 内容含变更描述 → 向 PM 呈交两段：
  1. **req 级变更内容**（solution.md `## 🔧 本轮实现深度变更` 原文）
  2. **项目级当前**：`$REPO_ROOT/CLAUDE.md` 的 `## 工程结构约束` section（auto-detected 标 + 派生内容）

  问 PM：

  > 本 req 改了项目代码架构。是否把变更同步到项目级 `CLAUDE.md`「## 工程结构约束」段（让后续 req 默认按新深度走）？
  > - **[Y] 同步**：PM 手改 `$REPO_ROOT/CLAUDE.md`「## 工程结构约束」段，删 auto-detected 标后视为手填，框架不再覆盖
  > - **[N] 不同步**：本 req 是一次性升级 / 试验，不影响后续 req 默认深度（项目级保持原档）

  - PM 选 **Y**：AI 不替 PM 改项目级（手改 = PM 决策落地，AI 不抢）；提示 PM「请手改 `$REPO_ROOT/CLAUDE.md`，按本 req 升级写新版本」+ 等 PM 改完确认后再继续步骤 3
  - PM 选 **N**：不动，本步骤结束

**Why 不让 AI 自动改项目级**：项目级深度变更影响所有后续 req，是 PM 长期决策；AI 自动覆盖容易把试验性升级当成永久升级。让 PM 手改，PM 心智更明确「我在改全局规则」。

### 步骤 3：推进状态

```bash
python3 .claude/scripts/req-transition.py "$ACTIVE_REQ_DIR" --to 7
```

### 步骤 4：commit 所有改动

在 req worktree 中 commit 所有未提交的改动：

```bash
git add -A
git commit -m "close: req-NNN-<slug>"
```

### 步骤 5：执行关闭

```bash
bash .claude/scripts/close-req.sh "$ACTIVE_REQ_DIR"
```

脚本自动执行：
1. 校验 stage 为 7
2. 校验所有 task 已关闭
3. cd 到主仓，merge req 分支到 main
4. 把 req worktree + branch 写入 `.runs/pending-cleanup.json`（不立即删，避免父进程 cwd dangling）
5. 移动 req 目录到 `requirements/closed/`（在 req 分支上 commit 后随 merge 落地）
6. 更新 req 状态为 closed
7. 提示 PM：回主仓后跑 `bash scripts/cleanup-pending-worktrees.sh` 完成清理

### 步骤 6：确认结果

```
Req 已关闭：req-NNN-<slug>
当前位置：主仓 main 分支

worktree 和 branch 待清理。请退出当前会话，回主仓后跑：
  bash scripts/cleanup-pending-worktrees.sh

运行 /new-req 开始下一个需求。
```

## Rules

- 必须在 req worktree 中执行（先 commit，再调用 close-req.sh）
- close-req.sh 会自动 cd 到主仓执行 merge，不需要手动切换
- merge 到 main 后不可回退（stage 7 是终态）
- req 目录移到 closed/ 后保留完整记录
- worktree/branch 的实际删除由 PM 在主仓 cwd 跑 `cleanup-pending-worktrees.sh` 完成（避免 close 删自己脚下目录导致 Stop hook posix_spawn ENOENT）
