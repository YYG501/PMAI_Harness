---
name: pmai-quick-fix
description: |
  不经完整需求流程的轻量修复：在临时隔离分支中完成错别字、链接、格式、少量样式或小幅代码改动，提交前执行偏差扫描，经 PM 审批后合并回主线。
---

# /pmai-quick-fix

## 入口护栏

执行本 skill 前先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止本 skill，只引导 PM 先发 `/pmai-init-project`。初始化或已有代码接入完成前，不要开启轻量修复隔离环境或改业务代码。

若由 `/pmai-lark-review` 进入，先完整读取 `skills/lark-review/references/lifecycle-handoff.md`。本批正式规格先在 T 中完成并由 lark-review apply；apply 前不启动 quick-fix worktree。apply 后本 skill 只处理规格之外的文件，正式规格不得进入 quick-fix diff；本批只有规格文字变化时跳过空 worktree和空提交。

> **PM 答题规则**：所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 四条硬规则走（空答 STOP / 没拿到答案禁止合入 / runtime 退化保留 wait / 多决策拆开顺序问）。

## When To Use

- PM 明确判断某个改动不需要完整 `/pmai-design` / `/pmai-build`。
- 适用于错别字、格式、链接、常量值、少量样式、很小的代码修补。
- 不适用于需要重新讨论范围、改模块规格、补验收路径或改一片功能的工作；这类走 `/pmai-design` 或 `/pmai-build`。

## Mode

quick-fix 只面向当前主线的小改。脚本创建 `tmp-quick-*` worktree，PM 审批后合回 main。

