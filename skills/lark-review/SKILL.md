---
name: pmai-lark-review
description: |
  回收 PM 在已发布飞书 Docx 规格中的正文修改、未解决批注和完整回复，先把发布基线、当前本地与当前飞书归位为独立目标版本，再按影响分流到 quick-fix、已有 build 迭代或 design/build，受控写回规格、归位决定并精细同步同一篇文档，最后在实现验证后处理已完成批注。用于“我在飞书 review/改过/批注了”“按飞书评审更新规格和原型”“把飞书意见收回来”等归档后评审回流场景；普通双向文档同步仍用 pmai-lark-sync。
---

# /pmai-lark-review · 飞书评审回收

把飞书评审作为已有产品上下文的新一轮输入。只增加采集与分流入口，不创建第二套产品生命周期。

## 入口护栏

先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止并引导 PM 先发 `/pmai-init-project`。

执行前完整读取：

- `references/review-routing.md`
- `references/lifecycle-handoff.md`
- `skills/_shared/decision-policy.md`
- `skills/lark-sync/references/verification.md`

需要回复或解决飞书评论前，再读取当前 `lark-cli` 随附的 `lark-shared`、`lark-drive` 和评论规范；使用原生 API 前先运行对应 `lark-cli schema`，不要凭旧参数写评论。新批次评论写操作统一交给 `lark-review.py complete-comments`；`complete-comment` 只用于兼容恢复。Agent 不直接拼 API、解决评论，也不向 checkpoint / reopen 自报 reply ID、作者或解决者。

## 输入

接受以下任一形式：

```text
/pmai-lark-review <飞书文档 URL>
/pmai-lark-review <仓内 markdown 路径>
```

必须最终唯一定位到：

- 一个本地规格 / PRD markdown；
- 该文件 frontmatter 中的 `lark_doc_id`，或 PM 给出的飞书 Docx URL；
- 所属模块、`decisions.md` / `spec.md` 和 `.pm-workflow/project.yml` 声明的实现入口。

只有 URL 时，在 `docs/**/*.md` 中按 `lark_doc_id` 或 `lark_doc_url` 查找。零个或多个匹配都停止，只问 PM 本地对应哪一份；不能把飞书内容落成一份新的平行规格。

调用本 skill 即表示 PM 授权完成整条评审回流：读取目标文档，受控更新本地规格并归位决定，精细同步同一篇飞书文档，再更新和验证原型 / 产品，最后回复和解决本批已完成评论。若 PM 明确说“只读 / 先比较 / 不要回写 / 不要处理评论”，则按该限制执行，不把调用本身扩大解释成写入授权。

## Workflow

### 1. 保护现场并只读采集

先执行 `git status --short --branch`，保护已有改动。评审采集不得修改本地文档、原型或飞书评论。

批次产物放在项目私有、Git 已忽略的 context cache 中，不能再放 `/tmp`。先检查同一目标 markdown 是否已有未完成批次：恰有一个且 manifest / plan 摘要仍有效时直接恢复该目录；没有时才新建；多个匹配或证据失效时停止并先归位现场，不能靠“最新目录”猜测。

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
REVIEW_ROOT="$REPO_ROOT/.pm-workflow/context/lark-review"
git -C "$REPO_ROOT" check-ignore -q -- ".pm-workflow/context/.pmai-ignore-probe" || exit 1
mkdir -p "$REVIEW_ROOT"
REVIEW_DIR=$(umask 077; mktemp -d "$REVIEW_ROOT/batch.XXXXXX")
python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" collect \
  "<markdown_path>" \
  --doc "<可选飞书 URL 或 token>" \
  --output-dir "$REVIEW_DIR"
