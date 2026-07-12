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
- `skills/_shared/gstack-integration.md`
- `skills/_shared/consistency-scan.md`
- `skills/_shared/PM-VIEW-RULES.md` 及其引用的 PM 视图规则
- `skills/_shared/pm-view/banner-rules.md`
- 当前模块 `.work-meta.json:build`

## 定位

正常用户链路不再要求 PM 额外运行本命令：PM 在 `/pmai-build` 看完结果后说“可以提交 / 定稿 / 可以合并”，build 会自动进入最终检查并调用同一个 finalize。

本入口只处理：

- 兼容旧的手动 `/pmai-build-close` 习惯；
- 会话中断后恢复 `final_check`；
- merge 冲突解决后的重试；
- 实现已落 main、文档仍为 `pending / failed` 的续跑；
- 合同 v1 的旧兼容收尾。

它不新建第二套 close 状态，不重新询问 worktree、执行器、文档类型或是否保存决定。

## 1. 先判恢复位置

读取 build contract：

- `contract_version=1`：调用 `close-work.sh` 的旧兼容路径；
- `building`：实现尚未形成可查看的提交，返回 `/pmai-build` 继续构建；
- `iterating`：PM 主动调用本入口本身就是兼容形式的定稿授权；记录当前实现提交与验收，进入 `final_check`；
- `final_check`：验证最新证据后落地主线；
- `landed + docs_status=pending|failed`：只恢复文档编译，不重复 merge；
- `documenting + docs_status=complete`：提交文档并完成清理；
- `.work-meta.json` 不存在：该模块没有可恢复的 active build，停止，不猜现场分支。

v2 直接调用：

```bash
bash "$PMAI_HOME/scripts/close-work.sh" "docs/modules/<模块>"
```

`close-work.sh` 根据同一合同自动转 `land-work.sh`，不靠 cwd、分支名字或碰巧存在的 worktree 猜流程。

若从 `iterating` 进入，必须一次写齐实现提交和 PM 验收，禁止并行跑 `commit` / `accept`：

```bash
IMPLEMENTATION_COMMIT=$(git -C "<build worktree>" rev-parse HEAD)
python3 "$PMAI_HOME/scripts/build-contract.py" complete \
  "<build worktree>/docs/modules/<模块>" \
  --implementation-commit "$IMPLEMENTATION_COMMIT"
```

随后按 `/pmai-build` 的目标适配器跑完整 required checks；build 验收证据是落地主线硬门，不能因为使用兼容入口而跳过。

## 2. final_check 恢复

先重新编译 context pack，确认：

- 没有未决产品问题；
- `implementation_commit` 是 PM 最后看到的版本；
- 所有 required checks 都有新鲜证据；
- 每份证据的 `source_hash` 和 `commit` 与合同一致；
- `limited / skipped / blocked` 有 PM 明确接受记录；
- 行为检查不是 `fail`。

然后运行：

```bash
python3 "$PMAI_HOME/scripts/build-contract.py" validate-land \
  "<build worktree>/docs/modules/<模块>"
bash "$PMAI_HOME/scripts/close-work.sh" \
  "<build worktree>/docs/modules/<模块>"
```

失败处理：

- 检查失败：回 `iterating`，保留工作区；
- merge 冲突：保留 `final_check`、分支和 worktree，解决冲突后重跑；
- 不清理、不 hard reset、不把无关脏改动带进提交。
- 主仓 main 上允许保留其它未提交 WIP；实现合并使用 `autostash` 保护这些改动，但真实路径冲突仍停住。

## 3. landed/docs_pending 恢复

实现已经在 main 时，禁止再次 merge 或重新跑实现落地。只做：

1. 在 main 重新编译 context pack；
2. 读取 `.pm-workflow/audits/<模块>/doc-impact.json`；
3. 若 impact map 缺失，用 landed diff、build contract 和 accepted deltas 重新生成；
4. 调用 spec-writing 的“落地主线后的目标对账”模式；
5. 按影响地图更新受影响的 `PRODUCT-STATE.md`、`PRODUCT-RULES.md`、`PRODUCT.md`、`DESIGN.md`、`TODO.md`、mockup manifest 和索引；
6. 未受影响项标 `no-change` 并写原因；
7. 校验每个新增或改变的对象、动作、状态、权限、页面和术语都有文档落点；
8. 完成覆盖后运行：

```bash
python3 "$PMAI_HOME/scripts/doc-impact.py" validate \
  ".pm-workflow/audits/<模块>/doc-impact.json"
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
- merge 冲突不清理 worktree；文档失败不重复 merge。
- 正式文档在实现落 main 后更新，单独提交。
- 不向 PM 再问 worktree、执行器、手动 close 或逐条“要不要保存”菜单。
- gstack/browser/Playwright 只是证据生产者，PMAI contract 才是落地主线判断入口；v2 UI 验收必须有 active browser-smoke，不能用 exception 跳过。
