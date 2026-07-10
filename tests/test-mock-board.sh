#!/usr/bin/env bash
# Tests for scripts/gen-mock-board.py
#
# 验证 mock 变体看版生成器：
# - 含 2 活跃/待合并 + 1 已退役 + 1 featured 的样例 manifest → 生成 index.html
# - 生成的看版按需求分组，含所有变体的链接 / 字段
# - 看版含左侧目录和搜索
# - 卡片路径渲染成统一查看页，查看页含返回目录 / 打开页面
# - 已退役变体在 <details> 折叠块里
# - 旧 round 文案可兜底推导需求分组
# - featured 变体带高亮标记
# - 顶部含"勿手改"生成物注释
# - manifest 不存在 → 生成"暂无变体"空看版，不崩
# - manifest 空 variants → 同上
# - 坏 JSON → 降级空看版，不崩
# - templates/mockups-manifest.json.tmpl 是合法 JSON 且能喂给生成器
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GEN="$REPO_ROOT/scripts/gen-mock-board.py"
IMPORT="$REPO_ROOT/scripts/import-mockup-variants.py"

# 每个场景用独立临时 repo 根；跑完清理
_make_repo() {
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/mockups"
  echo "$tmp"
}

# -----------------------------------------------------------------
# Scenario 1: 完整样例 manifest（2 活跃/待合并 + 1 已退役 + 1 featured）
# -----------------------------------------------------------------
test_full_manifest() {
  start_test "完整 manifest → 看版含全部变体 + 折叠退役 + 高亮 featured"
  local repo; repo=$(_make_repo)
  cat > "$repo/mockups/manifest.json" <<'JSON'
{
  "variants": [
    {
      "path": "approach-a/index.html",
      "requirement": "导航结构",
      "title": "方案 A：左侧导航",
      "explores": "左侧固定导航",
      "good_parts": "导航分组清晰",
      "status": "活跃",
      "round": "r1",
      "featured": true
    },
    {
      "path": "approach-b/index.html",
      "requirement": "导航结构",
      "title": "方案 B：顶部切换",
      "explores": "顶部 tab 切换",
      "good_parts": "切换快",
      "status": "待合并",
      "round": "r1",
      "featured": false
    },
    {
      "path": "skeleton-v0.html",
      "requirement": "导航结构",
      "title": "早期骨架",
      "explores": "最早的骨架草图",
      "good_parts": "卡片间距",
      "status": "已退役",
      "round": "r0",
      "featured": false,
      "retired_note": "已并入主原型（prototype/app/page.tsx, commit abc123）"
    }
  ]
}
JSON

  local out; out=$(python3 "$GEN" "$repo" 2>&1)
  local rc=$?
  assert_equal "0" "$rc" "gen should exit 0 on full manifest" || { echo "$out"; rm -rf "$repo"; return; }

  local html="$repo/mockups/index.html"
  local viewer="$repo/mockups/viewer.html"
  assert_file_exists "$html" || { rm -rf "$repo"; return; }
  assert_file_exists "$viewer" || { rm -rf "$repo"; return; }

  # 生成物注释（勿手改）
  assert_file_contains "$html" "勿手改" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "gen-mock-board.py" || { rm -rf "$repo"; return; }
  assert_file_contains "$viewer" "勿手改" || { rm -rf "$repo"; return; }

  # 按需求分组，三个变体的链接都出现
  assert_file_contains "$html" "board-sidebar" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "data-search" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "输入方向、亮点或轮次" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" 'href="#req-1"' || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "导航结构" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "approach-a/index.html" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "approach-b/index.html" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "skeleton-v0.html" || { rm -rf "$repo"; return; }

  # 卡片点击先进统一查看页，查看页提供返回目录 / 打开页面
  assert_file_contains "$html" 'href="viewer.html?path=approach-a%2Findex.html' || { rm -rf "$repo"; return; }
  assert_file_contains "$html" 'iframe src="approach-a/index.html"' || { rm -rf "$repo"; return; }
  assert_file_contains "$viewer" "返回目录" || { rm -rf "$repo"; return; }
  assert_file_contains "$viewer" "打开页面" || { rm -rf "$repo"; return; }
  assert_file_contains "$viewer" 'href="index.html"' || { rm -rf "$repo"; return; }

  # 字段内容渲染
  assert_file_contains "$html" "方案 A：左侧导航" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "左侧固定导航" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "导航分组清晰" || { rm -rf "$repo"; return; }

  # featured 高亮标记
  assert_file_contains "$html" "badge-featured" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "已选方向" || { rm -rf "$repo"; return; }

  # 已退役在 <details> 折叠块
  assert_file_contains "$html" "<details" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "已归档设计稿" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "已并入主原型" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 1b: 已退役变体的路径在折叠块内部（结构断言，非仅文本存在）
# -----------------------------------------------------------------
test_retired_inside_details() {
  start_test "已退役变体路径在 <details> 折叠块内部"
  local repo; repo=$(_make_repo)
  cat > "$repo/mockups/manifest.json" <<'JSON'
{
  "variants": [
    {"path": "live.html", "explores": "活的", "good_parts": "x", "status": "活跃", "round": "r1", "featured": false},
    {"path": "dead.html", "explores": "退役的", "good_parts": "y", "status": "已退役", "round": "r0", "featured": false}
  ]
}
JSON
  python3 "$GEN" "$repo" >/dev/null 2>&1
  local html="$repo/mockups/index.html"

  # 取 <details> 之后的内容，断言 dead.html 在其中、live.html 不在其中
  local after_details; after_details=$(python3 - "$html" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
idx = text.find("<details")
print(text[idx:] if idx >= 0 else "")
PY
)
  echo "$after_details" | grep -q "dead.html" || { _fail "dead.html should be inside <details>"; rm -rf "$repo"; return; }
  echo "$after_details" | grep -q "live.html" && { _fail "live.html should NOT be inside <details>"; rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 1c: 旧 round 文案兜底推导需求分组
# -----------------------------------------------------------------
test_round_derives_requirement_group() {
  start_test "旧 round 文案 → 兜底按同一需求分组"
  local repo; repo=$(_make_repo)
  cat > "$repo/mockups/manifest.json" <<'JSON'
{
  "variants": [
    {"path": "pet-a/index.html", "explores": "向导式添加流程", "good_parts": "新手路径清楚", "status": "活跃", "round": "宠物导入与创作第一轮", "featured": false},
    {"path": "pet-b/index.html", "explores": "连续添加队列", "good_parts": "适合连续处理素材", "status": "活跃", "round": "宠物导入与创作第二轮", "featured": false}
  ]
}
JSON
  python3 "$GEN" "$repo" >/dev/null 2>&1
  local html="$repo/mockups/index.html"

  assert_file_contains "$html" "宠物导入与创作" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "第一轮" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "第二轮" || { rm -rf "$repo"; return; }

  local heading_count; heading_count=$(grep -o "<h2>宠物导入与创作" "$html" | wc -l | tr -d ' ')
  assert_equal "1" "$heading_count" "same requirement should render one heading" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 2: manifest 不存在 → 空看版，不崩
# -----------------------------------------------------------------
test_missing_manifest() {
  start_test "manifest 不存在 → 生成空看版 + exit 0"
  local repo; repo=$(_make_repo)
  # 不写 manifest.json

  local out; out=$(python3 "$GEN" "$repo" 2>&1)
  local rc=$?
  assert_equal "0" "$rc" "missing manifest should exit 0" || { echo "$out"; rm -rf "$repo"; return; }

  local html="$repo/mockups/index.html"
  assert_file_exists "$html" || { rm -rf "$repo"; return; }
  assert_file_exists "$repo/mockups/viewer.html" || { rm -rf "$repo"; return; }
  assert_file_contains "$html" "暂无变体" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 3: manifest 空 variants → 空看版
# -----------------------------------------------------------------
test_empty_variants() {
  start_test "manifest variants 为空 → 空看版 + exit 0"
  local repo; repo=$(_make_repo)
  echo '{"variants": []}' > "$repo/mockups/manifest.json"

  local out; out=$(python3 "$GEN" "$repo" 2>&1)
  local rc=$?
  assert_equal "0" "$rc" "empty variants should exit 0" || { echo "$out"; rm -rf "$repo"; return; }

  assert_file_contains "$repo/mockups/index.html" "暂无变体" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 4: 坏 JSON → 降级空看版，不崩
# -----------------------------------------------------------------
test_bad_json() {
  start_test "坏 JSON → 降级空看版 + exit 0（不崩）"
  local repo; repo=$(_make_repo)
  printf '{ this is not valid json' > "$repo/mockups/manifest.json"

  local out; out=$(python3 "$GEN" "$repo" 2>&1)
  local rc=$?
  assert_equal "0" "$rc" "bad json should not crash" || { echo "$out"; rm -rf "$repo"; return; }
  assert_file_contains "$repo/mockups/index.html" "暂无变体" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 5: 模板 mockups-manifest.json.tmpl 合法且能喂给生成器
# -----------------------------------------------------------------
test_template_valid() {
  start_test "templates/mockups-manifest.json.tmpl 是合法 JSON 且生成空看版"
  local tmpl="$REPO_ROOT/templates/mockups-manifest.json.tmpl"
  assert_file_exists "$tmpl" || return

  # 合法 JSON
  python3 -c "import json,sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$tmpl" \
    || { _fail "template is not valid JSON"; return; }

  # 拿模板当 manifest 喂给生成器（应得空看版，因 variants 为空）
  local repo; repo=$(_make_repo)
  cp "$tmpl" "$repo/mockups/manifest.json"
  local out; out=$(python3 "$GEN" "$repo" 2>&1)
  local rc=$?
  assert_equal "0" "$rc" "template should generate without error" || { echo "$out"; rm -rf "$repo"; return; }
  assert_file_contains "$repo/mockups/index.html" "暂无变体" || { rm -rf "$repo"; return; }

  rm -rf "$repo"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 6: README 模板存在
# -----------------------------------------------------------------
test_readme_template_exists() {
  start_test "templates/mockups-README.md.tmpl 存在"
  assert_file_exists "$REPO_ROOT/templates/mockups-README.md.tmpl" || return
  pass_test
}

# -----------------------------------------------------------------
# Scenario 7: mockup skill 画之前必须对齐已有界面
# -----------------------------------------------------------------
test_mockup_skill_aligns_existing_ui() {
  start_test "mockup skill 默认先对齐已有界面"
  local skill="$REPO_ROOT/skills/mockup/SKILL.md"
  assert_file_exists "$skill" || return

  assert_file_contains "$skill" "### 1. 先对齐现有产品" || return
  assert_file_contains "$skill" '读 `DESIGN.md`' || return
  assert_file_contains "$skill" '读相关 `prototype/` 或真实产品页面' || return
  assert_file_contains "$skill" "已选、待合并和已退役方向" || return
  assert_file_contains "$skill" "默认贴合当前产品" || return
  assert_file_contains "$skill" "换风格" || return
  assert_file_contains "$skill" "在定基调" || return
  assert_file_contains "$skill" "不重新发明一套视觉语言" || return

  pass_test
}

# -----------------------------------------------------------------
# Scenario 8: gstack design-shotgun 输出可接回 PMAI mockups/
# -----------------------------------------------------------------
test_import_gstack_shotgun_results() {
  start_test "gstack 输出 → 复制进 mockups + 登记挑定方向"
  local repo; repo=$(_make_repo)
  cp "$REPO_ROOT/templates/mockups-manifest.json.tmpl" "$repo/mockups/manifest.json"

  local source; source=$(mktemp -d)
  printf 'fake-png-a' > "$source/variant-A.png"
  printf 'fake-png-b' > "$source/variant-B.png"
  cat > "$source/feedback.json" <<'JSON'
{
  "preferred": "B",
  "ratings": {"A": 3, "B": 5},
  "comments": {"B": "信息密度更合适"},
  "overall": "选 B，保留右侧详情"
}
JSON
  cat > "$source/approved.json" <<'JSON'
{"approved_variant": "B", "screen": "pipeline"}
JSON
  local concepts="$source/concepts.json"
  cat > "$concepts" <<'JSON'
{
  "A": {"title": "方案 A：低风险贴合", "explores": "沿用现有卡片结构", "good_parts": "落地风险低"},
  "B": {"title": "方案 B：任务流优先", "explores": "先看任务流再展开详情", "good_parts": "处理路径更清楚"}
}
JSON

  local out; out=$(python3 "$IMPORT" \
    --repo "$repo" \
    --source-dir "$source" \
    --requirement "商机工作台" \
    --round "第一轮" \
    --concepts "$concepts" \
    --dest-slug "deal-workspace" 2>&1)
  local rc=$?
  assert_equal "0" "$rc" "import should exit 0" || { echo "$out"; rm -rf "$repo" "$source"; return; }
  assert_file_exists "$repo/mockups/deal-workspace/round-1/variant-A.png" || { rm -rf "$repo" "$source"; return; }
  assert_file_exists "$repo/mockups/deal-workspace/round-1/variant-B.png" || { rm -rf "$repo" "$source"; return; }

  local manifest="$repo/mockups/manifest.json"
  assert_file_contains "$manifest" "方案 B：任务流优先" || { rm -rf "$repo" "$source"; return; }
  assert_file_contains "$manifest" "信息密度更合适" || { rm -rf "$repo" "$source"; return; }
  assert_file_contains "$manifest" '"status": "待合并"' || { rm -rf "$repo" "$source"; return; }
  assert_file_contains "$manifest" '"featured": true' || { rm -rf "$repo" "$source"; return; }

  python3 "$GEN" "$repo" >/dev/null 2>&1
  assert_file_contains "$repo/mockups/index.html" "商机工作台" || { rm -rf "$repo" "$source"; return; }
  assert_file_contains "$repo/mockups/index.html" "已选方向" || { rm -rf "$repo" "$source"; return; }

  rm -rf "$repo" "$source"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 9: PM 上传图片可导入 mockups/
# -----------------------------------------------------------------
test_import_uploaded_images() {
  start_test "用户上传图片 → 复制进 mockups + 登记为活跃设计稿"
  local repo; repo=$(_make_repo)
  local upload; upload=$(mktemp -d)
  printf 'uploaded-image' > "$upload/customer.png"

  local out; out=$(python3 "$IMPORT" \
    --repo "$repo" \
    --image "$upload/customer.png" \
    --requirement "客户导入" \
    --round "第二轮" \
    --dest-slug "customer-import" 2>&1)
  local rc=$?
  assert_equal "0" "$rc" "upload import should exit 0" || { echo "$out"; rm -rf "$repo" "$upload"; return; }

  assert_file_exists "$repo/mockups/customer-import/round-2/variant-A.png" || { rm -rf "$repo" "$upload"; return; }
  assert_file_contains "$repo/mockups/manifest.json" "外部设计稿 A" || { rm -rf "$repo" "$upload"; return; }
  assert_file_contains "$repo/mockups/manifest.json" '"status": "活跃"' || { rm -rf "$repo" "$upload"; return; }
  assert_file_contains "$repo/mockups/manifest.json" '"featured": false' || { rm -rf "$repo" "$upload"; return; }

  rm -rf "$repo" "$upload"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 10: mockup skill 发散 / gstack / 上传图片 / 禁内置出图
# -----------------------------------------------------------------
test_mockup_skill_gstack_or_upload_only_for_images() {
  start_test "mockup skill 用 gstack 或上传图片，不恢复内置出图"
  local skill="$REPO_ROOT/skills/mockup/SKILL.md"
  assert_file_contains "$skill" "判断是否存在真实交互岔路" || return
  assert_file_contains "$skill" "只是颜色、字体、圆角或左右换位" || return
  assert_file_contains "$skill" "框架自动选择工具" || return
  assert_file_contains "$skill" "gstack 受限：走 PMAI 内部 HTML / 静态稿" || return
  assert_file_contains "$skill" "有真实岔路" || return
  assert_file_contains "$skill" "scripts/import-mockup-variants.py" || return
  assert_file_contains "$skill" "PM 已给截图/设计图" || return

  local legacy_count
  legacy_count=$(grep -c "scripts/gen-mockup-image.sh" "$skill" || true)
  assert_equal "0" "$legacy_count" "旧出图脚本不应回到 mockup workflow" || return
  if grep -q "用框架自带的出图脚本\\|每版调一次出图脚本\\|codex@\\|codex 0.135.0" "$skill"; then
    _fail "mockup skill should not keep built-in image generation workflow"
    return
  fi

  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_full_manifest
test_retired_inside_details
test_round_derives_requirement_group
test_missing_manifest
test_empty_variants
test_bad_json
test_template_valid
test_readme_template_exists
test_mockup_skill_aligns_existing_ui
test_import_gstack_shotgun_results
test_import_uploaded_images
test_mockup_skill_gstack_or_upload_only_for_images

report_results "mock-board"
