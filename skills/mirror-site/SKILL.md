---
name: pmai-mirror-site
description: |
  对照参考站点对齐原型：逐页逐弹窗走查目标站点作为参照，在主原型中对齐。支持两种模式——依外部站点重建或补充页面、将既有原型对齐至线上真实产品。非无损复制（跨技术栈重建为近似实现）。不参照任何站点的纯新建请使用 /pmai-design 与 /pmai-build。
  触发词：照某站起原型 / 照它补几页 / 爬站重建 / 原型对齐线上。
---

# /pmai-mirror-site —— 照参考站对齐原型（§7.A/B 合并）

## 入口护栏

执行本 skill 前先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止本 skill，只引导 PM 先发 `/pmai-init-project`。初始化或已有代码接入完成前，不要读取/改写 `prototype/`、`mockups/` 或 mirror 审计产物。

> **PM 视图**：入口 banner（`status-view.py --banner-only --skill MIRROR-SITE`，无 active work 时用字面值）；Plan 阶段出确认门（PM 批了才动 `prototype/`）；产物只给路径 + 一句话，按 `_shared/PM-VIEW-RULES.md`。
> **PM 答题规则**：AskUserQuestion 按 `_shared/pm-view/askuser-rules.md`（空答 STOP，不默认走通过）。

## 定位

主原型 `prototype/` 要参照**某个站**长成 / 对齐成那样时用。把参照站当参照物，逐页 / 逐弹窗对比文案 / 按钮 / 禁用态 / 状态覆盖，出 P0/P1/P2 报告，AI 据此在栈内建 / 改、PM 拍板。**两种模式只差一个轴：参照来源 + 建增量 / 改存量。**

| | **mode=rebuild 照站重建（原 §7.A）** | **mode=align 对齐线上（原 §7.B）** |
|---|---|---|
| 参照来源 | 外部目标站（别人的站） | 自己的线上真实产品 |
| 动作 | 在 `prototype/` 栈内**重建近似**（建增量） | 把**已有原型**对齐到参照（改存量） |
| 场景 | 从现有站起原型 / 照某站补几页 | 原型先贴线上现实、再在上面设计改动（brownfield 关键） |

共同点（为什么是一个 skill）：

- **不是无损拷贝**：参照站是它那套栈，主原型是 Next.js + TS + Tailwind + shadcn —— 跨栈"录入"= 重写一遍 = 引入残版 + 视觉失真。所以**只看不导**：拿截图 / 结构当参考，代码在栈内建 / 改（同 Claude Design「只看不导」纪律）。
- 落地照 `DESIGN.md` + `工程结构约束-*.md`（mock / 真按层）；视觉照 DESIGN。
- 引擎 = `scripts/checks-diff.py`（§7.C），checks-spec 格式见 `skills/_shared/checks-spec.md`。
- 区别于覆盖审计（参照=范围清单）/ 视觉门（参照=DESIGN）/ 行为审（参照=验收流程）：本 skill 参照 = **参考站点 / 线上真实产品**（第四条 diff 轴）。

## 模式判断（入口先定）

- PM 给的是**外部站 URL + 该页原型还没有**（要从零照它建 / 补）→ `mode=rebuild`。
- PM 给的是**自己线上 URL + 原型已有对应页**（要让原型贴现实）→ `mode=align`。
- 拿不准 → AskUserQuestion 当场问 PM 是「照外部站重建」还是「对齐自己线上」。

## 红线（吸收自 prototype-live-align）

**Plan 阶段 PM 没批之前，绝对禁止改 / 建 `prototype/` 任何代码。** 每个 Execute 核心步骤完成回报「进展 / 验证 / 下一步」。

## 输入

1. 参照站入口 URL（rebuild=外部目标站；align=线上路由）。登录后页面见步骤 1 cookie。
2. 对应的本地路由（align 模式必给 / 不给则 AI 从 `prototype/` 路由结构推 + 跟 PM 确认范围；rebuild 模式新建则按参照站结构落点）。

## Workflow

### 步骤 0：banner + @读项目底座

入口 echo banner。**先读项目底座**（`PRODUCT-STATE.md` → `prototype/` 现状 / `DESIGN.md` / `工程结构约束-*.md`），知道原型现在有什么、按哪档建，才能判「参照站有而原型缺」是 delta 还是本就不做，且重建 / 对齐都落在同一条主原型线上、不另起风格。

### 步骤 1：Plan —— 爬参照站派生 checks-spec（产出，不改代码）

本步骤按 `skills/_shared/gstack-integration.md` 调用 gstack：`/setup-browser-cookies`、`/browse`、`/scrape` 只是抓取能力，长期记录落 `.pm-workflow/mirror/` 和 checks-diff 报告。

