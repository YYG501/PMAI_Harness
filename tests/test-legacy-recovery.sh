#!/usr/bin/env bash
# Explicit recovery contract for legacy active work.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RECOVERY="$FRAMEWORK_ROOT/scripts/legacy-work-recovery.py"
CONTEXT_PACK="$FRAMEWORK_ROOT/scripts/context-pack.py"
BUILD_CONTRACT="$FRAMEWORK_ROOT/scripts/build-contract.py"
ACTIVE_BUILD_CONTEXT="$FRAMEWORK_ROOT/scripts/active-build-context.py"
STATUS_VIEW="$FRAMEWORK_ROOT/scripts/status-view.py"

setup_legacy_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-legacy-recovery.XXXXXX")
  export T
  mkdir -p "$T/docs/modules/demo" "$T/.pm-workflow" "$T/prototype"
  printf '# Product\n\n一个旧项目。\n' > "$T/PRODUCT.md"
  printf '# State\n' > "$T/PRODUCT-STATE.md"
  printf '# Rules\n' > "$T/PRODUCT-RULES.md"
  printf '# Design\n' > "$T/DESIGN.md"
  printf '# Todo\n' > "$T/TODO.md"
  printf '# Modules\n' > "$T/docs/modules/INDEX.md"
  printf '# Spec\n' > "$T/docs/modules/demo/spec.md"
  printf '# Discussion\n' > "$T/docs/modules/demo/discussion.md"
  printf '# Decisions\n' > "$T/docs/modules/demo/decisions.md"
  printf '<!doctype html>\n' > "$T/prototype/index.html"
  python3 "$FRAMEWORK_ROOT/scripts/project-definition.py" write "$T" \
    --source docs/modules/demo/spec.md --type prototype --root prototype \
    --entrypoint prototype --language typescript --runtime node --framework test \
    --package-manager none >/dev/null
  git -C "$T" init -q -b main
  git -C "$T" config user.email test@example.com
  git -C "$T" config user.name "PMAI Test"
  git -C "$T" add -A
  git -C "$T" commit -qm "legacy fixture"
  local pack="$T/.pm-workflow/context.json"
  mkdir -p "${pack%/*}"
  python3 - "$T" "$T/docs/modules/demo" "$pack" "$CONTEXT_PACK" <<'PY'
import importlib.util, json, sys
from pathlib import Path
root = Path(sys.argv[1]).resolve()
module_dir = Path(sys.argv[2]).resolve()
output = Path(sys.argv[3])
script = Path(sys.argv[4]) if len(sys.argv) > 4 else Path("scripts/context-pack.py").resolve()
name = "legacy_test_context_pack"
spec = importlib.util.spec_from_file_location(name, script)
module = importlib.util.module_from_spec(spec)
sys.modules[name] = module
sys.path.insert(0, str(script.parent))
spec.loader.exec_module(module)
meta = module.load_work_meta(module_dir)
sources = module.collect_sources(root, module_dir, meta, None)
records, hashes, source_hash, scope = module.source_records(root, sources, 1)
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({"source_hash": source_hash, "input_hashes": hashes, "source_hash_scope": scope}, ensure_ascii=False), encoding="utf-8")
PY
  local source_hash
  source_hash=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$pack")
  local head
  head=$(git -C "$T" rev-parse HEAD)
  python3 - "$T/docs/modules/demo/.work-meta.json" "$source_hash" "$head" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
