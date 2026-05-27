---
name: pmai-close-req
description: |
  Req 关闭：写 close-report、更新 PRD、merge 到 main、归档。
---

# /pmai-close-req

> **PM 视图（M2 banner + Decision gate label）**：入口 banner（`status-view.py --banner-only --skill CLOSE-REQ`）；close-report 定稿闸门 label 按 `_shared/pm-view/banner-rules.md` §3 3 硬规则；退出 Next Up 引导「项目方向是否需要调整」（`/pmai-project-solution` 产品路线规划场景）或 `/pmai-new-req` 起下一 req。
>
> **PM 答题规则（M4）**：所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 3 硬规则走（空答 STOP / 没拿到答案禁止 merge to main / runtime 退化保留 wait）。

## When To Use

- Orchestrator 在 stage 7 调用
- 所有 task 必须已关闭

## 两阶段调用（必读）

`/pmai-close-req` 设计为两阶段调用，AI 根据 cwd 自动判断当前阶段：

- **Phase 1**（cwd 在 req worktree 内）：写 close-report、PRD、commit、登记待 finalize marker
- **Phase 2**（cwd 在主仓，不在任何 worktree 内）：merge → main、删 worktree/branch、清 marker

PM 体感：
1. 在 req 窗口运行 `/pmai-close-req` → AI 走 Phase 1 → 提示切到主仓窗口
2. PM 切到主仓窗口
3. 在主仓窗口运行 `/pmai-close-req` → AI 走 Phase 2 → 完全关闭

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: close-req"

# M2 banner（视觉锚点；见 _shared/pm-view/banner-rules.md §1）
python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill CLOSE-REQ || true
```

## Phase 自动判断（入口）

AI 进入 skill 时先检测 cwd 决定走 Phase 1 还是 Phase 2：

```bash
REPO_ROOT="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." && pwd)"
CURRENT_WT="$(git rev-parse --show-toplevel)"
PENDING_MARKER="$REPO_ROOT/.runs/pending-close-req.json"
```

分流逻辑：

| cwd 位置 | marker 状态 | 走向 |
|---|---|---|
| req worktree 内 | 不存在 | **Phase 1**（正常文档/commit 流程，结束时写 marker） |
| req worktree 内 | 已存在 | **Phase 1 短路**（直接告知"已 ready，请切到主仓窗口"） |
| 主仓（== REPO_ROOT） | 存在 | **Phase 2**（merge + delete + 清 marker） |
| 主仓（== REPO_ROOT） | 不存在 | **报错**："没有待 finalize 的 req。如要新启动 close-req，请进 req worktree 调用" |

## Phase 1：在 req worktree 内执行

### 步骤 1：写 close-report.md 初稿（`## 文档变更` 段留 placeholder，步骤 1.5 后回填）

<!-- 「文档变更」段必须在步骤 1.5 modulespec rewrite 之后填，否则会漏 rewrite 改动。 -->

在 req 目录写 `close-report.md`，内容包括：

```markdown
# Req Close Report: req-NNN-<slug>

## 需求概述
[从 prd.md §四 需求分析 提取，**不读 brief.md**——brief 是 stage 1 初稿，到 close-req 时已被 7 个 stage 演化，用它写关闭报告会反映已被推翻的初衷。在飞旧 req 若无 prd.md、仅有 solution.md，则从 solution.md §📌 方案摘要 提取]

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
<!-- placeholder：本段在步骤 1.5 完成后回填（含 rewrite 覆盖的 docs/modules/* + docs/DESIGN.md + docs/PROJECT.md 等；docs/prd.md 已砍，不在 rewrite 范围）。
     如果步骤 1.5 silent skipped（无业务偏差），本段写"本 req 无项目级文档变更"。 -->

## 原型简化项
<!-- close-req §2a 完成后回填本段。
     列本 req 通过 implementation-design.md 段 1.5 登记的所有 SIMP 行 —— 让评审 / 后续 req
     一眼看到「本 req 原型本期没全做 PRD 的哪几块」，不必再翻 implementation-design.md。

     无 simp 行（段 1.5 单行「无」或不存在）→ 本段写「本 req 原型按 PRD 全量实现，无简化项」。 -->

| SIMP-ID | PRD 锚点 | 真实需求 | 原型本次计划简化为 | 来源 |
|---|---|---|---|---|
| SIMP-NN | §六 6.X / Story N | 见 PRD §六 6.X | <从 implementation-design.md 段 1.5 抄过来> | kind 1 / kind 2 |

## 遗留问题
[如有未解决的问题或后续建议]
```

