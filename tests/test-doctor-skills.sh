#!/usr/bin/env bash
# test-doctor-skills.sh
#
# 防回归：bin/pmai-doctor 的 EXPECTED_SKILLS 必须与 skill 源目录（除 _shared / _internal）完全一致。
# 宿主暴露 fixture 使用测试侧明确合同，不从被测函数反向生成期望值。
# 背景（2026-06-22 事故）：reshape 删旧探索 skill / 加 design 等漏改本清单 →
#   pmai upgrade 的 doctor 自检把正确的升级误判成「缺 skill」触发回滚。
#   T0: bin/pmai-doctor 存在且含 EXPECTED_SKILLS 数组
#   T1: EXPECTED_SKILLS ⊆ skills/ 目录（防清单残留已删 skill → doctor 误报回滚）
#   T2: skills/ 目录 ⊆ EXPECTED_SKILLS（防新加 skill 漏纳入 → doctor 检测不到丢失）
#   T3: pmai-doctor --help 只打印帮助，不执行自检
#   T4: pmai-doctor 检测 host skill dir 的 stale 暴露入口
#   T5: pmai-status --help 只打印帮助，不执行状态扫描
#   T6: pmai-status 作为 doctor check 兼容包装报告 stale 暴露入口
#   T7: pmai-doctor 缺 Codex 暴露入口时失败
#   T8: install / upgrade / uninstall 覆盖 Codex/Kimi skill dir + legacy prompt cleanup + OpenCode commands
#   T9: pmai-doctor 默认只读，--repair 才自愈 Codex 首次空暴露目录
#   T10: pmai-doctor 不再生成 Codex slash prompts
#   T11: pmai-doctor --repair 可自愈 OpenCode slash commands
#   T12: pmai-doctor --repair 可自愈 Kimi 原生 Skill 暴露和 managed hooks
#   T15: 旧 updater 升级后保留公开入口；后续失败回滚恢复旧暴露策略
#   T16: 当前 updater 可降级到不含策略函数的旧版本
#   T17: upgrade doctor 日志默认唯一安全，同时保留测试 override
#   T21: 升级目标缺失 doctor 时回滚
#   T22: 升级目标 doctor 不可执行时回滚
#   T23: install doctor 失败时完整恢复所有全局宿主面并删除 clone
#   T24: install clone 后重载目标版本 exposure policy
#   T25: --to doctor 失败恢复 symbolic branch、空 Kimi 状态和旧版 fallback
#   T26: HUP / INT / TERM 回滚并恢复 symbolic / detached HEAD
#   T27: upgrade doctor 失败时恢复 Kimi config symlink 原始形态
#   T28: install 拒绝 dangling PMAI_HOME 且不删除原 symlink
#   T29: doctor 在显式 logical alias 下按原 PMAI_HOME 校验 Host targets
#   T30: Kimi config 普通文件/live symlink/dangling/missing 四态提交与回滚
#   T31: upgrade 在 Git 保护完成前的失败和信号不删除未提交改动
#   T32: doctor 在 stock macOS 没有 GNU timeout 时仍可执行远端检查
#   T33: install / upgrade / rollback 按目标版本清理已移除的 direction 入口
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
SKILL_LINKS="$REPO_ROOT/scripts/_lib/skill-links.sh"
HOST_HIDDEN_SKILLS="$REPO_ROOT/scripts/_lib/host-hidden-skills.txt"

# 解析 doctor 里 EXPECTED_SKILLS=( ... ) 之间的 skill 名（去注释 / 空行，排序去重）
expected_skills() {
  awk '/^EXPECTED_SKILLS=\(/{flag=1; next} flag && /^\)/{flag=0} flag{print}' "$DOCTOR" \
    | sed 's/#.*//' | tr ' \t' '\n\n' | grep -v '^$' | sort -u
}

# skills/ 目录下实际 skill 源（除 _shared / _internal），排序去重
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

# 当前产品合同：所有公开 skill 都是宿主入口；仅框架内部目录不暴露。
# 策略改变时先改这里表达新的产品预期，再改生产实现和数据清单。
expected_skill_is_host_exposed() {
  case "$1" in
    _internal|_shared) return 1 ;;
    *) return 0 ;;
  esac
}

test_host_exposure_policy_matches_product_contract() {
  start_test "T0b: 宿主暴露策略与独立产品合同一致"
  local hidden skill expected_rc actual_rc

  hidden=$(sed 's/#.*//' "$HOST_HIDDEN_SKILLS" | tr -d '[:space:]')
  if [ -n "$hidden" ]; then
    _fail "current product contract exposes every public skill, but hidden policy is non-empty"
    return
  fi

  while IFS= read -r skill; do
    expected_skill_is_host_exposed "$skill"
    expected_rc=$?
    (
      source "$SKILL_LINKS"
      pmai_skill_is_host_exposed "$skill"
    )
    actual_rc=$?
    if [ "$actual_rc" -ne "$expected_rc" ]; then
      _fail "production exposure policy disagrees for $skill: expected=$expected_rc actual=$actual_rc"
      return
    fi
  done < <(actual_skills)

  for skill in _internal _shared; do
    if (
      source "$SKILL_LINKS"
      pmai_skill_is_host_exposed "$skill"
    ); then
      _fail "$skill must remain framework-only"
      return
    fi
  done
  pass_test
}

setup_fake_global_install() {
  local tmp pmai_home fake_home sk name exposed

  tmp=$(mktemp -d /tmp/pmai-doctor-skills-XXXXXX)
  pmai_home="$tmp/pmai"
  fake_home="$tmp/home"

  mkdir -p "$pmai_home/bin" "$pmai_home/scripts/_lib" \
    "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.kimi-code/skills"
  cp "$DOCTOR" "$pmai_home/bin/pmai-doctor"
  chmod +x "$pmai_home/bin/pmai-doctor"
  ln -s "$SKILLS_DIR" "$pmai_home/skills"
  cp "$REPO_ROOT/scripts/_lib/global-install-lock.sh" "$pmai_home/scripts/_lib/global-install-lock.sh"
  cp "$REPO_ROOT/scripts/_lib/global_install_lock.py" "$pmai_home/scripts/_lib/global_install_lock.py"
  cp "$REPO_ROOT/scripts/_lib/atomic_file.py" "$pmai_home/scripts/_lib/atomic_file.py"
  cp "$REPO_ROOT/scripts/_lib/project_definition.py" "$pmai_home/scripts/_lib/project_definition.py"
  cp "$REPO_ROOT/scripts/_lib/consumer_entry.py" "$pmai_home/scripts/_lib/consumer_entry.py"
  cp "$REPO_ROOT/scripts/_lib/proposal.py" "$pmai_home/scripts/_lib/proposal.py"
  cp "$REPO_ROOT/scripts/consumer-doctor.py" "$pmai_home/scripts/consumer-doctor.py"
  cp "$REPO_ROOT/scripts/sync-consumer-entry.py" "$pmai_home/scripts/sync-consumer-entry.py"
  cp "$REPO_ROOT/scripts/gen-mock-board.py" "$pmai_home/scripts/gen-mock-board.py"
  cp "$REPO_ROOT/scripts/install-project-hooks.sh" "$pmai_home/scripts/install-project-hooks.sh"
  cp "$REPO_ROOT/scripts/install-hooks.sh" "$pmai_home/scripts/install-hooks.sh"
  ln -s "$REPO_ROOT/templates" "$pmai_home/templates"
  ln -s "$REPO_ROOT/scripts/install-opencode-commands.sh" "$pmai_home/scripts/install-opencode-commands.sh"
  ln -s "$REPO_ROOT/scripts/manage-kimi-hooks.py" "$pmai_home/scripts/manage-kimi-hooks.py"
  ln -s "$REPO_ROOT/scripts/kimi-hook-dispatch.sh" "$pmai_home/scripts/kimi-hook-dispatch.sh"
  ln -s "$SKILL_LINKS" "$pmai_home/scripts/_lib/skill-links.sh"
  cp "$HOST_HIDDEN_SKILLS" "$pmai_home/scripts/_lib/host-hidden-skills.txt"
  cp "$VERSION_FILE" "$pmai_home/VERSION"
  git -C "$pmai_home" init -q

  while IFS= read -r sk; do
    name=$(basename "$sk")
    expected_skill_is_host_exposed "$name" || continue
    exposed=$(exposed_name_for_skill "$name")
    ln -s "$pmai_home/skills/$name" "$fake_home/.claude/skills/$exposed"
    ln -s "$pmai_home/skills/$name" "$fake_home/.codex/skills/$exposed"
    ln -s "$pmai_home/skills/$name" "$fake_home/.kimi-code/skills/$exposed"
  done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name _shared ! -name _internal | sort)
  ln -s "$pmai_home/skills/_shared" "$fake_home/.claude/skills/_shared"
  ln -s "$pmai_home/skills/_shared" "$fake_home/.codex/skills/_shared"
  ln -s "$pmai_home/skills/_shared" "$fake_home/.kimi-code/skills/_shared"

  mkdir -p "$fake_home/.config/opencode/commands"
  if ! PMAI_HOME="$pmai_home" OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$pmai_home/scripts/install-opencode-commands.sh" --global >/dev/null 2>&1; then
    rm -rf "$tmp"
    return 1
  fi

  echo "$tmp|$pmai_home|$fake_home"
}

copy_global_lock_helpers_to() {
  local framework_root="$1"

  mkdir -p "$framework_root/scripts/_lib"
  cp "$REPO_ROOT/scripts/_lib/global-install-lock.sh" \
    "$framework_root/scripts/_lib/global-install-lock.sh"
  cp "$REPO_ROOT/scripts/_lib/global_install_lock.py" \
    "$framework_root/scripts/_lib/global_install_lock.py"
  cp "$REPO_ROOT/scripts/_lib/kimi-config-transaction.sh" \
    "$framework_root/scripts/_lib/kimi-config-transaction.sh"
}

# Transition fixtures start from committed HEAD, while this suite must also validate a
# newly added or removed public skill before the framework change is committed.
sync_current_skill_catalog_to_fixture() {
  local framework_root="$1"

  rm -rf "$framework_root/skills/direction" "$framework_root/skills/proposal"
  cp -R "$SKILLS_DIR/proposal" "$framework_root/skills/proposal"
  git -C "$framework_root" add -A -- skills/direction skills/proposal
}

seed_retired_direction_entries() {
  local pmai_home="$1"
  local fake_home="$2"
  local host_dir

  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.kimi-code/skills"; do
    ln -s "$pmai_home/skills/direction" "$host_dir/pmai-direction"
  done
  printf '%s\n' 'legacy direction command' \
    > "$fake_home/.config/opencode/commands/pmai-direction.md"
}

assert_retired_direction_entries_absent() {
  local fake_home="$1"
  local host_dir

  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.kimi-code/skills"; do
    if [ -e "$host_dir/pmai-direction" ] || [ -L "$host_dir/pmai-direction" ]; then
      _fail "已移除的 pmai-direction 入口仍残留：$host_dir"
      return 1
    fi
  done
  if [ -e "$fake_home/.config/opencode/commands/pmai-direction.md" ] \
    || [ -L "$fake_home/.config/opencode/commands/pmai-direction.md" ]; then
    _fail "已移除的 OpenCode pmai-direction.md 仍残留"
    return 1
  fi
  return 0
}

