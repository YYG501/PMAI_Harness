---
name: _shared/term-detector
description: |
  业务词 / 角色发现检测器（共享逻辑）。由 landed 后自动文档编译调用，识别本次工作真实落地的新业务词 / 角色，
  patch 进 PRODUCT 业务术语表 / 用户画像。
---

# _shared/term-detector

> **共享 detector**。不是 user-facing skill，而是写作 skill 的共享逻辑落点。
>
> **设计**：业务实体真正稳定要等 design/pmai-build/复审完成后再沉淀；PRD 写作阶段不直接 patch 长期术语表。本次工作内的临时词典职责由模块 `discussion.md` / `decisions.md` 或 PRD §三名词解释承担。

## 何时调用

| 调用 skill | 调用位置 | 输入文件 |
|---|---|---|
| 自动 finalize（兼容 `/pmai-build-close` 恢复） | landed 后术语回写 | context pack + accepted deltas + 涉及模块 `discussion.md` / `decisions.md` / `spec.md` + 按需功能型规格文档 |

**禁止位置**：
- `design` 刚开始：PM 修辞密度高、业务词还没沉淀
- `/pmai-design` 探索中：业务词还在变
- `spec-writing` 写功能型规格文档：功能型规格文档是评审 / build 产物，不直接升级长期术语
- 写实现深水区 / 技术约束内容：工程层允许技术词，误报率高

## 临时词典 vs 长期词典

| 层级 | 文件 | 谁写 | 谁读 |
|---|---|---|---|
| **本次工作临时词典** | 模块 `discussion.md` / `decisions.md` 或功能型规格文档 §三 名词解释 | design / spec-writing | build / finalize 按需读 |
| **跨工作长期词典** | `PRODUCT.md ## 业务术语表` | landed 后 detector 按 decision policy → patch | design / build / spec-writing 必读 |

两份词典在 build 阶段是**并集读**：PRODUCT 是已沉淀的稳定基线，模块 discussion/decisions 或 PRD §三是本次新引入还未升级的临时词。实现落入 main 后，detector 把真稳定下来的词提升到长期词典；兼容恢复入口复用同一逻辑。

普通术语定义属于可逆表达：AI 给推荐并推进，在自然收口点汇总。新角色、新对象或一个定义会改变产品模型时，才立即让 PM 拍板。不得把每个 detector finding 都变成 PM 问题。

## 如何调用

```bash
# 把即将写的内容存临时文件
TMPFILE=$(mktemp)
# ...写内容到 $TMPFILE...

RESULT=$(python3 "$PMAI_HOME/scripts/_lib/term-detector.py" \
  "$TMPFILE" "$REPO_ROOT" \
  --work-dir "$ACTIVE_WORK_DIR")

rm "$TMPFILE"
echo "$RESULT"
```

返回 JSON：
```json
{
  "new_terms": ["探测档延迟项"],
  "new_roles": ["平台审核员"],
  "skipped": ["售后单"],      // 本次工作已被 PM 拒绝（.term-skip.json）
  "whitelisted": ["用户"],    // 通用词，silent
  "registered": ["商品池"]    // PRODUCT 已有
}
```

## 话术模板（PM 视图，禁工程黑话）

### 单业务词（<3 新词时）

> 📖 你说的「<term>」AI 不在术语表里，给我一句话定义我加一条？（≤30 字）
> 不想加 → 说「跳过」（本次工作不再问这个词）

### 多业务词批量（≥3 新词时，autoplan DX F3 共识）

> 📖 发现 <N> 个新业务词：「<t1>」/「<t2>」/「<t3>」...。一次性处理：
> - 全加：每个给我一句话定义
> - 挑几个：说「加 <ti>」「跳过 <tj>」
> - 全跳过：本次工作不再问这些词

### 新角色

> 📖 内容里出现「<role>」这个新角色，画像表还没收录。要不要加？
> 建议：描述 = "..."，关键诉求 = "..."。你改/确认/跳过。

## SKIP 列表存储

PM 答「跳过 / 忽略 / 不重要」→ 写入：

```bash
SKIP_FILE="$ACTIVE_WORK_DIR/.term-skip.json"
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

**生命周期**：随当前工作；自动 finalize 完成或 `/pmai-build-cancel` 后清空（不持久跨工作）。

## 决策依据

- 锁定：不给全局 toggle（与 MEMORY 第 2「不留 FORCE」一致）

## 不另起新 skill

本 detector 是**内部共享逻辑**（`_shared/`），不出现在 PM 的 user-facing
skill 列表里。PM 看到的是业务流程里的产出 + 业务词提示。