**生成规则：**
- 遍历 `tasks/*.md` 填「完成的 task」表（这里只剩已完成态，因为 stage 7 guardrail 要求所有未关闭 task 都收尾）。
- 遍历 `tasks/discarded/*.md` 填废弃栏；为空时整个 `<details>` 块省略。
- 已废弃 task 编号断号是合规信号，不要为「整理顺序」而改号。
- **`## 文档变更` 段写 placeholder 注释 + 留空**，等步骤 1.5 完成后用 doc-update §8 返回的 `REWRITE_COVERED_FILES` 清单回填。
- **`## 原型简化项` 段写 placeholder 注释 + 留空**，等步骤 2a 完成后从 `implementation-design.md` 段 1.5 抄过来填。

### 步骤 1.5：聚合所有 closed task 偏差，按目标文档统一沉淀

<!-- modulespec 沉淀从 close-task per-task 推到这一步聚合。
     输入源不再是 SKIP_DOC_UPDATE marker（close-task 永不写 marker），
     改为遍历所有 closed task 直接收集偏差。 -->

**目的**：close-task 永不调 doc-update（不写 modulespec），所有 task 的偏差与功能清单累积到本步骤一次性沉淀。N 次 doc-update 启动成本合并成本 step 一次（§0.1 痛点）。

**输入源**（遍历所有 closed task，单文件后 3 处合一）：

1. **task 文件** `tasks/*.md`「📌 任务卡」表格的 `所属模块` / `所属模块章节` 字段 → 决定 sediment 进哪份 `docs/modules/<module>.md`
2. **`prd.md` §六 功能需求** —— 模块功能合同沉淀源（功能清单已从 task 移 PRD；task 执行区·实现规格仅作 task 级实现细节、不进 module spec）
3. **task 文件审计区** `## 📋 文档偏差` 表（v3 单文件）→ 指向 brief / analysis / prd / DESIGN / PROJECT / module 规格 的偏差对账
   - **v2 旧 task 兼容**：跨 PM 视图 `### 业务层偏差` + 工程合同 `## 10. 文档偏差` 两处（用 `detect_format` 分流）

> task「文档偏差」已 promote 成 req `adjustment` 事件 —— 本步骤的 modulespec
> sediment 与 close-req PRD 反向对齐（读 `adjustment` 事件）是不同消费者，互不冲突。

**流程**：

