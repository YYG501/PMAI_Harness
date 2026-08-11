---
name: pmai-record
description: |
  补录已确认的项目知识：仅在产品基线有效、主仓没有 active work 时，把 PM 已明确确认的待办、稳定术语、跨模块规则、项目级理路，或有 main 现存事实依据的现状纠错，写回既有真相源并单独提交。不用于产品方向重判、模块设计、进行中工作的同步或 Proposal 修改。
  触发词：记一下 / 补录一下 / 这个已经定了，别丢 / 把这条待办、术语、规则或理路记进项目。
---

# /pmai-record

## 定位

> **这是什么**：工作流之外的项目知识补录入口。它回答的是「这件事已经定了，帮我记住，后面别丢」。

`record` 只负责把**已经确认**的知识放到后续会读取的真相源，不负责重新判断产品方向、补做模块设计、替实现流程收尾，或把讨论中的想法包装成现状。

正常的 Proposal、design、quick-fix、build 都由各自流程保存和同步，不把 `/pmai-record` 作为固定下一步。

## 入口护栏

先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
echo "SKILL: record"
```

按以下顺序判断，任何一项不满足都停止，不落盘：

1. preamble 输出 `PMAI_PROJECT_INITIALIZED: 0`：引导 PM 先发 `/pmai-init-project`。
2. 在选择补录类型或目标文件前运行一次产品基线门：

   ```bash
   PROPOSAL_STATUS_JSON=$(python3 "$PMAI_HOME/scripts/proposal-contract.py" status "$REPO_ROOT")
   PROPOSAL_STATE=$(python3 -c \
     'import json,sys; print(json.load(sys.stdin)["state"])' \
     <<<"$PROPOSAL_STATUS_JSON")
   ```

   - `accepted` / `equivalent_baseline`：继续 record；
   - `required`：初始化后的唯一下一步仍是 `/pmai-proposal`，停止，不选落点、不写文件、不提交；
   - `invalid`：当前 Proposal 或产品基线已漂移，停止，只返回 `/pmai-proposal` 生成完整新版本；record 不修合同；
   - 其它未知结果：失败关闭，不猜测产品基线。

3. `WORKTREE_TYPE != main`：当前仍在隔离工作中，先发 `/pmai-status` 回到原工作。
4. `ACTIVE_WORK_COUNT != 0`：当前有进行中的模块工作，知识应由该工作的 design / build / finalize 收口；先发 `/pmai-status`，不得用 record 绕开原流程。
5. 本次目标真相源缺失、路径异常或不符合当前文档布局：引导 `/pmai-doctor` 做只读诊断；未经 PM 确认不得由 record 重建底座。
6. `git diff --cached --quiet` 不通过：已有 staged WIP，停止并说明冲突；不得提交、unstage、stash 或卷入已有暂存内容。

## When To Use

- PM 明确说「记一下」「补录一下」「这个已经定了，别丢」，当前产品基线有效，且内容不属于任何 active work。
- 一次独立讨论已经明确形成稳定术语、跨模块规则或项目级理路，PM 要求写回项目上下文。
- `TODO.md` 漏了 PM 已明确提出的后续事项。
- `PRODUCT-STATE.md` 与 main 已经存在的事实不一致，需要按可核验事实纠错。

以下情况不适用：

| PM 的真实意图 | 去哪里 |
|---|---|
| 产品定位、目标用户、价值、边界或 MVP 需要新判断 / 重判 | `/pmai-proposal` |
| 模块对象、动作、状态、权限、页面、异常路径或验收规则发生变化 | `/pmai-design` |
| 只是查看当前进度或不知道原工作在哪 | `/pmai-status` |
| 项目底座文件缺失或归位异常 | `/pmai-doctor` |
| quick-fix / build / Proposal / design 正在执行或刚完成 | 回原流程，由原流程自行同步 |

## 可写边界

完整读取 `skills/_shared/record-routing.md` 的“`/pmai-record` 专用边界”，并以该节作为**允许内容、落点、证据和禁写范围的唯一正本**。本 skill 不再复制第二张落点表。

从正本中只能选择一个或多个已明确允许的落点；无法唯一归类时停止并按其上游分流处理。无论如何都不得写 `docs/modules/**`、`docs/proposals/**`、mockup、工作流状态或实现文件。新增项目级理路时再完整读取 `_shared/decision-record.md`。

## Workflow

### 步骤 1：固定这次要记住的原话

从 PM 的明确表达中提取一条或几条已确认结论，并为每条标出：

- 要记什么；
- 为什么能确定它已经确认；
- 对应哪个允许落点。

只能从 PM 明确确认、既有有效决定或 main 可核验事实取材。讨论草稿、AI 建议、问句、未选择方案和未提交实现都不是已确认知识。

如果内容仍需比较方向或补产品判断，停止 record，按上表转 `/pmai-proposal` 或 `/pmai-design`；不要在本 skill 内补做讨论。

### 步骤 2：核验现状和写入冲突

读取相关真相源及 `git status --short`：

1. 确认目标文件存在且当前结构可识别；否则转 `/pmai-doctor`。
2. 确认目标文件没有本轮开始前的未提交改动；有重叠改动时停止，让 PM 先处理，不覆盖。
3. 写 `PRODUCT-STATE.md` 前，读取 main 已提交实现或已提交产品事实。没有可指认依据时，不得写「已支持 / 已上线 / 已完成」。
4. 去重：已有同义 TODO、术语、规则或理路时，只修正必要内容，不重复追加。

### 步骤 3：最小补录

只 patch 真正需要变化的行：

- TODO 保持无序，条目写清目标和涉及模块 / 文件。
- 术语只补稳定定义，不顺手改 PRODUCT 其它章节。
- 跨模块规则写清 scope；单模块规则退出本 skill，转 design。
- 项目级理路按 decision-record 模板新建冻结记录，不回改旧历史记录。
- PRODUCT-STATE 只把文档纠正到 main 已存在事实，不从讨论、mock 或 WIP 推导现状。

本次新建项目决策记录时，机械确认 `docs/INDEX.md` 能找到它；除此以外不扩写索引。

### 步骤 4：复核与提交

若只补 TODO、术语或有证据的 PRODUCT-STATE 纠错，PM 本次「记一下」已构成写入授权，可直接进入精确提交。

若修改 `PRODUCT-RULES.md` 或新增项目决策记录，先向 PM 展示路径和简短 diff，确认表述无误后再提交。PM 打回时只改本次补录内容。

提交前必须再次检查：

```bash
git -C "$REPO_ROOT" diff --cached --quiet
git -C "$REPO_ROOT" status --short
```

然后只逐个暂存本次实际修改的允许文件，禁止 `git add -A`。暂存后用 `git diff --cached --name-only` 核对集合与计划完全一致；出现任何额外路径立即停止，不得替 PM 清理暂存区。

```bash
git -C "$REPO_ROOT" add -- <本次实际修改的文件...>
git -C "$REPO_ROOT" commit -m "记录: <一句话说明补录内容>"
```

commit 失败时保留现场并说明原因，不 reset、不 stash、不改写历史。

### 步骤 5：回执

只用 PM 语言说明记住了什么和落在哪里：

```text
已记录（<short-hash>）：<一句话结论>，放在 <待办 / 术语 / 项目规则 / 项目决策 / 产品现状>。
```

不要输出「分类模型、manifest、冻结档、索引展开层、hash 对账」等内部实现词。

## Rules

- 只在产品基线状态为 `accepted / equivalent_baseline`、主仓且 `ACTIVE_WORK_COUNT=0` 时运行；Proposal required / invalid 只回 Proposal，active work 永远回原流程收口。
- 只补录已确认知识，不在 record 内探索、设计、实现或替 PM 作决定。
- 不把 record 作为 Proposal、design、quick-fix 或 build 的后续步骤。
- PRODUCT-STATE 只允许依据 main 已存在事实纠错；新能力只能由 landed 后自动文档编译写入。
- 只写允许路径，逐个暂存，单独提交；任何已有 staged WIP 都先停止。
- 项目底座缺失或异常时只转 doctor 诊断，未经确认不修复。