source_hash, head = sys.argv[2:]
meta = {
    "id": "work-demo",
    "name": "demo",
    "stage": 2,
    "status": "active",
    "lifecycle_state": "iterating",
    "approved_source_hash": source_hash,
    "design_revision": 1,
    "approved_target": {"paths": ["prototype/index.html"]},
    "build": {
        "contract_version": 4,
        "anchor": "docs/modules/demo/spec.md",
        "target": {"kind": "prototype", "paths": ["prototype/index.html"], "entrypoints": ["prototype"]},
        "approved_source_hash": source_hash,
        "design_revision": 1,
        "delivery_policy": {
            "schema_version": 1,
            "policy_version": 1,
            "target_kind": "prototype",
            "implementation_mode": "interactive-simulation",
            "principle": "规格决定最终产品语义；本合同决定本轮实现深度。",
            "must_deliver": ["用户可见的主路径、相关页面、弹窗或抽屉、关键状态和操作反馈必须可交互", "权限差异、错误结果和异步结果必须以确定性的演示行为呈现"],
            "simulate_by_default": ["数据持久化与数据库", "后端接口与异步任务", "鉴权、权限校验与审计", "外部系统集成、AI 引擎、通知与其它有副作用能力"],
            "allowed_support": ["fixture、内存状态、localStorage 和仓内 mock adapter", "只服务演示且无真实外部副作用的本地 stub"],
            "forbidden_without_decision": ["生产数据库、schema 或 migration", "真实鉴权、权限执行和生产账号体系", "真实外部写入、密钥接入和不可逆副作用", "生产基础设施、部署编排和迁移兼容代码"],
            "required_check": "prototype-boundary",
        },
        "delivery_policy_hash": "f0967301487437b8b9e5ca9b41c8d4b122b06f7ff7099e3faae5e1018d443399",
        "accepted_deltas": [],
        "lifecycle_state": "iterating",
        "mode": "main",
        "executor": "native",
        "branch": "main",
        "worktree": None,
        "baseline_sha": head,
        "audit_dir": ".pm-workflow/audits/demo",
        "started_at": "2026-08-01T00:00:00+08:00",
        "implementation_commit": None,
        "pm_accepted_at": None,
        "finalization": {"requested_at": None, "requested_commit": None, "rebound_at": None},
        "acceptance": {"iteration_checks": ["typecheck"], "final_checks": ["prototype-boundary", "browser-smoke"], "required_checks": ["prototype-boundary", "browser-smoke"], "iteration_evidence": [], "evidence": []},
        "docs_status": "pending",
    },
}
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  git -C "$T" add -A
  git -C "$T" commit -qm "legacy fixture state"
}

teardown() { rm -rf "$T"; }

setup_legacy_design_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-legacy-design-recovery.XXXXXX")
  export T
  mkdir -p "$T/docs/modules/demo"
  printf '# Product\n\n一个旧项目。\n' > "$T/PRODUCT.md"
  printf '# State\n' > "$T/PRODUCT-STATE.md"
  printf '# Rules\n' > "$T/PRODUCT-RULES.md"
  printf '# Design\n' > "$T/DESIGN.md"
  printf '# Todo\n' > "$T/TODO.md"
  printf '# Modules\n' > "$T/docs/modules/INDEX.md"
  printf '# Discussion\n\n继续讨论。\n' > "$T/docs/modules/demo/discussion.md"
  printf '# Decisions\n' > "$T/docs/modules/demo/decisions.md"
  git -C "$T" init -q -b main
  git -C "$T" config user.email test@example.com
  git -C "$T" config user.name "PMAI Test"
  git -C "$T" add -A
  git -C "$T" commit -qm "legacy design fixture"
  local head
  head=$(git -C "$T" rev-parse HEAD)
  python3 - "$T/docs/modules/demo/.work-meta.json" "$head" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
head = sys.argv[2]
meta = {
    "id": "work-demo-design",
    "name": "demo",
    "stage": 1,
    "status": "active",
    "lifecycle_state": "ready_to_build",
    "approved_source_hash": "a" * 64,
    "source_hash_version": 1,
    "design_revision": 2,
    "design_checkpoint_commit": head,
    "approved_target": {"paths": ["prototype/index.html"]},
}
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

test_legacy_build_requires_explicit_recovery() {
  start_test "legacy recovery: old build without checkpoint remains blocked by Proposal"
  setup_legacy_fixture
  local out rc
  out=$(cd "$T" && python3 "$ACTIVE_BUILD_CONTEXT" 2>&1)
  rc=$?
  if [ "$rc" = "2" ] && echo "$out" | grep -q "Product Proposal"; then pass_test; else _fail "legacy build should remain blocked before recovery rc=$rc out=$out"; fi
  teardown
}

test_legacy_build_recovers_and_binds_authority() {
  start_test "legacy recovery: PM checkpoint restores old build and binds authority"
  setup_legacy_fixture
  python3 "$RECOVERY" accept "$T/docs/modules/demo" --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 --reason "当前规格仍是本轮有效建造依据" >/dev/null || { _fail "recovery command failed"; teardown; return; }
  local out
  out=$(cd "$T" && python3 "$ACTIVE_BUILD_CONTEXT" 2>&1)
  if python3 -c 'import json,sys; d=json.load(sys.stdin); b=d["active_builds"][0]; r=b["legacy_recovery"]; assert d["status"]=="active"; assert b["contract_version"]==4; assert r["status"]=="accepted"; assert r["original_hash_chain_state"]=="consistent"; assert r["original_design_approved_source_hash"]==r["original_build_approved_source_hash"]==r["original_replayed_build_approved_source_hash"]' <<<"$out"; then pass_test; else _fail "recovered build context mismatch: $out"; fi
  teardown
}

