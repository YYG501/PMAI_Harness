#!/usr/bin/env bash
# Read-only consumer topology, document placement, project definition, and mockup checks.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/consumer-doctor.py"
ENTRY_SYNC="$REPO_ROOT/scripts/sync-consumer-entry.py"
INIT="$REPO_ROOT/scripts/init-project.sh"
PROJECT_DEFINITION="$REPO_ROOT/scripts/project-definition.py"
PROPOSAL_CONTRACT="$REPO_ROOT/scripts/proposal-contract.py"
MOCK_BOARD="$REPO_ROOT/scripts/gen-mock-board.py"
MOCK_QUALITY="$REPO_ROOT/scripts/mockup-quality.py"
CLEANUP_ROOT=$(mktemp -d /tmp/pmai-consumer-doctor-suite.XXXXXX)

cleanup() {
  rm -rf -- "$CLEANUP_ROOT"
}
trap cleanup EXIT

new_consumer() {
  local base repo
  base=$(mktemp -d "$CLEANUP_ROOT/fixture.XXXXXX") || return 1
  repo="$base/repo"
  if ! bash "$INIT" DoctorFixture "$repo" "consumer doctor fixture" >/dev/null 2>&1; then
    return 1
  fi
  printf '%s\n' "$repo"
}

audit() {
  python3 "$CHECKER" --repo-root "$1"
}

commit_fixture() {
  local repo="$1"
  git -C "$repo" add -A >/dev/null \
    && git -C "$repo" commit --no-verify -m "test: update fixture" >/dev/null
}

make_layout_unversioned() {
  local repo="$1" replacement
  replacement="${repo%/}/.pm-workflow/config.yml.unversioned"
  sed -n '/^builder:/,$p' "$repo/.pm-workflow/config.yml" > "$replacement" \
    && mv "$replacement" "$repo/.pm-workflow/config.yml"
}

test_fresh_consumer_is_current_and_read_only() {
  start_test "consumer-doctor: fresh init is current and check is read-only"
  local repo before after out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  before=$(git -C "$repo" status --porcelain=v1 --untracked-files=all)
  out=$(audit "$repo") || { _fail "fresh audit failed"; return; }
  after=$(git -C "$repo" status --porcelain=v1 --untracked-files=all)
  if [ "$before" != "$after" ] || ! python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "current"
assert payload["phase"] == "initialized"
assert payload["summary"] == {"error": 0, "sync": 0, "warning": 0}
assert payload["project_definition"]["state"] == "absent"
assert payload["proposal"]["state"] == "required"
assert payload["entry_contract"]["status"] == "current"
PY
  then
    _fail "fresh consumer should be current and unchanged"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_current_proposal_is_verified_and_drift_is_invalid() {
  start_test "consumer-doctor: accepted Proposal is verified and body drift is invalid"
  local repo current drifted
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  cat > "$repo/docs/proposals/demo-v1.md" <<'EOF'
# Demo Product Proposal

> 版本：v1
> Proposal ID：demo-v1
> 状态：当前
> 日期：2026-08-10
> 取代：无
> 支持的决定：是否投入一次可验证的审核闭环
> 证据截至：2026-08-10

## 0. 决策摘要与产品主张

为负责人提供可追溯的审核建议。

## 1. 产品成立的核心判断

负责人需要在提交前获得可追溯证据。

## 2. 用户、场景、问题与现状替代

负责人当前依靠人工搜索材料完成审核。

## 3. 产品回答与职责边界

产品聚合证据并给建议，最终结论仍由人确认。

## 4. 必要能力与 AI 角色

AI 分析材料，确定性系统执行门禁。

## 5. 替代方案、竞争判断与产品机会

现状替代是人工检索，机会在于减少遗漏。

## 6. 端到端产品体验与关键能力

从收到任务到核对证据并提交结论形成闭环。

## 7. 产品价值、因果链与指标

更完整的证据促成更可靠的审核行动。

## 8. MVP 范围、完整案例与决策门

先验证一个审核案例，不能改善结果时停止扩大投入。

## 9. 演进条件与长期方向

只有主案例成立后才扩展更多场景。

## 10. 下游交接摘要

- **第一个 design 目标**：完成审核闭环
- **主用户与触发时刻**：负责人收到审核任务时
- **要闭合的核心任务**：提交审核结论
- **必须保持的产品回答**：先聚合证据再给建议
- **必须保持的产品边界**：最终结论由人确认
- **MVP 必须证明**：建议促成有效行动
- **仍待验证的假设**：负责人愿意查看建议
- **design 需要收敛**：对象、动作、状态、权限和异常路径
EOF
  cat > "$repo/PRODUCT.md" <<'EOF'
# Product

## 当前 Product Proposal

[demo-v1](docs/proposals/demo-v1.md)

## 产品定位

为负责人提供可追溯审核建议的产品。

## 核心问题与价值

减少人工检索遗漏，帮助负责人作出可靠审核行动。

## 用户画像

对审核结果负责的业务负责人。

## 产品边界

产品给出建议，最终结论由人确认。

## MVP Case

负责人收到任务后核对证据、确认建议并提交结论。
EOF
  cat > "$repo/docs/proposals/INDEX.md" <<'EOF'
# Product Proposal 索引

| 文档 | 版本 | 状态 | 取代 | 决策日期 | 下游起点 |
|---|---|---|---|---|---|
| [`demo-v1.md`](demo-v1.md) | v1 | 当前 | 无 | 2026-08-10 | 审核闭环 |
EOF
  python3 "$PROPOSAL_CONTRACT" accept "$repo" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "proposal fixture should be accepted"
      return
    }
  commit_fixture "$repo" || { _fail "proposal fixture commit failed"; return; }
  current=$(audit "$repo") || { _fail "accepted proposal audit failed"; return; }
  printf '\n未经确认的变化。\n' >> "$repo/docs/proposals/demo-v1.md"
  drifted=$(audit "$repo") || { _fail "drifted proposal audit failed"; return; }
  if python3 - "$current" "$drifted" <<'PY'
import json, sys
current, drifted = (json.loads(value) for value in sys.argv[1:])
assert current["status"] == "current"
assert current["proposal"] == {
    "state": "accepted",
    "id": "demo-v1",
    "path": "docs/proposals/demo-v1.md",
    "supersedes": None,
}
assert drifted["status"] == "invalid"
assert drifted["proposal"]["state"] == "invalid"
assert "proposal_contract_invalid" in {item["code"] for item in drifted["findings"]}
PY
  then
    pass_test
  else
    _fail "doctor did not enforce current Proposal integrity"
    echo "$current" >&2
    echo "$drifted" >&2
  fi
}

