#!/usr/bin/env bash
set -uo pipefail

# 六步重构后的 req-transition 测试：per-req 四阶段
#   1 范围确认（前置产物 req-plan.md）→ 2 build → 3 复审 → 4 沉淀
# build / 复审 无法定文档前置（闸门靠 PM 验收 + task demo 确认）；
# 沉淀（4）= merge 回 main 不可回退；复审（3）回退要求 task 都已确认/取消。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

REQ_TRANSITION="$FRAMEWORK_ROOT/scripts/req-transition.py"

_run_req() {
  (cd "$FIXTURE_DIR" && python3 "$REQ_TRANSITION" "$@")
}

# -----------------------------------------------------------------
# I-RT1: cannot skip stages on forward transition
# -----------------------------------------------------------------

test_reject_cross_level_forward() {
  start_test "I-RT1 reject forward 1 → 3 (cross-level)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 1)

  if _run_req "$req_dir" --to 3 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject cross-level forward"
  else
    if grep -qE "(advance|stage)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing stage-advance message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_stage_too_high() {
  start_test "I-RT1 reject forward to stage > 4 (MAX_STAGE)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)

  if _run_req "$req_dir" --to 5 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject target > 4"
  else
    if grep -qE "(Max is 4|invalid stage)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing max-stage message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-RT3: forward transition requires prerequisite output file
#         六步：只有 stage 1「范围确认」有法定前置 = req-plan.md
# -----------------------------------------------------------------

test_reject_stage1_to_2_no_req_plan() {
  start_test "I-RT3 reject 1→2 when req-plan.md missing"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 1)
  rm -f "$req_dir/req-plan.md"  # 确保范围确认产物缺失

  if _run_req "$req_dir" --to 2 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when req-plan.md missing"
  else
    if grep -q "req-plan.md" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing req-plan.md message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_happy_path_1_to_2() {
  start_test "happy path: 1 → 2 succeeds with req-plan.md, stage_history appended"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 1)
  echo "# req-plan" > "$req_dir/req-plan.md"

  if ! _run_req "$req_dir" --to 2 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "forward 1→2 failed"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  new_stage=$(python3 -c "import json; print(json.load(open('$req_dir/.req-meta.json'))['stage'])")
  if [ "$new_stage" != "2" ]; then
    _fail "stage not updated to 2 (got $new_stage)"
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  hist_len=$(python3 -c "import json; print(len(json.load(open('$req_dir/.req-meta.json'))['stage_history']))")
  if [ "$hist_len" -lt 2 ]; then
    _fail "stage_history not appended (len=$hist_len)"
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  last_entry=$(python3 -c "import json; h = json.load(open('$req_dir/.req-meta.json'))['stage_history'][-1]; print(h.get('direction'), h.get('from_stage'), h.get('stage'))")
  if [ "$last_entry" != "forward 1 2" ]; then
    _fail "last stage_history entry wrong: $last_entry"
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_build_and_review_advance_no_file_gate() {
  start_test "六步：build(2)→复审(3)→沉淀(4) 无文档前置、可顺推"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 2)

  ok=1
  _run_req "$req_dir" --to 3 >/tmp/out.$$ 2>/tmp/err.$$ || ok=0
  if [ "$ok" = "1" ]; then
    _run_req "$req_dir" --to 4 >/tmp/out.$$ 2>/tmp/err.$$ || ok=0
  fi
  if [ "$ok" = "1" ]; then
    new_stage=$(python3 -c "import json; print(json.load(open('$req_dir/.req-meta.json'))['stage'])")
    [ "$new_stage" = "4" ] && pass_test || _fail "顺推后 stage 应=4，实际=$new_stage"
  else
    _fail "build/复审 不该有文档前置卡推进"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-RT4: 沉淀（4）= merge 回 main 不可回退
# -----------------------------------------------------------------

test_reject_rollback_from_settle() {
  start_test "I-RT4 reject rollback from stage 4（沉淀，不可逆）"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 4)

  if _run_req "$req_dir" --to 3 --rollback >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject rollback from stage 4"
  else
    if grep -qE "(沉淀|irreversible|stage 4)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing 沉淀-irreversible message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-RT5: 复审（3）可按普通回退规则退到 build（2）
# -----------------------------------------------------------------

test_allow_rollback_from_review_to_build() {
  start_test "I-RT5 allow rollback from 3（复审）to 2（build）"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)

  if _run_req "$req_dir" --to 2 --rollback >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "should allow rollback from review to build"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-RT6: rollback bounds
# -----------------------------------------------------------------

test_reject_rollback_to_zero() {
  start_test "I-RT6 reject rollback to stage 0"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 2)

  if _run_req "$req_dir" --to 0 --rollback >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject rollback to 0"
  else
    if grep -qE "(Min is 1|invalid stage)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing bounds message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_rollback_negative() {
  start_test "I-RT6 reject rollback to negative stage"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 2)

  if _run_req "$req_dir" --to -1 --rollback >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject rollback to negative"
  else
    pass_test
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_rollback_target_ge_current() {
  start_test "I-RT6 reject rollback when target >= current"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)

  if _run_req "$req_dir" --to 3 --rollback >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject rollback with target == current"
  else
    if grep -q "backward" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing backward message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_2_to_4_skip_review() {
  start_test "I-RT1 reject 2→4 (skip 复审 3) — 不可跳级"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 2)

  if _run_req "$req_dir" --to 4 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject 2→4 (skip stage 3)"
  else
    if grep -qE "(advance|stage)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing stage-advance message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_reject_cross_level_forward
test_reject_stage_too_high
test_reject_stage1_to_2_no_req_plan
test_happy_path_1_to_2
test_build_and_review_advance_no_file_gate
test_reject_rollback_from_settle
test_allow_rollback_from_review_to_build
test_reject_rollback_to_zero
test_reject_rollback_negative
test_reject_rollback_target_ge_current
test_reject_2_to_4_skip_review

report_results "req-transition"
