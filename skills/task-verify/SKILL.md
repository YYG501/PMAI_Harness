---
name: pmai-task-verify
description: |
  行为审：按 task「🧪 自测说明」段的验收流程驱动 gstack /browse 跑一遍浏览器，输出 pass/fail 报告 + 截图证据。
  自测说明由范围清单派生（确认范围时拍的「有哪些页面/字段/按钮/tab/状态」翻成「打开→操作→期望」的固定路径）。
  每次「建」完自动跑（建 → 三道审 → 呈交验收），也可 PM 手动重跑。
  与 review 工具区别：行为审是验证 PM 拍板的流程跑不跑得通（确定性 pass/fail）；review 是探索性质量审查（多元 finding）。
---

# /pmai-task-verify

## 在六步里的位置

「建」完自动跑的**三道审**之一 —— **行为审（跑得通不通）**：

```
建（在 prototype/ 用 Claude Code 栈内建）
  ↓
三道审（建完自动跑，合成一份给 PM）
  ├ 覆盖审计 —— 建全了没（范围清单 vs 代码硬 diff，coverage-reviewer agent）
  ├ 视觉门   —— 长得对不对（gstack /design-review，只截图不改）
  └ 行为审   —— 跑得通不通（本 skill：验收流程驱动 gstack /browse 走确定性路径）   ← 你在这
  ↓
体验迭代（AI 主动批量 flag、PM 勾改）
  ↓
呈交验收闸门（PM 一句 pass / 打回 = 唯一拍板点）
```

行为审是闸门下面「**自动产证据**」的一环：每次「建」完都跑同一条路径，给 PM 看「PM 当初拍的流程现在通没通」。**它不是拍板点** —— PM 的 pass/打回在呈交闸门做（见下方「与呈交闸门的关系」）。

## When To Use

- 「建」完自动跑（自审之后、commit 之前）由 AI 自动调用
- PM 手动重跑（异常场景：报告丢失 / 上次中断）

## I-RV1 边界（必读）

I-RV1 禁止 AI 自动调任何 **review 工具**（`/review` `/qa` `/qa-only` `/design-review` 等探索式审查）。行为审**不是 review 工具**：

| 维度 | review 工具 | 行为审（本 skill） |
|---|---|---|
| 性质 | 探索性质量审查（多元 finding + severity） | 确定性 UAT（pass/fail） |
| 驱动 | Claude 自主探索 / diff-aware | 范围清单派生的验收流程（步骤定死、每次同路径） |
| 输出 | 健康分 + bug 列表 + repro | 流程逐条 pass/fail + 失败截图 |
| 与 PM 决策对齐 | 弱（Claude 主观判断） | 强（每流程对照 PM 拍板的"期望"） |

**行为审必须由 AI 在「建」完自动调用**，不依赖 PM 手动触发；I-RV1 不适用。视觉门用的 `/design-review` 同理（建完自动跑的纪律，不是 PM 手动旁路的探索式 review）。

## 验收流程从哪来（范围清单派生）

行为审的流程**不是临时编的**，也不再从 task 描述里现想 —— 它是**确认范围时拍的范围清单派生出来的**：

- 确认范围那一步产出 `req-plan.md`，里头**范围清单**列了这个需求「有哪些页面 / 字段 / 按钮 / tab / 状态 / 做不做」（PM 拍板的 WHAT）。
- 拆 task 时，把范围清单里属于本 task 的项翻成**固定验收路径**（「打开 X → 操作 Y → 期望 Z」），写进 task 单文件**执行区**的「🧪 自测说明」段。
- 行为审只读这一段、按它一步步跑 —— 所以「跑得通不通」对照的就是**PM 当初拍的范围**，不是 AI 自己想的。

> 这是行为审与覆盖审计的分工：覆盖审计拿同一张范围清单查「建全了没（存在）」，行为审拿派生的流程查「跑得通不通（行为）」。两道都锚在范围清单上，所以没有结构化范围清单，两道都没了锚点。

## task 文件读取约定

本 skill 只读 task 单文件的「🧪 自测说明」段（执行区，`<!-- region: EXEC begin/end -->` 之间）。section 名固定 `## 🧪 自测说明...`，步骤 2 的 awk 锚点（前缀匹配 `/^## 🧪 自测说明/`）通用，无需分流读取。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: task-verify"
```

## Workflow

### 步骤 1：定位 task 文件 + 解析隔离副本路径（不 cd）

参数同建（task-execute）入口步骤 1（完整路径 / 短 ID / 无参数 自动扫描）。定位到 `TASK_FILE` 后，单窗口模型**不 `cd` 进隔离副本**——解析绝对路径，后续命令显式带目录：

```bash
MAIN_REPO_ROOT="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." && pwd)"
TASK_STEM=$(basename "$TASK_FILE" .md)
TASK_WORKTREE="$MAIN_REPO_ROOT/.worktrees/$TASK_STEM"
VERIFY_DIR="$TASK_WORKTREE/.pm-workflow/tasks/$TASK_STEM/verify"
mkdir -p "$VERIFY_DIR"

