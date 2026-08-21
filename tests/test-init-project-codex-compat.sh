#!/usr/bin/env bash
# Codex 主控入口兼容性测试：
# - framework 提供 AGENTS.md.tmpl
# - init-project 会把 AGENTS.md 和 .codex/hooks.json 生成到消费仓根目录
# - AGENTS.md 是通用薄入口，Claude/Codex hooks 引用 PMAI_HOME，不复制 framework 源资产
# - Kimi/OpenCode 只作为 Builder，新消费仓不生成它们的主控配置
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_PROJECT_SH="$REPO_ROOT/scripts/init-project.sh"
AGENTS_TMPL="$REPO_ROOT/templates/AGENTS.md.tmpl"
CODEX_HOOKS_TMPL="$REPO_ROOT/templates/codex-hooks.json.tmpl"
SETTINGS_TMPL="$REPO_ROOT/templates/settings.json.tmpl"
INSTALL_CODEX_HOOKS="$REPO_ROOT/scripts/install-codex-hooks.sh"
INSTALL_PROJECT_HOOKS="$REPO_ROOT/scripts/install-project-hooks.sh"

_mode_of() {
  python3 - "$1" <<'PY'
import os
import stat
import sys

print(format(stat.S_IMODE(os.stat(sys.argv[1]).st_mode), "o"))
PY
}

test_agents_template_exists_and_maps_codex() {
  start_test "T1: AGENTS.md.tmpl 存在并声明通用 host mapping"

  assert_file_exists "$AGENTS_TMPL" "AGENTS.md.tmpl should exist" || return
  assert_file_contains "$AGENTS_TMPL" "PMAI Agent Entry" "AGENTS.md.tmpl should name generic agent entry" || return
  assert_file_contains "$AGENTS_TMPL" "CLAUDE.md" "AGENTS.md.tmpl should reference CLAUDE.md truth source" || return
  assert_file_contains "$AGENTS_TMPL" "当前主控 agent" "AGENTS.md.tmpl should map driver role to current host" || return
  assert_file_contains "$AGENTS_TMPL" "Codex" "AGENTS.md.tmpl should still mention Codex" || return
  assert_file_contains "$AGENTS_TMPL" "Kimi Code、OpenCode 和 Cursor Agent" "AGENTS.md.tmpl should define builder-only hosts" || return
  assert_file_contains "$AGENTS_TMPL" '只可由 `/pmai-build` 选作外部 Builder' "AGENTS.md.tmpl should limit Kimi/OpenCode to Builder" || return
  assert_file_contains "$AGENTS_TMPL" "skill-preamble.sh" "AGENTS.md.tmpl should use neutral PMAI preamble" || return
  assert_file_contains "$AGENTS_TMPL" "AskUserQuestion 不可用" "AGENTS.md.tmpl should define AskUser fallback" || return
  assert_file_contains "$AGENTS_TMPL" "默认用中文" "AGENTS.md.tmpl should preserve Chinese default" || return
  assert_file_contains "$AGENTS_TMPL" "PMAI 消费仓" "AGENTS.md.tmpl should identify consumer repo" || return
  assert_file_contains "$AGENTS_TMPL" "PMAI_HOME" "AGENTS.md.tmpl should resolve installed framework path" || return
  assert_file_contains "$AGENTS_TMPL" "不能在这里再跑" "AGENTS.md.tmpl should prevent re-init inside consumer repo" || return
  assert_file_contains "$AGENTS_TMPL" "install-project-hooks.sh" "AGENTS.md.tmpl should check current Claude/Codex hooks" || return
  assert_file_contains "$AGENTS_TMPL" "--check" "AGENTS.md.tmpl should use a read-only hook drift check" || return
  assert_file_contains "$AGENTS_TMPL" "<!-- PMAI:BEGIN consumer-startup -->" "AGENTS.md.tmpl should mark the managed startup block" || return
  assert_file_contains "$AGENTS_TMPL" "<!-- PMAI:END consumer-startup -->" "AGENTS.md.tmpl should close the managed startup block" || return
  if grep -q "install-opencode-commands.sh" "$AGENTS_TMPL"; then
    _fail "consumer template must not refresh legacy OpenCode controller commands"
    return
  fi
  assert_file_contains "$AGENTS_TMPL" "不写死机器绑定路径" "AGENTS.md.tmpl should carry portable path principle" || return
  assert_file_contains "$AGENTS_TMPL" "/Users/<某人>/..." "AGENTS.md.tmpl should forbid user-specific local paths" || return
  pass_test
}

test_init_project_knows_agents_template() {
  start_test "T2: init-project.sh 白名单生成 AGENTS.md 并安装 host 配置"

  assert_file_contains "$INIT_PROJECT_SH" "templates/AGENTS.md.tmpl" "init-project should require AGENTS template" || return
  assert_file_contains "$INIT_PROJECT_SH" "templates/codex-hooks.json.tmpl" "init-project should require Codex hooks template" || return
  if grep -q 'install-opencode-commands.sh.*--project' "$INIT_PROJECT_SH"; then
    _fail "init-project must not install OpenCode controller commands"
    return
  fi
  assert_file_contains "$INIT_PROJECT_SH" "已阻止重复初始化" "init-project should hard-stop already initialized PMAI projects" || return
  assert_file_contains "$INIT_PROJECT_SH" 'AGENTS.md)' "init-project should route AGENTS.md template" || return
  assert_file_contains "$INIT_PROJECT_SH" 'DEST="$TARGET_DIR/AGENTS.md"' "init-project should write root AGENTS.md" || return
  assert_file_contains "$INIT_PROJECT_SH" "install-project-hooks.sh" "init-project should install project-level Claude/Codex hooks" || return
  pass_test
}

test_codex_hooks_template_shape() {
  start_test "T3: codex-hooks.json.tmpl 是项目级 Codex hook 配置"

  assert_file_exists "$CODEX_HOOKS_TMPL" "codex hooks template should exist" || return
  assert_file_contains "$CODEX_HOOKS_TMPL" '"PreToolUse"' "Codex hooks should include PreToolUse" || return
  assert_file_contains "$CODEX_HOOKS_TMPL" '"UserPromptSubmit"' "Codex hooks should include UserPromptSubmit" || return
  assert_file_contains "$CODEX_HOOKS_TMPL" "check-branch.sh" "Codex hooks should wire check-branch" || return
  assert_file_contains "$CODEX_HOOKS_TMPL" "review-skill-guard.cjs" "Codex hooks should wire review guard" || return
  assert_file_contains "$CODEX_HOOKS_TMPL" "active-build-guard.cjs" "Codex hooks should wire active build continuation" || return
  assert_file_contains "$CODEX_HOOKS_TMPL" "decision-gate-guard.cjs" "Codex hooks should bind PM answers and guard decision writes" || return
  assert_file_contains "$SETTINGS_TMPL" "decision-gate-guard.cjs" "Claude hooks should bind PM answers and guard decision writes" || return
  assert_file_contains "$CODEX_HOOKS_TMPL" '${PMAI_HOME:-$HOME/.pmai}' "Codex hooks should honor custom PMAI_HOME at runtime" || return
  assert_file_contains "$SETTINGS_TMPL" '${PMAI_HOME:-$HOME/.pmai}' "Claude hooks should honor custom PMAI_HOME at runtime" || return
  python3 -m json.tool "$CODEX_HOOKS_TMPL" >/dev/null || {
    _fail "codex-hooks.json.tmpl 不是合法 JSON"
    return
  }
  pass_test
}

