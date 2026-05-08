#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

CLOSE_TASK="$FRAMEWORK_ROOT/scripts/close-task.sh"

# Helper: mark a task as 已完成
# The task file lives inside the req worktree and is tracked on the req branch.
# The modification must be committed — otherwise close-task refuses merge on
# "req worktree has uncommitted changes" (I-CT2 extension from the quick-fix).
_mark_task_done() {
  local task_file="$1"
  sed -i.bak 's|^\*\*状态：\*\*.*|\*\*状态：\*\* 已完成|' "$task_file"
  rm -f "$task_file.bak"

  # Locate enclosing req worktree and commit the status change
  local wt_root="$(dirname "$task_file")"
  while [ "$wt_root" != "/" ] && [ ! -d "$wt_root/.git" ] && [ ! -f "$wt_root/.git" ]; do
    wt_root=$(dirname "$wt_root")
  done
  if [ -n "$wt_root" ] && { [ -d "$wt_root/.git" ] || [ -f "$wt_root/.git" ]; }; then
    (
      cd "$wt_root"
      git add -A 2>/dev/null
      git commit -q -m "mark task done" 2>/dev/null || true
    )
  fi
}

# Helper: clear 文档偏差 section (replace "无偏差" default)
_set_doc_diff_empty() {
  local task_file="$1"
  # "无偏差" placeholder kept -- script treats as OK
  :
}

# Helper: inject real 文档偏差 content (should trigger rejection)
_inject_doc_diff() {
  local task_file="$1"
  # Replace '无偏差' line with real content
  sed -i.bak 's|^无偏差$|docs/modules/foo.md 写的是 A，实际实现 B|' "$task_file"
  rm -f "$task_file.bak"
}

_mock_skip_doc_update_invocation() {
  local task_file="$1"
  local reason="${2:-}"
  if [ -z "$reason" ]; then
    echo 'Error: --skip-doc-update requires a reason. Usage: /close-task --skip-doc-update "<reason>"' >&2
    return 2
  fi

  local stamp="2026-04-25T20:48:48+08:00"
  local tmp="${task_file}.tmp"
  awk -v reason="$reason" -v stamp="$stamp" '
    /^## 文档偏差/ && !done {
      print
      print "<!-- SKIP_DOC_UPDATE: reason=\"" reason "\" created_at=\"" stamp "\" cleanup_status=\"pending\" -->"
      print ""
      print "## 人工 Cleanup TODO（A1 决议，doc-update 被 skip）"
      print "- [ ] 手动运行 /doc-update --task <task-id> 沉淀功能清单进 docs/modules/<module>.md"
      print "- [ ] cleanup 完成后，把上方 SKIP_DOC_UPDATE marker 的 cleanup_status 从 \"pending\" 改为 \"done\""
      print "- [ ] 重跑 /req-stage-gate 验证半 close 解除"
      done=1
      next
    }
    { print }
  ' "$task_file" > "$tmp"
  mv "$tmp" "$task_file"
  echo "task-001 已半 close（doc-update 被 skip）。需要人工 cleanup TODO 完成后才能推 stage 6→7。请运行 /doc-update 手动沉淀该 task 的功能清单。"
  return 0
}

_mock_autochain_prompt() {
  local req_dir="$1"
  local answer="${2:-}"
  local plan="$req_dir/task-plan.md"
  local id title module file status

  while IFS='|' read -r _ id title module _; do
    id=$(echo "$id" | xargs)
    title=$(echo "$title" | xargs)
    module=$(echo "$module" | xargs)
    [[ "$id" =~ ^task-[0-9]{3}$ ]] || continue
    file=$(find "$req_dir/tasks" -maxdepth 1 -name "$id-*.md" -print | head -1)
    if [ -z "$file" ]; then
      echo "下一个 task 是 ${id}: ${title}（所属模块: [${module}]）"
      echo "继续吗？(Y/n)"
      [ "$answer" = "n" ] && echo "已停止 stage 6 子循环；可手动运行 /task-spec <task-id> 继续"
      return 0
    fi
    status=$(grep -m1 '^\*\*状态：\*\*' "$file" | sed 's/.*\*\*状态：\*\* *//')
    if [ "$status" = "待确认" ]; then
      echo "下一个 task 是 ${id}: ${title}（所属模块: [${module}]）"
      echo "继续吗？(Y/n)"
      [ "$answer" = "n" ] && echo "已停止 stage 6 子循环；可手动运行 /task-spec <task-id> 继续"
      return 0
    fi
  done < "$plan"

  echo "stage 6 所有 task 已 close（含半 close）。可运行 /req-stage-gate 推进 stage 7。"
}

