<!--
设计文档：把 /init-project 改造成 agent 化的一气呵成入口
对齐 gsd 「Gsd New Project」体验
跟 PM 共写 §0 后锁定
-->

# /init-project 入口一气呵成 (v0)

> **状态**：§0 已锁（PM confirm 2026-05-24），方案主体待 review
> **日期**：2026-05-24
> **作者**：PM + AI
> **对齐参考**：gsd `Gsd New Project` 流程

---

## §0 原始痛点（PM + AI 共写，后续 review **不可反向修改**）

### §0.1 痛点（1-3 句）

PM 第一次开新项目时，要先在终端跑 `bash scripts/init-project.sh ...`（脚手架），再在 Claude Code 里发 `/project-solution`（定方向），再发 `/new-req`（起需求）——三步靠 echo / README 文案串接。其中 `/project-solution` 在 4 处用户入口（init 脚本 --help / init 脚本末尾 echo / README §1 / README §2）的"下一步"提示里**全部漏写**，导致 AI 和 PM 都把流程当两步（init → /new-req）。即使 `/new-req` 步骤 3.5 有 mini-fill 兜底把 PROJECT.md 补上，`roadmap.md` 永远不被填，项目级方向讨论缺失。

### §0.2 触发场景

| # | 场景描述 | 实证证据 |
|---|---|---|
| 1 | AI 第一次被问"框架使用流程"时答"init → /new-req"，漏 `/project-solution` | 本次对话（2026-05-24）；PM 追问"PROJECT 和 roadmap 什么时候填"才补正 |
| 2 | PM 跑完 `init-project.sh`，终端只看到"下一步：/new-req"，无任何 `/project-solution` 提示 | `scripts/init-project.sh:38, 275`；`README.md:63, 65` |
| 3 | gsd 单一 agent 入口（`Gsd New Project`）让 PM 一个命令把骨架 + 方向讨论 + 多份文档全跑完，体验流畅；我们三步分裂，PM 必须记住中间步骤 | PM 提供的 gsd ChatBuilder 对话(2026-05-24)，对比鲜明 |
| 4 | `/new-req` mini-fill 兜底把 PROJECT.md 补上，**但 `roadmap.md` 漏补** —— bug 被静默遮蔽 | `skills/new-req/SKILL.md:68-102` 只查 PROJECT 6 节，不查 roadmap |

### §0.3 根因（解决什么底层 mechanism）

**结构问题**：`init-project.sh` 是 shell 脚本，跑完即返回终端，**没有跟 PM 对话的能力** —— 所以方向讨论必须拆出独立 skill `/project-solution`，PM 在 Claude Code 里再发起。两段中间靠 echo / README 文案粘合，文案就会漂（设计拆 skill 时漏改入口）。

**症状层**：4 处"下一步"文案漏 `/project-solution`，但这是结果不是原因；即使修了 4 处文案，下次拆别的 skill 还会漂。

**真正修法**：把入口从 shell 脚本改成 **agent 化 skill**（`/init-project` skill），agent 内部串起「Bash 调 init-project.sh 建骨架 → 接管 project-solution 提问 → 产出 PROJECT/roadmap → 给"复制即用"下一步」全流程，PM 体验上只跑一个命令。

### §0.4 不解决什么（防 review 拉进来）

| # | 衍生 / 假设场景 | 为什么不在 §0 范围 |
|---|---|---|
| 1 | 扩展 init 产出到 gsd 7 份（research/ARCHITECTURE/FEATURES/TECH/RISKS、STATE.md、AGENTS.md） | Q2 分析：我们 stage 体系已覆盖 ARCHITECTURE / FEATURES / TECH，项目级 RISKS 第一次写空对空，STATE 在 req 并行模型里反误导，AGENTS = CLAUDE.md 已注入。前置一次写一堆 = 价值密度低 + 跟 stage 重叠 |
| 2 | 把 `init-project.sh` 删掉改成纯 skill | 保留脚本作为骨架构建器被 agent 用 Bash 工具调；纯 skill 化会让 chmod / git init / 模板替换等机械步骤变成 agent 写代码，错误率高 |
| 3 | 业务仓里 PM 也能跑 `/init-project` | `/init-project` 只在生成器仓里跑（init-project.sh 拷贝时已排除 init-project skill），改造后保持这一约束 |
| 4 | 修 `/new-req` 步骤 3.5 mini-fill 加 `/project-solution` 漏跑检测 | mini-fill 是 legacy readiness gate，设计目标是老项目同步兜底；不在它上叠新逻辑。根因修在入口，不在兜底层 |
| 5 | 整体改名 `/init-project` → `/new-project` | Q1 决议：沿用 `/init-project`，含义扩张到包括方向讨论 |

