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

**关键**：必须扫**三个来源**取最大值，不能凭印象只扫文件目录。**事实来源是 git 分支**——active req 都在自己分支上，main 分支视角下 `requirements/active/` 通常是空的（active req 没 merge 回 main），只看目录会漏号导致撞号。

机械执行下面命令（不要简化、不要跳步）：

```bash
# 1. closed req 目录（main 分支可见 — 已 merge 的归档）
CLOSED_NUMS=$(ls -d "$REPO_ROOT/requirements/closed/req-"* 2>/dev/null \
  | sed -E 's|.*/req-([0-9]+)-.*|\1|' | sort -n)

# 2. active req 目录（main 分支视角下通常空，但兜底扫一下）
ACTIVE_NUMS=$(ls -d "$REPO_ROOT/requirements/active/req-"* 2>/dev/null \
  | sed -E 's|.*/req-([0-9]+)-.*|\1|' | sort -n)

# 3. git 所有 req-NNN-* 分支（**主要来源** — 包括其他 worktree 里的 active req）
BRANCH_NUMS=$(git -C "$REPO_ROOT" for-each-ref --format='%(refname:short)' \
  'refs/heads/req-*' 2>/dev/null \
  | sed -E 's|.*req-([0-9]+)-.*|\1|' | grep -E '^[0-9]+$' | sort -n)

# 取三者最大值 + 1（任一都没有 → 001）
MAX=$(printf '%s\n' $CLOSED_NUMS $ACTIVE_NUMS $BRANCH_NUMS | grep -v '^$' | sort -n | tail -1)
NEW_NUM=$(printf '%03d' $((${MAX:-0} + 1)))
echo "下一个可用编号：req-$NEW_NUM"
```

**禁止**：
- 仅扫 `closed/` 不扫 `active/` 与 git 分支 — 错过 active req 的占号必然撞号
- 凭"我看到 closed 里最大是 002 所以新号 003"印象 — 必须实跑命令
- 跳过 git 分支扫描 — 这是主要来源（active req 占号唯一可靠依据）

### 步骤 2：判断是否 first req

`is_first_req = (CLOSED_NUMS、ACTIVE_NUMS、BRANCH_NUMS 三者全空)`。

任一非空都不是 first req。**不能仅看 closed/**——同样会被 active req 在自己分支上的事实骗到。

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

### 步骤 4：Stage 1 — 产出 brief.md（由 PM 主导）

**关键原则**：brief 阶段如何引导思考**由 PM 自己决定**，AI 不主动调用任何工具、不预读项目文档/历史 req。AI 在此步骤只做两件事：(1) 提示 PM 三条候选路径，(2) 等 PM 选择后整理产出为 `brief.md`。

输出提示给 PM（不要替 PM 选）：

```
brief.md 还没写。你可以选任何方式产出，我帮你整理成符合 PM-VIEW-RULES 的格式：

1. 自跑 /office-hours（gstack skill）做六问深挖思考 — 跑完把产出贴回来我整理
2. 直接口述需求要点（几句话也行）— 我按 PM-VIEW-RULES 结构化成 brief
3. 自己写完整 brief.md — 我只做格式校验

也可以混合（先跑 1 拿到产出，再补充几句让我合并）。等你说就行。
```

**等 PM 主动告诉**采用哪种路径或直接给内容。**禁止**：
- AI 主动调用 `/office-hours` 或任何 review/research skill — `/office-hours` 是 gstack 通用产品发现工具（含 builder/startup 模式选择 + telemetry + gbrain context queries），适合 PM 自主使用，不适合 AI 替 PM 跑
- 在 PM 给出方向前去读 `requirements/closed/req-*` 的 brief / 项目级 docs / brief 历史 — RAG 噪声，PM 需要时自己会让你读
- 自作主张提"我先了解一下背景再问你" — 破坏对话节奏

PM 给出 brief 内容后，AI 按 PM-VIEW-RULES（特别是 §三写作规则、§四 brief.md 严格度行）整理成 `brief.md`，写入 req 目录。

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

- 允许多个 active req 并行（每个 req 一个 worktree、一条分支、一份 .req-meta.json，互不干扰）。已有 active req 时不要拦截，正常创建即可
- slug 从需求描述自动生成，不需要问 PM
- brief.md 用 PM 的原话整理，不要过度改写或添加 PM 没说的内容
- brief 引导路径由 PM 选（步骤 4）；AI 不主动调 `/office-hours`、不预读历史 req / 项目 docs
- PM 直接描述清楚就直接写 brief；PM 选六问引导就提示 PM 自跑 `/office-hours` 后贴产出回来
