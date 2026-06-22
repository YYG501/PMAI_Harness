#!/usr/bin/env bash
# test-doctor-skills.sh
#
# 防回归：bin/pmai-doctor 的 EXPECTED_SKILLS 必须与 skills/ 目录（除 _shared）完全一致。
# 背景（2026-06-22 事故）：reshape 删 req-analysis / 加 design 等漏改本清单 →
#   pmai upgrade 的 doctor 自检把正确的升级误判成「缺 skill」触发回滚。
#   T0: bin/pmai-doctor 存在且含 EXPECTED_SKILLS 数组
#   T1: EXPECTED_SKILLS ⊆ skills/ 目录（防清单残留已删 skill → doctor 误报回滚）
#   T2: skills/ 目录 ⊆ EXPECTED_SKILLS（防新加 skill 漏纳入 → doctor 检测不到丢失）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCTOR="$REPO_ROOT/bin/pmai-doctor"
SKILLS_DIR="$REPO_ROOT/skills"

# 解析 doctor 里 EXPECTED_SKILLS=( ... ) 之间的 skill 名（去注释 / 空行，排序去重）
expected_skills() {
  awk '/^EXPECTED_SKILLS=\(/{flag=1; next} flag && /^\)/{flag=0} flag{print}' "$DOCTOR" \
    | sed 's/#.*//' | tr ' \t' '\n\n' | grep -v '^$' | sort -u
}

# skills/ 目录下实际 skill（除 _shared），排序去重
actual_skills() {
  find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
    | grep -v '^_shared$' | sort -u
}

test_doctor_exists() {
  start_test "T0: bin/pmai-doctor 存在且含 EXPECTED_SKILLS"
  if [ ! -f "$DOCTOR" ]; then _fail "bin/pmai-doctor 不存在"; return; fi
  if ! grep -q '^EXPECTED_SKILLS=(' "$DOCTOR"; then _fail "未找到 EXPECTED_SKILLS 数组"; return; fi
  pass_test
}

test_no_stale_in_expected() {
  start_test "T1: EXPECTED_SKILLS 无残留已删 skill（清单 ⊆ 目录）"
  local stale
  stale=$(comm -23 <(expected_skills) <(actual_skills))
  if [ -n "$stale" ]; then
    _fail "EXPECTED_SKILLS 里有 skills/ 目录不存在的 skill（doctor 会误报回滚）：$(echo $stale)"
    return
  fi
  pass_test
}

test_no_missing_in_expected() {
  start_test "T2: skills/ 目录的 skill 全部纳入 EXPECTED_SKILLS（目录 ⊆ 清单）"
  local uncovered
  uncovered=$(comm -13 <(expected_skills) <(actual_skills))
  if [ -n "$uncovered" ]; then
    _fail "skills/ 目录有 skill 未纳入 doctor EXPECTED_SKILLS（丢失检测不到）：$(echo $uncovered)"
    return
  fi
  pass_test
}

test_doctor_exists
test_no_stale_in_expected
test_no_missing_in_expected

report_results "doctor-skills"
