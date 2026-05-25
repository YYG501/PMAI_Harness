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

## task 文件形态（delta-3）

task-spec 产 **单文件 typed contract**（`task-NNN-<slug>.md`，三区：PM 确认区 / 执行区 /
审计区）。本 skill：
- **文档偏差检查在单文件**：审计区的「📋 文档偏差」section（不再跨两文件）。
- **归档单文件**：merge / 归档 / 清理只动一个 `.md`。
- **三态兼容**：在飞旧 v2 双文件 task 仍按双文件成对处理（用 `detect_format` 分流）。

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

**目的**：PM 验收通过 ≠ task md 自动跟原型代码一致。task-execute 反馈循环故意只改原型代码，task 文件的实现规格 / 验收 / 范围在反馈循环里不跟——所有对齐工作集中到本步骤 batch 处理。close-task 前补齐对账，避免 task md 进入 req 分支后跟代码不符。

**执行位置**：cwd 已在 task worktree（agent 直接读代码 + 写 task md，无需跨 worktree）。

#### 0.1 加载对照源

agent 读两边内容：

- **task 文件**（在 task worktree 里，单文件 typed contract）：
  - 执行区 `## 🔧 实现规格`（task 级实现要求）
  - 执行区 `## 🧩 实现设计引用`（HOW-ID 行 + 占位值）
  - PM 确认区 `## ✅ 验收清单`（PM 走查清单）
  - PM 确认区 `## 📦 范围`（改 / 不改）
  - 审计区 `## 📁 历史档案 → 执行日志`：执行报告里 AI 记的改动摘要 / 遇到的问题，作为对齐线索
- **task 改动的代码文件**（task 文件 PM 确认区 §📦 范围 → 改 字段列出的路径）：
  - 全文 Read（不超过 3 个文件就全读；多文件时按对齐相关性分批读）

```bash
TASK_WORKTREE="$REPO_ROOT/.worktrees/$TASK_BRANCH"
TASK_FILE="$TASK_WORKTREE/<task 文件相对路径>"
# 改动文件清单从 §📦 范围 → 改 提取
```

#### 0.2 语义对齐扫描

agent 对执行区·实现规格 / PM 确认区·验收清单 / 范围 的每条描述，跟实际代码做语义比对，输出**不一致项**（每项一行，附 task md 行号 + 代码 file:line）。

**扫描优先级**：
1. **优先**：执行日志「文档对齐预告」字段提到的所有段（这些是 AI 反馈循环里已经预告会变的，命中率高）
2. **覆盖**：四个段全量扫一遍兜底（防止预告遗漏 / 反馈中提到但未预告的段）

输出格式（每条差异 AI 自判 A 类 / B 类）：

```text
对齐扫描（共 N 处差异）：

1. [A] task 文件 执行区·实现规格 #3 描述：「...」
   代码 path/file.tsx:LXX 实际：「...」
   → 文档落后于代码，改 task md 对齐即可

2. [B] task 文件 PM 确认区·验收清单 #2：「...」
   代码 path/file.tsx:LXX 实际：「...」
   → B 类原因：代码未满足该验收项（疑似代码做错）

...
```

**A 类 / B 类判定标准**：

| 类 | 条件 | 处理 |
|---|---|---|
| **A 类**（默认对齐，不问 PM）| 文档落后于代码——task md 描述过期，代码是 PM 验收通过的合理实现，改 task md 即可对齐 | §0.3 AI 直接 Edit 对齐 |
| **B 类**（呈交 PM）| 命中下列任一「必要」情况 | §0.3 逐条呈交 PM |

B 类的三种「必要」情况：
1. **代码可能做错**——不一致暴露代码没满足验收清单某条 / 与契约冲突
2. **需回退原型代码**——改文档解决不了，要改代码才能对齐
3. **范围变了**——代码动了 `§📦 范围·改` 字段之外的文件

判不准属 A 还是 B → 算 B（呈交 PM）。

**N = 0 → 直接进步骤 1**，本步骤跳过。

#### 0.3 对齐处理（A 类默认对齐 · B 类才呈交 PM）

> **原则**：PM 验收通过 = 代码已是对的。文档对齐到代码是收尾的机械活，不开逐条确认门——
> A 类默认 AI 处理，只有 B 类（命中「必要」情况）才打断 PM。处理结果在步骤 2.3 汇总。

**A 类（默认对齐，不问 PM）**：AI 用 Edit 改 `$TASK_FILE`，把过期描述对齐到代码实际。
记下「对齐了哪几段」，留给步骤 2.3 汇总。

