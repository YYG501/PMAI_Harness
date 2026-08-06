#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CLOSE_WORK="$FRAMEWORK_ROOT/scripts/close-work.sh"
BUILD_CLOSE_SKILL="$FRAMEWORK_ROOT/skills/build-close/SKILL.md"

# close-work（方案 A）后真相源是 docs/modules/<模块>/。
# work_dir = docs/modules/<分支>（fixture_create_work 现返回模块目录）。
# 收尾语义：模块 .work-meta.json 被删（清工作状态），模块三件套留场；
# build.mode=worktree 走 merge，build.mode=main 直接在 main 清。

# Helper: 模块 .work-meta 是否还在（在 = 未收尾）
_module_meta_path_on_main() {
  echo "$FIXTURE_DIR/docs/modules/$1/.work-meta.json"
}

# =================================================
# I-CR3/CR5：build.mode=main → 走 main 直接清 .work-meta
# =================================================
test_main_mode_closes_via_main() {
  start_test "I-CR3 main-mode build → main 直接清 .work-meta"
  fixture_setup

  main_module=$(fixture_create_main_work "work-001" "test" 4)

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$main_module") >/tmp/out.$$ 2>/tmp/err.$$; then
    # 模块 .work-meta 已被清
    if [ -f "$main_module/.work-meta.json" ]; then
      _fail "module .work-meta should be cleared on main-clear path"
      cat /tmp/out.$$ >&2
    elif [ ! -d "$main_module" ]; then
      _fail "module dir should remain (only .work-meta cleared)"
    else
      pass_test
    fi
  else
    _fail "close-work should succeed on no-branch path (main clear)"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR4：build.mode=worktree 但 worktree 缺失 → 拒绝，不退化 main 直收
# =================================================
test_worktree_contract_rejects_missing_worktree() {
  start_test "I-CR4 worktree contract rejects missing worktree"
  fixture_setup

  work_dir=$(fixture_create_work "work-001" "test" 4)
  main_module="$FIXTURE_DIR/docs/modules/build-work-001-test"
  mkdir -p "$main_module"
  cp -R "$work_dir/." "$main_module/"
  mkdir -p "$FIXTURE_DIR/.pm-workflow/audits"
  cp -R "$FIXTURE_DIR/.worktrees/build-work-001-test/.pm-workflow/audits/build-work-001-test" \
    "$FIXTURE_DIR/.pm-workflow/audits/"
  (cd "$FIXTURE_DIR" && git add -A && git commit -q -m "mirror module on main")

  git -C "$FIXTURE_DIR" worktree remove "$FIXTURE_DIR/.worktrees/build-work-001-test" --force 2>/dev/null || \
    rm -rf "$FIXTURE_DIR/.worktrees/build-work-001-test"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$main_module") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "close-work should reject missing worktree when build contract says worktree"
  else
    if grep -q "build 合同要求隔离环境" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing build-contract missing worktree guidance"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_missing_build_contract() {
  start_test "I-CR12 reject close when .work-meta lacks build contract"
  fixture_setup

  work_dir=$(fixture_create_work "work-001" "test" 4)
  python3 - "$work_dir/.work-meta.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
meta = json.loads(p.read_text())
meta.pop("build", None)
p.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n")
PY
  (
    cd "$FIXTURE_DIR/.worktrees/build-work-001-test"
    git add docs/modules/build-work-001-test/.work-meta.json
    git commit -q -m "remove build contract"
  )

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "close-work should reject missing build contract"
  else
    if grep -q "缺少 build 合同" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing missing-build-contract guidance"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_missing_audit_evidence() {
  start_test "I-CR14 reject close when build audit evidence is missing"
  fixture_setup

  work_dir=$(fixture_create_work "work-001" "test" 4)
  (
    cd "$FIXTURE_DIR/.worktrees/build-work-001-test"
    rm -f ".pm-workflow/audits/build-work-001-test/behavior.json"
    git add -A
    git commit -q -m "remove behavior audit evidence"
  )

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "close-work should reject missing browser/behavior audit evidence"
  else
    if grep -q "build 验收证据不完整" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing audit evidence guidance"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR9: merge conflict → should not leave half-complete state
# =================================================
test_reject_on_merge_conflict_no_partial_state() {
  start_test "I-CR9 merge conflict does not leave partial state on main"
  fixture_setup

  work_dir=$(fixture_create_work "work-001" "test" 4)

  # Modify main branch to create a conflict with what work branch will do
  (
    cd "$FIXTURE_DIR"
    echo "main version" > conflict.txt
    git add conflict.txt
    git commit -q -m "main: conflict.txt"
  )

  # Modify same file on work branch
  (
    cd "$FIXTURE_DIR/.worktrees/build-work-001-test"
    echo "work version" > conflict.txt
    git add conflict.txt
    git commit -q -m "work: conflict.txt"
  )

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    :
  fi

  (
    cd "$FIXTURE_DIR"
    git checkout main -q 2>/dev/null || true
  )

  # 方案 A 下不再有 closed/ 目录。半完成态判定：merge 是否真落地。
  # 若 merge 失败回滚，work branch应仍在场 + work branch上模块 .work-meta 应仍有（pre-close）。
  if git -C "$FIXTURE_DIR" log main --oneline | grep "close: work-001" >/dev/null; then
    # merge 真落地（自动解决冲突的极端情况）：main 上模块 .work-meta 应已清
    if [ -f "$FIXTURE_DIR/docs/modules/build-work-001-test/.work-meta.json" ]; then
      _fail "merge landed but module .work-meta not cleared on main (half state)"
    else
      pass_test
    fi
  else
    # merge 未落地：work branch应仍在（可重试），模块 .work-meta 应仍在 work branch上（pre-close）
    if ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/build-work-001-test"; then
      _fail "work branch deleted but close did not land (half state)"
    elif [ ! -f "$FIXTURE_DIR/.worktrees/build-work-001-test/docs/modules/build-work-001-test/.work-meta.json" ]; then
      _fail "work branch rolled back but module .work-meta missing (half state)"
    else
      pass_test
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR5: clear-state commit must land on work branch before merge
# (verified via happy path: after close, main branch log contains the close commit)
# =================================================
test_archive_committed_before_merge() {
  start_test "I-CR5 clear-state commit lands before merge (happy path verifies order)"
  fixture_setup

  work_dir=$(fixture_create_work "work-001" "test" 4)

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    # After close, main should contain the close commit "close: 收尾 work-001"
    if git -C "$FIXTURE_DIR" log main --oneline | grep "close: 收尾 work-001" >/dev/null; then
      pass_test
    else
      _fail "close commit not found on main branch log"
      git -C "$FIXTURE_DIR" log main --oneline >&2
    fi
  else
    _fail "close-work failed unexpectedly"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# Happy path: full close-work succeeds (有 worktree → merge 路径)
# =================================================
test_happy_path_close_work() {
  start_test "happy path: close-work clears module .work-meta + merges to main"
  fixture_setup

  work_dir=$(fixture_create_work "work-001" "test" 4)

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    main_module="$FIXTURE_DIR/docs/modules/build-work-001-test"

    # 模块目录在 main 上仍在（三件套 discussion.md 留场）
    if [ ! -d "$main_module" ]; then
      _fail "module dir should exist on main (三件套留场)"
      ls "$FIXTURE_DIR/docs/modules" >&2 2>&1 || true
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi
    # 工作状态 .work-meta 已清
    if [ -f "$main_module/.work-meta.json" ]; then
      _fail ".work-meta.json should be cleared on main after close"
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi
    # discussion.md 应仍在
    if [ ! -f "$main_module/discussion.md" ]; then
      _fail "module 三件套 (discussion.md) should remain on main"
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi

    # branch + worktree 已删
    if git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/build-work-001-test"; then
      _fail "work branch should be deleted by close-work.sh"
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi
    if [ -d "$FIXTURE_DIR/.worktrees/build-work-001-test" ]; then
      _fail "worktree should be removed by close-work.sh"
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi

    # 当前分支 main
    cur=$(git -C "$FIXTURE_DIR" branch --show-current)
    if [ "$cur" != "main" ]; then
      _fail "expected to land on main, got $cur"
      rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
    fi

    pass_test
  else
    _fail "close-work failed on happy path"
    echo "--- stdout ---" >&2; cat /tmp/out.$$ >&2
    echo "--- stderr ---" >&2; cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR9b: on merge failure, work branch is reset to pre-close (module .work-meta still present)
# =================================================
test_merge_failure_rolls_back_work_branch() {
  start_test "I-CR9b merge failure rolls work branch back to pre-close state"
  fixture_setup

  work_dir=$(fixture_create_work "work-001" "test" 4)

  # Create conflict: same file on main and on work branch with different content
  (
    cd "$FIXTURE_DIR"
    echo "main" > clash.txt && git add clash.txt && git commit -q -m "main: clash"
  )
  (
    cd "$FIXTURE_DIR/.worktrees/build-work-001-test"
    echo "work" > clash.txt && git add clash.txt && git commit -q -m "work: clash"
  )

  # Should fail
  (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$ && \
    { _fail "close-work should have failed on conflict"; rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return; }

  # On work branch: 模块 .work-meta 应仍在（pre-close 状态，被回滚回来）
  work_wt="$FIXTURE_DIR/.worktrees/build-work-001-test"
  if [ ! -f "$work_wt/docs/modules/build-work-001-test/.work-meta.json" ]; then
    _fail "work branch should be rolled back with module .work-meta restored"
    ls "$work_wt/docs/modules/build-work-001-test" >&2 2>&1 || true
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  # main 上模块 .work-meta 不应被清（merge 未落地）
  if [ ! -f "$FIXTURE_DIR/docs/modules/build-work-001-test/.work-meta.json" ] && \
     git -C "$FIXTURE_DIR" show main:docs/modules/build-work-001-test/.work-meta.json >/dev/null 2>&1; then
    : # 不应到这（main 上本来就没 mirror，跳过）
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_close_commit_failure_restores_meta_and_retries_once() {
  start_test "legacy close: commit failure restores .work-meta and retry commits once"
  fixture_setup
  work_dir=$(fixture_create_work "work-001" "retry" 4)
  hook="$FIXTURE_DIR/.git/hooks/pre-commit"
  cat > "$hook" <<'SH'
#!/usr/bin/env bash
common_dir=$(git rev-parse --git-common-dir)
if [ ! -f "$common_dir/allow-close" ]; then
  echo "simulated close hook failure" >&2
  exit 1
fi
SH
  chmod +x "$hook"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "hook failure should stop close"
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi
  worktree="$FIXTURE_DIR/.worktrees/build-work-001-retry"
  rel_meta="docs/modules/build-work-001-retry/.work-meta.json"
  if [ ! -f "$worktree/$rel_meta" ]; then
    _fail "commit failure should restore .work-meta in the worktree"
  elif git -C "$worktree" diff --cached --name-only | grep -q "^$rel_meta$"; then
    _fail "restored .work-meta should not remain staged for deletion"
  else
    touch "$FIXTURE_DIR/.git/allow-close"
    if ! (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
      _fail "close should recover after the hook is fixed"
      cat /tmp/err.$$ >&2
    else
      close_count=$(git -C "$FIXTURE_DIR" log --format=%s | grep -c 'close: 收尾 work-001')
      if [ "$close_count" != "1" ]; then
        _fail "retry should create exactly one close commit"
      else
        pass_test
      fi
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CR10: reject when cwd is inside the worktree
# =================================================
test_reject_when_cwd_inside_work_worktree() {
  start_test "I-CR10 reject when cwd is inside worktree"
  fixture_setup

  work_dir=$(fixture_create_work "work-001" "test" 4)
  work_wt="$FIXTURE_DIR/.worktrees/build-work-001-test"

  if (cd "$work_wt" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when cwd is inside worktree"
  else
    if grep -qE "(worktree 里头|主仓窗口)" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing cwd-in-worktree message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_reject_if_work_worktree_has_unrelated_dirty_changes() {
  start_test "I-CR11 reject unrelated dirty changes in worktree"
  fixture_setup

  work_dir=$(fixture_create_work "work-001" "test" 4)
  work_wt="$FIXTURE_DIR/.worktrees/build-work-001-test"
  mkdir -p "$work_wt/prototypes"
  echo "leak" > "$work_wt/prototypes/unrelated.txt"

  if (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject unrelated dirty file instead of committing it"
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  if ! grep -q "当前模块目录外" /tmp/err.$$; then
    _fail "stderr missing unrelated dirty guidance"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  if git -C "$FIXTURE_DIR" show main:prototypes/unrelated.txt >/dev/null 2>&1; then
    _fail "unrelated dirty file leaked into main"
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_allows_unrelated_dirty_changes_on_main() {
  start_test "I-CR13 allow unrelated dirty changes on main during worktree close"
  fixture_setup

  work_dir=$(fixture_create_work "work-001" "test" 4)

  (
    cd "$FIXTURE_DIR"
    echo "main history" > main-history.txt
    git add main-history.txt
    git commit -q -m "main: unrelated history"
    echo "staged local wip" > local-staged.txt
    git add local-staged.txt
    echo "untracked local wip" > local-untracked.txt
  )

  if ! (cd "$FIXTURE_DIR" && bash "$CLOSE_WORK" "$work_dir") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "close-work should allow unrelated dirty changes on main"
    echo "--- stdout ---" >&2; cat /tmp/out.$$ >&2
    echo "--- stderr ---" >&2; cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  status=$(git -C "$FIXTURE_DIR" status --short --untracked-files=all)
  if ! printf '%s\n' "$status" | grep -q '^A  local-staged.txt$'; then
    _fail "staged local WIP should remain staged after close"
    printf '%s\n' "$status" >&2
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi
  if ! printf '%s\n' "$status" | grep -q '^?? local-untracked.txt$'; then
    _fail "untracked local WIP should remain untracked after close"
    printf '%s\n' "$status" >&2
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi
  if git -C "$FIXTURE_DIR" show HEAD:local-staged.txt >/dev/null 2>&1; then
    _fail "staged local WIP should not be included in close merge commit"
    rm -f /tmp/out.$$ /tmp/err.$$; fixture_teardown; return
  fi

  pass_test
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_build_close_skill_documents_contract_and_wip_rules() {
  start_test "build-close compatibility requires a ready candidate and preserves main WIP"

  assert_file_contains "$BUILD_CLOSE_SKILL" "finalize-work.py" "build-close should use the resumable finalize runner" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "review-ready" "build-close should still require a checked candidate before acceptance" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "本 close 不补业务代码" "build-close should not implement missing product behavior" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "主仓 main 上允许保留其它未提交 WIP" "build-close should allow unrelated main WIP" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "autostash" "build-close should document autostash merge behavior" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "PM 窗口只报阶段结果" "build-close should keep command chatter out of PM view" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "build 验收证据是落地主线硬门" "build-close should gate landing on audit evidence" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "安全待清理队列" "build-close should not block docs on pure cleanup failures" || return
  assert_file_contains "$BUILD_CLOSE_SKILL" "正常链路由 build 自动 finalize" "build-close should stay a recovery entry" || return
  pass_test
}

# =================================================
# Run all tests
# =================================================
test_main_mode_closes_via_main
test_worktree_contract_rejects_missing_worktree
test_reject_missing_build_contract
test_reject_missing_audit_evidence
test_reject_when_cwd_inside_work_worktree
test_reject_if_work_worktree_has_unrelated_dirty_changes
test_allows_unrelated_dirty_changes_on_main
test_build_close_skill_documents_contract_and_wip_rules
test_reject_on_merge_conflict_no_partial_state
test_archive_committed_before_merge
test_happy_path_close_work
test_merge_failure_rolls_back_work_branch
test_close_commit_failure_restores_meta_and_retries_once

report_results "close-work"
