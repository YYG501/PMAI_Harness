#!/usr/bin/env bash
# Current Product Proposal machine contract and downstream handoff regressions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROPOSAL_CONTRACT="$REPO_ROOT/scripts/proposal-contract.py"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-proposal-contract.XXXXXX")
  ATTACHED_WORKTREE=""
  mkdir -p "$T/docs/proposals" "$T/.pm-workflow"
  printf '# Product\n\n<!-- PMAI_PROPOSAL_REQUIRED -->\n' > "$T/PRODUCT.md"
  git -C "$T" init -q -b main
  git -C "$T" config user.name "PMAI Test"
  git -C "$T" config user.email "pmai-test@example.com"
  git -C "$T" add -- PRODUCT.md
  git -C "$T" commit -qm "init fixture"
}

teardown_fixture() {
  if [ -n "${ATTACHED_WORKTREE:-}" ]; then
    git -C "$T" worktree remove --force "$ATTACHED_WORKTREE" >/dev/null 2>&1 || true
    rm -rf "$ATTACHED_WORKTREE"
  fi
  rm -rf "$T"
}

write_active_build_meta() {
  local root="$1" mode="$2" lifecycle="$3" branch="$4"
  mkdir -p "$root/docs/modules/active-demo"
  python3 - "$root/docs/modules/active-demo/.work-meta.json" "$mode" "$lifecycle" "$branch" <<'PY'
import json
import sys
from pathlib import Path

path, mode, lifecycle, branch = sys.argv[1:]
value = {
    "id": "work-active-demo",
    "name": "active-demo",
    "status": "active",
    "lifecycle_state": lifecycle,
    "branch": branch,
    "build": {
        "mode": mode,
        "lifecycle_state": lifecycle,
        "branch": branch,
    },
}
Path(path).write_text(json.dumps(value, ensure_ascii=False) + "\n", encoding="utf-8")
PY
}

attach_active_build_worktree() {
  ATTACHED_WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/pmai-proposal-build.XXXXXX")
  rmdir "$ATTACHED_WORKTREE"
  git -C "$T" worktree add -q -b build-active-demo "$ATTACHED_WORKTREE" HEAD
  write_active_build_meta "$ATTACHED_WORKTREE" worktree iterating build-active-demo
  git -C "$ATTACHED_WORKTREE" add -- docs/modules/active-demo/.work-meta.json
  git -C "$ATTACHED_WORKTREE" commit -qm "test: active worktree build"
}