if [ ! -d "$TASK_WORKTREE" ]; then
  echo "❌ task 隔离副本不存在：$TASK_WORKTREE（先跑 /pmai-task-confirm 备好）" >&2
  exit 1
fi
```

后续 dev server / browse 命令一律显式带目录（`git -C` / 子 shell `( cd "$TASK_WORKTREE" && … )`，单次 Bash 调用内 cd 有效），不依赖会话 cwd——PM 不切窗口、不必 `claude --add-dir`。

### 步骤 2：读 task「🧪 自测说明」段（范围清单派生的验收流程）

```bash
awk '
  /^## 🧪 自测说明/{flag=1; next}
  /^## / && flag{flag=0}
  flag{print}
' "$TASK_FILE" > "$VERIFY_DIR/_plan.md"
```

解析每个 `### 流程 N: <name>` 块，提取：
- 流程名
- 动作步骤（PM 视图描述的数字列表）
- artifact 字段（截图路径）

**段为空 / 写"无（非 UI）"**：跳过本 skill，写 `report.md` 标记 `skipped: 非 UI`，返回 pass。

### 步骤 3：读 .pm-workflow/config.yml

```bash
CONFIG="$TASK_WORKTREE/.pm-workflow/config.yml"
if [ ! -f "$CONFIG" ]; then
  echo "❌ 缺少 .pm-workflow/config.yml；请先在项目里跑 scripts/init-project.sh" >&2
  exit 1
fi
```

提取字段（用 yq 或 python yaml 解析）：
- `dev_server.command` — 启动命令（如 `pnpm dev`）
- `dev_server.ports` — 端口探测列表（如 `[3000, 5173, 8080]`）
- `dev_server.ready_check` — 健康检查路径（如 `/`）

### 步骤 4：确认 dev server 在跑（不在跑就起）

按端口列表轮询 ready_check：

```bash
for port in "${PORTS[@]}"; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}${READY_CHECK}" 2>/dev/null)
  if [ "$CODE" = "200" ]; then
    PORT=$port
    BASE_URL="http://localhost:${PORT}"
    break
  fi
done
```

**找到** → 进步骤 5。

**找不到** → 在隔离副本里起 dev server（显式带目录、后台跑），30s 超时：

```bash
( cd "$TASK_WORKTREE" && $DEV_COMMAND ) > "$VERIFY_DIR/_dev-server.log" 2>&1 &
DEV_PID=$!
# 轮询 30s 直到 ready_check 200
```

仍未 ready → 写 `report.md` 标记 `dev_server_failed`，返回 fail（exit 1）。

### 步骤 4.5：登录态前置（验收流程触到登录后页面时）

行为审要测的页面在**登录后**时，先确保 `/browse` 带登录态。两条路，AI 按本页所在层的实现深度（读 `工程结构约束-{prototype,system,custom}.md` / `PRODUCT-STATE.md` 判 mock / system）选：

1. **登录能用 UI 走通**（账号密码表单 → 后端发 session cookie）——**默认走这条**：把「登录」作为验收流程**第一步**写进 `_plan.md`，`/browse` 跑一遍登录、同一 session 自然带上 cookie，后续步骤就是登录态，**不需要外部导入**。prototype mode（mock auth）+ system mode 里表单可登录的，都走这条。
2. **登录走不通 UI**（外部 SSO / OAuth 跳转 / MFA / captcha——仅 system mode 真 auth 可能遇到）：跑步骤 5 前用 Skill tool 调 gstack `/setup-browser-cookies` 导一次真 cookie，让后续 `/browse` 带登录态。
   ```bash
   # 仅当本页 = system mode 真 auth 且登录非表单可走时
   # （AI 判定后）用 Skill tool 调 gstack /setup-browser-cookies，导入常驻 browse session
   ```
   - ⚠️ cookie 导入有 **macOS Keychain 弹窗 + PM 手动选域，破坏无人值守**——**仅在路 1 走不通时才用**。

mock auth / 无鉴权 / 表单可登录 → 路 1，无 cookie 动作，直接进步骤 5。**只有 system mode 真 auth + 登录非表单可走**才落到路 2。

### 步骤 5：逐流程跑（调 gstack-browse，注入验收流程 + 固定纪律）

**不再用硬编码的「PM 动作→浏览器操作」映射表**（任何新句式都要回去改表 = 机械化债）。改成：把 `_plan.md` 的验收流程**原文当 prompt 注入** gstack `/browse`，由 `/browse` 自己把「打开→操作→期望」翻成浏览器操作，配一段**固定纪律 prompt** 钉住确定性。

用 Skill tool 调 `gstack-browse`，prompt = 验收流程原文 + 下面这段纪律（`$BASE_URL` / `$VERIFY_DIR` 填实际值）：

