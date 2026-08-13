#!/usr/bin/env bash
# Tests for scripts/mockup-quality.py.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
QUALITY="$REPO_ROOT/scripts/mockup-quality.py"

_make_repo() {
  local repo
  repo=$(mktemp -d "${TMPDIR:-/tmp}/pmai-mockup-quality.XXXXXX")
  mkdir -p "$repo/mockups/demo" "$repo/src"
  cat > "$repo/DESIGN.md" <<'EOF'
# Demo DESIGN

## 一、视觉基调

- 安静、聚焦任务结果。

## 四、项目设计系统

- 状态：未接入
- 设计系统：
- 使用范围：
- 项目级 Skill：
- Skill 文件：
EOF
  cat > "$repo/src/shell.html" <<'EOF'
<main>Existing shell</main>
EOF
  cat > "$repo/mockups/demo/index.html" <<'EOF'
<main>Mockup</main>
EOF
  echo "$repo"
}

_compile() {
  local repo="$1"
  python3 "$QUALITY" compile \
    --repo "$repo" \
    --requirement "协作工作台" \
    --round "第二轮" \
    --round-goal "让用户先看到 Agent 判断，再下钻证据" \
    --reference "src/shell.html" \
    --must-inherit "主任务结果是第一视觉层级" \
    --reuse "复用现有应用导航和页面标题模式" \
    --may-change "允许调整工作区内的信息组织" \
    --guardrail "首屏不堆叠同级面板" \
    --out "mockups/audits/collaboration/round-2/design-basis.json"
}

_write_pngs_and_report() {
  local repo="$1"
  python3 - "$repo" <<'PY'
import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path

root = Path(sys.argv[1])

def png(path, width, height):
    raw = b"".join(b"\x00" + b"\xff\xff\xff" * width for _ in range(height))
    def chunk(name, payload):
        return struct.pack(">I", len(payload)) + name + payload + struct.pack(">I", zlib.crc32(name + payload) & 0xffffffff)
    data = b"\x89PNG\r\n\x1a\n"
    data += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 1))
    data += chunk(b"IEND", b"")
    path.write_bytes(data)