write_intake_manifest() {
  python3 - "$T" "$@" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
files = []
for relative in sorted(sys.argv[2:]):
    files.append({
        "path": relative,
        "sha256": hashlib.sha256((root / relative).read_bytes()).hexdigest(),
    })
path = root / ".pm-workflow/intake-manifest.json"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(
    json.dumps({"schema_version": 1, "files": files}, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
}

write_proposal() {
  local path="$1" status="${2:-当前}" superseded_path="${3:-无}" id version
  id=$(basename "$path" .md)
  version="${id##*-}"
  cat > "$path" <<EOF
# Demo Product Proposal

> 版本：$version
> Proposal ID：$id
> 状态：$status
> 日期：2026-08-10
> 取代：$superseded_path
> 支持的决定：是否投入一次可验证的审核闭环
> 证据截至：2026-08-10

## 0. 决策摘要与产品主张

为运营负责人提供可验证的审核建议。

## 1. 产品成立的核心判断

负责人需要在提交前获得可追溯证据。

## 2. 用户、场景、问题与现状替代

运营负责人当前依靠人工搜索材料完成审核。

## 3. 产品回答与职责边界

产品聚合证据并给建议，最终结论仍由人确认。

## 4. 必要能力与 AI 角色

AI 只分析非结构化材料，确定性系统执行门禁。

## 5. 替代方案、竞争判断与产品机会

现状替代是人工检索，机会在于减少遗漏且保持可追溯。

## 6. 端到端产品体验与关键能力

从收到任务到核对证据、确认建议并提交结论形成闭环。

## 7. 产品价值、因果链与指标

更完整的证据促成更可靠的审核行动和结果。

## 8. MVP 范围、完整案例与决策门

先验证一个审核案例，不能促成有效行动时停止扩大投入。

## 9. 演进条件与长期方向

只有主案例成立后才扩展更多审核场景。

## 10. 下游交接摘要

- **第一个 design 目标**：完成一次审核闭环
- **主用户与触发时刻**：运营负责人收到待审核内容时
- **要闭合的核心任务**：判断并提交审核结论
- **必须保持的产品回答**：聚合证据后给出可追溯建议
- **必须保持的产品边界**：最终结论由人确认
- **MVP 必须证明**：建议促成有效行动并改善审核结果
- **仍待验证的假设**：负责人愿意在提交前查看建议
- **design 需要收敛**：对象、动作、状态、权限与异常路径
EOF
}

write_product_reference() {
  local relative="$1"
  cat > "$T/PRODUCT.md" <<EOF
# Product

## 当前 Product Proposal

[$(basename "$relative")]($relative)

## 产品定位

为运营负责人提供可追溯审核建议的产品。

## 核心问题与价值

减少人工检索遗漏，帮助负责人作出更可靠的审核行动。

## 用户画像

运营负责人，需要对审核结果负责。

## 产品边界

产品给出建议，最终结论由人确认。

## MVP Case

负责人收到任务后核对证据、确认建议并提交审核结论。
EOF
}

write_revision_index() {
  local old_status="${1:-已取代}" new_status="${2:-当前}"
  cat > "$T/docs/proposals/INDEX.md" <<EOF
# Product Proposal 索引

| 文档 | 版本 | 状态 | 取代 | 决策日期 | 下游起点 |
|---|---|---|---|---|---|
| [\`demo-v1.md\`](demo-v1.md) | v1 | $old_status | 无 | 2026-08-09 | 审核闭环 |
| [\`demo-v2.md\`](demo-v2.md) | v2 | $new_status | demo-v1 | 2026-08-10 | 审核闭环 |
EOF
}

write_v3_index() {
  cat > "$T/docs/proposals/INDEX.md" <<'EOF'
# Product Proposal 索引

| 文档 | 版本 | 状态 | 取代 | 决策日期 | 下游起点 |
|---|---|---|---|---|---|
| [`demo-v1.md`](demo-v1.md) | v1 | 已取代 | 无 | 2026-08-08 | 审核闭环 |
| [`demo-v2.md`](demo-v2.md) | v2 | 已取代 | demo-v1 | 2026-08-09 | 审核闭环 |
| [`demo-v3.md`](demo-v3.md) | v3 | 当前 | demo-v2 | 2026-08-10 | 审核闭环 |
EOF
}

write_v1_index() {
  cat > "$T/docs/proposals/INDEX.md" <<'EOF'
# Product Proposal 索引

| 文档 | 版本 | 状态 | 取代 | 决策日期 | 下游起点 |
|---|---|---|---|---|---|
| [`demo-v1.md`](demo-v1.md) | v1 | 当前 | 无 | 2026-08-10 | 审核闭环 |
EOF
}

commit_v1_proposal() {
  git -C "$T" add -- \
    docs/proposals/demo-v1.md docs/proposals/INDEX.md PRODUCT.md \
    .pm-workflow/proposal.json
  git -C "$T" commit -qm "docs: approve demo v1"
}

commit_v2_proposal() {
  git -C "$T" add -- \
    docs/proposals/demo-v1.md docs/proposals/demo-v2.md \
    docs/proposals/INDEX.md PRODUCT.md .pm-workflow/proposal.json
  git -C "$T" commit -qm "docs: approve demo v2"
}

commit_v3_proposal() {
  git -C "$T" add -- \
    docs/proposals/demo-v1.md docs/proposals/demo-v2.md docs/proposals/demo-v3.md \
    docs/proposals/INDEX.md PRODUCT.md .pm-workflow/proposal.json
  git -C "$T" commit -qm "docs: approve demo v3"
}

test_accept_and_validate_current_proposal() {
  start_test "proposal-contract: accept writes compact pointer and compiles handoff"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index

  local before accepted pending repeated validated
  before=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  write_product_reference docs/proposals/demo-v1.md
  accepted=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md \
    --id demo-v1 \
    --accepted-at 2026-08-10T10:00:00+08:00) || {
      _fail "first proposal should be accepted"
      teardown_fixture
      return
    }
  pending=$(python3 "$PROPOSAL_CONTRACT" status "$T" 2>/dev/null)
  commit_v1_proposal || {
    _fail "fixture proposal commit should succeed"
    teardown_fixture
    return
  }
  repeated=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md \
    --id demo-v1) || {
      _fail "accept should be idempotent for the same confirmed proposal"
      teardown_fixture
      return
    }
  validated=$(python3 "$PROPOSAL_CONTRACT" validate "$T") || {
    _fail "accepted proposal should validate"
    teardown_fixture
    return
  }

  if python3 - "$T/.pm-workflow/proposal.json" "$before" "$accepted" "$pending" "$repeated" "$validated" <<'PY'
import json, sys
path, before, accepted, pending, repeated, validated = sys.argv[1:]
contract = json.load(open(path))
assert set(contract) == {
    "schema_version", "id", "status", "path", "hash", "product_hash",
    "accepted_at", "supersedes"
}
assert contract["id"] == "demo-v1"
assert contract["status"] == "accepted"
assert contract["path"] == "docs/proposals/demo-v1.md"
assert contract["supersedes"] is None
assert contract["schema_version"] == 3
assert len(contract["hash"]) == 64
assert len(contract["product_hash"]) == 64
assert json.loads(before)["state"] == "required"
assert json.loads(accepted) == contract
assert json.loads(pending)["state"] == "invalid"
assert json.loads(repeated) == contract
current = json.loads(validated)
assert current["handoff"]["first_design_goal"] == "完成一次审核闭环"
assert current["handoff"]["product_boundary"] == "最终结论由人确认"
PY
  then
    pass_test
  else
    _fail "compact contract or handoff output mismatch"
  fi
  teardown_fixture
}

test_confirmed_body_drift_fails_closed() {
  start_test "proposal-contract: confirmed body drift is rejected"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "fixture proposal should be accepted"
      teardown_fixture
      return
    }
  commit_v1_proposal || {
    _fail "fixture proposal commit should succeed"
    teardown_fixture
    return
  }
  printf '\n未经新版本确认的变化。\n' >> "$T/docs/proposals/demo-v1.md"

  local out rc
  out=$(python3 "$PROPOSAL_CONTRACT" validate "$T" 2>&1)
  rc=$?
  if [ "$rc" != "0" ] && echo "$out" | grep -q "确认后发生正文漂移"; then
    pass_test
  else
    _fail "drift should fail with proposal recovery guidance: rc=$rc out=$out"
  fi
  teardown_fixture
}

test_product_baseline_hash_protects_only_product_judgments() {
  start_test "proposal-contract: PRODUCT baseline drift invalidates v3 but record sections stay editable"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  cat >> "$T/PRODUCT.md" <<'EOF'

## 术语表

- 审核建议：提交结论前供负责人核对的产品输出。
EOF
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "fixture proposal should be accepted"
      teardown_fixture
      return
    }
  commit_v1_proposal || {
    _fail "fixture proposal commit should succeed"
    teardown_fixture
    return
  }

  printf '%s\n' '- 审核证据：支持或反驳审核建议的材料。' >> "$T/PRODUCT.md"
  git -C "$T" add -- PRODUCT.md
  git -C "$T" commit -qm "docs: record confirmed term"
  local record_update drifted
  record_update=$(python3 "$PROPOSAL_CONTRACT" status "$T")

  sed -i.bak \
    's/产品给出建议，最终结论由人确认。/产品自动提交最终审核结论。/' \
    "$T/PRODUCT.md"
  rm -f "$T/PRODUCT.md.bak"
  git -C "$T" add -- PRODUCT.md
  git -C "$T" commit -qm "test: drift protected product baseline"
  drifted=$(python3 "$PROPOSAL_CONTRACT" status "$T" 2>/dev/null)

  if python3 - "$record_update" "$drifted" <<'PY'
import json, sys
record_update, drifted = (json.loads(item) for item in sys.argv[1:])
assert record_update["state"] == "accepted"
assert drifted["state"] == "invalid"
assert "PRODUCT.md 产品基线" in drifted["reason"]
assert "/pmai-proposal" in drifted["reason"]
PY
  then
    pass_test
  else
    _fail "PRODUCT baseline hash boundary mismatch: stable=$record_update drifted=$drifted"
  fi
  teardown_fixture
}

test_revision_requires_explicit_supersede_and_new_file() {
  start_test "proposal-contract: revision explicitly supersedes current version"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "fixture proposal should be accepted"
      teardown_fixture
      return
    }
  commit_v1_proposal || {
    _fail "v1 fixture commit should succeed"
    teardown_fixture
    return
  }

  write_proposal "$T/docs/proposals/demo-v1.md" '已被 `docs/proposals/demo-v2.md` 取代'
  write_proposal "$T/docs/proposals/demo-v2.md" 当前 docs/proposals/demo-v1.md
  write_product_reference docs/proposals/demo-v2.md
  local missing wrong_path accepted pending repeated drifted
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 >/dev/null 2>&1
  missing=$?
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v2 --supersedes demo-v1 >/dev/null 2>&1
  wrong_path=$?
  write_revision_index
  accepted=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1) || {
      _fail "explicit full revision should be accepted"
      teardown_fixture
      return
    }
  pending=$(python3 "$PROPOSAL_CONTRACT" status "$T" 2>/dev/null)
  commit_v2_proposal || {
    _fail "v2 fixture commit should succeed"
    teardown_fixture
    return
  }
  repeated=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1) || {
      _fail "same complete revision should be idempotent"
      teardown_fixture
      return
    }
  write_revision_index 当前 当前
  drifted=$(python3 "$PROPOSAL_CONTRACT" status "$T" 2>/dev/null)

  if [ "$missing" != "0" ] && [ "$wrong_path" != "0" ] \
     && python3 - "$accepted" "$pending" "$repeated" "$drifted" <<'PY'
import json, sys
accepted, pending, repeated, drifted = (json.loads(item) for item in sys.argv[1:])
assert accepted["id"] == "demo-v2"
assert accepted["supersedes"] == "demo-v1"
assert pending["state"] == "invalid"
assert repeated == accepted
assert drifted["state"] == "invalid"
assert "INDEX.md" in drifted["reason"]
PY
  then
    pass_test
  else
    _fail "revision guard mismatch: missing=$missing same_path=$wrong_path accepted=$accepted"
  fi
  teardown_fixture
}

test_revision_requires_old_version_and_unique_current_index() {
  start_test "proposal-contract: revision requires retired old version and unique current index"
  setup_fixture

  write_proposal "$T/docs/proposals/demo-v2.md" 当前 docs/proposals/demo-v1.md
  write_product_reference docs/proposals/demo-v2.md
  write_revision_index
  local orphan missing_old old_current missing_index double_current no_current
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1 >/dev/null 2>&1
  orphan=$?

  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "v1 fixture should be accepted with the current index prepared"
      teardown_fixture
      return
    }
  commit_v1_proposal || {
    _fail "v1 fixture commit should succeed"
    teardown_fixture
    return
  }
  write_proposal "$T/docs/proposals/demo-v2.md" 当前 docs/proposals/demo-v1.md
  write_product_reference docs/proposals/demo-v2.md
  write_revision_index

  rm -f "$T/docs/proposals/demo-v1.md"
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1 >/dev/null 2>&1
  missing_old=$?

  write_proposal "$T/docs/proposals/demo-v1.md"
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1 >/dev/null 2>&1
  old_current=$?

  write_proposal "$T/docs/proposals/demo-v1.md" '已被 `docs/proposals/demo-v2.md` 取代'
  rm -f "$T/docs/proposals/INDEX.md"
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1 >/dev/null 2>&1
  missing_index=$?

  write_revision_index 当前 当前
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1 >/dev/null 2>&1
  double_current=$?

  write_revision_index 已取代 已取代
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1 >/dev/null 2>&1
  no_current=$?

  if [ "$orphan" != "0" ] && [ "$missing_old" != "0" ] \
     && [ "$old_current" != "0" ] && [ "$missing_index" != "0" ] \
     && [ "$double_current" != "0" ] && [ "$no_current" != "0" ]; then
    pass_test
  else
    _fail "revision consistency bypassed: orphan=$orphan missing_old=$missing_old old_current=$old_current missing_index=$missing_index double_current=$double_current no_current=$no_current"
  fi
  teardown_fixture
}

test_unsafe_or_incomplete_proposal_is_rejected() {
  start_test "proposal-contract: unsafe paths and incomplete handoff are rejected"
  setup_fixture
  printf '# Outside\n' > "$T/outside.md"
  cat > "$T/docs/proposals/incomplete-v1.md" <<'EOF'
# Incomplete

> 状态：当前

## 10. 下游交接摘要

- **第一个 design 目标**：只有一个字段
EOF

  local traversal incomplete
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal ../outside.md --id outside-v1 >/dev/null 2>&1
  traversal=$?
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/incomplete-v1.md --id incomplete-v1 >/dev/null 2>&1
  incomplete=$?
  if [ "$traversal" != "0" ] && [ "$incomplete" != "0" ]; then
    pass_test
  else
    _fail "unsafe or incomplete proposal unexpectedly passed: traversal=$traversal incomplete=$incomplete"
  fi
  teardown_fixture
}

test_full_structure_and_product_baseline_are_required() {
  start_test "proposal-contract: complete sections and synchronized product baseline are required"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_product_reference docs/proposals/demo-v1.md

  python3 - "$T/docs/proposals/demo-v1.md" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = re.sub(
    r"\n## 5\. 替代方案、竞争判断与产品机会\n.*?(?=\n## 6\.)",
    "\n",
    text,
    flags=re.S,
)
path.write_text(text, encoding="utf-8")
PY
  local missing_section missing_baseline
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null 2>&1
  missing_section=$?

  write_proposal "$T/docs/proposals/demo-v1.md"
  python3 - "$T/PRODUCT.md" <<'PY'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = re.sub(r"\n## MVP Case\n.*\Z", "\n", text, flags=re.S)
path.write_text(text, encoding="utf-8")
PY
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null 2>&1
  missing_baseline=$?

  if [ "$missing_section" != "0" ] && [ "$missing_baseline" != "0" ]; then
    pass_test
  else
    _fail "incomplete proposal or PRODUCT baseline passed: sections=$missing_section baseline=$missing_baseline"
  fi
  teardown_fixture
}

test_equivalent_baseline_requires_all_product_judgments() {
  start_test "proposal-contract: equivalent baseline requires judgments, evidence, and PM confirmation"
  setup_fixture
  printf '# Product\n\n## 产品定位\n\n只有定位。\n' > "$T/PRODUCT.md"
  local incomplete placeholders undeclared bad_evidence bad_date dirty_git complete
  incomplete=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  cat > "$T/PRODUCT.md" <<'EOF'
# Product

## 产品定位

<!-- 应写清产品定位 -->
待补充。

## 核心问题与价值

{{CORE_PROBLEM_AND_VALUE}}

## 用户画像

| 角色 | 描述 | 关键诉求 |
|---|---|---|
| <主用户> | <用户责任> | <关键诉求> |

## 产品边界

TBD

## MVP Case

<谁在什么时刻完成什么任务>
EOF
  placeholders=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  write_product_reference docs/proposals/not-used.md
  rm -f "$T/.pm-workflow/proposal.json"
  undeclared=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  python3 - "$T/PRODUCT.md" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    "[not-used.md](docs/proposals/not-used.md)",
    "接入前已有等价产品基线。\n\n"
    "- 主要依据：`docs/missing-baseline.md`\n"
    "- PM 确认日期：2025-01-01",
)
path.write_text(text, encoding="utf-8")
PY
  bad_evidence=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  mkdir -p "$T/docs"
  printf '# 已有立项材料\n' > "$T/docs/existing-product-baseline.md"
  write_intake_manifest docs/existing-product-baseline.md
  sed -i.bak 's#docs/missing-baseline.md#docs/existing-product-baseline.md#' "$T/PRODUCT.md"
  rm -f "$T/PRODUCT.md.bak"
  sed -i.bak 's/PM 确认日期：2025-01-01/PM 确认日期：2025-02-30/' "$T/PRODUCT.md"
  rm -f "$T/PRODUCT.md.bak"
  git -C "$T" add -- PRODUCT.md docs/existing-product-baseline.md \
    .pm-workflow/intake-manifest.json
  git -C "$T" commit -qm "docs: record equivalent baseline evidence"
  bad_date=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  sed -i.bak 's/PM 确认日期：2025-02-30/PM 确认日期：2025-01-01/' "$T/PRODUCT.md"
  rm -f "$T/PRODUCT.md.bak"
  dirty_git=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  git -C "$T" add -- PRODUCT.md
  git -C "$T" commit -qm "docs: confirm equivalent baseline"
  complete=$(python3 "$PROPOSAL_CONTRACT" status "$T")

  if python3 - "$incomplete" "$placeholders" "$undeclared" "$bad_evidence" "$bad_date" "$dirty_git" "$complete" <<'PY'
import json, sys
incomplete, placeholders, undeclared, bad_evidence, bad_date, dirty_git, complete = (
    json.loads(item) for item in sys.argv[1:]
)
assert incomplete["state"] == "required"
assert incomplete["reason"] == "incomplete_equivalent_baseline"
assert "主用户" in incomplete["gaps"]
assert placeholders["state"] == "required"
assert placeholders["gaps"] == [
    "产品定位", "主用户", "核心问题与价值", "产品边界", "MVP 或当前产品结果",
    "等价基线声明", "等价基线主要依据", "等价基线 PM 确认日期",
]
assert undeclared["state"] == "required"
assert undeclared["gaps"] == [
    "等价基线声明", "等价基线主要依据", "等价基线 PM 确认日期"
]
assert bad_evidence["state"] == "required"
assert bad_evidence["gaps"] == ["等价基线主要依据"]
assert bad_date["state"] == "required"
assert bad_date["gaps"] == ["等价基线 PM 确认日期"]
assert dirty_git["state"] == "required"
assert dirty_git["gaps"] == ["等价基线 Git 完整性"]
assert complete["state"] == "equivalent_baseline"
assert complete["gaps"] == []
PY
  then
    pass_test
  else
    _fail "equivalent baseline completeness state mismatch"
  fi
  teardown_fixture
}

test_placeholder_content_is_not_complete() {
  start_test "proposal-contract: placeholders cannot satisfy proposal or product judgments"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_product_reference docs/proposals/demo-v1.md

  local header_placeholder proposal_placeholder handoff_placeholder product_placeholder
  sed -i.bak 's/> 支持的决定：是否投入一次可验证的审核闭环/> 支持的决定：<一句话>/' \
    "$T/docs/proposals/demo-v1.md"
  rm -f "$T/docs/proposals/demo-v1.md.bak"
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null 2>&1
  header_placeholder=$?

  write_proposal "$T/docs/proposals/demo-v1.md"
  sed -i.bak 's/负责人需要在提交前获得可追溯证据。/待补充。/' \
    "$T/docs/proposals/demo-v1.md"
  rm -f "$T/docs/proposals/demo-v1.md.bak"
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null 2>&1
  proposal_placeholder=$?

  write_proposal "$T/docs/proposals/demo-v1.md"
  sed -i.bak 's/完成一次审核闭环/<第一个可建造结果>/' \
    "$T/docs/proposals/demo-v1.md"
  rm -f "$T/docs/proposals/demo-v1.md.bak"
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null 2>&1
  handoff_placeholder=$?

  write_proposal "$T/docs/proposals/demo-v1.md"
  sed -i.bak 's/为运营负责人提供可追溯审核建议的产品。/待确认。/' "$T/PRODUCT.md"
  rm -f "$T/PRODUCT.md.bak"
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null 2>&1
  product_placeholder=$?

  if [ "$header_placeholder" != "0" ] \
     && [ "$proposal_placeholder" != "0" ] \
     && [ "$handoff_placeholder" != "0" ] \
     && [ "$product_placeholder" != "0" ]; then
    pass_test
  else
    _fail "placeholder content passed: header=$header_placeholder proposal=$proposal_placeholder handoff=$handoff_placeholder product=$product_placeholder"
  fi
  teardown_fixture
}

test_dates_are_real_and_ordered() {
  start_test "proposal-contract: document dates must be real and evidence cannot be later"
  setup_fixture
  write_product_reference docs/proposals/demo-v1.md
  local impossible future_evidence

  write_proposal "$T/docs/proposals/demo-v1.md"
  sed -i.bak 's/> 日期：2026-08-10/> 日期：2026-02-30/' "$T/docs/proposals/demo-v1.md"
  rm -f "$T/docs/proposals/demo-v1.md.bak"
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null 2>&1
  impossible=$?

  write_proposal "$T/docs/proposals/demo-v1.md"
  sed -i.bak 's/> 证据截至：2026-08-10/> 证据截至：2026-08-11/' "$T/docs/proposals/demo-v1.md"
  rm -f "$T/docs/proposals/demo-v1.md.bak"
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null 2>&1
  future_evidence=$?

  if [ "$impossible" != "0" ] && [ "$future_evidence" != "0" ]; then
    pass_test
  else
    _fail "date validation mismatch: impossible=$impossible future=$future_evidence"
  fi
  teardown_fixture
}

test_new_project_marker_cannot_be_bypassed() {
  start_test "proposal-contract: new-project marker wins over apparently complete content"
  setup_fixture
  write_equivalent_product_baseline "$T"
  printf '\n<!-- PMAI_PROPOSAL_REQUIRED -->\n' >> "$T/PRODUCT.md"
  local status accepted_status
  status=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "fixture proposal should be accepted"
      teardown_fixture
      return
    }
  commit_v1_proposal || {
    _fail "fixture proposal commit should succeed"
    teardown_fixture
    return
  }
  printf '\n<!-- PMAI_PROPOSAL_REQUIRED -->\n' >> "$T/PRODUCT.md"
  accepted_status=$(python3 "$PROPOSAL_CONTRACT" status "$T" 2>/dev/null)
  if python3 - "$status" "$accepted_status" <<'PY'
import json, sys
value = json.loads(sys.argv[1])
assert value["state"] == "required"
assert value["reason"] == "new_project"
assert json.loads(sys.argv[2])["state"] == "invalid"
PY
  then
    pass_test
  else
    _fail "new-project marker was bypassed: $status"
  fi
  teardown_fixture
}

test_product_reference_must_be_in_current_section_body() {
  start_test "proposal-contract: product pointer cannot hide in comments or another section"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/wrong-v1.md
  sed -i.bak '/docs\/proposals\/wrong-v1.md/a\
<!-- docs/proposals/demo-v1.md -->' "$T/PRODUCT.md"
  rm -f "$T/PRODUCT.md.bak"
  sed -i.bak '/减少人工检索遗漏/a\
docs/proposals/demo-v1.md' "$T/PRODUCT.md"
  rm -f "$T/PRODUCT.md.bak"

  local out rc
  out=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 2>&1)
  rc=$?
  if [ "$rc" != "0" ] && echo "$out" | grep -q '当前 Product Proposal'; then
    pass_test
  else
    _fail "misplaced product pointer passed: rc=$rc out=$out"
  fi
  teardown_fixture
}

test_idempotent_accept_revalidates_product_baseline() {
  start_test "proposal-contract: repeated accept revalidates synchronized product baseline"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "fixture proposal should be accepted"
      teardown_fixture
      return
    }
  commit_v1_proposal || {
    _fail "fixture proposal commit should succeed"
    teardown_fixture
    return
  }
  sed -i.bak 's/负责人收到任务后核对证据、确认建议并提交审核结论。/待补充。/' "$T/PRODUCT.md"
  rm -f "$T/PRODUCT.md.bak"

  local out rc
  out=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 2>&1)
  rc=$?
  if [ "$rc" != "0" ] && echo "$out" | grep -q '尚未同步完整精简产品基线'; then
    pass_test
  else
    _fail "repeated accept skipped baseline validation: rc=$rc out=$out"
  fi
  teardown_fixture
}

test_git_currentness_rejects_split_commits() {
  start_test "proposal-contract: split commits cannot activate a schema v3 proposal"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "pending proposal contract should be generated"
      teardown_fixture
      return
    }

  git -C "$T" add -- .pm-workflow/proposal.json
  git -C "$T" commit -qm "docs: split proposal contract"
  git -C "$T" add -- docs/proposals/demo-v1.md docs/proposals/INDEX.md PRODUCT.md
  git -C "$T" commit -qm "docs: split proposal baseline"

  local status
  status=$(python3 "$PROPOSAL_CONTRACT" status "$T" 2>/dev/null)
  if python3 - "$status" <<'PY'
import json, sys
value = json.loads(sys.argv[1])
assert value["state"] == "invalid"
assert "同一提交" in value["reason"]
assert "docs/proposals/demo-v1.md" in value["reason"]
PY
  then
    pass_test
  else
    _fail "split commits unexpectedly activated proposal: $status"
  fi
  teardown_fixture
}

test_accept_requires_integration_branch_but_validate_does_not() {
  start_test "proposal-contract: build branch reads ancestor contract but cannot accept a revision"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "v1 fixture should be generated on the integration branch"
      teardown_fixture
      return
    }
  commit_v1_proposal || {
    _fail "v1 fixture commit should succeed"
    teardown_fixture
    return
  }

  git -C "$T" switch -q -c build-demo
  local inherited blocked blocked_rc contract_id
  inherited=$(python3 "$PROPOSAL_CONTRACT" validate "$T" 2>/dev/null) || {
    _fail "build branch should still read the accepted ancestor Proposal"
    teardown_fixture
    return
  }

  write_proposal "$T/docs/proposals/demo-v1.md" '已被 `docs/proposals/demo-v2.md` 取代'
  write_proposal "$T/docs/proposals/demo-v2.md" 当前 docs/proposals/demo-v1.md
  write_revision_index
  write_product_reference docs/proposals/demo-v2.md
  blocked=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1 2>&1)
  blocked_rc=$?
  contract_id=$(python3 - "$T/.pm-workflow/proposal.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["id"])
PY
)

  if [ "$blocked_rc" != "0" ] \
     && echo "$blocked" | grep -q 'main/master' \
     && [ "$contract_id" = "demo-v1" ] \
     && python3 - "$inherited" <<'PY'
import json, sys
assert json.loads(sys.argv[1])["id"] == "demo-v1"
PY
  then
    pass_test
  else
    _fail "build branch Proposal guard mismatch: rc=$blocked_rc id=$contract_id out=$blocked"
  fi
  teardown_fixture
}

test_new_accept_rejects_main_mode_active_build_without_writing_contract() {
  start_test "proposal-contract: new accept rejects main-mode active build before contract write"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  write_active_build_meta "$T" main building main

  local out rc
  out=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 2>&1)
  rc=$?
  if [ "$rc" != "0" ] \
     && echo "$out" | grep -q 'active build' \
     && echo "$out" | grep -q 'replan-work.py --route proposal' \
     && echo "$out" | grep -q '保留已经在 main 的实现' \
     && ! echo "$out" | grep -q '/pmai-build-cancel' \
     && [ ! -e "$T/.pm-workflow/proposal.json" ]; then
    pass_test
  else
    _fail "main-mode active build bypassed Proposal guard: rc=$rc out=$out"
  fi
  teardown_fixture
}

test_revision_rejects_attached_active_build_but_existing_contract_stays_readable() {
  start_test "proposal-contract: attached active build blocks revision but not ancestor reads"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "fixture proposal should be generated"
      teardown_fixture
      return
    }
  commit_v1_proposal || {
    _fail "fixture proposal commit should succeed"
    teardown_fixture
    return
  }
  attach_active_build_worktree || {
    _fail "active build worktree fixture should be created"
    teardown_fixture
    return
  }

  local inherited repeated before blocked blocked_rc after
  inherited=$(python3 "$PROPOSAL_CONTRACT" validate "$ATTACHED_WORKTREE" 2>/dev/null) || {
    _fail "active build worktree should read its ancestor Proposal"
    teardown_fixture
    return
  }
  repeated=$(python3 "$PROPOSAL_CONTRACT" accept "$ATTACHED_WORKTREE" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 2>/dev/null) || {
      _fail "idempotent accept should remain a read-only validation"
      teardown_fixture
      return
    }
  before=$(<"$T/.pm-workflow/proposal.json")

  write_proposal "$T/docs/proposals/demo-v1.md" '已被 `docs/proposals/demo-v2.md` 取代'
  write_proposal "$T/docs/proposals/demo-v2.md" 当前 docs/proposals/demo-v1.md
  write_revision_index
  write_product_reference docs/proposals/demo-v2.md
  blocked=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1 2>&1)
  blocked_rc=$?
  after=$(<"$T/.pm-workflow/proposal.json")

  if [ "$blocked_rc" != "0" ] \
     && echo "$blocked" | grep -q 'replan-work.py' \
     && [ "$before" = "$after" ] \
     && python3 - "$inherited" "$repeated" "$after" <<'PY'
import json
import sys

inherited, repeated, after = (json.loads(item) for item in sys.argv[1:])
assert inherited["id"] == "demo-v1"
assert repeated["id"] == "demo-v1"
assert after["id"] == "demo-v1"
PY
  then
    pass_test
  else
    _fail "attached active build Proposal guard mismatch: rc=$blocked_rc out=$blocked"
  fi
  teardown_fixture
}

test_schema_v2_contract_stays_readable() {
  start_test "proposal-contract: committed schema v2 remains readable"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "fixture proposal should be generated"
      teardown_fixture
      return
    }
  python3 - "$T/.pm-workflow/proposal.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value["schema_version"] = 2
value.pop("product_hash")
path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  commit_v1_proposal || {
    _fail "schema v2 fixture commit should succeed"
    teardown_fixture
    return
  }

  local status repeated
  status=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  repeated=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1) || {
      _fail "schema v2 idempotent read should succeed"
      teardown_fixture
      return
    }
  if python3 - "$status" "$repeated" <<'PY'
import json, sys
status, repeated = (json.loads(item) for item in sys.argv[1:])
assert status["state"] == "accepted"
assert status["proposal"]["schema_version"] == 2
assert repeated["schema_version"] == 2
assert "product_hash" not in repeated
PY
  then
    pass_test
  else
    _fail "schema v2 compatibility mismatch: status=$status repeated=$repeated"
  fi
  teardown_fixture
}

test_legacy_contract_requires_committed_git_state() {
  start_test "proposal-contract: legacy v1 is committed-only and non-Git remains invalid"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
      _fail "fixture proposal should be generated"
      teardown_fixture
      return
    }
  commit_v1_proposal || {
    _fail "fixture proposal commit should succeed"
    teardown_fixture
    return
  }
  python3 - "$T/.pm-workflow/proposal.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value["schema_version"] = 1
value.pop("product_hash")
path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  git -C "$T" add -- .pm-workflow/proposal.json
  git -C "$T" commit -qm "test: legacy proposal contract"

  local legacy non_git unborn_root unborn_rc
  legacy=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  mv "$T/.git" "$T/.git-saved"
  non_git=$(python3 "$PROPOSAL_CONTRACT" status "$T" 2>/dev/null)

  unborn_root="$T/unborn"
  mkdir -p "$unborn_root/docs/proposals" "$unborn_root/.pm-workflow"
  cp "$T/PRODUCT.md" "$unborn_root/PRODUCT.md"
  cp "$T/docs/proposals/demo-v1.md" "$unborn_root/docs/proposals/demo-v1.md"
  cp "$T/docs/proposals/INDEX.md" "$unborn_root/docs/proposals/INDEX.md"
  git -C "$unborn_root" init -q
  python3 "$PROPOSAL_CONTRACT" accept "$unborn_root" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null 2>&1
  unborn_rc=$?

  if python3 - "$legacy" "$non_git" "$unborn_rc" "$unborn_root/.pm-workflow/proposal.json" <<'PY'
import json, sys
legacy, non_git = (json.loads(item) for item in sys.argv[1:3])
assert legacy["state"] == "accepted"
assert legacy["proposal"]["schema_version"] == 1
assert non_git["state"] == "invalid"
assert "Git" in non_git["reason"]
assert sys.argv[3] != "0"
from pathlib import Path
assert not Path(sys.argv[4]).exists()
PY
  then
    pass_test
  else
    _fail "legacy/non-Git compatibility mismatch: legacy=$legacy non_git=$non_git unborn=$unborn_rc"
  fi
  teardown_fixture
}

test_duplicate_proposal_and_product_structure_is_rejected() {
  start_test "proposal-contract: duplicate headers and normalized protected sections fail closed"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md

  sed -i.bak '/> Proposal ID：demo-v1/a\
> Proposal ID：demo-v1' "$T/docs/proposals/demo-v1.md"
  rm -f "$T/docs/proposals/demo-v1.md.bak"
  local duplicate_header duplicate_proposal duplicate_product
  duplicate_header=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 2>&1)

  write_proposal "$T/docs/proposals/demo-v1.md"
  cat >> "$T/docs/proposals/demo-v1.md" <<'EOF'

## 0. 决策摘要与产品主张

重复内容不得覆盖前一节。
EOF
  duplicate_proposal=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 2>&1)

  write_proposal "$T/docs/proposals/demo-v1.md"
  cat >> "$T/PRODUCT.md" <<'EOF'

## 1. 产品定位

重复编号标题不得绕过保护。
EOF
  duplicate_product=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 2>&1)

  if echo "$duplicate_header" | grep -q '文档头字段不得重复' \
    && echo "$duplicate_proposal" | grep -q '重复章节：0' \
    && echo "$duplicate_product" | grep -q '受保护章节不得重复'; then
    pass_test
  else
    _fail "duplicate structure guard mismatch: header=$duplicate_header proposal=$duplicate_proposal product=$duplicate_product"
  fi
  teardown_fixture
}

test_first_proposal_requires_one_current_index_row() {
  start_test "proposal-contract: first version also requires exactly one current index row"
  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_product_reference docs/proposals/demo-v1.md
  local missing duplicate
  missing=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 2>&1)
  write_v1_index
  sed -i.bak '/demo-v1.md.*当前/a\
| [`demo-v1.md`](demo-v1.md) | v1 | 当前 | 无 | 2026-08-10 | 重复行 |' \
    "$T/docs/proposals/INDEX.md"
  rm -f "$T/docs/proposals/INDEX.md.bak"
  duplicate=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 2>&1)
  if echo "$missing" | grep -q 'INDEX.md' \
    && echo "$duplicate" | grep -q '必须且只能'; then
    pass_test
  else
    _fail "first-version index guard mismatch: missing=$missing duplicate=$duplicate"
  fi
  teardown_fixture
}

test_legacy_product_baseline_is_anchored_to_contract_commit() {
  start_test "proposal-contract: schema v1/v2 compare PRODUCT baseline with activation commit"
  local schema failures=""
  for schema in 1 2; do
    setup_fixture
    write_proposal "$T/docs/proposals/demo-v1.md"
    write_v1_index
    write_product_reference docs/proposals/demo-v1.md
    python3 "$PROPOSAL_CONTRACT" accept "$T" \
      --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null || {
        failures="$failures schema-$schema-accept"
        teardown_fixture
        continue
      }
    python3 - "$T/.pm-workflow/proposal.json" "$schema" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
value["schema_version"] = int(sys.argv[2])
value.pop("product_hash")
path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
    commit_v1_proposal || {
      failures="$failures schema-$schema-commit"
      teardown_fixture
      continue
    }
    sed -i.bak \
      's/产品给出建议，最终结论由人确认。/产品自动提交最终审核结论。/' \
      "$T/PRODUCT.md"
    rm -f "$T/PRODUCT.md.bak"
    git -C "$T" add -- PRODUCT.md
    git -C "$T" commit -qm "test: drift schema $schema product baseline"
    local state
    state=$(python3 "$PROPOSAL_CONTRACT" status "$T" 2>/dev/null)
    if ! python3 - "$state" "$schema" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
assert value["state"] == "invalid"
assert "旧版 Proposal 合同生效后发生漂移" in value["reason"]
assert "/pmai-proposal" in value["reason"]
PY
    then
      failures="$failures schema-$schema-drift"
    fi
    teardown_fixture
  done
  if [ -z "$failures" ]; then
    pass_test
  else
    _fail "legacy PRODUCT baseline anchor mismatch:$failures"
  fi
}

test_equivalent_baseline_requires_manifest_and_safe_committed_state() {
  start_test "proposal-contract: equivalent baseline binds intake manifest and adopted state"
  setup_fixture
  write_equivalent_product_baseline "$T"
  python3 - "$T/PRODUCT.md" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
path.write_text(re.sub(r"\n## MVP Case\n.*\Z", "\n", text, flags=re.S), encoding="utf-8")
PY
  git -C "$T" add -- PRODUCT.md docs/existing-product-baseline.md \
    .pm-workflow/intake-manifest.json
  git -C "$T" commit -qm "docs: baseline without committed product state"
  local uncommitted_state accepted_state unsafe_state generated_evidence tampered_manifest
  uncommitted_state=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  git -C "$T" add -- PRODUCT-STATE.md
  git -C "$T" commit -qm "docs: commit adopted current product result"
  accepted_state=$(python3 "$PROPOSAL_CONTRACT" status "$T")

  mv "$T/PRODUCT-STATE.md" "$T/PRODUCT-STATE.real.md"
  ln -s PRODUCT-STATE.real.md "$T/PRODUCT-STATE.md"
  unsafe_state=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  rm "$T/PRODUCT-STATE.md"
  mv "$T/PRODUCT-STATE.real.md" "$T/PRODUCT-STATE.md"

  printf '# PMAI generated later\n' > "$T/docs/generated-later.md"
  sed -i.bak \
    's#docs/existing-product-baseline.md#docs/generated-later.md#' "$T/PRODUCT.md"
  rm -f "$T/PRODUCT.md.bak"
  git -C "$T" add -- PRODUCT.md PRODUCT-STATE.md docs/generated-later.md
  git -C "$T" commit -qm "test: point baseline at post-intake document"
  generated_evidence=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  write_intake_manifest docs/generated-later.md
  git -C "$T" add -- .pm-workflow/intake-manifest.json
  git -C "$T" commit -qm "test: rewrite intake manifest after onboarding"
  tampered_manifest=$(python3 "$PROPOSAL_CONTRACT" status "$T")

  if python3 - "$uncommitted_state" "$accepted_state" "$unsafe_state" "$generated_evidence" "$tampered_manifest" <<'PY'
import json
import sys

uncommitted, accepted, unsafe, generated, tampered = (json.loads(item) for item in sys.argv[1:])
assert uncommitted["state"] == "required"
assert uncommitted["gaps"] == ["等价基线 Git 完整性"]
assert accepted["state"] == "equivalent_baseline"
assert unsafe["state"] == "required"
assert "等价基线文件完整性" in unsafe["gaps"]
assert generated["state"] == "required"
assert generated["gaps"] == ["接入前依据 manifest"]
assert tampered["state"] == "required"
assert tampered["gaps"] == ["接入前依据 manifest"]
PY
  then
    pass_test
  else
    _fail "equivalent baseline manifest/state guard mismatch"
  fi
  teardown_fixture
}

test_all_historical_proposals_are_immutable_across_three_versions() {
  start_test "proposal-contract: v3 protects every historical Proposal blob"
  local pre_accept_guard index_drift_guard post_accept_guard

  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null
  commit_v1_proposal
  write_proposal "$T/docs/proposals/demo-v1.md" '已被 `docs/proposals/demo-v2.md` 取代'
  write_proposal "$T/docs/proposals/demo-v2.md" 当前 docs/proposals/demo-v1.md
  write_revision_index
  write_product_reference docs/proposals/demo-v2.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1 >/dev/null
  commit_v2_proposal
  printf '\n历史正文被已提交改写。\n' >> "$T/docs/proposals/demo-v1.md"
  git -C "$T" add -- docs/proposals/demo-v1.md
  git -C "$T" commit -qm "test: drift oldest proposal"
  write_proposal "$T/docs/proposals/demo-v2.md" '已被 `docs/proposals/demo-v3.md` 取代' docs/proposals/demo-v1.md
  write_proposal "$T/docs/proposals/demo-v3.md" 当前 docs/proposals/demo-v2.md
  write_v3_index
  write_product_reference docs/proposals/demo-v3.md
  pre_accept_guard=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v3.md --id demo-v3 --supersedes demo-v2 2>&1)
  teardown_fixture

  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 >/dev/null
  commit_v1_proposal
  write_proposal "$T/docs/proposals/demo-v1.md" '已被 `docs/proposals/demo-v2.md` 取代'
  write_proposal "$T/docs/proposals/demo-v2.md" 当前 docs/proposals/demo-v1.md
  write_revision_index
  write_product_reference docs/proposals/demo-v2.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v2.md --id demo-v2 --supersedes demo-v1 >/dev/null
  commit_v2_proposal
  write_proposal "$T/docs/proposals/demo-v2.md" '已被 `docs/proposals/demo-v3.md` 取代' docs/proposals/demo-v1.md
  write_proposal "$T/docs/proposals/demo-v3.md" 当前 docs/proposals/demo-v2.md
  write_v3_index
  write_product_reference docs/proposals/demo-v3.md
  python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v3.md --id demo-v3 --supersedes demo-v2 >/dev/null
  commit_v3_proposal
  sed -i.bak '/demo-v1.md/d' "$T/docs/proposals/INDEX.md"
  rm -f "$T/docs/proposals/INDEX.md.bak"
  git -C "$T" add -- docs/proposals/INDEX.md
  git -C "$T" commit -qm "test: remove oldest proposal from index"
  index_drift_guard=$(python3 "$PROPOSAL_CONTRACT" status "$T" 2>/dev/null)
  write_v3_index
  git -C "$T" add -- docs/proposals/INDEX.md
  git -C "$T" commit -qm "test: restore accepted proposal index"
  printf '\n第三版后改写更早历史。\n' >> "$T/docs/proposals/demo-v1.md"
  git -C "$T" add -- docs/proposals/demo-v1.md
  git -C "$T" commit -qm "test: drift oldest after v3"
  post_accept_guard=$(python3 "$PROPOSAL_CONTRACT" status "$T" 2>/dev/null)

  if echo "$pre_accept_guard" | grep -q '历史版本.*漂移' \
    && python3 - "$index_drift_guard" "$post_accept_guard" <<'PY'
import json
import sys

index_drift, value = (json.loads(item) for item in sys.argv[1:])
assert index_drift["state"] == "invalid"
assert "INDEX.md" in index_drift["reason"]
assert value["state"] == "invalid"
assert "历史版本" in value["reason"]
assert "demo-v1.md" in value["reason"]
PY
  then
    pass_test
  else
    _fail "three-version history guard mismatch: before=$pre_accept_guard after=$post_accept_guard"
  fi
  teardown_fixture
}

test_product_and_evidence_files_reject_symlinks() {
  start_test "proposal-contract: PRODUCT and equivalent evidence reject symlink files"
  local unsafe_product unsafe_evidence

  setup_fixture
  write_proposal "$T/docs/proposals/demo-v1.md"
  write_v1_index
  write_product_reference docs/proposals/demo-v1.md
  mv "$T/PRODUCT.md" "$T/PRODUCT.real.md"
  ln -s PRODUCT.real.md "$T/PRODUCT.md"
  unsafe_product=$(python3 "$PROPOSAL_CONTRACT" accept "$T" \
    --proposal docs/proposals/demo-v1.md --id demo-v1 2>&1)
  teardown_fixture

  setup_fixture
  write_equivalent_product_baseline "$T"
  mv "$T/docs/existing-product-baseline.md" "$T/docs/existing-product-baseline.real.md"
  ln -s existing-product-baseline.real.md "$T/docs/existing-product-baseline.md"
  git -C "$T" add -A
  git -C "$T" commit -qm "test: unsafe symlink baseline evidence"
  unsafe_evidence=$(python3 "$PROPOSAL_CONTRACT" status "$T")
  if echo "$unsafe_product" | grep -q 'PRODUCT.md.*symlink' \
    && python3 - "$unsafe_evidence" <<'PY'
import json
import sys

value = json.loads(sys.argv[1])
assert value["state"] == "required"
assert "等价基线主要依据" in value["gaps"]
PY
  then
    pass_test
  else
    _fail "symlink file guard mismatch: product=$unsafe_product evidence=$unsafe_evidence"
  fi
  teardown_fixture
}

test_capture_intake_distinguishes_generic_paths_from_pmai_markers() {
  start_test "proposal-contract: intake capture does not mistake generic brownfield filenames for PMAI"
  local root marker_error
  root=$(mktemp -d)
  mkdir -p "$root/.codex" "$root/docs"
  printf '# Existing product state\n\nGeneric project notes.\n' > "$root/PRODUCT-STATE.md"
  printf '# Existing context\n\nGeneric context notes.\n' > "$root/docs/CONTEXT.md"
  printf '# Existing audit\n\nGeneric codebase notes.\n' > "$root/docs/CODEBASE-AUDIT.md"
  printf '{"hooks": []}\n' > "$root/.codex/hooks.json"

  if ! python3 "$PROPOSAL_CONTRACT" capture-intake "$root" >/dev/null; then
    _fail "generic brownfield filenames should not block intake capture"
    rm -rf "$root"
    return
  elif ! python3 - "$root/.pm-workflow/intake-manifest.json" <<'PY'
import json
import sys

value = json.load(open(sys.argv[1], encoding="utf-8"))
assert {item["path"] for item in value["files"]} == {
    ".codex/hooks.json",
    "PRODUCT-STATE.md",
    "docs/CODEBASE-AUDIT.md",
    "docs/CONTEXT.md",
}
PY
  then
    _fail "generic brownfield files were not preserved in the intake manifest"
    rm -rf "$root"
    return
  fi

  rm -f "$root/.pm-workflow/intake-manifest.json"
  printf '{"command": "python3 $PMAI_HOME/scripts/status-view.py"}\n' \
    > "$root/.codex/hooks.json"
  marker_error=$(python3 "$PROPOSAL_CONTRACT" capture-intake "$root" 2>&1)
  if echo "$marker_error" | grep -q 'PMAI 已接入标记.*\.codex/hooks.json' \
    && [ ! -e "$root/.pm-workflow/intake-manifest.json" ]; then
    pass_test
  else
    _fail "real PMAI content marker should block late intake capture: $marker_error"
  fi
  rm -rf "$root"
}

test_accept_and_validate_current_proposal
test_confirmed_body_drift_fails_closed
test_product_baseline_hash_protects_only_product_judgments
test_revision_requires_explicit_supersede_and_new_file
test_revision_requires_old_version_and_unique_current_index
test_unsafe_or_incomplete_proposal_is_rejected
test_full_structure_and_product_baseline_are_required
test_equivalent_baseline_requires_all_product_judgments
test_placeholder_content_is_not_complete
test_dates_are_real_and_ordered
test_new_project_marker_cannot_be_bypassed
test_product_reference_must_be_in_current_section_body
test_idempotent_accept_revalidates_product_baseline
test_git_currentness_rejects_split_commits
test_accept_requires_integration_branch_but_validate_does_not
test_new_accept_rejects_main_mode_active_build_without_writing_contract
test_revision_rejects_attached_active_build_but_existing_contract_stays_readable
test_schema_v2_contract_stays_readable
test_legacy_contract_requires_committed_git_state
test_duplicate_proposal_and_product_structure_is_rejected
test_first_proposal_requires_one_current_index_row
test_legacy_product_baseline_is_anchored_to_contract_commit
test_equivalent_baseline_requires_manifest_and_safe_committed_state
test_all_historical_proposals_are_immutable_across_three_versions
test_product_and_evidence_files_reject_symlinks
test_capture_intake_distinguishes_generic_paths_from_pmai_markers

report_results "proposal-contract"