→ **review 中任何 finding 指向以上场景的，默认 DEFER**（除非 PM 显式接受拉进 §0）

---

## §1 方案概述

把现有 `/init-project` skill 改造成 **agent 化的一气呵成入口**。PM 在生成器仓的 Claude Code 窗口里发 `/init-project`，agent 内部 4 阶段：

```
阶段 A · 前置检查 + 收集基础参数
  ├─ 检测 gstack / 当前 cwd 是不是生成器仓 / 目标目录是否存在 / brownfield 判定
  └─ 分批问 PM：项目名 / 落地路径 / 一句话背景 / project-intent

阶段 B · 建骨架（agent Bash 调 init-project.sh）
  ├─ shell 脚本跑完 → 业务仓骨架 + git init + 第一个 commit("init: <name>")
  └─ agent 汇报：✅ 目录 / 模板 / scripts / skills / agents / hooks 已就绪

阶段 C · QUESTIONING（**字面调用 `/project-solution` skill**）
  ├─ agent 用 Skill 工具 invoke `/project-solution`
  ├─ /project-solution 内部跑它现有的 Workflow（提问 / 收敛 / 二选一确认）
  ├─ /project-solution 返回后 agent 拿到完成状态 + 已写好的 PROJECT.md / roadmap.md
  └─ 阶段 C 不重复实现提问法 —— 提问纪律 / 5 组话术 / 写作规则的真相源**只在 /project-solution 一处**

阶段 D · 落档 + 下一步提示
  ├─ PROJECT.md / roadmap.md 已由 /project-solution 写好 + commit
  ├─ /init-project 在此追加：终态汇总输出
  └─ 终态输出："✅ <name> 已就绪 / 下一步(复制): cd <target> && /new-req \"...\""
```

**PM 体验**：一个命令进去，到 PROJECT.md + roadmap.md 落档为止，全程在生成器仓的 Claude Code 窗口里，不切窗口、不跑第二个命令、不需要记中间步骤。

---

## §2 与现有机制的关系

| 现有组件 | 改造方案 |
|---|---|
| `scripts/init-project.sh` | **保留**，作为骨架构建器被新 `/init-project` skill 用 Bash 工具调；脚本本身只动 echo 文案（删掉指向 `/new-req` 的"下一步"，因为入口改了）|
| `skills/init-project/SKILL.md` | **重写 Workflow**：从"调 shell 脚本"扩张到"4 阶段 agent 流程"；保持 frontmatter description |
| `skills/project-solution/SKILL.md` | **强化定位为「项目方向规划入口」**：被 `/init-project` 阶段 C 字面调用 + **4 个独立调用场景**仍是它的核心价值（不是"实质死亡兜底品") —— A 项目方向重做 / B 季度规划 / C 老板新方向 / D brownfield 项目接入定方向。Workflow 主体不动，frontmatter 重写定位说明 |
| `templates/PROJECT.md.tmpl` `templates/roadmap.md.tmpl` | **不动**，仍是 init-project.sh 复制的空骨架；agent 在阶段 D 填满 |
| `skills/new-req/SKILL.md` 步骤 3.5 mini-fill | **不动**，保留作为老项目同步兜底（设计意图回归本意）|
| `README.md` `RUNTIME.md` | **更新 4 处文案**：快速开始章节改成单步（`/init-project` 一气呵成），删掉两步说明 |

---

## §3 实施清单

按 vp（vertical prototype）切片，每片独立可测、可 commit：

### vp-1：阶段 A + B（前置检查 + 骨架建设）

- 改 `skills/init-project/SKILL.md`：扩 Workflow 阶段 A + B
- 阶段 A：用 AskUserQuestion 或文本分批问参数（项目名 / 路径 / 背景 / intent）
- 阶段 A 增加 brownfield 检测（Q3 = 加）：目标目录已含 `.git/` 或代码文件 → 不允许直接 init，提示"业务仓接入走 /codebase-audit 流程，不是新建项目"
- 阶段 B：agent 用 Bash 调 `bash scripts/init-project.sh ...`
- 改 `scripts/init-project.sh:36-39 + 268-276 + 38`：删掉 echo / --help 里指向 `/new-req` 的"下一步"文案（入口改了，不需要那段）
- **估时**：1.5h

### vp-2：阶段 C（字面调用 /project-solution）

