---
name: pmai-build
description: |
  统一构建前台：读取 design 已提交的建造依据和项目级构建类型，后台生成默认验收；AI 推荐工作环境和构建工具，PM 一次确认后开工。PM 看结果多轮修改，明确说“定稿 / 可以提交 / 可以合并”后自动完成最终检查、落地主线和主线后的文档同步。
---

# /pmai-build · 统一构建与迭代主线

## 入口护栏

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill BUILD || true
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止并引导 PM 先发 `/pmai-init-project`。

执行前完整读取：

- `skills/_shared/context-reconstruction.md`
- `skills/_shared/decision-policy.md`
- `skills/_shared/gstack-integration.md`
- `skills/_shared/PM-VIEW-RULES.md` 及其引用的 PM 视图规则
- `skills/_shared/pm-view/banner-rules.md`
- 当前仓 `DESIGN.md`（UI 相关时）
- 当前模块 `spec.md` / `decisions.md` 与 context pack

## 定位

prototype 和 product 共用同一条生命周期：

```text
ready_to_build → building → iterating → final_check
→ landed → documenting → complete
```

它们只切换 build 对象和验收适配器，不分叉成两套工作流。

PM 的主体验是：开工前只确认一次工作环境和构建工具 → 看构建结果 → 提修改 → 再看 → 明确定稿。项目类型和验收方案不出现在开工确认卡；worktree、合同、hash、证据和文档影响地图等内部实现也不向 PM 展示。

纯错字、单文案、局部样式或不改变产品行为的极小修补走 `/pmai-quick-fix`。把 mockup / spec 做进主原型、改变信息结构或同时涉及实现和正式文档，不得伪装成小改；只要进入本 skill，就按完整 build 执行，并在开工前确认工作环境。

所有持久化路径必须由 `PMAI_HOME`、`REPO_ROOT`、`MAIN_REPO_ROOT`、`BUILD_DIR` 等运行时变量与仓内相对路径组合，禁止写死 `/Users/...` 这类机器绑定路径。

## 1. 恢复建造依据

定位模块和建造锚点：模块 `docs/modules/<模块>/spec.md` 或 PM 明确给出的功能型规格文档。优先读取 design 留下的：

- `lifecycle_state=ready_to_build`；
- `approved_source_hash`；
- `design_revision`；
- `design_checkpoint_commit`。

重新编译 context pack 并实际消费 active 决定、未决问题、相关页面/源码入口：

```bash
MODULE_DIR="$REPO_ROOT/docs/modules/<模块>"
CONTEXT_PACK="$REPO_ROOT/.pm-workflow/context/<模块>.json"

python3 "$PMAI_HOME/scripts/context-pack.py" \
  --repo-root "$REPO_ROOT" --module "$MODULE_DIR" \
  --goal "<本轮建造目标>" --output "$CONTEXT_PACK"
```

如果还有会改变产品模型的未决问题，停止 build，返回 design。若规格已经闭合但旧项目没有 `ready_to_build` 记录，后台执行 design 的规格编译、范围提交和 `build-contract.py ready`，不弹“是否保存建造依据”。

## 2. 静默读取项目类型并生成默认验收

build 不根据本轮话术、锚点或改动路径临时猜构建对象，也不在每次开工时重新询问。项目类型只读项目定义：

```bash
PROJECT_TYPE=$(python3 "$PMAI_HOME/scripts/project-type.py" "$REPO_ROOT")
```

- 新项目的真相源是 `.pm-workflow/config.yml:project.type`，只能是 `prototype` 或 `product`；
- 旧消费仓缺该字段时，helper 只兼容读取 `CLAUDE.md` 的既有 `auto-detected` 标记；`system` 映射为 `product`；
- `custom / unknown` 或无法读取时停止 build，要求 PM 先修改 `.pm-workflow/config.yml`；不得在本轮对话中临时选一个继续；
- PM 想改变项目性质时，直接修改该定义文件，再按新类型校准项目结构。

根据项目类型、目标路径、入口和风险后台生成默认验收档案：

```bash
PROFILE="$REPO_ROOT/.pm-workflow/audits/<模块>/acceptance-profile.json"
python3 "$PMAI_HOME/scripts/acceptance-profile.py" \
  --repo-root "$REPO_ROOT" \
  --target "$PROJECT_TYPE" \
  --path "<目标路径>" \
  <涉及迁移时 --data-migration> \
  <涉及权限/安全时 --security-sensitive> > "$PROFILE"
```

验收方案由框架默认规则决定，不让 PM 选择，也不展示在开工确认卡。工具受限、检查失败或出现 exception 时仍按 §7 如实记录，不能因为“不展示”而跳过。

