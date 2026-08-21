---
name: pmai-proposal
description: |
  产品级方向澄清与完整 Product Proposal 成文入口。用于新产品立项、产品定位与价值主张重判、目标用户或产品边界变化、MVP 投入判断，以及“为什么值得做 / 为什么现在做 / 为什么需要 AI”尚未讲清的场景；也用于已有项目方向失效后的完整改版。若方向已经确定、只是写介绍或汇报材料，走 /pmai-doc-writing；模块对象、规则、页面和交互设计走 /pmai-design；PRD 或功能规格走 /pmai-spec-writing。
---

# /pmai-proposal · 产品级方向澄清

## 入口护栏

先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill PROPOSAL || true
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止并引导 PM 先发 `/pmai-init-project`。

执行任何只读复核、方向修订或恢复前，先完整读取 `skills/_shared/loop-contract.md`。本 Skill 只补 Proposal 的业务输入、允许动作和完成条件；每次进入、收到新证据、PM 反馈、验证失败或跨会话恢复时，都按共享合同重新执行“恢复 → 目标 → 边界 → 最小完整动作 → 验证 → 路由”，不新增 Proposal 专属循环状态。

## 定位

Proposal 位于模块 design 之前，回答“这个产品为什么成立、值得先投什么”。全新项目默认先完成 Proposal；成熟项目只有接入流程已核验完整资料、`PRODUCT.md` 显式记录真实仓内依据和 PM 确认日期、机器状态为 `equivalent_baseline` 时才可直接 design。无论由初始化、方向纠正还是 PM 主动触发，一旦进入本 skill 就必须完成完整 Proposal。

一旦进入本 skill，就必须完成一份可独立评审的完整 Product Proposal。不得用 brief、方向摘要、问题清单、竞品报告或普通介绍稿代替；篇幅可以随产品复杂度缩放，但固定判断必须有明确结论、证据等级或验证方式。

Proposal 不替代 design：它定义产品级用户、问题、产品回答、价值、边界和 MVP 证明目标；对象关系、动作、状态、权限、页面、异常路径和建造规格仍由 `/pmai-design` 收敛。

## Proposal Loop Mapping

本阶段按 `loop-contract.md` 的 Proposal 映射执行：当前 Proposal/等价基线、产品证据、版本关系和冻结候选是输入；完整产品判断、版本草案与原子产品基线同步是允许动作；固定判断完整性、机器合同、Git currentness 和精确提交范围是验证。草案内部缺口执行 `retry_current`，真实产品分叉执行 `await_pm_decision`，提交并复验通过后执行 `advance → Design`。完整性复核通过时执行 `complete`：只读返回，不创建新版本或空提交。Proposal 的产品题和阶段路由题没有模块 `.work-meta.json`，统一使用 `decision-gate.py open-project → observe → answer-project → consume-project`；压缩摘要不能替代项目级 gate。

产品级判断是本阶段最高业务层级；若循环中只剩模块对象、规则、页面或交互问题，不在 Proposal 内继续展开，完成产品基线后交给 Design。若权威版本漂移、active build 未收口、写入边界重叠或 PM 尚未授权定稿，则在正式写入或提交前停止，并保留可验证的现有版本/候选作为恢复点。

## 触发与分流

| PM 的真实任务 | 入口 |
|---|---|
| 判断新产品是否成立，或重判定位、用户、价值、边界、MVP | 本 skill |
| 已有方向已经确定，只需写介绍、方向 memo、一页纸或汇报材料 | `/pmai-doc-writing` |
| 设计一个具体模块或把模块决定讨论清楚 | `/pmai-design` |
| 将已确认功能整理成 PRD / 功能规格 | `/pmai-spec-writing` |
| 补录已确认的待办、术语、规则或历史决定 | `/pmai-record` |

`/pmai-design` 和 `/pmai-record` 都不得修改 `docs/proposals/**`。发现当前 Proposal 已被新方向推翻时，返回本 skill 生成完整新版本。

