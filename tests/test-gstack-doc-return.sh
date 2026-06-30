#!/usr/bin/env bash
# Static and behavioral tests for gstack document side-path return into PMAI docs map.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-engineering-docs-index.py"

test_templates_expose_engineering_docs_map() {
  start_test "gstack doc return: 消费仓模板暴露 docs/engineering"

  assert_file_contains "$REPO_ROOT/templates/CLAUDE.md.tmpl" "gstack 旁路文档接回" "CLAUDE template should define gstack doc return" || return
  assert_file_contains "$REPO_ROOT/templates/CLAUDE.md.tmpl" "docs/engineering/" "CLAUDE template should name engineering destination" || return
  assert_file_contains "$REPO_ROOT/templates/CLAUDE.md.tmpl" "docs/engineering/INDEX.md" "CLAUDE template should require engineering index" || return
  assert_file_contains "$REPO_ROOT/templates/AGENTS.md.tmpl" "gstack Side Paths" "AGENTS template should expose Codex fallback" || return
  assert_file_contains "$REPO_ROOT/templates/AGENTS.md.tmpl" "docs/engineering/INDEX.md" "AGENTS template should require engineering index" || return
  assert_file_contains "$REPO_ROOT/templates/文档地图.md" "工程文档" "document map should include engineering docs" || return
  assert_file_contains "$REPO_ROOT/templates/docs-INDEX.md.tmpl" "engineering/" "docs index should list engineering directory" || return
  pass_test
}

test_init_project_installs_engineering_index() {
  start_test "gstack doc return: init-project 默认创建 engineering 索引"

  assert_file_exists "$REPO_ROOT/templates/engineering-INDEX.md.tmpl" "engineering index template should exist" || return
  assert_file_contains "$REPO_ROOT/scripts/init-project.sh" "engineering-INDEX.md" "init should map engineering index template" || return
  assert_file_contains "$REPO_ROOT/scripts/init-project.sh" "docs/engineering/INDEX.md" "init should install engineering index" || return
  assert_file_contains "$REPO_ROOT/scripts/init-project.sh" "mkdir -p \"\$TARGET_DIR/docs/engineering\"" "init should create engineering dir" || return
  pass_test
}

test_checker_blocks_unindexed_engineering_docs() {
  start_test "gstack doc return: checker 拦未登记工程文档"

  local tmp out
  tmp=$(mktemp -d)
  mkdir -p "$tmp/docs/engineering"
  printf '# 工程文档索引\n' > "$tmp/docs/engineering/INDEX.md"

  if out=$(python3 "$CHECKER" --repo-root "$tmp" --from-paths docs/engineering/api-auth.md 2>&1); then
    _fail "未登记 docs/engineering/api-auth.md 应被拦"
    rm -rf "$tmp"; return
  fi
  if ! echo "$out" | grep -q "docs/engineering/INDEX.md"; then
    _fail "失败提示应指向 engineering index，输出：$out"
    rm -rf "$tmp"; return
  fi

  rm -rf "$tmp"
  pass_test
}

test_checker_allows_indexed_engineering_docs() {
  start_test "gstack doc return: checker 放行已登记工程文档"

  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/docs/engineering"
  printf '# 工程文档索引\n\n- [api-auth.md](api-auth.md)\n' > "$tmp/docs/engineering/INDEX.md"

  if python3 "$CHECKER" --repo-root "$tmp" --from-paths docs/engineering/api-auth.md >/tmp/out.$$ 2>/tmp/err.$$; then
    pass_test
  else
    _fail "已登记工程文档不应被拦"
    cat /tmp/err.$$ >&2
  fi
  rm -f /tmp/out.$$ /tmp/err.$$
  rm -rf "$tmp"
}

test_checker_edge_cases() {
  start_test "gstack doc return: checker 边界场景"

  local tmp
  tmp=$(mktemp -d)

  if ! python3 "$CHECKER" --repo-root "$tmp" --from-paths docs/engineering/INDEX.md >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "INDEX.md 自身不应被拦"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$; rm -rf "$tmp"; return
  fi
  if ! python3 "$CHECKER" --repo-root "$tmp" --from-paths docs/deliverables/one-pager.md >/tmp/out.$$ 2>/tmp/err.$$; then
    _fail "非 engineering 文档不应被拦"
    cat /tmp/err.$$ >&2
    rm -f /tmp/out.$$ /tmp/err.$$; rm -rf "$tmp"; return
  fi

  rm -f /tmp/out.$$ /tmp/err.$$
  rm -rf "$tmp"
  pass_test
}

test_templates_expose_engineering_docs_map
test_init_project_installs_engineering_index
test_checker_blocks_unindexed_engineering_docs
test_checker_allows_indexed_engineering_docs
test_checker_edge_cases

report_results "gstack-doc-return"