test_missing_and_misplaced_documents_are_reported() {
  start_test "consumer-doctor: missing spine and misplaced docs are distinct"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  rm -f "$repo/PRODUCT-RULES.md"
  printf '# loose PRD\n' > "$repo/docs/loose-prd.md"
  out=$(audit "$repo") || { _fail "document audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
codes = {item["code"] for item in payload["findings"]}
assert payload["status"] == "invalid"
assert "missing_required_file" in codes
assert "misplaced_docs_markdown" in codes
PY
  then
    pass_test
  else
    _fail "missing and misplaced documents were not classified"
    echo "$out" >&2
  fi
}

prepare_ready_project() {
  local repo="$1" sentinel="$2"
  mkdir -p "$repo/docs/modules/demo" "$repo/apps/web"
  printf '# Discussion\n' > "$repo/docs/modules/demo/discussion.md"
  printf '# Decisions\n' > "$repo/docs/modules/demo/decisions.md"
  printf '# Spec\n' > "$repo/docs/modules/demo/spec.md"
  printf 'export const demo = true;\n' > "$repo/apps/web/index.ts"
  python3 "$PROJECT_DEFINITION" write "$repo" \
    --source docs/modules/demo/spec.md \
    --type prototype \
    --root apps/web \
    --entrypoint apps/web \
    --language typescript \
    --runtime node \
    --framework nextjs \
    --package-manager pnpm \
    --test-command "touch $sentinel" >/dev/null || return 1
  cat > "$repo/docs/modules/demo/.work-meta.json" <<'JSON'
{
  "id": "work-demo",
  "name": "demo",
  "status": "active",
  "stage": 1,
  "lifecycle_state": "ready_to_build",
  "design_revision": 1,
  "approved_source_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "design_checkpoint_commit": "fixture",
  "approved_target": {"paths": ["apps/web"]}
}
JSON
  commit_fixture "$repo"
}

test_project_definition_drives_custom_implementation_location() {
  start_test "consumer-doctor: project.yml drives implementation location without executing commands"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/command-was-executed"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  printf '# Spec changed without construction plan change\n' > "$repo/docs/modules/demo/spec.md"
  out=$(audit "$repo") || { _fail "project definition audit failed"; return; }
  if [ -e "$sentinel" ] || ! python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
codes = {item["code"] for item in payload["findings"]}
assert payload["status"] == "current"
assert payload["phase"] == "ready_to_build"
assert payload["project_definition"]["root"] == "apps/web"
assert payload["project_definition"]["entrypoints"] == ["apps/web"]
assert not any("source_hash" in code for code in codes)
PY
  then
    _fail "custom implementation location or command safety check failed"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_ready_contract_gap_is_progress_only() {
  start_test "consumer-doctor: incomplete ready scope is progress guidance, not repository damage"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/unused-ready-gap"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  python3 - "$repo/docs/modules/demo/.work-meta.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)
payload.pop("approved_target", None)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(audit "$repo") || { _fail "ready gap audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
finding = next(item for item in payload["findings"] if item["code"] == "ready_target_missing")
assert payload["status"] == "current"
assert finding["level"] == "warning"
assert finding["kind"] == "project_advisory"
assert finding["blocking"] is False
PY
  then
    pass_test
  else
    _fail "an incomplete ready scope should only block that module from starting"
    echo "$out" >&2
  fi
}

test_unknown_module_file_is_not_mislabeled_as_a_spec() {
  start_test "consumer-doctor: unknown module files are reported once without calling them specs"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  printf 'finder metadata\n' > "$repo/docs/modules/.DS_Store"
  out=$(audit "$repo") || { _fail "unknown module file audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
findings = [item for item in payload["findings"] if item.get("path") == "docs/modules/.DS_Store"]
assert [item["code"] for item in findings] == ["modules_unknown_file"]
PY
  then
    pass_test
  else
    _fail "an unknown file should not also be called an untracked functional spec"
    echo "$out" >&2
  fi
}

test_stale_consumer_entry_is_machine_detectable() {
  start_test "consumer-doctor: old AGENTS startup rule is detected without rewriting it"
  local repo before after out entry_out missing_out rc
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sed 's/install-project-hooks\.sh/install-codex-hooks.sh/g; s/ --check//g' \
    "$repo/AGENTS.md" > "$repo/AGENTS.md.old" \
    && mv "$repo/AGENTS.md.old" "$repo/AGENTS.md"
  before=$(git -C "$repo" status --porcelain=v1 --untracked-files=all)
  out=$(audit "$repo") || { _fail "stale entry audit failed"; return; }
  entry_out=$(python3 "$CHECKER" --repo-root "$repo" --entry-only)
  rc=$?
  after=$(git -C "$repo" status --porcelain=v1 --untracked-files=all)
  if [ "$rc" != "1" ] || [ "$before" != "$after" ] || ! python3 - "$out" "$entry_out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
entry = json.loads(sys.argv[2])
assert payload["status"] == "sync_required"
assert entry["status"] == "stale"
finding = next(item for item in payload["findings"] if item["code"] == "host_rules_stale")
assert finding["repair_action"] == {
    "id": "sync_consumer_entry",
    "target": "AGENTS.md",
    "availability": "automatic",
    "confirmation_required": True,
}
PY
  then
    _fail "old startup rules should be reported by the shared read-only check"
    echo "$out" >&2
    echo "$entry_out" >&2
    return
  fi
  rm "$repo/AGENTS.md"
  missing_out=$(python3 "$CHECKER" --repo-root "$repo" --entry-only)
  rc=$?
  if [ "$rc" != "2" ] || ! python3 - "$missing_out" <<'PY'
import json
import sys

assert json.loads(sys.argv[1])["status"] == "missing"
PY
  then
    _fail "missing AGENTS.md should be distinct from an outdated startup rule"
    echo "$missing_out" >&2
    return
  fi
  pass_test
}

test_consumer_entry_sync_is_read_only_scoped_and_idempotent() {
  start_test "consumer entry sync: check is read-only and apply only replaces the managed block"
  local repo before after check_out apply_out first_hash second_hash rc
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  printf '\n## Project Custom Rules\n\nPRESERVE_PROJECT_SENTINEL\n' >> "$repo/AGENTS.md"
  sed 's/install-project-hooks\.sh/install-codex-hooks.sh/g; s/ --check//g' \
    "$repo/AGENTS.md" > "$repo/AGENTS.md.old" \
    && mv "$repo/AGENTS.md.old" "$repo/AGENTS.md"

  before=$(shasum -a 256 "$repo/AGENTS.md" | awk '{print $1}')
  check_out=$(python3 "$ENTRY_SYNC" --repo-root "$repo" --check)
  rc=$?
  after=$(shasum -a 256 "$repo/AGENTS.md" | awk '{print $1}')
  if [ "$rc" != "1" ] || [ "$before" != "$after" ] || ! python3 - "$check_out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "stale"
assert payload["strategy"] == "managed_block"
assert payload["changed"] is False
PY
  then
    _fail "--check should report stale managed content without writing"
    echo "$check_out" >&2
    return
  fi

  apply_out=$(python3 "$ENTRY_SYNC" --repo-root "$repo" --apply)
  rc=$?
  first_hash=$(shasum -a 256 "$repo/AGENTS.md" | awk '{print $1}')
  if [ "$rc" != "0" ] \
    || ! grep -q 'PRESERVE_PROJECT_SENTINEL' "$repo/AGENTS.md" \
    || ! grep -q '<!-- PMAI:BEGIN consumer-startup -->' "$repo/AGENTS.md" \
    || ! grep -q 'install-project-hooks.sh' "$repo/AGENTS.md" \
    || ! grep -q -- '--check' "$repo/AGENTS.md" \
    || ! python3 - "$apply_out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "updated"
assert payload["strategy"] == "managed_block"
assert payload["changed"] is True
PY
  then
    _fail "--apply should update only the managed block and preserve project content"
    echo "$apply_out" >&2
    return
  fi

  apply_out=$(python3 "$ENTRY_SYNC" --repo-root "$repo" --apply)
  rc=$?
  second_hash=$(shasum -a 256 "$repo/AGENTS.md" | awk '{print $1}')
  if [ "$rc" != "0" ] || [ "$first_hash" != "$second_hash" ]; then
    _fail "repeated --apply should be idempotent"
    echo "$apply_out" >&2
    return
  fi
  pass_test
}

test_consumer_entry_sync_migrates_known_legacy_rules_and_keeps_custom_items() {
  start_test "consumer entry sync: known unmarked startup rules migrate without dropping project additions"
  local repo replacement out rc
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  replacement="$repo/AGENTS.md.legacy"
  awk '
    /<!-- PMAI:BEGIN consumer-startup -->/ {next}
    /<!-- PMAI:END consumer-startup -->/ {
      print "7. PRESERVE_LEGACY_PROJECT_STARTUP"
      next
    }
    {print}
  ' "$repo/AGENTS.md" > "$replacement" && mv "$replacement" "$repo/AGENTS.md"

  out=$(python3 "$ENTRY_SYNC" --repo-root "$repo" --check)
  rc=$?
  if [ "$rc" != "1" ] || ! python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "stale"
assert payload["strategy"] == "legacy_migration"
PY
  then
    _fail "known unmarked startup rules should be safely migratable"
    echo "$out" >&2
    return
  fi

  out=$(python3 "$ENTRY_SYNC" --repo-root "$repo" --apply)
  rc=$?
  if [ "$rc" != "0" ] \
    || ! grep -q 'PRESERVE_LEGACY_PROJECT_STARTUP' "$repo/AGENTS.md" \
    || ! grep -q '<!-- PMAI:BEGIN consumer-startup -->' "$repo/AGENTS.md" \
    || ! grep -q '### 项目启动补充' "$repo/AGENTS.md"; then
    _fail "legacy migration should preserve project-specific startup content outside the managed block"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_consumer_entry_sync_rejects_unsafe_shapes() {
  start_test "consumer entry sync: malformed markers, unknown legacy PMAI rules, and symlinks fail closed"
  local malformed misplaced unknown linked replacement before after out rc
  malformed=$(new_consumer) || { _fail "malformed fixture init failed"; return; }
  printf '\n<!-- PMAI:BEGIN consumer-startup -->\n' >> "$malformed/AGENTS.md"
  before=$(shasum -a 256 "$malformed/AGENTS.md" | awk '{print $1}')
  out=$(python3 "$ENTRY_SYNC" --repo-root "$malformed" --apply 2>/dev/null)
  rc=$?
  after=$(shasum -a 256 "$malformed/AGENTS.md" | awk '{print $1}')
  if [ "$rc" != "2" ] || [ "$before" != "$after" ]; then
    _fail "malformed managed markers must be rejected without writing"
    return
  fi

  misplaced=$(new_consumer) || { _fail "misplaced fixture init failed"; return; }
  replacement="$misplaced/AGENTS.md.misplaced"
  sed '/<!-- PMAI:BEGIN consumer-startup -->/d; /<!-- PMAI:END consumer-startup -->/d' \
    "$misplaced/AGENTS.md" > "$replacement" && mv "$replacement" "$misplaced/AGENTS.md"
  printf '\n<!-- PMAI:BEGIN consumer-startup -->\nmisplaced\n<!-- PMAI:END consumer-startup -->\n' \
    >> "$misplaced/AGENTS.md"
  before=$(shasum -a 256 "$misplaced/AGENTS.md" | awk '{print $1}')
  out=$(python3 "$ENTRY_SYNC" --repo-root "$misplaced" --apply 2>/dev/null)
  rc=$?
  after=$(shasum -a 256 "$misplaced/AGENTS.md" | awk '{print $1}')
  if [ "$rc" != "2" ] || [ "$before" != "$after" ]; then
    _fail "managed markers outside the Startup section must be rejected without writing"
    return
  fi

  unknown=$(new_consumer) || { _fail "unknown fixture init failed"; return; }
  replacement="$unknown/AGENTS.md.legacy"
  awk '
    /<!-- PMAI:BEGIN consumer-startup -->/ {next}
    /<!-- PMAI:END consumer-startup -->/ {
      print "7. 执行未知的 /pmai-mystery 旧入口规则。"
      next
    }
    {print}
  ' "$unknown/AGENTS.md" > "$replacement" && mv "$replacement" "$unknown/AGENTS.md"
  before=$(shasum -a 256 "$unknown/AGENTS.md" | awk '{print $1}')
  out=$(python3 "$ENTRY_SYNC" --repo-root "$unknown" --apply 2>/dev/null)
  rc=$?
  after=$(shasum -a 256 "$unknown/AGENTS.md" | awk '{print $1}')
  if [ "$rc" != "2" ] || [ "$before" != "$after" ]; then
    _fail "unknown PMAI legacy rules must require manual review"
    return
  fi

  linked=$(new_consumer) || { _fail "symlink fixture init failed"; return; }
  mv "$linked/AGENTS.md" "$linked/AGENTS.real.md"
  ln -s AGENTS.real.md "$linked/AGENTS.md"
  out=$(python3 "$ENTRY_SYNC" --repo-root "$linked" --apply 2>/dev/null)
  rc=$?
  if [ "$rc" != "2" ] || [ ! -L "$linked/AGENTS.md" ]; then
    _fail "AGENTS.md symlink must be rejected without replacing it"
    return
  fi
  pass_test
}

test_missing_implementation_entrypoint_blocks_build_recovery() {
  start_test "consumer-doctor: missing implementation entrypoint invalidates active build"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/unused"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  rm -rf "$repo/apps/web"
  cat > "$repo/docs/modules/demo/.work-meta.json" <<'JSON'
{
  "id": "work-demo",
  "name": "demo",
  "status": "active",
  "stage": 1,
  "lifecycle_state": "building",
  "build": {
    "contract_version": 1,
    "lifecycle_state": "building",
    "mode": "main",
    "target": {"kind": "prototype", "paths": ["apps/web"], "entrypoints": ["apps/web"]}
  }
}
JSON
  out=$(audit "$repo") || { _fail "missing implementation audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
codes = {item["code"] for item in payload["findings"]}
assert payload["status"] == "invalid"
assert "implementation_root_invalid" in codes
PY
  then
    pass_test
  else
    _fail "missing implementation root should invalidate active build"
    echo "$out" >&2
  fi
}

prepare_valid_mockups() {
  local repo="$1"
  mkdir -p "$repo/mockups/approach-a"
  printf '<main>Approach A</main>\n' > "$repo/mockups/approach-a/index.html"
  cat > "$repo/mockups/manifest.json" <<'JSON'
{
  "variants": [
    {
      "path": "approach-a/index.html",
      "requirement": "demo",
      "title": "Approach A",
      "explores": "task flow",
      "good_parts": "clear state",
      "status": "活跃",
      "round": "第一轮",
      "featured": false
    }
  ]
}
JSON
  python3 "$MOCK_BOARD" "$repo" >/dev/null || return 1
  commit_fixture "$repo"
}

test_mockup_manifest_assets_and_board_are_checked() {
  start_test "consumer-doctor: mockup manifest paths and generated board stay aligned"
  local repo current stale invalid replacement
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  prepare_valid_mockups "$repo" || { _fail "mockup fixture failed"; return; }
  current=$(audit "$repo") || { _fail "valid mockup audit failed"; return; }
  replacement="$repo/mockups/manifest.json.tmp"
  sed 's/task flow/updated task flow/' "$repo/mockups/manifest.json" > "$replacement" \
    && mv "$replacement" "$repo/mockups/manifest.json" \
    || { _fail "mockup manifest update failed"; return; }
  stale=$(audit "$repo") || { _fail "stale board audit failed"; return; }
  sed 's#approach-a/index.html#../outside.html#' "$repo/mockups/manifest.json" > "$replacement" \
    && mv "$replacement" "$repo/mockups/manifest.json" \
    || { _fail "mockup path update failed"; return; }
  invalid=$(audit "$repo") || { _fail "invalid mockup path audit failed"; return; }
  if python3 - "$current" "$stale" "$invalid" <<'PY'
import json
import sys

current, stale, invalid = (json.loads(value) for value in sys.argv[1:])
assert current["status"] == "current"
assert current["mockups"] == {"state": "current", "variants": 1}
assert "mockup_board_stale" in {item["code"] for item in stale["findings"]}
assert invalid["status"] == "invalid"
assert "mockup_variant_path" in {item["code"] for item in invalid["findings"]}
PY
  then
    pass_test
  else
    _fail "mockup topology findings mismatch"
  fi
}

test_mockup_current_schema_is_complete_and_timestamped() {
  start_test "consumer-doctor: current mockup schema requires complete comparison fields and timestamps"
  local repo current incomplete invalid replacement
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  mkdir -p "$repo/mockups/approach-a"
  printf '<main>Approach A</main>\n' > "$repo/mockups/approach-a/index.html"
  cat > "$repo/mockups/manifest.json" <<'JSON'
{
  "variants": [
    {
      "path": "approach-a/index.html",
      "requirement": "demo",
      "title": "Approach A",
      "approach": "task flow",
      "best_for": "focused review",
      "tradeoffs": "longer page",
      "explores": "task flow",
      "good_parts": "focused review",
      "status": "活跃",
      "round": "第一轮",
      "round_goal": "choose a review path",
      "created_at": "2026-08-13T10:00+08:00",
      "updated_at": "2026-08-13T10:00+08:00",
      "featured": false
    }
  ]
}
JSON
  python3 "$MOCK_BOARD" "$repo" >/dev/null || { _fail "mockup board generation failed"; return; }
  commit_fixture "$repo"
  current=$(audit "$repo") || { _fail "current schema audit failed"; return; }

  replacement="$repo/mockups/manifest.json.tmp"
  sed '/"tradeoffs":/d' "$repo/mockups/manifest.json" > "$replacement" \
    && mv "$replacement" "$repo/mockups/manifest.json" \
    || { _fail "incomplete schema update failed"; return; }
  incomplete=$(audit "$repo") || { _fail "incomplete schema audit failed"; return; }

  git -C "$repo" show HEAD:mockups/manifest.json > "$repo/mockups/manifest.json"
  sed 's/2026-08-13T10:00+08:00/not-a-time/' "$repo/mockups/manifest.json" > "$replacement" \
    && mv "$replacement" "$repo/mockups/manifest.json" \
    || { _fail "invalid timestamp update failed"; return; }
  invalid=$(audit "$repo") || { _fail "invalid timestamp audit failed"; return; }

  if python3 - "$current" "$incomplete" "$invalid" <<'PY'
import json
import sys

current, incomplete, invalid = (json.loads(value) for value in sys.argv[1:])
assert current["status"] == "current"
assert "mockup_variant_current_fields" in {item["code"] for item in incomplete["findings"]}
assert "mockup_variant_timestamp" in {item["code"] for item in invalid["findings"]}
PY
  then
    pass_test
  else
    _fail "current mockup schema findings mismatch"
  fi
}

test_mockup_quality_schema_requires_evidence_paths() {
  start_test "consumer-doctor: schema v2 requires design basis and visual audit"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  mkdir -p "$repo/mockups/approach-a"
  printf '<main>Approach A</main>\n' > "$repo/mockups/approach-a/index.html"
  cat > "$repo/mockups/manifest.json" <<'JSON'
{
  "variants": [{
    "schema_version": 2,
    "path": "approach-a/index.html",
    "requirement": "demo",
    "title": "Approach A",
    "approach": "task flow",
    "best_for": "focused review",
    "tradeoffs": "longer page",
    "explores": "task flow",
    "good_parts": "focused review",
    "status": "活跃",
    "round": "第一轮",
    "round_goal": "choose a review path",
    "created_at": "2026-08-13T10:00+08:00",
    "updated_at": "2026-08-13T10:00+08:00",
    "featured": false
  }]
}
JSON
  commit_fixture "$repo"
  out=$(audit "$repo") || { _fail "quality schema audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "invalid"
assert "mockup_quality_fields" in {item["code"] for item in payload["findings"]}
PY
  then
    pass_test
  else
    _fail "schema v2 should require quality evidence paths"
  fi
}

test_mockup_quality_evidence_is_verified_and_invalidated() {
  start_test "consumer-doctor: mockup 质量证据通过，DESIGN 漂移后失效"
  local repo current stale
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  mkdir -p "$repo/src" "$repo/mockups/demo" "$repo/mockups/audits/demo/round-1"
  printf '<main>Existing shell</main>\n' > "$repo/src/shell.html"
  printf '<main>Mockup</main>\n' > "$repo/mockups/demo/index.html"
  if ! python3 "$MOCK_QUALITY" compile \
      --repo "$repo" \
      --requirement "demo" \
      --round "第一轮" \
      --round-goal "先看判断结果" \
      --reference "src/shell.html" \
      --must-inherit "继承当前体验目标" \
      --reuse "复用现有应用外壳" \
      --may-change "允许调整内容区层级" \
      --guardrail "首屏减少同级信息竞争" \
      --out "mockups/audits/demo/round-1/design-basis.json" >/dev/null; then
    _fail "quality contract compile failed"
    return
  fi
  python3 - "$repo" <<'PY'
import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path

root = Path(sys.argv[1])
audit_dir = root / "mockups/audits/demo/round-1"

def png(path, width, height):
    raw = b"".join(b"\x00" + b"\xff\xff\xff" * width for _ in range(height))
    def chunk(name, payload):
        return struct.pack(">I", len(payload)) + name + payload + struct.pack(">I", zlib.crc32(name + payload) & 0xffffffff)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 1))
        + chunk(b"IEND", b"")
    )

desktop = audit_dir / "desktop.png"
narrow = audit_dir / "narrow.png"
png(desktop, 1024, 640)
png(narrow, 390, 640)
contract = audit_dir / "design-basis.json"
checks = {
    "design-principles",
    "existing-shell-and-components",
    "information-hierarchy",
    "task-path-and-states",
    "responsive-layout",
    "text-and-controls",
}
constraints = {"must-inherit-1", "reuse-1", "may-change-1", "guardrail-1"}
report = {
    "schema_version": 1,
    "kind": "mockup-visual-audit",
    "design_basis": "mockups/audits/demo/round-1/design-basis.json",
    "design_basis_sha256": hashlib.sha256(contract.read_bytes()).hexdigest(),
    "audited_at": "2026-08-13T18:00:00+08:00",
    "browser_adapter": "playwright",
    "variants": [{
        "path": "mockups/demo/index.html",
        "screenshots": {
            "desktop": {"path": "mockups/audits/demo/round-1/desktop.png", "width": 1024, "height": 640, "sha256": hashlib.sha256(desktop.read_bytes()).hexdigest(), "captured_at": "2026-08-13T17:55:00+08:00"},
            "narrow": {"path": "mockups/audits/demo/round-1/narrow.png", "width": 390, "height": 640, "sha256": hashlib.sha256(narrow.read_bytes()).hexdigest(), "captured_at": "2026-08-13T17:56:00+08:00"},
        },
        "checks": [{"id": item, "status": "pass", "evidence": f"checked {item}"} for item in sorted(checks)],
        "constraint_results": [{"id": item, "status": "pass", "evidence": f"checked {item}"} for item in sorted(constraints)],
        "observations": ["主任务优先，窄屏没有遮挡。"],
    }],
}
(audit_dir / "visual-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
manifest = {
    "variants": [{
        "schema_version": 2,
        "path": "demo/index.html",
        "requirement": "demo",
        "title": "结果优先",
        "approach": "先展示判断结果",
        "best_for": "快速处理任务",
        "tradeoffs": "过程信息需要下钻",
        "explores": "先展示判断结果",
        "good_parts": "快速处理任务",
        "status": "活跃",
        "round": "第一轮",
        "round_goal": "先看判断结果",
        "created_at": "2026-08-13T18:00:00+08:00",
        "updated_at": "2026-08-13T18:00:00+08:00",
        "design_basis": "audits/demo/round-1/design-basis.json",
        "visual_audit": "audits/demo/round-1/visual-audit.json",
        "featured": False,
    }]
}
(root / "mockups/manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  python3 "$MOCK_BOARD" "$repo" >/dev/null || { _fail "mockup board generation failed"; return; }
  commit_fixture "$repo" || { _fail "quality fixture commit failed"; return; }
  current=$(audit "$repo") || { _fail "current quality audit failed"; return; }
  printf '\n- 设计基线变化\n' >> "$repo/DESIGN.md"
  stale=$(audit "$repo") || { _fail "stale quality audit failed"; return; }

  if python3 - "$current" "$stale" <<'PY'
import json
import sys

current, stale = (json.loads(value) for value in sys.argv[1:])
assert current["status"] == "current"
assert stale["status"] == "invalid"
assert "mockup_quality_invalid" in {item["code"] for item in stale["findings"]}
PY
  then
    pass_test
  else
    _fail "mockup quality currentness findings mismatch"
  fi
}

test_secret_config_is_never_echoed() {
  start_test "consumer-doctor: tracked secret config is blocked without reading or echoing token"
  local repo out token
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  token="PMAI_DOCTOR_SECRET_DO_NOT_PRINT"
  printf '{"prd":{"token":"%s"}}\n' "$token" > "$repo/.claude/lark-publish.json"
  git -C "$repo" add -f .claude/lark-publish.json >/dev/null
  git -C "$repo" commit --no-verify -m "test: tracked secret" >/dev/null
  out=$(audit "$repo") || { _fail "secret audit failed"; return; }
  if [[ "$out" == *"$token"* ]]; then
    _fail "doctor leaked secret config content"
  elif python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "invalid"
assert "secret_config_tracked" in {item["code"] for item in payload["findings"]}
PY
  then
    pass_test
  else
    _fail "tracked secret config was not blocked"
  fi
}

test_legacy_layout_requires_sync_not_structural_repair() {
  start_test "consumer-doctor: legacy task layout is a sync finding"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  mkdir -p "$repo/requirements/active"
  out=$(audit "$repo") || { _fail "legacy audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "sync_required"
assert "legacy_layout" in {item["code"] for item in payload["findings"]}
PY
  then
    pass_test
  else
    _fail "legacy layout should request explicit migration"
  fi
}

test_non_git_and_symlinked_truth_sources_fail_closed() {
  start_test "consumer-doctor: non-Git PMAI markers and symlinked truth sources fail closed"
  local base repo non_git symlinked
  base=$(mktemp -d "$CLEANUP_ROOT/non-git.XXXXXX") || { _fail "temp dir failed"; return; }
  printf '# PMAI consumer marker\n' > "$base/PRODUCT-STATE.md"
  non_git=$(audit "$base") || true

  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  mv "$repo/PRODUCT.md" "$repo/PRODUCT.real.md"
  ln -s PRODUCT.real.md "$repo/PRODUCT.md"
  symlinked=$(audit "$repo") || true
  if python3 - "$non_git" "$symlinked" <<'PY'
import json
import sys

non_git, symlinked = (json.loads(value) for value in sys.argv[1:])
assert non_git["status"] == "invalid"
assert "not_git_repository" in {item["code"] for item in non_git["findings"]}
assert symlinked["status"] == "invalid"
assert "managed_path_symlink" in {item["code"] for item in symlinked["findings"]}
PY
  then
    pass_test
  else
    _fail "repository identity or symlink boundary did not fail closed"
  fi
}

test_active_build_must_match_project_definition() {
  start_test "consumer-doctor: active build target must match project.yml type and entrypoints"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/unused-mismatch"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  cat > "$repo/docs/modules/demo/.work-meta.json" <<'JSON'
{
  "id": "work-demo",
  "name": "demo",
  "status": "active",
  "stage": 1,
  "lifecycle_state": "building",
  "build": {
    "contract_version": 2,
    "lifecycle_state": "building",
    "mode": "main",
    "executor": "codex",
    "design_revision": 1,
    "approved_source_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "target": {"kind": "product", "paths": ["server/api"], "entrypoints": ["server"]},
    "acceptance": {"required_checks": ["tests"], "evidence": []},
    "docs_status": "pending"
  }
}
JSON
  out=$(audit "$repo") || { _fail "mismatched build audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
codes = {item["code"] for item in payload["findings"]}
assert payload["status"] == "invalid"
assert "build_project_type_mismatch" in codes
assert "build_entrypoints_mismatch" in codes
assert "build_target_outside_root" in codes
PY
  then
    pass_test
  else
    _fail "active build/project.yml mismatch was not blocked"
    echo "$out" >&2
  fi
}

test_unversioned_legacy_module_formats_are_not_invalid() {
  start_test "consumer-doctor: unversioned spec+decisions and merged spec are compatibility findings"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  make_layout_unversioned "$repo" || { _fail "unable to remove layout contract"; return; }
  mkdir -p "$repo/docs/modules/legacy-pair" "$repo/docs/modules/merged-spec"
  printf '# Legacy pair spec\nExisting product rules.\n' > "$repo/docs/modules/legacy-pair/spec.md"
  printf '# Legacy pair decisions\nDecision history.\n' > "$repo/docs/modules/legacy-pair/decisions.md"
  printf '# Merged legacy spec\nDiscussion, decisions, and specification are intentionally merged.\n' \
    > "$repo/docs/modules/merged-spec/spec.md"
  printf '\n- legacy-pair\n- merged-spec\n' >> "$repo/docs/modules/INDEX.md"
  commit_fixture "$repo" || { _fail "fixture commit failed"; return; }
  out=$(audit "$repo") || { _fail "legacy audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
findings = payload["findings"]
assert payload["status"] == "sync_required"
assert payload["classification_summary"]["project_content_invalid"] == 0
assert sum(item["code"] == "legacy_module_inferred" for item in findings) == 2
assert not any(item["code"] == "module_document_missing" for item in findings)
assert all(not item["blocking"] for item in findings)
PY
  then
    pass_test
  else
    _fail "bounded legacy inference should request declaration without invalidating content"
    echo "$out" >&2
  fi
}

test_declared_retired_and_split_modules_follow_truth_sources() {
  start_test "consumer-doctor: declared retired/split modules point to tracked substantive truth sources"
  local repo current broken out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  mkdir -p "$repo/docs/modules/retired-module" "$repo/docs/modules/split-module"
  printf '# Successor specification\nCurrent product truth.\n' > "$repo/docs/modules/successor.md"
  printf '\n| [`successor.md`](successor.md) | 功能规格 | successor | current truth |\n' \
    >> "$repo/docs/modules/INDEX.md"
  cat > "$repo/.pm-workflow/config.yml" <<'YAML'
consumer:
  schema_version: 1
  layout_version: 1
  paths:
    archive: docs/archive
  compatibility:
    module_retired:
      path: docs/modules/retired-module
      state: retired
      truth_sources:
        - docs/modules/successor.md
    module_split:
      path: docs/modules/split-module
      state: split
      truth_sources:
        - docs/modules/successor.md
builder:
  profiles:
    fixture:
      executor: manual
YAML
  commit_fixture "$repo" || { _fail "fixture commit failed"; return; }
  current=$(audit "$repo") || { _fail "declared compatibility audit failed"; return; }
  printf '   \n<!-- placeholder only -->\n' > "$repo/docs/modules/successor.md"
  broken=$(audit "$repo") || { _fail "broken successor audit failed"; return; }
  if python3 - "$current" "$broken" <<'PY'
import json
import sys

current, broken = (json.loads(value) for value in sys.argv[1:])
assert current["status"] == "current"
assert current["classification_summary"]["legacy_compatible"] == 2
assert not any(item["blocking"] for item in current["findings"])
assert broken["status"] == "invalid"
assert "module_truth_source_blank" in {item["code"] for item in broken["findings"]}
PY
  then
    pass_test
  else
    _fail "retired/split truth source validation mismatch"
    echo "$current" >&2
    echo "$broken" >&2
  fi
}

test_nonempty_inputs_do_not_require_gitkeep() {
  start_test "consumer-doctor: nonempty inputs do not require .gitkeep"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  rm -f "$repo/docs/inputs/.gitkeep"
  printf '# Source material\nReal input.\n' > "$repo/docs/inputs/source.md"
  commit_fixture "$repo" || { _fail "fixture commit failed"; return; }
  out=$(audit "$repo") || { _fail "inputs audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "current"
assert not any("gitkeep" in str(item.get("path", "")) for item in payload["findings"])
PY
  then
    pass_test
  else
    _fail "nonempty inputs should not depend on a sentinel file"
  fi
}

test_standard_index_can_register_legacy_index_and_custom_archive() {
  start_test "consumer-doctor: INDEX.md remains standard while registering legacy index and custom archive"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  git -C "$repo" mv docs/archive docs/_归档
  sed 's#archive: docs/archive#archive: docs/_归档#' "$repo/.pm-workflow/config.yml" \
    > "$repo/.pm-workflow/config.yml.tmp" \
    && mv "$repo/.pm-workflow/config.yml.tmp" "$repo/.pm-workflow/config.yml"
  sed 's#`archive/`#`_归档/`#' "$repo/docs/INDEX.md" > "$repo/docs/INDEX.md.tmp" \
    && mv "$repo/docs/INDEX.md.tmp" "$repo/docs/INDEX.md"
  printf '\n- [`索引.md`](./索引.md) — 历史项目索引，保留既有引用。\n' >> "$repo/docs/INDEX.md"
  printf '# 历史项目索引\nExisting navigation.\n' > "$repo/docs/索引.md"
  commit_fixture "$repo" || { _fail "fixture commit failed"; return; }
  out=$(audit "$repo") || { _fail "custom layout audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "current"
assert payload["consumer_contract"]["archive"] == "docs/_归档"
assert not any(item.get("path") == "docs/索引.md" for item in payload["findings"])
assert not any(item.get("path") == "docs/archive" for item in payload["findings"])
PY
  then
    pass_test
  else
    _fail "standard index registration or custom archive contract regressed"
    echo "$out" >&2
  fi
}

test_framework_sync_does_not_hide_project_damage() {
  start_test "consumer-doctor: framework-managed sync does not hide missing product spine"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  rm -f "$repo/PRODUCT.md" "$repo/docs/engineering/INDEX.md"
  out=$(audit "$repo") || { _fail "mixed finding audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
kinds = {item["kind"] for item in payload["findings"]}
assert payload["status"] == "invalid"
assert "project_content_invalid" in kinds
assert "framework_managed_sync" in kinds
assert any(item["blocking"] for item in payload["findings"])
PY
  then
    pass_test
  else
    _fail "blocking project damage should win over sync findings"
  fi
}

test_active_lifecycle_missing_document_is_invalid() {
  start_test "consumer-doctor: compatibility cannot downgrade active lifecycle validation"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/unused-active-doc"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  sed 's/^  compatibility: {}$/  compatibility:\n    module_demo:\n      path: docs\/modules\/demo\n      state: legacy\n      format: merged_spec/' \
    "$repo/.pm-workflow/config.yml" > "$repo/.pm-workflow/config.yml.tmp" \
    && mv "$repo/.pm-workflow/config.yml.tmp" "$repo/.pm-workflow/config.yml"
  rm -f "$repo/docs/modules/demo/decisions.md"
  out=$(audit "$repo") || { _fail "active document audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "invalid"
assert any(item["code"] == "active_module_compatibility_ignored" for item in payload["findings"])
assert any(
    item["code"] == "module_document_missing"
    and item.get("path", "").endswith("decisions.md")
    and item["blocking"]
    for item in payload["findings"]
)
PY
  then
    pass_test
  else
    _fail "active lifecycle must keep strict document validation"
  fi
}

test_blank_placeholder_document_is_invalid() {
  start_test "consumer-doctor: blank placeholder documents cannot satisfy current contract"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/unused-placeholder"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  printf '   \n<!-- intentionally blank -->\n' > "$repo/docs/modules/demo/spec.md"
  out=$(audit "$repo") || { _fail "blank document audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "invalid"
assert "module_document_blank" in {item["code"] for item in payload["findings"]}
PY
  then
    pass_test
  else
    _fail "blank placeholder should not make doctor green"
  fi
}

test_fresh_consumer_is_current_and_read_only
test_current_proposal_is_verified_and_drift_is_invalid
test_missing_and_misplaced_documents_are_reported
test_project_definition_drives_custom_implementation_location
test_ready_contract_gap_is_progress_only
test_unknown_module_file_is_not_mislabeled_as_a_spec
test_stale_consumer_entry_is_machine_detectable
test_consumer_entry_sync_is_read_only_scoped_and_idempotent
test_consumer_entry_sync_migrates_known_legacy_rules_and_keeps_custom_items
test_consumer_entry_sync_rejects_unsafe_shapes
test_missing_implementation_entrypoint_blocks_build_recovery
test_mockup_manifest_assets_and_board_are_checked
test_mockup_current_schema_is_complete_and_timestamped
test_mockup_quality_schema_requires_evidence_paths
test_mockup_quality_evidence_is_verified_and_invalidated
test_secret_config_is_never_echoed
test_legacy_layout_requires_sync_not_structural_repair
test_non_git_and_symlinked_truth_sources_fail_closed
test_active_build_must_match_project_definition
test_unversioned_legacy_module_formats_are_not_invalid
test_declared_retired_and_split_modules_follow_truth_sources
test_nonempty_inputs_do_not_require_gitkeep
test_standard_index_can_register_legacy_index_and_custom_archive
test_framework_sync_does_not_hide_project_damage
test_active_lifecycle_missing_document_is_invalid
test_blank_placeholder_document_is_invalid

report_results "consumer-doctor"
