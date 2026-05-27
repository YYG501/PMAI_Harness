# close-task 优化设计

讨论日期：2026-05-08
背景：PM 在实际项目（ExampleConsumerApp / req-003）跑完 task-002 验收通过后，在 req 窗口跑 /pmai-close-task 流程过长 + token 消耗大（38 分钟 + 60k token）。

---

## 0. 修订记录

### 0.1 2026-05-08 CEO 双视角 review（autoplan Phase 1）

跑 Claude subagent + Codex 双视角，CEO consensus table 6 维度中 **5 维度 CONFIRMED critical**：

| 维度 | 共识 |
|---|---|
| 1. Premises 站得住？ | CONFIRMED N — P2/P3 关于 commit 22146458 的来源 + task-001 close 成功原因都未验证 |
| 2. 框定的是对的问题？ | CONFIRMED N — I-CT8 audit 是 band-aid，根问题是"状态字段、事件流、commit"不在同一事务里 |
| 3. Scope 排序对？ | CONFIRMED N — R1（半 close 闭环）影响系统级信任破产，应排 #1，不是 #2 |
| 4. Alternatives 探索充分？ | CONFIRMED N — 原 §3 缺 0C-bis 对比表，A2/A3/A4 没认真评估 |
| 5. Implementation 依赖站得住？ | CONFIRMED N（codex 实查 repo） — `/pmai-doc-update --rewrite` flag **不存在**，doc-update SKILL 只有对账模式 + 沉淀模式；R1 原方案架在空气上 |
| 6. 6-month trajectory？ | CONFIRMED N — file-name allowlist 是 roach motel，每加一种元信息文件类型就要扩白名单 |

**关键失实**（必须重写）：

- 原 §3.1 杠杆 A 用 `task md + engineering md` file-name allowlist 做豁免，6 个月内会因为新增元信息文件（`.req-meta.json` / review 记录 / runtime marker）反复扩白名单。**应改用 commit subject / lifecycle event 类型做豁免依据**。
- 原 §4.1 R1 引用 `/pmai-doc-update --rewrite` flag，**该 flag 不存在**。doc-update SKILL 步骤 0.5 写明"由 close-req 阶段聚合所有 SKIP marker 后统一 rewrite"是意图但**实现层没写**。R1 必须先在 doc-update SKILL 里加 rewrite mode，或改用别的实现路径。
- 原 §6 优先级 杠杆 A > R1 错——按双视角共识 R1 应排 #1（系统级信任修复），杠杆 A 可以作为 hotfix 但 roadmap 优先级低于 R1。

### 0.2 2026-05-08 P2 / P3 验证结果（在 example-consumer-app 主仓跑）

**P2 验证 PASS**：

```text
commit 22146458 (task 分支独有)
Author: YYG501 | Date: 2026-05-07 18:53:39 +0800
Subject: task-002: switch executor to codex / gpt-5.4 (per PM at task-confirm)
Files: tasks/task-002-tab2-user-grant.engineering.md (only) — 改 4 字段 executor/model/port

孪生 commit 37ae47a (req 分支独有)，差 4 秒：
Subject: task-002: switch executor to codex / gpt-5.4 (sync from task-confirm)

两者 merge-base = cb03a36 (PM 视图 + 工程合同生成 commit)
```

**关键真相（plan §2.1 没识别）**：task-confirm step 3 切 executor 时**双向 commit** — 同时在 task 分支（22146458 "per PM at task-confirm"）和 req 分支（37ae47a "sync from task-confirm"）各 commit 一次。`skills/task-confirm/SKILL.md` 步骤 3（L121-135）只描述 sed 改字段，**完全漏写**这个双 commit 行为。

audit 跑 `req..task` 看到 22146458（task 分支独有）→ 触发 I-CT8。

**P3 修订**：

I-CT8 加入时间 2026-04-23（commit 476bc75），task-001 close 时间 2026-05-06，**audit 已启用 13 天**。task-001 close 成功不是"audit 后来加的"——是 **task-001 没切 executor**（没产生 task-confirm 阶段的元信息 commit）→ 没撞 I-CT8。

**结论**：task-002 是首个 PM 主动切 executor 的 task，是 **first-time edge case**，不是回归。

**对方案的影响**：

1. **A1 file-name allowlist 在当前 case 实际可以覆盖**：22146458 改动文件 only `task-002-tab2-user-grant.engineering.md`，命中 allowlist。所以 A1 是**立即可用 hotfix**。
2. **A2 subject prefix 仍有长期价值**：CEO review #6（roach motel）依然成立——未来增加新元信息文件类型时仍会扩 allowlist。
3. **新发现**：task-confirm 步骤 3 SKILL.md 漏写双向 commit 行为——这是文档缺口本身，单独 patch（小改动 5 分钟）。

**调整后的修复路线**：

- **立即**（hotfix）：A1 加 file-name allowlist 豁免 → close-task.sh 不再撞 I-CT8（解 38m + 60k token 燃眉）
- **2-4 周内**（重构）：A2 commit subject prefix 改造，3 处脚本统一约定 → 替代 A1 → 删 A1 file-name 逻辑
- **顺手**：补 task-confirm SKILL.md 步骤 3 双向 commit 行为描述

下面 §3.1 已基于此调整：A1 + A2 双轨方案。

下面 §3 / §4.1 / §6 已基于 review 共识重写。原 §1 / §2（问题描述 + 根因）保留。

---

## 1. 问题（实际经历原文）

### 1.1 验收通过后 task-execute 输出的提示文案

