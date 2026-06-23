---
name: pmai-status
description: |
  轻量现状视图：当前产品长什么样、在做哪个模块、最近的重要决策。只读、不改状态。开新窗口或想知道"我在哪 / 上次做到哪"时用。
---

# /pmai-status

> 轻量现状视图。复用 `status-view.py`，**只读、不改任何状态**。

## When To Use

- PM 想看：当前产品现状 / 在做哪个模块 / 最近的重要决策。
- 开新窗口、隔天回来，想一眼知道"我在哪、上次做到哪、下一步建议"。
- 不适用：要推进工作 → `/design`。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: status"
```

## Workflow

1. 跑现状播报（结构化，基于现有字段、不编造）：

   ```bash
   python3 "$PMAI_HOME/scripts/status-view.py" --narrative 2>/dev/null || true
   ```

2. @读 `docs/PRODUCT-STATE.md`（现状）+ `docs/PRODUCT-RULES.md`（跨模块规则与最近重要决策），并扫各 `docs/modules/<模块>/.req-meta`（哪个模块在做、做到哪一步），用 PM 视图大白话报一段：

   - **当前产品**：一句话现状。
   - **在做的模块**：哪个模块、在 `/design` / `/build` / 待 `/close` 哪一步。
   - **最近重要决策**：1–3 条（从 PRODUCT-RULES）。
   - **建议下一步**：一句。

3. **纯只读**：不写、不改任何文件或状态。无数据时直说"目前没有在做的模块，可发 `/design` 起新工作"，不编造。

## Rules

- 只读视图，绝不写文件 / 改状态（区别于会改状态的 `/design` / `/build` / `/close`）。
- PM 话术不出内部词（`.req-meta` / 真相源 / 派生 等不直接念给 PM）。
