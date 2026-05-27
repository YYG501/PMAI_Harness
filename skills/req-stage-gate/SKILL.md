---
name: pmai-req-stage-gate
description: |
  Req stage 边界推进：根据当前 stage 执行过渡逻辑，PM 确认后推进到下一 stage。
---

# /pmai-req-stage-gate

> **PM 视图（M2 banner + Decision gate label）**：本 skill 入口 / stage 转换处 / 退出处必出 banner（按 `_shared/pm-view/banner-rules.md` §1；用 `status-view.py --banner-only --skill REQ-STAGE-GATE`）；闸门 label 按 §3 3 硬规则（label=动作描述如「写 PRD」/ description=一句话 / 留守选项 Loop 回讨论态）；退出 Next Up 块按 §2 格式。**禁用模糊词** "OK" / "Proceed" / "Continue"。
>
> **PM 答题规则（M4）**：所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 3 硬规则走（空答 STOP / 没拿到答案禁止落盘 / runtime 退化保留 wait）。**禁止默认走 recommend 分支 / 禁止逃生舱**。

## When To Use

- Orchestrator 在每个 stage 完成后调用，推进到下一 stage

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: req-stage-gate"

# M2 banner（视觉锚点；见 _shared/pm-view/banner-rules.md §1）
python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill REQ-STAGE-GATE || true

# worktree 残留检测（informational，不阻塞推进；有问题仅打印警告供 PM 处理）
python3 "$PMAI_HOME/scripts/check-worktree-residue.py" || true
```

读取 `$ACTIVE_REQ_STAGE` 确定当前 stage。

如果 worktree 残留检测报警，先把警告原文展示给 PM 一句话说明（"发现 N 个 worktree 残留/冲突，已贴上方"），PM 可选择立刻清理或继续推进。不当 gate（参见 I-RT5 的范围）。

## Speed Mode（默认行为）

**TL;DR**：PRD（stage 3）拍板后，AI 自动推 stage 4/5，只在两处停 ——
（a）implementation-design.md / task-plan.md 命中**「决策类型=结构」**行 → 当场逐行问 PM 拍板
（b）进 stage 6 前给一次入口总览（自决项列表 + 已拍板结构决策复述 + task 拆分摘要 + PM 三选）

**做这个 mode 的根因**：旧行为 stage 4→5 / 5→6 各有一道"产物已写完，请走查"全文确认门 → PM "看了，过" × 2 等于追认 AI 在 implementation-design 里默默自决的多个**架构选型 / 文档归位 / icon 校验机制**等结构决策（req-008 实证：events.jsonl 里 HOW-01/04/05 都是 AI 推断后 PM 默认接受）。新行为把结构决策**前置到决策当下问**，PM 不再事后从 7 个 HOW 里找"哪些我该早点拍但 AI 自决了"。

**自动推条件**（达成则跳过原全文确认门）：

| Stage | 自动推条件 |
|---|---|
| 4（设计系统）| 步骤 4A gap-check 无新缺组件 + 步骤 4B PM 选不改 DESIGN → 跳 4C 完整确认门直接推 stage 5 |
| 4→5 步骤 5a（implementation-design）| implementation-design.md 段 1 HOW 表 + 段 1.5 SIMP 表**无任何「决策类型=结构」行 / 无任何 SIMP 行** → 跳 5a-gate 原全文确认门，直接进 5b |
| 5→6（task-plan）| task-plan.md §一 task 表**无任何「决策类型=结构」行** → 跳原 task-plan 全文确认门，直接出 stage 6 入口总览 |

**命中结构决策时的 prompt 格式**（逐行问，不批量）：

```
🛑 命中结构决策：<HOW-ID 或 SIMP-ID 或 task-ID>
<一行描述>

候选：
  A. <选项 1>（AI 倾向）
  B. <选项 2>
  C. <选项 3>

AI 倾向 A，理由：<一行>
PM 拍板：
```

PM 答完一个继续下一个；全部答完按 `decided_by=pm-explicit` append 进 req-events.jsonl 各行 + 进下一步。

**Stage 6 入口总览**（替代原 stage 5→6 task-plan 全文确认门）：

```bash
python3 "$PMAI_HOME/scripts/status-view.py" --stage6-entry "$ACTIVE_REQ_DIR"
```

输出格式（status-view.py 内 render）：
- 【AI 自决 N 件】（机械产出 — HOW-ID 列表）
- 【PM 拍过 M 件结构决策】（HOW-ID + 一行复述）
- 【task 拆分】（task-ID + 串行/并行）
- 【产物路径】（implementation-design.md / task-plan.md / DESIGN.md）
- PM 三选：✓ 全 ok 进 stage 6 / ↺ 回看 [ID] / ✗ 回卷到 stage X 重做

**Speed mode 的边界（不替换、不绕过的硬规则）**：

| 项 | 行为 |
|---|---|
| Stage 1-3 流程（brief / analysis / prd 各 stage 的门） | **不变**（speed 只动 stage 3 拍板后的链）|
| Stage 6 task 执行 / Stage 7 close-req | **不变**（不在 speed 范围）|
| 未决问题闸门（Stage 2 `check-open-questions.py`）| **不变**（硬规则，无 FORCE 逃生舱）|
| PRD 决策门（Stage 3 步骤 2 完整确认门）| **不变**（PRD 是 speed 的起点，必须 PM 拍板）|
| AI 拿不准是不是结构决策 | 默认按结构停（保守 / 模板填写规则）|
| 兼容老 req（无「决策类型」列的 implementation-design / task-plan）| AI 在 5a-gate / 5→6 入口现场推断，默认全部按结构（每行问）；不强制迁移老文件 |

下面 Stage 4→5 / Stage 5→6 段在原有"PM 全文确认门"基础上加了 speed mode 分支标记。生成器仓自身（无 `.req-meta.json` / 无 active req）不跑此 SKILL，speed mode 只在业务仓有 active req 时生效。

## 续跑模式（默认行为）

**TL;DR**：PM 只敲 1 次 `/pmai-req-stage-gate`，AI 自动续跑 stage 1→6（撞到 task 执行就退出）。中间 PM 只回答确认门，不再敲命令；不答就停在闸门等 PM 下次输入，关窗口几天后回来重敲 `/pmai-req-stage-gate` 从当前 stage 续走。

**PM chat 输出格式**：推进到下一 stage 时**不发独立的"已推进"通知**（避免每个 stage 之间多一段噪声）；直接进入下一 stage 的第一个动作 / 闸门 / 确认门。退出时（仅 2 种）的话术：

```
✅ Stage 已推进 N → N+1（<下一阶段中文名>）