_write_autochain_plan() {
  local req_dir="$1"
  cat > "$req_dir/task-plan.md" <<'EOF'
| id | title | 所属模块 | summary |
|----|-------|----------|---------|
| task-001 | 登录 | 账号模块 | 登录 |
| task-002 | 权限提示 | 权限模块 | 权限 |
EOF
}

# =================================================
# I-CT1: task status must be 已完成
# =================================================
test_reject_if_status_not_done() {
  start_test "I-CT1 reject when task status is not 已完成"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "001" "demo" "执行中" "/qa")
  fixture_create_task_worktree "$task" "req-001-test" >/dev/null

  if (cd "$FIXTURE_DIR/.worktrees/req-001-test" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should have rejected when status is 执行中"
  else
    if grep -q "已完成" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing expected message about 已完成"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT2: task branch does not exist → reject
# =================================================
test_reject_if_task_branch_missing() {
  start_test "I-CT2 reject when task branch does not exist"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "003" "nobranch" "待确认" "/qa")
  # Do NOT create worktree/branch for this task
  _mark_task_done "$task"

  if (cd "$FIXTURE_DIR/.worktrees/req-001-test" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when task branch missing"
  else
    if grep -q "分支" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing branch-missing message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT2: req worktree does not exist → reject
# =================================================
test_reject_if_req_worktree_missing() {
  start_test "I-CT2 reject when req worktree is missing"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "004" "noreqwt" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  _mark_task_done "$task"

  # task 文件在 task worktree 里也有副本（经 req 分支 checkout 而来）
  # 同步 mark_done 到 task worktree 的副本，并 commit 到 task 分支
  task_in_wt="$task_wt/requirements/active/req-001-test/tasks/task-004-noreqwt.md"
  sed -i.bak 's|^\*\*状态：\*\*.*|\*\*状态：\*\* 已完成|' "$task_in_wt"
  rm -f "$task_in_wt.bak"
  (cd "$task_wt" && git add -A && git commit -q -m "mark done")

  # Remove the req worktree directory
  git -C "$FIXTURE_DIR" worktree remove "$FIXTURE_DIR/.worktrees/req-001-test" --force 2>/dev/null || \
    rm -rf "$FIXTURE_DIR/.worktrees/req-001-test"

  # req worktree 已删：v4.5 下脚本会先报 "req worktree 不存在"（早于 cwd 校验）
  # 此处用主仓 cwd（req worktree 不存在，无法 cd 到它）
  if (cd "$FIXTURE_DIR" && bash "$CLOSE_TASK" "$task_in_wt") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when req worktree missing"
  else
    if grep -q "req worktree" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing req worktree message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT2: task worktree has uncommitted changes → reject
# =================================================
test_reject_if_task_worktree_dirty() {
  start_test "I-CT2 reject when task worktree has uncommitted changes"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "005" "dirty" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  _mark_task_done "$task"

  # Create uncommitted file in task worktree
  echo "dirty work" > "$task_wt/uncommitted.txt"

  if (cd "$FIXTURE_DIR/.worktrees/req-001-test" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when task worktree is dirty"
  else
    if grep -q "未提交" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing uncommitted-changes message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT3: merge conflict → reject
# =================================================
test_reject_on_merge_conflict() {
  start_test "I-CT3 reject when merge has conflicts"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "006" "conflict" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")

  # Create conflicting file in req worktree
  (
    cd "$FIXTURE_DIR/.worktrees/req-001-test"
    echo "from req side" > shared.txt
    git add shared.txt
    git commit -q -m "req: add shared.txt"
  )

  # Create conflicting file in task worktree (same path, different content)
  (
    cd "$task_wt"
    echo "from task side" > shared.txt
    git add shared.txt
    git commit -q -m "task: add shared.txt"
  )

  _mark_task_done "$task"

  if (cd "$FIXTURE_DIR/.worktrees/req-001-test" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject on merge conflict"
  else
    # Either merge fails or ancestor check fails — either way we exit non-zero
    if grep -qE "(merge|冲突|conflict)" /tmp/err.$$ /tmp/out.$$; then
      pass_test
    else
      _fail "stderr missing merge-conflict hint"
      cat /tmp/err.$$ >&2
      cat /tmp/out.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT6: 文档偏差 not processed → reject
# =================================================
test_reject_if_doc_diff_not_processed() {
  start_test "I-CT6 reject when 文档偏差 section has content"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "007" "docdiff" "待确认" "/qa")
  fixture_create_task_worktree "$task" "req-001-test" >/dev/null

  _mark_task_done "$task"
  _inject_doc_diff "$task"

  if (cd "$FIXTURE_DIR/.worktrees/req-001-test" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject when doc diff present"
  else
    if grep -q "文档偏差" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing doc-diff message"
      cat /tmp/err.$$ >&2
    fi
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# Happy path: full close succeeds; archive committed, branch/worktree deleted
# =================================================
test_happy_path_close_task() {
  start_test "happy path: close-task succeeds end-to-end"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "008" "happy" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  task_stem=$(basename "$task" .md)

  # Make a real commit on task branch so merge has something to do
  (
    cd "$task_wt"
    echo "task output" > output.txt
    git add output.txt
    git commit -q -m "task: add output"
  )

  _mark_task_done "$task"

  # Create fake runtime files to exercise archive path
  mkdir -p "$FIXTURE_DIR/.runs/events"
  echo '{"task":"'"$task_stem"'"}' > "$FIXTURE_DIR/.runs/$task_stem.json"
  # Seed a valid state-machine event stream (I-CT7 + I-CT8)
  fixture_seed_full_event_stream "$task"

  if (cd "$FIXTURE_DIR/.worktrees/req-001-test" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    # v4.5：close-task 跑在 req worktree → 直接删 task worktree + branch（一步关完）。
    # 不再走 .runs/pending-cleanup.json 中转。
    pending_file="$FIXTURE_DIR/.runs/pending-cleanup.json"
    if [ -f "$pending_file" ]; then
      queued_branch=$(python3 -c "import json; entries=json.load(open('$pending_file')); print(next((e['branch'] for e in entries if e['branch']=='$task_stem'), ''))")
      if [ "$queued_branch" = "$task_stem" ]; then
        _fail "pending-cleanup.json should NOT contain branch=$task_stem (v4.5: deleted directly)"
        rm -f /tmp/out.$$ /tmp/err.$$
        fixture_teardown
        return
      fi
    fi

    # Verify task branch + worktree have been deleted (v4.5 一步关完)
    if git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$task_stem"; then
      _fail "task branch should have been deleted (v4.5); still exists"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi
    if [ -d "$FIXTURE_DIR/.worktrees/$task_stem" ]; then
      _fail "task worktree should have been removed (v4.5); still exists"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    # Verify archive file is tracked on req branch (I-CT4)
    req_wt="$FIXTURE_DIR/.worktrees/req-001-test"
    archive_rel="requirements/active/req-001-test/tasks/_archived/$task_stem/$task_stem.json"
    if ! git -C "$req_wt" ls-files --error-unmatch "$archive_rel" >/dev/null 2>&1; then
      _fail "archive file not tracked on req branch: $archive_rel"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    # Verify there's an archive commit in req branch history
    if ! git -C "$req_wt" log --oneline | grep "archive: runtime for $task_stem" >/dev/null; then
      _fail "no archive commit found in req branch log"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    # Verify .runs/ originals cleaned
    if [ -f "$FIXTURE_DIR/.runs/$task_stem.json" ]; then
      _fail ".runs/ original should be cleaned"
      rm -f /tmp/out.$$ /tmp/err.$$
      fixture_teardown
      return
    fi

    pass_test
  else
    _fail "close-task failed on happy path"
    echo "--- stdout ---" >&2
    cat /tmp/out.$$ >&2
    echo "--- stderr ---" >&2
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT7: event stream file must exist (fail-closed)
# =================================================
test_reject_if_event_stream_missing() {
  start_test "I-CT7 reject when .runs/events/<task>.jsonl does not exist"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "101" "noevents" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  (cd "$task_wt" && echo "x" > out.txt && git add -A && git commit -q -m "task: work")
  _mark_task_done "$task"
  # Intentionally do NOT seed events

  if (cd "$FIXTURE_DIR/.worktrees/req-001-test" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should have rejected when event stream missing"
    cat /tmp/err.$$ >&2
  else
    if grep -q "I-CT7" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing I-CT7 marker"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT7: state-machine skipped (regression of 2026-04-22 1-hour event)
# =================================================
test_reject_if_state_machine_skipped() {
  start_test "I-CT7 regression: status forced 已完成 but no status_changed events (2026-04-22 pattern)"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "102" "bypass" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  # Simulate agent writing code WITHOUT ever calling task-transition.py
  (cd "$task_wt" && echo "leaked implementation" > leaked.ts && git add -A && git commit -q -m "seed: bring in task-001~004 code")
  # Agent then manually forces status to 已完成 to try to close-task
  _mark_task_done "$task"
  # Events file only has unrelated noise (no status_changed, no execution_started)
  mkdir -p "$FIXTURE_DIR/.runs/events"
  local task_stem=$(basename "$task" .md)
  echo '{"event":"review_completed","timestamp":"2020-01-01T00:00:00+00:00","task":"'"$task_stem"'","tool":"/qa","result":"pass"}' \
    > "$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  if (cd "$FIXTURE_DIR/.worktrees/req-001-test" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should have rejected when state machine was skipped"
    cat /tmp/err.$$ >&2
  else
    if grep -q "I-CT7" /tmp/err.$$; then
      # Verify merge did NOT happen (task branch still exists, data preserved)
      if git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/${task_stem}"; then
        pass_test
      else
        _fail "task branch was deleted despite audit rejection — data loss!"
      fi
    else
      _fail "stderr missing I-CT7 marker"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT8: commit timestamp predates transition-to-执行中
# =================================================
test_reject_if_commit_predates_execution() {
  start_test "I-CT8 reject when task commit timestamp predates status_changed(→执行中)"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "103" "timetravel" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  local task_stem=$(basename "$task" .md)

  # Commit at test-time (≈ now)
  (cd "$task_wt" && echo "early" > early.ts && git add -A && git commit -q -m "task: early write")
  _mark_task_done "$task"

  # Seed events with transition to 执行中 happening FAR IN THE FUTURE (after our commit)
  # This simulates "code was written before status ever advanced"
  mkdir -p "$FIXTURE_DIR/.runs/events"
  {
    echo "{\"event\":\"status_changed\",\"timestamp\":\"2099-01-01T00:00:00+00:00\",\"task\":\"$task_stem\",\"from\":\"待确认\",\"to\":\"执行中\"}"
    echo "{\"event\":\"execution_started\",\"timestamp\":\"2099-01-01T00:01:00+00:00\",\"task\":\"$task_stem\",\"executor\":\"claude-code\"}"
    echo "{\"event\":\"status_changed\",\"timestamp\":\"2099-01-01T00:20:00+00:00\",\"task\":\"$task_stem\",\"from\":\"执行中\",\"to\":\"已完成\"}"
  } > "$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  if (cd "$FIXTURE_DIR/.worktrees/req-001-test" && bash "$CLOSE_TASK" "$task") >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should have rejected when commit predates transition"
    cat /tmp/err.$$ >&2
  else
    if grep -q "I-CT8" /tmp/err.$$; then
      pass_test
    else
      _fail "stderr missing I-CT8 marker"
      cat /tmp/err.$$ >&2
    fi
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

# =================================================
# I-CT8 A1 hotfix: file-name allowlist exemption for metadata commits
# =================================================
test_ct8_exempts_engineering_md_only_commit() {
  start_test "I-CT8 A1 exempt: commit only modifies engineering.md (executor switch case)"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "104" "exec-switch" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  local task_stem=$(basename "$task" .md)

  # Simulate task-confirm step 3: 改 engineering.md executor 字段并 commit (early commit before state machine moves)
  local eng_file="${task%.md}.engineering.md"
  if [ ! -f "$eng_file" ]; then
    # v1 task fixture 没建 engineering.md，建一个最小可用的
    cat > "$eng_file" <<EOF
# Task ${task_stem} engineering

## 1. 元信息

**executor：** claude-code
**executor_model：**
EOF
  fi
  # Copy the engineering.md into task worktree at correct relative path
  local rel_path=$(echo "$eng_file" | sed -E "s|^${FIXTURE_DIR}/||")
  mkdir -p "$task_wt/$(dirname "$rel_path")"
  cp "$eng_file" "$task_wt/$rel_path"
  (cd "$task_wt" && \
    sed -i.bak 's/\*\*executor：\*\* claude-code/\*\*executor：\*\* codex/' "$rel_path" && \
    rm -f "$rel_path.bak" && \
    git add "$rel_path" && \
    git commit -q -m "${task_stem}: switch executor to codex (per PM at task-confirm)")
  _mark_task_done "$task"

  # Seed events with transition to 执行中 happening AFTER the commit
  # (simulates real task-confirm sequence: meta commit → later *→执行中)
  mkdir -p "$FIXTURE_DIR/.runs/events"
  {
    echo "{\"event\":\"status_changed\",\"timestamp\":\"2099-01-01T00:00:00+00:00\",\"task\":\"$task_stem\",\"from\":\"待确认\",\"to\":\"执行中\"}"
    echo "{\"event\":\"execution_started\",\"timestamp\":\"2099-01-01T00:01:00+00:00\",\"task\":\"$task_stem\",\"executor\":\"codex\"}"
    echo "{\"event\":\"status_changed\",\"timestamp\":\"2099-01-01T00:20:00+00:00\",\"task\":\"$task_stem\",\"from\":\"执行中\",\"to\":\"已完成\"}"
  } > "$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  # Run audit-task-events.py directly (skip full close-task path which has other checks)
  local audit_out
  if audit_out=$(cd "$FIXTURE_DIR" && python3 "$FRAMEWORK_ROOT/scripts/audit-task-events.py" \
        --task-file "$task" \
        --task-branch "$task_stem" \
        --req-branch "req-001-test" 2>&1); then
    pass_test
  else
    _fail "I-CT8 should exempt engineering.md-only commit, but rejected"
    echo "$audit_out" >&2
  fi
  fixture_teardown
}

test_ct8_exempts_task_md_only_commit() {
  start_test "I-CT8 A1 exempt: commit only modifies task md (status field update)"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "105" "status-flip" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  local task_stem=$(basename "$task" .md)

  # Copy task md into worktree and commit a status-field-only change
  local rel_task=$(echo "$task" | sed -E "s|^${FIXTURE_DIR}/||")
  mkdir -p "$task_wt/$(dirname "$rel_task")"
  cp "$task" "$task_wt/$rel_task"
  (cd "$task_wt" && \
    echo "" >> "$rel_task" && \
    git add "$rel_task" && \
    git commit -q -m "${task_stem}: bump task md (metadata)")
  _mark_task_done "$task"

  mkdir -p "$FIXTURE_DIR/.runs/events"
  {
    echo "{\"event\":\"status_changed\",\"timestamp\":\"2099-01-01T00:00:00+00:00\",\"task\":\"$task_stem\",\"from\":\"待确认\",\"to\":\"执行中\"}"
    echo "{\"event\":\"execution_started\",\"timestamp\":\"2099-01-01T00:01:00+00:00\",\"task\":\"$task_stem\",\"executor\":\"claude-code\"}"
    echo "{\"event\":\"status_changed\",\"timestamp\":\"2099-01-01T00:20:00+00:00\",\"task\":\"$task_stem\",\"from\":\"执行中\",\"to\":\"已完成\"}"
  } > "$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  local audit_out
  if audit_out=$(cd "$FIXTURE_DIR" && python3 "$FRAMEWORK_ROOT/scripts/audit-task-events.py" \
        --task-file "$task" \
        --task-branch "$task_stem" \
        --req-branch "req-001-test" 2>&1); then
    pass_test
  else
    _fail "I-CT8 should exempt task md only commit, but rejected"
    echo "$audit_out" >&2
  fi
  fixture_teardown
}

test_ct8_does_not_exempt_mixed_commit() {
  start_test "I-CT8 A1 NOT exempt: commit mixes task md + code file (preserves original intent)"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "106" "mixed" "待确认" "/qa")
  task_wt=$(fixture_create_task_worktree "$task" "req-001-test")
  local task_stem=$(basename "$task" .md)

  # Mixed commit: task md (worktree already has it from req fork) + a non-task source file
  local rel_task="requirements/active/req-001-test/tasks/${task_stem}.md"
  (cd "$task_wt" && \
    echo "trailing change for mixed test" >> "$rel_task" && \
    mkdir -p src && \
    echo "function leak() {}" > src/leak.js && \
    git add "$rel_task" src/leak.js && \
    git commit -q -m "${task_stem}: mixed metadata + code (should not exempt)")
  _mark_task_done "$task"

  mkdir -p "$FIXTURE_DIR/.runs/events"
  {
    echo "{\"event\":\"status_changed\",\"timestamp\":\"2099-01-01T00:00:00+00:00\",\"task\":\"$task_stem\",\"from\":\"待确认\",\"to\":\"执行中\"}"
    echo "{\"event\":\"execution_started\",\"timestamp\":\"2099-01-01T00:01:00+00:00\",\"task\":\"$task_stem\",\"executor\":\"claude-code\"}"
    echo "{\"event\":\"status_changed\",\"timestamp\":\"2099-01-01T00:20:00+00:00\",\"task\":\"$task_stem\",\"from\":\"执行中\",\"to\":\"已完成\"}"
  } > "$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"

  local audit_out
  if audit_out=$(cd "$FIXTURE_DIR" && python3 "$FRAMEWORK_ROOT/scripts/audit-task-events.py" \
        --task-file "$task" \
        --task-branch "$task_stem" \
        --req-branch "req-001-test" 2>&1); then
    _fail "I-CT8 should reject mixed commit, but passed"
    echo "$audit_out" >&2
  elif echo "$audit_out" | grep -q "I-CT8"; then
    pass_test
  else
    _fail "I-CT8 should reject mixed commit with I-CT8 marker"
    echo "$audit_out" >&2
  fi
  fixture_teardown
}

# =================================================
# A1: --skip-doc-update reason is required
# =================================================
test_skip_doc_update_no_reason() {
  start_test "A1 skip-doc-update rejects missing reason"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "201" "skip-no-reason" "已完成" "/qa")

  if _mock_skip_doc_update_invocation "$task" "" >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "should reject --skip-doc-update without reason"
  elif grep -q -- "--skip-doc-update requires a reason" /tmp/err.$$; then
    pass_test
  else
    _fail "stderr missing --skip-doc-update requires a reason"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_skip_doc_update_with_reason() {
  start_test "A1 skip-doc-update with reason exits zero"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "202" "skip-with-reason" "已完成" "/qa")

  if _mock_skip_doc_update_invocation "$task" "doc-update mock failure" >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "--skip-doc-update with reason should exit zero"
    cat /tmp/err.$$ >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_skip_doc_update_marker_written() {
  start_test "A1 skip-doc-update writes marker"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "203" "skip-marker" "已完成" "/qa")
  _mock_skip_doc_update_invocation "$task" "doc-update mock failure" >/tmp/out.$$ 2>/tmp/err.$$

  if grep -q '<!-- SKIP_DOC_UPDATE:' "$task" && grep -q 'cleanup_status="pending"' "$task"; then
    pass_test
  else
    _fail "SKIP_DOC_UPDATE marker missing or not pending"
    cat "$task" >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_skip_doc_update_cleanup_todo_written() {
  start_test "A1 skip-doc-update writes cleanup TODO"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "204" "skip-todo" "已完成" "/qa")
  _mock_skip_doc_update_invocation "$task" "doc-update mock failure" >/tmp/out.$$ 2>/tmp/err.$$

  if grep -q '人工 Cleanup TODO' "$task" \
    && grep -q '手动运行 /doc-update --task <task-id>' "$task" \
    && grep -q 'cleanup_status 从 "pending" 改为 "done"' "$task" \
    && grep -q '重跑 /req-stage-gate 验证半 close 解除' "$task"; then
    pass_test
  else
    _fail "cleanup TODO block incomplete"
    cat "$task" >&2
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_skip_doc_update_marker_grep_pattern() {
  start_test "A1 skip-doc-update marker grep pattern"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "205" "skip-grep" "已完成" "/qa")
  _mock_skip_doc_update_invocation "$task" "doc-update mock failure" >/tmp/out.$$ 2>/tmp/err.$$

  if grep -q '<!-- SKIP_DOC_UPDATE:' "$task" && grep -q 'cleanup_status="pending"' "$task"; then
    pass_test
  else
    _fail "Batch 3 marker grep failed"
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_skip_doc_update_exit_zero() {
  start_test "A1 skip-doc-update half-close exits zero"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "206" "skip-exit-zero" "已完成" "/qa")
  _mock_skip_doc_update_invocation "$task" "doc-update mock failure" >/tmp/out.$$ 2>/tmp/err.$$
  rc=$?

  if [ "$rc" -eq 0 ]; then
    pass_test
  else
    _fail "expected exit 0, got $rc"
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  fixture_teardown
}

test_autochain_has_next_task() {
  start_test "DX RU6 auto-chain prompts next task"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  _write_autochain_plan "$req_dir"
  fixture_create_task "$req_dir" "001" "login" "已完成" "/qa" >/dev/null
  out=$(_mock_autochain_prompt "$req_dir")

  if echo "$out" | grep -q "下一个 task 是"; then
    pass_test
  else
    _fail "auto-chain next-task prompt missing"
    echo "$out" >&2
  fi

  fixture_teardown
}

test_autochain_all_done() {
  start_test "DX RU6 auto-chain all done prompt"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  _write_autochain_plan "$req_dir"
  fixture_create_task "$req_dir" "001" "login" "已完成" "/qa" >/dev/null
  fixture_create_task "$req_dir" "002" "permission" "已完成" "/qa" >/dev/null
  out=$(_mock_autochain_prompt "$req_dir")

  if echo "$out" | grep -q "可运行 /req-stage-gate"; then
    pass_test
  else
    _fail "auto-chain all-done prompt missing"
    echo "$out" >&2
  fi

  fixture_teardown
}

test_autochain_user_n() {
  start_test "DX RU6 auto-chain stops when PM inputs n"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  _write_autochain_plan "$req_dir"
  fixture_create_task "$req_dir" "001" "login" "已完成" "/qa" >/dev/null
  out=$(_mock_autochain_prompt "$req_dir" "n")

  if echo "$out" | grep -q "已停止 stage 6 子循环"; then
    pass_test
  else
    _fail "auto-chain n stop prompt missing"
    echo "$out" >&2
  fi

  fixture_teardown
}

# =================================================
# Run all tests
# =================================================
test_reject_if_status_not_done
test_reject_if_task_branch_missing
test_reject_if_req_worktree_missing
test_reject_if_task_worktree_dirty
test_reject_on_merge_conflict
test_reject_if_doc_diff_not_processed
test_reject_if_event_stream_missing
test_reject_if_state_machine_skipped
test_reject_if_commit_predates_execution
test_ct8_exempts_engineering_md_only_commit
test_ct8_exempts_task_md_only_commit
test_ct8_does_not_exempt_mixed_commit
test_happy_path_close_task
test_skip_doc_update_no_reason
test_skip_doc_update_with_reason
test_skip_doc_update_marker_written
test_skip_doc_update_cleanup_todo_written
test_skip_doc_update_marker_grep_pattern
test_autochain_has_next_task
test_autochain_all_done
test_autochain_user_n
test_skip_doc_update_exit_zero

report_results "close-task"