## 权威边界

- `docs/proposals/<slug>-vN.md`：产品级判断、证据、取舍、价值链、MVP 与演进条件。
- `docs/proposals/INDEX.md`：供人阅读的当前版本与 supersede 关系索引。
- `.pm-workflow/proposal.json`：由 helper 生成的当前版本机器合同，绑定 Proposal ID、Proposal 正文 hash、`PRODUCT.md` 受保护产品基线 hash 与 supersede 关系；术语表等非产品基线章节仍可由其它入口正常维护。
- `PRODUCT.md`：从当前 Proposal 同步出的精简产品基线，保留当前版本、定位、核心问题与价值、用户、边界、MVP Case 和稳定术语。
- 模块三件套：具体模块的讨论、决定和规格，由 design 维护。
- `PRODUCT-STATE.md`：main 已落地事实；本 skill 禁止修改。

Proposal 是产品方向决策文档，不是当前实现事实，也不是 build 合同。

## Workflow

### 0. 活跃 build 的上游重规划收口

开始 Proposal 前先检查主仓与所有 attached worktrees。只要任一工作仍处于 `building / iterating / final_check`，就在对应 active 模块目录执行同一个重规划入口；成功后把本轮 `REPO_ROOT` 切回 `MAIN_REPO_ROOT`，再开始本 skill 的正常步骤：

```bash
REPLAN_JSON=$(python3 "$PMAI_HOME/scripts/replan-work.py" \
  "$ACTIVE_WORK_DIR" --route proposal)
CANDIDATE_MANIFEST_REL=$(python3 -c \
  'import json,sys; print(json.load(sys.stdin)["candidate_manifest_relative"])' \
  <<<"$REPLAN_JSON")
CANDIDATE_MANIFEST="$MAIN_REPO_ROOT/$CANDIDATE_MANIFEST_REL"
REPO_ROOT="$MAIN_REPO_ROOT"
python3 "$PMAI_HOME/scripts/replan-work.py" inspect "$CANDIDATE_MANIFEST"
```

- **worktree mode**：冻结旧分支的 `baseline..candidate_head`，删除两侧旧工作状态；不 merge、不进入清理队列，旧实现只作为后续核对材料。
- **main mode**：冻结 main 上的 `baseline..candidate_head`，只提交旧 `.work-meta.json` 的删除；已经进入 main 的实现原样保留，不回滚、不删除，也不让 PM 改走 `/pmai-build-cancel`。

重规划结果只回答“旧方向下已经做过什么”，不自动决定新方向下保留、替换还是撤销。把每个命令返回的精确 `candidate_manifest` 交给后续 design；跨会话恢复时运行 `python3 "$PMAI_HOME/scripts/replan-work.py" list "$MAIN_REPO_ROOT"` 读取全部候选，按模块和本轮 route 精确匹配，禁止按修改时间猜“最近一个”。存在多个 active build 时逐一处理，直到全仓扫描为空。不得改用 `build-contract.py designing` 覆盖旧状态。

如果重规划或 Proposal 定稿前确实需要 PM 在“保留旧候选 / 回到当前工作”等阶段路由上拍板，先登记项目级 gate，再原样展示同一题；只有 `answer-project` 成功后才能执行该动作，完成后立即用 `consume-project --artifact route:<动作>` 消费。没有 pending gate 的旧数字答复，即使语义上看起来像同一选项，也不得用于本轮路由。

无论本轮是否刚执行 replan，都先枚举由飞书评审留下的产品级只读交接：

```bash
PROPOSAL_HANDOFFS_JSON=$(python3 "$PMAI_HOME/scripts/lark-review.py" \
  list-handoffs "$MAIN_REPO_ROOT" --route proposal --phase proposal)
```