**B 类（逐条呈交 PM）**：每条 B 类呈交 PM 后问（AskUserQuestion 或 prose；按 PM 自然语言意图分流）：

```
这条对齐要你定一下（B 类原因：<§0.2 自判的原因>）：
 - 改 task md 对齐实际原型
 - 改代码对齐 task md（需回 task 窗口重做）
 - 这条不重要，跳过
```

**PM 回答的内部分流**：
- PM 说「改 md / md 对齐 / 改 task 文档」等 → AI 用 Edit 改 `$TASK_FILE`，改后展示 git diff
- PM 说「改代码 / 回退原型」等 → AI **不能自己改代码**。提示 PM：「这条对齐要回退原型。建议先关掉 close-task，回 task 窗口跑 /task-execute 重做后再 close。还是确认要在 close-task 阶段直接改代码？」 → PM 坚持要在本阶段改 → 视为退出 close-task 流程，AI 输出"请回 task 窗口重做"并 exit
- PM 说「跳过 / 算了 / 不重要」等 → AI 不动 task md，进下一条

**无 B 类（全 A 类，或 N=0）**：本步骤不打断 PM，对齐完直接进步骤 0.4。

#### 0.4 patch 后 commit 到 task 分支

所有 Y 项 patch 完成后，统一 commit（cwd 已在 task worktree；保留 `-C "$TASK_WORKTREE"` 作为显式分支标注，提醒落在 task 分支不是 req 分支）：

```bash
git -C "$TASK_WORKTREE" add "<task-md 相对路径>"
git -C "$TASK_WORKTREE" commit -m "task-NNN close-prep: PM 视图与原型对齐"
```

理由：task md 改动在 task 分支落地后，Phase 2 的 merge 会自然带进 req 分支作为最终历史。

#### 0.5 fail-fast 与边界

- **N = 0**：本步骤跳过，close-task 不阻塞。
- **全 A 类**：AI 默认对齐完即进步骤 0.4，不阻塞、不打断 PM。
- **B 类全部跳过**：close-task 不阻塞（PM 决策权，不强制对齐）。
- **PM 选"改代码"但又要在本阶段改**：agent 输出"请回 task 窗口跑 /task-execute"并 exit；不让 close-task 蜕变成 mini task-execute。
- **patch 失败 / git commit 失败**：close-task 阻塞，提示 PM 人工修复后重跑。

**与步骤 1 / 1.5 的边界**：

| 步骤 | 性质 | 对照源 |
|---|---|---|
| **0**（本节）| task 文件描述 ↔ 原型代码 | 执行区·实现规格 / PM 确认区·验收清单·范围 + 审计区·执行日志 vs 实际改动文件 |
| 1 | task 实证发现的项目级文档偏差 | task md §历史档案/§10 vs brief / **stage 2 真相源**（A 分支 analysis.md / B 分支 stage2-office-hours.md）/ solution / module spec |
| 1.5 | PM 反馈中的视觉规范沉淀 | task md PM 反馈分类=视觉规范 vs docs/DESIGN.md |

性质不同，串行处理不合并。

### 步骤 1：偏差记录留作 close-req 聚合输入（D13 final, 不调 doc-update）

**D13 final 改造**：close-task **不调** `/doc-update`。偏差记录原样保留在 task 文件里，由
close-req 步骤 1.5 聚合处理（按目标文档 rewrite OR patch）。

校验（这一步必跑，是 close-req 聚合 + delta-7 adjustment-promote 的输入约束）：

- **v3 单文件**：审计区 `## 📋 文档偏差` 表存在（即使是「无」也要存在该段）
- **v2 旧双文件**：PM 视图 `### 业务层偏差` 段 + 工程合同 `## 10. 文档偏差` 表（兼容）

用 `detect_format` 分流。判断：
- **段缺失** → 报错让 PM 补段头（即使填「无」）；不能省段，否则 close-req 聚合 +
  delta-7 promote 会找不到锚点
- **段存在（含「无」或具体表内容）** → 继续 §1.1 分类，**不调 /doc-update**

> **为什么不在这里调 /doc-update**：见本文件顶部「改造说明（D13 final）」。简言之，per-task 调 doc-update 是 N 次启动成本累加的根源（§0.1 痛点）；推迟到 close-req 末统一 rewrite。

#### 1.1 偏差分类：纠错 vs 计划外简化（v2 / D3）

读审计区·📋 文档偏差表。**对每条非「无」偏差行**逐条 AI 分类：

