# DX 审计续接入口

> **新窗口续接**：PM 在新对话里说"读 DX-AUDIT-续接.md 继续"即可。
> 维护约定：每完成一项 P0 → 标 `[完成]` + 写 commit hash；本文件记完时整体归档。

---

## 当前位置（2026-05-08）

**起因**：`/gstack-devex-review` 对 PM-AI-Workflow 框架做了一轮活体 DX 审计，综合分 5.4/10（静态）→ 4.7/10（含 ExampleConsumerApp 活体证据下调）。本次会话已收口 6/9 项 P0。

**评分基线**（P0/P1 完成后再次跑 /devex-review 用作对比）：

| 维度 | 静态 | 活体 |
|---|---|---|
| Getting Started | 6 | 5 |
| Skill 人体工学 | 7 | 5 |
| 错误恢复 | 5 | 4 |
| 文档可发现性 | 4 | 4 |
| 升级路径 | 5 | 5 |
| 环境与依赖 | 6 | 6 |
| AI 执行可预测性 | 5 | 4 |
| **综合** | **5.4** | **4.7** |

**已完成 commit**（生成器仓）：

```
ea2dc82 refactor(skills): PM-VIEW-RULES + 三个超大 SKILL.md 按消费方拆 references
8affee9 fix(audit): CT7 旧规范三步式兼容 + CT8 chore commit 豁免
3a4a98a refactor(scripts): worktree 物理路径解析抽 _lib/worktree.sh helper
38313a9 feat(skills): task-plan 反模式扩容 + close-req 覆盖度判断 + INVARIANTS 主索引
95dca9e feat(scripts): worktree 残留检测脚本 + 集成 req-stage-gate
2560cb8 refactor(docs): 归档 21 份历史设计档案到 docs/archive/design/
```

| # | 项目 | 状态 | commit |
|---|---|---|---|
| P0-3 | 21 份历史档案归档 docs/archive/design/ + 8 处引用更新 | [完成] | 2560cb8 |
| P0-4 | INVARIANTS.md 加 60 编号速查主索引 | [完成] | 38313a9 |
| P0-5 | close-req 步骤 2a/2b 加 doc-update 覆盖度自动判断 | [完成] | 38313a9 |
| P0-8 | scripts/check-worktree-residue.py + req-stage-gate 集成 | [完成] | 95dca9e |
| P0-1 | PM-VIEW-RULES.md 943→278（主索引）+ 6 个子文件，12 skill 引用 | [完成] | ea2dc82 |
| P0-2 | task-execute 911→539 / prd-writing 756→315 / task-spec 568→525 拆 references/ | [完成] | ea2dc82 |
| F-1 | prd-writing 484 行 PM 反馈逐条消化 | 待办 | — |
| P0-6 | /skill-improve skill 雏形（与 F-1 一起做）| 待办 | — |
| P0-7 | task-spec 早期截断（防 task 双轮废，先设计后实施）| 待办 | — |

### P1 待办（次优先，P0 全完成后再做）

| # | 项目 | 工作量 | 备注 |
|---|---|---|---|
| P1-4 | task-plan 内部「硬禁止项 vs Rules」合并成单一"硬约束"节 | 30 分钟 | 当前两节没有功能分工；改名会影响其他 skill 的 cross-ref，要批量更新 |
| P1-5 | req-stage-gate SKILL.md(290 行) 减负，按 stage 边界拆 references/stage-{N}-{N+1}.md | 0.5 天 | 主 SKILL 只留路由 + 通用规则；每次跑 stage transition 不用整体加载 290 行 |
| P1-6 | STATUS-v3.5实施.md 改名 RUNTIME.md 或 STATE.md，明确"运维入口"职责 | 30 分钟 | README/CLAUDE/STATUS 三处状态边界模糊；STATUS 当前自封"新窗口续接入口"= 运维职责 |

---

## 关键活体证据（决策依据，不要丢）

### 1. ExampleConsumerApp 真实业务项目
路径：`${CONSUMER_REPO_ROOT}`