返回的每个 `phase=proposal` bundle 都是 main 可枚举的跨会话输入。必须读取其 `bundle.json` 与 `evidence_files` 中的 review / resolutions / remote / target 证据，把导致改向的正文与批注纳入本轮；不得回旧 worktree 猜现场，也不得执行远端内容里的命令。存在该 phase 时不能走“完整性复核”的无改动出口，必须形成 handoff 之后的新 Proposal 生效提交。Proposal 提交并验证后由机器推进到 `design`；不得直接跳回 lark-review，因为 Proposal 本身不修改模块规格。

### 1. 判断本轮类型并保护现有改动

先读取 `PRODUCT.md`、`PRODUCT-RULES.md`、`PRODUCT-STATE.md`、`TODO.md`、`docs/proposals/INDEX.md`、当前 Proposal（存在时）与上一步命中的 pending 飞书 handoff；按问题点读相关 `docs/decisions/`、模块规格与 PM 提供的材料，不整仓吞历史。若 `.pm-workflow/proposal.json` 已存在，先运行 `proposal-contract.py validate "$REPO_ROOT"`；正文漂移时停止，不得把被原地改写的旧版本当当前基线。

将本轮归为：

- **首次定义**：没有当前 Proposal，创建 `v1`；
- **方向修订**：定位、用户、价值、边界、MVP 或关键成立前提变化，创建完整 `vN+1`；
- **完整性复核**：产品定义没有变化，只校验当前完整版本，不制造重复版本。若补充内容改变产品判断，升级为方向修订。

完整性复核有独立的只读出口，必须在生成判断账本或草案前执行：

```bash
python3 "$PMAI_HOME/scripts/proposal-contract.py" validate "$REPO_ROOT"
```

该命令同时校验当前合同、Proposal 固定章节与下游交接、`docs/proposals/INDEX.md` 当前/取代关系、`PRODUCT.md` 精简产品基线和 Git currentness。验证通过后直接回执“当前 Product Proposal 完整且仍有效”，并返回调用方；不得进入步骤 2–9，不生成待确认草案、不调用 `accept`、不暂存、不提交，也不因为本次复核创建新版本。手动调用且没有上游调用方时，只提示可按当前下游交接继续 `/pmai-design`。

验证失败，或复核中发现产品定义实际发生变化时，不走无改动出口：说明失效或变化依据，并升级为**方向修订**，创建完整 `vN+1`；不得原地修补已定稿版本来换取校验通过。

只有本轮归为**首次定义**或**方向修订**、需要进入步骤 2–9 时，才在步骤 2 前完整读取：

- `references/proposal-method.md`：Proposal 内容结构与判断方法的唯一正本；
- `skills/_shared/decision-policy.md`；
- `skills/_shared/PM-VIEW-RULES.md`；
- `skills/_shared/pm-view/writing-rules.md`；
- `skills/_shared/pm-view/banner-rules.md`；
- `skills/_shared/pm-view/askuser-rules.md`。

完整性复核通过时直接按只读出口返回，不加载成文方法和写作规则，也不继续执行任何写入步骤。

开始写前记录目标文件的 Git 状态。`PRODUCT.md`、当前 Proposal 或索引已有与本轮无关的未提交修改时，停止并指出重叠；不得覆盖或把用户 WIP 卷入提交。同时运行 `git -C "$REPO_ROOT" diff --cached --quiet --`：只要当前已有任何 staged 改动就停止，请 PM 先处理，不能让 Proposal 提交卷入已有暂存内容。

Proposal 只能在主仓 `main/master` 定稿。旧 active build 尚未按步骤 0 冻结候选并清掉活动状态前，不得用新 Proposal 改写其上游依据；候选 manifest 留待下游逐项 reconcile，不阻塞 Proposal 成文。`proposal-contract.py accept` 会再次扫描主仓与所有 attached worktrees，并在发现 active build 时拒绝写入合同。当前位于 `build-*` worktree / 分支时只能读取或幂等校验已有 Proposal，不得在那里生成或提交新版本；收口后回到主线重新进入本 skill。

### 2. 建立证据账本和判断主线

按 `references/proposal-method.md` 形成：

