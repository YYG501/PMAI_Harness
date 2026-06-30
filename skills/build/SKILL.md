---
name: pmai-build
description: |
  大需求的构建入口：将 /pmai-design 定稿的模块规格，或 /pmai-spec-writing 产出的功能型规格文档，在主原型中实际构建。由 PM 选择构建工具与是否启用隔离环境；构建后经原型评审迭代修正，并执行覆盖、视觉、行为三项审查，确认后合并回主线。仅用于大需求，讨论与小改动直接进行、不经此流程。
---

# /pmai-build

> 这是改造后的 **大需求建造入口**。它不拆任务卡、不走独立任务状态机。它对着**功能锚点**建：模块规格 `docs/modules/<模块>/spec.md`，或功能型规格文档 `docs/modules/<按内容命名>.md`。建完 review loop + 三道审，再 merge 回 main。
>
> 本 skill 只依赖两类通用资产：**exec-adapter**（可插拔执行器）和 **build-audits.py**（三道审编排）。二者不绑定任务卡。

## When To Use

- **只用于大需求**。判据由 PM 在 `/pmai-design` 收尾时拍：要新建 / 大改一片功能、改动量大到值得隔离 → 走 `/pmai-build`。
- **不走这的**（在 main 上直接动，本 skill 不介入）：
  - **讨论** = 改文档（模块三件套 discussion / decisions / spec）→ `/pmai-design` 里做，无 worktree。
  - **小改** = 改一两个字段 / 文案 / 一个组件的小调整 → 直接改 prototype/，无 worktree。main 写保护已放宽，允许直接改文档 + 小代码。
- 上游：`/pmai-design` 把模块规格 `spec.md` 定稿（信息模型理清、mock 已确认），或 `/pmai-spec-writing` 写出功能型规格文档 → 交给 `/pmai-build` 建。
- 下游：建完 + PM 验收通过 → `/pmai-build-close` 收尾（决策 / 术语回写基线、文档归位、有 worktree 则 merge 回 main）。

## PM 视图规则（必读）

须遵守 `skills/_shared/PM-VIEW-RULES.md`（主索引）。本 skill 里 PM 面对的是 demo 和「要不要改」的拍板，不是工程过程，具体读：
- `_shared/pm-view/banner-rules.md`（§2 Next Up、§2.5 内容禁忌：不写 worktree / merge / dispatch / Phase N 等内部术语、§3 决策门 label 三硬规则）
- `_shared/pm-view/askuser-rules.md`（§1 四硬规则：空答 STOP / 没拿到答案禁止往下走 / runtime 退化保留 wait / 多决策拆开顺序问）

**红线**：PM 面前不出现 worktree / 分支 / exec-adapter / dispatch / 三道审脚本名这类工程黑话。「开不开隔离环境建」「用哪个工具建」可以问 PM（这是 PM 的选择），但措辞用大白话（见步骤 1 / 步骤 2）。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: build"