audit_dir = root / "mockups/audits/collaboration/round-2"
audit_dir.mkdir(parents=True, exist_ok=True)
png(audit_dir / "desktop.png", 1024, 640)
png(audit_dir / "narrow.png", 390, 640)
contract = audit_dir / "design-basis.json"
check_ids = [
    "design-principles",
    "existing-shell-and-components",
    "information-hierarchy",
    "task-path-and-states",
    "responsive-layout",
    "text-and-controls",
]
constraint_ids = ["must-inherit-1", "reuse-1", "may-change-1", "guardrail-1"]
report = {
    "schema_version": 1,
    "kind": "mockup-visual-audit",
    "design_basis": "mockups/audits/collaboration/round-2/design-basis.json",
    "design_basis_sha256": hashlib.sha256(contract.read_bytes()).hexdigest(),
    "audited_at": "2026-08-13T18:00:00+08:00",
    "browser_adapter": "playwright",
    "variants": [{
        "path": "mockups/demo/index.html",
        "screenshots": {
            "desktop": {"path": "mockups/audits/collaboration/round-2/desktop.png", "width": 1024, "height": 640, "sha256": hashlib.sha256((audit_dir / "desktop.png").read_bytes()).hexdigest(), "captured_at": "2026-08-13T17:55:00+08:00"},
            "narrow": {"path": "mockups/audits/collaboration/round-2/narrow.png", "width": 390, "height": 640, "sha256": hashlib.sha256((audit_dir / "narrow.png").read_bytes()).hexdigest(), "captured_at": "2026-08-13T17:56:00+08:00"},
        },
        "checks": [{"id": item, "status": "pass", "evidence": f"checked {item}"} for item in check_ids],
        "constraint_results": [{"id": item, "status": "pass", "evidence": f"checked {item}"} for item in constraint_ids],
        "observations": ["核心判断先于辅助证据，窄屏没有遮挡或横向溢出。"],
    }],
}
(audit_dir / "visual-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

test_compile_requires_existing_ui_or_new_baseline() {
  start_test "mockup-quality: 已有产品必须绑定现有界面参考"
  local repo
  repo=$(_make_repo)
  if python3 "$QUALITY" compile \
      --repo "$repo" \
      --requirement "协作工作台" \
      --round "第一轮" \
      --round-goal "确定主任务层级" \
      --must-inherit "继承视觉基调" \
      --reuse "复用应用外壳" \
      --may-change "允许调整内容区" \
      --guardrail "减少同级信息竞争" >/tmp/mockup-quality.$$ 2>&1; then
    _fail "compile should reject an unbound existing UI"
    rm -rf "$repo"
    return
  fi
  if ! grep -q "必须至少绑定一个现有页面" /tmp/mockup-quality.$$; then
    _fail "compile failure should explain the missing reference"
    rm -rf "$repo"
    return
  fi
  rm -rf "$repo"
  pass_test
}

test_compile_and_verify_visual_audit() {
  start_test "mockup-quality: 设计依据 + 双 viewport + 逐项检查通过"
  local repo
  repo=$(_make_repo)
  if ! _compile "$repo" >/tmp/mockup-quality.$$ 2>&1; then
    _fail "compile should succeed"
    cat /tmp/mockup-quality.$$ >&2
    rm -rf "$repo"
    return
  fi
  local contract="$repo/mockups/audits/collaboration/round-2/design-basis.json"
  assert_file_contains "$contract" '"path": "DESIGN.md"' || { rm -rf "$repo"; return; }
  assert_file_contains "$contract" '"path": "src/shell.html"' || { rm -rf "$repo"; return; }
  assert_file_contains "$contract" '"id": "guardrail-1"' || { rm -rf "$repo"; return; }

  if ! python3 "$QUALITY" init-audit \
      --repo "$repo" \
      --contract "mockups/audits/collaboration/round-2/design-basis.json" \
      --variant "mockups/demo/index.html" \
      --out "mockups/audits/collaboration/round-2/audit-template.json" \
      >/tmp/mockup-quality.$$ 2>&1; then
    _fail "init-audit should create a report template"
    cat /tmp/mockup-quality.$$ >&2
    rm -rf "$repo"
    return
  fi
  local template="$repo/mockups/audits/collaboration/round-2/audit-template.json"
  assert_file_contains "$template" '"id": "design-principles"' || { rm -rf "$repo"; return; }
  assert_file_contains "$template" '"id": "must-inherit-1"' || { rm -rf "$repo"; return; }
  assert_file_contains "$template" '"status": "pending"' || { rm -rf "$repo"; return; }

  _write_pngs_and_report "$repo"
  if python3 "$QUALITY" verify \
      --repo "$repo" \
      --contract "mockups/audits/collaboration/round-2/design-basis.json" \
      --report "mockups/audits/collaboration/round-2/visual-audit.json" \
      >/tmp/mockup-quality.$$ 2>&1 && grep -q "MOCKUP_QUALITY: PASS" /tmp/mockup-quality.$$; then
    rm -rf "$repo"
    pass_test
  else
    _fail "complete visual audit should pass"
    cat /tmp/mockup-quality.$$ >&2
    rm -rf "$repo"
  fi
}

test_verify_rejects_stale_design_basis() {
  start_test "mockup-quality: DESIGN.md 变化后旧视觉证据失效"
  local repo
  repo=$(_make_repo)
  _compile "$repo" >/dev/null 2>&1
  _write_pngs_and_report "$repo"
  echo "- 新增设计约束" >> "$repo/DESIGN.md"
  if python3 "$QUALITY" verify \
      --repo "$repo" \
      --contract "mockups/audits/collaboration/round-2/design-basis.json" \
      --report "mockups/audits/collaboration/round-2/visual-audit.json" \
      >/tmp/mockup-quality.$$ 2>&1; then
    _fail "stale design evidence should fail"
    rm -rf "$repo"
    return
  fi
  if grep -q "DESIGN.md 已变化" /tmp/mockup-quality.$$; then
    rm -rf "$repo"
    pass_test
  else
    _fail "stale failure should name DESIGN.md"
    cat /tmp/mockup-quality.$$ >&2
    rm -rf "$repo"
  fi
}

test_compile_requires_existing_ui_or_new_baseline
test_compile_and_verify_visual_audit
test_verify_rejects_stale_design_basis

report_results "mockup-quality"
