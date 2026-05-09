# Step 3 详细：dispatch + rollback + 诊断

> 本文件是 `skills/task-execute/SKILL.md` 步骤 3 的物理拆分（核心执行机制：lock / dispatch / 越界保护 / 回滚 / 诊断文案）。主 SKILL 步骤 3 入口仅留状态 gate + 指向本文件的引用。

## 3a. Lock + manual 幂等重入

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

  # Preflight：scope 越界校验由 _gate.sh adapter_postcheck 在 dispatch 路径承担；
  # manual resume 路径不经 adapter，scope 校验降级为「PM 自负责」+ 下面的执行日志检查兜底。

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

## 3b. 正常 dispatch

```bash
if [ -z "${MANUAL_RESUME:-}" ]; then
  # I-AD5: Pre-dispatch checkpoint gate — task worktree 必须 clean
  # Why: codex / cursor-agent 的 stop 是软停，已派发的 sandbox shell 子进程会延迟落盘
  #      可能覆盖手改但没 commit 的文件；失败回滚基线是 HEAD，未 commit 改动会被 restore 清掉。
  # 故意不走 adapter 失败路径（不 rollback、不 --fail-execution），处理权交还 PM。
  DIRTY=$(git -C "$TASK_WORKTREE" status --porcelain 2>/dev/null)
  if [ -n "$DIRTY" ]; then
    echo "" >&2
    echo "❌ /task-execute 拒绝 dispatch：task worktree 有未 commit 改动（I-AD5）。" >&2
    echo "" >&2
    echo "原因：codex / cursor-agent 的 stop 是软停，已派发的 sandbox shell 子进程会延迟落盘，" >&2
    echo "可能覆盖你刚手改但没 commit 的文件。失败回滚基线是 HEAD，未 commit 的手改会被 restore 清掉。" >&2
    echo "" >&2
    echo "task worktree: $TASK_WORKTREE" >&2
    echo "现状：" >&2
    git -C "$TASK_WORKTREE" status --short >&2
    echo "" >&2
    echo "处理（任选一种后重跑 /task-execute）：" >&2
    echo "  保留改动：cd \"$TASK_WORKTREE\" && git add -A && git commit -m 'pre-execute checkpoint: <一句话>'" >&2
    echo "  丢弃改动：cd \"$TASK_WORKTREE\" && git restore . && git clean -fd" >&2
    echo "" >&2
    echo "注意：本次 task 状态保留为「执行中」，不回退、不 rollback worktree。" >&2
    exit 1
  fi

  # Resolve executor + model
  RESOLVED=$(python3 "$MAIN_REPO_ROOT/.claude/scripts/resolve-executor.py" "$TASK_FILE")
  EXECUTOR=$(echo "$RESOLVED" | jq -r .executor)
  EXECUTOR_MODEL=$(echo "$RESOLVED" | jq -r '.model // ""')

  # Build prompt
  PROMPT_FILE=$(mktemp)
  python3 "$MAIN_REPO_ROOT/.claude/scripts/build-execution-prompt.py" "$TASK_FILE" > "$PROMPT_FILE"

  # Baseline SHA（I-AD5 保证此时 working tree == HEAD）
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
    # 超 10 分钟会被 Bash tool timeout。如果遇上，改用：
    #   bash .claude/scripts/run-bg.sh "$LOG_PATH" bash "$ADAPTER"
    # 然后 Claude 用 **Bash run_in_background**（不是 Monitor —— Monitor 默认 5min 超时
    # 会被静默 cut）起一个 waiter，同时兜「正常退」和「卡死」两条信号：
    #   until [ -f "$LOG_PATH.exit" ] || [ -f "$LOG_PATH.stall" ]; do sleep 60; done
    #   if [ -f "$LOG_PATH.stall" ]; then echo "STALLED at $(cat "$LOG_PATH.stall")"
    #   else echo "exit_code=$(cat "$LOG_PATH.exit")"; fi
    # run-bg.sh 自带 watchdog（默认 180s 无 log 增长 → 写 .stall，不杀子进程）。
    # waiter 输出 STALLED → 进程仍在跑，处理权交 PM（杀 / 等 / 转 manual）。
    # 这是逃生路径，不是默认模式。

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

## 3c. 越界写保护 + 回滚函数

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

## 3e. 诊断文案函数

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
Task 执行失败，已回退到「待执行」。

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

## claude-code 执行者的主流程

当 executor=claude-code 走这里，当前 Claude 实例执行：

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
