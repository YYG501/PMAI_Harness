#!/usr/bin/env bash
# test-private-onboarding.sh
#
# 私有仓 onboarding smoke：不访问网络，用当前工作树 tracked 文件做临时 git
# snapshot，模拟「先拿到私有仓访问权，再从该仓安装 PMAI」的路径。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_ROOT=""
cleanup() {
  if [ -n "$TMP_ROOT" ]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup EXIT

make_fake_path() {
  local fake_bin="$1"
  local tool path

  mkdir -p "$fake_bin"
  for tool in awk basename bash sh cat chmod cmp comm cp cut date dirname find git git-upload-pack grep head ln mkdir mktemp mv node pwd python3 readlink rm sed sort tail touch tr uname wc xargs; do
    path=$(command -v "$tool" 2>/dev/null || true)
    if [ -n "$path" ] && [ ! -e "$fake_bin/$tool" ]; then
      ln -s "$path" "$fake_bin/$tool"
    fi
  done
  # Git's Cygwin helpers live in libexec, so Windows resolves their DLLs via
  # PATH. Keep the fixture tool allowlist while making those libraries visible.
  if [[ "$(uname -s)" == CYGWIN* ]]; then
    for path in /usr/bin/cyg*.dll; do
      ln "$path" "$fake_bin/$(basename "$path")"
    done
  fi
}

make_source_snapshot() {
  local src="$1"
  local file

  mkdir -p "$src"
  while IFS= read -r -d '' file; do
    [ -f "$REPO_ROOT/$file" ] || continue
    mkdir -p "$src/$(dirname "$file")"
    cp "$REPO_ROOT/$file" "$src/$file"
  done < <(git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard)

  git -C "$src" init -q
  git -C "$src" config user.email "pmai-test@example.com"
  git -C "$src" config user.name "PMAI Test"
  git -C "$src" add -A
  git -C "$src" commit -qm "test snapshot"
  git -C "$src" tag v0.0.1
  printf 'stable\n' > "$src/.install-channel-fixture"
  git -C "$src" add .install-channel-fixture
  git -C "$src" commit -qm "stable install fixture"
  git -C "$src" tag v0.0.2
  printf 'main\n' > "$src/.install-channel-fixture"
  git -C "$src" add .install-channel-fixture
  git -C "$src" commit -qm "rolling install fixture"
}

test_install_without_node_rolls_back() {
  start_test "runtime: 缺 Node 的安装失败并恢复原有宿主入口"
  local out rc
  mkdir -p "$FAKE_HOME/.claude/skills/pmai-existing"
  printf "keep" > "$FAKE_HOME/.claude/skills/pmai-existing/user.txt"
  mv "$FAKE_BIN/node" "$FAKE_BIN/node-held"
  out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX_HOME" PMAI_HOME="$PMAI_HOME" PATH="$FAKE_PATH" \
    bash "$BOOTSTRAP_REPO/bin/pmai" install 2>&1)
  rc=$?
  mv "$FAKE_BIN/node-held" "$FAKE_BIN/node"
  if [ "$rc" = 0 ] || [ -e "$PMAI_HOME" ] \
    || [ "$(cat "$FAKE_HOME/.claude/skills/pmai-existing/user.txt")" != keep ] \
    || ! echo "$out" | grep -q "Node"; then
    _fail "缺 Node 必须阻断安装、删除失败 clone 并恢复用户文件"
    echo "$out" >&2
  else
    pass_test
  fi
  rm -rf "$FAKE_HOME/.claude/skills/pmai-existing"
}

test_install_without_python_does_not_write() {
  start_test "runtime: 缺 Python 在写入前停止并给出修复提示"
  local out rc
  mv "$FAKE_BIN/python3" "$FAKE_BIN/python-held"
  out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX_HOME" PMAI_HOME="$PMAI_HOME" PATH="$FAKE_PATH" \
    bash "$BOOTSTRAP_REPO/bin/pmai" install 2>&1)
  rc=$?
  mv "$FAKE_BIN/python-held" "$FAKE_BIN/python3"
  if [ "$rc" = 0 ] || [ -e "$PMAI_HOME" ] || [ -e "$FAKE_HOME/.pmai-global-install.lock" ] \
    || ! echo "$out" | grep -q "缺少 python3"; then
    _fail "缺 Python 必须在安装写入前停止"
    echo "$out" >&2
  else
    pass_test
  fi
}

test_versioned_install_modes() {
  start_test "runtime: 首次安装支持 latest stable、指定 tag 和失败回滚"
  local stable_home stable_pmai exact_home exact_pmai invalid_home invalid_pmai out rc
  local stable_head first_head rolling_head

  stable_home="$TMP_ROOT/stable-home"
  stable_pmai="$stable_home/.pmai"
  mkdir -p "$stable_home/.codex"
  out=$(HOME="$stable_home" CODEX_HOME="$stable_home/.codex" PMAI_HOME="$stable_pmai" PATH="$FAKE_PATH" \
    bash "$BOOTSTRAP_REPO/bin/pmai" install --stable 2>&1)
  rc=$?
  stable_head=$(git -C "$SOURCE_REPO" rev-list -n 1 v0.0.2)
  if [ "$rc" != "0" ] || [ "$(git -C "$stable_pmai" rev-parse HEAD 2>/dev/null)" != "$stable_head" ] \
    || [ -n "$(git -C "$stable_pmai" symbolic-ref -q HEAD 2>/dev/null)" ] \
    || ! echo "$out" | grep -q "source: v0.0.2@"; then
    _fail "--stable 必须安装最新 tag、保持 detached 并报告实际来源"
    echo "$out" >&2
    return
  fi
  out=$(HOME="$stable_home" CODEX_HOME="$stable_home/.codex" PMAI_HOME="$stable_pmai" PATH="$FAKE_PATH" \
    bash "$stable_pmai/bin/pmai" upgrade --no-whats-new 2>&1)
  rc=$?
  rolling_head=$(git -C "$SOURCE_REPO" rev-parse HEAD)
  if [ "$rc" != "0" ] || [ "$(git -C "$stable_pmai" rev-parse HEAD 2>/dev/null)" != "$rolling_head" ] \
    || [ "$(git -C "$stable_pmai" symbolic-ref -q HEAD 2>/dev/null)" != "refs/heads/main" ]; then
    _fail "稳定版安装必须能通过默认 upgrade 切回 rolling main"
    echo "$out" >&2
    return
  fi

  exact_home="$TMP_ROOT/exact-home"
  exact_pmai="$exact_home/.pmai"
  mkdir -p "$exact_home/.codex"
  out=$(HOME="$exact_home" CODEX_HOME="$exact_home/.codex" PMAI_HOME="$exact_pmai" PATH="$FAKE_PATH" \
    bash "$BOOTSTRAP_REPO/bin/pmai" install --to v0.0.1 2>&1)
  rc=$?
  first_head=$(git -C "$SOURCE_REPO" rev-list -n 1 v0.0.1)
  if [ "$rc" != "0" ] || [ "$(git -C "$exact_pmai" rev-parse HEAD 2>/dev/null)" != "$first_head" ] \
    || ! echo "$out" | grep -q "source: v0.0.1@"; then
    _fail "--to 必须安装指定 tag 并报告实际来源"
    echo "$out" >&2
    return
  fi

  invalid_home="$TMP_ROOT/invalid-home"
  invalid_pmai="$invalid_home/.pmai"
  mkdir -p "$invalid_home/.codex"
  out=$(HOME="$invalid_home" CODEX_HOME="$invalid_home/.codex" PMAI_HOME="$invalid_pmai" PATH="$FAKE_PATH" \
    bash "$BOOTSTRAP_REPO/bin/pmai" install --to v9.9.9 2>&1)
  rc=$?
  if [ "$rc" = "0" ] || [ -e "$invalid_pmai" ] \
    || [ -e "$invalid_home/.claude/skills/pmai-init-project" ] \
    || ! echo "$out" | grep -q "tag v9.9.9 不存在"; then
    _fail "不存在的安装 tag 必须失败且不留下 framework 或宿主入口"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_detached_upgrade_failure_restores_channel() {
  start_test "runtime: tag 安装切换 main 失败时恢复 HEAD 和本地 main"
  local exact_home exact_pmai before_head before_main out rc
  exact_home="$TMP_ROOT/exact-home"
  exact_pmai="$exact_home/.pmai"
  before_head=$(git -C "$exact_pmai" rev-parse HEAD)
  before_main=$(git -C "$exact_pmai" rev-parse refs/heads/main)
  out=$(HOME="$exact_home" CODEX_HOME="$exact_home/.codex" PMAI_HOME="$exact_pmai" PATH="$FAKE_PATH" \
    bash "$exact_pmai/bin/pmai" upgrade --no-whats-new 2>&1)
  rc=$?
  if [ "$rc" = "0" ] || [ "$(git -C "$exact_pmai" rev-parse HEAD)" != "$before_head" ] \
    || [ -n "$(git -C "$exact_pmai" symbolic-ref -q HEAD 2>/dev/null)" ] \
    || [ "$(git -C "$exact_pmai" rev-parse refs/heads/main)" != "$before_main" ] \
    || [ "$(readlink "$exact_home/.codex/skills/pmai-build")" != "$exact_pmai/skills/build" ]; then
    _fail "detached 安装的 main 升级失败后必须恢复 tag、main ref 和宿主入口"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_doctor_missing_node_json() {
  start_test "runtime: installed doctor JSON 报告缺 Node 为安装问题"
  local out rc
  mv "$FAKE_BIN/node" "$FAKE_BIN/node-held"
  out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX_HOME" PMAI_HOME="$PMAI_HOME" PATH="$FAKE_PATH" \
    bash "$PMAI_HOME/bin/pmai" doctor --check --json 2>/dev/null)
  rc=$?
  mv "$FAKE_BIN/node-held" "$FAKE_BIN/node"
  if [ "$rc" = 0 ] || ! echo "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["conclusion"] == "broken"; assert any("Node" in str(item) for item in d["pm_report"]["action_items"]); assert all(item["status"] == "unknown" for item in d["checks"][1:])'; then
    _fail "缺 Node 的 doctor JSON 不得显示正常或只给参考提醒"
    echo "$out" >&2
  else
    pass_test
  fi
}

test_doctor_missing_python_json() {
  start_test "runtime: 完全缺 Python 时 doctor check/repair 仍返回稳定 JSON"
  local mode out rc lock_path
  lock_path="$TMP_ROOT/missing-python-doctor.lock"
  mv "$FAKE_BIN/python3" "$FAKE_BIN/python-held"
  for mode in --check --repair; do
    out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX_HOME" PMAI_HOME="$PMAI_HOME" \
      PMAI_GLOBAL_INSTALL_LOCK_PATH="$lock_path" PATH="$FAKE_PATH" \
      bash "$PMAI_HOME/bin/pmai" doctor "$mode" --json 2>/dev/null)
    rc=$?
    if [ "$rc" != "1" ] || ! printf '%s\n' "$out" | "$REAL_PYTHON" -c \
      'import json,sys; d=json.load(sys.stdin); assert d["conclusion"] == "broken"; assert d["recommended_action"] == "install_runtime"; assert d["mode"] == sys.argv[1]; assert d["pm_report"]["action_items"]' "${mode#--}"; then
      mv "$FAKE_BIN/python-held" "$FAKE_BIN/python3"
      _fail "缺 Python 时 $mode --json 必须返回退出码 1 和可解析诊断"
      echo "$out" >&2
      return
    fi
  done
  mv "$FAKE_BIN/python-held" "$FAKE_BIN/python3"
  if [ -e "$lock_path" ]; then
    _fail "缺 Python 的 --repair JSON 诊断不得创建全局安装锁"
    return
  fi
  pass_test
}

test_private_repo_install_surfaces_prereqs() {
  start_test "T1: 私有仓式 clone install 只安装完整主控入口并提示 gstack readiness"
  local out rc

  mkdir -p "$FAKE_CODEX_HOME/prompts"
  printf "legacy\n" > "$FAKE_CODEX_HOME/prompts/pmai-build.md"
  printf "keep\n" > "$FAKE_CODEX_HOME/prompts/my-own-prompt.md"

  out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX_HOME" PMAI_HOME="$PMAI_HOME" PATH="$FAKE_PATH" \
    bash "$BOOTSTRAP_REPO/bin/pmai" install 2>&1)
  rc=$?
  if [ "$rc" != "0" ]; then
    _fail "pmai install 应成功"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "PMAI v"; then
    _fail "install 输出缺少版本成功信息"
    echo "$out" >&2
    return
  fi
  if [ "$(git -C "$PMAI_HOME" remote get-url origin 2>/dev/null)" != "$SOURCE_REPO" ]; then
    _fail "install 应复用 bootstrap checkout 已认证的 origin"
    return
  fi
  if ! echo "$out" | grep -q "source: main@"; then
    _fail "滚动安装应输出 main 和实际 commit"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "gstack 未检测到"; then
    _fail "install 应提前提示 gstack readiness"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "初始化不受影响"; then
    _fail "install 的 gstack warning 应说明初始化不受影响"
    echo "$out" >&2
    return
  fi
  if [ ! -L "$FAKE_HOME/.claude/skills/pmai-init-project" ]; then
    _fail "Claude skill 暴露缺 pmai-init-project"
    return
  fi
  if [ ! -L "$FAKE_CODEX_HOME/skills/pmai-init-project" ]; then
    _fail "Codex skill 暴露缺 pmai-init-project"
    return
  fi
  if [ -e "$FAKE_CODEX_HOME/prompts/pmai-build.md" ]; then
    _fail "install 应清理旧版遗留的 pmai-* Codex prompt"
    return
  fi
  if [ ! -f "$FAKE_CODEX_HOME/prompts/my-own-prompt.md" ]; then
    _fail "install 不应清理非 PMAI 的 Codex prompt"
    return
  fi
  if [ -e "$FAKE_HOME/.config/opencode/commands/pmai-init-project.md" ]; then
    _fail "install 不应创建 OpenCode PMAI 主控 command"
    return
  fi
  if [ ! -f "$PMAI_HOME/scripts/project-definition.py" ] \
     || [ -e "$PMAI_HOME/scripts/build-audits.py" ] \
     || [ -e "$PMAI_HOME/agents/coverage-reviewer.md" ]; then
    _fail "隔离安装的 project definition / retired audit assets 不符合当前仓"
    return
  fi
  pass_test
}

test_upgrade_invalid_runtime_restores_previous_install() {
  start_test "runtime: 升级目标声明损坏时恢复旧版本及宿主入口"
  local before before_ref after_ref out rc
  before=$(git -C "$PMAI_HOME" rev-parse HEAD)
  before_ref=$(git -C "$PMAI_HOME" symbolic-ref -q HEAD)
  cp "$PMAI_HOME/config/runtime-manifest.json" "$TMP_ROOT/baseline-runtime.json"
  printf '{}\n' > "$SOURCE_REPO/config/runtime-manifest.json"
  git -C "$SOURCE_REPO" add config/runtime-manifest.json
  git -C "$SOURCE_REPO" commit -qm "invalid runtime regression fixture"
  git -C "$SOURCE_REPO" tag v0.0.0-runtime-fixture
  out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX_HOME" PMAI_HOME="$PMAI_HOME" PATH="$FAKE_PATH" \
    bash "$PMAI_HOME/bin/pmai" upgrade --to v0.0.0-runtime-fixture 2>&1)
  rc=$?
  after_ref=$(git -C "$PMAI_HOME" symbolic-ref -q HEAD)
  if [ "$rc" = 0 ] || [ "$(git -C "$PMAI_HOME" rev-parse HEAD)" != "$before" ] \
    || [ "$before_ref" != "$after_ref" ] \
    || ! cmp -s "$TMP_ROOT/baseline-runtime.json" "$PMAI_HOME/config/runtime-manifest.json" \
    || [ ! -f "$FAKE_CODEX_HOME/skills/pmai-build/SKILL.md" ] \
    || ! echo "$out" | grep -q "Runtime manifest"; then
    _fail "损坏环境声明的升级必须失败且完整恢复"
    echo "$out" >&2
  else
    pass_test
  fi
}

test_doctor_reports_private_onboarding_state() {
  start_test "T2: installed pmai doctor 报告 source/target 并 warning gstack"
  local out rc

  out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX_HOME" PMAI_HOME="$PMAI_HOME" PATH="$FAKE_PATH" \
    bash "$PMAI_HOME/bin/pmai" doctor 2>&1)
  rc=$?
  if [ "$rc" != "0" ]; then
    _fail "pmai doctor 在 warning 状态下仍应成功"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "CLI source:"; then
    _fail "doctor 应输出 CLI source"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "Audit target:"; then
    _fail "doctor 应输出 Audit target"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "gstack 未检测到"; then
    _fail "doctor 应提示 gstack 缺失"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "初始化和非 Web build 不受影响"; then
    _fail "doctor 的 gstack warning 应说明初始化和非 Web build 不受影响"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "OpenCode Builder"; then
    _fail "doctor 应报告 OpenCode Builder readiness"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_init_project_runs_without_gstack() {
  start_test "T3: 缺 gstack 时 init-project 仍建立上下文"
  local out rc target

  target="$WORK_DIR/MissingGstack"
  out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX_HOME" PMAI_HOME="$PMAI_HOME" PATH="$FAKE_PATH" \
    GIT_AUTHOR_NAME="PMAI Test" GIT_AUTHOR_EMAIL="pmai-test@example.com" \
    GIT_COMMITTER_NAME="PMAI Test" GIT_COMMITTER_EMAIL="pmai-test@example.com" \
    bash "$PMAI_HOME/scripts/init-project.sh" MissingGstack "$target" "private onboarding smoke" 2>&1)
  rc=$?
  if [ "$rc" != "0" ]; then
    _fail "缺 gstack 时 init-project 应成功"
    echo "$out" >&2
    return
  fi
  if [ -e "$target/.pm-workflow/project.yml" ] || [ -d "$target/prototype" ]; then
    _fail "初始化不应生成 project.yml 或 prototype"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_init_project_output_is_same_with_gstack_skill() {
  start_test "T4: 有 gstack 时初始化仍只建立上下文"
  local out rc target status_out

  mkdir -p "$FAKE_HOME/.claude/skills/gstack"
  echo "test-gstack" > "$FAKE_HOME/.claude/skills/gstack/VERSION"

  target="$WORK_DIR/PrivateDemo"
  out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX_HOME" PMAI_HOME="$PMAI_HOME" PATH="$FAKE_PATH" \
    GIT_AUTHOR_NAME="PMAI Test" GIT_AUTHOR_EMAIL="pmai-test@example.com" \
    GIT_COMMITTER_NAME="PMAI Test" GIT_COMMITTER_EMAIL="pmai-test@example.com" \
    bash "$PMAI_HOME/scripts/init-project.sh" PrivateDemo "$target" "private onboarding smoke" 2>&1)
  rc=$?
  if [ "$rc" != "0" ]; then
    _fail "补齐 gstack skill 后 init-project 应成功"
    echo "$out" >&2
    return
  fi
  if [ ! -f "$target/AGENTS.md" ]; then
    _fail "消费仓缺 AGENTS.md"
    return
  fi
  if [ ! -f "$target/.codex/hooks.json" ]; then
    _fail "消费仓缺 .codex/hooks.json"
    return
  fi
  if [ ! -f "$target/.claude/settings.json" ]; then
    _fail "消费仓缺 .claude/settings.json"
    return
  fi
  if [ -e "$target/.opencode/commands/pmai-build.md" ] || [ -e "$target/opencode.json" ]; then
    _fail "消费仓不应生成 OpenCode PMAI 主控配置"
    return
  fi
  if [ ! -f "$target/PRODUCT.md" ]; then
    _fail "消费仓缺 PRODUCT.md"
    return
  fi
  if [ -d "$target/.cursor" ]; then
    _fail "本轮不应生成 .cursor 配置"
    return
  fi

  status_out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX_HOME" PMAI_HOME="$PMAI_HOME" PATH="$FAKE_PATH" \
    python3 "$PMAI_HOME/scripts/status-view.py" "$target" --narrative 2>&1)
  if ! echo "$status_out" | grep -q "当前状态：没有进行中的工作"; then
    _fail "status-view 未识别新消费仓空闲状态"
    echo "$status_out" >&2
    return
  fi
  pass_test
}

TMP_ROOT=$(mktemp -d /tmp/pmai-private-onboarding-XXXXXX)
FAKE_HOME="$TMP_ROOT/home"
FAKE_CODEX_HOME="$FAKE_HOME/.codex"
PMAI_HOME="$FAKE_HOME/.pmai"
WORK_DIR="$TMP_ROOT/work"
SOURCE_REPO="$TMP_ROOT/source-repo"
BOOTSTRAP_REPO="$TMP_ROOT/bootstrap-repo"
FAKE_BIN="$TMP_ROOT/fake-bin"
REAL_PYTHON=$(command -v python3)

mkdir -p "$FAKE_HOME" "$FAKE_CODEX_HOME" "$WORK_DIR"
make_fake_path "$FAKE_BIN"
FAKE_PATH="$FAKE_BIN"
make_source_snapshot "$SOURCE_REPO"
git clone -q "$SOURCE_REPO" "$BOOTSTRAP_REPO"

test_install_without_python_does_not_write
test_install_without_node_rolls_back
test_versioned_install_modes
test_private_repo_install_surfaces_prereqs
test_doctor_missing_node_json
test_doctor_missing_python_json
test_doctor_reports_private_onboarding_state
test_init_project_runs_without_gstack
test_init_project_output_is_same_with_gstack_skill
test_upgrade_invalid_runtime_restores_previous_install
test_detached_upgrade_failure_restores_channel

report_results "private-onboarding"