[根据退出条件二选一：]
▶ Next Up — /pmai-task-confirm tasks/task-NNN-<slug>.md（进入 task 执行；后续 /pmai-task-execute → /pmai-close-task）
[或]
▶ Next Up — req 已关闭，回 main 分支；下个需求请发 /pmai-new-req "<一句话>"
```

<details>
<summary>展开：退出条件 / 不是退出条件 / 核心边界（详细规则）</summary>

PM 在 worktree 里**只需要敲一次** `/pmai-req-stage-gate`，之后 stage-gate 一路带 PM 走完所有 stage 推进。每个 stage 转换块的 `req-transition.py --to N` 成功后，**默认不退出**，立即续到下一 stage 的入口逻辑。

**2 个退出条件**（撞到任一退出本次 stage-gate 调用）：

| 条件 | 说明 |
|---|---|
| 推进到 stage 6（task 执行）成功 | task 循环由 `/pmai-task-spec` `/pmai-task-execute` `/pmai-close-task` 等独立 skill 承担，不属于 stage-gate 推进范围 |
| 推进到 stage 7 后调完 `/pmai-close-req` | req 关闭流程结束 |

**不是退出条件 / 不要写规则的几种情况**（chat 天然行为，写到 SKILL.md 反成噪声）：

- **PM 在确认门不答** → AI 就显示着确认门等 PM 下次输入；这是 chat 天然行为，不需要识别"喊停关键词"也不需要发"已暂停"通知
- **PM 关掉 claude 窗口几天后回来** → 新 chat session 自然不在 stage-gate 流程里；PM 重新敲 `/pmai-req-stage-gate`，stage-gate 从 `.req-meta.json` 当前 stage 续走
- **闸门挂起等 PM**（未决问题闸门、各 stage 定稿确认门、reviewer 有必改时的三选一）→ 挂着等 PM 答，不算"退出"也不算"暂停"——就是等

**核心边界（PM gatekeeper 没破）**：

- 每个 stage 的**确认门 / 闸门**都在原位，PM 没被任何自动化绕过
- 续跑只是把"PM 答 OK 推进 → 下一 stage 第一步"这条路径接通，省掉 PM 重敲 `/pmai-req-stage-gate` 的仪式
- PM 答 OK 类（OK / 通过 / 没问题 / 定了） → 走推进 + 续跑；PM 答修改类 → 走原修改分支；PM 不答 → AI 等

</details>

## attachments AI 接管 hook（trigger 0 — stage-gate 任何 stage 期间生效）

> **B 分支例外**：Stage 1→2 B 分支 office-hours 选源期间（3B / 3B-resume / 3B-snapshot 子步骤）**禁用 trigger 0**，详见下文 Stage 1→2 段。

PM 在 chat 描述 "我有 X 在 ~/Downloads/foo.pdf，重点 Y" → AI first-principle 识别（chat 含绝对路径 + 描述材料）→ 按当前 stage 推 `stage_prefix` 调 helper：

```python
from _lib.attachments import copy_attachment

stage_prefix = {
    1: "brief", 2: "analysis", 3: "prd",
    5: "task-plan",   # 或 "impl"，按当前 stage-5 子步骤
    7: "close",
}.get(int(os.environ.get("ACTIVE_REQ_STAGE", 0)), "unknown")

result = copy_attachment(req_dir, Path("~/Downloads/foo.pdf"),
                        stage_prefix=stage_prefix, hint="Y 重点")
```

chat 一行确认 `已归档（attachments/<新名>），Y 重点。继续。`（禁工程黑话）。异常 catch（`FileNotFoundError` / `SensitivePathError` / `FileSizeError`）→ chat 报错（fail-loud）。

**trigger 2 fallback**：stage-gate 在每 stage 入口扫 `attachments/`，`is_seen` 判定（基于 `.req-meta.json:attachments_seen` 真相源）。

**单一真相源**：`skills/_shared/pm-view/attachments-upload.md`。

---

## Stage 过渡逻辑

### Stage 1 → 2（描述需求 → 需求分析）

> **v4 体验包装层**：brief 二次确认 + 需求讨论方式选择**合二为一**，PM 视角"一次需求讨论"。下游分两条分流：A = 结构化批判（`/pmai-req-analysis`），B = YC office-hours 式（snapshot 复制）。两条分流的产物都通过 `_lib.state.set_stage_source` 写到 `.req-meta.json`，下游 SKILL 一律走 `get_stage_source(req_dir, 2)` helper 读 stage 2 真相源（不再硬编码 `analysis.md`）。

1. 检查 `brief.md` 存在且有内容

2. **brief 二次确认 + 需求讨论方式选择门**（v4 合二为一）：

   `/pmai-new-req` 在主对话写完 brief.md 后就 handoff 退场，PM 在 worktree 内新对话里第一次跑 `/pmai-req-stage-gate` 时，AI 重新读一遍 `brief.md`，把 brief 二确和"用哪种方式跟这个需求讨论"合并成一次对话（v3 书面体 + v4 选择门）：

   ```
   Stage 1 → 2

   ✅ brief.md
      <$ACTIVE_REQ_DIR/brief.md 绝对路径>

   📋 摘要
      <重新读 brief.md 的核心内容，一行>

   💬 怎么往下走？
    - 结构化挖透（默认）—— 一层层把需求问清楚，问完独立复核，剩下未决问题回来找你拍
    - 开放探讨 —— 像聊天一样发散聊，聊清楚直接进 Stage 2，不另做复核
    - brief 还要改 —— 说改哪里
   ```

   **PM 回答的内部分流**（不列 A/B 字母；按 PM 自然语言意图）：
   - PM 说「OK / 通过 / 没问题 / 定了」/ 选第一项 / 直说"结构化挖透 / 结构化批判 / 第一性原理 / req-analysis" → **分流 A**（步骤 3A）
   - PM 选 / 直说「开放探讨 / office-hours / YC 六问 / 设计思考」类 → **分流 B**（步骤 3B）
   - PM 提具体修改 → 按 PM 指示改 `brief.md`，改完后**只输出"已改完"二次摘要**（同一份模板，"一句话摘要"段填新内容），不贴全文；回到本步骤 2 重新出选择门

#### 分流 A：结构化批判（`/pmai-req-analysis`）

3A. **调用 `/pmai-req-analysis`**
   - skill 内部完成：读 brief + PROJECT、第一性原理 4 层分析、写 analysis.md（含 10 章 + `## 未决问题` section）、调 analysis-reviewer 一次后把报告原文贴 chat，让 PM 三选一（AI 改 / PM 自改 / 接受现状）
   - skill 返回 = **PM 已看过 reviewer 报告原文 + 已显式做出处理决定**；返回值带 `review_outcome ∈ {PASS, ACCEPTED_WITH_ISSUES}`
   - **orchestrator 不重调 reviewer**；如 `review_outcome=ACCEPTED_WITH_ISSUES`，stage-gate 在最终推进确认门加一行知会："⚠️ analysis 评审还有必改条目，但 PM 已显式接受继续推进"——但**不阻塞**推进
   - **写 stage 2 真相源元数据**（A 分支：`analysis.md` + `tool="req-analysis"`）：
     ```bash
     python3 -c "
     import sys; sys.path.insert(0, '$REPO_ROOT/.claude/scripts')
     from _lib.state import set_stage_source
     from pathlib import Path
     set_stage_source(Path('$ACTIVE_REQ_DIR'), 2, 'analysis.md', tool='req-analysis')
     "
     ```