## 3. 推荐工作环境与构建工具，由 PM 一次确认

恢复既有 v2 build 时，沿用合同里已确认的工作环境和构建工具，不重复确认。新 build 才执行本节：

1. **推荐工作环境**：默认推荐“独立环境”；若当前已经是本模块有效的 `build-*` 环境，则推荐“继续当前独立环境”。PM 也可以明确改为“当前环境”。
2. **推荐构建工具**：按项目级类型、消费仓配置和本机可用性只生成推荐，不视为最终选择：

   ```bash
   RECOMMENDED_BUILDER_JSON=$(python3 "$PMAI_HOME/scripts/builder-profile.py" recommend \
     "$REPO_ROOT/.pm-workflow/config.yml" --target "$PROJECT_TYPE")
   ```

3. **只展示这张确认卡**：

   ```text
   准备构建：<模块或目标>

   工作环境：<独立环境 | 继续当前独立环境 | 当前环境>
   构建工具：<工具名（model, thinking）>

   [按这个方案构建]
   [调整工作环境]
   [调整构建工具]
   ```

   卡片中禁止出现项目类型、验收方案、检查清单、worktree、build contract、hash、evidence JSON 等内容。`prototype / product` 只在后台参与适配，不作为本轮待确认项。

4. PM 调整工作环境时，只用 PM 语言展示“独立环境 / 当前环境”；选择当前环境代表本轮直接在当前主线工作，写入 `build.mode=main`。选择独立环境写入 `build.mode=worktree`。若当前环境不是 main/master，也不是本模块已记录的 `build-*` 环境，不提供“当前环境”这个无效选项。
5. PM 调整构建工具时，运行 `builder-profile.py list <config> --available-only`，只列本机可用工具；PM 选定后用 `resolve --profile <name>` 固化 snapshot。
6. 任一项调整后重新展示同一张卡；只有 PM 选择“按这个方案构建”才继续。AskUserQuestion 不可用时退化为三项编号选择并等待，不得把推荐自动当成确认。

确认后再建立或复用工作环境：

```bash
if [ "$BUILD_MODE" = "worktree" ]; then
  BUILD_BRANCH="build-<模块>-<时间戳>"
  BUILD_DIR="$MAIN_REPO_ROOT/.worktrees/$BUILD_BRANCH"
  git -C "$MAIN_REPO_ROOT" worktree add -b "$BUILD_BRANCH" "$BUILD_DIR" main
else
  BUILD_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"
  BUILD_DIR="$REPO_ROOT"
fi
```

所有 git 命令使用 `git -C "$BUILD_DIR"`；必须切目录的非 git 命令只在 subshell 中运行，不把主控 cwd 留在 worktree。

执行器使用 `EXECUTOR_STATUS_DIR`、heartbeat、退出码和日志文件回报进度；PM 窗口只报阶段摘要，不直播命令、日志和进程排障。可确认的构建工具包括当前主控、Claude Code、Codex、Cursor Agent、Gemini 和 OpenCode；卡片只显示当前推荐，PM 点“调整构建工具”时才展开可用项。

从 acceptance profile 取 `required_checks`，写合同 v2：

```bash
START_ARGS=(
  "$BUILD_DIR/docs/modules/<模块>"
  --anchor "<仓内建造锚点>"
  --mode "$BUILD_MODE"
  --executor "<PM 已确认的结果>"
  --builder-profile "<PM 已确认的结果>"
  --builder-json "<PM 已确认的 builder snapshot>"
  --branch "$BUILD_BRANCH"
  --baseline-sha "$(git -C "$BUILD_DIR" rev-parse HEAD)"
  --target-kind "$PROJECT_TYPE"
  --target-path "<目标路径>"
  --entrypoint "<入口>"
  --approved-source-hash "<ready 记录的 hash>"
  --design-revision "<ready 记录的 revision>"
  --required-check "<检查名>"
)
[ "$BUILD_MODE" = "worktree" ] && START_ARGS+=(--worktree "$BUILD_DIR")
python3 "$PMAI_HOME/scripts/build-contract.py" start "${START_ARGS[@]}"

git -C "$BUILD_DIR" add -- "docs/modules/<模块>/.work-meta.json"
git -C "$BUILD_DIR" commit -m "build(<模块>): start adaptive build"
```

`--required-check` 按后台档案逐项重复传入。合同只扩展现有 `.work-meta.json:build`，不新增平行状态系统，也不把合同内容展示给 PM。

## 4. 构建指定对象

把下面内容一次性交给 PM 已确认的构建工具：

