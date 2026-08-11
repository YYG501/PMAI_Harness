# shellcheck shell=bash
# Shared helpers for build executor adapters.
#
# Required env vars:
#   PROMPT_FILE
#   BUILD_DIR or TASK_WORKTREE (legacy env name accepted by /pmai-build while callers migrate)

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

adapter_prompt() {
  cat <<'EOF'
你是 PMAI 调用的外部 Builder，只负责按已确认范围实现代码并报告结果。
不要调用 PMAI Skill，不要推进 lifecycle，不要写验收通过、landing 或文档完成状态，
不要修改 .pm-workflow、.runs 或 docs/modules/*/.work-meta.json。所有验收、状态推进和合入由主控完成。

以下是本轮实现任务：
EOF
  cat "$PROMPT_FILE"
}

adapter_postcheck() {
  local executor_exit="${1:-0}"
  return "$executor_exit"
}

adapter_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}
