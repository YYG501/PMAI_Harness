---
name: pmai-close-task
description: |
  Task 关闭：对齐 task 文档与原型、检查文档偏差、归档运行时数据、merge 分支、清理 worktree。
  分两个 phase：task 窗口内 prepare（对齐 + 偏差处理 + commit）→ req 窗口 finalize（merge + 删 task worktree/branch）。
---

# /pmai-close-task

> **PM 视图（M2 banner + Decision gate label）**：每个 phase 入口 banner（`status-view.py --banner-only --skill CLOSE-TASK`）；偏差分类闸门 / PM 总审 diff 闸门 label 按 `_shared/pm-view/banner-rules.md` §3 3 硬规则；退出 Next Up 引导 `/pmai-close-req`（最后一个 task）或 `/pmai-task-confirm <next-task>`。
>
> **PM 答题规则（M4）**：所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 四条硬规则走（空答 STOP / 没拿到答案禁止 merge / runtime 退化保留 wait / 多决策拆开顺序问）。**Runtime 兜底**：本 skill 各门写的都是 picker 形态；runtime 不支持时 AI 按 §1.3 自动退化为编号列表，仍 wait。

## 两阶段调用（必读）

`/pmai-close-task` 设计为两阶段调用，AI 根据 cwd 自动判断当前阶段：

- **Phase 1**（cwd 在 task worktree 内）：task md 对齐 / 偏差处理 / DESIGN.md 沉淀 / commit / 登记 marker
- **Phase 2**（cwd 在 req worktree 内）：merge → req、归档 .runs/、删 task worktree+branch、auto-chain

PM 体感：
1. 在 task 窗口验收通过后运行 `/pmai-close-task` → AI 走 Phase 1 → 提示切到 req 窗口
2. PM 切到 req 窗口
3. 在 req 窗口运行 `/pmai-close-task` → AI 走 Phase 2 → 完全关闭 + auto-chain

## When To Use

- 在 task 窗口验收通过后调用（启动 Phase 1）
- 切到 req 窗口后再次调用（执行 Phase 2）
- Task 状态必须为「已完成」

## task 文件形态

task-spec 产 **单文件 typed contract**（`task-NNN-<slug>.md`，三区：PM 确认区 / 执行区 /
审计区）。本 skill：
- **文档偏差检查在单文件**：审计区的「📋 文档偏差」section（不再跨两文件）。
- **归档单文件**：merge / 归档 / 清理只动一个 `.md`。
- **三态兼容**：在飞旧 v2 双文件 task 仍按双文件成对处理（用 `detect_format` 分流）。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: close-task"

# M2 banner（视觉锚点；见 _shared/pm-view/banner-rules.md §1）
python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill CLOSE-TASK || true
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
| req worktree 内 | 不存在 | **报错**："没有待 finalize 的 task。请先在 task 窗口运行 /pmai-close-task" |
| 主仓或其他位置 | - | **报错**："请在 task 窗口或 req 窗口运行 /pmai-close-task" |

## modulespec 维护策略

close-task **不调** `/pmai-doc-update`（任何模式都不调）。task close 只 merge + 归档，**不动 `docs/modules/*.md`**。modulespec 维护推迟到 close-req 末统一 rewrite（doc-update §8 rewrite mode）。

**PM 心智模型注脚**（防误判）：

- 跑完 `/pmai-close-task` 看不到 modulespec 变化 = **正常**
- 沉淀在 `/pmai-close-req` 末批量发生，你那时一次审完整段 diff
- 这是为节省 N 次 doc-update 启动 token 成本

### 旧 flag tombstone

旧版本支持的 `--skip-doc-update` / `--doc-update-now` flag **已废弃**。PM/AI 如带这两个 flag 调用 close-task：

```text
Error: --skip-doc-update / --doc-update-now 已废弃。
       close-task 不再调 doc-update；正常 close-task 即可，modulespec 由 close-req 末统一 rewrite。
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

**B 类（逐条呈交 PM）**：每条 B 类用 AskUserQuestion picker（按 `askuser-rules.md §1.4` 多决策拆开顺序问，runtime 不支持时按 §1.3 退化编号列表）：

prose 头部：
```
这条对齐要你定一下（B 类原因：<§0.2 自判的原因>）：
  文档原文：<偏差行第 2 列>
  实际实现：<偏差行第 3 列>
