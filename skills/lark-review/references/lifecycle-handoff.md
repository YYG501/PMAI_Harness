# 飞书评审与产品生命周期交接

本合同只在 `/pmai-lark-review` 已于 Git 忽略的 `.pm-workflow/context/lark-review/` 中生成并校验当前批次的 `review.json`、`target.md`、`resolutions.json` 时生效。批次跨轮保留并优先恢复，只有 checkpoint 与下游生命周期都完成后才清理。普通 design、build、quick-fix 和 spec-writing 不改变原流程。

## 交接顺序

### 1. apply 前：只收敛候选决定并编译 T

- 正式规格正文仍是采集快照 L，只读；B / L / R 都不能成为写入目标。
- `discussion.md` / `decisions.md` 和 active build 合同也保持采集前状态。候选决定、预期 supersede 和 accepted delta 只写入 `resolutions.json`；apply 成功前不得改写任何权威产品状态。
- spec-writing 把本批正式规格的实际输出改到 `$REVIEW_DIR/target.md`。T 只含正文，不带 frontmatter；所有检查和文字打磨也针对 T。
- T 若不再等于脚本机械归位结果，必须在 `resolutions.json:target` 记录 `mode=lifecycle_compiled`、非 `rule` 的确认依据和原因。飞书正文变化只有在 PM 本轮明确声明由自己修改 / 已认可，或看过全部差异后一次确认，才能作为该依据；revision 本身不证明作者或认可。
- 新 design 在此阶段停在规格编译完成点，不进入 `ready_to_build`；quick-fix 不创建只为修改正式规格的空 worktree。

### 2. apply：完成唯一一次正式规格写入

由 `/pmai-lark-review` seal T，再调用 `lark-review.py apply`。只有 apply 成功后，正式规格才从 L 变为 T。任何本地、飞书正文或评论围栏变化都重新 collect，不把旧计划带进下一轮。

### 3. apply 后：恢复既有生命周期

- 立即把本批候选决定正式写入 `discussion.md` / `decisions.md`，或对 active build 调用一次 `add-delta`；全部引用同一 batch ID，不得在此时重选另一套口径。归位失败就停止，不写飞书、不开始实现。
- 决定或 accepted delta 持久归位后，用 lark-sync 模式 A 精细同步同一篇飞书文档并刷新发布基线；评论暂不解决。第一笔写入前重新 fetch，只有最新 revision 同时等于 apply plan 的 `remote_revision_id` 与首笔 expected revision 才能写；第一笔及后续每笔写操作继续携带对应 expected revision。
- 新 design 重新生成 context pack，再按正常流程暂存并提交已经应用的正式规格、决定和其它建造依据，进入 `ready_to_build` 后启动 build。
- active build 以刚写入的 accepted delta 和已经应用的正式规格继续迭代；实现 worktree 不重复写一份评审规格。
- quick-fix 只处理规格之外的文档、原型或代码改动；正式规格不得进入 quick-fix diff。若本批只有规格文字变化，跳过空 worktree 和空提交。
- build 落地主线后的规格对账应以已应用的 T 为起点。本批已确认口径不再重写；若实现期间产生新的 accepted delta，按新的本地变化处理，不能偷改旧评审计划。

### 4. 验证后处理评论

只有受影响的决定、规格、prototype / product 和飞书回读全部验证完成，才逐条调用 `lark-review.py complete-comment --manifest --plan --comment-id --result-text`。本地规格由批次清单唯一绑定，不再额外接收路径。局部评论必须写结果；只有全文评论明确无法回复时可省略 `--result-text` 做 solve-only。命令负责回复、解决、回读，并把绑定 batch / plan / 文档 / comment、结果 reply ID / 作者 / 正文 hash、`solver_user_id`、`solved_time` 和最终状态的受控证据原子写入同批 `comment-actions.json`。

checkpoint / reopen 只消费该回执，不接受 Agent 自填 reply、author 或 solver。未绑定的新回复一律视为新反馈，PM / 协作者手工解决的评论不能被 checkpoint 当作系统完成，也不能被 reopen。checkpoint 必须回读证明发布基线已经指向 T、飞书 revision 已与该基线一致，并逐条验证应完成评论的回执与当前状态一致、deferred 评论仍未解决；全量围栏中的任何批次外变化都重新 collect。实现失败不回退已经确认的目标规格，但评论保持未解决，并把实现缺口留在原生命周期。
