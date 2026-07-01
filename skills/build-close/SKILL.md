---
name: pmai-build-close
description: |
  构建完成后的收尾入口：在 /pmai-build 做完且 PM 验收通过后，提交与合并实现改动，对齐模块决策和规格，更新产品现状、术语和跨模块规则，并归位产出文档。
---

# /pmai-build-close

> **这是什么**：`/pmai-build` 之后的收尾。实现已经做完、PM 已验收，才用它把最终结果收进主线和长期基线：提交 / 合并 / 清理隔离环境，对齐模块 `decisions.md` 与 `spec.md`，更新产品现状、术语和跨模块规则。
>
> **和 `/pmai-design` 的关系**：`/pmai-design` 开场**读**基线（`PRODUCT-RULES` + 相关模块 `decisions.md` + `PRODUCT.md` 业务术语表）；`/pmai-build-close` 收尾**写**这三处。一读一写，闭环。
>
> **PM 视图**：收尾用 PM 看得懂的话——「现状更新了 / 决策记下了 / 术语进表了 / 探的几版视觉留着了 / 改动并回主线了」。不出现"四类分流 / 派生 4 环 / 三身份 / supersede / 一致性扫描"等内部词。
>
> **执行纪律**：合同校验、字段补录、读文件、验证命令、tmux / 进程清理都属于内部动作。PM 窗口只报阶段结果和需要 PM 拍的产品问题，不直播命令流水、进程号、tail 日志或“我读了 N 个文件”。
>
> **混合交付唯一收口**：凡一次工作同时包含主原型改动和模块文档 / mockup 归位或退役，最终只能由 `/pmai-build-close` 收口。直接把 `prototype/`、`docs/modules/`、`mockups/` 混在一个普通提交里，是绕过 build/close。

## 什么时候用

- `/pmai-build` 已经把功能做进主原型，PM 明确验收通过。
- build 过程中出现了实现侧产品调整，需要把最终原型、模块决策和模块规格对齐。
- 有隔离环境时，把已验收改动合回主线并清理。
- 本次交付同时涉及 `prototype/` / `Sources/` 与 `docs/modules/` 或 `mockups/`，需要把实现、规格、决策和探索稿状态一起收口。
- 不适用：只完成了 `/pmai-design` 讨论但还没实现 → 要么 `/pmai-build`，要么先放着；若只是想先沉淀项目级术语 / 跨模块规则 / 当前设计状态，走 `/pmai-record`。

## 这一步干四件事

| | 干什么 | 落到哪 |
|---|---|---|
| **① 跨工作记忆回写** | build 后确认稳定的**决策**、造的**新术语**沉进基线 | 单模块决策 → 模块 `decisions.md`；跨模块**规则** → `PRODUCT-RULES.md`；跨文件**理路** → `docs/decisions/`（冻结）；新术语 → `PRODUCT.md` 业务术语表 |
| **② 规格定稿 / 就地升版** | 用最终原型和 PM 验收结果反向对齐规格真相源 | `docs/modules/<模块>/spec.md`（同文件夹就地演进：升版本号 + 变更日志 + 老条目 supersede） |
| **③ 老规格 vs 新原型对账** | 防 review 改原型时把规格信息悄悄删了 | 逐条 flag「确认删 / 还是漏实现」，PM 拍；不盲目重写 |
| **④ 文档自动归位 + 现状更新 + merge** | 产出落各自的家、根目录不留游离；现状档更新；有 worktree 则合回 main | `PRODUCT-STATE.md` / `docs/inputs/<类别>/` / `mockups/`；`.worktrees/<分支>/` → main |

> **四类分流是同一套**（@读 `skills/_shared/record-routing.md`）：① 耐久事实（现状/规则/稳定结构）② 理路 ③ 遗留 ④ 探索变体。本 skill 是它在「收尾」开火点的完整套用——决策 / 理路按 **3 个正交的家**分流（见下「v2 落点对齐」；2026-06-21 开放 5 拍板撤销原"3 减 2 折叠"）。

