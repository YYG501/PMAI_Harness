#!/usr/bin/env bash
# build-audits.py 回归：三道审编排（resolve 校验输入 + synthesize 收集合成 + 门禁）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUDITS="$FRAMEWORK_ROOT/scripts/build-audits.py"

echo "▶ Running test-build-audits.sh"
echo "─────────────────────────────────────────"

# 建一个最小消费仓 fixture：.pm-workflow/config.yml + 模块 spec.md + prototype/
_setup() {
  T=$(mktemp -d)
  MOD="$T/docs/modules/demo"
  mkdir -p "$T/.pm-workflow" "$T/prototype" "$MOD"
  cat > "$T/.pm-workflow/config.yml" <<'EOF'
dev_server:
  command: pnpm dev
  ports: [3000, 5173]
  ready_check: /
EOF
  echo "# demo 规格" > "$MOD/spec.md"
  echo "# DESIGN" > "$T/docs/DESIGN.md"
  SPEC="$MOD/spec.md"
  AUD="$T/.pm-workflow/audits/spec"
}
_teardown() { rm -rf "$T"; }

# 写三道规范化结果
_write_coverage() { mkdir -p "$AUD"; echo "$1" > "$AUD/coverage.json"; }
_write_visual()   { mkdir -p "$AUD"; echo "$1" > "$AUD/visual.json"; }
_write_behavior() { mkdir -p "$AUD"; echo "$1" > "$AUD/behavior.json"; }

test_resolve_ok() {
  start_test "resolve: 输入齐全 → 建 audits/ + 打印三道 manifest"
  _setup
  out=$(python3 "$AUDITS" resolve "$SPEC" --repo-root "$T" 2>&1)
  if [ -d "$AUD" ] && echo "$out" | grep -q "覆盖审计" && echo "$out" | grep -q "视觉门" && echo "$out" | grep -q "行为审" && echo "$out" | grep -q "3000"; then
    pass_test
  else
    _fail "resolve 应建 audits/ + 打印三道 + 端口。Output: $out"
  fi
  _teardown
}

test_resolve_missing_rangelist() {
  start_test "resolve: 缺范围清单 spec.md → fail-loud"
  _setup
  rm -f "$SPEC"
  if python3 "$AUDITS" resolve "$SPEC" --repo-root "$T" >/tmp/ba.$$ 2>&1; then
    _fail "缺范围清单应 fail-loud 非零"
  else
    grep -q "锚点文件不存在" /tmp/ba.$$ && pass_test || _fail "应提示锚点缺失：$(cat /tmp/ba.$$)"
  fi
  rm -f /tmp/ba.$$; _teardown
}

test_resolve_missing_port() {
  start_test "resolve: config.yml 无 dev_server.ports → fail-loud"
  _setup
  echo "other: 1" > "$T/.pm-workflow/config.yml"
  if python3 "$AUDITS" resolve "$SPEC" --repo-root "$T" >/tmp/ba.$$ 2>&1; then
    _fail "缺端口应 fail-loud 非零"
  else
    grep -q "端口" /tmp/ba.$$ && pass_test || _fail "应提示端口缺失：$(cat /tmp/ba.$$)"
  fi
  rm -f /tmp/ba.$$; _teardown
}

test_synthesize_incomplete_fails() {
  start_test "synthesize: 缺一道结果（行为审未跑）→ fail-loud 三道不完整"
  _setup
  _write_coverage '{"items":[{"name":"登录页","status":"built"}]}'
  _write_visual '{"findings":[]}'
  # 故意不写 behavior.json
  if python3 "$AUDITS" synthesize "$SPEC" --repo-root "$T" >/tmp/ba.$$ 2>&1; then
    _fail "缺一道应 fail-loud 非零"
  else
    grep -q "三道审不完整" /tmp/ba.$$ && grep -q "行为审" /tmp/ba.$$ && pass_test || _fail "应提示行为审未跑：$(cat /tmp/ba.$$)"
  fi
  rm -f /tmp/ba.$$; _teardown
}

test_synthesize_clean_gate() {
  start_test "synthesize: 三道全过 → gate=clean + synthesis.md"
  _setup
  _write_coverage '{"items":[{"name":"登录页","status":"built"},{"name":"列表","status":"built"}]}'
  _write_visual '{"findings":[]}'
  _write_behavior '{"status":"pass","passed":3,"total":3}'
  out=$(python3 "$AUDITS" synthesize "$SPEC" --repo-root "$T" 2>&1)
  summary=$(echo "$out" | grep '"gate"')
  if echo "$summary" | grep -q '"gate": "clean"' && [ -f "$AUD/synthesis.md" ] && grep -q "可看 demo 拍板" "$AUD/synthesis.md"; then
    pass_test
  else
    _fail "三道全过应 gate=clean + 写 synthesis.md。Output: $out"
  fi
  _teardown
}