来自 `skills/task-execute/SKILL.md` 步骤 12「PM 说通过」path（同样路径在 `skills/task-submit/SKILL.md` §4）：

```
验收通过

  Committed c54a05, ran 4 shell commands

✅ task-002 状态已转「已完成」，10 commit 全部 clean。

下一步：关闭本（task）窗口，切到 req 窗口运行：
  /pmai-close-task task-002

理由：close-task 会删本窗口的 task worktree，必须在 req 窗口（不会"删自己脚下"）执行。
close-task 会做：
  - 对账 task PM 视图 + 工程合同 vs 项目级文档（doc-update 模式）
  - merge task 分支到 req 分支
  - 杀 dev server (PID 在 task worktree 里)
  - 删 task worktree
  - 归档 .runs/ 状态

dev server (port 6959) 保持运行直到 close-task。
```

PM 反馈：太啰嗦——「理由 / close-task 会做 / dev server 状态」是 close-task skill 内部知识，不应该在调用前提示里复读。

### 1.2 进 req 窗口跑 /pmai-close-task 后的实际流程

PM 实测原文：

> 我需要先消化当前状态：req worktree 里有一处针对 task-002-tab2-user-grant.md 的过期未提交改动（把状态从「待确认」改成「执行中」），但 task worktree 的 task md 已经是「已完成」（且事件流也已记录 status_changed → 已完成）。这处 dirty 改动是早期状态机更新留下的遗留，会让 close-task.sh 在「req worktree 必须 clean」处被拦下，且最终会被 task 分支版本覆盖。我先把它丢弃，然后按 close-task workflow 顺序走。
>
>   Ran 2 shell commands
>
> Step 0: task md ↔ 原型对齐
>
> 读 task worktree 的 PM 视图主文件 + 改动文件 page.tsx，做语义对齐扫描。
>
>   Read 2 files, ran 6 shell commands
>
> 步骤 0 扫描发现 2 处 §📐/任务卡过期描述（task md 没跟上代码 + PM 反馈 #1/#4 已落实但任务卡/§📐 ASCII 残留旧文案）：
>
> | # | task md 行号 | 现状 | 实际原型 | 类型 |
> |---|---|---|---|---|
> | 1 | L 14, L 127, L 131 | 「跟随失效状态」筛选项 | 代码 line 2194-2196 用「访问状态」（PM 反馈 #1 已确认改名） | Y - 改 task md 对齐代码 |
> | 2 | L 14 | 「点击列表行触发」Drawer | 代码 line 2274-2280 用行末 [查看详情] 按钮（PM 反馈 #4 决策 #5 反转） | Y - 改 task md 对齐代码 |
>
> 两处差异都已被 PM 反馈 #1/#4 明确批准，仅是 §📐 + 任务卡概述没跟着同步更新。我直接 patch 两处，然后在 task 分支 commit。
>
> [patch 3 处 + commit b33ab6e]
>
> Step 1: 文档偏差检查
>
> 读 PM 视图 §历史档案 → 业务层偏差表 + 工程合同 §10 文档偏差表。
>
>   Read 1 file
>
> 步骤 1 发现两处文档偏差：
>
> 业务层偏差（PM 视图历史档案）：
> - docs/modules/租户平台/产品访问管理/functions-v4.1.md §16/§17/§18：Drawer 触发入口从「行点击」→「行末 [查看详情] 按钮」（PM 反馈 #4 决策 #5 反转）
> - 同上文件：列表「来源部门额度池」+「来源许可证」两列 → 合并单列「来源」（PM 反馈 #1）
>
> 工程层偏差（engineering.md §10）：
> - docs/DESIGN.md §11.1 弹窗结构 padding/rounded/footer 与 shadcn primitive 默认值不一致 — 备注「本 task 范围不改，留给项目级 Dialog primitive 重构」
>
> 参考 task-001 close 历史是用 --skip-doc-update 半关（commit 5cc676e）。task-002 的偏差更偏「业务规则文档需要沉淀」，让 PM 决定。
>
> [PM 选 --skip-doc-update 半 close]
>
> [写 SKIP_DOC_UPDATE marker + cleanup TODO，commit 1ec59f]
>
> Step 1.5: 视觉规范反馈 → DESIGN.md
>
> 扫描 task-002 PM 反馈中分类含「视觉规范」的条目。
>
>   Read 1 file, ran 4 shell commands
>
> PM 反馈分类全部为「决策记录 / 反向约束 / 正向规则」，无明确标记为「视觉规范」的反馈条目。N=0，跳过 step 1.5。
>
> Step 2: 执行 close-task.sh
>
> 但 close-task.sh 假设 req worktree 在 $REPO_ROOT/.worktrees/<req-branch>，而实际在 <LOCAL_HOME>/.superset/worktrees/<uuid>/req-003-...（Conductor / Superset 模式）。我先确认 close-task.sh 能否在这个非标布局下正确运行——预期会在「req worktree 不存在」检查处 fail-fast。
>
>   Listed 1 directory, ran 1 shell command
>
> 我用 symlink 让 close-task.sh 把符合预期路径解析到实际的 .superset worktree。这种方式 reversible / 不改 git 状态。
>
> [Reading 4 files, running 17 shell commands…]
>
> · 执行 close-task.sh… (18m 52s · ↑ 59.8k tokens · almost done thinking)
> · 执行 close-task.sh… (19m 47s · ↓ 62.8k tokens)
> ✔ step 0: task md ↔ 原型对齐
> ✔ step 1: 文档偏差检查
> ✔ step 1.5: 视觉规范反馈→DESIGN.md
> ◼ step 2: 执行 close-task.sh

