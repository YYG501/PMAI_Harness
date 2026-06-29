# project-questioning：项目方向讨论的共享真相源

> **职责**：项目方向讨论的**提问纪律 / 问题库 / 写作规则 / Decision gate / 5 节检查**的**单一真相源**。
> **调用方**：`/pmai-init-project` 已有代码分支触发的 codebase-audit step 4（已有代码首次接入定方向，内联）+ `/pmai-direction`（事后方向校准：方向重定 / 路线规划）。
> **§2.5 抽取边界**：本文件含**写作规则 + 话术问题库 + 收敛条件 + Decision gate 模板 + 检查清单**（跨场景共享）；调用方各自判断输入态和问题顺序：codebase-audit 管已有代码首次接入，`/pmai-direction` 管已接入项目的方向重定 / 路线规划。
> **复用 pattern**：跟 `skills/_shared/PM-VIEW-RULES.md` 同款 shared reference 机制。

---

## §1 调用方约定

调用方应当：

1. **判断场景**（调用方自己做）：
   - `/pmai-init-project` 已有代码分支触发的 codebase-audit step 4 → 已有代码首次接入（输入 = 刚产出的 `docs/CODEBASE-AUDIT.md` 现状档）
   - `/pmai-direction` → 已接入项目的事后方向校准（方向重定 / 路线规划）
2. **决定问题顺序**（调用方自己排）：
   - 已有代码首次接入：先读 `docs/CODEBASE-AUDIT.md` 作实况语境，再问产品定位 → 用户画像 → 技术栈 → 业务术语表 → TODO 待办池
   - 方向重定：按 PM 提的变化切入，必要时重写产品定位 / 用户画像 / 技术栈 / 业务术语表 / TODO
   - 路线规划：跳过产品定位 / 用户画像 / 技术栈（除非 PM 明确说这些也变了），只刷新 TODO 待办池和必要的业务术语
3. **跑提问 + 闸门 + 写作 + 确认门**（按 §2-§7 走）
4. **PM 定稿后**：调用方按自己语境继续（codebase-audit 首次接入给 ▶ Next Up 引到 `/pmai-design`；direction skill 退出）

---

## §2 提问纪律

沿用模块探索里沉淀下来的提问纪律，但不依赖任何 design-only 方法文件：

- **分批提问**：一次问一组相关问题，不一口气甩全部
- **追问**：PM 答得模糊就追问到能落笔，不拿模糊回答硬写
- **收敛**：问到够写 5 节 + 初始队列即停，不无限发散
- **编号作答**：每批问题编号，引导 PM 用 `1A 2C` 或自由文本回答

**禁止**：① 拿 PM 模糊回答硬写 ② 一气呵成把 30 题甩出来 ③ 自由话术不编号导致 PM 答案丢失定位

---

## §3 问题库（按 5 节组织）

| PRODUCT 节 | 要问出 | 典型话术 |
|---|---|---|
| 产品定位 | 是什么产品 / 解决什么问题 / 给谁用 / 有无长期硬约束 | 「这个项目要解决什么核心问题？目标用户是谁？有没有不能动的边界（合规 / 集成 / 性能）？」|
| 用户画像 | 主角色是谁 / 关键诉求（起手 1 个主角色即可） | 「最主要的用户是哪种人？他们最大的诉求是什么？」|
| 技术栈 | 主要语言 / 前端 / 后端 / 部署 | 「用什么技术栈？前端 / 后端 / 部署有偏好吗？还是按现状走？」|
| 业务术语表 | 项目里有没有需要统一口径的业务专名 | 「业务里有什么术语容易跟同行混的？比如『订单』vs『工单』？」|
| —（TODO）| PM 提过 / 讨论过想做的事 | 「列出你现在想到要做的事，不用排顺序。」|

> **项目名称节**通常 `/pmai-init-project` 已填（参数 1），调用方确认即可。

**调用方挑用**：调用方按场景挑 5 节里的子集 + 顺序（codebase-audit 首次接入按 5 节顺序；direction 按方向重定 / 路线规划挑用）。**叙事性里程碑不另开节** —— TODO 是 PM 的待办池，只记 PM 提过 / 讨论过想做的，AI 不从代码 / 竞品 / 已收尾历史反推填充。

---

## §4 未决问题闸门（收敛前硬规则）

讨论收敛、动手写 `PRODUCT.md` 之前 —— 如果还有需要 PM 拍板才能定的项目级问题（如「先做单人版还是直接做协作版」），**不能带着模糊往下写**。

**步骤**：