```

AskUserQuestion：
- `question`: "这条偏差怎么对齐？"
- `options`:
  - `label`: `改 task md`
    `description`: `对齐 task md 到实际原型，AI 用 Edit 改完展示 git diff`
  - `label`: `改代码`
    `description`: `回退原型对齐 task md（建议关掉 close-task 回 task 窗口跑 /pmai-task-execute 重做）`
  - `label`: `跳过`
    `description`: `这条不重要，AI 不动 task md，进下一条`

**PM 答题处理**：
- 选 `改 md` / 输 `1` / 输 "改 md / md 对齐 / 改 task 文档" → AI 用 Edit 改 `$TASK_FILE`，改后展示 git diff
- 选 `改代码` / 输 `2` / 输 "改代码 / 回退原型" → AI **不能自己改代码**。提示 PM：「建议先关掉 close-task 回 task 窗口跑 /pmai-task-execute 重做后再 close。还是确认要在 close-task 阶段直接改代码？」→ PM 坚持要在本阶段改 → 视为退出 close-task 流程，AI 输出"请回 task 窗口重做"并 exit
- 选 `跳过` / 输 `3` / 输 "跳过 / 算了 / 不重要" → AI 不动 task md，进下一条
- PM 空答 / 没答 → STOP wait next message（按 `askuser-rules.md §1.1`）

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
- **PM 选"改代码"但又要在本阶段改**：agent 输出"请回 task 窗口跑 /pmai-task-execute"并 exit；不让 close-task 蜕变成 mini task-execute。
- **patch 失败 / git commit 失败**：close-task 阻塞，提示 PM 人工修复后重跑。

**与步骤 1 / 1.5 的边界**：

| 步骤 | 性质 | 对照源 |
|---|---|---|
| **0**（本节）| task 文件描述 ↔ 原型代码 | 执行区·实现规格 / PM 确认区·验收清单·范围 + 审计区·执行日志 vs 实际改动文件 |
| 1 | task 实证发现的项目级文档偏差 | task md §历史档案/§10 vs brief / **stage 2 真相源**（A 分支 analysis.md / B 分支 stage2-office-hours.md）/ solution / module spec |
| 1.5 | PM 反馈中的视觉规范沉淀 | task md PM 反馈分类=视觉规范 vs docs/DESIGN.md |

性质不同，串行处理不合并。

### 步骤 1：偏差记录留作 close-req 聚合输入（不调 doc-update）

close-task **不调** `/pmai-doc-update`。偏差记录原样保留在 task 文件里，由 close-req 步骤 1.5 聚合处理（按目标文档 rewrite OR patch）。

校验（这一步必跑，是 close-req 聚合 + adjustment-promote 的输入约束）：

- **v3 单文件**：审计区 `## 📋 文档偏差` 表存在（即使是「无」也要存在该段）
- **v2 旧双文件**：PM 视图 `### 业务层偏差` 段 + 工程合同 `## 10. 文档偏差` 表（兼容）

用 `detect_format` 分流。判断：
- **段缺失** → 报错让 PM 补段头（即使填「无」）；不能省段，否则 close-req 聚合 + promote 会找不到锚点
- **段存在（含「无」或具体表内容）** → 继续 §1.1 分类，**不调 /pmai-doc-update**

> **为什么不在这里调 /pmai-doc-update**：见本文件顶部「modulespec 维护策略」。简言之，per-task 调 doc-update 是 N 次启动成本累加的根源；推迟到 close-req 末统一 rewrite。

#### 1.1 偏差分类：纠错 vs 计划外简化

读审计区·📋 文档偏差表。**对每条非「无」偏差行**逐条 AI 分类：

| 类别 | 判别 | 处理 |
|---|---|---|
| **纠错偏差**（默认）| 偏差是「文档写错了 → 按代码改对」—— 字段名错 / 流程描述错 / 文案过期 | 留原表不动；close-task.sh phase 2 把它 promote 成 `adjustment` 事件，close-req §2a 反向覆盖 PRD（原路径不变）|
| **计划外简化**| 偏差是「task 执行期临时决定少做某功能 / 边界 / 流程」—— 实现比 PRD 写的少、但不属于 stage 5 PM 主动决策的 SIMP-N（不在 implementation-design.md 段 1.5 已登记范围）| **停下问 PM**：是否回填 implementation-design.md 段 1.5（补 SIMP-NN）—— 见 §1.2 |

