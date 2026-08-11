#!/usr/bin/env bash
# Regression coverage for PM-facing capability promises and receipts.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIRECTION_DIR="$REPO_ROOT/skills/direction"
RECORD="$REPO_ROOT/skills/record/SKILL.md"
QUESTIONING="$REPO_ROOT/skills/_shared/project-questioning.md"
CODEBASE_AUDIT="$REPO_ROOT/skills/_internal/codebase-audit/SKILL.md"
MIGRATE_REQS="$REPO_ROOT/scripts/migrate-reqs-to-modules.py"
DECISION_TEMPLATE="$REPO_ROOT/templates/decision-record.md.tmpl"
ASKUSER_RULES="$REPO_ROOT/skills/_shared/pm-view/askuser-rules.md"
BANNER_RULES="$REPO_ROOT/skills/_shared/pm-view/banner-rules.md"
LARK_SYNC="$REPO_ROOT/skills/lark-sync/SKILL.md"
LARK_SYNC_VERIFY="$REPO_ROOT/skills/lark-sync/references/verification.md"
LARK_SYNC_PULL="$REPO_ROOT/skills/lark-sync/references/pull-from-lark.md"
LARK_SYNC_DIFF="$REPO_ROOT/skills/lark-sync/references/diff-only.md"
LARK_REVIEW="$REPO_ROOT/skills/lark-review/SKILL.md"
LARK_REVIEW_SCRIPT="$REPO_ROOT/scripts/lark-review.py"
BUILD_CANCEL="$REPO_ROOT/skills/build-cancel/SKILL.md"
FEEDBACK="$REPO_ROOT/skills/feedback/SKILL.md"
HUMANIZE="$REPO_ROOT/skills/humanize/SKILL.md"
README="$REPO_ROOT/README.md"
CLAUDE_TEMPLATE="$REPO_ROOT/templates/CLAUDE.md.tmpl"
AGENTS_TEMPLATE="$REPO_ROOT/templates/AGENTS.md.tmpl"

test_direction_is_retired_and_record_is_bounded() {
  start_test "PM surface: direction 退出，record 只补录已确认知识"
  local medium_tier

  if [ -e "$DIRECTION_DIR" ]; then
    _fail "direction should be removed instead of retained as a compatibility router"
    return
  fi
  assert_file_contains "$RECORD" "这件事已经定了，帮我记住" "record should represent a distinct PM intent" || return
  assert_file_contains "$RECORD" "产品定位、目标用户、价值、边界或 MVP" "record should route product-level reframing to proposal" || return
  assert_file_contains "$RECORD" "/pmai-proposal" "record should route product-level reframing to proposal" || return
  assert_file_contains "$RECORD" "不把 record 作为 Proposal、design、quick-fix 或 build 的后续步骤" "record should stay out of normal workflow completion" || return
  if grep -qE '/pmai-direction|skills/direction|direction skill|direction 方向' \
    "$QUESTIONING" "$CODEBASE_AUDIT" "$MIGRATE_REQS" "$DECISION_TEMPLATE" \
    "$ASKUSER_RULES" "$BANNER_RULES"; then
    _fail "retired direction remains on an active PM-facing route"
    return
  fi
  assert_file_contains "$QUESTIONING" "/pmai-proposal" "product-level gaps should route to proposal" || return
  assert_file_contains "$QUESTIONING" "/pmai-design" "module-level gaps should route to design" || return
  assert_file_contains "$QUESTIONING" "/pmai-record" "confirmed facts should route to record" || return
  assert_file_contains "$MIGRATE_REQS" "/pmai-proposal" "legacy migration guidance should route product changes to proposal" || return
  assert_file_contains "$MIGRATE_REQS" "/pmai-design" "legacy migration guidance should route module work to design" || return
  assert_file_contains "$MIGRATE_REQS" "/pmai-record" "legacy migration guidance should reserve record for confirmed facts" || return
  medium_tier=$(grep '^| 中 |' "$CLAUDE_TEMPLATE")
  if [ -z "$medium_tier" ] || printf '%s\n' "$medium_tier" | grep -q '/pmai-record'; then
    _fail "active design guidance must not route medium work to record"
    return
  fi
  if ! printf '%s\n' "$medium_tier" | grep -q '继续 `/pmai-design`' \
    || ! printf '%s\n' "$medium_tier" | grep -q '/pmai-status.*只读恢复'; then
    _fail "active design guidance should continue design and use status only for recovery"
    return
  fi
  if grep -qE '路线规划|季度规划|半年规划' \
    "$RECORD" "$QUESTIONING" "$README" "$CLAUDE_TEMPLATE"; then
    _fail "PM surface still promises unsupported roadmap planning"
    return
  fi
  pass_test
}

