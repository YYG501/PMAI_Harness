---
name: task-execute
description: |
  在 task worktree 中实现代码、启动 dev server、写执行日志、填文档偏差、自审并记录。
---

# /task-execute

## When To Use

- Suborchestrator 在 task worktree 中读取此 skill 并执行

## Workflow

### 步骤 1：读取 task 文件

读取 task 文件（使用绝对路径到主仓的 req 目录）。提取：
- 任务描述
- 执行范围
- 验收标准
- 审查工具列表
- 启动前必读文档

### 步骤 2：读取必读文档

按「启动前必读」列表，逐个读取文档内容。理解：
- 模块规格中的**功能清单（硬约束）**：功能行为、数据规则、角色权限必须严格遵循
- 模块规格中的**实现指引（软指引）**：推荐组件、DESIGN.md 对齐、交互状态覆盖，可在设计系统框架内自由发挥
- 设计系统规范（DESIGN.md）
- 项目背景（CONTEXT.md）
- 参考源码（如列表中有已有页面/组件源码，理解其组件结构和布局模式）

**硬软分离原则：** 功能清单定义"做什么"（不可偏离），实现指引建议"怎么做"（可灵活调整）。在满足功能行为和设计系统约束的前提下，追求最好的视觉效果和交互体验。

### 步骤 3：实现代码（含 dispatch）

**步骤 3 的流程：状态 gate → dispatch → 越界保护 → 零改动检查。** 失败路径统一走 `--fail-execution` 回退 + 诊断文案。

#### 3.0 前置状态 gate（I-AD1 的入口侧对应物）

在拿 lock、起 executor 之前，必须先校验 task 状态 == `执行中`。没经过 `/task-confirm` 的 task 不允许直接执行。这是针对「orchestrator 或 suborchestrator 绕过状态机直接调 /task-execute」的结构性防御。

```bash
CURRENT_STATUS=$(python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" --get-status 2>/dev/null || echo "")
if [ "$CURRENT_STATUS" != "执行中" ]; then
  echo "❌ /task-execute 入口拒绝：task 状态为「${CURRENT_STATUS:-未知}」，不是「执行中」。" >&2
  echo "" >&2
  echo "正确流程：" >&2
  echo "  1) /task-confirm $TASK_FILE   # PM 确认 task 后，执行此命令把状态从「待确认」转到「执行中」" >&2
  echo "  2) /task-execute $TASK_FILE   # 当前命令" >&2
  echo "" >&2
  echo "不要跳过 /task-confirm。状态机（待确认→执行中→待验收→已完成）是数据完整性的前提，跳过会导致 close-task 事件流审计（I-CT7/I-CT8）拒绝 merge。" >&2
  exit 1
fi
```

#### 3a. Lock + manual 幂等重入

```bash
TASK_ID=$(basename "$TASK_FILE" .md | sed -E 's/^(task-[0-9]+).*/\1/')
LOCK_DIR="$MAIN_REPO_ROOT/.runs/.lock-${TASK_ID}"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "❌ 另一个 /task-execute 正在运行 Task-${TASK_ID}。如确定没有，手动删除 $LOCK_DIR 后重试。" >&2
  exit 1
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

PENDING_FILE="$MAIN_REPO_ROOT/.runs/.pending-manual-${TASK_ID}.json"

if [ -f "$PENDING_FILE" ]; then
  BASELINE_SHA=$(jq -r .baseline_sha "$PENDING_FILE")
  STARTED_AT=$(jq -r .started_at "$PENDING_FILE")

  echo "✓ 检测到 Task-${TASK_ID} 的 manual 续跑标记（since $STARTED_AT）。"
  echo "  将保留 $TASK_WORKTREE 的现有改动，不会重新调用任何执行器。"
  echo "  先跑 preflight，通过后直接进入自审阶段（step 4）。"
  echo ""

  # Preflight: 检查 worktree 改动是否超出 allowlist
  # 调 build-execution-prompt.py 不可行（不提供 allowlist），这里直接跟 task 文件解析
  ALLOWLIST=$(python3 "$MAIN_REPO_ROOT/.claude/scripts/parse-task-scope.py" "$TASK_FILE" 2>/dev/null || true)
  # 简化版：只检查文件是否在 allowlist（详细实现见批次 7 的完整脚本，这里用宽松策略）
  CHANGED=$(git -C "$TASK_WORKTREE" diff --name-only "$BASELINE_SHA" HEAD 2>/dev/null || \
            git -C "$TASK_WORKTREE" status --porcelain | awk '{print $2}')

  # 检查执行日志和文档偏差 section 已填
  if ! grep -q '^### 执行报告' "$TASK_FILE"; then
    echo "⚠️ 请先在 task 文件「执行日志」section 记录你做了什么（见模板 ### 执行报告 格式），再重跑 /task-execute。"
    echo "  pending 标记保留。"
    exit 1
  fi

  # 通过 → 删标记，追加事件，进 step 4
  rm -f "$PENDING_FILE"
  python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
    --type execution_manual_completed
  # 跳到 step 4（不 exec adapter，不记 execution_started）
  MANUAL_RESUME=1
fi
```