- 建造锚点全文；
- context pack 中相关 active 决定和 accepted deltas；
- build target、目标路径和入口；
- 完整任务、相关页面、边界状态和验收标准；
- UI 相关时的 `DESIGN.md` 与已有组件/页面；
- 只改目标对象，不改正式产品文档；禁止自行 commit。

### prototype 适配器

- 优先复用当前原型组件与现有界面语言；
- 建主路径、关联页面、弹窗/抽屉和相关边界状态；
- 允许 mock 数据，但必须标清哪些是 mock、哪些行为已建实；
- 建完启动原型，给 PM 可访问入口。

### product 适配器

- 遵守仓库真实架构、测试和迁移约束；
- 实现接口、数据、权限和兼容行为，不用 prototype 壳替代；
- 涉及 UI 时复用真实产品组件并准备浏览器验收；
- 涉及迁移、安全或破坏性数据动作时追加相应检查。

构建工具失败时默认保留半成品，先检查已落改动与日志；若要换工具，给出新的推荐并重新展示只含工作环境和构建工具的确认卡，不能静默替换 PM 已确认的工具。只有丢弃会破坏可用改动时才让 PM 授权；禁止自动 `git restore .` / `git clean -fd`。

启动页面时只读取 `.pm-workflow/config.yml:dev_server.command` 并替换 `{port}`，不临时猜 `-- --hostname`、`--port` 或其它框架参数。

## 5. 进入 PM 看结果的迭代循环

首次实现完成后提交目标改动，并记录实现 commit，进入 `iterating`：

```bash
git -C "$BUILD_DIR" add -- <target paths>
git -C "$BUILD_DIR" commit -m "build(<模块>): implement <结果>"
IMPLEMENTATION_COMMIT=$(git -C "$BUILD_DIR" rev-parse HEAD)
python3 "$PMAI_HOME/scripts/build-contract.py" commit \
  "$BUILD_DIR/docs/modules/<模块>" \
  --implementation-commit "$IMPLEMENTATION_COMMIT"
git -C "$BUILD_DIR" add -- "docs/modules/<模块>/.work-meta.json"
git -C "$BUILD_DIR" commit -m "build(<模块>): record iteration"
```

给 PM 看结果，不先跑完整发布门。PM 每轮反馈后：

1. 判断是实现修正，还是新的产品决定；
2. 只改受影响路径；
3. 只跑受影响的快速检查；
4. 提交该轮修改；
5. 再给 PM 看。

如果反馈改变对象、动作、状态、权限、真相源、页面任务或产品规则，记录 accepted delta：

```bash
python3 "$PMAI_HOME/scripts/build-contract.py" add-delta \
  "$BUILD_DIR/docs/modules/<模块>" \
  --summary "<PM 接受的新产品决定>" \
  --affected-surface "<受影响文档/页面>"
```

这会递增 `design_revision`、更新 source hash、清空旧证据并回到 `iterating`。正式文档仍等实现落到 main 后统一更新。

实现修正不改变产品决定时，不递增 revision；但实现 commit 变化后，绑定旧 commit 的证据不能复用。

## 6. 识别 PM 定稿语义，自动进入 final_check

下列表达在 PM 已看到当前结果的语境中，视为对提交并合入 main 的明确授权：

- “可以提交”
- “定稿”
- “可以合并”
- “这版可以了”
- “提交吧 / 合进去吧”

该表达本身就是 one-way door 授权，不再二次问“是否收尾”，也不要求 PM 手动发 `/pmai-build-close`。

先提交最后一轮目标改动，记录该实现 commit 和 PM 验收：

```bash
IMPLEMENTATION_COMMIT=$(git -C "$BUILD_DIR" rev-parse HEAD)
python3 "$PMAI_HOME/scripts/build-contract.py" complete \
  "$BUILD_DIR/docs/modules/<模块>" \
  --implementation-commit "$IMPLEMENTATION_COMMIT"
```

重新编译 context pack。若出现未决产品问题，回 `iterating`；不得带着问题落主线。

## 7. 对最终 commit 跑完整验收

只在 final_check 跑 acceptance profile 的全部 `required_checks`。

### prototype 完整检查

- 可启动性和主动 browser smoke；
- 建造依据逐项覆盖；
- 关键任务路径、页面、弹窗/抽屉；
- 空态、错误态、长内容、权限差异等相关状态；
- 对照 `DESIGN.md` 的视觉一致性；
- 实际交互行为。

优先使用 browser/gstack 生成证据。

若 `DESIGN.md` 的视觉基线段未建，先以现有产品页面和组件为事实基线，并在可用时自动调用 gstack `/design-consultation` 补充检查依据；仍不足时视觉检查只能记为 `limited`，不能输出“视觉一致性通过”。这不是让 PM 选择工具或补工程配置的菜单。