**AI 分类启发式**（pattern 沉淀，非阈值脚本，memory `feedback_judgment_pattern_not_mechanization`）：

- 「实际实现」字段比「文档原文」**少做了一段**（不是改错而是少做）→ 倾向计划外简化
- 「实际实现」字段比「文档原文」**做的是另一种实现**（同范围、不同方式）→ 纠错偏差
- 「建议改法」字段写「按代码对齐文档」→ 纠错；写「文档保留，原型本期不做」/「下个 req 再做」
  → 计划外简化
- task PM 确认区·验收清单受影响行有 `[SIMP-N]` 标签 → 此条已在计划内，**不应在偏差表登记**
  （C3 carve-out；若已登记 → 提示 executor 自审失职，AI 帮删该行 + 提醒 PM）

判不准 → 当**计划外简化**问 PM（让 PM 判，AI 不假装会判）。

#### 1.2 计划外简化：停下问 PM 回填 implementation-design.md（C9 限定 close-time）

对每条计划外简化偏差用 AskUserQuestion picker（按 `askuser-rules.md §1.4` 多决策拆开顺序问）：

prose 头部：
```
本 task 偏差表第 N 行像「原型本期临时少做」（不是文档写错）：
 - 文档原文：<偏差行第 2 列>
 - 实际实现：<偏差行第 3 列>
```

AskUserQuestion：
- `question`: "这条偏差是计划内简化（回填 SIMP-NN）、真偏差（promote adjustment 覆盖 PRD），还是跳过？"
- `options`:
  - `label`: `回填 simp 段`
    `description`: `推荐——PRD 保留真实需求 + 加「原型本次计划简化为」标注`
  - `label`: `按 adjustment promote`
    `description`: `PRD 改成实际做成的样子；真实需求只在 req-events.before 留痕`
  - `label`: `跳过这条`
    `description`: `不处理，PM 自己事后决策`

**PM 答题处理**：

- 选 `回填 simp 段` / 输 `1` → AI 用 Edit 在 implementation-design.md 段 1.5 末追加一行：
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
- 选 `按 adjustment promote` / 输 `2` → 偏差行留原表不动（走原路径）
- 选 `跳过这条` / 输 `3` → 不处理，进下一条
- PM 选「跳过」→ 偏差行留原表不动，备注「PM 选择不分类」

#### 1.3 全部分类完成后

进入步骤 1.5（视觉规范）。phase 2 close-task.sh 仍按原逻辑 promote 偏差成 adjustment ——
回填 simp 的行已经从偏差表删了，不会 promote；adjustment 路径的行照走。

### 步骤 1.5：视觉规范反馈反推 DESIGN.md（4 类分流，`_shared/pm-view/input-flow.md` §9.4 第四类）

扫本 task PM 视图的 `## 📁 历史档案 → ### PM 反馈` 区域，对**分类=「视觉规范」**的条目按子类逐条处理。

> **关键原则**：DESIGN.md = task 启动前的硬约束（init C.5 视觉基线 + stage 4 4A 新组件完整规格定稿）。close-task 沉淀的是**未来约束**，不是"补本次实现"。本 task 实现错了 → 改代码，不是改 DESIGN.md。

#### 1.5.0 前置检查（DESIGN.md 不存在 fallback）

```bash
DESIGN_MD="$MAIN_REPO_ROOT/docs/DESIGN.md"
if [ ! -f "$DESIGN_MD" ]; then
  echo "ℹ️  $REPO_ROOT/docs/DESIGN.md 不存在，跳过视觉规范沉淀。"
  # 直接进入步骤 2
fi
```

#### 1.5.1 扫描候选反馈

Read 本 task PM 视图主文件的 PM 反馈 section，提取候选：
- 分类含 `视觉规范` 的反馈条目
- 处理结果**不**含「已沉淀 DESIGN.md」备注的（避免重复处理）

