#!/usr/bin/env bash
# run-bg.sh — 后台跑 <cmd>，stdout/stderr 重定向到 <log-path>，结束后
# 原子写 exit code 到 <log-path>.exit。
#
# 这是逃生工具，不是默认协议。当 task-execute 的同步 dispatch 撞上
# Bash tool 10 分钟 timeout 时，调用方手动改用本工具：
#
#   bash run-bg.sh "$LOG" bash "$ADAPTER"
#   # Claude 用 Monitor 等 .exit 文件出现：
#   #   until [ -f "$LOG.exit" ]; do sleep 60; done && cat "$LOG.exit"
#
# 不做：setsid/PGID、abort、hard timeout、自动协议化。
set -uo pipefail

LOG="${1:?usage: run-bg.sh <log-path> <cmd...>}"
shift
[ "$#" -gt 0 ] || { echo "run-bg.sh: missing <cmd>" >&2; exit 2; }

EXIT_FILE="${LOG}.exit"
rm -f "$EXIT_FILE"
mkdir -p "$(dirname "$LOG")"

(
  "$@" > "$LOG" 2>&1
  EC=$?
  echo "$EC" > "${EXIT_FILE}.tmp" && mv "${EXIT_FILE}.tmp" "$EXIT_FILE"
) </dev/null >/dev/null 2>&1 &
disown

echo "PID=$!"
echo "log:  $LOG"
echo "exit: $EXIT_FILE"
