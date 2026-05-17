---
name: close-task
description: |
  Task 关闭：对齐 task 文档与原型、检查文档偏差、归档运行时数据、merge 分支、清理 worktree。
  分两个 phase：task 窗口内 prepare（对齐 + 偏差处理 + commit）→ req 窗口 finalize（merge + 删 task worktree/branch）。
---

# /close-task

## 两阶段调用（必读）

`/close-task` 设计为两阶段调用，AI 根据 cwd 自动判断当前阶段：

- **Phase 1**（cwd 在 task worktree 内）：task md 对齐 / 偏差处理 / DESIGN.md 沉淀 / commit / 登记 marker
- **Phase 2**（cwd 在 req worktree 内）：merge → req、归档 .runs/、删 task worktree+branch、auto-chain

PM 体感：
1. 在 task 窗口验收通过后运行 `/close-task` → AI 走 Phase 1 → 提示切到 req 窗口
2. PM 切到 req 窗口
3. 在 req 窗口运行 `/close-task` → AI 走 Phase 2 → 完全关闭 + auto-chain

## When To Use

- 在 task 窗口验收通过后调用（启动 Phase 1）
- 切到 req 窗口后再次调用（执行 Phase 2）
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

## Phase 自动判断（入口）

AI 进入 skill 时先检测 cwd 决定走 Phase 1 还是 Phase 2：

```bash
REPO_ROOT="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." && pwd)"
CURRENT_WT="$(git rev-parse --show-toplevel)"
PENDING_MARKER="$REPO_ROOT/.runs/pending-close-task.json"
```

分流逻辑：

| cwd 位置 | marker 状态 | 走向 |
|---|---|---|
| task worktree 内（`.worktrees/task-*`） | 不存在 | **Phase 1**（正常对齐/偏差/commit 流程，结束时写 marker） |
| task worktree 内（同一 task） | 已存在 | **Phase 1 短路**（直接告知"已 ready，请切到 req 窗口"） |
| req worktree 内（`.worktrees/req-*`） | 存在 | **Phase 2**（merge + delete + 清 marker） |
| req worktree 内 | 不存在 | **报错**："没有待 finalize 的 task。请先在 task 窗口运行 /close-task" |
| 主仓或其他位置 | - | **报错**："请在 task 窗口或 req 窗口运行 /close-task" |

## 改造说明（D13 final, 2026-05-16, §0.1 token 启动成本）

<!-- WHY breadcrumb: D13 final 改造把 modulespec 沉淀从 close-task per-task 推到 close-req 末聚合。
     详见 docs/归档/完成/modulespec-维护/主方案.md。任何"为什么 close-task 不调 doc-update"
     的疑问先读那份方案 §0.1 + §1 + §3 vp-1。-->