### 1.3 卡住的根因（PM 现场诊断）

> close-task.sh 在 I-CT8 审计层卡住：commit 22146458（task-confirm 时切换 executor 的工程合同改动，仅改 executor 字段）的提交时间戳 2026-05-07T10:53:39Z 早于事件流里第一次 *→执行中（2026-05-07T12:15:30Z），约 1.5 小时前。
>
> 这是框架层 task-confirm 没有自动写入对应 status 事件造成的「事件缺失」（task-001 同模式但 close 成功——可能事件流当时被 framework 写过额外的早期 transition 事件）。Close-task workflow 错误消息明确建议「补齐缺失事件再重跑 close-task」。

### 1.4 关键观察（修方向时不要混淆）

- **38 分钟 + 60k token 烧在 step 2 卡住后 AI 尝试补齐缺失事件**（"Reading 4 files, running 17 shell commands"），不是 step 0 / 1 / 1.5
- step 0 / 1 / 1.5 单独的 token 消耗 5-10k 每次，是次要痛点
- step 0 / 1 / 1.5 在贴的实际数据里都打 ✔，step 2 才是 ◼
- task-001 同模式但 close 成功——证明这不是 task-002 的偶发，而是 task-002 触发了某个回归

---

## 2. 根因分析

### 2.1 根因 1（基础设施层，最大）：I-CT8 audit 不区分元信息 commit

**位置**：`scripts/audit-task-events.py:159-181`

**当前实现**：

```python
def audit_ct8(events, task_branch, req_branch):
    earliest = first_transition_to_executing_time(events)
    commits = task_branch_commits(task_branch, req_branch)
    if not commits or earliest is None:
        return violations
    for sha, ts, subject in commits:
        if ts < earliest:
            violations.append(
                f"I-CT8: commit {sha[:8]} ({ts.isoformat()}) 早于首次 status_changed(*→执行中) "
                f"({earliest.isoformat()})。说明代码在状态机推进前就已写入。subject: {subject}"
            )
    return violations
```

I-CT8 的本意（INVARIANTS.md）："代码不能在状态机推进前写入"。但当前实现一刀切——所有 commit 都按"代码 commit"判定，不区分元信息 commit。

**task-confirm 必然在 *→执行中 之前产生 commit**：

1. `skills/task-confirm/SKILL.md:121-135` 步骤 3：PM 切换 executor → sed 改 task md 的 `**executor：**` / `**executor_model：**` 字段
2. `scripts/create-task-worktree.sh:117-118`：fork task 分支后，在 req 分支 `git rm task md` + commit `"task-NNN: move task md to task branch (v4.5)"`

这些 commit 都是元信息（executor 字段 / task md 文件移动），**不是业务代码**，但 I-CT8 拒绝它们。

**task-001 当时 close 成功**：可能事件流被手动补齐，或 audit-task-events.py 加 I-CT8 之前就 close 了。代码没动 → task-002 同模式必然撞 → 这是设计漏洞，不是个例 bug。

### 2.2 根因 2（流程层）：close-task §0 / §1 / §1.5 在 v2 重做场景几乎是空跑

**证据**：
- task-001 → `--skip-doc-update` 半 close
- task-002 → `--skip-doc-update` 半 close（同 reason）
- task-003 / 004 预计同样
- §1.5 N=0 跳过

v2 重做的 4 个 task 全走半 close，文档沉淀**统一推到 close-req 阶段**。close-task §0 / §1 / §1.5 在这个场景里是纯开销——扫一遍只为发现"没什么要做的"或"决议跳过"。这不是个例，是 v2 重做的**默认形态**。

§0 token 大户：
- `Read page.tsx`（task 改动文件全文）：~30k token
- `Read task md`（PM 视图主文件全文）：~10k token
- `Read DESIGN.md`（步骤 1.5）：~5k token
- 加起来一次 close-task 烧 5-10k token（PM 体感 2-5 分钟）

### 2.3 独立小坑

| # | 坑 | 位置 | 关联 |
|---|---|---|---|
| C1 | req worktree dirty（task-transition.py 改状态字段没 commit） | `scripts/task-transition.py:280-307` | 不阻塞 close-task 但每次都要 PM 处理 |
| C2 | Conductor / Superset 路径硬编码 | `scripts/close-task.sh:137-142` | 当前用 symlink workaround |
| C3 | 验收通过文案啰嗦 | `skills/task-execute/SKILL.md` L878-885 + `skills/task-submit/SKILL.md` L181-186 | 5 行可砍到 1 行 |

---

## 3. 修复方案

### 3.1 杠杆 A：I-CT8 audit 漏洞修复（重写后）

#### 0C-bis Alternatives 对比

| 方案 | 实现路径 | 优点 | 缺点 |
|---|---|---|---|
| **A1**（原 plan）file-name allowlist | git show --name-only 看 commit 文件，全是 `task md + engineering md` 才豁免 | 改动小（12 行） | **roach motel**：新增 `.req-meta.json` / review 记录 / runtime marker 后要持续扩白名单；6 个月内必然反复改 |
| **A2**（推荐）commit subject prefix | task-confirm / create-task-worktree / task-execute 元信息 commit 用约定 subject（如 `task-NNN: meta:` / `task-NNN: lifecycle:`），audit 按 subject prefix 豁免 | 元信息意图显式表达；新增元信息文件类型时不需要改 audit；commit log 自带审计 origin | 要改 3 个 commit 来源的脚本统一 subject 约定 |
| **A3** 推迟元信息 commit | task-confirm 步骤 3 切 executor 不立即 commit；create-task-worktree.sh 不 commit；都推迟到 task-execute 第一次 commit 一起 | 治本：`*→执行中` 之前没有 task 分支 commit，I-CT8 自然不撞 | 改动面大，task-execute 入口要做 deferred-merge 逻辑；状态机一致性变复杂；create-task-worktree.sh 跨 worktree 协调 |
| **A4** 删 I-CT8 | 直接删 audit_ct8 + 关联测试 | 0 维护成本；如果 I-CT8 从未在 solo PM workflow 拦下真实 bug，invariant 是 theatrical | 失去"代码不能在状态机推进前写入"审计；P3（task-001 close 成功）回归保护没了 |

