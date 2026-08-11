#!/usr/bin/env bash
# Kimi Code first-class host and external builder regression: native skills,
# managed hooks, entry templates, lifecycle coverage, and current-host mapping.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANAGER="$REPO_ROOT/scripts/manage-kimi-hooks.py"
DISPATCH="$REPO_ROOT/scripts/kimi-hook-dispatch.sh"

test_kimi_native_entry_is_documented() {
  start_test "K1: 生成器和消费仓声明 Kimi 原生 /skill:pmai-* 入口"

  assert_file_contains "$REPO_ROOT/AGENTS.md" "/skill:pmai-build" "generator entry should document Kimi native command" || return
  assert_file_contains "$REPO_ROOT/templates/AGENTS.md.tmpl" "/skill:pmai-build" "consumer entry should document Kimi native command" || return
  assert_file_contains "$REPO_ROOT/templates/CLAUDE.md.tmpl" "/skill:pmai-status" "consumer charter should map status for Kimi" || return
  assert_file_contains "$REPO_ROOT/AGENTS.md" "重新完整读取本 checkout" "generator Kimi entry should prefer checkout sources" || return
  pass_test
}

test_kimi_hook_manager_preserves_user_config() {
  start_test "K2: Kimi hook manager 只维护标记区并保留用户配置"
  local tmp config before_without_block after_remove

  tmp=$(mktemp -d)
  config="$tmp/config.toml"
  printf '%s\n' 'default_model = "demo"' '' '[thinking]' 'enabled = true' > "$config"

  python3 "$MANAGER" install --config "$config" >/dev/null || {
    _fail "manage-kimi-hooks install failed"
    rm -rf "$tmp"
    return
  }
  python3 "$MANAGER" check --config "$config" >/dev/null || {
    _fail "manage-kimi-hooks check failed after install"
    rm -rf "$tmp"
    return
  }
  assert_file_contains "$config" 'event = "PreToolUse"' "Kimi hooks should include PreToolUse" || { rm -rf "$tmp"; return; }
  assert_file_contains "$config" 'event = "UserPromptSubmit"' "Kimi hooks should include UserPromptSubmit" || { rm -rf "$tmp"; return; }
  assert_file_contains "$config" 'kimi-hook-dispatch.sh' "Kimi hooks should route through scoped dispatcher" || { rm -rf "$tmp"; return; }
  assert_file_contains "$config" 'prompt-review' "Kimi hooks should keep review injection separate" || { rm -rf "$tmp"; return; }
  assert_file_contains "$config" 'prompt-build' "Kimi hooks should keep active build injection separate" || { rm -rf "$tmp"; return; }
  local prompt_hook_count
  prompt_hook_count=$(grep -c 'event = "UserPromptSubmit"' "$config")
  if [ "$prompt_hook_count" != "2" ]; then
    _fail "Kimi should install two independent prompt hooks, got $prompt_hook_count"
    rm -rf "$tmp"
    return
  fi

  before_without_block=$(sed -n '1,/^# >>> PMAI managed Kimi Code hooks >>>$/p' "$config" | sed '$d' | sed '/^[[:space:]]*$/d')
  python3 "$MANAGER" remove --config "$config" >/dev/null || {
    _fail "manage-kimi-hooks remove failed"
    rm -rf "$tmp"
    return
  }
  after_remove=$(sed '/^[[:space:]]*$/d' "$config")
  if [ "$before_without_block" != "$after_remove" ]; then
    _fail "Kimi hook remove should preserve non-PMAI config"
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_kimi_dispatch_is_scoped_and_maps_write_path() {
  start_test "K3: Kimi 全局 Hook 仅作用于 PMAI 消费仓并映射 path 字段"
  local tmp consumer ordinary payload out rc

  tmp=$(mktemp -d)
  consumer="$tmp/consumer"
  ordinary="$tmp/ordinary"
  mkdir -p "$consumer" "$ordinary"
  git -C "$consumer" init -q -b main
  git -C "$ordinary" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"
  payload=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Write","tool_input":{"path":"%s/src/app.ts","content":"x"}}' "$consumer" "$consumer")

  out=$(
    cd "$consumer" || exit 99
    printf '%s' "$payload" | PMAI_HOME="$REPO_ROOT" bash "$DISPATCH" write 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ]; then
    _fail "PMAI consumer main write should be denied after Kimi path mapping"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q "main 分支写保护"; then
    _fail "Kimi write denial should preserve PMAI branch guard reason"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi

  payload=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Write","tool_input":{"path":"%s/src/app.ts","content":"x"}}' "$ordinary" "$ordinary")
  (
    cd "$ordinary" || exit 99
    printf '%s' "$payload" | PMAI_HOME="$REPO_ROOT" bash "$DISPATCH" write >/dev/null 2>&1
  )
  rc=$?
  if [ "$rc" != "0" ]; then
    _fail "global Kimi hook should be a no-op outside PMAI repos"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_lifecycle_surface_is_complete() {
  start_test "K4: 生命周期与 doctor 覆盖 Kimi，status 只作兼容包装"
  local file

  for file in pmai-install pmai-upgrade pmai-uninstall pmai-doctor; do
    assert_file_contains "$REPO_ROOT/bin/$file" "KIMI_CODE_HOME" "$file should honor KIMI_CODE_HOME" || return
    assert_file_contains "$REPO_ROOT/bin/$file" "KIMI_SKILLS" "$file should manage Kimi skills" || return
  done
  assert_file_contains "$REPO_ROOT/bin/pmai-install" "manage-kimi-hooks.py" "install should manage Kimi hooks" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-upgrade" "manage-kimi-hooks.py" "upgrade should refresh Kimi hooks" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-uninstall" "manage-kimi-hooks.py" "uninstall should remove only managed Kimi hooks" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-doctor" "Kimi Code PMAI-managed hooks" "doctor should validate Kimi hooks" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-status" "pmai-doctor" "status should delegate Kimi health to doctor" || return
  assert_file_contains "$REPO_ROOT/bin/pmai-status" "--check" "status should use read-only doctor mode" || return
  pass_test
}

test_builder_supports_kimi_with_current_host_exclusion() {
  start_test "K5: Kimi 可作外部 builder，作为当前主控时排除同名 profile"
  local out

  out=$(python3 "$REPO_ROOT/scripts/builder-profile.py" list \
    "$REPO_ROOT/templates/pm-workflow.config.yml.tmpl" --current-host codex 2>&1) || {
    _fail "builder-profile should list Kimi for other hosts"
    echo "$out" >&2
    return
  }
  if ! echo "$out" | grep -q '"executor": "kimi-code"'; then
    _fail "Kimi should be available as an external builder for Codex"
    return
  fi

  out=$(python3 "$REPO_ROOT/scripts/builder-profile.py" list \
    "$REPO_ROOT/templates/pm-workflow.config.yml.tmpl" --current-host kimi-code 2>&1) || {
    _fail "builder-profile should accept --current-host kimi-code"
    echo "$out" >&2
    return
  }
  if ! echo "$out" | grep -q '"executor": "native"'; then
    _fail "Kimi host should keep current-session native build available"
    return
  fi
  if echo "$out" | grep -q '"executor": "kimi-code"'; then
    _fail "Kimi current host should exclude the same external profile"
    return
  fi
  if [ ! -x "$REPO_ROOT/scripts/exec-adapters/kimi-code.sh" ]; then
    _fail "Kimi external builder adapter should be executable"
    return
  fi
  pass_test
}

test_public_skill_names_match_kimi_native_commands() {
  start_test "K6: 公开 Skill frontmatter 与 Kimi 原生命令名一致"
  local skill_file skill_dir expected actual

  for skill_file in "$REPO_ROOT"/skills/*/SKILL.md; do
    skill_dir=$(basename "$(dirname "$skill_file")")
    case "$skill_dir" in
      _internal|_shared) continue ;;
      pmai-*) expected="$skill_dir" ;;
      *) expected="pmai-$skill_dir" ;;
    esac
    actual=$(sed -n 's/^name:[[:space:]]*//p' "$skill_file" | head -1)
    if [ "$actual" != "$expected" ]; then
      _fail "$skill_file should declare name: $expected for /skill:$expected, got: ${actual:-missing}"
      return
    fi
  done
  pass_test
}

test_no_machine_bound_kimi_paths() {
  start_test "K7: Kimi 宿主资产不写死机器路径"
  if grep -En -- '/Users/[A-Za-z0-9]' "$MANAGER" "$DISPATCH" "$REPO_ROOT/templates/AGENTS.md.tmpl" "$REPO_ROOT/templates/CLAUDE.md.tmpl"; then
    _fail "Kimi host assets should not contain machine-bound paths"
    return
  fi
  pass_test
}

test_kimi_dispatch_keeps_prompt_outputs_separate() {
  start_test "K8: Kimi prompt review 与 active build 分别分发"
  assert_file_contains "$DISPATCH" 'prompt-review' "dispatcher should expose review prompt mode" || return
  assert_file_contains "$DISPATCH" 'prompt-build' "dispatcher should expose active build prompt mode" || return
  if grep -Eq 'write\|bash\|prompt\)' "$DISPATCH"; then
    _fail "dispatcher should not concatenate two hook outputs through one prompt mode"
    return
  fi
  pass_test
}

test_kimi_dispatch_never_executes_forged_generator_hooks() {
  start_test "K9: 仿冒生成器仓不能让 Kimi 全局 dispatcher 执行仓内 JS"
  local tmp forged sentinel payload out

  tmp=$(mktemp -d)
  forged="$tmp/forged-generator"
  sentinel="$tmp/repo-local-hook-executed"
  mkdir -p "$forged/skills/init-project" "$forged/hooks"
  git -C "$forged" init -q -b main
  printf '# fake runtime\n' > "$forged/RUNTIME.md"
  printf '# fake claude\n' > "$forged/CLAUDE.md"
  printf '# fake skill\n' > "$forged/skills/init-project/SKILL.md"
  cat > "$forged/hooks/check-doc-currency.cjs" <<'JS'
require('fs').writeFileSync(process.env.PMAI_TEST_SENTINEL, 'executed');
JS

  payload=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Bash","tool_input":{"command":"git commit -m fake"}}' "$forged")
  out=$(
    cd "$forged" || exit 99
    printf '%s' "$payload" | PMAI_HOME="$forged" PMAI_TEST_SENTINEL="$sentinel" bash "$DISPATCH" bash 2>&1
  )
  if [ -e "$sentinel" ]; then
    _fail "forged generator executed repository-local hook: $out"
    rm -rf "$tmp"
    return
  fi

  # Marker-based generator recognition remains available for a development
  # checkout separate from the installed framework, but it executes only the
  # dispatcher's trusted hook source.
  payload=$(printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"/review"}' "$forged")
  out=$(
    cd "$forged" || exit 99
    printf '%s' "$payload" | bash "$DISPATCH" prompt-review 2>&1
  )
  if ! echo "$out" | grep -q "REVIEW SKILL 执行强制约束"; then
    _fail "separate generator checkout should still run the trusted review hook: $out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_dispatch_fails_closed_when_trusted_prompt_hook_breaks() {
  start_test "K10: Kimi prompt dispatcher 对可信 hook 缺失/Node 失败/hook 非零失败关闭"
  local tmp trusted generator payload out rc fake_bin

  tmp=$(mktemp -d)
  trusted="$tmp/trusted-framework"
  generator="$tmp/generator-checkout"
  fake_bin="$tmp/fake-bin"
  mkdir -p "$trusted/scripts" "$trusted/hooks" \
    "$generator/skills/init-project" "$fake_bin"
  cp "$DISPATCH" "$trusted/scripts/kimi-hook-dispatch.sh"
  chmod +x "$trusted/scripts/kimi-hook-dispatch.sh"
  git -C "$generator" init -q -b main
  printf '# runtime\n' > "$generator/RUNTIME.md"
  printf '# claude\n' > "$generator/CLAUDE.md"
  printf '# skill\n' > "$generator/skills/init-project/SKILL.md"
  payload=$(printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","prompt":"继续"}' "$generator")

  out=$(
    cd "$generator" || exit 99
    printf '%s' "$payload" | bash "$trusted/scripts/kimi-hook-dispatch.sh" prompt-build 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "prompt-build 的可信 hook 文件缺失"; then
    _fail "missing trusted prompt hook should block with rc=2: $out"
    rm -rf "$tmp"
    return
  fi

  printf 'process.exit(0);\n' > "$trusted/hooks/review-skill-guard.cjs"
  local required_cmd
  for required_cmd in dirname mktemp cat python3 git rm; do
    ln -s "$(command -v "$required_cmd")" "$fake_bin/$required_cmd"
  done
  out=$(
    cd "$generator" || exit 99
    printf '%s' "$payload" | PATH="$fake_bin" \
      /bin/bash "$trusted/scripts/kimi-hook-dispatch.sh" prompt-review 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "prompt-review 需要 node"; then
    _fail "missing node should block with rc=2: $out"
    rm -rf "$tmp"
    return
  fi

  printf 'process.exit(7);\n' > "$trusted/hooks/active-build-guard.cjs"
  out=$(
    cd "$generator" || exit 99
    printf '%s' "$payload" | bash "$trusted/scripts/kimi-hook-dispatch.sh" prompt-build 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "prompt-build 执行失败（退出状态 7）"; then
    _fail "arbitrary hook failure should block with rc=2: $out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_write_dispatch_fails_closed_when_trusted_guard_breaks() {
  start_test "K11: Kimi write dispatcher 对可信护栏缺失/映射失败/检查非零失败关闭"
  local tmp trusted consumer generator payload out rc

  tmp=$(mktemp -d)
  trusted="$tmp/trusted-framework"
  consumer="$tmp/consumer"
  generator="$tmp/generator-checkout"
  mkdir -p "$trusted/scripts" "$consumer" "$generator/skills/init-project"
  cp "$DISPATCH" "$trusted/scripts/kimi-hook-dispatch.sh"
  chmod +x "$trusted/scripts/kimi-hook-dispatch.sh"

  git -C "$consumer" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"
  payload=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Write","tool_input":{"path":"%s/src/app.ts","content":"x"}}' "$consumer" "$consumer")

  out=$(
    cd "$consumer" || exit 99
    printf '%s' "$payload" | bash "$trusted/scripts/kimi-hook-dispatch.sh" write 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "write 的可信 hook 文件缺失"; then
    _fail "missing trusted write guard should block with rc=2: $out"
    rm -rf "$tmp"
    return
  fi

  git -C "$generator" init -q -b main
  printf '# runtime\n' > "$generator/RUNTIME.md"
  printf '# claude\n' > "$generator/CLAUDE.md"
  printf '# skill\n' > "$generator/skills/init-project/SKILL.md"
  payload=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Write","tool_input":{"path":"%s/src/app.ts","content":"x"}}' "$generator" "$generator")
  out=$(
    cd "$generator" || exit 99
    printf '%s' "$payload" | bash "$trusted/scripts/kimi-hook-dispatch.sh" write 2>&1
  )
  rc=$?
  if [ "$rc" != "0" ] || [ -n "$out" ]; then
    _fail "generator write should remain a no-op when the consumer guard is missing: $out"
    rm -rf "$tmp"
    return
  fi

  printf '#!/usr/bin/env bash\nexit 0\n' > "$trusted/scripts/check-branch.sh"
  payload=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Write","tool_input":{}}' "$consumer")
  out=$(
    cd "$consumer" || exit 99
    printf '%s' "$payload" | bash "$trusted/scripts/kimi-hook-dispatch.sh" write 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "write 输入映射失败"; then
    _fail "write input without a path should block when validation fails: $out"
    rm -rf "$tmp"
    return
  fi

  payload=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Write","tool_input":[]}' "$consumer")
  out=$(
    cd "$consumer" || exit 99
    printf '%s' "$payload" | bash "$trusted/scripts/kimi-hook-dispatch.sh" write 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "write 输入映射失败"; then
    _fail "write input with a non-object tool_input should block: $out"
    rm -rf "$tmp"
    return
  fi

  printf '#!/usr/bin/env bash\necho "stub write guard failed" >&2\nexit 7\n' > "$trusted/scripts/check-branch.sh"
  payload=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Write","tool_input":{"path":"%s/src/app.ts","content":"x"}}' "$consumer" "$consumer")
  out=$(
    cd "$consumer" || exit 99
    printf '%s' "$payload" | bash "$trusted/scripts/kimi-hook-dispatch.sh" write 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "write 检查失败（退出状态 7）"; then
    _fail "arbitrary write guard failure should block with rc=2: $out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_write_rejects_conflicting_path_aliases() {
  start_test "K14: Kimi write 的 file_path/path 必须规范化后指向同一目标"
  local tmp trusted consumer capture payload out rc

  tmp=$(mktemp -d)
  trusted="$tmp/trusted-framework"
  consumer="$tmp/consumer"
  capture="$tmp/mapped-input.json"
  mkdir -p "$trusted/scripts" "$consumer/src" "$consumer/packages/foo/docs"
  cp "$DISPATCH" "$trusted/scripts/kimi-hook-dispatch.sh"
  chmod +x "$trusted/scripts/kimi-hook-dispatch.sh"
  cat > "$trusted/scripts/check-branch.sh" <<'SH'
#!/usr/bin/env bash
cat > "$PMAI_TEST_CAPTURE"
SH
  git -C "$consumer" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"

  payload=$(printf '{"cwd":"%s","tool_input":{"file_path":"%s/src/app.ts","path":"%s/src/other.ts"}}' \
    "$consumer" "$consumer" "$consumer")
  out=$(
    cd "$consumer" || exit 99
    printf '%s' "$payload" | PMAI_TEST_CAPTURE="$capture" \
      bash "$trusted/scripts/kimi-hook-dispatch.sh" write 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "write 输入映射失败" \
    || [ -e "$capture" ]; then
    _fail "conflicting file_path/path should block before the write guard: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi

  payload=$(printf '{"cwd":"%s","tool_input":{"file_path":"src/../src/app.ts","path":"%s/src/app.ts"}}' \
    "$consumer" "$consumer")
  out=$(
    cd "$consumer" || exit 99
    printf '%s' "$payload" | PMAI_TEST_CAPTURE="$capture" \
      bash "$trusted/scripts/kimi-hook-dispatch.sh" write 2>&1
  )
  rc=$?
  if [ "$rc" != "0" ] || [ -n "$out" ] || [ ! -f "$capture" ]; then
    _fail "canonically identical file_path/path should reach the write guard: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  python3 - "$capture" "$consumer" <<'PY'
import json
import sys
from pathlib import Path

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["tool_input"]["file_path"] == str(
    (Path(sys.argv[2]) / "src/app.ts").resolve(strict=False)
)
assert "path" not in payload["tool_input"]
PY
  if [ "$?" -ne 0 ]; then
    _fail "canonical alias mapping changed the accepted write payload"
    rm -rf "$tmp"
    return
  fi

  rm -f "$capture"
  payload=$(printf '{"cwd":"%s","tool_input":{"path":"docs/a.md"}}' \
    "$consumer/packages/foo")
  out=$(
    cd "$consumer/packages/foo" || exit 99
    printf '%s' "$payload" | PMAI_TEST_CAPTURE="$capture" \
      bash "$trusted/scripts/kimi-hook-dispatch.sh" write 2>&1
  )
  rc=$?
  if [ "$rc" != "0" ] || [ -n "$out" ] || [ ! -f "$capture" ]; then
    _fail "relative write path from a nested payload cwd should reach the guard: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  python3 - "$capture" "$consumer/packages/foo/docs/a.md" <<'PY'
import json
import sys
from pathlib import Path

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["tool_input"]["file_path"] == str(Path(sys.argv[2]).resolve(strict=False)), payload
PY
  if [ "$?" -ne 0 ]; then
    _fail "nested payload cwd did not map the relative write target to its absolute path"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_dispatch_blocks_conflicting_pmai_and_process_roots() {
  start_test "K15: 进程 cwd 路由普通仓，PMAI 路由内的 payload 跨根失败关闭"
  local tmp consumer ordinary other forged payload out rc

  tmp=$(mktemp -d)
  consumer="$tmp/consumer"
  ordinary="$tmp/ordinary"
  other="$tmp/other"
  forged="$tmp/forged-generator"
  mkdir -p "$consumer" "$ordinary" "$other" "$forged/skills/init-project"
  git -C "$consumer" init -q -b main
  git -C "$ordinary" init -q -b main
  git -C "$other" init -q -b main
  git -C "$forged" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"
  printf '# runtime\n' > "$forged/RUNTIME.md"
  printf '# claude\n' > "$forged/CLAUDE.md"
  printf '# skill\n' > "$forged/skills/init-project/SKILL.md"

  for payload in \
    "$(printf '{\"cwd\":\"%s\",\"prompt\":\"继续\"}' "$ordinary")" \
    "$(printf '{\"cwd\":\"%s\",\"prompt\":\"继续\"}' "$forged")"; do
    out=$(
      cd "$consumer" || exit 99
      printf '%s' "$payload" | bash "$DISPATCH" prompt-build 2>&1
    )
    rc=$?
    if [ "$rc" != "2" ] || ! echo "$out" | grep -q "cwd 与进程 cwd 指向不同 Git 仓库"; then
      _fail "PMAI process cwd conflict should block: rc=$rc out=$out"
      rm -rf "$tmp"
      return
    fi
  done

  payload=$(printf '{"cwd":"%s","prompt":"继续"}' "$consumer")
  out=$(
    cd "$ordinary" || exit 99
    printf '%s' "$payload" | bash "$DISPATCH" prompt-build 2>&1
  )
  rc=$?
  if [ "$rc" != "0" ] || [ -n "$out" ]; then
    _fail "ordinary process cwd should ignore a forged PMAI payload route: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi

  payload=$(printf '{"cwd":"%s","prompt":"继续"}' "$other")
  out=$(
    cd "$ordinary" || exit 99
    printf '%s' "$payload" | bash "$DISPATCH" prompt-build 2>&1
  )
  rc=$?
  if [ "$rc" != "0" ] || [ -n "$out" ]; then
    _fail "two ordinary repositories should remain a silent no-op: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_dispatch_rejects_invalid_input_only_inside_pmai_repos() {
  start_test "K12: Kimi dispatcher 识别仓库后统一拒绝非法输入"
  local tmp consumer generator ordinary missing payload mode out rc

  tmp=$(mktemp -d)
  consumer="$tmp/consumer"
  generator="$tmp/generator"
  ordinary="$tmp/ordinary"
  missing="$tmp/does-not-exist"
  mkdir -p "$consumer" "$generator/skills/init-project" "$ordinary"
  git -C "$consumer" init -q -b main
  git -C "$generator" init -q -b main
  git -C "$ordinary" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"
  printf '# runtime\n' > "$generator/RUNTIME.md"
  printf '# claude\n' > "$generator/CLAUDE.md"
  printf '# skill\n' > "$generator/skills/init-project/SKILL.md"

  for payload in '{bad-json' '[]'; do
    out=$(
      cd "$ordinary" || exit 99
      printf '%s' "$payload" | bash "$DISPATCH" prompt-build 2>&1
    )
    rc=$?
    if [ "$rc" != "0" ] || [ -n "$out" ]; then
      _fail "ordinary repo should remain a no-op for malformed input: $out"
      rm -rf "$tmp"
      return
    fi
  done

  payload=$(printf '{"cwd":"%s","tool_input":{"path":"%s/src/app.ts"}}' "$missing" "$ordinary")
  out=$(
    cd "$ordinary" || exit 99
    printf '%s' "$payload" | bash "$DISPATCH" write 2>&1
  )
  rc=$?
  if [ "$rc" != "0" ] || [ -n "$out" ]; then
    _fail "ordinary repo should remain a no-op after invalid cwd fallback: $out"
    rm -rf "$tmp"
    return
  fi

  for mode in write bash prompt-review prompt-build; do
    out=$(
      cd "$generator" || exit 99
      printf '%s' '{bad-json' | bash "$DISPATCH" "$mode" 2>&1
    )
    rc=$?
    if [ "$rc" != "2" ] || ! echo "$out" | grep -q "输入不是合法 JSON"; then
      _fail "PMAI generator $mode should reject invalid JSON with rc=2: $out"
      rm -rf "$tmp"
      return
    fi
  done

  out=$(
    cd "$consumer" || exit 99
    printf '%s' '[]' | bash "$DISPATCH" write 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "输入必须是 JSON 对象"; then
    _fail "PMAI consumer should reject a non-object payload: $out"
    rm -rf "$tmp"
    return
  fi

  payload=$(printf '{"cwd":42,"tool_input":{"path":"%s/src/app.ts"}}' "$consumer")
  out=$(
    cd "$consumer" || exit 99
    printf '%s' "$payload" | bash "$DISPATCH" write 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "cwd 必须是有效字符串路径"; then
    _fail "PMAI consumer should reject a non-string cwd after fallback: $out"
    rm -rf "$tmp"
    return
  fi

  payload=$(printf '{"cwd":"%s","tool_input":{"path":"%s/src/app.ts"}}' "$missing" "$consumer")
  out=$(
    cd "$consumer" || exit 99
    printf '%s' "$payload" | bash "$DISPATCH" write 2>&1
  )
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "cwd 无法定位 Git 仓库"; then
    _fail "invalid payload cwd should fall back to the PMAI process cwd and block: $out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_dispatch_fails_closed_for_missing_or_broken_python() {
  start_test "K13: Kimi dispatcher 对 Python 缺失和启动失败保持相同失败语义"
  local tmp consumer generator ordinary fake_bin runtime_state repo expected out rc required_cmd

  tmp=$(mktemp -d)
  consumer="$tmp/consumer"
  generator="$tmp/generator"
  ordinary="$tmp/ordinary"
  fake_bin="$tmp/fake-bin"
  mkdir -p "$consumer" "$generator/skills/init-project" "$ordinary" "$fake_bin"
  git -C "$consumer" init -q -b main
  git -C "$generator" init -q -b main
  git -C "$ordinary" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"
  printf '# runtime\n' > "$generator/RUNTIME.md"
  printf '# claude\n' > "$generator/CLAUDE.md"
  printf '# skill\n' > "$generator/skills/init-project/SKILL.md"
  for required_cmd in dirname mktemp cat git grep node rm; do
    ln -s "$(command -v "$required_cmd")" "$fake_bin/$required_cmd"
  done

  for runtime_state in missing broken; do
    if [ "$runtime_state" = "broken" ]; then
      printf '#!/bin/sh\nexit 9\n' > "$fake_bin/python3"
      chmod +x "$fake_bin/python3"
    fi
    for repo in "$ordinary" "$consumer" "$generator"; do
      expected=2
      [ "$repo" = "$ordinary" ] && expected=0
      out=$(
        cd "$repo" || exit 99
        printf '%s' '{}' | PATH="$fake_bin" /bin/bash "$DISPATCH" write 2>&1
      )
      rc=$?
      if [ "$rc" != "$expected" ]; then
        _fail "$runtime_state python in $(basename "$repo") should return $expected, got $rc: $out"
        rm -rf "$tmp"
        return
      fi
      if [ "$expected" = "0" ] && [ -n "$out" ]; then
        _fail "ordinary repo should stay silent with $runtime_state python: $out"
        rm -rf "$tmp"
        return
      fi
      if [ "$expected" = "2" ] && ! echo "$out" | grep -q "需要 python3"; then
        _fail "PMAI repo should explain $runtime_state python failure: $out"
        rm -rf "$tmp"
        return
      fi
    done
  done

  rm -rf "$tmp"
  pass_test
}

test_kimi_ordinary_routing_does_not_parse_payload() {
  start_test "K23: ordinary 进程 cwd 在读取 payload 前直接 no-op"
  local tmp consumer ordinary fake_bin payload out rc required_cmd

  tmp=$(mktemp -d)
  consumer="$tmp/consumer"
  ordinary="$tmp/ordinary"
  fake_bin="$tmp/fake-bin"
  mkdir -p "$consumer" "$ordinary" "$fake_bin"
  git -C "$consumer" init -q -b main
  git -C "$ordinary" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"
  for required_cmd in dirname git; do
    ln -s "$(command -v "$required_cmd")" "$fake_bin/$required_cmd"
  done

  for payload in \
    '{bad-json' \
    "$(printf '{\"cwd\":\"%s\",\"tool_input\":{}}' "$consumer")"; do
    out=$(
      cd "$ordinary" || exit 99
      printf '%s' "$payload" | PATH="$fake_bin" /bin/bash "$DISPATCH" write 2>&1
    )
    rc=$?
    if [ "$rc" != "0" ] || [ -n "$out" ]; then
      _fail "ordinary routing should not inspect hook payload or require runtimes: rc=$rc out=$out"
      rm -rf "$tmp"
      return
    fi
  done

  rm -rf "$tmp"
  pass_test
}

test_kimi_prompt_build_times_out_before_outer_hook() {
  start_test "K16: Kimi prompt-build 在 stdin 未结束时主动失败关闭"
  local tmp consumer out rc

  tmp=$(mktemp -d)
  consumer="$tmp/consumer"
  mkdir -p "$consumer"
  git -C "$consumer" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"

  out=$(python3 - "$consumer" "$DISPATCH" <<'PY' 2>&1
import json
import os
import subprocess
import sys

consumer, dispatcher = sys.argv[1:3]
env = os.environ.copy()
env["PMAI_KIMI_STDIN_TIMEOUT_MS"] = "50"
process = subprocess.Popen(
    ["bash", dispatcher, "prompt-build"],
    cwd=consumer,
    env=env,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
assert process.stdin is not None
process.stdin.write(json.dumps({"cwd": consumer, "prompt": "看看还有什么问题"}))
process.stdin.flush()
try:
    process.wait(timeout=2)
except subprocess.TimeoutExpired as exc:
    process.kill()
    raise AssertionError("dispatcher waited for the outer Kimi timeout") from exc
stdout = process.stdout.read() if process.stdout is not None else ""
stderr = process.stderr.read() if process.stderr is not None else ""
assert process.returncode == 0, (process.returncode, stdout, stderr)
data = json.loads(stdout)
context = data["hookSpecificOutput"]["additionalContext"]
assert "ACTIVE BUILD 续接护栏不可用" in context, context
assert "读取期限内未结束" in context, context
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "Kimi stdin timeout did not fail closed promptly: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_missing_python_does_not_wait_for_stdin_eof() {
  start_test "K17: Python 缺失时 Kimi dispatcher 不等待 stdin EOF"
  local tmp consumer generator ordinary fake_bin out rc required_cmd

  tmp=$(mktemp -d)
  consumer="$tmp/consumer"
  generator="$tmp/generator"
  ordinary="$tmp/ordinary"
  fake_bin="$tmp/fake-bin"
  mkdir -p "$consumer" "$generator/skills/init-project" "$ordinary" "$fake_bin"
  git -C "$consumer" init -q -b main
  git -C "$generator" init -q -b main
  git -C "$ordinary" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"
  printf '# runtime\n' > "$generator/RUNTIME.md"
  printf '# claude\n' > "$generator/CLAUDE.md"
  printf '# skill\n' > "$generator/skills/init-project/SKILL.md"
  for required_cmd in dirname git grep mktemp node rm; do
    ln -s "$(command -v "$required_cmd")" "$fake_bin/$required_cmd"
  done

  out=$(python3 - "$ordinary" "$consumer" "$generator" "$fake_bin" "$DISPATCH" <<'PY' 2>&1
import os
import subprocess
import sys

ordinary, consumer, generator, fake_bin, dispatcher = sys.argv[1:]
env = os.environ.copy()
env["PATH"] = fake_bin
env["PMAI_KIMI_STDIN_TIMEOUT_MS"] = "50"

for repo in (ordinary, consumer, generator):
    process = subprocess.Popen(
        ["/bin/bash", dispatcher, "write"],
        cwd=repo,
        env=env,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired as exc:
        process.kill()
        raise AssertionError(f"dispatcher waited for stdin EOF in {repo}") from exc
    stdout = process.stdout.read() if process.stdout is not None else ""
    stderr = process.stderr.read() if process.stderr is not None else ""
    expected = 0 if repo == ordinary else 2
    assert process.returncode == expected, (repo, process.returncode, stdout, stderr)
    assert stdout == "", (repo, stdout)
    if repo == ordinary:
        assert stderr == "", (repo, stderr)
    else:
        assert "需要 python3" in stderr, (repo, stderr)

print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "missing Python dispatcher did not terminate before stdin EOF: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_dispatch_fails_closed_when_git_is_unavailable() {
  start_test "K20: Git 不可用时 PMAI cwd 与 payload cwd 都失败关闭"
  local tmp consumer generator ordinary fake_bin out rc

  tmp=$(mktemp -d)
  consumer="$tmp/consumer"
  generator="$tmp/generator"
  ordinary="$tmp/ordinary"
  fake_bin="$tmp/fake-bin"
  mkdir -p "$consumer" "$generator/skills/init-project" "$ordinary" "$fake_bin"
  git -C "$consumer" init -q -b main
  git -C "$generator" init -q -b main
  git -C "$ordinary" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"
  printf '# runtime\n' > "$generator/RUNTIME.md"
  printf '# claude\n' > "$generator/CLAUDE.md"
  printf '# skill\n' > "$generator/skills/init-project/SKILL.md"
  cat > "$fake_bin/git" <<'SH'
#!/bin/sh
exit 127
SH
  chmod +x "$fake_bin/git"

  out=$(python3 - "$ordinary" "$consumer" "$generator" "$fake_bin" "$DISPATCH" <<'PY' 2>&1
import json
import os
import subprocess
import sys

ordinary, consumer, generator, fake_bin, dispatcher = sys.argv[1:]
env = os.environ.copy()
env["PATH"] = fake_bin + os.pathsep + env.get("PATH", "")

def dispatch(cwd, payload):
    try:
        return subprocess.run(
            ["/bin/bash", dispatcher, "write"],
            cwd=cwd,
            env=env,
            input=payload,
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"dispatcher did not terminate without Git in {cwd}") from exc

for repo, expected in ((ordinary, 0), (consumer, 2), (generator, 2)):
    result = dispatch(repo, "{}")
    assert result.returncode == expected, (repo, result.returncode, result.stdout, result.stderr)
    assert result.stdout == "", (repo, result.stdout)
    if expected == 0:
        assert result.stderr == "", (repo, result.stderr)
    else:
        assert "Git 不可用或仓库定位失败" in result.stderr, (repo, result.stderr)

payload = json.dumps(
    {"cwd": consumer, "tool_input": {"path": f"{consumer}/src/app.ts"}},
    ensure_ascii=False,
)
result = dispatch(ordinary, payload)
assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
assert result.stdout == "", result.stdout
assert result.stderr == "", result.stderr
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "Git-unavailable dispatcher contract failed or exceeded its deadline: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_ordinary_repo_does_not_wait_for_stdin() {
  start_test "K18: ordinary 仓不等待 stdin 结束"
  local tmp ordinary out rc

  tmp=$(mktemp -d)
  ordinary="$tmp/ordinary"
  mkdir -p "$ordinary"
  git -C "$ordinary" init -q -b main

  out=$(python3 - "$ordinary" "$DISPATCH" <<'PY' 2>&1
import subprocess
import sys

ordinary, dispatcher = sys.argv[1:]
process = subprocess.Popen(
    ["bash", dispatcher, "prompt-build"],
    cwd=ordinary,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
try:
    process.wait(timeout=2)
except subprocess.TimeoutExpired as exc:
    process.kill()
    raise AssertionError("ordinary dispatcher waited for stdin") from exc
stdout = process.stdout.read() if process.stdout is not None else ""
stderr = process.stderr.read() if process.stderr is not None else ""
assert process.returncode == 0, (process.returncode, stdout, stderr)
assert stdout == "" and stderr == "", (stdout, stderr)
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "ordinary dispatcher did not no-op before stdin: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_timeout_blocks_when_context_json_generation_fails() {
  start_test "K19: timeout 失败上下文生成异常时 Kimi dispatcher 返回 rc2"
  local tmp consumer fake_bin marker out rc required_cmd real_python

  tmp=$(mktemp -d)
  consumer="$tmp/consumer"
  fake_bin="$tmp/fake-bin"
  marker="$tmp/python-used"
  mkdir -p "$consumer" "$fake_bin"
  git -C "$consumer" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"
  for required_cmd in dirname git grep mktemp rm; do
    ln -s "$(command -v "$required_cmd")" "$fake_bin/$required_cmd"
  done
  real_python=$(command -v python3)
  cat > "$fake_bin/python3" <<'SH'
#!/bin/sh
if [ ! -e "$PMAI_TEST_PYTHON_MARKER" ]; then
  : > "$PMAI_TEST_PYTHON_MARKER"
  exec "$PMAI_TEST_REAL_PYTHON" "$@"
fi
exit 9
SH
  chmod +x "$fake_bin/python3"

  out=$(python3 - "$consumer" "$fake_bin" "$marker" "$real_python" "$DISPATCH" <<'PY' 2>&1
import json
import os
import subprocess
import sys

consumer, fake_bin, marker, real_python, dispatcher = sys.argv[1:]
env = os.environ.copy()
env.update(
    {
        "PATH": fake_bin,
        "PMAI_KIMI_STDIN_TIMEOUT_MS": "50",
        "PMAI_TEST_PYTHON_MARKER": marker,
        "PMAI_TEST_REAL_PYTHON": real_python,
    }
)
process = subprocess.Popen(
    ["/bin/bash", dispatcher, "prompt-build"],
    cwd=consumer,
    env=env,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
assert process.stdin is not None
process.stdin.write(json.dumps({"cwd": consumer, "prompt": "继续"}))
process.stdin.flush()
try:
    process.wait(timeout=2)
except subprocess.TimeoutExpired as exc:
    process.kill()
    raise AssertionError("dispatcher waited for the outer Kimi timeout") from exc
stdout = process.stdout.read() if process.stdout is not None else ""
stderr = process.stderr.read() if process.stderr is not None else ""
assert process.returncode == 2, (process.returncode, stdout, stderr)
assert stdout == "", stdout
assert "无法生成 prompt-build 的失败关闭上下文" in stderr, stderr
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "prompt-build timeout JSON failure did not block: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_prompt_build_shares_remaining_total_budget() {
  start_test "K21: Kimi stdin 读取耗时从 prompt-build 总预算扣除"
  local tmp trusted consumer runtime_tmp fake_bin real_mktemp out rc

  tmp=$(mktemp -d)
  trusted="$tmp/framework"
  consumer="$tmp/consumer"
  runtime_tmp="$tmp/runtime-tmp"
  fake_bin="$tmp/fake-bin"
  real_mktemp=$(command -v mktemp)
  mkdir -p "$trusted/scripts" "$trusted/hooks" "$consumer" "$runtime_tmp" "$fake_bin"
  cat > "$fake_bin/mktemp" <<SH
#!/bin/sh
exec "$real_mktemp" "$runtime_tmp/pmai.XXXXXX"
SH
  chmod +x "$fake_bin/mktemp"
  cp "$DISPATCH" "$trusted/scripts/kimi-hook-dispatch.sh"
  cat > "$trusted/hooks/active-build-guard.cjs" <<'JS'
const fs = require('fs');
fs.readFileSync(0);
process.stdout.write(JSON.stringify({
  remaining: Number(process.env.PMAI_ACTIVE_BUILD_TOTAL_BUDGET_MS || 0),
}));
JS
  git -C "$consumer" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"

  out=$(python3 - "$consumer" "$trusted/scripts/kimi-hook-dispatch.sh" \
    "$runtime_tmp" "$fake_bin" <<'PY' 2>&1
import json
import os
import subprocess
import sys
import time
from pathlib import Path

consumer, dispatcher, runtime_tmp, fake_bin = sys.argv[1:]
env = os.environ.copy()
env["PMAI_KIMI_STDIN_TIMEOUT_MS"] = "1000"
env["PMAI_ACTIVE_BUILD_TOTAL_BUDGET_MS"] = "2000"
env["PATH"] = fake_bin + os.pathsep + env.get("PATH", "")
process = subprocess.Popen(
    ["bash", dispatcher, "prompt-build"],
    cwd=consumer,
    env=env,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
)
assert process.stdin is not None
process.stdin.write(json.dumps({"cwd": consumer, "prompt": "继续"}))
process.stdin.flush()

# mktemp creates the input file first and the budget clock second. Observing a
# typed clock value in this isolated directory proves the reader has recorded
# its cross-process start time before we intentionally hold stdin open.
deadline = time.monotonic() + 2
clock_started = False
while time.monotonic() < deadline:
    for candidate in Path(runtime_tmp).iterdir():
        try:
            value = candidate.read_text(encoding="ascii").strip()
        except (OSError, UnicodeDecodeError):
            continue
        clock_kind, separator, clock_value = value.partition(":")
        if (
            separator
            and clock_kind in {"monotonic", "wall"}
            and clock_value.isdigit()
        ):
            clock_started = True
            break
    if clock_started:
        break
    if process.poll() is not None:
        break
    time.sleep(0.01)
assert clock_started, "dispatcher did not start the budget clock"
time.sleep(0.3)
process.stdin.close()
assert process.wait(timeout=3) == 0
stdout = process.stdout.read() if process.stdout is not None else ""
stderr = process.stderr.read() if process.stderr is not None else ""
assert stderr == "", stderr
remaining = json.loads(stdout)["remaining"]
assert 0 < remaining < 1800, remaining
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "prompt-build did not receive the shared remaining budget: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_oversized_payload_respects_process_cwd_route() {
  start_test "K22: 超限 payload 在 ordinary 仓 no-op、在 PMAI 仓失败关闭"
  local tmp ordinary consumer out rc

  tmp=$(mktemp -d)
  ordinary="$tmp/ordinary"
  consumer="$tmp/consumer"
  mkdir -p "$ordinary" "$consumer"
  git -C "$ordinary" init -q -b main
  git -C "$consumer" init -q -b main
  printf '# PMAI consumer\n' > "$consumer/AGENTS.md"
  printf '# state\n' > "$consumer/PRODUCT-STATE.md"

  out=$(python3 - "$ordinary" "$consumer" "$DISPATCH" <<'PY' 2>&1
import json
import subprocess
import sys

ordinary, consumer, dispatcher = sys.argv[1:]
payloads = {
    ordinary: b"{" + b"x" * (4 * 1024 * 1024 + 1),
    consumer: (
        json.dumps({"cwd": consumer, "prompt": ""})[:-2].encode("utf-8")
        + b"x" * (4 * 1024 * 1024 + 1)
    ),
}
for cwd, payload in payloads.items():
    result = subprocess.run(
        ["bash", dispatcher, "prompt-build"],
        cwd=cwd,
        input=payload,
        capture_output=True,
        timeout=3,
    )
    expected = 0 if cwd == ordinary else 2
    assert result.returncode == expected, (cwd, result.returncode, result.stdout, result.stderr)
    assert result.stdout == b"", (cwd, result.stdout)
    if cwd == ordinary:
        assert result.stderr == b"", result.stderr
    else:
        assert "超过 4 MiB 上限" in result.stderr.decode("utf-8"), result.stderr
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "oversized payload did not follow the process cwd route: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_kimi_native_entry_is_documented
test_kimi_hook_manager_preserves_user_config
test_kimi_dispatch_is_scoped_and_maps_write_path
test_kimi_lifecycle_surface_is_complete
test_builder_supports_kimi_with_current_host_exclusion
test_public_skill_names_match_kimi_native_commands
test_no_machine_bound_kimi_paths
test_kimi_dispatch_keeps_prompt_outputs_separate
test_kimi_dispatch_never_executes_forged_generator_hooks
test_kimi_dispatch_fails_closed_when_trusted_prompt_hook_breaks
test_kimi_write_dispatch_fails_closed_when_trusted_guard_breaks
test_kimi_write_rejects_conflicting_path_aliases
test_kimi_dispatch_blocks_conflicting_pmai_and_process_roots
test_kimi_dispatch_rejects_invalid_input_only_inside_pmai_repos
test_kimi_dispatch_fails_closed_for_missing_or_broken_python
test_kimi_ordinary_routing_does_not_parse_payload
test_kimi_prompt_build_times_out_before_outer_hook
test_kimi_missing_python_does_not_wait_for_stdin_eof
test_kimi_dispatch_fails_closed_when_git_is_unavailable
test_kimi_ordinary_repo_does_not_wait_for_stdin
test_kimi_timeout_blocks_when_context_json_generation_fails
test_kimi_prompt_build_shares_remaining_total_budget
test_kimi_oversized_payload_respects_process_cwd_route

report_results "kimi-host-compat"
