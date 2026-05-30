---
name: pmai-next
description: |
  推进当前需求到下一步：读当前需求做到哪了，把它往前推一步——确认范围 / 接着建 / 建完三道审 / 收尾沉淀。推进前先说清「接下来要做什么 / 要你拍哪个板」再动手。
---

# /pmai-next

> **本 skill 是需求推进的主驱动。** 一个需求从「范围确认 → build → 复审 → 沉淀」一路往前走，都靠它推。PM 不用记自己在哪一步——发 `/pmai-next`，AI 读当前状态，告诉你「现在该做 X / 要你拍 Y」，你点头它再动。
>
> 异常恢复（窗口被关 / 状态读不出 / worktree 残留卡住）走 `/pmai-req-stage-gate` 复位，复位完再回到 `/pmai-next`。

> **PM 视图（banner + 决策门 label）**：入口 banner（`status-view.py --banner-only --skill NEXT`）；推进确认门 / 验收门 label 按 `_shared/pm-view/banner-rules.md` §3 三条硬规则；退出 Next Up 块按 §2。
>
> **PM 答题规则**：所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 四条硬规则走（空答 STOP / 没拿到答案禁止落盘或推进 / runtime 退化保留 wait / 多决策拆开顺序问）。**Runtime 兜底**：本 skill 各门写的都是 picker 形态；runtime 不支持时 AI 按 §1.3 自动退化为编号列表，仍 wait。

## 什么时候用

- 一个需求做到一半，想往前走一步：发 `/pmai-next`。
- `/pmai-new-req` 把范围确认完、拉好 worktree 后，PM 在新窗口发 `/pmai-next` 接着建。
- 某一步的确认门没答就关了窗口，回来重发 `/pmai-next`，它从当前位置把同一个确认门重新拉起来。

## 核心护栏：先说要做什么，再动手

**这是本 skill 的第一铁律。** AI 读完当前状态后，**永远先用一两句话讲清**：

- 「接下来我要做 X」（比如：接着在主原型里建这次的增量 / 跑三道复审 / 把成果合回主线）
- 「需要你先拍 Y」（比如：这块归到哪个菜单下、这个范围要不要收）

讲清之后**才动手**。不闷头跑、不一上来就改文件。命中要 PM 拍板的结构决策（分区 / 菜单归类 / 模块切分 / 命名底稿）时，当场逐条问 PM 拍，不事后追认。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: next"

# 视觉锚点（见 _shared/pm-view/banner-rules.md §1）
python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill NEXT || true