#### 推荐：A1 hotfix → A2 重构（双轨）

§0.2 P2 验证发现 22146458 改动仅触动 `engineering.md`，**A1 file-name allowlist 在当前 case 实际命中**。所以路径调整为：

**Phase 1（立即，hotfix）：A1 file-name allowlist**

- 改动 ~12 行 `audit-task-events.py`
- 立即解锁 task-002 close-task（实际已 close，但下次同 case 不再撞）
- 同时立即可让 task-003 / 004 后续 close 走通
- 不依赖任何脚本约定改造

**Phase 2（2-4 周内，重构）：A2 commit subject prefix**

- 改 3 处脚本（task-confirm 切 executor 的 commit / create-task-worktree.sh / 任何其他元信息 commit）统一 subject 约定 `task-NNN: meta:...`
- audit 改成 subject prefix 检测
- 删 A1 file-name allowlist 逻辑
- 配套补 task-confirm SKILL.md 步骤 3 漏写的"双向 commit"行为描述

**为何不直接跳到 A2**：A1 是 12 行简单改动，立即可用；A2 改动面 3 脚本 + audit + 测试 + SKILL 文档，需要更长时间。先 A1 解燃眉，再 A2 治本。

**A2 仍要做的理由（CEO review #6 共识）**：

- **稳健性**：subject 约定一旦立下，新增元信息文件不需要改 audit
- **审计 origin 显式**：commit log 自己说"我是 lifecycle 操作"，不需要事后 file-list 推断
- **可扩展**：未来加 metadata_changed 事件时 audit 可以 cross-check subject 与事件流

#### A1 实现草稿（Phase 1 hotfix，立即）

加 ~12 行到 `scripts/audit-task-events.py`：

```python
def commit_only_touches_task_docs(sha: str, task_stem: str, repo_root: Path) -> bool:
    """True if commit only modifies the task md / engineering md."""
    try:
        out = subprocess.check_output(
            ["git", "-C", str(repo_root), "show", "--name-only", "--format=", sha],
            text=True
        )
    except subprocess.CalledProcessError:
        return False
    files = [f.strip() for f in out.split("\n") if f.strip()]
    if not files:
        return False
    allowed_basenames = {f"{task_stem}.md", f"{task_stem}.engineering.md"}
    return all(Path(f).name in allowed_basenames for f in files)
```

`audit_ct8` 加 `task_stem` + `repo_root` 参数，循环里：

```python
for sha, ts, subject in commits:
    if ts < earliest:
        if commit_only_touches_task_docs(sha, task_stem, repo_root):
            continue   # A1 hotfix: 纯 task md / engineering 元信息 commit 豁免
        violations.append(...)
```

`main()` 调用时传 `task_file.stem` + 推导 `repo_root`。

**测试用例（Phase 1）**：
1. 纯 engineering.md commit（22146458 case）早于 *→执行中 → pass
2. 纯 task md commit（status 修改）早于 *→执行中 → pass
3. 混合 commit（task md + page.tsx）早于 *→执行中 → fail（保留 I-CT8 原意）
4. 现有 task-001 / 002 事件流回归 → pass

**Phase 1 收益**：
- close-task.sh 直接过 audit，38 分钟卡死消失，60k token 浪费消失
- task-003 / 004 后续 close 不再撞
- 改动面极小（audit-task-events.py + tests），不动任何 SKILL.md / 其他脚本

#### A2 重构（Phase 2，2-4 周）— 上方 Step 1-4 草稿

§0.2 调整后，A2 仍然按 `Step 1 约定 subject prefix → Step 2 audit 改 → Step 3 测试 → Step 4 迁移` 路径走，但 **Step 0 验证已完成（见 §0.2），可以删除**。Phase 2 落地后删 A1 file-name 逻辑。

#### A2 实现草稿

**Step 0（前置必做）：验证 commit 22146458 实际来源**

```bash
git -C <task-002-worktree> show 22146458 --stat   # 看 commit 改了什么
git -C <task-002-worktree> log audit-task-events.py --all   # I-CT8 加入时间，确认 task-001 close 时是否存在
```

如果 22146458 实际是 task-execute 阶段的 commit（不是 task-confirm），方案要扩展 subject prefix 覆盖范围。

**Step 1：约定 subject prefix**

| 来源 | Subject 模板 |
|---|---|
| `create-task-worktree.sh` 现有 commit | 改成 `task-NNN: meta:move task md to task branch (v4.5)` |
| `task-confirm` 步骤 3 切 executor（如果实际有 commit） | `task-NNN: meta:switch executor to <X>` |
| `task-execute` 入口字段回填（worktree path / dev server port） | `task-NNN: meta:backfill runtime fields` |
| 任何其他元信息 commit | `task-NNN: meta:<short desc>` |

约束：subject 必须以 `task-NNN: meta:` 或 `task-NNN: lifecycle:` 开头。

**Step 2：`audit-task-events.py` 加豁免**