4A. **未决问题闸门**（A 分支硬约束；B 分支由 caller 跳过，**不**动 lint 脚本本身）：

   调用 lint 脚本：

   ```bash
   python3 "$PMAI_HOME/scripts/check-open-questions.py" "$ACTIVE_REQ_DIR/analysis.md"
   ```

   - **退出码 1**（有未答）→ 确认门进入"答题模式"，stdout 给出未答题号 + 行号：
     ```
     Stage 2（需求分析）— analysis 含未决问题

     ✅ analysis.md
        <$ACTIVE_REQ_DIR/analysis.md 绝对路径>

     📋 一句话摘要
        <本次分析的核心结论，一行>

     ⚠️ 留了 <N> 个未决问题需要先回答，推进前必须答完。

     请选择处理方式：
      - 我逐题问你（推荐，答完写回 analysis.md）
      - 你想先改 analysis 某段（请说哪里）
     ```
     **不允许**提供"直接推进"选项——这是硬规则，没有例外也没有 FORCE 逃生舱
   - **退出码 0**（全部已答 / section 写"本 req 无未决问题" / section 不存在）→ 确认门进入"推进模式"：
     ```
     Stage 2（需求分析）— analysis 待确认

     ✅ analysis.md
        <$ACTIVE_REQ_DIR/analysis.md 绝对路径>

     📋 一句话摘要
        <本次分析的核心结论，一行>

     [若 review_outcome=ACCEPTED_WITH_ISSUES 加一行：]
     ⚠️ analysis 评审标了"可以继续但有待改进"，你之前显式接受了，继续推进。

     这版 analysis 内容是否可以定稿？如还有需要调整的内容，请直接说；确认后我会推进到功能规格（Stage 3）。
     ```
     （所有 req 默认都走功能规格阶段，不再提供"跳过"选项）

5A. **PM 回答未决问题的处理**：
   - PM 选"逐题问你"分支后，逐题展示问题，PM 每回答一题，把答案写回 analysis.md 对应 `**PM 回答：**` 后面
   - 所有问题答完 → 重跑 `check-open-questions.py` 验证（退出码 0）→ 解锁推进选项 → 回到步骤 4A 的"推进模式"
   - PM 在答题过程中临时想改 analysis 某段 → 允许中途切到"改 analysis"分支 → 改完后**回到步骤 3A 重调 /pmai-req-analysis**（analysis 改过，reviewer 必须重跑一次；由 /pmai-req-analysis 步骤 4-5 的"调一次 + 三选一"机制保证），再走步骤 4A 闸门

#### 分流 B：YC office-hours 式（snapshot 复制 + 体验包装）

> B 分支**不调 reviewer**（office-hours 自带 Cross-Model Perspective + Spec Review Loop）、**不调未决问题闸门**（office-hours 的 Open Questions prose 不带答题占位）、**不调 attachments hook**（由 attachments 独立设计承接）。
>
> **trigger 0 禁用边界（cross-design 冲突防护）**：B 分支 3B 探测 + 3B-resume + 3B-snapshot 三个子步骤期间 **attachments trigger 0 禁用**。PM 在这几个子步骤里给的绝对路径是 **office-hours 设计稿源材料**，走 `set_stage_source(req_dir, 2, 'stage2-office-hours.md', tool='office-hours', origin=<原绝对路径>)`，**不**调 `copy_attachment` 归档为 attachment。5B 推进确认门 PM OK 后恢复 trigger 0。

3B. **探测 office-hours 产物 + PM 三选一**

   ```bash
   # 取 gstack 项目 slug（与 office-hours skill 产物目录一致）
   # fail-loud：slug 解析失败要明说原因，不能 silent fallback 到 "unknown" 让 PM 误以为"真没产物"
   SLUG=""
   SLUG_ERR=""
   GSTACK_SLUG_BIN="$HOME/.claude/skills/gstack/bin/gstack-slug"
   if [ ! -x "$GSTACK_SLUG_BIN" ]; then
     SLUG_ERR="gstack-slug 命令不存在（路径：$GSTACK_SLUG_BIN）—— gstack 可能未装或路径已变"
   else
     GSTACK_OUT=$("$GSTACK_SLUG_BIN" 2>&1) && eval "$GSTACK_OUT" || true
     if [ -z "${SLUG:-}" ]; then
       SLUG_ERR="gstack-slug 调用失败（stderr: $GSTACK_OUT）—— 本项目可能未在 gstack 注册"
     fi
   fi

   if [ -n "$SLUG" ]; then
     OH_DIR="$HOME/.gstack/projects/$SLUG"
     # 按 mtime 倒序列 office-hours 设计稿（文件名约定：<user>-<branch>-design-<datetime>.md）
     OH_FILES=$(ls -t "$OH_DIR"/*-design-*.md 2>/dev/null || true)
   else
     OH_DIR=""
     OH_FILES=""
   fi
   ```

   **分流三态**（按 `$SLUG_ERR` 和 `$OH_FILES` 拆三种）：

   - **(I) SLUG 解析失败**（`$SLUG_ERR` 非空）→ **不说"没探测到"**（事实不符），直告 PM 探测无法进行：

     ```
     Stage 1 → 2（开放探讨 — 没找到现成的 office-hours 稿）

     ⚠️ 无法定位 gstack 项目目录：
        <SLUG_ERR 原文>

     💬 怎么往下走？
      - 现在跑一份 —— 在本 chat 跑 /office-hours，跑完贴路径给我
      - 我自己指定路径 —— 贴绝对路径过来
      - 换默认的结构化挖透
     ```

   - **(II) SLUG OK + 找到 ≥1 个** → 列文件名 + mtime，问 PM 三选一：

     ```
     Stage 1 → 2（开放探讨 — 选讨论稿）

     📂 找到 N 份 office-hours 稿（按更新时间倒序）：
       1. <filename>  (<mtime ISO>)
       2. ...

     💬 用哪份做这次的讨论稿？
      - 用第 1 份（默认，最新的）
      - 跑一份新的 —— 在本 chat 跑 /office-hours，跑完告诉我新文件名
      - 我自己指定路径 —— 贴绝对路径过来
      - 换默认的结构化挖透
     ```

   - **(III) SLUG OK + 没找到** → 显式告 PM 是真无产物（slug 解析成功）：

     ```
     Stage 1 → 2（开放探讨 — 没现成稿）

     📂 这个项目下还没跑过 office-hours。

     💬 怎么往下走？
      - 现在跑一份 —— 在本 chat 跑 /office-hours，跑完告诉我新文件名（推荐）
      - 我自己指定路径 —— 贴绝对路径过来
      - 换默认的结构化挖透
     ```

   PM 答「换结构化挖透 / 切回结构化批判」→ 回步骤 3A（按 A 分支跑）。
   PM 答「跑新」/「跑 office-hours」→ **进步骤 3B-resume**。
   PM 答「用第 N 份」/「指定路径 <abs>」→ **进步骤 3B-snapshot**（源路径已确定）。

