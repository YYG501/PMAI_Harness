# Loop Contract（PMAI 主链共用）

Proposal、Design、Build 共用这一份循环协议。它规定 Agent 每轮怎样恢复事实、选择动作、验证结果和决定下一步；各 Skill 只补充本阶段的业务输入、允许动作和完成条件。

本合同不新增 `loop state`、task state、decision state 或动态工作流。`lifecycle` 继续是唯一持久状态；Proposal 合同、模块工作合同、Git 提交、source hash 和 evidence 继续是恢复依据。下面的动作名只是当前轮次的判断结果，不写入新的状态文件。

## 1. 每轮固定顺序

每次进入 Skill、收到 PM 新反馈、工具失败、权威文件变化或跨会话恢复时，都执行同一个顺序：

1. **恢复**：读取当前权威文件、机器合同、Git 状态和可恢复 checkpoint；Design 同时读取 `.work-meta.json:decision_gates` 的 pending / answered / consumed 与 answer event 归属。不能靠聊天摘要、cwd、分支名、文件时间或“最近一次”猜现场。
2. **确认目标**：用一句话确认本轮要得到的业务结果，以及当前应由 Proposal、Design 还是 Build 负责。
3. **确认边界**：检查当前依据是否仍有效、允许改哪些内容、哪些动作需要 PM 授权。依据无效或阶段不对时，在写入前分流。
4. **执行最小完整动作**：只做足以推进当前目标的一组连贯动作，不顺手扩展范围，也不在一次循环里混做两个阶段。
5. **验证实际结果**：读取文件、diff、命令结果、页面或证据，确认动作真的生效；不能用 Agent 自报完成替代结果证据。
6. **路由**：根据本轮新事实选择继续当前阶段、等待 PM、返回上游、进入下游、从 checkpoint 恢复或完成。路由后重新开始下一轮，不能沿用路由前的旧判断。

若步骤 1–3 不能确定唯一目标、唯一权威依据或安全写入边界，本轮只能停止或恢复，不能先动手再补判断。

## 2. 统一动作

| 动作 | 适用条件 | 下一步 |
|---|---|---|
| `retry_current` | 问题仍属于当前阶段，且目标与权威依据没有变化 | 在当前 Skill 修正最小缺口，再重新验证 |
| `await_pm_decision` | 存在真实产品分叉、one-way door 未授权、用户挑战未闭合或多个候选无法唯一定位 | 明确只问阻塞当前动作的业务决定；除登记 pending gate 外，未回答前不写产品权威文件、不提交、不 ready |
| `route_proposal` | 产品定位、目标用户、核心问题与价值、职责边界、MVP 证明目标或关键成立前提变化 | 先按现有重规划合同冻结 active candidate，再进入 Proposal |
| `route_design` | 模块对象、关系、动作、状态、权限、真相源、业务规则、信息结构、任务路径、关键交互或建造定义变化 | 先按现有重规划合同冻结 active candidate，再进入 Design |
| `advance` | 本阶段完成条件有新鲜证据，且下游输入已经形成 | 只进入固定的下游阶段，不跳级 |
| `resume_checkpoint` | 已存在可验证的未完成 checkpoint | 从精确 checkpoint 只补缺失项，不重放已完成动作 |
| `complete` | 当前请求已经完成，或只读验证证明没有需要修改的内容 | 返回结果；不制造新版本、空提交或重复工作 |

`decision-policy.md` 负责判断什么需要 PM 拍板；本合同负责判断这项工作应留在哪个阶段、何时重试、何时停止和如何恢复。两者不得互相复制。

## 3. 路由优先级

同一轮出现多个信号时，按以下顺序处理：

1. **恢复与安全先行**：合同无效、依据漂移、路径不安全、候选不唯一或 checkpoint 无法验证时，先停止或恢复；不得继续写入。
2. **产品方向高于模块设计**：同时触及产品方向和模块模型时，执行 `route_proposal`；Proposal 生效后再重新核对模块设计。
3. **模块模型高于实现调整**：同时触及模块规则和实现细节时，执行 `route_design`；不得把模型变化降级为 accepted delta。
4. **PM 最新反馈高于旧定稿意图**：final checks 期间收到新的产品或体验反馈，先回快速迭代并重新分流；纯验收发现的实现缺口可以保留原定稿意图。
5. **阶段证据高于口头进度**：只有验证通过才能 `advance`；“已经做了”“应该没问题”和工具自报成功都不构成完成证据。
6. **已完成 checkpoint 不重放**：landing 已完成就不重复 merge，Proposal 只读复核通过就不创建新版本，`ready_to_build` 已有效就不重写设计依据；同一 ready checkpoint 的重试只修复派生缓存并复用既有授权。