```

新项目由模板忽略 `.pm-workflow/context/`；旧项目先按 context cache 的既有兼容规则把该目录写入本地 `.git/info/exclude`，再通过 `git check-ignore` 验证。不能验证为 ignored 时不创建批次。省略 `--doc` 时脚本读取 frontmatter。读取 `$REVIEW_DIR/review.json` 以及其中列出的 diff；评论定位必须保留准确度，不得把 quote 弱匹配说成精确 block。

collector 先取得同一 revision 的 Markdown / full XML；评论分页结束后复核本地文件仍是原文，并用一次轻量 Markdown 围栏确认飞书文档身份、revision 和正文仍未变化，才写批次产物，不重复下载同 revision 的整篇 XML。full XML 连同 block ID、样式、图片 / 附件 token 和 `reference_map` 固化为 `remote-native.json`，这是目标稿和格式验收的唯一原生底稿。默认展示未解决评论，同时分别以 `is_solved=false` 和 `is_solved=true` 完整分页、合并并去重，连续两轮完整扫描的围栏完全相同后才接受，另存包含两种状态的全量只读围栏。不能通过省略 `is_solved` 猜测接口会返回全量评论；分页 envelope、item 或 token 畸形也必须失败关闭。期间任一版本变化都重新 collect，不能继续使用半新半旧的采集结果。

发布基线缺失时按 reference 的 legacy 规则降级。发布 revision 已记录但历史版本读取失败时停止，不能假装已经识别正文增量。

### 2. 先归位版本，再理解反馈

不得让 Agent 直接拿三份快照编辑正式规格。固定使用四个身份：

- `B`：`baseline.md`，发布基线，只用于判断变化，永不写回；
- `L`：`local.md`，采集时本地正文；
- `R`：`remote.md` + `remote-native.json`，采集时飞书正文的稳定语义投影和原生格式；
- `T`：`target.md`，本批唯一候选目标；`target_base=remote_native_snapshot`，只有 T 可以经 `apply` 写入正式规格。

先运行：

```bash
python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" reconcile \
  --manifest "$REVIEW_DIR/review.json"