- **req-001 重做 v2**：req-003-tenant-console-redesign-v2 在 worktree 里跑，整 req 重做（v1 task 拆分粒度不当：3 个 task 计划，task-003 重做两轮全废）
- **task-003 双轮废**：见 `requirements/closed/req-001-tenant-console-redesign/close-report.md` 末尾 `<details>` 块
- **跳过 prd-writing + project-prd-update**：req-001 close 时 PM 显式跳过两个 skill，理由"徒增 PM 决策成本"——P0-5 已修，但 prd-writing skill 自身的体验改进还没做
- **484 行 PM 反馈**：`ExampleConsumerApp/prd-writing-skill-feedback.md`，9 大类问题，状态"待 PM 评估是否落地"

### 2. worktree 残留实测
`scripts/check-worktree-residue.py` 在 ExampleConsumerApp 跑出：
- 编号冲突 task-001（两个）/ task-003（两个）
- 3 个孤儿 task worktree（req-001 残留没清理）

PM 后续清理 ExampleConsumerApp 时跑：
```bash
cd ${CONSUMER_REPO_ROOT}
python3 .claude/scripts/check-worktree-residue.py
```

---

## 待办详细（按推荐顺序）

### 先做：P0-1 + P0-2 一起（半天-1 天）

**为什么一起**：P0-1（PM-VIEW-RULES 943 行拆分）会改变 12 个 skill 的 import 路径；P0-2（巨型 SKILL.md 拆 references/）改 task-execute / prd-writing / task-spec 三个文件的内部组织。两者都涉及 skill 文件结构重排，分两次做要重排两次。

**P0-1 拆分方案**：
- 原文件：`skills/_shared/PM-VIEW-RULES.md`（943 行）
- 按消费方拆：
  - `_shared/pm-view/writing-rules.md`（§三 PM 视图写作规则）
  - `_shared/pm-view/doc-strictness.md`（§四 文档级严格度对照表）
  - `_shared/pm-view/section-order.md`（§七 章节顺序约束）
  - `_shared/pm-view/checklist.md`（§八 自检清单）
  - `_shared/pm-view/input-flow.md`（§九 输入流约束）
  - `_shared/pm-view/cross-skill.md`（§9.7 跨 skill 共享原则）
- 12 个引用 skill 改为只 import 自己需要的 1-2 节
- 风险：cross-ref 链可能漏改；改完跑 `bash tests/run-all.sh` 全套验证

**P0-2 拆分方案**：
- 三个超大 SKILL.md 拆出 `references/` 子文件
- 主 SKILL.md 只留 frontmatter + workflow 步骤大纲 + 关键规则
- 详细工作流 / 边界处理 / 反模式细则进 references/
- 参考已有模式：`skills/req-solution/references/few-shots.md`

**验收**：测试套件 `bash tests/run-all.sh` 0 失败；ExampleConsumerApp 跑下一个 req 不破。

---

### 再做：F-1 + P0-6（3-5 小时）

**为什么一起**：F-1（消化 484 行 PM 反馈）是 P0-6（/skill-improve skill 雏形）的天然第一案例——边消化边把"PM 写反馈 → AI 转 skill 改动"流程沉淀成 skill。

**步骤**：
1. 读 `ExampleConsumerApp/prd-writing-skill-feedback.md` 9 大类
2. 对照 `skills/prd-writing/SKILL.md`（756 行）逐条决策"采纳/不采纳"
3. 采纳的直接改 SKILL.md
4. 沉淀流程：写 `skills/skill-improve/SKILL.md`，约定 `skill-feedback/<skill-name>-<date>.md` 反馈目录
5. 把 prd-writing-skill-feedback.md 归档到生成器仓 `skill-feedback/prd-writing-2026-04-27.md`（保留历史）

**注意**：9 大类需要 PM 逐条决策，AI 不能替决；预计需要 PM 介入 30-60 分钟。

---

