#!/usr/bin/env bash
# Tests for cancel-work.sh — enforces invariants I-CA1 ~ I-CA7（方案 A·清模块 .work-meta）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CANCEL_WORK="$FRAMEWORK_ROOT/scripts/cancel-work.sh"
CLEANUP_PENDING="$FRAMEWORK_ROOT/scripts/cleanup-pending-worktrees.sh"

# cancel-work（方案 A）：真相源 = docs/modules/<模块>/。废弃 = 在 main 上清模块 .work-meta，
# 不 merge work branch到 main；worktree 推迟到 cleanup-pending 兜底清。
#
# fixture_create_work 在 worktree 里建模块目录。把它镜像到 main 的 docs/modules/，
# 让 cancel-work 能在 main 上清掉模块 .work-meta。返回 main 上的模块目录路径。
_setup_module_on_main() {
  local work_id="$1"
  local name="$2"
  local stage="${3:-3}"
  local work_branch="build-$work_id-$name"

  fixture_create_work "$work_id" "$name" "$stage" >/dev/null

  local main_module="$FIXTURE_DIR/docs/modules/$work_branch"
  mkdir -p "$main_module"
  cp -R "$FIXTURE_DIR/.worktrees/$work_branch/docs/modules/$work_branch/." "$main_module/"

  (cd "$FIXTURE_DIR" && git add -A >/dev/null 2>&1 && git commit -q -m "mirror module $work_id on main" 2>/dev/null || true)

  echo "$main_module"
}

# ---------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------

test_cancel_happy_path() {
  start_test "happy path: cancel clears module .work-meta on main + removes worktree/branch"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-001" "test" 3)

  cd "$FIXTURE_DIR"
  bash "$CANCEL_WORK" "$work_dir" >/dev/null 2>&1

  # Cancel 后 worktree/branch 推迟到 cleanup（防 dangling cwd）。
  bash "$CLEANUP_PENDING" >/dev/null 2>&1

  # Worktree removed
  if [ -d "$FIXTURE_DIR/.worktrees/build-work-001-test" ]; then
    _fail "worktree should be gone after cleanup"
    fixture_teardown; return
  fi
  # Branch removed
  if git -C "$FIXTURE_DIR" branch --list build-work-001-test | grep -q .; then
    _fail "build branch should be deleted after cleanup"
    fixture_teardown; return
  fi
  # 模块 .work-meta 已清（main 上）
  if [ -f "$FIXTURE_DIR/docs/modules/build-work-001-test/.work-meta.json" ]; then
    _fail "module .work-meta should be cleared on main"
    fixture_teardown; return
  fi
  # 模块三件套留场（discussion.md 仍在）
  if [ ! -f "$FIXTURE_DIR/docs/modules/build-work-001-test/discussion.md" ]; then
    _fail "module 三件套 (discussion.md) should remain on main"
    fixture_teardown; return
  fi
  pass_test
  fixture_teardown
}