# 视觉锚点（见 _shared/pm-view/banner-rules.md §1）
python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill BUILD || true
```

preamble 会解析出 `PMAI_HOME` / `MAIN_REPO_ROOT` / `REPO_ROOT` / `BRANCH`。后续命令以这些运行时变量作为仓库根 / 工作区根锚点，**不写死某台机器的本地路径，也不依赖会话 cwd**：worktree 在 `.worktrees/` 下可能不在会话子树内，cwd 会被沙盒 reset。

## Workflow

### 步骤 0：定位功能锚点 + 确认是大需求

1. 接参数：`/pmai-build <模块名>`、`/pmai-build docs/modules/<文档名>.md` 或 `/pmai-build`（无参时让 PM 一句话说要建哪个模块 / 哪份功能型规格文档）。
2. 定位功能锚点：
   ```bash
   # 模块锚点
   MODULE_DIR="$REPO_ROOT/docs/modules/<模块>"
   BUILD_ANCHOR="$MODULE_DIR/spec.md"

   # 功能型规格文档锚点
   BUILD_ANCHOR="$REPO_ROOT/docs/modules/<按内容命名>.md"
   ```
   - 模块锚点下 `spec.md` 不存在 → 这个模块还没设计。提示 PM 先跑 `/pmai-design <模块>` 把规格定稿再来 `/pmai-build`。不在 build 里临时设计。
   - 功能型规格文档路径不存在 → 提示 PM 先用 `/pmai-spec-writing` 写清功能型规格文档，或重新给出正确路径。
   - `BUILD_ANCHOR` 在 → `@读` 它（功能范围 + 业务规则 + 字段口径 + 验收标准就是建造契约）。若锚点是模块 `spec.md`，再 `@读` 同模块 `decisions.md`；若锚点是功能型规格文档，则按其覆盖范围读取相关模块的 `spec.md` / `decisions.md` 和 `docs/modules/INDEX.md`。
3. **确认这是大需求**。如果看下来其实是小改（一两处字段 / 文案 / 局部调整），一句话提示 PM「这个改动不大，直接在 prototype/ 改掉就行、不用单开建造流程」，征得同意后**退出 /pmai-build**，按小改直接动 prototype/（main 上，无 worktree）。大需求才继续步骤 1。

> 为什么对着功能锚点：模块规格是长期真相源；功能型规格文档是 PM 明确要求的 PRD / 功能需求 / 功能规格成稿。build 的覆盖审计锚点必须和 PM 选定的建造依据一致。

### 步骤 0.5：构建前硬门：先保存建造依据，再问两道选择

`/pmai-build` 不是“读完 spec 就直接动手”的入口。进入任何实现改动前，必须先过两个硬门：

1. **建造依据可被后续环境读到**：模块 `spec.md` / `decisions.md` / 已确认 mock 或功能型规格文档不能只停在未跟踪 / 未提交状态。
2. **PM 已回答两道构建选择**：先答“要不要开隔离环境”，再答“用什么工具建”。

先跑一次真实状态：

```bash
git -C "$REPO_ROOT" status --short --untracked-files=all
```

如果 `BUILD_ANCHOR`、同模块 `decisions.md`、`mockups/` 看版或本次功能型规格文档还在未跟踪 / 未提交状态，说明刚才 `/pmai-design` 产出的建造依据还没保存成可复用起点。**未提交的规格 / mock / 文档不是跳过 PM 选择的理由**，更不能说“开隔离环境拿不到这些文件，所以我直接在 main 上实现”。

正确处理只有两种：

AskUserQuestion：
- `question`: "这次建造依据还没保存，先怎么处理？"
- `options`:
  - `label`: `保存本次建造依据（推荐）`
    `description`: `只保存本模块规格、决策和已确认看版；不碰无关改动`
  - `label`: `先停住`
    `description`: `暂不实现，保留当前讨论结果，等你确认后再 build`

**PM 答题处理**：
- 选 `保存本次建造依据` / 输 `1` → 只提交当前模块相关的 `docs/modules/<模块>/`、相关功能型规格文档、`mockups/` 看版 / manifest、必要索引；**不要**把无关未跟踪文件（如 `Guides/`、`Scripts/`、下载素材、临时文件）顺手带进提交。提交后继续步骤 1 / 步骤 2。
- 选 `先停住` / 输 `2` → STOP，不进入 build。
- runtime 不支持 AskUserQuestion → 输出编号列表并 wait。PM 没答前禁止继续。

**两道构建选择是硬门**：步骤 1 和步骤 2 必须按顺序问。没拿到“执行方式”和“执行器”两个答案之前，读文件 / 跑 `status` 可以，**禁止修改 `prototype/`、`Sources/` 或任何业务代码**，也禁止输出“我会直接在当前主仓实现”这类替 PM 拍板的话。

### 步骤 1：PM 选要不要开隔离环境建（worktree 可选）

大需求默认建议开隔离环境（worktree），但**由 PM 拍**——这是改造后的灵活点：讨论 / 小改本就不开，大需求 PM 可选直接在 main 上建（单人 PM、改动可控时）或开隔离。

prose 头部（大白话，不出现 worktree / 分支字样）：
```
准备建：<模块或文档名> —— <一句话这次要建什么>
功能锚点已确认（<BUILD_ANCHOR 相对路径>），可以开建。
```

AskUserQuestion：
- `question`: "这次改动要不要单独开一个隔离环境来建？"
- `options`:
  - `label`: `开隔离环境（推荐）`
    `description`: `改动和当前主线分开，建完确认了再合并；适合改动较大`
  - `label`: `直接在主线上建`
    `description`: `不隔离，边建边能看；适合改动可控、想快`

**PM 答题处理**：
- 选 `开隔离环境` / 输 `1` / 输 "隔离 / 开 / 推荐" → 进步骤 1A（拉 worktree），`BUILD_DIR` = worktree 路径。
- 选 `直接在主线上建` / 输 `2` / 输 "直接 / 不隔离 / 在主线" → 跳过 1A，`BUILD_DIR="$REPO_ROOT"`（main 上建）。main 写保护已放宽，prototype/ 与文档可直接写。
- PM 没答 / 空答 / runtime 没返回 → 按 `_shared/pm-view/askuser-rules.md` STOP。**禁止默认选“直接在主线上建”**。

#### 1A：拉 worktree（PM 选了隔离时）

worktree 统一挂 `.worktrees/<分支>/`（repo 根下单一挂载目录，框架本就这样）。分支名从模块名派生英文 kebab-case：

```bash
BUILD_BRANCH="build-<模块 slug>"        # 例 build-capability-match
BUILD_DIR="$MAIN_REPO_ROOT/.worktrees/$BUILD_BRANCH"