| 类别 | 判别 | 处理 |
|---|---|---|
| **纠错偏差**（默认）| 偏差是「文档写错了 → 按代码改对」—— 字段名错 / 流程描述错 / 文案过期 | 留原表不动；close-task.sh phase 2 把它 promote 成 `adjustment` 事件，close-req §2a 反向覆盖 PRD（原路径不变）|
| **计划外简化**（v2 D3 新增）| 偏差是「task 执行期临时决定少做某功能 / 边界 / 流程」—— 实现比 PRD 写的少、但不属于 stage 5 PM 主动决策的 SIMP-N（不在 implementation-design.md 段 1.5 已登记范围）| **停下问 PM**：是否回填 implementation-design.md 段 1.5（补 SIMP-NN）—— 见 §1.2 |

**AI 分类启发式**（pattern 沉淀，非阈值脚本，memory `feedback_judgment_pattern_not_mechanization`）：

- 「实际实现」字段比「文档原文」**少做了一段**（不是改错而是少做）→ 倾向计划外简化
- 「实际实现」字段比「文档原文」**做的是另一种实现**（同范围、不同方式）→ 纠错偏差
- 「建议改法」字段写「按代码对齐文档」→ 纠错；写「文档保留，原型本期不做」/「下个 req 再做」
  → 计划外简化
- task PM 确认区·验收清单受影响行有 `[SIMP-N]` 标签 → 此条已在计划内，**不应在偏差表登记**
  （C3 carve-out；若已登记 → 提示 executor 自审失职，AI 帮删该行 + 提醒 PM）

判不准 → 当**计划外简化**问 PM（让 PM 判，AI 不假装会判）。

#### 1.2 计划外简化：停下问 PM 回填 implementation-design.md（C9 限定 close-time）

对每条计划外简化偏差呈交 PM：

```
本 task 偏差表第 N 行像「原型本期临时少做」（不是文档写错）：
 - 文档原文：<偏差行第 2 列>
 - 实际实现：<偏差行第 3 列>

这是计划内简化（应该回填 stage 5 implementation-design.md 段 1.5 SIMP-NN，让 close-req
正确标注 PRD），还是真偏差（按原路径 promote adjustment 覆盖 PRD）？

 - 回填 simp 段（推荐 —— PRD 保留真实需求 + 加「原型本次计划简化为」标注）
 - 按 adjustment promote（PRD 改成实际做成的样子；真实需求只在 req-events.before 留痕）
 - 跳过这条不处理（PM 自己事后决策）
```

**PM 回答的内部分流**：

- PM 选「回填 simp 段」→ AI 用 Edit 在 implementation-design.md 段 1.5 末追加一行：
  - SIMP-ID 顺延接（读现有最大 SIMP-NN，+1）
  - PRD 锚点 = 偏差行第 1 列「文档位置」
  - 真实需求 = 「见 PRD <文档位置>」引用
  - 原型本次计划简化为 = 偏差行第 3 列「实际实现」
  - 为什么简化 = PM 给的理由（追问一句「为什么本期少做这块」）
  - 来源 = `kind 1 (close-task 回填)`
  - 同步在 task 偏差表把该行删除 + 在 task PM 确认区·验收清单受影响行追加 `[SIMP-N]` 标签
  - **C9 限定**：回填只在 close-time（本步骤）发生；**不**触发已完成 task 重新生成 / 不**回退**
    其他已 closed task 的 task-spec / 不**重生成**当前 task。类比 close-req PRD 反向对齐 ——
    本步骤是「写入设计文档」的 close 时一次性动作，下游 task 不重跑。
- PM 选「按 adjustment promote」→ 偏差行留原表不动（走原路径）
- PM 选「跳过」→ 偏差行留原表不动，备注「PM 选择不分类」

#### 1.3 全部分类完成后

进入步骤 1.5（视觉规范）。phase 2 close-task.sh 仍按原逻辑 promote 偏差成 adjustment ——
回填 simp 的行已经从偏差表删了，不会 promote；adjustment 路径的行照走。

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

#### 1.5.4 沉淀处理（默认 promote · 拿不准才问 PM）

> **原则**：分类已是「视觉规范」的反馈，默认就是项目级长期规范——AI 直接 patch
> `docs/DESIGN.md`（不 commit），不逐条问。只有 AI 拿不准的才打断 PM。

**默认 promote（不问 PM）**：AI 判定该条确属项目级视觉规范 → 用 Edit patch
`docs/DESIGN.md`（**不 commit**），内部记账分类 `Y-rule`。

**拿不准才逐条问 PM**：仅当 AI 判断该条可能是 task-local 特例（不通用）、或可能分类
错了（其实不是视觉规范）→ 呈交 PM 一个对话式问句：

