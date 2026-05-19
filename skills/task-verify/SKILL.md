---
name: task-verify
description: |
  按 task md「🧪 自测说明」段的流程化 UAT 跑浏览器测试，输出 pass/fail 报告。
  在 task-execute 步骤 7.5（commit 前）自动调用；也可 PM 手动调。
  与 review skill 区别：UAT 是验证 PM 拍板的流程是否通（明确 pass/fail）；review 是探索性质量审查（多元 finding）。
---

# /task-verify

## When To Use

- task-execute 步骤 7.5（自审 placeholder 之后、commit 之前）由 AI 自动调用
- PM 手动调（异常重跑场景：报告丢失 / 上次 verify 中断）

## I-RV1 边界（必读）

I-RV1 禁止 AI 自动调任何 **review skill**（`/review` `/qa` `/qa-only` `/design-review` 等）。task-verify **不是 review skill**：

| 维度 | review skill | task-verify |
|---|---|---|
| 性质 | 质量审查（多元 finding + severity） | 流程化 UAT（pass/fail） |
| 驱动 | Claude 自主探索 / diff-aware | task md 预定义流程 |
| 输出 | 健康分 + bug 列表 + repro | 流程逐条 pass/fail + 失败截图 |
| 与 PM 决策对齐 | 弱（Claude 主观判断） | 强（每流程对照 PM 拍的"期望"） |

**task-verify 必须由 AI 在 task-execute 自动调用**，不依赖 PM 手动触发；I-RV1 不适用。

## 拆两文件约定

本 skill 只读 **PM 视图主文件**（`.md`）的「🧪 自测说明」段。工程合同（`.engineering.md`）不参与。

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-verify"
```

## Workflow

### 步骤 1：定位 task 文件 + cd 到 task worktree

参数同 task-execute 入口步骤 1（完整路径 / 短 ID / 无参数 自动扫描）。定位到 `TASK_FILE` 后：

```bash
TASK_STEM=$(basename "$TASK_FILE" .md)
TASK_WORKTREE="$MAIN_REPO_ROOT/.worktrees/$TASK_STEM"
VERIFY_DIR="$TASK_WORKTREE/.pm-workflow/tasks/$TASK_STEM/verify"
mkdir -p "$VERIFY_DIR"
```

cd 到 task worktree 沙盒边界处理同 task-execute 入口步骤 2（分两次 Bash 调用 + EXPECTED_CANONICAL 验证 + `claude --add-dir` 提示）；失败直接报错退出。

### 步骤 2：读 task md 「🧪 自测说明」段

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

**段为空 / 写"无（非 UI task）"**：跳过本 skill，写 `report.md` 标记 `skipped: 非 UI task`，返回 pass。

### 步骤 3：读 .pm-workflow/config.yml

```bash
CONFIG="$TASK_WORKTREE/.pm-workflow/config.yml"
if [ ! -f "$CONFIG" ]; then
  echo "❌ 缺少 .pm-workflow/config.yml；请先在消费仓跑 scripts/init-project.sh" >&2
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

**找不到** → 起 dev server，30s 超时：

```bash
$DEV_COMMAND > "$VERIFY_DIR/_dev-server.log" 2>&1 &
DEV_PID=$!
# 轮询 30s 直到 ready_check 200
```

仍未 ready → 写 `report.md` 标记 `dev_server_failed`，返回 fail（exit 1）。

### 步骤 5：逐流程跑（调 gstack-browse）

读 `_plan.md` 的每个流程，调 Skill tool → `gstack-browse` 按 PM 视图动作描述翻译成浏览器操作：

| PM 视图动作 | 浏览器操作 |
|---|---|
| "打开 /xxx" | navigate `$BASE_URL/xxx` |
| "输入 X" | fill 对应表单字段 |
| "点击 Y" | click 对应按钮（按 text / role） |
| "期望：跳转 /yyy" | assert URL 含 `/yyy` |
| "期望：显示 X 文案" | assert page contains text "X" |
| "期望：Logo 位置留空" | assert 对应选择器 empty / hidden |
| "期望：只 N 个侧边栏" | assert count of `aside` == N |
| "期望：无 X 文案" | assert page NOT contains "X" |
| artifact: verify/flow-N.png | screenshot 到 `$VERIFY_DIR/flow-N.png` |

**流程内任一 assert 失败**：
- 记录失败步骤序号 + PM 视图原文 + 浏览器实际状态摘要
- 截图当前状态 → `$VERIFY_DIR/flow-N-FAIL.png`
- 标记本流程 fail，继续下一流程（**不中断整个 verify**，便于一次性出全报告）

**全部 assert 通过** → 标记本流程 pass，存最终截图。

### 步骤 6：写 verify/report.md

```markdown
# Verify Report — task-NNN

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

- **全部流程 pass** → `exit 0`，stdout 输出 `✅ task-verify pass（N/N 流程通过）`
- **任一流程 fail** → `exit 1`，stdout 输出 `❌ task-verify fail（M/N 通过，详见 verify/report.md）` + 失败流程一句话摘要

## Rules

- 在 **task worktree** 跑（dev server / 改动都在那）
- 不算 review skill；AI 必须在 task-execute 步骤 7.5 自动调用，I-RV1 不适用
- dev server 已在跑（task-execute 步骤 4 起的）→ 复用，不重启
- 工具默认 `gstack-browse`；未来若消费仓在 config.yml 配 `verify.screenshot_tool` 为别的值，按 config 走（当前版本仅支持 gstack-browse）
- 失败不中断整个 verify —— 跑完所有流程后统一出报告，便于一次性看全
- 报告路径固定 `.pm-workflow/tasks/<task-stem>/verify/report.md`，task-execute / task-confirm 都读这个
- 非 UI task（自测说明段写"无"）直接返回 pass，不起 dev server
