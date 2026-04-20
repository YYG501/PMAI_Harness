---
name: new-req
description: |
  开始一个新需求：创建 req 目录和 worktree，引导 PM 完成 stage 1（brief.md）。
---

# /new-req

## When To Use

- PM 在业务项目中调用，参数是需求描述（如 `/new-req "实现用户登录"`）

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

**3c. 提示 PM 切换 IDE 到 worktree 目录**：

```
📁 Req worktree 已创建：<worktree-path>

请在 IDE 中打开此目录，这样你可以直接查看和编辑 req 文档：
  cursor <worktree-path>
  或
  code <worktree-path>

后续所有 stage 的文档产出都在这个目录里。
```

如果 PM 同意，帮 PM 执行 `cursor <worktree-path>` 或 `code <worktree-path>`。

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

### 步骤 6：确认门

brief.md 写好后，**必须把 brief.md 全文贴给 PM 看**（不只是摘要），然后询问：

```
以下是 brief.md 的完整内容：

---
[贴出 brief.md 全文]
---

确认后进入 stage 2（需求分析）。

A) 确认，进入 stage 2
B) 我要修改（请说明改哪里）
```

**规则：所有确认门都必须把该 stage 的完整产出文档贴给 PM 看。** PM 不应该需要自己去 worktree 路径里找文件。

PM 确认后，调用 `/req-stage-gate` 推进到 stage 2。

## Rules

- 一次只能有一个 active req（如果已有 active req，提示 PM 先关闭或取消）
- slug 从需求描述自动生成，不需要问 PM
- brief.md 用 PM 的原话整理，不要过度改写或添加 PM 没说的内容
- 引导问题是辅助，PM 如果已经描述清楚了就直接写 brief，不必逐个追问