# worktree 残留检测（informational，不阻塞；有问题仅打印警告供 PM 处理）
python3 "$PMAI_HOME/scripts/check-worktree-residue.py" || true
```

worktree 残留检测报警时，先把警告原文一句话转给 PM（"发现 N 个 worktree 残留 / 冲突，已贴上方"），PM 可选立刻清理或继续。本 skill 不当 gate。

## 怎么推进

### 第 1 步：读当前需求做到哪了

通过 `_lib.state.get_overall_state()` 拿当前 active req、当前在哪个阶段（范围确认 / build / 复审 / 沉淀）、最近一次状态变更、当前 task 情况。

**无 active req → 不编造**（防 narrative 幻觉），直接给兜底提示：

```
目前没有 active req。
可以发 /pmai-new-req 起新需求，或发 /pmai-init-project 起新项目。
```

### 第 2 步：先报「接下来要做什么 / 要你拍什么」

按核心护栏，用 PM 听得懂的话讲清当前位置 + 下一步动作 + 要不要 PM 拍板。**不贴文档全文**——PM 的 IDE 已挂在 worktree 上，需要时让 PM 看路径自己读。

### 第 3 步：按当前阶段做对应的下一步

| 当前阶段 | `/pmai-next` 做什么 |
|---|---|
| **范围确认** | 读产品现状 + 跑当前主原型找 delta，和 PM 把范围谈成 `req-plan.md`（范围清单 + 关键决策页），PM 拍板。范围细化 / 列范围清单走 `/pmai-task-plan`；想深挖工程 HOW 按需后台走 `/pmai-implementation-design`。结构决策当场逐条问 PM 拍。**范围定稿前，若关键决策页里还有没拍板的问题，用 `check-open-questions.py` 拦住、逐条让 PM 答完才放行，不给绕过的口子。** |
| **build** | 在 `prototype/` 里用 Claude Code 栈内建这次的增量（零录入、mode 中立），动手前**强制 @读 `docs/DESIGN.md`**。看 demo 确认方向的工作单元走 `/pmai-task-execute` |
| **复审** | build 完自动跑三道审：覆盖审计（范围清单 vs 实际改了什么的硬对比）+ 视觉门（gstack `/design-review` 只截图不改）+ 行为审（按验收流程跑 gstack `/browse`）。审完进体验迭代 + 呈交闸门，等 PM 验收 |
| **沉淀** | 调 `/pmai-close-req` 收尾：更新产品现状（PRODUCT-STATE）+ 把主原型合回主线；PM 要拿去评审时按需反向出可评审 PRD |

每个阶段的具体流程在对应 skill 里，本 skill 只负责**判断当前在哪一步、报清楚、把对应能力拉起来**，不复制各 skill 的内部细节。

### build 阶段：串行 / 并行派发（按 task-plan 拍的执行模式）

task-plan 里 PM 拍过这次的执行模式（串行 / 并行 / 混合）。build 推进按它走：

- **串行**：一个 task 走完 `/pmai-task-execute`（建 → 三道审 → 呈交）、PM 拍板，再起下一个。
- **并行**：把**依赖已满足、互不冲突**的 task **各派一个独立执行器并发建**——每个 task 自己的 locked worktree、自己的执行器（claude subagent / codex / cursor / gemini）。全部建完 + 各自三道审后，**逐个呈交 PM 验收**（建并发、呈交仍串行，PM 一个个拍）。
- **混合**：先串行打底的 task（产规范 / 被依赖的），再把后面独立的并发铺开。

> **一 task 一执行器（铁律，2026-04-22 串台根因）**：并发时**绝不让一个执行器一口气干多个 task**。每个 task = 一次独立 `/pmai-task-execute` 派发 = 一个只认自己 worktree 的执行器（workspace 限定 + 越界保护兜底）。2026-04-22 事故就是一个 Codex suborchestrator 一气干了 task-001→006、把各 task 代码混进一个 worktree——结构上禁掉「一执行器多 task」即根除。
> 并发安全：每 task worktree 建时 `git worktree lock`（防一个 task 的清理 prune 掉另一个在跑的）；同 task 重复派发由 per-task lock 挡。
> **安全边界（2026-05-30 实测 + PM 拍板「接受残留」）**：外部执行器**不能靠 sandbox / config 物理关进自己的 worktree**——codex `workspace-write` 实测放行整个 `$HOME`（cwd / `writable_roots` 都收窄不动它），`git worktree lock` 也不拦 fs 写。所以防线是**结构化**：一 task 一执行器 + dispatch 越界保护（扫自己 worktree 超 allowlist 的文件、rollback）——足以挡 2026-04-22 那次事故形态（执行器把别 task 代码堆进**自己**的 worktree 再 commit）。**残留**：执行器故意写绝对路径到**兄弟** worktree 物理拦不住，但非历史形态、正常 build prompt 不诱发、低概率；真物理隔离（容器 / 独立 uid）对单人工具不成比例，**不做**。

### 第 4 步：推进后给一句 Next Up

一步走完，按 `_shared/pm-view/banner-rules.md` §2 出 ▶ Next Up 块，告诉 PM 下一步动作。例：

```
▶ Next Up：
   <这一步成果一句话> —— 下一步发 /pmai-next 继续推进
```

中途 PM 不答确认门就关窗口 → 回来重发 `/pmai-next` 自动从当前位置续走。

## 续跑行为

- 确认门没答 → 按 `askuser-rules.md` §1.1 STOP wait，不重试、不默认走推荐项、不静默继续。
- 没拿到 PM 答案前 → 按 §1.2 不写 PM 视图文件、不 commit、不切阶段。
- 窗口被关后回来重发 `/pmai-next` → 从当前状态重新判断并把同一个确认门拉起来；不假装有进度。

## Rules

- **先说后做**：推进任何一步前先讲清「要做 X / 要你拍 Y」，PM 点头再动手——本 skill 第一铁律。
- **不编造状态**：读不到 active req 就直说没有，引导发 `/pmai-new-req`；不假装有进度。
- **结构决策前置**：分区 / 菜单归类 / 模块切分 / 命名底稿命中时当场逐条问 PM 拍板，不自判「无歧义」跳门、不事后追认。
- **不复制各阶段 skill 的内部逻辑**：本 skill 只判断当前位置 + 报清楚 + 把对应能力拉起来；范围确认 / build / 复审 / 沉淀的细节各归其 skill。
- **PM chat 输出禁工程黑话**：不出现 `hash` / `lint` / 脚本名 / 内部编号 等内部记账词；用 PM 听得懂的话讲现状和下一步。
- **只给路径 + 一句话**：PM 的 IDE 已挂在 worktree 上，确认门 / 报告不贴文档全文。
- **worktree 残留检测只报不挡**：informational，不当 gate。
