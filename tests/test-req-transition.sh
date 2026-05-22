#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

REQ_TRANSITION="$FRAMEWORK_ROOT/scripts/req-transition.py"

_run_req() {
  (cd "$FIXTURE_DIR" && python3 "$REQ_TRANSITION" "$@")
}

_set_meta_stage() {
  # Directly rewrite the meta stage without using the transition script
  local req_dir="$1"
  local stage="$2"
  python3 - "$req_dir" "$stage" <<'PY'
import json, sys
from pathlib import Path
req_dir = Path(sys.argv[1])
stage = int(sys.argv[2])
mf = req_dir / ".req-meta.json"
meta = json.loads(mf.read_text(encoding="utf-8"))
meta["stage"] = stage
mf.write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
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
  start_test "I-RT1 reject forward to stage > 7"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)

  if _run_req "$req_dir" --to 8 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject target > 7"
  else
    pass_test
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-RT3: forward transition requires prerequisite output file
# -----------------------------------------------------------------

test_reject_stage1_to_2_no_brief() {
  start_test "I-RT3 reject 1→2 when brief.md missing"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 1)
  # Remove brief.md (fixture created it)
  rm -f "$req_dir/brief.md"

  if _run_req "$req_dir" --to 2 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when brief.md missing"
  else
    if grep -q "brief.md" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing brief.md message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-RT4: cannot rollback from stage 7
# -----------------------------------------------------------------

test_reject_rollback_from_stage7() {
  start_test "I-RT4 reject rollback from stage 7"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 7)

  if _run_req "$req_dir" --to 6 --rollback >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject rollback from stage 7"
  else
    if grep -qE "(stage 7|irreversible|不可逆)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing stage-7 message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-RT5: stage 6 rollback requires no active tasks
# -----------------------------------------------------------------

test_reject_rollback_from_stage6_with_active_task() {
  start_test "I-RT5 reject rollback from stage 6 with active task"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  fixture_create_task "$req_dir" "001" "live" "执行中" >/dev/null

  if _run_req "$req_dir" --to 5 --rollback >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject rollback with active task"
  else
    if grep -qE "(open tasks|active|执行中)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing active-task message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_allow_rollback_from_stage6_all_closed() {
  start_test "I-RT5 allow rollback from 6 when all tasks 已完成"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 6)
  fixture_create_task "$req_dir" "001" "done" "已完成" >/dev/null

  if _run_req "$req_dir" --to 5 --rollback >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "should allow rollback when all closed"
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

test_reject_rollback_target_greater() {
  start_test "I-RT6 reject rollback when target > current"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)

  if _run_req "$req_dir" --to 5 --rollback >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject rollback with target > current"
  else
    pass_test
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# Happy path: 1 → 2 with brief.md
# -----------------------------------------------------------------

test_happy_path_1_to_2() {
  start_test "happy path: 1 → 2 succeeds with brief.md, stage_history appended"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 1)
  # fixture already created brief.md

  if ! _run_req "$req_dir" --to 2 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "forward 1→2 failed"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # Verify meta updated
  new_stage=$(python3 -c "import json; print(json.load(open('$req_dir/.req-meta.json'))['stage'])")
  if [ "$new_stage" != "2" ]; then
    _fail "stage not updated to 2 (got $new_stage)"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # Verify stage_history appended
  hist_len=$(python3 -c "import json; print(len(json.load(open('$req_dir/.req-meta.json'))['stage_history']))")
  if [ "$hist_len" -lt 2 ]; then
    _fail "stage_history not appended (len=$hist_len)"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  # Verify direction + from_stage
  last_entry=$(python3 -c "import json; h = json.load(open('$req_dir/.req-meta.json'))['stage_history'][-1]; print(h.get('direction'), h.get('from_stage'), h.get('stage'))")
  if [ "$last_entry" != "forward 1 2" ]; then
    _fail "last stage_history entry wrong: $last_entry"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown
    return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# I-RT4: stage 3→5 requires DESIGN.md content regardless of is_first