3B-resume. **resume 协议**（PM 中断本 chat 去跑 `/office-hours`，跑完通知 AI）

   AI 输出一句话提示后**保持在 chat 等待**：

   ```
   好的，在本 chat 直接跑 /office-hours，跑完贴一下文件名或绝对路径过来，
   我接着把它接进这个 req 当 Stage 2 的讨论稿。
   ```

   PM 跑完后**任一回话句式 AI 都要接住**（不强求格式）：
   - 给文件名："跑完了，文件名 yourname-req-001-foo-design-20260525-153010.md"
   - 给绝对路径："/Users/.../gstack/projects/<slug>/<file>.md"
   - 只说"跑完了" → AI 自己回到步骤 3B 重新探测（按 mtime 拿到最新一份）

   解析出源路径后续走步骤 3B-snapshot。

   > **PM 关 chat 后续走**：PM 在 resume 等待态关掉 chat 几天后回来 → 重敲 `/pmai-req-stage-gate` → stage-gate 从 `.req-meta.json` 当前 stage 续走（stage 仍是 1，brief 已 commit），重新走步骤 2 选择门即可（office-hours 已跑过的产物在步骤 3B 探测时会被列出来选）。续跑模式自然支持，不需要额外"暂停态"机制。

3B-snapshot. **AI snapshot 复制 + 写元数据**

   1. 校验源路径存在且可读（Read 失败 → 抛错给 PM）：
      ```bash
      test -r "$SRC_PATH" || { echo "源路径不可读：$SRC_PATH"; exit 1; }
      ```

   2. AI 用 Read 工具读源文件**全文**（不要 head/tail/grep 截断 —— snapshot 要 1:1）。

   3. AI 用 Write 工具复制到 `$ACTIVE_REQ_DIR/stage2-office-hours.md`，**顶部追加 snapshot 注释**（caller 自行拼接，源路径 + ISO 时间戳，例）：

      ```markdown
      <!-- snapshot from <源绝对路径> at <ISO-8601 时间戳> -->

      <office-hours 设计稿原文>
      ```

   4. 写 stage 2 真相源元数据（B 分支：`stage2-office-hours.md` + `tool="office-hours"` + `origin=<源绝对路径>`）：

      ```bash
      python3 -c "
      import sys; sys.path.insert(0, '$REPO_ROOT/.claude/scripts')
      from _lib.state import set_stage_source
      from pathlib import Path
      set_stage_source(
          Path('$ACTIVE_REQ_DIR'), 2,
          'stage2-office-hours.md',
          tool='office-hours',
          origin='$SRC_PATH',
      )
      "
      ```

4B. **B 分支 _不_ 跑**：
   - analysis-reviewer（office-hours 自带 Cross-Model Perspective + Spec Review Loop）
   - `check-open-questions.py` 未决问题闸门（office-hours `Open Questions` prose 不带 `**PM 回答：**` 占位；不该让 lint 脚本本身 req-aware）
   - attachments hook（由 attachments 独立设计承接）
   - term-detector hook（业务词催补统一收敛到 `close-req` 步骤 3.4 一处）

5B. **B 分支推进确认门**

   ```
   Stage 2（需求分析）— office-hours 讨论稿已接入

   ✅ 讨论稿
      <$ACTIVE_REQ_DIR/stage2-office-hours.md 绝对路径>

   📂 原始 office-hours 文件
      <$ACTIVE_REQ_DIR/.req-meta.json:stage2_source_origin 原 ~/.gstack/ 绝对路径>

   📋 摘要
      <office-hours 设计稿核心要点，一行>

   这版讨论稿内容是否可以定稿？如要换原始文件请直接说；确认后我会推进到功能规格（Stage 3）。
   ```

   PM 回答的内部分流：
   - PM 说「OK / 通过 / 没问题 / 定了」 → 推进
   - PM 提换原始文件 / 重跑 → 回步骤 3B
   - PM 提改 brief → 回步骤 2 选择门

#### 推进命令（A 或 B 任一确认后执行）

```bash
python3 "$PMAI_HOME/scripts/req-transition.py" "$ACTIVE_REQ_DIR" --to 2
```

> `req-transition.py` 内部走 `_lib.state.get_stage_source(req_dir, current)` helper，按 `.req-meta.json:stage2_source` 解析真相源：A 分支验 `analysis.md` 存在，B 分支验 `stage2-office-hours.md` 存在。

推进成功后**续到 Stage 2 → 3 入口**（默认续跑，参见上文「续跑模式」）。

### Stage 2 → 3（需求分析 → 功能规格）

PM 选择进入 stage 3 时：

1. **调用 `/pmai-prd-writing`（stage-3 orchestrated 模式）**
   - 调用时在 prompt 里明确「stage-3 orchestrated 模式」——这是被 stage-gate 编排的固定 req 级模式，skill 跳过自身开场三选一对话、不走最终确认（详见 `prd-writing/SKILL.md` 的 stage-3 模式段）。
   - skill 内部完成：读 `brief.md` + **stage 2 真相源**（A 分支 `analysis.md` / B 分支 `stage2-office-hours.md`，路径由 `_lib.state.get_stage_source(req_dir, 2)` 解析）+ `docs/PROJECT.md`（+ 已有 `docs/modules/` 如存在），从 stage 2 真相源的功能分解派生 §六 功能需求层级、写 `prd.md`（章节结构按 PRD 9 章 / 11 章不变；§三 名词解释承担本 req 临时词典职责，下游 impl-design / task-spec 必读），写完跑 `check-prd-hierarchy.py` lint，并为本次每条产品决策 append `decision` 事件（业务词向 PROJECT.md 长期沉淀已迁到 `close-req` 步骤 3.4，本步不再跑 detector）
   - skill 返回时 `prd.md` 已落盘、lint 已闭环（详见 `prd-writing/SKILL.md`：lint 在 skill 内闭环，**不**传递给 stage-gate 二次显示）；返回值带本次新增的 `decision` 摘要（备选 / 理由），供步骤 2 确认门一并渲染

