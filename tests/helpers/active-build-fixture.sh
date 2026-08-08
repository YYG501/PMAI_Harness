# shellcheck shell=bash

ACTIVE_BUILD_FRAMEWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

active_build_fixture_setup() {
  local target_kind="${1:-prototype}"
  local lifecycle="${2:-iterating}"
  ACTIVE_BUILD_FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/pmai-active-build.XXXXXX")
  export ACTIVE_BUILD_FIXTURE

  git -C "$ACTIVE_BUILD_FIXTURE" init -q -b main
  git -C "$ACTIVE_BUILD_FIXTURE" config user.email test@example.com
  git -C "$ACTIVE_BUILD_FIXTURE" config user.name Test
  mkdir -p "$ACTIVE_BUILD_FIXTURE/docs/modules/demo" "$ACTIVE_BUILD_FIXTURE/src"
  printf '# PMAI consumer\n' > "$ACTIVE_BUILD_FIXTURE/AGENTS.md"
  printf '# 当前产品\n' > "$ACTIVE_BUILD_FIXTURE/PRODUCT-STATE.md"
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

  python3 - "$ACTIVE_BUILD_FRAMEWORK_ROOT" "$ACTIVE_BUILD_FIXTURE" "$target_kind" "$lifecycle" <<'PY'
import json
import sys
from pathlib import Path

framework_root = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
target_kind = sys.argv[3]
lifecycle = sys.argv[4]
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
    "build": {
        "contract_version": 4,
        "anchor": "docs/modules/demo/spec.md",
        "target": {
            "kind": target_kind,
            "paths": ["src/index.ts"],
            "entrypoints": ["src"],
        },
        "approved_source_hash": "a" * 64,
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

  git -C "$ACTIVE_BUILD_FIXTURE" add -A
  git -C "$ACTIVE_BUILD_FIXTURE" commit -q -m init
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