# -----------------------------------------------------------------

test_reject_3_to_5_when_design_empty_non_first() {
  start_test "I-RT4 reject 3→5 when DESIGN.md empty (even for non-first req)"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3 false)

  # 确保 stage 3 的前置输出 solution.md 存在（不是 DESIGN.md；是 req 内的方案设计文档）
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    echo "# Solution" > "requirements/active/req-001-test/solution.md"
    git add -A && git commit -q -m "add solution.md"
  )

  # docs/DESIGN.md 是空的（fixture_setup 用 touch 创建）
  if _run_req "$req_dir" --to 5 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject 3→5 when DESIGN.md empty"
  else
    if grep -q "DESIGN.md" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing DESIGN.md message"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_2_to_4_skip_stage3_non_first() {
  start_test "I-RT2 reject 2→4 (skip stage 3) for non-first req — stage 3 不再可跳"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 2 false)
  # 制造 stage 2 的产出文件 analysis.md（前置条件）
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    echo "# Analysis" > "requirements/active/req-001-test/analysis.md"
    git add -A && git commit -q -m "add analysis.md"
  )

  if _run_req "$req_dir" --to 4 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject 2→4 (stage 3 不可跳)"
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

test_allow_3_to_5_when_design_populated() {
  start_test "I-RT4 allow 3→5 when DESIGN.md has content"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3 false)

  # 在 req worktree 里补 solution.md 和 docs/DESIGN.md 内容
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    echo "# Solution" > "requirements/active/req-001-test/solution.md"
    cat > docs/DESIGN.md <<'EOF'
# 设计系统

## 颜色
- primary: #000
- secondary: #fff

## 字体
- 标题: Inter 24px
- 正文: Inter 16px

## 间距
- base: 8px
EOF
    git add -A && git commit -q -m "populate design"
  )

  if _run_req "$req_dir" --to 5 >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "should allow 3→5 when DESIGN.md populated"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# -----------------------------------------------------------------
# delta-2+4 E3: stage 3 换芯（solution.md → prd.md）文件存在性新旧判别
# -----------------------------------------------------------------

test_stage3_to_4_new_flow_prd() {
  start_test "delta-2+4 E3: stage 3 有 prd.md → --to 4 走新流程成功"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)
  echo "# PRD" > "$req_dir/prd.md"

  if _run_req "$req_dir" --to 4 >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "stage 3（有 prd.md）→ 4 应成功"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_stage3_to_4_legacy_flow_solution() {
  start_test "delta-2+4 E3: 在飞旧 req（有 solution.md 无 prd.md）→ --to 4 走旧流程成功"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)
  echo "# Solution" > "$req_dir/solution.md"

  if _run_req "$req_dir" --to 4 >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "在飞旧 req（solution.md）→ 4 应走旧流程成功"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_stage3_to_4_missing_both_rejected() {
  start_test "delta-2+4 E3: stage 3 既无 prd.md 也无 solution.md → --to 4 拒绝"
  fixture_setup
  req_dir=$(fixture_create_req "req-001" "test" 3)

  if _run_req "$req_dir" --to 4 >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "stage 3 无产出文件应拒绝推进"
  else
    if grep -qE "prd\.md" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr 应提示缺 prd.md"
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
test_reject_stage1_to_2_no_brief
test_reject_rollback_from_stage7
test_reject_rollback_from_stage6_with_active_task
test_allow_rollback_from_stage6_all_closed
test_reject_rollback_to_zero
test_reject_rollback_negative
test_reject_rollback_target_ge_current
test_reject_rollback_target_greater
test_happy_path_1_to_2
test_reject_3_to_5_when_design_empty_non_first
test_reject_2_to_4_skip_stage3_non_first
test_allow_3_to_5_when_design_populated
test_stage3_to_4_new_flow_prd
test_stage3_to_4_legacy_flow_solution
test_stage3_to_4_missing_both_rejected

report_results "req-transition"