# 从 main 拉（带上 main 上已定稿的功能锚点 / PRODUCT.md / DESIGN.md）
git -C "$MAIN_REPO_ROOT" worktree add -b "$BUILD_BRANCH" "$BUILD_DIR" main
```

**cwd 护栏（硬规则）**：禁止 `cd "$BUILD_DIR"`（含 `cd … && cmd` 顺手写法）。在 worktree 内跑命令必须用三种安全形式之一：
| 形式 | 用法 | 场景 |
|---|---|---|
| `git -C "$BUILD_DIR" <cmd>` | `git -C "$BUILD_DIR" status` | 所有 git 命令 |
| `( cd "$BUILD_DIR/prototype" && <cmd> )` subshell | `( cd "$BUILD_DIR/prototype" && pnpm dev )` | 必须切 cwd 的非 git 命令（起 dev server、跑工具链） |
| 工具自带 `--cwd` / `--prefix` | 包管理器 / 脚本 | 脚本 |

理由：Bash 工具 cwd 在多次调用间持久，一旦 `cd` 进 worktree，PM 看 status 栏会被拖进隔离分支（违反 PM 视图契约）。subshell `(...)` 不污染主 shell。

> **PM 在 main 上建时（没开 worktree）**：`BUILD_DIR="$REPO_ROOT"`，命令直接在主仓跑，无 cwd 护栏问题。

### 步骤 2：PM 选用哪个独立工具建（执行器可选）

改造后的核心灵活点：**PM 选谁来建**。当前窗口里的 AI 只负责编排、检查和呈交；下面选择的是独立建造工具。`/pmai-build` 提供通用执行器入口（`scripts/exec-adapters/{claude-code,codex,cursor-agent,gemini,manual}.sh` + Claude Code host 可用时的独立 subagent 路径），执行器只负责按 prompt 改 `BUILD_DIR/prototype/`，不碰阶段状态。

AskUserQuestion：
- `question`: "用哪个独立工具来建？"
- `options`:
  - `label`: `独立 Claude Code（推荐）`
    `description`: `后台建，过程不刷屏；完成后我只汇报结果和预览入口`
  - `label`: `独立 Codex CLI`
    `description`: `另起一个 Codex CLI 进程建，不是当前对话自己改`
  - `label`: `独立 Cursor Agent`
    `description`: `用 cursor-agent 建`
  - `label`: `独立 Gemini CLI`
    `description`: `用 Gemini CLI 建`
  - `label`: `我手动建`
    `description`: `你建完后，我只帮你跑检查`

**PM 答题处理**（映射到 build executor 名）：
- `独立 Claude Code` / `Claude Code` / 输 `1` → `EXECUTOR=claude-code`
- `独立 Codex CLI` / `Codex` / 输 `2` → `EXECUTOR=codex`
- `独立 Cursor Agent` / `Cursor` / 输 `3` → `EXECUTOR=cursor-agent`
- `独立 Gemini CLI` / `Gemini` / 输 `4` → `EXECUTOR=gemini`
- `我手动建` / `我自己建` / 输 `5` → `EXECUTOR=manual`
- PM 没答 / 空答 / runtime 没返回 → 按 `_shared/pm-view/askuser-rules.md` STOP。**禁止把当前主控 AI 当默认执行器直接改代码**。

> **executor 来源**：本 skill **直接问 PM** 用什么工具建。settings.json 里若配了 `executor.default` 可作为 AskUserQuestion 的默认高亮项，但仍由 PM 当场拍。`executor_model` 留空走 settings 默认（不另外问 PM 模型，除非 PM 主动提）。

### 步骤 2.5：写入 build 合同（给 build-close 用）

拿到「要不要隔离环境」和「执行器」两个答案后，先把本次 build 的执行合同写进当前模块 `.work-meta.json`，再开始实现。`/pmai-build-close` 只按这份合同收尾，不再根据当前 cwd / 分支名字猜。

如果当前模块还没有 `.work-meta.json`，但 `MODULE_WORK_DIR` 和 `BUILD_ANCHOR` 已明确，`build-contract.py start` 会自动补最小状态记录并写入 build 合同。这是框架内部状态，不再向 PM 追加确认。只有功能型规格文档无法判断归属哪个模块时，才问 PM“这次 build 归到哪个模块？”。

```bash
MODULE_WORK_DIR="$BUILD_DIR/docs/modules/<模块>"
BUILD_MODE="<worktree|main>"   # PM 选隔离环境 => worktree；PM 选直接主线 => main
BASELINE_SHA=$(git -C "$BUILD_DIR" rev-parse HEAD)

python3 "$PMAI_HOME/scripts/build-contract.py" start "$MODULE_WORK_DIR" \
  --anchor "$BUILD_ANCHOR" \
  --mode "$BUILD_MODE" \
  --executor "$EXECUTOR" \
  --branch "${BUILD_BRANCH:-main}" \
  --worktree "$([ "$BUILD_MODE" = "worktree" ] && printf '%s' "$BUILD_DIR" || true)" \
  --baseline-sha "$BASELINE_SHA" \
  --audit-dir ".pm-workflow/audits/<模块>"

