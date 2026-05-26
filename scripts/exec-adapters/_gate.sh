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
  if [ -n "${TASK_FILE:-}" ] && [ -f "${MAIN_REPO_ROOT:-}/$HOME/.pmai/scripts/task-events.py" ]; then
    python3 "$MAIN_REPO_ROOT/$HOME/.pmai/scripts/task-events.py" append "$TASK_FILE" \
      --type execution_failed \
      --note "adapter_gate: $reason" 2>/dev/null || true
  fi
  exit 1
}

adapter_precheck() {
  : "${TASK_FILE:?adapter_precheck requires TASK_FILE}"
  : "${MAIN_REPO_ROOT:?adapter_precheck requires MAIN_REPO_ROOT}"

  local transition_py="$MAIN_REPO_ROOT/$HOME/.pmai/scripts/task-transition.py"
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
  local checker="$MAIN_REPO_ROOT/$HOME/.pmai/scripts/check-task-scope.py"
  if [ ! -f "$checker" ]; then
    python3 "$MAIN_REPO_ROOT/$HOME/.pmai/scripts/task-events.py" append "$TASK_FILE" \
      --type execution_failed \
      --note "I-AD2 violation: check-task-scope.py missing" 2>/dev/null || true
    echo "❌ 找不到 check-task-scope.py，I-AD2 越界校验 fail-closed" >&2
    return 2
  fi

  # 收集改动：worktree 内 unstaged + staged（adapter 约定 unstaged，但 Codex 偶尔会 stage）
  # diff HEAD 覆盖 tracked/staged；ls-files 覆盖 untracked。NUL → newline 后喂 checker。
  local changed_file
  changed_file=$(mktemp "${TMPDIR:-/tmp}/pmaiwf-scope.XXXXXX") || return 2
  if ! (
    cd "$TASK_WORKTREE" && {
      git diff --name-only -z HEAD -- 2>/dev/null
      git ls-files --others --exclude-standard -z 2>/dev/null
    } | python3 -c '
import sys
seen = []
for raw in sys.stdin.buffer.read().split(b"\0"):
    if not raw:
        continue
    path = raw.decode("utf-8", "surrogateescape")
    if path not in seen:
        seen.append(path)
print("\n".join(seen))
'
  ) >"$changed_file"; then
    rm -f "$changed_file"
    python3 "$MAIN_REPO_ROOT/$HOME/.pmai/scripts/task-events.py" append "$TASK_FILE" \
      --type execution_failed \
      --note "I-AD2 violation: failed to collect changed paths" 2>/dev/null || true
    echo "❌ I-AD2: 收集 worktree 改动失败。" >&2
    return 2
  fi
  if [ ! -s "$changed_file" ]; then
    # 零改动：让 task-execute 的零改动检查决定是否 --fail-execution
    rm -f "$changed_file"
    return "$executor_exit"
  fi

  if ! python3 "$checker" "$TASK_FILE" --paths-from "$changed_file"; then
    rm -f "$changed_file"
    # scope 越界 → 记 execution_failed，返回非零给 task-execute
    python3 "$MAIN_REPO_ROOT/$HOME/.pmai/scripts/task-events.py" append "$TASK_FILE" \
      --type execution_failed \
      --note "I-AD2 violation: diff 越界 allowlist" 2>/dev/null || true
    echo "" >&2
    echo "❌ I-AD2: 执行器写入范围越界 task 的 allowlist。" >&2
    echo "   代码已保留在 ${TASK_WORKTREE}，请人工检查或 /task-execute 带 --fail-execution 回退。" >&2
    return 2
  fi
  rm -f "$changed_file"

  return "$executor_exit"
}
