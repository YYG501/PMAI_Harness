# shellcheck shell=bash
# Shared helpers for build executor adapters.
#
# Required env vars:
#   PROMPT_FILE
#   BUILD_DIR or TASK_WORKTREE (legacy env name accepted by /build while callers migrate)

adapter_build_dir() {
  local dir="${BUILD_DIR:-${TASK_WORKTREE:-}}"
  [ -n "$dir" ] || {
    echo "❌ adapter gate 拒绝：BUILD_DIR required" >&2
    exit 1
  }
  [ -d "$dir" ] || {
    echo "❌ adapter gate 拒绝：BUILD_DIR 不存在：$dir" >&2
    exit 1
  }
  printf '%s\n' "$dir"
}

adapter_precheck() {
  : "${PROMPT_FILE:?adapter_precheck requires PROMPT_FILE}"
  [ -f "$PROMPT_FILE" ] || {
    echo "❌ adapter gate 拒绝：PROMPT_FILE 不存在：$PROMPT_FILE" >&2
    exit 1
  }
  adapter_build_dir >/dev/null
}

adapter_postcheck() {
  local executor_exit="${1:-0}"
  return "$executor_exit"
}