```python
META_SUBJECT_RE = re.compile(r'^task-\d+:\s*(meta|lifecycle):', re.IGNORECASE)

def is_metadata_commit(subject: str) -> bool:
    return bool(META_SUBJECT_RE.match(subject))


# audit_ct8 循环里：
for sha, ts, subject in commits:
    if ts < earliest:
        if is_metadata_commit(subject):
            continue   # 豁免：subject 显式声明 meta/lifecycle 操作
        violations.append(
            f"I-CT8: commit {sha[:8]} ({ts.isoformat()}) 早于首次 *→执行中 事件 "
            f"且 subject 不是 meta/lifecycle 类型。subject: {subject}"
        )
```

**Step 3：测试用例（5 个）**

1. 纯元信息 commit（subject `task-002: meta:move task md...`）早于 *→执行中 → pass
2. 代码 commit（subject `task-002: implement Tab 2 grant flow`）早于 *→执行中 → fail（保留 I-CT8 原意）
3. 混合：subject meta 但实际改了 page.tsx → 决策：以 subject 为准（A2 哲学）；如果担心 silent regression 加 strict mode（subject 必须匹配 + diff 必须不含 src/ 路径）
4. 现有 task-001 / 002 事件流回归 → pass（保证升级不破坏历史）
5. 无 *→执行中 事件 → I-CT8 silent skip（保留现行行为）

**Step 4：迁移**

- 改 `create-task-worktree.sh` L118 的 commit message 加 `meta:` 前缀
- task-confirm SKILL.md 步骤 3 / task-execute SKILL.md 入口步骤如果有元信息 commit，统一加前缀
- 老 task（task-001 close 时的 commit）不动——audit 看不到老 task（已经 close）

**收益**：
- close-task.sh 直接过 audit
- 38 分钟卡死消失，60k token 浪费消失
- 新增元信息 commit 类型时不需要改 audit（subject 约定自然覆盖）
- commit log 自带 lifecycle origin（未来 review / debug 友好）

**vs A1（原 plan）的 trade-off**：A2 改动面 ~30 行（含 3 处 subject 修改 + audit 修改），A1 ~12 行。多花 18 行换长期稳健（不再 file-name 追逐）。

#### 不选 A3 / A4 的理由

- **A3** 治本但改动面 task-execute / create-task-worktree / state machine 三处耦合，A1/A2 hotfix 之后再考虑
- **A4** 删 I-CT8 应在收集 N 个 close-task 数据后决定（如果 I-CT8 从未拦下真实 bug，再 A4）

### 3.2 杠杆 B（次大）：close-task §0 / §1 / §1.5 在半 close 场景早退

修 `skills/close-task/SKILL.md` 步骤 0 / 1 / 1.5，加早退判断：

| Step | 早退条件 | 原内容 |
|---|---|---|
| §0 task md ↔ 原型对齐 | 「📁 历史档案 → 执行日志」最新执行报告含「**文档对齐预告：** 无」 → 跳过；含具体段名 → 只对预告段做局部对齐，不全文 Read 兜底 | 当前是 token 大户 |
| §1 文档偏差检查 | engineering.md §10 含 `SKIP_DOC_UPDATE` marker → §1 早退（PM 已经决定跳过对账） | v2 重做场景默认走这条 |
| §1.5 视觉规范沉淀 | PM 反馈无「视觉规范」分类 → 早退（已部分实现，进一步降低扫描成本） | N=0 时已跳过 |

**配套**：

- `skills/task-execute/SKILL.md` §反馈循环规则（L599-626）的「文档对齐预告」字段（L648-651）从"建议填"升级为"硬约束"——commit 前 grep 校验执行报告含「文档对齐预告：」字段非空（无影响时填"无"）。
- close-task §0 不再"全量扫一遍兜底"（SKILL.md L102 移除「**覆盖**：四个段全量扫一遍兜底」）。

**收益**：
- 每个 task close 节省 5-10k token + 几分钟
- v2 重做场景下 close-task workflow 退化成"按预告 patch + 跳过对账 + close-task.sh"

**风险**：
- 如果 AI 没认真填预告，对齐遗漏会留到 close-req 阶段才被发现。但 close-req 本来就是 v2 重做场景的对齐汇总点，不是新增风险。
- 反馈循环规则要保持"AI 必须填预告"——如果 AI 偷懒填"无"但实际有改动，会有 silent drift。需要 task-submit 阶段加一条 sanity check：本轮 commit 改了文件 + 预告填"无" → 给 PM 提示。

### 3.3 独立修复

#### C1：req worktree dirty（task-transition.py 状态修改没 commit）

**位置**：`scripts/task-transition.py:280-307` `do_transition()`

当前：改状态字段 + append 事件（伪事务），但不 commit。改动留在 working tree。

**修复方向**（待确认）：
- 选项 1：do_transition 末尾自动 commit（`git add <task-file> && git commit -m "task-NNN: status N→M"`）。代价：commit 数膨胀，每个状态转换一个 commit。
- 选项 2：状态字段改在 task worktree 而不是 req worktree。代价：跨 worktree 协调复杂。
- 选项 3：保持现状但 close-task 自动 reset dirty 改动（已被 task 分支版本覆盖）。代价：close-task 帮忙做"丢弃 PM 没做完的事"，违反"close-task 不蜕变"原则。

**当前讨论倾向**：选项 1，但要先看 `task_changed` 事件流跟 commit 数是否还有别的耦合。**待独立查**。

#### C2：Conductor / Superset 路径硬编码

**位置**：`scripts/close-task.sh:137-142`