- 本轮要支持的投入或方向决定；
- 已确认事实、有依据的推断、待验证假设；
- 最危险前提和会推翻当前方向的反例；
- 目标用户、现状替代、产品回答与职责边界；
- 价值因果链与最小可验证 MVP；
- AI 产品的 AI 必要性、人机分工和运行边界；非 AI 产品明确该项为什么不适用。

竞品或市场事实会改变方向时，优先查官方资料或一手证据，并记录链接与日期。没有证据时只能写“待验证”，不得制造市场空白、客户需求、业务基线或财务影响。

### 3. 只让 PM 拍真实产品分叉

按 `decision-policy.md` 过滤问题。机械项自动处理，可逆偏好给推荐并继续；只有会改变产品用户、核心问题、价值、职责边界、成功标准或 MVP 验证路径的真实分叉才停住。每次展示 Proposal 问题前必须先调用项目级 `decision-gate.py open-project`，把完整展示消息和选项登记下来；UserPromptSubmit 捕获答复后，先 `answer-project`，再继续本轮。

提问前先报告剩余真实决策数量；一次只问一题，用业务结果描述两个方向，并给推荐和代价。所有确认门遵守 `askuser-rules.md`：空答停止、未回答前不落盘、runtime 无 picker 时退化为编号列表后继续等待。

### 4. 收敛完整成文依据

写文件前先给 PM 一页式判断摘要：

```text
这份 Proposal 要支持的决定：<一句话>
当前建议：<一句话>
最危险前提：<一句话>
MVP 只证明：<一句话>
产品明确不负责：<一句话>
将同步到 PRODUCT.md：<当前版本 / 定位 / 核心问题与价值 / 用户 / 边界 / MVP Case / 术语的变化摘要>
```

然后使用 Decision gate：

Proposal 题使用项目级收据（不要伪造模块 `.work-meta.json`）：

```bash
GATE_JSON=$(python3 "$PMAI_HOME/scripts/decision-gate.py" open-project "$REPO_ROOT" \
  --kind "product-model" \
  --summary "<这题改变的产品结果>" \
  --message "<即将原样展示给 PM 的完整问题>" \
  --option "1=<选项一>" --option "2=<选项二>" \
  --allow-free-text)
GATE_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["gate_id"])' <<<"$GATE_JSON")
```

下一条用户消息由 hook 产生 `answer_event_id`；确认它确实回答当前题后调用：

```bash
python3 "$PMAI_HOME/scripts/decision-gate.py" answer-project "$REPO_ROOT" \
  --gate-id "$GATE_ID" --event-id "$ANSWER_EVENT_ID"
```

完成本题对应的 Proposal 草案、定稿或路由动作后立即消费：

```bash
python3 "$PMAI_HOME/scripts/decision-gate.py" consume-project "$REPO_ROOT" \
  --gate-id "$GATE_ID" --artifact "proposal:<draft|accept>|route:<action>"
```

- `生成完整 Proposal`：按当前结论生成完整版本；
- `继续讨论产品方向`：留在本 skill 补齐判断。

PM 未选择前不得写 Proposal、索引或 `PRODUCT.md`；没有本轮项目 gate 的 `answer` 收据时，项目级写入护栏必须拒绝。

### 5. 生成完整 Proposal 草案

按参考方法的固定结构生成 `docs/proposals/<slug>-vN.md`，状态先写“待确认”。完整文档必须包含：

1. 决策摘要与产品主张；
2. 产品成立的核心判断；
3. 用户、场景、问题与现状替代；
4. 产品回答与职责边界；
5. 必要能力与 AI 角色；
6. 替代方案、竞争判断与产品机会；
7. 端到端产品体验与关键能力；
8. 产品价值、因果链与指标；
9. MVP 范围、完整 Case Rundown 和继续 / 调整 / 停止门；
10. 演进条件与长期方向；
11. 固定的“下游交接摘要”。

不适用的内容保留简短结论和理由，不删除整项。开放问题放回它影响的判断旁边，并写验证方式；不得用一章开放问题替代产品结论。

