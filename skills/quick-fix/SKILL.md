---
name: quick-fix
description: |
  不走 req/task 流程的 PM 审批快捷修复：在 tmp-quick-* worktree 完成小改动、检查红线、审批后 ff-only 合入启动位置对应的 base 分支（main 或 active req 分支）。
---

# /quick-fix

## When To Use

- PM 明确判断某个改动不需要完整 `/new-req` 流程或开新 task
- 适用于错别字、格式、链接、常量值、少量样式或 PM 明确认可的轻量代码改动
- 不适用于需要完整需求分析、task 拆分、自审或阶段验收的功能改动

## Mode（启动位置决定 base）

| 启动位置 | base 分支 | merge 目标 |
|---|---|---|
| 主仓根 + 当前 main | `main` | 主仓根 |
| `req-*` worktree（任意 req 分支） | 该 req 分支 | 该 req worktree |
| `task-*` worktree | **拒绝**（task 阶段走 `/task-execute`） | — |
| 其他 | 拒绝 | — |

base 由脚本 `ensure_quickfix_root` 自动推断，无需 `--base` 参数。

## Preamble

```bash
source "$(git rev-parse --show-toplevel)/.claude/scripts/skill-preamble.sh"
echo "SKILL: quick-fix"
```

## Workflow

### 步骤 1：确认 PM 意图

PM 必须给出一句话描述，例如：

```bash
/quick-fix "修正文档里的错别字"
```

如果 PM 的描述为空，或听起来像需要完整 req 流程的新功能，先询问 PM 是否改走 `/new-req`。

### 步骤 2：启动 quick-fix worktree

调用脚本创建隔离 worktree：

```bash
bash .claude/scripts/quick-fix.sh "<desc>"
```

脚本会输出：

```text
BASE_BRANCH: main 或 req-NNN-<slug>
BASE_HEAD: <sha>
BRANCH: tmp-quick-YYYYMMDD-HHMMSS-PID
WORKTREE: <主仓>/.worktrees/tmp-quick-YYYYMMDD-HHMMSS-PID
```

### 步骤 3：只在 worktree 内改文件

切换到脚本输出的 `WORKTREE` 路径后再做任何 Edit/Write：

```bash
cd "<WORKTREE>"
```

**禁止从 quick-fix worktree 写主仓路径。** 例如不要写：

```text
<MAIN_REPO_ROOT>/docs/...
<MAIN_REPO_ROOT>/src/...
```

跨 worktree 写主仓路径会被 hook 按 main 分支拦截，也会破坏 quick-fix 的隔离模型。

### 步骤 4：完成改动后让脚本收口

脚本会做：
1. 事后红线检查
2. TypeScript 改动的 `tsc --noEmit` 检查（除非 PM 使用 `--skip-tsc`）
3. 输出完整 diff
4. 等 PM 审批
5. 通过后提交 `[quick-fix]` 和 `[quick-fix-log]` 两个 commit
6. ff-only merge 到 BASE_BRANCH（main mode 合 main，req mode 合该 req 分支）；失败时自动 rebase BASE_BRANCH 后 retry
7. 成功后清理 tmp worktree 和分支

PM 审批选项：

```text
通过：合入 BASE_BRANCH
重做：保留 worktree，按反馈继续修改
取消：清理 worktree 和分支，BASE_BRANCH 不变
```

### 步骤 5：常用子命令

```bash
bash .claude/scripts/quick-fix.sh --skip-tsc "<desc>"
bash .claude/scripts/quick-fix.sh --force "<desc>"
bash .claude/scripts/quick-fix.sh --cancel tmp-quick-YYYYMMDD-HHMMSS-PID
bash .claude/scripts/quick-fix.sh --cleanup
bash .claude/scripts/quick-fix.sh --history 10
bash .claude/scripts/quick-fix.sh --snapshot
```

## Rules

- `/quick-fix` 是 main 与 active req 分支写保护的唯一例外，但只通过 `tmp-quick-*` worktree + PM 审批 + 脚本合并成立
- 必须从主仓 main 或 `req-*` worktree 启动；task worktree 内禁止（走 `/task-execute`）
- AI 只能在脚本创建的 quick-fix worktree 内修改文件
- 禁止修改 `requirements/active/*/tasks/*.md`
- 禁止修改 `requirements/active/*/.req-meta.json`
- 禁止修改 `.claude/scripts/`、`.claude/skills/`、`.claude/settings.json`
- PM 未明确”通过”前，不要手动 commit、merge 或删除 worktree
- 如果 ff-only/rebase 失败，保留 worktree，按脚本提示让 PM 决定手工处理或 `--cancel`
- req mode 下 base 分支由启动位置自动推断；不允许手动改 base（避免 PM 在 req-A worktree 跑了 quick-fix 却合到 req-B 分支）
