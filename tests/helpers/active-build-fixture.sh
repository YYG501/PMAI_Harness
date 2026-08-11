# shellcheck shell=bash

ACTIVE_BUILD_FRAMEWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

active_build_fixture_setup() {
  local target_kind="${1:-prototype}"
  local lifecycle="${2:-iterating}"
  local context_pack source_hash source_hash_version
  ACTIVE_BUILD_FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/pmai-active-build.XXXXXX")
  export ACTIVE_BUILD_FIXTURE

  git -C "$ACTIVE_BUILD_FIXTURE" init -q -b main
  git -C "$ACTIVE_BUILD_FIXTURE" config user.email test@example.com
  git -C "$ACTIVE_BUILD_FIXTURE" config user.name Test
  mkdir -p \
    "$ACTIVE_BUILD_FIXTURE/docs/modules/demo" \
    "$ACTIVE_BUILD_FIXTURE/docs/proposals" \
    "$ACTIVE_BUILD_FIXTURE/src"
  printf '# PMAI consumer\n' > "$ACTIVE_BUILD_FIXTURE/AGENTS.md"
  git -C "$ACTIVE_BUILD_FIXTURE" add -- AGENTS.md
  git -C "$ACTIVE_BUILD_FIXTURE" commit -q -m init

  cat > "$ACTIVE_BUILD_FIXTURE/docs/proposals/demo-v1.md" <<'EOF'
# Demo Product Proposal

> 版本：v1
> Proposal ID：demo-v1
> 状态：当前
> 日期：2026-08-10
> 取代：无
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
  cat > "$ACTIVE_BUILD_FIXTURE/docs/proposals/INDEX.md" <<'EOF'
# Product Proposal 索引

| 文档 | 版本 | 状态 | 取代 | 决策日期 | 下游起点 |
|---|---|---|---|---|---|
| [`demo-v1.md`](demo-v1.md) | v1 | 当前 | 无 | 2026-08-10 | 审核闭环 |
EOF
  cat > "$ACTIVE_BUILD_FIXTURE/PRODUCT.md" <<'EOF'
# Product

## 当前 Product Proposal

[demo-v1.md](docs/proposals/demo-v1.md)

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
  python3 "$ACTIVE_BUILD_FRAMEWORK_ROOT/scripts/proposal-contract.py" accept \
    "$ACTIVE_BUILD_FIXTURE" \
    --proposal docs/proposals/demo-v1.md \
    --id demo-v1 \
    --accepted-at 2026-08-10T10:00:00+08:00 >/dev/null
  git -C "$ACTIVE_BUILD_FIXTURE" add -- \
    .pm-workflow/proposal.json \
    PRODUCT.md \
    docs/proposals/INDEX.md \
    docs/proposals/demo-v1.md
  git -C "$ACTIVE_BUILD_FIXTURE" commit -q -m "docs: approve product proposal"

  printf '# 当前产品\n' > "$ACTIVE_BUILD_FIXTURE/PRODUCT-STATE.md"
  printf '# 产品规则\n' > "$ACTIVE_BUILD_FIXTURE/PRODUCT-RULES.md"
  printf '# 设计基线\n' > "$ACTIVE_BUILD_FIXTURE/DESIGN.md"
  printf '# 待办\n' > "$ACTIVE_BUILD_FIXTURE/TODO.md"
  printf '# Modules\n' > "$ACTIVE_BUILD_FIXTURE/docs/modules/INDEX.md"
  printf '# Demo spec\n' > "$ACTIVE_BUILD_FIXTURE/docs/modules/demo/spec.md"
  printf '# Demo decisions\n' > "$ACTIVE_BUILD_FIXTURE/docs/modules/demo/decisions.md"
  printf '# Demo discussion\n\n## 未决问题\n\n本轮工作无未决问题。\n' \
    > "$ACTIVE_BUILD_FIXTURE/docs/modules/demo/discussion.md"
  printf 'export const demo = true;\n' > "$ACTIVE_BUILD_FIXTURE/src/index.ts"

  python3 "$ACTIVE_BUILD_FRAMEWORK_ROOT/scripts/project-definition.py" write \
    "$ACTIVE_BUILD_FIXTURE" \
    --source docs/modules/demo/spec.md \
    --type "$target_kind" \
    --root src \
    --entrypoint src \
    --language typescript \
    --runtime node \
    --framework fixture \
    --package-manager npm \
    --build-command "npm run build" \
    --test-command "npm test" \
    --typecheck-command "npm run typecheck" >/dev/null

  git -C "$ACTIVE_BUILD_FIXTURE" add -- \
    .pm-workflow/project.yml \
    PRODUCT-STATE.md \
    PRODUCT-RULES.md \
    DESIGN.md \
    TODO.md \
    docs/modules/INDEX.md \
    docs/modules/demo/spec.md \
    docs/modules/demo/decisions.md \
    docs/modules/demo/discussion.md \
    src/index.ts
  git -C "$ACTIVE_BUILD_FIXTURE" commit -q -m "docs: approve demo design"

  context_pack=$(mktemp "${TMPDIR:-/tmp}/pmai-active-build-context.XXXXXX")
  python3 "$ACTIVE_BUILD_FRAMEWORK_ROOT/scripts/context-pack.py" \
    --repo-root "$ACTIVE_BUILD_FIXTURE" \
    --module "$ACTIVE_BUILD_FIXTURE/docs/modules/demo" \
    --output "$context_pack" >/dev/null
  read -r source_hash source_hash_version < <(
    python3 - "$context_pack" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    pack = json.load(handle)
print(pack["source_hash"], pack["source_hash_version"])
PY
  )
  rm -f "$context_pack"

  python3 - \
    "$ACTIVE_BUILD_FRAMEWORK_ROOT" \
    "$ACTIVE_BUILD_FIXTURE" \
    "$target_kind" \
    "$lifecycle" \
    "$source_hash" \
    "$source_hash_version" <<'PY'
import json
import sys
from pathlib import Path

framework_root = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
target_kind = sys.argv[3]
lifecycle = sys.argv[4]
source_hash = sys.argv[5]
source_hash_version = int(sys.argv[6])
sys.path.insert(0, str(framework_root / "scripts"))
from _lib.delivery_policy import delivery_policy_for, delivery_policy_hash

policy = delivery_policy_for(target_kind)
final_checks = ["typecheck", "production-build"]
if target_kind == "prototype":
    final_checks.extend(["browser-acceptance", "prototype-boundary"])
else:
    final_checks.append("scope-coverage")
meta = {
    "id": "work-demo",
    "name": "demo",
    "stage": 2,
    "status": "active",
    "lifecycle_state": lifecycle,
    "approved_source_hash": source_hash,
    "source_hash_version": source_hash_version,
    "design_revision": 1,
    "approved_target": {"paths": ["src/index.ts"]},
    "build": {
        "contract_version": 4,
        "anchor": "docs/modules/demo/spec.md",
        "target": {
            "kind": target_kind,
            "paths": ["src/index.ts"],
            "entrypoints": ["src"],
        },
        "approved_source_hash": source_hash,
        "source_hash_version": source_hash_version,
        "design_revision": 1,
        "delivery_policy": policy,
        "delivery_policy_hash": delivery_policy_hash(policy),
        "accepted_deltas": [],
        "lifecycle_state": lifecycle,
        "mode": "main",
        "executor": "codex",
        "branch": "main",
        "worktree": None,
        "acceptance": {
            "iteration_checks": ["typecheck"],
            "final_checks": final_checks,
            "required_checks": final_checks,
            "iteration_evidence": [],
            "evidence": [],
        },
        "docs_status": "pending",
    },
}
(repo_root / "docs/modules/demo/.work-meta.json").write_text(
    json.dumps(meta, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

  git -C "$ACTIVE_BUILD_FIXTURE" add -- docs/modules/demo/.work-meta.json
  git -C "$ACTIVE_BUILD_FIXTURE" commit -q -m "build: start demo"
}

active_build_fixture_add_second() {
  cp -R "$ACTIVE_BUILD_FIXTURE/docs/modules/demo" "$ACTIVE_BUILD_FIXTURE/docs/modules/second"
  python3 - "$ACTIVE_BUILD_FIXTURE/docs/modules/second/.work-meta.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
meta = json.loads(path.read_text(encoding="utf-8"))
meta["id"] = "work-second"
meta["name"] = "second"
meta["build"]["anchor"] = "docs/modules/second/spec.md"
path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  git -C "$ACTIVE_BUILD_FIXTURE" add -A
  git -C "$ACTIVE_BUILD_FIXTURE" commit -q -m second
}

active_build_fixture_teardown() {
  if [ -n "${ACTIVE_BUILD_FIXTURE:-}" ] && [ -d "$ACTIVE_BUILD_FIXTURE" ]; then
    rm -rf "$ACTIVE_BUILD_FIXTURE"
  fi
  unset ACTIVE_BUILD_FIXTURE
}