```

脚本在同一项目私有批次目录生成 `target.md`、`resolutions.json`、`remote-coverage.json`、`remote-preview.md` 和 `state=draft` 的 `apply-plan.json`。按以下规则处理：

- T 无条件从当前飞书 `remote_native_snapshot` 开始；本地变化只能作为对 R 的显式补充或改写归入 T，不能把旧 L 当底稿覆盖 R；
- B 与本地发布源是否同格式，只决定能否机械识别不重叠差异，不影响内容底稿选择；`common_ancestor_compatible=false` 也必须从 R 开始；
- 本地与飞书修改同一语义时显式归位冲突，但 PM 已认可的飞书内容仍是默认保留项；
- `remote-coverage.json` 逐项记录 R→T 的保留、移动、改写、删除和格式处置。每一项删除或改写必须绑定格式规则、评论、已确认决定或 PM 明确例外；内容覆盖率和格式归位率必须都是 100%，未归位数量必须为 0；
- 大规模改写、结构变化或高风险标题 / 表格变化会强制生成 `remote-preview.md`。PM 未确认预览时不能 seal；
- 每条新评论或新回复都必须在 `resolutions.json` 有处置。`pending` / `needs_pm` 阻断写入；`deferred` 必须写明归属和原因，并在收口时保持评论未解决。
- T 经评论、决定或 spec-writing 重新编译后，把 `resolutions.json:target.mode` 改为 `lifecycle_compiled`，并记录确认依据和原因；保持默认 `reconciled` 却修改 T 会被 seal 阻断。

Agent 只能编辑 `$REVIEW_DIR/target.md` 和 `$REVIEW_DIR/resolutions.json`。`remote-native.json`、`remote-coverage.json` 和 `remote-preview.md` 都由脚本生成；正式规格正文保持 L，不得提前修改。未完成批次跨轮保留并优先恢复，目录丢失或任一快照摘要变化时才重新 collect，不凭记忆重建。

### 3. 建立评审批次

把本轮输入区分为：

1. 飞书正文直接修改；
2. 批注及完整回复；
3. 本地在发布后产生的变化；
4. 已解决评论或 checkpoint 前未更新的旧评论。

Docx revision 只能证明正文发生变化，不能可靠证明是谁修改的。只有 PM 在**本轮**明确说“这些正文是我改的”或“我已认可这些正文修改”，才自动把 R 的正文增量视为已确认；必须把这句本轮依据写入 `resolutions.json`，不能用历史猜测、文档所有者或 open_id 代替。

若没有上述明确依据，先把本批全部飞书正文差异一次性展示给 PM，只问一次“是否将以上正文修改全部作为本轮已认可口径”；PM 可以一次指出例外。拿到回答前保持正文项 `needs_pm`，不得 seal / apply，也不逐条重复询问。确认只解决“是否接受正文增量”，其中仍存在的真实产品分叉继续按 decision policy 收敛。

批注按 `review-routing.md` 区分明确指令、问题 / 建议、冲突和无法定位项。问句、假设和建议不能直接写成 active decision。

把上述判断写入 `resolutions.json`，形成一张批次账本：`来源 → 位置 → 候选结论 → 影响对象 → 执行路径 → 确认依据`，并补齐 `remote_coverage` 与强制预览确认。apply 成功前它只是绑定本批 B/L/R/T 的临时候选账本，不得先改 `discussion.md`、`decisions.md` 或 build accepted delta。不要先让 PM 逐条批准整张清单；只有真实产品岔路、相互冲突或本地/飞书双边修改无法合并时才提问。

### 4. 按最高影响分流

整批只走一条主执行路径：

| 最高影响 | 路径 |
|---|---|
| 仅错字、格式、链接、无语义变化的措辞或已确认的小实现纠正 | 内部转 `/pmai-quick-fix` |
| 同模块已有 active build | 回到该 `/pmai-build` 的反馈迭代；产品变化写 accepted delta |
| 改变对象、规则、状态、权限、真相源、页面任务、成功标准，或规格与原型需要联动 | 原地重进 `/pmai-design <模块>`，随后接 `/pmai-build` |
| 仍有真实产品分叉 | 按 decision policy 问一个业务问题，拿到答案后继续上述路径 |

混合批次按最高影响整体升级，不能先把文字部分 quick-fix 合入，再另开 build 修改原型。

复用下游 Skill 的全部门禁：quick-fix 的 diff / 合入审批、build 的开工卡、浏览器验证和 PM 定稿授权都继续有效。`lark-review` 不把“是否先应用评审清单”增加成新确认门。

### 5. apply 前只收敛候选决定并把最终规格编译到 T

按 `lifecycle-handoff.md` 执行前半段：

1. **quick-fix**：只在 T 中完成无语义变化的规格修正，先不创建 worktree。
2. **新 design/build**：把正文修改和批注结论作为候选决定留在 `resolutions.json`，记录计划归入的模块、飞书 URL、comment ID 和需要 supersede 的旧决定；此时不修改 `discussion.md` / `decisions.md`。调用 spec-writing 直接以批次账本为输入，把正式规格候选输出到 T，停在进入 `ready_to_build` 之前。
3. **active build**：把 PM 已接受的新口径、影响面、飞书来源和预期 accepted delta 先记在 `resolutions.json`，不得提前调用 `add-delta`。spec-writing 以该候选 delta 编译 T，暂不改变 build source hash，也不开始依赖新口径的实现。
4. 飞书正文增量已有本轮明确依据或通过一次整批确认、真实产品分叉全部闭合、批次账本完整、T 已是最终目标正文后再 seal；不能为了先改原型而提前写正式规格，也不能让原型反向缩小 T。

同时完成 `resolutions.json:decision_routing`：每个正文归位项和评论至少有一条来源绑定，结果只能是 `not_required / create / supersede`。只有新增、改变或推翻产品对象、状态、权限、业务规则、真相源、异常处理或成功标准时，才填写安全的仓内 `decisions.md` 目标、决定 ID、摘要、原因和需要替代的旧决定；纯措辞、排版、格式、示例补充和不改变规则的解释标为 `not_required` 并写原因。任何 `pending`、漏来源或不安全目标都阻止 seal。active build 若同时改变实现合同，还要写 accepted delta，不能用 delta 代替稳定产品决定。

决定或 T 编译失败时不 apply；实现与验证在 apply 后继续，失败时保留评论为未解决且不写 checkpoint。

### 6. Seal 并受控写入正式规格

确认 `target.md` 是最终规格正文，且 `resolutions.json` 已覆盖全部正文差异和本批评论后运行：

```bash
python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" reconcile \
  --manifest "$REVIEW_DIR/review.json" \
  --resolutions "$REVIEW_DIR/resolutions.json" \
  --seal

python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" apply \
  "<markdown_path>" \
  --plan "$REVIEW_DIR/apply-plan.json"
