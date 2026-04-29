#!/usr/bin/env bash
# run-bg.sh — 后台跑 <cmd>，stdout/stderr 重定向到 <log-path>，结束后
# 原子写 exit code 到 <log-path>.exit。
#
# Watchdog（默认开）：每 RUN_BG_WATCHDOG_INTERVAL 秒（默认 60）看一次 log size，
# 累计 RUN_BG_STALL_SECONDS 秒（默认 180）没增长就原子写 <log-path>.stall（内容
# 是 ISO-8601 UTC 时间戳）。不杀任何子进程，处理权交还 PM。
# 设 RUN_BG_STALL_SECONDS=0 关闭 watchdog。
#
# 调用方协议（见 task-execute/SKILL.md）：用 Bash run_in_background 起 waiter
#   until [ -f "$LOG.exit" ] || [ -f "$LOG.stall" ]; do sleep 60; done
#   if [ -f "$LOG.stall" ]; then echo "STALLED at $(cat "$LOG.stall")"
#   else echo "exit_code=$(cat "$LOG.exit")"; fi
# 不要用 Monitor —— Monitor 默认 5min 超时，长跑会被静默 cut。
#
# 不做：setsid/PGID、abort、hard timeout、kill 子进程。
set -uo pipefail

LOG="${1:?usage: run-bg.sh <log-path> <cmd...>}"
shift
[ "$#" -gt 0 ] || { echo "run-bg.sh: missing <cmd>" >&2; exit 2; }

EXIT_FILE="${LOG}.exit"
STALL_FILE="${LOG}.stall"
STALL_SECONDS="${RUN_BG_STALL_SECONDS:-180}"
WATCHDOG_INTERVAL="${RUN_BG_WATCHDOG_INTERVAL:-60}"
rm -f "$EXIT_FILE" "$STALL_FILE"
mkdir -p "$(dirname "$LOG")"
: > "$LOG"  # 确保 log 立刻可 stat，避免 watchdog 第一轮拿空值

(
  "$@" > "$LOG" 2>&1
  EC=$?
  echo "$EC" > "${EXIT_FILE}.tmp" && mv "${EXIT_FILE}.tmp" "$EXIT_FILE"
) </dev/null >/dev/null 2>&1 &
RUNNER_PID=$!
disown

if [ "$STALL_SECONDS" -gt 0 ]; then
  (
    last_size=$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')
    last_size="${last_size:-0}"
    stalled_for=0
    # LOG 守卫：调用方清场删 LOG（如测试 rm sandbox）→ watchdog 自杀
    while [ ! -f "$EXIT_FILE" ] && [ -f "$LOG" ]; do
      sleep "$WATCHDOG_INTERVAL"
      [ -f "$EXIT_FILE" ] && exit 0
      [ -f "$LOG" ] || exit 0
      cur_size=$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')
      cur_size="${cur_size:-0}"
      if [ "$cur_size" = "$last_size" ]; then
        stalled_for=$((stalled_for + WATCHDOG_INTERVAL))
        if [ "$stalled_for" -ge "$STALL_SECONDS" ]; then
          date -u +%FT%TZ > "${STALL_FILE}.tmp" && mv "${STALL_FILE}.tmp" "$STALL_FILE"
          exit 0
        fi
      else
        stalled_for=0
        last_size="$cur_size"
      fi
    done
  ) </dev/null >/dev/null 2>&1 &
  disown
fi

echo "PID=$RUNNER_PID"
echo "log:   $LOG"
echo "exit:  $EXIT_FILE"
echo "stall: $STALL_FILE"
