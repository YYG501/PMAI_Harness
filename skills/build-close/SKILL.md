---
name: pmai-build-close
description: |
  统一 finalize 的兼容与恢复入口。正常链路由 /pmai-build 在 PM 明确定稿后自动调用；本入口用于旧调用习惯、中断续跑、merge 冲突处理后重试或 landed/docs_pending 文档恢复。
---

# /pmai-build-close · finalize 兼容与恢复入口

## 入口护栏

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill BUILD-CLOSE || true
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止并引导 PM 先发 `/pmai-init-project`。

执行前读取：

- `skills/_shared/context-reconstruction.md`
- `skills/_shared/decision-policy.md`
- `skills/_shared/loop-contract.md`
- `skills/_shared/gstack-integration.md`
- `skills/_shared/consistency-scan.md`
- `skills/_shared/PM-VIEW-RULES.md` 及其引用的 PM 视图规则
- `skills/_shared/pm-view/banner-rules.md`
- `skills/build/references/finalization.md`
- 当前模块 `.work-meta.json:build`

## 定位

正常用户链路不再要求 PM 额外运行本命令：PM 在 `/pmai-build` 看完结果后说“可以提交 / 定稿 / 可以合并”，build 会自动进入最终检查并调用同一个 finalize。

宿主 finalize-route hook 会把这些自然语言授权直接路由到唯一 runner，并阻止在 runner 前手工拼接检查、提交或 merge；本入口不能绕过该护栏。

本入口只处理：

- 兼容旧的手动 `/pmai-build-close` 习惯；
- 会话中断后恢复 `final_check`；
- merge 冲突解决后的重试；
- 实现已落 main、文档仍为 `pending / failed` 的续跑；
- 合同 v1 的旧兼容收尾。

它不新建第二套 close 状态，不重新询问 worktree、执行器、文档类型或是否保存决定。

## Recovery Loop Mapping

本入口只实现共享 Loop Contract 的 `resume_checkpoint`，不拥有新的阶段判断：从 canonical lifecycle 和证据定位唯一 checkpoint，只补该 checkpoint 缺失的机械或语义项。`final_check` 不重放已经通过且仍新鲜的 final evidence；`landed + docs_pending` 不重复 merge；多个候选、合同漂移或 checkpoint 无法验证时停止，不按 cwd、分支名或文件时间猜测。任何新产品反馈都交回 Build 重新分类，任何上游模型变化都由 Build 按共享合同路由到 Design 或 Proposal。

## 1. 先判恢复位置

读取 build contract：

- `contract_version=1`：调用 `close-work.sh` 的旧兼容路径；
- `building`：实现尚未形成可查看的提交，返回 `/pmai-build` 继续构建；
- `iterating`：PM 主动调用本入口表示希望定稿；v4+ 先记录 `request-finalization`，再在冻结 commit 的 validation worktree 完成一次 `final_checks`，全部通过后才生成验收就绪快照并进入 `final_check`；
- `final_check`：验证最新证据后落地主线；
- `landed + docs_status=pending|failed`：只恢复文档编译，不重复 merge；
- `documenting + docs_status=complete`：提交文档并完成清理；
- `.work-meta.json` 不存在：该模块没有可恢复的 active build，停止，不猜现场分支。

v2 直接调用：

```bash
bash "$PMAI_HOME/scripts/close-work.sh" "docs/modules/<模块>"
```

`close-work.sh` 根据同一合同自动转 `land-work.sh`，不靠 cwd、分支名字或碰巧存在的 worktree 猜流程。

`finalize-work.py` 是统一的可恢复收尾 runner；本 Skill 只负责恢复位置判断和失败路由，不复制 runner 实现。

若从 `iterating` 进入，不能先写 `pm_accepted_at` 再临时跑完整验收。v4+ 直接调用统一候选入口；它按批准目标树和 recovery checkpoint 绑定正确候选，而不是固定绑定当前 Git HEAD，再让 runner 从 currentness 开始只执行缺失的机械项：

```bash
python3 "$PMAI_HOME/scripts/finalize-candidate.py" \
  --module-dir "<build worktree>/docs/modules/<模块>" \
  <Web 项目追加 --browser-manifest "<build worktree>/<build.audit_dir>/browser-manifest.json"> \
  <有结构化 coverage 时追加 --coverage-plan "<checks-spec.json>" --coverage-artifacts "<页面抓取目录>"，并逐项追加 --coverage-confirm-state "<check id>">
```

候选绑定会记录 source/base commit、批准路径树摘要、source hash、明确来源与 diff mode；legacy recovery 优先使用经确认 checkpoint，后续无关 HEAD 不会替换候选，也不要求人工改 baseline。runner 返回 `3` 时，按 `skills/build/references/finalization.md` 完成当前主控负责的语义检查并记录 evidence，再重跑同一命令。v1-v4 继续按运行时 adapter 恢复，不升级合同版本。build 验收证据是落地主线硬门，不能因为使用兼容入口而跳过。任何检查发现规格漏项、实现缺口或业务代码需要修改，都保持/退回 `iterating` 并交还 `/pmai-build`；本 close 不补业务代码、不一边收尾一边重新验收。

## 2. final_check 恢复

只做轻量 currentness 与合同校验，确认：