```

`apply` 是本批唯一允许修改正式规格正文的入口。它会重新校验：目标文档身份、发布基线、B/L/R 和 T 摘要、采集后本地正文未变化、飞书正文仍是采集 revision、评论和回复未变化。任一项变化都零写入，旧 plan 标记为不可继续但保留批次现场，再在 `REVIEW_ROOT` 新建批次重新 collect；没有 `--force` 路径。

### 7. 正式归位决定、精细同步，再继续原生命周期和处理评论

apply 成功后，按上一步的决定归档路由执行：产品规则变化正式写入对应 `decisions.md`（需要时 supersede 旧决定），active build 的实现合同变化再调用一次 `add-delta`；纯措辞和格式变化不制造 decision。记录同一批次 ID、飞书 URL 和 comment ID，不能重新解释 T。这是需要沉淀的产品决定首个持久归位点；归位失败时停止，不同步飞书、不开始实现，也不靠重新 collect 猜回已经应用的决定。

决定归位成功后，立即调用 `/pmai-lark-sync` 模式 A，把最终本地口径精细同步回**同一篇**飞书文档并回读验证。同步必须消费 apply plan 的 `target_base=remote_native_snapshot` 和 `remote-coverage.json`，只用 XML `str_replace` / `block_*` 修补已归位差异；所有标记为 preserved 的原生 block ID、样式属性、图片 / 附件 token 和引用映射都不得重建。第一笔写入前必须重新 fetch：文档身份不变，且最新 revision 必须同时等于 apply plan 的 `remote_revision_id` 和本次同步首笔采用的 expected revision；不一致时零写入，保留批次并重新 collect。确认通过后，第一笔 `lark-cli docs +update` 携带该 expected revision，后续每笔都携带上一笔写操作返回的 `--revision-id`；revision 冲突时停止。禁止 Markdown overwrite 或整段重建来省事。

基线刷新后立即做机器验收：

```bash
python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" verify-sync \
  --manifest "$REVIEW_DIR/review.json" \
  --plan "$REVIEW_DIR/apply-plan.json"
```

`verify-sync` 会重新取得同一 revision 的 Markdown 与 full XML，校验飞书正文的稳定语义投影等于 T，并逐个比较需保留 block 的格式 hash、资源 token 和原引用映射。任何一项不一致都不允许处理评论或 checkpoint；验收回执绑定 ready plan 与最终 revision，checkpoint 先确认飞书仍是该 revision，再复用回执，不重复下载 full XML。

飞书正文回读通过后，按 `lifecycle-handoff.md` 继续已选路径：

1. quick-fix 只在 worktree 处理规格之外的目标；若本批只有规格文字变化，不制造空 worktree 或空提交。
2. 新 design 重新生成 context pack，按正常合同提交已应用的规格、决定和建造依据，再进入 build。
3. active build 继续刚写入的 accepted delta 对应的实现迭代。
4. 按项目定义更新 prototype / product，运行该生命周期的 targeted checks；Web 结果做真实浏览器走查。

规格已经是确认的目标合同。实现失败时不把规格回退成旧 L，也不把评论标为完成；把实现缺口留在原 lifecycle 恢复。

在 seal 前，为每条准备完成的局部评论把面向 PM 的最终回复写入 `resolutions.json:comments[].result_text`；`deferred` 不得预填。实现与验证完成后，一次运行整批受控命令：

```bash
python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" complete-comments \
  --manifest "$REVIEW_DIR/review.json" \
  --plan "$REVIEW_DIR/apply-plan.json"
```

局部评论必须有非空 `result_text`。只有 `whole_document` 评论且飞书接口明确不支持回复时，才可留空做 solve-only；账本必须明确记录未回复原因，不得把它表述成已回复。

`complete-comments` 只在批次开始和全部写入结束时各读取一次稳定全量评论围栏，中间按 ready plan 顺序回复、解决，并把每笔写响应立即原子写入 `$REVIEW_DIR/comment-actions.json`。回执绑定 batch、ready plan、文档、comment、结果 reply ID / 作者 / 正文 hash、`solver_user_id`、服务端原样返回的 `solved_time` 和最终状态；中断后重跑同一命令按 journal 恢复，不重复回复。接口不返回 `solved_time` 时保持 `null`，改用 solve 写响应 hash + 最终稳定回读形成 `write_ack_and_stable_readback`。旧批次或单项中断才使用 `complete-comment --comment-id` 兼容恢复；`legacy_stable_readback` 仍可读取，但不作为新批次正常入口。Agent 不直接调用评论写 API。

处理范围继续遵守：

- 只对“结论已经落入权威文档，受影响原型 / 产品已验证”的评论回复结果并标记解决；
- 新回复改变要求、评论仍是未决产品问题、定位内容已删除或结果未验证时，保持未解决；
- 全文评论不支持回复时，只能由上述 solve-only 受控路径直接解决；
- 只处理本批次 comment ID，不批量解决文档里的其它评论。

`/pmai-lark-sync` 模式 A 已负责把回读确认后的 revision 与本地正文 hash 刷新为下一轮发布基线。先检查目标 markdown 的两项字段与本次回读一致；只有同步被中断、旧版本未执行基线步骤或恢复时，才补跑：

```bash
python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" baseline \
  "<markdown_path>" \
  --revision-id "<回读确认后的 revision>" \
  --expected-source-hash "<apply-plan target.body_sha256>"