## v2 落点对齐（与旧 close-work 的关键差异，必读）

本 skill 是 `close-work` 在框架瘦身 v2（吸收 ExampleAgentProject 设计方法）下的演进。落点按 v2 文档体系走，**不照搬旧 close-work 的目录动作**：

- **不再移目录到 `closed/`**。v2 取消了 `requirements/active|closed/` 整棵树——文档全进 `docs/` 一棵树（模块三件套在 `docs/modules/<模块>/`，附件按类别在 `docs/inputs/<类别>/`，worktree 挂 `.worktrees/<分支>/`）。所以 `/pmai-build-close` **没有"整目录搬家"这一步**；它做的是"把散落的产出归到各自的家 + merge 分支"。
- **决策 / 理路 3 个正交的家**（2026-06-21 开放 5 拍板：撤销原"3 减 2 折叠"，理路单独冻结落点）：① 单模块决策 → 模块 `decisions.md`（活）；② 跨模块 / 全局**规则**（产品行为约束）→ 项目级 `PRODUCT-RULES.md`（活、scope）；③ 跨文件 / 项目级**理路**（护城河 / 机制咬合 / 演进故事）→ `docs/decisions/<日期>-<slug>.md`（**冻结**、写一次、不维护）。理路与规则维度正交——一份文件没法半冻半活、防腐铁律没法对半执行，**别混塞 PRODUCT-RULES 一份**。
  > 单一真相源对齐：理路落点 + 门槛 @读 `_shared/decision-record.md`（`docs/decisions/` 冻结档）、四类分流 @读 `_shared/record-routing.md`（已反转回 3 家）。本 skill 与二者口径已统一，**不再需要"以本 skill 为准"的例外**（原例外是折叠期 lifecycle 未对齐的产物，开放 5 拍板后消解）。
- **规格就地升版，不 per-版本开新文件夹**：重做一个模块 = 在同一 `docs/modules/<模块>/` 里演进 `spec.md`（版本号 + 变更日志 + 老条目 supersede 删除线 + git）；只有"模块身份本身变了"才另起 + 归档旧的（例外，PM 拍）。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: build-close"

