---
name: new-req
description: |
  开始一个新需求：创建 req 目录和 worktree，引导 PM 完成 stage 1（brief.md）。
---

# /new-req

## When To Use

- PM 在业务项目中调用，参数是需求描述（如 `/new-req "实现用户登录"`）

## PM 视图规则（必读）

本 skill 间接产出 `brief.md`（通过 /office-hours），须遵守 `skills/_shared/PM-VIEW-RULES.md`。
特别注意：
- §三 PM 视图写作规则（明确指代 / 正向描述 / 禁工程词 / 禁像素颜色 / 禁反向约束）
- §四 文档级严格度对照表（brief.md 行）
- §九 输入流约束（brief.md 是后续所有 stage 的源头，不接受任何上游 .engineering.md 输入）

`brief.md` 不拆文件（PM-VIEW-RULES §二）。

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: new-req"
```

## Workflow

### 步骤 1：确定 req 编号

扫描 `$REPO_ROOT/requirements/active/` 和 `$REPO_ROOT/requirements/closed/` 目录，找到最大 req 编号，新 req 编号 = 最大编号 + 1。

如果没有任何 req 目录，编号从 001 开始。

### 步骤 2：判断是否 first req

检查 `$REPO_ROOT/requirements/closed/` 是否为空（无任何 req 目录）。如果 active/ 和 closed/ 都没有已完成的 req，则当前为 first req。

### 步骤 3：先创建 worktree，再在 worktree 里创建 req 目录

**顺序很重要：先 worktree，后文件。** 不能在主仓创建文件再拉 worktree（未 commit 的文件不会出现在 worktree 里）。

从 PM 提供的需求描述生成 slug（英文 kebab-case，2-4 个词）。

**3a. 创建 worktree：**

```bash
bash .claude/scripts/create-req-worktree.sh "req-NNN-<slug>"
```

cd 到返回的 worktree 路径。

**3b. 在 worktree 里创建 req 目录和元数据：**

创建目录：`requirements/active/req-NNN-<slug>/`

创建子目录：`tasks/`、`tasks/_archived/`

创建 `.req-meta.json`：

```json
{
  "id": "req-NNN",
  "name": "<slug>",
  "branch": "req-NNN-<slug>",
  "worktree": ".worktrees/req-NNN-<slug>",
  "stage": 1,
  "stage_history": [
    {"stage": 1, "entered_at": "<ISO-8601>"}
  ],
  "is_first_req": true/false,
  "status": "active"
}
```

### 步骤 4：Stage 1 — 调用 /office-hours 产出 brief.md

调用 `/office-hours`（gstack skill），用六问追问帮 PM 深挖需求：
1. 需求真实性：有没有真实用户在痛苦？
2. Status quo：他们现在怎么解决？
3. Desperate specificity：谁最急迫需要？
4. 最窄楔子：能不能再砍一半范围？
5. 观察证据：你亲眼见过吗？
6. Future-fit：3 年后还有意义吗？

`/office-hours` 完成后，将其产出的 design doc 内容**复制到** req 目录的 `brief.md`。

`brief.md` 是 stage 1 的唯一真相源，后续所有 stage 只读 brief.md。

### 步骤 6：Handoff（结束本对话，让 PM 在 worktree 新对话里继续）

brief.md 写好后，**当前主对话不再继续 stage 2**。`/new-req` 的职责到此为止——req 全过程从这里搬到 worktree 内的独立 Claude 对话，让每个 req 拿到干净的 context。

输出 handoff 块（**不出 A/B**，不在主对话里调 `/req-stage-gate`）：

```
📝 brief.md 已写入：`<绝对路径>`

一句话摘要：[本次 brief 的核心内容，一行]

—— 主对话到此为止 ——

下一步（PM 自己执行）：
  1. 打开新终端窗口
  2. 运行：
       cd <worktree 绝对路径>
       claude
  3. 在新 Claude 对话里跑：
       /req-stage-gate
     （新对话会重新读 brief.md 给二次确认门，确认后进入 stage 2）
```

**规则**：
- 主对话不输出 A/B；A/B 由新对话里的 `/req-stage-gate` 负责。
- 输出只给路径 + 一句话摘要，不贴 brief 全文。需要时让新对话的 Claude 把 brief.md 读回 chat。

## Rules

- 一次只能有一个 active req（如果已有 active req，提示 PM 先关闭或取消）
- slug 从需求描述自动生成，不需要问 PM
- brief.md 用 PM 的原话整理，不要过度改写或添加 PM 没说的内容
- 引导问题是辅助，PM 如果已经描述清楚了就直接写 brief，不必逐个追问
