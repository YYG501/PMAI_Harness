---
name: pmai-quick-fix
description: |
  不走 req/task 流程的 PM 审批快捷修复：在 tmp-quick-* worktree 完成小改动、检查红线、审批后 ff-only 合入启动位置对应的 base 分支（main 或 active req 分支）。
---

# /pmai-quick-fix

## When To Use

- PM 明确判断某个改动不需要完整 `/pmai-new-req` 流程或开新 task
- 适用于错别字、格式、链接、常量值、少量样式或 PM 明确认可的轻量代码改动
- 不适用于需要完整需求分析、task 拆分、自审或阶段验收的功能改动

## Mode（启动位置决定 base）

| 启动位置 | base 分支 | merge 目标 |
|---|---|---|
| 主仓根 + 当前 main | `main` | 主仓根 |
| `req-*` worktree（任意 req 分支） | 该 req 分支 | 该 req worktree |
| `task-*` worktree | **拒绝**（task 阶段走 `/pmai-task-execute`） | — |
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
/pmai-quick-fix "修正文档里的错别字"
```

如果 PM 的描述为空，或听起来像需要完整 req 流程的新功能，先询问 PM 是否改走 `/pmai-new-req`。

### 步骤 2：启动 quick-fix worktree

调用脚本创建隔离 worktree：

```bash
bash "$PMAI_HOME/scripts/quick-fix.sh" "<desc>"
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

### 步骤 3.5：偏差扫描（commit 前必跑，不得跳过）

完成原始改动后、调用脚本收口（步骤 4）**前**——AI 必须按 §Drift Scan Reference 节执行偏差扫描，并按其中的标准模板（§3.5.3）输出区块给 PM 看。

触发逻辑：
1. 取当前分支（main / req-NNN-<slug>）
2. 取改动 target 类别（按 diff 命中文件路径分类——参见 §3.5.1 提示清单）
3. 翻 §3.5.1 表查"我在 X 分支改 Y，相关内容是 Z₁ Z₂ ..."
4. grep / Read 这些 Z 看实际命中
5. 按 §3.5.2 概念分类（当前合同 / 历史档案 / 分层 lazy sync）判断每个命中要不要也改
6. 把整套改动（原始 + 必要的相关同步）一次性 stage 到 quick-fix worktree
7. 按 §3.5.3 模板输出偏差扫描区块给 PM 看
8. 进入步骤 4 让脚本展示完整 diff 给 PM 审批

**short-circuit 例外**：当改动仅触及"叙述/格式类"（§📁 历史档案 / typo / 引用更新），AI 可输出简化版扫描区块（§3.5.3 简化版），不让 PM 答"决策性 vs 轻量"分类提问。