test_manual_workflows_are_host_entries() {
  start_test "T13: 兼容恢复和明确手动能力保留宿主入口"
  local setup tmp pmai_home fake_home host_dir skill expected actual

  if ! expected_skill_is_host_exposed build-close || ! expected_skill_is_host_exposed publish-to-lark; then
    _fail "build-close / publish-to-lark should remain explicitly invocable"
    return
  fi
  if ! expected_skill_is_host_exposed design || ! expected_skill_is_host_exposed spec-writing; then
    _fail "independently useful design/spec-writing skills should stay exposed"
    return
  fi
  if ! expected_skill_is_host_exposed proposal || ! expected_skill_is_host_exposed record; then
    _fail "independently useful proposal/record skills should stay exposed"
    return
  fi
  for file in "$INSTALL" "$UPGRADE" "$DOCTOR" "$REPO_ROOT/scripts/install-opencode-commands.sh"; do
    if ! grep -q "pmai_skill_is_host_exposed" "$file"; then
      _fail "$(basename "$file") should use the shared exposure policy"
      return
    fi
  done
  if ! grep -q 'pmai-doctor' "$STATUS" || ! grep -q -- '--check' "$STATUS" \
    || grep -qE 'CODEX_SKILLS|KIMI_SKILLS|OPENCODE_CONFIG_DIR|skill-links' "$STATUS"; then
    _fail "pmai-status should be a thin compatibility wrapper around doctor --check"
    return
  fi

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"; do
    for skill in build-close publish-to-lark proposal record; do
      expected="pmai-$skill"
      if [ ! -L "$host_dir/$expected" ]; then
        _fail "$expected should be installed for $(basename "$(dirname "$host_dir")")"
        rm -rf "$tmp"
        return
      fi
      actual=$(sed -n 's/^name:[[:space:]]*//p' "$host_dir/$expected/SKILL.md" | head -1)
      if [ "$actual" != "$expected" ]; then
        _fail "$host_dir/$expected should expose parseable name $expected, got ${actual:-missing}"
        rm -rf "$tmp"
        return
      fi
    done
  done
  rm -rf "$tmp"
  pass_test
}