### 6. 维护版本与索引

首次创建 `docs/proposals/INDEX.md` 时使用参考方法中的固定表格。

方向修订必须：

- 新建完整 `vN+1`，不得覆盖旧正文或只写 delta；
- 新文档写明 `取代：<旧版本路径>`；
- 旧文档只更新状态头为“已被 <新版本> 取代”，正文保持原样；
- 索引中只能有一个“当前”版本，历史版本保留可追溯。

纯措辞修订若不改变产品判断，可在待确认草案中继续修改；已经定稿的版本不原地改写，下一次正式变化统一生成新版本。

### 7. 预览、质检和最终确认

按参考方法逐项检查全文一致性，重点确认摘要、用户、产品边界、关键能力、价值链、MVP 和下游交接没有互相矛盾。

向 PM 展示：

- 当前建议与最危险前提；
- 新版本路径及被取代版本；
- 将进入 `PRODUCT.md` 的稳定基线；
- 仍待 MVP 验证的假设；
- 交给 design 的第一个结果。

最终 Decision gate：

- `定稿并同步产品基线`：将本版本设为“当前”，完成原子同步；
- `继续修改 Proposal`：保持“待确认”，按反馈修改完整草案后重新质检。

### 8. 原子同步 PRODUCT.md 并提交

PM 定稿后，才把当前 Proposal 中已经确认且长期稳定的内容同步到 `PRODUCT.md`：

- 当前 Product Proposal 的仓内相对链接，并移除 `PMAI_PROPOSAL_REQUIRED` 标记；
- 一句话产品定位；
- 主用户的核心问题、产品机制和可观察价值；
- 主用户及其核心诉求；
- 产品负责 / 不负责的边界；
- 一段精简 MVP Case：主用户、触发、关键任务和预期结果；
- 已稳定的业务术语。

完成本次定稿写入前必须确认当前项目 gate 已 `answer-project`；正文、索引、`PRODUCT.md` 和合同校验通过后，立即用 `consume-project --artifact proposal:accept` 消费定稿授权。不要把早先“生成草案”或“继续 Proposal”的答复当成定稿授权。

竞争结论、详细证据、完整价值链、MVP 指标与决策门、阶段计划、开放假设和产品愿景继续留在 Proposal，不塞进 `PRODUCT.md`。保留 `PRODUCT.md` 现有自定义内容，只精确修改受影响段落。

完成正文、版本状态、索引和 `PRODUCT.md` 后，先生成当前版本机器合同；Proposal ID 固定使用 `<slug>-vN`，方向修订时传入旧 Proposal ID：

```bash
python3 "$PMAI_HOME/scripts/proposal-contract.py" accept "$REPO_ROOT" \
  --proposal "docs/proposals/<slug>-vN.md" \
  --id "<slug>-vN"

# 方向修订时使用：
python3 "$PMAI_HOME/scripts/proposal-contract.py" accept "$REPO_ROOT" \
  --proposal "docs/proposals/<slug>-vN.md" \
  --id "<slug>-vN" \
  --supersedes "<旧-proposal-id>"
```

helper 必须成功并写出 `.pm-workflow/proposal.json`；生成合同后不得再改 Proposal 正文或 `PRODUCT.md` 中受保护的产品判断，否则对应 hash 失效。术语表等非产品基线章节不在这条锁定边界内。此时合同只是待提交，不得调用 status、context pack 或下游 skill 把它称为已生效。

把新 Proposal、旧版本状态头（如有）、`docs/proposals/INDEX.md`、`PRODUCT.md` 和 `.pm-workflow/proposal.json` 作为一个原子变更提交；逐个列出路径，禁止 `git add -A`：