2. **输出确认门**（一份完整模板，把产物落地 / 规格要点 / 本次决策摘要 / 可选 review / 确认问句拼成单次输出；不分两轮发）：

   ```
   Stage 3（功能规格）— prd 待确认

   ✅ prd.md 已生成
      <$ACTIVE_REQ_DIR/prd.md 绝对路径>

   📋 本次规格要点
      1. <要点 1，一行业务语言，例：覆盖 X / Y / Z 三个功能模块>
      2. <要点 2，例：验收标准按 N 个用户故事组织>
      3. <要点 3，例：明确非目标——本期不做 W>
      （≤ 2 个要点时可压成 1-2 行；≥ 3 个用有序列表分条；每条只描述业务面内容，不出现内部术语）

   🧭 本次新增决策

      [PM 拍] 你之前已明确给过指示
         1. <决策标题> — 选定 <方案>
         （事件流里 `decided_by=pm-explicit` 的条目；无则本子段省略）

      [AI 推断] AI 在 PRD 写作中自己定的（默认通过；要反对哪条直接说条目号）
         1. <决策标题> — 选定 <方案>；备选 <…>；理由 <一行>
         2. <决策标题> — …
         （事件流里 `decided_by=ai-inferred` 的条目；无则本子段省略）

      （两段都无 / 本 req 无产品决策时整个 🧭 段省略）

   📊 可选 review（你自跑，跑完贴结论我帮你 append 事件）
      /plan-ceo-review     — 战略：范围与产品野心
      /plan-eng-review     — 架构、数据流、边界
      /plan-design-review  — 交互与视觉层问题
      /autoplan            — 上述 plan-* 的批量打包

      跑哪几个你定，全跳也行。

   这版 prd 内容是否可以定稿？如还有需要调整的内容，请直接说；确认后我会推进到设计系统建立（Stage 4）。
   ```

   **模板要点**（v3 书面体）：
   - **顶部 stage 标记**：`Stage N（中文名）— <产物> <状态>` 独占首行（例 `Stage 3（功能规格）— prd 待确认`），PM 一眼知道当前位置
   - 各段标题用 emoji 锚点（✅ / 📋 / 🧭 / 📊）让 PM 视线快速分段
   - 路径独立缩进，不挤标题行
   - **规格要点用有序列表分条**：PRD 内容天然多面（功能模块 / 验收 / 非目标 等），≥ 3 个要点强制用有序列表，每条聚焦一个业务面
   - **🧭 本次新增决策段**：按 `decided_by` **强制分两子段**渲染 —— `[PM 拍]` 段渲染 `decided_by=pm-explicit` 的条目（PM 已在 stage 1/2/3 主动开口拍过，**只列标题 + 选定**，备选 / 理由略，省 PM 阅读量）；`[AI 推断]` 段渲染 `decided_by=ai-inferred` 的条目（AI 在 PRD 写作中自己定的、PM 未单独确认，**列标题 + 选定 + 备选 + 理由**让 PM 一眼判断是否反对）。**两子段标签 `[PM 拍]` `[AI 推断]` 用 PM 可懂语**，**不要**在 PM 视图里出现 `decided_by` / `pm-explicit` / `ai-inferred` 等字段名（仅本 SKILL.md 文档里出现作开发说明）。某子段无条目时该子段省略；两子段都无时整个 🧭 段省略。决策事件由 `/pmai-prd-writing` 内部 append，stage-gate 只负责按 `decided_by` 分段展示
   - **`[AI 推断]` 段的默认通过语义**：PM 不点名反对的条目默认通过（原 `ai-inferred` 事件保留作审计痕迹）；PM 想反对的直接说条目号 + 理由，AI 临场决定修订粒度——只修该条决策（改 PRD §四对应描述 + append 新 `decision` 事件 same `prd_anchor` + `decided_by=pm-explicit` 替代）或返工 `/pmai-prd-writing`。**不另立独立确认门**——这一栏的"默认通过 / 单挑反对"并进 stage 3 定稿确认门，PM 在末段确认问句里一并表达
   - **不显示** 任何 lint / 脚本名 / "进入 stage 3" / "term-detector" 等工程黑话（PM 视角只关心 `prd.md` 主文件 + 下一阶段名称；详见 `task-spec/SKILL.md` 步骤 12 上方禁词清单，本闸门同样适用）
   - **禁止再加 ⚠️ lint 待办 / lint 摘要等"传话块"**：lint 处理已在 `/pmai-prd-writing` 内闭环，PM 在 stage-gate 不需要再看一遍
   - **末段确认问句独占末段**：统一句式「这版 X 内容是否可以定稿？如还有需要调整的内容，请直接说；确认后我会推进到 <下一阶段名>（Stage N）。」**不列 A/B 字母选项**、**不列"放弃"**、**不在问句后追加 brief/prd 预览或动作复述**
   - **反面示例**：
     ```
     ✘ ✅ prd.md 已 lint 通过（"lint" 是内部词，PM 视角整行删；写"已生成"即可）
     ✘ ⚠️ check-prd-hierarchy.py 报 3 处 §六 层级违规，已自动修订
        （lint 处理已在 /pmai-prd-writing 内闭环，PM 视角整段删除）
     ✘ 一句话摘要：覆盖 X / Y / Z + 新增 D10 / D11 + 风险 R4 + 验收 N 项 ...
        （单行塞多个要点 → 改有序列表分条）
     ✘ A) 确认（进入 term-detector + 推进 stage 3） / B) 我要修改 prd
        （A/B 字母选项 + 工程黑话；改对话式问句）
     ✘ ——这份 PRD 就这样定吗？OK 我就把功能规格阶段定下来，进入下一步。
        （v2 旧句式：破折号开头 + "OK 我..."把示范回答嵌入动作。改 v3 统一句式）
     ✘ 〔确认问句之后〕另起一段贴 prd 核心内容预览
        （确认门只给路径 + 摘要，问句后不追加任何东西。需要看全文 PM 自己打开文件 / 让新对话读回 chat）
     ```

   PM 跑完任一 review 后报告结论 → AI 调 `task-events.py append` 记 `plan_review_completed`（task 文件不存在时此处可省略，仅做口述确认）；事件流仅作审计记录，不当 gate（I-RV1/I-RV2）。

3. **PM 回答的内部分流**（chat 不列 A/B 选项；按 PM 自然语言意图）：
   - PM 说「OK / 通过 / 没问题 / 定了」等 → 走"确认"分支：直接跑 `req-transition.py --to 3`
   - PM 提具体修改意见 → 走"修改"分支：回步骤 1 重调 `/pmai-prd-writing`（stage-3 orchestrated 模式，prompt 含 "PM 在确认门提了修改：…"）→ 重新输出步骤 2 完整模板（PM 可决定要不要再跑一遍 review）→ 再次询问
   - PM 说「放弃这个 req / 不做了」 → 走"放弃"分支：提示 PM 跑 `/pmai-cancel-req`（**chat 模板里不主动列出此选项**，PM 主动提才走）

推进（PM 确认后执行）：
```bash
python3 "$PMAI_HOME/scripts/req-transition.py" "$ACTIVE_REQ_DIR" --to 3
```

> **stage 3 只有一个 PM 定稿确认门**——就是步骤 2。`/pmai-prd-writing` 在 stage-3 orchestrated 模式下不出自己的确认门，由本步骤 2 统一兜住。stage 3 不再有 reconcile / 行数 lint / PROJECT 6 节门等额外门或步骤。

推进成功后**续到 Stage 3 → 4 入口**（gap-check + 新组件规格定稿）。

> **旧 req 兼容（文件存在性判别）**：stage 3 涉及校验时按文件存在性判别新旧流程——`solution.md` 存在且 `prd.md` 不存在 → 旧流程（同步前在飞的旧 req，stage 3 产物仍是 `solution.md`，按旧逻辑跑完即可）；否则 → 新流程（要 `prd.md`）。两文件都有（异常态）→ `prd.md` 优先 + 打一行警告给 PM 知会。`req-transition.py` 内部同样按文件存在性判别（归 req-transition.py owner）。

### Stage 3 → 4（功能规格 → 设计系统）

> **PROJECT 6 节强制门已撤掉**（PROJECT 由 `/pmai-project-solution` 产出 + 已有项目走 `/pmai-new-req`
> legacy gate）。stage 3→4 此处直接推进 stage 4。

**stage 4 永远进**—— stage 4 = **必跑 gap-check + 新组件完整规格定稿**
；gap-check 是每 req 的组件复用关口 + 完整规格定稿门，必跑。视觉基线本身在 init C.5 已由 gstack `/design-consultation` 定稿，stage 4 不再嵌视觉基线更新分支。

```bash
python3 "$PMAI_HOME/scripts/req-transition.py" "$ACTIVE_REQ_DIR" --to 4
```

推进成功后**续到 Stage 4 入口**。

### Stage 4（设计系统 —— gap-check 必跑：新组件完整规格定稿）

