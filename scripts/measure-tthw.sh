#!/usr/bin/env bash
# measure-tthw.sh — measure time from init-project to first status-view-visible req.
set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  bash scripts/measure-tthw.sh [options]

参数:
  --threshold-seconds <n>  总 TTHW 阈值，默认 60
  --project-name <name>    临时项目名，默认 TTHWDemo
  --intent <intent>        init-project project-intent，默认 prototype
  --title <text>           headless req 标题
  --brief <text>           headless req brief 内容
  --keep                   保留临时项目，便于调试
  -h, --help               显示帮助

输出:
  stdout 输出 JSON：
    init_seconds / first_requirement_seconds / total_tthw_seconds / artifact
EOF
}

die() {
  echo "❌ $*" >&2
  exit 2
}

need_value() {
  local flag="$1"
  local value="${2:-}"
  [ -n "$value" ] || die "$flag 需要参数值"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

THRESHOLD_SECONDS="60"
PROJECT_NAME="TTHWDemo"
PROJECT_INTENT="prototype"
REQ_TITLE="DX smoke requirement"
REQ_BRIEF="Build a minimal demo flow"
KEEP=false
RUN_ROOT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --threshold-seconds)
      need_value "$1" "${2:-}"
      THRESHOLD_SECONDS="$2"
      shift 2
      ;;
    --project-name)
      need_value "$1" "${2:-}"
      PROJECT_NAME="$2"
      shift 2
      ;;
    --intent)
      need_value "$1" "${2:-}"
      PROJECT_INTENT="$2"
      shift 2
      ;;
    --title)
      need_value "$1" "${2:-}"
      REQ_TITLE="$2"
      shift 2
      ;;
    --brief)
      need_value "$1" "${2:-}"
      REQ_BRIEF="$2"
      shift 2
      ;;
    --keep)
      KEEP=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数: $1"
      ;;
  esac
done

cleanup() {
  if [ "$KEEP" != true ] && [ -n "$RUN_ROOT" ] && [ -d "$RUN_ROOT" ]; then
    rm -rf "$RUN_ROOT"
  fi
}
trap cleanup EXIT

now_ms() {
  python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
}

seconds_between() {
  python3 - "$1" "$2" <<'PY'
import sys
start = int(sys.argv[1])
end = int(sys.argv[2])
print(f"{(end - start) / 1000:.3f}")
PY
}

json_get() {
  python3 - "$1" "$2" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
value = data
for part in sys.argv[2].split("."):
    value = value[part]
print(value)
PY
}

RUN_ROOT="$(mktemp -d)"
TARGET_DIR="$RUN_ROOT/$PROJECT_NAME"
INIT_LOG="$RUN_ROOT/init.log"
REQ_JSON="$RUN_ROOT/req.json"
REQ_LOG="$RUN_ROOT/create-req.log"
STATUS_LOG="$RUN_ROOT/status-view.log"

T0="$(now_ms)"
if ! bash "$FRAMEWORK_ROOT/scripts/init-project.sh" \
  "$PROJECT_NAME" "$TARGET_DIR" "TTHW smoke project" "$PROJECT_INTENT" \
  >"$INIT_LOG" 2>&1; then
  cat "$INIT_LOG" >&2
  exit 1
fi
T1="$(now_ms)"

if ! (
  cd "$TARGET_DIR"
  bash .claude/scripts/create-req-headless.sh \
    --title "$REQ_TITLE" \
    --brief "$REQ_BRIEF"
) >"$REQ_JSON" 2>"$REQ_LOG"; then
  cat "$REQ_LOG" >&2
  exit 1
fi
T2="$(now_ms)"

if ! (
  cd "$TARGET_DIR"
  python3 .claude/scripts/status-view.py
) >"$STATUS_LOG" 2>&1; then
  cat "$STATUS_LOG" >&2
  exit 1
fi
if grep -q "没有活跃的需求" "$STATUS_LOG"; then
  cat "$STATUS_LOG" >&2
  exit 1
fi

REQ_DIR="$(json_get "$REQ_JSON" req_dir)"
BRIEF_PATH="$(json_get "$REQ_JSON" brief_path)"
[ -d "$REQ_DIR" ] || die "headless req_dir 不存在: $REQ_DIR"
[ -f "$BRIEF_PATH" ] || die "headless brief 不存在: $BRIEF_PATH"

INIT_SECONDS="$(seconds_between "$T0" "$T1")"
FIRST_REQ_SECONDS="$(seconds_between "$T1" "$T2")"
TOTAL_SECONDS="$(seconds_between "$T0" "$T2")"

STATUS="pass"
if ! python3 - "$TOTAL_SECONDS" "$THRESHOLD_SECONDS" <<'PY'
import sys
total = float(sys.argv[1])
threshold = float(sys.argv[2])
raise SystemExit(0 if total <= threshold else 1)
PY
then
  STATUS="fail"
fi

STATUS="$STATUS" \
INIT_SECONDS="$INIT_SECONDS" \
FIRST_REQ_SECONDS="$FIRST_REQ_SECONDS" \
TOTAL_SECONDS="$TOTAL_SECONDS" \
THRESHOLD_SECONDS="$THRESHOLD_SECONDS" \
RUN_ROOT="$RUN_ROOT" \
PROJECT_DIR="$TARGET_DIR" \
REQ_JSON="$REQ_JSON" \
STATUS_LOG="$STATUS_LOG" \
python3 - <<'PY'
import json
import os

with open(os.environ["REQ_JSON"], encoding="utf-8") as f:
    req = json.load(f)

payload = {
    "status": os.environ["STATUS"],
    "init_seconds": float(os.environ["INIT_SECONDS"]),
    "first_requirement_seconds": float(os.environ["FIRST_REQ_SECONDS"]),
    "total_tthw_seconds": float(os.environ["TOTAL_SECONDS"]),
    "threshold_seconds": float(os.environ["THRESHOLD_SECONDS"]),
    "run_root": os.environ["RUN_ROOT"],
    "project_dir": os.environ["PROJECT_DIR"],
    "worktree": req["worktree"],
    "artifact": req["brief_path"],
    "req_id": req["req_id"],
    "branch": req["branch"],
}
print(json.dumps(payload, ensure_ascii=False, indent=2))
PY

[ "$STATUS" = "pass" ]