test_synthesize_needs_review_gate() {
  start_test "synthesize: 漏建 + 视觉 finding + 行为 fail → gate=needs-review + 建议项"
  _setup
  _write_coverage '{"items":[{"name":"登录页","status":"built"},{"name":"导出按钮","status":"missing","note":"范围清单要求但代码没有"},{"name":"筛选","status":"degraded","note":"占位"}]}'
  _write_visual '{"findings":[{"severity":"P1","desc":"卡片间距与 DESIGN 不一致"}]}'
  _write_behavior '{"status":"fail","passed":1,"total":2,"note":"导出流程点击无反应"}'
  out=$(python3 "$AUDITS" synthesize "$SPEC" --repo-root "$T" 2>&1)
  if echo "$out" | grep -q '"gate": "needs-review"' \
     && echo "$out" | grep -q '"missing": 1' \
     && echo "$out" | grep -q '"degraded": 1' \
     && grep -q "补建：导出按钮" "$AUD/synthesis.md" \
     && grep -q "卡片间距" "$AUD/synthesis.md"; then
    pass_test
  else
    _fail "应 gate=needs-review + 漏建/降级计数 + 建议项。Output: $out  / synthesis: $(cat "$AUD/synthesis.md" 2>/dev/null)"
  fi
  _teardown
}

test_synthesize_fail_on_gate_exit() {
  start_test "synthesize --fail-on-gate: needs-review → 非零退出码"
  _setup
  _write_coverage '{"items":[{"name":"x","status":"missing"}]}'
  _write_visual '{"findings":[]}'
  _write_behavior '{"status":"pass","passed":1,"total":1}'
  if python3 "$AUDITS" synthesize "$SPEC" --repo-root "$T" --fail-on-gate >/dev/null 2>&1; then
    _fail "needs-review + --fail-on-gate 应返回非零"
  else
    pass_test
  fi
  _teardown
}

# --- B3 参数化锚点：build skill 用 --range-list/--audit-dir/--label 显式锚定 ---

test_resolve_override_spec_anchor() {
  start_test "resolve --range-list/--audit-dir: build skill 锚点=模块 spec.md（非 req-plan.md）"
  _setup
  SPEC="$T/docs/modules/demo/spec.md"
  out=$(python3 "$AUDITS" resolve "$SPEC" --repo-root "$T" --range-list "$SPEC" --audit-dir ".pm-workflow/audits/demo" --label "demo" 2>&1)
  # 范围清单锚到 spec.md + audits 落点按模块名 demo
  if echo "$out" | grep -q "modules/demo/spec.md" \
     && [ -d "$T/.pm-workflow/audits/demo" ] \
     && [ ! -d "$T/.pm-workflow/audits/spec" ]; then
    pass_test
  else
    _fail "override 应锚 spec.md + audits/demo。Output: $out"
  fi
  _teardown
}

test_synthesize_override_label() {
  start_test "synthesize --audit-dir/--label: 报告标题用模块名 + 读对 audit-dir"
  _setup
  AUD="$T/.pm-workflow/audits/demo"
  _write_coverage '{"items":[{"name":"列表","status":"built"}]}'
  _write_visual '{"findings":[]}'
  _write_behavior '{"status":"pass","passed":1,"total":1}'
  SPEC="$T/docs/modules/demo/spec.md"
  out=$(python3 "$AUDITS" synthesize "$SPEC" --repo-root "$T" --audit-dir ".pm-workflow/audits/demo" --label "demo" 2>&1)
  if echo "$out" | grep -q '"label": "demo"' && grep -q "三道审合成报告 — demo" "$AUD/synthesis.md"; then
    pass_test
  else
    _fail "override synthesize 标题应=demo。Output: $out / synthesis: $(cat "$AUD/synthesis.md" 2>/dev/null)"
  fi
  _teardown
}

test_resolve_ok
test_resolve_missing_rangelist
test_resolve_missing_port
test_synthesize_incomplete_fails
test_synthesize_clean_gate
test_synthesize_needs_review_gate
test_synthesize_fail_on_gate_exit
test_resolve_override_spec_anchor
test_synthesize_override_label

report_results "build-audits"