## 4. Proposal Loop Mapping

- **输入**：当前 Proposal/等价产品基线、`PRODUCT.md`、产品证据、被取代关系、产品级 handoff 和冻结候选。
- **允许动作**：区分事实/推断/假设，收敛产品级判断，询问真实产品分叉，生成或修改完整待确认版本，原子同步产品基线。
- **验证**：固定判断完整、版本关系唯一、Proposal 与 `PRODUCT.md`/机器合同一致、Git currentness 与精确提交范围通过。
- **当前阶段重试**：证据不足、完整版本内部矛盾、PM 对完整草案提出修改时，保持 Proposal 并修正整份判断。
- **等待 PM**：产品用户、价值、边界、MVP 或 one-way 定稿授权尚未闭合时，执行 `await_pm_decision`，未回答前不写正式基线。
- **进入下游**：原子提交和提交后 validate 均通过，执行 `advance → Design`。
- **完成出口**：完整性复核证明当前版本完整且未变化，执行 `complete`，不创建重复版本。

## 5. Design Loop Mapping

- **输入**：当前 Product Proposal/等价基线、模块三件套、context pack、相关现状与实现、replan candidate、评审 handoff 和 PM 新反馈。
- **允许动作**：恢复模块上下文，收敛对象/动作/状态/权限/页面/异常，按需调用 meta/mockup/spec-writing，并固定唯一 build 入口。
- **验证**：真实产品分叉已经闭合，每个新增/变化的模块决定都有绑定展示题、用户消息与 checkpoint 的 consumed gate；对象到页面的覆盖完整，规格没有用猜测补未知项，项目建造定义有效，ready currentness 与批准路径通过。
- **当前阶段重试**：模块模型仍有缺口、规格编译发现遗漏、mockup 暴露新模块问题时，执行 `retry_current` 并回到对应未知项。
- **返回上游**：产品定位、用户、价值、边界、MVP 或成立前提变化，执行 `route_proposal`；Proposal 生效后重新编译上下文并逐条复核旧模块结论。
- **等待 PM**：模块模型存在真实岔路、项目建造定义需要重定义或唯一主模块无法确定时，执行 `await_pm_decision`。
- **进入下游**：规格、决定、项目定义、checkpoint 与批准路径均有效，执行 `advance → Build`。

## 6. Build Loop Mapping

- **输入**：current `ready_to_build`、项目建造定义、build contract、目标与实现深度、当前 implementation commit、iteration/final evidence、replan candidate 和 PM 新反馈。
- **允许动作**：只在批准目标内实现，运行当前车道的检查，记录绑定 commit/source hash 的 evidence；仅对不改变产品基线和模块模型的已批准小调整记录 scoped adjustment。
- **验证**：每轮实现都先校验 currentness 和路径；快速车道只跑 iteration checks；PM 明确定稿后才冻结候选并运行 final checks；landing 与文档阶段分别复用现有 runner/checkpoint。
- **UI 前置验证**：高风险布局改动在首次编辑前检查共享 primitive / cascade，完成后用 browser 的实际尺寸断言验证 computed result；这是一项附加证据，不新增生命周期状态，也不能替代最终 browser acceptance。
- **当前阶段重试**：bug、样式、文案、局部交互偏差和验收发现的实现缺口执行 `retry_current`。纯验收缺口保留定稿意图并重跑失效的 final evidence；PM 新反馈先清定稿意图再重新分流。
- **返回上游**：产品方向变化执行 `route_proposal`；模块模型、关键路径、验收目标或 prototype real edge 变化执行 `route_design`；两者都不得写 accepted delta。
- **等待 PM**：新 build 的工作环境/构建工具确认、不可逆动作、多个 active build 无法唯一定位时执行 `await_pm_decision`。
- **进入下游**：PM 明确定稿且冻结候选的全部新鲜证据通过后，执行 `advance → final_check/landing`；没有明确授权不得提前进入。
- **恢复**：`final_check` 只补缺失验收/landing，`landed + docs_pending` 只补文档，`complete` 不再恢复。