```bash
REQ_WORKTREE="$REPO_ROOT/.worktrees/$REQ_BRANCH"
if [ ! -d "$REQ_WORKTREE" ]; then
  echo "❌ req worktree 不存在: ${REQ_WORKTREE}。"
  ...
fi
```

**修复方向**：用 `git worktree list --porcelain` 解析当前 req 分支对应的实际 worktree 路径，不假设 `.worktrees/<branch>` 布局：

```bash
REQ_WORKTREE=$(git worktree list --porcelain | awk -v branch="$REQ_BRANCH" '
  /^worktree / { wt=$2 }
  /^branch refs\/heads\// {
    split($2, parts, "/")
    if (parts[3] == branch) print wt
  }')
```

兼容 Conductor / Superset 把 worktree 放在 `~/.superset/worktrees/<uuid>/<branch>` 的布局。

#### C3：验收通过文案

`skills/task-execute/SKILL.md` L878-885 + `skills/task-submit/SKILL.md` L181-186 改成：

```text
✅ task-NNN 已完成。到 req 窗口跑 /pmai-close-task task-NNN。
```

理由 / 子步骤 / dev server 状态 close-task skill 自己有，调用前不复读。

---

## 4. close-req 同源问题（同步发现）

读完 `skills/close-req/SKILL.md` + `scripts/close-req.sh` + `scripts/req-transition.py` 后类比 close-task 的两个根因，发现 close-req 阶段也有同源问题，且其中一条比 close-task 任何一坑都严重。

### 4.1 R1（最大）：半 close marker 不闭环（重写后）

**现象**：
- task-001 / task-002 engineering.md §10 都有 `SKIP_DOC_UPDATE` marker，`cleanup_status="pending"`
- task-002 engineering.md §12「半 close cleanup TODO」第一条明确写：「等 task-002 / task-003 / task-004 全部 close 后，由 close-req（rewrite task）统一重写 docs/modules/.../functions-v4.1.md §16-21」
- doc-update SKILL.md 步骤 0.5（L53）预言：「由 close-req 阶段聚合所有 SKIP marker 后统一 rewrite」
- **但 close-req SKILL 步骤 2a / 2b / 2c 完全不读这些 marker，doc-update SKILL 也没有 rewrite mode 的实现**
- close-req 关闭后 marker 仍是 `cleanup_status=pending`，cleanup TODO 永远没人扫

**性质**：设计意图（doc-update / task close 提示 / engineering §12）和实现脱节。**rewrite mode 在 doc-update SKILL 里压根不存在**——这是双层脱节。

#### R1 实现路径对比

| 方案 | 实现 | 评估 |
|---|---|---|
| **R1-A** doc-update 加 rewrite mode + close-req 调用 | 在 `skills/doc-update/SKILL.md` 加新步骤"步骤 8：rewrite mode（close-req 触发）"；close-req SKILL 加步骤 1.5 扫 marker → 聚合 → 调 doc-update rewrite mode；doc-update 接 multi-task SKIP markers + 同目标文档 → 整段重写 + PM diff 确认 | 推荐——doc-update 设计意图的延伸，符合 SKILL 自己的预言 |
| **R1-B** close-req inline 重写 | close-req SKILL 加步骤 1.5 扫 marker；inline 让 PM 在 chat 写新版 module spec；不走 doc-update | 简单但不复用 doc-update 的对账 / PM 确认机制 |
| **R1-C** 沿用现有沉淀模式 multi-task batch | 让 close-req 对每个有 SKIP marker 的 task 跑一遍 doc-update 沉淀模式（步骤 1.7） | doc-update 沉淀模式按单 task 设计，多 task 跑会重复杂交；不解 R1 根本 |

#### 推荐：R1-A（doc-update 加 rewrite mode）

**Step 1：doc-update SKILL.md 加 rewrite mode**

新增章节：

```markdown
### 步骤 8：rewrite mode（close-req 触发的多 task 聚合重写）

触发条件：close-req 在步骤 1.5 扫到 ≥2 个同目标文档的 SKIP_DOC_UPDATE marker，调 doc-update rewrite mode。

输入：
- 目标文档路径（如 docs/modules/<module>/functions-v4.1.md）
- 多个 task 的 SKIP marker reason + §12 cleanup TODO + 业务层偏差表 + 工程合同 §10 偏差表
- 受影响章节范围（聚合所有 task 的 §16-21 等指向，确认 rewrite 边界）

流程：
  1. 读目标文档全文 + 所有相关 task 的 PM 视图功能清单 + 偏差表
  2. AI 起草新版整段（替换原章节）
  3. PM 审 diff（默认逐章节批准；PM 可主动选 "all-at-once" 跳过逐章节）
  4. 写入目标文档 → 把所有相关 task 的 SKIP marker cleanup_status 改 "done" → §12 cleanup TODO 对应项标 [x]

PM 拒绝 rewrite（任一章节）→ exit 1，让 close-req 决定是 retry 还是降级 patch mode 或 skip。
```

**Step 2：close-req SKILL.md 加步骤 1.5**

