---
name: pmai-req-stage-gate
description: |
  异常恢复入口（薄壳）：需求推进的主驱动已搬到 /pmai-next。本 skill 只在窗口被关 / 流程卡住 / 状态不一致时兜底，重新把当前该做的那一步拉起来。
---

# /pmai-req-stage-gate

> **本 skill 已不是主推进引擎。** 需求从「范围确认 → build → 复审 → 沉淀」的推进，统一走 `/pmai-next`：它先读 PRODUCT-STATE.md + 当前需求状态，告诉你「现在要做 X / 要你确认 Y」，再动手。本 skill 现在只是**异常恢复入口**——当 `/pmai-next` 因为窗口被关、状态错乱、worktree 残留等原因卡住时，PM 手动敲它把局面理清、把当前该做的那一步重新拉起来。
>
> **PM 视图**：banner / 确认门 / 退出话术按 `_shared/pm-view/banner-rules.md` + `_shared/pm-view/askuser-rules.md`，禁用模糊词 "OK" / "Proceed" / "Continue"，禁工程黑话。

## When To Use

只在下面这几种**异常**情况手动调；正常推进一律走 `/pmai-next`：

- `/pmai-next` 报当前状态读不出来 / 跟磁盘对不上
- 上一个窗口在确认门没答就关了，回来想重新看到那个确认门
- worktree 有残留 / 冲突，推进被挡住，想先理清现场再继续
- 不确定现在做到哪一步，想要一次「现状 + 下一步」的复位

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: req-stage-gate"

# 视觉锚点（见 _shared/pm-view/banner-rules.md）
python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill REQ-STAGE-GATE || true

# worktree 残留检测（informational，不阻塞；有问题仅打印警告供 PM 处理）
python3 "$PMAI_HOME/scripts/check-worktree-residue.py" || true
```

如果 worktree 残留检测报警，先把警告原文一句话转给 PM（"发现 N 个 worktree 残留 / 冲突，已贴上方"），PM 可选择立刻清理或继续。本 skill 不当 gate。

## 做什么

1. **读当前需求状态**：通过 `_lib.state.get_overall_state()` 拿到当前 active req、当前阶段（范围确认 / build / 复审 / 沉淀）、最近一次状态变更、当前 task 情况。

2. **复位播报**：用 PM 听得懂的话讲清「你现在在哪、上一步做完了什么、下一步该做什么」。**不编造**——读不到 active req 就直说没有，让 PM 起新需求。

3. **把控制权交回 `/pmai-next`**：理清现场后，统一提示 PM 敲 `/pmai-next` 继续推进。本 skill 不自己跑范围确认 / build / 复审 / 沉淀的任何一步——那些都是 `/pmai-next` 的职责。

### 无 active req 兜底

```
目前没有 active req。
可以发 /pmai-new-req 起新需求，或发 /pmai-init-project 起新项目。
```

### 有 active req 时的复位话术

```
当前需求：req-NNN <一句话>
现在在：<范围确认 / build / 复审 / 沉淀> 阶段
上一步：<最近一次状态变更，一句话>

下一步：发 /pmai-next 继续推进。
```

## 异常恢复场景

### 卡在确认门 / 窗口被关后回来

PM 在 `/pmai-next` 的某个确认门没答就关了窗口，回来重敲本 skill → AI 读当前状态，把「上次停在哪个确认要你拍」讲清楚，然后提示发 `/pmai-next`——`/pmai-next` 会从当前位置把同一个确认门重新拉起来。本 skill 不复制 `/pmai-next` 的确认门文案，只负责复位。

### worktree 残留 / 冲突

Preamble 的 `check-worktree-residue.py` 报警时，把警告原文转给 PM，按 PM 选择处理（立刻清理 / 先继续）。清理干净后提示发 `/pmai-next` 继续。

### task 关闭后续走

一个需求的 task 都做完、PM 验收过后，正常情况下 `/pmai-close-task` 会直接把沉淀（更新 PRODUCT-STATE、merge 主原型回 main）这一步拉起来。如果那一步因为窗口被关没接上，PM 回来敲本 skill → AI 复位后提示发 `/pmai-next`，由它把沉淀阶段重新拉起来。

## 已搬走的能力（指针）

下面这些原来在本 skill 里编排的逻辑，**已并入 `/pmai-next`**，本 skill 不再承担：

| 原能力 | 现在归属 |
|---|---|
| 范围确认（读 PRODUCT-STATE + 跑主原型 + 三条上坡路 → req-plan.md） | `/pmai-new-req` 起、`/pmai-next` 推进 |
| build 推进（在 prototype/ 栈内建，强制读 DESIGN.md） | `/pmai-next` |
| 结构决策前置（命中结构决策当场逐行问 PM 拍板，不事后追认） | `/pmai-next`（保留同款「先说要你确认 Y 再动」护栏） |
| build 完三道复审（覆盖审计 / 视觉门 / 行为审） | `/pmai-next` |
| 体验迭代 + 沉淀闸门 | `/pmai-next` |
| worktree 残留检测 | 本 skill 保留（异常恢复时用）+ `/pmai-next` 入口同款 |
| 按需反向 PRD | `/pmai-prd-writing`（standalone） |

## Rules

- **本 skill 不是推进引擎**：不自己跑范围确认 / build / 复审 / 沉淀任何一步，只复位现状 + 把控制权交回 `/pmai-next`。
- **不编造状态**：读不到 active req 就直说没有（防 narrative 幻觉），不假装有进度。
- **复位话术只给路径 + 一句话**：PM 的 IDE 已经挂在 worktree 上，不贴文档全文。
- **PM chat 输出禁工程黑话**：不出现 `hash` / `lint` / 脚本名 / 内部编号 等内部记账词；用 PM 听得懂的话讲现状和下一步。
- **worktree 残留检测只报不挡**：informational，不当 gate。
