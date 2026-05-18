---
name: close-req
description: |
  Req 关闭：写 close-report、更新 PRD、merge 到 main、归档。
---

# /close-req

## When To Use

- Orchestrator 在 stage 7 调用
- 所有 task 必须已关闭

## 两阶段调用（必读）

`/close-req` 设计为两阶段调用，AI 根据 cwd 自动判断当前阶段：

- **Phase 1**（cwd 在 req worktree 内）：写 close-report、PRD、commit、登记待 finalize marker
- **Phase 2**（cwd 在主仓，不在任何 worktree 内）：merge → main、删 worktree/branch、清 marker

PM 体感：
1. 在 req 窗口运行 `/close-req` → AI 走 Phase 1 → 提示切到主仓窗口
2. PM 切到主仓窗口
3. 在主仓窗口运行 `/close-req` → AI 走 Phase 2 → 完全关闭

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: close-req"
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

<!-- WHY breadcrumb: D13 final 下 step 1.5 才发生 modulespec rewrite。
     close-report 的「文档变更」段必须在 step 1.5 之后填，否则会漏 rewrite 改动。
     polish-9（Eng Codex E4）。 -->

在 req 目录写 `close-report.md`，内容包括：

```markdown
# Req Close Report: req-NNN-<slug>

## 需求概述
[从 solution.md §📌 方案摘要提取，**不读 brief.md**——brief 是 stage 1 初稿，到 close-req 时已被 7 个 stage 演化，用它写关闭报告会反映已被推翻的初衷]

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
<!-- placeholder：本段在步骤 1.5 完成后回填（含 rewrite 覆盖的 docs/modules/* + docs/DESIGN.md + docs/CONTEXT.md 等；docs/prd.md 已砍，不在 rewrite 范围）。
     如果步骤 1.5 silent skipped（无业务偏差），本段写"本 req 无项目级文档变更"。 -->

## 遗留问题
[如有未解决的问题或后续建议]
```

**生成规则：**
- 遍历 `tasks/*.md` 填「完成的 task」表（这里只剩已完成态，因为 stage 7 guardrail 要求所有未关闭 task 都收尾）。
- 遍历 `tasks/discarded/*.md` 填废弃栏；为空时整个 `<details>` 块省略。
- 已废弃 task 编号断号是合规信号，不要为「整理顺序」而改号。
- **`## 文档变更` 段写 placeholder 注释 + 留空**，等步骤 1.5 完成后用 doc-update §8 返回的 `REWRITE_COVERED_FILES` 清单回填。

### 步骤 1.5：聚合所有 closed task 偏差，按目标文档统一沉淀（D13 final, 2026-05-16）

<!-- WHY breadcrumb: D13 final 把 modulespec 沉淀从 close-task per-task 推到这一步聚合。
     输入源不再是 SKIP_DOC_UPDATE marker（close-task vp-1 后永远不写 marker），
     改为遍历所有 closed task 直接收集偏差。详见
     docs/归档/完成/modulespec-维护/主方案.md §0.1 + §1 + §3 vp-2 + polish-1/7/13/15。 -->

**目的**：D13 final 下 close-task 永不调 doc-update（不写 modulespec），所有 task 的偏差与功能清单累积到本步骤一次性沉淀。N 次 doc-update 启动成本合并成本 step 一次（§0.1 痛点）。

**输入源**（遍历所有 closed task，4 处合一）：

1. **PM 视图主文件** `tasks/*.md` 头部「📌 任务卡」表格的 `**所属模块**` / `**所属模块章节**` 字段 → 决定 sediment 进哪份 `docs/modules/<module>.md`
2. **PM 视图主文件** `## 📋 功能清单` → 沉淀进 module spec 的功能合同
3. **PM 视图主文件** `## 📁 历史档案 → 业务层偏差` 表 → 指向 brief / analysis / solution PM 视图 / prd / module 规格 的偏差对账
4. **工程合同** `tasks/*.engineering.md` `## 10. 文档偏差` 表（仅 `HAS_ENG=true`）→ 指向 solution.engineering / DESIGN / CONTEXT / module 等工程层偏差对账

**流程**：