test_skill_frontmatter_does_not_claim_framework_version() {
  start_test "T14: Skill frontmatter 不维护孤立框架版本"
  local hits
  hits=$(grep -R -n --include='SKILL.md' '^version:' "$SKILLS_DIR" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    _fail "Skill frontmatter should not duplicate the framework VERSION source"
    echo "$hits" >&2
    return
  fi
  pass_test
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
  start_test "T4: pmai-doctor 检测并清理已移除的 pmai-direction 入口"
  local setup tmp pmai_home fake_home out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  ln -s "$pmai_home/skills/direction" "$fake_home/.codex/skills/pmai-direction"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "存在已移除的 pmai-direction 时 doctor 应失败"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q "Codex stale exposed skill entry(s): .*pmai-direction"; then
    _fail "doctor 未点名 stale pmai-direction"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" --repair 2>&1)
  rc=$?
  if [ "$rc" != "0" ] \
     || [ -e "$fake_home/.codex/skills/pmai-direction" ] \
     || [ -L "$fake_home/.codex/skills/pmai-direction" ]; then
    _fail "doctor --repair 应删除 PMAI 管理的旧 pmai-direction 链接"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
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
  start_test "T6: pmai-status 兼容包装委托 doctor 报告 stale 入口"
  local setup tmp pmai_home fake_home out

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  ln -s "$SKILLS_DIR/design" "$fake_home/.codex/skills/pmai-new-req"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$STATUS" 2>&1)
  rm -rf "$tmp"

  if ! echo "$out" | grep -q "pmai status 已并入 pmai doctor --check"; then
    _fail "status 未提示兼容入口已并入 doctor check"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "Codex stale exposed skill entry(s): .*pmai-new-req"; then
    _fail "status 包装后的 doctor 未列出 stale pmai-new-req"
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
  if ! echo "$out" | grep -q "Codex invalid skill entry(s): .*pmai-design:missing"; then
    _fail "doctor 未点名缺 Codex pmai-design"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_doctor_rejects_wrong_target_and_real_directory_entries() {
  start_test "T7b: doctor 拒绝等价错误目标和实体目录伪装的宿主入口"
  local setup tmp pmai_home fake_home out rc marker

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  rm -f "$fake_home/.codex/skills/pmai-design" "$fake_home/.codex/skills/_shared"
  ln -s "$SKILLS_DIR/design" "$fake_home/.codex/skills/pmai-design"
  mkdir -p "$fake_home/.codex/skills/_shared"
  marker="$fake_home/.codex/skills/_shared/foreign.txt"
  printf '%s\n' 'do-not-replace' > "$marker"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" bash "$DOCTOR" 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "字面目标不匹配或实体 _shared 存在时 doctor 应失败"
    echo "$out" >&2
  elif ! echo "$out" | grep -q 'pmai-design:wrong-target'; then
    _fail "doctor 未识别解析到同一目录但字面错误的 symlink 目标"
    echo "$out" >&2
  elif ! echo "$out" | grep -q '_shared:not-symlink'; then
    _fail "doctor 未识别实体目录伪装的 _shared 入口"
    echo "$out" >&2
  elif [ ! -f "$marker" ]; then
    _fail "doctor 不得覆盖不属于 PMAI 的实体 _shared 目录"
  else
    out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" \
      CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
      OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" bash "$DOCTOR" --repair 2>&1)
    rc=$?
    if [ "$rc" = "0" ]; then
      _fail "doctor --repair 不得把外来入口当成 PMAI 自有入口覆盖"
      echo "$out" >&2
    elif [ "$(readlink "$fake_home/.codex/skills/pmai-design")" != "$SKILLS_DIR/design" ] \
      || [ ! -f "$marker" ]; then
      _fail "doctor --repair 改写了外来 symlink 或实体 _shared 目录"
    else
      pass_test
    fi
  fi

  rm -rf "$tmp"
}

test_lifecycle_scripts_cover_codex_skills() {
  start_test "T8: install / upgrade / uninstall 覆盖 Codex/Kimi skill dir + legacy prompt cleanup + OpenCode commands"
  local file

  for file in "$INSTALL" "$UPGRADE" "$UNINSTALL" "$DOCTOR"; do
    if ! grep -q "CODEX_SKILLS" "$file"; then
      _fail "$(basename "$file") 未声明 CODEX_SKILLS，Codex skill 暴露会漂移"
      return
    fi
    if ! grep -q "KIMI_CODE_HOME" "$file" || ! grep -q "KIMI_SKILLS" "$file"; then
      _fail "$(basename "$file") 未声明 Kimi 宿主面，原生 Skill 暴露会漂移"
      return
    fi
  done
  for file in "$INSTALL" "$UPGRADE" "$UNINSTALL"; do
    if ! grep -q "CODEX_PROMPTS" "$file"; then
      _fail "$(basename "$file") 未声明 CODEX_PROMPTS，无法清理 legacy Codex prompts"
      return
    fi
  done
  for file in "$DOCTOR"; do
    if grep -q "CODEX_PROMPTS" "$file"; then
      _fail "$(basename "$file") 不应继续把 legacy Codex prompts 当成当前 host surface"
      return
    fi
  done
  if ! grep -q "remove_managed_codex_prompts" "$INSTALL" || ! grep -q "remove_managed_codex_prompts" "$UPGRADE"; then
    _fail "install / upgrade 应清理 legacy Codex prompts"
    return
  fi
  for file in "$INSTALL" "$UPGRADE" "$UNINSTALL" "$DOCTOR"; do
    if ! grep -q "OPENCODE_CONFIG_DIR" "$file"; then
      _fail "$(basename "$file") 未声明 OPENCODE_CONFIG_DIR，OpenCode command 暴露会漂移"
      return
    fi
  done
  if ! grep -q "install-opencode-commands.sh" "$INSTALL" || ! grep -q "install-opencode-commands.sh" "$UPGRADE"; then
    _fail "install / upgrade 应调用 install-opencode-commands.sh"
    return
  fi
  if ! grep -q 'pmai-doctor' "$STATUS" || ! grep -q -- '--check' "$STATUS"; then
    _fail "pmai-status 应只委托 doctor --check"
    return
  fi
  pass_test
}

test_doctor_repairs_empty_codex_exposure() {
  start_test "T9: doctor 默认只读，--repair 才自愈空 Codex 暴露目录"
  local setup tmp pmai_home fake_home out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  rm -rf "$fake_home/.codex/skills"
  mkdir -p "$fake_home/.codex/skills"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "Codex 暴露目录为空时只读 doctor 应失败"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if [ -e "$fake_home/.codex/skills/pmai-design" ] \
    || [ -L "$fake_home/.codex/skills/pmai-design" ]; then
    _fail "默认 doctor 不得写入空 Codex 暴露目录"
    rm -rf "$tmp"
    return
  fi

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" --repair 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "Codex 暴露目录为空时 doctor --repair 应自愈并通过"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q "Codex skill exposure repaired"; then
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

  rm -f "$fake_home/.codex/skills/pmai-design"
  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" --repair 2>&1)
  rc=$?
  if [ "$rc" != "0" ] || [ ! -L "$fake_home/.codex/skills/pmai-design" ]; then
    _fail "doctor --repair 应补回单个缺失的 PMAI skill 入口"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_doctor_does_not_generate_codex_prompts() {
  start_test "T10: pmai-doctor 不再生成 Codex slash prompts"
  local setup tmp pmai_home fake_home out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  rm -rf "$fake_home/.codex/prompts"
  mkdir -p "$fake_home/.codex/prompts"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" --repair 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "Codex prompt 目录为空时 doctor 应忽略该目录并通过"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if echo "$out" | grep -q "Codex CLI slash prompts"; then
    _fail "doctor 不应再报告 Codex prompt 状态"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if find "$fake_home/.codex/prompts" -maxdepth 1 -name 'pmai-*.md' -print -quit | grep -q .; then
    _fail "doctor 不应创建任何 pmai-* Codex prompt"
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

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" --repair 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "OpenCode command 目录为空时 doctor --repair 应自愈并通过"
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

test_doctor_repairs_modified_opencode_command_content() {
  start_test "T11b: doctor 检测并逐字修复被修改的 OpenCode command"
  local setup tmp pmai_home fake_home command out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  mkdir -p "$fake_home/.config/opencode/commands"
  PMAI_HOME="$pmai_home" OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$pmai_home/scripts/install-opencode-commands.sh" --global >/dev/null 2>&1
  command="$fake_home/.config/opencode/commands/pmai-design.md"
  printf '%s\n' 'tampered-by-user' >> "$command"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" bash "$DOCTOR" --repair 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "OpenCode command 内容漂移时 doctor --repair 应修复并通过"
    echo "$out" >&2
  elif ! echo "$out" | grep -q 'OpenCode slash commands repaired and verified'; then
    _fail "doctor 未报告 OpenCode 内容漂移已修复并复验"
    echo "$out" >&2
  elif grep -q 'tampered-by-user' "$command"; then
    _fail "doctor 修复后仍残留被篡改内容"
  elif ! PMAI_HOME="$pmai_home" OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$pmai_home/scripts/install-opencode-commands.sh" --global --check >/dev/null 2>&1; then
    _fail "doctor 报告修复后，确定性 renderer 复验仍失败"
  else
    pass_test
  fi

  rm -rf "$tmp"
}

test_doctor_repairs_kimi_native_surface() {
  start_test "T12: pmai-doctor 自愈 Kimi 原生 Skill 暴露和 managed hooks"
  local setup tmp pmai_home fake_home out rc config

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  rm -rf "$fake_home/.kimi-code/skills"
  mkdir -p "$fake_home/.kimi-code/skills"
  config="$fake_home/.kimi-code/config.toml"
  printf '%s\n' 'default_model = "demo"' > "$config"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" KIMI_CODE_HOME="$fake_home/.kimi-code" bash "$DOCTOR" --repair 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "Kimi 宿主面为空时 doctor 应自愈并通过"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q "Kimi Code skill exposure repaired"; then
    _fail "doctor 未报告 Kimi 原生 Skill 暴露自愈"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q "Kimi Code PMAI-managed hooks repaired"; then
    _fail "doctor 未报告 Kimi managed hooks 自愈"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if [ ! -L "$fake_home/.kimi-code/skills/pmai-build" ]; then
    _fail "doctor 未创建 Kimi pmai-build symlink"
    rm -rf "$tmp"
    return
  fi
  if ! grep -q '^# >>> PMAI managed Kimi Code hooks >>>$' "$config"; then
    _fail "doctor 未在 Kimi config 中安装 PMAI managed hooks"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_doctor_rechecks_kimi_repair_result() {
  start_test "T12b: Kimi manager 假修复成功时 doctor 失败关闭"
  local setup tmp pmai_home fake_home manager config out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  manager="$pmai_home/scripts/manage-kimi-hooks.py"
  config="$fake_home/.kimi-code/config.toml"
  rm -f "$manager"
  cat > "$manager" <<'PY'
#!/usr/bin/env python3
import sys

if sys.argv[1] == "check":
    print("DRIFT: fixture remains unrepaired")
    raise SystemExit(1)
raise SystemExit(0)
PY
  chmod +x "$manager"
  printf '%s\n' 'default_model = "demo"' > "$config"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" \
    KIMI_CODE_HOME="$fake_home/.kimi-code" bash "$DOCTOR" --repair 2>&1)
  rc=$?
  if [ "$rc" = "0" ]; then
    _fail "manager install 返回 0 但复验仍 drift 时 doctor 不得通过"
    echo "$out" >&2
  elif ! echo "$out" | grep -q "修复后校验仍未通过"; then
    _fail "doctor 未报告 Kimi repair 复验失败"
    echo "$out" >&2
  else
    pass_test
  fi
  rm -rf "$tmp"
}

test_doctor_json_contract_and_status_alias() {
  start_test "T12c: doctor JSON 合同稳定，status JSON 与 check 等价"
  local setup tmp pmai_home fake_home doctor_json status_json broken_json rc real_python

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"

  doctor_json=$(PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$pmai_home/bin/pmai-doctor" --check --json 2>"$tmp/doctor.err")
  rc=$?
  if [ "$rc" != "0" ] || ! python3 - "$doctor_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["schema_version"] == 1
assert payload["mode"] == "check"
assert payload["conclusion"] == "healthy"
assert payload["recommended_action"] == "none"
assert payload["summary"]["fail"] == 0
assert isinstance(payload["framework"], dict)
assert isinstance(payload["consumer"], dict)
assert isinstance(payload["findings"], list)
assert [item["id"] for item in payload["checks"]] == [
    "framework_install",
    "ai_tool_entry",
    "required_materials",
    "documents_and_history",
    "product_files",
    "active_work",
    "project_safety",
]
assert payload["checks"][0]["status"] == "normal"
assert payload["checks"][1]["status"] == "normal"
assert all(item["status"] == "not_applicable" for item in payload["checks"][2:])
assert payload["product_progress"] == {"phase": "not_applicable", "notes": []}
assert payload["pm_report"]["action_items"] == []
notice_categories = {item["category"] for item in payload["pm_report"]["notices"]}
assert "framework_currentness" in notice_categories
assert "browser_adapter" in notice_categories
assert payload["pm_report"]["progress"] == payload["product_progress"]
PY
  then
    _fail "健康 doctor 应只输出合法 schema v1 JSON 并以 0 退出"
    echo "$doctor_json" >&2
    rm -rf "$tmp"
    return
  fi

  status_json=$(PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$STATUS" --json 2>"$tmp/status.err")
  rc=$?
  if [ "$rc" != "0" ] || ! python3 - "$doctor_json" "$status_json" <<'PY'
import json
import sys

assert json.loads(sys.argv[1]) == json.loads(sys.argv[2])
PY
  then
    _fail "pmai status --json 应与 pmai doctor --check --json 完全等价"
    rm -rf "$tmp"
    return
  fi
  if ! grep -q "pmai status 已并入 pmai doctor --check" "$tmp/status.err"; then
    _fail "status JSON 兼容入口缺弃用提示"
    rm -rf "$tmp"
    return
  fi

  rm -f "$fake_home/.codex/skills/pmai-design"
  broken_json=$(PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$pmai_home/bin/pmai-doctor" --json 2>"$tmp/broken.err")
  rc=$?
  if [ "$rc" = "0" ] || ! python3 - "$broken_json" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["conclusion"] == "broken"
assert payload["recommended_action"] == "repair"
assert payload["summary"]["fail"] > 0
checks = {item["id"]: item for item in payload["checks"]}
assert checks["framework_install"]["status"] == "normal"
assert checks["ai_tool_entry"]["status"] == "problem"
assert [item["check_id"] for item in payload["pm_report"]["action_items"]] == ["ai_tool_entry"]
PY
  then
    _fail "broken JSON 结论必须与非零退出码一致"
    echo "$broken_json" >&2
    rm -rf "$tmp"
    return
  fi

  ln -s "$pmai_home/skills/design" "$fake_home/.codex/skills/pmai-design"
  real_python=$(command -v python3)
  mkdir -p "$tmp/fail-json-bin"
  cat > "$tmp/fail-json-bin/python3" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = "-" ] && [[ "\${2:-}" == */pmai-doctor-results.* ]]; then
  exit 97
fi
exec "$real_python" "\$@"
SH
  chmod +x "$tmp/fail-json-bin/python3"
  doctor_json=$(PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    PATH="$tmp/fail-json-bin:$PATH" \
    bash "$pmai_home/bin/pmai-doctor" --check --json 2>"$tmp/json-emitter.err")
  rc=$?
  if [ "$rc" != "2" ] || [ -n "$doctor_json" ]; then
    _fail "doctor JSON 序列化失败时必须失败关闭且不得输出伪 JSON"
    echo "rc=$rc stdout=$doctor_json" >&2
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_doctor_reports_consumer_hook_drift() {
  start_test "T12d: doctor 把消费仓 hooks 漂移归为 consumer_sync_required"
  local setup tmp pmai_home fake_home consumer out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  cat > "$pmai_home/scripts/install-project-hooks.sh" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "--check" ] || exit 2
exit 1
SH
  consumer="$tmp/consumer"
  if ! bash "$REPO_ROOT/scripts/init-project.sh" DoctorHookFixture "$consumer" \
    "doctor hook fixture" >/dev/null 2>&1; then
    _fail "unable to initialize current consumer fixture"
    rm -rf "$tmp"
    return
  fi
  sed 's/install-project-hooks\.sh/install-codex-hooks.sh/g; s/ --check//g' \
    "$consumer/AGENTS.md" > "$consumer/AGENTS.md.old" \
    && mv "$consumer/AGENTS.md.old" "$consumer/AGENTS.md"

  out=$(cd "$consumer" && PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$pmai_home/bin/pmai-doctor" --check --json 2>"$tmp/consumer.err")
  rc=$?
  if [ "$rc" != "0" ] || ! python3 - "$out" "$consumer" <<'PY'
import json
import os
import sys

payload = json.loads(sys.argv[1])
assert payload["conclusion"] == "consumer_sync_required"
assert payload["recommended_action"] == "refresh_project_hooks"
assert payload["consumer"]["kind"] == "consumer"
assert payload["consumer"]["root"] == os.path.realpath(sys.argv[2])
assert payload["consumer"]["project_hooks"] == "drifted"
checks = {item["id"]: item for item in payload["checks"]}
assert len(checks) == 7
assert checks["ai_tool_entry"]["status"] == "attention"
assert checks["required_materials"]["status"] == "normal"
assert checks["documents_and_history"]["status"] == "normal"
assert checks["product_files"]["status"] == "normal"
assert checks["active_work"]["status"] == "normal"
assert checks["project_safety"]["status"] == "normal"
assert [item["check_id"] for item in payload["pm_report"]["action_items"]] == ["ai_tool_entry"]
assert all(
    item["status"] in {"attention", "problem"}
    for item in payload["pm_report"]["action_items"]
)
assert payload["pm_report"]["action_items"][0]["repair_actions"] == [{
    "id": "sync_consumer_entry",
    "target": "AGENTS.md",
    "availability": "automatic",
    "confirmation_required": True,
}]
PY
  then
    _fail "消费仓 hooks 漂移应保持只读并返回唯一同步建议"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_doctor_keeps_product_progress_out_of_health() {
  start_test "T12h: refreshed project entry stays healthy while unfinished module scope is only progress"
  local setup tmp pmai_home fake_home consumer out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  consumer="$tmp/consumer-progress"
  if ! bash "$REPO_ROOT/scripts/init-project.sh" DoctorProgressFixture "$consumer" \
    "doctor progress fixture" >/dev/null 2>&1; then
    _fail "unable to initialize progress fixture"
    rm -rf "$tmp"
    return
  fi
  mkdir -p "$consumer/docs/modules/demo" "$consumer/apps/web"
  printf '# Discussion\n' > "$consumer/docs/modules/demo/discussion.md"
  printf '# Decisions\n' > "$consumer/docs/modules/demo/decisions.md"
  printf '# Spec\n' > "$consumer/docs/modules/demo/spec.md"
  printf 'export const demo = true;\n' > "$consumer/apps/web/index.ts"
  printf '\n- [demo](demo/spec.md)\n' >> "$consumer/docs/modules/INDEX.md"
  python3 "$REPO_ROOT/scripts/project-definition.py" write "$consumer" \
    --source docs/modules/demo/spec.md \
    --type prototype \
    --root apps/web \
    --entrypoint apps/web \
    --language typescript \
    --runtime node \
    --framework nextjs \
    --package-manager pnpm \
    --test-command "echo ok" >/dev/null || {
      _fail "unable to write progress project definition"
      rm -rf "$tmp"
      return
    }
  cat > "$consumer/docs/modules/demo/.work-meta.json" <<'JSON'
{
  "id": "work-demo",
  "name": "demo",
  "status": "active",
  "stage": 1,
  "lifecycle_state": "ready_to_build",
  "design_revision": 1,
  "approved_source_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "design_checkpoint_commit": "fixture"
}
JSON
  git -C "$consumer" add -A >/dev/null \
    && git -C "$consumer" commit --no-verify -m "test: progress only" >/dev/null

  out=$(cd "$consumer" && PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$pmai_home/bin/pmai-doctor" --check --json 2>"$tmp/consumer-progress.err")
  rc=$?
  if [ "$rc" != "0" ] || ! python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["conclusion"] == "healthy"
assert payload["recommended_action"] == "none"
assert payload["consumer"]["project_hooks"] == "current"
assert payload["consumer"]["opencode"] == "current"
assert payload["consumer"]["git_hook"] == "current"
assert all(item["status"] == "normal" for item in payload["checks"])
assert payload["product_progress"]["phase"] == "ready_to_build"
assert payload["product_progress"]["notes"] == [
    "模块还没有确定这次要修改的页面或文件，暂不能开始制作"
]
assert any(item.get("code") == "ready_target_missing" for item in payload["findings"])
PY
  then
    _fail "product progress should not change the health conclusion after project entry refresh"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_doctor_reports_invalid_consumer_structure() {
  start_test "T12f: doctor 把消费仓结构损坏与宿主待同步分开"
  local setup tmp pmai_home fake_home consumer out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  consumer="$tmp/consumer-invalid"
  if ! bash "$REPO_ROOT/scripts/init-project.sh" DoctorInvalidFixture "$consumer" \
    "doctor invalid fixture" >/dev/null 2>&1; then
    _fail "unable to initialize invalid consumer fixture"
    rm -rf "$tmp"
    return
  fi
  cat > "$pmai_home/scripts/install-project-hooks.sh" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "--check" ] || exit 2
exit 1
SH
  rm -f "$consumer/PRODUCT.md"
  printf '# Roadmap\n' > "$consumer/docs/ROADMAP.md"

  out=$(cd "$consumer" && PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$pmai_home/bin/pmai-doctor" --check --json 2>"$tmp/consumer-invalid.err")
  rc=$?
  if [ "$rc" = "0" ] || ! python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["conclusion"] == "consumer_invalid"
assert payload["recommended_action"] == "review_consumer_structure"
assert payload["consumer"]["topology_status"] == "invalid"
assert payload["consumer"]["phase"] == "initialized"
assert payload["consumer"]["project_hooks"] == "drifted"
assert payload["consumer"]["opencode"] == "current"
assert payload["consumer"]["git_hook"] == "current"
assert payload["consumer"]["audit"]["status"] == "invalid"
checks = {item["id"]: item for item in payload["checks"]}
assert checks["ai_tool_entry"]["status"] == "attention"
assert checks["required_materials"]["status"] == "problem"
assert checks["documents_and_history"]["status"] == "attention"
assert checks["documents_and_history"]["problems"] == [
    "docs/ 顶层文档没有归入当前分类目录：docs/ROADMAP.md"
]
assert any(item["code"] == "missing_required_file" for item in payload["consumer"]["audit"]["findings"])
assert any(
    item.get("code") == "missing_required_file"
    and item.get("kind") == "project_content_invalid"
    and item.get("blocking") is True
    and item.get("category") == "consumer"
    for item in payload["findings"]
)
PY
  then
    _fail "invalid consumer structure should return its own nonzero conclusion"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_doctor_reports_unversioned_legacy_as_compatibility_sync() {
  start_test "T12g: doctor 把未标版本旧模块归为兼容声明而非内容损坏"
  local setup tmp pmai_home fake_home consumer out current_out rc replacement

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  consumer="$tmp/consumer-legacy"
  if ! bash "$REPO_ROOT/scripts/init-project.sh" DoctorLegacyFixture "$consumer" \
    "doctor legacy fixture" >/dev/null 2>&1; then
    _fail "unable to initialize legacy consumer fixture"
    rm -rf "$tmp"
    return
  fi
  replacement="$consumer/.pm-workflow/config.yml.unversioned"
  sed -n '/^builder:/,$p' "$consumer/.pm-workflow/config.yml" > "$replacement" \
    && mv "$replacement" "$consumer/.pm-workflow/config.yml"
  mkdir -p "$consumer/docs/modules/legacy-pair"
  printf '# Legacy specification\nExisting rules.\n' > "$consumer/docs/modules/legacy-pair/spec.md"
  printf '# Legacy decisions\nExisting history.\n' > "$consumer/docs/modules/legacy-pair/decisions.md"
  printf '\n- legacy-pair\n' >> "$consumer/docs/modules/INDEX.md"
  git -C "$consumer" add -A >/dev/null \
    && git -C "$consumer" commit --no-verify -m "test: legacy layout" >/dev/null

  out=$(cd "$consumer" && PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$pmai_home/bin/pmai-doctor" --check --json 2>"$tmp/consumer-legacy.err")
  rc=$?
  if [ "$rc" != "0" ] || ! python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["conclusion"] == "consumer_sync_required"
assert payload["recommended_action"] == "declare_consumer_compatibility"
assert payload["consumer"]["topology_status"] == "sync_required"
assert payload["consumer"]["audit"]["classification_summary"]["project_content_invalid"] == 0
assert any(
    item.get("kind") == "compatibility_declaration_required"
    and item.get("blocking") is False
    and item.get("category") == "consumer"
    for item in payload["findings"]
)
assert all(
    item["check_id"] == "documents_and_history"
    for item in payload["pm_report"]["action_items"]
)
PY
  then
    _fail "legacy compatibility should remain a nonblocking consumer sync"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi

  cat > "$consumer/.pm-workflow/config.yml" <<'YAML'
consumer:
  schema_version: 1
  layout_version: 1
  paths:
    archive: docs/archive
  compatibility:
    module_legacy_pair:
      path: docs/modules/legacy-pair
      state: legacy
      format: spec_decisions
builder:
  profiles:
    fixture:
      executor: manual
YAML
  current_out=$(cd "$consumer" && PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$pmai_home/bin/pmai-doctor" --check --json 2>"$tmp/consumer-legacy-current.err")
  rc=$?
  if [ "$rc" != "0" ] || ! python3 - "$current_out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["conclusion"] == "healthy"
assert payload["pm_report"]["action_items"] == []
legacy_notices = [
    item for item in payload["pm_report"]["notices"]
    if item["category"] == "legacy_compatible"
]
assert len(legacy_notices) == 1
assert "legacy-pair" in legacy_notices[0]["message"]
PY
  then
    _fail "declared legacy modules should be reference notices, not action items"
    echo "$current_out" >&2
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_doctor_skill_separates_status_doctor_and_upgrade() {
  start_test "T12e: Doctor Skill 使用 PM 摘要、结构化入口修复和联网版本复查"
  local skill="$SKILLS_DIR/doctor/SKILL.md"

  if ! grep -q '/pmai-status.*产品进度' "$skill" \
    || ! grep -q '/pmai-doctor.*框架是否健康' "$skill" \
    || ! grep -q '/pmai-upgrade.*执行已经确认' "$skill" \
    || ! grep -q '修复必须二次确认' "$skill" \
    || ! grep -q 'doctor --repair --json' "$skill" \
    || ! grep -q '正常项也不能省略' "$skill" \
    || ! grep -q 'PMAI 安装' "$skill" \
    || ! grep -q 'AI 工具接入' "$skill" \
    || ! grep -q '项目必需资料' "$skill" \
    || ! grep -q '文档与历史资料' "$skill" \
    || ! grep -q '原型和产品文件' "$skill" \
    || ! grep -q '正在进行的工作' "$skill" \
    || ! grep -q '项目安全' "$skill" \
    || ! grep -q '项目进度提示' "$skill" \
    || ! grep -q '不参与总结论' "$skill" \
    || ! grep -q 'pm_report.action_items' "$skill" \
    || ! grep -q 'pm_report.notices' "$skill" \
    || ! grep -q 'sync_consumer_entry' "$skill" \
    || ! grep -q 'sync-consumer-entry.py' "$skill" \
    || ! grep -q '宿主.*联网' "$skill" \
    || ! grep -q 'ls-remote --heads origin refs/heads/main' "$skill"; then
    _fail "Doctor Skill 未完整声明 status / doctor / upgrade 和用户输出边界"
    return
  fi
  pass_test
}

prepare_install_target_repo() {
  local source_repo="$1"
  local doctor_mode="$2"
  local policy_mode="$3"

  git clone -q --no-hardlinks "$REPO_ROOT" "$source_repo" || return 1
  cp "$REPO_ROOT/scripts/_lib/skill-links.sh" "$source_repo/scripts/_lib/skill-links.sh"
  cp "$REPO_ROOT/scripts/install-opencode-commands.sh" \
    "$source_repo/scripts/install-opencode-commands.sh"
  cp "$REPO_ROOT/scripts/manage-kimi-hooks.py" "$source_repo/scripts/manage-kimi-hooks.py"
  copy_global_lock_helpers_to "$source_repo"

  if [ "$policy_mode" = "hide-design" ]; then
    cat >> "$source_repo/scripts/_lib/skill-links.sh" <<'SH'

pmai_skill_is_host_exposed() {
  [ "$1" != "design" ]
}
SH
  fi

  case "$doctor_mode" in
    fail)
      cat > "$source_repo/bin/pmai-doctor" <<'SH'
#!/usr/bin/env bash
echo "target doctor rejected install" >&2
exit 31
SH
      ;;
    assert-target-policy)
      cat > "$source_repo/bin/pmai-doctor" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
for host_dir in "$HOME/.claude/skills" "${CODEX_HOME:-$HOME/.codex}/skills" "${KIMI_CODE_HOME:-$HOME/.kimi-code}/skills"; do
  [ -L "$host_dir/pmai-build" ] || { echo "missing target pmai-build: $host_dir" >&2; exit 1; }
  [ "$(readlink "$host_dir/pmai-build")" = "$PMAI_HOME/skills/build" ] \
    || { echo "wrong target pmai-build: $host_dir" >&2; exit 1; }
  [ ! -e "$host_dir/pmai-design" ] && [ ! -L "$host_dir/pmai-design" ] \
    || { echo "target policy leaked pmai-design: $host_dir" >&2; exit 1; }
done
[ -f "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/commands/pmai-build.md" ] \
  || { echo "missing target OpenCode pmai-build" >&2; exit 1; }
[ ! -e "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/commands/pmai-design.md" ] \
  || { echo "target policy leaked OpenCode pmai-design" >&2; exit 1; }
exit 0
SH
      ;;
    *) return 2 ;;
  esac

  chmod +x "$source_repo/bin/pmai-doctor" \
    "$source_repo/scripts/install-opencode-commands.sh" \
    "$source_repo/scripts/manage-kimi-hooks.py"
  git -C "$source_repo" add bin/pmai-doctor scripts/_lib/skill-links.sh \
    scripts/_lib/global-install-lock.sh scripts/_lib/global_install_lock.py \
    scripts/_lib/kimi-config-transaction.sh \
    scripts/install-opencode-commands.sh scripts/manage-kimi-hooks.py
  git -C "$source_repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid \
    commit -q --allow-empty -m "install transaction target fixture"
}

test_install_doctor_failure_restores_every_global_surface() {
  start_test "T23: install 目标 doctor 失败时完整回滚所有全局宿主面"
  local tmp source_repo pmai_home fake_home legacy_target tmpdir out rc host_dir
  local old_prompt old_command old_kimi kimi_target

  tmp=$(mktemp -d /tmp/pmai-install-rollback-XXXXXX)
  source_repo="$tmp/source"
  pmai_home="$tmp/pmai-home"
  fake_home="$tmp/home"
  legacy_target="$tmp/legacy/design"
  tmpdir="$tmp/tmp"
  mkdir -p "$legacy_target" "$tmpdir" \
    "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.codex/prompts" "$fake_home/.kimi-code/skills" \
    "$fake_home/.config/opencode/commands"
  if ! prepare_install_target_repo "$source_repo" fail current; then
    _fail "无法创建 install 回滚目标 fixture"
    rm -rf "$tmp"
    return
  fi

  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"; do
    ln -s "$legacy_target" "$host_dir/pmai-design"
    ln -s "$pmai_home/skills/_shared" "$host_dir/_shared"
  done
  old_prompt='legacy codex prompt'
  old_command='legacy opencode command'
  old_kimi='default_model = "legacy"'
  kimi_target="$fake_home/kimi-config-target.toml"
  printf '%s\n' "$old_prompt" > "$fake_home/.codex/prompts/pmai-design.md"
  printf '%s\n' "$old_command" > "$fake_home/.config/opencode/commands/pmai-design.md"
  printf '%s\n' "$old_kimi" > "$kimi_target"
  ln -s "$kimi_target" "$fake_home/.kimi-code/config.toml"

  out=$(TMPDIR="$tmpdir" HOME="$fake_home" PMAI_HOME="$pmai_home" \
    PMAI_REMOTE="$source_repo" PMAI_GLOBAL_INSTALL_LOCK_PATH="$tmp/global.lock" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" bash "$INSTALL" 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "目标 doctor 失败时 install 不得报告成功"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if [ -e "$pmai_home" ] || [ -L "$pmai_home" ]; then
    _fail "失败安装本轮创建的 clone 未删除"
    rm -rf "$tmp"
    return
  fi
  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"; do
    if [ ! -L "$host_dir/pmai-design" ] \
      || [ "$(readlink "$host_dir/pmai-design")" != "$legacy_target" ]; then
      _fail "失败安装未恢复旧 Host skill：$host_dir/pmai-design"
      rm -rf "$tmp"
      return
    fi
    if [ ! -L "$host_dir/_shared" ] \
      || [ "$(readlink "$host_dir/_shared")" != "$pmai_home/skills/_shared" ]; then
      _fail "失败安装未恢复原 _shared 状态：$host_dir/_shared"
      rm -rf "$tmp"
      return
    fi
    if [ -e "$host_dir/pmai-build" ] || [ -L "$host_dir/pmai-build" ]; then
      _fail "失败安装遗留本轮新建 Host skill：$host_dir/pmai-build"
      rm -rf "$tmp"
      return
    fi
  done
  if [ "$(cat "$fake_home/.codex/prompts/pmai-design.md")" != "$old_prompt" ]; then
    _fail "失败安装未恢复 legacy Codex prompt"
  elif [ "$(cat "$fake_home/.config/opencode/commands/pmai-design.md")" != "$old_command" ]; then
    _fail "失败安装未恢复 OpenCode command"
  elif [ -e "$fake_home/.config/opencode/commands/pmai-build.md" ] \
    || [ -L "$fake_home/.config/opencode/commands/pmai-build.md" ]; then
    _fail "失败安装遗留本轮新建 OpenCode command"
  elif [ ! -L "$fake_home/.kimi-code/config.toml" ] \
    || [ "$(readlink "$fake_home/.kimi-code/config.toml")" != "$kimi_target" ] \
    || [ "$(cat "$kimi_target")" != "$old_kimi" ]; then
    _fail "失败安装未恢复 Kimi config symlink 原始形态"
  elif find "$fake_home" \( -name '.pmai-install-backup.*' \
    -o -name '.pmai-install-kimi-backup.*' \) -print -quit | grep -q .; then
    _fail "失败安装回滚后遗留 surface backup"
  else
    pass_test
  fi

  rm -rf "$tmp"
}

test_install_uses_cloned_target_exposure_policy() {
  start_test "T24/T33: install 按目标版本生成入口并清理已移除的 direction"
  local tmp source_repo pmai_home fake_home kimi_target out rc host_dir

  tmp=$(mktemp -d /tmp/pmai-install-policy-XXXXXX)
  source_repo="$tmp/source"
  pmai_home="$tmp/pmai-home"
  fake_home="$tmp/home"
  mkdir -p "$tmp/tmp" "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.kimi-code/skills" "$fake_home/.config/opencode/commands"
  if ! prepare_install_target_repo "$source_repo" assert-target-policy hide-design; then
    _fail "无法创建 install 目标策略 fixture"
    rm -rf "$tmp"
    return
  fi
  rm -rf "$source_repo/skills/direction"
  git -C "$source_repo" add -A -- skills/direction
  if ! git -C "$source_repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid \
    commit -q --allow-empty -m "remove retired direction skill"; then
    _fail "无法创建不含 direction 的 install 目标 fixture"
    rm -rf "$tmp"
    return
  fi
  seed_retired_direction_entries "$pmai_home" "$fake_home"
  kimi_target="$fake_home/kimi-config-target.toml"
  printf 'default_model = "legacy"\n' > "$kimi_target"
  ln -s "$kimi_target" "$fake_home/.kimi-code/config.toml"

  out=$(TMPDIR="$tmp/tmp" HOME="$fake_home" PMAI_HOME="$pmai_home" \
    PMAI_REMOTE="$source_repo" PMAI_GLOBAL_INSTALL_LOCK_PATH="$tmp/global.lock" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" bash "$INSTALL" 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "目标版本 policy 合法时 install 应成功"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! assert_retired_direction_entries_absent "$fake_home"; then
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"; do
    if [ ! -L "$host_dir/pmai-build" ] \
      || [ "$(readlink "$host_dir/pmai-build")" != "$pmai_home/skills/build" ]; then
      _fail "目标 policy 未安装公开 skill：$host_dir/pmai-build"
      rm -rf "$tmp"
      return
    fi
    if [ -e "$host_dir/pmai-design" ] || [ -L "$host_dir/pmai-design" ]; then
      _fail "install 沿用了 clone 前策略并错误暴露 design：$host_dir"
      rm -rf "$tmp"
      return
    fi
  done
  if [ ! -f "$fake_home/.config/opencode/commands/pmai-build.md" ] \
    || [ -e "$fake_home/.config/opencode/commands/pmai-design.md" ]; then
    _fail "OpenCode commands 未遵守 clone 后目标版本策略"
  elif [ ! -L "$fake_home/.kimi-code/config.toml" ] \
    || [ "$(readlink "$fake_home/.kimi-code/config.toml")" != "$kimi_target" ] \
    || ! grep -q '^# >>> PMAI managed Kimi Code hooks >>>$' "$kimi_target"; then
    _fail "成功安装未保持 Kimi config symlink 并更新其目标内容"
  else
    pass_test
  fi

  rm -rf "$tmp"
}

test_install_preserves_dangling_pmai_home_symlink() {
  start_test "T28: install 拒绝 dangling PMAI_HOME 且保留原 symlink"
  local tmp fake_home pmai_home missing_target out rc

  tmp=$(mktemp -d /tmp/pmai-install-dangling-home-XXXXXX)
  fake_home="$tmp/home"
  pmai_home="$tmp/pmai-home"
  missing_target="$tmp/missing-install"
  mkdir -p "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.kimi-code/skills" "$fake_home/.config/opencode/commands"
  ln -s "$missing_target" "$pmai_home"

  out=$(HOME="$fake_home" PMAI_HOME="$pmai_home" PMAI_REMOTE="$tmp/not-used" \
    PMAI_GLOBAL_INSTALL_LOCK_PATH="$tmp/global.lock" CODEX_HOME="$fake_home/.codex" \
    KIMI_CODE_HOME="$fake_home/.kimi-code" OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$INSTALL" 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "dangling PMAI_HOME 不得进入 clone"
    echo "$out" >&2
  elif [ ! -L "$pmai_home" ] || [ "$(readlink "$pmai_home")" != "$missing_target" ]; then
    _fail "install 错误删除或改写了既有 dangling PMAI_HOME"
    echo "$out" >&2
  else
    pass_test
  fi
  rm -rf "$tmp"
}

test_doctor_preserves_logical_pmai_home_targets() {
  start_test "T29: doctor 用 logical PMAI_HOME 精确校验 Host symlink target"
  local setup tmp pmai_home fake_home logical_home host_dir sk name exposed out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  logical_home="$tmp/logical-pmai-home"
  ln -s "$pmai_home" "$logical_home"

  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"; do
    rm -rf "$host_dir"
    mkdir -p "$host_dir"
    while IFS= read -r sk; do
      name=$(basename "$sk")
      expected_skill_is_host_exposed "$name" || continue
      exposed=$(exposed_name_for_skill "$name")
      ln -s "$logical_home/skills/$name" "$host_dir/$exposed"
    done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name _shared ! -name _internal | sort)
    ln -s "$logical_home/skills/_shared" "$host_dir/_shared"
  done

  out=$(PMAI_HOME="$logical_home" HOME="$fake_home" \
    PMAI_GLOBAL_INSTALL_LOCK_PATH="$tmp/global.lock" CODEX_HOME="$fake_home/.codex" \
    KIMI_CODE_HOME="$fake_home/.kimi-code" OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    bash "$pmai_home/bin/pmai-doctor" 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "logical PMAI_HOME 与 CLI_ROOT 指向同一安装时 doctor 应通过"
    echo "$out" >&2
  elif [ "$(readlink "$fake_home/.codex/skills/pmai-design")" \
    != "$logical_home/skills/design" ]; then
    _fail "doctor 把 logical Host target 改写成了 physical path"
  else
    pass_test
  fi
  rm -rf "$tmp"
}

UPGRADE_ROLLBACK_REMOTE=""
UPGRADE_ROLLBACK_OLD_HEAD=""
UPGRADE_ROLLBACK_TAG=""

prepare_upgrade_rollback_fixture() {
  local tmp="$1"
  local source_repo="$tmp/source"
  local remote="$tmp/origin.git"

  if ! git clone -q --no-hardlinks "$REPO_ROOT" "$source_repo"; then
    return 1
  fi

  # 模拟旧版本还没有 exposure policy helper。repo-local 当前 updater 仍可驱动它，
  # 回滚时必须清空目标策略并回到旧版全公开 fallback。
  rm -f "$source_repo/scripts/_lib/skill-links.sh"
  git -C "$source_repo" add -A scripts/_lib/skill-links.sh
  if ! git -C "$source_repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid \
    commit -q -m "legacy install without exposure helper"; then
    return 1
  fi
  UPGRADE_ROLLBACK_OLD_HEAD=$(git -C "$source_repo" rev-parse HEAD)

  cp "$REPO_ROOT/scripts/_lib/skill-links.sh" "$source_repo/scripts/_lib/skill-links.sh"
  cat >> "$source_repo/scripts/_lib/skill-links.sh" <<'SH'

pmai_skill_is_host_exposed() {
  [ "$1" != "design" ]
}
SH
  cat > "$source_repo/scripts/manage-kimi-hooks.py" <<'PY'
#!/usr/bin/env python3
import os
from pathlib import Path

path = Path(os.environ["KIMI_CODE_HOME"]) / "config.toml"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text('created_by_target = true\n', encoding='utf-8')
PY
  cat > "$source_repo/bin/pmai-doctor" <<'SH'
#!/usr/bin/env bash
signal_name="${PMAI_TEST_SIGNAL:-}"
if [ -n "$signal_name" ]; then
  kill -s "$signal_name" "$PPID"
  exit 0
fi
echo "target doctor rejected upgrade" >&2
exit 41
SH
  chmod +x "$source_repo/bin/pmai-doctor" "$source_repo/scripts/manage-kimi-hooks.py"
  git -C "$source_repo" add bin/pmai-doctor scripts/_lib/skill-links.sh \
    scripts/manage-kimi-hooks.py
  if ! git -C "$source_repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid \
    commit -q -m "failing restrictive upgrade target"; then
    return 1
  fi
  UPGRADE_ROLLBACK_TAG="v0.0.0-test-rollback-transaction"
  git -C "$source_repo" tag "$UPGRADE_ROLLBACK_TAG"
  if ! git clone -q --bare "$source_repo" "$remote"; then
    return 1
  fi
  UPGRADE_ROLLBACK_REMOTE="$remote"
}

clone_upgrade_rollback_baseline() {
  local install="$1"
  local initial_state="$2"

  git clone -q "$UPGRADE_ROLLBACK_REMOTE" "$install" || return 1
  git -C "$install" reset -q --hard "$UPGRADE_ROLLBACK_OLD_HEAD" || return 1
  if [ "$initial_state" = "detached" ]; then
    git -C "$install" checkout -q --detach "$UPGRADE_ROLLBACK_OLD_HEAD" || return 1
  fi
}

assert_upgrade_rollback_state() {
  local install="$1"
  local fake_home="$2"
  local initial_state="$3"
  local actual_ref host_dir

  if [ "$(git -C "$install" rev-parse HEAD)" != "$UPGRADE_ROLLBACK_OLD_HEAD" ]; then
    _fail "upgrade rollback 未恢复原 commit：$initial_state"
    return 1
  fi
  actual_ref=$(git -C "$install" symbolic-ref -q HEAD 2>/dev/null || true)
  if [ "$initial_state" = "branch" ] && [ "$actual_ref" != "refs/heads/main" ]; then
    _fail "upgrade rollback 未恢复 refs/heads/main：${actual_ref:-detached}"
    return 1
  fi
  if [ "$initial_state" = "detached" ] && [ -n "$actual_ref" ]; then
    _fail "upgrade rollback 把原 detached HEAD 错误附着到 $actual_ref"
    return 1
  fi
  if [ -e "$fake_home/.kimi-code/config.toml" ] \
    || [ -L "$fake_home/.kimi-code/config.toml" ]; then
    _fail "升级前不存在的 Kimi config 在回滚后仍然残留"
    return 1
  fi
  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"; do
    if [ ! -L "$host_dir/pmai-design" ] \
      || [ "$(readlink "$host_dir/pmai-design")" != "$install/skills/design" ]; then
      _fail "旧版缺 helper 时未按全公开 fallback 恢复 pmai-design：$host_dir"
      return 1
    fi
  done
  return 0
}

test_upgrade_to_doctor_failure_restores_branch_kimi_and_legacy_policy() {
  start_test "T25: --to doctor 失败恢复 main、空 Kimi 状态和旧版 fallback"
  local tmp install fake_home state out rc

  tmp=$(mktemp -d /tmp/pmai-upgrade-rollback-fixture-XXXXXX)
  if ! prepare_upgrade_rollback_fixture "$tmp"; then
    _fail "无法创建 upgrade 回滚 fixture"
    rm -rf "$tmp"
    return
  fi
  install="$tmp/install-failure"
  fake_home="$tmp/home-failure"
  state="$tmp/state-failure"
  mkdir -p "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.kimi-code/skills" "$fake_home/.config/opencode/commands" "$state"
  if ! clone_upgrade_rollback_baseline "$install" branch; then
    _fail "无法创建 upgrade main baseline"
    rm -rf "$tmp"
    return
  fi

  out=$(HOME="$fake_home" PMAI_HOME="$install" PMAI_STATE="$state" \
    PMAI_GLOBAL_INSTALL_LOCK_PATH="$tmp/failure.lock" CODEX_HOME="$fake_home/.codex" \
    KIMI_CODE_HOME="$fake_home/.kimi-code" OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    PMAI_UPGRADE_DOCTOR_LOG="$tmp/failure-doctor.log" \
    bash "$UPGRADE" --to "$UPGRADE_ROLLBACK_TAG" --no-whats-new 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "目标 doctor 失败时 --to 不得成功"
    echo "$out" >&2
  elif ! assert_upgrade_rollback_state "$install" "$fake_home" branch; then
    echo "$out" >&2
  else
    pass_test
  fi

  rm -rf "$tmp"
}

test_upgrade_doctor_failure_restores_kimi_config_symlink() {
  start_test "T27: upgrade doctor 失败恢复 Kimi config symlink 原始形态"
  local tmp install fake_home state kimi_target out rc

  tmp=$(mktemp -d /tmp/pmai-upgrade-kimi-symlink-XXXXXX)
  if ! prepare_upgrade_rollback_fixture "$tmp"; then
    _fail "无法创建 upgrade Kimi symlink fixture"
    rm -rf "$tmp"
    return
  fi
  install="$tmp/install"
  fake_home="$tmp/home"
  state="$tmp/state"
  kimi_target="$fake_home/kimi-config-target.toml"
  mkdir -p "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.kimi-code/skills" "$fake_home/.config/opencode/commands" "$state"
  clone_upgrade_rollback_baseline "$install" branch || {
    _fail "无法创建 upgrade Kimi symlink baseline"
    rm -rf "$tmp"
    return
  }
  printf 'default_model = "legacy"\n' > "$kimi_target"
  ln -s "$kimi_target" "$fake_home/.kimi-code/config.toml"

  out=$(HOME="$fake_home" PMAI_HOME="$install" PMAI_STATE="$state" \
    PMAI_GLOBAL_INSTALL_LOCK_PATH="$tmp/global.lock" CODEX_HOME="$fake_home/.codex" \
    KIMI_CODE_HOME="$fake_home/.kimi-code" OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    PMAI_UPGRADE_DOCTOR_LOG="$tmp/doctor.log" \
    bash "$UPGRADE" --to "$UPGRADE_ROLLBACK_TAG" --no-whats-new 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "目标 doctor 失败时 upgrade 不得报告成功"
    echo "$out" >&2
  elif [ ! -L "$fake_home/.kimi-code/config.toml" ] \
    || [ "$(readlink "$fake_home/.kimi-code/config.toml")" != "$kimi_target" ] \
    || [ "$(cat "$kimi_target")" != 'default_model = "legacy"' ]; then
    _fail "upgrade 回滚未恢复 Kimi config symlink 原始形态"
    echo "$out" >&2
  elif find "$fake_home/.kimi-code" -name '.pmai-upgrade-kimi-backup.*' \
    -print -quit | grep -q .; then
    _fail "upgrade 回滚遗留 Kimi config backup"
  else
    pass_test
  fi
  rm -rf "$tmp"
}

test_kimi_config_transaction_covers_all_entry_states() {
  start_test "T30: Kimi config 四态 transaction 的 commit / rollback 都保持原始形态"
  local tmp helper kind action case_dir config target artifact expected

  tmp=$(mktemp -d /tmp/pmai-kimi-config-matrix-XXXXXX)
  helper="$REPO_ROOT/scripts/_lib/kimi-config-transaction.sh"
  for kind in file symlink-live symlink-dangling missing; do
    for action in commit rollback; do
      case_dir="$tmp/$kind-$action"
      config="$case_dir/kimi/config.toml"
      target="$case_dir/referents/live.toml"
      mkdir -p "$(dirname "$config")" "$(dirname "$target")"
      case "$kind" in
        file)
          printf 'value = "original"\n' > "$config"
          ;;
        symlink-live)
          printf 'value = "original"\n' > "$target"
          ln -s ../referents/live.toml "$config"
          ;;
        symlink-dangling)
          ln -s ../referents/missing.toml "$config"
          ;;
        missing) ;;
      esac

      if ! (
        set -Eeuo pipefail
        # shellcheck disable=SC1090
        source "$helper"
        pmai_kimi_config_tx_snapshot "$config" ".pmai-matrix-backup"
        if pmai_kimi_config_tx_needs_check; then
          printf 'value = "updated"\n' > "$config"
        fi
        if [ "$action" = "commit" ]; then
          pmai_kimi_config_tx_finalize
          pmai_kimi_config_tx_cleanup "matrix commit "
        else
          pmai_kimi_config_tx_restore
        fi
      ); then
        _fail "Kimi config transaction failed for $kind/$action"
        rm -rf "$tmp"
        return
      fi

      expected='value = "original"'
      [ "$action" = "commit" ] && expected='value = "updated"'
      case "$kind" in
        file)
          if [ ! -f "$config" ] || [ -L "$config" ] \
            || [ "$(cat "$config")" != "$expected" ]; then
            _fail "regular config state drifted after $action"
            rm -rf "$tmp"
            return
          fi
          ;;
        symlink-live)
          if [ ! -L "$config" ] \
            || [ "$(readlink "$config")" != "../referents/live.toml" ] \
            || [ "$(cat "$target")" != "$expected" ]; then
            _fail "live symlink state drifted after $action"
            rm -rf "$tmp"
            return
          fi
          ;;
        symlink-dangling)
          if [ ! -L "$config" ] \
            || [ "$(readlink "$config")" != "../referents/missing.toml" ] \
            || [ -e "$case_dir/referents/missing.toml" ]; then
            _fail "dangling symlink state drifted after $action"
            rm -rf "$tmp"
            return
          fi
          ;;
        missing)
          if [ -e "$config" ] || [ -L "$config" ]; then
            _fail "missing config was materialized after $action"
            rm -rf "$tmp"
            return
          fi
          ;;
      esac

      artifact=$(find "$case_dir" \
        \( -name '.pmai-matrix-backup.*' -o -name '.pmai-kimi-config-stage.*' \) \
        -print -quit)
      if [ -n "$artifact" ]; then
        _fail "Kimi config transaction leaked recovery material: $artifact"
        rm -rf "$tmp"
        return
      fi
    done
  done

  rm -rf "$tmp"
  pass_test
}

test_kimi_config_transaction_preserves_concurrent_referent_edit() {
  start_test "T30b: Kimi symlink referent 并发修改触发 CAS 且不被回滚覆盖"
  local tmp helper config target out rc

  tmp=$(mktemp -d /tmp/pmai-kimi-config-concurrent-XXXXXX)
  helper="$REPO_ROOT/scripts/_lib/kimi-config-transaction.sh"
  config="$tmp/kimi/config.toml"
  target="$tmp/referents/live.toml"
  mkdir -p "$(dirname "$config")" "$(dirname "$target")"
  printf 'value = "original"\n' > "$target"
  ln -s ../referents/live.toml "$config"

  out=$( (
      set -Eeuo pipefail
      source "$helper"
      pmai_kimi_config_tx_snapshot "$config" ".pmai-concurrent-backup"
      printf 'value = "pmai-update"\n' > "$config"
      printf 'value = "external-update"\n' > "$target"
      if pmai_kimi_config_tx_finalize; then
        exit 0
      else
        finalize_rc=$?
      fi
      pmai_kimi_config_tx_restore || true
      exit "$finalize_rc"
    ) 2>&1 )
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "concurrent referent edit should reject finalize"
  elif [ ! -L "$config" ] \
    || [ "$(readlink "$config")" != "../referents/live.toml" ] \
    || [ "$(cat "$target")" != 'value = "external-update"' ]; then
    _fail "concurrent referent edit was overwritten or symlink shape drifted: $out"
  else
    pass_test
  fi
  rm -rf "$tmp"
}

test_upgrade_preserves_dirty_tree_before_git_rollback_is_safe() {
  start_test "T31: upgrade 前置 status/stash/signal/snapshot 失败不丢本地改动"
  local tmp real_git mode case_dir install fake_home fake_bin expected out rc stash_out

  tmp=$(mktemp -d /tmp/pmai-upgrade-dirty-protection-XXXXXX)
  real_git=$(command -v git)
  for mode in status-fail stash-fail stash-signal snapshot-fail; do
    case_dir="$tmp/$mode"
    install="$case_dir/install"
    fake_home="$case_dir/home"
    fake_bin="$case_dir/fake-bin"
    mkdir -p "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
      "$fake_home/.kimi-code/skills" "$fake_home/.config/opencode/commands" \
      "$case_dir/state" "$fake_bin"
    if ! git clone -q --no-hardlinks "$REPO_ROOT" "$install"; then
      _fail "无法创建 dirty protection fixture: $mode"
      rm -rf "$tmp"
      return
    fi
    printf '\nlocal tracked change: %s\n' "$mode" >> "$install/VERSION"
    printf 'local untracked change: %s\n' "$mode" > "$install/local-untracked.txt"
    expected=$(cat "$install/VERSION")
    if [ "$mode" = "snapshot-fail" ]; then
      mkdir -p "$fake_home/.kimi-code/config.toml"
    fi

    cat > "$fake_bin/git" <<'SH'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = "status" ] && [ "${2:-}" = "--porcelain" ] \
  && [ "$PMAI_TEST_GIT_MODE" = "status-fail" ]; then
  exit 42
fi
if [ "${1:-}" = "stash" ] && [ "${2:-}" = "push" ]; then
  case "$PMAI_TEST_GIT_MODE" in
    stash-fail) exit 43 ;;
    stash-signal)
      kill -TERM "$PPID"
      exit 143
      ;;
  esac
fi
exec "$PMAI_TEST_REAL_GIT" "$@"
SH
    chmod +x "$fake_bin/git"

    out=$(HOME="$fake_home" PMAI_HOME="$install" PMAI_STATE="$case_dir/state" \
      PMAI_GLOBAL_INSTALL_LOCK_PATH="$case_dir/global.lock" \
      CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
      OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
      PMAI_TEST_GIT_MODE="$mode" PMAI_TEST_REAL_GIT="$real_git" \
      PATH="$fake_bin:$PATH" \
      bash "$UPGRADE" --to v-does-not-matter --no-whats-new 2>&1)
    rc=$?
    if [ "$rc" = "0" ]; then
      _fail "upgrade 前置失败不得成功：$mode"
      echo "$out" >&2
      rm -rf "$tmp"
      return
    fi

    if [ "$mode" = "snapshot-fail" ]; then
      stash_out=$(git -C "$install" stash list)
      if [ -z "$stash_out" ] || ! git -C "$install" stash pop --index >/dev/null 2>&1; then
        _fail "snapshot 失败后 dirty tree 没有保存在可恢复 stash：$out"
        rm -rf "$tmp"
        return
      fi
    fi
    if [ "$(cat "$install/VERSION")" != "$expected" ] \
      || [ ! -f "$install/local-untracked.txt" ] \
      || [ "$(cat "$install/local-untracked.txt")" != "local untracked change: $mode" ]; then
      _fail "upgrade 前置失败删除或改写了本地改动：$mode"
      echo "$out" >&2
      rm -rf "$tmp"
      return
    fi
  done

  rm -rf "$tmp"
  pass_test
}

test_doctor_has_stock_macos_timeout_fallback() {
  start_test "T32: doctor 的 remote check 不依赖 stock macOS 缺失的 GNU timeout"
  if ! grep -q 'command -v gtimeout' "$DOCTOR" \
    || ! grep -q 'timeout() { shift; "$@"; }' "$DOCTOR"; then
    _fail "doctor should share the timeout/gtimeout/direct portability fallback"
  else
    pass_test
  fi
}

assert_upgrade_signal_rollback() {
  local fixture_tmp="$1"
  local signal_name="$2"
  local initial_state="$3"
  local expected_rc="$4"
  local case_dir="$fixture_tmp/case-${signal_name}-${initial_state}"
  local install="$case_dir/install"
  local fake_home="$case_dir/home"
  local state="$case_dir/state"
  local out rc

  mkdir -p "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.kimi-code/skills" "$fake_home/.config/opencode/commands" "$state"
  clone_upgrade_rollback_baseline "$install" "$initial_state" || return 1

  out=$(HOME="$fake_home" PMAI_HOME="$install" PMAI_STATE="$state" \
    PMAI_GLOBAL_INSTALL_LOCK_PATH="$case_dir/global.lock" CODEX_HOME="$fake_home/.codex" \
    KIMI_CODE_HOME="$fake_home/.kimi-code" OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" \
    PMAI_UPGRADE_DOCTOR_LOG="$case_dir/doctor.log" PMAI_TEST_SIGNAL="$signal_name" \
    bash "$UPGRADE" --to "$UPGRADE_ROLLBACK_TAG" --no-whats-new 2>&1)
  rc=$?

  if [ "$rc" != "$expected_rc" ]; then
    _fail "$signal_name 应以 $expected_rc 退出，实际 rc=$rc"
    echo "$out" >&2
    return 1
  fi
  if ! assert_upgrade_rollback_state "$install" "$fake_home" "$initial_state"; then
    echo "$out" >&2
    return 1
  fi
  return 0
}

test_upgrade_signals_restore_symbolic_and_detached_head() {
  start_test "T26: upgrade HUP/INT/TERM 均回滚并恢复原 HEAD 形态"
  local tmp

  tmp=$(mktemp -d /tmp/pmai-upgrade-signal-XXXXXX)
  if ! prepare_upgrade_rollback_fixture "$tmp"; then
    _fail "无法创建 upgrade signal fixture"
    rm -rf "$tmp"
    return
  fi
  if ! assert_upgrade_signal_rollback "$tmp" HUP branch 129 \
    || ! assert_upgrade_signal_rollback "$tmp" INT detached 130 \
    || ! assert_upgrade_signal_rollback "$tmp" TERM branch 143; then
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_upgrade_preserves_public_links_and_restores_rollback_policy() {
  start_test "T15/T33: upgrade 清理 direction，失败回滚恢复旧策略和入口集合"
  local tmp source_repo remote install fake_home state doctor_log current_upgrade
  local out rc candidate_head rollback_out rollback_rc final_head host_dir skill

  tmp=$(mktemp -d /tmp/pmai-upgrade-transition-XXXXXX)
  source_repo="$tmp/source"
  remote="$tmp/origin.git"
  install="$tmp/pmai-home"
  fake_home="$tmp/home"
  state="$tmp/state"
  doctor_log="$tmp/doctor.log"
  current_upgrade="$tmp/pmai-upgrade-current"

  if ! git clone -q --no-hardlinks "$REPO_ROOT" "$source_repo"; then
    _fail "无法创建升级源 fixture"
    rm -rf "$tmp"
    return
  fi
  cp "$UPGRADE" "$current_upgrade"
  cp "$DOCTOR" "$source_repo/bin/pmai-doctor"
  cp -R "$REPO_ROOT/skills/doctor" "$source_repo/skills/doctor"
  sync_current_skill_catalog_to_fixture "$source_repo"
  cp "$REPO_ROOT/scripts/_lib/skill-links.sh" "$source_repo/scripts/_lib/skill-links.sh"
  cp "$REPO_ROOT/scripts/install-opencode-commands.sh" "$source_repo/scripts/install-opencode-commands.sh"
  copy_global_lock_helpers_to "$source_repo"

  # 旧进程在 merge 前已载入不含暴露过滤的 rebuild_symlinks。
  sed \
    -e '/pmai_skill_is_host_exposed "$skill_name" || continue/d' \
    "$current_upgrade" > "$source_repo/bin/pmai-upgrade"
  chmod +x "$source_repo/bin/pmai-upgrade" "$source_repo/bin/pmai-doctor"
  git -C "$source_repo" add bin/pmai-upgrade bin/pmai-doctor skills/doctor \
    scripts/_lib/skill-links.sh scripts/_lib/global-install-lock.sh \
    scripts/_lib/global_install_lock.py scripts/_lib/kimi-config-transaction.sh \
    scripts/install-opencode-commands.sh
  if ! git -C "$source_repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid \
    commit -q -m "legacy updater fixture"; then
    _fail "无法提交旧 updater fixture"
    rm -rf "$tmp"
    return
  fi
  if ! git clone -q --bare "$source_repo" "$remote" \
    || ! git clone -q "$remote" "$install"; then
    _fail "无法创建本地升级 origin/install"
    rm -rf "$tmp"
    return
  fi

  cp "$current_upgrade" "$source_repo/bin/pmai-upgrade"
  git -C "$source_repo" add bin/pmai-upgrade
  if ! git -C "$source_repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid \
    commit -q -m "current updater fixture" \
    || ! git -C "$source_repo" push -q "$remote" main; then
    _fail "无法发布当前 updater fixture"
    rm -rf "$tmp"
    return
  fi
  candidate_head=$(git -C "$source_repo" rev-parse HEAD)

  mkdir -p "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.kimi-code/skills" "$fake_home/.config/opencode/commands" "$state"
  seed_retired_direction_entries "$install" "$fake_home"
  out=$(HOME="$fake_home" PMAI_HOME="$install" PMAI_STATE="$state" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" PMAI_REMOTE="$remote" \
    PMAI_UPGRADE_DOCTOR_LOG="$doctor_log" \
    bash "$install/bin/pmai-upgrade" --no-whats-new 2>&1)
  rc=$?

  if [ "$rc" != "0" ] || [ "$(git -C "$install" rev-parse HEAD)" != "$candidate_head" ]; then
    _fail "旧 updater 应升级成功且停在当前 candidate"
    echo "$out" >&2
    [ -f "$doctor_log" ] && cat "$doctor_log" >&2
    rm -rf "$tmp"
    return
  fi
  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"; do
    for skill in build-close publish-to-lark; do
      if [ ! -L "$host_dir/pmai-$skill" ]; then
        _fail "旧 updater 升级后缺少公开兼容入口 pmai-$skill: $host_dir"
        rm -rf "$tmp"
        return
      fi
    done
  done
  if ! assert_retired_direction_entries_absent "$fake_home"; then
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi

  # 模拟下一版改变暴露策略后 doctor 失败。回滚必须 reset 后重载旧 helper，
  # 否则 pmai-design 会继续被未来策略过滤，旧安装状态恢复不完整。
  sed 's/_internal|_shared)/_internal|_shared|design)/' \
    "$source_repo/scripts/_lib/skill-links.sh" > "$tmp/skill-links.future"
  mv "$tmp/skill-links.future" "$source_repo/scripts/_lib/skill-links.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$source_repo/bin/pmai-doctor"
  chmod +x "$source_repo/bin/pmai-doctor"
  git -C "$source_repo" add bin/pmai-doctor scripts/_lib/skill-links.sh
  if ! git -C "$source_repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid \
    commit -q -m "future policy failure fixture" \
    || ! git -C "$source_repo" push -q "$remote" main; then
    _fail "无法发布失败回滚 fixture"
    rm -rf "$tmp"
    return
  fi

  seed_retired_direction_entries "$install" "$fake_home"

  rollback_out=$(HOME="$fake_home" PMAI_HOME="$install" PMAI_STATE="$state" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" PMAI_REMOTE="$remote" \
    PMAI_UPGRADE_DOCTOR_LOG="$doctor_log" \
    bash "$install/bin/pmai-upgrade" --no-whats-new 2>&1)
  rollback_rc=$?
  final_head=$(git -C "$install" rev-parse HEAD)

  if [ "$rollback_rc" = "0" ] || [ "$final_head" != "$candidate_head" ]; then
    _fail "future doctor 失败时应回滚到升级前 candidate"
    echo "$rollback_out" >&2
    rm -rf "$tmp"
    return
  fi
  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"; do
    if [ ! -L "$host_dir/pmai-design" ] \
      || [ "$(readlink "$host_dir/pmai-design")" != "$install/skills/design" ]; then
      _fail "回滚未按旧策略恢复 pmai-design: $host_dir"
      echo "$rollback_out" >&2
      rm -rf "$tmp"
      return
    fi
  done
  if ! assert_retired_direction_entries_absent "$fake_home"; then
    echo "$rollback_out" >&2
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_upgrade_can_pin_to_legacy_policy_without_function_leak() {
  start_test "T16: --to 旧策略会清除 Bash 残留函数并完成降级"
  local tmp source_repo remote install fake_home state doctor_log legacy_head out rc host_dir skill

  tmp=$(mktemp -d /tmp/pmai-upgrade-downgrade-XXXXXX)
  source_repo="$tmp/source"
  remote="$tmp/origin.git"
  install="$tmp/pmai-home"
  fake_home="$tmp/home"
  state="$tmp/state"
  doctor_log="$tmp/doctor.log"

  if ! git clone -q --no-hardlinks "$REPO_ROOT" "$source_repo"; then
    _fail "无法创建降级源 fixture"
    rm -rf "$tmp"
    return
  fi
  cp "$UPGRADE" "$source_repo/bin/pmai-upgrade"
  copy_global_lock_helpers_to "$source_repo"
  sed \
    -e '/^pmai_skill_is_host_exposed()/,/^}/d' \
    -e '/^pmai_prune_managed_hidden_skill_links()/,/^}/d' \
    "$REPO_ROOT/scripts/_lib/skill-links.sh" > "$tmp/skill-links.legacy"
  mv "$tmp/skill-links.legacy" "$source_repo/scripts/_lib/skill-links.sh"
  sed '/pmai_skill_is_host_exposed "$skill_name" || continue/d' \
    "$REPO_ROOT/scripts/install-opencode-commands.sh" > "$source_repo/scripts/install-opencode-commands.sh"
  cat > "$source_repo/bin/pmai-doctor" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
for host_dir in "$HOME/.claude/skills" "${CODEX_HOME:-$HOME/.codex}/skills" "${KIMI_CODE_HOME:-$HOME/.kimi-code}/skills"; do
  for skill in pmai-design pmai-build-close pmai-publish-to-lark pmai-direction; do
    [ -L "$host_dir/$skill" ] || { echo "legacy doctor missing $host_dir/$skill" >&2; exit 1; }
  done
done
for command in pmai-design.md pmai-build-close.md pmai-publish-to-lark.md pmai-direction.md; do
  [ -f "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/commands/$command" ] \
    || { echo "legacy doctor missing OpenCode $command" >&2; exit 1; }
done
echo "legacy doctor passed"
EOF
  chmod +x "$source_repo/bin/pmai-upgrade" "$source_repo/bin/pmai-doctor" \
    "$source_repo/scripts/install-opencode-commands.sh"
  git -C "$source_repo" add bin/pmai-upgrade bin/pmai-doctor \
    scripts/_lib/skill-links.sh scripts/_lib/global-install-lock.sh \
    scripts/_lib/global_install_lock.py scripts/_lib/kimi-config-transaction.sh \
    scripts/install-opencode-commands.sh
  if ! git -C "$source_repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid \
    commit -q -m "legacy exposure policy fixture"; then
    _fail "无法提交旧策略 fixture"
    rm -rf "$tmp"
    return
  fi
  legacy_head=$(git -C "$source_repo" rev-parse HEAD)
  git -C "$source_repo" tag v0.0.0-test-legacy "$legacy_head"

  cp "$UPGRADE" "$source_repo/bin/pmai-upgrade"
  cp "$DOCTOR" "$source_repo/bin/pmai-doctor"
  sync_current_skill_catalog_to_fixture "$source_repo"
  cp "$REPO_ROOT/scripts/install-opencode-commands.sh" "$source_repo/scripts/install-opencode-commands.sh"
  copy_global_lock_helpers_to "$source_repo"
  sed 's/_internal|_shared)/_internal|_shared|design)/' \
    "$REPO_ROOT/scripts/_lib/skill-links.sh" > "$source_repo/scripts/_lib/skill-links.sh"
  chmod +x "$source_repo/bin/pmai-upgrade" "$source_repo/bin/pmai-doctor" \
    "$source_repo/scripts/install-opencode-commands.sh"
  git -C "$source_repo" add bin/pmai-upgrade bin/pmai-doctor \
    scripts/_lib/skill-links.sh scripts/_lib/global-install-lock.sh \
    scripts/_lib/global_install_lock.py scripts/_lib/kimi-config-transaction.sh \
    scripts/install-opencode-commands.sh
  if ! git -C "$source_repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid \
    commit -q -m "new restrictive exposure policy fixture" \
    || ! git clone -q --bare "$source_repo" "$remote" \
    || ! git clone -q "$remote" "$install"; then
    _fail "无法创建已安装的新策略 fixture"
    rm -rf "$tmp"
    return
  fi

  mkdir -p "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.kimi-code/skills" "$fake_home/.config/opencode/commands" "$state"
  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"; do
    ln -s "$install/skills/_shared" "$host_dir/_shared"
  done

  out=$(HOME="$fake_home" PMAI_HOME="$install" PMAI_STATE="$state" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" PMAI_UPGRADE_DOCTOR_LOG="$doctor_log" \
    bash "$install/bin/pmai-upgrade" --to v0.0.0-test-legacy --no-whats-new 2>&1)
  rc=$?

  if [ "$rc" != "0" ] || [ "$(git -C "$install" rev-parse HEAD)" != "$legacy_head" ]; then
    _fail "--to 应完成旧策略降级并停在目标 tag"
    echo "$out" >&2
    [ -f "$doctor_log" ] && cat "$doctor_log" >&2
    rm -rf "$tmp"
    return
  fi
  if ! grep -q 'legacy doctor passed' "$doctor_log"; then
    _fail "测试 override 应保留旧 doctor 的可读日志"
    rm -rf "$tmp"
    return
  fi
  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"; do
    for skill in design build-close publish-to-lark direction; do
      if [ ! -L "$host_dir/pmai-$skill" ]; then
        _fail "旧策略入口未恢复: $host_dir/pmai-$skill"
        rm -rf "$tmp"
        return
      fi
    done
  done
  if [ ! -f "$fake_home/.config/opencode/commands/pmai-direction.md" ]; then
    _fail "降级到仍包含 direction 的旧版本时应恢复 OpenCode 入口"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_upgrade_doctor_log_and_project_hook_notice() {
  start_test "T17: doctor 日志默认唯一安全且升级不冒充项目 hook 已刷新"

  if grep -q '/tmp/pmai-upgrade-doctor.log' "$UPGRADE" \
    || ! grep -q 'mktemp "${TMPDIR:-/tmp}/pmai-upgrade-doctor.XXXXXX"' "$UPGRADE" \
    || ! grep -q 'PMAI_UPGRADE_DOCTOR_LOG' "$UPGRADE"; then
    _fail "upgrade 应使用唯一 mktemp 日志，并保留显式测试 override"
    return
  fi
  if ! grep -q '/pmai-doctor' "$UPGRADE" \
    || ! grep -q 'install-project-hooks.sh' "$UPGRADE" \
    || ! grep -q '不会被静默改写' "$UPGRADE"; then
    _fail "upgrade 摘要必须说明已有消费仓项目 hooks 需要单独检查和刷新"
    return
  fi
  pass_test
}

assert_upgrade_rolls_back_for_unusable_doctor() {
  local doctor_state="$1"
  local tmp source_repo remote install fake_home state doctor_log old_head out rc final_head

  tmp=$(mktemp -d /tmp/pmai-upgrade-doctor-rollback-XXXXXX)
  source_repo="$tmp/source"
  remote="$tmp/origin.git"
  install="$tmp/pmai-home"
  fake_home="$tmp/home"
  state="$tmp/state"
  doctor_log="$tmp/doctor.log"

  if ! git clone -q --no-hardlinks "$REPO_ROOT" "$source_repo"; then
    _fail "无法创建 doctor 回滚源 fixture"
    rm -rf "$tmp"
    return 1
  fi
  cp "$UPGRADE" "$source_repo/bin/pmai-upgrade"
  cp "$DOCTOR" "$source_repo/bin/pmai-doctor"
  sync_current_skill_catalog_to_fixture "$source_repo"
  cp "$REPO_ROOT/scripts/_lib/skill-links.sh" "$source_repo/scripts/_lib/skill-links.sh"
  cp "$REPO_ROOT/scripts/install-opencode-commands.sh" "$source_repo/scripts/install-opencode-commands.sh"
  copy_global_lock_helpers_to "$source_repo"
  chmod +x "$source_repo/bin/pmai-upgrade" "$source_repo/bin/pmai-doctor" \
    "$source_repo/scripts/install-opencode-commands.sh"
  git -C "$source_repo" add bin/pmai-upgrade bin/pmai-doctor \
    scripts/_lib/skill-links.sh scripts/_lib/global-install-lock.sh \
    scripts/_lib/global_install_lock.py scripts/_lib/kimi-config-transaction.sh \
    scripts/install-opencode-commands.sh
  if ! git -C "$source_repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid \
    commit -q --allow-empty -m "upgrade doctor rollback baseline"; then
    _fail "无法提交 doctor 回滚基线 fixture"
    rm -rf "$tmp"
    return 1
  fi
  old_head=$(git -C "$source_repo" rev-parse HEAD)
  if ! git clone -q --bare "$source_repo" "$remote" \
    || ! git clone -q "$remote" "$install"; then
    _fail "无法创建 doctor 回滚 origin/install fixture"
    rm -rf "$tmp"
    return 1
  fi

  case "$doctor_state" in
    missing) rm -f "$source_repo/bin/pmai-doctor" ;;
    non-executable) chmod a-x "$source_repo/bin/pmai-doctor" ;;
    *)
      _fail "未知 doctor fixture 状态：$doctor_state"
      rm -rf "$tmp"
      return 1
      ;;
  esac
  git -C "$source_repo" add -A bin/pmai-doctor
  if ! git -C "$source_repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid \
    commit -q -m "publish unusable doctor fixture: $doctor_state" \
    || ! git -C "$source_repo" push -q "$remote" main; then
    _fail "无法发布 $doctor_state doctor fixture"
    rm -rf "$tmp"
    return 1
  fi

  mkdir -p "$fake_home/.claude/skills" "$fake_home/.codex/skills" \
    "$fake_home/.kimi-code/skills" "$fake_home/.config/opencode/commands" "$state"
  out=$(HOME="$fake_home" PMAI_HOME="$install" PMAI_STATE="$state" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" PMAI_UPGRADE_DOCTOR_LOG="$doctor_log" \
    bash "$install/bin/pmai-upgrade" --no-whats-new 2>&1)
  rc=$?
  final_head=$(git -C "$install" rev-parse HEAD)

  if [ "$rc" = "0" ] || [ "$final_head" != "$old_head" ] \
    || [ ! -x "$install/bin/pmai-doctor" ] \
    || ! echo "$out" | grep -q "升级后的 pmai-doctor 缺失或不可执行"; then
    _fail "$doctor_state doctor 必须触发完整升级回滚"
    echo "$out" >&2
    rm -rf "$tmp"
    return 1
  fi

  rm -rf "$tmp"
  return 0
}

test_upgrade_rolls_back_when_target_doctor_is_missing() {
  start_test "T21: 升级目标缺失 pmai-doctor 时回滚"
  assert_upgrade_rolls_back_for_unusable_doctor missing || return
  pass_test
}

test_upgrade_rolls_back_when_target_doctor_is_not_executable() {
  start_test "T22: 升级目标 pmai-doctor 不可执行时回滚"
  assert_upgrade_rolls_back_for_unusable_doctor non-executable || return
  pass_test
}

test_repo_local_status_delegates_to_target_doctor() {
  start_test "T18: repo-local status 通过 doctor check 委托目标版本"
  local setup tmp pmai_home fake_home out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  cat > "$pmai_home/bin/pmai-doctor" <<'SH'
#!/usr/bin/env bash
printf 'TARGET_STATUS_DOCTOR:%s:%s\n' "$PMAI_HOME" "$*"
exit 23
SH
  chmod +x "$pmai_home/bin/pmai-doctor"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" KIMI_CODE_HOME="$fake_home/.kimi-code" \
    OPENCODE_CONFIG_DIR="$fake_home/.config/opencode" bash "$STATUS" 2>&1)
  rc=$?
  if [ "$rc" != "23" ] \
    || ! echo "$out" | grep -q "TARGET_STATUS_DOCTOR:$pmai_home:--check"; then
    _fail "status 未把只读检查完整委托给目标 doctor: rc=$rc out=$out"
  else
    pass_test
  fi

  rm -rf "$tmp"
}

test_repo_local_doctor_delegates_to_target_version() {
  start_test "T19: repo-local doctor 把跨版本审计与自愈委托给 PMAI_HOME"
  local tmp pmai_home fake_home out rc

  tmp=$(mktemp -d)
  tmp=$(cd "$tmp" && pwd -P)
  pmai_home="$tmp/pmai"
  fake_home="$tmp/home"
  mkdir -p "$pmai_home/bin" "$fake_home"
  cat > "$pmai_home/bin/pmai-doctor" <<'SH'
#!/usr/bin/env bash
printf 'TARGET_DOCTOR:%s:%s\n' "$PMAI_HOME" "$*"
exit 23
SH
  chmod +x "$pmai_home/bin/pmai-doctor"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" --target-only 2>&1)
  rc=$?
  if [ "$rc" != "23" ] \
    || [ "$out" != "TARGET_DOCTOR:$pmai_home:--target-only" ]; then
    _fail "repo-local doctor did not preserve target doctor behavior: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_repo_local_doctor_fails_closed_when_target_doctor_missing() {
  start_test "T20: PMAI_HOME 存在但目标 doctor 缺失时不跨版本自愈"
  local tmp pmai_home fake_home out rc

  tmp=$(mktemp -d)
  pmai_home="$tmp/pmai"
  fake_home="$tmp/home"
  mkdir -p "$pmai_home/bin" "$pmai_home/skills/design" \
    "$fake_home/.codex/skills"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" \
    CODEX_HOME="$fake_home/.codex" bash "$DOCTOR" 2>&1)
  rc=$?
  if [ "$rc" != "2" ] \
    || ! echo "$out" | grep -q "目标 PMAI doctor 缺失或不可执行"; then
    _fail "repo-local doctor should fail closed for an incomplete target: rc=$rc out=$out"
  elif [ -e "$fake_home/.codex/skills/pmai-design" ] \
    || [ -L "$fake_home/.codex/skills/pmai-design" ]; then
    _fail "repo-local doctor mutated target-owned exposure after delegation became impossible"
  else
    pass_test
  fi

  rm -rf "$tmp"
}

test_doctor_exists
test_host_exposure_policy_matches_product_contract
test_no_stale_in_expected
test_no_missing_in_expected
test_doctor_help_is_help_only
test_doctor_detects_stale_exposed_skill
test_status_help_is_help_only
test_status_reports_stale_exposed_skill
test_doctor_requires_codex_exposure
test_doctor_rejects_wrong_target_and_real_directory_entries
test_lifecycle_scripts_cover_codex_skills
test_doctor_repairs_empty_codex_exposure
test_doctor_does_not_generate_codex_prompts
test_doctor_repairs_opencode_commands
test_doctor_repairs_modified_opencode_command_content
test_doctor_repairs_kimi_native_surface
test_doctor_rechecks_kimi_repair_result
test_doctor_json_contract_and_status_alias
test_doctor_reports_consumer_hook_drift
test_doctor_keeps_product_progress_out_of_health
test_doctor_reports_invalid_consumer_structure
test_doctor_reports_unversioned_legacy_as_compatibility_sync
test_doctor_skill_separates_status_doctor_and_upgrade
test_manual_workflows_are_host_entries
test_skill_frontmatter_does_not_claim_framework_version
test_install_doctor_failure_restores_every_global_surface
test_install_uses_cloned_target_exposure_policy
test_install_preserves_dangling_pmai_home_symlink
test_doctor_preserves_logical_pmai_home_targets
test_upgrade_to_doctor_failure_restores_branch_kimi_and_legacy_policy
test_upgrade_doctor_failure_restores_kimi_config_symlink
test_kimi_config_transaction_covers_all_entry_states
test_kimi_config_transaction_preserves_concurrent_referent_edit
test_upgrade_preserves_dirty_tree_before_git_rollback_is_safe
test_doctor_has_stock_macos_timeout_fallback
test_upgrade_signals_restore_symbolic_and_detached_head
test_upgrade_preserves_public_links_and_restores_rollback_policy
test_upgrade_can_pin_to_legacy_policy_without_function_leak
test_upgrade_doctor_log_and_project_hook_notice
test_upgrade_rolls_back_when_target_doctor_is_missing
test_upgrade_rolls_back_when_target_doctor_is_not_executable
test_repo_local_status_delegates_to_target_doctor
test_repo_local_doctor_delegates_to_target_version
test_repo_local_doctor_fails_closed_when_target_doctor_missing

report_results "doctor-skills"
