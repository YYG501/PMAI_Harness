#!/usr/bin/env bash
# test-doctor-skills.sh
#
# 防回归：bin/pmai-doctor 的 EXPECTED_SKILLS 必须与公开 skills/ 目录（除 _shared / _internal）完全一致。
# 背景（2026-06-22 事故）：reshape 删旧探索 skill / 加 design 等漏改本清单 →
#   pmai upgrade 的 doctor 自检把正确的升级误判成「缺 skill」触发回滚。
#   T0: bin/pmai-doctor 存在且含 EXPECTED_SKILLS 数组
#   T1: EXPECTED_SKILLS ⊆ skills/ 目录（防清单残留已删 skill → doctor 误报回滚）
#   T2: skills/ 目录 ⊆ EXPECTED_SKILLS（防新加 skill 漏纳入 → doctor 检测不到丢失）
#   T3: pmai-doctor --help 只打印帮助，不执行自检
#   T4: pmai-doctor 检测 host skill dir 的 stale 暴露入口
#   T5: pmai-status --help 只打印帮助，不执行状态扫描
#   T6: pmai-status 报告 stale 暴露入口，提示 upgrade 重同步
#   T7: pmai-doctor 缺 Codex 暴露入口时失败
#   T8: install / upgrade / uninstall 覆盖 Codex skill dir + Codex CLI prompts + OpenCode commands
#   T9: pmai-doctor 可自愈 Codex 首次空暴露目录（兼容旧 upgrader）
#   T10: pmai-doctor 可自愈 Codex CLI slash prompts
#   T11: pmai-doctor 可自愈 OpenCode slash commands
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCTOR="$REPO_ROOT/bin/pmai-doctor"
STATUS="$REPO_ROOT/bin/pmai-status"
SKILLS_DIR="$REPO_ROOT/skills"
VERSION_FILE="$REPO_ROOT/VERSION"
INSTALL="$REPO_ROOT/bin/pmai-install"
UPGRADE="$REPO_ROOT/bin/pmai-upgrade"
UNINSTALL="$REPO_ROOT/bin/pmai-uninstall"

# 解析 doctor 里 EXPECTED_SKILLS=( ... ) 之间的 skill 名（去注释 / 空行，排序去重）
expected_skills() {
  awk '/^EXPECTED_SKILLS=\(/{flag=1; next} flag && /^\)/{flag=0} flag{print}' "$DOCTOR" \
    | sed 's/#.*//' | tr ' \t' '\n\n' | grep -v '^$' | sort -u
}

# skills/ 目录下实际公开 skill（除 _shared / _internal），排序去重
actual_skills() {
  find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
    | grep -vE '^(_shared|_internal)$' | sort -u
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

  mkdir -p "$pmai_home/scripts" "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.codex/prompts"
  ln -s "$SKILLS_DIR" "$pmai_home/skills"
  ln -s "$REPO_ROOT/scripts/install-opencode-commands.sh" "$pmai_home/scripts/install-opencode-commands.sh"
  cp "$VERSION_FILE" "$pmai_home/VERSION"
  git -C "$pmai_home" init -q

  while IFS= read -r sk; do
    name=$(basename "$sk")
    exposed=$(exposed_name_for_skill "$name")
    ln -s "$sk" "$fake_home/.claude/skills/$exposed"
    ln -s "$sk" "$fake_home/.codex/skills/$exposed"
    printf -- "---\ndescription: fake %s\n---\n" "$exposed" > "$fake_home/.codex/prompts/$exposed.md"
  done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name _shared ! -name _internal | sort)
  ln -s "$SKILLS_DIR/_shared" "$fake_home/.claude/skills/_shared"
  ln -s "$SKILLS_DIR/_shared" "$fake_home/.codex/skills/_shared"

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
  ln -s "$SKILLS_DIR/design" "$fake_home/.codex/skills/pmai-new-req"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" 2>&1)
  rc=$?
  rm -rf "$tmp"

  if [ "$rc" = "0" ]; then
    _fail "存在 stale pmai-new-req 时 doctor 应失败"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "Codex stale exposed skill symlink(s): .*pmai-new-req"; then
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
  ln -s "$SKILLS_DIR/design" "$fake_home/.codex/skills/pmai-new-req"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$STATUS" 2>&1)
  rm -rf "$tmp"

  if ! echo "$out" | grep -q "Codex drift:"; then
    _fail "status 未输出 Codex drift"
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

