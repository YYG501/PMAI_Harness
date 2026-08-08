#!/usr/bin/env bash
# test-doctor-skills.sh
#
# 防回归：bin/pmai-doctor 的 EXPECTED_SKILLS 必须与 skill 源目录（除 _shared / _internal）完全一致。
# 宿主暴露是该源清单经 pmai_skill_is_host_exposed 过滤后的子集。
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
#   T8: install / upgrade / uninstall 覆盖 Codex/Kimi skill dir + legacy prompt cleanup + OpenCode commands
#   T9: pmai-doctor 可自愈 Codex 首次空暴露目录（兼容旧 upgrader）
#   T10: pmai-doctor 不再生成 Codex slash prompts
#   T11: pmai-doctor 可自愈 OpenCode slash commands
#   T12: pmai-doctor 可自愈 Kimi 原生 Skill 暴露和 managed hooks
#   T15: 旧 updater 进程可迁移隐藏入口；后续失败回滚恢复旧暴露策略
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
source "$REPO_ROOT/scripts/_lib/skill-links.sh"

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

setup_fake_global_install() {
  local tmp pmai_home fake_home sk name exposed

  tmp=$(mktemp -d /tmp/pmai-doctor-skills-XXXXXX)
  pmai_home="$tmp/pmai"
  fake_home="$tmp/home"

  mkdir -p "$pmai_home/scripts/_lib" "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"
  ln -s "$SKILLS_DIR" "$pmai_home/skills"
  ln -s "$REPO_ROOT/scripts/install-opencode-commands.sh" "$pmai_home/scripts/install-opencode-commands.sh"
  ln -s "$REPO_ROOT/scripts/manage-kimi-hooks.py" "$pmai_home/scripts/manage-kimi-hooks.py"
  ln -s "$REPO_ROOT/scripts/kimi-hook-dispatch.sh" "$pmai_home/scripts/kimi-hook-dispatch.sh"
  ln -s "$REPO_ROOT/scripts/_lib/skill-links.sh" "$pmai_home/scripts/_lib/skill-links.sh"
  cp "$VERSION_FILE" "$pmai_home/VERSION"
  git -C "$pmai_home" init -q

  while IFS= read -r sk; do
    name=$(basename "$sk")
    pmai_skill_is_host_exposed "$name" || continue
    exposed=$(exposed_name_for_skill "$name")
    ln -s "$sk" "$fake_home/.claude/skills/$exposed"
    ln -s "$sk" "$fake_home/.codex/skills/$exposed"
    ln -s "$sk" "$fake_home/.kimi-code/skills/$exposed"
  done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name _shared ! -name _internal | sort)
  ln -s "$SKILLS_DIR/_shared" "$fake_home/.claude/skills/_shared"
  ln -s "$SKILLS_DIR/_shared" "$fake_home/.codex/skills/_shared"
  ln -s "$SKILLS_DIR/_shared" "$fake_home/.kimi-code/skills/_shared"

  echo "$tmp|$pmai_home|$fake_home"
}