test_legacy_build_records_mismatched_original_chain() {
  start_test "legacy recovery: historical hash mismatch remains explicit and auditable"
  setup_legacy_fixture
  python3 - "$T/docs/modules/demo/.work-meta.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
meta = json.loads(path.read_text(encoding="utf-8"))
meta["build"]["accepted_deltas"] = [{
    "kind": "product-behavior",
    "summary": "历史调整",
    "affected_surfaces": ["demo"],
    "accepted_at": "2026-08-01T01:00:00+08:00",
}]
meta["build"]["approved_source_hash"] = "b" * 64
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  local out
  out=$(python3 "$RECOVERY" accept "$T/docs/modules/demo" --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 --reason "确认当前 authority 并保留历史损坏证据" 2>&1) || { _fail "mismatched legacy chain should be recoverable: $out"; teardown; return; }
  if python3 - "$T/docs/modules/demo/.work-meta.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1], encoding="utf-8"))
recovery = meta["legacy_recovery"]
assert recovery["original_hash_chain_state"] == "mismatch"
assert recovery["original_build_approved_source_hash"] == "b" * 64
assert recovery["original_replayed_build_approved_source_hash"] != "b" * 64
assert recovery["original_design_approved_source_hash"] != "b" * 64
assert recovery["original_accepted_delta_count"] == 1
assert len(recovery["original_accepted_deltas"]) == 1
assert meta["build"]["accepted_deltas"] == []
PY
  then pass_test; else _fail "historical mismatch audit record is incomplete"; fi
  teardown
}

test_legacy_recovery_fails_on_bound_file_change() {
  start_test "legacy recovery: bound authority change fails closed"
  setup_legacy_fixture
  python3 "$RECOVERY" accept "$T/docs/modules/demo" --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 --reason "当前规格仍是本轮有效建造依据" >/dev/null || { _fail "recovery command failed"; teardown; return; }
  printf '\n变化\n' >> "$T/docs/modules/demo/spec.md"
  local out rc
  out=$(cd "$T" && python3 "$ACTIVE_BUILD_CONTEXT" 2>&1); rc=$?
  if [ "$rc" = "2" ] && echo "$out" | grep -q "authority 文件发生变化"; then pass_test; else _fail "bound authority drift should fail closed rc=$rc out=$out"; fi
  teardown
}

test_legacy_build_accepts_new_scoped_delta() {
  start_test "legacy recovery: recovered build continues through a new scoped delta"
  setup_legacy_fixture
  python3 "$RECOVERY" accept "$T/docs/modules/demo" --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 --reason "当前规格仍是本轮有效建造依据" >/dev/null || { _fail "recovery command failed"; teardown; return; }
  local out
  out=$(python3 "$BUILD_CONTRACT" add-delta "$T/docs/modules/demo" \
    --summary "调整已确认文案" \
    --affected-surface "demo" \
    --scope-attestation approved-module-task-no-model-change \
    --approval-kind pm-confirmation \
    --approval-reference "session:legacy-recovery-test" 2>&1) || { _fail "recovered build should accept scoped delta: $out"; teardown; return; }
  out=$(cd "$T" && python3 "$ACTIVE_BUILD_CONTEXT" 2>&1) || { _fail "recovered build should remain resumable: $out"; teardown; return; }
  if python3 -c 'import json,sys; d=json.load(sys.stdin); b=d["active_builds"][0]; assert len(b["accepted_deltas"]) == 1; assert b["legacy_recovery"]["original_accepted_delta_count"] == 0' <<<"$out"; then pass_test; else _fail "recovered delta context mismatch: $out"; fi
  teardown
}