**默认行为反转**：close-task **不调** `/doc-update`（任何模式都不调）。task close 只 merge + 归档，
**不动 docs/modules/*.md**。modulespec 维护推迟到 close-req 末统一 rewrite（doc-update §8 rewrite mode）。

**台 PM 心智模型注脚**（防误判）：

- 你跑完 `/close-task` 看不到 modulespec 变化 = **正常**（D13 设计，不是 bug）
- 沉淀在 `/close-req` 末批量发生，你那时一次审完整段 diff
- 这是为节省 N 次 doc-update 启动 token 成本（详见 §0.1）

### 旧 flag tombstone

旧版本支持的 `--skip-doc-update` / `--doc-update-now` flag **已于 D13 final 废弃**。
PM/AI 如带这两个 flag 调用 close-task：

```text
Error: --skip-doc-update / --doc-update-now 已废弃（D13 final, 2026-05-16）。
       close-task 不再调 doc-update；正常 close-task 即可，modulespec 由 close-req 末统一 rewrite。
       详见 docs/归档/完成/modulespec-维护/主方案.md。
```

→ 必须 exit non-zero（fail loud）；不要 silent ignore。

## Phase 1：在 task worktree 内执行

### 步骤 0：task 文档 ↔ 原型对齐

**目的**：PM 验收通过 ≠ task md 自动跟原型代码一致。task-execute 反馈循环故意只改原型代码，task md 业务字段（§🎯/§📐/§📋/§✅）在反馈循环里不跟——所有对齐工作集中到本步骤 batch 处理。close-task 前补齐对账，避免 task md 进入 req 分支后跟代码不符。

**执行位置**：cwd 已在 task worktree（agent 直接读代码 + 写 task md，无需跨 worktree）。

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

#### 0.3 PM 决议（每条逐条问，对话式）

每条差异呈交 PM 后问（AskUserQuestion 或 prose；不列字母，按 PM 自然语言意图分流）：

```
要怎么对齐这条？
 - 改 task md 对齐实际原型（最常见——原型迭代过、md 没跟上）
 - 改代码对齐 task md（少见——原型实现偏离了契约，需要回 task 窗口重做）
 - 这条不重要，跳过
```

**PM 回答的内部分流**：
- PM 说「改 md / md 对齐 / 改 task 文档」等 → AI 用 Edit 改 `$TASK_PM_VIEW`，改后展示 git diff，PM 满意进下一条
- PM 说「改代码 / 回退原型」等 → AI **不能自己改代码**。提示 PM：「这条对齐要回退原型。建议先关掉 close-task，回 task 窗口跑 /task-execute 重做后再 close。还是确认要在 close-task 阶段直接改代码？」 → PM 坚持要在本阶段改 → 视为退出 close-task 流程，AI 输出"请回 task 窗口重做"并 exit
- PM 说「跳过 / 算了 / 不重要」等 → AI 不动 task md，进下一条

#### 0.4 patch 后 commit 到 task 分支

所有 Y 项 patch 完成后，统一 commit（cwd 已在 task worktree；保留 `-C "$TASK_WORKTREE"` 作为显式分支标注，提醒落在 task 分支不是 req 分支）：

```bash
git -C "$TASK_WORKTREE" add "<task-md 相对路径>"
git -C "$TASK_WORKTREE" commit -m "task-NNN close-prep: PM 视图与原型对齐"
```

理由：task md 改动在 task 分支落地后，Phase 2 的 merge 会自然带进 req 分支作为最终历史。

#### 0.5 fail-fast 与边界

- **N = 0 或全部跳过**：close-task **不阻塞**（PM 决策权，不强制对齐）。
- **PM 选"改代码"但又要在本阶段改**：agent 输出"请回 task 窗口跑 /task-execute"并 exit；不让 close-task 蜕变成 mini task-execute。
- **patch 失败 / git commit 失败**：close-task 阻塞，提示 PM 人工修复后重跑。

**与步骤 1 / 1.5 的边界**：

| 步骤 | 性质 | 对照源 |
|---|---|---|
| **0**（本节）| task md 描述 ↔ 原型代码 | task md §🎯 §📐 §📋 §✅ + 执行日志「文档对齐预告」 vs 实际改动文件 |
| 1 | task 实证发现的项目级文档偏差 | task md §历史档案/§10 vs brief/analysis/solution/module spec |
| 1.5 | PM 反馈中的视觉规范沉淀 | task md PM 反馈分类=视觉规范 vs docs/DESIGN.md |

性质不同，串行处理不合并。

### 步骤 1：偏差记录留作 close-req 聚合输入（D13 final, 不调 doc-update）

**D13 final 改造**：close-task **不调** `/doc-update`。偏差记录（PM 视图历史档案 + 工程合同 §10）原样保留在 task 文件里，由 close-req 步骤 1.5 聚合处理（按目标文档 rewrite OR patch）。

兼容性判断（仅用于校验偏差段是否存在 / 格式是否正确，不再触发 /doc-update）：

```bash
ENG_FILE="${TASK_FILE%.md}.engineering.md"
[ -f "$ENG_FILE" ] && HAS_ENG=true || HAS_ENG=false
```

校验（这一步必跑，是 close-req 聚合的输入约束）：

1. **PM 视图主文件** `## 📁 历史档案` 含 `### 业务层偏差` 段（即使是「无偏差」也要存在该段）
2. **工程合同** `## 10. 文档偏差` 表（仅 `HAS_ENG=true`；同样允许「无偏差」）

判断：
- **段缺失** → 报错让 PM 补段头（即使填「无偏差」）；不能省段，否则 close-req 聚合会找不到锚点
- **段存在（含「无偏差」或具体表内容）** → 继续下一步，**不调 /doc-update**

> **为什么不在这里调 /doc-update**：见本文件顶部「改造说明（D13 final）」。简言之，per-task 调 doc-update 是 N 次启动成本累加的根源（§0.1 痛点）；推迟到 close-req 末统一 rewrite。

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

#### 1.5.4 PM 决策（每条逐条问，对话式）

呈交 PM 一个对话式问句（AskUserQuestion 或 prose；不列字母代号）：

```
请选择此条反馈的处理方式：
 - 沉淀进 DESIGN.md（项目级长期规范 → AI patch DESIGN.md，不 commit，等你审 diff）
 - 只在本 task 备注（本 task 特殊情况，不通用 → 保留在 task PM 反馈，标 "task-only"）
 - 我分类错了（其实不是视觉规范 → 改回正确分类按那条规则走）
```

**PM 回答的内部分流 + 内部分类映射**：
- PM 说「沉淀 / 写进 DESIGN / 项目级」等 → 内部记账分类 `Y-rule` → AI 用 Edit patch `docs/DESIGN.md`（不 commit）
- PM 说「task 备注 / 只本 task / task-only」等 → 内部记账分类 `Y-task-note` → 保留在 task PM 反馈，标处理结果「task-only」
- PM 说「分类错了 / 不是视觉 / 重分类」等 → 内部记账分类 `N` → 改 task PM 反馈的分类字段为正确类型，按该类型原规则走

**禁止**：silent commit `docs/DESIGN.md`。设计 SoT 改动必须 PM 显式审 diff。commit 由 PM 在 close-task 完成后自己跑（commit message 模板：`docs(DESIGN): 沉淀 task-NNN 反馈 — [摘要]`）。

#### 1.5.5 沉淀 DESIGN.md 后的二次确认

每条选了"沉淀进 DESIGN.md"的 patch 完成后：

1. AI 输出 `git -C $REPO_ROOT diff docs/DESIGN.md` 让 PM 看
2. PM 满意 → AI 用 Edit 把本条 PM 反馈的「处理结果」改为「已处理」+ 备注「已沉淀 DESIGN.md §X.Y」
3. PM 要求修改 → AI 重 patch 重 diff，循环到 PM 满意（无循环上限，但 3 次还无法对齐时 AI 主动停下问 PM 是否改成"只在本 task 备注"或"分类错了"）

#### 1.5.6 完成后进步骤 2

所有 N 条视觉规范反馈处理完毕（每条都标了 `Y-rule` / `Y-task-note` / `N` 三个分类之一作为内部记账），DESIGN.md 改动**未 commit**（步骤 3 提示 PM 自己 commit），进入步骤 2。

**与步骤 1 文档偏差检查的边界**：
- 步骤 1 处理"客观文档偏差"（字段名错 / 流程描述错）→ `/doc-update` 对账
- 步骤 1.5 处理"主观视觉规范沉淀"（PM 判断哪些反馈应作项目级长期规范）→ AI 起草 + PM 三选一
- 性质不同，串行处理不合并

### 步骤 2：Phase 1 收尾：登记 finalize marker，提示 PM 切窗口

#### 2.1 兜底 commit 检查

phase 1 步骤 0 / 1 / 1.5 应该已经把改动 commit 完。这里二次检查，确保 task worktree 干净（除 docs/DESIGN.md，那个等 PM 二次审 diff 后手 commit）：

```bash
UNCOMMITTED=$(git status --porcelain | grep -v 'docs/DESIGN.md' || true)
if [ -n "$UNCOMMITTED" ]; then
  echo "❌ task worktree 有未 commit 改动（不含 DESIGN.md）："
  echo "$UNCOMMITTED"
  echo "请检查 step 0 / 1 是否漏 commit。"
  exit 1
fi
```

#### 2.2 写 marker

写 `$REPO_ROOT/.runs/pending-close-task.json`（marker 落主仓的 `.runs/`，因为 task worktree 会被 phase 2 删）：

```bash
mkdir -p "$REPO_ROOT/.runs"
python3 - "$PENDING_MARKER" "$TASK_FILE_ABS" "$TASK_BRANCH" "$TASK_WORKTREE" "$REQ_BRANCH" "$REQ_WORKTREE" <<'PY'
import json, sys, datetime
marker, task_file, t_branch, t_wt, r_branch, r_wt = sys.argv[1:7]
entry = {
    "task_file_abs": task_file,
    "task_branch": t_branch,
    "task_worktree": t_wt,
    "req_branch": r_branch,
    "req_worktree": r_wt,
    "ready_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}
with open(marker, "w") as f:
    json.dump(entry, f, indent=2, ensure_ascii=False)
PY
```

#### 2.3 输出切窗口指示

AI 向 PM 输出结束语，task 窗口工作到此结束：

```
✅ task-NNN 文档已对齐 / 偏差已处理 / 改动已 commit，已登记待 finalize marker。

请切到 req 窗口（cwd = req worktree），再次运行：

  /close-task

AI 会自动走 Phase 2 完成 merge + 删 task worktree/branch + auto-chain。
```

**如果步骤 1.5 patch 过 DESIGN.md**（uncommitted 状态），追加提示：

```
⚠️ 步骤 1.5 沉淀了 K 条视觉规范反馈到 docs/DESIGN.md（uncommitted）。
等 Phase 2 完成 task close 后，请在 req 窗口审 git diff docs/DESIGN.md 并 commit。
建议 commit message: docs(DESIGN): 沉淀 task-NNN 反馈 — [一行摘要]
```

**Phase 1 短路场景**：进入 skill 时检测到 marker 已存在（之前调过一次但 PM 没切窗口），跳过步骤 0 / 1 / 1.5 / 2.1 / 2.2，直接输出 2.3 切窗口指示。不要重复对齐 / 重复 commit。

## Phase 2：在 req worktree 内执行

### 步骤 P2.1：读 marker

```bash
if [ ! -f "$PENDING_MARKER" ]; then
  echo "❌ 没有待 finalize 的 task。"
  echo "   请先在 task 窗口运行 /close-task"
  exit 1
fi

TASK_FILE_ABS=$(python3 -c "import json; print(json.load(open('$PENDING_MARKER'))['task_file_abs'])")
```

### 步骤 P2.2：调 close-task.sh

```bash
bash .claude/scripts/close-task.sh "$TASK_FILE_ABS"
```

脚本自动：
1. 校验 cwd 在 req worktree 内（防御性二次校验）
2. 校验 task 状态为「已完成」
3. 检查文档偏差（二次检查，有未处理偏差会阻塞）
4. merge task 分支 → req 分支
5. 归档 `.runs/` 到 req worktree 的 `tasks/_archived/` 并 commit 到 req 分支
6. **直接删** task worktree + task branch
7. 杀掉 dev server 进程
8. 清理 `.runs/` 原件
9. 追加 `task_closed` 事件

### 步骤 P2.3：清 marker

```bash
rm -f "$PENDING_MARKER"
```

### 步骤 P2.4：确认 + auto-chain

脚本成功后，检查 `task-plan.md` 决定 auto-chain 提示：

- 若 `PENDING > 0`：

  ```
  Stage 6（task 执行）— task-NNN 已关闭

  下一步：task-XXX（<title>，所属模块: [...]）
  在本（req）窗口运行：/task-spec task-XXX → /task-confirm
  ```

- 若 `PENDING == 0`：

  ```
  Stage 6（task 执行）— task-NNN 已关闭，本 req 全部 task 已关闭

  下一步：在本（req）窗口运行 /req-stage-gate 推进至 Stage 7（req 关闭）。
  ```

**额外提示（仅当 Phase 1 步骤 1.5 patch 过 DESIGN.md 时）**：

```
⚠️ docs/DESIGN.md uncommitted（K 条视觉规范沉淀）。
请审 git diff docs/DESIGN.md 后在本（req）窗口 commit：
  git add docs/DESIGN.md && git commit -m "docs(DESIGN): 沉淀 task-NNN 反馈 — [摘要]"
```

## Rules

- Phase 1 必须在 task worktree 内执行；Phase 2 必须在 req worktree 内执行
- Phase 间通过 `$REPO_ROOT/.runs/pending-close-task.json` 衔接（marker 落主仓，因 task worktree 会被 phase 2 删）
- Phase 1 进入时若 marker 已存在 → 短路（直接告知"已 ready，请切窗口"），不重复对齐
- Phase 2 进入时若 marker 不存在 → 报错（避免误触）
- 必须在 task 状态为「已完成」时才能关闭
- **步骤 0 对齐**：N=0 或全 skip 不阻塞 close-task（PM 决策权）；PM 选 R 但要在本阶段改代码 → agent 拒绝并提示回 task-execute（不让 close-task 蜕变成 mini task-execute）
- 步骤 0 patch 必须 commit 到 task 分支（cwd 已在 task worktree），随 Phase 2 merge 自然进 req 分支
- 文档偏差必须在 Phase 1 处理（close-task.sh 会做二次检查；偏差检查跨 PM 视图主文件 + 工程合同两处）
- **PM 视图主文件 + 工程合同必须成对处理**：归档 / merge / 清理时两文件一起动，不允许只动一份
- 不要手动执行 merge/删分支/清 worktree，全部由 close-task.sh 处理
- close-task.sh 一步关完 phase 2：merge → 归档 → 删 worktree → 删 branch；不走 pending-cleanup 中转

> **注**：`close-task.sh` 脚本在 PR 3 阶段会改造为按"主文件 + .engineering.md"成对归档；当前 PR 2 阶段脚本仍按单文件处理，工程合同需要 PM 在 close 后手动确认归档（或等 PR 3）。