候选数 = N。**N = 0 → 直接进入步骤 2**。

#### 1.5.2 4 类分流（每条反馈先判子类）

对每条候选反馈，AI 先判子类（4 选 1）：

| 子类 | 判定信号 | 落地动作 |
|---|---|---|
| **① 本 task 实现偏差** | "颜色不对 / 间距错了 / 字体没用 X" — 指向本次代码实现没对齐已定规范 | **不动 DESIGN.md**。task 仍在 worktree → 应改代码；已合并 → 告知 PM 起 quick-fix 或下个 task 修。记账 `Y-task-fix` |
| **② 项目级视觉基线更新** | "以后整个项目按这个 / 所有按钮 hover 都这样 / 项目色板换 X" — 指向 gstack 写的视觉基线段（颜色 / 字体 / 间距 / 布局 / 动效） | **patch DESIGN.md gstack 写的对应段**（`## Aesthetic Direction` / `## Color` / `## Typography` / `## Spacing` / `## Layout` / `## Motion` 之一）。记账 `Y-baseline` |
| **③ 共享组件 inventory 新规范 / 现有组件规格补充** | "侧栏导航选中态颜色其实应该 X / 新增一个 toast 组件" — 指向 inventory 段的某一行 | **patch DESIGN.md `## 共享组件 inventory` 表**（已有组件更新视觉/状态/交互列，或新组件追行）。记账 `Y-inventory` |
| **④ 文案 voice & tone（拒绝写 DESIGN.md）** | "空状态文案太严肃 / 错误提示应该俏皮 / 所有 toast 文案都用 X 风格" | **拒绝写 DESIGN.md**，告知 PM "这是文案 voice & tone，建议沉淀到 docs/PROJECT.md（项目级语气）或 docs/prd.md（req 级文案）；DESIGN.md 只管视觉规范"。记账 `N-wrong-doc` |

AI 拿不准 → 呈交 PM 用 AskUserQuestion picker（4 选 1）：

prose 头部：
```
本条反馈分类拿不准（请你拍）：
  反馈原文：<反馈条目>
```

AskUserQuestion：
- `question`: "这条反馈属于哪一类？"
- `options`:
  - `label`: `本 task 实现偏差`
    `description`: `不动 DESIGN.md，task 仍在 worktree 应改代码 / 已合并起 quick-fix`
  - `label`: `项目级视觉基线更新`
    `description`: `patch DESIGN.md gstack 写的对应段（Color/Typography/Spacing 等）`
  - `label`: `共享组件 inventory 新规范`
    `description`: `patch DESIGN.md 共享组件 inventory 表`
  - `label`: `文案 voice & tone`
    `description`: `拒绝写 DESIGN.md，建议沉淀到 PROJECT.md（项目级）或 prd.md（req 级）`

#### 1.5.3 沉淀处理（按子类执行）

**子类 ② / ③：默认 promote（不问 PM）**
- 读 `docs/DESIGN.md` 章节结构（`grep '^## \|^### \|^#### ' docs/DESIGN.md`）按子类定位对应段：
  - ② → gstack 视觉基线段（`## Aesthetic Direction` / `## Color` / `## Typography` 等）
  - ③ → `## 共享组件 inventory` 表行
- AI 用 Edit patch（**不 commit**）

**子类 ①**：不写 DESIGN.md，PM 反馈条目「处理结果」标 `task-fix`

**子类 ④**：不写 DESIGN.md，PM 反馈条目「处理结果」标 `wrong-doc:<建议归属>`（PROJECT.md / prd.md）

**禁止**：silent commit `docs/DESIGN.md`。DESIGN.md 改动 patch-不-commit，PM 在 close 收尾审总 diff 自己 commit（步骤 2.3 提示）—— 这一步总审是 PM 对默认 promote 的把关。

#### 1.5.4 沉淀后记账

每条 promote 的 patch 完成后，AI 把该条 PM 反馈的「处理结果」改为「已处理」+ 备注「已沉淀 DESIGN.md <段名 / inventory>」。**不逐条给 PM 看 diff** —— DESIGN.md 总 diff 由步骤 2.3 汇总，PM 在 close 收尾时一次性审、当场可撤。

