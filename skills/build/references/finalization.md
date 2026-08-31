# 最终化执行合同

## 原则

- PM 定稿前不生成 candidate build、browser 或文档 patch；最终化提速来自删除重复工作，不是把工作提前。
- 正常路径只跑三道门：一次代码验证、一次批准范围/规格覆盖、一次受影响体验批次。
- 真实构建缺陷、浏览器失败、merge 冲突或 PM 新反馈立即退出/重置 10 分钟目标，不得播报成正常路径成功。

### 角色隔离

- **Verifier** 是 finalization runner 的执行角色：负责 currentness、命令、浏览器、范围和边界等机械检查，并生成绑定当前 `implementation_commit + source_hash` 的 receipt 与 pre-landing audit binding。
- **Judge** 默认由当前主控派发 child（也可使用外部 backend）作为独立只读语义验收角色：只消费 Verifier 已生成的 evidence，逐项覆盖 `finalize-run.json` 的 `semantic_checks`，以同一 `evidence_digest` attach `semantic-judge.json`。Judge 必须使用不同于 Verifier 的 `run_id`，不得修改实现或机械 evidence。
- **当前主控** 只负责编排：接收 PM 定稿授权、派发/回收 Verifier 与 Judge、校验 role/backend/run id/digest、处理失败路由、推进 lifecycle、landing 和文档同步。主控不把自己的语义判断标成独立 Judge。
- 新 build 默认使用 `native-child` backend。若 child 或外部执行能力不可用而由当前主控接管，必须标记 `backend=main-fallback`、`independent=false`；Verifier receipt 为 `status=degraded` 并记录降级原因。该结果属于“非独立降级执行”，不能对外宣称独立验收。

## 统一入口

PM 明确定稿后调用：

```bash
python3 "$PMAI_HOME/scripts/finalize-work.py" \
  --module-dir "$BUILD_DIR/docs/modules/<模块>" \
  <Web 项目追加 --browser-manifest "$BUILD_DIR/<build.audit_dir>/browser-manifest.json"> \
  <有结构化 coverage 时追加 --coverage-plan "<checks-spec.json>" --coverage-artifacts "<页面抓取目录>"，并逐项追加 --coverage-confirm-state "<check id>">
```

该命令在 Verifier 的 child 或外部执行上下文中运行；调用时传入 `--agent-backend child|external` 及该次 `--agent-run-id`（可附 `--agent-host/--agent-model`）。未能派发 child/外部 Verifier 时才省略这些参数，由当前主控自动以 `main-fallback` 接管并写入降级原因。

宿主 hook 同时把“可以提交 / 可以合并 / 定稿 / 这版可以了”等明确授权绑定到当前会话的短期 finalize intent。意图存在时，PreToolUse(Bash) 禁止先手工跑 test、typecheck、build、browser、commit 或 merge；只允许先进入下面的 candidate / resumable runner，以及 runner 返回后明确要求的 evidence checkpoint。该 intent 不新增 lifecycle 状态，生命周期仍以 `.work-meta.json` 和 runner artifact 为准。

正常从 `iterating` 冻结当前候选时统一调用下面的入口；它先机械绑定正确候选，再调用同一个可恢复 runner。新 build 的批准目标树已经跟随 HEAD 时绑定 HEAD；已记录实现与后续 HEAD 的批准目标树相同时保留已记录实现；legacy recovery 优先绑定经 PM 确认的 checkpoint，只有承接该 checkpoint 的已记录实现确实继续改变批准目标树时才前移。Skill 不手工改 baseline，也不自行拼接 Git commit 与 finalize 命令：

```bash
python3 "$PMAI_HOME/scripts/finalize-candidate.py" \
  --module-dir "$BUILD_DIR/docs/modules/<模块>" \
  <Web 项目追加 --browser-manifest "$BUILD_DIR/<build.audit_dir>/browser-manifest.json"> \
  <有结构化 coverage 时追加 --coverage-plan "<checks-spec.json>" --coverage-artifacts "<页面抓取目录>"，并逐项追加 --coverage-confirm-state "<check id>">
```