> **本阶段核心原则**：task 启动前 DESIGN.md 必须是**完整硬约束** —— 视觉基线（gstack 写的 8 段，init C.5 时已定）+ 本 req 新组件的**完整规格**（视觉 / 状态 / 交互 / 边界）。executor 读到的是完整规范，没有"自己看着办"的灰色地带。
>
> **跟之前的差异**：以前 4A 只声明"复用 vs 新建"留占位、close-task 才回填 → executor 跑 task 时 inventory 行视觉字段空着，照样乱搞。现在 4A 必须 **PM + AI 共写完整规格**才进 stage 5。
>
> **砍掉旧 4B（"DESIGN.md 视觉规范更新"分支）**：视觉基线在 init C.5 已由 gstack `/design-consultation` 定稿，req 级一般不动；PM 想改基线 → 任意时机直接调 `/design-consultation`（PM 主动入口），不嵌进 stage 4 流程。

#### 步骤 4A：gap-check + 新组件完整规格定稿（每 req 无条件跑）

> 本质 = 每个 req 一道「逐组件判复用 vs 新建 + 新建组件 PM + AI 共写完整规格」的关口。
> 直接对症 ① 组件不复用 ② executor 在视觉规范不完整的地方乱搞。

1. **前提**：`docs/DESIGN.md` 须含「共享组件 inventory」段（init C.5 已建空段；旧项目兜底由 `/pmai-new-req` 步骤 2B 检测追加）。
2. **读 `prd.md`** 枚举本 req 要建的**界面 / 交互 / 组件**。
3. **逐组件对 inventory 判复用 vs 新建**：
   - inventory 里**有** → **复用**（设计输出指向它）
   - inventory 里**没有** → **新建**，触发下一步组件规格定稿
4. **新组件完整规格定稿子流程**（对每个新建组件，PM + AI 共写）：

   AI 基于 `docs/DESIGN.md` 视觉基线（颜色 / 字体 / 间距 / 动效）+ `prd.md` 描述出**完整规格初稿**，PM 审 + 改，直到拍板。一个新组件规格必须包含：

   ```
   组件：<组件名>
     视觉：<尺寸 / 背景色 / 边框 / 阴影 / 圆角 等，引用 DESIGN.md 视觉基线变量>
     状态：<默认 / hover / 选中 / disabled / 加载中 ... 每个状态视觉差异>
     交互：<鼠标点击 / 键盘操作 / 触发事件>
     边界：<响应式断点 / 无内容时 / 数据极端值 等>
   ```

   PM 拍板后 AI 用 Edit 把完整规格行写进 `docs/DESIGN.md` 共享组件 inventory 表（6 列：组件名 / 用途 / 视觉 / 状态 / 交互 / 出处 req）。

5. **硬度**：**新组件规格未定稿 → 不进 stage 5**。这是关口级强约束，跟 stage 5 5a-gate「结构决策必 PM 拍板」同款硬度。

gap-check 是**交互关口** —— 产物 = PM 在 chat 逐组件表态过程本身 + 完整规格行入 inventory。**不单独落 per-req 文件**。复用决策由 stage 5 `/pmai-implementation-design` 段 2 读 inventory 承接。

#### 步骤 4B：确认门 + 推进

> 旧版"DESIGN.md 视觉规范更新"分支已砍。视觉基线在 init C.5 定，req 级不再嵌入 design-consultation。PM 想改基线任意时机主动调 `/design-consultation`，不走本 SKILL。

**Speed mode 自动续条件**：步骤 4A gap-check **0 个新建组件**（全部复用）→ 直接执行 `req-transition.py --to 5` 推进 + 续 Stage 5；chat 里只出一行过场：

```
Stage 4 OK（组件全部复用 / 本次无新建） → 进 Stage 5 实现设计
```

**有新建组件**（PM 在 4A 期间共写过任何新组件规格）→ 走完整确认门：

```
Stage 4（设计系统）— 待确认

✅ 组件复用关口：复用 X 个 / 新建 Y 个（完整规格已入 DESIGN.md inventory）
   新建组件清单：
    - <组件 1>
    - <组件 2>
    ...

确认后我会推进到实现设计 + task 规划（Stage 5）。
```

PM 确认后推进：

```bash
python3 "$PMAI_HOME/scripts/req-transition.py" "$ACTIVE_REQ_DIR" --to 5
```

推进成功后**续到 Stage 4 → 5 入口**（先 `/pmai-implementation-design`，见下）。

### Stage 4 → 5（→ 实现设计 + task 拆分）

stage 5 内部两步编排：**先 `/pmai-implementation-design`（产 req 级 HOW）→
PM 确认门审架构决策表 → 再 `/pmai-task-plan`（拆 task）**。

#### 步骤 5a：调 `/pmai-implementation-design`

调用 `/pmai-implementation-design` 产出 `$ACTIVE_REQ_DIR/implementation-design.md`（req 级实现设计：
架构决策表 / 文件·模式索引 / 约束与验收 / 审计与修订）。

- **产出失败**（输入缺失 / PRD 未定稿等）→ skill 报告失败原因，**不继续到步骤 5b**；
  PM 修复后重跑 `/pmai-req-stage-gate`。
- 产出成功 → 进步骤 5a-gate。

#### 步骤 5a-gate：implementation-design PM 决策门（speed mode）

`implementation-design.md` 含「这个 req 用什么架构、为什么这么选」的架构决策 —— AI 单方面
定再注入 task 与「PM 在环里」冲突，**必须经 PM 审定才放行**。

**Speed mode 行为**（取代原"全文确认门"）：

1. **扫文件找结构决策行**：
   ```bash
   # 扫段 1 HOW 表：取「决策类型」列 = 「结构」的所有行
   # 扫段 1.5 SIMP 表：取所有 SIMP-NN 行（SIMP 全部视作结构决策，见模板说明）
   # 扫段 3.3 自由度声明表：取所有非「无」行（每条偏离声明全视作结构决策）
   ```

2. **逐行 prompt**（按文件出现顺序：段 1 HOW → 段 1.5 SIMP → 段 3.3 自由度声明）：

   段 1 / 段 1.5 行：
   ```
   🛑 命中结构决策：HOW-NN <一行描述>

   候选：
     A. <选项 1>（AI 倾向）
     B. <选项 2>
     C. <选项 3>

   AI 倾向 A，理由：<段 1「理由」列内容，一行>
   PM 拍板：
   ```

   段 3.3 自由度声明行：
   ```
   🛑 命中自由度偏离：<适用范围>

   AI 提案：<档位>
   理由：<段 3.3「理由」列内容，一行>

   PM 拍板：保留 / 改档位 / 取消本条偏离
   ```

   PM 答一个进下一个；中途答完后调 `req-events.py append decision` 写每行（`decided_by=pm-explicit`），供 stage 6 入口总览复述。

3. **全部答完后**：直接进步骤 5b（不再发原全文确认门）。

4. **无任何结构决策行**（罕见，比如纯机械应用 PRD 已硬约束的 req）：直接进步骤 5b；chat 出一行：
   ```
   Stage 5 实现设计 OK（无需要拍板的架构决策） → 进 task 拆分
   ```

5. **PM 在结构决策门外想改其他段**（如改"段 3.1 易错点"）：允许中途切到 revise 模式 → 回 `/pmai-implementation-design` revise → 改完重扫段 1 / 段 1.5 重出本步骤。