### product 完整检查

- 规格范围覆盖；
- 仓库已有测试、typecheck、build；
- 接口与数据行为；
- 迁移、回滚、兼容读取（涉及时）；
- UI 浏览器检查（涉及时）；
- 权限、安全、越权和破坏性数据检查（涉及时）。

每项都用 `record-evidence` 绑定同一个 `approved_source_hash + implementation_commit + checked_at`。工具受限只能写 `limited / skipped / blocked` 并记录 exception；不得伪装 `pass`。行为检查 `fail` 不能例外放行。

完整检查失败：

```bash
python3 "$PMAI_HOME/scripts/build-contract.py" iterating "$BUILD_DIR/docs/modules/<模块>"
```

保留当前工作环境，修复后再由 PM 看结果；不 merge、不清理。

完整检查通过后提交 audit artifacts 与合同状态，再运行：

```bash
python3 "$PMAI_HOME/scripts/build-contract.py" validate-land \
  "$BUILD_DIR/docs/modules/<模块>"
```

## 8. 自动落地主线

最终检查通过后直接调用同一 finalize 流程：

```bash
bash "$PMAI_HOME/scripts/close-work.sh" "$BUILD_DIR/docs/modules/<模块>"
```

- 独立环境发生 merge 冲突：停止在可恢复的 `final_check`，保留分支和 worktree；
- 不清理或回退用户无关脏改动；
- 实现落主线后进入 `landed + docs_pending`；
- `/pmai-build-close` 只作为兼容或恢复入口，正常链路无需 PM 再调用。

## 9. 基于 main 编译正式文档

第一次 finalize 返回 doc impact map 后，必须在 main 上完成：

1. 重新生成 context pack；
2. 读取 landed diff、build contract、accepted deltas 和 doc impact map；
3. 调用 spec-writing 的“落地主线后的事实对账”模式更新模块 `spec.md` 与 `decisions.md`；
4. 按影响地图更新 `PRODUCT-STATE.md`、`PRODUCT-RULES.md`、`PRODUCT.md` 术语、`DESIGN.md`、`TODO.md`、mockup manifest 和索引；
5. 未受影响文件标 `no-change` 并写原因；
6. 检查新增或改变的对象、动作、状态、权限、页面和术语都有文档落点；
7. 对 doc impact 每项执行 `doc-impact.py cover`；
8. `doc-impact.py validate` 通过后执行 `build-contract.py docs-complete`；
9. 再次调用 `close-work.sh`，单独提交文档同步、删除临时 `.work-meta.json` 并进入 `complete`。

正式文档只描述 main 已经存在的事实。不得在 merge 前提前改成“已完成”。

文档失败时：

```bash
python3 "$PMAI_HOME/scripts/build-contract.py" docs-fail \
  "$REPO_ROOT/docs/modules/<模块>" --reason "<失败原因>"
```

保留 `landed + docs_pending`。续跑只从文档影响地图继续，不重复 merge。

## PM 回执

迭代中：

```text
这版已经可以看：<入口>。
这轮完成了：<主路径和关键状态>。
你直接看结果说哪里要改；我会继续改并只复查受影响部分。
```

完成后：

```text
✅ <模块> 已定稿：最终检查通过，改动已进入主线，正式文档也按主线事实更新完成。

▶ Next Up：继续 /pmai-design <下一个模块>，或 /pmai-status 看当前产品现状。
```

## Rules

- prototype / product 共用同一生命周期，只切换目标和验收适配器。
- 项目类型由 `.pm-workflow/config.yml` 项目级定义；build 只读，不按本轮需求猜，也不在开工确认卡展示。
- 验收方案按项目类型和风险后台生成默认值；不让 PM 选择，也不在开工确认卡展示。
- 新 build 开工前，AI 推荐工作环境和构建工具，PM 只确认这两项；调整后必须重显同一张确认卡。
- PM 不需要理解 worktree、合同、hash、证据 JSON 或手动 close；构建工具只以名称、模型和思考档展示。
- 迭代中只跑受影响快速检查；PM 定稿后才跑全部 required checks。
- 新产品决定进入 accepted deltas 并使旧证据失效；实现 commit 变化也使旧证据失效。
- PM 明确说“可以提交 / 定稿 / 可以合并”就是落地主线授权，不二次确认。
- 最终检查失败回 iterating；merge 冲突保留 final_check 和 worktree。
- 实现先落 main，正式文档后更新；文档失败不重复 merge。
- skipped / limited / blocked 不能伪装 pass；证据必须绑定 source hash 和 implementation commit。
- 正式文档无迭代流水账，历史只在 Git 与 decisions 中。