git -C "$BUILD_DIR" add "$MODULE_WORK_DIR/.work-meta.json"
git -C "$BUILD_DIR" commit -m "build(<模块>): record build contract"
```

合同最少包含：

```json
{
  "build": {
    "anchor": "docs/modules/<模块>/spec.md",
    "mode": "worktree | main",
    "executor": "claude-code | codex | cursor-agent | gemini | manual",
    "branch": "build-<模块> | main",
    "worktree": ".worktrees/build-<模块> | null",
    "baseline_sha": "<build 前 HEAD>",
    "audit_dir": ".pm-workflow/audits/<模块>",
    "audit_exception": null,
    "implementation_commit": null,
    "pm_accepted_at": null
  }
}
```

若 `MODULE_WORK_DIR` 或 `BUILD_ANCHOR` 无法确定，说明当前功能锚点不能绑定到明确模块：STOP，先回 `/pmai-design` 建模块三件套 / 工作状态，或由 PM 明确确认当前功能型规格文档归属哪个模块后再写合同。禁止临时靠当前分支名猜模块。

### 步骤 3：建之前先把 DESIGN.md 读进 context（硬规则）

动手写代码前，把项目 `DESIGN.md`（视觉规范单一来源 + 共享组件 inventory）读进 context。这是栈内 build 的硬规则——UI 漏读 DESIGN.md 是早期反复迭代踩坑的根因。用 `cat` 无条件 echo 到 transcript（比依赖 Read tool 自觉触发硬）：

```bash
DESIGN_MD="$BUILD_DIR/DESIGN.md"
if [ -f "$DESIGN_MD" ]; then
  echo "════════ DESIGN.md（视觉规范单一来源，build 必须遵循）════════"
  cat "$DESIGN_MD"
  echo "════════ END DESIGN.md ════════"
  if grep -qE "状态：兜底骨架|视觉基线段未建" "$DESIGN_MD"; then
    echo "⚠️  DESIGN.md 只有已有代码接入时的兜底骨架，视觉基线还没建。"
    echo "   先让 PM 选："
    echo "   1. 暂停 build，跑 gstack /design-consultation 或手填 DESIGN.md 视觉基线后再建。"
    echo "   2. 继续 build，但视觉门只能做低置信检查：只报明显 AI slop / 组件违和 / 可用性问题，不判定视觉一致性通过。"
  fi
else
  echo "ℹ️  $DESIGN_MD 不存在；建议 PM 跑 gstack /design-consultation 建项目级视觉规范。"
fi
```

如果命中 `状态：兜底骨架` / `视觉基线段未建`，**不要假装视觉标准已存在**。先把上面两种选择给 PM：补视觉基线再建，或继续但把视觉门标成低置信。PM 选继续时，执行器仍要按已有 inventory / 组件复用规则建；后续视觉门只能挑明显问题，不能输出“视觉一致性通过”这种强结论。

同时把 `BUILD_ANCHOR`（步骤 0 已读）作为功能契约：信息模型 / 业务规则 / 字段口径 / 状态机 / 验收标准 / 文案是「做什么」的硬约束；DESIGN.md 是「长什么样」的硬约束。先用 Glob 扫 `prototype/` 已有页面和组件，能复用就 import、不重写。

### 步骤 4：派执行器在 prototype/ 里建（含越界 + 零改动兜底）

按步骤 2 选定的 `EXECUTOR` 派发。所有路径锚 `BUILD_DIR`（worktree 或 main），改动落在 `BUILD_DIR/prototype/`。

**派发前提：working tree clean**（codex / cursor-agent 的 stop 是软停，已派发的 sandbox 子进程可能延迟落盘覆盖未 commit 的手改）：
```bash
DIRTY=$(git -C "$BUILD_DIR" status --porcelain 2>/dev/null)
[ -n "$DIRTY" ] && { echo "❌ 工作区有未提交改动，先提交或丢弃再建。"; git -C "$BUILD_DIR" status --short; exit 1; }
BASELINE_SHA=$(git -C "$BUILD_DIR" rev-parse HEAD)
```

若 dirty 来自刚生成的模块规格 / mock / 功能型规格文档，回到步骤 0.5 做设计上下文 checkpoint；不要绕过 dirty check，也不要改口成“所以直接在 main 上建”。

#### 4a：claude-code（默认）= 优先派独立 build subagent；不可用时走 CLI adapter

如果当前 host 支持 **Agent 工具**（典型是 Claude Code 主控），spawn 一个独立 Claude subagent 去 `BUILD_DIR` 里建（不在驱动自己的上下文 inline 建：保隔离 + 角色分离 + PM 窗口不被建码刷屏）。subagent prompt = `BUILD_ANCHOR` 全文 + DESIGN.md 约束 + 一段隔离纪律：

- 「你在 `$BUILD_DIR` 里建 <模块> 这一片：改动只落在 `$BUILD_DIR/prototype/` 下，代码和文档里不要写入机器绑定的本地路径；先 Glob 扫已有页面 / 组件，相似的先读源码复用其布局和组件，优先 import 不重写；遵循已有样式模式和目录约定；**禁止 git add / git commit**（commit 由我统一做）。」
- `executor_model` 非空时按它选 subagent 的 model（opus / sonnet / haiku）。

subagent 返回后回到本驱动跑 4c / 4d。

如果当前 runtime 没有 Claude subagent 工具（典型是 Codex 主控），不要假装已派 subagent；改走 `scripts/exec-adapters/claude-code.sh` 调本机 `claude -p` 非交互执行器。这样满足两种使用方式：
- PM 手动切到 Claude Code 后跑 `/pmai-build`：走原生 subagent 体验。
- PM 留在 Codex 窗口里选择 `Claude Code`：走 Claude Code CLI adapter，建完仍由当前驱动继续检查和呈交。

#### 4b：claude-code / codex / cursor-agent / gemini / manual = 走 build adapter

调用通用 build adapter（独立 CLI 进程；adapter 约定改动落 `BUILD_DIR` 且 unstaged，不自己 commit）。执行过程只写日志和状态文件；PM 窗口只报阶段摘要，不直播读文件、进程号、日志 tail、临时命令试错。

```bash
PROMPT_FILE=$(mktemp)
# prompt 用功能锚点当契约。直接把 BUILD_ANCHOR + DESIGN.md + 上面那段隔离纪律
# 拼成 prompt 写进 $PROMPT_FILE。