1. 遍历 `tasks/*.md`；按 `detect_format` 分流提取每 task 的偏差（v3 单文件审计区 / v2 跨两文件）。
2. **按目标文档分组**：同一份 `docs/modules/<module>.md` / `docs/DESIGN.md` / `docs/PROJECT.md` 的多 task 偏差并到一起（**项目主 `docs/prd.md` 已砍，不在范围**；req 级 `prd.md` 是 stage 3 定稿冻结基准，不进本 sediment 流程）。基础设施 task（`所属模块=基础设施`）跳过 module sediment，但其偏差表仍走对账。
2.5. **稳定结构反查（弥补 task 偏差表盲区）**：

   **盲区根因**：task 偏差表只检测「已有文档原文 vs 代码」diff —— 本 req 新建/改了「稳定结构」（菜单 IA / 路由表 / schema / config / contract），但 `docs/modules/` 从来没建过对应规格文件 → 偏差表填「无」（无源可比）→ §1.5 silent skip → 稳定结构只活在代码里，下次想沉淀也不知道有这件事。req-008 close 后发现菜单 IA 三个 app 都漏沉淀，根因即此。

   **反查流程**：

   ```bash
   BASE=$(git merge-base main HEAD)   # req 起点
   git diff --stat "$BASE" HEAD | grep -v '^docs/\|^requirements/\|^tests/'
   git diff "$BASE" HEAD -- '*.ts' '*.tsx' '*.py' '*.go' '*.json' '*.yaml' '*.yml' | head -500
   ```

   AI 看本 req 全部代码侧 diff，自答：本 req 是否新建/改了**稳定结构**，但 `docs/modules/` 无对应规格文件？

   - 正面线索：路径/文件名含 `routes`/`router`/`navigation`/`menu`/`sidebar`/`permissions`/`schema`/`contract`/`api`/`config`；内容是**声明性数据**（数组/对象/枚举字面量）非函数逻辑；影响产品 IA（用户能看到的导航/权限/URL 结构）
   - 负面排除（不算）：单页业务逻辑、组件 refactor、测试、bug fix、内部工具脚本、纯样式调整
   - 已被 task 偏差表覆盖的（条目已指向某 modulespec / DESIGN / PROJECT）→ 不重复列

   **输出候选「孤儿稳定结构」清单**，每条含：

   - 涉及文件清单（代码侧路径）+ 1-2 行 diff 证据
   - 稳定结构类型（菜单 / 路由 / schema / config / contract / 其他）
   - 建议 modulespec 目标路径（基于 task「所属模块」字段 + 现有 `docs/modules/` 目录结构推断）
   - **AI 自审反证**一行：「这不该入 modulespec 的理由」—— 强制 AI 给出否定理由，防过度推荐

   **PM 决议**（每条候选三选一，AskUserQuestion）：

   | 决议 | 行为 |
   |---|---|
   | **建** | 本 req 顺便建 modulespec 主规格文件 → 追加进步骤 3 决议表，走 rewrite 分支 |
   | **不建（追认代码即文档）** | close-report.md `## 文档变更` 段加一行：「<结构类型>：真相源 = <代码路径>（PM close-req-NNN 追认）」防下个 req 重复问 |
   | **推下个 req** | close-report.md `## 遗留问题` 段加一条点名（含建议 modulespec 路径 + 涉及文件） |

   **零候选**：反查无候选孤儿 → 直接跳到步骤 3，不调 AskUserQuestion。

3. 聚合后呈交 PM，按目标文档逐份决议（AskUserQuestion 或 prose；**两选项**，skip 分支已砍）：

   | 决议 | 触发条件 | 行为 |
   |---|---|---|
   | **rewrite**（默认 / 主路径） | 任何 closed task 改某目标文档 → 默认 rewrite | 调 doc-update SKILL 步骤 8 rewrite mode（req-level aggregation contract，不要求 ≥2 SKIP marker）|
   | **patch** | PM 显式选 + 单 task 单文档单段 | 调现有 doc-update 对账模式（步骤 1.5/1.6/2-5）|

4. PM 决议后，doc-update SKILL §8 返回 `{覆盖的目标文档清单, 覆盖的模块清单}`（输出契约），供步骤 2a 作 metric。
5. **回填 close-report.md `## 文档变更` 段**：把 `REWRITE_COVERED_FILES` 写进步骤 1 初稿留的 placeholder。
6. **INDEX.md derived refresh**（独立于 REWRITE_COVERED_FILES metric）：

   主 rewrite 完成后，单独刷新 `docs/modules/INDEX.md`。**不进** REWRITE_COVERED_FILES（避免污染 §2a metric）：

   ```bash
   # 1. AI 归纳：读本 req 涉及的 docs/modules/<m>.md 的 §摘要 + §一模块定位 + §三一级章节标题，提炼用途（≤30 字）
   # 2. patch docs/modules/INDEX.md（新模块插入新行；已存在且本 req 改过规格的更新简介；未改动的不动）
   # 3. lint 校验
   python3 "$PMAI_HOME/scripts/check-index-lint.py" "$REPO_ROOT" --exit-code || {
     # lint 失败 → AI 二次重写
     # 仍失败 → 输出空 diff 跳过本次 INDEX 刷新（不阻塞 close-req 整体）
     echo "⚠️ INDEX lint 二次重写仍失败，跳过本次 INDEX 刷新"
   }
   # 4. PM 审 diff：git diff docs/modules/INDEX.md
   # PM reject → AI 重新归纳；2 次仍 reject → 空 diff 跳过（同上）
   ```

   独立输出字段：`{"index_refreshed": true|false, "index_lint_passed": true|false}`，写入 step 1.5 返回但**不进** REWRITE_COVERED_FILES。