若 `MANUAL_RESUME=1`，跳过 3b/3c/3d 直接进 step 4。

#### 3b. 正常 dispatch

```bash
if [ -z "${MANUAL_RESUME:-}" ]; then
  # Resolve executor + model
  RESOLVED=$(python3 "$MAIN_REPO_ROOT/.claude/scripts/resolve-executor.py" "$TASK_FILE")
  EXECUTOR=$(echo "$RESOLVED" | jq -r .executor)
  EXECUTOR_MODEL=$(echo "$RESOLVED" | jq -r '.model // ""')

  # Build prompt
  PROMPT_FILE=$(mktemp)
  python3 "$MAIN_REPO_ROOT/.claude/scripts/build-execution-prompt.py" "$TASK_FILE" > "$PROMPT_FILE"

  # Baseline SHA
  BASELINE_SHA=$(git -C "$TASK_WORKTREE" rev-parse HEAD)

  # Event
  python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
    --type execution_started \
    --payload "{\"executor\":\"$EXECUTOR\",\"model\":\"$EXECUTOR_MODEL\",\"baseline_sha\":\"$BASELINE_SHA\"}"

  LOG_PATH="$MAIN_REPO_ROOT/.runs/execution-${TASK_ID}-${EXECUTOR}.log"
  mkdir -p "$MAIN_REPO_ROOT/.runs"

  # Dispatch
  if [ "$EXECUTOR" = "claude-code" ]; then
    # 走下面「claude-code 执行者的主流程」——当前 Claude 实例自己实现
    # Prompt 已写到 $PROMPT_FILE，Claude 应读它理解执行边界
    echo "✓ executor=claude-code，当前 Claude 实例继续执行。Prompt: $PROMPT_FILE"
  elif [ "$EXECUTOR" = "manual" ]; then
    MAIN_REPO_ROOT="$MAIN_REPO_ROOT" \
    TASK_FILE="$TASK_FILE" \
    TASK_WORKTREE="$TASK_WORKTREE" \
    PROMPT_FILE="$PROMPT_FILE" \
    EXECUTOR_MODEL="$EXECUTOR_MODEL" \
      bash "$MAIN_REPO_ROOT/.claude/scripts/exec-adapters/manual.sh"
    exit 0  # manual 已写 pending，skill 结束
  else
    # codex / cursor-agent
    ADAPTER="$MAIN_REPO_ROOT/.claude/scripts/exec-adapters/${EXECUTOR}.sh"
    if [ ! -x "$ADAPTER" ]; then
      echo "❌ 找不到 adapter: $ADAPTER" >&2
      python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" \
        --fail-execution --reason "adapter_missing"
      exit 1
    fi
    MAIN_REPO_ROOT="$MAIN_REPO_ROOT" \
    TASK_FILE="$TASK_FILE" \
    TASK_WORKTREE="$TASK_WORKTREE" \
    PROMPT_FILE="$PROMPT_FILE" \
    EXECUTOR_MODEL="$EXECUTOR_MODEL" \
      bash "$ADAPTER" > "$LOG_PATH" 2>&1
    EXIT_CODE=$?

    if [ "$EXIT_CODE" -ne 0 ]; then
      CLASSIFICATION=$(bash "$MAIN_REPO_ROOT/.claude/scripts/classify-failure.sh" "$EXIT_CODE" "$LOG_PATH")
      rollback_worktree "$BASELINE_SHA"  # 见 3c 回滚函数
      python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
        --type execution_failed \
        --payload "{\"executor\":\"$EXECUTOR\",\"model\":\"$EXECUTOR_MODEL\",\"exit_code\":$EXIT_CODE,\"classification\":\"$CLASSIFICATION\",\"log_path\":\"$LOG_PATH\"}"
      python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" \
        --fail-execution --reason "$CLASSIFICATION"
      output_diagnostic "$CLASSIFICATION" "$EXECUTOR" "$LOG_PATH" "$TASK_FILE"
      exit 0
    fi
  fi
fi
```