test_legacy_recovery_rejects_tampered_record_cleanly() {
  start_test "legacy recovery: tampered recovery record fails without traceback"
  setup_legacy_fixture
  python3 "$RECOVERY" accept "$T/docs/modules/demo" --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 --reason "当前规格仍是本轮有效建造依据" >/dev/null || { _fail "recovery command failed"; teardown; return; }
  python3 - "$T/docs/modules/demo/.work-meta.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
meta = json.loads(path.read_text(encoding="utf-8"))
meta["legacy_recovery"]["authority_source_hash"] = "bad"
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  local out rc context_out context_rc status_out
  out=$(python3 "$BUILD_CONTRACT" validate-currentness "$T/docs/modules/demo" 2>&1); rc=$?
  context_out=$(cd "$T" && python3 "$ACTIVE_BUILD_CONTEXT" "$T" \
    --module "$T/docs/modules/demo" 2>&1); context_rc=$?
  status_out=$(cd "$T" && python3 "$STATUS_VIEW" --narrative 2>&1)
  if [ "$rc" = "1" ] \
     && echo "$out" | grep -q "64 位小写 SHA-256" \
     && ! echo "$out" | grep -q "Traceback" \
     && [ "$context_rc" = "2" ] \
     && echo "$context_out" | grep -q '"route": "pmai-proposal"' \
     && echo "$status_out" | grep -q "当前可执行入口：/pmai-proposal"; then
    pass_test
  else
    _fail "tampered recovery should fail cleanly and return to Proposal: rc=$rc out=$out context=$context_out status=$status_out"
  fi
  teardown
}

test_legacy_design_returns_to_designing() {
  start_test "legacy recovery: old ready design returns to designing without Proposal fabrication"
  setup_legacy_design_fixture
  python3 "$RECOVERY" accept-design "$T/docs/modules/demo" --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 --reason "继续该模块，但重新确认设计目标" >/dev/null || { _fail "design recovery command failed"; teardown; return; }
  local pack="$T/context.json" out
  out=$(python3 "$CONTEXT_PACK" --repo-root "$T" --module "$T/docs/modules/demo" --output "$pack" 2>&1) || { _fail "recovered design should compile context: $out"; teardown; return; }
  if python3 - "$T/docs/modules/demo/.work-meta.json" "$pack" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1], encoding="utf-8"))
pack = json.load(open(sys.argv[2], encoding="utf-8"))
assert meta["status"] == "active"
assert meta["lifecycle_state"] == "designing"
assert meta["source_hash_version"] == 2
assert "stage" not in meta
assert "approved_source_hash" not in meta
assert "design_checkpoint_commit" not in meta
assert "approved_target" not in meta
assert meta["design_revision"] == 2
assert meta["legacy_recovery"]["kind"] == "active-design"
assert meta["legacy_recovery"]["original_lifecycle_state"] == "ready_to_build"
assert meta["legacy_recovery"]["original_ready_contract"]["approved_source_hash"] == "a" * 64
assert pack["lifecycle_state"] == "designing"
assert pack["legacy_recovery"]["kind"] == "active-design"
PY
  then pass_test; else _fail "recovered design state mismatch"; fi
  teardown
}

test_legacy_design_allows_normal_design_edits() {
  start_test "legacy recovery: recovered design can continue normal design edits"
  setup_legacy_design_fixture
  python3 "$RECOVERY" accept-design "$T/docs/modules/demo" --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 --reason "继续该模块" >/dev/null || { _fail "design recovery command failed"; teardown; return; }
  printf '\n变化\n' >> "$T/docs/modules/demo/discussion.md"
  local out
  out=$(python3 "$CONTEXT_PACK" --repo-root "$T" --module "$T/docs/modules/demo" 2>&1) || { _fail "recovered design should remain editable: $out"; teardown; return; }
  if python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["lifecycle_state"]=="designing"; assert d["legacy_recovery"]["kind"]=="active-design"' <<<"$out"; then pass_test; else _fail "recovered design context mismatch: $out"; fi
  teardown
}

test_legacy_design_rejects_build_state() {
  start_test "legacy recovery: design entry cannot capture an active build"
  setup_legacy_fixture
  local out rc
  out=$(python3 "$RECOVERY" accept-design "$T/docs/modules/demo" --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 --reason "错误入口" 2>&1); rc=$?
  if [ "$rc" = "1" ] && echo "$out" | grep -q "build contract"; then pass_test; else _fail "design recovery should reject build state rc=$rc out=$out"; fi
  teardown
}

