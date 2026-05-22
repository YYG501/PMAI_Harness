---
name: project-solution
description: |
  项目级一次性 skill：PM 在 /init-project 之后调用，定项目顶层方向。
  内部两段——段 1 讨论方向（复用 analysis 提问法纪律），段 2 产出 docs/CONTEXT.md（6 节）+ docs/roadmap.md。
  不占 req stage、不走 req-stage-gate；项目骨架建好后只跑这一次。
---

# /project-solution

## When To Use

- PM 在框架仓库初始化出一个新项目、跑完 `/init-project` 之后调用
- 一个项目只跑一次：把项目顶层方向（产品定位 / 用户 / 路线 / 技术栈 / 术语）一次性定下来，写进 `docs/CONTEXT.md`，并列出待做需求队列 `docs/roadmap.md`
- 它不是 req 级 skill——不占任何 req stage，不由 `/req-stage-gate` 调度

> 已存在的老项目不补跑本 skill。老项目的项目级语境兜底走 `/new-req` 首次跑时的 mini-fill。

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: project-solution"
```

## 与 init-project 的关系

`init-project` 是纯脚手架（建目录 / 脚本 / git，纯空骨架）。`project-solution` 接在它后面，
负责往骨架里填项目级方向内容。两者职责不重叠：

| | init-project | project-solution |
|---|---|---|
| 干什么 | 建空骨架（目录 / 脚本 / git） | 定项目方向，填 `docs/CONTEXT.md` + `docs/roadmap.md` |
| 何时 | 创建项目时 | `/init-project` 之后、起第一个 req 之前 |
| 跑几次 | 一次 | 一次 |

## 产出

- `docs/CONTEXT.md` —— 项目顶层方案，6 节：项目名称 / 产品定位 / 用户画像 / 产品路线 / 技术栈 / 业务术语表（模板 `$REPO_ROOT/templates/CONTEXT.md.tmpl`）
- `docs/roadmap.md` —— 计划态 req 队列（模板 `$REPO_ROOT/templates/roadmap.md.tmpl`）

**单文件，不产工程孪生** —— 本 skill 不产 `solution.engineering.md` 之类的工程合同。项目级方向只用 PM 视角写。

**「产品路线」节 vs roadmap 的分工**（产出时同时填两者并对 PM 说明）：

| | CONTEXT.md「产品路线」节 | docs/roadmap.md |
|---|---|---|
| 装什么 | 里程碑 / 大方向（如「Q3 上线 MVP」「先做单人版再做协作」） | 计划态 req 队列（颗粒到单个需求） |
| 生命周期 | 稳定基线，变动慢 | 操作态，随 req 推进更新 |
| 谁读 | AI 后续每个 req 必读的项目语境 | PM 自己的规划视图（挑下一个做什么） |

写完后向 PM 一句话说明：「产品路线节 = 大方向里程碑；roadmap = 你接下来要做的需求清单，做完一个改一次状态。」

## Workflow

本 skill 内部两段 + 一个确认门。**不走 req stage、不调 req-transition.py、不调 req-stage-gate。**

---

### 段 1 · 讨论方向

目标：把项目顶层方向问清楚，够写 `docs/CONTEXT.md` 6 节 + 列出初始 req 队列。

#### 步骤 1：读已有输入

- `docs/CONTEXT.md`（`/init-project` 已建空骨架；可能有项目名 + 项目背景）
- `CLAUDE.md`（看 `/init-project` 注入的项目背景 / 工程结构约束档位）
- **`docs/代码现状档.md`（如存在 — brownfield 场景，delta-1）**：已有代码库接入时，`/codebase-audit`
  先扫码产出的 7 维度现状档。存在 → 全文读，作为项目方向讨论的实况语境（被现状档喂着讨论，
  和新项目一样跑 project-solution，只是多这份输入）。

#### 步骤 2：分批提问 PM（复用 analysis 提问法纪律）

复用 `req-analysis` 的提问方法 / 纪律——**不是字面调用 `/req-analysis`**（scope 不同：那是 req 级，这是项目级）。借用的纪律：

- **分批提问**：一次问一组相关问题，不一口气甩全部
- **追问**：PM 答得模糊就追问到能落笔，不拿模糊回答硬写
- **收敛**：问到够写 6 节 + 初始队列即停，不无限发散
- **编号作答**：每批问题编号，引导 PM 用 `1A 2C` 或自由文本回答

要问到能填满 6 节的程度：

| CONTEXT 节 | 要问出 |
|---|---|
| 产品定位 | 这是什么产品 / 解决什么问题 / 给谁用 / 有无长期硬约束 |
| 用户画像 | 主角色是谁、关键诉求（起手 1 个主角色即可） |
| 产品路线 | 里程碑 / 大方向（先做什么后做什么） |
| 技术栈 | 主要语言 / 前端 / 后端 / 部署 |
| 业务术语表 | 项目里有没有需要统一口径的业务专名 |
| —（roadmap）| PM 现在已知的待做需求，大致排个序 |

> 项目名称节通常 `/init-project` 已填，确认即可。

**可选——PM 自跑外部 review**：项目方向需要更激进的第二视角时，建议 PM 自己跑 `/office-hours`（想清楚值不值得做）或 `/plan-ceo-review`（挑战范围 / 想更大）。这两个保持 gstack 官方默认，PM 自跑、把结论带回本讨论。本 skill 不自动调它们。

> **不设第二视角强制评审** —— 项目方向不像 req 级 analysis 有 analysis-reviewer。项目方向的第二视角由 PM 可选自跑的 `/plan-ceo-review` 担任，不在本 skill 内强制。

#### 步骤 3：未决问题闸门（收敛前硬规则）

讨论收敛、动手写 `docs/CONTEXT.md` 之前——如果还有需要 PM 拍板才能定的项目级问题（如「先做单人版还是直接做协作版」），**不能带着模糊往下写**。

把未决问题写进暂存文件 `docs/.project-solution-open-questions.md`，格式：

```markdown
## 未决问题