```markdown
### 步骤 1.5：扫描半 close cleanup TODO（v2 重做场景必经）

遍历 tasks/*.engineering.md，找所有 §10 含 <!-- SKIP_DOC_UPDATE: ... cleanup_status="pending" --> marker。

预筛：marker reason 含 "等下游 req" / "下游 req 处理" 等跨 req 关键词时 → silent skip 这条 marker（保留 pending），打印一行 "task-NNN 标 inter-req 推迟，跳过"。

对剩下每个 marker：
  1. 读 marker reason + 同 task §12 cleanup TODO 清单 + PM 视图业务层偏差表 + 工程合同 §10 偏差表
  2. 按"目标文档"分组（同一份 module spec / DESIGN.md / prd 的多 task 偏差并到一起）

聚合后呈交 PM，按目标文档逐份决议：
  - **rewrite**（≥2 task 改同文档时默认）：调 doc-update SKILL 步骤 8 rewrite mode
  - **patch**（单 task 改单文档时）：调现有 doc-update 对账模式（步骤 1.5/1.6/2-5）
  - **skip**：本 req 不沉淀，留到下游 req（marker cleanup_status 保持 pending，append inter-req 备注 `<!-- DEFERRED_TO_REQ: req-NNN reason="..." -->`）

全部 marker 处理完后才进步骤 2a /pmai-prd-writing（这时 module spec 已经统一沉淀，prd-writing 输入干净）。

PM 决议过程中拒绝任何 rewrite / patch → close-req 中止，retry 时回到步骤 1.5 重新决议。
```

**Step 3：测试用例**

- 单 req 内有 2 个 task 改同 module spec → close-req 步骤 1.5 触发 rewrite mode
- 单 req 内有 1 个 task 半 close → 走 patch mode
- 单 req 内无半 close marker → 步骤 1.5 silent skip

**收益**：
- 半 close 流程从"无人收尾"变成"close-req 自动收尾"
- prd-writing 输入质量提升（不再读杂交版 module spec）
- task-001 / 002 / 003 / 004 的累积偏差一次性沉淀，不留 TODO 债
- doc-update SKILL 步骤 0.5 的设计意图终于有实现支撑

**vs 原 plan**：原方案直接调 `/pmai-doc-update --rewrite`（虚构的 flag），实际不存在。重写后改成"先在 doc-update SKILL 加 rewrite mode 实现，再让 close-req 调用"——多一步 SKILL 改造，但不再架空。

### 4.2 R2：worktree 路径硬编码

**位置**：`scripts/close-req.sh:71`

```bash
REQ_WORKTREE="$REPO_ROOT/.worktrees/$REQ_BRANCH"
if [ ! -d "$REQ_WORKTREE" ]; then
  echo "❌ req worktree 不存在: ${REQ_WORKTREE}。"
  ...
fi
```

**问题**：与 close-task.sh L137-142 同病——假设 worktree 在 `$REPO_ROOT/.worktrees/<branch>`，Conductor / Superset 模式下 worktree 在 `~/.superset/worktrees/<uuid>/<branch>`，需要 symlink 兜。

**修复**：与 §3.3 C2 同一种修复（用 `git worktree list --porcelain` 解析），两处一起改。

### 4.3 R3：`git add -A && commit` 太宽松

**位置**：`skills/close-req/SKILL.md` 步骤 4

```bash
git add -A
git commit -m "close: req-NNN-<slug>"
```

**问题**：会一锅端所有 dirty 改动——包括 v2 重做的杂交残留、未审 review 改动、其他工具串扰留下的文件。这是反向反模式：close-task 步骤 0 严格 dirty 拦截，close-req 步骤 4 完全不拦。

**修复**：`git add -A` 之前先列 dirty 文件给 PM 看，PM 显式确认才 commit。或者只 add 已知归档相关路径（close-report.md / closed/<req>/）。

### 4.4 R4：prd-writing 在半 close 上下文的 token + 质量风险

**问题**：v2 重做场景下 functions-v4.1.md 是杂交版（被 task-001 / 002 改过但 SKIP_DOC_UPDATE 没沉淀新规则）。/pmai-prd-writing 步骤 2a 必做，会从 module spec 抽 PRD 输入——读到杂交版 → 输出 PRD 质量低 + 烧 token。

**修复**：R1 解决后这个自动消失。R1 先扫 marker 统一重写 module spec → prd-writing 读到的是干净版。

不需要独立修。

### 4.5 close-req 不需要类 I-CT8 审计

close-req 阶段所有 task 都已 close（脚本步骤 39-58 校验），每个 task 的事件流在 close-task 时已经审计过。close-req 阶段不需要再审 task 事件流。**根因 1（I-CT8 漏洞）只在 close-task 撞，close-req 不撞**。

---

## 5. 已知风险（review 共识保留项）

§5.1 / §5.3 / §5.4 的内容（A1 file-name 漏洞 / 排序错 / 测试缺失）已并入 §0 修订记录、§3.1（A2 subject prefix）、§3.1 step 3（5 个测试用例）、§6 优先级。本节只保留**重写后仍未关闭**的风险。

### 5.1 杠杆 B 的"预告字段权威化"风险靠 sanity check 兜不住

CEO review 双视角共识：杠杆 B 的 silent drift 风险（"AI 偷懒填'无'但实际有改动"）靠 task-submit sanity check 兜底是手挥——sanity check 要做语义判断："代码改了 page.tsx L2194 的 Select option label，task md §📋 第 N 条对应该改"——这是 LLM 难做对的语义对齐。

Codex 还指出：这正是 CLAUDE.md "根因优先" 反对的"加更醒目的提示"反模式。如果 AI 第一次填错，下一个 AI 看 sanity check 也会填错。

**结论（已落到 §6 #6）**：杠杆 B 推迟到 R1 + A2 落地、N 次 close-task 观察 §0 实际 token 下降到多少之后再评估。**别先建一个治不准的预告字段权威化机制 → 再建一个治不准的 sanity check 治预告字段**。

### 5.2 A2 commit subject 混合改动场景未确定

A2 的 subject prefix 豁免哲学：subject 显式声明 `meta:` / `lifecycle:` 就豁免，不看 diff 内容。