7. 全部目标文档处理完毕（含 INDEX derived refresh）后进步骤 2a。

**quickfix 历史改动处理**：

`/pmai-quick-fix` 改 `docs/modules/*.md` 是**旁路**（不走 close-task → close-req 流程），但 modulespec 当前文件状态已包含 quickfix 改动（git working tree）。步骤 1.5 调 doc-update §8 rewrite mode 时，**输入是「当前 modulespec 全文 + 本 req 各 task 偏差」**，quickfix 改动天然包含在 baseline 里 → 不需要额外收集机制。如果 PM 想审 quickfix 历史 → 看 `git log --grep '\[quick-fix\]' -- docs/modules/`，与 rewrite 流程解耦。

**PM 拒绝处理**：PM 决议过程中拒绝任一 rewrite / patch（不接受 AI 草稿）→ close-req 中止，下次重跑 close-req 时回到步骤 1.5 重新决议。不要尝试"半重写"。

**边界**：

- 步骤 1.5 是 close-req 的**主路径**（每 req 必跑一次）
- **本 req 内全部 closed task 偏差表都是「无偏差」且无功能清单变化 + 步骤 2.5 反查无候选孤儿（或所有候选 PM 选「不建 / 推下个 req」）** → silent skip 进步骤 2a（仅在「基础设施 task 单 req」之类的纯非业务 req 出现）
- inter-req 推迟 / DEFERRED_TO_REQ skip 分支已砍（多 req 并行不在范围）
- 旧 SKIP marker 兼容：消费仓若有旧 `<!-- SKIP_DOC_UPDATE: ... cleanup_status=... -->` 残留，本步骤遇到时**等同普通偏差源处理**（一次性消费掉，rewrite 决议时 `cleanup_status` 改 `done` 留作 audit trail；不再阻塞 stage 6→7 推进）

### 步骤 2a：PRD 反向对齐成 as-built + 原型简化项标注

> PRD 已在 stage 3 产出、定稿冻结。close-req 这一步把冻结的 PRD **一次性反向对齐成 as-built** —— 执行期 task 对 PRD 的偏离在 `req-events.jsonl` 的 `adjustment` 事件里累积，本步骤逐条把 PRD 改成实际做成的样子。
>
> 除了 adjustment overwrite，还读 `implementation-design.md` 段 1.5 原型简化项，在 PRD 受影响行**追加标注**（保留真实需求 + 追加「原型本次计划简化为」）。两步**顺序硬约束**：先 adjustment overwrite 全部完成 → 再 simp 标注追加；避免标注被后续 overwrite 抹掉。

#### 2a.1 读 adjustment 事件 + 段 1.5 原型简化项

```bash
python3 "$PMAI_HOME/scripts/req-events.py" list "$ACTIVE_REQ_DIR"
```

`req-events.py list` 折叠出本 req 全部 `adjustment` 事件（close-task Phase 2 promote 来的
「文档偏差」）。每条含：`from_task` / `prd_anchor`（PRD 哪条被调）/ `before`（PRD 原定）/
`after`（实际做成）/ `reason`。

