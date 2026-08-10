---
name: pmai-status
description: |
  轻量现状视图：展示当前产品形态、进行中的模块与近期关键决策。只读，不改变状态。适用于开启新窗口或回顾当前进度时。
---

# /pmai-status

## 入口护栏

执行本 skill 前先运行：

```bash
PMAI_PREAMBLE_READ_ONLY=1
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
unset PMAI_PREAMBLE_READ_ONLY
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，本 skill 只报告未初始化并引导 PM 先发 `/pmai-init-project`，不要继续读取不存在的 PMAI 项目文档。

> 轻量现状视图。复用 `status-view.py`，**只读、不改任何状态**。

## When To Use

- PM 想看：当前产品现状 / 在做哪个模块 / 最近的重要决策。
- 开新窗口、隔天回来，想一眼知道"我在哪、上次做到哪、下一步建议"。
- 不适用：没有 active work 时要推进新工作 → `/pmai-design`。已有 `building / iterating / final_check` 时，继续查看、检查或修改当前结果属于原 `/pmai-build`，不是新 design。

## Preamble

```bash
PMAI_PREAMBLE_READ_ONLY=1
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
unset PMAI_PREAMBLE_READ_ONLY
echo "SKILL: status"
```

## Workflow

1. 如果 preamble 或 status-view 提示当前目录还没有 PMAI 初始化，只输出这件事并引导 PM 先发 `/pmai-init-project`。它会自动判断全新项目 / 资料目录 / 已有代码库；本 skill 到此停止，不继续读不存在的 PMAI 文档。

2. 跑现状播报（结构化，基于现有字段、不编造）：

   ```bash
   python3 "$PMAI_HOME/scripts/status-view.py" --narrative 2>/dev/null || true
   ```

   若状态是 `building / iterating / final_check`，PM 随后说“启动看看”“还有什么问题”“改一下当前结果”等自然语言时，按当前 `/pmai-build` 续接：先读取 `status-view.py --execution-context` 的只读合同，再重新编译 context pack。不要把它路由成通用 QA，也不要重新发明 PM 未决问题。

3. @读 `PRODUCT-STATE.md`（现状）+ `PRODUCT-RULES.md`（跨模块规则与最近重要决策；不存在就跳过，不把“不存在”当成近期决策汇报）+ 当前涉及模块的 `discussion.md` / `decisions.md` / `spec.md`，必要时看 `git status --short --untracked-files=all` 判断是否有未提交改动。用 PM 视图大白话报一段，按下面合同输出：

   **无进行中工作、且工作区干净**：
   ```markdown
   当前状态：没有进行中的工作

   <一句话产品现状>

   建议下一步：
   小修现有结果可发 /pmai-quick-fix；新功能或产品规则变化发 /pmai-design。
   ```

   **无进行中工作、但工作区有未提交改动**：
   ```markdown
   当前状态：有一轮改动还没收口

   <一句话产品现状>

   正在处理的是「<从 docs/modules 或 git diff 推断的模块名；推断不出就写这轮未提交改动>」。

   这轮已经定下来的方向是：
   1. <从 decisions/spec 里取 1 条已拍方向>
   2. <最多 5 条，不够就少写>

   需要注意：
   当前有未提交的代码或文档改动。它们不是已经完成的稳定状态。

   建议下一步：
   先把这轮改动固定到独立分支或提交点，再继续验证和收口。
   ```

   **一个进行中工作**：
   ```markdown
   当前状态：有 1 个进行中的工作

   <一句话产品现状>

   正在处理的是「<模块名>」。

   状态：<需求讨论 / 设计已定 / 构建中 / 看结果并修改 / 最终检查 / 已进入主线待更新文档>。
   已定方向：<1–3 条；没有就省略，不写“未见”>

   建议下一步：
   <一句明确动作>
   ```

   **多个进行中工作**：
   ```markdown
   当前状态：有 <N> 个进行中的工作

   <一句话产品现状>

   进行中的工作：

   1. <模块名>
      状态：<设计讨论 / 等待实现或正在实现 / 正在复审 / 等待收尾>。
      已定方向：<一句；没有就省略>
      下一步：<一句明确动作>

   2. <模块名>
      状态：<...>。
      下一步：<...>
   ```

   排序规则：已进入主线待更新文档的排最前，其次是最终检查、看结果并修改、构建中、设计已定、需求讨论。

4. **纯只读**：不写、不改任何文件或状态。无数据时直说"目前没有在做的模块，可发 `/pmai-design` 起新工作"，不编造。

## Rules

- 只读视图，绝不写文件 / 改状态（区别于会改状态的 `/pmai-quick-fix` / `/pmai-design` / `/pmai-build` / `/pmai-build-close`）。
- PM 话术不出内部词（`.work-meta` / 真相源 / 派生 等不直接念给 PM）。
- 不把脚本诊断讲给 PM：禁止输出“PMAI 状态脚本显示”“记录层没有挂起模块”“可以理解为”“PRODUCT-RULES.md 不存在所以没有决策”这类话。只说 PM 要行动的事实。
- 如果脚本状态和工作区状态不一致，优先给 PM 一个行动结论：有未提交改动就说“有一轮改动还没收口”，不要展开内部原因。