1. 遍历 `tasks/*.md`（过滤 `*.engineering.md`）和成对的 `.engineering.md`；提取每 task 的 4 处输入。
2. **按目标文档分组**：同一份 `docs/modules/<module>.md` / `docs/DESIGN.md` / `docs/CONTEXT.md` / `solution.md` / `solution.engineering.md` 的多 task 偏差并到一起（**v5 vp-1 后 `docs/prd.md` 不在范围**）。基础设施 task（`所属模块=基础设施`）跳过 module sediment，但其偏差表仍走对账。
3. 聚合后呈交 PM，按目标文档逐份决议（AskUserQuestion 或 prose；**两选项**，skip 分支 D13 final 已砍）：

   | 决议 | 触发条件 | 行为 |
   |---|---|---|
   | **rewrite**（默认 / D13 final 主路径） | 任何 closed task 改某目标文档 → 默认 rewrite | 调 doc-update SKILL 步骤 8 rewrite mode（req-level aggregation contract，不要求 ≥2 SKIP marker）|
   | **patch** | PM 显式选 + 单 task 单文档单段 | 调现有 doc-update 对账模式（步骤 1.5/1.6/2-5）|

4. PM 决议后，doc-update SKILL §8 返回 `{覆盖的目标文档清单, 覆盖的模块清单}`（polish-2 输出契约），供步骤 2a 作 metric。
5. **回填 close-report.md `## 文档变更` 段**（polish-9）：把 `REWRITE_COVERED_FILES` 写进步骤 1 初稿留的 placeholder。
6. **INDEX.md derived refresh**（v5 vp-3，独立于 REWRITE_COVERED_FILES metric）：

   主 rewrite 完成后，单独刷新 `docs/modules/INDEX.md`。**不进** REWRITE_COVERED_FILES（避免污染 §2a metric）：

   ```bash
   # 1. AI 归纳：读本 req 涉及的 docs/modules/<m>.md 的 §摘要 + §一模块定位 + §三一级章节标题，提炼用途（≤30 字）
   # 2. patch docs/modules/INDEX.md（新模块插入新行；已存在且本 req 改过规格的更新简介；未改动的不动）
   # 3. lint 校验
   python3 "$REPO_ROOT/.claude/scripts/check-index-lint.py" "$REPO_ROOT" --exit-code || {
     # lint 失败 → AI 二次重写
     # 仍失败 → 输出空 diff 跳过本次 INDEX 刷新（不阻塞 close-req 整体）
     echo "⚠️ INDEX lint 二次重写仍失败，跳过本次 INDEX 刷新"
   }
   # 4. PM 审 diff：git diff docs/modules/INDEX.md
   # PM reject → AI 重新归纳；2 次仍 reject → 空 diff 跳过（同上）
   ```

   独立输出字段：`{"index_refreshed": true|false, "index_lint_passed": true|false}`，写入 step 1.5 返回但**不进** REWRITE_COVERED_FILES。

7. 全部目标文档处理完毕（含 INDEX derived refresh）后进步骤 2a。

**quickfix 历史改动处理**（polish-8）：

`/quick-fix` 改 `docs/modules/*.md` 是**旁路**（不走 close-task → close-req 流程），但 modulespec 当前文件状态已包含 quickfix 改动（git working tree）。步骤 1.5 调 doc-update §8 rewrite mode 时，**输入是「当前 modulespec 全文 + 本 req 各 task 偏差」**，quickfix 改动天然包含在 baseline 里 → 不需要额外收集机制。如果 PM 想审 quickfix 历史 → 看 `git log --grep '\[quick-fix\]' -- docs/modules/`，与 rewrite 流程解耦。

**PM 拒绝处理**：PM 决议过程中拒绝任一 rewrite / patch（不接受 AI 草稿）→ close-req 中止，下次重跑 close-req 时回到步骤 1.5 重新决议。不要尝试"半重写"。

**边界**：

- 步骤 1.5 是 D13 final 下 close-req 的**主路径**（每 req 必跑一次）
- **本 req 内全部 closed task 偏差表都是「无偏差」且无功能清单变化** → silent skip 进步骤 2a（仅在「基础设施 task 单 req」之类的纯非业务 req 出现）
- ~~inter-req 推迟 / DEFERRED_TO_REQ skip 分支~~ → D13 final 已砍（polish-13，§0.4.1 多 req 并行不在范围）
- 旧 SKIP marker 兼容（polish-15）：消费仓若有旧 `<!-- SKIP_DOC_UPDATE: ... cleanup_status=... -->` 残留（D13 final 前写的），本步骤遇到时**等同普通偏差源处理**（一次性消费掉，rewrite 决议时 `cleanup_status` 改 `done` 留作 audit trail；不再阻塞 stage 6→7 推进）

### 步骤 2a：产出 req 级 PRD（PM 主导，v5 vp-2 决议）

