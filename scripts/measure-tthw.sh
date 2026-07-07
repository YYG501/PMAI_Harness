#!/usr/bin/env bash
# measure-tthw.sh — PMAI developer-experience timing helper.
#
# Two lanes are intentionally separate:
#   1. smoke  = automated skeleton timing (init-project.sh + status-view.py)
#   2. record = human dogfood timing for the first module spec

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMEWORK_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/measure-tthw.sh smoke [--project-name NAME] [--target-dir DIR] [--background TEXT] [--intent prototype|system|custom|unknown]
  bash scripts/measure-tthw.sh record <project-dir> --module NAME --started-at ISO --ended-at ISO [--spec PATH] [--note TEXT]

Modes:
  smoke
    Measures the automated skeleton path only:
      init-project.sh -> status-view.py --narrative

  record
    Appends one human dogfood timing record to:
      <project-dir>/.pm-workflow/audits/tthw.jsonl

Notes:
  The first module spec includes PM decisions. Do not fake that with a
  non-interactive script; use record mode after a real /pmai-init-project ->
  /pmai-design run.
EOF
}

mode="${1:-smoke}"
if [ "$mode" = "--help" ] || [ "$mode" = "-h" ]; then
  usage
  exit 0
fi
shift || true

run_smoke() {
  local project_name="PMAI-TTHW-Smoke"
  local target_dir=""
  local background="TTHW skeleton smoke project"
  local intent="prototype"
  local cleanup_dir=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --project-name) project_name="${2:?--project-name needs value}"; shift 2 ;;
      --target-dir) target_dir="${2:?--target-dir needs value}"; shift 2 ;;
      --background) background="${2:?--background needs value}"; shift 2 ;;
      --intent) intent="${2:?--intent needs value}"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) echo "❌ unknown smoke flag: $1" >&2; usage >&2; exit 2 ;;
    esac
  done

  case "$intent" in
    prototype|system|custom|unknown) ;;
    *) echo "❌ intent 非法: $intent（必须是 prototype/system/custom/unknown）" >&2; exit 2 ;;
  esac

  if [ -z "$target_dir" ]; then
    cleanup_dir=$(mktemp -d "${TMPDIR:-/tmp}/pmai-tthw.XXXXXX")
    target_dir="$cleanup_dir/$project_name"
  fi

  local started ended elapsed log_file
  log_file="${TMPDIR:-/tmp}/pmai-measure-tthw.$$.log"
  started=$(date +%s)
  if ! bash "$FRAMEWORK_DIR/scripts/init-project.sh" "$project_name" "$target_dir" "$background" "$intent" >"$log_file" 2>&1; then
    echo "❌ skeleton smoke failed during init-project.sh" >&2
    echo "   log: $log_file" >&2
    tail -20 "$log_file" >&2 || true
    exit 1
  fi
  if ! python3 "$FRAMEWORK_DIR/scripts/status-view.py" "$target_dir" --narrative >>"$log_file" 2>&1; then
    echo "❌ skeleton smoke failed during status-view.py --narrative" >&2
    echo "   log: $log_file" >&2
    tail -20 "$log_file" >&2 || true
    exit 1
  fi
  ended=$(date +%s)
  elapsed=$((ended - started))

  echo "PMAI TTHW skeleton smoke"
  echo "  target: $target_dir"
  echo "  log: $log_file"
  echo "TTHW_SKELETON_SECONDS=$elapsed"
  echo "TTHW_TARGET_SECONDS=10"
  if [ "$elapsed" -le 10 ]; then
    echo "TTHW_SKELETON_STATUS=pass"
  else
    echo "TTHW_SKELETON_STATUS=slow"
  fi

  if [ -n "$cleanup_dir" ]; then
    rm -rf "$cleanup_dir"
  fi
}

record_dogfood() {
  if [ $# -lt 1 ]; then
    echo "❌ record 缺少 <project-dir>" >&2
    usage >&2
    exit 2
  fi

  local project_dir="$1"
  shift
  local module=""
  local started_at=""
  local ended_at=""
  local spec=""
  local note=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --module) module="${2:?--module needs value}"; shift 2 ;;
      --started-at) started_at="${2:?--started-at needs value}"; shift 2 ;;
      --ended-at) ended_at="${2:?--ended-at needs value}"; shift 2 ;;
      --spec) spec="${2:?--spec needs value}"; shift 2 ;;
      --note) note="${2:?--note needs value}"; shift 2 ;;
      --help|-h) usage; exit 0 ;;
      *) echo "❌ unknown record flag: $1" >&2; usage >&2; exit 2 ;;
    esac
  done

  if [ ! -d "$project_dir" ]; then
    echo "❌ project-dir 不存在: $project_dir" >&2
    exit 2
  fi
  if [ -z "$module" ] || [ -z "$started_at" ] || [ -z "$ended_at" ]; then
    echo "❌ record 需要 --module、--started-at、--ended-at" >&2
    usage >&2
    exit 2
  fi

  if [ -z "$spec" ]; then
    spec="docs/modules/$module/spec.md"
  fi

  python3 - "$project_dir" "$module" "$started_at" "$ended_at" "$spec" "$note" <<'PY'
from __future__ import annotations

import json
import sys
from datetime import datetime
from pathlib import Path

project_dir = Path(sys.argv[1]).resolve()
module = sys.argv[2]
started_raw = sys.argv[3]
ended_raw = sys.argv[4]
spec_raw = sys.argv[5]
note = sys.argv[6]


def parse_iso(value: str) -> datetime:
    normalized = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise SystemExit(f"❌ 时间格式不可读: {value}（请用 ISO，如 2026-07-07T10:00:00+08:00）") from exc


started = parse_iso(started_raw)
ended = parse_iso(ended_raw)
duration_s = int((ended - started).total_seconds())
if duration_s < 0:
    raise SystemExit("❌ ended-at 早于 started-at")

spec_path = Path(spec_raw)
if not spec_path.is_absolute():
    spec_path = project_dir / spec_path

audit_dir = project_dir / ".pm-workflow" / "audits"
audit_dir.mkdir(parents=True, exist_ok=True)
log_path = audit_dir / "tthw.jsonl"

record = {
    "kind": "first_module_spec",
    "module": module,
    "started_at": started_raw,
    "ended_at": ended_raw,
    "duration_s": duration_s,
    "duration_min": round(duration_s / 60, 2),
    "target_min": 30,
    "spec_path": str(spec_path.relative_to(project_dir)) if spec_path.is_relative_to(project_dir) else str(spec_path),
    "spec_exists": spec_path.is_file(),
}
if note:
    record["note"] = note

with log_path.open("a", encoding="utf-8") as fh:
    fh.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")

print(f"TTHW_DOGFOOD_LOG={log_path}")
print(f"TTHW_FIRST_SPEC_SECONDS={duration_s}")
print(f"TTHW_FIRST_SPEC_MINUTES={record['duration_min']}")
print(f"TTHW_FIRST_SPEC_SPEC_EXISTS={'1' if record['spec_exists'] else '0'}")
PY
}

case "$mode" in
  smoke) run_smoke "$@" ;;
  record) record_dogfood "$@" ;;
  *)
    echo "❌ unknown mode: $mode" >&2
    usage >&2
    exit 2
    ;;
esac
