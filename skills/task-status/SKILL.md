---
name: pmai-task-status
description: |
  全局状态总览：从产品视角展示当前需求的产品现状、主原型状态和本次增量进展，附最近动作和下一步建议。
---

# /pmai-task-status

## When To Use

- PM 随时调用，查看「我现在在哪、产品长什么样、这次在加什么」

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: task-status"
```

## Workflow

### 步骤 1：调用 status-view.py

```bash
python3 "$PMAI_HOME/scripts/status-view.py"
```

脚本自动：
1. 找到主仓根目录
2. 扫描 `requirements/active/` 找当前活跃需求
3. 读取当前需求进展、产物文件、最近一次动作
4. 读取执行中 task 的最后事件
5. 统计多 task 摘要：执行中 / 待启动 / 已完成
6. 输出格式化状态总览

### 步骤 2：按产品轴展示结果

把 status-view.py 的原始输出读进来，**重新组织成产品视角**给 PM 看。展示主轴是产品，不是流程进度——三段递进：

1. **产品现状摘要**：当前产品做到哪一步、能干什么。源头是项目根的 `PRODUCT-STATE.md`（产品现状统一层）；没读到就如实说「还没建产品现状档」，不编造。
2. **主原型状态**：`prototype/` 主原型当前的样子（已有哪些页面 / 流程跑得通到哪），以及本次需求在原型里改动的位置。
3. **本次增量**：当前活跃需求要往产品里加什么。源头是该需求的 `req-plan.md`（范围清单 WHAT + 关键决策页 WHY）；列出范围清单里这次要做的事，以及做到哪了。

**不要把流程进度当主轴播给 PM**——别输出「第几步 / 几步走完」这类内部流程编号，PM 关心的是产品和增量，不是流水线坐标。

多 task 摘要第一行必须使用脚本给出的这行：

```text
📋 task 概览: 执行中 N1 / 待启动 N2 / 已完成 N3
```

其中「待启动」指状态为「待执行」且 worktree 已建的 task；「执行中」覆盖 AI 实现期 + PM 验收期（commit 不切状态，PM 通过呈交块时直接转「已完成」）。每个 task 是 PM 看 demo 确认方向的一个阶段单元。

逐 task 提示规则：

- 扫到「待执行」状态且 worktree 已建的 task，输出：
  ```text
  等待 PM 在新窗口启动（跑 /pmai-task-execute task-NNN）
  ```
- 扫到「执行中」状态 task，输出：
  ```text
  执行中：在对应 task 窗口实现 / 验收（可跑 /pmai-task-submit 重新查看呈交块）
  ```

输出格式示例：

```
当前需求：req-002-review-system
产品现状：评审系统已能登录 + 提交评审；本次在加「评审历史」一栏。
主原型：prototype/ 已跑通登录与提交流程，本次改动落在评审详情页。
本次增量（req-plan.md 范围清单）：①历史列表 ②历史筛选 ③历史导出。
📋 task 概览: 执行中 2 / 待启动 1 / 已完成 1
Task 状态：
  ✅ task-001 数据模型 — 已完成
  🔄 task-002 历史列表 — 执行中（实现中，最后活动：自审 - /qa pass）
  🔄 task-003 历史筛选 — 执行中（已 commit 待 PM 验收，可跑 /pmai-task-submit 看呈交块）
  ⏳ task-004 历史导出 — 待执行：等待 PM 在新窗口启动（跑 /pmai-task-execute task-004）
下一步：处理执行中 task，或发 /pmai-next 推进，或启动待启动 task
```

如果没有活跃需求：

```
📭 没有活跃的需求。发 /pmai-new-req 开始一个新需求，或 /pmai-init-project 起一个新项目。
```

### 步骤 3：给下一步建议

末尾给一句下一步。**推进统一走 `/pmai-next`**——它会先说清「接下来要做 X / 要你确认 Y」再动手：

- 有执行中 task：先把执行中 task 处理完（在对应窗口实现 / 验收）。
- task 都收尾了、需求该往前走：发 `/pmai-next` 推进到下一步。
- 没有活跃需求：发 `/pmai-new-req` 起新需求，或 `/pmai-init-project` 起新项目。
- 想反向出一份评审用 PRD：发 `/pmai-prd-writing`（独立沉淀，不占需求推进）。

## Rules

- 不修改任何状态，纯只读操作
- 可以在任何位置调用（主仓、req worktree、task worktree）
- status-view.py 会自动找到主仓根目录
- 展示主轴永远是产品（产品现状 / 主原型 / 本次增量），不是内部流程编号
- 产品现状 / 增量内容读不到对应文件时如实说「还没建」，绝不编造