- 新 `/init-project` Workflow 在阶段 C 段写明：「调用 `/project-solution` skill 完成方向讨论」（agent 用 Skill 工具 invoke）
- **不重复实现提问法** —— 提问纪律 / 5 组话术 / 写作规则真相源**只在 /project-solution 一处**
- 验证技术可行性：Skill 工具在 skill 内 invoke 另一个 skill（vp-5 测试时验证）
- 处理 sub-skill 返回值：`/project-solution` 跑完返回状态，`/init-project` agent 拿到后进阶段 D
- 异常处理：sub-skill 失败 / PM 中断 / 部分完成场景下，`/init-project` 的恢复策略
- **估时**：0.75h（比内嵌方案省 0.75h，因为不再重写提问法）

### vp-3：阶段 D（终态汇总 + 下一步）

- PROJECT.md / roadmap.md / commit 由阶段 C 调用的 `/project-solution` 已完成；阶段 D 不重复写
- `/init-project` agent 在阶段 D 收到 sub-skill 返回后做汇总输出
- 终态输出格式（含 ✅ 已就绪 + "复制即用"下一步）
- **估时**：0.25h（比之前减 0.25h，因为不重写文件）

### vp-4：文档同步

- 改 `README.md:55-94`（快速开始章节）：删两步说明改单步（`/init-project` 一气呵成）
- 改 `README.md:65`（"5 分钟你会看到"）：更新引号里终端文案
- 改 `RUNTIME.md` 新窗口续接命令（如有指向旧两步）
- 更新 `CHANGELOG.md` 未发布段
- **估时**：0.5h

### vp-5：测试 + 端到端验证

- 跑 `tests/run-all.sh` 确认 398/0 没变（新流程不触动测试基线）
- 用 `bash scripts/measure-tthw.sh` 跑一次完整新流程，计时（期望 init 自身 ~10 秒 + 方向讨论 5-15 分钟 + 落档 ~5 秒 ≤ 30 分钟）
- 准备消费仓真实跑通：在 ExampleConsumerApp 之外起一个新项目（比如 ChatBuilder 那种），全流程跑一遍，PM 验收体验
- **估时**：1h

### vp-6：`/project-solution` 定位强化（不是"兜底"，是规划入口）

- 在 `skills/project-solution/SKILL.md` frontmatter / When To Use 段**重写定位**：明确它是**项目方向规划入口**，覆盖 4 个独立调用场景：
  - A 项目方向重做（跑过几个 req 后发现产品定位偏了）
  - B 季度 / 半年规划（主动校准 PROJECT 6 节 + 重新排 roadmap）
  - C 老板 / 市场新方向（外部输入逼着改路线）
  - D brownfield 接入定方向（紧接 `/codebase-audit` 之后跑）
  - E 被 `/init-project` 阶段 C 调用（首次定项目方向）
- 删除原 frontmatter / When To Use 里"老项目同步兜底"等定位偏弱的描述（兜底 ≠ 价值，规划 = 价值）
- Workflow 主体不动 —— 现有提问法 / 收敛 / 二选一确认门都对，只是外层定位说明扩张
- **估时**：0.75h（比之前 0.25h 扩 0.5h，因为要重写 4 个使用场景的引导段）

**总估时**：~4.75h（不含 PM 验收）—— 比 v0 减 0.25h，因为字面调用 `/project-solution` 省了阶段 C/D 重写文件成本，加在 vp-6 定位重写

---

## §4 砍掉的机制清单（防被 review 加回来）

| # | 砍掉的 | 为什么砍 |
|---|---|---|
| 1 | 扩 init 产出到 7 份文档（research/STATE/AGENTS）| §0.4.1：跟我们 stage 体系重叠，价值密度低 |
| 2 | 把 init-project.sh 删掉改成纯 skill | §0.4.2：保留作骨架构建器更稳 |
| 3 | mini-fill 加 `/project-solution` 漏跑检测 | §0.4.4：根因修在入口，不叠兜底 |
| 4 | 改名 `/new-project` | §0.4.5 + Q1=a 决议 |
| 5 | 在业务仓也允许跑 `/init-project` | §0.4.3：保持只在生成器仓里跑的约束 |
| 6 | **删除 `/project-solution` skill** / 把它降级为 `/init-project` 内部子流程 | PM 2026-05-24 挑战澄清：`/project-solution` 是**项目方向规划入口**（不是一次性脚手架），4 个独立调用场景（重做 / 规划 / 新方向 / brownfield 接入）跟首次创建项目同等重要 —— 删了等于砍掉 PM 项目级规划能力 |
| 7 | **在 `/init-project` 阶段 C 内嵌一份提问法 / 话术副本** | 双份维护必漂移（跟"四处文案漂移"是同一种 pattern）；字面调用 `/project-solution` 让提问法真相源只在一处 |

---

## §5 风险与待验

### 风险

