# 飞书评审与产品生命周期交接

本合同只在 `/pmai-lark-review` 已于 Git 忽略的 `.pm-workflow/context/lark-review/` 中生成并校验当前批次的 `review.json`、`target.md`、`resolutions.json` 时生效。批次跨轮保留并优先恢复，只有 checkpoint 与下游生命周期都完成后才清理。普通 design、build、quick-fix 和 spec-writing 不改变原流程。

## 交接顺序

### 1. apply 前：只收敛候选决定并编译 T

- 正式规格正文仍是采集快照 L，只读；B / L / R 都不能成为写入目标。T 的目标底稿固定为 R 的 `remote_native_snapshot`，L 只能作为显式归位的补充证据。
- `discussion.md` / `decisions.md` 和 active build 合同也保持采集前状态。候选决定、预期 supersede 和 accepted delta 只写入 `resolutions.json`；其中 `decision_routing` 必须逐来源区分 `not_required / create / supersede` 并绑定目标、决定 ID 与原因。apply 成功前不得改写任何权威产品状态。
- spec-writing 把本批正式规格的实际输出改到 `$REVIEW_DIR/target.md`。T 只含正文，不带 frontmatter；所有检查和文字打磨也针对 T。
- T 若不再等于脚本机械归位结果，必须在 `resolutions.json:target` 记录 `mode=lifecycle_compiled`、非 `rule` 的确认依据和原因。飞书正文变化只有在 PM 本轮明确声明由自己修改 / 已认可，或看过全部差异后一次确认，才能作为该依据；revision 本身不证明作者或认可。
- `remote-coverage.json` 必须证明 R 的内容与原生格式全部归位；每个删除 / 改写都有规则、评论、决定或 PM 例外，强制预览已由 PM 确认，未归位为 0。
- 新 design 在此阶段停在规格编译完成点，不进入 `ready_to_build`；quick-fix 不创建只为修改正式规格的空 worktree。

### 2. apply：完成唯一一次正式规格写入

由 `/pmai-lark-review` seal T，再调用 `lark-review.py apply`。只有 apply 成功后，正式规格才从 L 变为 T。任何本地、飞书正文或评论围栏变化都重新 collect，不把旧计划带进下一轮。

### 3. apply 后：恢复既有生命周期

- 按候选路由选择性归档：产品规则变化写入 / supersede `decisions.md`；纯措辞、排版和格式不写 decision；active build 的实现合同变化另调用一次 `add-delta`。全部引用同一 batch ID，不得在此时重选另一套口径。归位失败就停止，不写飞书、不开始实现。
- 决定或 accepted delta 持久归位后，用 lark-sync 模式 A 按 apply plan 与 `remote-coverage.json` 对同一篇飞书文档做 XML 原生 block 精细同步并刷新发布基线；评论暂不解决。第一笔写入前重新 fetch，只有最新 revision 同时等于 apply plan 的 `remote_revision_id` 与首笔 expected revision 才能写；第一笔及后续每笔写操作继续携带对应 expected revision。刷新基线后运行 `lark-review.py verify-sync --manifest --plan`，正文投影、格式 hash、资源 token 或引用映射任一失败都停止。
- 新 design 重新生成 context pack，再按正常流程暂存并提交已经应用的正式规格、决定和其它建造依据，进入 `ready_to_build` 后启动 build。
- active build 以刚写入的 accepted delta 和已经应用的正式规格继续迭代；实现 worktree 不重复写一份评审规格。
- quick-fix 只处理规格之外的文档、原型或代码改动；正式规格不得进入 quick-fix diff。若本批只有规格文字变化，跳过空 worktree 和空提交。
- build 落地主线后的规格对账应以已应用的 T 为起点。本批已确认口径不再重写；若实现期间产生新的 accepted delta，按新的本地变化处理，不能偷改旧评审计划。

### 4. 验证后处理评论

只有受影响的决定、规格、prototype / product 和飞书原生格式回读全部验证完成，才调用一次 `lark-review.py complete-comments --manifest --plan`。局部评论结果必须已在 seal 前固化到 resolution；只有全文评论明确无法回复时可做 solve-only。命令在批次首尾各读取一次稳定全量围栏，中间逐笔保存回复 / solve 写响应；最终把绑定 batch / plan / 文档 / comment、结果 reply ID / 作者 / 正文 hash、`solver_user_id`、服务端实际 `solved_time` 和状态的证据写入同批 `comment-actions.json`。缺少 `solved_time` 时保持 null，以写响应 hash + 最终稳定回读收口；中断后重跑整批命令，不重复回复。旧 `complete-comment` 只用于兼容恢复。

checkpoint / reopen 只消费该回执，不接受 Agent 自填 reply、author 或 solver。未绑定的新回复一律视为新反馈，PM / 协作者手工解决的评论不能被 checkpoint 当作系统完成，也不能被 reopen。checkpoint 必须回读证明发布基线已经指向 T、飞书 revision 已与该基线一致，并逐条验证应完成评论的回执与当前状态一致、deferred 评论仍未解决；全量围栏中的任何批次外变化都重新 collect。实现失败不回退已经确认的目标规格，但评论保持未解决，并把实现缺口留在原生命周期。
