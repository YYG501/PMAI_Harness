# 最终化执行合同

## 原则

- PM 定稿前不生成 candidate build、browser 或文档 patch；最终化提速来自删除重复工作，不是把工作提前。
- 正常路径只跑三道门：一次代码验证、一次批准范围/规格覆盖、一次受影响体验批次。
- 真实构建缺陷、浏览器失败、merge 冲突或 PM 新反馈立即退出/重置 10 分钟目标，不得播报成正常路径成功。

## 统一入口

PM 明确定稿后调用：

```bash
python3 "$PMAI_HOME/scripts/finalize-work.py" \
  --module-dir "$BUILD_DIR/docs/modules/<模块>" \
  <Web 项目追加 --browser-manifest "$BUILD_DIR/.pm-workflow/audits/<模块>/browser-manifest.json">
```

runner 按 v4 lifecycle 续跑并自动完成 currentness、隔离命令验证、浏览器批次、evidence 记录、review-ready、accept 和 landing。已经通过且仍绑定同一 commit/source hash 的机械项不重复执行。

返回码 `3` 表示机械项已完成，但仍缺当前主控必须语义判断的检查，例如 `prototype-boundary / coverage / scope-coverage / migration / security`。runner 会保持一个 running `semantic-validation` 计时；按现有专用脚本或规格对账完成并 `record-evidence` 后，原命令重跑即可从准确位置继续且不重复 currentness。实现/source 变化或 PM 新反馈会把该次语义阶段记为失败并重置正常路径。不得把语义检查伪造成 runner 自动通过。

runner 在 `final_check` 只提交当前模块 `.work-meta.json` 和对应 audit 目录，再进入 landing，其他 staged 路径会立即阻断。worktree 成功合入后会进入安全待清理队列，并立即输出 `FINALIZE_RESUME_MODULE=<main 模块路径>`；完成文档地图后用该 main 路径重跑，不能继续引用等待后台清理的 worktree 路径。

旧 v4 若已经进入 `final_check` 且没有 `finalize-run.json`，直接按原状态落地，不补造 runner 游标，也不要求迁移 timing 字段。只有本轮 runner 已创建且绑定当前 commit/source hash 的游标，landing 才启用完整阶段账本硬门。

## 浏览器批次

Web 新 build 只生成一个 `browser-acceptance` final check，不再分别跑 browser-smoke、visual、behavior。旧 v2/v3/v4 合同若已经记录旧三项，仍按旧证据恢复，不迁移合同。

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

`browser-acceptance.py` 把全部命令交给 gstack `browse chain` 一次执行，并由合同核验单会话、三类覆盖、流程状态和截图文件。不得手写 pass artifact。

## 文档

实现 landed 后才由 `doc-impact.py` 生成地图：

- `PRODUCT-STATE.md` 记录本轮真实落地状态；
- accepted delta 才要求模块 spec、decisions 和 delta 明确指向的产品真相源；
- landed diff 已经修改的正式文档自动记为 covered；
- 未受影响的 PRODUCT、RULES、DESIGN、TODO、mockup 和索引不进入清单，不再逐份打开后写 no-change。

完成地图中的 pending 项后执行 `docs-complete`，再用 runner 输出的 main 模块路径重跑统一入口。`landed/docs_pending`、`documenting/complete` 都由现有 lifecycle 恢复，不重复 merge。完成提交前，runner 会校验本次适用的 currentness、命令验证、浏览器、语义判断、landing 和 documentation timing 都有通过记录且没有 running 项。