**加读**：`$ACTIVE_REQ_DIR/implementation-design.md` 段 1.5「原型简化项」全表 —— 每条含
`SIMP-ID` / PRD 锚点 / 真实需求 / 原型本次计划简化为 / 为什么简化 / 来源（kind 1/2）。

> **IRON 容错**：
> - 旧 req 无 `req-events.jsonl` → `list` 输出「No req events found.」→ adjustment 分支 silent skip
> - implementation-design.md 不存在或段 1.5 不存在或单行「无」→ simp 分支 silent skip
> - 两分支都 skip → 本步骤整体 silent skip

#### 2a.2 第一步：逐条 adjustment overwrite prd.md（顺序硬约束：先全 overwrite）

对每条 `adjustment`：定位 `prd_anchor` 指向的 PRD 章节，把内容从 `before` 改成 `after`
（PRD → as-built），呈交 PM 审。**产物预览「原型」节**：stage 3 写的是产物意图描述（文字版），
本步骤用真实原型链接 / 截图**替换回填**（codex#5）。

- PM 逐条审 diff（对话式）；PM 满意 → 落 `prd.md`
- 全部 adjustment overwrite 完成后**才进步骤 2a.3 simp 标注**（不交叉）

#### 2a.3 第二步：逐条 simp 标注追加 prd.md（顺序硬约束：再全 simp 标注）

对段 1.5 每条 SIMP 行：

1. **锚点解析**：按「§<章节号> <功能名>」/「Story <编号>」格式解析 SIMP 行的「PRD 锚点」
   字段，在 prd.md §六 功能需求 / §七 验收标准定位对应行
2. **解析失败**（找不到对应章节、章节名漂移、功能名多匹配等）→ **停下问 PM**：

   ```
   段 1.5 SIMP-N 的 PRD 锚点「§六 6.X 用户登录」在当前 prd.md 找不到对应章节。
   可能原因：
   - PRD §六 章节号被前面 adjustment overwrite 改了 → 锚点过期
   - simp 段写时锚点笔误
   - PRD 章节命名重排
   请选：
   - 我手动告诉你 SIMP-N 对应 prd.md 哪一行
   - 跳过 SIMP-N 不标注（close-report 会记「N 条 simp 锚点未解析」）
   - 中止本次 close-req 回去修 simp 段
   ```

   PM 决定后按答复执行；**不**机械写错位置。
3. **解析成功** → 在 PRD 该行**保留真实需求原文 + 追加一句标注**：
   - kind 1（行为简化）：在功能描述段末追加「> **原型本次计划简化为**：<原型本次计划简化为>（来源：implementation-design.md SIMP-N）」
   - kind 2（整块不做）：在功能段末追加「> **本功能原型本次不实现**（来源：implementation-design.md SIMP-N）」
4. PM 逐条审 diff（对话式），同 adjustment 流程；PM 满意 → 落 `prd.md`

**顺序硬约束**：所有 simp 标注必须在所有 adjustment overwrite 完成后才追加。
若中途交叉 → 后续 adjustment overwrite 可能把已追加的 simp 标注抹掉。

#### 2a.4 PRD 写回后 PM-view re-lint

所有 adjustment overwrite + simp 标注落盘后，对 prd.md 跑一次 PM-view lint：

```bash
python3 "$PMAI_HOME/scripts/check-doc-pm-view.py" "$ACTIVE_REQ_DIR/prd.md"
```

理由：simp 标注是从 implementation-design.md 段 1.5「原型本次计划简化为」字段写过来的，
源头虽已 `--simp-scope` lint 过，但写回 PRD 时上下文变了（裸字段 vs 引用块），
再校验一次确保 PRD 整文件仍守 PM-view 纪律。处理输出：

- 0 errors + 0 warnings → 进步骤 2a.5
- 有 errors → 反查 simp 标注或 adjustment overwrite 引入的违例字段，手 patch；连续 3 次仍有
  error → 停下问 PM
- 有 warnings → 每条显式判定，不默默 ack