if [ "$EXECUTOR" = "manual" ]; then
  echo "请在 $BUILD_DIR/prototype/ 里按 <BUILD_ANCHOR 相对路径> 建，建完回来发 /pmai-build 继续（我跳过执行器、直接帮你跑检查）。"
  # PM 手动改完重新进 /pmai-build → 检测到 manual 选择，跳过派发，直接进 4c/4d 检查 + 步骤 5
  exit 0
fi

ADAPTER="$PMAI_HOME/scripts/exec-adapters/${EXECUTOR}.sh"
[ -x "$ADAPTER" ] || { echo "❌ 找不到 adapter：$ADAPTER"; exit 1; }
RUN_DIR="$MAIN_REPO_ROOT/.runs/pmai-build-${EXECUTOR}-$(date +%Y%m%d%H%M%S)"
LOG="$RUN_DIR/output.log"; mkdir -p "$RUN_DIR"

# adapter 入参用环境变量。build 自己负责 clean tree、越界检查和零改动检查；
# adapter 只负责把执行器跑起来。
MAIN_REPO_ROOT="$MAIN_REPO_ROOT" BUILD_DIR="$BUILD_DIR" MODULE_NAME="<模块>" PROMPT_FILE="$PROMPT_FILE" \
  EXECUTOR_STATUS_DIR="$RUN_DIR" EXECUTOR_TIMEOUT_SECONDS="${EXECUTOR_TIMEOUT_SECONDS:-900}" \
  bash "$ADAPTER" > "$LOG" 2>&1