# 视觉锚点 banner（见 _shared/pm-view/banner-rules.md）
python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill BUILD-CLOSE 2>/dev/null || true
```

> **PM 答题规则**：所有 AskUserQuestion 按 `_shared/pm-view/askuser-rules.md` §1 走（空答 STOP / 没拿到答案禁止 merge 到主线 / runtime 不支持 picker 时退化为编号列表仍 wait / 多决策拆开顺序问）。

## 入口判断：读取 build 合同（不再猜 worktree）

`/pmai-build-close` 兼容两种 build 形态：PM 在 `/pmai-build` 里选择直接在主线上建，或选择开隔离环境建。**形态只由当前模块 `.work-meta.json:build` 合同决定**，不再根据当前会话 cwd、当前分支名、或有没有碰巧存在的 worktree 来猜。

`/pmai-build` 必须已经写入：

```json
{
  "build": {
    "anchor": "docs/modules/<模块>/spec.md",
    "mode": "worktree | main",
    "executor": "codex | claude-code | cursor-agent | gemini | manual",
    "branch": "build-<模块> | main",
    "worktree": ".worktrees/build-<模块> | null",
    "baseline_sha": "<build 前 HEAD>",
    "audit_dir": ".pm-workflow/audits/<模块>",
    "audit_exception": {
      "accepted_at": "<视觉 / 浏览器审受限时，PM 明确接受的时间>",
      "reason": "<为什么允许带着受限审计收尾>"
    },
    "implementation_commit": "<PM 验收时 HEAD>",
    "pm_accepted_at": "<PM 验收时间>"
  }
}
```

先跑合同校验：

```bash
MODULE_WORK_DIR="<当前模块目录>"
python3 "$PMAI_HOME/scripts/build-contract.py" validate-close "$MODULE_WORK_DIR"
```

校验失败时 STOP：

- 缺 `build` 字段 → 不是一个可 close 的 build；先恢复/补全本次 build 上下文，不能直接沉淀成已完成。
- 缺 `implementation_commit` 或 `pm_accepted_at`：
  - 如果 PM 在当前对话已经明确说“通过 / 可以收尾 / close”，且当前 build worktree HEAD 就是已验收版本，用一次原子命令补齐合同：
    ```bash
    IMPLEMENTATION_COMMIT=$(git -C "$BUILD_DIR" rev-parse HEAD)
    python3 "$PMAI_HOME/scripts/build-contract.py" complete "$MODULE_WORK_DIR" \
      --implementation-commit "$IMPLEMENTATION_COMMIT"
    ```
    禁止并行跑 `commit` / `accept` 两条命令，避免字段互相覆盖。
  - 如果没有明确验收信号 → STOP，不能进入 build-close。
- 合同是 `mode=worktree` 但分支或 worktree 找不到 → 不退化成 main 直收，先恢复 worktree 或补合同。
- 合同是 `mode=main` 但当前不在 main/master → 停止，回主仓主线再收尾。
- 缺三道审证据（`coverage.json` / `visual.json` / `behavior.json` / `synthesis.md`）→ STOP，回 `/pmai-build` 补跑覆盖、视觉和行为审；不能只靠 PM 说“通过”跳过 browser / gstack 验收。
- 视觉门或行为审是 `limited` / `skipped` → 必须有 `audit_exception` 记录 PM 明确接受的原因；行为审 `fail` 一律 STOP。
- 缺 build contract 时，即使文件已经改完、PM 说“提交吧”，也不能把它包装成已完成 close；先回 `/pmai-build` 补齐合同、三道审和验收记录。

gstack / browser 证据按 `skills/_shared/gstack-integration.md` 处理：它们只是 evidence producer，`build-contract.py validate-close` 才是收口判断入口。

```bash
REPO_ROOT="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." && pwd)"
CURRENT_WT="$(git rev-parse --show-toplevel 2>/dev/null)"
CUR_BRANCH="$(git branch --show-current 2>/dev/null)"
```

| build 合同 | 会话 cwd | 走法 |
|---|---|---|
| `mode=main` | 主仓 main/master | 走步骤 1–5（回写 + 定稿 + 对账 + 归位），**无 merge 步**（本就在 main） |
| `mode=worktree` | **在主仓**（推荐：主仓会话用 `git -C` 远程操作 worktree） | 走步骤 1–5 + 步骤 6（commit + merge 回 main + 删 worktree）。**cwd 在主仓，删 worktree安全、不触 ENOENT** |
| `mode=worktree` | 在 `.worktrees/<分支>/` 内 | close-work.sh **友好提示切回主仓窗口**再跑（删 worktree 时进程不能站在里头，ENOENT，脚本内无法修复） |

> **为什么推荐主仓会话**：worktree = build 的并行隔离；操作它不必把会话切进去——主仓会话 `git -C "$BUILD_DIR"` 远程改 / `( cd … && cmd )` subshell 跑 dev，process cwd 始终在主仓，close 删 worktree 永远安全。build skill 的 cwd 护栏已强制这条。
> v2 放宽了 main 写保护（允许直接改文档 / 小代码），所以 build 可选择直接在 main 上做；这种情况下 `/pmai-build-close` 只做提交、沉淀和归位，不需要合回。

---

## 步骤 1：判定本次动了哪个模块 + 读基线（接 /pmai-design 的读侧）

先弄清这次工作落在**哪个模块**、它的三件套在哪：

```bash
# 本次工作起点（小改场景 BASE 可能就是上一个 commit；大需求是分支起点）
WORK_ROOT="${ACTIVE_WORK_DIR:-$REPO_ROOT}"
BASE=$(git -C "$WORK_ROOT" merge-base main HEAD 2>/dev/null || git -C "$WORK_ROOT" rev-parse HEAD~1)
git -C "$WORK_ROOT" diff --stat "$BASE" HEAD
```

- 改了 `docs/modules/<模块>/` 下的文件 → 本次涉及该模块。
- 改了 `prototype/` 代码 → 对应到它实现的模块（看 `.work-meta` 当前工作状态 / `discussion.md`）。
- 没有任何模块归属（纯基础设施 / 工具脚本）→ 多数步骤 silent skip，跳到步骤 4/5 归位。

**读基线对齐口径**（和 `/pmai-design` 开场读的是同三处，确保回写时用既有词、不和已定决策打架）：

- `PRODUCT.md` 业务术语表 —— 本次新词要不要并进去、有没有和既有词冲突。
- `PRODUCT-RULES.md` —— 本次跨模块决策是否已有同类规则（避免重复 / 矛盾）。
- 涉及模块的 `docs/modules/<模块>/decisions.md` —— 本次模块决策是不是 supersede 了旧的某条。

---

## 步骤 2：跨工作记忆回写（① 决策 + 术语 —— 本 skill 的核心新增）

这是 v2 补的真实缺口：**本次拍的决策、造的术语，要沉进下一次 `/pmai-design` 开场会读到的家**，不能只躺在本次的讨论/代码里随工作结束失忆。

### 2.1 决策回写 —— 分两个家

从本次工作的 `discussion.md` 收敛过程 + PM 在对话里拍过的板里，挑出**后续工作该知道的决策**。每条按"作用范围"分流：

| 决策的作用范围 | 落点 | 怎么写 |
|---|---|---|
| **只管本模块**（这张卡放什么字段 / 这个状态机怎么转 / 这个模块某行为定哪样） | 该模块 `docs/modules/<模块>/decisions.md` | 追加一条：**结论 + 为什么 + 否过什么**；若 supersede 了旧决策，老条目打**删除线**并标"被 <日期/本次> 取代"，不删除（留痕） |
| **跨模块 / 全局**（跨功能产品规则 / 几个机制怎么整体咬合 / 护城河论证 / 演进方向） | 规则 → `PRODUCT-RULES.md`（活）；理路 → `docs/decisions/`（冻结） | 跨功能**规则**按 `PRODUCT-RULES.md.tmpl` 的「规则清单」格式（标题 + 规则 + scope + 来源日期）写进 `PRODUCT-RULES`；跨文件**整体理路**（为什么这么拼：护城河 / 机制咬合 / 演进故事）→ `docs/decisions/<日期>-<slug>.md` **冻结档**（@读 `decision-record.md`）。**理路与规则维度正交、分家落、不混塞一份**（开放 5·已拍 B） |

**找候选 + PM 逐条拍**（@读 `_shared/record-routing.md` ②；理路门槛 @读 `_shared/decision-record.md` 判"有实质理路才记 / 纯微调不记"）。每条候选给：一句话决策 + 建议落点 + **一行自审反证**「这条不该回写的理由」（强制给否定理由，防过度推荐）。

> **减法 / 退役类决策走对抗三问**：若某候选是"砍掉某功能 / 退役某机制 / 合并某模块"性质的决策，自审反证**升级为对抗三问**（@读 `skills/_shared/anti-cut-check.md`）——三行自答附在该 `decisions` 条目下，别让减法在收尾这一刻无人把关。

逐条 AskUserQuestion picker（多条按 `askuser-rules.md §1.4` 拆开顺序问）：
- `question`: "「<一句话决策>」要不要记下来给后面用？"
- `options`:
  - `记进本模块`：写进 `docs/modules/<模块>/decisions.md`（后面做这个模块时 `/pmai-design` 会读到）
  - `记成跨模块规则`：写进 `PRODUCT-RULES.md`（产品行为约束、管整个产品、所有模块都受约束、活档）
  - `冻结成项目理路`：写进 `docs/decisions/<日期>-<slug>.md`（护城河 / 机制咬合 / 演进故事这类叙事性"为什么"，**冻结档**、写一次不维护；从 `docs/INDEX.md` 展开）
  - `不记`：本次没有要传给后面的决策（自审反证成立）

> **为什么补这处**：旧 close-work 沉淀只收"整体意图"，**单条决策会漏在已关需求里**、下一个工作的 `/pmai-design` 读不到 → PM 被迫重复说。本步把"决策回写"显式化、绑死在收尾这一刻。

### 2.2 术语回写 —— 进 PRODUCT.md 业务术语表

本次**新定义 / 改了口径的概念、角色、业务词**，回写 `PRODUCT.md` 业务术语表 / 用户画像表——下次 `/pmai-design` 讨论用既有词，不重新发明。

可借现成 term-detector 扫一遍候选（与旧 close-work 步骤 6 同机制；详见 `skills/_shared/term-detector/SKILL.md`）：

```bash
# 扫输入 = 本次工作主文件（模块 discussion/spec + 本次会话拍板）
TMPFILE=$(mktemp)
for f in "$REPO_ROOT"/docs/modules/<模块>/discussion.md "$REPO_ROOT"/docs/modules/<模块>/spec.md; do
  [ -f "$f" ] && cat "$f" >> "$TMPFILE"