#### 2a.5 commit + 边界

- 全部对齐 + 标注 + lint 通过后 git commit 留痕：`docs(prd): close-req as-built 反向对齐 + 原型简化项标注 — req-NNN`
- **只改实际内容**（PRD 行为 → as-built + simp 标注追加），是 close 时一次性、有意的内容更新；
  不是 stage 3 那种「冻结」语义。git commit 留痕、可审计。
- 反向对齐**不写任何元数据 / hash 回 PRD**（PRD 是单文件、无 hash 机器；只改业务内容，
  避免 memory `reconcile-no-self-reference` 类自指问题）。
- 无 adjustment 事件 + 无 simp 行 → silent skip，close-report 记「本 req PRD 无执行期偏离、
  无原型简化项，无需反向对齐」。
- 无 adjustment 但有 simp → 只跑步骤 2a.3 simp 标注分支；反之只跑 2a.2。
- close-report 增「原型简化项」节：列每条 SIMP-ID + PRD 锚点 + 计划简化为，让评审
  有汇总入口（detail 见 close-req SKILL Phase 1 步骤 1）。

> modulespec 沉淀已由步骤 1.5 rewrite 流程覆盖 —— 本步骤只做 PRD 反向对齐 + simp 标注。

### 步骤 2b：~~增量同步项目主 PRD~~（已砍）

> 项目主 PRD `docs/prd.md` 已砍。本步骤废弃。→ 跳到 §2c。

### 步骤 2c：检查 req 级实现深度变更，提示 PM 是否同步项目级

读 req 级实现深度变更记录的 `## 🔧 本轮实现深度变更` section：

