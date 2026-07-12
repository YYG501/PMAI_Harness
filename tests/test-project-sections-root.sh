#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-project-sections.py"

test_root_product_is_only_authority() {
  start_test "project sections: reads root PRODUCT.md and ignores docs/PRODUCT.md"
  local t out
  t=$(mktemp -d)
  mkdir -p "$t/docs"
  cat > "$t/PRODUCT.md" <<'MD'
## 项目名称
Demo
## 产品定位
给运营团队使用的审核产品。
## 用户画像
| 角色 | 描述 | 关键诉求 |
|---|---|---|
| 运营 | 审核人员 | 快速处理 |
## 产品边界
只处理运营审核，不处理资金结算。
## 业务术语表
| 术语 | 说明 |
|---|---|
| 审核单 | 待处理业务对象 |
MD
  echo '# stale docs copy' > "$t/docs/PRODUCT.md"
  out=$(python3 "$CHECKER" "$t")
  rm -rf "$t"
  if python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["all_filled"] is True; assert d["project_path"].endswith("/PRODUCT.md") and "/docs/" not in d["project_path"]' <<<"$out"; then
    pass_test
  else
    _fail "checker did not use root PRODUCT.md"
  fi
}

test_root_missing_does_not_fall_back_to_docs() {
  start_test "project sections: missing root file does not fall back to legacy docs copy"
  local t out
  t=$(mktemp -d)
  mkdir -p "$t/docs"
  echo '## 项目名称' > "$t/docs/PRODUCT.md"
  out=$(python3 "$CHECKER" "$t")
  rm -rf "$t"
  if python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["exists"] is False; assert len(d["empty_sections"])==5' <<<"$out"; then
    pass_test
  else
    _fail "checker incorrectly used docs/PRODUCT.md"
  fi
}

test_root_product_is_only_authority
test_root_missing_does_not_fall_back_to_docs
report_results "project-sections-root"
