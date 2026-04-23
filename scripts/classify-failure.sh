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

# Fallback: scan log for keywords
if [ -n "$LOG_PATH" ] && [ -f "$LOG_PATH" ]; then
  if grep -qiE "sandbox|permission denied|workspace-write" "$LOG_PATH"; then
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