- 现役流程：实现深度变更记录在 req 级实现设计文档（HOW 视图）。
- 在飞旧 req 兼容：仅有 `$ACTIVE_REQ_DIR/solution.md` 时，从其 `## 🔧 本轮实现深度变更` section 读。
- 两处都无该 section / 内容是「无变更」/ 留空 → 跳过本步。
- 内容含变更描述 → 向 PM 呈交两段：
  1. **req 级变更内容**（`## 🔧 本轮实现深度变更` 原文）
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
python3 "$PMAI_HOME/scripts/req-transition.py" "$ACTIVE_REQ_DIR" --to 7
```

### 步骤 3.4：业务词催补 hook（从 prd-writing 迁来）

req 关闭时是业务实体真正落地稳定的时刻（task 都执行完、PRD 已 as-built 反向对齐）—— 这一步把本 req 引入的新业务词 / 角色 patch 进 `docs/PROJECT.md` 业务术语表 / 用户画像表，作为长期沉淀。

```bash
# 扫输入 = 本 req 全部 PM 视图主文件（prd + 所有 closed task 主文件 .md，不扫 .engineering.md）
TMPFILE=$(mktemp)
cat "$ACTIVE_REQ_DIR/prd.md" > "$TMPFILE"
for t in "$ACTIVE_REQ_DIR"/tasks/closed/*.md; do
  [ -f "$t" ] && [[ "$t" != *.engineering.md ]] && cat "$t" >> "$TMPFILE"
done

python3 "$PMAI_HOME/scripts/_lib/term-detector.py" \
  "$TMPFILE" "$REPO_ROOT" --req-dir "$ACTIVE_REQ_DIR"

rm "$TMPFILE"
```

按返回 JSON 处理（详见 `skills/_shared/term-detector/SKILL.md`）：≥3 新词走多词批量话术；<3 走单词；新角色独立话术；全空 silent skip。PM 拒绝某词 → 追加 `.term-skip.json`；PM 同意 → patch `$REPO_ROOT/docs/PROJECT.md` 业务术语表 / 用户画像表。

**为什么放在这里**：本 req 内的 `prd.md §三` 已经承担过本 req 临时词典的职责（impl-design / task-spec 已读它）；close-req 是把临时词典里"真正稳定下来的、值得跨 req 共享的"那部分 promote 到 PROJECT.md 业务术语表的唯一时机。

### 步骤 4：commit 所有改动

在 req worktree 中 commit 所有未提交的改动：

```bash
git add -A
git commit -m "close: req-NNN-<slug>"
```

### 步骤 5：登记 finalize marker，提示 PM 切窗口

写 `$REPO_ROOT/.runs/pending-close-req.json`（marker 落在主仓的 `.runs/`，因为 req worktree 会被 phase 2 删掉）：

```bash
mkdir -p "$REPO_ROOT/.runs"
python3 - "$PENDING_MARKER" "$ACTIVE_REQ_DIR" "$REQ_BRANCH" "$REQ_WORKTREE" <<'PY'
import json, sys, datetime
marker, req_dir, branch, worktree = sys.argv[1:5]
entry = {
    "req_dir_abs": req_dir,
    "branch": branch,
    "worktree": worktree,
    "ready_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
}
with open(marker, "w") as f:
    json.dump(entry, f, indent=2, ensure_ascii=False)
PY
```

AI 向 PM 输出结束语，req 窗口工作到此结束：

```
✅ Req 文档已 commit，stage = 7，已登记待 finalize marker。

▶ Next Up — 切到主仓窗口跑 /pmai-close-req：

如果主仓窗口还开着：直接切过去运行 `/pmai-close-req`
如果主仓窗口已关：
  cd <MAIN_REPO_ROOT>     ← 替换为主仓根绝对路径
  claude
  /pmai-close-req

AI 会自动走 Phase 2 完成 merge + 删 worktree/branch。
```

**Phase 1 短路场景**：进入 skill 时检测到 marker 已存在（之前调过一次但 PM 没切窗口），跳过步骤 1-4，直接输出上方结束语。不要重复写文档或重复 commit。

## Phase 2：在主仓内执行

### 步骤 P2.1：读 marker 并校验

```bash
if [ ! -f "$PENDING_MARKER" ]; then
  echo "❌ 没有待 finalize 的 req。"
  echo "   如要启动 close-req，请进 req worktree 后调用 /pmai-close-req"
  exit 1
fi

REQ_DIR_ABS=$(python3 -c "import json; print(json.load(open('$PENDING_MARKER'))['req_dir_abs'])")
```

### 步骤 P2.2：调 close-req.sh

```bash
bash scripts/close-req.sh "$REQ_DIR_ABS"
```

脚本自动：
1. 二次校验 cwd 不在 req worktree 内（防御性）
2. 校验 stage = 7 + 所有 task 已关闭
3. 在 req 分支移动目录到 `requirements/closed/` + 更新 meta + **建 `docs/prds/<req-name>.md` symlink 收口**（指向 `requirements/closed/<req-name>/prd.md`，让 PM 在 `docs/prds/` 一处看所有 PRD） + commit
4. merge req 分支 → main
5. 直接删 req worktree + req branch

### 步骤 P2.3：清 marker

```bash
rm -f "$PENDING_MARKER"
```

### 步骤 P2.4：确认结果

```
✅ Req 已完全关闭：<req-id>
📍 当前位置：主仓 main 分支

▶ Next Up — /pmai-new-req "<下一个需求>"（开始下一 req）
         或 /pmai-project-solution（roadmap 规划，重新审视项目方向）
```

## Rules

- Phase 1 必须在 req worktree 内执行；Phase 2 必须在主仓内执行
- Phase 间通过 `$REPO_ROOT/.runs/pending-close-req.json` 衔接（marker 落主仓，因 req worktree 会被 phase 2 删）
- Phase 1 进入时若 marker 已存在 → 短路（直接告知"已 ready，请切窗口"），不重复写文档
- Phase 2 进入时若 marker 不存在 → 报错（避免误触）
- merge 到 main 后不可回退（stage 7 是终态）
- req 目录移到 closed/ 后保留完整记录
- close-req.sh 直接删 worktree + branch（无 pending-cleanup.json 中转）