test_cancel_receipt_only_reports_background_queue() {
  start_test "cancel receipt queues cleanup without delegating a command to PM"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-001" "receipt" 3)

  cd "$FIXTURE_DIR"
  if ! bash "$CANCEL_WORK" "$work_dir" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel failed while checking receipt"
    cat /tmp/err.$$ >&2
  elif [ ! -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "cancel should queue the related work environment"
  elif ! grep -q "后台清理队列" /tmp/out.$$; then
    _fail "cancel receipt should report queued background cleanup"
    cat /tmp/out.$$ >&2
  elif grep -qE 'cleanup-pending-worktrees|bash scripts|请.*执行|回主仓.*运行' /tmp/out.$$; then
    _fail "cancel receipt still delegates cleanup mechanics to PM"
    cat /tmp/out.$$ >&2
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA1: main 零污染
# ---------------------------------------------------------------

test_cancel_does_not_merge_to_main() {
  start_test "I-CA1 cancel does not merge work code to main"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-001" "test" 3)

  # 在 work branch上加一个显著的文件，证明 work branch有内容
  (
    cd "$FIXTURE_DIR/.worktrees/build-work-001-test"
    echo "work-only content" > work-only-marker.md
    git add -A
    git commit -q -m "work branch change"
  )

  cd "$FIXTURE_DIR"
  bash "$CANCEL_WORK" "$work_dir" >/dev/null 2>&1

  # main 上不应该存在 work-only-marker.md
  if [ -f "$FIXTURE_DIR/work-only-marker.md" ]; then
    _fail "main should NOT have work branch's content"
    fixture_teardown; return
  fi

  # git log on main should not contain the work branch commit message
  if git -C "$FIXTURE_DIR" log main --oneline | grep -q "work branch change"; then
    _fail "main log should not contain work branch commit"
    fixture_teardown; return
  fi
  pass_test
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA4（方案 A）：cancel 后模块 .work-meta 已清（不再移 closed/、不再留 status=cancelled 文件）
# ---------------------------------------------------------------

test_cancel_clears_module_meta() {
  start_test "I-CA4 after cancel, module .work-meta is cleared (no closed/ archive)"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-001" "test" 3)

  cd "$FIXTURE_DIR"
  bash "$CANCEL_WORK" "$work_dir" >/dev/null 2>&1

  # 模块 .work-meta 应被删（main 上）
  if [ -f "$FIXTURE_DIR/docs/modules/build-work-001-test/.work-meta.json" ]; then
    _fail "module .work-meta should be cleared after cancel"
    fixture_teardown; return
  fi
  # 方案 A 下不再有 requirements/pmai-closed/ 归档目录
  if [ -d "$FIXTURE_DIR/requirements/pmai-closed/build-work-001-test" ]; then
    _fail "no requirements/pmai-closed/ archive should be created under 方案 A"
    fixture_teardown; return
  fi
  # cancel commit 应进入 main
  # 用 grep ... >/dev/null（不加 -q）：grep -q 命中即早退会让上游 git SIGPIPE，
  # 在 set -o pipefail 下整条管道返回非 0，假阴性。
  if ! git -C "$FIXTURE_DIR" log main --oneline | grep "cancel: work-001" >/dev/null; then
    _fail "main log should contain a cancel commit"
    fixture_teardown; return
  fi
  pass_test
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA5: 幂等
# ---------------------------------------------------------------

test_cancel_is_idempotent_after_partial_cleanup() {
  start_test "I-CA5 idempotent: re-run after partial cleanup does not error"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-001" "test" 3)

  # 手动模拟部分清理状态：删掉 worktree 和分支（但留下 main 上的模块 .work-meta）
  git -C "$FIXTURE_DIR" worktree remove "$FIXTURE_DIR/.worktrees/build-work-001-test" --force 2>/dev/null || \
    rm -rf "$FIXTURE_DIR/.worktrees/build-work-001-test"
  git -C "$FIXTURE_DIR" branch -D build-work-001-test 2>/dev/null || true

  cd "$FIXTURE_DIR"
  # 再跑 cancel-work 应该能清理完剩下的（清 main 上模块 .work-meta）且不报错
  if bash "$CANCEL_WORK" "$work_dir" >/tmp/out.$$ 2>/tmp/err.$$; then
    :
  else
    _fail "second-run cancel-work failed (rc=$?)"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  # 模块 .work-meta 应已清
  if [ -f "$FIXTURE_DIR/docs/modules/build-work-001-test/.work-meta.json" ]; then
    _fail "module .work-meta should be cleared after idempotent re-run"
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi
  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_cancel_rerun_on_already_cleared_does_not_error() {
  start_test "I-CA5 idempotent: running cancel twice on same work does not crash"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-001" "test" 3)

  cd "$FIXTURE_DIR"
  bash "$CANCEL_WORK" "$work_dir" >/dev/null 2>&1
  # 第二次：模块 .work-meta 已被删，脚本应优雅退出（缺 meta 直接报错退出，rc!=0 但不崩溃）。
  # 用 cleanup 把 worktree/branch 清完后第二次跑：模块 .work-meta 已无 → 脚本 fail-fast（缺 meta）。
  bash "$CLEANUP_PENDING" >/dev/null 2>&1
  if bash "$CANCEL_WORK" "$work_dir" >/tmp/out.$$ 2>/tmp/err.$$; then
    # 已无 .work-meta，理应报「不存在」退出非 0；若返回 0 也不算崩溃
    pass_test
  else
    # 缺 meta 时 fail-fast 退出是预期的优雅处理（非崩溃）
    if grep -q "不存在" /tmp/err.$$; then
      pass_test
    else
      _fail "second cancel-work run should fail gracefully (got unexpected error)"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# ---------------------------------------------------------------
# I-CA7: cancel-work must refuse when main has unrelated dirty changes
# ---------------------------------------------------------------

test_cancel_rejects_dirty_main() {
  start_test "I-CA7 cancel rejects when main has unrelated dirty changes"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-001" "test" 3)

  # 在 main 留一个无关脏文件
  echo "stray" > "$FIXTURE_DIR/unrelated.txt"

  cd "$FIXTURE_DIR"
  if bash "$CANCEL_WORK" "$work_dir" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel should have refused with dirty main"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  if ! grep -qE "(污染|unrelated|无关|拒绝)" /tmp/err.$$; then
    _fail "stderr missing pollution-refusal message"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  # 无关文件仍然在，说明没污染 cancel commit
  if [ ! -f "$FIXTURE_DIR/unrelated.txt" ]; then
    _fail "unrelated file got consumed"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  # 没有 cancel commit 进入 main
  if git -C "$FIXTURE_DIR" log main --oneline | grep -q "cancel:"; then
    _fail "main log should not contain a cancel commit"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_cancel_rejects_unconfirmed_module_changes() {
  start_test "cancel only deletes .work-meta and rejects other module changes"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-001" "test" 3)

  printf '\nunconfirmed discussion\n' >> "$work_dir/discussion.md"

  cd "$FIXTURE_DIR"
  if bash "$CANCEL_WORK" "$work_dir" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel should reject unconfirmed changes in the same module"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi
  if ! grep -q "discussion.md" /tmp/err.$$; then
    _fail "cancel should identify the unconfirmed module change"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi
  if ! grep -q "unconfirmed discussion" "$work_dir/discussion.md"; then
    _fail "cancel discarded the unconfirmed discussion change"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi
  if git -C "$FIXTURE_DIR" log main --oneline | grep -q "cancel:"; then
    _fail "cancel commit should not be created after the guard fails"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_cancel_restores_meta_when_commit_fails() {
  start_test "cancel restores .work-meta when its commit is rejected"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-001" "test" 3)

  mkdir -p "$FIXTURE_DIR/.git/hooks"
  printf '#!/bin/sh\nexit 1\n' > "$FIXTURE_DIR/.git/hooks/pre-commit"
  chmod +x "$FIXTURE_DIR/.git/hooks/pre-commit"

  cd "$FIXTURE_DIR"
  if bash "$CANCEL_WORK" "$work_dir" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel should fail when the commit hook rejects its commit"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi
  if [ ! -f "$work_dir/.work-meta.json" ]; then
    _fail "cancel did not restore .work-meta after the commit failed"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi
  if [ -n "$(git -C "$FIXTURE_DIR" status --porcelain --untracked-files=all)" ]; then
    _fail "cancel left staged or working-tree changes after the commit failed"
    git -C "$FIXTURE_DIR" status --short >&2
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi
  if [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
    _fail "cancel queued cleanup even though its state commit failed"
    rm -f /tmp/out.$$ /tmp/err.$$
    fixture_teardown; return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_cancel_prepare_failure_happens_before_state_commit() {
  start_test "cancel prepares cleanup before committing state"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-010" "prepare-fail" 3)
  local fake_bin real_python before after
  fake_bin=$(mktemp -d "${TMPDIR:-/tmp}/pmai-cancel-fakebin.XXXXXX")
  real_python=$(command -v python3)
  before=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  mkdir -p "$fake_bin"
  cat > "$fake_bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == *"pending_cleanup.py" ]] && [ "${2:-}" = "prepare" ]; then
  echo "simulated prepare failure" >&2
  exit 1
fi
exec "$PMAI_TEST_REAL_PYTHON" "$@"
SH
  chmod +x "$fake_bin/python3"

  if (cd "$FIXTURE_DIR" && PATH="$fake_bin:$PATH" \
    PMAI_TEST_REAL_PYTHON="$real_python" bash "$CANCEL_WORK" "$work_dir") \
    >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel should stop when the durable prepare cannot be written"
  else
    after=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
    if [ "$before" != "$after" ]; then
      _fail "cancel committed state before its cleanup intent"
    elif [ ! -f "$work_dir/.work-meta.json" ]; then
      _fail "prepare failure removed the authoritative work meta"
    elif [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
      _fail "failed prepare left a partial queue entry"
    else
      pass_test
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  rm -rf -- "$fake_bin"
  fixture_teardown
}

test_cancel_activation_failure_recovers_from_main_truth() {
  start_test "cancel activation interruption recovers from committed main truth"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-011" "activate-fail" 3)
  local fake_bin real_python queue worktree branch
  fake_bin=$(mktemp -d "${TMPDIR:-/tmp}/pmai-cancel-fakebin.XXXXXX")
  real_python=$(command -v python3)
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  branch="build-work-011-activate-fail"
  worktree="$FIXTURE_DIR/.worktrees/$branch"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/python3" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == *"pending_cleanup.py" ]] && [ "${2:-}" = "activate" ]; then
  echo "simulated activation interruption" >&2
  exit 1
fi
exec "$PMAI_TEST_REAL_PYTHON" "$@"
SH
  chmod +x "$fake_bin/python3"

  if ! (cd "$FIXTURE_DIR" && PATH="$fake_bin:$PATH" \
    PMAI_TEST_REAL_PYTHON="$real_python" bash "$CANCEL_WORK" "$work_dir") \
    >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "a persisted prepared record should keep cancel successful"
    cat /tmp/err.$$ >&2
  elif [ -f "$work_dir/.work-meta.json" ]; then
    _fail "cancel state was not committed before the simulated interruption"
  elif ! python3 - "$queue" <<'PY'
import json, re, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["phase"] == "prepared", entries
assert entries[0]["activation"] == "main_meta_absent", entries
assert re.fullmatch(r"[0-9a-f]{32}", entries[0]["transaction_id"]), entries
PY
  then
    _fail "activation interruption did not retain the prepared recovery record"
  elif ! (cd "$FIXTURE_DIR" && bash "$CLEANUP_PENDING") \
    >/tmp/cleanup.$$ 2>/tmp/cleanup.err.$$; then
    _fail "main cleanup did not auto-promote the committed cancel"
    cat /tmp/cleanup.$$ /tmp/cleanup.err.$$ >&2
  elif [ -d "$worktree" ] \
    || git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$branch" \
    || [ -f "$queue" ]; then
    _fail "recovered cancel cleanup left its worktree, branch, or queue entry"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$ /tmp/cleanup.$$ /tmp/cleanup.err.$$
  rm -rf -- "$fake_bin"
  fixture_teardown
}

test_cancel_supports_master_only_repository() {
  start_test "cancel records and cleans against master in a master-only repository"
  fixture_setup
  work_dir=$(_setup_module_on_main "work-012" "master-only" 3)
  local branch queue worktree
  branch="build-work-012-master-only"
  queue="$FIXTURE_DIR/.runs/pending-cleanup.json"
  worktree="$FIXTURE_DIR/.worktrees/$branch"
  git -C "$FIXTURE_DIR" branch -m main master

  if ! (cd "$FIXTURE_DIR" && bash "$CANCEL_WORK" "$work_dir") \
    >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel failed in a master-only repository"
    cat /tmp/err.$$ >&2
  elif [ -f "$work_dir/.work-meta.json" ]; then
    _fail "cancel did not commit the state removal on master"
  elif ! python3 - "$queue" <<'PY'
import json, re, sys
entries = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(entries) == 1, entries
assert entries[0]["phase"] == "active", entries
assert entries[0]["integration_ref"] == "refs/heads/master", entries
assert re.fullmatch(r"[0-9a-f]{32}", entries[0]["transaction_id"]), entries
PY
  then
    _fail "cancel did not bind its exact master integration ref and transaction"
  elif ! git -C "$FIXTURE_DIR" log master --oneline | \
    grep "cancel: work-012" >/dev/null; then
    _fail "cancel commit was not written to master"
  elif ! (cd "$FIXTURE_DIR" && bash "$CLEANUP_PENDING") \
    >/tmp/cleanup.$$ 2>/tmp/cleanup.err.$$; then
    _fail "master-bound cleanup did not complete"
    cat /tmp/cleanup.$$ /tmp/cleanup.err.$$ >&2
  elif [ -d "$worktree" ] \
    || git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$branch" \
    || [ -f "$queue" ]; then
    _fail "master-bound cancel left its worktree, branch, or queue entry"
  else
    pass_test
  fi

  rm -f /tmp/out.$$ /tmp/err.$$ /tmp/cleanup.$$ /tmp/cleanup.err.$$
  fixture_teardown
}

test_cancel_rejects_main_mode_without_side_effects() {
  start_test "cancel rejects main mode before changing main or queuing cleanup"
  fixture_setup
  local work_dir implementation before_head before_branch before_meta before_implementation after_head
  cd "$FIXTURE_DIR"
  work_dir=$(fixture_create_main_work "work-013" "main-mode" 3)
  implementation="$FIXTURE_DIR/main-implementation.txt"
  printf 'main implementation must remain\n' > "$implementation"
  git -C "$FIXTURE_DIR" add -- "main-implementation.txt"
  git -C "$FIXTURE_DIR" commit -q -m "add main implementation"
  git -C "$FIXTURE_DIR" switch -q -c cancel-main-guard-caller

  before_head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  before_branch=$(git -C "$FIXTURE_DIR" branch --show-current)
  before_meta=$(git hash-object "$work_dir/.work-meta.json")
  before_implementation=$(git hash-object "$implementation")

  if (cd "$FIXTURE_DIR" && bash "$CANCEL_WORK" "$work_dir") \
    >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "cancel should reject build.mode=main"
  elif ! grep -q "replan-work.py" /tmp/err.$$ \
    || ! grep -qE "proposal.*design|design.*proposal" /tmp/err.$$; then
    _fail "main-mode refusal should route through replan-work.py to proposal/design"
    cat /tmp/err.$$ >&2
  else
    after_head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
    if [ "$before_head" != "$after_head" ]; then
      _fail "main-mode refusal changed HEAD"
    elif [ "$before_branch" != "$(git -C "$FIXTURE_DIR" branch --show-current)" ]; then
      _fail "main-mode refusal checked out another branch"
    elif [ ! -f "$work_dir/.work-meta.json" ] \
      || [ "$before_meta" != "$(git hash-object "$work_dir/.work-meta.json")" ]; then
      _fail "main-mode refusal changed or removed .work-meta.json"
    elif [ ! -f "$implementation" ] \
      || [ "$before_implementation" != "$(git hash-object "$implementation")" ]; then
      _fail "main-mode refusal changed or removed the implementation"
    elif [ -f "$FIXTURE_DIR/.runs/pending-cleanup.json" ]; then
      _fail "main-mode refusal queued cleanup"
    else
      pass_test
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  cd "$FRAMEWORK_ROOT"
  fixture_teardown
}

# ---------------------------------------------------------------
# Run all
# ---------------------------------------------------------------

test_cancel_happy_path
test_cancel_receipt_only_reports_background_queue
test_cancel_does_not_merge_to_main
test_cancel_clears_module_meta
test_cancel_is_idempotent_after_partial_cleanup
test_cancel_rerun_on_already_cleared_does_not_error
test_cancel_rejects_dirty_main
test_cancel_rejects_unconfirmed_module_changes
test_cancel_restores_meta_when_commit_fails
test_cancel_prepare_failure_happens_before_state_commit
test_cancel_activation_failure_recovers_from_main_truth
test_cancel_supports_master_only_repository
test_cancel_rejects_main_mode_without_side_effects

report_results "cancel-work"
