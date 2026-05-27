#!/usr/bin/env bash
# test-prd-hierarchy-lint.sh
#
# 验证 scripts/check-prd-hierarchy.py 三类检查：
#   T1: 类 1 — §六 层级 UI 词违规（既有覆盖，保留 smoke）
#   T2: 类 2 — 描述风格违规（既有覆盖，保留 smoke）
#   T3: 类 3 — §六 表格结构（<br/> 单格塞编号 → fail）
#   T4: 类 3 — 续行 rowspan 正例 → pass
#   T5: 类 2 — fenced code block 内 ASCII 原型字符不被误报 → pass
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT="$REPO_ROOT/scripts/check-prd-hierarchy.py"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# -----------------------------------------------------------------
# T3: <br/> 单格塞编号 → 类 3 fail
# -----------------------------------------------------------------
start_test "T3 类 3 — <br/> 单格塞编号 fail"

cat > "$TMP_DIR/prd-br-violation.md" <<'EOF'
## 六、功能需求

### 6.1 测试节

#### 功能表格

| 二级功能 | 三级功能 | 使用角色 | 需求描述 |
| --- | --- | --- | --- |
| 列表 | 查看 | 角色 A | 1. 第一条规则<br/>2. 第二条规则<br/>3. 第三条规则 |

## 七、验收标准

无。
EOF

if python3 "$LINT" "$TMP_DIR/prd-br-violation.md" > "$TMP_DIR/out-br.txt" 2>&1; then
  _fail "T3: <br/> 单格 PRD lint 应失败但返回 0"
else
  rc=$?
  if [ "$rc" = "1" ] && grep -q "类 3 — §六 表格结构违规" "$TMP_DIR/out-br.txt"; then
    pass_test "T3 类 3 — <br/> 单格塞编号 fail"
  else
    _fail "T3: 退出码 $rc / 类 3 段缺失"
    cat "$TMP_DIR/out-br.txt" >&2
  fi
fi

# -----------------------------------------------------------------
# T4: 续行 rowspan 正例 → 类 3 pass
# -----------------------------------------------------------------
start_test "T4 类 3 — 续行 rowspan 正例 pass"

cat > "$TMP_DIR/prd-rowspan-ok.md" <<'EOF'
## 六、功能需求

### 6.1 测试节

#### 功能表格

| 二级功能 | 三级功能 | 使用角色 | 需求描述 |
| --- | --- | --- | --- |
| 列表 | 查看 | 角色 A | 1. 第一条规则 |
| | | | 2. 第二条规则 |
| | | | 3. 第三条规则 |

## 七、验收标准

无。
EOF

if python3 "$LINT" "$TMP_DIR/prd-rowspan-ok.md" > "$TMP_DIR/out-rowspan.txt" 2>&1; then
  if grep -q "✓ lint 通过" "$TMP_DIR/out-rowspan.txt"; then
    pass_test "T4 类 3 — 续行 rowspan 正例 pass"
  else
    _fail "T4: 退出 0 但缺通过 marker"
    cat "$TMP_DIR/out-rowspan.txt" >&2
  fi
else
  _fail "T4: 续行 rowspan 正例应通过但退出 $?"
  cat "$TMP_DIR/out-rowspan.txt" >&2
fi

# -----------------------------------------------------------------
# T1: 类 1 §六 层级 UI 词 smoke
# -----------------------------------------------------------------
start_test "T1 类 1 — UI 词违规 fail"

cat > "$TMP_DIR/prd-l1-violation.md" <<'EOF'
## 六、功能需求

### 6.1 测试节

#### 功能表格

| 二级功能 | 三级功能 | 使用角色 | 需求描述 |
| --- | --- | --- | --- |
| 分配额度弹窗 | 字段输入 | 角色 A | 1. 业务规则 |

## 七、验收标准

无。
EOF

if python3 "$LINT" "$TMP_DIR/prd-l1-violation.md" > "$TMP_DIR/out-l1.txt" 2>&1; then
  _fail "T1: UI 词 PRD 应 fail 但返回 0"
else
  if grep -q "类 1 — §六 功能需求层级违规" "$TMP_DIR/out-l1.txt"; then
    pass_test "T1 类 1 — UI 词违规 fail"
  else
    _fail "T1: 类 1 段缺失"
    cat "$TMP_DIR/out-l1.txt" >&2
  fi
fi

# -----------------------------------------------------------------
# T2: 类 2 描述风格 smoke
# -----------------------------------------------------------------
start_test "T2 类 2 — 描述风格违规 fail"

cat > "$TMP_DIR/prd-l2-violation.md" <<'EOF'
## 六、功能需求

### 6.1 测试节

#### 功能表格

| 二级功能 | 三级功能 | 使用角色 | 需求描述 |
| --- | --- | --- | --- |
| 列表 | 查看 | 角色 A | 1. 用颜色 #FF0000 标记 |

## 七、验收标准

无。
EOF

if python3 "$LINT" "$TMP_DIR/prd-l2-violation.md" > "$TMP_DIR/out-l2.txt" 2>&1; then
  _fail "T2: 颜色 hex PRD 应 fail 但返回 0"
else
  if grep -q "类 2 — 描述风格违规" "$TMP_DIR/out-l2.txt"; then
    pass_test "T2 类 2 — 描述风格违规 fail"
  else
    _fail "T2: 类 2 段缺失"
    cat "$TMP_DIR/out-l2.txt" >&2
  fi
fi

# -----------------------------------------------------------------
# T5: fenced code block 内 ASCII 原型字符（▾ / · / ⋮）不被类 2 误报
# -----------------------------------------------------------------
start_test "T5 类 2 — fenced block ASCII 原型字符不误报"

cat > "$TMP_DIR/prd-ascii-ok.md" <<'EOF'
## 六、功能需求

### 6.1 角色管理

这是角色列表页 —— 进入菜单后默认展示。

```
┌────────────────────────────────────────┐
│  角色管理        筛选: 类型[全部▾]      │
├────────────────────────────────────────┤
│  财务审计员      · 自定义 · 2 人        │
│  区域销售总监    · 自定义 · 5 人        │
└────────────────────────────────────────┘
```

| 二级功能 | 三级功能 | 使用角色 | 需求描述 |
| --- | --- | --- | --- |
| 列表 | 查看 | 角色 A | 1. 业务规则 |

## 七、验收标准

无。
EOF

if python3 "$LINT" "$TMP_DIR/prd-ascii-ok.md" > "$TMP_DIR/out-ascii.txt" 2>&1; then
  if grep -q "✓ lint 通过" "$TMP_DIR/out-ascii.txt"; then
    pass_test "T5 类 2 — fenced block ASCII 原型字符不误报"
  else
    _fail "T5: 退出 0 但缺通过 marker"
    cat "$TMP_DIR/out-ascii.txt" >&2
  fi
else
  _fail "T5: fenced ASCII 应 pass 但 lint 误报退出 $?"
  cat "$TMP_DIR/out-ascii.txt" >&2
fi

report_results "prd-hierarchy-lint"
exit $((FAIL_COUNT > 0 ? 1 : 0))