```

评论写入完成后，只有预期评论都存在同批受控回执，才记录 checkpoint：

```bash
python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" checkpoint \
  "<markdown_path>" \
  --manifest "$REVIEW_DIR/review.json" \
  --plan "$REVIEW_DIR/apply-plan.json"
```

`checkpoint` 只读取 manifest / plan 同目录的 `comment-actions.json` 和 `remote-verification.json`，不接受自由填写 reply、author 或 solver 的参数。它再次执行最终门禁，不能只靠 Agent 口头判断：本地正文必须仍为 sealed T；`lark_published_source_hash` 必须等于 T 的正文 hash；飞书当前 revision 必须与原生格式验收回执和本地发布基线相同；`applied / already_satisfied / no_spec_change` 必须有匹配 ready plan 的完成回执且当前已解决，`deferred` 必须仍未解决。当前回复、作者、解决者、服务端实际返回的解决时间与状态都必须和受控回执一致；没有时间时验证证据模式和稳定围栏，不要求虚构时间。PM / 协作者手工回复或解决不能冒充本批完成。任何其它评论的新建、重开、解决、删除、编辑或新回复，即使最终已解决，也停止并重新 collect。

如果 checkpoint 因新回复或其它评论竞态拒绝，而当前尝试已经由系统解决了本批评论，先对每个本次系统已解决的 comment ID 执行受批次约束的恢复：

```bash
python3 "${PMAI_HOME:-$HOME/.pmai}/scripts/lark-review.py" reopen \
  "<markdown_path>" \
  --manifest "$REVIEW_DIR/review.json" \
  --plan "$REVIEW_DIR/apply-plan.json" \
  --comment-id "<comment_id>"