1. **agent 调 shell 后 cwd 问题**：agent 用 Bash 调 init-project.sh 后，Bash 工具的 cwd 是生成器仓根；后续阶段 D 写文件用绝对路径 `<target-dir>/...` 即可绕开，**不需要真 cd**。已验证 Claude Code Bash 工具 cwd 持久化机制 → 风险低
2. **阶段 C 太长 PM 没耐心**：参考 gsd 体验，分批问 + 选项简写答（`1A 2C`）+ 收敛即止；不一口气问 30 题 → 风险中
3. **brownfield 检测误伤**：目标目录已存在直接拒（沿用现有 init-project.sh 行为，§0.4.3）；但目标目录"不存在但父目录有其他项目"的情况，要不要扫一遍 → 待验
4. **Skill 工具能否在 skill 内 invoke 另一个 skill** ⚠️ **技术待验关键**：`/init-project` 阶段 C 需要字面调用 `/project-solution`。Claude Code Skill 工具在被调用的 skill 上下文里能否再 invoke 另一个 skill？如果不行，fallback 是"`/init-project` 阶段 C 提示 PM 自己发 `/project-solution`，等它跑完再回来"—— 但这会破坏"一气呵成"。**必须在 vp-2 实施前先做技术验证**（建一个最小可调通的 skill A 调 skill B 跑通）。如果技术上不可行，要回头评估 §1 设计 → 风险高
5. **sub-skill 异常处理**：`/project-solution` 跑到一半 PM 中断 / 报错 / 部分写完 PROJECT 后退出 —— `/init-project` agent 如何检测、如何告诉 PM "下次直接 `/project-solution` 续上即可，不用重跑 init-project"。需要在 vp-2 设计返回值约定 → 风险中

### 待验

| # | 待验项 | 验证方式 |
|---|---|---|
| 1 | PM 跑通新流程的实际体验（顺畅度对齐 gsd）| 端到端跑一次新项目（vp-5）|
| 2 | 阶段 C 5 组提问的 PM 耐心阈值 | 实际跑一次测耗时（vp-5 measure-tthw）|
| 3 | brownfield 边界情况误伤 | 准备 3 个测试场景：空目录 / 已存在含 git / 已存在含代码无 git |
| 4 | **Skill 工具能否在 skill 内 invoke 另一个 skill** | vp-2 实施前先做最小可行验证：写一个测试 skill A,内部用 Skill 工具调测试 skill B,看能否跑通 + 返回值能否拿到 |
| 5 | `/project-solution` 在被 `/init-project` 调用时 vs 独立调用时,体验是否一致 | vp-5 端到端测试时,先测独立调用一次,再测被 init-project 调用一次,对比两次的 PM 输入步数 + 产出 |

---

## §6 实证支撑

| 数据点 | 来源 |
|---|---|
| 4 处入口文案漏 `/project-solution` | grep 验证：`scripts/init-project.sh:38, 275`、`README.md:63, 65` |
| AI 第一次答漏掉 `/project-solution` | 本次对话（2026-05-24）|
| mini-fill 设计意图（老项目兜底）vs 实际遮蔽新项目 bug | `skills/new-req/SKILL.md:68-102, 102` 注释 |
| gsd 单一入口体验对比 | PM 提供的 ChatBuilder 完整对话（2026-05-24 21:30-23:30 段）|
| 我们三步分裂体验 | `skills/init-project/SKILL.md:58` 唯一正确指引藏在 PM 不读的 SKILL.md 里 |

---

## §X Review Findings

> 等设计文档共写完 / 锁 §0 后，autoplan / eng-review / ceo-review 跑完落这里。

---

## §Y 决议日志

| 日期 | 决议 | 影响 |
|---|---|---|
| 2026-05-24 | Q1=a 沿用 `/init-project` 名字 | skill 文件名 / 入口命令不动 |
| 2026-05-24 | Q2=a 保持产出范围（PROJECT + roadmap，不扩 7 份）| 阶段 D 范围锁定 |
| 2026-05-24 | Q3=加 brownfield 检测 | vp-1 阶段 A 加检测分支 |
| 2026-05-24 | Q4=b 先写设计文档 | 本文件 |
| 2026-05-24 | PM 挑战澄清：`/project-solution` 是项目方向规划入口（不是一次性脚手架）| §1 阶段 C 改字面调用 + §2 表更新定位 + §3 vp-2/vp-3/vp-6 重估 + §4 加 2 条砍机制 + §5 加 Skill-in-skill 技术风险 |

---

**End of /init-project 入口一气呵成 v0.1**（v0.1 = PM 挑战澄清 /project-solution 定位后的修订）