#### 3c. 越界写保护 + 回滚函数

```bash
# 回滚函数（失败路径或越界时调用）
rollback_worktree() {
  local baseline="$1"
  cd "$TASK_WORKTREE"
  # Tracked changes: restore from baseline
  git status --porcelain -z | \
    while IFS= read -r -d '' line; do
      local status="${line:0:2}"
      local path="${line:3}"
      case "$status" in
        "??")  rm -rf "$path" ;;                                   # untracked
        *)     git restore --source="$baseline" --worktree --staged -- "$path" ;;
      esac
    done
}

if [ -z "${MANUAL_RESUME:-}" ]; then
  # 越界检查：收集改动、分类、按 allowlist 过滤
  cd "$TASK_WORKTREE"
  BAD_FILES=""
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    # gitignore matched → skip (生成物)
    if git check-ignore -q "$path" 2>/dev/null; then continue; fi
    # Check against task allowlist (implementation detail: parse-task-scope.py or inline)
    # MVP: allow anything not under docs/ unless explicitly listed in task's 执行范围
    if [[ "$path" == docs/* ]]; then
      # docs/ must be explicitly in task allowlist
      if ! grep -qE "^\s*-\s*(新建|修改)：.*$path" "$TASK_FILE"; then
        BAD_FILES="$BAD_FILES $path"
      fi
    fi
  done < <(git status --porcelain | awk '{print $2}')

  if [ -n "$BAD_FILES" ]; then
    rollback_worktree "$BASELINE_SHA"
    python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
      --type execution_failed \
      --payload "{\"reason\":\"boundary_violation\",\"bad_files\":\"$BAD_FILES\"}"
    python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" \
      --fail-execution --reason "boundary_violation"
    output_diagnostic "boundary_violation" "$EXECUTOR" "$LOG_PATH" "$TASK_FILE"
    exit 0
  fi

  # 3d. 零改动检查
  CHANGE_COUNT=$(git status --porcelain | wc -l | tr -d ' ')
  if [ "$CHANGE_COUNT" -eq 0 ]; then
    python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
      --type execution_failed \
      --payload "{\"reason\":\"no_changes\"}"
    python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" \
      --fail-execution --reason "no_changes"
    output_diagnostic "no_changes" "$EXECUTOR" "$LOG_PATH" "$TASK_FILE"
    exit 0
  fi

  python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
    --type execution_completed \
    --payload "{\"executor\":\"$EXECUTOR\",\"model\":\"$EXECUTOR_MODEL\"}"
fi
```

#### 3e. 诊断文案函数

```bash
output_diagnostic() {
  local classification="$1" executor="$2" log="$3" task="$4"
  local stage="adapter 启动"
  local suggest=""
  case "$classification" in
    sandbox_denied)
      stage="adapter 启动"
      suggest="检查 ~/.codex/config.toml 的 sandbox_mode（应为 workspace-write），或改用 executor=cursor-agent / manual"
      ;;
    model_not_found)
      stage="执行器启动"
      suggest="检查 task 文件 **executor_model：** 字段，或清空让 settings 默认生效"
      ;;
    network)
      stage="执行中"
      suggest="网络 / rate limit 问题，稍等重试，或换执行者"
      ;;
    boundary_violation)
      stage="执行后越界检查"
      suggest="检查 task 「执行范围」字段，确认允许写入清单是否漏列了合法路径"
      ;;
    no_changes)
      stage="执行完成"
      suggest="执行器退 0 但 worktree 无改动。可能 prompt 被误解为"只分析"——检查 build-execution-prompt 输出"
      ;;
    *)
      suggest="查看日志诊断"
      ;;
  esac

  cat <<EOM

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Task 执行失败，已回退到「待确认」。

执行者：$executor
失败阶段：$stage
分类：$classification
日志：$log

下一步可直接选一项：
1. 同执行者重试（修根因后）：
   $suggest
   /task-confirm $task

2. 改用其它执行者：
   编辑 $task，修改 **executor：** 字段后
   /task-confirm $task

3. 搁置：
   /task-status 查看其它待办
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOM
}
```

---

**claude-code 执行者的主流程**（当 executor=claude-code 走这里，当前 Claude 实例执行）：

**实现前必做（UI 类 task）：**
- 读 `$PROMPT_FILE` 获取完整执行契约（允许/禁止写入、验收标准、写回职责）
- 用 Glob 扫描项目中的页面和组件目录，了解已有哪些组件和页面
- 如果要实现的功能与已有页面类似（如列表页、表单页），先读取该页面源码，复用其布局和组件
- 优先 import 已有组件，不要重写功能相同的组件
- 遵循已有代码的样式模式和目录约定

