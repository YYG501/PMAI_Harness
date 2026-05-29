---
name: pmai-close-req
description: |
  需求收尾（沉淀）：更新产品现状、把主原型合回主线、归档；按需反向出可评审 PRD。
---

# /pmai-close-req

> **PM 视图（banner + 决策门 label）**：入口 banner（`status-view.py --banner-only --skill CLOSE-REQ`）；收尾确认门 label 按 `_shared/pm-view/banner-rules.md` §3 三条硬规则；退出 Next Up 引导「项目方向是否需要调整」（`/pmai-project-solution` 产品路线规划）或 `/pmai-new-req` 起下一个需求。
>
> **PM 答题规则**：所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 四条硬规则走（空答 STOP / 没拿到答案禁止 merge 到主线 / runtime 退化保留 wait / 多决策拆开顺序问）。**Runtime 兜底**：本 skill 各门写的都是 picker 形态；runtime 不支持时 AI 按 §1.3 自动退化为编号列表，仍 wait。

## 这一步在六步里是哪一步

六步的**最后一步「沉淀」**。需求的原型已经过复审、PM 已验收，这一步把成果固化下来：

1. **每个需求必做**——更新「产品现状」（PRODUCT-STATE）+ 把主原型合回主线。
2. **按需**——PM 真要拿去评审时，反向合成一份可评审 PRD（真系统口径）。

**防腐铁律**：「产品现状」**只在这一刻被写**。别处随手更新它必然漂成假现状——所以沉淀是它唯一的写入口。

## 什么时候用

- 由 `/pmai-next` 在需求走到「沉淀」这一步时驱动调用。
- 前提：该需求下所有 task 已收尾（看 demo 确认方向的单元都关掉了）。

## 两阶段调用（必读）

`/pmai-close-req` 设计为两阶段调用，AI 根据 cwd 自动判断当前阶段：

- **Phase 1**（cwd 在需求 worktree 内）：更新产品现状、按需合成 PRD、commit、登记待 finalize marker。
- **Phase 2**（cwd 在主仓，不在任何 worktree 内）：合回主线 → 删 worktree/branch → 清 marker。

PM 体感：
1. 在需求窗口运行 `/pmai-close-req` → AI 走 Phase 1 → 提示切到主仓窗口。
2. PM 切到主仓窗口。
3. 在主仓窗口运行 `/pmai-close-req` → AI 走 Phase 2 → 完全收尾。

> worktree 是后台机器，PM 不用关心它怎么建怎么删；这里出现「切窗口」只是因为合回主线要在主仓做。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: close-req"

# 视觉锚点 banner（见 _shared/pm-view/banner-rules.md §1）
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
| 需求 worktree 内 | 不存在 | **Phase 1**（正常沉淀 / commit 流程，结束时写 marker） |
| 需求 worktree 内 | 已存在 | **Phase 1 短路**（直接告知"已 ready，请切到主仓窗口"） |
| 主仓（== REPO_ROOT） | 存在 | **Phase 2**（合回主线 + 删 worktree + 清 marker） |
| 主仓（== REPO_ROOT） | 不存在 | **报错**："没有待 finalize 的需求。如要新启动 close-req，请进需求 worktree 调用" |

## Phase 1：在需求 worktree 内执行

### 步骤 1：更新「产品现状」（PRODUCT-STATE.md）—— 每个需求必做

这是沉淀的核心动作之一。本需求新建 / 改了哪些页面、哪个能力从 mock 转成真系统、主原型现在长什么样——都在这一刻 patch 进 `docs/PRODUCT-STATE.md`，让下一个需求的 AI 一进项目就知道产品当前的样子。

**输入源**（读这几处归纳本需求带来的现状变化）：

1. `req-plan.md` 的「范围清单」段 —— 本需求**建成了什么**（页面 / 区域 / 能力）。
2. `prototype/` 当前代码 —— 主原型现在实际有哪些页面 / 分区（>500 行禁整文件 Read，按 `input-flow.md` §9.3.1 强约束分段看）。
3. 本需求的实现深度决策 —— 哪一层从 mock 转成真系统（若有），在 `req-plan.md`「关键决策」里。

**patch PRODUCT-STATE.md 这几节**（只动本需求真正改了的行；模板见 `templates/PRODUCT-STATE.md.tmpl`）：

