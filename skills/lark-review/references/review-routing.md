# 飞书评审归类与分流

## 目录

- [1. 证据语义](#1-证据语义)
- [2. 定位准确度](#2-定位准确度)
- [3. 版本归位](#3-版本归位)
- [4. 影响分类](#4-影响分类)
- [5. 批次升级规则](#5-批次升级规则)
- [6. 决定归档](#6-决定归档)
- [7. Legacy 基线](#7-legacy-基线)
- [8. 评论完成条件](#8-评论完成条件)

## 1. 证据语义

按下面顺序理解同一处反馈：

1. 飞书正文直接修改只是内容变化证据；Docx revision 不能可靠证明修改者身份或 PM 已认可。
2. 评论卡片的完整 replies 才是完整语义；后续回复可以修正首条评论，不能只读 quote 或第一条。
3. “改成 X”“这里应使用 Y”且上下文唯一，是明确指令。
4. “是否考虑 X”“感觉不对”“建议看看 Y”是问题或候选，不是决定。
5. 已解决评论默认不是本轮输入；只有 PM 明确要求复查历史评论，或旧 checkpoint 因评论竞态被拒绝而需要恢复时，才用 `collect --include-solved` 读取。后者会把 checkpoint 后有更新的已解决评论重新纳入处置账本。
6. checkpoint 前未更新的未解决评论仍展示，但不重复当成新指令；出现新回复后重新进入本轮。

只有 PM 在本轮明确说明正文是自己修改或已经认可，正文增量才可自动视为已确认。否则必须先完整展示整批正文差异，只问一次是否全部认可，并允许 PM 一次指出例外；拿到回答前不 seal / apply，不逐条追问。正文即使已经确认，仍需按影响进入 design/build；“已确认”只表示不重复询问采用与否，不表示可以绕过产品上下文更新。

## 2. 定位准确度

| collector 结果 | 可以做什么 |
|---|---|
| `relation_exact` | 以 block ID 为准确位置，结合所在章节判断影响 |
| `parent_resource_exact` | 只确认到嵌入资源；内部记录、单元格或画板节点需下钻 |
| `whole_document` | 全文评论，只能结合完整正文理解，不能回复时按完成条件决定是否直接解决 |
| `content_deleted` | 原引用已删除；保留原 relation，但不能按旧 block 自动修改 |
| `quote_inferred` | 只能称为推断；确认上下文唯一后才能修改 |
| `quote_ambiguous` / `unlocated` | 不猜落点；先扩大读取范围或问 PM |

`content_deleted=true` 时，评论原位置已经不存在。只能根据完整回复和当前规格重新判断，不得把旧 quote 强塞回正文。若意见仍未处理且明确留到以后，标记 `deferred` 并保持未解决；若旧内容已经被当前确认方案替代，标记 `superseded`，回复当前落点后可正常收口。定位消失本身不能自动推出任何一种状态。

## 3. 版本归位

始终把 `B / L / R / T` 当作不同身份：B 是比较证据，L 和 R 是采集快照，T 才是目标正文。不得用路径名、文件新旧时间或“看起来更完整”猜真相源。

- T 的唯一内容与格式底稿始终是当前飞书 R 的 `remote_native_snapshot`；B/L 只用于识别需要补回或冲突的本地增量；
- B 与本地发布 source hash 兼容时，才允许用三方差异机械定位不重叠项；兼容性不参与底稿选择；
- local-only 作为对 R 的显式补充归位，remote-only 默认保留 R；能机械定位不等于已经获得 PM 认可；
- 同一区域双边变化必须显式选择 local / remote / merged；
- B 缺失或与本地源格式不兼容时，禁止 raw Markdown 三方合并，但 T 仍从 R 初始化；没有本轮明确依据时仍走一次整批确认；
- 每个 R→T 删除或改写必须在 `remote_coverage` 绑定格式规则、评论、已确认决定或 PM 例外；内容和原生格式存在未归位项时不能 seal；
- 评论只改变 T 或其它受影响对象，不改写 B / L / R；
- 评论标记 `applied` 时，T 必须经过生命周期重新编译并产生实际正文变化；已有口径用 `already_satisfied`，不改规格用 `no_spec_change`；
- 手工 `merged` 必须形成独立合并结果，不能把完整 L 或完整 R 复制成 T 后冒充合并；
- T seal 后任一快照、本地正文、飞书 revision 或评论变化，都使旧 plan 失效。

## 4. 影响分类

### A. 文档与轻微实现修正

- 错字、标点、格式、链接和不改变产品含义的措辞；
- 单个 UI 文案或局部样式；
- 现有规格已经唯一说明正确行为，原型 / 产品只是局部做错；
- 不改变对象、动作、状态、权限、规则、页面任务或验收含义。

无 active build 时可走 quick-fix；有 active build 时回原 build 迭代。若规格已经唯一说明正确行为，只是实现、文案、样式或局部交互做错，直接纠正实现，不写 accepted delta。

### B. 产品级变化

下列任一变化都必须回完整 `/pmai-proposal` 生成并确认新版本，不因已有 active build 而降级为 accepted delta。当前评审批次一律先转为只读 handoff，旧 T 永不 apply 并从恢复扫描排除：无 active build 时直接用 `lark-review.py handoff --route proposal` 绑定当前 main 产品基线；命中 `building / iterating / final_check` 的 main 或 worktree build 时，先运行 `replan-work.py ... --route proposal`，再用返回的精确 candidate manifest 调用 handoff。两条路径都必须生成 main `handoff_bundle`；bundle 初始 `phase=proposal`，后续会话由 Proposal 按该 phase 恢复正文、评论和候选结论，`route` 只保留最初分流来源。

- 产品定位、目标用户、核心问题与价值；
- 产品职责边界、MVP 证明目标或关键成立前提。

Proposal 确认后重新检查本批模块结论；与新产品基线冲突的旧决定必须明确 supersede。

### C. 模块级变化

下列任一变化都进入 design，影响实现时随后进入 build；同模块已有 active build 也必须先回 `/pmai-design`，不得写 accepted delta。命中 `building / iterating / final_check` 的 main 或 worktree build 时，先运行 `replan-work.py ... --route design`，再用返回的精确 candidate manifest 调用 `lark-review.py handoff`；旧批次不得 seal / apply。main `handoff_bundle` 初始 `phase=design`，后续会话由对应 design 按该 phase 和模块精确恢复，`route` 只保留最初分流来源：

- 产品对象、对象关系或责任归属；
- 用户可执行动作、状态流转、权限或可见范围；
- 真相源、业务规则、异常处理或成功标准；
- 页面任务、信息结构、关键交互或跨模块合同；
- 规格和原型 / 产品需要同时改变。

已经由本轮明确声明或整批确认接受的正文修改触发本类时，把它记录为 PM 已接受的新决定；评论触发本类但仍是问句时，先按 decision policy 收敛真实岔路。

### D. Active build 内的小范围调整

同模块已有 active build 时，只有同时满足以下条件才可回原 build 写 accepted delta：

- 调整位于已批准模块与当前任务内；
- 不改变产品定位、用户、价值、边界、MVP 或关键成立前提；
- 不改变对象、关系、动作、状态、权限、真相源、信息结构、任务路径或关键交互。

这类调整只可改变已批准范围内的小范围行为或体验。无法唯一归入本类时，按 B/C 的更高影响路径处理。

### E. 冲突或未知

- 本地与飞书从同一发布基线分别修改了同一语义；
- 正文修改与评论要求互相冲突；
- 多条评论给出不同结论；
- 评论位置不唯一，或缺少完成修改所需的业务信息。

先给证据、影响和推荐，只问一个会改变业务结果的问题。不能用整篇 remote-wins 或 local-wins 掩盖冲突。

只有开放性问句、没有足够用户场景证据时，推荐默认保持当前已确认范围，把候选能力留待后续 design；同时明确这是基于证据不足的最小范围建议，不能把 AI 的范围偏好包装成产品事实。

## 5. 批次升级规则

整批影响级别取最高项：`冲突待决 > 产品级变化 > 模块级变化 > active build 小范围调整 > 轻微修正`。

- 有冲突：先解决冲突，再重新判断整批路径。
- 有任一产品级变化：整批先 handoff，再回 Proposal；确认后重新判断模块结论，旧批不 apply。
- 有任一模块级变化：整批回 design/build；不得因 active build 写 accepted delta。
- 只有 active build 小范围调整：整批回原 build 形成 accepted delta。
- 全部是轻微修正且没有 active build：才允许 quick-fix。
- 同模块已有 active build：优先复用该 build，不另开 quick-fix 或第二个 build；纯实现纠偏不写 delta。

这样同一轮评审只产生一版规格、一组决定和一个可验收结果。

## 6. 决定归档

飞书变化不等于都要写 `decisions.md`。只在变化新增、改变或推翻产品对象、状态、权限、业务规则、真相源、异常处理或成功标准时，写一条新决定或 supersede 旧决定；记录 batch ID、飞书 URL 和相关 comment ID。

错字、措辞、排版、格式、示例补充，以及不改变既有产品规则的解释，只更新 T / spec，不写 decision。active build 只有小范围调整才写 accepted delta；模块规则变化必须回 design 并归位 `decisions.md`，产品级变化必须回 Proposal，三者不能互相替代。

上述判断必须逐正文归位项 / 评论写进 `resolutions.json:decision_routing`。`not_required` 也必须说明为什么不构成产品决定；`create / supersede` 必须绑定仓内 `decisions.md`、决定 ID、摘要和原因，supersede 还要列旧决定 ID。不得用空路由把“选择性归档”退化成口头判断。

## 7. Legacy 基线

没有 `lark_published_revision_id` / `lark_published_source_hash` 的旧文档不能稳定区分：

- 发布后 PM 在飞书的修改；
- 发布后本地继续发生的修改；
- 飞书导出格式造成的普通差异。

此时仍可读取并处理评论，但正文只输出当前本地与当前飞书的双向差异。除非 PM 明确指定真相源，否则不自动用一边覆盖另一边。完成本轮并重新同步后，由发布 / 同步能力建立新基线，后续评审恢复三方比较。

如果 frontmatter 已记录发布 revision，但历史 revision 无法读取，这不是 legacy：它表示权限、版本或文档身份出现异常，必须停止，不能静默退化。

## 8. 评论完成条件

一条评论只有同时满足以下条件才可解决：

1. 最终结论已经写入对应权威文档或确认无需改文档；
2. 受影响的 prototype / product 已修改，或确认没有实现影响；
3. 对应生命周期检查通过；
4. 飞书最终正文已精细同步并回读；
5. 重新读取评论后没有改变要求的新回复。

满足条件后正常路径只能用 `lark-review.py complete-comments` 整批处理评论：局部评论的结果文本在 seal 前固化到 resolution，命令只做一次批次初始稳定围栏和一次最终稳定围栏，中间逐笔保存写回执。默认模式由 PMAI 回复并解决；PM 明确要自己核验后解决时使用 `--reply-only`，该模式只创建受控结果回复并记录 `replied_pending_pm`，solve 调用必须为 0。PM 手工解决后用 `verify-comments` 分批回读，全部形成 `solved_by_pm_verified` 才能 checkpoint。未经受控 reply-only 绑定的外部回复或手工解决不构成本批完成证据；任何 PM 手工解决都不能被本批 reopen。仅当 `whole_document` 评论明确无法回复时，才允许默认模式 solve-only；旧 `complete-comment` 只用于旧批次或单项中断恢复。若评论由 PMAI 受控解决后出现新回复，checkpoint 必须失败，但在原结果 reply、`solver_user_id` 与服务端实际 `solved_time` 仍匹配回执时可受控 reopen。

回复只写结果和落点，例如“已按该意见更新权限规则，并同步修改成员详情页；本轮验证通过”。不要回复内部 worktree、hash、合同或测试编排细节。