```
你在跑一条 PM 拍板的确定性验收流程，不是自由探索。严格遵守：
- 严格按流程文本逐步走，一步不漏、不加戏、不自由点别的页面
- 每一步的「期望」都要 assert；断言优先用页面可见文案，不要用 CSS selector（文案更稳、跨两次跑一致）
- 某步 assert 失败：记录失败步骤序号 + 流程原文 + 页面实际状态摘要，截图当前状态到
  $VERIFY_DIR/flow-N-FAIL.png，然后【继续跑下一个流程】（不中断整个行为审）
- 全程只读不改：不要尝试改任何代码 / 文件
- 只回每个流程的 ✅/❌ + 失败摘要 + 截图路径；不要给"下一步建议"、不要打健康分
BASE_URL = $BASE_URL；截图目录 = $VERIFY_DIR；通过流程截图存 flow-N.png、失败存 flow-N-FAIL.png
```

每个流程 `/browse` 跑完回 pass/fail + 截图：通过存 `$VERIFY_DIR/flow-N.png`，失败存 `$VERIFY_DIR/flow-N-FAIL.png`，**失败不中断、继续下一流程**（便于一次性出全报告）。

> **为什么是 `/browse` 不是 `/qa`**：`/browse` 是「指哪打哪」的确定性浏览器操作层，allowed-tools 只有 Bash/Read/AskUserQuestion，**物理上无 Edit/Write → 天然只报不改**。`/qa` 是「Test→Fix→Verify」，会**自动改代码 + 强制 clean working tree（刚 build 完必 dirty、每次先被拦）+ 出健康分（不是"你拍的流程通没通"）**——撞「只报不改 + 确定性」两条硬约束，prompt 也压不住它 click-everything 的探索目标。**确定性来自注入的固定流程文本 + 这段纪律 prompt，不来自换工具。**

### 步骤 6：写 verify/report.md

```markdown
# 行为审报告 — task-NNN

- **时间：** YYYY-MM-DD HH:MM
- **dev server：** http://localhost:PORT
- **总流程数：** N
- **通过：** M
- **失败：** N-M

## 流程结果

### 流程 1: 未登录访问受保护页 ✅
- 截图：[flow-1.png](./flow-1.png)

### 流程 2: 错误密码登录 ❌
- 失败步骤：步骤 3「期望：显示"密码错误"」
- 实际：页面无 .error 元素，URL 跳到 /workspace
- 截图：[flow-2-FAIL.png](./flow-2-FAIL.png)

### 流程 N: 冷启动 smoke ✅
- 日志：[cold-start.log](./cold-start.log)

## 结论

❌ FAIL — 流程 2 未通过。请修复"错误密码"路径的错误提示后重跑。
```

### 步骤 7：返回 pass / fail

- **全部流程 pass** → `exit 0`，stdout 输出 `✅ 行为审 pass（N/N 流程通过）`
- **任一流程 fail** → `exit 1`，stdout 输出 `❌ 行为审 fail（M/N 通过，详见 verify/report.md）` + 失败流程一句话摘要

**输出禁止扩写**：除上述规定的一行 stdout（fail 时再加失败流程一句话摘要），**禁止**追加 `STATUS:` / `REASON:` / `ATTEMPTED:` / `RECOMMENDATION:` 这种交接块，**禁止**指挥下一步动作（如「回去继续走」「写自审 → commit → 呈交 PM 验收」）。行为审是「建」完自动跑的子流程，越界给"下一步建议"会让 AI 在此处误判为 task 终态、停下来等下一轮 → task 既没 commit 也没呈交（自说自话）。**任何"下一步"由调它的 build 流程的 transition 规则决定。**

## 与呈交闸门的关系（两件事，别混）

行为审产**证据**；呈交闸门做**决策**：

- **行为审（本 skill）** = 每次「建」完自动跑、出 pass/fail + 截图。它把结果并进三道审合成报告，喂给呈交块，**自己不停下来等 PM**。
- **呈交闸门** = PM 一句 `pass` / `打回` —— 整个「建」流程**唯一的拍板点**。它架在三道审（含行为审）的证据上，由 PM 拍。**绝不自动**：不设"AI 觉得行为审过了就替 PM 过"。

所以：

- 行为审 **pass**：把这一道并进合成报告，自动接 commit → 呈交 PM 验收**一气走完**；**不要**在这停下来宣告 task 完成（task 还没 commit、PM 还没看任何东西，那是常见跑偏）。
- 行为审 **fail**：不 commit，把失败摘要写进 task 反馈、AI 修代码、重跑行为审；连续 3 次还 fail，把累积报告呈交 PM 决定是否人工接手。

## Rules

- 在 **task worktree** 跑（dev server / 改动都在那）
- 不算 review 工具；AI 必须在「建」完自动调用，I-RV1 不适用
- dev server 已在跑（建的时候起的）→ 复用，不重启
- 工具默认 `gstack-browse`；未来若项目在 config.yml 配 `verify.screenshot_tool` 为别的值，按 config 走（当前版本仅支持 gstack-browse）
- 失败不中断整个行为审 —— 跑完所有流程后统一出报告，便于一次性看全
- 报告路径固定 `.pm-workflow/tasks/<task-stem>/verify/report.md`，build 流程 / close-task 都读这个
- 非 UI（自测说明段写"无"）直接返回 pass，不起 dev server