set_work_name() {
  local module_dir="$1" name="$2"
  python3 - "$module_dir/.work-meta.json" "$name" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
meta = json.loads(path.read_text(encoding="utf-8"))
meta["name"] = sys.argv[2]
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

test_status_reuses_recovered_build_route_when_proposal_required() {
  start_test "legacy recovery: Proposal required 时 status 复用 active build route"
  setup_legacy_fixture
  set_work_name "$T/docs/modules/demo" "能力匹配卡"
  git -C "$T" add -- docs/modules/demo/.work-meta.json
  git -C "$T" commit -qm "name recovered build"
  python3 "$RECOVERY" accept "$T/docs/modules/demo" \
    --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 \
    --reason "当前规格仍是本轮有效建造依据" >/dev/null || {
      _fail "recovery command failed"; teardown; return;
    }
  local status_out context_out route
  status_out=$(cd "$T" && python3 "$STATUS_VIEW" --narrative 2>&1)
  context_out=$(cd "$T" && python3 "$ACTIVE_BUILD_CONTEXT" "$T" --module "$T/docs/modules/demo" 2>&1)
  route=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["route"])' <<<"$context_out")
  if echo "$status_out" | grep -q "项目级产品方向：Product Proposal 尚未完成" \
     && echo "$status_out" | grep -q "项目级提醒：.*新工作或没有合法恢复记录" \
     && echo "$status_out" | grep -q "正在处理：能力匹配卡" \
     && echo "$status_out" | grep -q "当前阶段：看结果并修改" \
     && echo "$status_out" | grep -q "下一阶段：最终检查" \
     && echo "$status_out" | grep -q "当前可执行入口：/$route" \
     && [ "$route" = "pmai-build" ]; then
    pass_test
  else
    _fail "recovered build status route mismatch: route=$route status=$status_out context=$context_out"
  fi
  teardown
}

test_status_reuses_recovered_design_route_when_proposal_required() {
  start_test "legacy recovery: Proposal required 时 status 复用 active design route"
  setup_legacy_design_fixture
  set_work_name "$T/docs/modules/demo" "成本与定价"
  git -C "$T" add -- docs/modules/demo/.work-meta.json
  git -C "$T" commit -qm "name recovered design"
  python3 "$RECOVERY" accept-design "$T/docs/modules/demo" \
    --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 \
    --reason "继续该模块，但重新确认设计目标" >/dev/null || {
      _fail "design recovery command failed"; teardown; return;
    }
  local status_out pack_out route
  status_out=$(cd "$T" && python3 "$STATUS_VIEW" --narrative 2>&1)
  pack_out=$(python3 "$CONTEXT_PACK" --repo-root "$T" --module "$T/docs/modules/demo" 2>&1)
  route=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["route"])' <<<"$pack_out")
  if echo "$status_out" | grep -q "项目级产品方向：Product Proposal 尚未完成" \
     && echo "$status_out" | grep -q "正在处理：成本与定价" \
     && echo "$status_out" | grep -q "当前阶段：需求讨论" \
     && echo "$status_out" | grep -q "下一阶段：设计已定" \
     && echo "$status_out" | grep -q "当前可执行入口：/$route" \
     && [ "$route" = "pmai-design" ]; then
    pass_test
  else
    _fail "recovered design status route mismatch: route=$route status=$status_out pack=$pack_out"
  fi
  teardown
}

test_status_blocks_unrecovered_work_when_proposal_required() {
  start_test "legacy recovery: Proposal required 且无 recovery 时 status 继续阻断"
  setup_legacy_fixture
  local status_out context_out rc
  status_out=$(cd "$T" && python3 "$STATUS_VIEW" --narrative 2>&1)
  context_out=$(cd "$T" && python3 "$ACTIVE_BUILD_CONTEXT" "$T" --module "$T/docs/modules/demo" 2>&1)
  rc=$?
  if [ "$rc" = "2" ] \
     && echo "$context_out" | grep -q '"route": "pmai-proposal"' \
     && echo "$status_out" | grep -q "当前可执行入口：/pmai-proposal" \
     && echo "$status_out" | grep -q "需要退回：.*Product Proposal" \
     && ! echo "$status_out" | grep -q "当前可执行入口：/pmai-build"; then
    pass_test
  else
    _fail "unrecovered work should remain blocked: rc=$rc status=$status_out context=$context_out"
  fi
  teardown
}

