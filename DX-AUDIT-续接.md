# DX 审计续接入口

> **新窗口续接**：PM 在新对话里说"读 DX-AUDIT-续接.md 继续"即可。
> 维护约定：每完成一项 P0 → 标 `[完成]` + 写 commit hash；本文件记完时整体归档。

---

## 当前位置（2026-05-08）

**起因**：`/gstack-devex-review` 对 PM-AI-Workflow 框架做了一轮活体 DX 审计，综合分 4.7/10。本次会话已收口 4/9 项 P0。

**已完成 commit**（生成器仓）：

```
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
| P0-1 | PM-VIEW-RULES.md 943 行按消费方拆分 | 待办 | — |
| P0-2 | 巨型 SKILL.md 拆 references/（task-execute 911/prd-writing 756/task-spec 568）| 待办 | — |
| F-1 | prd-writing 484 行 PM 反馈逐条消化 | 待办 | — |
| P0-6 | /skill-improve skill 雏形（与 F-1 一起做）| 待办 | — |
| P0-7 | task-spec 早期截断（防 task 双轮废，先设计后实施）| 待办 | — |

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