**三条 invariant 越界时拒绝执行**（详见 §3.5.1 req 分支表的"不改"行）：
- active req 阶段产物（brief / analysis / prd / task-plan）的决策性修订 → 引导 PM 走 `req-transition.py --rollback` 或 stage 3 `/pmai-prd-writing` revise
- active task 产出 → 引导 PM 走 `/pmai-task-execute` / `/pmai-task-submit` / `/pmai-close-task`
- 在 req 分支跑 quick-fix 改 `docs/**` → 引导 PM 改用 main quick-fix 或留给 close-req → `/pmai-doc-update`

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
bash "$PMAI_HOME/scripts/quick-fix.sh" --skip-tsc "<desc>"
bash "$PMAI_HOME/scripts/quick-fix.sh" --force "<desc>"
bash "$PMAI_HOME/scripts/quick-fix.sh" --cancel tmp-quick-YYYYMMDD-HHMMSS-PID
bash "$PMAI_HOME/scripts/quick-fix.sh" --cleanup
bash "$PMAI_HOME/scripts/quick-fix.sh" --history 10
bash "$PMAI_HOME/scripts/quick-fix.sh" --snapshot
```

## Drift Scan Reference

本节是步骤 3.5 偏差扫描的参考资料。AI 跑步骤 3.5 时翻这节查表 / 套概念 / 输出模板。

### 3.5.1 改动相关内容提示（指导性清单——非机械白名单）

按 `(分支 × 改对象)` 给 AI 一份"改 X 时同时考虑哪些相关内容"的提示。AI 改完一处后翻这份清单，**主动想到要查相关内容**，自己判断是否要也改。**遇到表外的 target 按 §3.5.2 概念分类自己推断**。

#### 在 main 分支

| 改对象 | 同时要考虑 |
|---|---|
| `prototypes/**` | `docs/modules/*.md`（项目级模块规格描述的功能形态）/ `docs/modules/INDEX.md`（模块用途索引）/ `docs/DESIGN.md`（视觉规范——涉及视觉时） |
| `docs/PROJECT/DESIGN/modules/prd.md` | `prototypes/**`（原型是否已反映新文档——反向同步）/ 文档间交叉引用 |
| `requirements/closed/<closed-req>/**`（含其内 tasks/） | 这是历史快照（引用更新 / 错别字 / 反映后续 req 变化）；通常不外溢。改"产品决策记录"= 改写历史，PM 要明确意图。**改完必须在被改文件末尾追加 visible §📝 后期修订记录 section**（详见 §3.5.2）|
| `templates/` / `.claude/scripts/` / `.claude/skills/` | §Rules 已禁止；走单独 PR 不走 quick-fix |
| **其他 target**（表外） | **按 §3.5.2 概念分类自己推断**——表外不是"无需扫"，是"AI 用概念判断" |

#### 在 req-NNN-<slug> 分支

| 改对象 | 同时要考虑 |
|---|---|
| `prototypes/**` | 本 req `prd.md`（功能规格——产品决策是否被撤销/修订）/ 本 req 实现设计文档（如存在——实现约束更新）/ 已 close 的 task PM 视图（产品事实变化记 `[quick-fix-log]`，task md 不改）/ `docs/modules/*` **不直接改**（留给 close-req → `/pmai-doc-update`） |
| `requirements/active/<本req>/brief.md` 或 `analysis.md` | PM 必先分类（criterion 见下方）：决策性 → 拒绝走 `--rollback`；轻量 → 允许 + 扫下游产物链 |
| `requirements/active/<本req>/prd.md` | 同上；决策性修订走 stage 3 `/pmai-prd-writing` revise；下游 task-plan / 已 close task md 引用是否要更新 |
| 已 close task 的 `task-NNN-*.md` / `.engineering.md` | **不改**（历史档案）；产品事实变化记 `[quick-fix-log]` |
| active task 产出 | **不改**（task 分支独家） |
| `docs/**`（项目级合同） | **不改**（在 main 跑或留给 close-req） |
| **其他 target**（表外） | **按 §3.5.2 概念分类自己推断**——同 main 分支 |

#### 「决策性 vs 轻量」判断 criterion

PM 在 req 分支 quick-fix 触及阶段产物（brief / analysis / prd / task-plan）时，AI 让 PM 明示分类。判断依据：

**决策性**（必走 stage-rollback / stage 3 `/pmai-prd-writing` revise）：
- 触动 §🎯 关键产品决策 / §📌 摘要 / §📦 交付物 / §🚦 跨功能产品规则 / §✅ 验收清单 等"产品决策载体"章节
- 改动会让下游 stage 产物 stale（analysis 改 → prd stale；prd 改 → task-plan stale；以此类推）

**轻量**（允许 quick-fix）：
- 仅触动 §📁 历史档案 / 引用更新（章节号变了）/ typo / 格式 / blockquote 等"叙述/格式载体"章节
- 改动不影响下游 stage 产物的语义

**Short-circuit**（PM 不必先分类，AI 直接走"轻量"路径）：
- diff 仅触及 §📁 历史档案 / 显著的引用更新 / 显然的 typo —— AI 在偏差扫描区块里说明"识别为轻量类，跳过分类提问"

**边界 case 由 PM 拍板**：AI 不确定时回单行问 PM "决策性 / 轻量"。

### 3.5.2 合同概念分类（指导原则）

让 AI 知道哪些是当前合同 / 哪些是历史档案 / 哪里是"分层 lazy sync 边界"，遇到表外的 target 时按概念推断：

```
当前合同（被改动撤销/修订时必须同步，扫描必扫）：
- 项目级活合同：docs/{PROJECT, DESIGN, modules, prd}.md
- 各 active req 的 stage 3 功能规格：prd.md（在飞旧 req 仍可能是 solution.md + solution.engineering.md）
- 项目代码：prototypes/

历史档案（修订是叙述维护，不强制反向扫；**但需追加可见的「后期修订记录」节**）：
- closed req 产出（含其内的 tasks/）：`requirements/closed/**`（包括 `requirements/closed/<closed-req>/tasks/*.md`）—— **仅在 main 分支跑 quick-fix 时适用**
- ⚠️ **active req 内已 close 的 task md**（`requirements/active/<active-req>/tasks/task-NNN-*.md`）虽然概念上也是历史档案，**但 SKILL Rules 已禁止 quick-fix 修改任何 active req 内的 task md**（无论该 task 已 close 还是 active）；本节的「后期修订记录」规则在该场景**不适用**——产品事实变化记入 `[quick-fix-log]`，由 close-req 阶段反映
- 格式：在被修订文件**末尾**新加一节（不存在则新建，已存在则 append 一行）：
  ````
  ## 📝 后期修订记录

  > YYYY-MM-DD quick-fix: <一句话本次修订内容>；commit <短 hash 待 commit 后回填或 TBD>
  ````
- 理由 1：历史档案的"叙述维护"如不留痕，后人翻档时无法分辨"哪行是当年写的、哪行是后期补的"
- 理由 2：用 **visible 新 section** 而不是 HTML 注释——audit trail 的读者是后人翻档，藏在 HTML 注释里看不到就失去意义
- 理由 3：在**末尾新加 section**而不是 append 到原 §📁 历史档案——保持 closed 时锁定的原有内容不变，新旧分明
- 与项目内的对照：工程合同 reconcile 末尾的 HTML 注释（input-flow §9.6.4）服务的是脚本机械 audit（PM 不看），形式不通用；quick-fix 改历史档案是 PM 决策的修订，必须 visible

分层 lazy sync 边界（不立刻同步，由后续流程统一处理）：
- 项目级 docs 变更 ↔ 各 active req prd → close-req 阶段 /pmai-doc-update 处理
- main 上原型变更 ↔ 各 active req → 各 req 自己 close-req 时处理
```

**术语澄清**：本节的"分层 lazy sync"指**项目级 ↔ req 级**或 **main ↔ req** 的跨层合同关系；和 `_shared/pm-view/input-flow.md` §9.6 定义的"PM 视图主文件 ↔ 工程合同"双文件 lazy sync 是**同型机制不同对象**——别混淆。§9.6 的 reconcile 流程不直接服务于 quick-fix；quick-fix 偏差扫描是 close-req `/pmai-doc-update` 之前的轻量补丁。

### 3.5.3 偏差扫描输出格式（标准模板）

quick-fix commit 前 AI 必须按以下模板输出区块给 PM 看：

```
偏差扫描

我改了：
  - <file>:<行号或段落>  — <一句话本次改动>
  ...

扫描范围（按 §3.5.1 提示清单）：
  分支：<main / req-NNN-<slug>>
  改对象类别：<prototypes / docs/ / closed req / 阶段产物 / ...>
  §3.5.1 提示要查：
    - <file 1>
    - <file 2>
    ...

实际扫描结果：
  - <file>:<段落> — 命中 / 未命中 — <相关性判断一行>
  ...

按 §3.5.2 概念分类的判断：
  - 必同步（当前合同被撤销）：<list 或 "无">
  - 不外溢但需追加「后期修订记录」（历史档案被修订）：<list 或 "无">
  - 分层 lazy sync deferred：<list 或 "无">

整套改动方案：
  - 原始改动：<list>
  - 同步追加：<list 或 "无相关合同需同步">
  - 后期修订记录追加（历史档案修订）：<list 或 "无">

进入 commit + merge 流程（PM 审批 `通过 / 重做 / 取消`）。
```

> **后期修订记录注意**：当原始改动本身就在 `requirements/closed/**`（含 closed req 内的 tasks/）上时，
> AI 必须在该文件末尾新加（或 append 到已有的）`## 📝 后期修订记录` section，加一条 visible blockquote：
>
> ```
> > YYYY-MM-DD quick-fix: <一句话>; commit <短 hash 或 TBD>
> ```
>
> commit hash 在脚本 commit 后由人/脚本回填，或先留 TBD。这条记录和原始改动一起进
> quick-fix worktree，被 PM 在 diff 里一并审批。

#### 简化版（short-circuit 时使用）

当改动仅触及"叙述/格式类"（§📁 历史档案 / typo / 引用更新），AI 输出简化版：

```
偏差扫描

我改了：<file>:<段落>  — <typo / 引用更新 / 历史档案补一行 等叙述类>
识别为轻量类（仅触及 §📁 历史档案 / 格式 / 引用），跳过分类提问。
按 §3.5.2：无相关合同需同步。

进入 commit + merge 流程。
```

## Rules

- `/pmai-quick-fix` 是 main 与 active req 分支写保护的唯一例外，但只通过 `tmp-quick-*` worktree + PM 审批 + 脚本合并成立
- 必须从主仓 main 或 `req-*` worktree 启动；task worktree 内禁止（走 `/pmai-task-execute`）
- AI 只能在脚本创建的 quick-fix worktree 内修改文件
- 禁止修改 `requirements/active/*/tasks/*.md`
- 禁止修改 `requirements/active/*/.req-meta.json`
- 禁止修改 `.claude/scripts/`、`.claude/skills/`、`.claude/settings.json`
- PM 未明确”通过”前，不要手动 commit、merge 或删除 worktree
- 如果 ff-only/rebase 失败，保留 worktree，按脚本提示让 PM 决定手工处理或 `--cancel`
- req mode 下 base 分支由启动位置自动推断；不允许手动改 base（避免 PM 在 req-A worktree 跑了 quick-fix 却合到 req-B 分支）
- **quick-fix commit 前必跑「偏差扫描」步骤**（参见 §Drift Scan Reference 节）；AI 按 §3.5.3 模板输出区块给 PM 看；不得跳过；PM 审批仍是 `通过 / 重做 / 取消` 三选，不加新选项分散决策
- **三条 invariant 越界时拒绝执行 quick-fix**（详见 §Drift Scan Reference §3.5.1 req 分支表）：active req 阶段产物决策性修订 → 走 stage-rollback；active task 产出 → 走 task 流程；req 分支不改 docs/**
