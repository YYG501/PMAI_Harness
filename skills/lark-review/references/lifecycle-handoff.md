# 飞书评审与产品生命周期交接

本合同只在 `/pmai-lark-review` 已于 Git 忽略的 `.pm-workflow/context/lark-review/` 中生成并校验当前批次时生效。`list-resumables` 从 main 与 attached worktree 恢复普通未完成批次；checkpoint 写入同批完成收据后不再恢复。转成只读 handoff 后，旧批永不 apply，由 main bundle 按机器 phase 接力 Proposal / design / spec-writing，再回同篇飞书 fresh collect。

## 交接顺序

### 1. apply 前：只收敛候选决定并编译 T

- 正式规格正文仍是采集快照 L，只读；B / L / R 都不能成为写入目标。T 的目标底稿固定为 R 的 `remote_native_snapshot`，L 只能作为显式归位的补充证据。
- `discussion.md` / `decisions.md` 和 active build 合同也保持采集前状态。候选决定、预期 supersede 和 accepted delta 只写入 `resolutions.json`；其中 `decision_routing` 必须逐来源区分 `not_required / create / supersede` 并绑定目标、决定 ID 与原因。对仍会 seal / apply 的普通批次，apply 成功前不得改写任何权威产品状态。
- 主执行路径在 seal 前固化。产品级变化在无 active build 时用 `handoff --route proposal` 直接生成只读交接；存在 active build 时先由 `replan-work.py` 固定 candidate，再用同一路由 handoff。模块模型变化用 `handoff --route design`，必要时同样先固定 candidate。命令把不可变证据复制到 main bundle，旧批从普通恢复中排除并拒绝 reconcile / seal / apply。`route` 只记录来源，恢复只看 `phase`：产品级按 `proposal → design → lark_review → closed`，模块级按 `design → lark_review → closed`。Proposal 只有形成并验证 handoff 之后的新生效提交，才能 `advance-handoff --to design`；design 只有提交绑定规格且当前文件仍等于该 Git blob，才能 `advance-handoff --to lark-review --evidence-commit <SHA>`；禁止跳级、倒退或口头声称已覆盖。`closed` 只能由同 main、同规格、同 Docx 的 fresh checkpoint 写入。只有不改变对象、关系、业务规则、权限模型或关键任务路径的当前模块小调整，才允许继续 `scoped-adjustment`。
- spec-writing 把本批正式规格的实际输出改到 `$REVIEW_DIR/target.md`。T 只含正文，不带 frontmatter；所有检查和文字打磨也针对 T。
- T 若不再等于脚本机械归位结果，必须在 `resolutions.json:target` 记录 `mode=lifecycle_compiled`、非 `rule` 的确认依据和原因。飞书正文变化只有在 PM 本轮明确声明由自己修改 / 已认可，或看过全部差异后一次确认，才能作为该依据；revision 本身不证明作者或认可。
- `remote-coverage.json` 必须证明 R 的内容与原生格式全部归位；每个删除 / 改写都有规则、评论、决定或 PM 例外，强制预览已完成验收，未归位为 0。纯排版 / 结构保真可记录 `agent_reviewed`，真实产品分叉才使用 `pm_confirmed`。
- 存在候选产品决定时，`resolutions.json:consistency` 必须将每条候选与仓内全部当前有效决定逐一对照，并绑定当前 T 和决定源摘要。缺项、过期或任一 `needs_pm` 都不能 seal；只有后者按 decision policy 打断 PM。active build 小调整则必须在 `active_build_delta` 固化当前 module、work ID、批准 source hash、design revision、PM 新口径、影响面、term/role 影响和全部正文 / applied 评论来源；它不能与任何 `create / supersede` 决定同时存在，且 T 去掉发布 frontmatter 后必须相对上一 authority checkpoint 真实变化。
- 新 design 在此阶段停在规格编译完成点，不进入 `ready_to_build`；quick-fix 不创建只为修改正式规格的空 worktree。

### 2. apply：完成唯一一次正式规格写入

由 `/pmai-lark-review` seal T，再调用 `lark-review.py apply`。只有 apply 成功后，正式规格才从 L 变为 T。任何本地、飞书正文或评论围栏变化都重新 collect，不把旧计划带进下一轮。`handed_off` 批次不进入本节：旧 T 永不 apply，只保留为上游交接证据。

### 3. apply 后：恢复既有生命周期

