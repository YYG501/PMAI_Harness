#!/usr/bin/env bash
# I-DC1 三道防线回归测试。
#
# 覆盖：
#   1. scripts/_lib/dirty-check.sh 的 list_doc_dirty / auto_commit_docs 函数
#   2. scripts/create-task-worktree.sh 的 pre-fork dirty gate（dirty 时 auto-commit + warn）
#   3. scripts/req-transition.py 的 pre-transition gate（forward 时 auto-commit / rollback 不触发）
#
# 事故背景：2026-05-09 task-005（ExampleConsumerApp）三个状态变更弹窗文案偏差，
# 因 task-spec 多轮 revise 全停在 working tree 没 commit，task-confirm fork 拿到 v1。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

DIRTY_CHECK_LIB="$FRAMEWORK_ROOT/scripts/_lib/dirty-check.sh"
CREATE_TASK_WT="$FRAMEWORK_ROOT/scripts/create-task-worktree.sh"
REQ_TRANSITION="$FRAMEWORK_ROOT/scripts/req-transition.py"

# ── 1. dirty-check.sh 函数行为 ───────────────────────────────

test_list_doc_dirty_clean() {
  start_test "list_doc_dirty: clean worktree → rc=0 + 空输出"
  fixture_setup
  local out rc
  out=$( bash -c "
    source '$DIRTY_CHECK_LIB'
    list_doc_dirty '$FIXTURE_DIR'
  " 2>&1 )
  rc=$?
  if [ "$rc" != "0" ] || [ -n "$out" ]; then
    _fail "expected rc=0+空，got rc=$rc out='$out'"
    fixture_teardown
    return
  fi
  fixture_teardown
  pass_test
}

test_list_doc_dirty_dirty() {
  start_test "list_doc_dirty: dirty → rc=1 + 列出文件"
  fixture_setup
  echo "untracked" > "$FIXTURE_DIR/x.md"
  echo "modified" >> "$FIXTURE_DIR/CLAUDE.md"
  local out rc
  out=$( bash -c "
    source '$DIRTY_CHECK_LIB'
    list_doc_dirty '$FIXTURE_DIR'
  " )
  rc=$?
  if [ "$rc" != "1" ]; then
    _fail "expected rc=1, got $rc"
    fixture_teardown
    return
  fi
  echo "$out" | grep -q x.md || { _fail "missing x.md in output"; fixture_teardown; return; }
  echo "$out" | grep -q CLAUDE.md || { _fail "missing CLAUDE.md in output"; fixture_teardown; return; }
  fixture_teardown
  pass_test
}

test_list_doc_dirty_pathspec_scope() {
  start_test "list_doc_dirty: pathspec 收窄"
  fixture_setup
  echo "in scope" > "$FIXTURE_DIR/in.md"
  echo "out of scope" > "$FIXTURE_DIR/out.md"
  local out
  out=$( bash -c "
    source '$DIRTY_CHECK_LIB'
    list_doc_dirty '$FIXTURE_DIR' 'in.md'
  " )
  if ! echo "$out" | grep -q in.md; then _fail "missing in.md"; fixture_teardown; return; fi
  if echo "$out" | grep -q out.md; then _fail "out.md leaked across pathspec"; fixture_teardown; return; fi
  fixture_teardown
  pass_test
}

test_auto_commit_docs_creates_commit() {
  start_test "auto_commit_docs: dirty → 创建 commit"
  fixture_setup
  echo "new content" > "$FIXTURE_DIR/doc.md"
  local before_head
  before_head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  bash -c "
    source '$DIRTY_CHECK_LIB'
    auto_commit_docs '$FIXTURE_DIR' 'test: seal doc' 'doc.md'
  " >/dev/null 2>&1
  local rc=$?
  local after_head
  after_head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  if [ "$rc" != "0" ]; then _fail "rc=$rc"; fixture_teardown; return; fi
  if [ "$before_head" = "$after_head" ]; then _fail "HEAD 未推进"; fixture_teardown; return; fi
  local last_msg
  last_msg=$(git -C "$FIXTURE_DIR" log -1 --pretty=%s)
  assert_equal "test: seal doc" "$last_msg" "commit message"
  fixture_teardown
  pass_test
}

test_auto_commit_docs_noop_when_clean() {
  start_test "auto_commit_docs: clean → 静默 noop"
  fixture_setup
  local before_head
  before_head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  bash -c "
    source '$DIRTY_CHECK_LIB'
    auto_commit_docs '$FIXTURE_DIR' 'should noop' 'CLAUDE.md'
  " >/dev/null 2>&1
  local rc=$?
  local after_head
  after_head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)
  if [ "$rc" != "0" ]; then _fail "rc=$rc"; fixture_teardown; return; fi
  if [ "$before_head" != "$after_head" ]; then _fail "noop 不应推进 HEAD"; fixture_teardown; return; fi
  fixture_teardown
  pass_test
}

test_auto_commit_docs_only_pathspec_scope() {
  start_test "auto_commit_docs: pathspec 严格隔离"
  fixture_setup
  echo "in scope" > "$FIXTURE_DIR/in.md"
  echo "out of scope" > "$FIXTURE_DIR/out.md"
  bash -c "
    source '$DIRTY_CHECK_LIB'
    auto_commit_docs '$FIXTURE_DIR' 'commit only in.md' 'in.md'
  " >/dev/null 2>&1
  local last_files
  last_files=$(git -C "$FIXTURE_DIR" show --name-only --pretty=format: HEAD | tr '\n' ' ')
  echo "$last_files" | grep -q 'in.md' || { _fail "in.md 缺在 commit"; fixture_teardown; return; }
  if echo "$last_files" | grep -q 'out.md'; then _fail "out.md 越界"; fixture_teardown; return; fi
  if ! [ -f "$FIXTURE_DIR/out.md" ]; then _fail "out.md 被删了"; fixture_teardown; return; fi
  local untracked
  untracked=$(git -C "$FIXTURE_DIR" ls-files --others --exclude-standard | tr '\n' ' ')
  echo "$untracked" | grep -q 'out.md' || { _fail "out.md 应保持 untracked"; fixture_teardown; return; }
  fixture_teardown
  pass_test
}

# ── 2. create-task-worktree.sh pre-fork gate ─────────────────

test_create_task_worktree_seals_dirty_task_md() {
  start_test "create-task-worktree: dirty task md auto-commit + fork"
  fixture_setup
  local req_dir
  req_dir=$(fixture_create_req "req-001" "test" 5)
  local req_branch="req-001-test"
  local req_wt="$FIXTURE_DIR/.worktrees/$req_branch"

  local task_file="$req_dir/tasks/task-001-foo.md"
  local eng_file="$req_dir/tasks/task-001-foo.engineering.md"
  cat > "$task_file" <<'EOF'
# Task 001 v1

**状态：** 待执行
**审查工具：** /qa
**分支：** task-001-foo
**worktree：**
**开发服务器：**

## 启动前必读
- docs/CONTEXT.md

## 任务描述
v1 文案

## 执行范围
- 新建: x.txt

## 验收标准
- [ ] ok

## 依赖
无
EOF
  cat > "$eng_file" <<'EOF'
<!-- synced_pm_view_hash: aaaaaaaaaaaa -->
# task-001 工程合同 v1

## §1 执行者
**executor：** claude-code
EOF
  ( cd "$req_wt" && git add -A && git commit -q -m "task-001 first-gen" )

  # 模拟 task-spec revise 改 working tree 不 commit
  cat > "$task_file" <<'EOF'
# Task 001 v3 (PM 已修订)

**状态：** 待执行
**审查工具：** /qa
**分支：** task-001-foo
**worktree：**
**开发服务器：**

## 启动前必读
- docs/CONTEXT.md

## 任务描述
v3 终态文案 (修订后)

## 执行范围
- 新建: x.txt

## 验收标准
- [ ] ok

## 依赖
无
EOF

  local out rc
  out=$( cd "$req_wt" && bash "$CREATE_TASK_WT" "$task_file" "$req_branch" 2>&1 )
  rc=$?
  if [ "$rc" != "0" ]; then _fail "create-task-worktree rc=$rc, out=$out"; fixture_teardown; return; fi
  echo "$out" | grep -q "I-DC1 pre-fork gate" || { _fail "缺少 I-DC1 警告"; echo "$out"; fixture_teardown; return; }

  # task 分支应该有 v3 内容
  local task_wt="$FIXTURE_DIR/.worktrees/task-task-001-foo"
  if [ -d "$task_wt" ]; then
    # v4.5 fork 后 task md 在 task 分支保留（未来从 req 分支删）
    # 在 task 分支 HEAD 找 task md
    local task_branch="task-task-001-foo"
    local task_md_at_fork
    task_md_at_fork=$(git -C "$FIXTURE_DIR" show "$task_branch:requirements/active/$req_branch/tasks/task-001-foo.md" 2>/dev/null)
    if ! echo "$task_md_at_fork" | grep -q "v3 终态文案"; then
      _fail "task 分支 fork 内容应含 v3 终态文案，实际：$(echo "$task_md_at_fork" | head -5)"
      fixture_teardown
      return
    fi
  fi

  fixture_teardown
  pass_test
}

# ── 3. req-transition.py pre-transition gate ─────────────────

test_req_transition_forward_auto_commits_dirty() {
  start_test "req-transition forward: dirty → auto-commit"
  fixture_setup
  local req_dir
  req_dir=$(fixture_create_req "req-002" "trans" 1)
  local req_branch="req-002-trans"
  local req_wt="$FIXTURE_DIR/.worktrees/$req_branch"

  echo "PM 改的 brief 内容" >> "$req_dir/brief.md"
  echo "# Analysis" > "$req_dir/analysis.md"

  local out rc
  out=$( cd "$req_wt" && python3 "$REQ_TRANSITION" "$req_dir" --to 2 2>&1 )
  rc=$?
  if [ "$rc" != "0" ]; then _fail "transition rc=$rc, out=$out"; fixture_teardown; return; fi
  echo "$out" | grep -q "I-DC1 pre-transition gate" || { _fail "缺少 I-DC1 警告"; fixture_teardown; return; }

  # gate 跑在 save_meta 之前 → brief / analysis 应已 commit；
  # .req-meta.json 是 transition 自身后续写的，不在 gate 范围（一直如此，由 close 流程兜底）。
  local docs_dirty
  docs_dirty=$( git -C "$req_wt" status --porcelain -- "$req_dir/brief.md" "$req_dir/analysis.md" 2>/dev/null )
  if [ -n "$docs_dirty" ]; then _fail "PM 文档未落盘: $docs_dirty"; fixture_teardown; return; fi

  fixture_teardown
  pass_test
}

test_req_transition_rollback_skips_gate() {
  start_test "req-transition rollback: 不触发 gate"
  fixture_setup
  local req_dir
  req_dir=$(fixture_create_req "req-003" "rb" 3)
  local req_branch="req-003-rb"
  local req_wt="$FIXTURE_DIR/.worktrees/$req_branch"

  echo "## dirty stuff" >> "$req_dir/brief.md"

  local out rc
  out=$( cd "$req_wt" && python3 "$REQ_TRANSITION" "$req_dir" --to 2 --rollback 2>&1 )
  rc=$?
  if [ "$rc" != "0" ]; then _fail "rollback rc=$rc, out=$out"; fixture_teardown; return; fi
  if echo "$out" | grep -q "I-DC1 pre-transition gate"; then
    _fail "rollback 不应触发 gate"
    fixture_teardown
    return
  fi

  local dirty
  dirty=$( git -C "$req_wt" status --porcelain -- "$req_dir/brief.md" 2>/dev/null )
  if [ -z "$dirty" ]; then _fail "rollback 不应自动 commit"; fixture_teardown; return; fi

  fixture_teardown
  pass_test
}

test_req_transition_forward_clean_noop() {
  start_test "req-transition forward: clean → 静默 noop"
  fixture_setup
  local req_dir
  req_dir=$(fixture_create_req "req-004" "clean" 1)
  local req_branch="req-004-clean"
  local req_wt="$FIXTURE_DIR/.worktrees/$req_branch"

  local out rc
  out=$( cd "$req_wt" && python3 "$REQ_TRANSITION" "$req_dir" --to 2 2>&1 )
  rc=$?
  if [ "$rc" != "0" ]; then _fail "rc=$rc, out=$out"; fixture_teardown; return; fi
  if echo "$out" | grep -q "I-DC1 pre-transition gate"; then
    _fail "clean 不应警告"
    fixture_teardown
    return
  fi
  fixture_teardown
  pass_test
}

# ── Run ──────────────────────────────────────────────────────

test_list_doc_dirty_clean
test_list_doc_dirty_dirty
test_list_doc_dirty_pathspec_scope
test_auto_commit_docs_creates_commit
test_auto_commit_docs_noop_when_clean
test_auto_commit_docs_only_pathspec_scope
test_create_task_worktree_seals_dirty_task_md
test_req_transition_forward_auto_commits_dirty
test_req_transition_rollback_skips_gate
test_req_transition_forward_clean_noop

cd /
report_results "test-pre-dispatch-doc-gate"
