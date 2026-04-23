# shellcheck shell=bash
# Shared gate helpers for external executor adapters (codex.sh / cursor-agent.sh).
# Enforces INVARIANTS.md I-AD1 / I-AD2 / I-AD4.
#
# Usage (in adapter):
#   source "$(dirname "$0")/_gate.sh"
#   adapter_precheck           # I-AD1 + fail-closed state gate
#   ... run executor ...
#   adapter_postcheck "$EXIT"  # I-AD2 + audit diff scope
#
# Required env vars:
#   TASK_FILE, TASK_WORKTREE, MAIN_REPO_ROOT

_gate_fail() {
  local reason="$1"
  echo "❌ adapter gate 拒绝：$reason" >&2
  # Record execution_failed so close-task audit sees it
  if [ -n "${TASK_FILE:-}" ] && [ -f "${MAIN_REPO_ROOT:-}/.claude/scripts/task-events.py" ]; then
    python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
      --type execution_failed \
      --note "adapter_gate: $reason" 2>/dev/null || true
  fi
  exit 1
}

adapter_precheck() {
  : "${TASK_FILE:?adapter_precheck requires TASK_FILE}"
  : "${MAIN_REPO_ROOT:?adapter_precheck requires MAIN_REPO_ROOT}"

  local transition_py="$MAIN_REPO_ROOT/.claude/scripts/task-transition.py"
  if [ ! -f "$transition_py" ]; then
    _gate_fail "找不到 task-transition.py（$transition_py）"
  fi

  local status
  status=$(python3 "$transition_py" "$TASK_FILE" --get-status 2>/dev/null || echo "")
  if [ "$status" != "执行中" ]; then
    _gate_fail "I-AD1: task 状态为「${status:-未知}」，不允许启动外部执行器。正确流程：/task-confirm → 状态=执行中 → /task-execute"
  fi
}

adapter_postcheck() {
  : "${TASK_WORKTREE:?adapter_postcheck requires TASK_WORKTREE}"
  : "${TASK_FILE:?adapter_postcheck requires TASK_FILE}"
  : "${MAIN_REPO_ROOT:?adapter_postcheck requires MAIN_REPO_ROOT}"

  local executor_exit="${1:-0}"

  # I-AD2: diff 范围校验
  local checker="$MAIN_REPO_ROOT/.claude/scripts/check-task-scope.py"
  if [ ! -f "$checker" ]; then
    echo "⚠️ 找不到 check-task-scope.py，跳过 I-AD2 越界校验" >&2
    return "$executor_exit"
  fi

  # 收集改动：worktree 内 unstaged + staged（adapter 约定 unstaged，但 Codex 偶尔会 stage）
  # 注意：这里不比 HEAD 而比 status --porcelain，避免漏掉 untracked 文件
  local changed
  changed=$(cd "$TASK_WORKTREE" && git status --porcelain 2>/dev/null | awk '{print $NF}')
  if [ -z "$changed" ]; then
    # 零改动：让 task-execute 的零改动检查决定是否 --fail-execution
    return "$executor_exit"
  fi

  if ! echo "$changed" | python3 "$checker" "$TASK_FILE" --allow-empty; then
    # scope 越界 → 记 execution_failed，返回非零给 task-execute
    python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
      --type execution_failed \
      --note "I-AD2 violation: diff 越界 allowlist" 2>/dev/null || true
    echo "" >&2
    echo "❌ I-AD2: 执行器写入范围越界 task 的 allowlist。" >&2
    echo "   代码已保留在 ${TASK_WORKTREE}，请人工检查或 /task-execute 带 --fail-execution 回退。" >&2
    return 2
  fi

  return "$executor_exit"
}