1. **登录态**（参照站需登录时）：用 Skill tool 调 gstack `/setup-browser-cookies` 导真 cookie（⚠️ macOS Keychain 弹窗、PM 手动选域，仅必要时），让后续 `/browse` 带登录态。
2. 用 gstack `/browse` 逐页 / 逐弹窗走参照站（**细到每个弹窗、每个 tab、每个状态**；L1/L2/L3 + modal），抓 `url/title/textPreview/buttons[{text,disabled}]` + 截图。rebuild 模式数据要填进 mock 让 demo 更真 → 可选 gstack `/scrape` 抓真实内容。
3. AI 据此**派生 checks-spec**（`skills/_shared/checks-spec.md` 格式：每页 / 弹窗一个 check，must_have_text / must_check_buttons[disabled] / must_cover_states / reference_path / local_path），落 `.pm-workflow/mirror/<module>/checks.json`。**checks 由 AI 派生、不让 PM 手写 JSON。**
4. **结构决策类**（要建 / 对齐哪些页 / 范围边界 / 菜单归类 / 页面切分）当场逐条问 PM 拍（`_shared/pm-view/banner-rules.md` 结构决策前置）。

**Plan 确认门**：把 checks-spec 计划表（PM 视图：要建 / 对齐哪些页 + 各页关键文案·按钮·状态）给 PM，AskUserQuestion 让 PM 圈定范围 / 批 / 改。**批了才进步骤 2。**

### 步骤 2：Execute —— 按模式建 / 改（PM 批后）

1. 起 / 复用 prototype dev server（在隔离副本里、显式带目录，单窗口不 cd 会话）。
2. **mode=rebuild**：AI 照截图 + checks-spec 在 `prototype/` 里**重建近似页面**（Next.js 栈、视觉照 DESIGN、复用已有 `components/ui` 不重写同功能组件）。重建是 build —— 走正常 build 纪律（强制读 DESIGN、可派给 PM 指定的独立执行器）。
   **mode=align**：逐 check 用 `/browse` 抓两份 `reference/<check_id>.json`（线上）+ `local/<check_id>.json`（prototype）放 `.pm-workflow/mirror/<module>/artifacts/`，跑引擎出 patch_todo，AI 按 patch_todo **改 `prototype/`**（P0 先 / 再 P1 / P2 视觉照 DESIGN）。

### 步骤 3：验（checks-diff）

```bash
python3 "$PMAI_HOME/scripts/checks-diff.py" \
  --plan .pm-workflow/mirror/<module>/checks.json \
  --artifacts .pm-workflow/mirror/<module>/artifacts \
  --report .pm-workflow/mirror/<module>/report.md \
  --todo   .pm-workflow/mirror/<module>/patch_todo.md
```

- rebuild：起 dev server 抓 `local/<check_id>.json`，爬出来的结构当 `reference/`，按 P0/P1 补齐重建（漏的页 / 文案 / 按钮），P2 视觉照 DESIGN。
- align：重抓 local → 重跑 diff 直到 P0 清零（或 PM 接受残留）。
- 视觉细则（sticky / 横滚 / 禁 native alert·confirm 用包装组件 / 留白密度 / 四态）照 `DESIGN.md` + `工程结构约束-*.md`，不在引擎里硬判。每完成一个核心步骤回报「进展 / 验证 / 下一步」。

### 步骤 4：呈交 PM

把最终 report.md（rebuild=重建覆盖率「建了 / 丢了 / 降级占位」；align=P0/P1/P2 统计）+ 建 / 改了哪些页给 PM 看（只给路径 + 一句话），PM 拍板到位 / 还要补。**这是 PM 决策点，不自动判定完成。**

## Rules

- **只看不导**：截图 / 结构当参考，代码栈内建 / 改，不跨栈录入
- Plan 没批前不动 `prototype/`（红线）；checks 由 AI 派生不让 PM 写 JSON
- 单窗口：dev server / browse / 建改 显式带目录，不 cd 会话、不切窗口
- 引擎只查结构 / 文案 / 按钮态；视觉归 DESIGN + `/design-review`，状态覆盖演示归行为审 `/browse`
- rebuild 重建是 build：强制读 DESIGN、复用已有组件、可派独立执行器；抓真实数据填 mock 用 `/scrape`
- 参照站登录后页面才用 `/setup-browser-cookies`（无人值守会被 Keychain 弹窗打断，仅必要时）
- 全走 `/browse`（headless），禁 `mcp__claude-in-chrome__*`