```bash
git -C "$REPO_ROOT" add -- \
  "docs/proposals/<slug>-vN.md" \
  "docs/proposals/INDEX.md" \
  "PRODUCT.md" \
  ".pm-workflow/proposal.json"
# 方向修订时再显式加入被取代的旧 Proposal
git -C "$REPO_ROOT" add -- "docs/proposals/<旧-slug>-vN.md"

# 必须逐项核对：输出只能包含上面的本轮原子路径，不能多、不能少
git -C "$REPO_ROOT" diff --cached --name-only
git -C "$REPO_ROOT" commit -m "docs: approve product proposal <slug> vN"

# 提交后复验 Git currentness；只有成功后才能回执定稿
python3 "$PMAI_HOME/scripts/proposal-contract.py" validate "$REPO_ROOT"

# 对 PROPOSAL_HANDOFFS_JSON 中每个 bundle 逐项执行；机器只接受紧邻阶段
python3 "$PMAI_HOME/scripts/lark-review.py" advance-handoff \
  "<handoff_bundle>" --to design
```

暂存清单有额外路径或缺少本轮路径时停止，不得提交。提交或提交后 `validate` 失败时不得声称同步完成；保留可见改动并说明失败原因。只有同一提交成功且复验通过后，新 Proposal 和同步后的 `PRODUCT.md` 才共同成为当前产品基线；有 `phase=proposal` handoff 时，全部 `advance-handoff` 也必须成功后才能交给 design。

### 9. 固定下游交接

完成回执只给一个主线下一步。没有 pending 飞书产品级 handoff 时，使用 Proposal “下游交接摘要”中的第一个可建造结果：

```text
Product Proposal 已定稿：docs/proposals/<slug>-vN.md
产品基线已同步：PRODUCT.md

## ▶ Next Up — /pmai-design "<MVP 第一个可建造结果>"
```

`/pmai-design` 必须读取当前 Proposal 的“下游交接摘要”，但不得回写 Proposal。后续方向再次变化时，重新进入本 skill。

存在 pending 飞书产品级 handoff 时，先按 `handoff_bundle` 中的文档与模块去重形成下游覆盖队列；回执仍只突出第一条可执行动作，其余条目作为后续队列列出，不把多个模块拼成一条命令：

```text
Product Proposal 已定稿：docs/proposals/<slug>-vN.md
产品基线已同步：PRODUCT.md

飞书评审影响的规格将按顺序重新核对：<模块或功能型规格列表>

## ▶ Next Up — /pmai-design "<第一项>"
```

每项 design / spec-writing 都必须读取同一个 bundle 的证据并按新 Proposal 更新权威规格；全部受影响规格处理完成后才回 `/pmai-lark-review` 同步原文、fresh collect、验证实现并闭合评论。Proposal 不修改模块规格，也不把“Proposal 已覆盖”误报成整批评审已经完成。Proposal 不得直接跳回 lark-review，因为它本身不修改模块规格。

## Rules

- Proposal 对已通过上述显式等价基线机器门的成熟项目可跳过；全新项目默认先完成。首次定义或方向修订只要进入就必须完成完整文档，不提供简版、半份或只给大纲的退出方式；完整性复核只读验证已经完整的当前版本，不制造重复版本。
- 产品方向改变时创建完整新版本并 supersede 旧版；不覆盖已定稿正文，不写增量补丁稿。
- 事实、推断、假设分开；无客户、市场、竞品或财务证据时明确待验证。
- AI 只在具体任务上证明必要性；确定性工作优先交给确定性软件。
- MVP 必须验证“判断或能力变化 → 用户行动 → 结果变化”，不以功能完成或模型指标单独宣告成功。
- `PRODUCT.md`、Proposal 版本关系和 `.pm-workflow/proposal.json` 同一提交原子同步；本 skill 不改 `PRODUCT-STATE.md`、模块三件套、`project.yml`、代码或 mockup。
- doc-writing 可以读取 Proposal 生成派生材料；design、record、doc-writing、spec-writing 都不得修改 Proposal。
- PM-facing 输出使用业务语言，不展示 hash、工作区、状态机或内部编排术语。
- 每次进入、反馈和恢复都遵守 `skills/_shared/loop-contract.md`；本 Skill 不复制一套 Proposal 专属 loop state。