### Q1: <问题标题>

<题干，描述清楚问题边界与影响>

候选答案（如有）：
- A) ...
- B) ...

**PM 回答：**
```

`**PM 回答：**` 后留空作占位。没有未决项时，section 下显式写一行 `（本项目无未决问题）`——**不能省略 section**。

然后对暂存文件跑闸门脚本：

```bash
python3 "$REPO_ROOT/.claude/scripts/check-open-questions.py" \
  "$REPO_ROOT/docs/.project-solution-open-questions.md" --require-section
```

- 退出 0 → 全部已答（或显式声明无未决项），进段 2
- 退出 1 → 有未答项 / 缺 section → 把未答题逐条贴给 PM 让其作答，PM 答完回写暂存文件，重跑脚本

**`--require-section` 必带**：暂存文件必须真有 `## 未决问题` section，否则闸门形同虚设。

> **禁逃生舱**：没有「暂跳过」「以后再说」「带假设前进」选项。PM 真不知道某题答案 → AI 给一个精简默认值让 PM 微调或接受，但答案必须落到暂存文件里、闸门必须过。

闸门过后，暂存文件已完成使命——可保留作讨论记录，不进 CONTEXT.md。

---

### 段 2 · 输出

#### 步骤 4：写 docs/CONTEXT.md（6 节）

按 `$REPO_ROOT/templates/CONTEXT.md.tmpl` 把 6 节填实：项目名称 / 产品定位 / 用户画像 / 产品路线 / 技术栈 / 业务术语表。

- 「产品路线」节只写里程碑 / 大方向（见上方分工表）
- 写作遵守 PM 视图规则：正向描述、名词带指代、不写工程黑话（reducer / props / schema）；项目级方向用 PM 语言

#### 步骤 5：写 docs/roadmap.md

按 `$REPO_ROOT/templates/roadmap.md.tmpl` 写 `docs/roadmap.md`：把段 1 问出的待做需求列成队列，每行一个需求，初始状态都是 `planned`，按 PM 给的优先级填排序号。`req-id` 列留空（req 起后再回填）。

---

### 确认门

段 2 写完后走确认门。本确认门**替代旧 stage 3→4 的 CONTEXT 6 节强制门**——它兼做 6 节齐不齐检查。

#### 步骤 6：开场问模式

```
📝 准备写项目方向（docs/CONTEXT.md + docs/roadmap.md）。

想填详细版（按完整规范），还是最简版（产品定位 1 句话 / 1 个主角色 / 1 条术语 起手）？
最简版几分钟搞定，以后起 req 时还能接着补。
```