test_record_requires_a_valid_product_baseline() {
  start_test "PM surface: record 不能绕过初始化后的 Proposal"

  local gate_count gate_line worktree_line workflow_line
  gate_count=$(grep -Fc 'proposal-contract.py" status "$REPO_ROOT"' "$RECORD")
  gate_line=$(grep -n 'proposal-contract.py" status "$REPO_ROOT"' "$RECORD" | head -1 | cut -d: -f1)
  worktree_line=$(grep -n '`WORKTREE_TYPE != main`' "$RECORD" | head -1 | cut -d: -f1)
  workflow_line=$(grep -n '^## Workflow' "$RECORD" | head -1 | cut -d: -f1)
  if [ "$gate_count" -ne 1 ] || [ -z "$gate_line" ] || [ -z "$worktree_line" ] \
    || [ -z "$workflow_line" ] || [ "$gate_line" -ge "$worktree_line" ] \
    || [ "$gate_line" -ge "$workflow_line" ]; then
    _fail "record Proposal gate must run exactly once before routing or writes"
    return
  fi
  assert_file_contains "$RECORD" '`accepted` / `equivalent_baseline`：继续 record' \
    "record should proceed only from a valid product baseline" || return
  assert_file_contains "$RECORD" '`required`：初始化后的唯一下一步仍是 `/pmai-proposal`' \
    "new projects must return to Proposal before record" || return
  assert_file_contains "$RECORD" '`invalid`：当前 Proposal 或产品基线已漂移.*只返回 `/pmai-proposal`' \
    "invalid Proposal state must fail closed before record" || return
  assert_file_contains "$RECORD" '不选落点、不写文件、不提交' \
    "required Proposal state must remain mutation-free" || return
  assert_file_contains "$RECORD" '`docs/proposals/\*\*`' \
    "record must continue to forbid Proposal writes" || return
  pass_test
}