```
这条反馈我拿不准（[反馈摘要]）：
 - 沉淀进 DESIGN.md（项目级长期规范）
 - 只在本 task 备注（task 特例，不通用）
 - 分类错了（其实不是视觉规范）
```

**PM 回答的内部分流 + 内部分类映射**：
- PM 说「沉淀 / 写进 DESIGN / 项目级」等 → 记账 `Y-rule` → AI 用 Edit patch `docs/DESIGN.md`（不 commit）
- PM 说「task 备注 / 只本 task / task-only」等 → 记账 `Y-task-note` → 保留在 task PM 反馈，标处理结果「task-only」
- PM 说「分类错了 / 不是视觉 / 重分类」等 → 记账 `N` → 改 task PM 反馈的分类字段为正确类型，按该类型原规则走

**禁止**：silent commit `docs/DESIGN.md`。DESIGN.md 改动 patch-不-commit，PM 在 close
收尾审总 diff 自己 commit（步骤 2.3 提示）——这一步总审是 PM 对默认 promote 的把关。

#### 1.5.5 沉淀后记账

每条 promote 的 patch 完成后，AI 把该条 PM 反馈的「处理结果」改为「已处理」+ 备注
「已沉淀 DESIGN.md §X.Y」。**不逐条给 PM 看 diff** —— DESIGN.md 总 diff 由步骤 2.3
汇总，PM 在 close 收尾时一次性审、当场可撤。

#### 1.5.6 完成后进步骤 1.6

所有 N 条视觉规范反馈处理完毕（每条都标了 `Y-rule` / `Y-task-note` / `N` 三个分类之一作为内部记账），DESIGN.md 改动**未 commit**（步骤 3 提示 PM 自己 commit），进入步骤 1.6。

### 步骤 1.6：跨功能产品行为规则反馈 selective promote 到 PRODUCT-RULES.md（delta-9 vp-2）

与步骤 1.5「视觉规范 → DESIGN.md」同型 —— 扫本 task PM 反馈，对**全项目跨功能产品行为
规则**类条目逐条处理：默认 promote 到 `docs/PRODUCT-RULES.md`，AI 拿不准的才问 PM。

#### 1.6.1 前置检查

```bash
PRODUCT_RULES_MD="$MAIN_REPO_ROOT/docs/PRODUCT-RULES.md"
if [ ! -f "$PRODUCT_RULES_MD" ]; then
  echo "ℹ️  docs/PRODUCT-RULES.md 不存在，跳过跨功能规则沉淀。"
  # 直接进入步骤 2
fi
```

#### 1.6.2 扫描候选 + AI 预判

Read 本 task 审计区·历史档案的 PM 反馈段，AI 预判哪些条目属「**全项目跨功能产品行为规则**」
——适用范围超出本 task 模块、是「产品在 X 情况下应 / 不应 Y」的规则、向前管未写的 task。
候选数 = N。**N = 0 → 直接进步骤 2**。

> 边界：用词 / 术语 → PROJECT.md 术语表；模块级规则 → modulespec；视觉规范 → DESIGN.md
> （步骤 1.5 已处理）；task-local / 同模块前瞻 → 留 task 文件。本步骤只捞全项目跨功能规则。

#### 1.6.3 promote 处理（默认 promote · 拿不准才问 PM）

> **原则**：AI 预判为「全项目跨功能产品行为规则」的，默认 promote 到
> `docs/PRODUCT-RULES.md`（不 commit），不逐条问。只有拿不准的才打断 PM。

**默认 promote（不问 PM）**：AI 判定该条确属全项目跨功能规则 → 用 Edit 把条目追加进
`docs/PRODUCT-RULES.md`「规则清单」段（**不 commit**）。条目格式：

```
### <一句话标题>
- 规则：<产品在 X 情况下应 / 不应 Y>
- scope：全局 | 域限定:<关键词>
- 来源：<本 req / task>（<日期>）
```

**拿不准才逐条问 PM**：仅当 AI 判断该条可能够不上「全项目跨功能规则」（够不上全项目、
或该归术语表 / modulespec / DESIGN.md）→ 呈交 PM：

```
这条我拿不准（[反馈摘要]）：
 - promote 进 PRODUCT-RULES.md（全项目跨功能规则）
 - 不是跨功能规则（留 task 或改归别处）
```

- PM 选 promote → AI 追加进 PRODUCT-RULES.md（不 commit）
- PM 说不是 → 不动 PRODUCT-RULES.md，按 PM 指示归类

PRODUCT-RULES.md 改动 patch-不-commit，PM 在 close 收尾审总 diff 自己 commit。

