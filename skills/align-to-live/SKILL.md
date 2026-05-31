---
name: pmai-align-to-live
description: |
  §7.B 对齐线上：把主原型 prototype/ 对齐到「线上真实产品」——第四条 diff 轴
  （覆盖审计 vs 范围清单 / 视觉门 vs DESIGN / 行为审 vs 验收 / 对齐线上 vs 线上真实产品）。
  brownfield 关键：原型先对齐现实、再在上面设计改动。按需 skill（PM 手动调 / new-req 范围确认
  里 AI 判断该对齐时建议）。吸收自 PM 雏形 prototype-live-align：两阶段 Plan→PM 批→Execute。
---

# /pmai-align-to-live —— 对齐线上（§7.B）

> **PM 视图**：入口 banner（`status-view.py --banner-only --skill ALIGN-TO-LIVE`，无 active req 时用字面值）；Plan 阶段出确认门（PM 批了才改原型）；产物只给路径 + 一句话，按 `_shared/PM-VIEW-RULES.md`。
> **PM 答题规则**：AskUserQuestion 按 `_shared/pm-view/askuser-rules.md`（空答 STOP，不默认走通过）。

## 定位

主原型 `prototype/` 要长得 / 行为像**线上真实产品**时用。把线上当参照物，逐页 / 逐弹窗对比文案 / 按钮 / 禁用态 / 状态覆盖，出 P0/P1/P2 差异报告，AI 按报告改原型、PM 拍板。

- 不是无损拷贝（跨栈重建必然近似）；线上是**参照**，落地仍在 `prototype/` 栈内（Next.js + TS + Tailwind + shadcn，照 `docs/DESIGN.md` + `工程结构约束-*.md`）。
- 引擎 = `scripts/checks-diff.py`（§7.C），checks-spec 格式见 `skills/_shared/checks-spec.md`。
- 区别于覆盖审计（参照=范围清单）/ 视觉门（参照=DESIGN）/ 行为审（参照=验收流程）：本 skill 参照 = **线上真实产品**。

## 红线（吸收自 prototype-live-align）

**Plan 阶段 PM 没批之前，绝对禁止改 `prototype/` 任何代码。** 每个 Execute 核心步骤完成回报「进展 / 验证 / 下一步」。

## 输入

1. 线上对齐入口 URL（线上路由；登录后页面见下「登录态」）。
2. 要对齐的本地路由（prototype 路由；不给则 AI 从 prototype/ 路由结构推 + 跟 PM 确认范围）。

## Workflow

### 步骤 0：banner + @读项目底座

入口 echo banner。**先读项目底座**（`docs/PRODUCT-STATE.md` → `prototype/` 现状 / `docs/DESIGN.md` / `工程结构约束-*.md`），知道原型现在长什么样、哪层 mock / 真，才能判「线上有而原型缺」是 delta 还是本就不做。

### 步骤 1：Plan —— 爬线上派生 checks-spec（产出，不改代码）

1. **登录态**：线上多为登录后页面 → 先用 Skill tool 调 gstack `/setup-browser-cookies` 导真 cookie（⚠️ macOS Keychain 弹窗、PM 手动选域），让后续 `/browse` 带登录态。
2. 用 gstack `/browse` 逐页 / 逐弹窗走线上（L1/L2/L3 + modal），抓 `url/title/textPreview/buttons[{text,disabled}]` + 截图。
3. AI 据此**派生 checks-spec**（`skills/_shared/checks-spec.md` 格式：每 check 的 must_have_text / must_check_buttons[disabled] / must_cover_states / reference_path / local_path），落 `.pm-workflow/align/<module>/checks.json`。**checks 由 AI 派生、不让 PM 手写 JSON。**
4. **结构决策类**（哪些页要对齐 / 范围边界）当场逐条问 PM 拍（`_shared/pm-view/banner-rules.md` 结构决策前置）。

**Plan 确认门**：把 checks-spec 计划表（PM 视图：要对齐哪些页 / 各页关键文案·按钮·状态）给 PM，AskUserQuestion 让 PM 批 / 改。**批了才进步骤 2。**

### 步骤 2：Execute —— 抓两边 → diff → 改原型（PM 批后）

1. 起 / 复用 prototype dev server（在隔离副本里、显式带目录，单窗口不 cd 会话）。
2. 逐 check 用 `/browse` 抓两份：`reference/<check_id>.json`（线上）+ `local/<check_id>.json`（prototype），放 `.pm-workflow/align/<module>/artifacts/`。
3. 跑引擎：
   ```bash
   python3 "$PMAI_HOME/scripts/checks-diff.py" \
     --plan .pm-workflow/align/<module>/checks.json \
     --artifacts .pm-workflow/align/<module>/artifacts \
     --report .pm-workflow/align/<module>/report.md \
     --todo   .pm-workflow/align/<module>/patch_todo.md
   ```
4. AI 按 patch_todo 改 `prototype/`（P0 先 / 再 P1 / P2 视觉细则照 DESIGN）。视觉细则（sticky / 横滚 / 禁 native alert·confirm 用包装组件 / 留白密度 / 四态）照 `docs/DESIGN.md` + `工程结构约束-*.md`，不在引擎里硬判。
5. 重抓 local → 重跑 diff 直到 P0 清零（或 PM 接受残留）。每完成一个核心步骤回报「进展 / 验证 / 下一步」。

### 步骤 3：呈交 PM

把最终 report.md（P0/P1/P2 统计）+ 改了哪些页给 PM 看（只给路径 + 一句话），PM 拍板对齐到位 / 还要改。**这是 PM 决策点，不自动判定对齐完成。**

## Rules

- Plan 没批前不改 `prototype/`（红线）；checks 由 AI 派生不让 PM 写 JSON
- 单窗口：dev server / browse 显式带目录，不 cd 会话、不切窗口
- 引擎只查结构 / 文案 / 按钮态；视觉归 DESIGN + `/design-review`，状态覆盖演示归行为审 `/browse`
- 线上登录后页面才用 `/setup-browser-cookies`（无人值守会被 Keychain 弹窗打断，仅必要时）
- 全走 `/browse`（headless），禁 `mcp__claude-in-chrome__*`