test_status_reuses_recovery_when_proposal_invalid() {
  start_test "legacy recovery: Proposal invalid 时合法存量工作仍按模块 route 续接"
  setup_legacy_fixture
  python3 "$RECOVERY" accept "$T/docs/modules/demo" \
    --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 \
    --reason "当前规格仍是本轮有效建造依据" >/dev/null || {
      _fail "recovery command failed"; teardown; return;
    }
  printf '{}\n' > "$T/.pm-workflow/proposal.json"
  local status_out context_out
  status_out=$(cd "$T" && python3 "$STATUS_VIEW" --narrative 2>&1)
  context_out=$(cd "$T" && python3 "$ACTIVE_BUILD_CONTEXT" "$T" \
    --module "$T/docs/modules/demo" 2>&1)
  if echo "$status_out" | grep -q "项目级产品方向：Product Proposal 已失效" \
     && echo "$status_out" | grep -q "项目级提醒：.*没有合法恢复记录" \
     && echo "$status_out" | grep -q "当前可执行入口：/pmai-build" \
     && echo "$context_out" | grep -q '"route": "pmai-build"' \
     && echo "$context_out" | grep -q '"status": "active"'; then
    pass_test
  else
    _fail "invalid Proposal should not override valid recovery: status=$status_out context=$context_out"
  fi
  teardown
}

test_status_renders_expected_multi_recovery_routes() {
  start_test "legacy recovery: 双模块展示完整阶段与各自真实入口"
  setup_legacy_fixture
  set_work_name "$T/docs/modules/demo" "能力匹配卡"
  mkdir -p "$T/docs/modules/pricing"
  printf '# Discussion\n\n继续讨论。\n' > "$T/docs/modules/pricing/discussion.md"
  printf '# Decisions\n' > "$T/docs/modules/pricing/decisions.md"
  local head
  head=$(git -C "$T" rev-parse HEAD)
  python3 - "$T/docs/modules/pricing/.work-meta.json" "$head" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
meta = {
    "id": "work-pricing-design",
    "name": "成本与定价",
    "status": "active",
    "lifecycle_state": "ready_to_build",
    "approved_source_hash": "a" * 64,
    "source_hash_version": 1,
    "design_revision": 1,
    "design_checkpoint_commit": sys.argv[2],
    "approved_target": {"paths": ["prototype/index.html"]},
}
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  git -C "$T" add -- docs/modules/demo/.work-meta.json docs/modules/pricing
  git -C "$T" commit -qm "add two legacy works"
  python3 "$RECOVERY" accept "$T/docs/modules/demo" \
    --confirmed-by PM --confirmed-at 2026-08-12T12:00:00+08:00 \
    --reason "当前规格仍是本轮有效建造依据" >/dev/null || {
      _fail "build recovery command failed"; teardown; return;
    }
  git -C "$T" add -- docs/modules/demo/.work-meta.json
  git -C "$T" commit -qm "recover capability build"
  python3 "$RECOVERY" accept-design "$T/docs/modules/pricing" \
    --confirmed-by PM --confirmed-at 2026-08-12T12:05:00+08:00 \
    --reason "继续该模块，但重新确认设计目标" >/dev/null || {
      _fail "design recovery command failed"; teardown; return;
    }
  local status_out
  status_out=$(cd "$T" && python3 "$STATUS_VIEW" --narrative 2>&1)
  if echo "$status_out" | grep -q "当前状态：有 2 个进行中的工作" \
     && echo "$status_out" | grep -q "完整阶段：需求讨论 → 设计已定 → 构建中 → 看结果并修改 → 最终检查 → 进入主线 → 更新正式文档 → 完成" \
     && echo "$status_out" | grep -A6 "1. 能力匹配卡" | grep -q "当前可执行入口：/pmai-build" \
     && echo "$status_out" | grep -A6 "1. 能力匹配卡" | grep -q "下一阶段：最终检查" \
     && echo "$status_out" | grep -A6 "2. 成本与定价" | grep -q "当前可执行入口：/pmai-design" \
     && echo "$status_out" | grep -A6 "2. 成本与定价" | grep -q "下一阶段：设计已定"; then
    pass_test
  else
    _fail "multi recovery status mismatch: $status_out"
  fi
  teardown
}

test_legacy_build_requires_explicit_recovery
test_legacy_build_recovers_and_binds_authority
test_legacy_build_records_mismatched_original_chain
test_legacy_recovery_fails_on_bound_file_change
test_legacy_build_accepts_new_scoped_delta
test_legacy_recovery_rejects_tampered_record_cleanly
test_legacy_design_returns_to_designing
test_legacy_design_allows_normal_design_edits
test_legacy_design_rejects_build_state
test_status_reuses_recovered_build_route_when_proposal_required
test_status_reuses_recovered_design_route_when_proposal_required
test_status_blocks_unrecovered_work_when_proposal_required
test_status_reuses_recovery_when_proposal_invalid
test_status_renders_expected_multi_recovery_routes
report_results "legacy-recovery"