done
python3 "$PMAI_HOME/scripts/_lib/term-detector.py" "$TMPFILE" "$REPO_ROOT"
rm -f "$TMPFILE"
```

按返回 JSON：≥3 新词走多词批量话术 / <3 单词 / 新角色独立话术 / 全空 silent skip。PM 拒某词 → 追 `.term-skip.json`；PM 同意 → patch `PRODUCT.md`。**纯文字微调不算新术语**（不污染术语表）。

---

## 步骤 3：规格定稿 / 就地升版（②）

把本次的设计结论固化成规格真相源 `docs/modules/<模块>/spec.md`。两种触发：

- **正向**（`/pmai-design` 讨论定了 + 用 mock 确认了设计）→ 把信息模型结论写成规格。
- **反向**（大需求 build 完）→ 以最终 `prototype/` + `discussion.md` 决策为据，反向把规格写到真系统口径定稿。**哪怕这版原型是 mock 壳，规格也按真实系统口径写，绝不从 mock 的随手实现反推规则。**

**就地升版规则**（v2：重做模块 = 同文件夹演进，不 per-版本开新文件夹）：

1. `spec.md` 顶部「版本信息」升号（如 v1.3 → v1.4）。
2. 「变更日志」追加一行：本次改了什么 + 日期。
3. 被取代的老条目打**删除线** + 标"被 v<新版> 取代"（supersede 留痕，不直接删——读者能看到演进）。
4. 顶部声明保持钉死："本规格是权威定义；与原型不一致以规格为准；没说清的先确认"（治规格 4 问之"分不清原型/规格"）。

**写规格纪律**（@读 `/pmai-spec-writing` 模块规格目标的写作纪律 / `_shared/pm-view/writing-rules.md`）：规格只留 normative 文字——"为什么"甩 `decisions.md` / `PRODUCT-RULES`，"原型长什么样"甩 `DESIGN.md` / mock，**规格里不嵌原型 ASCII**（设计确认靠 mock，不靠规格画图）。

> **`spec.md` 的生成和修改一律走 `/pmai-spec-writing` 模块规格目标**。设计拍板在 `/pmai-design`；`/pmai-build-close` 只提供最终原型、验收结论和收尾对账结果作为输入，调用 spec-writing 把已定结论写入/修订 `spec.md`。若发现规格还有没理清的信息结构 → 不在 `/pmai-build-close` 硬写，回 `/pmai-design` 补。

---

## 步骤 4：老规格 vs 新原型对账（③ —— 治"review 删规格"）

**@读 `skills/_shared/consistency-scan.md`**。这是规格 4 问之第 4 问的关键收口：用最终原型回头校准规格时，不能把"原型没体现的规格条款"自动当噪声删掉。按共享方法做轻量对账，**不盲目重写、每条对不上都 flag 让 PM 拍**：

```bash
# 索引漂移：docs/ 顶层野文档没挂进 docs/INDEX.md（advisory，不阻塞）
python3 "$PMAI_HOME/scripts/check-state-index-drift.py" "$REPO_ROOT" || true
```

**对账动作**：按 `consistency-scan.md` 的三步走，把本次改动涉及的字段 / 规则 / 概念，在 `spec.md`、`prototype/`、`DESIGN.md`、`PRODUCT.md` 术语表之间互查。只输出三类 PM 可拍的问题：哪个口径算数、有意删还是漏实现、术语是否统一。PM 逐条拍后，再把规格修订输入交给 `/pmai-spec-writing` 模块规格目标更新 `spec.md` / 记 TODO（漏实现 → 推下个工作）/ 更新术语表。

> 这是 **silent 自检 + 并入收尾呈交**的轻行为，**不升格成强制门**（守红线 I-RV1：不升格 AI 自动 review）。脚本 advisory（`|| true`），最终判断在 PM。

---

## 步骤 5：文档自动归位 + 现状更新（④ + ① 现状）

治 §0.1 痛点"产出散在根目录"。每份产出有钉死的家，AI **自动归位**，根目录不留游离文档。

### 5.1 现状档更新（PRODUCT-STATE，唯一现状写入点）

本次新建/改了哪些页面、哪个能力从 mock 转真、主原型现在长什么样——patch 进 `PRODUCT-STATE.md`（@读 `record-routing.md` ①；防腐铁律：PRODUCT-STATE 只在沉淀这刻被写）。AI 出 diff 草稿，PM 审，落盘。

### 5.2 产出归位（根目录不留游离）

| 这次产出了什么 | 归到哪 |
|---|---|
| 模块讨论/决策/规格 | `docs/modules/<模块>/`（discussion.md / decisions.md / spec.md，已在步骤 2/3 落） |
| PM 上传的附件 / 素材（访谈 / 竞品 / 脑暴 / 产品原文…） | `docs/inputs/<类别>/`（按类型自动归类；保留敏感路径预检 + 大小上限，并在当前模块记录引用） |
| 探索期的 mock 变体 | `mockups/`（manifest.json 真相源 + 看版） |
| 根目录散落的临时 md / 半成品 | 归 `docs/archive/` 或并进对应模块文件夹；**根目录不留游离** |

### 5.3 探索变体退役（④）

本次若把某 mock 变体并进了主原型 → 在 `mockups/manifest.json` 把该条 `status` 改 `已退役` + 填 `retired_note`「已并入主原型（位置/commit）」，跑 `gen-mock-board.py` 重生成看版（**留不删**）。

```bash
# mockups/ 是 main 级 store：若本次在 worktree 内，标退役放到步骤 6 merge 回 main 后做（worktree 内改会和 main 分叉）
python3 "$PMAI_HOME/scripts/gen-mock-board.py" "$REPO_ROOT"
```

只改**本次 build 明确使用 / PM 确认吸收**的那一个变体条目；不要为了退役一个 mock 顺手重写整份历史看版描述。如果无法确定是哪条变体，宁可在模块规格附件里说明“主原型为已验收口径，mock 为讨论留痕”，不要猜着改 manifest。

### 5.4 顺手补索引

- 本次新建了 `docs/modules/<新模块>/` 或 `docs/modules/<按内容命名>.md` → 刷 `docs/modules/INDEX.md`；如新增顶层文档类别，补 `docs/INDEX.md`。`check-index-lint.py` 校验失败两次则空 diff 跳过、不阻塞。
- 不写 `status=closed` / `已收口` 到 `.work-meta.json`。当前模型里 `.work-meta.json` 只表示“正在做”；真正收尾由 `close-work.sh` 在最后删除该文件。若还没合回主线或验收缺口未解决，就保持 active，不伪装成完成时间线。
- 正式 close 提交混合交付时，内部可用 `PMAI_ALLOW_MIXED_DELIVERY=build-close` 放行 pre-commit 的混合提交守卫；这个放行口只能在合同校验和三道审通过后使用，不能用于普通手工提交。

> **silent skip**：纯非业务工作（只动工具脚本 / 基础设施）→ 步骤 2–5 可整体 silent skip，回执记「本次无产品级文档变更」。

---

## 步骤 6：有 worktree 则 commit + merge 回 main（仅大需求）

**只在 build 合同是 `mode=worktree` 时走本步**；`mode=main` 无 merge 步。推荐在**主仓会话**跑——`git -C "$BUILD_DIR"` 远程 commit + merge + 删 worktree，cwd 始终在主仓、删 worktree 不触 ENOENT。

主仓 main 上允许保留其它未提交 WIP。它们不是 build-close 的处理对象，不能被提交、清理或拿来要求 PM 先处理。`close-work.sh` 合并时使用 Git autostash 临时挪开 tracked WIP，合并后放回；若真的会覆盖同一路径，Git 会失败，脚本回滚 build 分支的清状态提交并停止。

```bash
# 1) commit worktree 里所有改动（主仓会话用 git -C 远程操作，不必把会话切进 worktree）
git -C "$BUILD_DIR" add -A
git -C "$BUILD_DIR" commit -m "build-close: <模块>-<一句话本次成果>"
```

merge 回 main（具体的 merge / 删 worktree / 删分支编排由 lifecycle 脚本承接——见文末接口；本 skill 只描述目标行为）：

- 把 `.worktrees/<分支>/` 的改动 merge 回 `main`（合回主线后不可回退，收尾是终态）。
- 删该 worktree + 分支（无中转文件）。
- merge 回 main 后，若步骤 5.3 有待退役的 mock 变体 → 此刻（cwd 在 main）补标 `已退役` + 重生成看版。
- 如果 main 上已有无关脏改，回执里只说“仍保留你原有的未提交改动”，不要把它当成 close 风险反复展开。只有路径冲突 / Git 拒绝合并时，才提示 PM 先保存或移开冲突文件。

### 6.1 验证失败处理

合并前后按项目配置跑必要验证。验证失败先判定是**代码失败**还是**运行环境失败**：

- 代码失败 → 停止，不 merge / 不清理 worktree，先修到通过。
- 运行环境失败（例如 sandbox 禁止子进程 / 端口绑定 / 浏览器权限）→ 用同一条命令在允许的环境重跑；PM 窗口只报“验证环境受限，已用同一命令重跑”，不要展开底层报错流水。

> **AskUser 硬约束**：merge 前若任何 PM 决策门没拿到答案（空答 / runtime 退化未 wait）→ **STOP，禁止 merge 到主线**（`askuser-rules.md §1`）。

---

## 步骤 7：回执（PM 视图语言）

给 PM 一行收尾回执，只用 PM 看得懂的话（@读 `record-routing.md` §PM 话术纪律，禁内部词）：

```
✅ 已收尾：<模块> 规格定到 v<X>{；这次拍的几条决策记下了/术语进表了}{；和原型对了一遍，<N> 处待你定的已处理}{；探的 <M> 版视觉留在看版了}{；改动并回主线了（<short-hash>）}。