风险：如果 commit subject 写 `task-002: meta:move task md` 但 diff 实际包含 `src/page.tsx` 改动（人为或工具误操作），audit silent pass，I-CT8 失效。

**两条路线（PM 拍）**：
- **宽松（默认）**：以 subject 为准。理由：subject 由约定脚本生成，人为改动是 git pre-commit hook 防线问题，不是 audit 责任。
- **严格**：subject `meta:` 时 audit 二次校验 diff 是否仅含 task md / engineering md / `.req-meta.json` / `.runs/*`，否则报错。

§3.1 step 3 测试用例 #3 已经在 PM 决策清单里。

---

## 6. 优先级与下一步

**优先级**（基于 2026-05-08 CEO 双视角 review 共识重排）：

| # | 改动 | 阶段 | 收益 | 成本 | 影响面 |
|---|---|---|---|---|---|
| **1** | **杠杆 A1**（I-CT8 file-name allowlist hotfix） | hotfix（立即） | 38m + 60k token / close-task；解锁 task-003 / 004 close | audit-task-events.py ~12 行 + 4 测试用例 | 仅 audit-task-events.py |
| **2** | **R1**（半 close marker 闭环 + doc-update rewrite mode） | hotfix（立即） | 系统级信任修复——不留 TODO 债 + prd-writing 输入清洁 | doc-update SKILL.md 加步骤 8 + close-req SKILL.md 加步骤 1.5 | doc-update + close-req SKILL |
| **3** | task-confirm SKILL.md 步骤 3 补"双向 commit"行为描述 | 顺手 | 文档准确性 | 5 分钟 | 1 SKILL |
| **4** | **杠杆 A2**（commit subject prefix 重构 + sunset A1） | 重构（2-4 周） | 治本——新元信息文件类型不需扩白名单 | audit + 3 脚本 + 5 测试 + sunset A1 | audit + 3 脚本 + SKILL |
| 5 | C1（req worktree dirty 根因） | 高频小痛 | 消除每次 close-task PM 手动处理 dirty | 待查根因 | task-transition.py |
| 6 | R2 + C2（worktree 路径硬编码） | Conductor 兼容 | 不需 symlink workaround | close-req.sh + close-task.sh 各 5 行 | 两脚本 |
| 7 | R3（close-req `git add -A` 收紧） | 安全 | 防 dirty 一锅端 | close-req SKILL 加 PM 确认 | close-req SKILL.md |
| 8 | 杠杆 B（预告字段权威化） | 推迟 | 5-10k token + 几分钟 / close-task | 推迟到 R1+A2 落地 + N 次观察 | 反馈循环规则 |
| 9 | C3（验收通过文案） | 顺手 | 文案干净 | 5 分钟 | 2 SKILL.md |

**排序逻辑（基于 §0.2 验证）**：

- **#1 A1 hotfix 优先**：22146458 改动只在 engineering.md，A1 file-name allowlist 命中即可解燃眉。Phase 1 立即可做，~12 行代码。
- **#2 R1 并行**：跟 A1 不冲突（不同文件），可以一起 PR。R1 是系统级信任修复，避免半 close 流程长期债务。
- **#3 顺手**：task-confirm SKILL.md 步骤 3 漏写双向 commit，§0.2 发现，5 分钟改文档。
- **#4 A2 重构推迟**：CEO review #6 (allowlist roach motel) 长期成立，但 A1 已止血，A2 有时间慢做，2-4 周内完成 + sunset A1。
- **#5-#7**：原 #3-#5 顺序保留。
- **#8 杠杆 B**：silent drift 风险靠 sanity check 兜不住，推迟到 N 次观察后再评估。

**下一步行动**：

1. **AI 实施 #1 + #2 + #3**（hotfix 三件套，可并行）：
   - apply A1 patch 到 `scripts/audit-task-events.py` + 加 4 测试用例
   - apply R1 patch 到 `skills/doc-update/SKILL.md` 步骤 8 + `skills/close-req/SKILL.md` 步骤 1.5
   - 补 `skills/task-confirm/SKILL.md` 步骤 3 双向 commit 行为
2. **PM ack 后** commit + 同步框架到 example-consumer-app → 跑 task-003 / 004 close 验证
3. **2-4 周内**：A2 重构（按 §3.1 Phase 2 草稿）+ sunset A1
4. **#5-#9**：按节奏

---

## 7. 待澄清（重写后）

原"杠杆 A 豁免边界"已被 A2 subject prefix 解决。剩余开放项：

- **A2 subject 严格 vs 宽松**：见 §5.2，PM 拍。
- **R1 doc-update rewrite mode 的 PM 决议粒度**：多 task 聚合到同一目标文档时，PM 是一次审完整 rewrite diff，还是逐章节审？前者快但 cognitive load 大，后者慢但安全。建议：默认逐章节，PM 可选 "all-at-once" 跳过逐章节。
- **R1 跨 req 边界**：如果 task close 时声明 SKIP marker reason 是"等下游 req 处理"，本 req close-req 步骤 1.5 应该 silent skip 这条 marker（不强迫 PM 决议），加 inter-req 备注追踪。
- **杠杆 B 的硬约束程度**：「文档对齐预告」字段升级硬约束后，AI 偷懒填"无"的风险靠 task-submit sanity check 兜——这条 check 实施成本和准确度待评估，已推迟到 §6 #6。
- **C1 commit 频次**：每次状态转换一个 commit 会让 git log 噪声大。是否合并到下一次有意义 commit（如 task-execute 的代码 commit）里更优？依赖 task-transition.py 实现细节。