- 没有未决产品问题；
- `implementation_commit` 是 PM 最后看到的版本；
- 验收就绪快照与当前 implementation commit、source hash 一致；
- 所有 final checks 都已有新鲜证据，不重复跑同一 commit 的完整验收；
- 每份证据的 `source_hash` 和 `commit` 与合同一致；
- final-validation 中只有 tests/typecheck 可在 PM 明确绑定当前 artifact 后登记 limited；其它 `limited / skipped / blocked` 只按旧合同允许范围处理；
- 行为检查不是 `fail`。

然后运行：

```bash
python3 "$PMAI_HOME/scripts/build-contract.py" validate-land \
  "<build worktree>/docs/modules/<模块>"
bash "$PMAI_HOME/scripts/close-work.sh" \
  "<build worktree>/docs/modules/<模块>"
```

失败处理：

- 快照缺失、过期或检查失败：回 `iterating`，保留工作区并交还 build；close 不修改业务代码；
- merge 冲突：保留 `final_check`、分支和 worktree，解决冲突后重跑；
- 不清理、不 hard reset、不把无关脏改动带进提交。
- 主仓 main 上允许保留其它未提交 WIP；实现合并使用 `autostash` 保护这些改动，但真实路径冲突仍停住。
- worktree 被开发服务或缓存占用时，记录到安全待清理队列并继续文档同步；纯清理失败不把已落地主线的实现伪装成 landing 失败。

## 3. landed/docs_pending 恢复

实现已经在 main 时，禁止再次 merge 或重新跑实现落地。只做：

1. 在 main 重新编译 context pack；
2. 对 `<build.audit_dir>/doc-impact.json` 执行 `doc-impact.py ensure-current`，不能因文件已经存在就直接复用；
3. impact map 只在 landed 后按当前候选绑定、implementation diff 和 accepted deltas 生成，不在 build 阶段提前准备；旧 schema 或 commit/source/tree/delta 绑定不一致时自动重建；
4. 调用 spec-writing 的“落地主线后的目标对账”模式；
5. 只更新影响地图实际列出的 pending 真相源；landed diff 已改文档由脚本自动记为 covered；
6. 未受影响的 PRODUCT、RULES、DESIGN、TODO、mockup 和索引不进入清单，不逐份打开、不写 no-change；
7. 校验 accepted delta 和实际交付状态都有文档落点；
8. 完成覆盖后运行：

```bash
python3 "$PMAI_HOME/scripts/doc-impact.py" validate \
  "<build.audit_dir>/doc-impact.json"
python3 "$PMAI_HOME/scripts/build-contract.py" docs-complete \
  "docs/modules/<模块>"
bash "$PMAI_HOME/scripts/close-work.sh" "docs/modules/<模块>"
```

文档失败时记录：

```bash
python3 "$PMAI_HOME/scripts/build-contract.py" docs-fail \
  "docs/modules/<模块>" --reason "<失败原因>"
```

保留 landed 状态；下一次只继续本节。

## 4. 文档规则

- `spec.md` / PRD 只描述当前有效的最终目标；landed 后只有 accepted delta 可以修改目标，漏实现保留为实现缺口；
- `PRODUCT-STATE.md` 等现状文档只描述 main 已存在的事实；
- 只要对账发现漏实现或无依据实现，就停止正式文档写入并保持 `landed + docs_pending|failed`；不得先改 `PRODUCT-STATE.md` 记录缺口，缺口只进入影响地图/审计证据；
- `spec.md` 正文不保留删除线旧正文、老版/新版对照或迭代流水账；
- 历史决定与 supersede 关系留在 `decisions.md`，完整文件演进留在 Git；
- 单模块决定进模块 `decisions.md`；跨模块现行规则进 `PRODUCT-RULES.md`；项目级冻结理路进 `docs/decisions/`；
- 只有 build 期间 PM 明确接受的新决定才能进入 accepted deltas 和决定记录；问句、AI 推测、讨论草稿不得落为决定；
- 文档同步使用单独 commit，完成后删除临时 `.work-meta.json`。

## PM 回执

PM 窗口只报阶段结果，不直播 context pack、合同 JSON、git 命令、日志或 worktree 排障。

恢复中：

```text
我已找到上次停住的位置：<最终检查 / 已进入主线、待更新文档>。
我会从这里继续，不重复已经完成的合并。
```

完成后：

```text
✅ 已收尾：实现已在主线，模块规格、产品现状和受影响文档已按最终结果对齐。

▶ Next Up：继续 /pmai-design <下一个模块>，或 /pmai-status 查看当前产品现状。
```

## Rules

- 正常链路由 build 自动 finalize；本 skill 只兼容和恢复。
- 只按 build contract 和 lifecycle state 续跑，不从 cwd / 分支形态猜。
- `final_check` 只接受绑定最终 source hash 与 implementation commit 的新鲜证据。
- v4+ `iterating` 必须先有 PM 定稿请求，再运行一次 final checks 并通过 `review-ready`；`final_check` 不首次跑完整验收、不修改业务代码。
- merge 冲突不清理 worktree；文档失败不重复 merge。
- 运行进程或缓存导致的 worktree 清理失败进入待清理队列，不阻塞文档阶段。
- 正式文档在实现落 main 后更新，单独提交。
- 不向 PM 再问 worktree、执行器、手动 close 或逐条“要不要保存”菜单。
- gstack/browser/Playwright 只是证据生产者，PMAI contract 才是落地主线判断入口；新 build 的 browser-acceptance 与旧合同的 active browser-smoke 都不能用 exception 跳过。
- 本 Skill 只执行 `skills/_shared/loop-contract.md` 的 `resume_checkpoint`；不创建 close 专属 loop state，也不重放已完成 checkpoint。