- 新建文件按执行范围创建
- 修改文件按执行范围修改
- 不动的文件不要碰
- **禁止 git add / git commit**（commit 由 step 10 统一做）

### 步骤 4：启动 dev server（UI 类 task）

如果是 UI 类 task：
1. 启动 dev server，绑定到 task 文件中指定的端口
2. 确保 server 在后台运行，不阻塞后续步骤
3. 验证 server 可访问

非 UI 类 task 跳过此步骤。

### 步骤 5：写执行日志

在 task 文件的「执行日志」section 填写：

```markdown
### 执行报告 - [YYYY-MM-DD HH:MM]
**改动摘要：** [简述做了什么]
**新建文件：** [文件列表]
**修改文件：** [文件列表]
**验收标准完成情况：**
- [x] 条件 1 — 已实现
- [x] 条件 2 — 已实现
```

### 步骤 6：写文档偏差

在 task 文件的「文档偏差」section：
- 如果实现与文档描述一致：写「无偏差」
- 如果有偏差：填写偏差表格

```markdown
| 文档位置 | 文档原文 | 实际实现 |
|----------|----------|----------|
| docs/modules/auth.md 第 15 行 | 使用 JWT 认证 | 改用 Session 认证（因 XX 原因） |
```

### 步骤 7：自审（gstack 质量 gate）

自审链路按以下顺序运行 gstack skill：

**7a. /review（代码审查，所有 task）**
- 运行 `/review`，审查 task 分支 vs req 分支的 diff
- **suborchestrator 自行处理所有发现，不 Ask PM**
- mechanical issues 自动修，critical issues 自行修复并记录到自审记录
- 追加事件：
  ```bash
  python3 .claude/scripts/task-events.py append "<task-file>" --type review_completed --tool "/review" --result "<pass|fail>"
  ```

**7b. /qa（功能测试，仅 UI task）**
- 如果审查工具字段包含 `/qa`：
  - 运行 `/qa`，测试 dev server URL
  - 发现 bug 自行修复（atomic commit）
  - 追加事件

**7c. /design-review（视觉审查，仅 UI task）**
- 如果审查工具字段包含 `/design-review`：
  - 运行 `/design-review`，对照 DESIGN.md 检查视觉一致性
  - 发现问题自行修复
  - 追加事件

### 步骤 8：写自审记录

在 task 文件的「自审记录」section 填写每个工具的审查结果，包括发现的问题和处理方式：

```markdown
### 自审 1 - [YYYY-MM-DD HH:MM]
**工具：** /review
**结果：** pass（2 个 mechanical issue 已自动修复）
**详细发现：** 
- F-001: 变量命名不一致 → 已修复
- F-002: 缺少 null check → 已修复
**遗留问题：** 无
```

### 步骤 9：修复自审发现的问题

如果自审发现了无法自动修复的问题：
1. 手动修复代码
2. 重新跑对应的审查工具
3. 更新自审记录
4. 追加新的 review_completed 事件

### 步骤 10：Commit + 提交待验收

**所有审查工具通过后，先 commit 再转状态。** Adapter 执行路径和 claude-code inline 路径在此处统一 commit（之前 worktree 一直是 unstaged）。

```bash
cd "$TASK_WORKTREE"

# 收集改动摘要（从最近一条「执行报告」section 提取）
SUMMARY=$(awk '/^### 执行报告/{flag=1} flag && /^\*\*改动摘要/{sub(/\*\*改动摘要：\*\*\s*/,"");print;exit}' "$TASK_FILE")
[ -z "$SUMMARY" ] && SUMMARY="实现 $(basename "$TASK_FILE" .md)"

git add -A
git commit -m "task-${TASK_ID}: ${SUMMARY}"

# 转待验收
python3 .claude/scripts/task-transition.py "$TASK_FILE" --to 待验收
```

脚本会自动校验：
- 文档偏差 section 已填
- 自审记录 section 有内容
- 所有审查工具都有 review_completed 事件

Dev server 保持运行（PM 验收时需要访问）。

## Rules

- task 文件用绝对路径读写（task worktree 中的路径和主仓路径不同）
- 代码改动在 task worktree 中进行
- 文档（docs/）不在 task worktree 中修改（hook 会拦截）
- 文档偏差记录到 task 文件，由 `/doc-update` 在 close-task 前处理
- 每个审查工具必须有对应的 review_completed 事件，否则无法转为待验收
- dev server 在 task-execute 结束后保持运行，直到 close-task 时杀掉
