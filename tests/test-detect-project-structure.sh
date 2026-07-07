#!/usr/bin/env bash
# detect-project-structure.py 5 档判定 E2E（4.5b）
#
# 每个用例：建临时 git 仓 → 按指定文件分布 commit → 跑 detect → 校验判定。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DETECT="$REPO_ROOT/scripts/detect-project-structure.py"
SCHEMA="$REPO_ROOT/templates/工程结构约束.schema.json"

# Helper：建一个临时 git 仓 + 按 list 写文件 + commit
_make_repo() {
  local repo
  repo=$(mktemp -d "${TMPDIR:-/tmp}/detect-test.XXXXXX")
  (
    cd "$repo"
    git init -b main -q
    git config user.email "test@test.local"
    git config user.name "Test"
  )
  echo "$repo"
}

_commit_file() {
  local repo="$1"
  local relpath="$2"
  mkdir -p "$repo/$(dirname "$relpath")"
  echo "// stub" > "$repo/$relpath"
}

_finalize_repo() {
  local repo="$1"
  (
    cd "$repo"
    git add -A
    git commit -q -m "init" 2>/dev/null || true
  )
}

# Run detect, capture judgment + confidence
_detect_judgment() {
  local repo="$1"
  python3 "$DETECT" --repo "$repo" --schema "$SCHEMA" --json 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['judgment'], d['confidence'])"
}

# -----------------------------------------------------------------
# Tests
# -----------------------------------------------------------------

test_prototype_project() {
  start_test "prototype 项目：仅 components/ui + framework/layout"
  local repo
  repo=$(_make_repo)
  _commit_file "$repo" "src/components/ui/Button.tsx"
  _commit_file "$repo" "src/components/ui/Card.tsx"
  _commit_file "$repo" "src/framework/layout/Shell.tsx"
  _commit_file "$repo" "src/app/page.tsx"
  _finalize_repo "$repo"

  local result
  result=$(_detect_judgment "$repo")
  if [[ "$result" != "prototype "* ]]; then
    _fail "expected 'prototype'，得：$result"
    rm -rf "$repo"
    return
  fi
  pass_test
  rm -rf "$repo"
}

test_system_project() {
  start_test "system 项目：framework/page/Template + hooks + modules/pages + store"
  local repo
  repo=$(_make_repo)
  _commit_file "$repo" "src/framework/page/ListTemplate.tsx"
  _commit_file "$repo" "src/framework/page/DetailTemplate.tsx"
  _commit_file "$repo" "src/framework/hooks/useAuth.ts"
  _commit_file "$repo" "src/framework/hooks/useFetch.ts"
  _commit_file "$repo" "src/framework/context/AppContext.tsx"
  _commit_file "$repo" "src/modules/account/pages/login.tsx"
  _commit_file "$repo" "src/modules/account/lib/store.ts"
  _finalize_repo "$repo"

  local result
  result=$(_detect_judgment "$repo")
  if [[ "$result" != "system "* ]]; then
    _fail "expected 'system'，得：$result"
    rm -rf "$repo"
    return
  fi
  # 高置信
  local conf
  conf=$(echo "$result" | awk '{print $2}')
  if (( $(echo "$conf < 0.7" | bc -l) )); then
    _fail "system 多 signal 命中应高置信 ≥0.7，得：$conf"
    rm -rf "$repo"
    return
  fi
  pass_test
  rm -rf "$repo"
}

test_hybrid_project() {
  start_test "hybrid 项目：system signal + prototype-friendly signal 共存"
  local repo
  repo=$(_make_repo)
  _commit_file "$repo" "src/components/ui/Button.tsx"
  _commit_file "$repo" "src/framework/page/ListTemplate.tsx"
  _commit_file "$repo" "src/framework/hooks/useAuth.ts"
  _finalize_repo "$repo"

  local result
  result=$(_detect_judgment "$repo")
  if [[ "$result" != "hybrid "* ]]; then
    _fail "expected 'hybrid'，得：$result"
    rm -rf "$repo"
    return
  fi
  pass_test
  rm -rf "$repo"
}

test_non_product_repo_falls_to_unknown() {
  start_test "非产品仓（scan_roots 下无 ts/tsx）→ unknown，让 PM 自决"
  local repo
  repo=$(_make_repo)
  _commit_file "$repo" "scripts/foo.py"
  _commit_file "$repo" "templates/bar.md.tmpl"
  _commit_file "$repo" "skills/baz/SKILL.md"
  _finalize_repo "$repo"

  local result
  result=$(_detect_judgment "$repo")
  if [[ "$result" != "unknown "* ]]; then
    _fail "expected 'unknown'，得：$result"
    rm -rf "$repo"
    return
  fi
  pass_test
  rm -rf "$repo"
}

test_unknown_project() {
  start_test "unknown 项目：scan_roots 下有 ts/tsx 但无 signal 命中"
  local repo
  repo=$(_make_repo)
  _commit_file "$repo" "src/utils/helpers.ts"
  _commit_file "$repo" "src/utils/format.ts"
  _commit_file "$repo" "src/types.ts"
  _finalize_repo "$repo"

  local result
  result=$(_detect_judgment "$repo")
  if [[ "$result" != "unknown "* ]]; then
    _fail "expected 'unknown'，得：$result"
    rm -rf "$repo"
    return
  fi
  pass_test
  rm -rf "$repo"
}

test_self_repo_is_unknown() {
  start_test "self check: PM-AI-Workflow 本仓判 unknown（非产品仓，本不该跑 detect）"
  local result
  result=$(python3 "$DETECT" --json 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['judgment'])")
  if [ "$result" != "unknown" ]; then
    _fail "本仓 (生成器源头) 应判 unknown，得：$result"
    return
  fi
  pass_test
}

test_positional_repo_arg_alias() {
  start_test "位置参数 repo 路径等价于 --repo"
  local repo
  repo=$(_make_repo)
  _commit_file "$repo" "src/components/ui/Button.tsx"
  _commit_file "$repo" "src/framework/layout/Shell.tsx"
  _commit_file "$repo" "src/app/page.tsx"
  _finalize_repo "$repo"

  local result
  result=$(python3 "$DETECT" "$repo" --schema "$SCHEMA" --json 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['judgment'])")
  if [ "$result" != "prototype" ]; then
    _fail "位置参数 repo 应可被识别，得：$result"
    rm -rf "$repo"
    return
  fi
  rm -rf "$repo"
  pass_test
}

test_missing_repo_path_is_friendly() {
  start_test "不存在 repo 路径给 PM 可读错误"
  local missing out rc
  missing="${TMPDIR:-/tmp}/detect-missing-$$"
  rm -rf "$missing"

  out=$(python3 "$DETECT" "$missing" --schema "$SCHEMA" 2>&1)
  rc=$?
  if [ "$rc" != "1" ]; then
    _fail "不存在 repo 应 exit 1，得：$rc"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "repo 不存在" || ! echo "$out" | grep -q -- "--repo <path>"; then
    _fail "不存在 repo 应输出可读修复提示"
    echo "$out" >&2
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_prototype_project
test_system_project
test_hybrid_project
test_non_product_repo_falls_to_unknown
test_unknown_project
test_self_repo_is_unknown
test_positional_repo_arg_alias
test_missing_repo_path_is_friendly

report_results "detect-project-structure"