test_lark_receipts_hide_internal_protocol() {
  start_test "PM surface: 飞书最终回执只报告结果"

  local sync_receipt sync_verify_receipt sync_pull_receipt sync_diff_receipt review_receipt rendered_review
  sync_receipt=$(awk '/^### 步骤 3：验收与输出/{show=1} /^## Rules/{show=0} show' "$LARK_SYNC")
  sync_verify_receipt=$(awk '/^## 输出摘要/{show=1} show' "$LARK_SYNC_VERIFY")
  sync_pull_receipt=$(awk '/^## 输出$/{show=1} /^## 禁止/{show=0} show' "$LARK_SYNC_PULL")
  sync_diff_receipt=$(awk '/^## 输出格式/{show=1} /^## 规则/{show=0} show' "$LARK_SYNC_DIFF")
  review_receipt=$(awk '/^## 最终回执/{show=1} /^## Rules/{show=0} show' "$LARK_REVIEW")
  rendered_review=$(PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$REPO_ROOT/scripts" \
    python3 - "$LARK_REVIEW_SCRIPT" <<'PY'
import importlib.util
import sys
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("pmai_lark_review_receipt_test", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
print(module._render_pm_receipt(
    document_url="https://example.feishu.cn/docx/example",
    body_change_count=2,
    content_verified=True,
    completed_comment_count=3,
    waiting_pm_comment_count=1,
    retained_comment_count=2,
    decision_write_count=1,
    implementation_result="updated_verified",
    implementation_label="prototype",
    incomplete_reason=None,
))
PY
  )

  if printf '%s\n' "$sync_receipt" | grep -qE '同步模式|A/B/C/D|revision|frontmatter'; then
    _fail "lark-sync PM receipt still exposes internal sync protocol"
    return
  fi
  if printf '%s\n%s\n%s\n' "$sync_verify_receipt" "$sync_pull_receipt" "$sync_diff_receipt" \
    | grep -qE '模式：|模式 A/B/C|飞书 revision：|frontmatter：'; then
    _fail "lark-sync reference receipts still expose internal sync protocol"
    return
  fi
  if printf '%s\n' "$review_receipt" | grep -qE '批次现场|目标底稿|remote_native_snapshot|revision|执行路径|checkpoint|机器耗时'; then
    _fail "lark-review PM receipt still exposes batch or recovery internals"
    return
  fi
  if ! printf '%s\n' "$sync_receipt" | grep -q '需要你处理' \
    || ! printf '%s\n' "$review_receipt" | grep -q '产品结果'; then
    _fail "lark PM receipts should retain actionable results"
    return
  fi
  if ! printf '%s\n' "$rendered_review" | grep -q '产品结果：原型已更新并验证' \
    || ! printf '%s\n' "$rendered_review" | grep -q '请在飞书手工解决 1 条' \
    || printf '%s\n' "$rendered_review" \
      | grep -qE 'revision|hash|checkpoint|DONE_WITH_CONCERNS|批次|目标底稿'; then
    _fail "real lark-review renderer should expose business results without protocol details"
    return
  fi
  pass_test
}

test_cancel_receipt_never_delegates_cleanup_to_pm() {
  start_test "PM surface: build-cancel 不让 PM 手工清理"

  local receipt
  receipt=$(awk '/^### 步骤 3：回执/{show=1} /^## Rules/{show=0} show' "$BUILD_CANCEL")
  if printf '%s\n' "$receipt" | grep -qE 'cleanup-pending|bash scripts|回主仓后运行'; then
    _fail "build-cancel receipt still delegates cleanup commands to PM"
    return
  fi
  if ! printf '%s\n' "$receipt" | grep -q '不需要你运行清理命令'; then
    _fail "build-cancel should state that cleanup is automatic"
    return
  fi
  pass_test
}

test_capability_claims_are_bounded() {
  start_test "PM surface: feedback 与 humanize 不夸大能力"

  if ! sed -n '1,8p' "$FEEDBACK" | grep -q '当前只有 Codex'; then
    _fail "feedback frontmatter should disclose the verified Codex-only locator"
    return
  fi
  if ! grep -q '当前只有 Codex' "$README" \
    || ! grep -q '当前只有 Codex' "$CLAUDE_TEMPLATE" \
    || ! grep -q '当前只有 Codex' "$AGENTS_TEMPLATE"; then
    _fail "consumer-facing feedback descriptions should disclose Codex-only support"
    return
  fi
  if grep -qE '独立模型|另一个模型' "$HUMANIZE" \
    || ! grep -q '独立上下文' "$HUMANIZE" \
    || ! grep -q '明确选择并验证' "$HUMANIZE"; then
    _fail "humanize should call codex cold reading an independent context unless a different model is verified"
    return
  fi
  if grep -q '8 类禁用' "$HUMANIZE"; then
    _fail "humanize should not duplicate a drifting category count"
    return
  fi
  pass_test
}

test_docs_do_not_turn_inventory_into_navigation() {
  start_test "PM surface: README 与消费仓模板不要求 PM 编排后台入口"

  assert_file_contains "$README" "init-project" "README should start the normal path with project initialization" || return
  assert_file_contains "$README" "它不是主流程的固定一步" "README should frame status as recovery only" || return
  if grep -qE '^## (完整 Skill 命令汇总|Skill 安装清单)|正常协作.*design.*build.*status' "$README"; then
    _fail "README should not retain a full command inventory or make status a normal workflow step"
    return
  fi
  local main_path main_chain
  main_path=$(awk '/^### 2\. PM 在业务仓里的主路径/{show=1} /^### 3\./{show=0} show' "$README")
  main_chain=$(printf '%s\n' "$main_path" | awk '/^```/{fence++; next} fence==1')
  if printf '%s\n' "$main_chain" | grep -qE '/pmai-(meta|mockup|quick-fix|record|direction|lark-review|lark-sync|build-close|build-cancel)'; then
    _fail "README normal path should expose the approved proposal, design, spec-writing and build chain only"
    return
  fi

  local main_entries status_count
  main_entries=$(awk '/^### 主入口/{show=1} /^### 确认门/{show=0} show' "$CLAUDE_TEMPLATE")
  status_count=$(printf '%s\n' "$main_entries" | grep -c '/pmai-status' || true)
  if [ "$status_count" -ne 1 ]; then
    _fail "consumer CLAUDE main entries should list status exactly once"
    return
  fi
  if printf '%s\n' "$main_entries" | grep -qE '/pmai-build-close|/pmai-spec-writing'; then
    _fail "recovery and background writing capabilities should not be main entries"
    return
  fi
  if ! grep -q '只有发生中断续跑.*pmai-build-close' "$CLAUDE_TEMPLATE"; then
    _fail "build-close should remain available only under explicit recovery conditions"
    return
  fi
  if grep -qE '完整路径验收和文档影响草案|预生成的文档影响草案' "$AGENTS_TEMPLATE" "$CLAUDE_TEMPLATE"; then
    _fail "consumer templates should not claim doc impact exists before landing"
    return
  fi
  if ! grep -q '先合入 main，再基于 landed diff 生成文档影响地图' "$AGENTS_TEMPLATE" \
    || ! grep -q '先合入 main，再基于 landed diff 生成文档影响地图' "$CLAUDE_TEMPLATE"; then
    _fail "consumer templates should generate doc impact from the landed diff"
    return
  fi
  pass_test
}

test_direction_is_retired_and_record_is_bounded
test_record_requires_a_valid_product_baseline
test_lark_receipts_hide_internal_protocol
test_cancel_receipt_never_delegates_cleanup_to_pm
test_capability_claims_are_bounded
test_docs_do_not_turn_inventory_into_navigation

report_results "pm-facing-surface"