#### 1.6.4 完成后进步骤 2

PRODUCT-RULES.md 改动**未 commit**（步骤 3 提示 PM）；进入步骤 2。

**与步骤 1 文档偏差检查的边界**：
- 步骤 1 处理"客观文档偏差"（字段名错 / 流程描述错）→ `/doc-update` 对账
- 步骤 1.5 处理"视觉规范沉淀"（AI 默认 promote 项目级视觉规范，拿不准才问 PM）→ patch DESIGN.md
- 性质不同，串行处理不合并

### 步骤 2：Phase 1 收尾：登记 finalize marker，提示 PM 切窗口

#### 2.1 兜底 commit 检查

phase 1 步骤 0 / 1 / 1.5 / 1.6 应该已经把改动 commit 完。这里二次检查，确保 task worktree
干净（除 `docs/DESIGN.md` + `docs/PRODUCT-RULES.md` —— 两者等 PM 二次审 diff 后手 commit）：

```bash
# delta-9 D9-4：PRODUCT-RULES.md 与 DESIGN.md 同 —— patch-不-commit，须一起进白名单，
# 否则未 commit 的 PRODUCT-RULES.md 会拌倒 worktree-clean 检查（commit 6382baf 同类 bug）。
UNCOMMITTED=$(git status --porcelain | grep -vE 'docs/(DESIGN|PRODUCT-RULES)\.md' || true)
if [ -n "$UNCOMMITTED" ]; then
  echo "❌ task worktree 有未 commit 改动（不含 DESIGN.md / PRODUCT-RULES.md）："
  echo "$UNCOMMITTED"
  echo "请检查 step 0 / 1 / 1.5 / 1.6 是否漏 commit。"
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

#### 2.3 输出切窗口指示（含自动收尾摘要）

AI 向 PM 输出结束语，task 窗口工作到此结束。结束语含**自动收尾摘要** —— 把本次 close
默认自动做了什么一次性讲清楚（PM 不被逐条打断、但末尾看得见）：

```
✅ task-NNN Phase 1 完成。本次自动收尾：

· 文档对齐：A 类 X 处已自动对齐到代码（B 类 Y 处已逐条经你确认）
· 视觉规范：K 条已 promote 到 docs/DESIGN.md（未 commit）
· 跨功能规则：M 条已 promote 到 docs/PRODUCT-RULES.md（未 commit）
（X/Y/K/M 为 0 的行省略；全 0 时整段写「无需对齐 / 无沉淀」）

请切到 req 窗口（cwd = req worktree），再次运行：

  /close-task

AI 会自动走 Phase 2 完成 merge + 删 task worktree/branch + auto-chain。
```

**若步骤 1.5 / 1.6 patch 过 DESIGN.md / PRODUCT-RULES.md**（uncommitted），追加提示：

```
⚠️ docs/DESIGN.md / docs/PRODUCT-RULES.md 有未 commit 的沉淀改动。
Phase 2 完成后，请在 req 窗口审 git diff 这两个文件 —— 这是你对本次自动 promote 的
总把关，发现不该 promote 的当场撤掉，满意后再 commit。
建议 commit message: docs(DESIGN): 沉淀 task-NNN 反馈 — [摘要]
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
5. **delta-7 vp-3：promote task 审计区「📋 文档偏差」→ req `adjustment` 事件**
   （append 到 `requirements/active/<req>/req-events.jsonl` 并 commit；格式判别走
   `detect_format` 三态，v2 旧 task 从 `.engineering.md §10` 读、v3 从审计区读；
   close-req 反向对齐读这些 adjustment 事件）
6. 归档 `.runs/` 到 req worktree 的 `tasks/_archived/` 并 commit 到 req 分支
7. **直接删** task worktree + task branch
8. 杀掉 dev server 进程
9. 清理 `.runs/` 原件
10. 追加 `task_closed` 事件

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
- 文档偏差必须在 Phase 1 处理（close-task.sh 会做二次检查；v3 单文件在审计区·📋 文档偏差，v2 旧 task 跨两文件）
- **v3 单文件归档**：merge / 归档 / 清理只动一个 `.md`；在飞旧 v2 双文件 task 仍成对处理
- delta-7 vp-3：Phase 2 把 task 文档偏差 promote 成 req `adjustment` 事件（由 close-task.sh 自动做）
- 不要手动执行 merge/删分支/清 worktree，全部由 close-task.sh 处理
- close-task.sh 一步关完 phase 2：merge → adjustment-promote → 归档 → 删 worktree → 删 branch