> **D 决议（v5 §2 vp-2，2026-05-18）**：原 D13 final 覆盖度算法（`MODULE_TASKS_DONE == TASK_COUNT && docs/prd.md ∈ REWRITE_COVERED_FILES`）整段砍掉。PM 视角下「req 级 PRD」是评审材料（给研发评审），是否产出由 **PM 显式决定**，0 或 1 份/req，不再算覆盖度。

直接对话式问 PM：

```
📝 req close 阶段。要不要给研发评审写一份 req 级 PRD？

- 要 → 跑 /prd-writing，对话式确认输入后产出 req 级 PRD
- 不要 → 跳过这步；close-report.md 自动记一句"本 req 未产出 req 级 PRD"
```

**PM 回答的内部分流**：
- PM 说「要 / 写一份 / OK」等 → 跑 `/prd-writing`（详见 §2 vp-5 改造后的灵活模式：对话式确认输入清单 + 产物路径）
- PM 说「不要 / 跳过 / 没必要」等 → 跳过；AI 在 close-report.md 写"本 req 未产出 req 级 PRD（PM 决定）"

**任何分支都不需要 PM 写理由** —— PM 主导决策，不要 AI 二次质疑。

> **历史**：v5 之前 §2a 用覆盖度算法（`MODULE_TASKS_DONE == TASK_COUNT` 等）做三选一推荐（完整 / 补差 / 跳过 PRD），与 PM 主导原则冲突（autoplan CEO F4 / DX D2 共识）。v5 vp-2 砍此算法。

### 步骤 2b：~~增量同步项目主 PRD~~（v5 vp-2 + vp-1 砍）

> **v5 §4 砍掉清单 #3 / #4**：项目主 PRD `docs/prd.md` 已砍（vp-1 实施），`/project-prd-update` skill 已砍。本步骤 D13 final 时的「链式同步项目主 PRD」逻辑整段废弃。

req 级 PRD 是单 req 评审材料（PM 决定是否产出），定稿后不修订 / 不并入项目主 PRD（因为项目主 PRD 已经不存在了）。

→ 跳到 §2c。

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

### 步骤 3.5：里程碑追加询问（v5 vp-3）

问 PM 是否把本 req 加入 `docs/CONTEXT.md ## 产品路线`：

```
📝 本次 req 刚 close。要不要加进 `docs/CONTEXT.md` 产品路线？
- 是：追加 `YYYY-MM-DD · <req-name>（关联 <req-id>）`，要标 ⭐ 吗（标了能用 `status-view --milestone` 筛）
- 否：不动路线（默认）
```

PM 答「是 + ⭐」/「是 不标 ⭐」/「否」三选：

- 「是 + ⭐」→ AI patch `docs/CONTEXT.md` `## 产品路线` `### 已完成` 段追加 `- ⭐ YYYY-MM-DD · <req-name>（关联 <req-id>）`
- 「是 不标 ⭐」→ 同上但不加 ⭐
- 「否 / 默认 / 不动」→ 不 patch，进步骤 4

不追问理由（PM 主观判断，autoplan 不进 §0）。

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

请切到主仓窗口（cwd = 主仓根目录），再次运行：

  /close-req

AI 会自动走 Phase 2 完成 merge + 删 worktree/branch。
```

**Phase 1 短路场景**：进入 skill 时检测到 marker 已存在（之前调过一次但 PM 没切窗口），跳过步骤 1-4，直接输出上方结束语。不要重复写文档或重复 commit。

## Phase 2：在主仓内执行

### 步骤 P2.1：读 marker 并校验

```bash
if [ ! -f "$PENDING_MARKER" ]; then
  echo "❌ 没有待 finalize 的 req。"
  echo "   如要启动 close-req，请进 req worktree 后调用 /close-req"
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
3. 在 req 分支移动目录到 `requirements/closed/` + 更新 meta + commit
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

运行 /new-req 开始下一个需求。
```

## Rules

- Phase 1 必须在 req worktree 内执行；Phase 2 必须在主仓内执行
- Phase 间通过 `$REPO_ROOT/.runs/pending-close-req.json` 衔接（marker 落主仓，因 req worktree 会被 phase 2 删）
- Phase 1 进入时若 marker 已存在 → 短路（直接告知"已 ready，请切窗口"），不重复写文档
- Phase 2 进入时若 marker 不存在 → 报错（避免误触）
- merge 到 main 后不可回退（stage 7 是终态）
- req 目录移到 closed/ 后保留完整记录
- close-req.sh 直接删 worktree + branch（无 pending-cleanup.json 中转）
