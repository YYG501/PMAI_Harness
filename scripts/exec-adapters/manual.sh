#!/usr/bin/env bash
# manual build adapter.
#
# It records a pending manual build marker and exits 0. /pmai-build should stop and
# resume checks after the PM finishes editing.

set -euo pipefail

source "$(dirname "$0")/_gate.sh"
adapter_precheck

BUILD_DIR_RESOLVED="$(adapter_build_dir)"
MAIN_REPO_ROOT="${MAIN_REPO_ROOT:-$BUILD_DIR_RESOLVED}"
MODULE_NAME="${MODULE_NAME:-manual-build}"
NOW="$(date -Iseconds)"
BASELINE_SHA="$(git -C "$BUILD_DIR_RESOLVED" rev-parse HEAD 2>/dev/null || echo unknown)"

mkdir -p "$MAIN_REPO_ROOT/.runs"
PENDING_FILE="$MAIN_REPO_ROOT/.runs/.pending-manual-build-${MODULE_NAME}.json"

cat > "$PENDING_FILE" <<EOF
{
  "module": "$MODULE_NAME",
  "build_dir": "$BUILD_DIR_RESOLVED",
  "executor": "manual",
  "started_at": "$NOW",
  "baseline_sha": "$BASELINE_SHA",
  "snoozed_until": null
}
EOF

cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Manual build 已登记

请在以下目录完成实现：
  $BUILD_DIR_RESOLVED/prototype

完成后重新进入 /pmai-build，我会跳过执行器并继续跑检查。
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