#### 1.5.5 完成后进步骤 1.6

所有 N 条视觉规范反馈处理完毕（每条都标了 `Y-baseline` / `Y-inventory` / `Y-task-fix` / `N-wrong-doc` 之一作为内部记账），DESIGN.md 改动**未 commit**（步骤 3 提示 PM 自己 commit），进入步骤 1.6。

### 步骤 1.6：跨功能产品行为规则反馈 selective promote 到 PRODUCT-RULES.md

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

**拿不准才逐条问 PM**：仅当 AI 判断该条可能够不上「全项目跨功能规则」（够不上全项目、或该归术语表 / modulespec / DESIGN.md）→ AskUserQuestion picker：

prose 头部：
```
这条规则我拿不准是不是全项目跨功能：
  反馈原文：<反馈摘要>
```

AskUserQuestion：
- `question`: "这条规则归到 PRODUCT-RULES.md 还是别处？"
- `options`:
  - `label`: `promote 进 PRODUCT-RULES.md`
    `description`: `全项目跨功能产品行为规则`
  - `label`: `不是跨功能规则`
    `description`: `留 task 或改归别处（你说归哪）`

**PM 答题处理**：
- 选 `promote` / 输 `1` → AI 追加进 PRODUCT-RULES.md（不 commit）
- 选 `不是跨功能规则` / 输 `2` → 不动 PRODUCT-RULES.md，按 PM 指示归类

PRODUCT-RULES.md 改动 patch-不-commit，PM 在 close 收尾审总 diff 自己 commit。

#### 1.6.4 完成后进步骤 2

PRODUCT-RULES.md 改动**未 commit**（步骤 3 提示 PM）；进入步骤 2。

**与步骤 1 文档偏差检查的边界**：
- 步骤 1 处理"客观文档偏差"（字段名错 / 流程描述错）→ `/pmai-doc-update` 对账
- 步骤 1.5 处理"视觉规范沉淀"（AI 默认 promote 项目级视觉规范，拿不准才问 PM）→ patch DESIGN.md
- 性质不同，串行处理不合并

### 步骤 2：Phase 1 收尾：登记 finalize marker，提示 PM 切窗口

#### 2.1 兜底 commit 检查

phase 1 步骤 0 / 1 / 1.5 / 1.6 应该已经把改动 commit 完。这里二次检查，确保 task worktree
干净（除 `docs/DESIGN.md` + `docs/PRODUCT-RULES.md` —— 两者等 PM 二次审 diff 后手 commit）：

```bash
#  ：PRODUCT-RULES.md 与 DESIGN.md 同 —— patch-不-commit，须一起进白名单，
# 否则未 commit 的 PRODUCT-RULES.md 会拌倒 worktree-clean 检查（同类 bug 防回归）。
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

按 [banner-rules §2.5 内容禁忌](../_shared/pm-view/banner-rules.md#25-内容禁忌pm-facing-输出禁工程黑话与内部原理) — 不写 Phase 1/2、不写 merge / worktree / auto-chain 等内部术语：

```
✅ task-NNN 本窗口收尾完成。本次自动做了：

· 文档对齐：A 类 X 处已自动对齐到代码（B 类 Y 处已逐条经你确认）
· 视觉规范：K 条已写入 docs/DESIGN.md（未 commit）
· 跨功能规则：M 条已写入 docs/PRODUCT-RULES.md（未 commit）
（X/Y/K/M 为 0 的行省略；全 0 时整段写「无需对齐 / 无沉淀」）

▶ Next Up — 切到 req 窗口跑 /pmai-close-task：

如果 req 窗口还开着：直接切过去运行 `/pmai-close-task`
如果 req 窗口已关：
  cd <REQ_WORKTREE_ABS>     ← 替换为本 req worktree 绝对路径（脚本在 finalize marker 写过）
  claude
  /pmai-close-task

