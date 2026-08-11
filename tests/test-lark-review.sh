#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/lark-review/SKILL.md"
ROUTING="$REPO_ROOT/skills/lark-review/references/review-routing.md"
COLLECTOR="$REPO_ROOT/scripts/lark-review.py"
PROPOSAL_CONTRACT="$REPO_ROOT/scripts/proposal-contract.py"
DOCTOR="$REPO_ROOT/bin/pmai-doctor"
README="$REPO_ROOT/README.md"
AGENTS_TEMPLATE="$REPO_ROOT/templates/AGENTS.md.tmpl"
CLAUDE_TEMPLATE="$REPO_ROOT/templates/CLAUDE.md.tmpl"
PUBLISH_SKILL="$REPO_ROOT/skills/publish-to-lark/SKILL.md"
SYNC_SKILL="$REPO_ROOT/skills/sync-from-lark/SKILL.md"
WRITEBACK_CONTRACT="$REPO_ROOT/skills/_shared/lark-writeback.md"
DESIGN_SKILL="$REPO_ROOT/skills/design/SKILL.md"
PROPOSAL_SKILL="$REPO_ROOT/skills/proposal/SKILL.md"
BUILD_SKILL="$REPO_ROOT/skills/build/SKILL.md"
QUICK_FIX_SKILL="$REPO_ROOT/skills/quick-fix/SKILL.md"
SPEC_SKILL="$REPO_ROOT/skills/spec-writing/SKILL.md"
HANDOFF="$REPO_ROOT/skills/lark-review/references/lifecycle-handoff.md"
AGENT="$REPO_ROOT/skills/lark-review/agents/openai.yaml"

BASE_RAW=$(mktemp -d /tmp/pmai-lark-review-test-XXXXXX)
BASE=$(cd "$BASE_RAW" && pwd -P)
SHIM="$BASE/bin"
mkdir -p "$SHIM"
cp "$SCRIPT_DIR/helpers/fake-lark-review-cli.sh" "$SHIM/lark-cli"
chmod +x "$SHIM/lark-cli"
export PATH="$SHIM:$PATH"
export PYTHONPYCACHEPREFIX="$BASE/pycache"

cleanup() {
  rm -rf "$BASE"
}
trap cleanup EXIT

make_review_doc() {
  local path="$1"
  local root
  root=$(dirname "$path")
  mkdir -p "$root/.git" "$root/docs/modules/example"
  printf '# PMAI Agent Entry\n' > "$root/AGENTS.md"
  printf '# Product State\n' > "$root/PRODUCT-STATE.md"
  local body='# Spec

Old rule
'
  local hash
  hash=$(printf '%s' "$body" | PYTHONPATH="$REPO_ROOT/scripts" python3 -c 'import sys; from _lib.lark_adapter import markdown_body_hash; print(markdown_body_hash(sys.stdin.read()))')
  {
    echo '---'
    echo 'lark_doc_id: docR'
    echo 'lark_doc_url: https://example.feishu.cn/docx/docR'
    echo 'lark_published_revision_id: 7'
    echo "lark_published_source_hash: $hash"
    echo 'lark_reviewed_comment_at: 150'
    echo '---'
    echo
    printf '%s' "$body"
  } > "$path"
}

make_git_module_review_repo() {
  local root="$1"
  mkdir -p "$root"
  git -C "$root" init -q -b main
  git -C "$root" config user.email test@example.com
  git -C "$root" config user.name "PMAI Test"
  mkdir -p "$root/docs/modules/example"
  printf '# PMAI Agent Entry\n' > "$root/AGENTS.md"
  printf '# Product State\n' > "$root/PRODUCT-STATE.md"
  local body='# Spec

Old rule
'
  local hash
  hash=$(printf '%s' "$body" | PYTHONPATH="$REPO_ROOT/scripts" python3 -c 'import sys; from _lib.lark_adapter import markdown_body_hash; print(markdown_body_hash(sys.stdin.read()))')
  {
    echo '---'
    echo 'lark_doc_id: docR'
    echo 'lark_doc_url: https://example.feishu.cn/docx/docR'
    echo 'lark_published_revision_id: 7'
    echo "lark_published_source_hash: $hash"
    echo 'lark_reviewed_comment_at: 150'
    echo '---'
    echo
    printf '%s' "$body"
  } > "$root/docs/modules/example/spec.md"
  git -C "$root" add -- AGENTS.md PRODUCT-STATE.md docs/modules/example/spec.md
  git -C "$root" commit -q -m "review fixture"
}

accept_test_proposal() {
  local root="$1"
  mkdir -p "$root/docs/proposals" "$root/.pm-workflow"
  cat > "$root/docs/proposals/review-v1.md" <<'MD'
# Review Product Proposal

> 版本：v1
> Proposal ID：review-v1
> 状态：当前
> 日期：2026-08-11
> 取代：无
> 支持的决定：是否投入可验证的规格评审闭环
> 证据截至：2026-08-11

## 0. 决策摘要与产品主张

为产品负责人提供可验证的规格评审闭环。

## 1. 产品成立的核心判断

负责人需要让在线评审与本地产品依据保持一致。

## 2. 用户、场景、问题与现状替代

产品负责人在飞书评审规格后需要可靠回收到产品主线。

## 3. 产品回答与职责边界

产品归位评审证据并保留人工最终决策。

## 4. 必要能力与 AI 角色

AI 负责归位证据，确定性脚本负责版本门禁。

## 5. 替代方案、竞争判断与产品机会

人工复制容易丢失上下文，机会在于可追溯闭环。

## 6. 端到端产品体验与关键能力

从在线评审、方向修订、规格更新到评论收口形成闭环。

## 7. 产品价值、因果链与指标

一致的依据减少遗漏并提高评审结论可执行性。

## 8. MVP 范围、完整案例与决策门

先验证一个规格从飞书回收到产品主线的完整案例。

## 9. 演进条件与长期方向

主案例成立后再扩展更多文档类型。

## 10. 下游交接摘要

- **第一个 design 目标**：完成评审闭环
- **主用户与触发时刻**：产品负责人完成飞书评审时
- **要闭合的核心任务**：更新规格并收口评论
- **必须保持的产品回答**：归位证据后再更新产品依据
- **必须保持的产品边界**：最终产品方向由人确认
- **MVP 必须证明**：评审结论能够完整回到产品主线
- **仍待验证的假设**：负责人愿意按闭环处理评审
- **design 需要收敛**：对象、状态、权限和异常路径
MD
  cat > "$root/docs/proposals/INDEX.md" <<'MD'
# Product Proposal 索引

| 文档 | 版本 | 状态 | 取代 | 决策日期 | 下游起点 |
|---|---|---|---|---|---|
| [`review-v1.md`](review-v1.md) | v1 | 当前 | 无 | 2026-08-11 | 评审闭环 |
MD
  cat > "$root/PRODUCT.md" <<'MD'
# Product

## 当前 Product Proposal

[review-v1.md](docs/proposals/review-v1.md)

## 产品定位

为产品负责人提供可验证规格评审闭环的产品。

## 核心问题与价值

减少在线评审回收时的上下文遗漏。

## 用户画像

需要对产品规格负责的产品负责人。

## 产品边界

产品归位证据，最终方向仍由人确认。

## MVP Case

负责人完成飞书评审后更新规格并收口评论。
MD
  python3 "$PROPOSAL_CONTRACT" accept "$root" \
    --proposal docs/proposals/review-v1.md --id review-v1 \
    --accepted-at '2026-08-11T10:00:00+08:00' >/dev/null || return 1
  git -C "$root" add -- PRODUCT.md docs/proposals/review-v1.md \
    docs/proposals/INDEX.md .pm-workflow/proposal.json || return 1
  git -C "$root" commit -q -m "docs: accept review proposal" || return 1
  python3 "$PROPOSAL_CONTRACT" validate "$root" >/dev/null
}

