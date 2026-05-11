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

### 步骤 1：写 close-report.md

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
[列出本次 req 修改过的文档]

## 遗留问题
[如有未解决的问题或后续建议]
```

**生成规则：**
- 遍历 `tasks/*.md` 填「完成的 task」表（这里只剩已完成态，因为 stage 7 guardrail 要求所有未关闭 task 都收尾）。
- 遍历 `tasks/discarded/*.md` 填废弃栏；为空时整个 `<details>` 块省略。
- 已废弃 task 编号断号是合规信号，不要为「整理顺序」而改号。

### 步骤 1.5：扫描半 close cleanup TODO（v2 重做场景必经）

**目的**：闭合 task 半 close 的设计意图——`SKIP_DOC_UPDATE` marker 显式声明"由 close-req 阶段聚合所有 SKIP marker 后统一 rewrite"（doc-update SKILL 步骤 0.5），但 close-req 历史上没读这些 marker，导致 marker 永远 `cleanup_status="pending"`、cleanup TODO 永远没人扫。本步骤把这个闭环补上。

**流程**：

1. 遍历 `tasks/*.engineering.md`（兼容旧格式：`tasks/*.md` 含 `## 文档偏差` section），找所有 §10 含
   ```html
   <!-- SKIP_DOC_UPDATE: ... cleanup_status="pending" -->
   ```
   marker 的 task。

2. **预筛跨 req 推迟项**：marker reason 含 `"等下游 req"` / `"下游 req 处理"` / `"inter-req"` 等关键词时 → silent skip 这条 marker（保留 pending 状态），打印一行 `task-NNN 标 inter-req 推迟，跳过`。

3. 对剩下每个 marker，提取：
   - marker reason
   - 同 task §12 cleanup TODO 清单（pending 项）
   - PM 视图「📁 历史档案 → 业务层偏差」表
   - 工程合同 §10 偏差表

4. **按目标文档分组**：同一份 `docs/modules/<module>.md` / `docs/DESIGN.md` / `docs/prd.md` 的多 task 偏差并到一起。

5. 聚合后呈交 PM，按目标文档逐份决议（AskUserQuestion 或 prose）：

   | 决议 | 触发条件 | 行为 |
   |---|---|---|
   | **rewrite**（默认） | 同目标文档 ≥2 task 改 | 调 doc-update SKILL 步骤 8 rewrite mode |
   | **patch** | 单 task 改单文档 | 调现有 doc-update 对账模式（步骤 1.5/1.6/2-5）|
   | **skip** | 本 req 不沉淀，留到下游 req | marker `cleanup_status` 保持 `pending`，append inter-req 备注 `<!-- DEFERRED_TO_REQ: req-NNN reason="..." -->` |

6. 完成处理后：
   - rewrite / patch 决议 → 把对应 task §10 marker 的 `cleanup_status` 改为 `"done"` + §12 cleanup TODO 对应项标 `[x]`
   - skip 决议 → 不动 marker

7. 全部 marker 处理完毕后才进步骤 2a `/prd-writing`（这时 module spec 已经统一沉淀，prd-writing 输入干净）。

**PM 拒绝处理**：PM 决议过程中拒绝任一 rewrite / patch（不接受 AI 草稿）→ close-req 中止，下次重跑 close-req 时回到步骤 1.5 重新决议。不要尝试"半重写"。

**边界**：
- 步骤 1.5 是 v2 重做场景的**主路径**（多 task 半 close）；**单 req 内无 SKIP marker → 步骤 1.5 silent skip 进 2a**
- 不要在本步骤直接修改任何 task md 内容——marker 状态由 doc-update SKILL 在 rewrite/patch 完成时回写

### 步骤 2a：产出 req 级 PRD（按 doc-update 覆盖度判断）

#### 2a.1 自动检测 doc-update 覆盖度

调用前先检测本 req 周期内 task doc-update 是否已经把规格沉淀完整：

```bash
# 1. req 分支周期内改过 docs/prd.md 与 docs/modules/*/functions.md 的 commits
COVERAGE_COMMITS=$(git -C "$REPO_ROOT" log --oneline \
  $(git merge-base "$REQ_BRANCH" main).."$REQ_BRANCH" \
  -- 'docs/prd.md' 'docs/modules/' 2>/dev/null | wc -l | tr -d ' ')

# 2. 本 req 各 task 的 SKIP_DOC_UPDATE marker 数（cleanup_status="pending" 还在的）
SKIP_PENDING=$(grep -l 'cleanup_status="pending"' "$ACTIVE_REQ_DIR/tasks/"*.md 2>/dev/null | wc -l | tr -d ' ')
TASK_COUNT=$(ls "$ACTIVE_REQ_DIR/tasks/"*.md 2>/dev/null | grep -v engineering | wc -l | tr -d ' ')

echo "doc-update 覆盖：$COVERAGE_COMMITS commits 改过 docs/{prd.md, modules/}"
echo "task SKIP marker pending: $SKIP_PENDING / $TASK_COUNT"
```

#### 2a.2 按覆盖度走默认路径

| 检测结果 | 默认推荐 | 含义 |
|---|---|---|
| `COVERAGE_COMMITS >= TASK_COUNT` 且 `SKIP_PENDING == 0` | **默认"跳过 PRD"** | 全部 task 都 doc-update 沉淀进 docs/prd.md / modules，再写一份 req 级 prd.md 是冗余 |
| `COVERAGE_COMMITS > 0` 但有 SKIP_PENDING | **默认"补差"** | 部分 task 已沉淀，未沉淀的需要在 req 级 prd.md 补 |
| `COVERAGE_COMMITS == 0` | **默认"完整 PRD"** | 没有 task 把内容沉淀进项目级文档，req 级 prd.md 是唯一规格记录 |

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