EXIT_CODE=$?
```

> 如果当前 host 会因为长命令 timeout，改用后台方式运行上面这段，等待 `$RUN_DIR/exit` / `$RUN_DIR/status.json`。不要在 PM 窗口反复输出 `ps` / `tail` / `kill` 过程；最多一句“建造工具还在跑，我继续等结果”。

**执行器失败 / 超时处理**：
- **默认保留半成品**。禁止自动 `git restore .` / `git clean -fd` 清掉执行器已经落盘的可用改动。
- 先读 `$RUN_DIR/status.json`、`$LOG` 和 `git -C "$BUILD_DIR" status --short`，判断是否有 `prototype/` 改动。
- 给 PM 的话只汇报结果，不讲进程细节：
  ```
  建造工具没有正常完成，但已经留下了一部分原型改动。
  你可以选：
  1. 我接手补完并继续检查
  2. 换一个工具重跑
  3. 丢弃这次半成品重来
  ```
- 只有 PM 选 `丢弃这次半成品重来`，才允许清理执行器落盘改动；清理前再次用 `git -C "$BUILD_DIR" status --short` 确认范围。

#### 4c：越界写保护（轻量）

build 改动应集中在 `prototype/`。`docs/*` 改动**默认不属于 build 边界**（文档归位是 `/pmai-build-close` 的事）。扫一遍，越界就提示 PM：

```bash
( cd "$BUILD_DIR" && git status --porcelain | awk '{print $2}' ) | while read -r p; do
  case "$p" in docs/*) echo "⚠️ 越界：执行器改了 ${p}（build 只该动 prototype/，文档改动归 /pmai-build-close）。" ;; esac
done
```

> 本 skill 用「docs/* = 越界」这条简单规则即可——大需求建造改的就是 prototype/。命中越界给 PM 看，PM 决定回退还是放行（不静默吞）。

#### 4d：零改动检查

```bash
CHANGE_COUNT=$(git -C "$BUILD_DIR" status --porcelain | wc -l | tr -d ' ')
[ "$CHANGE_COUNT" -eq 0 ] && { echo "⚠️ 执行器退出但 prototype/ 无改动。可能 prompt 被误解为「只分析」——检查功能锚点是否给够了可建的结构。换工具或「我自己建」。"; exit 0; }
```

### 步骤 5：起 dev server（UI 类）

UI 类需求起 dev server 给后面 review loop + 视觉门 + 行为审复用（**只起一次，三道审复用同一个**，别各起各的）。

**① 先装依赖（worktree 复用 pnpm store，不重复下载）**：worktree 从 main 拉、没有 `node_modules`。用 **pnpm** 装——它把包存全局 store、`node_modules` 是到 store 的硬链接，多个 worktree 并行 build 共享同一份 store、不各下一遍（这就是"复用 build 组件"）：

```bash
( cd "$BUILD_DIR/prototype" && pnpm install )   # main 上建（BUILD_DIR=REPO_ROOT）若 node_modules 已在、可跳过
```

**② 按项目配置启动，不临场猜命令**：多个 worktree 同时 build 会抢 config.yml 同一个 dev 端口。从候选端口探测、占用就顺延下一个，把实际端口记下来给三道审复用。启动命令必须来自 `.pm-workflow/config.yml` 的 `dev_server.command`：

- 如果 command 里含 `{port}`，替换成选中的端口后执行。
- 如果 command 不含 `{port}`，按原 command 执行，不临时猜 `-- --hostname`、`--port`、`--host` 这类框架参数；需要动态端口的项目应把占位命令写进 config。
- `ready_check` 和 `startup_timeout` 同样从 config 读取。启动失败时只向 PM 汇报“服务没起来 + 日志路径 + 下一步”，不要把多轮命令试错刷到 PM 窗口。

```bash
# 从 config.yml dev_server.ports 候选里挑第一个没被占用的（候选解析见 build-audits.py _dev_ports）
PORT=""
for p in <config.yml dev_server.ports 候选>; do
  if ! lsof -iTCP:"$p" -sTCP:LISTEN -t >/dev/null 2>&1; then PORT="$p"; break; fi
done
[ -z "$PORT" ] && { echo "❌ 候选端口都被占用：先关掉别的 dev server，或在 config.yml 的 dev_server.ports 加端口。"; exit 1; }
DEV_CMD="<config.yml dev_server.command，替换 {port}>"
( cd "$BUILD_DIR/prototype" && eval "$DEV_CMD" )   # Bash run_in_background 后台跑；记下 $PORT 给视觉门 / 行为审复用
```

> **并行 build 心智**：worktree = 真实 build 的并行隔离（不同分支各挂一个 worktree、同时改、互不串）；① 复用 pnpm store 让 N 个 worktree 不各装一遍依赖、② 端口错开让 N 个 dev server 不抢端口。worktree 从 main 拉天然带定稿的功能锚点 / `PRODUCT-*` / `DESIGN.md`（决策文档读得到），无需另同步。

非 UI 类需求跳过。

### 步骤 6：建完三道审（覆盖 / 视觉 / 行为，复用 build-audits.py）

建完 AI **自动**跑三道机器审，走 `build-audits.py` 编排（确定性收集 + 合成一份给 PM；只报不改，是给 PM 看的证据，不替 PM 拍板）。

> **锚点已敲死**：覆盖审计锚点统一是步骤 0 选定的 **`BUILD_ANCHOR`**（模块 `spec.md` 或 `docs/modules/<按内容命名>.md`）。`build-audits.py` 已参数化锚点（`--range-list` / `--audit-dir` / `--label`）。统一接脚本，复用其 fail-loud「三道齐全」校验——覆盖审计是防残承重墙，不走纯 AI 自跑（避免静默漏一道审还往下走）：
> ```bash
> BUILD_ANCHOR="$BUILD_DIR/<docs/modules/... 实际锚点路径>"   # 模块 spec 或功能型规格文档
> python3 "$PMAI_HOME/scripts/build-audits.py" resolve "$BUILD_ANCHOR" \
>     --repo-root "$BUILD_DIR" --range-list "$BUILD_ANCHOR" \
>     --audit-dir ".pm-workflow/audits/<模块>" --label "<模块>"
> # …三道审各写 coverage.json / visual.json / behavior.json 进 $BUILD_DIR/.pm-workflow/audits/<模块>/…
> python3 "$PMAI_HOME/scripts/build-audits.py" synthesize "$BUILD_ANCHOR" \
>     --repo-root "$BUILD_DIR" --audit-dir ".pm-workflow/audits/<模块>" --label "<模块>"
> ```
>
> `coverage.json` / `visual.json` / `behavior.json` 是 `.pm-workflow/` 下的内部证据，不写进 `docs/`，也不作为消费仓主目录结构对 PM 展开；给 PM 看的是合成后的结论和待改项。
> `visual.json` 必须写 `status`：`pass` / `needs-review` / `limited` / `skipped`。`behavior.json` 必须写 `status`：`pass` / `fail` / `skipped` / `limited`。`limited` / `skipped` 不是通过；如果工具受限但 PM 明确接受风险，必须用 `build-contract.py audit-exception` 记录原因，否则 `/pmai-build-close` 会拒绝收尾。

三道审抓三种不同的病：

- **① 覆盖审计**（白纸新鲜视角，对标 `coverage-reviewer` agent）：拿**功能锚点 BUILD_ANCHOR** 对 `prototype/` 代码逐项 diff，报每条规格点：✅ 建了 / ❌ 丢了 / ⚠️ 降级占位（空壳 / 假数据 / 交互没接）。故意不让建代码的 AI 自审，避盲区。静态读码，不需 dev server，先跑。
- **② 视觉门**（gstack `/design-review`，只截图不改）：对照 `DESIGN.md` 审视觉一致性（间距 / 层级 / 配色 / AI slop）。用 `/browse`（headless），禁 `mcp__claude-in-chrome__*`。出口是 PM 一句话 pass / 打回，**AI 不替 PM 改视觉**。复用步骤 5 的 dev server。
- **③ 行为审**（验收流程驱动 `/browse` 走确定性路径）：从功能锚点的核心动作 / 状态机 / 验收标准派生验收流程，`/browse` 逐流程跑，验证「跑得通不通」（明确 pass/fail，区别于 `/qa` 的 AI 探索）。复用步骤 5 的 dev server。

视觉 / 浏览器工具受限时按三态呈交，不展开底层工具报错：
- `已完成视觉检查`：写 `visual.status=pass|needs-review`，给截图 / 关键观察 / 问题清单。
- `视觉检查受限但页面可访问`：写 `visual.status=limited`，说明已完成构建和页面返回检查，列出未覆盖的视觉风险。PM 若接受，记录 `audit-exception`。
- `视觉检查未完成`：写 `visual.status=skipped` 或停止，说明阻塞原因、日志路径和下一步选择。PM 若仍要收尾，必须记录 `audit-exception`。

### 步骤 7：review loop（看原型挑错、AI 改）

三道审合成一页给 PM + AI 把自己看出来的问题一起**主动批量 flag**，PM 勾哪些改（不是 AI 静默全改，也不是 PM 自己逐个找）：

```
建完自查（<模块>）：
覆盖：规格 N 项，建了 X / 占位 Y / 漏 Z
  ⚠️ 「<功能>」建了但点了没反应（占位）
  ❌ 「<功能>」没建
视觉：M 处和 DESIGN.md 不一致
  • <具体>
行为：验收流程 a/b 通过；失败：<哪条没通>

要不要我现在一起改？（你勾哪些，我改哪些）
```

- PM 勾的项 → AI 改 `BUILD_DIR/prototype/` 代码 → **重新跑步骤 6 三道审**（每轮改完重审，别只改不验）。
- review loop 只动 prototype/ 代码，**不动 spec.md / decisions.md**（文档对齐是 `/pmai-build-close` 的事；改造后讨论 / 定稿在 main 上由 /pmai-design 做，build 期不改模块文档）。
- 行为审 fail → 进本 loop 修代码，不往下走；连续磨不动（反复改不到位）→ 上抛，提示 PM 可能要回 `/pmai-design` 重收规格，别在 build 里死磕。
- **停止条件**：demo 达到 PM 心里的成功标准 + PM 在步骤 8 拍板。

### 步骤 8：commit + 呈交 PM 验收（唯一决策点）

review loop 收敛后 commit（worktree 或 main 都用 `git -C "$BUILD_DIR"`）：

```bash
git -C "$BUILD_DIR" add -A
git -C "$BUILD_DIR" commit -m "build(<模块>): <一句话做了什么>"
```

dev server 保持运行（PM 验收要访问）。呈交块 + AskUserQuestion（PM 全程唯一的拍板点）：

- `question`: "<模块> 这版可以吗？"
- `options`:
  - `label`: `可以，收尾`
    `description`: `进收尾：决策 / 术语回写基线，文档归位，合并回主线`
  - `label`: `还要改`
    `description`: `说哪里要改，我接着改`

**PM 答题处理**：
- 选 `可以，收尾` / 输 `1` / 输 "OK / 通过 / 可以" → 先确认三道审合成报告已生成；若视觉 / 浏览器审是 `limited` / `skipped`，先让 PM 明确接受这个缺口并记录原因，再把最新实现提交和 PM 验收写回 build 合同，最后进步骤 9（接 `/pmai-build-close`）：
  ```bash
  IMPLEMENTATION_COMMIT=$(git -C "$BUILD_DIR" rev-parse HEAD)
  # 仅当视觉 / 浏览器审受限或跳过，且 PM 明确接受风险时执行：
  python3 "$PMAI_HOME/scripts/build-contract.py" audit-exception "$MODULE_WORK_DIR" \
    --reason "<PM 接受的受限原因>"

  python3 "$PMAI_HOME/scripts/build-contract.py" complete "$MODULE_WORK_DIR" \
    --implementation-commit "$IMPLEMENTATION_COMMIT"
  ```
- 选 `还要改` / 输 `2` / 提具体反馈 → 回步骤 7 review loop 按反馈改 → 重审 → 追加 fix commit（`build(<模块>) fixup: <一句话>`）→ 重新呈交。

### 步骤 9：交接 /pmai-build-close 收尾（含 merge）

PM 拍 `可以，收尾` → build 的活到此为止，**merge 回 main + 文档归位 + 决策 / 术语回写基线 由 `/pmai-build-close` 做**（不在 build 里 merge：`/pmai-build-close` 是改造后的收尾原子动作，把决策 / 术语沉淀和 merge 焊在一起，绕不过）。

输出 Next Up（不写 worktree / merge / 分支字样，按 banner-rules §2.5）：

```
✅ <模块> 这版建好了，你确认通过。

▶ Next Up：发 /pmai-build-close 收尾这个模块 —— 把这次拍的决策和新术语沉淀进基线，文档归位<，改动合回主线>。
```

> 括号里「改动合回主线」仅在开了隔离环境（步骤 1 选了 worktree）时出现；PM 在 main 上直接建的，无 merge、`/pmai-build-close` 只做沉淀 + 文档归位。`/pmai-build-close` 按步骤 2.5 写入的 build 合同决定收尾方式。

## 与上下游的衔接（一句话）

| 环节 | 谁做 | 交给 build / build 交出去的 |
|---|---|---|
| 上游 `/pmai-design` / `/pmai-spec-writing` | 在 main 上理清信息模型、`/mock` 确认设计、产 / 演进模块规格 `spec.md`；或写功能型规格文档 | build 拿模块 `spec.md` 或 `docs/modules/<按内容命名>.md` 当建造契约（覆盖审计锚点）+ 相关 `decisions.md` 当背景 |
| 本 skill `/pmai-build` | 仅大需求：PM 选工具 + 选要不要 worktree → 派执行器在 prototype/ 建 → review loop + 三道审 → commit + 呈交 | 建好的 prototype/ 改动（worktree 或 main 上）+ PM 验收通过信号 |
| 下游 `/pmai-build-close` | 决策 / 术语回写基线、文档归位，按 build 合同决定是否 merge 回 main 并清理隔离环境 | 把 build 产物收口进基线 + 主线 |

## Rules

- **只大需求走 build**。讨论（改文档）/ 小改（一两处字段 / 文案 / 局部）不走这——在 main 上由 `/pmai-design` 或直接改 prototype/ 完成，无 worktree。步骤 0 判出是小改 → 退出 build。
- **对着功能锚点建**。覆盖审计锚点 = `docs/modules/<模块>/spec.md` 或 `docs/modules/<按内容命名>.md`。不拆任务卡、不走独立任务状态机。
- **PM 选独立建造工具**（claude-code / codex / cursor-agent / gemini / manual，复用 exec-adapter）**+ PM 选要不要 worktree**（步骤 1 / 步骤 2 两道 PM 决策）。executor 从问 PM 拿；当前主控 AI 只编排、检查和呈交，不把自己默认为执行器。
- **两道构建选择是硬门**：没拿到“要不要隔离环境”和“用什么工具建”两个 PM 答案前，只能读文件 / 查状态，不能改 `prototype/` / `Sources/` / 业务代码。runtime 不支持 AskUserQuestion 就编号列表 wait，禁止默认选择。
- **build 合同是 build-close 的唯一收尾依据**：两道 PM 选择拿到后立即写 `.work-meta.json:build` 并提交；缺 `.work-meta.json` 但模块和锚点明确时自动补最小状态，不再问 PM；PM 验收通过后写入 `implementation_commit` 与 `pm_accepted_at`。`/pmai-build-close` 不再靠当前 cwd、分支名或有没有 worktree 猜执行方式。
- **未提交上下文先保存，不准绕过**：未提交的规格 / mock / 文档不是跳过 PM 选择的理由；先只保存当前模块建造依据，或停住。禁止用“worktree 拿不到未跟踪文件”为理由自行决定直接在 main 上实现。
- **worktree 可选、统一挂 `.worktrees/<分支>/`**。开了就用 `git -C "$BUILD_DIR"` / subshell，禁 `cd` 进 worktree（cwd 护栏）；没开则 `BUILD_DIR="$REPO_ROOT"`、main 上直接建（main 写保护已放宽）。
- **claude-code = 优先派独立 build subagent**（Agent 工具），不在驱动上下文 inline 建（隔离 + 角色分离 + 不刷 PM 屏）；当前 runtime 没有 subagent 时走 `exec-adapters/claude-code.sh` 调 Claude Code CLI。codex / cursor-agent / gemini / manual 走现成 exec-adapter。一次只建本模块这一片。执行器运行过程写日志和状态文件，PM 窗口只报阶段摘要。
- **建之前必读 DESIGN.md**（cat echo 进 context）+ 功能锚点当契约；若 DESIGN.md 只有“兜底骨架 / 视觉基线段未建”，先让 PM 选择补视觉基线或继续低置信视觉门；先扫已有组件复用、不重写。
- **三道审 AI 自动跑、只报不改**（覆盖 / 视觉 / 行为，复用 build-audits.py 编排或等价自跑；三道审复用同一次 dev server）；出口都是给 PM 看的证据，不替 PM 拍板。探索式 review（`/review` `/qa` `/qa-only`）是 PM 手动旁路，AI 不自动调（守 I-RV1）。
- **`/pmai-meta` 不进默认 build 门**：如果 PM 在 build 前怀疑功能锚点本身不稳，可先旁路跑 `/pmai-meta` 做问题会诊；如果已有规格 / 方案且想多视角找盲区，由 `/pmai-meta` 走已有材料压测。build 流程本身仍只按功能锚点 + 三道审推进；功能锚点不稳时也可回 `/pmai-design` 重理。
- **review loop 只动 prototype/ 代码**，不改 spec.md / decisions.md（模块文档对齐归 `/pmai-build-close`；build 期不改文档）。AI 主动批量 flag、PM 勾改；每轮改完重跑三道审。
- **commit 用 `git -C "$BUILD_DIR"`**；执行器禁自己 commit（claude-code subagent prompt 里写死、adapter 约定 unstaged）。
- **PM 验收是唯一决策点**（步骤 8）；通过后**不在 build 里 merge**，交 `/pmai-build-close` 做提交 / 合并 + 沉淀（决策 / 术语回写基线绑定在 build-close，绕不过）。
- 越界（执行器改了 docs/*）/ 零改动 / 执行器失败都给 PM 看、不静默吞；执行器失败默认保留半成品，由 PM 选“接手补完 / 换工具重跑 / 丢弃重来”，禁止自动 `restore/clean` 清空已落盘改动。
- 路径定位用运行时变量（`BUILD_DIR` / `MAIN_REPO_ROOT` / `REPO_ROOT`）和仓内相对路径组合；框架、模板、prompt 和业务代码里禁止写死 `/Users/...` 这类机器绑定路径。