test_doctor_requires_codex_exposure() {
  start_test "T7: pmai-doctor 缺 Codex 暴露入口时失败"
  local setup tmp pmai_home fake_home out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  rm -f "$fake_home/.codex/skills/pmai-design"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" 2>&1)
  rc=$?
  rm -rf "$tmp"

  if [ "$rc" = "0" ]; then
    _fail "缺 Codex pmai-design 暴露入口时 doctor 应失败"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "Codex missing exposed skill symlink(s): .*pmai-design"; then
    _fail "doctor 未点名缺 Codex pmai-design"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_lifecycle_scripts_cover_codex_skills() {
  start_test "T8: install / upgrade / uninstall 覆盖 Codex skill dir + Codex CLI prompts + OpenCode commands"
  local file

  for file in "$INSTALL" "$UPGRADE" "$UNINSTALL" "$DOCTOR" "$STATUS"; do
    if ! grep -q "CODEX_SKILLS" "$file"; then
      _fail "$(basename "$file") 未声明 CODEX_SKILLS，Codex skill 暴露会漂移"
      return
    fi
  done
  for file in "$INSTALL" "$UPGRADE" "$UNINSTALL" "$DOCTOR" "$STATUS"; do
    if ! grep -q "CODEX_PROMPTS" "$file"; then
      _fail "$(basename "$file") 未声明 CODEX_PROMPTS，Codex CLI slash prompt 暴露会漂移"
      return
    fi
  done
  for file in "$INSTALL" "$UPGRADE" "$UNINSTALL" "$DOCTOR" "$STATUS"; do
    if ! grep -q "OPENCODE_CONFIG_DIR" "$file"; then
      _fail "$(basename "$file") 未声明 OPENCODE_CONFIG_DIR，OpenCode command 暴露会漂移"
      return
    fi
  done
  if ! grep -q "install-opencode-commands.sh" "$INSTALL" || ! grep -q "install-opencode-commands.sh" "$UPGRADE"; then
    _fail "install / upgrade 应调用 install-opencode-commands.sh"
    return
  fi
  pass_test
}

test_doctor_repairs_empty_codex_exposure() {
  start_test "T9: pmai-doctor 自愈 Codex 首次空暴露目录"
  local setup tmp pmai_home fake_home out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  rm -rf "$fake_home/.codex/skills"
  mkdir -p "$fake_home/.codex/skills"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "Codex 暴露目录为空时 doctor 应自愈并通过"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q "Codex initial skill exposure repaired"; then
    _fail "doctor 未报告 Codex 初始暴露自愈"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if [ ! -L "$fake_home/.codex/skills/pmai-design" ]; then
    _fail "doctor 未创建 Codex pmai-design symlink"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if [ -e "$fake_home/.codex/skills/pmai-_internal" ] || [ -L "$fake_home/.codex/skills/pmai-_internal" ]; then
    _fail "doctor 不应把 skills/_internal 暴露成 pmai-_internal"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_doctor_repairs_codex_prompts() {
  start_test "T10: pmai-doctor 自愈 Codex CLI slash prompts"
  local setup tmp pmai_home fake_home out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  rm -rf "$fake_home/.codex/prompts"
  mkdir -p "$fake_home/.codex/prompts"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "Codex prompt 目录为空时 doctor 应自愈并通过"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q "Codex CLI slash prompts repaired"; then
    _fail "doctor 未报告 Codex prompt 自愈"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if [ ! -f "$fake_home/.codex/prompts/pmai-design.md" ]; then
    _fail "doctor 未创建 Codex /pmai-design prompt"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! grep -q "PMAI /pmai-design" "$fake_home/.codex/prompts/pmai-design.md"; then
    _fail "生成的 /pmai-design prompt 内容不指向 PMAI workflow"
    cat "$fake_home/.codex/prompts/pmai-design.md" >&2
    rm -rf "$tmp"
    return
  fi
  if ! grep -q "skill-preamble.sh" "$fake_home/.codex/prompts/pmai-design.md" \
     || ! grep -q "PMAI_PROJECT_INITIALIZED: 0" "$fake_home/.codex/prompts/pmai-design.md"; then
    _fail "生成的 /pmai-design prompt 缺未初始化项目护栏"
    cat "$fake_home/.codex/prompts/pmai-design.md" >&2
    rm -rf "$tmp"
    return
  fi
  if [ -e "$fake_home/.codex/prompts/pmai-_internal.md" ]; then
    _fail "doctor 不应把 skills/_internal 暴露成 Codex prompt"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_doctor_repairs_opencode_commands() {
  start_test "T11: pmai-doctor 自愈 OpenCode slash commands"
  local setup tmp pmai_home fake_home out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  rm -rf "$fake_home/.config/opencode/commands"
  mkdir -p "$fake_home/.config/opencode/commands"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "OpenCode command 目录为空时 doctor 应自愈并通过"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q "OpenCode slash commands repaired"; then
    _fail "doctor 未报告 OpenCode command 自愈"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if [ ! -f "$fake_home/.config/opencode/commands/pmai-design.md" ]; then
    _fail "doctor 未创建 OpenCode /pmai-design command"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! grep -q '$PMAI_HOME/skills/design/SKILL.md' "$fake_home/.config/opencode/commands/pmai-design.md"; then
    _fail "生成的 /pmai-design OpenCode command 未路由到 PMAI skill"
    cat "$fake_home/.config/opencode/commands/pmai-design.md" >&2
    rm -rf "$tmp"
    return
  fi
  if ! grep -q "skill-preamble.sh" "$fake_home/.config/opencode/commands/pmai-design.md" \
     || ! grep -q "PMAI_PROJECT_INITIALIZED: 0" "$fake_home/.config/opencode/commands/pmai-design.md"; then
    _fail "生成的 /pmai-design OpenCode command 缺未初始化项目护栏"
    cat "$fake_home/.config/opencode/commands/pmai-design.md" >&2
    rm -rf "$tmp"
    return
  fi
  if [ -e "$fake_home/.config/opencode/commands/pmai-_internal.md" ]; then
    _fail "doctor 不应把 skills/_internal 暴露成 OpenCode command"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_doctor_exists
test_no_stale_in_expected
test_no_missing_in_expected
test_doctor_help_is_help_only
test_doctor_detects_stale_exposed_skill
test_status_help_is_help_only
test_status_reports_stale_exposed_skill
test_doctor_requires_codex_exposure
test_lifecycle_scripts_cover_codex_skills
test_doctor_repairs_empty_codex_exposure
test_doctor_repairs_codex_prompts
test_doctor_repairs_opencode_commands

report_results "doctor-skills"
