---
name: pmai-build
description: |
  大需求的构建入口：将 /pmai-design 定稿的模块规格，或 /pmai-prd-writing 产出的功能型文档，在主原型中实际构建。由 PM 选择构建工具与是否启用隔离环境；构建后经原型评审迭代修正，并执行覆盖、视觉、行为三项审查，确认后合并回主线。仅用于大需求，讨论与小改动直接进行、不经此流程。
---

# /pmai-build

> 这是改造后的 **大需求建造入口**。它不拆任务卡、不走独立任务状态机。它对着**功能锚点**建：模块规格 `docs/modules/<模块>/spec.md`，或功能型文档 `docs/modules/<按内容命名>.md`。建完 review loop + 三道审，再 merge 回 main。
>
> 本 skill 只依赖两类通用资产：**exec-adapter**（可插拔执行器）和 **build-audits.py**（三道审编排）。二者不绑定任务卡。

## When To Use

- **只用于大需求**。判据由 PM 在 `/pmai-design` 收尾时拍：要新建 / 大改一片功能、改动量大到值得隔离 → 走 `/pmai-build`。
- **不走这的**（在 main 上直接动，本 skill 不介入）：
  - **讨论** = 改文档（模块三件套 discussion / decisions / spec）→ `/pmai-design` 里做，无 worktree。
  - **小改** = 改一两个字段 / 文案 / 一个组件的小调整 → 直接改 prototype/，无 worktree。main 写保护已放宽，允许直接改文档 + 小代码。
- 上游：`/pmai-design` 把模块规格 `spec.md` 定稿（信息模型理清、mock 已确认），或 `/pmai-prd-writing` 写出功能型文档 → 交给 `/pmai-build` 建。
- 下游：建完 + PM 验收通过 → `/pmai-close` 收尾（决策 / 术语回写基线、文档归位、有 worktree 则 merge 回 main）。

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

preamble 会解析出 `PMAI_HOME` / `MAIN_REPO_ROOT` / `REPO_ROOT` / `BRANCH`。后续命令都用这些绝对路径锚点，**不依赖会话 cwd**：worktree 在 `.worktrees/` 下可能不在会话子树内，cwd 会被沙盒 reset。

## Workflow

### 步骤 0：定位功能锚点 + 确认是大需求

1. 接参数：`/pmai-build <模块名>`、`/pmai-build docs/modules/<文档名>.md` 或 `/pmai-build`（无参时让 PM 一句话说要建哪个模块 / 哪份功能型文档）。
2. 定位功能锚点：
   ```bash
   # 模块模式
   MODULE_DIR="$REPO_ROOT/docs/modules/<模块>"
   BUILD_ANCHOR="$MODULE_DIR/spec.md"

   # 功能型文档模式
   BUILD_ANCHOR="$REPO_ROOT/docs/modules/<按内容命名>.md"
   ```
   - 模块模式下 `spec.md` 不存在 → 这个模块还没设计。提示 PM 先跑 `/pmai-design <模块>` 把规格定稿再来 `/pmai-build`。不在 build 里临时设计。
   - 功能型文档路径不存在 → 提示 PM 先用 `/pmai-prd-writing` 写清功能型文档，或重新给出正确路径。
   - `BUILD_ANCHOR` 在 → `@读` 它（功能范围 + 业务规则 + 字段口径 + 验收标准就是建造契约）。若锚点是模块 `spec.md`，再 `@读` 同模块 `decisions.md`；若锚点是功能型文档，则按其覆盖范围读取相关模块的 `spec.md` / `decisions.md` 和 `docs/modules/INDEX.md`。
3. **确认这是大需求**。如果看下来其实是小改（一两处字段 / 文案 / 局部调整），一句话提示 PM「这个改动不大，直接在 prototype/ 改掉就行、不用单开建造流程」，征得同意后**退出 /pmai-build**，按小改直接动 prototype/（main 上，无 worktree）。大需求才继续步骤 1。

> 为什么对着功能锚点：模块规格是长期真相源；功能型文档是 PM 明确要求的 PRD / 功能需求 / 功能规格成稿。build 的覆盖审计锚点必须和 PM 选定的建造依据一致。

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

### 步骤 2：PM 选用什么工具建（执行器可选）

