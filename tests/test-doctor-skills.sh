#!/usr/bin/env bash
# test-doctor-skills.sh
#
# 防回归：bin/pmai-doctor 的 EXPECTED_SKILLS 必须与 skills/ 目录（除 _shared）完全一致。
# 背景（2026-06-22 事故）：reshape 删旧探索 skill / 加 design 等漏改本清单 →
#   pmai upgrade 的 doctor 自检把正确的升级误判成「缺 skill」触发回滚。
#   T0: bin/pmai-doctor 存在且含 EXPECTED_SKILLS 数组
#   T1: EXPECTED_SKILLS ⊆ skills/ 目录（防清单残留已删 skill → doctor 误报回滚）
#   T2: skills/ 目录 ⊆ EXPECTED_SKILLS（防新加 skill 漏纳入 → doctor 检测不到丢失）
#   T3: pmai-doctor --help 只打印帮助，不执行自检
#   T4: pmai-doctor 检测 ~/.claude/skills/pmai-* 的 stale 暴露入口
#   T5: pmai-status --help 只打印帮助，不执行状态扫描
#   T6: pmai-status 报告 stale 暴露入口，提示 upgrade 重同步
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCTOR="$REPO_ROOT/bin/pmai-doctor"
STATUS="$REPO_ROOT/bin/pmai-status"
SKILLS_DIR="$REPO_ROOT/skills"
VERSION_FILE="$REPO_ROOT/VERSION"

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

exposed_name_for_skill() {
  case "$1" in
    pmai-*) echo "$1" ;;
    *) echo "pmai-$1" ;;
  esac
}

setup_fake_global_install() {
  local tmp pmai_home fake_home sk name exposed

  tmp=$(mktemp -d /tmp/pmai-doctor-skills-XXXXXX)
  pmai_home="$tmp/pmai"
  fake_home="$tmp/home"

  mkdir -p "$pmai_home" "$fake_home/.claude/skills"
  ln -s "$SKILLS_DIR" "$pmai_home/skills"
  cp "$VERSION_FILE" "$pmai_home/VERSION"
  git -C "$pmai_home" init -q

  while IFS= read -r sk; do
    name=$(basename "$sk")
    exposed=$(exposed_name_for_skill "$name")
    ln -s "$sk" "$fake_home/.claude/skills/$exposed"
  done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name _shared | sort)
  ln -s "$SKILLS_DIR/_shared" "$fake_home/.claude/skills/_shared"

  echo "$tmp|$pmai_home|$fake_home"
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

test_doctor_help_is_help_only() {
  start_test "T3: pmai-doctor --help 只打印帮助，不执行自检"
  local out
  out=$(bash "$DOCTOR" --help 2>&1)
  if ! echo "$out" | grep -q "Usage:"; then
    _fail "--help 未打印 Usage"
    return
  fi
  if echo "$out" | grep -q "PMAI Doctor — integrity self-check"; then
    _fail "--help 不应执行 doctor 自检"
    return
  fi
  pass_test
}

test_doctor_detects_stale_exposed_skill() {
  start_test "T4: pmai-doctor 检测 stale pmai-* 暴露入口"
  local setup tmp pmai_home fake_home out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  ln -s "$SKILLS_DIR/design" "$fake_home/.claude/skills/pmai-new-req"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" 2>&1)
  rc=$?
  rm -rf "$tmp"

  if [ "$rc" = "0" ]; then
    _fail "存在 stale pmai-new-req 时 doctor 应失败"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "Stale exposed skill symlink(s): .*pmai-new-req"; then
    _fail "doctor 未点名 stale pmai-new-req"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_status_help_is_help_only() {
  start_test "T5: pmai-status --help 只打印帮助，不执行状态扫描"
  local out
  out=$(bash "$STATUS" --help 2>&1)
  if ! echo "$out" | grep -q "Usage:"; then
    _fail "--help 未打印 Usage"
    return
  fi
  if echo "$out" | grep -q "PMAI Status"; then
    _fail "--help 不应执行 status 扫描"
    return
  fi
  pass_test
}

test_status_reports_stale_exposed_skill() {
  start_test "T6: pmai-status 报告 stale pmai-* 暴露入口"
  local setup tmp pmai_home fake_home out

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  ln -s "$SKILLS_DIR/design" "$fake_home/.claude/skills/pmai-new-req"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$STATUS" 2>&1)
  rm -rf "$tmp"

  if ! echo "$out" | grep -q "Exposure drift:"; then
    _fail "status 未输出 Exposure drift"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "stale:.*pmai-new-req"; then
    _fail "status 未列出 stale pmai-new-req"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_doctor_exists
test_no_stale_in_expected
test_no_missing_in_expected
test_doctor_help_is_help_only
test_doctor_detects_stale_exposed_skill
test_status_help_is_help_only
test_status_reports_stale_exposed_skill

report_results "doctor-skills"
