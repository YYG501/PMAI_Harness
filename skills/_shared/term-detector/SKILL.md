---
name: _shared/term-detector
description: |
  业务词 / 角色发现检测器（共享逻辑）。**当前只在 `close-req` Phase 1
  调用一次**，识别本 req 真实落地的新业务词 / 角色，
  patch 进 PROJECT 业务术语表 / 用户画像。
---

# _shared/term-detector

> ** 共享 detector**。不是 user-facing skill，而是写作 skill 的共
> 享逻辑落点。
>
> **设计**：从早期 brief / analysis / prd 三处调用收敛到 close-req 一处 —— 业务实体真正稳定要等 task 都执行完、PRD 已 as-built 反向对齐；PRD 阶段就 patch 长期术语表偏早。本 req 范围内的临时词典职责由 `prd.md §三 名词解释` 承担（被 `implementation-design` 和 `task-spec` 显式 Required Inputs 当词典必读）。

## 何时调用

| 调用 skill | 调用位置 | 输入文件 |
|---|---|---|
| `close-req` | Phase 1 步骤 3.4（req 推进到 stage 7 之后、里程碑追加询问之前） | `prd.md` + 全部 `tasks/closed/*.md`（不扫 `.engineering.md`） |

**禁止位置**：
- `new-req` 写 brief（已退场）：PM 修辞密度高、业务词还没沉淀
- `req-analysis` / `req-stage-gate` B 分支写 analysis / stage2-office-hours（已退场）：业务词还在变
- `prd-writing` 写 prd.md（已退场）：业务实体未经 task 落地验证；本 req 临时词典职责改由 `prd.md §三 名词解释` 承担
- 写工程合同（`.engineering.md`）：工程层允许技术词，误报率高
- close-task：单 task 收尾不催，统一推迟到 close-req

## 临时词典 vs 长期词典

| 层级 | 文件 | 谁写 | 谁读 |
|---|---|---|---|
| **本 req 临时词典** | `prd.md §三 名词解释` | `prd-writing` 写 PRD 时 AI 直接写 | `implementation-design` / `task-spec` 必读 |
| **跨 req 长期词典** | `docs/PROJECT.md ## 业务术语表` | `close-req` 步骤 3.4 detector + PM 确认 → patch | `implementation-design` / `task-spec` 必读 |

两份词典在 stage 5 是**并集读**：PROJECT 是已沉淀的稳定基线，PRD §三 是本 req 新引入还未升级的临时词。close-req 时 detector 把本 req 真稳定下来的词从临时词典 promote 到长期词典。

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
  "registered": ["商品池"]    // PROJECT 已有
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

- 锁定：不给全局 toggle（与 MEMORY 第 2「不留 FORCE」一致）

## 不另起新 skill

本 detector 是**内部共享逻辑**（`_shared/`），不出现在 PM 的 user-facing
skill 列表里。PM 看到的是 4 个写作 skill 各自的产出 + 业务词提示。