```

多个评论重复传 `--comment-id`。`reopen` 同样只消费同批 `comment-actions.json`：目标评论允许在受控解决后出现 PM 新回复，但原结果 reply 的 ID / 作者 / 正文 hash、`solver_user_id` 和 `solved_time` 必须仍与本批回执一致；其它评论不得变化。PM 或协作者手工解决的评论没有受控回执，绝不能 reopen。写后会复核 T、文档 revision 和稳定全量评论围栏，不能借它改批次外状态。随后在 `REVIEW_ROOT` 下新建批次执行 `collect --include-solved`；checkpoint 后有更新的已解决评论会重新进入 `resolutions.json`，已 reopen 的评论保持未解决，直到新要求完成。失败的旧批次保留为 reopen 证据，不得再次 checkpoint；后续归位、seal、apply 和 checkpoint 全部使用新批次。不能用默认 collect 跳过。

checkpoint 不替代 quick-fix / build 的生命周期验收门禁，也不自行证明 prototype / product、targeted checks 或浏览器证据；这些先由已选下游路径验证通过，checkpoint 只证明最终正文、发布基线和评论批次已经一致收口。它写入最终发布 revision 和最终评论水位，不复用采集时旧水位。

checkpoint 只记录本轮覆盖到的 revision、评论更新时间、同秒互动 ID 边界和完成时间，不代表未验证事项已完成。只有本批 checkpoint 成功、下游生命周期也完成后才清理 `$REVIEW_DIR`；中断、失败、等待 PM 或待恢复时全部保留，且不得清理仍被新批次 reopen 引用的旧批次。

## 性能纪律

机器处理目标是 10–15 分钟，不含等待 PM 决策、外部限流和下游 build / 浏览器验收。整批只做一次 collect、一次 draft reconcile、一次 seal、一次 apply 和一次最终同步；`remote-native.json` 是后续阶段的缓存底稿，不得为了重新理解格式反复下载整篇文档，也不得为每条评论重新 collect 或重跑生命周期。

`review.json.performance`、`apply-plan.json.performance`、`verify-sync`、`comment-actions.json.performance` 与 checkpoint 分别输出阶段耗时和 API / 全量扫描次数。评论数增加时只能增加 reply / solve 写调用，稳定全量扫描固定为批次首尾各一轮；checkpoint 复用同 revision 的格式验收，只做一次稳定评论围栏和一次 Markdown revision 围栏。超过 15 分钟时先报告最慢阶段和 API 往返数量，再优化分页或远端限流；不能通过减少每轮稳定围栏、跳过 revision 门禁或省略格式验收换速度。

## 最终回执

```text
飞书评审已收回：<URL>
正文：已归入 N 处 / 无正文变化 / 仍有 N 处需要 PM 判断
内容与格式：已核对通过 / 未完成（原因）
评论：已完成 N 条，保留 N 条未解决
本地更新：<规格、选择性写入的 decisions、原型或产品>
产品结果：<原型或产品已更新并验证 / 本轮无需改实现 / 尚未完成及原因>
需要你处理：<无需处理 / 一个明确的产品决定>
```

内部证据和恢复信息继续完整保存，但正常回执只呈现 PM 能理解和需要行动的结果。处理中断时，说明已经完成到哪里、哪些产品结果尚未完成；不要让 PM 管理内部文件或恢复步骤。

## Rules

- 飞书正文直接修改默认只是内容证据；只有 PM 本轮明确声明由自己修改 / 已认可，或看过整批差异后一次确认，才成为已确认口径。批注问句默认未确认。
- 调用本 skill 是对本批完整回流的写入意图；PM 明确限制为只读或不处理评论时，以该限制为准。
- 不把 `lark-sync` 的整篇回拉模式用于评审回收。
- 当前飞书原生版本是唯一目标底稿；`common_ancestor_compatible` 只影响差异对齐，不得把 T 切回旧 L。
- B / L / R 都是只读证据；只有已 seal 的 T 可以通过 apply 修改正式规格正文。
- 只有产品规则变化写 `decisions.md`；措辞和格式变化不得制造 decision。
- 下游 quick-fix、design、build 不得绕过 apply 直接编辑本批正式规格正文。
- 不用原型或代码反推并覆盖规格。
- 不按评论数量拆出多个并行生命周期。
- 未验证完成前不解决评论、不写 checkpoint。
- checkpoint 只记录飞书收口水位，不替代下游生命周期的实现与验收证据。
- 批次快照和评论全文只暂存在 Git 已忽略的 `.pm-workflow/context/lark-review/`，用于跨轮恢复；它们不是产品真相源，完成后清理，稳定产品结论只归入既有真相源。
- 不写死本机路径；始终通过 `PMAI_HOME`、项目根和仓内相对路径定位资产。

## Failure Handling

| 情况 | 处理 |
|---|---|
| 找不到唯一的本地对应文档 | 停止，只问 PM 本地对应哪一份 |
| 目标是旧版 `/doc/` 或非 Docx 链接 | 停止，引导迁移到 Docx；不得用 docx 评论接口猜读 |
| 发布基线缺失 | 输出 legacy 降级，不自动覆盖本地正文 |
| 已记录 revision 读取失败 | 停止，保留现场并报告版本 / 权限问题 |
| 公共祖先格式不兼容 | 禁止 raw Markdown 三方合并，但 T 仍从 R 的原生快照开始；本地增量逐项归位 |
| 远端内容或格式覆盖率不足 100% | 保留 `remote-coverage.json` / `remote-preview.md`，未归位清零前不 seal |
| 大规模 R→T 差异未确认预览 | 停在 draft，PM 明确确认 `remote-preview.md` 后再 seal |
| 本地与飞书发布后都变化 | 只自动合并不重叠项；同处变化让 PM 拍冲突 |
| 评论无法精确定位 | 保留 quote 与上下文并标明推断；有歧义时不修改 |
| 飞书正文作者 / 认可状态无法证明 | 展示整批正文差异，只问一次是否认可；未答前不 seal / apply |
| seal / apply 发现本地、飞书或评论变化 | 零写入，旧 plan 不再执行但保留批次现场；新建批次重新 collect |
| 第一次同步前 fetch 的 revision 不等于 apply plan / expected revision | 零写入，保留批次并重新 collect |
| `complete-comments` 部分写入或回读失败 | 不伪造回执、不写 checkpoint；保留整批 journal，原命令重跑恢复且不重复回复；若 solve 写入已有受控响应且随后出现 PM 新回复，`reopen` 先按稳定回读补齐完成证据再受控重开 |
| 飞书不返回 `solved_time` | 保持时间为空，用写响应 hash + 稳定回读收口；旧回执走 legacy 稳定回读，不伪造时间 |
| 解决评论后 checkpoint 发现新回复或批次外变化 | 不写 checkpoint；只按本批受控回执 `reopen` 本次完成的评论，再新建持久批次并 `collect --include-solved`，把新回复重新纳入归位 |
| 下游 quick-fix / build 未完成 | 保持评论未解决，不写 checkpoint |
| 飞书回写或回读失败 | 本地成果保留，评论未解决，报告可恢复步骤 |