test_internal_workflows_are_not_host_entries() {
  start_test "T13: 恢复和底层执行能力不暴露为宿主入口"

  if pmai_skill_is_host_exposed build-close || pmai_skill_is_host_exposed publish-to-lark; then
    _fail "build-close / publish-to-lark should remain internal-only"
    return
  fi
  if ! pmai_skill_is_host_exposed design || ! pmai_skill_is_host_exposed spec-writing; then
    _fail "independently useful design/spec-writing skills should stay exposed"
    return
  fi
  for file in "$INSTALL" "$UPGRADE" "$DOCTOR" "$STATUS" "$REPO_ROOT/scripts/install-opencode-commands.sh"; do
    if ! grep -q "pmai_skill_is_host_exposed" "$file"; then
      _fail "$(basename "$file") should use the shared exposure policy"
      return
    fi
  done
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
  start_test "T8: install / upgrade / uninstall 覆盖 Codex/Kimi skill dir + legacy prompt cleanup + OpenCode commands"
  local file

  for file in "$INSTALL" "$UPGRADE" "$UNINSTALL" "$DOCTOR" "$STATUS"; do
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
  for file in "$DOCTOR" "$STATUS"; do
    if grep -q "CODEX_PROMPTS" "$file"; then
      _fail "$(basename "$file") 不应继续把 legacy Codex prompts 当成当前 host surface"
      return
    fi
  done
  if ! grep -q "remove_managed_codex_prompts" "$INSTALL" || ! grep -q "remove_managed_codex_prompts" "$UPGRADE"; then
    _fail "install / upgrade 应清理 legacy Codex prompts"
    return
  fi
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

test_doctor_does_not_generate_codex_prompts() {
  start_test "T10: pmai-doctor 不再生成 Codex slash prompts"
  local setup tmp pmai_home fake_home out rc

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  rm -rf "$fake_home/.codex/prompts"
  mkdir -p "$fake_home/.codex/prompts"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" bash "$DOCTOR" 2>&1)
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

test_doctor_repairs_kimi_native_surface() {
  start_test "T12: pmai-doctor 自愈 Kimi 原生 Skill 暴露和 managed hooks"
  local setup tmp pmai_home fake_home out rc config

  setup=$(setup_fake_global_install)
  IFS='|' read -r tmp pmai_home fake_home <<< "$setup"
  rm -rf "$fake_home/.kimi-code/skills"
  mkdir -p "$fake_home/.kimi-code/skills"
  config="$fake_home/.kimi-code/config.toml"
  printf '%s\n' 'default_model = "demo"' > "$config"

  out=$(PMAI_HOME="$pmai_home" HOME="$fake_home" KIMI_CODE_HOME="$fake_home/.kimi-code" bash "$DOCTOR" 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "Kimi 宿主面为空时 doctor 应自愈并通过"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q "Kimi Code initial skill exposure repaired"; then
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

test_upgrade_migrates_legacy_links_and_restores_rollback_policy() {
  start_test "T15: 旧 updater 迁移隐藏入口，失败回滚恢复旧策略"
  local tmp source_repo remote install fake_home state doctor_log current_upgrade
  local out rc candidate_head rollback_out rollback_rc final_head retired_count host_dir

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
  cp "$REPO_ROOT/scripts/_lib/skill-links.sh" "$source_repo/scripts/_lib/skill-links.sh"
  cp "$REPO_ROOT/scripts/install-opencode-commands.sh" "$source_repo/scripts/install-opencode-commands.sh"

  # 旧进程在 merge 前已载入不含暴露过滤的 rebuild_symlinks。
  sed \
    -e '/pmai_skill_is_host_exposed "$skill_name" || continue/d' \
    "$current_upgrade" > "$source_repo/bin/pmai-upgrade"
  chmod +x "$source_repo/bin/pmai-upgrade" "$source_repo/bin/pmai-doctor"
  git -C "$source_repo" add bin/pmai-upgrade bin/pmai-doctor \
    scripts/_lib/skill-links.sh scripts/install-opencode-commands.sh
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
  retired_count=$(grep -c 'retired 2 PMAI-managed hidden skill link(s)' "$doctor_log" || true)
  if [ "$retired_count" != "3" ]; then
    _fail "doctor 应分别迁移 Claude/Codex/Kimi 的两个隐藏入口"
    cat "$doctor_log" >&2
    rm -rf "$tmp"
    return
  fi
  for host_dir in "$fake_home/.claude/skills" "$fake_home/.codex/skills" "$fake_home/.kimi-code/skills"; do
    if [ -e "$host_dir/pmai-build-close" ] || [ -L "$host_dir/pmai-build-close" ] \
      || [ -e "$host_dir/pmai-publish-to-lark" ] || [ -L "$host_dir/pmai-publish-to-lark" ]; then
      _fail "旧 updater 遗留的隐藏入口未清理: $host_dir"
      rm -rf "$tmp"
      return
    fi
  done

  # 模拟下一版改变暴露策略后 doctor 失败。回滚必须 reset 后重载旧 helper，
  # 否则 pmai-design 会继续被未来策略过滤，旧安装状态恢复不完整。
  sed 's/_internal|_shared|build-close|publish-to-lark/_internal|_shared|design|build-close|publish-to-lark/' \
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
test_doctor_does_not_generate_codex_prompts
test_doctor_repairs_opencode_commands
test_doctor_repairs_kimi_native_surface
test_internal_workflows_are_not_host_entries
test_skill_frontmatter_does_not_claim_framework_version
test_upgrade_migrates_legacy_links_and_restores_rollback_policy

report_results "doctor-skills"
