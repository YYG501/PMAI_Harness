#!/usr/bin/env bash
# Classify executor adapter failure based on exit code and log content.
#
# Usage: classify-failure.sh <exit_code> [<log_path>]
# Output: one of: sandbox_denied | model_not_found | network | boundary_violation | no_changes | unknown
#
# Exit code mapping (adapters follow this convention):
#   0         success (classify-failure shouldn't be called)
#   10        sandbox_denied
#   11        model_not_found
#   12        network / rate limit
#   *         unknown (fall back to log keyword scan)

set -euo pipefail

EXIT_CODE="${1:-}"
LOG_PATH="${2:-}"

if [ -z "$EXIT_CODE" ]; then
  echo "Usage: $0 <exit_code> [<log_path>]" >&2
  exit 2
fi

case "$EXIT_CODE" in
  10) echo "sandbox_denied"; exit 0 ;;
  11) echo "model_not_found"; exit 0 ;;
  12) echo "network"; exit 0 ;;
esac

# Fallback: scan log for keywords.
# 原则：exit 10/11/12 是精准信号；这里是兜底分类，宁可漏判（落 unknown）
# 也别假阳性。所以关键词必须是"真错误短语"，不能是 CLI 参数名（"sandbox" /
# "workspace-write" 单独出现几乎一定是 `--sandbox workspace-write` 命令行回显，
# 不是错误本体）。
if [ -n "$LOG_PATH" ] && [ -f "$LOG_PATH" ]; then
  if grep -qiE "sandbox[[:space:]]+(denied|violation|error|blocked|rejected)|(denied|blocked|rejected)[[:space:]]+by[[:space:]]+sandbox|permission denied|operation not permitted|EACCES" "$LOG_PATH"; then
    echo "sandbox_denied"
    exit 0
  fi
  if grep -qiE "model not found|invalid model|model unavailable|unauthorized" "$LOG_PATH"; then
    echo "model_not_found"
    exit 0
  fi
  if grep -qiE "rate limit|429|network|connection refused|timeout" "$LOG_PATH"; then
    echo "network"
    exit 0
  fi
fi

echo "unknown"