切到 req 窗口跑 /pmai-close-task 后 AI 自动完成本 task 的归档，并自动开下一个 task（如果还有）。
```

**若步骤 1.5 / 1.6 patch 过 DESIGN.md / PRODUCT-RULES.md**（uncommitted），追加提示：

```
⚠️ docs/DESIGN.md / docs/PRODUCT-RULES.md 有未提交的沉淀改动。
切到 req 窗口跑完 /pmai-close-task 后，请审 git diff 这两个文件 —— 这是你对本次自动
沉淀的总把关，发现不该写入的当场撤掉，满意后再 commit。
建议 commit message: docs(DESIGN): 沉淀 task-NNN 反馈 — [摘要]
```

**Phase 1 短路场景**：进入 skill 时检测到 marker 已存在（之前调过一次但 PM 没切窗口），跳过步骤 0 / 1 / 1.5 / 2.1 / 2.2，直接输出 2.3 切窗口指示。不要重复对齐 / 重复 commit。

## Phase 2：在 req worktree 内执行

### 步骤 P2.1：读 marker

```bash
if [ ! -f "$PENDING_MARKER" ]; then
  echo "❌ 没有待 finalize 的 task。"
  echo "   请先在 task 窗口运行 /pmai-close-task"
  exit 1
fi

TASK_FILE_ABS=$(python3 -c "import json; print(json.load(open('$PENDING_MARKER'))['task_file_abs'])")
```

### 步骤 P2.2：调 close-task.sh

```bash
bash "$PMAI_HOME/scripts/close-task.sh" "$TASK_FILE_ABS"
```

脚本自动：
1. 校验 cwd 在 req worktree 内（防御性二次校验）
2. 校验 task 状态为「已完成」
3. 检查文档偏差（二次检查，有未处理偏差会阻塞）
4. merge task 分支 → req 分支
5. **：promote task 审计区「📋 文档偏差」→ req `adjustment` 事件**
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

脚本成功后，检查 `task-plan.md` 决定下一步：

- 若 `PENDING > 0`：发"还有待办 task" handoff 提示

  ```
  Stage 6（task 执行）— task-NNN 已关闭

  下一步：task-XXX（<title>，所属模块: [...]）
  在本（req）窗口运行：/pmai-task-spec task-XXX → /pmai-task-confirm
  ```

- 若 `PENDING == 0`：**in-place 出 Stage 6→7 关 req 确认门**（不让 PM 再敲一次 `/pmai-req-stage-gate`）

  模板跟 `req-stage-gate/SKILL.md`「Stage 6 → 7」段步骤 3 **共用同一段文案**（关 req 模板单一真相源在 req-stage-gate；本处只复述，不允许两边偏移）：

  prose 头部：
  ```
  Stage 6 task 执行 → 7 req close

  ✅ 状态
     <N 个 task 全部 close、worktree 全部清理>
  ```

  AskUserQuestion：
  - `question`: "是否确认关闭此需求，进入 Stage 7 req close？"
  - `options`:
    - `label`: `关闭 req`
      `description`: `启动 /pmai-close-req（生成 close-report、PRD 反向对齐、merge 进 main、归档）`
    - `label`: `还要开新 task`
      `description`: `本 req 还没完，回 stage 6 跑 /pmai-task-spec 起新 task`

  **PM 答题处理**：

  - 选 `关闭 req` / 输 `1` / 输 "确认 / 关 / 关闭" → AI 跑推进 + chain `/pmai-close-req`：
    ```bash
    python3 "$PMAI_HOME/scripts/req-transition.py" "$ACTIVE_REQ_DIR" --to 7
    ```
    成功后直接调用 `/pmai-close-req`（不再发"已推进 Stage 6→7"过渡通知，跟 req-stage-gate 续跑模式规则一致）
  - 选 `还要开新 task` / 输 `2` / 提具体 task 描述 → AI 转 `/pmai-task-spec` 起新 task，**不**推 Stage 7
  - PM 不答关窗口 → 几天后 PM 回来重敲 `/pmai-req-stage-gate`，由 req-stage-gate 的 Stage 6→7 入口重新拉起同一个关 req 门（兜底续走路径，确保关 req 门永远有入口）

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
- ：Phase 2 把 task 文档偏差 promote 成 req `adjustment` 事件（由 close-task.sh 自动做）
- 不要手动执行 merge/删分支/清 worktree，全部由 close-task.sh 处理
- close-task.sh 一步关完 phase 2：merge → adjustment-promote → 归档 → 删 worktree → 删 branch