- apply 后不重新分类，只执行 seal 前固化的路由。所有产品级路径与 active 模块模型路径都不会进入本节；它们已经把旧批次转为只读 handoff。新 design 按候选路由选择性写入 / supersede `decisions.md`；纯措辞、排版和格式不写 decision。
- 当前批次直接按 `skills/_shared/lark-writeback.md` 的内部合同，依据 apply plan 与 `remote-coverage.json` 对同一篇飞书文档做 XML 原生 block 精细写回并刷新发布基线；不得调用另一个公开 Skill，评论暂不解决。第一笔写入前重新 fetch，只有最新 revision 同时等于 apply plan 的 `remote_revision_id` 与首笔 expected revision 才能写；第一笔及后续每笔写操作继续携带对应 expected revision。刷新基线后运行 `lark-review.py verify-sync --manifest --plan`，正文投影、格式 hash、资源 token 或引用映射任一失败都停止。到这里发布 frontmatter 必须稳定，后续 authority checkpoint 前不得再次同步或改写这些字段。
- 只有已固化的 active-build `scoped-adjustment` 路径继续：基于稳定规格重新编译当前模块 context pack，再调用一次带固定 scope attestation、`lark-review-batch`、sealed batch ID、同批 `remote-verification.json` 与 `--applied-context-pack <pack>` 的 `add-delta`。合同通过 lark-review 的共享 sealed validator 重放完整批次，并要求 CLI 的 summary、affected surfaces、term/role affects 与 `active_build_delta` 完全一致；随后只记录当前模块 `spec.md` 为 `authority_paths`，复核其正文相对上一 authority checkpoint 确有变化，并校验没有其它 authority 文档变化。不得手填 hash、扩大文档范围、只改发布 frontmatter 或用普通 delta 吞掉规格变化。
- `add-delta` 后精确暂存并提交当前模块 `spec.md + .work-meta.json` 作为 authority checkpoint；再用 `build-contract.py commit --implementation-commit <checkpoint>` 记录当前 candidate，并单独提交更新后的 `.work-meta.json`。delta 同时绑定当前 HEAD；commit 机械校验 checkpoint 承接上一权威提交并直接接在该 HEAD 后、单提交路径和 baseline→candidate 范围，并核对 spec Git blob 与 pack 内容绑定、meta blob 与当前合同；任一失败就停止，不开始实现。
- 新 design 重新生成 context pack，再按正常流程暂存并提交已经应用的正式规格、决定和其它建造依据，进入 `ready_to_build` 后启动 build。
- active build 以刚写入的 accepted delta 和已经应用的正式规格继续迭代；实现 worktree 不重复写一份评审规格。
- 轻微修正只有在无 active build 时才进入 quick-fix；有 active build 时回原 build 直接纠正规格之外的实现，规格语义未变就不写 accepted delta。正式规格不得进入 quick-fix diff；若本批只有规格文字变化，跳过空 worktree 和空提交。
- build 落地主线后的规格对账应以已应用的 T 为起点。本批已确认口径不再重写；若实现期间产生新的 accepted delta，按新的本地变化处理，不能偷改旧评审计划。

### 4. 验证后处理评论

只有受影响的决定、规格、prototype / product 和飞书原生格式回读全部验证完成，才调用一次 `lark-review.py complete-comments --manifest --plan`。局部评论结果必须已在 seal 前固化到 resolution；只有全文评论明确无法回复时可在默认模式做 solve-only。默认模式回复并解决；PM 要求自行核验后解决时增加 `--reply-only`，只回复并记录 `replied_pending_pm`，随后由 `verify-comments` 回读 PM 手工解决，全部核验后记录 `solved_by_pm_verified`。命令在批次首尾各读取一次稳定全量围栏并逐笔保存写响应；中断后按原模式重跑，不重复回复。旧 `complete-comment` 只用于兼容恢复。

checkpoint / reopen 只消费该回执，不接受 Agent 自填 reply、author 或 solver。未绑定的新回复一律视为新反馈；未经 reply-only 受控回复和 `verify-comments` 核验的外部手工解决不能进入 checkpoint，任何 PM 手工解决都不能被 reopen。checkpoint 必须回读证明发布基线已经指向 T、飞书 revision 已与该基线一致，并逐条验证应完成评论的回执与当前状态一致、deferred 评论仍未解决；全量围栏中的任何批次外变化都重新 collect。实现失败不回退已经确认的目标规格，但评论保持未解决，并把实现缺口留在原生命周期。
