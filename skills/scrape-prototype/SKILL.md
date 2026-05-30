---
name: pmai-scrape-prototype
description: |
  §7.A 站点爬原型：把一个目标站（每页每弹窗）走一遍当参考，在主原型 prototype/ 栈内
  重建近似。用于「从现有站起原型」/「照某站补几页」。不是无损拷贝（跨栈重建必然近似，
  同「只看不导」纪律）。引擎 = gstack /browse（+ /scrape 抓数据）+ §7.C checks-diff 验重建。
  按需 skill（PM 手动调 / new-req 范围确认里 AI 判断该爬时建议）。
---

# /pmai-scrape-prototype —— 站点爬原型（§7.A）

> **PM 视图**：入口 banner（`status-view.py --banner-only --skill SCRAPE-PROTOTYPE`，无 active req 用字面值）；爬完计划 + 重建范围出确认门（PM 批了才在 prototype/ 建）；产物只给路径 + 一句话。
> **PM 答题规则**：AskUserQuestion 按 `_shared/pm-view/askuser-rules.md`（空答 STOP）。

## 定位

PM 想**照一个现有站起原型 / 补几页**时用：gstack `/browse` 把目标站每页每弹窗走一遍（截图 + 结构），AI 在 `prototype/` 栈内**重建近似**，再用 checks-diff 验重建覆盖了没。

- **不是无损拷贝**：目标站是它那套栈，主原型是 Next.js + TS + Tailwind + shadcn —— 跨栈"录入"= 重写一遍 = 引入残版 + 视觉失真。所以**只看不导**：拿截图 / 结构当参考，代码在栈内重建（同 Claude Design「只看不导」纪律）。
- 落地照 `docs/DESIGN.md` + `工程结构约束-*.md`（mock / 真按层）；视觉照 DESIGN。
- 与 §7.B 对齐线上的区别：§7.B 是**已有原型对齐到线上**（改存量）；§7.A 是**从站点起 / 补原型**（建增量）。两者共用 §7.C checks-spec 引擎（参照都是爬出来的站）。

## 输入

1. 目标站 URL（要爬的站 / 页）。
2. 登录后页面 → 见步骤 1 cookie。

## Workflow

### 步骤 0：banner + @读脊柱

入口 echo banner。**先读脊柱**（`docs/PRODUCT-STATE.md` → `prototype/` 现状 / `docs/DESIGN.md` / `工程结构约束-*.md`）——知道主原型现在有什么、按哪档建，重建才落在同一条主原型线上、不另起风格。

### 步骤 1：爬站 → 派生 checks-spec + 截图（产出，不改代码）

1. **登录态**（如目标站要登录）：Skill tool 调 gstack `/setup-browser-cookies` 导 cookie（⚠️ macOS Keychain 弹窗）。
2. gstack `/browse` 逐页 / 逐弹窗走目标站（**细到每个弹窗、每个 tab、每个状态**），抓 `url/title/textPreview/buttons[{text,disabled}]` + 截图，存 `.pm-workflow/scrape/<module>/`。数据要填进 mock 让 demo 更真 → 可选 gstack `/scrape` 抓真实内容。
3. AI 据此**派生 checks-spec**（`skills/_shared/checks-spec.md` 格式：每页 / 弹窗一个 check，must_have_text / must_check_buttons[disabled] / must_cover_states / reference_path），落 `.pm-workflow/scrape/<module>/checks.json`。**不让 PM 手写 JSON。**

**确认门**：把「爬到哪些页 / 弹窗 + 打算重建哪些」给 PM（PM 视图清单），AskUserQuestion 让 PM 圈定重建范围 + 拍结构决策（菜单归类 / 页面切分等当场问）。**批了才进步骤 2。**

### 步骤 2：在 prototype/ 栈内重建（PM 批后）

1. AI 照截图 + checks-spec 在 `prototype/` 里重建近似页面（Next.js 栈、视觉照 DESIGN、复用已有 `components/ui` 不重写同功能组件）。改动落隔离副本、单窗口 git -C，不 cd 会话。
2. 重建是 build —— 走正常 build 纪律（强制读 DESIGN、可派给 PM 指定的独立执行器）。

### 步骤 3：验重建（checks-diff，参照=爬出来的站）

1. 起 prototype dev server，逐 check 抓 `local/<check_id>.json`；爬出来的结构当 `reference/`。
2. 跑引擎：
   ```bash
   python3 "$PMAI_HOME/scripts/checks-diff.py" \
     --plan .pm-workflow/scrape/<module>/checks.json \
     --artifacts .pm-workflow/scrape/<module>/artifacts \
     --report .pm-workflow/scrape/<module>/report.md --todo .pm-workflow/scrape/<module>/patch_todo.md
   ```
3. AI 按 P0/P1 补齐重建（漏的页 / 文案 / 按钮），P2 视觉照 DESIGN。

### 步骤 4：呈交 PM

report.md（重建覆盖率：建了 / 丢了 / 降级占位）+ demo 给 PM 看（只给路径 + 一句话），PM 拍板重建到位 / 还要补。**PM 决策点，不自动判完成。**

## Rules

- **只看不导**：截图 / 结构当参考，代码栈内重建，不跨栈录入
- 确认门没批前不在 `prototype/` 建（同 align-to-live 红线）；checks 由 AI 派生不让 PM 写 JSON
- 单窗口：dev server / browse / 重建 显式带目录，不 cd 会话、不切窗口
- 重建是 build：强制读 DESIGN、复用已有组件、可派独立执行器
- 全走 `/browse`（headless），禁 `mcp__claude-in-chrome__*`；抓真实数据填 mock 用 `/scrape`