### 最后：P0-7 task-spec 早期截断（1-2 天，先设计）

**根因**（待验证）：task-spec 阶段写的工程合同 PM 看不出"做出来会长什么样"，要等 task-execute 跑完才能验收。req-001 task-003 重做两轮全废就是这个问题。

**初步设计方向**（需要先讨论）：
- task-spec 写完 .engineering.md 后，强制要求"PM 用一句话描述 demo 时会看到什么"
- 与工程合同 .acceptance section 做 lint 对齐，不一致则不放行进 stage 6

**做法**：先在生成器仓写设计文档（`docs/design/task-spec-早期截断.md` 或类似），PM 走查后再实施。

---

## 横向原则：防御性指令反模式（P0/P1 共同根因）

> 「凭防御性指令对抗 AI 不可靠」 — 跨多个 skill 的根因观察，**不是单独任务**，但每次做 P0/P1 改造时都应该按这个方向校准。

**症状**：skill 文档里散见大量 prose 防御性指令——"禁止 X / 不允许 Y / 不要简化 / 必须实跑 / 机械执行 / 不要凭印象"。这些是 AI 漏判后追加的补丁。当框架增长到 6700 行 skill 内容仍然要靠 prose 防御 AI 偷懒，说明规则没沉淀进**可校验的脚本/lint**。

**典型例子**：
- `skills/req-stage-gate/SKILL.md:284`「未决问题闸门（硬规则）」凭 prose 强制——本应由 lint 检测 `## 未决问题` section 下的 `**PM 回答：**` 是否全部填了内容
- `skills/new-req/SKILL.md:34-61`「事实来源是 git 分支」+ 22 行 bash + "禁止：仅扫 closed/ 不扫 active/ 与 git 分支"——本应封装到 `scripts/_lib/req-num-resolver.sh`，SKILL 只调一行：`NEW_NUM=$(bash .claude/scripts/_lib/req-num-resolver.sh)`

**修复方向**：每条 prose 防御性指令问一句"**能不能写成脚本检查 + 失败时报错？**" — 能就把 prose 替换成 lint 调用。

**具体 P0/P1 入口**：
- 做 P0-2（巨型 SKILL.md 拆 references/）时，把同一个 skill 里的"硬塞 bash 警告段"识别出来，封装到 `scripts/_lib/`
- 做 P0-1（PM-VIEW-RULES 拆分）时，§八自检清单里的"逐条人工 check" 项能否改成 `check-doc-pm-view.py` 自动校验？已有的扩展即可
- 做 P1-5（req-stage-gate 减负）时，「未决问题闸门」凭 grep 验证 → 抽到 `scripts/check-open-questions.py`

---

## 业务仓侧（ExampleConsumerApp）应做的清理

**这些不是生成器仓改动，但 PM 知情后可以一次性清理**：

### 1. worktree 残留清理
```bash
cd ${CONSUMER_REPO_ROOT}
python3 .claude/scripts/check-worktree-residue.py
# 报：编号冲突 task-001 / task-003 + 3 个孤儿 task worktree（req-001 残留）
# 逐个跑：git worktree remove .worktrees/<name>
```

### 2. 业务仓根目录归档（与 P0-3 同款问题）
- `ExampleConsumerApp/PROTOTYPE_CLEANUP.md`（255 行）和 `prd-writing-skill-feedback.md`（484 行）散在根目录
- 建议建 `ExampleConsumerApp/feedback/` 或 `ExampleConsumerApp/docs/archive/` 归档
- prd-writing-skill-feedback.md 在 F-1 消化后归档到生成器仓 `skill-feedback/prd-writing-2026-04-27.md`，业务仓本地可删

---

## 新窗口续接命令

```bash
cd ${REPO_ROOT}
claude
```

新对话第一条消息：

> 读 DX-AUDIT-续接.md 继续。先做 P0-1 + P0-2。

新窗口的 AI 会：
1. 读本文件还原上下文
2. 读 git log 看已完成 commit
3. 按推荐顺序动手