`build.candidate_binding` 同时绑定来源类型、source/base commit、批准目标路径、目标文件树摘要、approved source hash 和 diff mode，并用摘要防止后续字段被静默改写。`implementation_commit`、prototype boundary、final evidence、browser batch 和 doc impact 都必须消费这同一候选身份；任何一项 currentness 不一致都停止，不重新从当前 HEAD 猜候选。

已经进入 `final_check / landed / documenting` 的中断恢复继续直接调用 `finalize-work.py`，避免把恢复状态重新写回 `iterating`。

runner 按 v4+ lifecycle 续跑并自动完成 currentness、隔离命令验证、浏览器批次、coverage evidence（提供输入时）和 Verifier evidence 记录；存在 semantic checks 时，等待独立 Judge attach 后才可进入 review-ready、accept 和 landing。已经通过且仍绑定同一 commit/source hash 的机械项不重复执行。

统一入口的顺序是机器合同：`PM finalize intent → finalize-candidate.py → finalize-work.py`。任何手工检查、提交或 merge 都不能替代 candidate binding；`build-close` 只作为中断、冲突和 `landed/docs_pending` 的恢复入口。

`.pm-workflow/project.yml` 的所有 `commands.*` 与 `web.start` 都从 `implementation.root` 执行。新定义在写入和新 build 启动时机械校验 entrypoint 必须位于 root 内，并拒绝命令再次使用 `pnpm --dir <root>`、`npm --prefix <root>`、`yarn --cwd <root>` 或 `cd <root> &&` 选择同一目录。合法 legacy recovery 只在 final validation 运行时精确移除一次重复前缀，并把原命令和适配结果写入 artifact；不改写旧 `project.yml`。

`final-validation.py` 分项保留每条命令的状态、exit code 和日志。install 失败会把后续项记为 blocked；test/typecheck 失败不会阻止 production build 继续执行，build 自身仍是硬门。只有 tests/typecheck 可由 PM 对当前 `implementation_commit + source_hash + results_digest` 绑定的 `final-validation.json` 明确接受为 limited；原始失败仍保留，runner 只把对应 evidence 登记为 limited。build、browser、prototype boundary 和 behavior 失败不能通过 exception 放行。

新轮次的 currentness 使用 `source_hash_version=2`：模块规格/决定/讨论、输入证据、`PRODUCT.md`、`PRODUCT-RULES.md`、`DESIGN.md`、项目级冻结决定和 `project.yml` 是会使设计过期的依据；`PRODUCT-STATE.md`、`TODO.md`、模块索引仍进入 context pack 供理解，但单独变化不判本模块过期。没有版本字段的旧 ready/build 继续按 v1 全量范围恢复到本轮结束，不在升级时静默换 hash。

返回码 `3` 表示机械项已完成，但仍缺 semantic checks 的独立 Judge 结果。Judge 读取 Verifier evidence 和规格，对 `prototype-boundary / coverage / scope-coverage / migration / security` 等语义项逐 check 给出结果；有 checks-spec 与页面抓取证据时用统一 coverage 参数，机器 P0/P1 必须为零，`must_cover_states` 必须逐 check 显式确认。Judge 的 `checks` 必须精确覆盖当前 `semantic_checks`，并以同一 evidence digest attach；语义判断不能覆盖机器缺口。实现/source 变化或 PM 新反馈会使该次语义阶段失效并重置正常路径。不得把语义检查伪造成 Verifier 或 runner 自动通过。

主控收到 Judge JSON 后，用 `finalize-audit-binding.py attach-judge` 校验 role、不同 `run_id`、当前 evidence digest 和 semantic checks 的精确覆盖，并把结果保存为 audit 目录内的 `semantic-judge.json`；随后重新调用 `finalize-work.py`，由 runner 从当前 checkpoint 继续，不重复已通过的机械检查。