改造后的核心灵活点：**PM 选谁来建**。`/pmai-build` 提供通用执行器入口（`scripts/exec-adapters/{claude-code,codex,cursor-agent,gemini,manual}.sh` + Claude Code host 可用时的独立 subagent 路径），执行器只负责按 prompt 改 `BUILD_DIR/prototype/`，不碰阶段状态。

AskUserQuestion：
- `question`: "用什么来建？"
- `options`:
  - `label`: `Claude Code（默认）`
    `description`: `我直接派一个独立的 Claude 去建，过程不刷你的屏`
  - `label`: `Codex`
    `description`: `用 OpenAI Codex CLI 建`
  - `label`: `Cursor`
    `description`: `用 cursor-agent 建`
  - `label`: `Gemini`
    `description`: `用 Gemini CLI 建`
  - `label`: `我自己建`
    `description`: `你手动改，我只在建完帮你跑检查`

**PM 答题处理**（映射到 build executor 名）：
- `Claude Code` / 输 `1` → `EXECUTOR=claude-code`
- `Codex` / 输 `2` → `EXECUTOR=codex`
- `Cursor` / 输 `3` → `EXECUTOR=cursor-agent`
- `Gemini` / 输 `4` → `EXECUTOR=gemini`
- `我自己建` / 输 `5` → `EXECUTOR=manual`

> **executor 来源**：本 skill **直接问 PM** 用什么工具建。settings.json 里若配了 `executor.default` 可作为 AskUserQuestion 的默认高亮项，但仍由 PM 当场拍。`executor_model` 留空走 settings 默认（不另外问 PM 模型，除非 PM 主动提）。

### 步骤 3：建之前先把 DESIGN.md 读进 context（硬规则）

动手写代码前，把项目 `docs/DESIGN.md`（视觉规范单一来源 + 共享组件 inventory）读进 context。这是栈内 build 的硬规则——UI 漏读 DESIGN.md 是早期反复迭代踩坑的根因。用 `cat` 无条件 echo 到 transcript（比依赖 Read tool 自觉触发硬）：

```bash
DESIGN_MD="$BUILD_DIR/docs/DESIGN.md"
if [ -f "$DESIGN_MD" ]; then
  echo "════════ docs/DESIGN.md（视觉规范单一来源，build 必须遵循）════════"
  cat "$DESIGN_MD"
  echo "════════ END docs/DESIGN.md ════════"
else
  echo "ℹ️  $DESIGN_MD 不存在；建议 PM 跑 gstack /design-consultation 建项目级视觉规范。"
fi
```

同时把 `BUILD_ANCHOR`（步骤 0 已读）作为功能契约：信息模型 / 业务规则 / 字段口径 / 状态机 / 验收标准 / 文案是「做什么」的硬约束；DESIGN.md 是「长什么样」的硬约束。先用 Glob 扫 `prototype/` 已有页面和组件，能复用就 import、不重写。

### 步骤 4：派执行器在 prototype/ 里建（含越界 + 零改动兜底）

按步骤 2 选定的 `EXECUTOR` 派发。所有路径锚 `BUILD_DIR`（worktree 或 main），改动落在 `BUILD_DIR/prototype/`。

**派发前提：working tree clean**（codex / cursor-agent 的 stop 是软停，已派发的 sandbox 子进程可能延迟落盘覆盖未 commit 的手改）：
```bash
DIRTY=$(git -C "$BUILD_DIR" status --porcelain 2>/dev/null)
[ -n "$DIRTY" ] && { echo "❌ 工作区有未提交改动，先提交或丢弃再建。"; git -C "$BUILD_DIR" status --short; exit 1; }
BASELINE_SHA=$(git -C "$BUILD_DIR" rev-parse HEAD)
```

#### 4a：claude-code（默认）= 优先派独立 build subagent；不可用时走 CLI adapter

如果当前 host 支持 **Agent 工具**（典型是 Claude Code 主控），spawn 一个独立 Claude subagent 去 `BUILD_DIR` 里建（不在驱动自己的上下文 inline 建：保隔离 + 角色分离 + PM 窗口不被建码刷屏）。subagent prompt = `BUILD_ANCHOR` 全文 + DESIGN.md 约束 + 一段隔离纪律：