## 7. 固定场景

这些场景是合同回归夹具，不是 Session Eval，也不证明真实 Agent 成功率。它们只锁定可确定的阶段、动作和 checkpoint 规则，供人工 dogfood 与未来 session case 复用。

| 场景 ID | 阶段 | 触发 | 动作 | 去向 | checkpoint 规则 |
|---|---|---|---|---|---|
| SCN-P01 | proposal | 当前完整 Proposal 校验通过且产品判断未变化 | complete | proposal | read_only_no_new_version |
| SCN-P02 | proposal | PM 修改待确认完整草案但产品层级不变 | retry_current | proposal | revise_full_draft |
| SCN-P03 | proposal | 产品用户价值边界或 MVP 存在真实分叉 | await_pm_decision | proposal | no_write_before_answer |
| SCN-P04 | proposal | 原子提交与提交后 validate 均通过 | advance | design | validated_product_baseline |
| SCN-D01 | design | 权限或关键任务路径仍有真实岔路 | await_pm_decision | design | displayed_pending_gate_no_authority_write |
| SCN-D02 | design | 产品定位目标用户价值边界或 MVP 前提变化 | route_proposal | proposal | revalidate_design_after_proposal |
| SCN-D03 | design | 规格编译发现模块覆盖遗漏 | retry_current | design | return_to_open_module_question |
| SCN-D04 | design | 决定规格项目定义和 ready currentness 全部通过 | advance | build | validated_ready_to_build_and_build_preflight |
| SCN-B01 | build | 实现与当前规格不一致或存在普通 bug | retry_current | build | keep_current_build |
| SCN-B02 | build | 模块对象权限规则关键路径或验收目标变化 | route_design | design | freeze_candidate_before_replan |
| SCN-B03 | build | 产品用户价值边界或 MVP 前提变化 | route_proposal | proposal | freeze_candidate_before_replan |
| SCN-B04 | build | PM 接受批准范围内且不改模型的小调整 | retry_current | build | record_scoped_adjustment |
| SCN-B05 | build | PM 明确定稿且当前候选可冻结 | advance | final_check | finalize_current_candidate |
| SCN-B06 | build | final checks 只发现实现缺口 | retry_current | build | preserve_finalization_intent |
| SCN-B07 | build | final checks 期间 PM 提出新的产品或体验反馈 | retry_current | build | clear_finalization_and_reclassify |
| SCN-R01 | recovery | final_check 中断且已有部分新鲜证据 | resume_checkpoint | final_check | run_missing_final_steps_only |
| SCN-R02 | recovery | 实现已 landed 但文档 pending 或 failed | resume_checkpoint | documenting | docs_only_no_remerge |
| SCN-R03 | recovery | 多个 active build 都可能匹配当前请求 | await_pm_decision | recovery | no_mtime_guess |

## 8. 停止条件

出现以下任一情况必须停止当前动作：

- PM 必须拍板的真实分叉或不可逆授权尚未回答；
- 当前权威来源无效、漂移、互相冲突或无法唯一定位；
- 动作会越出当前阶段权限或批准路径；
- 所需验证能力缺失，且合同不允许 exception；
- 用户已有 WIP 与本轮目标重叠，无法安全拆分；
- 当前步骤的失败已经改变产品或模块前提，继续重试只是在症状上打补丁。

停止时说明业务阻塞、已保留的 checkpoint 和恢复入口；不要把内部状态字段、命令菜单或排障细节变成 PM 的工作。

## 9. 明确不做

- 不让 Agent 自己发明新阶段、动态拓扑或开放式工作流。
- 不默认引入多 Agent；Builder 仍只是 Build 的受限执行器，主控负责验证与路由。
- 不把 Goal Engineering 变成另一份目标状态；目标继续来自 Proposal、模块规格和当前 PM 请求。
- 不把 Prompt 对比、模型成功率或策略优劣伪装成静态合同结论；这些问题以后进入 Session Eval。
- 不为复用而抹平 Proposal、Design、Build 的业务差异；共享的是循环纪律，不是产物和权限。