> **兼容老 req**（已存在的 implementation-design.md 没「决策类型」列）：现场逐行推断，默认按结构问（保守）。AI 不强制迁移老文件。

#### 步骤 5b：调 `/pmai-task-plan`

PM 确认 implementation-design 后，调用 `/pmai-task-plan` 拆 task。

推进成功后**续到 Stage 5 → 6 入口**（task-plan 写完后进确认门）。

### Stage 5 → 6（task 规划 → task 执行）

1. 检查 `task-plan.md` 存在。
2. **检查 `implementation-design.md` 存在**—— stage 5 必产 req 级实现设计；
   缺失说明步骤 5a 被跳过 → 报错拦下，提示 PM 回 stage 5 跑 `/pmai-implementation-design`。
   （在飞旧 req 无此文件 → 不拦，按旧流程兼容。）
3. 检查 `task-plan.md` 包含 task 标题列表和 `## 变更记录` section。

4. **Speed mode 行为：task-plan 结构决策门**（取代原全文确认门）：

   - **扫 task-plan.md §一 task 表**：取「决策类型」列 = 「结构」的所有行
   - **逐行 prompt**（按 order 顺序）：
     ```
     🛑 命中结构决策：task-NNN <一行 title>

     候选 / 原因：
       <为什么这个 task 是结构决策 — 合并 / 拆开 / 重排 / 反模式 A 命中>
       AI 的拆法：<本 task 当前归位>
       备选：<不这样拆会怎样 — 一行>

     PM 拍板：保留 AI 拆法 / 改成 <PM 说>
     ```
   - PM 答完所有结构 task → 进 stage 6 入口总览（步骤 5）

   **无任何结构决策行**（task 表全是机械翻 PRD §七 验收项）→ 跳过本步骤 4，直接进步骤 5。

5. **Stage 6 入口总览**（替代原 task-plan 全文确认门）：

   ```bash
   python3 "$PMAI_HOME/scripts/status-view.py" --stage6-entry "$ACTIVE_REQ_DIR"
   ```

   输出格式（status-view 内 render，**PM 单一真相源**）：

   ```
   ═══════════════════════════════════════
   ✅ Stage 4/5 完成，准备进 stage 6 task 执行
   ═══════════════════════════════════════

   【AI 自决 N 件】（机械产出 / PRD 已硬约束）
     HOW-02 <一行选择>
     HOW-03 <一行选择>
     ...

   【PM 拍过 M 件结构决策】
     HOW-01 <一行选定>
     HOW-04 <一行选定>
     ...
     task-001 <拆分理由复述>
     ...

   【task 拆分】
     task-001 <title>
     task-002 <title>
     task-003 <title>
     执行：串行 / 并行（PM 启动建议复述）

   【产物路径】
     <绝对路径>/pmai-implementation-design.md
     <绝对路径>/pmai-task-plan.md
     <绝对路径>/docs/DESIGN.md（本 req <改 / 不改>）

   📊 可选 review（你自跑，跑完贴结论我帮你 append 事件）
     /plan-eng-review     — 拆分合理性、依赖、并行性
     /plan-design-review  — UI task 划分是否完整
     /autoplan            — 上述 plan-* 的批量打包

   下一步：
     ✓ 全部 ok 进 stage 6
     ↺ 我要回看 [HOW-XX / SIMP-XX / task-XXX]
     ✗ 回卷到 stage 4/5 重做
   ```

6. **PM 回答的内部分流**（不列字母；按 PM 自然语言意图）：
   - PM 说「OK / 通过 / 没问题 / 定了 / ✓」→ 推进 stage 6
   - PM 说「回看 HOW-XX / task-XXX」→ AI 给该项详情 + 重新走该项的结构决策门；改完回到步骤 5 重出总览
   - PM 说「回卷 / 回到 stage X」→ 调 `req-transition.py --to <X> --rollback`
   - PM 提具体修改意见 → 回 `/pmai-task-plan` 改 `task-plan.md` → 改完后重新跑步骤 4 + 5

> stage 5→6 入口总览只审阅 `task-plan.md` + `implementation-design.md` 的结构决策项；具体 task 文件由 stage 6 的 `/pmai-task-spec` 逐个生成，写完后由 task-spec 步骤 8 再次输出推荐 review 区块。

推进：
```bash
python3 "$PMAI_HOME/scripts/req-transition.py" "$ACTIVE_REQ_DIR" --to 6
```

推进成功后**stage-gate 退出**（续跑模式 2 条退出条件之一：「推进到 stage 6 成功」）。后续 task 执行由 `/pmai-task-spec` `/pmai-task-execute` `/pmai-close-task` 独立 skill 承担，不属于 stage-gate 推进范围。退出话术按上文「续跑模式 / PM chat 输出格式」。

### Stage 6 → 7（task 执行 → req close）

> **本段是兜底续走入口**：默认情况下，PM 关最后一个 task 时 `/pmai-close-task` 已 in-place 直接出本段步骤 3 的关 req 确认门（不再让 PM 敲一次 `/pmai-req-stage-gate`，省一次输入；详见 `close-task/SKILL.md` 步骤 P2.4 PENDING==0 分支）。本入口保留的唯一作用：PM 在 close-task 关 req 门**不答关窗口**几天后回来重敲 `/pmai-req-stage-gate`，由本段把同一个关 req 门重新拉起，保证关 req 门永远有入口。
>
> **关 req 确认门模板（步骤 3）是单一真相源**，close-task PENDING==0 分支只复述、不另立文案；改本段时一并核对 `close-task/SKILL.md` 步骤 P2.4 复述段是否还匹配。

1. Read `task-plan.md`, extract task id list, and exclude ids marked deleted in the `## 变更记录` section.
   - 变更记录 exclusion algorithm：解析 task-plan.md 文末 `## 变更记录`（如果存在），找到包含关键词 `删除` 的条目，从条目中提取 `task-001` / `task-002` 这类 task-id，并从 verification list 排除。
2. For each id verify:
   - `tasks/task-NNN-*.md` file exists。
   - task status is `「已完成」`。
   - task branch has been merged to req branch（等价于 `/pmai-close-task` 已跑完）。
   - task worktree has been cleaned up。
   <!-- half-close detection 已删：close-task 永不写 SKIP_DOC_UPDATE marker，本检测永远 false。
        Stage 6→7 简化为「merged + worktree cleaned」即可推进；旧 marker 残留由 close-req
        步骤 1.5 rewrite 时 cleanup_status 改 done，本步骤不再扫 marker 不再阻塞。 -->

3. All satisfied → 对话式确认门：

   ```
   Stage 6（task 执行）— 全部 task 已完成

   ✅ 状态
      <N 个 task 全部 close、worktree 全部清理>

   是否确认关闭此需求？如还需开启新的 task，请直接说；确认后我会启动关闭流程（Stage 7）。
   ```

4. Not satisfied → list which tasks are missing which steps。

缺失项输出格式：

