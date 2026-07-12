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
  for tool in awk basename bash cat chmod comm cp cut date dirname find git grep head ln mkdir mktemp mv pwd python3 rm sed sort tail touch tr uname wc xargs; do
    path=$(command -v "$tool" 2>/dev/null || true)
    if [ -n "$path" ] && [ ! -e "$fake_bin/$tool" ]; then
      ln -s "$path" "$fake_bin/$tool"
    fi
  done
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
}

test_private_repo_install_surfaces_prereqs() {
  start_test "T1: 私有仓式 clone install 会安装并提示 gstack readiness"
  local out rc

  out=$(HOME="$FAKE_HOME" CODEX_HOME="$FAKE_CODEX_HOME" PMAI_HOME="$PMAI_HOME" PMAI_REMOTE="$SOURCE_REPO" PATH="$FAKE_PATH" \
    bash "$REPO_ROOT/bin/pmai" install 2>&1)
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
  if [ ! -f "$FAKE_HOME/.config/opencode/commands/pmai-init-project.md" ]; then
    _fail "OpenCode command 暴露缺 pmai-init-project"
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
  if ! echo "$out" | grep -q "OpenCode slash commands"; then
    _fail "doctor 应检查 OpenCode slash commands"
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
  if [ ! -f "$target/.opencode/commands/pmai-build.md" ]; then
    _fail "消费仓缺 .opencode/commands/pmai-build.md"
    return
  fi
  if [ ! -f "$target/opencode.json" ]; then
    _fail "消费仓缺 opencode.json"
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
FAKE_BIN="$TMP_ROOT/fake-bin"

mkdir -p "$FAKE_HOME" "$FAKE_CODEX_HOME" "$WORK_DIR"
make_fake_path "$FAKE_BIN"
FAKE_PATH="$FAKE_BIN"
make_source_snapshot "$SOURCE_REPO"

test_private_repo_install_surfaces_prereqs
test_doctor_reports_private_onboarding_state
test_init_project_runs_without_gstack
test_init_project_output_is_same_with_gstack_skill

report_results "private-onboarding"
