#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMING="$FRAMEWORK_ROOT/scripts/build-timing.py"

test_timing_records_phases_and_non_blocking_preview_warning() {
  start_test "build-timing: records phase duration and warns when time-to-preview misses target"
  local t audit summary
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-build-timing-test.XXXXXX")
  audit="$t/timing.json"
  python3 "$TIMING" start --audit-file "$audit" --id preview-1 \
    --phase preview --kind minor \
    --started-at "2026-07-17T10:01:00+08:00" \
    --feedback-at "2026-07-17T10:00:00+08:00" >/dev/null
  if ! python3 "$TIMING" finish --audit-file "$audit" --id preview-1 \
    --ended-at "2026-07-17T10:06:00+08:00" --preview-ready \
    >/tmp/build-timing.$$ 2>/tmp/build-timing.err.$$; then
    _fail "preview warning must not fail the timing command"
    cat /tmp/build-timing.err.$$ >&2
    rm -rf "$t"; return
  fi
  python3 "$TIMING" start --audit-file "$audit" --id build-1 \
    --phase production-build --kind final \
    --started-at "2026-07-17T10:10:00+08:00" >/dev/null
  python3 "$TIMING" finish --audit-file "$audit" --id build-1 \
    --ended-at "2026-07-17T10:12:30+08:00" >/dev/null
  python3 "$TIMING" start --audit-file "$audit" --id final-1 \
    --phase final-validation --kind final \
    --started-at "2026-07-17T10:13:00+08:00" >/dev/null
  python3 "$TIMING" finish --audit-file "$audit" --id final-1 --status fail \
    --reason "production build found a real defect" \
    --ended-at "2026-07-17T10:14:00+08:00" >/dev/null
  summary=$(python3 "$TIMING" summary --audit-file "$audit")
  if python3 - "$audit" "$summary" <<'PY'
import json, sys
summary = json.loads(sys.argv[2])
audit = json.load(open(sys.argv[1]))
preview = audit["entries"][0]
assert preview["duration_seconds"] == 300
assert preview["time_to_preview_seconds"] == 360
assert "超过 5 分钟目标" in preview["warning"]
assert summary["phase_seconds"]["preview"] == 300
assert summary["phase_seconds"]["production-build"] == 150
assert summary["previews"][0]["seconds"] == 360
assert summary["normal_path"]["status"] == "exited"
assert summary["normal_path"]["exit_reasons"] == [{
    "phase": "final-validation",
    "reason": "production build found a real defect",
}]
PY
  then
    pass_test
  else
    _fail "timing audit or summary mismatch"
    cat "$audit" >&2
  fi
  rm -f /tmp/build-timing.$$ /tmp/build-timing.err.$$
  rm -rf "$t"
}

test_finalization_timing_requires_every_phase_to_pass() {
  start_test "build-timing: finalization completeness rejects missing or running phases"
  local t audit
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-build-timing-final.XXXXXX")
  audit="$t/timing.json"
  python3 "$TIMING" start --audit-file "$audit" --id current-1 \
    --phase currentness --kind final >/dev/null
  python3 "$TIMING" finish --audit-file "$audit" --id current-1 >/dev/null
  if python3 "$TIMING" validate-finalization --audit-file "$audit" \
    --required-phase currentness --required-phase landing \
    >/tmp/build-timing.$$ 2>/tmp/build-timing.err.$$; then
    _fail "missing landing phase should fail completeness validation"
    rm -rf "$t"; return
  fi
  python3 "$TIMING" start --audit-file "$audit" --id landing-1 \
    --phase landing --kind final >/dev/null
  if python3 "$TIMING" validate-finalization --audit-file "$audit" \
    --required-phase currentness --required-phase landing \
    >/tmp/build-timing.$$ 2>/tmp/build-timing.err.$$; then
    _fail "running landing phase should fail completeness validation"
    rm -rf "$t"; return
  fi
  python3 "$TIMING" finish --audit-file "$audit" --id landing-1 >/dev/null
  if python3 "$TIMING" validate-finalization --audit-file "$audit" \
    --required-phase currentness --required-phase landing \
    >/tmp/build-timing.$$ 2>/tmp/build-timing.err.$$; then
    pass_test
  else
    _fail "all required passing phases should satisfy completeness validation"
    cat /tmp/build-timing.err.$$ >&2
  fi
  rm -f /tmp/build-timing.$$ /tmp/build-timing.err.$$
  rm -rf "$t"
}

test_timing_records_phases_and_non_blocking_preview_warning
test_finalization_timing_requires_every_phase_to_pass
report_results "build-timing"
