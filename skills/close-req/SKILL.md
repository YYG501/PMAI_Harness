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
<!-- placeholder：本段在步骤 1.5 完成后回填（含 rewrite 覆盖的 docs/modules/* + docs/prd.md 等）。
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
     docs/归档/完成/D13-modulespec/主方案.md §0.1 + §1 + §3 vp-2 + polish-1/7/13/15。 -->

**目的**：D13 final 下 close-task 永不调 doc-update（不写 modulespec），所有 task 的偏差与功能清单累积到本步骤一次性沉淀。N 次 doc-update 启动成本合并成本 step 一次（§0.1 痛点）。

**输入源**（遍历所有 closed task，4 处合一）：

1. **PM 视图主文件** `tasks/*.md` 头部「📌 任务卡」表格的 `**所属模块**` / `**所属模块章节**` 字段 → 决定 sediment 进哪份 `docs/modules/<module>.md`
2. **PM 视图主文件** `## 📋 功能清单` → 沉淀进 module spec 的功能合同
3. **PM 视图主文件** `## 📁 历史档案 → 业务层偏差` 表 → 指向 brief / analysis / solution PM 视图 / prd / module 规格 的偏差对账
4. **工程合同** `tasks/*.engineering.md` `## 10. 文档偏差` 表（仅 `HAS_ENG=true`）→ 指向 solution.engineering / DESIGN / CONTEXT / module 等工程层偏差对账

**流程**：

1. 遍历 `tasks/*.md`（过滤 `*.engineering.md`）和成对的 `.engineering.md`；提取每 task 的 4 处输入。
2. **按目标文档分组**：同一份 `docs/modules/<module>.md` / `docs/DESIGN.md` / `docs/prd.md` / `docs/CONTEXT.md` / `solution.md` / `solution.engineering.md` 的多 task 偏差并到一起。基础设施 task（`所属模块=基础设施`）跳过 module sediment，但其偏差表仍走对账。
3. 聚合后呈交 PM，按目标文档逐份决议（AskUserQuestion 或 prose；**两选项**，skip 分支 D13 final 已砍）：

   | 决议 | 触发条件 | 行为 |
   |---|---|---|
   | **rewrite**（默认 / D13 final 主路径） | 任何 closed task 改某目标文档 → 默认 rewrite | 调 doc-update SKILL 步骤 8 rewrite mode（req-level aggregation contract，不要求 ≥2 SKIP marker）|
   | **patch** | PM 显式选 + 单 task 单文档单段 | 调现有 doc-update 对账模式（步骤 1.5/1.6/2-5）|

4. PM 决议后，doc-update SKILL §8 返回 `{覆盖的目标文档清单, 覆盖的模块清单}`（polish-2 输出契约），供步骤 2a 作 metric。
5. **回填 close-report.md `## 文档变更` 段**（polish-9）：把 `REWRITE_COVERED_FILES` 写进步骤 1 初稿留的 placeholder。
6. 全部目标文档处理完毕后进步骤 2a。

**quickfix 历史改动处理**（polish-8）：

`/quick-fix` 改 `docs/modules/*.md` 是**旁路**（不走 close-task → close-req 流程），但 modulespec 当前文件状态已包含 quickfix 改动（git working tree）。步骤 1.5 调 doc-update §8 rewrite mode 时，**输入是「当前 modulespec 全文 + 本 req 各 task 偏差」**，quickfix 改动天然包含在 baseline 里 → 不需要额外收集机制。如果 PM 想审 quickfix 历史 → 看 `git log --grep '\[quick-fix\]' -- docs/modules/`，与 rewrite 流程解耦。

**PM 拒绝处理**：PM 决议过程中拒绝任一 rewrite / patch（不接受 AI 草稿）→ close-req 中止，下次重跑 close-req 时回到步骤 1.5 重新决议。不要尝试"半重写"。

**边界**：

- 步骤 1.5 是 D13 final 下 close-req 的**主路径**（每 req 必跑一次）
- **本 req 内全部 closed task 偏差表都是「无偏差」且无功能清单变化** → silent skip 进步骤 2a（仅在「基础设施 task 单 req」之类的纯非业务 req 出现）
- ~~inter-req 推迟 / DEFERRED_TO_REQ skip 分支~~ → D13 final 已砍（polish-13，§0.4.1 多 req 并行不在范围）
- 旧 SKIP marker 兼容（polish-15）：消费仓若有旧 `<!-- SKIP_DOC_UPDATE: ... cleanup_status=... -->` 残留（D13 final 前写的），本步骤遇到时**等同普通偏差源处理**（一次性消费掉，rewrite 决议时 `cleanup_status` 改 `done` 留作 audit trail；不再阻塞 stage 6→7 推进）

### 步骤 2a：产出 req 级 PRD（按步骤 1.5 实际 rewrite 覆盖判断）

#### 2a.1 用步骤 1.5 rewrite 覆盖清单作 metric（D13 final, polish-4）

<!-- WHY breadcrumb: D13 final 把每 task doc-update commits 数（COVERAGE_COMMITS）
     这个 per-task metric 砍掉，改用步骤 1.5 实际 rewrite 的目标文档 / 模块清单。
     close-task 不再调 doc-update 后，COVERAGE_COMMITS 永远 0 会让旧 metric 误判。
     详见 docs/归档/完成/D13-modulespec/主方案.md §3 polish-4。 -->

读步骤 1.5 doc-update §8 返回的覆盖清单（polish-2 输出契约）：

```text
REWRITE_COVERED_FILES   # 步骤 1.5 rewrite 覆盖的目标文档（含 docs/prd.md / docs/modules/* / 等）
REWRITE_COVERED_MODULES # 覆盖的模块名清单（PM 视图「所属模块」字段汇总）
TASK_COUNT              # 本 req 所有 closed task 数（不含基础设施 task）
MODULE_TASKS_DONE       # 「所属模块」非「基础设施」且步骤 1.5 rewrite 已覆盖的 task 数
```

#### 2a.2 按覆盖度走默认路径

| 检测结果 | 默认推荐 | 含义 |
|---|---|---|
| `MODULE_TASKS_DONE == TASK_COUNT` 且 `docs/prd.md ∈ REWRITE_COVERED_FILES` | **默认"跳过 PRD"** | 全部业务 task 都 rewrite 沉淀进 docs/prd.md / modules，再写一份 req 级 prd.md 是冗余 |
| `MODULE_TASKS_DONE > 0 但 < TASK_COUNT` 或 `docs/prd.md ∉ REWRITE_COVERED_FILES` | **默认"补差"** | 部分 task 已沉淀，未沉淀的需要在 req 级 prd.md 补 |
| `REWRITE_COVERED_FILES == ∅` | **默认"完整 PRD"** | 步骤 1.5 silent skipped（无任何业务偏差），req 级 prd.md 是唯一规格记录 |

向 PM 呈交检测结果 + 对话式三选项（不列字母）：

```
📊 doc-update 覆盖度检测
   - 这次需求里 docs/prd.md + docs/modules/ 累计被改了 X 次
   - 还有 Y 条 task 标了"跳过文档沉淀"未补
   - 默认推荐：<完整 PRD / 补差 / 跳过 PRD>（理由：…）

要怎么办？
 - 跑 /prd-writing 写一份完整 req 级 prd.md
 - 跑 /prd-writing 只补还没沉淀的部分（推荐"补差"时默认）
 - 跳过这步（已经沉淀过了，再写一份是冗余；自动在 close-report.md 标一句话）
```

**PM 回答的内部分流 + 内部决议代号映射**（决议代号给 step 2b 用）：
- PM 说「完整 / 全写 / 完整 PRD」等 → 内部决议 `A` → 跑 /prd-writing 写完整 req 级 prd.md
- PM 说「跳过 / 不写 / 已经沉淀」等 → 内部决议 `B` → 跳过；自动在 close-report.md 写"req 级 PRD 已通过 task doc-update 沉淀"
- PM 说「补差 / 只补 / 补未沉淀」等 → 内部决议 `C` → 跑 /prd-writing 但 prompt 含"docs/prd.md 已包含 X，重点写未沉淀的 Y/Z"
- PM 直接说「OK / 按推荐 / 默认」 → 走默认推荐对应的分支

**任何分支都不需要 PM 写理由**——三个分支都是合规路径，差异只在产物详细度。

### 步骤 2b：增量同步项目主 PRD（按 step 2a 决议链推进）

| step 2a 决议 | step 2b 默认行为 |
|---|---|
| **A**（完整 req 级 prd.md） | 调 `/project-prd-update` 把 req 级 prd.md 增量并入 `docs/prd.md` |
| **B**（跳过 step 2a） | 默认跳过 step 2b（task doc-update 已经直接改 docs/prd.md，再调 /project-prd-update 是 no-op）；在 close-report 写"项目主 PRD 已通过 task doc-update 直接同步" |
| **C**（补差） | 调 `/project-prd-update`，输入 prompt 含"step 2a 仅补 Y/Z 部分，请只 reconcile 这两部分" |

同样不需要 PM 写跳过理由——决议链由 step 2a 自动推导。

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