- PM 答「最简 / 简版 / 快」→ 精简模式：每节 1 条起手即接受
- PM 答「详细 / 完整 / 详版」→ 详细模式：按 CONTEXT 模板各节注释里的规范长度
- PM 答「混合」→ 各节 PM 临场决定

> **fast-path**：精简模式下 trivial 项目不被前置仪式拖住——产品定位一句话、用户画像一个角色、术语表一条，起手即可过门。

#### 步骤 7：6 节齐不齐检查

```bash
CONTEXT_STATE=$(python3 "$REPO_ROOT/.claude/scripts/check-context-sections.py" "$REPO_ROOT")
ALL_FILLED=$(echo "$CONTEXT_STATE" | python3 -c "import sys, json; print(json.load(sys.stdin)['all_filled'])")
EMPTY=$(echo "$CONTEXT_STATE" | python3 -c "import sys, json; print(','.join(json.load(sys.stdin)['empty_sections']))")
```

- `all_filled` 为 True → 6 节都有实质内容，进步骤 8
- 有空节 → 把空节（`$EMPTY`）逐节引导 PM 填，填完重跑脚本，直到全填

**禁逃生舱**：不给「暂跳过」「这节不重要」选项。PM 真不知道某节写啥 → AI 给精简模式默认值（例：产品定位「工具型应用，给单人 PM 用，无长期硬约束」），PM 微调或直接接受。

#### 步骤 8：PM 定稿

向 PM 展示两个文件的路径 + 一句话摘要，让 PM 定稿：

```
项目方向已写好：

📋 docs/CONTEXT.md
   <绝对路径>
   产品定位 / 用户画像 / 产品路线 / 技术栈 / 业务术语表 已填

🗺 docs/roadmap.md
   <绝对路径>
   <N> 个待做需求已排队

这样定吗？想改的说哪里；OK 的话项目方向就定下来了。
```

- PM 说「OK / 定了 / 没问题」→ skill 退出
- PM 提具体修改 → 改对应文件，回步骤 8 重新确认

退出前向 PM 说明产品路线节与 roadmap 的分工（见上方「产出」段），并引导下一步：

```
项目方向定稿。下一步：运行 /new-req 开始第一个需求。
```

## Rules

**禁止项**：

- ❌ 走 req stage / 调 `req-transition.py` / 调 `/req-stage-gate` —— 本 skill 是项目级一次性，不占 req stage
- ❌ 产工程孪生文件（`solution.engineering.md` 之类）—— 单文件，只写 PM 视角
- ❌ 未决问题闸门给逃生舱（「暂跳过」「带假设前进」）—— PM 必须把答案落到暂存文件，闸门必须过
- ❌ 6 节检查给逃生舱（「这节不重要」「以后再说」）—— 空节必须填，PM 不知道写啥时 AI 给精简默认值
- ❌ 自动调 `/office-hours` / `/plan-ceo-review` —— 这两个由 PM 可选自跑
- ❌ 设 analysis-reviewer 式第二视角强制评审 —— 项目方向第二视角由 PM 自跑 `/plan-ceo-review`
- ❌ 对 `docs/CONTEXT.md` 直接跑未决问题闸门 —— CONTEXT.md 无 `## 未决问题` section，闸门会形同虚设；必须对暂存文件跑
- ❌ PM chat 出现工程黑话（hash / reconcile / stale / 步骤编号）—— 给 PM 看的话只用 PM 视图语言

**必做项**：

- ✅ 段 1 收敛前必过未决问题闸门（对暂存文件 + `--require-section`）
- ✅ 确认门兼做 6 节齐不齐检查（替代旧 stage 3→4 的 CONTEXT 强制门）
- ✅ 产出时同时填 CONTEXT.md「产品路线」节与 `docs/roadmap.md`，并向 PM 说明分工
- ✅ 确认门继承「精简 / 详细」模式选择 + 「PM 不知道写啥时 AI 给精简默认值」逃生阀

## 边界

- **允许产出**：`docs/CONTEXT.md`、`docs/roadmap.md`、讨论暂存文件 `docs/.project-solution-open-questions.md`
- **允许动作**：分批提问、未决问题闸门、6 节检查、确认门
- **禁止顺手推进**：不自动起 req、不调 `/new-req`、不产任何 req 级文档
- **退出条件**：`docs/CONTEXT.md` 6 节全填、`docs/roadmap.md` 已写、未决问题闸门已过、PM 已定稿