1. 把未决问题写进**暂存文件** `docs/.project-solution-open-questions.md`（注：文件名沿用历史 prefix，不要重命名）：

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

2. 跑闸门脚本：

```bash
python3 "$PMAI_HOME/scripts/check-open-questions.py" \
  "$REPO_ROOT/docs/.project-solution-open-questions.md" --require-section
```

- 退出 0 → 全部已答（或显式声明无未决项），进 §5
- 退出 1 → 有未答项 / 缺 section → 把未答题逐条贴给 PM 让其作答，PM 答完回写暂存文件，重跑脚本

3. `--require-section` 必带：暂存文件必须真有 `## 未决问题` section，否则闸门形同虚设。

**禁逃生舱**：没有「暂跳过」「以后再说」「带假设前进」选项。PM 真不知道某题答案 → AI 给一个精简默认值让 PM 微调或接受，但答案必须落到暂存文件里、闸门必须过。

---

## §5 写作规则

### §5.1 PRODUCT.md 5 节（模板见 `$PMAI_HOME/templates/PRODUCT.md.tmpl`）

| 节 | 写什么 |
|---|---|
| 项目名称 | 通常 `/pmai-init-project` 参数 1 已填，确认即可 |
| 产品定位 | 1-3 句话；最简版「工具型应用，给单人 PM 用」也接受 |
| 用户画像 | 起手 1 个主角色 + 关键诉求；最简版 1 句话 |
| 技术栈 | 主要语言 / 前端 / 后端 / 部署 |
| 业务术语表 | 至少 1 条；无业务专名时可空表 |

### §5.2 TODO.md（模板见 `$PMAI_HOME/templates/TODO.md.tmpl`）

**TODO 是 PM 的待办池**——只记 PM 提过 / 讨论过想做的事，无序、不排顺序。三态简单：

| 状态 | 含义 |
|---|---|
| `todo` | 讨论过 / 提过想做，还没开始 |
| `doing` | 正在做（已进入 `/pmai-design` 或 `/pmai-build`） |
| `done` | 做完了（对应工作已 close） |

字段：来源工作（进入 `/pmai-design` / `/pmai-build` 后回填，可空）/ 标题 / 状态。**没有「排序」列**——待办池不排顺序。

**写 TODO 的硬规则**：
1. **只记 PM 主动提过 / 讨论过想做的事**——AI 不从代码、竞品、历史收尾记录反推填充，池子里只有 PM 真说过想做的。
2. **不替 PM 排顺序**——条目无序，PM 要做时自己挑。
3. PM 没给具体待办 → TODO 留空（一行占位即可），不替 PM 脑补队列。

### §5.3 TODO.md 是 PM 待办池（不是规划真相源）

TODO 不是项目方向真相源——**方向真相源是 `PRODUCT.md`**。TODO 只是 PM 自己维护的待办清单：想到要做的记一笔、不想做了划掉。

PM 要起新需求时，调用方应**提醒 PM「待办池里有这些」让 PM 挑一个**，不替 PM 判断「下一个该做 X」。

### §5.4 PM 视图规则

- 正向描述、名词带指代、不写工程黑话（reducer / props / schema）
- 项目级方向用 PM 语言

---

## §6 Decision gate 确认门（gsd Decision gate pattern）

> Decision gate 是 PM 答完 5 节 + TODO 后的**收敛闸门**，3 条硬规则照搬 gsd `new-project.md:368-380` "Ready?" pattern。

### §6.1 3 条硬规则

| # | 规则 |
|---|---|
| 1 | **label = 动作描述**（例："创建 PRODUCT.md" / "继续探索"），禁用 "OK" / "Proceed" / "Continue" 模糊词 |
| 2 | **description = 一句话解释**（例："我会开始写 PRODUCT.md，进入下一步" / "你还想补充行业 / 客户 / 流程"），不是文档化长说明 |
| 3 | **留守选项有 Loop 回路**：选了「继续探索」自动回到讨论态，不退出 skill |

### §6.2 Decision gate 模板（AskUserQuestion）

```
header: "Ready?"
question: "我想我大致明白你想做什么了。准备好写 PRODUCT.md 了吗？"
options:
  - label: "创建 PRODUCT.md"
    description: "我会开始写 PRODUCT.md，进入后续配置、需求和路线图流程。"
  - label: "继续探索"
    description: "你还想补充行业、客户类型、典型流程、Demo 形态或内部协作方式。"
```

PM 选「继续探索」→ 回 §2 提问；Loop 直到 PM 选「创建 PRODUCT.md」。

