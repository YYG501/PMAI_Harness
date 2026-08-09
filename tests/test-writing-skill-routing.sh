#!/usr/bin/env bash
# Stable contracts for writing-skill routing. Keep wording assertions out of this suite.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DESIGN="$REPO_ROOT/skills/design/SKILL.md"
HUMANIZE="$REPO_ROOT/skills/humanize/SKILL.md"
HUMANIZE_PATTERNS="$REPO_ROOT/skills/humanize/references/patterns.md"
SPEC="$REPO_ROOT/skills/spec-writing/SKILL.md"
SPEC_TMPL="$REPO_ROOT/skills/spec-writing/templates/prd.md.tmpl"
SPEC_RULES="$REPO_ROOT/skills/spec-writing/references/writing-rules.md"
SPEC_FEWSHOTS="$REPO_ROOT/skills/spec-writing/references/few-shots.md"
PMVIEW="$REPO_ROOT/skills/_shared/PM-VIEW-RULES.md"
PMVIEW_CHECKLIST="$REPO_ROOT/skills/_shared/pm-view/checklist.md"
CHECK_PRD="$REPO_ROOT/scripts/check-prd-hierarchy.py"
DOC="$REPO_ROOT/skills/doc-writing/SKILL.md"
DOC_REF="$REPO_ROOT/skills/doc-writing/references/product-direction.md"
PUBLISH="$REPO_ROOT/skills/publish-to-lark/SKILL.md"
OLD_WRITING_DIR="$REPO_ROOT/skills/prd""-writing"
OLD_WRITING_COMMAND="/pmai-prd""-writing"

frontmatter_name() {
  sed -n '1,/^---$/p' "$1" | sed -n 's/^name:[[:space:]]*//p' | head -n 1
}

assert_route() {
  local source="$1"
  local target="$2"
  local reason="$3"
  if ! grep -Fq -- "$target" "$source"; then
    _fail "$reason"
    return 1
  fi
}

test_public_entries_and_retired_alias() {
  start_test "writing routes: public entries are stable and old alias stays retired"

  if [ "$(frontmatter_name "$HUMANIZE")" != "pmai-humanize" ] \
    || [ "$(frontmatter_name "$SPEC")" != "pmai-spec-writing" ] \
    || [ "$(frontmatter_name "$DOC")" != "pmai-doc-writing" ]; then
    _fail "writing skill frontmatter names drifted"
    return
  fi
  assert_file_missing "$OLD_WRITING_DIR" "old writing skill directory should not exist" || return
  if grep -Fq -- "$OLD_WRITING_COMMAND" "$SPEC"; then
    _fail "spec-writing should not restore the retired command alias"
    return
  fi
  pass_test
}

test_routing_graph_is_connected() {
  start_test "writing routes: each capability links to its owning workflow"

  assert_route "$DESIGN" "/pmai-spec-writing" "design must hand confirmed specifications to spec-writing" || return
  assert_route "$HUMANIZE" "/pmai-spec-writing" "humanize must route functional document work to spec-writing" || return
  assert_route "$HUMANIZE" "/pmai-doc-writing" "humanize must route product-direction documents to doc-writing" || return
  assert_route "$SPEC" "/pmai-design" "spec-writing must return unresolved product decisions to design" || return
  assert_route "$SPEC" "/pmai-humanize" "spec-writing must retain the expression-only finishing route" || return
  assert_route "$DOC" "/pmai-spec-writing" "doc-writing must route functional specifications to spec-writing" || return
  assert_route "$DOC" "/pmai-humanize" "doc-writing must retain the expression-only finishing route" || return
  pass_test
}

test_canonical_assets_are_linked() {
  start_test "writing routes: canonical rules, examples, templates, and playbook are linked"
  local asset

  for asset in "$SPEC_TMPL" "$SPEC_RULES" "$SPEC_FEWSHOTS" "$PMVIEW" \
    "$PMVIEW_CHECKLIST" "$DOC_REF" "$HUMANIZE_PATTERNS"; do
    assert_file_exists "$asset" "missing writing asset: $asset" || return
    if [ ! -s "$asset" ]; then
      _fail "writing asset is empty: $asset"
      return
    fi
  done
  assert_route "$SPEC" "references/writing-rules.md" "spec-writing must link its canonical writing rules" || return
  assert_route "$SPEC" "references/few-shots.md" "spec-writing must link its canonical examples" || return
  assert_route "$DOC" "references/product-direction.md" "doc-writing must link its product-direction playbook" || return
  pass_test
}

