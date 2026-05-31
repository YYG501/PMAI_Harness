#!/usr/bin/env bash
# checks-diff.py（§7.C 引擎）回归：checks-spec + 抓取产物 → P0/P1/P2。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIFF="$FRAMEWORK_ROOT/scripts/checks-diff.py"

echo "▶ Running test-checks-diff.sh"
echo "─────────────────────────────────────────"

test_detects_p0_p1_p2() {
  start_test "checks-diff: 按钮缺失=P0 / 文案缺失=P1 / 状态覆盖=P2"
  local T; T=$(mktemp -d)
  cat > "$T/plan.json" <<'EOF'
{"schema_version":"1.0","module":"m","checks":[
 {"id":"c1","level":"L1","kind":"page","must_have_text":["标题A","标题B"],
  "must_check_buttons":[{"text":"新建","disabled":false},{"text":"删除","disabled":true}],
  "must_cover_states":["loading","empty"]}]}
EOF
  mkdir -p "$T/art/reference" "$T/art/local"
  echo '{"textPreview":"标题A 标题B","buttons":[{"text":"新建","disabled":false},{"text":"删除","disabled":true}]}' > "$T/art/reference/c1.json"
  echo '{"textPreview":"标题A","buttons":[{"text":"新建","disabled":false}]}' > "$T/art/local/c1.json"
  python3 "$DIFF" --plan "$T/plan.json" --artifacts "$T/art" --report "$T/rep.md" >/dev/null 2>&1
  local p0 p1 p2
  p0=$(grep -m1 "^- P0:" "$T/rep.md" | awk '{print $NF}')
  p1=$(grep -m1 "^- P1:" "$T/rep.md" | awk '{print $NF}')
  p2=$(grep -m1 "^- P2:" "$T/rep.md" | awk '{print $NF}')
  if [ "$p0" = "1" ] && [ "$p1" = "1" ] && [ "$p2" = "1" ]; then
    pass_test
  else
    _fail "期望 P0=1(删除缺) P1=1(标题B缺) P2=1(状态)，实 P0=$p0 P1=$p1 P2=$p2"
  fi
  rm -rf "$T"
}

test_coverage_mode_no_reference() {
  start_test "checks-diff: 覆盖审计模式（无 reference）—— local 缺 must-have 直接 P1"
  local T; T=$(mktemp -d)
  cat > "$T/plan.json" <<'EOF'
{"schema_version":"1.0","module":"m","checks":[
 {"id":"c1","level":"L1","kind":"page","must_have_text":["导出CSV"],"must_check_buttons":[]}]}
EOF
  mkdir -p "$T/art/local"
  echo '{"textPreview":"别的内容","buttons":[]}' > "$T/art/local/c1.json"
  python3 "$DIFF" --plan "$T/plan.json" --artifacts "$T/art" --report "$T/rep.md" >/dev/null 2>&1
  local p1; p1=$(grep -m1 "^- P1:" "$T/rep.md" | awk '{print $NF}')
  [ "$p1" = "1" ] && pass_test || _fail "覆盖审计模式应报 P1=1（导出CSV 缺），实 P1=$p1"
  rm -rf "$T"
}

test_fail_on_p0() {
  start_test "checks-diff: --fail-on-p0 有 P0 返回非零"
  local T; T=$(mktemp -d)
  cat > "$T/plan.json" <<'EOF'
{"schema_version":"1.0","module":"m","checks":[{"id":"c1","must_check_buttons":[{"text":"X","disabled":false}]}]}
EOF
  mkdir -p "$T/art/local"
  echo '{"buttons":[]}' > "$T/art/local/c1.json"
  if python3 "$DIFF" --plan "$T/plan.json" --artifacts "$T/art" --report "$T/rep.md" --fail-on-p0 >/dev/null 2>&1; then
    _fail "有 P0 + --fail-on-p0 应返回非零"
  else
    pass_test
  fi
  rm -rf "$T"
}

test_rejects_path_traversal_cid() {
  start_test "checks-diff: check.id 路径穿越（../x）被拒为 P0（P1-4）"
  local T; T=$(mktemp -d)
  cat > "$T/plan.json" <<'EOF'
{"schema_version":"1.0","module":"m","checks":[{"id":"../../etc/x","must_have_text":["x"]}]}
EOF
  mkdir -p "$T/art/local"
  python3 "$DIFF" --plan "$T/plan.json" --artifacts "$T/art" --report "$T/rep.md" >/dev/null 2>&1
  if grep -q "非法字符" "$T/rep.md"; then pass_test; else _fail "应把含 / 的 check.id 报为 P0 非法字符"; fi
  rm -rf "$T"
}

test_malformed_artifact_no_crash() {
  start_test "checks-diff: 畸形 artifact（顶层数组）报 P0 不崩整份报告（P2-1）"
  local T; T=$(mktemp -d)
  cat > "$T/plan.json" <<'EOF'
{"schema_version":"1.0","module":"m","checks":[{"id":"c1","must_have_text":["x"]}]}
EOF
  mkdir -p "$T/art/local"
  echo '[1,2,3]' > "$T/art/local/c1.json"
  if python3 "$DIFF" --plan "$T/plan.json" --artifacts "$T/art" --report "$T/rep.md" >/dev/null 2>&1; then
    grep -q "畸形" "$T/rep.md" && pass_test || _fail "应报本地抓取畸形 P0"
  else
    _fail "畸形 artifact 不该让脚本崩溃（应报 P0 继续）"
  fi
  rm -rf "$T"
}

test_assertion_less_check_flagged() {
  start_test "checks-diff: 无断言的 check 报 P2「无可执行断言」不静默判无差异（P2-2）"
  local T; T=$(mktemp -d)
  cat > "$T/plan.json" <<'EOF'
{"schema_version":"1.0","module":"m","checks":[{"id":"c1"}]}
EOF
  mkdir -p "$T/art/local"
  echo '{"textPreview":"","buttons":[]}' > "$T/art/local/c1.json"
  python3 "$DIFF" --plan "$T/plan.json" --artifacts "$T/art" --report "$T/rep.md" >/dev/null 2>&1
  grep -q "无可执行断言" "$T/rep.md" && pass_test || _fail "无断言 check 应报 P2 无可执行断言"
  rm -rf "$T"
}

test_detects_p0_p1_p2
test_coverage_mode_no_reference
test_fail_on_p0
test_rejects_path_traversal_cid
test_malformed_artifact_no_crash
test_assertion_less_check_flagged

report_results "checks-diff"