- 「你在 `$BUILD_DIR` 里建 <模块> 这一片：所有文件用**绝对路径**写到 `$BUILD_DIR/prototype/...`；先 Glob 扫已有页面 / 组件，相似的先读源码复用其布局和组件，优先 import 不重写；遵循已有样式模式和目录约定；**禁止 git add / git commit**（commit 由我统一做）。」
- `executor_model` 非空时按它选 subagent 的 model（opus / sonnet / haiku）。

subagent 返回后回到本驱动跑 4c / 4d。

如果当前 runtime 没有 Claude subagent 工具（典型是 Codex 主控），不要假装已派 subagent；改走 `scripts/exec-adapters/claude-code.sh` 调本机 `claude -p` 非交互执行器。这样满足两种使用方式：
- PM 手动切到 Claude Code 后跑 `/pmai-build`：走原生 subagent 体验。
- PM 留在 Codex 窗口里选择 `Claude Code`：走 Claude Code CLI adapter，建完仍由当前驱动继续检查和呈交。

#### 4b：claude-code / codex / cursor-agent / gemini / manual = 走 build adapter

调用通用 build adapter（独立 CLI 进程；adapter 约定改动落 `BUILD_DIR` 且 unstaged，不自己 commit）：

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
LOG="$MAIN_REPO_ROOT/.runs/pmai-build-${EXECUTOR}.log"; mkdir -p "$MAIN_REPO_ROOT/.runs"

# adapter 入参用环境变量。build 自己负责 clean tree、越界检查和零改动检查；
# adapter 只负责把执行器跑起来。
MAIN_REPO_ROOT="$MAIN_REPO_ROOT" BUILD_DIR="$BUILD_DIR" MODULE_NAME="<模块>" PROMPT_FILE="$PROMPT_FILE" \
  bash "$ADAPTER" > "$LOG" 2>&1