test_retired_forced_formats_stay_absent() {
  start_test "writing routes: retired universal formats and implementation inventories stay absent"

  if grep -Fq -- "## 五、功能清单格式（强制）" "$PMVIEW" \
    || grep -Fq -- '适用：模块 `spec.md` / `prd` 中描述具体功能时' "$PMVIEW" \
    || grep -Fq -- "原型覆盖范围表" "$SPEC" "$SPEC_TMPL" "$SPEC_FEWSHOTS" \
    || grep -Fq -- "§六 原型节 ASCII 示例" "$SPEC_FEWSHOTS" \
    || grep -Fq -- "必须用「\*\*X。\*\* 段落说明」结构" "$SPEC_RULES" \
    || grep -Fq -- "给出反例 + 反例后果" "$SPEC_RULES"; then
    _fail "a retired forced writing format was restored"
    return
  fi
  pass_test
}

test_precision_terms_are_not_blanket_banned() {
  start_test "writing routes: plain language rules preserve precise product contracts"

  if grep -Fq '死锁 / 互锁 / 悬挂引用 / 鉴权 / 三件套——改成业务语言。' "$SPEC_RULES" \
    || grep -Fq '| 鉴权 | 权限判断 |' "$HUMANIZE_PATTERNS" \
    || grep -qE '[89] 类禁用' "$SPEC" "$SPEC_RULES" "$HUMANIZE"; then
    _fail "writing rules restored a blanket ban on precise contract language"
    return
  fi
  pass_test
}

test_paths_do_not_require_machine_specific_input() {
  start_test "writing routes: document inputs do not require machine-specific paths"

  if grep -Fq -- "贴绝对路径" "$SPEC" \
    || grep -Fq -- "markdown 文件绝对路径" "$PUBLISH" \
    || grep -Eq '/Users/[^<[:space:]]+/' "$SPEC" "$DOC" "$PUBLISH"; then
    _fail "writing workflow requires a machine-specific absolute path"
    return
  fi
  pass_test
}

test_prd_lint_observable_behavior() {
  start_test "writing routes: PRD lint accepts explained terms and rejects UI hierarchy/style misuse"
  local tmp plain_doc pass_doc hierarchy_doc visual_doc
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/pmai-writing-boundary.XXXXXX")
  plain_doc="$tmp/plain.md"
  pass_doc="$tmp/pass.md"
  hierarchy_doc="$tmp/hierarchy.md"
  visual_doc="$tmp/visual.md"

  cat > "$plain_doc" <<'MARKDOWN'
# 文件确认规则

文件未确认时保留待处理状态；确认后才进入下一步。
MARKDOWN
  if ! python3 "$CHECK_PRD" "$plain_doc" >"$tmp/plain.out" 2>&1; then
    _fail "plain module prose should not be forced into a four-column table"
    rm -rf "$tmp"
    return
  fi

  cat > "$pass_doc" <<'MARKDOWN'
# 权限规格

## 六、功能需求

| 二级功能 | 三级功能 | 使用角色 | 需求描述 |
| --- | --- | --- | --- |
| 配置 | 查看详情 | 管理员 | "许可证状态 Badge"展示当前状态；服务端鉴权（校验当前用户身份和权限）为最终判断。 |

## 七、验收标准

- RBAC（按角色分配操作权限）变更后立即生效。
- SLA（服务可用性目标）不低于 99.9%。
- 阻止 IDOR（通过篡改资源编号访问无权资源）。
MARKDOWN
  if ! python3 "$CHECK_PRD" "$pass_doc" >"$tmp/pass.out" 2>&1; then
    _fail "explained UI and contract terms should pass lint"
    rm -rf "$tmp"
    return
  fi

  sed 's/| 配置 |/| 权限 Tab |/' "$pass_doc" > "$hierarchy_doc"
  if python3 "$CHECK_PRD" "$hierarchy_doc" >"$tmp/hierarchy.out" 2>&1 \
    || ! grep -Fq "权限 Tab" "$tmp/hierarchy.out"; then
    _fail "UI components used as feature hierarchy should fail with a useful reason"
    rm -rf "$tmp"
    return
  fi

  sed 's/"许可证状态 Badge"展示当前状态/许可证状态使用 Badge 红色展示/' \
    "$pass_doc" > "$visual_doc"
  if python3 "$CHECK_PRD" "$visual_doc" >"$tmp/visual.out" 2>&1 \
    || ! grep -Fq "Badge 视觉样式" "$tmp/visual.out"; then
    _fail "visual styling in product behavior should fail with a useful reason"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_public_entries_and_retired_alias
test_routing_graph_is_connected
test_canonical_assets_are_linked
test_retired_forced_formats_stay_absent
test_precision_terms_are_not_blanket_banned
test_paths_do_not_require_machine_specific_input
test_prd_lint_observable_behavior

report_results "writing-skill-routing"