- **当前功能 / 能力** 表：本需求新增 / 升级的能力追加 / 更新行。
- **主原型现状** 表：新建 / 改动的页面、区域追加 / 更新。
- **实现深度状态** 表：本需求把哪层从 mock 转真，更新该行 + 记一笔何时转的。

AI 把 patch 草稿（diff 形态）呈交 PM 审；PM 满意 → 落盘。

> **为什么放这里、为什么只在这里写**：单人 PM 没有人帮 review，「维护一份活文档」的纪律会腐烂（旧仓主原型跑完整个项目只剩一个 README = 教训）。把更新绑死在沉淀这一个原子动作里，是防止现状档漂成假现状的唯一办法。

### 步骤 2：把本需求带来的稳定结构 / 模块规格沉淀进 docs（对账并入这一步）

本需求若新建 / 改了**稳定结构**（菜单 / 路由 / 权限 / schema / 跨功能产品规则），它现在只活在 `prototype/` 代码里——这一步把它沉淀成长期可读的规格，下一个需求才不会重复踩。

**怎么找该沉淀什么**（看本需求全部代码侧改动，自己判断）：

```bash
BASE=$(git merge-base main HEAD)   # 本需求起点
git diff --stat "$BASE" HEAD | grep -v '^docs/\|^requirements/\|^tests/'
git diff "$BASE" HEAD -- '*.ts' '*.tsx' '*.py' '*.go' '*.json' '*.yaml' '*.yml' | head -500
```

AI 看 diff，自答：本需求是否新建 / 改了**稳定结构**，但 `docs/` 里没有对应规格？

- 正面线索：路径 / 文件名含 `routes` / `router` / `navigation` / `menu` / `sidebar` / `permissions` / `schema` / `contract` / `api` / `config`；内容是**声明性数据**（数组 / 对象 / 枚举字面量）而非函数逻辑；影响产品的导航 / 权限 / URL 结构（用户看得见的）。
- 负面排除（不算）：单页业务逻辑、组件 refactor、测试、bug fix、内部工具脚本、纯样式。
- 跨功能的产品规则（不绑单个页面的规则，如「删最后一个管理员要拦」）→ 候选进 `docs/PRODUCT-RULES.md`。

**输出候选清单**，每条含：涉及文件 + 1-2 行 diff 证据 / 结构类型 / 建议沉淀目标（基于现有 `docs/modules/` 与 `docs/PRODUCT-RULES.md` 推断）/ 一行**自审反证**「这条不该沉淀的理由」（强制给否定理由，防过度推荐）。

**PM 决议**（每条候选用 AskUserQuestion picker，按 `askuser-rules.md §1.4` 多决策拆开顺序问）：

- `question`: "「<结构类型>」这条怎么处理？"
- `options`:
  - `label`: `沉淀进规格`
    `description`: `本需求顺便建 / 更新对应规格文件（docs/modules/<模块>.md 或 docs/PRODUCT-RULES.md）`
  - `label`: `不沉淀（追认代码即文档）`
    `description`: `close-report 记一行追认（防下个需求重复问）`
  - `label`: `推下个需求`
    `description`: `close-report「遗留问题」记一条点名（含建议目标 + 涉及文件）`

**零候选**：找不到候选 → 直接跳到步骤 3，不调 AskUserQuestion。

**沉淀 / 更新规格文件**：PM 选「沉淀进规格」的，AI 把对应规格写 / 更新到目标文件，呈交 PM 审 diff，满意后落盘。这一步把过去散在每个 task 的对账合并成沉淀时一次做完——少 N 次启动成本。

> **quickfix 历史改动天然包含在内**：`/pmai-quick-fix` 直接改 `docs/` 是旁路，但它的改动已在当前文件状态（git working tree）里，这一步以「当前文件全文」为基准沉淀，不需要额外收集。想审 quickfix 历史看 `git log --grep '\[quick-fix\]' -- docs/`。

**INDEX 刷新**：若本步骤新建 / 改了 `docs/modules/<模块>.md`，顺手刷 `docs/modules/INDEX.md`（新模块插行 / 已存在且本需求改过的更新简介），跑 lint 校验：

```bash
python3 "$PMAI_HOME/scripts/check-index-lint.py" "$REPO_ROOT" --exit-code || {
  echo "⚠️ INDEX lint 二次重写仍失败，跳过本次 INDEX 刷新"
}
```