write_replan_candidate_manifest() {
  local path="$1"
  local mode="$2"
  local route="$3"
  local work_id="$4"
  local worktree="$5"
  local branch="$6"
  local candidate_head="$7"
  local baseline="$8"
  mkdir -p "$(dirname "$path")"
  python3 - "$path" "$mode" "$route" "$work_id" "$worktree" "$branch" \
    "$candidate_head" "$baseline" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
mode, route, work_id, worktree, branch, candidate_head, baseline = sys.argv[2:]
path.write_text(json.dumps({
    "schema_version": 1,
    "work_id": work_id,
    "mode": mode,
    "route": route,
    "candidate_head": candidate_head,
    "original_baseline_sha": baseline,
    "branch": branch,
    "worktree": worktree,
    "module": "docs/modules/example",
    "main_branch": "main",
    "created_at": "2026-08-10T12:00:00+08:00",
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

assert_pending_handoff_bundle() {
  local main_root="$1"
  local route="$2"
  local handoff_output="$3"
  local manifest="$4"
  local include_candidate="${5:-0}"
  local batch_id bundle list_output filtered_output
  batch_id=$(python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["batch_id"])' \
    "$manifest") || return 1
  bundle="$main_root/.runs/lark-review-handoffs/$batch_id/bundle.json"

  if ! python3 - "$handoff_output" "$bundle" "$batch_id" "$route" \
    "$include_candidate" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(sys.argv[1])
bundle_path = Path(sys.argv[2])
batch_id, route = sys.argv[3:5]
include_candidate = sys.argv[5] == "1"
assert result["handoff_bundle"] == str(bundle_path)
bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
assert bundle["batch_id"] == batch_id
assert bundle["route"] == route
assert bundle["phase"] == route
assert bundle["phase_history"] == []
assert bundle["state"] == "pending"
required = {
    "handoff": "handoff.json",
    "review": "review.json",
    "draft_plan": "apply-plan.json",
    "resolutions": "resolutions.json",
    "target": "target.md",
    "local": "local.md",
    "remote": "remote.md",
    "remote_native": "remote-native.json",
    "local_remote_diff": "local-vs-remote.diff",
    "remote_coverage": "remote-coverage.json",
    "remote_preview": "remote-preview.md",
}
if include_candidate:
    required["candidate_manifest"] = "candidate-manifest.json"
for filename in required.values():
    evidence_path = bundle_path.parent / filename
    assert evidence_path.is_file(), evidence_path
    assert not evidence_path.is_symlink(), evidence_path
PY
  then
    _fail "handoff did not create a self-contained pending bundle: $handoff_output"
    return 1
  fi

  if ! list_output=$(python3 "$COLLECTOR" list-handoffs "$main_root" \
    --route "$route" 2>&1); then
    _fail "pending handoff list failed: $list_output"
    return 1
  elif ! python3 - "$list_output" "$bundle" "$batch_id" "$route" \
    "$include_candidate" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(sys.argv[1])
bundle_path = Path(sys.argv[2])
batch_id, route = sys.argv[3:5]
include_candidate = sys.argv[5] == "1"
assert result["status"] == "handoff_list"
assert result["count"] == 1
entry = result["handoffs"][0]
assert entry["batch_id"] == batch_id
assert entry["route"] == route
assert entry["phase"] == route
assert entry["state"] == "pending"
assert entry["handoff_bundle"] == str(bundle_path)
expected = {
    "handoff": "handoff.json",
    "review": "review.json",
    "draft_plan": "apply-plan.json",
    "resolutions": "resolutions.json",
    "target": "target.md",
    "local": "local.md",
    "remote": "remote.md",
    "remote_native": "remote-native.json",
    "local_remote_diff": "local-vs-remote.diff",
    "remote_coverage": "remote-coverage.json",
    "remote_preview": "remote-preview.md",
}
if include_candidate:
    expected["candidate_manifest"] = "candidate-manifest.json"
evidence_files = entry["evidence_files"]
assert isinstance(evidence_files, dict)
returned_paths = {Path(path) for path in evidence_files.values()}
for filename in expected.values():
    expected_path = bundle_path.parent / filename
    assert expected_path in returned_paths, (filename, evidence_files)
for evidence_path in returned_paths:
    assert evidence_path.parent == bundle_path.parent, evidence_path
    assert evidence_path.is_file(), evidence_path
    assert not evidence_path.is_symlink(), evidence_path
PY
  then
    _fail "list-handoffs did not return the pending bundle and sibling evidence: $list_output"
    return 1
  fi

  local other_route="proposal"
  [ "$route" = "proposal" ] && other_route="design"
  if ! filtered_output=$(python3 "$COLLECTOR" list-handoffs "$main_root" \
    --route "$other_route" 2>&1); then
    _fail "handoff route filter failed: $filtered_output"
    return 1
  elif ! python3 - "$filtered_output" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["status"] == "handoff_list"
assert result["count"] == 0
assert result["handoffs"] == []
PY
  then
    _fail "list-handoffs returned a bundle from the wrong route: $filtered_output"
    return 1
  fi
}

complete_decision_routing() {
  confirm_remote_body "$1" || return 1
  python3 - "$1" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["decision_routing"]:
    item.update(
        outcome="not_required",
        target_path="",
        decision_id="",
        supersedes=[],
        summary="",
        reason="测试项不改变稳定产品规则",
    )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

confirm_remote_body() {
  python3 - "$1" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["body"]:
    if item["decision"] == "needs_pm":
        item.update(
            decision="remote",
            authority="pm_confirmed",
            reason="PM 本轮确认采用飞书正文增量",
        )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

seal_simple_review() {
  local work="$1"
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null || return 1
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["comments"]:
    item.update({
        "decision": "no_spec_change",
        "authority": "existing_spec",
        "reason": "测试中确认评论不需要额外修改规格",
        "result_text": "Updated and verified",
    })
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json" || return 1
  python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal >/dev/null
}

seal_controlled_review() {
  local work="$1"
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null || return 1
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["comments"]:
    if item["comment_id"] == "c1":
        item.update({
            "decision": "no_spec_change",
            "authority": "existing_spec",
            "reason": "测试中确认评论不需要额外修改规格",
            "result_text": "Updated and verified",
        })
    else:
        item.update({
            "decision": "deferred",
            "authority": "pm_confirmed",
            "reason": "测试中保留为未解决评论",
        })
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json" || return 1
  python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal >/dev/null
}

prepare_controlled_review() {
  local work="$1"
  mkdir -p "$work/out" "$work/remote-state"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null || return 1
  seal_controlled_review "$work" || return 1
  python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" >/dev/null || return 1
  refresh_review_baseline "$work" || return 1
  FAKE_REVIEW_SYNCED_REMOTE=1 \
    python3 "$COLLECTOR" verify-sync \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" >/dev/null || return 1
}

prepare_batch_review() {
  local work="$1"
  mkdir -p "$work/out" "$work/remote-state"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null || return 1
  seal_simple_review "$work" || return 1
  python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" >/dev/null || return 1
  refresh_review_baseline "$work" || return 1
  FAKE_REVIEW_SYNCED_REMOTE=1 \
    python3 "$COLLECTOR" verify-sync \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" >/dev/null || return 1
}

complete_controlled_c1() {
  local work="$1"
  FAKE_REVIEW_SYNCED_REMOTE=1 \
  FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
  FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 \
      --result-text 'Updated and verified'
}

refresh_review_baseline() {
  local work="$1"
  local revision="${2:-10}"
  local target_hash
  target_hash=$(python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["target"]["body_sha256"])' \
    "$work/out/apply-plan.json") || return 1
  FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_SYNCED_REVISION="$revision" \
    python3 "$COLLECTOR" baseline "$work/spec.md" \
      --revision-id "$revision" \
      --expected-source-hash "$target_hash" >/dev/null
}

test_skill_contract() {
  start_test "lark-review: Skill 暴露、基线和分流合同完整"
  assert_file_contains "$SKILL" "name: pmai-lark-review" "frontmatter should expose pmai-lark-review" || return
  assert_file_contains "$SKILL" "lark-review.py.*collect" "skill should call deterministic collector" || return
  assert_file_contains "$SKILL" "lark-review.py" "skill should use the authoritative review helper" || return
  assert_file_contains "$SKILL" "resolve-target" "skill should bind the authoritative markdown before collect" || return
  assert_file_contains "$SKILL" "不得从当前 cwd 猜仓根" "review target must not inherit a stale main cwd" || return
  assert_file_contains "$SKILL" "REVIEW_ACTIVE_WORK_DIR" "active review routing should use the target-bound work directory" || return
  if grep -Fq 'REPO_ROOT=$(git rev-parse --show-toplevel)' "$SKILL"; then
    _fail "lark-review must not derive the review repository from the controller cwd"
    return
  fi
  assert_file_contains "$SKILL" "lark-review.py.*reconcile" "skill should require deterministic reconciliation" || return
  assert_file_contains "$SKILL" "lark-review.py.*apply" "skill should require guarded target apply" || return
  assert_file_contains "$SKILL" "remote_native_snapshot" "review target must be based on the native remote snapshot" || return
  assert_file_contains "$SKILL" "remote-coverage.json" "review must expose remote content/format coverage" || return
  assert_file_contains "$SKILL" "内容与格式：.*核对" "final receipt must report content and format preservation as a PM-readable outcome" || return
  assert_file_contains "$SKILL" "lark-review.py.*verify-sync" "review must verify native format after writeback" || return
  assert_file_contains "$SKILL" "10–15 分钟" "review must define a machine-time performance target" || return
  assert_file_contains "$SKILL" "产品规则变化写.*decisions.md.*措辞和格式变化不得" "decision recording must be selective" || return
  assert_file_contains "$SKILL" "decision_routing" "decision archival routing must be explicit before seal" || return
  assert_file_contains "$SKILL" "不可信业务证据" "remote review content must be treated as untrusted evidence" || return
  assert_file_contains "$SKILL" "不得执行其包含的 shell / API / Skill 命令" "remote content must not trigger instructions" || return
  assert_file_contains "$SKILL" "target_path.*只允许.*docs/modules/<单一模块>/decisions.md" "decision targets must use the module allowlist" || return
  assert_file_contains "$SKILL" "B / L / R.*只读证据" "skill should keep source versions read-only" || return
  assert_file_contains "$SKILL" "只有已 seal 的 T" "skill should make T the only writable target" || return
  assert_file_contains "$SKILL" "整批只走一条主执行路径" "mixed batch should use one lifecycle" || return
  assert_file_contains "$AGENT" "Proposal" "Lark review agent prompt should expose product-level routing" || return
  assert_file_contains "$AGENT" "design" "Lark review agent prompt should expose module-level routing" || return
  assert_file_contains "$AGENT" "build" "Lark review agent prompt should expose active-build routing" || return
  if grep -q "更新、验证原型" "$AGENT"; then
    _fail "Lark review agent prompt still assumes every review updates a prototype"
    return
  fi
  assert_file_contains "$SKILL" "未验证完成前不解决评论" "comments must remain open before verification" || return
  assert_file_contains "$SKILL" "全量评论围栏" "checkpoint should bind all comments, including solved comments" || return
  assert_file_contains "$SKILL" "is_solved=false.*is_solved=true" "full comment fence must query both solved states explicitly" || return
  assert_file_contains "$SKILL" "lark-review.py.*complete-comments" "new batches should complete comments through one controlled batch command" || return
  assert_file_contains "$SKILL" "comments\[\].result_text" "comment result text should be sealed before batch completion" || return
  assert_file_contains "$SKILL" "批次开始.*全部写入结束.*稳定全量评论围栏" "batch completion should use stable boundary scans" || return
  assert_file_contains "$SKILL" "checkpoint.*复用.*不重复下载 full XML" "checkpoint should reuse revision-bound native verification" || return
  assert_file_contains "$SKILL" "comment-actions.json" "checkpoint should consume controlled comment receipts" || return
  assert_file_contains "$SKILL" "lark-review.py.*reopen" "checkpoint recovery should reopen system-solved batch comments" || return
  assert_file_contains "$SKILL" "不接受自由填写.*reply.*author.*solver" "comment recovery must not trust caller-supplied identities" || return
  assert_file_contains "$SKILL" "\.pm-workflow/context/lark-review" "review batches should survive across turns outside Git" || return
  assert_file_contains "$SKILL" "连续两轮.*围栏" "full comment scans should require consecutive stable fences" || return
  assert_file_contains "$SKILL" "apply 成功后只执行 seal 前固化的路由" "apply must not reclassify the sealed route" || return
  assert_file_contains "$SKILL" "checkpoint 不替代" "checkpoint should keep lifecycle evidence in downstream gates" || return
  assert_file_contains "$HANDOFF" "apply 成功前不得改写任何权威产品状态" "authority writes must wait for apply" || return
  assert_file_contains "$ROUTING" "revision 不能可靠证明.*PM 已认可" "remote revision must not impersonate PM approval" || return
  assert_file_contains "$ROUTING" "只问一次是否全部认可" "unattributed body edits should use one batch confirmation" || return
  assert_file_contains "$ROUTING" "产品级变化" "routing should distinguish product-level changes" || return
  assert_file_contains "$SKILL" "产品定位、目标用户、核心问题与价值、产品职责边界、MVP 证明目标或关键成立前提变化" "product-level review changes must return to Proposal" || return
  assert_file_contains "$SKILL" "模块对象、关系、动作、状态、权限、真相源、信息结构、任务路径或关键交互变化" "module-level review changes must return to design" || return
  assert_file_contains "$SKILL" "已批准模块与当前任务内形成 PM 已接受的小范围行为或体验调整" "only scoped active-build adjustments may use accepted delta" || return
  assert_file_contains "$ROUTING" "下列任一变化都必须回完整.*pmai-proposal" "routing must send product-level changes back to Proposal" || return
  assert_file_contains "$ROUTING" "同模块已有 active build 也必须先回.*pmai-design.*不得写 accepted delta" "routing must not turn module changes into active-build deltas" || return
  assert_file_contains "$ROUTING" "只有同时满足以下条件才可回原 build 写 accepted delta" "routing must limit active-build deltas to scoped adjustments" || return
  assert_file_contains "$ROUTING" "规格已经唯一说明正确行为.*直接纠正实现，不写 accepted delta" "active implementation corrections must not create deltas" || return
  assert_file_contains "$ROUTING" "当前评审批次一律先转为只读 handoff.*旧 T 永不 apply" "product-level review changes must always hand off before Proposal" || return
  if grep -q "产品变化默认写 accepted delta\|有 active build 时整批回原 build 形成 accepted delta" "$SKILL" "$ROUTING"; then
    _fail "lark review still defaults active-build product changes to accepted delta"
    return
  fi
  assert_file_contains "$DOCTOR" "lark-review" "doctor should expose lark-review" || return
  assert_file_contains "$AGENTS_TEMPLATE" "/pmai-lark-review" "consumer AGENTS should route lark review" || return
  assert_file_contains "$CLAUDE_TEMPLATE" "/pmai-lark-review" "consumer CLAUDE should list lark-review" || return
  assert_file_contains "$PUBLISH_SKILL" "lark_published_revision_id" "publisher should record review revision" || return
  assert_file_contains "$SYNC_SKILL" "/pmai-lark-review" "mechanical pull should route review intent" || return
  assert_file_contains "$WRITEBACK_CONTRACT" "评审回流写回" "review should share the internal writeback contract" || return
  assert_file_contains "$HANDOFF" "apply 前：只收敛候选决定并编译 T" "ordinary review batches should apply T before implementation" || return
  assert_file_contains "$HANDOFF" "无 active build 时用.*handoff --route proposal" "product-level reviews without a build need a direct read-only handoff" || return
  assert_file_contains "$SKILL" "--applied-context-pack.*APPLIED_CONTEXT_PACK" "active build review should bind the applied context pack" || return
  assert_file_contains "$SKILL" "--approval-artifact.*remote-verification.json" "active build review should bind the verified sealed batch" || return
  assert_file_contains "$SKILL" "只读.*handoff.*不 seal / apply" "high-impact active reviews must leave the old batch read-only" || return
  assert_file_contains "$SKILL" "find-resumable" "batch recovery must use the machine scanner" || return
  assert_file_contains "$SKILL" "lark-review.py.*handoff" "upstream replan must persist a machine handoff" || return
  assert_file_contains "$SKILL" "list-handoffs" "review recovery must enumerate durable handoff bundles from main" || return
  assert_file_contains "$PROPOSAL_SKILL" "list-handoffs" "Proposal must recover pending product-review handoffs" || return
  assert_file_contains "$PROPOSAL_SKILL" "--route proposal" "Proposal must only consume product-level handoff bundles" || return
  assert_file_contains "$DESIGN_SKILL" "list-handoffs" "design must recover pending module-review handoffs" || return
  assert_file_contains "$DESIGN_SKILL" "--route design" "design must only consume module-level handoff bundles" || return
  assert_file_contains "$SKILL" "--closes-handoff" "fresh lark-review checkpoint must close the consumed handoff bundle" || return
  if ! python3 "$COLLECTOR" checkpoint --help 2>&1 \
    | grep -q -- '--closes-handoff'; then
    _fail "checkpoint CLI must expose --closes-handoff for durable handoff closure"
    return
  fi
  assert_file_contains "$SKILL" "plan 状态改成.*handed_off" "handoff must make the old plan non-resumable" || return
  assert_file_contains "$SKILL" "route、review / draft plan / T / resolutions 摘要.*candidate manifest" "handoff must bind route, batch artifacts, and the exact candidate" || return
  assert_file_contains "$SKILL" "main 与 worktree build 使用同一合同" "handoff must support both build modes" || return
  assert_file_contains "$SKILL" "\[有 active 时先 replan\] → handoff → Proposal → design / spec-writing" "product handoff must precede Proposal authority changes" || return
  assert_file_contains "$SKILL" "旧 manifest、markdown path 和.*REVIEW_DIR.*禁止复用" "replanned reviews must not apply from an old worktree batch" || return
  assert_file_contains "$SKILL" "fresh collect.*闭合原评论" "replanned reviews must collect a fresh main-bound batch" || return
  assert_file_contains "$HANDOFF" "不改变对象、关系、业务规则、权限模型或关键任务路径" "scoped review deltas must exclude module-model changes" || return
  assert_file_contains "$SKILL" "--scope-attestation approved-module-task-no-model-change" "review deltas must carry scope attestation" || return
  assert_file_contains "$SKILL" "--approval-kind lark-review-batch" "review deltas must bind sealed batch evidence" || return
  assert_file_contains "$SKILL" "authority_paths" "applied review must bind exact authority paths" || return
  assert_file_contains "$SKILL" "spec.md + \.work-meta.json" "review flow must create an exact authority checkpoint" || return
  if ! python3 - "$SKILL" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
section = text.split("### 7. 按已固化路由精细同步", 1)[1]
positions = [
    section.index("先按 `skills/_shared/lark-writeback.md`"),
    section.index("verify-sync"),
    section.index("APPLIED_CONTEXT_PACK"),
    section.index('build-contract.py" add-delta'),
    section.index("checkpoint reviewed spec authority"),
]
assert positions == sorted(positions), positions
PY
  then
    _fail "active-build review order must be sync/verify -> pack -> delta -> authority checkpoint"
    return
  fi
  assert_file_contains "$SKILL" "lark_published_source_hash.*T" "checkpoint should verify the final published target" || return
  assert_file_contains "$DESIGN_SKILL" "lifecycle-handoff.md" "design should honor review handoff" || return
  assert_file_contains "$BUILD_SKILL" "lifecycle-handoff.md" "build should honor review handoff" || return
  assert_file_contains "$QUICK_FIX_SKILL" "lifecycle-handoff.md" "quick-fix should honor review handoff" || return
  assert_file_contains "$SPEC_SKILL" "lifecycle-handoff.md" "spec-writing should output review target" || return
  if grep -R -n '/Users/' "$REPO_ROOT/skills/lark-review" "$COLLECTOR" >/dev/null; then
    _fail "lark-review assets must not contain machine-bound paths"
    return
  fi
  assert_file_contains "$SKILL" "没有.*--force" "skill should explicitly forbid force bypasses" || return
  if grep -E -n 'add_argument\([^)]*--force' "$COLLECTOR" >/dev/null; then
    _fail "lark-review CLI must not expose a force option"
    return
  fi
  pass_test
}

test_review_target_binds_the_active_worktree() {
  start_test "lark-review: 目标模块绑定 active build 的真实 worktree"
  local main="$BASE/resolve-target-main"
  local worktree="$BASE/resolve-target-active"
  local second="$BASE/resolve-target-second"
  local out

  make_git_module_review_repo "$main"
  git -C "$main" worktree add -q -b build-review-active "$worktree" main
  python3 - "$worktree/docs/modules/example/.work-meta.json" \
    work-review-active build-review-active <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "id": sys.argv[2],
    "name": "example review",
    "branch": sys.argv[3],
    "stage": 2,
    "status": "active",
    "lifecycle_state": "iterating",
    "build": {
        "branch": sys.argv[3],
        "lifecycle_state": "iterating",
    },
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

  if ! out=$(python3 "$COLLECTOR" resolve-target \
    "$main/docs/modules/example/spec.md" 2>&1); then
    _fail "active worktree target resolution failed: $out"
    return
  elif ! python3 - "$out" "$main" "$worktree" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(sys.argv[1])
main = str(Path(sys.argv[2]).resolve())
worktree = Path(sys.argv[3]).resolve()
assert result["markdown_path"] == str(worktree / "docs/modules/example/spec.md")
assert result["repo_root"] == str(worktree)
assert result["main_repo_root"] == main
assert result["active_work_dir"] == str(worktree / "docs/modules/example")
assert result["active_work_id"] == "work-review-active"
assert result["lifecycle_state"] == "iterating"
PY
  then
    _fail "resolved target did not bind the active worktree: $out"
    return
  fi

  git -C "$main" worktree add -q -b build-review-second "$second" main
  python3 - "$second/docs/modules/example/.work-meta.json" \
    work-review-second build-review-second <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "id": sys.argv[2],
    "name": "duplicate example review",
    "branch": sys.argv[3],
    "stage": 2,
    "status": "active",
    "lifecycle_state": "building",
    "build": {
        "branch": sys.argv[3],
        "lifecycle_state": "building",
    },
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  if out=$(python3 "$COLLECTOR" resolve-target \
    "$main/docs/modules/example/spec.md" 2>&1); then
    _fail "resolver must reject two active builds for one review target"
    return
  elif ! echo "$out" | grep -q "命中多个 active build"; then
    _fail "ambiguous active target should fail explicitly: $out"
    return
  fi
  pass_test
}

test_collect_rejects_changes_during_comment_collection() {
  start_test "lark-review: 评论采集期间本地或飞书变化时不生成混杂批次"
  local remote_work="$BASE/collect-remote-race"
  mkdir -p "$remote_work/out" "$remote_work/state"
  make_review_doc "$remote_work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_REMOTE_CHANGES_AFTER_FETCH=1 \
    FAKE_REVIEW_STATE_DIR="$remote_work/state" \
    python3 "$COLLECTOR" collect "$remote_work/spec.md" \
    --output-dir "$remote_work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '飞书正文在评论采集期间变化' \
    || [ -e "$remote_work/out/review.json" ]; then
    _fail "remote collect race should fail before manifest: rc=$rc out=$out"
    return
  fi

  local local_work="$BASE/collect-local-race"
  mkdir -p "$local_work/out"
  make_review_doc "$local_work/spec.md"
  out=$(FAKE_REVIEW_MUTATE_LOCAL_PATH="$local_work/spec.md" \
    python3 "$COLLECTOR" collect "$local_work/spec.md" \
    --output-dir "$local_work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '本地 markdown 在评论采集期间变化' \
    || [ -e "$local_work/out/review.json" ] \
    || ! grep -q '^Concurrent local edit$' "$local_work/spec.md"; then
    _fail "local collect race should fail without overwriting: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_collect_requires_repository_root_before_side_effects() {
  start_test "lark-review: collect 在联网和建批前绑定 Git 仓根"
  local work="$BASE/collect-without-repo"
  mkdir -p "$work"
  make_review_doc "$work/spec.md"
  rmdir "$work/.git"

  local out rc
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" \
    --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] \
    || ! echo "$out" | grep -q '不在可识别的 Git 仓库' \
    || [ -e "$work/out" ]; then
    _fail "collect outside Git must fail before creating a batch: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_collects_three_way_body_and_paginated_comments() {
  start_test "lark-review: 三方正文、评论分页、回复分页与 block 定位"
  local work="$BASE/full"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  export FAKE_LARK_LOG="$work/lark.log"
  local out
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" 2>&1)
  local rc=$?
  unset FAKE_LARK_LOG
  if [ "$rc" -ne 0 ]; then
    _fail "collector failed: $out"
    return
  fi
  python3 - "$work/out/review.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["body"]["status"] == "remote_only", data["body"]
assert data["body"]["baseline_status"] == "revision"
assert data["body"]["common_ancestor_compatible"] is True
assert len(data["body"]["remote_source_hash"]) == 64
assert data["batch_id"]
assert set(data["artifacts"]) == {
    "baseline.md", "local.md", "remote.md", "remote-native.json"
}
assert data["body"]["target_base"] == "remote_native_snapshot"
assert data["performance"]["document_full_fetches"] == 1
assert data["performance"]["document_snapshot_pairs"] == 1
assert data["performance"]["document_revision_fence_fetches"] == 1
assert data["performance"]["document_fetch_api_calls"] == 4
assert data["document"]["published_revision_id"] == 7
assert data["document"]["current_revision_id"] == 9
comments = data["comments"]
assert comments["count"] == 2, comments
assert comments["interaction_count"] == 3, comments
assert comments["reply_count"] == 1, comments
assert comments["new_or_updated_count"] == 2, comments
first, second = comments["items"]
assert first["location"]["accuracy"] == "relation_exact", first
assert first["location"]["block_id"] == "b-rule", first
assert first["replies"][0]["text"] == "Use new rule", first
assert second["location"]["accuracy"] == "quote_ambiguous", second
assert len(second["replies"]) == 2, second
assert second["replies"][1]["text"] == "Second reply", second
PY
  if [ "$?" -ne 0 ]; then
    _fail "review.json assertions failed"
    return
  fi
  if ! grep -q -- '^-Old rule' "$work/out/remote-vs-baseline.diff" \
    || ! grep -q -- '^+New rule' "$work/out/remote-vs-baseline.diff"; then
    _fail "remote diff missing expected change"
    return
  fi
  if ! grep -q '"is_solved":false' "$work/lark.log" \
    || ! grep -q '"is_solved":true' "$work/lark.log" \
    || ! grep -q '"need_relation":true' "$work/lark.log" \
    || ! grep -q 'comments-next' "$work/lark.log" \
    || ! grep -q 'replies-next' "$work/lark.log"; then
    _fail "pagination or unresolved/relation params missing: $(cat "$work/lark.log")"
    return
  fi
  pass_test
}

test_checkpoint_is_separate_and_preserves_body() {
  start_test "lark-review: 完成后 checkpoint 单独写入且保留正文/基线"
  local work="$BASE/checkpoint"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  complete_controlled_c1 "$work" >/dev/null || { _fail "failed to complete c1"; return; }
  FAKE_REVIEW_SYNCED_REMOTE=1 \
  FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
  FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --reviewed-at '2026-08-04T12:00:00+08:00' >/dev/null
  if ! grep -q '^lark_reviewed_revision_id: 10$' "$work/spec.md" \
    || ! grep -q '^lark_reviewed_comment_at: 270$' "$work/spec.md" \
    || ! grep -q '^lark_reviewed_comment_ids: \["comment:c1"\]$' "$work/spec.md" \
    || ! grep -q '^lark_reviewed_at: 2026-08-04T12:00:00+08:00$' "$work/spec.md" \
    || ! grep -q '^lark_published_revision_id: 10$' "$work/spec.md" \
    || ! grep -q '^New rule$' "$work/spec.md" \
    || [ ! -f "$work/out/checkpoint.json" ]; then
    _fail "checkpoint fields/body incorrect: $(cat "$work/spec.md")"
    return
  fi
  local review_root="$work/.pm-workflow/context/lark-review"
  local scan_out
  mkdir -p "$review_root"
  mv "$work/out" "$review_root/batch.done"
  scan_out=$(python3 "$COLLECTOR" find-resumable "$work/spec.md" \
    --review-root "$review_root" 2>&1) || {
    _fail "checkpointed batch recovery scan failed: $scan_out"; return;
  }
  if ! python3 - "$scan_out" <<'PY'
import json, sys
value = json.loads(sys.argv[1])
assert value["status"] == "none"
assert value["skipped_checkpoint_count"] == 1
assert value["skipped_checkpoints"][0]["reason"] == "checkpointed"
PY
  then
    _fail "checkpointed batch was still reported as resumable: $scan_out"
    return
  fi
  pass_test
}

test_list_resumables_scans_main_and_attached_worktrees() {
  start_test "lark-review: 全局恢复扫描 attached worktree 并排除 handoff"
  local main="$BASE/list-resumables-main"
  local worktree="$BASE/list-resumables-linked"
  local main_batch="$main/.pm-workflow/context/lark-review/batch.handoff"
  local linked_batch="$worktree/.pm-workflow/context/lark-review/batch.active"
  local main_spec="$main/docs/modules/example/spec.md"
  local linked_spec="$worktree/docs/modules/example/spec.md"
  local out

  make_git_module_review_repo "$main"
  mkdir -p "$main_batch"
  python3 "$COLLECTOR" collect "$main_spec" --output-dir "$main_batch" >/dev/null || {
    _fail "failed to collect main handoff batch"; return;
  }
  python3 "$COLLECTOR" reconcile --manifest "$main_batch/review.json" >/dev/null || {
    _fail "failed to draft main handoff batch"; return;
  }
  python3 "$COLLECTOR" handoff --manifest "$main_batch/review.json" \
    --route proposal >/dev/null || {
    _fail "failed to mark main batch as handoff"; return;
  }

  git -C "$main" worktree add -q -b build-resumable "$worktree" main
  mkdir -p "$linked_batch"
  python3 "$COLLECTOR" collect "$linked_spec" --output-dir "$linked_batch" >/dev/null || {
    _fail "failed to collect linked worktree batch"; return;
  }
  python3 "$COLLECTOR" reconcile --manifest "$linked_batch/review.json" >/dev/null || {
    _fail "failed to draft linked worktree batch"; return;
  }

  out=$(python3 "$COLLECTOR" list-resumables "$main" 2>&1) || {
    _fail "global resumable scan failed: $out"; return;
  }
  if ! python3 - "$out" "$worktree" "$linked_batch" <<'PY'
import json, sys
from pathlib import Path

value = json.loads(sys.argv[1])
worktree = str(Path(sys.argv[2]).resolve())
batch = str(Path(sys.argv[3]).resolve())
assert value["status"] == "resumable_list"
assert value["read_only"] is True
assert value["count"] == 1
assert value["skipped_handoff_count"] == 1
item = value["batches"][0]
assert item["repo_root"] == worktree
assert item["batch_dir"] == batch
assert item["markdown_relative"] == "docs/modules/example/spec.md"
assert item["state"] == "draft"
PY
  then
    _fail "global resumable list did not preserve worktree identity: $out"
    return
  fi
  pass_test
}

test_checkpoint_requires_published_target_and_resolved_comments() {
  start_test "lark-review: checkpoint 前必须已发布 T 且完成本批评论"
  local work="$BASE/checkpoint-gates"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  seal_controlled_review "$work" || { _fail "failed to seal review batch"; return; }
  python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" >/dev/null

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '发布基线尚未指向本批目标 T' \
    || grep -q '^lark_reviewed_revision_id:' "$work/spec.md"; then
    _fail "checkpoint should reject an unpublished T: rc=$rc out=$out"
    return
  fi

  refresh_review_baseline "$work" || { _fail "failed to refresh baseline"; return; }
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'comment-actions.json' \
    || grep -q '^lark_reviewed_revision_id:' "$work/spec.md"; then
    _fail "checkpoint should reject comments without controlled receipts: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_checkpoint_rejects_remote_mismatch_and_new_unresolved_comment() {
  start_test "lark-review: checkpoint 阻断远端版本漂移和受控回执后的新回复"
  local work="$BASE/checkpoint-races"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  complete_controlled_c1 "$work" >/dev/null || { _fail "failed to complete c1"; return; }

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_SYNCED_REVISION=11 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '飞书当前 revision 与本地发布基线不一致'; then
    _fail "checkpoint should reject remote revision drift: rc=$rc out=$out"
    return
  fi

  : > "$work/remote-state/pm-after-result-c1"
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '评论围栏与完成回执不一致' \
    || grep -q '^lark_reviewed_revision_id:' "$work/spec.md"; then
    _fail "checkpoint should reject a reply after the controlled receipt: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_checkpoint_rejects_reopened_out_of_batch_comment() {
  start_test "lark-review: PM 手工回复和解决不能冒充受控完成或被 reopen"
  local work="$BASE/checkpoint-manual-solve"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  : > "$work/remote-state/manual-reply-c1"
  : > "$work/remote-state/solved-c1"

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'comment-actions.json' \
    || grep -q '^lark_reviewed_revision_id:' "$work/spec.md"; then
    _fail "checkpoint should reject PM manual completion: rc=$rc out=$out"
    return
  fi
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" reopen "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'comment-actions.json' \
    || [ -e "$work/remote-state/reopened-c1" ]; then
    _fail "reopen should reject PM manual completion: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_checkpoint_rejects_solved_out_of_batch_comment() {
  start_test "lark-review: 评论写入和最终回读失败保留可恢复中间回执"
  local work="$BASE/comment-action-partial"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_PATCH_FAIL=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'solve_requested'; then
    _fail "patch failure should leave solve_requested: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["actions"][0]["status"] == "solve_requested"
assert data["actions"][0]["reply"]["reply_id"] == "r-result-c1"
PY
  then
    _fail "partial action receipt was not recoverable"
    return
  fi
  complete_controlled_c1 "$work" >/dev/null || {
    _fail "complete-comment failed to recover solve_requested"; return;
  }

  local read_work="$BASE/comment-action-read-failure"
  prepare_controlled_review "$read_work" || { _fail "failed to prepare read failure review"; return; }
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_FINAL_READ_FAIL=1 \
    FAKE_REVIEW_STATE_DIR="$read_work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$read_work/out/review.json" \
      --plan "$read_work/out/apply-plan.json" \
      --comment-id c1 --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '回读失败'; then
    _fail "final read failure should fail closed: rc=$rc out=$out"
    return
  fi
  complete_controlled_c1 "$read_work" >/dev/null || {
    _fail "complete-comment failed to recover after final read failure"; return;
  }
  if ! python3 - "$read_work/out/comment-actions.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["actions"][0]["status"] == "completed"
PY
  then
    _fail "final read recovery did not complete the receipt"
    return
  fi
  pass_test
}

test_checkpoint_binds_system_result_reply() {
  start_test "lark-review: complete-comment 生成绑定批次和远端身份的受控回执"
  local work="$BASE/checkpoint-result-reply"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }

  local out rc
  out=$(python3 "$COLLECTOR" checkpoint "$work/spec.md" \
    --manifest "$work/out/review.json" --plan "$work/out/apply-plan.json" \
    --result-reply 'c1=r-result' 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'unrecognized arguments'; then
    _fail "checkpoint must remove caller-supplied reply IDs: rc=$rc out=$out"
    return
  fi
  out=$(python3 "$COLLECTOR" reopen "$work/spec.md" \
    --manifest "$work/out/review.json" --plan "$work/out/apply-plan.json" \
    --comment-id c1 --solver-author ou-shared 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'unrecognized arguments'; then
    _fail "reopen must remove caller-supplied solver identity: rc=$rc out=$out"
    return
  fi
  out=$(complete_controlled_c1 "$work" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"status": "completed"'; then
    _fail "controlled completion failed: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" "$work/out/apply-plan.json" <<'PY'
import json, sys
actions = json.load(open(sys.argv[1], encoding="utf-8"))
plan = json.load(open(sys.argv[2], encoding="utf-8"))
action = actions["actions"][0]
assert actions["batch_id"] == plan["batch_id"]
assert actions["plan"]["ready_token"] == plan["ready_token"]
assert action["status"] == "completed"
assert action["reply"]["reply_id"] == "r-result-c1"
assert action["reply"]["user_id"] == "ou-shared"
assert action["solver_user_id"] == "ou-shared"
assert action["solved_time"] == 270
PY
  then
    _fail "controlled receipt is not bound to batch/plan/reply/solver"
    return
  fi
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --reviewed-at '2026-08-04T12:40:00+08:00' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^lark_reviewed_revision_id: 10$' "$work/spec.md"; then
    _fail "checkpoint should accept the controlled receipt: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_complete_comment_accepts_sparse_create_response() {
  start_test "lark-review: 创建回复响应缺正文时绑定实际发送文本 hash"
  local work="$BASE/sparse-reply-create"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_REPLY_CREATE_NO_CONTENT=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 \
      --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"status": "completed"'; then
    _fail "sparse reply create response should complete: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import hashlib, json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
reply = data["actions"][0]["reply"]
assert reply["reply_id"] == "r-result-c1"
assert reply["text_sha256"] == hashlib.sha256(b"Updated and verified").hexdigest()
PY
  then
    _fail "sparse create response did not preserve the sent result hash"
    return
  fi
  pass_test
}

test_complete_comments_batches_full_scans_and_checkpoint_reuses_verification() {
  start_test "lark-review: 整批评论只在首尾全量扫描且 checkpoint 复用格式验收"
  local work="$BASE/comment-batch"
  prepare_batch_review "$work" || { _fail "failed to prepare batch review"; return; }
  : > "$work/lark.log"

  local out rc
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comments \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"execution_mode": "batch"'; then
    _fail "batch completion failed: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["execution_mode"] == "batch"
assert [item["comment_id"] for item in value["actions"]] == ["c1", "c2"]
assert all(item["status"] == "completed" for item in value["actions"])
assert all(item["solved_time"] is None for item in value["actions"])
assert all(item["solve_evidence_mode"] == "write_ack_and_stable_readback" for item in value["actions"])
perf = value["performance"]
assert perf["attempt_count"] == 1, perf
assert perf["comment_full_scans"] == 4, perf
assert perf["comment_list_api_calls"] == 10, perf
assert perf["reply_write_api_calls"] == 2, perf
assert perf["solve_write_api_calls"] == 2, perf
PY
  then
    _fail "batch receipt or performance counters are incorrect"
    return
  fi
  local list_calls
  list_calls=$(grep -c 'file.comments list' "$work/lark.log")
  if [ "$list_calls" -ne 10 ]; then
    _fail "batch should use 10 list page calls for two stable boundary scans, got $list_calls"
    return
  fi

  : > "$work/lark.log"
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --reviewed-at '2026-08-07T12:00:00+08:00' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || grep -q -- '--doc-format xml' "$work/lark.log"; then
    _fail "checkpoint should reuse native verification without full XML: rc=$rc out=$out"
    return
  fi
  if [ "$(grep -c 'file.comments list' "$work/lark.log")" -ne 4 ] \
    || [ "$(grep -c 'docs +fetch' "$work/lark.log")" -ne 1 ]; then
    _fail "checkpoint should use one stable comment scan and one markdown fence: $(cat "$work/lark.log")"
    return
  fi
  pass_test
}

test_reply_only_waits_for_pm_and_verifies_manual_solve() {
  start_test "lark-review: reply-only 受控回复后由 PM 手工解决并回读"
  local work="$BASE/comment-reply-only"
  prepare_batch_review "$work" || { _fail "failed to prepare reply-only review"; return; }
  : > "$work/lark.log"

  local out rc
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comments --reply-only \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"status": "replied_pending_pm"' \
    || grep -q 'file.comments patch' "$work/lark.log" \
    || [ "$(grep -c 'file.comment.replys create' "$work/lark.log")" -ne 2 ]; then
    _fail "reply-only should create replies without solving: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["schema_version"] == 3
assert value["execution_mode"] == "reply_only"
assert all(item["status"] == "replied_pending_pm" for item in value["actions"])
assert all(item["completion_status"] == "replied_pending_pm" for item in value["actions"])
assert value["performance"]["solve_write_api_calls"] == 0
PY
  then
    _fail "reply-only journal is incomplete"
    return
  fi
  out=$(python3 "$COLLECTOR" receipt \
    --manifest "$work/out/review.json" \
    --plan "$work/out/apply-plan.json" \
    --implementation-result no_change 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] \
    || ! echo "$out" | grep -q '等待你手工解决 2 条' \
    || ! echo "$out" | grep -q '需要你处理：请在飞书手工解决 2 条' \
    || echo "$out" | grep -qE 'revision|hash|checkpoint|DONE_WITH_CONCERNS'; then
    _fail "reply-only PM receipt should expose only the pending business action: rc=$rc out=$out"
    return
  fi

  : > "$work/remote-state/pm-solved-c1"
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" verify-comments \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"status": "waiting_for_pm"'; then
    _fail "partial PM solve should remain waiting: rc=$rc out=$out"
    return
  fi
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    _fail "checkpoint should wait for every PM-owned solve"
    return
  fi

  : > "$work/remote-state/pm-solved-c2"
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" verify-comments \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"status": "verified"'; then
    _fail "all PM solves should verify: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert all(item["status"] == "completed" for item in value["actions"])
assert all(item["completion_status"] == "solved_by_pm_verified" for item in value["actions"])
assert all(item["solver_user_id"] == "ou-pm" for item in value["actions"])
assert all(item["solve_write_ack_sha256"] is None for item in value["actions"])
PY
  then
    _fail "PM solve evidence was not persisted"
    return
  fi
  out=$(python3 "$COLLECTOR" receipt \
    --manifest "$work/out/review.json" \
    --plan "$work/out/apply-plan.json" \
    --implementation-result no_change 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] \
    || ! echo "$out" | grep -q '评论：已完成 2 条，等待你手工解决 0 条' \
    || ! echo "$out" | grep -q '产品结果：本轮无需改实现' \
    || ! echo "$out" | grep -q '需要你处理：无需处理'; then
    _fail "verified PM receipt should report a completed business result: rc=$rc out=$out"
    return
  fi
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --reviewed-at '2026-08-10T12:00:00+08:00' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "checkpoint should accept verified PM solves: rc=$rc out=$out"
    return
  fi
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" reopen "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || [ -e "$work/remote-state/reopened-c1" ]; then
    _fail "PM-owned solves must never be reopened by PMAI: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_complete_comments_recovers_partial_batch_without_duplicate_replies() {
  start_test "lark-review: 整批评论中断后按 journal 恢复且不重复回复"
  local work="$BASE/comment-batch-recovery"
  prepare_batch_review "$work" || { _fail "failed to prepare batch review"; return; }
  : > "$work/lark.log"

  local out rc
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_PATCH_FAIL=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comments \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'journal 已保留'; then
    _fail "batch patch failure should retain journal: rc=$rc out=$out"
    return
  fi
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comments \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "batch recovery failed: rc=$rc out=$out"
    return
  fi
  if [ "$(grep -c 'file.comment.replys create' "$work/lark.log")" -ne 2 ]; then
    _fail "batch recovery duplicated a result reply: $(cat "$work/lark.log")"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["performance"]["attempt_count"] == 2
assert all(item["status"] == "completed" for item in value["actions"])
PY
  then
    _fail "recovered batch receipt is incomplete"
    return
  fi
  pass_test
}

test_batch_final_read_failure_can_recover_and_reopen() {
  start_test "lark-review: 批量 solve 已确认但最终回读中断后仍可受控 reopen"
  local work="$BASE/comment-batch-reopen-recovery"
  prepare_batch_review "$work" || { _fail "failed to prepare batch review"; return; }
  : > "$work/lark.log"

  local out rc
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_FINAL_READ_FAIL=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comments \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'journal 已保留'; then
    _fail "batch final read failure should retain journal: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert all(item["status"] == "solve_requested" for item in value["actions"])
assert all(item["solve_write_ack_sha256"] for item in value["actions"])
PY
  then
    _fail "failed batch did not retain solve write acknowledgements"
    return
  fi

  : > "$work/remote-state/pm-after-result-c1"
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" reopen "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id 'c1' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"status": "reopened"'; then
    _fail "solve_requested batch action could not recover and reopen: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
actions = {item["comment_id"]: item for item in value["actions"]}
assert actions["c1"]["status"] == "reopened"
assert actions["c2"]["status"] == "completed"
assert actions["c1"]["solved_time"] is None
assert actions["c2"]["solved_time"] is None
assert actions["c1"]["solve_evidence_mode"] == "write_ack_and_stable_readback"
assert actions["c2"]["solve_evidence_mode"] == "write_ack_and_stable_readback"
PY
  then
    _fail "reopen recovery did not persist controlled completion evidence"
    return
  fi
  if [ "$(grep -c 'file.comment.replys create' "$work/lark.log")" -ne 2 ]; then
    _fail "reopen recovery duplicated result replies: $(cat "$work/lark.log")"
    return
  fi
  pass_test
}

test_checkpoint_failure_can_recollect_solved_comment() {
  start_test "lark-review: 结果回复竞态失败后先受控 reopen 再重新采集"
  local work="$BASE/checkpoint-solved-recovery"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  complete_controlled_c1 "$work" >/dev/null || { _fail "failed to complete c1"; return; }
  mkdir -p "$work/recovery"
  : > "$work/remote-state/pm-after-result-c1"

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '评论围栏与完成回执不一致' \
    || grep -q '^lark_reviewed_revision_id:' "$work/spec.md"; then
    _fail "checkpoint should reject PM feedback racing the result reply: rc=$rc out=$out"
    return
  fi

  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" reopen "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id 'c1' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"status": "reopened"' \
    || [ ! -e "$work/remote-state/reopened-c1" ]; then
    _fail "failed to reopen the system-solved batch comment: rc=$rc out=$out"
    return
  fi

  FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" collect "$work/spec.md" \
      --output-dir "$work/recovery" --include-solved >/dev/null || {
        _fail "failed to recollect solved comments after checkpoint rejection"
        return
      }
  python3 "$COLLECTOR" reconcile --manifest "$work/recovery/review.json" >/dev/null
  if ! python3 - "$work/recovery/review.json" "$work/recovery/resolutions.json" <<'PY'
import json, sys
review = json.load(open(sys.argv[1], encoding="utf-8"))
resolutions = json.load(open(sys.argv[2], encoding="utf-8"))
comment = next(item for item in review["comments"]["items"] if item["comment_id"] == "c1")
assert comment["is_solved"] is False
assert any(reply["text"] == "Actually use B" for reply in comment["replies"])
assert "c1" in {item["comment_id"] for item in resolutions["comments"]}
PY
  then
    _fail "solved comment or PM reply missing from recovery batch"
    return
  fi
  pass_test
}

test_checkpoint_preserves_deferred_comments() {
  start_test "lark-review: deferred 评论必须保持未解决才可 checkpoint"
  local work="$BASE/checkpoint-deferred"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  complete_controlled_c1 "$work" >/dev/null || { _fail "failed to complete c1"; return; }

  local out rc
  : > "$work/remote-state/solved-c2"
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '评论围栏与完成回执不一致'; then
    _fail "checkpoint should reject a solved deferred comment: rc=$rc out=$out"
    return
  fi

  local clean="$BASE/checkpoint-deferred-open"
  prepare_controlled_review "$clean" || { _fail "failed to prepare open deferred review"; return; }
  complete_controlled_c1 "$clean" >/dev/null || { _fail "failed to complete clean c1"; return; }
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$clean/remote-state" \
    python3 "$COLLECTOR" checkpoint "$clean/spec.md" \
      --manifest "$clean/out/review.json" \
      --plan "$clean/out/apply-plan.json" \
      --reviewed-at '2026-08-04T12:30:00+08:00' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^lark_reviewed_revision_id: 10$' "$clean/spec.md"; then
    _fail "checkpoint should accept an unchanged open deferred comment: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_content_deleted_can_be_superseded_instead_of_deferred() {
  start_test "lark-review: content_deleted 旧内容被替代时可回复收口"
  PYTHONDONTWRITEBYTECODE=1 python3 - "$COLLECTOR" <<'PY'
import importlib.util
import sys
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("lark_review_superseded_test", path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = module
spec.loader.exec_module(module)
manifest = {
    "comments": {
        "items": [{
            "comment_id": "deleted-1",
            "update_time": 20,
            "new_since_checkpoint": True,
            "is_solved": False,
            "is_whole": False,
            "location": {"accuracy": "content_deleted"},
        }],
        "included_solved": False,
    }
}
records, template, unresolved = module._comment_reconciliation(
    manifest,
    {
        "deleted-1": {
            "decision": "superseded",
            "authority": "pm_confirmed",
            "reason": "旧内容已被当前确认方案替代",
            "result_text": "旧内容已由当前方案替代，文档已更新。",
        }
    },
    sealing=True,
)
assert unresolved == 0
assert records[0]["location_accuracy"] == "content_deleted"
assert records[0]["decision"] == "superseded"
assert records[0]["result_text"]
assert template[0]["decision"] == "superseded"
PY
  if [ "$?" -ne 0 ]; then
    _fail "content_deleted should allow an evidenced superseded disposition"
    return
  fi
  pass_test
}

test_same_second_comment_uses_create_time_and_id_boundary() {
  start_test "lark-review: 同秒新评论用 create_time + ID 水位识别"
  local work="$BASE/same-second"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  FAKE_REVIEW_CREATE_ONLY=1 python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 - "$work/out/review.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["comments"]["new_or_updated_count"] == 1, data["comments"]
assert data["comments"]["max_update_time"] == 150
assert data["comments"]["max_update_ids"] == [
    "comment:c-same-second", "reply:r-same-second"
]
PY
  if [ "$?" -ne 0 ]; then
    _fail "same-second cursor assertions failed"
    return
  fi
  pass_test
}

test_checkpoint_cursor_does_not_preconsume_comment_id() {
  start_test "lark-review: reply 水位不提前消费同秒 comment ID"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$COLLECTOR" <<'PY'
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("lark_review_comment_cursor_test", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

public_snapshot = [{
    "comment_id": "c1",
    "comment_event_time": 10,
    "update_time": 100,
    "replies": [{"reply_id": "r1", "create_time": 10, "update_time": 100}],
}]
checkpoint_time, checkpoint_ids = module._comment_cursor_from_snapshot(public_snapshot)
assert checkpoint_time == 100
assert checkpoint_ids == ["reply:r1"], checkpoint_ids

later_raw = [{
    "comment_id": "c1",
    "_comment_event_time": 100,
    "update_time": 100,
    "replies": [{"reply_id": "r1", "create_time": 10, "update_time": 100}],
}]
marked, _, ids = module._with_comment_cursor(
    later_raw,
    reviewed_comment_at=checkpoint_time,
    reviewed_comment_ids=set(checkpoint_ids),
)
assert marked[0]["new_since_checkpoint"] is True, marked
assert marked[0]["comment_event_time"] == 100, marked
assert ids == ["comment:c1", "reply:r1"], ids
PY
  then
    pass_test
  else
    _fail "same-second comment ID was consumed by an earlier reply-only checkpoint"
  fi
}

test_baseline_refresh_is_atomic() {
  start_test "lark-review: 精细同步后原子刷新 revision 与正文 hash"
  local work="$BASE/baseline"
  mkdir -p "$work"
  make_review_doc "$work/spec.md"
  local old_hash new_hash expected_hash
  old_hash=$(sed -n 's/^lark_published_source_hash: //p' "$work/spec.md")
  printf '\nLocal final.\n' >> "$work/spec.md"
  expected_hash=$(PYTHONPATH="$REPO_ROOT/scripts" python3 - "$work/spec.md" <<'PY'
import sys
from pathlib import Path
from _lib.lark_adapter import markdown_body_hash, parse_frontmatter
_, body = parse_frontmatter(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(markdown_body_hash(body))
PY
)
  python3 "$COLLECTOR" baseline "$work/spec.md" --revision-id 9 \
    --expected-source-hash "$expected_hash" >/dev/null
  new_hash=$(sed -n 's/^lark_published_source_hash: //p' "$work/spec.md")
  if ! grep -q '^lark_published_revision_id: 9$' "$work/spec.md" \
    || [ "$old_hash" = "$new_hash" ] || [ "$new_hash" != "$expected_hash" ]; then
    _fail "baseline refresh incorrect: old=$old_hash new=$new_hash expected=$expected_hash"
    return
  fi
  pass_test
}

test_reconcile_seals_target_before_apply() {
  start_test "lark-review: B/L/R 先归位为独立 T，seal 后才允许写规格"
  local work="$BASE/reconcile"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/apply-plan.json" "$work/out/resolutions.json" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
resolutions = json.load(open(sys.argv[2], encoding="utf-8"))
assert plan["state"] == "draft", plan
assert plan["unresolved_count"] == 3, plan
assert len(resolutions["body"]) == 1
assert resolutions["body"][0]["decision"] == "needs_pm"
assert resolutions["body"][0]["authority"] == "pending"
assert all(item["decision"] == "pending" for item in resolutions["comments"])
PY
  if [ "$?" -ne 0 ] || ! grep -q '^New rule$' "$work/out/target.md" \
    || ! grep -q '^Old rule$' "$work/spec.md"; then
    _fail "draft target or source isolation incorrect"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["comments"]:
    item.update(decision="no_spec_change", authority="existing_spec", reason="无需改规格", result_text="Updated and verified")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json"
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal >/dev/null
  python3 "$COLLECTOR" apply "$work/spec.md" --plan "$work/out/apply-plan.json" >/dev/null
  local second
  second=$(python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  local stale rc
  stale=$(FAKE_REVIEW_REMOTE_CHANGED=1 python3 "$COLLECTOR" apply \
    "$work/spec.md" --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if ! grep -q '^New rule$' "$work/spec.md" \
    || ! echo "$second" | grep -q 'already_applied' \
    || [ "$rc" -eq 0 ] \
    || ! echo "$stale" | grep -q '飞书正文 revision' \
    || ! grep -q '^lark_doc_id: docR$' "$work/spec.md"; then
    _fail "sealed target apply/idempotency fence failed: second=$second stale=$stale"
    return
  fi
  pass_test
}

test_decision_routing_is_explicit_and_selective() {
  start_test "lark-review: 每个飞书变化显式路由 decision 且只沉淀产品规则"
  local work="$BASE/decision-routing"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["comments"]:
    item.update(
        decision="no_spec_change",
        authority="existing_spec",
        reason="不改变规格规则",
        result_text="Updated and verified",
    )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  confirm_remote_body "$work/out/resolutions.json"
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '尚未完成 decision 归档路由'; then
    _fail "pending decision routing must block seal: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["decision_routing"]:
    if item["source_type"] == "body":
        item.update(
            outcome="supersede",
            target_path="docs/modules/example/decisions.md",
            decision_id="D-NEW-RULE",
            supersedes=["D-OLD-RULE"],
            summary="飞书确认采用新业务规则",
            reason="正文修改改变稳定业务规则",
        )
    else:
        item.update(
            outcome="not_required",
            target_path="",
            decision_id="",
            supersedes=[],
            summary="",
            reason="评论仅解释现有规则",
        )
data["consistency"] = {
    "status": "checked",
    "target_sha256": __import__("hashlib").sha256(
        open(path.replace("resolutions.json", "target.md"), "rb").read()
    ).hexdigest(),
    "source_hashes": [],
    "candidate_decision_ids": [
        "docs/modules/example/decisions.md#D-NEW-RULE"
    ],
    "reviewed_active_decision_ids": [],
    "checks": [],
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "valid selective decision routing should seal: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/apply-plan.json" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
assert plan["decision_write_count"] == 1
route = next(item for item in plan["decision_routing"] if item["outcome"] == "supersede")
assert route["decision_id"] == "D-NEW-RULE"
assert route["supersedes"] == ["D-OLD-RULE"]
PY
  [ "$?" -eq 0 ] || { _fail "decision routing missing from ready plan"; return; }

  mkdir -p "$work/outside-module"
  rmdir "$work/docs/modules/example"
  ln -s "$work/outside-module" "$work/docs/modules/example"
  out=$(python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'symlink 组件' \
    || ! grep -q '^Old rule$' "$work/spec.md"; then
    _fail "apply must recheck a decision target replaced by symlink: rc=$rc out=$out"
    return
  fi
  rm "$work/docs/modules/example"
  mkdir -p "$work/docs/modules/example"

  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
route = next(item for item in data["decision_routing"] if item["outcome"] == "supersede")
route["target_path"] = "docs/decisions/decisions.md"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '只允许仓内'; then
    _fail "decision routing must reject targets outside module decisions: rc=$rc out=$out"
    return
  fi

  ln -s "$work/outside-module" "$work/docs/modules/linked"
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
route = next(item for item in data["decision_routing"] if item["outcome"] == "supersede")
route["target_path"] = "docs/modules/linked/decisions.md"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'symlink 组件'; then
    _fail "decision routing must reject symlink path components: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_cross_decision_conflict_and_stale_receipt_block_seal() {
  start_test "lark-review: seal 阻断跨决定冲突和过期一致性回执"
  local work="$BASE/decision-consistency"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  cat > "$work/PRODUCT-RULES.md" <<'EOF'
# 项目级规则

## 规则清单

<!--
### <一句话标题>
- 规则：模板不能成为现行规则。
-->

### 账号删除前必须清理有效会话

- 规则：账号仍有有效会话时不能删除。
EOF
  printf '%s\n' \
    '# 租户决定' \
    '' \
    '## D16 移出后保留租户身份' \
    '' \
    '成员移出租户后，仍保留租户身份。' \
    > "$work/docs/modules/example/decisions.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/resolutions.json" "$work/out/target.md" \
    "$work/PRODUCT-RULES.md" "$work/docs/modules/example/decisions.md" <<'PY'
import hashlib, json, sys
from pathlib import Path

resolution_path, target_path, product_rules_path, decisions_path = map(Path, sys.argv[1:])
data = json.loads(resolution_path.read_text(encoding="utf-8"))
for item in data["body"]:
    item.update(
        decision="remote",
        authority="pm_confirmed",
        reason="PM 本轮确认采用飞书正文增量",
    )
for item in data["comments"]:
    item.update(
        decision="no_spec_change",
        authority="existing_spec",
        reason="评论不改变规格规则",
        result_text="Updated and verified",
    )
for item in data["decision_routing"]:
    if item["source_type"] == "body":
        item.update(
            outcome="create",
            target_path="docs/modules/example/decisions.md",
            decision_id="D30",
            supersedes=[],
            summary="没有租户身份才能删除账号",
            reason="正文修改新增账号删除资格规则",
        )
    else:
        item.update(
            outcome="not_required",
            target_path="",
            decision_id="",
            supersedes=[],
            summary="",
            reason="评论仅解释现有规则",
        )
candidate = "docs/modules/example/decisions.md#D30"
product_rule = "PRODUCT-RULES.md#" + hashlib.sha256(
    "PRODUCT-RULES.md:账号删除前必须清理有效会话".encode("utf-8")
).hexdigest()[:12]
module_decision = "docs/modules/example/decisions.md#D16"
data["consistency"] = {
    "status": "needs_pm",
    "target_sha256": hashlib.sha256(target_path.read_bytes()).hexdigest(),
    "source_hashes": [
        {
            "path": "PRODUCT-RULES.md",
            "sha256": hashlib.sha256(product_rules_path.read_bytes()).hexdigest(),
        },
        {
            "path": "docs/modules/example/decisions.md",
            "sha256": hashlib.sha256(decisions_path.read_bytes()).hexdigest(),
        },
    ],
    "candidate_decision_ids": [candidate],
    "reviewed_active_decision_ids": sorted([product_rule, module_decision]),
    "checks": [
        {
            "candidate_decision_id": candidate,
            "active_decision_id": product_rule,
            "status": "compatible",
            "reason": "清理有效会话与租户身份条件可以同时成立",
        },
        {
            "candidate_decision_id": candidate,
            "active_decision_id": module_decision,
            "status": "needs_pm",
            "reason": "移出后仍有租户身份时，是否还能进入账号删除资格存在冲突",
        },
    ],
}
resolution_path.write_text(
    json.dumps(data, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '需要 PM 拍板'; then
    _fail "cross-decision conflict should block seal: rc=$rc out=$out"
    return
  fi

  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["consistency"]["status"] = "checked"
for item in data["consistency"]["checks"]:
    if item["status"] == "needs_pm":
        item.update(
            status="compatible",
            reason="测试中先标记为已核对，用于验证决定源变化会使回执过期",
        )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  printf '\n补充决定源内容。\n' >> "$work/docs/modules/example/decisions.md"
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '缺少绑定当前 target'; then
    _fail "stale decision-source receipt should block seal: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_v3_ready_plan_resumes_original_flow_but_not_new_reply_only() {
  start_test "lark-review: v3 ready 批次可恢复原流程但新评论模式要求 v4"
  local work="$BASE/v3-ready-resume"
  mkdir -p "$work/out" "$work/remote-state"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  seal_simple_review "$work" || { _fail "failed to seal source v4 batch"; return; }
  python3 - "$work/out/resolutions.json" "$work/out/apply-plan.json" <<'PY'
import hashlib, json, sys
from pathlib import Path

resolutions_path, plan_path = map(Path, sys.argv[1:])
resolutions = json.loads(resolutions_path.read_text(encoding="utf-8"))
resolutions["schema_version"] = 3
resolutions.pop("consistency", None)
resolutions_path.write_text(
    json.dumps(resolutions, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

plan = json.loads(plan_path.read_text(encoding="utf-8"))
plan["schema_version"] = 3
plan.pop("consistency", None)
plan["preview"].pop("pm_confirmation_required", None)
plan["resolutions"]["sha256"] = hashlib.sha256(
    resolutions_path.read_bytes()
).hexdigest()
plan.pop("ready_token", None)
encoded = json.dumps(plan, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
plan["ready_token"] = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
plan_path.write_text(
    json.dumps(plan, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
  python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" >/dev/null \
    || { _fail "v3 ready plan should remain applicable"; return; }
  refresh_review_baseline "$work" || { _fail "failed to refresh v3 baseline"; return; }
  FAKE_REVIEW_SYNCED_REMOTE=1 python3 "$COLLECTOR" verify-sync \
    --manifest "$work/out/review.json" \
    --plan "$work/out/apply-plan.json" >/dev/null \
    || { _fail "v3 ready plan should regenerate v2 remote verification"; return; }

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 python3 "$COLLECTOR" complete-comments --reply-only \
    --manifest "$work/out/review.json" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'v4 批次'; then
    _fail "reply-only must require a newly sealed v4 batch: rc=$rc out=$out"
    return
  fi

  FAKE_REVIEW_SYNCED_REMOTE=1 \
  FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
  FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comments \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" >/dev/null \
    || { _fail "v3 ready plan should keep original batch-completion behavior"; return; }
  python3 - "$work/out/remote-verification.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
assert data["schema_version"] == 2
data["schema_version"] = 1
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'remote-verification.json'; then
    _fail "v1 remote verification should require verify-sync again: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_nested_git_cannot_change_decision_write_boundary() {
  start_test "lark-review: 嵌套 .git 不能缩小 decision 写入边界"
  local work="$BASE/nested-git-boundary"
  local markdown="$work/docs/modules/current/spec.md"
  mkdir -p "$work/.git" "$work/docs/modules/current/.git" \
    "$work/docs/modules/current/docs/modules/other" "$work/outside"
  printf '# PMAI Agent Entry\n' > "$work/AGENTS.md"
  printf '# Product State\n' > "$work/PRODUCT-STATE.md"
  printf '# Spec\n' > "$markdown"
  ln -s "$work/outside" "$work/docs/modules/other"

  if PYTHONDONTWRITEBYTECODE=1 python3 - "$COLLECTOR" "$markdown" "$work" <<'PY'
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
markdown_path = Path(sys.argv[2]).resolve()
expected_root = Path(sys.argv[3]).resolve()
spec = importlib.util.spec_from_file_location("lark_review_nested_git_test", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

repo_root = module._repository_root(markdown_path)
assert repo_root == expected_root, (repo_root, expected_root)
try:
    module._decision_target_path(repo_root, "docs/modules/other/decisions.md")
except module.ReviewError as exc:
    assert "symlink" in str(exc)
else:
    raise AssertionError("outer-repo symlink boundary was not enforced")
PY
  then
    pass_test
  else
    _fail "nested .git changed the canonical decision target root"
  fi
}

test_manifest_markdown_parent_symlink_cannot_rebind_batch() {
  start_test "lark-review: collect 后父目录 symlink 不能把批次重绑到同仓文件"
  local work="$BASE/manifest-parent-symlink"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  mkdir -p "$work/docs/modules/a" "$work/docs/modules/b"
  mv "$work/spec.md" "$work/docs/modules/a/spec.md"
  cp "$work/docs/modules/a/spec.md" "$work/docs/modules/b/spec.md"

  python3 "$COLLECTOR" collect "$work/docs/modules/a/spec.md" \
    --output-dir "$work/out" >/dev/null
  rm "$work/docs/modules/a/spec.md"
  rmdir "$work/docs/modules/a"
  ln -s "$work/docs/modules/b" "$work/docs/modules/a"

  local out rc
  out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] \
    || ! echo "$out" | grep -q '路径组件不能是 symlink' \
    || [ -e "$work/out/resolutions.json" ]; then
    _fail "manifest markdown must not follow a replaced parent symlink: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_artifact_io_parent_rebind_never_touches_outside() {
  start_test "lark-review: 产物读写期间父目录改向时仓外零读写零误删"
  local work="$BASE/artifact-parent-rebind"
  mkdir -p "$work/artifacts" "$work/outside"
  printf 'inside-old\n' > "$work/artifacts/artifact.txt"
  printf 'outside-secret\n' > "$work/outside/artifact.txt"
  printf 'outside-sentinel\n' > "$work/outside/sentinel.txt"

  if PYTHONDONTWRITEBYTECODE=1 python3 - "$COLLECTOR" "$work" <<'PY'
import importlib.util
import os
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
work = Path(sys.argv[2]).resolve()
parent = work / "artifacts"
held_parent = work / "artifacts-held"
outside = work / "outside"

spec = importlib.util.spec_from_file_location("lark_review_artifact_race_test", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

from _lib import atomic_file

outside_before = {
    path.name: path.read_bytes()
    for path in outside.iterdir()
}
outside_artifact = (outside / "artifact.txt").stat()
outside_reads = 0
original_read = atomic_file.os.read


def guarded_read(fd: int, size: int) -> bytes:
    global outside_reads
    current = os.fstat(fd)
    if (current.st_dev, current.st_ino) == (
        outside_artifact.st_dev,
        outside_artifact.st_ino,
    ):
        outside_reads += 1
    return original_read(fd, size)


def restore_parent() -> None:
    if parent.is_symlink():
        parent.unlink()
    if held_parent.exists():
        held_parent.rename(parent)


def expect_rebind_failure(operation) -> None:
    original_snapshot = atomic_file._snapshot_at
    race_triggered = False

    def racing_snapshot(*args, **kwargs):
        nonlocal race_triggered
        result = original_snapshot(*args, **kwargs)
        if (
            Path(kwargs["display_path"]) == parent / "artifact.txt"
            and not race_triggered
        ):
            race_triggered = True
            parent.rename(held_parent)
            parent.symlink_to(outside, target_is_directory=True)
        return result

    atomic_file._snapshot_at = racing_snapshot
    try:
        try:
            operation()
        except module.ReviewError:
            pass
        else:
            raise AssertionError("parent rebind was accepted")
    finally:
        atomic_file._snapshot_at = original_snapshot
        restore_parent()


atomic_file.os.read = guarded_read
try:
    expect_rebind_failure(
        lambda: module._write_text(parent / "artifact.txt", "inside-new\n")
    )
    assert {
        path.name: path.read_bytes()
        for path in outside.iterdir()
    } == outside_before
    assert sorted(path.name for path in parent.iterdir()) == ["artifact.txt"]

    (parent / "artifact.txt").write_text("inside-old\n", encoding="utf-8")
    expect_rebind_failure(
        lambda: module._read_regular_text(
            parent / "artifact.txt",
            label="竞态产物",
        )
    )
finally:
    atomic_file.os.read = original_read
    restore_parent()

assert outside_reads == 0, outside_reads
assert {
    path.name: path.read_bytes()
    for path in outside.iterdir()
} == outside_before
assert sorted(path.name for path in parent.iterdir()) == ["artifact.txt"]
PY
  then
    pass_test
  else
    _fail "artifact parent rebind reached or modified the outside directory"
  fi
}

test_batch_entry_paths_never_pre_resolve_symlinks() {
  start_test "lark-review: 批次入口不把 symlink 预解析成仓外普通文件"
  local work="$BASE/batch-entry-symlink"
  mkdir -p "$work/batch" "$work/outside"
  printf '{"schema_version":3}\n' > "$work/outside/review.json"
  printf 'outside\n' > "$work/outside/artifact.txt"
  ln -s "$work/outside" "$work/linked"

  if PYTHONDONTWRITEBYTECODE=1 python3 - "$COLLECTOR" "$work" <<'PY'
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
work = Path(sys.argv[2]).resolve()
outside = work / "outside"
linked = work / "linked"

spec = importlib.util.spec_from_file_location("lark_review_entry_symlink_test", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

outside_before = {
    path.name: path.read_bytes()
    for path in outside.iterdir()
}
operations = (
    lambda: module._manifest_path(str(linked / "review.json")),
    lambda: module._read_regular_text(
        linked / "artifact.txt",
        label="symlink 产物",
    ),
    lambda: module._write_text(linked / "new-artifact.txt", "new\n"),
)
for operation in operations:
    try:
        operation()
    except module.ReviewError:
        pass
    else:
        raise AssertionError("symlink entry was accepted")

assert {
    path.name: path.read_bytes()
    for path in outside.iterdir()
} == outside_before
PY
  then
    pass_test
  else
    _fail "batch entry resolved a symlink into the outside directory"
  fi
}

test_repository_root_supports_worktree_git_file_and_requires_binding() {
  start_test "lark-review: .git 文件式仓根可识别且 reconcile 必须有 repo_root"
  local work="$BASE/worktree-root-compat"
  mkdir -p "$work/docs/modules/current"
  printf 'gitdir: /tmp/example-worktree-gitdir\n' > "$work/.git"
  printf '# PMAI Agent Entry\n' > "$work/AGENTS.md"
  printf '# Product State\n' > "$work/PRODUCT-STATE.md"
  printf '# Spec\n' > "$work/docs/modules/current/spec.md"

  if PYTHONDONTWRITEBYTECODE=1 python3 - "$COLLECTOR" \
    "$work/docs/modules/current/spec.md" "$work" <<'PY'
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
markdown_path = Path(sys.argv[2]).resolve()
expected_root = Path(sys.argv[3]).resolve()
spec = importlib.util.spec_from_file_location("lark_review_root_compat_test", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

assert module._repository_root(markdown_path) == expected_root
for schema_version in (2, 3):
    unbound = {
        "schema_version": schema_version,
        "markdown_path": str(markdown_path),
    }
    try:
        module._manifest_repository_root(unbound, markdown_path)
    except module.ReviewError as exc:
        assert "缺少 collect 时" in str(exc)
    else:
        raise AssertionError(
            f"schema v{schema_version} manifest without repo_root was accepted"
        )
PY
  then
    pass_test
  else
    _fail "worktree or legacy repository-root compatibility regressed"
  fi
}

test_repository_root_prefers_real_nested_worktree() {
  start_test "lark-review: 内嵌真实 worktree 使用当前 worktree 根而非外层主仓"
  local work="$BASE/real-nested-worktree"
  local main="$work/main"
  local nested="$main/.worktrees/review"
  mkdir -p "$main/docs/modules/current"
  git -C "$main" init -q -b main
  git -C "$main" config user.name "PMAI Test"
  git -C "$main" config user.email "pmai-test@example.com"
  printf '# PMAI Agent Entry\n' > "$main/AGENTS.md"
  printf '# Product State\n' > "$main/PRODUCT-STATE.md"
  printf '# Spec\n' > "$main/docs/modules/current/spec.md"
  git -C "$main" add AGENTS.md PRODUCT-STATE.md docs/modules/current/spec.md
  git -C "$main" commit -qm "fixture"
  git -C "$main" worktree add -q -b review "$nested"

  if PYTHONDONTWRITEBYTECODE=1 python3 - "$COLLECTOR" \
    "$nested/docs/modules/current/spec.md" "$nested" <<'PY'
import importlib.util
import sys
from pathlib import Path

module_path = Path(sys.argv[1])
markdown_path = Path(sys.argv[2]).resolve()
expected_root = Path(sys.argv[3]).resolve()
spec = importlib.util.spec_from_file_location("lark_review_real_worktree_test", module_path)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

assert module._repository_root(markdown_path) == expected_root
manifest = {
    "schema_version": 3,
    "markdown_path": str(markdown_path),
    "repo_root": str(expected_root),
}
assert module._manifest_repository_root(manifest, markdown_path) == expected_root
PY
  then
    pass_test
  else
    _fail "real nested worktree was not selected as the canonical repository root"
  fi
}

test_applied_comment_requires_changed_lifecycle_target() {
  start_test "lark-review: applied 评论必须实际编译进独立 T"
  local work="$BASE/applied-comment"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["comments"]:
    if item["comment_id"] == "c1":
        item.update(decision="applied", authority="pm_confirmed", reason="按评论补充完成条件", result_text="Updated and verified")
    else:
        item.update(decision="no_spec_change", authority="existing_spec", reason="无需额外修改", result_text="Updated and verified")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json"
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '评论标记 applied 时'; then
    _fail "applied comment should reject an unchanged reconciled T: rc=$rc out=$out"
    return
  fi

  printf '\nApplied completion rule.\n' >> "$work/out/target.md"
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["target"] = {
    "mode": "lifecycle_compiled",
    "authority": "pm_confirmed",
    "reason": "按已确认评论重新编译规格",
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^Applied completion rule\.$' "$work/out/target.md"; then
    _fail "changed lifecycle-compiled T should seal: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_apply_rejects_local_change_after_collect() {
  start_test "lark-review: apply 前本地正文变化时零写入"
  local work="$BASE/local-race"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  seal_simple_review "$work" || { _fail "failed to seal"; return; }
  printf '\nConcurrent local edit\n' >> "$work/spec.md"
  local out rc
  out=$(python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '本地规格正文已在 collect 后变化' \
    || ! grep -q '^Concurrent local edit$' "$work/spec.md"; then
    _fail "local CAS should reject without overwriting: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_apply_rejects_remote_or_comment_change() {
  start_test "lark-review: apply 前飞书正文或评论变化时零写入"
  local work="$BASE/remote-race"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  seal_simple_review "$work" || { _fail "failed to seal"; return; }
  local out rc
  out=$(FAKE_REVIEW_REMOTE_CHANGED=1 python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '飞书正文 revision' \
    || ! grep -q '^Old rule$' "$work/spec.md"; then
    _fail "remote revision fence should reject: rc=$rc out=$out"
    return
  fi
  out=$(FAKE_REVIEW_COMMENT_CHANGED=1 python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '飞书评论或回复' \
    || ! grep -q '^Old rule$' "$work/spec.md"; then
    _fail "comment fence should reject: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_already_applied_rechecks_local_cas() {
  start_test "lark-review: already_applied 返回前仍复核本地正文"
  local work="$BASE/already-applied-local-race"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  seal_simple_review "$work" || { _fail "failed to seal"; return; }
  python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" >/dev/null
  local out rc
  out=$(FAKE_REVIEW_MUTATE_LOCAL_PATH="$work/spec.md" \
    python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '本地规格在远端复核期间变化' \
    || ! grep -q '^Concurrent local edit$' "$work/spec.md"; then
    _fail "already_applied local CAS should fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_manual_merge_requires_compiled_target() {
  start_test "lark-review: 双边冲突标记 merged 时必须真正编译 T"
  local work="$BASE/manual-merge"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  sed -i.bak 's/^Old rule$/Local rule/' "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
assert data["body"][0]["decision"] == "pending", data["body"]
data["body"][0].update(
    decision="merged",
    authority="pm_confirmed",
    reason="PM 确认合并本地与飞书口径",
)
for item in data["comments"]:
    item.update(
        decision="no_spec_change",
        authority="existing_spec",
        reason="无需额外修改规格",
        result_text="Updated and verified",
    )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json"
  local out rc
  out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -Eq '冲突标记|target.md 与机械归位结果不一致'; then
    _fail "merged should not silently select local; rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
resolutions_path = sys.argv[1]
data = json.load(open(resolutions_path, encoding="utf-8"))
data["target"] = {
    "mode": "lifecycle_compiled",
    "authority": "pm_confirmed",
    "reason": "按已确认决定编译合并后的规格",
}
with open(resolutions_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  cp "$work/out/local.md" "$work/out/target.md"
  out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '不能退化为完整 L 或完整 R'; then
    _fail "manual merged target must not equal full L: rc=$rc out=$out"
    return
  fi
  cp "$work/out/remote.md" "$work/out/target.md"
  out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '不能退化为完整 L 或完整 R'; then
    _fail "manual merged target must not equal full R: rc=$rc out=$out"
    return
  fi
  printf '# Spec\n\nMerged rule\n' > "$work/out/target.md"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - \
    "$work/out/resolutions.json" "$work/out/remote.md" "$work/out/target.md" <<'PY'
import json, sys
from pathlib import Path
from _lib.lark_review_semantics import markdown_semantic_units

resolutions_path = Path(sys.argv[1])
remote_units = markdown_semantic_units(Path(sys.argv[2]).read_text(encoding="utf-8"))
target_units = markdown_semantic_units(Path(sys.argv[3]).read_text(encoding="utf-8"))
remote_rule = next(item for item in remote_units if item.text == "New rule")
target_rule = next(item for item in target_units if item.text == "Merged rule")
data = json.loads(resolutions_path.read_text(encoding="utf-8"))
data["remote_coverage"] = [{
    "remote_unit_id": remote_rule.unit_id,
    "disposition": "rewritten",
    "target_unit_ids": [target_rule.unit_id],
    "format_disposition": "preserved",
    "evidence": {
        "kind": "decision",
        "id": data["body"][0]["change_id"],
        "reason": "PM 已确认把双边规则合并为新口径",
    },
}]
resolutions_path.write_text(
    json.dumps(data, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
  out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^Merged rule$' "$work/out/target.md"; then
    _fail "compiled merged target should seal; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_incompatible_remote_only_starts_target_from_native_remote() {
  start_test "lark-review: remote-only 即使祖先格式不兼容也从飞书原生快照初始化 T"
  local work="$BASE/incompatible"
  mkdir -p "$work/out" "$work/.git"
  local body='# Spec

Old [rule]
'
  local hash
  hash=$(printf '%s' "$body" | PYTHONPATH="$REPO_ROOT/scripts" python3 -c 'import sys; from _lib.lark_adapter import markdown_body_hash; print(markdown_body_hash(sys.stdin.read()))')
  {
    echo '---'
    echo 'lark_doc_id: docR'
    echo 'lark_doc_url: https://example.feishu.cn/docx/docR'
    echo 'lark_published_revision_id: 7'
    echo "lark_published_source_hash: $hash"
    echo '---'
    echo
    printf '%s' "$body"
  } > "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/review.json" "$work/out/apply-plan.json" "$work/out/remote-native.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
plan = json.load(open(sys.argv[2], encoding="utf-8"))
native = json.load(open(sys.argv[3], encoding="utf-8"))
assert manifest["body"]["common_ancestor_compatible"] is False
assert plan["required_items"]["body"][0]["kind"] == "ancestor_incompatible"
assert plan["target_base"] == "remote_native_snapshot"
assert plan["target_base_revision"] == 9
assert manifest["artifacts"]["remote-native.json"]["sha256"]
assert native["document"]["revision_id"] == 9
assert 'align="left"' in native["document"]["content"]
assert '<b>New rule</b>' in native["document"]["content"]
assert native["document"]["reference_map"]["doc:spec"] == "docR"
PY
  if [ "$?" -ne 0 ] || ! grep -q '^New rule$' "$work/out/target.md" \
    || grep -Fq 'Old [rule]' "$work/out/target.md"; then
    _fail "incompatible remote-only target must start from current remote"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["body"][0].update(
    decision="remote", authority="pm_confirmed", reason="PM 确认采用飞书正文"
)
for item in data["comments"]:
    item.update(
        decision="no_spec_change", authority="existing_spec", reason="无需改规格",
        result_text="Updated and verified"
    )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json"
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^New rule$' "$work/out/target.md"; then
    _fail "PM-confirmed remote target should seal from R: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_unassigned_remote_rewrite_blocks_seal() {
  start_test "lark-review: R 到 T 的无依据改写阻止 seal"
  local work="$BASE/remote-coverage"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  sed -i.bak 's/^New rule$/Rewritten without evidence/' "$work/out/target.md"
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["target"].update(
    mode="lifecycle_compiled",
    authority="pm_confirmed",
    reason="测试远端覆盖门禁",
)
for item in data["comments"]:
    item.update(decision="no_spec_change", authority="existing_spec", reason="无需改规格", result_text="Updated and verified")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json"
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '远端语义.*未归位'; then
    _fail "unassigned remote rewrite must block seal: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/remote-coverage.json" <<'PY'
import json, sys
coverage = json.load(open(sys.argv[1], encoding="utf-8"))
assert coverage["summary"]["unassigned_count"] == 1, coverage
assert coverage["summary"]["remote_accounted_ratio"] < 1
assert coverage["summary"]["remote_format_accounted_ratio"] < 1
PY
  [ "$?" -eq 0 ] || { _fail "coverage ledger must expose the missing remote unit"; return; }
  pass_test
}

test_rewritten_remote_unit_requires_target() {
  start_test "lark-review: rewritten 必须绑定至少一个有效目标语义单元"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - <<'PY'
from _lib.lark_review_semantics import (
    build_native_snapshot,
    build_remote_coverage,
    markdown_semantic_units,
)

remote = "# Spec\n\nOld rule\n"
target = "# Spec\n\nNew rule\n"
remote_rule = next(unit for unit in markdown_semantic_units(remote) if unit.text == "Old rule")
snapshot = build_native_snapshot({
    "document_id": "docR",
    "revision_id": 9,
    "content": '<h1 id="h-spec">Spec</h1><p id="p-old">Old rule</p>',
})
coverage = build_remote_coverage(
    remote,
    target,
    native_snapshot=snapshot,
    resolutions=[{
        "remote_unit_id": remote_rule.unit_id,
        "disposition": "rewritten",
        "target_unit_ids": [],
        "format_disposition": "preserved",
        "evidence": {
            "kind": "pm_exception",
            "id": "rewrite-old",
            "reason": "PM 确认改写旧规则",
        },
    }],
    batch_id="empty-rewrite-target",
    remote_revision_id=9,
)
entry = next(item for item in coverage["entries"] if item["remote"]["unit_id"] == remote_rule.unit_id)
native = {item["block_id"]: item for item in coverage["native_format_entries"]}
assert entry["disposition"] == "unassigned", entry
assert "至少一个" in entry["resolution_error"], entry
assert coverage["summary"]["rewritten_count"] == 0, coverage
assert coverage["summary"]["unassigned_count"] == 1, coverage
assert coverage["summary"]["remote_accounted_ratio"] < 1, coverage
assert native["p-old"]["format_disposition"] == "unassigned", native
PY
  if [ "$?" -ne 0 ]; then
    _fail "empty rewritten target list was accepted"
    return
  fi
  pass_test
}

test_duplicate_remote_units_keep_independent_native_format_accounts() {
  start_test "lark-review: 同文重复段落的原生格式账本互不豁免"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - <<'PY'
from _lib.lark_review_semantics import (
    build_native_snapshot,
    build_remote_coverage,
    markdown_semantic_units,
)

remote = "# Spec\n\nRepeat\n\nRepeat\n"
target = "# Spec\n\nRepeat\n"
remote_repeats = [u for u in markdown_semantic_units(remote) if u.text == "Repeat"]
snapshot = build_native_snapshot({
    "document_id": "docR",
    "revision_id": 9,
    "content": '<?xml version="1.0" encoding="UTF-8"?><h1 id="b-title">Spec</h1><p id="b-repeat-1" align="left">Repeat</p><p id="b-repeat-2" align="right">Repeat</p>',
})
resolution = {
    "remote_unit_id": remote_repeats[1].unit_id,
    "disposition": "removed",
    "target_unit_ids": [],
    "format_disposition": "removed_with_content",
    "evidence": {"kind": "pm_exception", "id": "remove-second", "reason": "PM 删除第二段"},
}

coverage = build_remote_coverage(
    remote,
    target,
    native_snapshot=snapshot,
    resolutions=[resolution],
    batch_id="batch",
    remote_revision_id=9,
)
native = {item["block_id"]: item for item in coverage["native_format_entries"]}
assert native["b-repeat-1"]["format_disposition"] == "preserved", native
assert native["b-repeat-2"]["format_disposition"] == "removed_with_content", native
assert coverage["summary"]["format_unassigned_count"] == 0

bad = {**resolution, "format_disposition": "intentional_change"}
bad_coverage = build_remote_coverage(
    remote,
    target,
    native_snapshot=snapshot,
    resolutions=[bad],
    batch_id="batch",
    remote_revision_id=9,
)
assert bad_coverage["summary"]["unassigned_count"] == 1
assert bad_coverage["summary"]["format_unassigned_count"] == 1

semantic_remote = "# Spec\n\nUse [policy](https://remote.example) with `account_id` and **Required**.\n"
semantic_target = "# Spec\n\nUse [policy](https://local.example) with `accountid` and Required.\n"
semantic_snapshot = build_native_snapshot({
    "document_id": "docR",
    "revision_id": 9,
    "content": '<h1 id="b-semantic-title">Spec</h1><p id="b-semantic"><a href="https://remote.example">policy</a><code>account_id</code><b>Required</b></p>',
})
semantic_coverage = build_remote_coverage(
    semantic_remote,
    semantic_target,
    native_snapshot=semantic_snapshot,
    resolutions=[],
    batch_id="batch-semantic",
    remote_revision_id=9,
)
assert semantic_coverage["summary"]["unassigned_count"] == 1, semantic_coverage
PY
  if [ "$?" -ne 0 ]; then
    _fail "duplicate native format accounting is not independent"
    return
  fi
  pass_test
}

test_semantic_structure_changes_are_not_preserved() {
  start_test "lark-review: 标题层级、列表形态和表格角色纳入语义结构"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - <<'PY'
from _lib.lark_review_semantics import (
    build_native_snapshot,
    build_remote_coverage,
    markdown_semantic_units,
)


def snapshot(content):
    return build_native_snapshot({
        "document_id": "docR",
        "revision_id": 9,
        "content": content,
    })


heading_remote = markdown_semantic_units("# Spec\n")
heading_target = markdown_semantic_units("## Spec\n")
assert heading_remote[0].unit_id == heading_target[0].unit_id
assert heading_remote[0].structure_signature == "heading:level=1"
assert heading_target[0].structure_signature == "heading:level=2"
heading_coverage = build_remote_coverage(
    "# Spec\n",
    "## Spec\n",
    native_snapshot=snapshot('<h1 id="heading">Spec</h1>'),
    resolutions=[],
    batch_id="heading-level",
    remote_revision_id=9,
)
heading_entry = heading_coverage["entries"][0]
assert heading_entry["disposition"] == "unassigned", heading_entry
assert heading_entry["structural_change"] is True, heading_entry
assert heading_coverage["summary"]["preserved_count"] == 0, heading_coverage
assert heading_coverage["summary"]["high_risk_structural_count"] == 1, heading_coverage
assert heading_coverage["summary"]["preview_required"] is True, heading_coverage

list_remote = markdown_semantic_units("# Spec\n\n  - Choice\n")
list_target = markdown_semantic_units("# Spec\n\n  1. Choice\n")
remote_choice = next(item for item in list_remote if item.kind == "list_item")
target_choice = next(item for item in list_target if item.kind == "list_item")
assert remote_choice.unit_id == target_choice.unit_id
assert remote_choice.structure_signature == "list_item:unordered:indent=2"
assert target_choice.structure_signature == "list_item:ordered:indent=2"
list_coverage = build_remote_coverage(
    "# Spec\n\n  - Choice\n",
    "# Spec\n\n  1. Choice\n",
    native_snapshot=snapshot(
        '<h1 id="list-heading">Spec</h1><p id="choice">Choice</p>'
    ),
    resolutions=[],
    batch_id="list-orderedness",
    remote_revision_id=9,
)
list_entry = next(
    item for item in list_coverage["entries"] if item["remote"]["kind"] == "list_item"
)
assert list_entry["disposition"] == "unassigned", list_entry
assert list_entry["structural_change"] is True, list_entry
assert list_coverage["summary"]["high_risk_structural_count"] == 1, list_coverage
assert list_coverage["summary"]["preview_required"] is True, list_coverage

cross_coverage = build_remote_coverage(
    "# A\n\n- Choice\n\n# B\n\nKeep\n",
    "# A\n\n# B\n\n1. Choice\n\nKeep\n",
    native_snapshot=snapshot(
        '<h1 id="a">A</h1><p id="cross-choice">Choice</p>'
        '<h1 id="b">B</h1><p id="keep">Keep</p>'
    ),
    resolutions=[],
    batch_id="cross-section-structure",
    remote_revision_id=9,
)
cross_choice = next(
    item for item in cross_coverage["entries"] if item["remote"]["text"] == "Choice"
)
assert cross_choice["disposition"] == "unassigned", cross_choice
assert cross_choice["structural_change"] is True, cross_choice

cross_kind_remote = "# Spec\n\nRule\n"
cross_kind_target = "# Spec\n\n# Rule\n"
remote_rule = next(
    item for item in markdown_semantic_units(cross_kind_remote) if item.text == "Rule"
)
target_rule = next(
    item for item in markdown_semantic_units(cross_kind_target) if item.text == "Rule"
)
cross_kind_coverage = build_remote_coverage(
    cross_kind_remote,
    cross_kind_target,
    native_snapshot=snapshot(
        '<h1 id="cross-kind-heading">Spec</h1><p id="cross-kind-rule">Rule</p>'
    ),
    resolutions=[{
        "remote_unit_id": remote_rule.unit_id,
        "disposition": "rewritten",
        "target_unit_ids": [target_rule.unit_id],
        "format_disposition": "preserved",
        "evidence": {
            "kind": "pm_exception",
            "id": "paragraph-to-heading",
            "reason": "PM 确认将段落改写为标题",
        },
    }],
    batch_id="cross-kind-rewrite",
    remote_revision_id=9,
)
cross_kind_entry = next(
    item
    for item in cross_kind_coverage["entries"]
    if item["remote"]["unit_id"] == remote_rule.unit_id
)
assert cross_kind_entry["disposition"] == "rewritten", cross_kind_entry
assert cross_kind_entry["structural_change"] is True, cross_kind_entry
assert cross_kind_coverage["summary"]["high_risk_structural_count"] == 1, cross_kind_coverage
assert cross_kind_coverage["summary"]["preview_required"] is True, cross_kind_coverage

table_units = [
    item
    for item in markdown_semantic_units(
        "| Name |\n| --- |\n| Alice |\n"
    )
    if item.kind == "table_row"
]
assert [item.structure_signature for item in table_units] == [
    "table_row:role=header",
    "table_row:role=data",
]
PY
  if [ "$?" -ne 0 ]; then
    _fail "semantic matching ignored a Markdown structure change"
    return
  fi
  pass_test
}

test_cross_section_duplicate_text_cannot_consume_wrong_unit() {
  start_test "lark-review: 跨章节重复文本按章节位置归位"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - <<'PY'
from _lib.lark_review_semantics import (
    build_native_snapshot,
    build_remote_coverage,
    markdown_semantic_units,
)

remote = "# A\n\nShared rule\n\n# B\n\nShared rule\n"
target = "# A\n\n# B\n\nShared rule\n"
remote_units = markdown_semantic_units(remote)
repeats = [unit for unit in remote_units if unit.text == "Shared rule"]
remote_a, remote_b = repeats
assert remote_a.section_path == ["A"]
assert remote_b.section_path == ["B"]
snapshot = build_native_snapshot({
    "document_id": "docR",
    "revision_id": 9,
    "content": (
        '<h1 id="h-a">A</h1><p id="p-a">Shared rule</p>'
        '<h1 id="h-b">B</h1><p id="p-b">Shared rule</p>'
    ),
})
wrong_removal = {
    "remote_unit_id": remote_b.unit_id,
    "disposition": "removed",
    "target_unit_ids": [],
    "format_disposition": "removed_with_content",
    "evidence": {
        "kind": "pm_exception",
        "id": "remove-b",
        "reason": "PM 指定删除 B 章规则",
    },
}
coverage = build_remote_coverage(
    remote,
    target,
    native_snapshot=snapshot,
    resolutions=[wrong_removal],
    batch_id="section-bound",
    remote_revision_id=9,
)
entries = {
    item["remote"]["unit_id"]: item
    for item in coverage["entries"]
}
native = {item["block_id"]: item for item in coverage["native_format_entries"]}
assert entries[remote_a.unit_id]["disposition"] == "unassigned", entries
assert entries[remote_b.unit_id]["disposition"] == "preserved", entries
assert coverage["unknown_resolution_ids"] == [remote_b.unit_id], coverage
assert coverage["summary"]["unassigned_count"] == 1, coverage
assert native["p-a"]["format_disposition"] == "unassigned", native
assert native["p-b"]["format_disposition"] == "preserved", native

ambiguous_remote = "# A\n\nShared rule\n\n# B\n\nShared rule\n"
ambiguous_target = "# C\n\nShared rule\n\n# D\n\nShared rule\n"
ambiguous_snapshot = build_native_snapshot({
    "document_id": "docR",
    "revision_id": 9,
    "content": (
        '<h1 id="ambiguous-h-a">A</h1><p id="ambiguous-p-a">Shared rule</p>'
        '<h1 id="ambiguous-h-b">B</h1><p id="ambiguous-p-b">Shared rule</p>'
    ),
})
ambiguous_coverage = build_remote_coverage(
    ambiguous_remote,
    ambiguous_target,
    native_snapshot=ambiguous_snapshot,
    resolutions=[],
    batch_id="ambiguous-sections",
    remote_revision_id=9,
)
ambiguous_repeats = [
    item
    for item in ambiguous_coverage["entries"]
    if item["remote"]["text"] == "Shared rule"
]
assert len(ambiguous_repeats) == 2, ambiguous_repeats
assert all(item["disposition"] == "unassigned" for item in ambiguous_repeats), ambiguous_repeats
PY
  if [ "$?" -ne 0 ]; then
    _fail "cross-section duplicate text was matched to the wrong chapter"
    return
  fi
  pass_test
}

test_unique_cross_section_units_are_moved() {
  start_test "lark-review: 唯一语义跨章节和章节改名正文按 moved 归位"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - <<'PY'
from _lib.lark_review_semantics import (
    build_native_snapshot,
    build_remote_coverage,
    markdown_semantic_units,
)

remote = "# A\n\nUnique rule\n\n# B\n\nKeep B\n"
target = "# A\n\n# B\n\nKeep B\n\nUnique rule\n"
remote_rule = next(unit for unit in markdown_semantic_units(remote) if unit.text == "Unique rule")
snapshot = build_native_snapshot({
    "document_id": "docR",
    "revision_id": 9,
    "content": (
        '<h1 id="move-h-a">A</h1><p id="move-rule">Unique rule</p>'
        '<h1 id="move-h-b">B</h1><p id="move-keep">Keep B</p>'
    ),
})
coverage = build_remote_coverage(
    remote,
    target,
    native_snapshot=snapshot,
    resolutions=[],
    batch_id="unique-cross-section",
    remote_revision_id=9,
)
entry = next(item for item in coverage["entries"] if item["remote"]["unit_id"] == remote_rule.unit_id)
target_by_id = {item["unit_id"]: item for item in coverage["target_units"]}
matched_target = target_by_id[entry["target_unit_ids"][0]]
assert entry["disposition"] == "moved", entry
assert matched_target["section_path"] == ["B"], matched_target
assert coverage["summary"]["moved_count"] == 1, coverage
assert coverage["summary"]["unassigned_count"] == 0, coverage
assert coverage["summary"]["high_risk_structural_count"] == 1, coverage
assert coverage["summary"]["preview_required"] is True, coverage

renamed_remote = "# Old section\n\nStable detail\n"
renamed_target = "# New section\n\nStable detail\n"
renamed_remote_units = markdown_semantic_units(renamed_remote)
renamed_target_units = markdown_semantic_units(renamed_target)
old_heading = next(unit for unit in renamed_remote_units if unit.kind == "heading")
new_heading = next(unit for unit in renamed_target_units if unit.kind == "heading")
stable_detail = next(unit for unit in renamed_remote_units if unit.text == "Stable detail")
renamed_snapshot = build_native_snapshot({
    "document_id": "docR",
    "revision_id": 9,
    "content": '<h1 id="rename-h">Old section</h1><p id="rename-detail">Stable detail</p>',
})
renamed_coverage = build_remote_coverage(
    renamed_remote,
    renamed_target,
    native_snapshot=renamed_snapshot,
    resolutions=[{
        "remote_unit_id": old_heading.unit_id,
        "disposition": "rewritten",
        "target_unit_ids": [new_heading.unit_id],
        "format_disposition": "preserved",
        "evidence": {
            "kind": "pm_exception",
            "id": "rename-section",
            "reason": "PM 确认章节改名",
        },
    }],
    batch_id="renamed-section",
    remote_revision_id=9,
)
renamed_entry = next(
    item
    for item in renamed_coverage["entries"]
    if item["remote"]["unit_id"] == stable_detail.unit_id
)
assert renamed_entry["disposition"] == "moved", renamed_entry
assert renamed_coverage["summary"]["moved_count"] == 1, renamed_coverage
assert renamed_coverage["summary"]["rewritten_count"] == 1, renamed_coverage
assert renamed_coverage["summary"]["unassigned_count"] == 0, renamed_coverage
assert renamed_coverage["summary"]["preview_required"] is True, renamed_coverage
PY
  if [ "$?" -ne 0 ]; then
    _fail "unique cross-section semantic unit was not accounted as moved"
    return
  fi
  pass_test
}

test_comment_without_solved_time_can_checkpoint() {
  start_test "lark-review: 缺少 solved_time 时以写回执和稳定回读收口"
  local work="$BASE/comment-no-solved-time"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q 'write_ack_and_stable_readback'; then
    _fail "missing solved_time should use controlled readback evidence: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
action = json.load(open(sys.argv[1], encoding="utf-8"))["actions"][0]
assert action["status"] == "completed"
assert action["solved_time"] is None
assert action["solve_evidence_mode"] == "write_ack_and_stable_readback"
assert action["solve_write_ack_sha256"]
PY
  [ "$?" -eq 0 ] || { _fail "controlled receipt is incomplete"; return; }
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" --plan "$work/out/apply-plan.json" \
      --reviewed-at '2026-08-07T12:00:00+08:00' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^lark_reviewed_revision_id: 10$' "$work/spec.md"; then
    _fail "checkpoint should accept stable no-time receipt: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_verify_sync_preserves_native_format_and_resources() {
  start_test "lark-review: 精细写回后机器验证飞书原生格式和资源"
  local work="$BASE/verify-sync"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    python3 "$COLLECTOR" verify-sync \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"format_coverage": 1.0'; then
    _fail "native format verification should pass: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/remote-verification.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["target_base"] == "remote_native_snapshot"
assert value["content_projection_match"] is True
assert value["remote_format_accounted_ratio"] == 1.0
assert value["preserved_native_block_count"] == 5
assert value["original_references_preserved"] is True
PY
  [ "$?" -eq 0 ] || { _fail "remote verification receipt is incomplete"; return; }
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_FORMAT_LOSS=1 \
    python3 "$COLLECTOR" verify-sync \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -Eq '格式或资源未被保留|引用映射未被完整保留'; then
    _fail "format/resource loss must fail verification: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_image_urls_use_resource_aware_projection() {
  start_test "lark-review: 图片临时 URL 不改变正文身份但普通链接仍参与验收"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - <<'PY'
from _lib.lark_review_semantics import markdown_verification_projection

local = "# Spec\n\n![账号列表](assets/account.png)\n\n[帮助](https://example.com/a)\n"
temporary = "# Spec\n\n![账号列表](https://open.feishu.cn/temp/token?expires=1)\n\n[帮助](https://example.com/a)\n"
rotated = "# Spec\n\n![账号列表](https://open.feishu.cn/temp/token?expires=2)\n\n[帮助](https://example.com/a)\n"
assert markdown_verification_projection(local) == markdown_verification_projection(temporary)
assert markdown_verification_projection(temporary) == markdown_verification_projection(rotated)
assert markdown_verification_projection(local) != markdown_verification_projection(
    local.replace("https://example.com/a", "https://example.com/b")
)
assert markdown_verification_projection(local) != markdown_verification_projection(
    local.replace("账号列表", "账号详情")
)
assert markdown_verification_projection(local) != markdown_verification_projection(
    local.replace("![账号列表]", "![新增图](assets/new.png)\n\n![账号列表]")
)
PY
  if [ "$?" -ne 0 ]; then
    _fail "resource-aware Markdown projection is incorrect"
    return
  fi
  pass_test
}

test_verify_sync_rejects_unsynced_markdown_structure() {
  start_test "lark-review: verify-sync 拒绝未同步的标题层级和列表形态"
  local work="$BASE/verify-sync-structure"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  PYTHONDONTWRITEBYTECODE=1 python3 - "$COLLECTOR" \
    "$work/out/review.json" "$work/out/apply-plan.json" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

collector_path = Path(sys.argv[1])
manifest_path = Path(sys.argv[2])
plan_path = Path(sys.argv[3])
spec = importlib.util.spec_from_file_location(
    "lark_review_structure_verification_test",
    collector_path,
)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
plan = json.loads(plan_path.read_text(encoding="utf-8"))


def assert_structure_rejected(target_body, remote_body):
    module._fetch_current_pair = lambda _doc_id: (
        {
            "document_id": "docR",
            "revision_id": 10,
            "content": remote_body,
        },
        {},
    )
    try:
        module._sync_verification(
            manifest_path,
            manifest,
            plan_path,
            plan,
            {
                "doc_id": "docR",
                "published_revision_id": 10,
                "body": target_body,
            },
        )
    except module.ReviewError as exc:
        assert "稳定语义投影" in str(exc), str(exc)
    else:
        raise AssertionError("unsynced Markdown structure passed verify-sync")


assert_structure_rejected("## Spec\n\nNew rule\n", "# Spec\n\nNew rule\n")
assert_structure_rejected("# Spec\n\n1. Choice\n", "# Spec\n\n- Choice\n")
PY
  if [ "$?" -ne 0 ]; then
    _fail "verify-sync accepted an unsynced Markdown structure"
    return
  fi
  pass_test
}

test_legacy_remote_coverage_schema_is_rejected() {
  start_test "lark-review: v1 远端覆盖账本不能沿用旧预览结论执行或验收"
  local work="$BASE/legacy-remote-coverage"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  python3 - "$work/out/remote-coverage.json" "$work/out/apply-plan.json" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

coverage_path = Path(sys.argv[1])
plan_path = Path(sys.argv[2])
coverage = json.loads(coverage_path.read_text(encoding="utf-8"))
assert coverage["schema_version"] == 2, coverage
coverage["schema_version"] = 1
coverage["summary"]["preview_required"] = False
coverage_path.write_text(
    json.dumps(coverage, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

plan = json.loads(plan_path.read_text(encoding="utf-8"))
plan["remote_coverage"]["sha256"] = hashlib.sha256(
    coverage_path.read_bytes()
).hexdigest()
binding = {key: value for key, value in plan.items() if key != "ready_token"}
encoded = json.dumps(
    binding,
    ensure_ascii=False,
    sort_keys=True,
    separators=(",", ":"),
)
plan["ready_token"] = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
plan_path.write_text(
    json.dumps(plan, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
  if [ "$?" -ne 0 ]; then
    _fail "failed to construct a sealed v1 coverage ledger"
    return
  fi

  local out rc
  out=$(python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '远端覆盖账本不是可执行的完整账本'; then
    _fail "apply accepted a sealed v1 coverage ledger: rc=$rc out=$out"
    return
  fi

  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    python3 "$COLLECTOR" verify-sync \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '不是完整的远端覆盖账本'; then
    _fail "verify-sync accepted a sealed v1 coverage ledger: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_structural_remote_change_requires_preview_review() {
  start_test "lark-review: 结构性 R 到 T 改写必须预览但纯结构可由 AI 验收"
  local work="$BASE/remote-preview"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  sed -i.bak 's/^# Spec$/# Updated spec/' "$work/out/target.md"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - \
    "$work/out/resolutions.json" "$work/out/remote.md" "$work/out/target.md" <<'PY'
import json, sys
from pathlib import Path
from _lib.lark_review_semantics import markdown_semantic_units

path = Path(sys.argv[1])
remote = markdown_semantic_units(Path(sys.argv[2]).read_text(encoding="utf-8"))
target = markdown_semantic_units(Path(sys.argv[3]).read_text(encoding="utf-8"))
old_heading = next(item for item in remote if item.kind == "heading")
new_heading = next(item for item in target if item.kind == "heading")
data = json.loads(path.read_text(encoding="utf-8"))
data["target"] = {
    "mode": "lifecycle_compiled",
    "authority": "pm_confirmed",
    "reason": "按 PM 确认更新标题",
}

for item in data["comments"]:
    item.update(decision="no_spec_change", authority="existing_spec", reason="无需改规格", result_text="Updated and verified")
data["remote_coverage"] = [{
    "remote_unit_id": old_heading.unit_id,
    "disposition": "rewritten",
    "target_unit_ids": [new_heading.unit_id],
    "format_disposition": "preserved",
    "evidence": {
        "kind": "pm_exception",
        "id": "pm-heading-confirmation",
        "reason": "PM 确认标题改写但保留原样式",
    },
}]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  complete_decision_routing "$work/out/resolutions.json"
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '强制预览阈值' \
    || ! grep -q 'remote-heading-' "$work/out/remote-preview.md" \
    || ! grep -q '处置：moved' "$work/out/remote-preview.md"; then
    _fail "structural rewrite should stop for PM preview: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["preview"] = {
    "approved": True,
    "authority": "agent_reviewed",
    "reason": "已核对标题结构、正文和原生样式，未改变产品含义",
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"preview_required": true'; then
    _fail "agent-reviewed structural preview should seal: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_large_reorder_requires_pm_preview() {
  start_test "lark-review: 20 项纯重排计入结构变化并强制预览"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - <<'PY'
from _lib.lark_review_semantics import (
    build_native_snapshot,
    build_remote_coverage,
    render_remote_preview,
)

items = [f"Item {index}" for index in range(1, 21)]
remote = "# Spec\n\n" + "\n".join(f"- {item}" for item in items) + "\n"
target = "# Spec\n\n" + "\n".join(f"- {item}" for item in reversed(items)) + "\n"
snapshot = build_native_snapshot({
    "document_id": "docR",
    "revision_id": 9,
    "content": '<h1 id="title">Spec</h1>' + "".join(
        f'<p id="item-{index}">{item}</p>'
        for index, item in enumerate(items, start=1)
    ),
})
coverage = build_remote_coverage(
    remote,
    target,
    native_snapshot=snapshot,
    resolutions=[],
    batch_id="reorder",
    remote_revision_id=9,
)
summary = coverage["summary"]
assert summary["moved_count"] >= 19, summary
assert summary["unassigned_count"] == 0, summary
assert summary["remote_preserved_ratio"] == 1.0, summary
assert summary["preview_required"] is True, summary
preview = render_remote_preview(coverage)
assert "处置：moved" in preview, preview
assert "移动：" in preview, preview

inserted_target = "# Spec\n\n- Added first\n" + "\n".join(
    f"- {item}" for item in items
) + "\n"
inserted = build_remote_coverage(
    remote,
    inserted_target,
    native_snapshot=snapshot,
    resolutions=[],
    batch_id="inserted",
    remote_revision_id=9,
)
assert inserted["summary"]["moved_count"] == 0, inserted
assert inserted["summary"]["preview_required"] is False, inserted
PY
  if [ "$?" -ne 0 ]; then
    _fail "large semantic reorder did not produce a useful mandatory preview"
    return
  fi
  pass_test
}

test_legacy_solve_requested_without_write_ack_is_rejected() {
  start_test "lark-review: solve_requested 缺少 solve 写回执时拒绝冒充受控完成"
  local work="$BASE/legacy-no-solved-time"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  python3 - "$work/out/review.json" "$work/out/apply-plan.json" <<'PY'
import hashlib, json, sys
manifest_path, plan_path = sys.argv[1:]
manifest = json.load(open(manifest_path, encoding="utf-8"))
manifest["schema_version"] = 2
with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
plan = json.load(open(plan_path, encoding="utf-8"))
plan["schema_version"] = 2
plan["manifest"]["sha256"] = hashlib.sha256(open(manifest_path, "rb").read()).hexdigest()
plan.pop("ready_token", None)
encoded = json.dumps(plan, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
plan["ready_token"] = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
with open(plan_path, "w", encoding="utf-8") as handle:
    json.dump(plan, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_FINAL_READ_FAIL=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'solve_requested'; then
    _fail "failed readback should leave a recoverable solve request: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["schema_version"] = 1
for action in data["actions"]:
    action.pop("solve_evidence_mode", None)
    action.pop("solve_write_ack_sha256", None)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '缺少系统解决写响应'; then
    _fail "missing solve write acknowledgement should fail closed: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
action = data["actions"][0]
assert data["schema_version"] == 1
assert action["status"] == "solve_requested"
assert "solve_evidence_mode" not in action
assert "solve_write_ack_sha256" not in action
PY
  [ "$?" -eq 0 ] || { _fail "ambiguous legacy receipt should remain uncompleted"; return; }
  pass_test
}

test_review_requires_cli_with_versioned_docs_skills() {
  start_test "lark-review: 使用评论和 Markdown fetch 时要求专用 CLI 最低版本"
  local work="$BASE/old-cli"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_VERSION='lark-cli 1.0.48' python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '最低要求 1.0.49'; then
    _fail "old review CLI should fail closed: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_legacy_document_degrades_without_claiming_delta() {
  start_test "lark-review: 旧文档无发布基线时降级为 legacy"
  local work="$BASE/legacy"
  mkdir -p "$work/out" "$work/.git"
  printf '# PMAI Agent Entry\n' > "$work/AGENTS.md"
  printf '# Product State\n' > "$work/PRODUCT-STATE.md"
  cat > "$work/spec.md" <<'MD'
---
lark_doc_id: docR
---

# Spec

Old rule
MD
  local out
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" 2>&1)
  if [ "$?" -ne 0 ]; then
    _fail "legacy collection should succeed: $out"
    return
  fi
  local status
  status=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["body"]["status"])' "$work/out/review.json")
  if [ "$status" != "legacy_baseline" ]; then
    _fail "expected legacy_baseline, got $status"
    return
  fi
  pass_test
}

test_recorded_revision_failure_is_fail_closed() {
  start_test "lark-review: 已记录历史 revision 读取失败时阻断"
  local work="$BASE/fail-baseline"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_FAIL_BASELINE=1 python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '不能安全识别正文增量'; then
    _fail "expected fail-closed baseline error; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_recorded_revision_response_must_match_requested_revision() {
  start_test "lark-review: 历史版本响应与请求不一致时阻断"
  local work="$BASE/wrong-baseline"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_WRONG_BASELINE=1 python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '历史版本响应与请求不一致'; then
    _fail "expected mismatched baseline response to fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_current_markdown_and_xml_must_share_revision() {
  start_test "lark-review: Markdown/XML revision 持续不一致时阻断"
  local work="$BASE/torn-pair"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_TORN_PAIR=1 python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'revision 持续变化'; then
    _fail "expected torn current snapshot to fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_doc_argument_must_match_frontmatter_url() {
  start_test "lark-review: --doc 与 frontmatter URL 身份冲突时阻断"
  local work="$BASE/doc-conflict"
  mkdir -p "$work/out"
  cat > "$work/spec.md" <<'MD'
---
lark_doc_url: https://example.feishu.cn/docx/docOther
---

# Spec
MD
  local out rc
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --doc docR \
    --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'lark_doc_url'; then
    _fail "expected document identity conflict to fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_collect_rejects_unbound_local_document() {
  start_test "lark-review: --doc 不能替代本地规格的持久身份绑定"
  local work="$BASE/unbound-local"
  mkdir -p "$work/out"
  cat > "$work/spec.md" <<'MD'
# Spec

Old rule
MD
  local out rc
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --doc docR \
    --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '缺少 lark_doc_id' \
    || [ -e "$work/out/review.json" ]; then
    _fail "unbound local document should fail during collect; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_checkpoint_rejects_rebound_document() {
  start_test "lark-review: collect 后文档重新绑定时拒绝旧 checkpoint"
  local work="$BASE/rebound"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  seal_simple_review "$work" || { _fail "failed to seal"; return; }
  python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" >/dev/null
  sed -i.bak 's/^lark_doc_id: docR$/lark_doc_id: docOther/' "$work/spec.md"
  local out rc
  out=$(python3 "$COLLECTOR" checkpoint "$work/spec.md" \
    --manifest "$work/out/review.json" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '文档身份不匹配'; then
    _fail "expected rebound checkpoint to fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_baseline_accepts_url_only_and_rejects_revision_rollback() {
  start_test "lark-review: URL-only 文档可建基线且 revision 不得回退"
  local work="$BASE/url-baseline"
  mkdir -p "$work"
  cat > "$work/spec.md" <<'MD'
---
lark_doc_url: https://example.feishu.cn/docx/docR
---

# Spec
MD
  local source_hash
  source_hash=$(PYTHONPATH="$REPO_ROOT/scripts" python3 - "$work/spec.md" <<'PY'
import sys
from pathlib import Path
from _lib.lark_adapter import markdown_body_hash, parse_frontmatter
_, body = parse_frontmatter(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(markdown_body_hash(body))
PY
)
  python3 "$COLLECTOR" baseline "$work/spec.md" --revision-id 9 \
    --expected-source-hash "$source_hash" >/dev/null
  if ! grep -q '^lark_doc_id: docR$' "$work/spec.md" \
    || ! grep -q '^lark_published_revision_id: 9$' "$work/spec.md"; then
    _fail "URL-only baseline 未补齐 canonical doc id: $(cat "$work/spec.md")"
    return
  fi
  local out rc
  out=$(python3 "$COLLECTOR" baseline "$work/spec.md" --revision-id 8 \
    --expected-source-hash "$source_hash" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '拒绝回退'; then
    _fail "baseline revision rollback should fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_legacy_doc_url_is_rejected_before_comment_collection() {
  start_test "lark-review: 旧版 /doc/ 与 /docs/ 链接在入口失败关闭"
  local work="$BASE/legacy-doc-url"
  mkdir -p "$work/out"
  cat > "$work/spec.md" <<'MD'
---
lark_doc_url: https://example.feishu.cn/doc/docLegacy
---

# Spec
MD
  local out rc
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '只支持飞书 Docx'; then
    _fail "legacy doc URL should fail before docx comment calls; rc=$rc out=$out"
    return
  fi
  sed -i.bak 's#/doc/docLegacy#/docs/docLegacy#' "$work/spec.md"
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '只支持飞书 Docx'; then
    _fail "legacy docs URL should fail before docx comment calls; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_invalid_pagination_is_fail_closed() {
  start_test "lark-review: has_more 无 token 时阻断"
  local work="$BASE/fail-page"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_BAD_PAGE=1 python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '分页 token 缺失或重复'; then
    _fail "expected pagination failure; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_malformed_comment_pages_are_fail_closed() {
  start_test "lark-review: 畸形评论 envelope、item 和分页字段全部阻断"
  local cases=(
    'FAKE_REVIEW_DATA_NULL:data 不是对象'
    'FAKE_REVIEW_MALFORMED_ITEM:items 包含非对象条目'
    'FAKE_REVIEW_BAD_HAS_MORE:has_more 缺失或不是布尔值'
    'FAKE_REVIEW_BAD_PAGE_TOKEN_TYPE:page_token 不是字符串或 null'
  )
  local index=0 spec flag expected work out rc
  for spec in "${cases[@]}"; do
    index=$((index + 1))
    flag=${spec%%:*}
    expected=${spec#*:}
    work="$BASE/malformed-page-$index"
    mkdir -p "$work/out"
    make_review_doc "$work/spec.md"
    out=$(env "$flag=1" python3 "$COLLECTOR" collect \
      "$work/spec.md" --output-dir "$work/out" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q "$expected" \
      || [ -e "$work/out/review.json" ]; then
      _fail "$flag should fail closed before manifest: rc=$rc out=$out"
      return
    fi
  done
  pass_test
}

test_torn_solved_state_scan_retries_to_stability() {
  start_test "lark-review: 评论跨已解决状态查询切换时重试到连续稳定"
  local work="$BASE/torn-comment-state"
  mkdir -p "$work/out" "$work/state"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_TORN_COMMENT_SCAN_ONCE=1 \
    FAKE_REVIEW_STATE_DIR="$work/state" \
    python3 "$COLLECTOR" collect "$work/spec.md" \
      --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || [ ! -e "$work/out/review.json" ] \
    || [ ! -e "$work/state/torn-comment-scan-seen" ]; then
    _fail "transient solved-state overlap should retry: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_product_handoff_without_active_build_is_read_only() {
  start_test "lark-review: 产品级变化无 active build 也先只读 handoff"
  local work="$BASE/product-handoff-main"
  local review_root="$work/.pm-workflow/context/lark-review"
  local batch="$review_root/batch.product"
  local blocked="$review_root/batch.product-blocked"
  local spec="$work/docs/modules/example/spec.md"
  local out blocked_out

  make_git_module_review_repo "$work"
  mkdir -p "$batch"
  python3 "$COLLECTOR" collect "$spec" --output-dir "$batch" >/dev/null || {
    _fail "failed to collect direct product handoff fixture"; return;
  }
  python3 "$COLLECTOR" reconcile --manifest "$batch/review.json" >/dev/null || {
    _fail "failed to draft direct product handoff fixture"; return;
  }
  if ! out=$(python3 "$COLLECTOR" handoff \
    --manifest "$batch/review.json" --route proposal 2>&1); then
    _fail "direct product handoff failed: $out"
    return
  elif ! python3 - "$batch/handoff.json" "$batch/apply-plan.json" "$out" <<'PY'
import json
import sys
from pathlib import Path

handoff = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
plan = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
result = json.loads(sys.argv[3])
assert handoff["schema_version"] == 2
assert handoff["handoff_mode"] == "direct_product_change"
assert handoff["route"] == "proposal"
assert handoff["candidate_manifest"] is None
assert handoff["product_baseline"]["active_build_count"] == 0
assert handoff["product_baseline"]["branch"] == "main"
assert plan["state"] == "handed_off"
assert result["handoff_mode"] == "direct_product_change"
assert result["candidate_manifest"] is None
PY
  then
    _fail "direct product handoff binding mismatch: $out"
    return
  fi
  assert_pending_handoff_bundle \
    "$work" proposal "$out" "$batch/review.json" || return

  mkdir -p "$blocked"
  python3 "$COLLECTOR" collect "$spec" --output-dir "$blocked" >/dev/null || {
    _fail "failed to collect active product handoff fixture"; return;
  }
  python3 "$COLLECTOR" reconcile --manifest "$blocked/review.json" >/dev/null || {
    _fail "failed to draft active product handoff fixture"; return;
  }
  python3 - "$work/docs/modules/example/.work-meta.json" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "id": "work-product-active",
    "name": "active product review",
    "branch": "main",
    "stage": 2,
    "status": "active",
    "lifecycle_state": "building",
    "build": {"branch": "main", "lifecycle_state": "building"},
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  if blocked_out=$(python3 "$COLLECTOR" handoff \
    --manifest "$blocked/review.json" --route proposal 2>&1); then
    _fail "active product handoff must require a replan candidate"
    return
  elif ! echo "$blocked_out" | grep -q "必须先 replan.*candidate manifest"; then
    _fail "active product handoff should fail with replan guidance: $blocked_out"
    return
  elif [ -e "$blocked/handoff.json" ]; then
    _fail "failed direct handoff must not create a marker"
    return
  fi
  pass_test
}

test_fresh_checkpoint_closes_product_handoff_bundle() {
  start_test "lark-review: 扁平功能规格的 handoff bundle 可由 fresh checkpoint 关闭"
  local work="$BASE/product-handoff-checkpoint"
  local review_root="$work/.pm-workflow/context/lark-review"
  local handoff_batch="$review_root/batch.product-handoff"
  local fresh_batch="$work/out"
  local spec="$work/docs/modules/account-policy.md"
  local bundle handoff_out checkpoint_out list_out closed_list_out target_hash
  local proposal_commit authority_commit advance_out blocked_out

  make_git_module_review_repo "$work"
  cp "$work/docs/modules/example/spec.md" "$spec"
  git -C "$work" add -- docs/modules/account-policy.md
  git -C "$work" commit -q -m "add flat functional specification"
  mkdir -p "$handoff_batch"
  python3 "$COLLECTOR" collect "$spec" --output-dir "$handoff_batch" >/dev/null || {
    _fail "failed to collect product handoff closure fixture"; return;
  }
  python3 "$COLLECTOR" reconcile \
    --manifest "$handoff_batch/review.json" >/dev/null || {
    _fail "failed to draft product handoff closure fixture"; return;
  }
  handoff_out=$(python3 "$COLLECTOR" handoff \
    --manifest "$handoff_batch/review.json" --route proposal 2>&1) || {
    _fail "failed to create product handoff for checkpoint: $handoff_out"; return;
  }
  bundle=$(python3 -c \
    'import json,sys; print(json.load(sys.stdin)["handoff_bundle"])' \
    <<<"$handoff_out") || {
    _fail "handoff output did not expose its durable bundle: $handoff_out"; return;
  }
  if blocked_out=$(python3 "$COLLECTOR" advance-handoff "$bundle" \
    --to design 2>&1); then
    _fail "proposal handoff advanced without a new accepted Proposal"
    return
  elif ! echo "$blocked_out" | grep -q "Product Proposal"; then
    _fail "missing Proposal evidence should fail explicitly: $blocked_out"
    return
  fi
  accept_test_proposal "$work" || {
    _fail "failed to establish the post-handoff Proposal"; return;
  }
  proposal_commit=$(git -C "$work" rev-parse HEAD)
  advance_out=$(python3 "$COLLECTOR" advance-handoff "$bundle" \
    --to design 2>&1) || {
    _fail "accepted Proposal did not advance handoff to design: $advance_out"; return;
  }
  if ! echo "$advance_out" | grep -q '"phase": "design"'; then
    _fail "Proposal advancement did not report design phase: $advance_out"
    return
  fi
  if blocked_out=$(python3 "$COLLECTOR" advance-handoff "$bundle" \
    --to lark-review --evidence-commit "$proposal_commit" 2>&1); then
    _fail "handoff advanced without a committed authority spec change"
    return
  elif ! echo "$blocked_out" | grep -Eq "必须晚于|没有修改当前 handoff 绑定的规格"; then
    _fail "missing authority change should fail explicitly: $blocked_out"
    return
  fi

  PYTHONPATH="$REPO_ROOT/scripts" python3 - \
    "$spec" "$handoff_batch/target.md" <<'PY'
import sys
from pathlib import Path
from _lib.lark_adapter import replace_markdown_body

markdown = Path(sys.argv[1])
target = Path(sys.argv[2]).read_text(encoding="utf-8")
replace_markdown_body(markdown, target, require_canonical_path=True)
PY
  if [ "$?" -ne 0 ]; then
    _fail "failed to simulate the upstream Proposal/design authority update"
    return
  fi
  git -C "$work" add -- docs/modules/account-policy.md
  git -C "$work" commit -q -m "docs: update reviewed authority spec"
  authority_commit=$(git -C "$work" rev-parse HEAD)
  advance_out=$(python3 "$COLLECTOR" advance-handoff "$bundle" \
    --to lark-review --evidence-commit "$authority_commit" 2>&1) || {
    _fail "authority spec commit did not advance handoff to lark_review: $advance_out"; return;
  }
  if ! echo "$advance_out" | grep -q '"phase": "lark_review"'; then
    _fail "authority advancement did not report lark_review phase: $advance_out"
    return
  fi
  if blocked_out=$(python3 "$COLLECTOR" advance-handoff "$bundle" \
    --to design 2>&1); then
    _fail "handoff phase accepted a backward transition"
    return
  elif ! echo "$blocked_out" | grep -q "只能按顺序推进"; then
    _fail "backward transition should fail explicitly: $blocked_out"
    return
  fi
  target_hash=$(PYTHONPATH="$REPO_ROOT/scripts" python3 - "$spec" <<'PY'
import sys
from pathlib import Path
from _lib.lark_adapter import markdown_body_hash, parse_frontmatter

_, body = parse_frontmatter(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(markdown_body_hash(body))
PY
  ) || return
  python3 "$COLLECTOR" baseline "$spec" --revision-id 9 \
    --expected-source-hash "$target_hash" >/dev/null || {
    _fail "failed to establish the post-handoff main publishing baseline"; return;
  }

  mkdir -p "$fresh_batch" "$work/remote-state"
  python3 "$COLLECTOR" collect "$spec" --output-dir "$fresh_batch" >/dev/null || {
    _fail "failed to collect the fresh post-handoff batch"; return;
  }
  seal_simple_review "$work" || {
    _fail "failed to seal the fresh post-handoff batch"; return;
  }
  python3 "$COLLECTOR" apply "$spec" \
    --plan "$fresh_batch/apply-plan.json" >/dev/null || {
    _fail "failed to apply the fresh post-handoff batch"; return;
  }
  target_hash=$(python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["target"]["body_sha256"])' \
    "$fresh_batch/apply-plan.json") || return
  FAKE_REVIEW_SYNCED_REMOTE=1 python3 "$COLLECTOR" baseline "$spec" \
    --revision-id 10 --expected-source-hash "$target_hash" >/dev/null || {
    _fail "failed to refresh the fresh batch publishing baseline"; return;
  }
  FAKE_REVIEW_SYNCED_REMOTE=1 python3 "$COLLECTOR" verify-sync \
    --manifest "$fresh_batch/review.json" \
    --plan "$fresh_batch/apply-plan.json" >/dev/null || {
    _fail "failed to verify the fresh batch remote projection"; return;
  }
  FAKE_REVIEW_SYNCED_REMOTE=1 \
  FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
  FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comments \
      --manifest "$fresh_batch/review.json" \
      --plan "$fresh_batch/apply-plan.json" >/dev/null || {
    _fail "failed to complete the fresh batch comments"; return;
  }
  checkpoint_out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$spec" \
      --manifest "$fresh_batch/review.json" \
      --plan "$fresh_batch/apply-plan.json" \
      --closes-handoff "$bundle" \
      --reviewed-at '2026-08-11T12:00:00+08:00' 2>&1) || {
    _fail "fresh checkpoint failed to close its consumed handoff: $checkpoint_out"; return;
  }
  list_out=$(python3 "$COLLECTOR" list-handoffs "$work" \
    --route proposal 2>&1) || {
    _fail "failed to list pending handoffs after checkpoint: $list_out"; return;
  }
  closed_list_out=$(python3 "$COLLECTOR" list-handoffs "$work" \
    --route proposal --include-closed 2>&1) || {
    _fail "failed to audit closed handoffs after checkpoint: $closed_list_out"; return;
  }
  if ! python3 - "$bundle" "$fresh_batch/review.json" "$checkpoint_out" \
    "$list_out" "$closed_list_out" <<'PY'
import json
import sys
from pathlib import Path

bundle_path = Path(sys.argv[1])
fresh_review = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
checkpoint = json.loads(sys.argv[3])
pending_list = json.loads(sys.argv[4])
closed_list = json.loads(sys.argv[5])
bundle = json.loads(bundle_path.read_text(encoding="utf-8"))
assert checkpoint["closed_handoffs"] == [str(bundle_path)]
assert Path(checkpoint["checkpoint"]).name == "checkpoint.json"
assert bundle["state"] == "closed"
assert bundle["phase"] == "closed"
assert [item["to"] for item in bundle["phase_history"]] == [
    "design", "lark_review", "closed",
]
assert bundle["module"] == "docs/modules/account-policy.md"
assert bundle["markdown_relative"] == "docs/modules/account-policy.md"
assert bundle["closure"]["batch_id"] == fresh_review["batch_id"]
assert pending_list["count"] == 0
assert pending_list["handoffs"] == []
assert closed_list["count"] == 1
assert closed_list["handoffs"][0]["state"] == "closed"
assert closed_list["handoffs"][0]["phase"] == "closed"
assert closed_list["handoffs"][0]["handoff_bundle"] == str(bundle_path)
assert closed_list["handoffs"][0]["closure"]["batch_id"] == fresh_review["batch_id"]
PY
  then
    _fail "handoff bundle did not transition from pending to closed"
    return
  fi
  pass_test
}

test_replan_handoff_blocks_old_batch_and_recovery_skips_it() {
  start_test "lark-review: replanned main batch becomes read-only and is skipped"
  local work="$BASE/replan-handoff-main"
  local review_root="$work/.pm-workflow/context/lark-review"
  local batch="$review_root/batch.main"
  local spec="$work/docs/modules/example/spec.md"
  local candidate="$work/.runs/replan-candidates/work-main-review.json"
  local head handoff_out scan_out seal_out apply_out target_scan_out resolutions_scan_out
  make_git_module_review_repo "$work"
  mkdir -p "$batch"
  python3 "$COLLECTOR" collect "$spec" --output-dir "$batch" >/dev/null || {
    _fail "failed to collect main handoff fixture"; return;
  }
  python3 "$COLLECTOR" reconcile --manifest "$batch/review.json" >/dev/null || {
    _fail "failed to draft main handoff fixture"; return;
  }
  head=$(git -C "$work" rev-parse HEAD)
  write_replan_candidate_manifest "$candidate" main proposal work-main-review \
    "$work" main "$head" "$head"

  if ! handoff_out=$(python3 "$COLLECTOR" handoff \
    --manifest "$batch/review.json" \
    --route proposal \
    --candidate-manifest "$candidate" 2>&1); then
    _fail "main handoff failed: $handoff_out"
    return
  fi
  if ! python3 - "$batch/handoff.json" "$batch/apply-plan.json" "$candidate" "$handoff_out" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

handoff = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
plan = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
candidate_hash = hashlib.sha256(Path(sys.argv[3]).read_bytes()).hexdigest()
result = json.loads(sys.argv[4])
assert handoff["state"] == "read_only"
assert handoff["route"] == "proposal"
assert handoff["candidate_manifest"]["mode"] == "main"
assert handoff["candidate_manifest"]["sha256"] == candidate_hash
assert plan["state"] == "handed_off"
assert plan["handoff"]["sha256"] == hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest()
assert result["status"] == "handed_off"
assert result["candidate_manifest_sha256"] == candidate_hash
PY
  then
    _fail "main handoff did not bind the exact candidate manifest"
    return
  fi

  if ! scan_out=$(python3 "$COLLECTOR" find-resumable "$spec" \
    --review-root "$review_root" 2>&1); then
    _fail "handoff recovery scan failed: $scan_out"
    return
  elif ! python3 - "$scan_out" <<'PY'
import json
import sys

result = json.loads(sys.argv[1])
assert result["status"] == "none"
assert result["resumable_count"] == 0
assert result["skipped_handoff_count"] == 1
assert result["skipped_handoffs"][0]["route"] == "proposal"
PY
  then
    _fail "recovery scan returned the read-only handoff as resumable: $scan_out"
    return
  fi

  seal_out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$batch/review.json" \
    --resolutions "$batch/resolutions.json" --seal 2>&1)
  if [ "$?" -eq 0 ] || ! echo "$seal_out" | grep -q "只读 handoff"; then
    _fail "handed-off batch must reject seal: $seal_out"
    return
  fi
  apply_out=$(python3 "$COLLECTOR" apply "$spec" \
    --plan "$batch/apply-plan.json" 2>&1)
  if [ "$?" -eq 0 ] || ! echo "$apply_out" | grep -q "只读 handoff"; then
    _fail "handed-off batch must reject apply: $apply_out"
    return
  fi

  cp "$batch/target.md" "$work/target.saved"
  printf '\nforged handoff target\n' >> "$batch/target.md"
  target_scan_out=$(python3 "$COLLECTOR" find-resumable "$spec" \
    --review-root "$review_root" 2>&1)
  if [ "$?" -eq 0 ] || ! echo "$target_scan_out" | grep -q "target.md 已变化"; then
    _fail "handoff target must remain immutable: $target_scan_out"
    return
  fi
  cp "$work/target.saved" "$batch/target.md"
  python3 - "$batch/resolutions.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
payload["forged_after_handoff"] = True
path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  resolutions_scan_out=$(python3 "$COLLECTOR" find-resumable "$spec" \
    --review-root "$review_root" 2>&1)
  if [ "$?" -eq 0 ] || ! echo "$resolutions_scan_out" | grep -q "resolutions.json 已变化"; then
    _fail "handoff resolutions must remain immutable: $resolutions_scan_out"
    return
  fi
  pass_test
}

test_replan_handoff_supports_linked_worktree_batches() {
  start_test "lark-review: 扁平功能规格绑定 active worktree 并生成持久 handoff"
  local main="$BASE/replan-handoff-worktree-main"
  local worktree="$BASE/replan-handoff-linked"
  local review_root="$worktree/.pm-workflow/context/lark-review"
  local batch="$review_root/batch.worktree"
  local moved_batch="$BASE/replan-handoff-linked-batch-moved"
  local main_spec="$main/docs/modules/account-policy.md"
  local spec="$worktree/docs/modules/account-policy.md"
  local candidate="$main/.runs/replan-candidates/work-linked-review.json"
  local head out resolve_out scan_out
  make_git_module_review_repo "$main"
  cp "$main/docs/modules/example/spec.md" "$main_spec"
  git -C "$main" add -- docs/modules/account-policy.md
  git -C "$main" commit -q -m "add flat functional specification"
  git -C "$main" worktree add -q -b build-handoff "$worktree" main
  python3 - "$worktree/docs/modules/example/.work-meta.json" <<'PY'
import json
import sys
from pathlib import Path

Path(sys.argv[1]).write_text(json.dumps({
    "id": "work-linked-review",
    "name": "flat functional review",
    "branch": "build-handoff",
    "stage": 2,
    "status": "active",
    "lifecycle_state": "iterating",
    "build": {
        "anchor": "docs/modules/account-policy.md",
        "branch": "build-handoff",
        "lifecycle_state": "iterating",
    },
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  git -C "$worktree" add -- docs/modules/example/.work-meta.json
  git -C "$worktree" commit -q -m "bind flat specification to active work"

  if ! resolve_out=$(python3 "$COLLECTOR" resolve-target "$main_spec" 2>&1); then
    _fail "flat functional target resolution failed: $resolve_out"
    return
  elif ! python3 - "$resolve_out" "$main" "$worktree" <<'PY'
import json
import sys
from pathlib import Path

result = json.loads(sys.argv[1])
main = str(Path(sys.argv[2]).resolve())
worktree = Path(sys.argv[3]).resolve()
assert result["markdown_path"] == str(worktree / "docs/modules/account-policy.md")
assert result["repo_root"] == str(worktree)
assert result["main_repo_root"] == main
assert result["active_work_dir"] == str(worktree / "docs/modules/example")
assert result["active_work_id"] == "work-linked-review"
PY
  then
    _fail "flat functional target did not bind the active worktree: $resolve_out"
    return
  fi

  mkdir -p "$batch"
  python3 "$COLLECTOR" collect "$spec" --output-dir "$batch" >/dev/null || {
    _fail "failed to collect worktree handoff fixture"; return;
  }
  python3 "$COLLECTOR" reconcile --manifest "$batch/review.json" >/dev/null || {
    _fail "failed to draft worktree handoff fixture"; return;
  }
  head=$(git -C "$worktree" rev-parse HEAD)
  write_replan_candidate_manifest "$candidate" worktree design work-linked-review \
    "$worktree" build-handoff "$head" "$head"

  if ! out=$(python3 "$COLLECTOR" handoff \
    --manifest "$batch/review.json" \
    --route design \
    --candidate-manifest "$candidate" 2>&1); then
    _fail "worktree handoff failed: $out"
    return
  elif ! python3 - "$batch/handoff.json" "$out" "$worktree" <<'PY'
import json
import sys
from pathlib import Path

handoff = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
result = json.loads(sys.argv[2])
assert handoff["candidate_manifest"]["mode"] == "worktree"
assert handoff["candidate_manifest"]["worktree"] == sys.argv[3]
assert handoff["candidate_manifest"]["route"] == "design"
assert result["route"] == "design"
PY
  then
    _fail "worktree handoff identity mismatch: $out"
    return
  fi
  if ! scan_out=$(python3 "$COLLECTOR" find-resumable "$spec" \
    --review-root "$review_root" 2>&1); then
    _fail "worktree recovery scan failed: $scan_out"
    return
  elif ! python3 - "$scan_out" <<'PY'
import json
import sys
result = json.loads(sys.argv[1])
assert result["status"] == "none"
assert result["skipped_handoff_count"] == 1
assert result["skipped_handoffs"][0]["route"] == "design"
PY
  then
    _fail "worktree handoff was not skipped by recovery: $scan_out"
    return
  fi
  mv "$batch" "$moved_batch"
  if [ -e "$batch" ]; then
    _fail "worktree handoff fixture was not moved away from its original batch path"
    return
  fi
  assert_pending_handoff_bundle \
    "$main" design "$out" "$moved_batch/review.json" 1 || return
  if ! python3 - "$main" "$moved_batch" <<'PY'
import json
import sys
from pathlib import Path

main = Path(sys.argv[1])
old_batch = Path(sys.argv[2])
review = json.loads((old_batch / "review.json").read_text(encoding="utf-8"))
bundle_dir = main / ".runs" / "lark-review-handoffs" / review["batch_id"]
bundle = json.loads((bundle_dir / "bundle.json").read_text(encoding="utf-8"))
copied_review = json.loads((bundle_dir / "review.json").read_text(encoding="utf-8"))
copied_handoff = json.loads((bundle_dir / "handoff.json").read_text(encoding="utf-8"))
copied_resolutions = json.loads(
    (bundle_dir / "resolutions.json").read_text(encoding="utf-8")
)
assert copied_review["batch_id"] == review["batch_id"]
assert copied_handoff["batch_id"] == review["batch_id"]
assert copied_handoff["route"] == "design"
assert copied_handoff["candidate_manifest"]["markdown_relative"] == "docs/modules/account-policy.md"
assert bundle["module"] == "docs/modules/example"
assert bundle["markdown_relative"] == "docs/modules/account-policy.md"
assert copied_resolutions["batch_id"] == review["batch_id"]
assert (bundle_dir / "target.md").read_text(encoding="utf-8").strip()
assert (bundle_dir / "remote.md").read_text(encoding="utf-8").strip()
PY
  then
    _fail "main handoff bundle could not be read after the worktree batch moved"
    return
  fi
  pass_test
}

test_replan_handoff_rejects_unverifiable_git_provenance() {
  start_test "lark-review: handoff rejects fake, unrelated, and unretained candidate commits"
  local work="$BASE/replan-handoff-invalid-git"
  local batch="$work/.pm-workflow/context/lark-review/batch.invalid-git"
  local spec="$work/docs/modules/example/spec.md"
  local candidate="$work/.runs/replan-candidates/work-invalid-review.json"
  local head tree unrelated descendant out plan_state
  make_git_module_review_repo "$work"
  mkdir -p "$batch"
  python3 "$COLLECTOR" collect "$spec" --output-dir "$batch" >/dev/null || {
    _fail "failed to collect invalid provenance fixture"; return;
  }
  python3 "$COLLECTOR" reconcile --manifest "$batch/review.json" >/dev/null || {
    _fail "failed to draft invalid provenance fixture"; return;
  }
  head=$(git -C "$work" rev-parse HEAD)
  tree=$(git -C "$work" rev-parse 'HEAD^{tree}')

  write_replan_candidate_manifest "$candidate" main proposal work-invalid-review \
    "$work" main ffffffffffffffffffffffffffffffffffffffff "$head"
  if out=$(python3 "$COLLECTOR" handoff \
    --manifest "$batch/review.json" --route proposal \
    --candidate-manifest "$candidate" 2>&1); then
    _fail "handoff accepted a nonexistent candidate commit"
    return
  elif ! echo "$out" | grep -q "candidate HEAD.*可读取的 commit"; then
    _fail "missing candidate commit should fail explicitly: $out"
    return
  fi

  write_replan_candidate_manifest "$candidate" main proposal work-invalid-review \
    "$work" main "$head" eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
  if out=$(python3 "$COLLECTOR" handoff \
    --manifest "$batch/review.json" --route proposal \
    --candidate-manifest "$candidate" 2>&1); then
    _fail "handoff accepted a nonexistent baseline commit"
    return
  elif ! echo "$out" | grep -q "baseline.*可读取的 commit"; then
    _fail "missing baseline commit should fail explicitly: $out"
    return
  fi

  unrelated=$(printf 'unrelated candidate\n' | git -C "$work" commit-tree "$tree")
  write_replan_candidate_manifest "$candidate" main proposal work-invalid-review \
    "$work" main "$unrelated" "$head"
  if out=$(python3 "$COLLECTOR" handoff \
    --manifest "$batch/review.json" --route proposal \
    --candidate-manifest "$candidate" 2>&1); then
    _fail "handoff accepted a baseline outside candidate ancestry"
    return
  elif ! echo "$out" | grep -q "baseline 不是 candidate HEAD 的祖先"; then
    _fail "non-ancestor baseline should fail explicitly: $out"
    return
  fi

  descendant=$(printf 'detached candidate\n' | git -C "$work" commit-tree "$tree" -p "$head")
  write_replan_candidate_manifest "$candidate" main proposal work-invalid-review \
    "$work" main "$descendant" "$head"
  if out=$(python3 "$COLLECTOR" handoff \
    --manifest "$batch/review.json" --route proposal \
    --candidate-manifest "$candidate" 2>&1); then
    _fail "handoff accepted a candidate no longer retained by main"
    return
  elif ! echo "$out" | grep -q "不再包含 candidate HEAD"; then
    _fail "unretained candidate should fail explicitly: $out"
    return
  fi

  plan_state=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' \
    "$batch/apply-plan.json")
  if [ "$plan_state" != "draft" ] || [ -e "$batch/handoff.json" ]; then
    _fail "failed provenance checks must not transition or mark the draft batch"
    return
  fi
  pass_test
}

test_replan_handoff_rejects_worktree_branch_drift() {
  start_test "lark-review: handoff requires the registered candidate worktree and branch"
  local main="$BASE/replan-handoff-drift-main"
  local worktree="$BASE/replan-handoff-drift-linked"
  local batch="$worktree/.pm-workflow/context/lark-review/batch.drift"
  local spec="$worktree/docs/modules/example/spec.md"
  local candidate="$main/.runs/replan-candidates/work-drift-review.json"
  local head out
  make_git_module_review_repo "$main"
  git -C "$main" worktree add -q -b build-drift "$worktree" main
  mkdir -p "$batch"
  python3 "$COLLECTOR" collect "$spec" --output-dir "$batch" >/dev/null || {
    _fail "failed to collect worktree drift fixture"; return;
  }
  python3 "$COLLECTOR" reconcile --manifest "$batch/review.json" >/dev/null || {
    _fail "failed to draft worktree drift fixture"; return;
  }
  head=$(git -C "$worktree" rev-parse HEAD)
  write_replan_candidate_manifest "$candidate" worktree design work-drift-review \
    "$worktree" build-drift "$head" "$head"
  git -C "$worktree" switch -q -c moved-drift

  if out=$(python3 "$COLLECTOR" handoff \
    --manifest "$batch/review.json" --route design \
    --candidate-manifest "$candidate" 2>&1); then
    _fail "handoff accepted a candidate after its worktree changed branches"
    return
  elif ! echo "$out" | grep -q "worktree/branch 已不存在或身份不一致"; then
    _fail "worktree branch drift should fail explicitly: $out"
    return
  fi
  if [ -e "$batch/handoff.json" ]; then
    _fail "worktree provenance failure must not create handoff.json"
    return
  fi
  pass_test
}

test_resolutions_are_bound_to_review_batch() {
  start_test "lark-review: resolutions 账本不能跨批次复用"
  local work="$BASE/foreign-resolution-batch"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["batch_id"] = "different-review-batch"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  local out rc
  out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '批次不匹配'; then
    _fail "foreign resolutions batch should fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_skill_contract
test_review_target_binds_the_active_worktree
test_collects_three_way_body_and_paginated_comments
test_collect_rejects_changes_during_comment_collection
test_collect_requires_repository_root_before_side_effects
test_checkpoint_is_separate_and_preserves_body
test_list_resumables_scans_main_and_attached_worktrees
test_checkpoint_requires_published_target_and_resolved_comments
test_checkpoint_rejects_remote_mismatch_and_new_unresolved_comment
test_checkpoint_rejects_reopened_out_of_batch_comment
test_checkpoint_rejects_solved_out_of_batch_comment
test_checkpoint_binds_system_result_reply
test_complete_comment_accepts_sparse_create_response
test_complete_comments_batches_full_scans_and_checkpoint_reuses_verification
test_reply_only_waits_for_pm_and_verifies_manual_solve
test_complete_comments_recovers_partial_batch_without_duplicate_replies
test_batch_final_read_failure_can_recover_and_reopen
test_checkpoint_failure_can_recollect_solved_comment
test_checkpoint_preserves_deferred_comments
test_content_deleted_can_be_superseded_instead_of_deferred
test_same_second_comment_uses_create_time_and_id_boundary
test_checkpoint_cursor_does_not_preconsume_comment_id
test_baseline_refresh_is_atomic
test_reconcile_seals_target_before_apply
test_decision_routing_is_explicit_and_selective
test_cross_decision_conflict_and_stale_receipt_block_seal
test_v3_ready_plan_resumes_original_flow_but_not_new_reply_only
test_nested_git_cannot_change_decision_write_boundary
test_manifest_markdown_parent_symlink_cannot_rebind_batch
test_artifact_io_parent_rebind_never_touches_outside
test_batch_entry_paths_never_pre_resolve_symlinks
test_repository_root_supports_worktree_git_file_and_requires_binding
test_repository_root_prefers_real_nested_worktree
test_applied_comment_requires_changed_lifecycle_target
test_apply_rejects_local_change_after_collect
test_apply_rejects_remote_or_comment_change
test_already_applied_rechecks_local_cas
test_manual_merge_requires_compiled_target
test_incompatible_remote_only_starts_target_from_native_remote
test_unassigned_remote_rewrite_blocks_seal
test_rewritten_remote_unit_requires_target
test_duplicate_remote_units_keep_independent_native_format_accounts
test_semantic_structure_changes_are_not_preserved
test_cross_section_duplicate_text_cannot_consume_wrong_unit
test_unique_cross_section_units_are_moved
test_comment_without_solved_time_can_checkpoint
test_verify_sync_preserves_native_format_and_resources
test_image_urls_use_resource_aware_projection
test_verify_sync_rejects_unsynced_markdown_structure
test_legacy_remote_coverage_schema_is_rejected
test_structural_remote_change_requires_preview_review
test_large_reorder_requires_pm_preview
test_legacy_solve_requested_without_write_ack_is_rejected
test_review_requires_cli_with_versioned_docs_skills
test_legacy_document_degrades_without_claiming_delta
test_recorded_revision_failure_is_fail_closed
test_recorded_revision_response_must_match_requested_revision
test_current_markdown_and_xml_must_share_revision
test_doc_argument_must_match_frontmatter_url
test_collect_rejects_unbound_local_document
test_checkpoint_rejects_rebound_document
test_baseline_accepts_url_only_and_rejects_revision_rollback
test_legacy_doc_url_is_rejected_before_comment_collection
test_invalid_pagination_is_fail_closed
test_malformed_comment_pages_are_fail_closed
test_torn_solved_state_scan_retries_to_stability
test_product_handoff_without_active_build_is_read_only
test_fresh_checkpoint_closes_product_handoff_bundle
test_replan_handoff_blocks_old_batch_and_recovery_skips_it
test_replan_handoff_supports_linked_worktree_batches
test_replan_handoff_rejects_unverifiable_git_provenance
test_replan_handoff_rejects_worktree_branch_drift
test_resolutions_are_bound_to_review_batch

report_results "lark-review"
