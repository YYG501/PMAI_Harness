#!/usr/bin/env bash
# Claude Code build adapter.
#
# WARNING: bypassPermissions has no sandbox. /pmai-build must run its
# post-execution changed-path review before accepting the result.

set -euo pipefail

source "$(dirname "$0")/_gate.sh"
adapter_precheck

BUILD_DIR_RESOLVED="$(adapter_build_dir)"
PROMPT="$(cat "$PROMPT_FILE")"
STATUS_DIR="${EXECUTOR_STATUS_DIR:-}"
TIMEOUT_SECONDS="${EXECUTOR_TIMEOUT_SECONDS:-0}"

MODEL_ARGS=()
[ -n "${EXECUTOR_MODEL:-}" ] && MODEL_ARGS=(--model "$EXECUTOR_MODEL")

write_status() {
  local state="$1"
  local exit_code="${2:-}"
  [ -n "$STATUS_DIR" ] || return 0
  mkdir -p "$STATUS_DIR"
  python3 - "$STATUS_DIR/status.json" "$state" "$exit_code" "$BUILD_DIR_RESOLVED" <<'PY_STATUS'
import json
import sys
from datetime import datetime, timezone

path, state, exit_code, build_dir = sys.argv[1:5]
payload = {
    "state": state,
    "build_dir": build_dir,
    "updated_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
}
if exit_code:
    payload["exit_code"] = int(exit_code)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY_STATUS
}

HEARTBEAT_PID=""
start_heartbeat() {
  [ -n "$STATUS_DIR" ] || return 0
  mkdir -p "$STATUS_DIR"
  (
    while true; do
      date +%s > "$STATUS_DIR/heartbeat"
      sleep 5
    done
  ) &
  HEARTBEAT_PID=$!
}

stop_heartbeat() {
  [ -n "$HEARTBEAT_PID" ] || return 0
  kill "$HEARTBEAT_PID" 2>/dev/null || true
  wait "$HEARTBEAT_PID" 2>/dev/null || true
  HEARTBEAT_PID=""
}

CHILD_PID=""
cleanup() {
  stop_heartbeat
}
trap cleanup EXIT
trap 'if [ -n "$CHILD_PID" ]; then kill "$CHILD_PID" 2>/dev/null || true; fi; write_status stopped 130; exit 130' INT TERM

write_status running
start_heartbeat

EXEC_EXIT=0
(
  cd "$BUILD_DIR_RESOLVED"
  claude -p \
    --permission-mode bypassPermissions \
    --output-format text \
    --no-session-persistence \
    ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} \
    "$PROMPT"
) &
CHILD_PID=$!
[ -n "$STATUS_DIR" ] && printf '%s\n' "$CHILD_PID" > "$STATUS_DIR/pid"

TIMED_OUT=0
case "$TIMEOUT_SECONDS" in
  ""|*[!0-9]*) TIMEOUT_SECONDS=0 ;;
esac

if [ "$TIMEOUT_SECONDS" -gt 0 ] 2>/dev/null; then
  STARTED_AT=$(date +%s)
  while kill -0 "$CHILD_PID" 2>/dev/null; do
    NOW=$(date +%s)
    if [ $((NOW - STARTED_AT)) -ge "$TIMEOUT_SECONDS" ]; then
      TIMED_OUT=1
      kill "$CHILD_PID" 2>/dev/null || true
      wait "$CHILD_PID" 2>/dev/null || true
      EXEC_EXIT=124
      break
    fi
    sleep 2
  done
fi

if [ "$TIMED_OUT" -eq 0 ]; then
  wait "$CHILD_PID" || EXEC_EXIT=$?
fi

if [ -n "$STATUS_DIR" ]; then
  printf '%s\n' "$EXEC_EXIT" > "$STATUS_DIR/exit"
  if [ "$TIMED_OUT" -eq 1 ]; then
    write_status timed_out "$EXEC_EXIT"
  elif [ "$EXEC_EXIT" -eq 0 ]; then
    write_status completed "$EXEC_EXIT"
  else
    write_status failed "$EXEC_EXIT"
  fi
fi

adapter_postcheck "$EXEC_EXIT"