lint 连续失败或 PM 两次 reject → 空 diff 跳过本次 INDEX 刷新（不阻塞 close-req 整体）。

**silent skip**：本需求纯非业务（如只动基础设施 / 工具脚本），无现状变化、无稳定结构候选、无规则变化 → 步骤 1 / 2 都可 silent skip，close-report 记「本需求无产品级文档变更」。

### 步骤 3：按需反向出可评审 PRD（PM 要拿去评审才做）

PRD 不是每个需求都硬产——琐碎需求硬产一份没人看的 PRD 就是文档税。**只在 PM 真要拿去评审时合成**，且可一次覆盖多个需求。

**先问 PM 要不要**（AskUserQuestion picker）：

- `question`: "本需求要不要现在反向合成一份可评审 PRD？"
- `options`:
  - `label`: `要，现在出`
    `description`: `调 /pmai-prd-writing standalone 反向合成（真系统口径，结构←原型+范围清单 / 规则←brief+决策页）`
  - `label`: `先不出`
    `description`: `沉淀只更新产品现状 + 合回主线；以后真要评审再单独 /pmai-prd-writing`

PM 选「要」→ **调 `/pmai-prd-writing` standalone** 合成。合成铁律（PRD 多源合成，不是把代码翻译成文档）：

- **结构 / 字段 / 交互** ← 最终 `prototype/` + `req-plan.md`「范围清单」。
- **业务规则 / 权限语义** ← brief + `req-plan.md`「关键决策」。**哪怕这版原型是 mock 壳，PRD 也按真实系统口径写，绝不从 mock 的随手实现反推规则。**
- 反向 PRD **不写任何元数据 / hash 回去**（避免自指问题）。

PM 选「先不出」→ 跳过，close-report 记「本需求未出评审 PRD（按需，以后单独 /pmai-prd-writing）」。

### 步骤 4：写 close-report.md（收尾记录）

在需求目录写 `close-report.md`，作为本需求的收尾记录：

```markdown
# 收尾记录：req-NNN-<slug>

## 需求概述
[从 req-plan.md「关键决策」+「范围清单」提炼。**不读 brief.md** —— brief 是范围确认前的初稿，到这一步已被原型 + 复审演化，用它写收尾记录会反映已被推翻的初衷。]

## 完成的 task
| Task | 摘要 |
|------|------|
| task-001-xxx | [从执行日志提取] |

<!-- 仅当有废弃 task 时输出本段 -->
<details>
<summary>已废弃 task（N 个）</summary>

| Task | 废弃理由 |
|------|----------|

</details>

## 产品现状变更
[步骤 1 / 2 实际改了 PRODUCT-STATE / docs 的哪些；无变更则写「本需求无产品级文档变更」。]

## 评审 PRD
[步骤 3：出了 → 路径；没出 → 「按需，以后单独 /pmai-prd-writing」。]

## 遗留问题
[步骤 2 PM 选「推下个需求」的稳定结构候选 + 其他后续建议。]
```

**生成规则**：
- 遍历 `tasks/*.md` 填「完成的 task」表（这里只剩已收尾态，因为沉淀前 task 都已关掉）。
- 遍历 `tasks/discarded/*.md` 填废弃栏；为空时整个 `<details>` 块省略。
- 已废弃 task 编号断号是合规信号，不要为「整理顺序」改号。

### 步骤 5：推进状态到「沉淀」

```bash
python3 "$PMAI_HOME/scripts/req-transition.py" "$ACTIVE_REQ_DIR" --to 4
```

### 步骤 6：业务词催补 —— 把本需求稳定下来的新词沉进 docs/PROJECT.md

需求收尾是业务实体真正落地稳定的时刻——把本需求引入的新业务词 / 角色 patch 进 `docs/PROJECT.md` 业务术语表 / 用户画像表，作为长期沉淀：

```bash
# 扫输入 = 本需求的 PM 视图主文件（req-plan + 所有收尾 task 主文件 .md）
TMPFILE=$(mktemp)
[ -f "$ACTIVE_REQ_DIR/req-plan.md" ] && cat "$ACTIVE_REQ_DIR/req-plan.md" > "$TMPFILE"
for t in "$ACTIVE_REQ_DIR"/tasks/closed/*.md; do
  [ -f "$t" ] && cat "$t" >> "$TMPFILE"
done

python3 "$PMAI_HOME/scripts/_lib/term-detector.py" \
  "$TMPFILE" "$REPO_ROOT" --req-dir "$ACTIVE_REQ_DIR"

rm "$TMPFILE"
```