---

## §7 写作前 5 节齐不齐检查

写完 `PRODUCT.md` 后跑：

```bash
PROJECT_STATE=$(python3 "$PMAI_HOME/scripts/check-project-sections.py" "$REPO_ROOT")
ALL_FILLED=$(echo "$PROJECT_STATE" | python3 -c "import sys, json; print(json.load(sys.stdin)['all_filled'])")
EMPTY=$(echo "$PROJECT_STATE" | python3 -c "import sys, json; print(','.join(json.load(sys.stdin)['empty_sections']))")
```

- `all_filled` 为 True → 5 节都有实质内容，进 §8 PM 定稿
- 有空节 → 把空节（`$EMPTY`）逐节引导 PM 填，填完重跑脚本

**禁逃生舱**：不给「暂跳过」「这节不重要」选项。PM 真不知道某节写啥 → AI 给精简模式默认值（例：产品定位「工具型应用，给单人 PM 用，无长期硬约束」），PM 微调或直接接受。

---

## §8 PM 定稿展示模板

向 PM 展示两个文件的路径 + 一句话摘要，让 PM 定稿：

```
项目方向已写好：

📋 PRODUCT.md
   <绝对路径>
   产品定位 / 用户画像 / 技术栈 / 业务术语表 已填

🗒 TODO.md
   <绝对路径>
   <N> 条待办已记入待办池

这样定吗？想改的说哪里；OK 的话项目方向就定下来了。
```

- PM 说「OK / 定了 / 没问题」→ 调用方继续（codebase-audit 首次接入进入收尾提示；direction skill 退出）
- PM 提具体修改 → 改对应文件，回 §8 重新确认

---

## §9 atomic commit（调用方按需）

写完 PRODUCT.md + TODO.md + PM 定稿后，调用方 atomic commit（gsd new-project Step 4 pattern）：

```bash
cd <target-dir>  # 业务仓
git add PRODUCT.md TODO.md
git commit -m "docs: project direction settled"
```

> 单文件 commit，不产工程孪生 `solution.engineering.md` —— 项目级方向只用 PM 视角写。

---

## §10 调用方实现指南

### §10.1 codebase-audit step 4（已有代码首次接入）

1. agent @读 本文件
2. 全文读 `docs/CODEBASE-AUDIT.md`，把现状档作为问题语境
3. 按已有代码接入顺序问 PM：产品定位 → 用户画像 → 技术栈 → 业务术语表 → TODO 待办池
4. §4 未决问题闸门
5. §6 Decision gate
6. §5 写 PRODUCT.md + TODO.md
7. §7 5 节齐不齐检查
8. §8 PM 定稿
9. §9 atomic commit
10. 返回 codebase-audit 收尾提示，并给 ▶ Next Up 引到第一个 `/pmai-design`

### §10.2 `/pmai-direction`（方向重定 / 路线规划）

1. agent 按 SKILL.md 步骤 1 读已有输入（CLAUDE.md / `PRODUCT.md` / `TODO.md`，存在 `docs/CODEBASE-AUDIT.md` 时只作为背景材料）
2. **判断意图**（方向重定 / 路线规划）—— 调用方 `/pmai-direction` SKILL.md 的“意图判断”表给出触发条件 + 输入态 + 提问顺序
3. agent @读 本文件
4. 按 `/pmai-direction` SKILL.md 的“提问顺序”列问 PM：
   - 方向重定：变化来源 / 旧方向哪里不成立 → 产品定位 → 用户画像 → 技术栈（如有变化）→ 业务术语 → 刷新 TODO 待办池
   - 路线规划：问 PM 现在想做什么，记进 TODO 待办池（**AI 不扫 `requirements/pmai-closed/` 反推历史、不排序**）→ 业务术语增量（默认跳过产品定位 / 用户画像 / 技术栈）
5. §4 未决问题闸门
6. §6 Decision gate
7. §5 写 / 改 PRODUCT.md + TODO.md
8. §7 5 节齐不齐检查
9. §8 PM 定稿
10. §9 atomic commit
11. skill 退出（不像 init-project 还有阶段 D）

> 注：`/pmai-direction` 的**完整提问顺序表 + 输入态 + 触发条件**留在 `skills/direction/SKILL.md`；本节 §10.2 只给"调用方实现指南"的步骤骨架，避免双份维护漂移。

---

**End of `_shared/project-questioning.md`**（项目方向讨论共享内核；方向重定 / 路线规划顺序细化已落 `direction/SKILL.md`）