EXIT_CODE=$?
[ "$EXIT_CODE" -ne 0 ] && { echo "❌ 执行器失败（exit $EXIT_CODE），日志：$LOG。可换工具重建或改用「我自己建」。"; git -C "$BUILD_DIR" restore . 2>/dev/null; git -C "$BUILD_DIR" clean -fd 2>/dev/null; exit 0; }
```

> 超 10 分钟会被 Bash tool timeout：改用 `scripts/run-bg.sh` 后台跑 + Bash run_in_background 起 waiter（`until [ -f "$LOG.exit" ] || [ -f "$LOG.stall" ]; do sleep 60; done`）。

#### 4c：越界写保护（轻量）

build 改动应集中在 `prototype/`。`docs/*` 改动**默认不属于 build 边界**（文档归位是 `/pmai-close` 的事）。扫一遍，越界就提示 PM：

```bash
( cd "$BUILD_DIR" && git status --porcelain | awk '{print $2}' ) | while read -r p; do
  case "$p" in docs/*) echo "⚠️ 越界：执行器改了 $p（build 只该动 prototype/，文档改动归 /pmai-close）。" ;; esac
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

**② 端口探测错开（并行 build 防抢端口）**：多个 worktree 同时 build 会抢 config.yml 同一个 dev 端口。从候选端口探测、占用就顺延下一个，把实际端口记下来给三道审复用：

```bash
# 从 config.yml dev_server.ports 候选里挑第一个没被占用的（候选解析见 build-audits.py _dev_ports）
PORT=""
for p in <config.yml dev_server.ports 候选>; do
  if ! lsof -iTCP:"$p" -sTCP:LISTEN -t >/dev/null 2>&1; then PORT="$p"; break; fi
done
[ -z "$PORT" ] && { echo "❌ 候选端口都被占用：先关掉别的 dev server，或在 config.yml 的 dev_server.ports 加端口。"; exit 1; }
( cd "$BUILD_DIR/prototype" && <dev 命令> --port "$PORT" )   # Bash run_in_background 后台跑；记下 $PORT 给视觉门 / 行为审复用
```

> **并行 build 心智**：worktree = 真实 build 的并行隔离（不同分支各挂一个 worktree、同时改、互不串）；① 复用 pnpm store 让 N 个 worktree 不各装一遍依赖、② 端口错开让 N 个 dev server 不抢端口。worktree 从 main 拉天然带定稿的功能锚点 / `PRODUCT-*` / `DESIGN.md`（决策文档读得到），无需另同步。

非 UI 类需求跳过。

### 步骤 6：建完三道审（覆盖 / 视觉 / 行为，复用 build-audits.py）

建完 AI **自动**跑三道机器审，走 `build-audits.py` 编排（确定性收集 + 合成一份给 PM；只报不改，是给 PM 看的证据，不替 PM 拍板）。

> **锚点已敲死**：覆盖审计锚点统一是步骤 0 选定的 **`BUILD_ANCHOR`**（模块 `spec.md` 或 `docs/modules/<按内容命名>.md`）。`build-audits.py` 已参数化锚点（`--range-list` / `--audit-dir` / `--label`）。统一接脚本，复用其 fail-loud「三道齐全」校验——覆盖审计是防残承重墙，不走纯 AI 自跑（避免静默漏一道审还往下走）：
> ```bash
> BUILD_ANCHOR="$BUILD_DIR/<docs/modules/... 实际锚点路径>"   # 模块 spec 或功能型文档
> python3 "$PMAI_HOME/scripts/build-audits.py" resolve "$BUILD_ANCHOR" \
>     --repo-root "$BUILD_DIR" --range-list "$BUILD_ANCHOR" \
>     --audit-dir ".pm-workflow/audits/<模块>" --label "<模块>"
> # …三道审各写 coverage.json / visual.json / behavior.json 进 $BUILD_DIR/.pm-workflow/audits/<模块>/…
> python3 "$PMAI_HOME/scripts/build-audits.py" synthesize "$BUILD_ANCHOR" \
>     --repo-root "$BUILD_DIR" --audit-dir ".pm-workflow/audits/<模块>" --label "<模块>"
> ```

三道审抓三种不同的病：

- **① 覆盖审计**（白纸新鲜视角，对标 `coverage-reviewer` agent）：拿**功能锚点 BUILD_ANCHOR** 对 `prototype/` 代码逐项 diff，报每条规格点：✅ 建了 / ❌ 丢了 / ⚠️ 降级占位（空壳 / 假数据 / 交互没接）。故意不让建代码的 AI 自审，避盲区。静态读码，不需 dev server，先跑。
- **② 视觉门**（gstack `/design-review`，只截图不改）：对照 `docs/DESIGN.md` 审视觉一致性（间距 / 层级 / 配色 / AI slop）。用 `/browse`（headless），禁 `mcp__claude-in-chrome__*`。出口是 PM 一句话 pass / 打回，**AI 不替 PM 改视觉**。复用步骤 5 的 dev server。
- **③ 行为审**（验收流程驱动 `/browse` 走确定性路径）：从功能锚点的核心动作 / 状态机 / 验收标准派生验收流程，`/browse` 逐流程跑，验证「跑得通不通」（明确 pass/fail，区别于 `/qa` 的 AI 探索）。复用步骤 5 的 dev server。

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
- review loop 只动 prototype/ 代码，**不动 spec.md / decisions.md**（文档对齐是 `/pmai-close` 的事；改造后讨论 / 定稿在 main 上由 /pmai-design 做，build 期不改模块文档）。
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
- 选 `可以，收尾` / 输 `1` / 输 "OK / 通过 / 可以" → 进步骤 9（接 `/pmai-close`）。
- 选 `还要改` / 输 `2` / 提具体反馈 → 回步骤 7 review loop 按反馈改 → 重审 → 追加 fix commit（`build(<模块>) fixup: <一句话>`）→ 重新呈交。

### 步骤 9：交接 /pmai-close 收尾（含 merge）

PM 拍 `可以，收尾` → build 的活到此为止，**merge 回 main + 文档归位 + 决策 / 术语回写基线 由 `/pmai-close` 做**（不在 build 里 merge：`/pmai-close` 是改造后的收尾原子动作，把决策 / 术语沉淀和 merge 焊在一起，绕不过）。

输出 Next Up（不写 worktree / merge / 分支字样，按 banner-rules §2.5）：

```
✅ <模块> 这版建好了，你确认通过。

▶ Next Up：发 /pmai-close 收尾这个模块 —— 把这次拍的决策和新术语沉淀进基线，文档归位<，改动合回主线>。
```

> 括号里「改动合回主线」仅在开了隔离环境（步骤 1 选了 worktree）时出现；PM 在 main 上直接建的，无 merge、`/pmai-close` 只做沉淀 + 文档归位。`/pmai-close` 自己会判断有没有 worktree。

## 与上下游的衔接（一句话）

| 环节 | 谁做 | 交给 build / build 交出去的 |
|---|---|---|
| 上游 `/pmai-design` / `/pmai-prd-writing` | 在 main 上理清信息模型、`/mock` 确认设计、产 / 演进模块规格 `spec.md`；或写功能型文档 | build 拿模块 `spec.md` 或 `docs/modules/<按内容命名>.md` 当建造契约（覆盖审计锚点）+ 相关 `decisions.md` 当背景 |
| 本 skill `/pmai-build` | 仅大需求：PM 选工具 + 选要不要 worktree → 派执行器在 prototype/ 建 → review loop + 三道审 → commit + 呈交 | 建好的 prototype/ 改动（worktree 或 main 上）+ PM 验收通过信号 |
| 下游 `/pmai-close` | 决策 / 术语回写基线、文档归位、有 worktree 则 merge 回 main 并删 | 把 build 产物收口进基线 + 主线 |

## Rules

- **只大需求走 build**。讨论（改文档）/ 小改（一两处字段 / 文案 / 局部）不走这——在 main 上由 `/pmai-design` 或直接改 prototype/ 完成，无 worktree。步骤 0 判出是小改 → 退出 build。
- **对着功能锚点建**。覆盖审计锚点 = `docs/modules/<模块>/spec.md` 或 `docs/modules/<按内容命名>.md`。不拆任务卡、不走独立任务状态机。
- **PM 选工具**（claude-code / codex / cursor-agent / gemini / manual，复用 exec-adapter）**+ PM 选要不要 worktree**（步骤 1 / 步骤 2 两道 PM 决策）。executor 从问 PM 拿。
- **worktree 可选、统一挂 `.worktrees/<分支>/`**。开了就用 `git -C "$BUILD_DIR"` / subshell，禁 `cd` 进 worktree（cwd 护栏）；没开则 `BUILD_DIR="$REPO_ROOT"`、main 上直接建（main 写保护已放宽）。
- **claude-code = 优先派独立 build subagent**（Agent 工具），不在驱动上下文 inline 建（隔离 + 角色分离 + 不刷 PM 屏）；当前 runtime 没有 subagent 时走 `exec-adapters/claude-code.sh` 调 Claude Code CLI。codex / cursor-agent / gemini / manual 走现成 exec-adapter。一次只建本模块这一片。
- **建之前必读 DESIGN.md**（cat echo 进 context）+ 功能锚点当契约；先扫已有组件复用、不重写。
- **三道审 AI 自动跑、只报不改**（覆盖 / 视觉 / 行为，复用 build-audits.py 编排或等价自跑；三道审复用同一次 dev server）；出口都是给 PM 看的证据，不替 PM 拍板。探索式 review（`/review` `/qa` `/qa-only`）是 PM 手动旁路，AI 不自动调（守 I-RV1）。
- **review loop 只动 prototype/ 代码**，不改 spec.md / decisions.md（模块文档对齐归 `/pmai-close`；build 期不改文档）。AI 主动批量 flag、PM 勾改；每轮改完重跑三道审。
- **commit 用 `git -C "$BUILD_DIR"`**；执行器禁自己 commit（claude-code subagent prompt 里写死、adapter 约定 unstaged）。
- **PM 验收是唯一决策点**（步骤 8）；通过后**不在 build 里 merge**，交 `/pmai-close` 做 merge + 沉淀（决策 / 术语回写基线焊在 close 里绕不过）。
- 越界（执行器改了 docs/*）/ 零改动 / 执行器失败都给 PM 看、不静默吞；失败可换工具或改「我自己建」。
- 所有路径用绝对路径（`BUILD_DIR` / `MAIN_REPO_ROOT` / `REPO_ROOT`），不依赖会话 cwd。