| 启动位置 | 行为 |
|---|---|
| 主仓根 + 当前 main | 允许，base = main |
| `.worktrees/pmai-build-*` | 拒绝；先回主仓，并在原 `/pmai-build` 会话继续或用 `/pmai-status` 恢复 |
| 其他分支 / 历史 worktree | 拒绝；避免把小修合进错误基线 |

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: quick-fix"
```

## Workflow

### 步骤 1：确认 PM 意图

PM 必须给出一句话描述：

```bash
/pmai-quick-fix "修正文档里的错别字"
```

描述为空，或听起来像新功能 / 规格变化 / 验收变化时，先问 PM 是否改走 `/pmai-design`。

### 步骤 2：启动 quick-fix worktree

```bash
bash "$PMAI_HOME/scripts/quick-fix.sh" "<desc>"
```

脚本会输出：

```text
BASE_BRANCH: main
BASE_HEAD: <sha>
BRANCH: tmp-quick-YYYYMMDD-HHMMSS-PID
WORKTREE: <主仓>/.worktrees/tmp-quick-YYYYMMDD-HHMMSS-PID
```

### 步骤 3：只在 worktree 内改文件

切换到脚本输出的 `WORKTREE` 路径后再做任何 Edit/Write：

```bash
cd "<WORKTREE>"
```

禁止从 quick-fix worktree 写主仓绝对路径。跨 worktree 写主仓会破坏隔离模型。

### 步骤 3.5：偏差扫描（commit 前必跑）

完成原始改动后、调用脚本收口前，AI 必须做偏差扫描：

1. 取本次 diff 命中的文件路径。
2. 按 §3.5.1 查该改动可能影响哪些长期合同。
3. grep / Read 相关文件，判断是否要同步。
4. 把原始改动 + 必要同步一次性 stage 到 quick-fix worktree。
5. 按 §3.5.3 模板输出区块给 PM 看。
6. 进入步骤 4 让脚本展示完整 diff 给 PM 审批。

short-circuit：仅 typo / 格式 / 引用更新时，可输出简化版扫描区块，不问额外分类。

**越界时拒绝 quick-fix**：
- 改动会改变模块 `spec.md` 的核心产品决策 → 走 `/pmai-design` 重新拍板，并由 `/pmai-spec-writing` 模块规格目标修订 `spec.md`。
- 改动会在 `.pm-workflow/project.yml` 声明的实现入口新增或大改一片功能 → 走 `/pmai-build`。
- 改动会改项目级规则 / 术语并需要产品判断 → 走 `/pmai-record` 或 `/pmai-design`；已经进入 build 则回原 `/pmai-build` 继续统一 lifecycle。

### 步骤 4：完成改动后让脚本收口

脚本会做：

1. 事后红线检查。
2. TypeScript 改动的 `tsc --noEmit` 检查（除非 PM 使用 `--skip-tsc`）。
3. 输出完整 diff。
4. 等 PM 审批。
5. 通过后提交 `[quick-fix]` 和 `[quick-fix-log]` 两个 commit。
6. ff-only merge 到 main；失败时自动 rebase main 后 retry。
7. 成功后清理 tmp worktree 和分支。

PM 审批选项：

```text
通过：合入 main
重做：保留 worktree，按反馈继续修改
取消：清理 worktree 和分支，main 不变
```

### 步骤 5：常用子命令

```bash
bash "$PMAI_HOME/scripts/quick-fix.sh" --skip-tsc "<desc>"
bash "$PMAI_HOME/scripts/quick-fix.sh" --force "<desc>"
bash "$PMAI_HOME/scripts/quick-fix.sh" --cancel tmp-quick-YYYYMMDD-HHMMSS-PID
bash "$PMAI_HOME/scripts/quick-fix.sh" --cleanup
bash "$PMAI_HOME/scripts/quick-fix.sh" --history 10
bash "$PMAI_HOME/scripts/quick-fix.sh" --snapshot
```

## Drift Scan Reference

### 3.5.1 改动相关内容提示

| 改对象 | 同时要考虑 |
|---|---|
| `project.yml` 声明的实现路径 | 对应 `docs/modules/<模块>/spec.md`、`docs/modules/<模块>/decisions.md`、`DESIGN.md`、`PRODUCT-STATE.md` |
| `docs/modules/<模块>/spec.md` | 当前 build target 是否已反映、`docs/modules/<模块>/decisions.md` 是否需要记录为什么、`PRODUCT-RULES.md` 是否有跨模块规则冲突 |
| `docs/modules/<模块>/decisions.md` | `spec.md` 是否要同步结论、`PRODUCT-RULES.md` 是否已有更高层规则 |
| `PRODUCT-STATE.md` | `docs/modules/INDEX.md`、相关模块 `spec.md`、主原型是否一致 |
| `PRODUCT-RULES.md` | 相关模块 `decisions.md` / `spec.md` 是否需要引用或避免冲突 |
| `DESIGN.md` | Web build target 是否遵循；若只是视觉规则文字修订，不强制改实现 |
| `docs/inputs/**` | 只改材料归档 / 引用，不反向改产品合同 |
| `templates/` / `scripts/` / `skills/` | 这是框架自身改动；小修可做，但要跑相关测试，不按产品合同扫描 |
| 其他 target | 按 §3.5.2 概念分类自行推断 |

### 3.5.2 合同概念分类

```text
当前合同（被改动撤销/修订时必须同步，扫描必扫）：
- 项目级活合同：PRODUCT-STATE.md / PRODUCT-RULES.md / DESIGN.md
- 模块合同：docs/modules/<模块>/discussion.md / decisions.md / spec.md
- 项目代码：`.pm-workflow/project.yml:implementation.entrypoints`

历史档案（只作叙述维护，不强制反向扫）：
- docs/archive/**
- docs/archive/** 中明确标为历史或已废弃的设计稿

输入材料（证据，不是产品合同）：
- docs/inputs/**
```

### 3.5.3 偏差扫描输出格式

```text
偏差扫描

我改了：
  - <file>:<行号或段落> — <一句话本次改动>

扫描范围：
  改对象类别：<prototype / module spec / product rules / template / ...>
  按 §3.5.1 提示要查：
    - <file 1>
    - <file 2>

实际扫描结果：
  - <file>:<段落> — 命中 / 未命中 — <相关性判断一行>

按 §3.5.2 概念分类的判断：
  - 必同步：<list 或 "无">
  - 历史档案：<list 或 "无">
  - 输入材料：<list 或 "无">

整套改动方案：
  - 原始改动：<list>
  - 同步追加：<list 或 "无相关合同需同步">

进入 commit + merge 流程（PM 审批 `通过 / 重做 / 取消`）。
```

简化版：

```text
偏差扫描

我改了：<file>:<段落> — <typo / 引用更新 / 格式修正>
识别为轻量类。按 §3.5.2：无相关合同需同步。

进入 commit + merge 流程。
```

## Rules

- `/pmai-quick-fix` 只通过 `tmp-quick-*` worktree + PM 审批 + 脚本合并成立。
- AI 只能在脚本创建的 quick-fix worktree 内修改文件。
- PM 未明确"通过"前，不要手动 commit、merge 或删除 worktree。
- 如果 ff-only/rebase 失败，保留 worktree，按脚本提示让 PM 决定手工处理或 `--cancel`。
- quick-fix commit 前必跑偏差扫描；不得跳过。