▶ Next Up:
  /pmai-design "<下一个要做的模块/需求>"   — 起下一段工作（开场会自动带上刚记下的决策和术语）
  /status                              — 看现在做到哪
```

---

## Rules

- **build 合同优先**：`/pmai-build-close` 必须先读 `.work-meta.json:build`；执行方式、执行器、分支/worktree、实现提交和 PM 验收都以合同为准。没有合同或合同不完整时 STOP，先补 build 上下文，不做“沉淀但未落地”的假 close。
- **混合交付唯一收口**：凡 staged / 本轮改动同时包含 `prototype/` 或 `Sources/`，以及 `docs/modules/` 或 `mockups/`，必须由 `/pmai-build-close` 在合同、三道审和 PM 验收齐全后放行；没有 build contract 就停止，不能把“已经改完了”伪装成 close。
- **合同补录必须原子化**：PM 已明确验收但合同缺实现提交 / 验收时间时，只能用 `build-contract.py complete` 一次写齐；禁止并行或交错跑 `commit` / `accept` 两步，避免字段互相覆盖。
- **不靠分支形态猜收尾**：当前在非 main 分支、普通 `codex/*` 分支、或 worktree 丢失，都不是新的 PM 分流菜单；只说明合同与现场不一致，停止并给出恢复上下文的最短动作。
- **未落主线不写完成态**：还没按合同合回主线，或三道审 / 验证 / 验收缺口没有明确记录前，不得输出“已收口 / 时间线已完成”。若选择 PR/保留分支，那是待合回状态，不是 build-close 完成。
- **三道审证据是 close 硬门**：`build-contract.py validate-close` 必须看到覆盖、视觉、行为三份结果和合成报告。browser / gstack 没跑就是缺证据；工具受限只能记录为 `limited` / `skipped`，并经 PM 明确接受后继续，不能静默当通过。
- **gstack 不是收口权威**：`/design-review`、`/browse` 可以产视觉 / 行为证据，但是否能 close 只看 PMAI build contract 和 PM 验收记录。
- **形态自适应**：`/pmai-build` 可以直接在 main 上建，也可以开隔离环境建；`/pmai-build-close` 只在 build 经 PM 验收后使用，并根据 build 合同 `mode` 决定是否合并。只完成讨论但暂不实现时，不需要 build-close。
- **决策 / 理路 3 个正交的家**（开放 5 拍板，撤销原 3→2 折叠）：单模块决策 → 模块 `decisions.md`（活）；跨模块**规则** → `PRODUCT-RULES.md`（活、scope）；跨文件**理路** → `docs/decisions/<日期>-<slug>.md`（**冻结**）。理路与规则分家、不混塞一份。
- **术语回写**：新定义的概念/角色/业务词 → `PRODUCT.md` 业务术语表；纯文字微调不算。
- **规格就地升版**：重做模块 = 同 `docs/modules/<模块>/` 演进 `spec.md`（版本号 + 变更日志 + 老条目 supersede 留痕）；身份变了才另起 + 归档旧的（例外，PM 拍）。规格只留 normative、不嵌原型 ASCII、顶部钉"规格为权威"。
- **老规格 vs 新原型对账**：每条对不上的都 flag「确认删 / 还是漏实现」让 PM 拍，不盲目重写——根除"规格被 review 悄悄删"。脚本 advisory（`|| true`），**不升格强制门**（I-RV1）。
- **`PRODUCT-STATE.md` 只在沉淀这刻写**（防腐铁律）：`/pmai-build-close`（build 验收后）+ `/pmai-record`（轻量记录）是仅有的 sanctioned 写入口，收敛点触发的原子写。
- **不再移目录到 `closed/`**：v2 取消 `requirements/active|closed/` 树；`/pmai-build-close` 没有"整目录搬家"步，只做归位 + merge。
- **四类分流 @读 `_shared/record-routing.md`**（单一真相源，已反转回 3 家）；理路门槛 + 冻结落点 @读 `_shared/decision-record.md`（`docs/decisions/` 冻结档）。三者口径已统一，无"以本 skill 为准"例外。
- **merge 终态**：合回主线后不可回退；merge 前任何 PM 决策门没拿到答案 → STOP，禁止 merge。
- **不因 main 无关 WIP 阻塞**：消费仓 main 上允许有其它未提交改动；close 不能提交、清理或要求先处理这些无关 WIP。只有 Git 判定会覆盖同一路径或发生真实冲突时才停止。
- **PM 话术纪律**（F-G4）：回执/提议只用 PM 视图语言，不出现"四类分流 / 出口①②③④ / 派生 4 环 / 三身份 / supersede / 一致性扫描 / manifest / featured"等内部词。
- **不删代码**：瘦身 = 缩小活跃集；本 skill 是 close-work 的活跃演进，`close-work` 转 dormant 保留不删。
```