test_e2e_generates_agents_md_without_framework_assets() {
  start_test "T4: init-project e2e 生成 AGENTS.md / .codex/hooks.json 且不泄漏 framework 资产"

  local base proj
  base=$(mktemp -d)
  proj="$base/codex-compat-proj"

  if ! PMAI_HOME="$REPO_ROOT" bash "$INIT_PROJECT_SH" "codex-compat-proj" "$proj" "Codex 主控兼容测试" \
       >/tmp/test-init-project-codex-compat.out 2>&1; then
    _fail "init-project.sh 执行失败 —— 见 /tmp/test-init-project-codex-compat.out"
    tail -20 /tmp/test-init-project-codex-compat.out >&2
    rm -rf "$base"
    return
  fi

  if [ ! -f "$proj/AGENTS.md" ]; then
    _fail "消费仓根目录未生成 AGENTS.md"
    rm -rf "$base"
    return
  fi
  if [ ! -f "$proj/.codex/hooks.json" ]; then
    _fail "消费仓根目录未生成 .codex/hooks.json"
    rm -rf "$base"
    return
  fi
  if [ -e "$proj/.opencode/commands/pmai-build.md" ] \
    || [ -L "$proj/.opencode/commands/pmai-build.md" ]; then
    _fail "新消费仓不应生成 .opencode/commands/pmai-build.md"
    rm -rf "$base"
    return
  fi
  if [ -e "$proj/opencode.json" ] || [ -L "$proj/opencode.json" ]; then
    _fail "新消费仓不应生成 opencode.json"
    rm -rf "$base"
    return
  fi

  if ! grep -q "PMAI Agent Entry" "$proj/AGENTS.md"; then
    _fail "生成的 AGENTS.md 缺通用主控入口标题"
    rm -rf "$base"
    return
  fi
  if ! grep -q '<!-- PMAI:BEGIN consumer-startup -->' "$proj/AGENTS.md" \
    || ! grep -q '<!-- PMAI:END consumer-startup -->' "$proj/AGENTS.md"; then
    _fail "生成的 AGENTS.md 缺 PMAI 托管启动区块标记"
    rm -rf "$base"
    return
  fi

  if ! grep -q "Kimi Code、OpenCode 和 Cursor Agent" "$proj/AGENTS.md" \
    || ! grep -q "外部 Builder" "$proj/AGENTS.md"; then
    _fail "生成的 AGENTS.md 缺 Kimi/OpenCode Builder 边界"
    rm -rf "$base"
    return
  fi

  if ! grep -q "PMAI 消费仓" "$proj/AGENTS.md"; then
    _fail "生成的 AGENTS.md 缺消费仓定位"
    rm -rf "$base"
    return
  fi

  if ! grep -q "不能在这里再跑" "$proj/AGENTS.md" || ! grep -q "/pmai-init-project" "$proj/AGENTS.md"; then
    _fail "生成的 AGENTS.md 未阻止消费仓重复 init"
    rm -rf "$base"
    return
  fi
  if ! grep -q "不写死机器绑定路径" "$proj/AGENTS.md"; then
    _fail "生成的 AGENTS.md 缺路径可迁移原则"
    rm -rf "$base"
    return
  fi
  if ! grep -q "check-branch.sh" "$proj/.codex/hooks.json" \
     || ! grep -q "review-skill-guard.cjs" "$proj/.codex/hooks.json" \
     || ! grep -q "active-build-guard.cjs" "$proj/.codex/hooks.json"; then
    _fail "生成的 .codex/hooks.json 未注册 PMAI hooks"
    rm -rf "$base"
    return
  fi
  python3 -m json.tool "$proj/.codex/hooks.json" >/dev/null || {
    _fail "生成的 .codex/hooks.json 不是合法 JSON"
    rm -rf "$base"
    return
  }
  if [ -d "$proj/.claude/skills" ] || [ -d "$proj/.claude/scripts" ] || [ -d "$proj/.claude/agents" ]; then
    _fail "消费仓 .claude/ 泄漏 framework 资产"
    rm -rf "$base"
    return
  fi
  if [ -d "$proj/skills" ] || [ -d "$proj/scripts" ] || [ -d "$proj/.cursor" ]; then
    _fail "消费仓泄漏 framework 源资产或生成了 Cursor 配置"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_shared_preamble_reports_stale_consumer_entry() {
  start_test "T4b: shared preamble reports old consumer startup rules without rewriting them"

  local base proj current_out stale_out missing_out before after
  base=$(mktemp -d)
  proj="$base/preamble-entry-proj"
  if ! PMAI_HOME="$REPO_ROOT" bash "$INIT_PROJECT_SH" "preamble-entry-proj" "$proj" \
       "consumer entry check" >/dev/null 2>&1; then
    _fail "unable to initialize preamble entry fixture"
    rm -rf "$base"
    return
  fi

  current_out=$(cd "$proj" && PMAI_HOME="$REPO_ROOT" PMAI_PREAMBLE_READ_ONLY=1 \
    bash -c 'source "$PMAI_HOME/scripts/skill-preamble.sh"; printf "ENTRY:%s\n" "$PMAI_PROJECT_ENTRY_STATUS"' 2>&1)
  if [[ "$current_out" != *"ENTRY:current"* ]] || [[ "$current_out" == *"启动规则是旧版本"* ]]; then
    _fail "current consumer entry should pass the shared startup check quietly"
    echo "$current_out" >&2
    rm -rf "$base"
    return
  fi

  sed 's/install-project-hooks\.sh/install-codex-hooks.sh/g; s/ --check//g' \
    "$proj/AGENTS.md" > "$proj/AGENTS.md.old" \
    && mv "$proj/AGENTS.md.old" "$proj/AGENTS.md"
  before=$(git -C "$proj" status --porcelain=v1 --untracked-files=all)
  stale_out=$(cd "$proj" && PMAI_HOME="$REPO_ROOT" PMAI_PREAMBLE_READ_ONLY=1 \
    bash -c 'source "$PMAI_HOME/scripts/skill-preamble.sh"; printf "ENTRY:%s\n" "$PMAI_PROJECT_ENTRY_STATUS"' 2>&1)
  after=$(git -C "$proj" status --porcelain=v1 --untracked-files=all)
  if [ "$before" != "$after" ] \
    || [[ "$stale_out" != *"ENTRY:stale"* ]] \
    || [[ "$stale_out" != *"启动规则是旧版本"* ]]; then
    _fail "old consumer entry should be reported without changing project files"
    echo "$stale_out" >&2
    rm -rf "$base"
    return
  fi

  rm "$proj/AGENTS.md"
  missing_out=$(cd "$proj" && PMAI_HOME="$REPO_ROOT" PMAI_PREAMBLE_READ_ONLY=1 \
    bash -c 'source "$PMAI_HOME/scripts/skill-preamble.sh"; printf "ENTRY:%s\n" "$PMAI_PROJECT_ENTRY_STATUS"' 2>&1)
  if [[ "$missing_out" != *"ENTRY:missing"* ]] \
    || [[ "$missing_out" != *"缺少可用的 AGENTS.md"* ]]; then
    _fail "missing consumer entry should be reported directly"
    echo "$missing_out" >&2
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_install_codex_hooks_merges_existing_hooks() {
  start_test "T5: install-codex-hooks.sh merge 既有 hook 且幂等"

  local base repo
  base=$(mktemp -d)
  repo="$base/repo"
  mkdir -p "$repo/.codex"
  (
    cd "$repo" || exit 1
    git init -b main >/dev/null 2>&1
  )
  cat > "$repo/.codex/hooks.json" <<'JSON'
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo keep-existing"
          }
        ]
      }
    ]
  }
}
JSON

  if ! (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_CODEX_HOOKS") >/tmp/test-install-codex-hooks.out 2>&1; then
    _fail "install-codex-hooks.sh 执行失败"
    cat /tmp/test-install-codex-hooks.out >&2
    rm -rf "$base"
    return
  fi
  if ! grep -q "keep-existing" "$repo/.codex/hooks.json"; then
    _fail "既有 Codex hook 被覆盖"
    rm -rf "$base"
    return
  fi
  if ! grep -q "check-branch.sh" "$repo/.codex/hooks.json"; then
    _fail "PMAI check-branch hook 未安装"
    rm -rf "$base"
    return
  fi
  if ! grep -q "review-skill-guard.cjs" "$repo/.codex/hooks.json"; then
    _fail "PMAI review guard hook 未安装"
    rm -rf "$base"
    return
  fi
  if ! grep -q "active-build-guard.cjs" "$repo/.codex/hooks.json"; then
    _fail "PMAI active build guard hook 未安装"
    rm -rf "$base"
    return
  fi

  (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_CODEX_HOOKS") >/tmp/test-install-codex-hooks-2.out 2>&1 || {
    _fail "install-codex-hooks.sh 第二次执行失败"
    cat /tmp/test-install-codex-hooks-2.out >&2
    rm -rf "$base"
    return
  }

  local guard_count
  guard_count=$(grep -c "review-skill-guard.cjs" "$repo/.codex/hooks.json")
  if [ "$guard_count" != "1" ]; then
    _fail "install-codex-hooks.sh 非幂等，review guard 出现 $guard_count 次"
    rm -rf "$base"
    return
  fi
  guard_count=$(grep -c "active-build-guard.cjs" "$repo/.codex/hooks.json")
  if [ "$guard_count" != "1" ]; then
    _fail "install-codex-hooks.sh 非幂等，active build guard 出现 $guard_count 次"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_checks_and_refreshes_both_hosts() {
  start_test "T6: project hook installer 只读检测并确定性刷新 Claude/Codex"

  local base repo before_claude before_codex rc
  base=$(mktemp -d)
  repo="$base/repo"
  mkdir -p "$repo/.claude" "$repo/.codex"
  git -C "$repo" init -q -b main
  cat > "$repo/.claude/settings.json" <<'JSON'
{
  "theme": "keep-user-setting",
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "node \"/custom/review-skill-guard.cjs\""},
          {"type": "command", "command": "echo active-build-guard.cjs custom"},
          {"type": "command", "command": "node \"$HOME/.pmai/hooks/review-skill-guard.cjs\"", "timeout": 3}
        ]
      }
    ]
  }
}
JSON
  cat > "$repo/.codex/hooks.json" <<JSON
{
  "custom": "keep-codex-setting",
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {"type": "command", "command": "node \"$REPO_ROOT/hooks/active-build-guard.cjs\"", "timeout": 3},
          {"type": "command", "command": "node \"/custom/active-build-guard.cjs\""}
        ]
      }
    ]
  }
}
JSON
  before_claude=$(shasum -a 256 "$repo/.claude/settings.json" | awk '{print $1}')
  before_codex=$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')

  (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS" --check) >/tmp/test-project-hooks-check.out 2>&1
  rc=$?
  if [ "$rc" != "1" ]; then
    _fail "stale project hooks should return 1 in --check mode, got $rc"
    cat /tmp/test-project-hooks-check.out >&2
    rm -rf "$base"
    return
  fi
  if [ "$before_claude" != "$(shasum -a 256 "$repo/.claude/settings.json" | awk '{print $1}')" ] \
    || [ "$before_codex" != "$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')" ]; then
    _fail "--check must not modify host config"
    rm -rf "$base"
    return
  fi
  if [ -e "$repo/.git/.pmai-install-project-hooks.lock" ]; then
    _fail "--check must not create the cooperative installer lock"
    rm -rf "$base"
    return
  fi

  if ! (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS") >/tmp/test-project-hooks-install.out 2>&1; then
    _fail "project hook refresh failed"
    cat /tmp/test-project-hooks-install.out >&2
    rm -rf "$base"
    return
  fi
  if [ ! -f "$repo/.git/.pmai-install-project-hooks.lock" ] \
    || [ -L "$repo/.git/.pmai-install-project-hooks.lock" ]; then
    _fail "install must retain a regular cooperative lock in the Git directory"
    rm -rf "$base"
    return
  fi
  if ! (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS" --check) >/tmp/test-project-hooks-check-2.out 2>&1; then
    _fail "refreshed project hooks should pass --check"
    cat /tmp/test-project-hooks-check-2.out >&2
    rm -rf "$base"
    return
  fi

  python3 - "$repo/.claude/settings.json" "$repo/.codex/hooks.json" "$REPO_ROOT" <<'PY' || {
import json
import sys

claude = json.load(open(sys.argv[1], encoding="utf-8"))
codex = json.load(open(sys.argv[2], encoding="utf-8"))
framework_root = sys.argv[3]
assert claude["theme"] == "keep-user-setting"
assert codex["custom"] == "keep-codex-setting"
claude_commands = [
    hook.get("command", "")
    for groups in claude["hooks"].values()
    for group in groups
    if isinstance(group, dict)
    for hook in group.get("hooks", [])
    if isinstance(hook, dict)
]
assert 'node "/custom/review-skill-guard.cjs"' in claude_commands
assert "echo active-build-guard.cjs custom" in claude_commands
runtime_review = 'node "${PMAI_HOME:-$HOME/.pmai}/hooks/review-skill-guard.cjs"'
runtime_active = 'node "${PMAI_HOME:-$HOME/.pmai}/hooks/active-build-guard.cjs"'
assert claude_commands.count(runtime_review) == 1
assert runtime_active in claude_commands
codex_commands = [
    hook.get("command", "")
    for groups in codex["hooks"].values()
    for group in groups
    if isinstance(group, dict)
    for hook in group.get("hooks", [])
    if isinstance(hook, dict)
]
assert 'node "/custom/active-build-guard.cjs"' in codex_commands
assert f'node "{framework_root}/hooks/active-build-guard.cjs"' not in codex_commands
assert codex_commands.count(runtime_review) == 1
assert codex_commands.count(runtime_active) == 1
PY
    _fail "project hook refresh lost custom config or failed to replace exact PMAI hook"
    rm -rf "$base"
    return
  }

  local review_command payload hook_out custom_home
  custom_home="$base/home-without-default-pmai"
  mkdir -p "$custom_home"
  review_command=$(python3 - "$repo/.codex/hooks.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for group in data["hooks"]["UserPromptSubmit"]:
    for hook in group.get("hooks", []):
        command = hook.get("command", "")
        if command.startswith("node ") and "review-skill-guard.cjs" in command:
            print(command)
            raise SystemExit(0)
raise SystemExit(1)
PY
  ) || {
    _fail "refreshed Codex config missing review hook command"
    rm -rf "$base"
    return
  }
  payload=$(printf '{"cwd":"%s","prompt":"/review"}' "$repo")
  hook_out=$(printf '%s' "$payload" | HOME="$custom_home" PMAI_HOME="$REPO_ROOT" bash -c "$review_command" 2>&1)
  if [ -e "$custom_home/.pmai" ] || ! echo "$hook_out" | grep -q "REVIEW SKILL 执行强制约束"; then
    _fail "runtime PMAI_HOME hook should execute without a default ~/.pmai install: $hook_out"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_requires_verified_lock_fd() {
  start_test "T6a: project hook installer 不信任伪造 boolean/lock fd 环境"

  local base repo spoof_repo out rc
  base=$(mktemp -d)
  repo="$base/repo"
  spoof_repo="$base/spoof-repo"
  mkdir -p "$repo" "$spoof_repo"
  git -C "$repo" init -q -b main
  git -C "$spoof_repo" init -q -b main

  if ! (cd "$repo" && PMAI_HOME="$REPO_ROOT" \
    PMAI_PROJECT_HOOKS_LOCK_HELD=1 bash "$INSTALL_PROJECT_HOOKS" --host codex) \
    >/tmp/test-project-hooks-lock-env.out 2>&1; then
    _fail "legacy boolean env should be ignored while the real wrapper acquires a lock"
    cat /tmp/test-project-hooks-lock-env.out >&2
    rm -rf "$base"
    return
  elif [ ! -f "$repo/.git/.pmai-install-project-hooks.lock" ] \
    || [ ! -f "$repo/.codex/hooks.json" ]; then
    _fail "legacy boolean env bypassed the cooperative lock wrapper"
    rm -rf "$base"
    return
  fi

  printf 'not the installer lock\n' > "$spoof_repo/unrelated.lock"
  out=$(
    cd "$spoof_repo" || exit 99
    exec 9<"$spoof_repo/unrelated.lock"
    PMAI_HOME="$REPO_ROOT" PMAI_PROJECT_HOOKS_LOCK_FD=9 \
      bash "$INSTALL_PROJECT_HOOKS" --host codex 2>&1
  )
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q "协作锁 fd 无法验证"; then
    _fail "unrelated inherited fd should fail closed: rc=$rc out=$out"
  elif [ -e "$spoof_repo/.codex/hooks.json" ]; then
    _fail "unverified lock fd allowed Host config mutation"
  else
    pass_test
  fi

  rm -f /tmp/test-project-hooks-lock-env.out
  rm -rf "$base"
}

test_project_hook_installer_reports_recovery_even_when_current() {
  start_test "T6b: current Host config still fails closed on unfinished CAS recovery"

  local base repo recovery before out rc
  base=$(mktemp -d)
  repo="$base/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main

  if ! (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS" --host codex) \
    >/tmp/test-project-hooks-recovery-setup.out 2>&1; then
    _fail "failed to prepare current Codex hooks"
    cat /tmp/test-project-hooks-recovery-setup.out >&2
    rm -rf "$base"
    return
  fi

  recovery="$repo/.codex/.hooks.json.pmai-cas-original-crash"
  printf '%s\n' '{"old":"recover me"}' > "$recovery"
  before=$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')

  out=$(cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS" --check --host codex 2>&1)
  rc=$?
  if [ "$rc" -ne 1 ] \
    || ! echo "$out" | grep -Fq "$recovery" \
    || ! echo "$out" | grep -Fq "存在未收口的原子写入" \
    || echo "$out" | grep -Fq "invalid existing"; then
    _fail "--check hid unfinished CAS recovery: rc=$rc out=$out"
    rm -rf "$base"
    return
  fi

  out=$(cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS" --host codex 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -Fq "$recovery" \
    || ! echo "$out" | grep -Fq "存在未收口的原子写入" \
    || echo "$out" | grep -Fq "invalid existing" \
    || [ ! -f "$recovery" ] \
    || [ "$before" != "$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')" ]; then
    _fail "install overwrote or hid unfinished CAS recovery: rc=$rc out=$out"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_rejects_special_config_without_blocking() {
  start_test "T6c: project hook installer 初读拒绝 FIFO 与 symlink-to-FIFO"

  local base repo out rc
  base=$(mktemp -d)
  repo="$base/repo"
  mkdir -p "$repo/.claude"
  git -C "$repo" init -q -b main

  out=$(python3 - "$repo" "$INSTALL_PROJECT_HOOKS" "$REPO_ROOT" <<'PY' 2>&1
import os
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1])
installer = sys.argv[2]
framework = sys.argv[3]
config = repo / ".claude" / "settings.json"
fifo_target = repo.parent / "settings.fifo"


def run_case(kind: str) -> None:
    config.unlink(missing_ok=True)
    fifo_target.unlink(missing_ok=True)
    if kind == "fifo":
        os.mkfifo(config)
    else:
        os.mkfifo(fifo_target)
        config.symlink_to(fifo_target)

    env = os.environ.copy()
    env["PMAI_HOME"] = framework
    try:
        result = subprocess.run(
            ["bash", installer, "--host", "claude"],
            cwd=repo,
            env=env,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"installer blocked on {kind}") from exc
    output = result.stdout + result.stderr
    assert result.returncode != 0, (kind, output)
    assert "普通文件" in output, (kind, output)


run_case("fifo")
run_case("symlink-to-fifo")
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "特殊 Host 配置未快速失败: rc=$rc out=$out"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_doctor_reports_current_project_hook_drift() {
  start_test "T7: doctor --check 只读检查消费仓 hooks"

  local base repo out
  base=$(mktemp -d)
  repo="$base/repo"
  mkdir -p "$repo/scripts"
  git -C "$repo" init -q -b main
  printf '# PMAI consumer\n' > "$repo/AGENTS.md"
  printf '# state\n' > "$repo/PRODUCT-STATE.md"
  printf '#!/usr/bin/env bash\n' > "$repo/scripts/init-project.sh"

  out=$(cd "$repo" && PMAI_HOME="$REPO_ROOT" \
    PMAI_STATE="$base/status-state" \
    CODEX_HOME="$base/codex-home" KIMI_CODE_HOME="$base/kimi-home" \
    OPENCODE_CONFIG_DIR="$base/opencode" bash "$REPO_ROOT/bin/pmai-doctor" --check 2>&1)
  if ! echo "$out" | grep -q "Current consumer project hooks need refresh"; then
    _fail "doctor should report consumer hook drift: $out"
    rm -rf "$base"
    return
  fi
  if [ -e "$base/status-state" ] \
    || [ -e "$repo/.git/.pmai-install-project-hooks.lock" ]; then
    _fail "doctor check must not create update-check state or the installer lock"
    rm -rf "$base"
    return
  fi

  if ! (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS") >/dev/null 2>&1; then
    _fail "failed to prepare current project hooks"
    rm -rf "$base"
    return
  fi
  out=$(cd "$repo" && PMAI_HOME="$REPO_ROOT" \
    PMAI_STATE="$base/status-state" \
    CODEX_HOME="$base/codex-home" KIMI_CODE_HOME="$base/kimi-home" \
    OPENCODE_CONFIG_DIR="$base/opencode" bash "$REPO_ROOT/bin/pmai-doctor" --check 2>&1)
  if ! echo "$out" | grep -q "Current consumer project hooks match the installed framework"; then
    _fail "doctor should report refreshed hooks as current: $out"
    rm -rf "$base"
    return
  fi
  if [ -e "$base/status-state" ]; then
    _fail "doctor refresh check must remain read-only"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_rejects_invalid_event_atomically() {
  start_test "T8: project hook installer 遇到非法 event 时不留下半安装状态"

  local base repo out before_claude before_codex
  base=$(mktemp -d)
  repo="$base/repo"
  out="$base/install.out"
  mkdir -p "$repo/.claude" "$repo/.codex"
  git -C "$repo" init -q -b main
  printf '%s\n' '{"theme":"keep-claude-setting"}' > "$repo/.claude/settings.json"
  cat > "$repo/.codex/hooks.json" <<'JSON'
{
  "custom": "keep-codex-setting",
  "hooks": {
    "UserPromptSubmit": {
      "hooks": []
    }
  }
}
JSON
  before_claude=$(shasum -a 256 "$repo/.claude/settings.json" | awk '{print $1}')
  before_codex=$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')

  if (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS") >"$out" 2>&1; then
    _fail "非数组 hook event 应让安装失败"
    rm -rf "$base"
    return
  fi
  if ! grep -q "must be an array" "$out"; then
    _fail "非法 hook event 未给出明确错误"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi
  if [ "$before_claude" != "$(shasum -a 256 "$repo/.claude/settings.json" | awk '{print $1}')" ] \
    || [ "$before_codex" != "$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')" ]; then
    _fail "后一个 host 校验失败时不应改写任一配置"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_rolls_back_write_failure_and_preserves_modes() {
  start_test "T9: project hook installer 写盘失败会跨 Host 回滚且保留权限"

  local base repo fake_bin out before_claude before_codex mode_claude mode_codex leftovers
  local linked_target linked_backup outside_target outside_dir real_python
  base=$(mktemp -d)
  repo="$base/repo"
  fake_bin="$base/bin"
  out="$base/install.out"
  mkdir -p "$repo/.claude" "$repo/.codex" "$fake_bin"
  git -C "$repo" init -q -b main
  printf '%s\n' '{"theme":"old-claude"}' > "$repo/.claude/settings.json"
  printf '%s\n' '{"custom":"old-codex"}' > "$repo/.codex/hooks.json"
  chmod 0600 "$repo/.claude/settings.json"
  chmod 0640 "$repo/.codex/hooks.json"
  before_claude=$(shasum -a 256 "$repo/.claude/settings.json" | awk '{print $1}')
  before_codex=$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')
  real_python=$(command -v python3)

  cat > "$fake_bin/python3" <<SH
#!/usr/bin/env bash
parent=""
dest_name=""
previous=""
for argument in "\$@"; do
  if [ "\$previous" = "--parent-display" ]; then parent="\$argument"; fi
  if [ "\$previous" = "--destination-name" ]; then dest_name="\$argument"; fi
  previous="\$argument"
done
if [ "\${1:-}" = "$REPO_ROOT/scripts/_lib/atomic_file.py" ] \
  && [ "\${2:-}" = "replace-at" ] \
  && [[ "\$parent/\$dest_name" == */.codex/hooks.json ]]; then
  exit 73
fi
exec "$real_python" "\$@"
SH
  chmod +x "$fake_bin/python3"

  if (cd "$repo" && PATH="$fake_bin:$PATH" PMAI_HOME="$REPO_ROOT" \
    bash "$INSTALL_PROJECT_HOOKS") >"$out" 2>&1; then
    _fail "第二个 Host 写盘失败时安装器不应返回成功"
    rm -rf "$base"
    return
  fi
  if ! grep -q "已恢复写入前的 Host 配置" "$out"; then
    _fail "写盘失败未明确报告跨 Host 回滚"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi
  mode_claude=$(_mode_of "$repo/.claude/settings.json")
  mode_codex=$(_mode_of "$repo/.codex/hooks.json")
  if [ "$before_claude" != "$(shasum -a 256 "$repo/.claude/settings.json" | awk '{print $1}')" ] \
    || [ "$before_codex" != "$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')" ] \
    || [ "$mode_claude" != "600" ] || [ "$mode_codex" != "640" ]; then
    _fail "跨 Host 回滚必须恢复原内容和 mode"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi
  leftovers=$(find "$repo" \( -name '*.pmai-new.*' -o -name '*.bak.*' \) -print -quit)
  if [ -n "$leftovers" ]; then
    _fail "成功回滚后遗留事务临时文件：$leftovers"
    rm -rf "$base"
    return
  fi

  rm -f "$repo/.claude/settings.json"
  before_codex=$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')
  if (cd "$repo" && PATH="$fake_bin:$PATH" PMAI_HOME="$REPO_ROOT" \
    bash "$INSTALL_PROJECT_HOOKS") >"$base/install-new-file.out" 2>&1; then
    _fail "新建第一个 Host 后第二个写盘失败不应返回成功"
    rm -rf "$base"
    return
  fi
  if [ -e "$repo/.claude/settings.json" ] \
    || [ "$before_codex" != "$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')" ] \
    || [ "$(_mode_of "$repo/.codex/hooks.json")" != "640" ]; then
    _fail "原配置不存在时，跨 Host 回滚应删除本轮新建文件并恢复既有配置"
    cat "$base/install-new-file.out" >&2
    rm -rf "$base"
    return
  fi
  leftovers=$(find "$repo" \( -name '*.pmai-new.*' -o -name '*.bak.*' \) -print -quit)
  if [ -n "$leftovers" ]; then
    _fail "新文件回滚后遗留事务临时文件：$leftovers"
    rm -rf "$base"
    return
  fi

  printf '%s\n' '{"theme":"old-claude"}' > "$repo/.claude/settings.json"
  chmod 0600 "$repo/.claude/settings.json"
  if ! (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS" --host claude) \
    >"$base/claude-install.out" 2>&1; then
    _fail "Claude-only 正常刷新失败"
    cat "$base/claude-install.out" >&2
    rm -rf "$base"
    return
  fi
  if [ "$(_mode_of "$repo/.claude/settings.json")" != "600" ]; then
    _fail "刷新已有配置不应放宽 0600 权限"
    rm -rf "$base"
    return
  fi

  rm -f "$repo/.codex/hooks.json"
  if ! (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS" --host codex) \
    >"$base/codex-install.out" 2>&1; then
    _fail "Codex-only 新配置安装失败"
    cat "$base/codex-install.out" >&2
    rm -rf "$base"
    return
  fi
  if [ "$(_mode_of "$repo/.codex/hooks.json")" != "644" ]; then
    _fail "新建 Host 配置应使用 0644"
    rm -rf "$base"
    return
  fi

  linked_target="$repo/.claude/linked-claude-settings.json"
  printf '%s\n' '{"theme":"linked-claude"}' > "$linked_target"
  chmod 0600 "$linked_target"
  rm -f "$repo/.claude/settings.json"
  ln -s "$linked_target" "$repo/.claude/settings.json"
  if ! (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS" --host claude) \
    >"$base/claude-symlink-install.out" 2>&1; then
    _fail "符号链接 Claude 配置刷新失败"
    cat "$base/claude-symlink-install.out" >&2
    rm -rf "$base"
    return
  fi
  linked_backup=$(find "$repo/.claude" -maxdepth 1 -name 'linked-claude-settings.json.bak.*' -print -quit)
  if [ ! -L "$repo/.claude/settings.json" ] \
    || [ "$(readlink "$repo/.claude/settings.json")" != "$linked_target" ] \
    || ! grep -q 'linked-claude' "$linked_target" \
    || ! grep -q 'review-skill-guard.cjs' "$linked_target" \
    || [ "$(_mode_of "$linked_target")" != "600" ] \
    || [ -z "$linked_backup" ] \
    || ! grep -q 'linked-claude' "$linked_backup" \
    || [ "$(_mode_of "$linked_backup")" != "600" ]; then
    _fail "刷新符号链接配置应保留链接、原目标权限和可恢复备份"
    cat "$base/claude-symlink-install.out" >&2
    rm -rf "$base"
    return
  fi
  if ! (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS" --check --host claude) \
    >"$base/claude-symlink-check.out" 2>&1; then
    _fail "刷新后的符号链接配置应通过只读漂移检查"
    cat "$base/claude-symlink-check.out" >&2
    rm -rf "$base"
    return
  fi

  outside_target="$base/outside-claude-settings.json"
  printf '%s\n' '{"theme":"outside-must-stay"}' > "$outside_target"
  rm -f "$repo/.claude/settings.json"
  ln -s "$outside_target" "$repo/.claude/settings.json"
  if (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS" --host claude) \
    >"$base/outside-leaf.out" 2>&1; then
    _fail "仓外 leaf symlink 不应被刷新"
    rm -rf "$base"
    return
  fi
  if ! grep -q '解析到仓库外' "$base/outside-leaf.out" \
    || ! grep -q 'outside-must-stay' "$outside_target" \
    || grep -q 'active-build-guard.cjs' "$outside_target" \
    || find "$base" -maxdepth 1 -name 'outside-claude-settings.json.bak.*' -print -quit | grep -q .; then
    _fail "仓外 leaf symlink 必须失败关闭且不得写入或备份仓外文件"
    cat "$base/outside-leaf.out" >&2
    rm -rf "$base"
    return
  fi

  outside_dir="$base/outside-claude-dir"
  mkdir -p "$outside_dir"
  printf '%s\n' '{"theme":"outside-parent-must-stay"}' > "$outside_dir/settings.json"
  rm -rf "$repo/.claude"
  ln -s "$outside_dir" "$repo/.claude"
  if (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_PROJECT_HOOKS" --host claude) \
    >"$base/outside-parent.out" 2>&1; then
    _fail "仓外父目录 symlink 不应被刷新"
    rm -rf "$base"
    return
  fi
  if ! grep -q '解析到仓库外' "$base/outside-parent.out" \
    || ! grep -q 'outside-parent-must-stay' "$outside_dir/settings.json" \
    || grep -q 'active-build-guard.cjs' "$outside_dir/settings.json"; then
    _fail "仓外父目录 symlink 必须失败关闭且不得写入仓外配置"
    cat "$base/outside-parent.out" >&2
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_codex_hook_wrapper_rejects_host_override() {
  start_test "T10: Codex-only wrapper 拒绝调用方覆盖 host"

  local base repo out
  base=$(mktemp -d)
  repo="$base/repo"
  out="$base/wrapper.out"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main

  if (cd "$repo" && PMAI_HOME="$REPO_ROOT" bash "$INSTALL_CODEX_HOOKS" --host claude) >"$out" 2>&1; then
    _fail "Codex-only wrapper 不应接受 --host claude"
    rm -rf "$base"
    return
  fi
  if ! grep -q -- "--host" "$out"; then
    _fail "Codex-only wrapper 应明确提示 --host 不可用"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi
  if [ -e "$repo/.claude/settings.json" ] || [ -e "$repo/.codex/hooks.json" ]; then
    _fail "拒绝 host 覆盖时不应写入任何配置"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_doctor_delegates_relative_target_to_its_doctor() {
  start_test "T11: repo-local doctor 把相对 PMAI_HOME 交给目标 doctor"

  local base fake_home install out rc
  base=$(mktemp -d)
  fake_home="$base/home"
  install="$base/install"
  mkdir -p "$fake_home" "$install/bin"
  cat > "$install/bin/pmai-doctor" <<'SH'
#!/usr/bin/env bash
printf 'TARGET_RELATIVE:%s:%s\n' "$PMAI_HOME" "$*"
exit 23
SH
  chmod +x "$install/bin/pmai-doctor"

  out=$(cd "$base" && HOME="$fake_home" PMAI_HOME=install \
    PMAI_STATE="$base/status-state" \
    CODEX_HOME=codex-home KIMI_CODE_HOME=kimi-home \
    OPENCODE_CONFIG_DIR=opencode bash "$REPO_ROOT/bin/pmai-doctor" --check 2>&1)
  rc=$?
  if [ "$rc" != "23" ] || ! echo "$out" | grep -q 'TARGET_RELATIVE:install:--check'; then
    _fail "doctor 应保留 logical PMAI_HOME 并委托目标 doctor: rc=$rc out=$out"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_doctor_rejects_unreadable_host_root() {
  start_test "T12: repo-local doctor 对不可用目标 doctor 失败关闭"

  local base install out rc
  base=$(mktemp -d)
  install="$base/install"
  mkdir -p "$install"
  chmod 0000 "$install"

  out=$(HOME="$base/home" PMAI_HOME="$install" \
    CODEX_HOME="$base/codex" KIMI_CODE_HOME="$base/kimi" \
    OPENCODE_CONFIG_DIR="$base/opencode" bash "$REPO_ROOT/bin/pmai-doctor" --check 2>&1)
  rc=$?
  chmod 0700 "$install"
  if [ "$rc" = "0" ]; then
    _fail "不可进入的 PMAI_HOME 不应返回成功: $out"
    rm -rf "$base"
    return
  fi
  if ! echo "$out" | grep -q "目标 PMAI doctor 缺失或不可执行"; then
    _fail "不可用目标必须明确报告 doctor 缺失或不可执行: $out"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_preserves_concurrent_second_host_edit() {
  start_test "T13: project hook installer 不覆盖首个 Host 写入后的并发编辑"

  local base repo fake_bin out before_claude real_python
  base=$(mktemp -d)
  repo="$base/repo"
  fake_bin="$base/bin"
  out="$base/install.out"
  mkdir -p "$repo/.claude" "$repo/.codex" "$fake_bin"
  git -C "$repo" init -q -b main
  printf '%s\n' '{"theme":"old-claude"}' > "$repo/.claude/settings.json"
  printf '%s\n' '{"custom":"old-codex"}' > "$repo/.codex/hooks.json"
  before_claude=$(shasum -a 256 "$repo/.claude/settings.json" | awk '{print $1}')
  real_python=$(command -v python3)

  cat > "$fake_bin/python3" <<SH
#!/usr/bin/env bash
parent=""
dest_name=""
previous=""
for argument in "\$@"; do
  if [ "\$previous" = "--parent-display" ]; then parent="\$argument"; fi
  if [ "\$previous" = "--destination-name" ]; then dest_name="\$argument"; fi
  previous="\$argument"
done
if [ "\${1:-}" = "$REPO_ROOT/scripts/_lib/atomic_file.py" ] \
  && [ "\${2:-}" = "replace-at" ] \
  && [[ "\$parent/\$dest_name" == */.claude/settings.json ]]; then
  "$real_python" "\$@" || exit \$?
  printf '%s\n' '{"custom":"concurrent-codex"}' > "$repo/.codex/hooks.json"
  exit 0
fi
exec "$real_python" "\$@"
SH
  chmod +x "$fake_bin/python3"

  if (cd "$repo" && PATH="$fake_bin:$PATH" PMAI_HOME="$REPO_ROOT" \
    bash "$INSTALL_PROJECT_HOOKS") >"$out" 2>&1; then
    _fail "第二个 Host 被并发编辑后安装器不应返回成功"
    rm -rf "$base"
    return
  fi
  if [ "$before_claude" != "$(shasum -a 256 "$repo/.claude/settings.json" | awk '{print $1}')" ] \
    || ! grep -q 'concurrent-codex' "$repo/.codex/hooks.json"; then
    _fail "并发编辑应保留，已写入的首个 Host 应回滚"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_rolls_back_symlink_retarget() {
  start_test "T14: project hook installer 检测写入期间 symlink 改向并回滚旧目标"

  local base repo fake_bin out old_target new_target before_old before_new real_python
  base=$(mktemp -d)
  repo="$base/repo"
  fake_bin="$base/bin"
  out="$base/install.out"
  old_target="$repo/.claude/old-settings.json"
  new_target="$repo/.claude/new-settings.json"
  mkdir -p "$repo/.claude" "$fake_bin"
  git -C "$repo" init -q -b main
  printf '%s\n' '{"theme":"old-target"}' > "$old_target"
  printf '%s\n' '{"theme":"new-target"}' > "$new_target"
  ln -s "$old_target" "$repo/.claude/settings.json"
  before_old=$(shasum -a 256 "$old_target" | awk '{print $1}')
  before_new=$(shasum -a 256 "$new_target" | awk '{print $1}')
  real_python=$(command -v python3)

  cat > "$fake_bin/python3" <<SH
#!/usr/bin/env bash
parent=""
dest_name=""
previous=""
for argument in "\$@"; do
  if [ "\$previous" = "--parent-display" ]; then parent="\$argument"; fi
  if [ "\$previous" = "--destination-name" ]; then dest_name="\$argument"; fi
  previous="\$argument"
done
if [ "\${1:-}" = "$REPO_ROOT/scripts/_lib/atomic_file.py" ] \
  && [ "\${2:-}" = "replace-at" ] \
  && [[ "\$parent/\$dest_name" == */old-settings.json ]]; then
  "$real_python" "\$@" || exit \$?
  /bin/rm -f "$repo/.claude/settings.json"
  /bin/ln -s "$new_target" "$repo/.claude/settings.json"
  exit 0
fi
exec "$real_python" "\$@"
SH
  chmod +x "$fake_bin/python3"

  if (cd "$repo" && PATH="$fake_bin:$PATH" PMAI_HOME="$REPO_ROOT" \
    bash "$INSTALL_PROJECT_HOOKS" --host claude) >"$out" 2>&1; then
    _fail "写入期间 symlink 改向后安装器不应返回成功"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi
  if [ "$(readlink "$repo/.claude/settings.json")" != "$new_target" ] \
    || [ "$before_old" != "$(shasum -a 256 "$old_target" | awk '{print $1}')" ] \
    || [ "$before_new" != "$(shasum -a 256 "$new_target" | awk '{print $1}')" ]; then
    _fail "symlink 改向应保留，新目标不得写入，旧目标应恢复"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_rejects_parent_directory_rebind() {
  start_test "T14b: project hook installer 拒绝已绑定父目录被移出仓库"

  local base repo fake_bin out outside captured marker real_python leftovers
  base=$(mktemp -d)
  base=$(cd "$base" && pwd -P)
  repo="$base/repo"
  fake_bin="$base/bin"
  out="$base/install.out"
  outside="$base/outside"
  captured="$outside/captured-claude"
  marker="$base/rebound"
  mkdir -p "$repo/.claude" "$fake_bin" "$outside"
  git -C "$repo" init -q -b main
  printf '%s\n' '{"theme":"outside-must-stay"}' > "$repo/.claude/settings.json"
  real_python=$(command -v python3)

  cat > "$fake_bin/python3" <<SH
#!/usr/bin/env bash
parent=""
previous=""
for argument in "\$@"; do
  if [ "\$previous" = "--parent-display" ]; then parent="\$argument"; fi
  previous="\$argument"
done
if [ "\${1:-}" = "$REPO_ROOT/scripts/_lib/atomic_file.py" ] \
  && [ "\${2:-}" = "snapshot-at" ] \
  && [ "\$parent" = "$repo/.claude" ] \
  && [ ! -e "$marker" ]; then
  /usr/bin/touch "$marker"
  /bin/mv "$repo/.claude" "$captured"
  /bin/mkdir "$repo/.claude"
fi
exec "$real_python" "\$@"
SH
  chmod +x "$fake_bin/python3"

  if (cd "$repo" && PATH="$fake_bin:$PATH" PMAI_HOME="$REPO_ROOT" \
    bash "$INSTALL_PROJECT_HOOKS" --host claude) >"$out" 2>&1; then
    _fail "父目录绑定后被移出仓库时安装器不应返回成功"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi
  leftovers=$(find "$outside" "$repo/.claude" \
    \( -name '*.pmai-new.*' -o -name '*.bak.*' \) -print -quit)
  if [ ! -f "$marker" ] \
    || [ -e "$repo/.claude/settings.json" ] \
    || ! grep -q 'outside-must-stay' "$captured/settings.json" \
    || grep -q 'review-skill-guard.cjs' "$captured/settings.json" \
    || [ -n "$leftovers" ] \
    || ! grep -q '配置目录在绑定期间被改向' "$out"; then
    _fail "父目录重绑后不得读取后继续、写入、复制或在仓外创建事务文件"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_does_not_overwrite_concurrent_committed_edit() {
  start_test "T15: project hook installer 回滚不覆盖已提交后的并发编辑"

  local base repo fake_bin out before_codex backup stage real_python
  base=$(mktemp -d)
  repo="$base/repo"
  fake_bin="$base/bin"
  out="$base/install.out"
  mkdir -p "$repo/.claude" "$repo/.codex" "$fake_bin"
  git -C "$repo" init -q -b main
  printf '%s\n' '{"theme":"old-claude"}' > "$repo/.claude/settings.json"
  printf '%s\n' '{"custom":"old-codex"}' > "$repo/.codex/hooks.json"
  before_codex=$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')
  real_python=$(command -v python3)

  cat > "$fake_bin/python3" <<SH
#!/usr/bin/env bash
parent=""
dest_name=""
previous=""
for argument in "\$@"; do
  if [ "\$previous" = "--parent-display" ]; then parent="\$argument"; fi
  if [ "\$previous" = "--destination-name" ]; then dest_name="\$argument"; fi
  previous="\$argument"
done
if [ "\${1:-}" = "$REPO_ROOT/scripts/_lib/atomic_file.py" ] \
  && [ "\${2:-}" = "replace-at" ] \
  && [[ "\$parent/\$dest_name" == */.claude/settings.json ]]; then
  "$real_python" "\$@" || exit \$?
  printf '%s\n' '{"theme":"concurrent-after-commit"}' > "\$parent/\$dest_name"
  exit 0
fi
exec "$real_python" "\$@"
SH
  chmod +x "$fake_bin/python3"

  if (cd "$repo" && PATH="$fake_bin:$PATH" PMAI_HOME="$REPO_ROOT" \
    bash "$INSTALL_PROJECT_HOOKS") >"$out" 2>&1; then
    _fail "写入后发生并发编辑时安装器不应返回成功"
    rm -rf "$base"
    return
  fi
  backup=$(find "$repo/.claude" -maxdepth 1 -name 'settings.json.bak.*' -print -quit)
  stage=$(find "$repo/.codex" -maxdepth 1 -name 'hooks.json.pmai-new.*' -print -quit)
  if ! grep -q 'concurrent-after-commit' "$repo/.claude/settings.json" \
    || [ "$before_codex" != "$(shasum -a 256 "$repo/.codex/hooks.json" | awk '{print $1}')" ] \
    || [ -z "$backup" ] \
    || [ -z "$stage" ] \
    || ! grep -q 'old-claude' "$backup" \
    || ! grep -q '未覆盖并发内容' "$out" \
    || ! grep -Fq "$(basename "$stage")" "$out"; then
    _fail "回滚必须保留并发内容、原配置备份和未提交 Host 暂存文件"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_rejects_reused_stage_identity() {
  start_test "T15b: project hook installer 不安装或清理被换 inode 的 stage"

  local base repo fake_bin out marker real_python stage
  base=$(mktemp -d)
  repo="$base/repo"
  fake_bin="$base/bin"
  out="$base/install.out"
  marker="$base/swapped-stage"
  mkdir -p "$repo/.claude" "$fake_bin"
  git -C "$repo" init -q -b main
  printf '%s\n' '{"theme":"old-claude"}' > "$repo/.claude/settings.json"
  real_python=$(command -v python3)

  cat > "$fake_bin/python3" <<SH
#!/usr/bin/env bash
parent=""
dest_name=""
staged_name=""
previous=""
for argument in "\$@"; do
  if [ "\$previous" = "--parent-display" ]; then parent="\$argument"; fi
  if [ "\$previous" = "--destination-name" ]; then dest_name="\$argument"; fi
  if [ "\$previous" = "--staged-name" ]; then staged_name="\$argument"; fi
  previous="\$argument"
done
if [ "\${1:-}" = "$REPO_ROOT/scripts/_lib/atomic_file.py" ] \
  && [ "\${2:-}" = "replace-at" ] \
  && [ "\$dest_name" = "settings.json" ] \
  && [ ! -e "$marker" ]; then
  /usr/bin/touch "$marker"
  /bin/rm -f "\$parent/\$staged_name"
  printf '%s\n' 'foreign-stage' > "\$parent/\$staged_name"
fi
exec "$real_python" "\$@"
SH
  chmod +x "$fake_bin/python3"

  if (cd "$repo" && PATH="$fake_bin:$PATH" PMAI_HOME="$REPO_ROOT" \
    bash "$INSTALL_PROJECT_HOOKS" --host claude) >"$out" 2>&1; then
    _fail "stage inode 被替换后安装器不应返回成功"
    rm -rf "$base"
    return
  fi
  stage=$(find "$repo/.claude" -maxdepth 1 -name 'settings.json.pmai-new.*' -print -quit)
  if [ ! -f "$marker" ] \
    || ! grep -q 'old-claude' "$repo/.claude/settings.json" \
    || grep -q 'review-skill-guard.cjs' "$repo/.claude/settings.json" \
    || [ -z "$stage" ] \
    || ! grep -q 'foreign-stage' "$stage"; then
    _fail "foreign stage 必须保留且不得安装或被 cleanup 删除"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_rejects_reused_backup_identity() {
  start_test "T15c: project hook installer 回滚不安装被换 inode 的 backup"

  local base repo fake_bin out marker real_python backup
  base=$(mktemp -d)
  repo="$base/repo"
  fake_bin="$base/bin"
  out="$base/install.out"
  marker="$base/swapped-backup"
  mkdir -p "$repo/.claude" "$repo/.codex" "$fake_bin"
  git -C "$repo" init -q -b main
  printf '%s\n' '{"theme":"old-claude"}' > "$repo/.claude/settings.json"
  printf '%s\n' '{"custom":"old-codex"}' > "$repo/.codex/hooks.json"
  real_python=$(command -v python3)

  cat > "$fake_bin/python3" <<SH
#!/usr/bin/env bash
parent=""
dest_name=""
previous=""
for argument in "\$@"; do
  if [ "\$previous" = "--parent-display" ]; then parent="\$argument"; fi
  if [ "\$previous" = "--destination-name" ]; then dest_name="\$argument"; fi
  previous="\$argument"
done
if [ "\${1:-}" = "$REPO_ROOT/scripts/_lib/atomic_file.py" ] \
  && [ "\${2:-}" = "replace-at" ] \
  && [ "\$dest_name" = "hooks.json" ] \
  && [ ! -e "$marker" ]; then
  /usr/bin/touch "$marker"
  backup=\$(/usr/bin/find "$repo/.claude" -maxdepth 1 -name 'settings.json.bak.*' -print -quit)
  /bin/rm -f "\$backup"
  printf '%s\n' 'foreign-backup' > "\$backup"
  exit 73
fi
exec "$real_python" "\$@"
SH
  chmod +x "$fake_bin/python3"

  if (cd "$repo" && PATH="$fake_bin:$PATH" PMAI_HOME="$REPO_ROOT" \
    bash "$INSTALL_PROJECT_HOOKS") >"$out" 2>&1; then
    _fail "backup inode 被替换后跨 Host 安装不应返回成功"
    rm -rf "$base"
    return
  fi
  backup=$(find "$repo/.claude" -maxdepth 1 -name 'settings.json.bak.*' -print -quit)
  if [ ! -f "$marker" ] \
    || [ -z "$backup" ] \
    || ! grep -q 'foreign-backup' "$backup" \
    || grep -q 'foreign-backup' "$repo/.claude/settings.json" \
    || ! grep -q 'review-skill-guard.cjs' "$repo/.claude/settings.json" \
    || ! grep -q 'old-codex' "$repo/.codex/hooks.json"; then
    _fail "foreign backup 必须保留且不得作为回滚源安装"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_project_hook_installer_rejects_malformed_prepare_protocol() {
  start_test "T15d: project hook installer 严格拒绝非 8 字段 identity 协议"

  local base repo fake_bin out real_python before protocol
  base=$(mktemp -d)
  repo="$base/repo"
  fake_bin="$base/bin"
  out="$base/install.out"
  mkdir -p "$repo/.claude" "$fake_bin"
  git -C "$repo" init -q -b main
  printf '%s\n' '{"theme":"must-stay"}' > "$repo/.claude/settings.json"
  before=$(shasum -a 256 "$repo/.claude/settings.json" | awk '{print $1}')
  real_python=$(command -v python3)

  cat > "$fake_bin/python3" <<SH
#!/usr/bin/env bash
if [ "\${1:-}" = "$REPO_ROOT/scripts/_lib/atomic_file.py" ] \
  && [ "\${2:-}" = "prepare-at" ]; then
  printf '%s\n' "\${PMAI_BAD_PREPARED_PROTOCOL:-}"
  exit 0
fi
exec "$real_python" "\$@"
SH
  chmod +x "$fake_bin/python3"

  for protocol in \
    $'1\t2\tbackup\t3\t4\tstage\t5' \
    $'1\t2\tbackup\t3\t4\tstage\t5\t6\textra' \
    $'-\t-\t-\t-\t-\tstage\t5\t6' \
    $'x\t2\tbackup\t3\t4\tstage\t5\t6'; do
    if (cd "$repo" && PATH="$fake_bin:$PATH" \
      PMAI_BAD_PREPARED_PROTOCOL="$protocol" PMAI_HOME="$REPO_ROOT" \
      bash "$INSTALL_PROJECT_HOOKS" --host claude) >"$out" 2>&1; then
      _fail "malformed prepare protocol unexpectedly succeeded: $protocol"
      rm -rf "$base"
      return
    fi
    if ! grep -Eq '字段数不是 8|非法 replacement 身份组合' "$out"; then
      _fail "malformed prepare protocol did not fail explicitly: $protocol"
      cat "$out" >&2
      rm -rf "$base"
      return
    fi
    if [ "$before" != "$(shasum -a 256 "$repo/.claude/settings.json" | awk '{print $1}')" ]; then
      _fail "malformed prepare protocol modified the Host config"
      rm -rf "$base"
      return
    fi
  done

  rm -rf "$base"
  pass_test
}

test_init_project_blocks_reinitialize_even_with_allow_existing() {
  start_test "T16: init-project.sh 即使带 --allow-existing 也拒绝已初始化 PMAI 目录"

  local base proj out
  base=$(mktemp -d)
  proj="$base/already-pmai"
  out="/tmp/test-init-project-reinit-guard.out"
  mkdir -p "$proj"
  cat > "$proj/AGENTS.md" <<'MD'
# already-pmai

## PMAI Agent Entry

本仓已经初始化完成，不能在这里再跑 /pmai-init-project。
MD

  if PMAI_HOME="$REPO_ROOT" bash "$INIT_PROJECT_SH" "already-pmai" "$proj" "重复初始化保护测试" --allow-existing \
       >"$out" 2>&1; then
    _fail "init-project.sh 不应允许已初始化 PMAI 目录带 --allow-existing 重跑"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi

  if ! grep -q "目标目录已经接入 PMAI" "$out"; then
    _fail "重复初始化保护未输出 PMAI marker 提示"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi
  if ! grep -q "已阻止重复初始化" "$out"; then
    _fail "重复初始化保护未输出阻止说明"
    cat "$out" >&2
    rm -rf "$base"
    return
  fi
  if [ -f "$proj/PRODUCT.md" ] || [ -f "$proj/.pm-workflow/config.yml" ]; then
    _fail "重复初始化保护失败：脚本仍写入了 PMAI 模板"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_agents_template_exists_and_maps_codex
test_init_project_knows_agents_template
test_codex_hooks_template_shape
test_e2e_generates_agents_md_without_framework_assets
test_shared_preamble_reports_stale_consumer_entry
test_install_codex_hooks_merges_existing_hooks
test_project_hook_installer_checks_and_refreshes_both_hosts
test_project_hook_installer_requires_verified_lock_fd
test_project_hook_installer_reports_recovery_even_when_current
test_project_hook_installer_rejects_special_config_without_blocking
test_doctor_reports_current_project_hook_drift
test_project_hook_installer_rejects_invalid_event_atomically
test_project_hook_installer_rolls_back_write_failure_and_preserves_modes
test_codex_hook_wrapper_rejects_host_override
test_doctor_delegates_relative_target_to_its_doctor
test_doctor_rejects_unreadable_host_root
test_project_hook_installer_preserves_concurrent_second_host_edit
test_project_hook_installer_rolls_back_symlink_retarget
test_project_hook_installer_rejects_parent_directory_rebind
test_project_hook_installer_does_not_overwrite_concurrent_committed_edit
test_project_hook_installer_rejects_reused_stage_identity
test_project_hook_installer_rejects_reused_backup_identity
test_project_hook_installer_rejects_malformed_prepare_protocol
test_init_project_blocks_reinitialize_even_with_allow_existing

report_results "init-project-codex-compat"