```text
Stage 6 → 7 blocked: 以下 task 尚未完整关闭

- task-001:
  - missing task file: 请运行 /pmai-task-spec task-001 完成 spec（或按下方「废弃 task」三步跳过）
- task-002:
  - status is 执行中: 请在 task 窗口完成 PM 验收（task-submit 呈交块）+ /pmai-close-task
  - task branch not merged to req branch: 请运行 /pmai-close-task
- task-003:
  - task worktree still exists: 请确认 /pmai-close-task 清理完成

—— 想跳过某个 task（不再实现）？必须把以下三步**全部跑完**，只跑一两步会留下不一致 metadata：

  1. 移文件：
       mkdir -p tasks/discarded
       mv tasks/task-NNN-*.md tasks/discarded/
  2. 改 task-plan.md：在文末 `## 变更记录` section 加一条 "删除 task-NNN：<一句话理由>"
     （section 不存在就自己新建）
  3. 在被移到 tasks/discarded/ 的 task 文件顶部加一段（close-report 会摘要进「已废弃 task」段）：
       ## 废弃理由
       <一句话理由>

  三步做完后重跑 /pmai-req-stage-gate，verify 会跳过被废弃的 task。
```

边界情况：

- task in task-plan.md but task file not yet generated → judgment fails，prompt PM to run `/pmai-task-spec <task-id>`，**或**按上方「废弃 task」三步跳过。
- Infrastructure tasks → same close requirement；doc-update 会 auto-skips module merge，但仍必须完成 `/pmai-close-task` 的 branch merge 和 worktree cleanup。
- task 文件存在但不在 task-plan.md，且未在 `## 变更记录` 中说明 → 不作为关闭条件来源；提示 PM 校验是否需要补回 task-plan.md 或按「废弃 task」三步删除孤儿 task 文件。

推进：
```bash
python3 "$PMAI_HOME/scripts/req-transition.py" "$ACTIVE_REQ_DIR" --to 7
```

然后调用 `/pmai-close-req`。**`/pmai-close-req` 跑完即 stage-gate 退出**（续跑模式 2 条退出条件之一：「推进到 stage 7 后调完 `/pmai-close-req`」）。

## Rules

- **续跑模式是默认行为**（参见上文「续跑模式」整节）：`req-transition.py --to N` 成功后默认续到下一 stage 入口，PM 一次 `/pmai-req-stage-gate` 启动后无需再敲命令直到撞退出条件。**退出条件只有 2 条**（推进到 stage 6 / 推进到 stage 7 后调完 close-req），不允许在 stage 之间插入"PM 请再跑一次 /pmai-req-stage-gate" 这种 handoff 文案——这种文案是 v3.5 之前的旧行为，本规则上线后视为违例
- **stage 之间不发独立"已推进"通知**：续跑到下一 stage 时直接进入第一个动作 / 闸门 / 确认门，不在中间发"✅ Stage 已推进 N→N+1。下一步进入 stage M→M+1"这种过渡段（旧 chat 让 PM 体感"我又要敲一次"，且续跑模式下根本不需要敲命令）。只在 stage-gate **退出**时按上文「PM chat 输出格式」发一次终止通知
- **不写 PM 喊停识别**：PM 在确认门不答就是停（chat 天然行为），不要在 SKILL.md 加"喊停关键词识别"、不要发"已暂停"通知。PM 关窗口几天后回来重敲 `/pmai-req-stage-gate` 自然从当前 stage 续走，不需要"暂停态"概念
- 每个 stage 结束必须显式问 PM 确认，不能自动跳过确认门
- **确认门只给绝对路径 + 一句话变更摘要，不贴文档全文。** PM 的 IDE 已经挂在 worktree 上，文件在左侧目录树里可见，不需要把内容贴回 chat
- **确认门标准格式**（v3 书面体）：
  - **顶部 stage 标记独占首行**：`Stage N（中文名）— <产物> <状态>`（例 `Stage 3（功能规格）— prd 待确认`、`Stage 4（设计系统）— 组件规格待确认`）
  - emoji 锚点分段（✅ 路径 / 📋 摘要 / 🧭 决策 / 📊 可选 review）
  - 路径独立缩进，不挤标题行
  - **末段确认问句独占末段**，统一句式：「这版 X 内容是否可以定稿？如还有需要调整的内容，请直接说；确认后我会推进到 <下一阶段名>（Stage N）。」（关闭门变体：「是否确认关闭此需求？如还需开启新的 task，请直接说；确认后我会启动关闭流程（Stage 7）。」）
  - **禁**：A/B 字母选项；"——"破折号开头；"OK 我..."把示范回答嵌入动作描述；问句后追加 brief/prd 预览或动作复述
  - **不主动列"放弃 req"选项**（PM 真要放弃直接说「放弃这个 req / cancel」，AI 提示走 `/pmai-cancel-req`）
- **PM chat 输出禁工程黑话**（与 `task-spec/SKILL.md` 步骤 12 上方禁词清单等价）：所有 stage 的确认门 / 任何给 PM 看的 chat 文本里**严禁**出现 `hash` / 12 位 hash 值 / `lint` / `check-prd-hierarchy` / `term-detector` / `步骤 N.M` 内部编号 等内部状态机 / 脚本术语。这些都是 AI 内部记账，PM 没有动作可做。**用"已生成"/"已更新"替代"已 lint 通过"**
- **摘要 ≥ 3 个要点用有序列表分条**：所有 stage 的 📋 摘要段，当要点超过 2 个时强制用有序列表（`1.` / `2.` / ...）分条展示，每条一行业务语言；不允许塞成单行长串
- **review 工具一律 PM 自跑**（I-RV1）：stage-gate 在产物写完后只输出推荐清单，不自动调任何 `/plan-*-review` / `/review` / `/qa` / `/design-review`。PM 跑完任一 review 后口述结论，AI 调 `task-events.py append` 机械记录事件作为审计痕迹；事件流不当 gate
- **stage 3 单确认门**：stage 2→3 的 `/pmai-prd-writing` 在 stage-3 orchestrated 模式下不出自己的确认门，stage 3 只保留 stage-gate 步骤 2 一个 PM 定稿确认门；该确认门同时渲染本次新增 `decision` 摘要（备选 / 理由）供 PM 一并确认，不另立决策确认门
- review 结果（PM 跑完贴回 chat 的）允许直接贴 chat——review 是讨论内容，不是文档产出
- **未决问题闸门（硬规则）**：任何 stage 的产出文档如果含有"需要 PM 回答"的未决项，确认门必须先让 PM 答完再开放推进选项。不允许并列给出"直接推进"和"回答问题"两个选项让 PM 选——这会让 PM 绕过未回答的问题。机器校验由 `scripts/check-open-questions.py` 承担：扫 `## 未决问题` section 下的 `**PM 回答：**` 占位，任一未填 → 退出 1。目前最严格落地在 Stage 1→2（analysis.md），其他 stage 如有类似未决产出 section 直接复用本脚本
- 推进命令只能用 `req-transition.py`，不能手动改 `.req-meta.json`
- Stage 4 的 DESIGN.md 内容检测（inventory 段是否存在 / 新建组件规格是否完整）由 `req-transition.py` 自动处理
- 回退场景：PM 说要回到之前的 stage 时，使用 `--rollback` 参数
  ```bash
  python3 "$PMAI_HOME/scripts/req-transition.py" "$ACTIVE_REQ_DIR" --to <target> --rollback
  ```