按返回 JSON 处理（详见 `skills/_shared/term-detector/SKILL.md`）：≥3 新词走多词批量话术；<3 走单词；新角色独立话术；全空 silent skip。PM 拒绝某词 → 追加 `.term-skip.json`；PM 同意 → patch `docs/PROJECT.md` 业务术语表 / 用户画像表。

### 步骤 7：commit 所有改动

在需求 worktree 中 commit 所有未提交的改动：

```bash
git add -A
git commit -m "close: req-NNN-<slug>"
```

### 步骤 8：登记 finalize marker，提示 PM 切窗口

写 `$REPO_ROOT/.runs/pending-close-req.json`（marker 落在主仓的 `.runs/`，因为需求 worktree 会被 Phase 2 删掉）：

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

AI 向 PM 输出结束语，需求窗口工作到此结束：

```
✅ 产品现状已更新、收尾记录已 commit，已登记待 finalize marker。

▶ Next Up — 切到主仓窗口跑 /pmai-close-req：

如果主仓窗口还开着：直接切过去运行 `/pmai-close-req`
如果主仓窗口已关：
  cd <MAIN_REPO_ROOT>     ← 替换为主仓根绝对路径
  claude
  /pmai-close-req

AI 会自动走 Phase 2，把主原型合回主线并清理后台 worktree。
```

**Phase 1 短路场景**：进入 skill 时检测到 marker 已存在（之前调过一次但 PM 没切窗口），跳过步骤 1-7，直接输出上方结束语。不要重复写文档或重复 commit。

## Phase 2：在主仓内执行

### 步骤 P2.1：读 marker 并校验

```bash
if [ ! -f "$PENDING_MARKER" ]; then
  echo "❌ 没有待 finalize 的需求。"
  echo "   如要启动 close-req，请进需求 worktree 后调用 /pmai-close-req"
  exit 1
fi

REQ_DIR_ABS=$(python3 -c "import json; print(json.load(open('$PENDING_MARKER'))['req_dir_abs'])")
```

### 步骤 P2.2：调 close-req.sh

```bash
bash scripts/close-req.sh "$REQ_DIR_ABS"
```

脚本自动：
1. 二次校验 cwd 不在需求 worktree 内（防御性）。
2. 校验需求已到沉淀这一步 + 所有 task 已收尾。
3. 在需求分支把目录移到 `requirements/closed/` + 更新 meta + 建 `docs/prds/<req-name>.md` 收口 symlink（若本需求出过 PRD）+ commit。
4. 把主原型 / 需求分支合回主线（merge req 分支 → main）。
5. 直接删需求 worktree + 需求分支。

### 步骤 P2.3：清 marker

```bash
rm -f "$PENDING_MARKER"
```

### 步骤 P2.4：确认结果

```
✅ 需求已完全收尾：<req-id>，主原型已合回主线。
📍 当前位置：主仓 main 分支

▶ Next Up — /pmai-new-req "<下一个需求>"（开始下一个需求）
         或 /pmai-project-solution（重新审视项目方向 / 路线）
```

## Rules

- Phase 1 必须在需求 worktree 内执行；Phase 2 必须在主仓内执行。
- Phase 间通过 `$REPO_ROOT/.runs/pending-close-req.json` 衔接（marker 落主仓，因需求 worktree 会被 Phase 2 删）。
- Phase 1 进入时若 marker 已存在 → 短路（直接告知"已 ready，请切窗口"），不重复写文档。
- Phase 2 进入时若 marker 不存在 → 报错（避免误触）。
- **「产品现状」只在本 skill 沉淀这一刻写**（防腐铁律）；别处随手更新它必然漂成假现状。
- **PRD 按需出，不是每需求必出**；要出就走 `/pmai-prd-writing` standalone，真系统口径、多源合成。
- 合回主线后不可回退（沉淀是终态）。
- 需求目录移到 closed/ 后保留完整记录。
- close-req.sh 直接删 worktree + branch（无中转文件）。