runner 在 `final_check` 只提交当前模块 `.work-meta.json` 和对应 audit 目录，再进入 landing，其他 staged 路径会立即阻断。worktree 成功合入后会进入安全待清理队列，并立即输出 `FINALIZE_RESUME_MODULE=<main 模块路径>`；完成文档地图后用该 main 路径重跑，不能继续引用等待后台清理的 worktree 路径。

新工作轮次的 audit 目录由 `build.audit_dir` 固定并包含唯一 work id；所有 artifact、timing、landing 和文档影响地图都只读写该目录。缺少该字段的旧合同继续回退 `.pm-workflow/audits/<模块>`，只作恢复兼容。

旧 v4 若已经进入 `final_check` 且没有 `finalize-run.json`，直接按原状态落地，不补造 runner 游标，也不要求迁移 timing 字段。只有本轮 runner 已创建且绑定当前 commit/source hash 的游标，landing 才启用完整阶段账本硬门。

## 浏览器批次

Web 新 build 只生成一个 `browser-acceptance` final check，不再分别跑 browser-smoke、visual、behavior。旧 v1-v4 不升级合同版本：已经新鲜的旧证据继续读取；缺失旧 browser-smoke / visual / behavior 时，runner 只执行一次相同的 active browser batch，再按旧合同实际要求的检查名确定性派生证据。各派生项绑定同一主 batch 摘要，coverage 不从浏览器动作自动推断。

最终化时才根据冻结 diff、批准目标和最终规格写 manifest：

```json
{
  "schema_version": 1,
  "base_url": "http://127.0.0.1:3000",
  "flows": [
    {
      "id": "affected-task",
      "route": "/affected-route",
      "covers": ["smoke", "visual", "behavior"],
      "commands": [
        ["goto", "{base_url}/affected-route"],
        ["wait", "main"],
        ["screenshot", "{audit_dir}/affected-task.png"],
        ["click", "button[data-testid=action]"],
        ["is", "visible", "[data-testid=result]"]
      ]
    }
  ]
}
```

选择流程时：

- 只放本轮受影响的独特任务，不按页面数量重复验收同一共享实现；
- 共享组件由一个能覆盖变化的代表路由验证；共享 shell、路由或权限边界变化时才扩大到各独特分支；
- 纯导航配置先做静态范围检查，只有用户可观察行为变化才加入浏览器；
- behavior 必须包含交互及其后的主动断言；visual 必须生成 audit 目录内的真实截图；smoke 必须主动加载并断言。

`browser-acceptance.py` 把全部命令交给 gstack `browse chain` 一次执行，并由合同核验单会话、三类覆盖、流程状态和截图文件。legacy 派生证据必须与主 batch 位于同一 audit 目录，映射精确覆盖当前旧合同要求，主批次摘要会从稳定字段重新计算；不得手写 pass artifact。

## 文档

实现 landed 后才由 `doc-impact.py` 生成地图。每次文档续跑先执行 `ensure-current`；schema、work/module、implementation/landed commit、base/head、approved source hash、accepted deltas、candidate tree 或 binding digest 任一不一致时原子重建，只有绑定完全一致的地图才保留已填写 coverage：

- `PRODUCT-STATE.md` 记录本轮真实落地状态；
- accepted delta 才要求模块 spec、decisions 和 delta 明确指向的产品真相源；
- landed diff 已经修改的正式文档自动记为 covered；
- 未受影响的 PRODUCT、RULES、DESIGN、TODO、mockup 和索引不进入清单，不再逐份打开后写 no-change。

完成地图中的 pending 项后执行 `docs-complete`，再用 runner 输出的 main 模块路径重跑统一入口。`landed/docs_pending`、`documenting/complete` 都由现有 lifecycle 恢复，不重复 merge。完成提交前，runner 会校验本次适用的 currentness、命令验证、浏览器、语义判断、landing 和 documentation timing 都有通过记录且没有 running 项。
