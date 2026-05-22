---
name: _shared/term-detector
description: |
  业务词 / 角色发现检测器（vp-4b 共享逻辑）。被 new-req / req-analysis /
  prd-writing / task-spec 各 skill 在写 PM 视图主文件时调用，识别未登记的
  业务词 / 角色让 AI 提示 PM 补 CONTEXT 业务术语表 / 用户画像。
---

# _shared/term-detector

> **vp-4b 共享 detector**。不是 user-facing skill，而是 4 个写作 skill 的共
> 享逻辑落点。被各 skill 在写 brief / analysis / prd / task spec PM
> 视图主文件**前 / 中**调用。

## 何时调用

| 调用 skill | 调用位置 | 输入文件 |
|---|---|---|
| `new-req` | 步骤 4 写 brief 草稿前 / 中 | 即将写的 brief.md 内容 |
| `req-analysis` | 写 analysis.md 时 | 即将写的 analysis.md 内容 |
| `prd-writing` | 写 prd.md 时 | 即将写的 prd.md 内容 |
| `task-spec` | 写 task PM 视图主文件时（**仅 .md，不扫 .engineering.md**）| 即将写的 task-NNN-*.md 内容 |

**禁止位置**：
- 写工程合同（`.engineering.md`）时不调用（工程层允许技术词，误报率高）
- close-task / close-req 时不调用（产出已稳定，不再催新词）

## 如何调用

```bash
# 把即将写的内容存临时文件
TMPFILE=$(mktemp)
# ...写内容到 $TMPFILE...

RESULT=$(python3 "$REPO_ROOT/.claude/scripts/_lib/term-detector.py" \
  "$TMPFILE" "$REPO_ROOT" \
  --req-dir "$ACTIVE_REQ_DIR")

rm "$TMPFILE"
echo "$RESULT"
```

返回 JSON：
```json
{
  "new_terms": ["探测档延迟项"],
  "new_roles": ["平台审核员"],
  "skipped": ["售后单"],      // 本 req 已被 PM 拒绝（.term-skip.json）
  "whitelisted": ["用户"],    // 通用词，silent
  "registered": ["商品池"]    // CONTEXT 已有
}
```

## 话术模板（PM 视图，禁工程黑话）

### 单业务词（<3 新词时）

> 📖 你说的「<term>」AI 不在术语表里，给我一句话定义我加一条？（≤30 字）
> 不想加 → 说「跳过」（本 req 不再问这个词）

### 多业务词批量（≥3 新词时，autoplan DX F3 共识）

> 📖 发现 <N> 个新业务词：「<t1>」/「<t2>」/「<t3>」...。一次性处理：
> - 全加：每个给我一句话定义
> - 挑几个：说「加 <ti>」「跳过 <tj>」
> - 全跳过：本 req 不再问这些词

### 新角色

> 📖 内容里出现「<role>」这个新角色，画像表还没收录。要不要加？
> 建议：描述 = "..."，关键诉求 = "..."。你改/确认/跳过。

## SKIP 列表存储

PM 答「跳过 / 忽略 / 不重要」→ 写入：

```bash
SKIP_FILE="$ACTIVE_REQ_DIR/.term-skip.json"
# 初始化（如不存在）
[ ! -f "$SKIP_FILE" ] && echo '{"skipped_terms": [], "skipped_roles": []}' > "$SKIP_FILE"

# 追加（用 python -c 或 jq）
python3 -c "
import json
with open('$SKIP_FILE') as f: data = json.load(f)
data['skipped_terms'].append('<term>')  # 或 skipped_roles
with open('$SKIP_FILE', 'w') as f: json.dump(data, f, ensure_ascii=False, indent=2)
"
```

**生命周期**：随 req worktree；close-req / cancel-req 后清空（不持久跨 req）。

## 决策依据

- v5 `docs/设计/PRD-体系收敛.md` §2.7
- D4 锁定：不给全局 toggle（与 MEMORY 第 2「不留 FORCE」一致）
- autoplan T4/T12/T22/T24 共识

## 不另起新 skill

本 detector 是**内部共享逻辑**（`_shared/`），不出现在 PM 的 user-facing
skill 列表里。PM 看到的是 4 个写作 skill 各自的产出 + 业务词提示。
