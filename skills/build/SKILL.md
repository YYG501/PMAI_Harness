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

若由 `/pmai-lark-review` 进入，先完整读取 `skills/lark-review/references/lifecycle-handoff.md`。新 build 只能在 T 已 seal/apply、候选决定正式归位、飞书精细同步、design 重新生成 context pack 并提交建造依据后启动。已有 active build 在 seal/apply 前完成 §5 的决定层级分流并把执行路径固化到评审批次：产品级或模块模型变化退出当前 active-build 批次，分别回 `/pmai-proposal` / `/pmai-design`；实现纠偏直接修实现、不写 delta；只有已固化的 accepted-delta 路径才继续 apply。apply 后不得重新分类；该路径先精细同步飞书、verify 并稳定发布 frontmatter，再重新编译当前模块 context pack、调用 `add-delta --applied-context-pack <pack>`、提交精确 authority checkpoint，最后继续实现。

执行前完整读取：

- `skills/_shared/context-reconstruction.md`
- `skills/_shared/decision-policy.md`
- `skills/_shared/loop-contract.md`
- `skills/_shared/gstack-integration.md`
- `skills/_shared/project-design-system.md`
- `skills/_shared/PM-VIEW-RULES.md` 及其引用的 PM 视图规则
- `skills/_shared/pm-view/banner-rules.md`
- `skills/build/references/finalization.md`
- 当前仓 `DESIGN.md`（UI 相关时）
- 当前模块 `spec.md` / `decisions.md` 与 context pack

## 定位

prototype 和 product 共用同一条生命周期：

```text
ready_to_build → building → iterating → final_check
→ landed → documenting → complete
```

它们只切换 build 对象和验收适配器，不分叉成两套工作流。

## Build Loop Mapping

本阶段按 `loop-contract.md` 的 Build 映射执行：current `ready_to_build`、项目建造定义、build contract、目标与实现深度、当前 implementation commit、证据和 PM 新反馈是输入；批准路径内实现、当前车道检查与有证据的小范围调整是允许动作；currentness、路径、实现结果和绑定 commit/source hash 的证据是验证。

实现偏差与普通缺陷执行 `retry_current`；模块对象、规则、权限、关键路径、验收目标或 prototype real edge 变化执行 `route_design`；产品用户、价值、边界、MVP 或关键成立前提变化执行 `route_proposal`；新 build 的环境/工具、不可逆动作或多个 active build 无法唯一定位时执行 `await_pm_decision`。PM 明确定稿且冻结候选的 final evidence 全部通过后，才执行 `advance → final_check/landing`。恢复时严格使用 `resume_checkpoint`：`final_check` 只补缺失的验收/landing，`landed + docs_pending` 只补文档，已经完成的动作不重放。

PM 的主体验是：开工前只确认一次工作环境和构建工具 → 看构建结果 → 提修改 → 再看 → 明确定稿。项目类型和验收方案不出现在开工确认卡；worktree、合同、hash、证据和文档影响地图等内部实现也不向 PM 展示。

### 已有 build 的自然语言续接

当已有 `building / iterating / final_check`，PM 不必重复输入命令。“启动起来看看”“检查当前结果”“还有什么没有解决”“按刚才结果继续改”等都沿用当前 `/pmai-build`。只有 PM 明确开启无关的新工作时才转其它入口；多个可续接 build 时只问本轮模块，不静默猜测。

续接时先读取 `active-build-context.py`，再按 §1 重新编译并消费 context pack。该输出会重新校验当前 Product Proposal / 等价产品基线、`PRODUCT.md`、模块规格、决定、build contract 与 `project.yml`，只读不写状态。任一权威来源在批准后变化、Proposal 无效、合同无效或 policy 漂移时立即停止续接；产品方向缺口回 `/pmai-proposal`，其余建造依据变化回 `/pmai-design`，不得继续修改或记录 implementation commit，也不得绕过当前 `target + delivery_policy + acceptance lane` 转成通用 QA。

仅当 v1-v4 active build 早于 Proposal 合同、且 PM 明确确认当前规格与产品依据仍是该轮有效起点时，才可运行 `legacy-work-recovery.py accept` 建立一次性恢复 checkpoint。该命令保留旧 delta/hash 审计记录，以当前 authority 内容 hash 重建后续链，不升级合同版本、不生成 Proposal、不修改模块文档；恢复后的任一绑定内容再次变化仍立即停止。新工作、v5 build 和没有 PM 明确确认的旧工作不得使用此入口。

### 上游重规划留下的候选

design 若交来 `replan-work.py` 返回的精确 `candidate_manifest`，先只读查看旧实现差异。跨会话或变量丢失时，先从 main 读取全部候选，再按当前模块和 design 交接的 route 精确匹配；禁止按 mtime 或“最近一次”猜测：

```bash
REPLAN_CANDIDATES_JSON=$(python3 "$PMAI_HOME/scripts/replan-work.py" \
  list "$MAIN_REPO_ROOT")
python3 "$PMAI_HOME/scripts/replan-work.py" inspect "$CANDIDATE_MANIFEST"
```

`list` 必须读取全部结果；没有精确匹配就不消费，出现多个匹配就停止厘清，不能静默选一个。`inspect` 的 diff 固定为“原 baseline 到旧冻结候选”，后续 main 提交不会混入。

按候选模式处理：

- `worktree`：该 diff 只是参考，不是新 build 的 baseline 或默认实现。仍需要的内容在新环境重新实现并验证，已被替代或放弃的内容明确排除；禁止整分支 merge、整包复制或自动 cherry-pick。
- `main`：该 diff 中的实现已经位于当前 main。新 build 从当前 main 正常起步，逐项验证应保留的行为，并用新的提交前向调整或显式撤销不再成立的部分；不得把同一实现盲目重做，也不得由 replan/retire 回滚它。

只有上述差异都已逐项采用、替代或明确放弃，才显式退役旧候选。worktree 候选要求对应结果已经进入当前新 build 的实现提交；main 候选若原实现继续成立，可在当前 build 已按新依据验证后保留，不强制造一次无意义重写，前向调整或撤销则必须进入新的实现提交：

```bash
python3 "$PMAI_HOME/scripts/replan-work.py" retire \
  "$CANDIDATE_MANIFEST" --reconciled
```

worktree 候选 retire 后把旧 worktree/branch 送入现有 pending cleanup 并清除 manifest；main 候选 retire 只清除 manifest，不建清理任务、不改 main 实现。两者都不改变新 build 合同。未完成逐项核对时保留 manifest；路径丢失、候选漂移或队列身份冲突时停止。

纯错字、单文案、局部样式或不改变产品行为的极小修补走 `/pmai-quick-fix`。把 mockup / spec 做进最终 build target、改变信息结构或同时涉及实现和正式文档，不得伪装成小改；只要进入本 skill，就按完整 build 执行，并在开工前确认工作环境。

所有持久化路径必须由 `PMAI_HOME`、`REPO_ROOT`、`MAIN_REPO_ROOT`、`BUILD_DIR` 等运行时变量与仓内相对路径组合，禁止写死 `/Users/...` 这类机器绑定路径。

## 1. 恢复建造依据

定位模块和建造锚点：模块 `docs/modules/<模块>/spec.md` 或 PM 明确给出的功能型规格文档。优先读取 design 留下的：

- `lifecycle_state=ready_to_build`；
- `approved_source_hash`；
- `design_revision`；
- `design_checkpoint_commit`；
- `approved_target.paths`。

重新编译 context pack 并实际消费 active 决定、未决问题、相关页面/源码入口：

```bash
MODULE_DIR="$REPO_ROOT/docs/modules/<模块>"
CONTEXT_PACK="$REPO_ROOT/.pm-workflow/context/<模块>.json"

python3 "$PMAI_HOME/scripts/context-pack.py" \
  --repo-root "$REPO_ROOT" --module "$MODULE_DIR" \
  --goal "<本轮建造目标>" --output "$CONTEXT_PACK"

READY_JSON=$(python3 "$PMAI_HOME/scripts/build-contract.py" validate-ready \
  "$MODULE_DIR" --context-pack "$CONTEXT_PACK")
TARGET_PATHS=()
while IFS= read -r path; do
  TARGET_PATHS+=("$path")
done < <(python3 -c 'import json,sys; print(*json.load(sys.stdin)["target_paths"], sep="\n")' <<<"$READY_JSON")

python3 "$PMAI_HOME/scripts/build-contract.py" check-dirty "$MODULE_DIR"
```

`validate-ready` 必须确认当前 source hash 与 design 批准依据一致，并取得 design 已固定的目标路径；不一致时停止 build，返回 design 重新核对。`check-dirty` 只阻断目标路径上已有的未提交改动，防止旧原型改动被默认带入或丢失；其它路径的用户改动继续保护，不要求清空整仓。给 PM 说明时翻译成受影响页面，不展示 hash 或内部文件清单。

如果还有会改变产品模型的未决问题，停止 build，返回 design。若规格已经闭合但旧项目没有完整 `ready_to_build + approved_target` 记录，后台执行 design 的规格编译、目标路径固定、范围提交和 `build-contract.py ready`，不弹“是否保存建造依据”。

## 2. 读取 design 已确认的项目建造定义

build 不根据本轮话术、锚点或改动路径临时猜构建对象、技术栈或运行命令。先完整校验 design 已提交的项目定义：

```bash
PROJECT_DEFINITION_JSON=$(python3 "$PMAI_HOME/scripts/project-definition.py" show "$REPO_ROOT")
PROJECT_TYPE=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["project"]["type"])' <<<"$PROJECT_DEFINITION_JSON")
IMPLEMENTATION_ROOT=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["implementation"]["root"])' <<<"$PROJECT_DEFINITION_JSON")
PROJECT_ENTRYPOINTS=()
while IFS= read -r path; do
  PROJECT_ENTRYPOINTS+=("$path")
done < <(python3 -c 'import json,sys; print(*json.load(sys.stdin)["implementation"]["entrypoints"], sep="\n")' <<<"$PROJECT_DEFINITION_JSON")
```

- 新项目唯一真相源是 `.pm-workflow/project.yml`，其中同时定义 type、代码根、入口、技术栈、真实命令和 Web 能力；
- 文件缺失或校验失败时停止 build，返回 `/pmai-design` 完成或修复定稿；build 不提供临时补选菜单；
- 旧消费仓仅由 `project-type.py` 兼容读取旧 config/marker；下一次 design 定稿时必须生成新文件；
- 改变 type、framework 或 root 必须回 design 由 PM 明确确认并递增 revision。

`TARGET_PATHS` 只取自上一步通过 currentness 校验的 design 批准范围。每一项都必须是仓内相对路径、位于 `implementation.root` 内，并命中 `PROJECT_ENTRYPOINTS` 中的实现入口。不得用整仓 `.`、context pack 搜索结果或当前文件树猜一个替代路径。

根据项目类型、本轮目标路径、项目入口和风险后台生成默认验收档案：

```bash
WORK_ID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' \
  "$REPO_ROOT/docs/modules/<模块>/.work-meta.json")
AUDIT_DIR_REL=".pm-workflow/audits/<模块>/$WORK_ID"
PROFILE="$REPO_ROOT/$AUDIT_DIR_REL/acceptance-profile.json"
mkdir -p "$(dirname "$PROFILE")"
PROFILE_ARGS=(
  --repo-root "$REPO_ROOT"
  --project-definition "$REPO_ROOT/.pm-workflow/project.yml"
)
for path in "${TARGET_PATHS[@]}"; do
  PROFILE_ARGS+=(--path "$path")
done
<涉及迁移时 PROFILE_ARGS+=(--data-migration)>
<涉及权限/安全时 PROFILE_ARGS+=(--security-sensitive)>
python3 "$PMAI_HOME/scripts/acceptance-profile.py" "${PROFILE_ARGS[@]}" > "$PROFILE"
```

验收档案同时编译 `delivery_policy`：规格继续决定最终产品语义，`project.type` 决定本轮实现深度。`prototype` 固定为 `interactive-simulation`，`product` 固定为 `production-implementation`；build 不得把“完整规格”误解成“原型也要把底层建实”。验收方案和实现深度合同都由框架后台决定，不让 PM 重选，也不展示在开工确认卡。工具受限、检查失败或出现 exception 时仍按 §7 如实记录，不能因为“不展示”而跳过。

## 3. 推荐工作环境与构建工具，由 PM 一次确认

恢复既有 v2 / v3 / v4 build 时，沿用合同里已确认的工作环境和构建工具，不重复确认。新 build 才执行本节：

1. **推荐工作环境**：默认推荐“独立环境”；若当前已经是本模块有效的 `build-*` 环境，则推荐“继续当前独立环境”。PM 也可以明确改为“当前环境”。
2. **识别当前主控并推荐构建工具**：把当前 runtime 映射成 `claude-code / codex / kimi-code / opencode / cursor-agent`；无法识别时用 `unknown`。Claude Code、Codex、Kimi Code、Cursor Agent 和 OpenCode 都可以作为外部构建工具，但 profile 必须和当前主控不同，不能让任一主控再次启动自己；“当前会话直接构建”不是外部 profile，始终作为有效选项。按项目级类型、消费仓配置和本机可用性生成推荐与完整可选列表：

   ```bash
   CURRENT_HOST="<claude-code | codex | kimi-code | opencode | cursor-agent | unknown>"
   RECOMMENDED_BUILDER_JSON=$(python3 "$PMAI_HOME/scripts/builder-profile.py" recommend \
     "$REPO_ROOT/.pm-workflow/config.yml" \
     --project-definition "$REPO_ROOT/.pm-workflow/project.yml" \
     --current-host "$CURRENT_HOST")
   AVAILABLE_BUILDERS_JSON=$(python3 "$PMAI_HOME/scripts/builder-profile.py" list \
     "$REPO_ROOT/.pm-workflow/config.yml" \
     --available-only \
     --current-host "$CURRENT_HOST")
   ```

   `list` 和 `recommend` 都必须排除当前主控对应的外部 profile。`list` 在其它可用外部工具之外始终包含“当前会话直接构建”；`recommend` 仍优先按项目配置选择可用外部 profile，没有可用外部工具时才推荐当前会话直接构建。

3. **一次展示推荐结果和全部有效选项**：

   ```text
   准备构建：<模块或目标>

   工作环境（已选）：<独立环境 | 继续当前独立环境 | 当前环境>
   可选环境：
   - 独立环境：在单独环境构建，不影响当前工作；已有本模块独立环境时继续使用
   - 当前环境：直接在当前目录构建

   构建工具（已选）：<工具名（model, thinking） | 当前会话直接构建>
   本机可用工具：
   - 当前会话直接构建
   - <工具名（model, thinking）>（已选）
   - <其它可用工具（逐项列出）>

   回复“按这个方案构建”即可开始；
   也可以直接回复“工作环境改为<选项>”或“构建工具改为<工具名>”。
   ```

   “当前环境”只在当前环境有效时列出；若当前环境不是 main/master，也不是本模块已记录的 `build-*` 环境，就不显示这个无效选项。工具列表只取 `AVAILABLE_BUILDERS_JSON`：始终展示“当前会话直接构建”，并逐项展示本机实际可用且非当前主控的外部工具。卡片中禁止出现项目类型、验收方案、检查清单、worktree、build contract、hash、evidence JSON 等内容。`prototype / product` 只在后台参与适配，不作为本轮待确认项。

4. PM 调整工作环境时，只用 PM 语言展示“独立环境 / 当前环境”；选择当前环境代表本轮直接在当前主线工作，写入 `build.mode=main`。选择独立环境写入 `build.mode=worktree`。若当前环境不是 main/master，也不是本模块已记录的 `build-*` 环境，不提供“当前环境”这个无效选项。
5. PM 调整构建工具时，只接受卡片已经列出的工具；选定后用 `resolve --profile <name> --current-host "$CURRENT_HOST"` 固化 snapshot。`resolve` 再次拒绝与当前主控相同的 profile，不能靠 PM 文本或旧配置绕过。
6. 任一项调整后重新展示同一张完整卡；只有 PM 选择“按这个方案构建”才继续。AskUserQuestion 不可用时仍展示完整卡并等待自然语言回复，不得把推荐自动当成确认，也不得再让 PM 先点“调整”才能看到选项。

确认后再建立或复用工作环境：

```bash
if [ "$BUILD_MODE" = "worktree" ]; then
  BUILD_BRANCH="build-<模块>-<时间戳>"
  BUILD_DIR="$MAIN_REPO_ROOT/.worktrees/$BUILD_BRANCH"
  BUILD_BASE_BRANCH="$(git -C "$MAIN_REPO_ROOT" branch --show-current)"
  if [ "$BUILD_BASE_BRANCH" != "main" ] && [ "$BUILD_BASE_BRANCH" != "master" ]; then
    if git -C "$MAIN_REPO_ROOT" show-ref --verify --quiet refs/heads/main; then
      BUILD_BASE_BRANCH="main"
    elif git -C "$MAIN_REPO_ROOT" show-ref --verify --quiet refs/heads/master; then
      BUILD_BASE_BRANCH="master"
    else
      echo "主仓缺少 main/master，不能建立独立构建环境。" >&2
      exit 1
    fi
  fi
  git -C "$MAIN_REPO_ROOT" worktree add -b "$BUILD_BRANCH" "$BUILD_DIR" "$BUILD_BASE_BRANCH"
else
  BUILD_BRANCH="$(git -C "$REPO_ROOT" branch --show-current)"
  BUILD_DIR="$REPO_ROOT"
fi
```

所有 git 命令使用 `git -C "$BUILD_DIR"`；必须切目录的非 git 命令只在 subshell 中运行，不把主控 cwd 留在 worktree。

执行器使用 `EXECUTOR_STATUS_DIR`、heartbeat、退出码和日志文件回报进度；PM 窗口只报阶段摘要，不直播命令、日志和进程排障。可确认的外部构建工具包括 Claude Code、Codex、Kimi Code、Cursor Agent 和 OpenCode，但必须排除当前主控对应的外部 profile；“当前会话直接构建”始终与这些外部工具一起列为有效选项。没有外部工具可用时，推荐当前会话直接构建。

从 acceptance profile 分别取快速迭代和定稿验收两组检查，写版本化合同。当前新合同为 v5：`iteration_checks` 只服务 PM 看结果期间的快循环，`final_checks` 只有 PM 明确请求定稿后才允许运行；build 开始后 lifecycle 只写入 `build.lifecycle_state`，不再同时写顶层 lifecycle、旧 `stage` 或 `required_checks`。同时由 `target.kind` 自动固化 `delivery_policy + delivery_policy_hash`。旧 v2/v3/v4 合同只作中断恢复兼容：

```bash
ITERATION_CHECKS=()
FINAL_CHECKS=()
while IFS= read -r check; do
  ITERATION_CHECKS+=("$check")
done < <(python3 -c 'import json,sys; print(*(item["name"] for item in json.load(open(sys.argv[1]))["iteration_checks"]), sep="\n")' "$PROFILE")
while IFS= read -r check; do
  FINAL_CHECKS+=("$check")
done < <(python3 -c 'import json,sys; print(*(item["name"] for item in json.load(open(sys.argv[1]))["final_checks"]), sep="\n")' "$PROFILE")

START_ARGS=(
  "$BUILD_DIR/docs/modules/<模块>"
  --anchor "<仓内建造锚点>"
  --mode "$BUILD_MODE"
  --executor "<PM 已确认的结果>"
  --builder-profile "<PM 已确认的结果>"
  --builder-json "<PM 已确认的 builder snapshot>"
  --branch "$BUILD_BRANCH"
  --baseline-sha "$(git -C "$BUILD_DIR" rev-parse HEAD)"
  --audit-dir "$AUDIT_DIR_REL"
  --target-kind "$PROJECT_TYPE"
  --approved-source-hash "<ready 记录的 hash>"
  --design-revision "<ready 记录的 revision>"
)
[ "${#TARGET_PATHS[@]}" -gt 0 ] || { echo "build target paths 为空，返回 design 修复建造依据" >&2; exit 1; }
[ "${#PROJECT_ENTRYPOINTS[@]}" -gt 0 ] || { echo "project.yml entrypoints 为空，返回 design 修复项目定义" >&2; exit 1; }
[ "${#FINAL_CHECKS[@]}" -gt 0 ] || { echo "acceptance profile 未生成 final_checks，停止 build" >&2; exit 1; }
for path in "${TARGET_PATHS[@]}"; do START_ARGS+=(--target-path "$path"); done
for entrypoint in "${PROJECT_ENTRYPOINTS[@]}"; do START_ARGS+=(--entrypoint "$entrypoint"); done
for check in "${ITERATION_CHECKS[@]}"; do START_ARGS+=(--iteration-check "$check"); done
for check in "${FINAL_CHECKS[@]}"; do START_ARGS+=(--final-check "$check"); done
[ "$BUILD_MODE" = "worktree" ] && START_ARGS+=(--worktree "$BUILD_DIR")
python3 "$PMAI_HOME/scripts/build-contract.py" start "${START_ARGS[@]}"

git -C "$BUILD_DIR" add -- "docs/modules/<模块>/.work-meta.json"
git -C "$BUILD_DIR" commit -m "build(<模块>): start adaptive build"
```

两组检查都按后台档案逐项重复传入。合同只扩展现有 `.work-meta.json:build`，不新增平行状态系统，也不把合同内容展示给 PM；旧合同字段只由统一兼容读取层解释，新工作不再生成。
`start` 自身会再次强制校验 current `ready_to_build`、`project.yml`、批准目标与仓内路径；缺任一前置时只能返回 design，不能由 build 补造状态或临时合同。

## 4. 构建指定对象

每次调用构建工具——包括首次实现、每轮反馈修改和中断恢复——都先从当前 `.work-meta.json:build` 重新读取 `target + delivery_policy`，并在 UI 相关时重新读取 `DESIGN.md`、按 `project-design-system.md` 解析与执行当前项目设计系统声明，不能依赖首轮 prompt 记忆。把下面内容一次性交给 PM 已确认的构建工具，且**实现深度合同必须放在规格全文之前**：

- 当前 `target.kind`、`delivery_policy` 全文及其不可违反的实现深度；
- 建造锚点全文；
- context pack 中相关 active 决定和 accepted deltas；
- build target、目标路径和入口；
- 完整任务、相关页面、边界状态和验收标准；
- UI 相关时的 `DESIGN.md` 全文与已有组件/页面；
- `DESIGN.md` 声明的设计系统名称、使用范围、项目级 Skill 名称和 Skill 仓内路径；明确要求“当前宿主能原生调用时调用；不能原生调用时，完整读取该 `SKILL.md` 及其 required references 后执行”；
- 只改目标对象，不改正式产品文档；禁止自行 commit。

已声明的项目级 Skill 缺失、不可读、未被 Git 跟踪，或构建工具无法访问其仓内路径时，在实现前停止；不得删除这段上下文后继续构建，也不得声称已经接入设计系统。未声明项目级 Skill 时，仍按 `DESIGN.md`、共享组件 inventory、已有组件和现有页面实现。

### prototype 适配器

- **规格管最终产品做什么，原型合同管本轮做到哪一层**：不得因为规格完整就把原型升级成真实系统；
- 优先复用当前原型组件与现有界面语言；
- 建主路径、关联页面、弹窗/抽屉和相关边界状态；
- 用户能看到和操作的页面、状态、反馈必须真实可交互；数据持久化、后端接口、鉴权/权限执行、外部集成、AI 引擎、异步任务和通知默认用 fixture、内存状态、localStorage 或无副作用 mock adapter 模拟；
- 未经 active decision 明确批准，不得新增生产数据库/schema/migration、真实鉴权账号体系、外部写入或密钥接入、生产基础设施/部署编排和迁移兼容代码；
- 必须列清本轮模拟了哪些底层能力、哪些用户可见行为已建成；“做得更真”不是原型的完成标准；
- 建完启动原型，给 PM 可访问入口。

### product 适配器

- 遵守仓库真实架构、测试和迁移约束；
- 实现接口、数据、权限和兼容行为，不用 prototype 壳替代；
- 涉及 UI 时复用真实产品组件并准备浏览器验收；
- 涉及迁移、安全或破坏性数据动作时追加相应检查。

外部构建工具只用于首次实现或 PM 已确认的大型重构。active build 内的文案、间距、布局、按钮命名和局部交互反馈默认由当前会话直接修改，不重新派发外部 builder，也不让外部执行器重新读取整套规格和仓库；只有改动已经扩成跨模块架构重构时，才重新展示构建工具确认卡。

构建工具失败时默认保留半成品，先检查已落改动与日志；若要换工具，给出新的推荐并重新展示只含工作环境和构建工具的确认卡，不能静默替换 PM 已确认的工具。只有丢弃会破坏可用改动时才让 PM 授权；禁止自动 `git restore .` / `git clean -fd`。

启动页面时只读取 `.pm-workflow/project.yml:web.start` 并替换 `{port}`，从 `implementation.root` 执行；ready path 和端口候选同样来自 `project.yml`。不得从 builder config 猜 Next.js、`--hostname`、`--port` 或其它框架参数，也不得让命令再次 `--dir / --prefix / --cwd / cd` 到同一个 implementation root。

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

首次实现只完成能支持 PM 查看结果的必要检查，不在这里运行 production build 或完整浏览器验收。启动并持续保留同一个 dev server 与浏览器连接；不得在每轮修改后重建服务、重开浏览器，或让 production build 与 dev server 共用并改写同一个构建缓存目录。

先给 PM 看结果，不把定稿验收挡在“能刷新看到页面/功能”之前。PM 每轮反馈后进入快速迭代车道：

1. 先运行 `active-build-context.py` 重新校验 currentness，再读取当前 build 合同的 `target + delivery_policy`；UI 相关时同时重新读取 `DESIGN.md` 并执行当前声明的项目级设计系统 Skill；校验或 Skill 访问失败时不得修改、提交或写 accepted delta；
2. 先按决定层级分流 PM 新反馈，不能只因反馈发生在 build 中就记成 delta：
   - 改变产品定位、目标用户、核心问题与价值、产品职责边界、MVP 证明目标或关键成立前提 → 停止 build，转 `/pmai-proposal`；不得写 accepted delta；
   - 改变模块对象、关系、动作、状态、权限、真相源、业务规则、信息结构、任务路径、关键交互，或要求原型接入真实数据库、鉴权、外部写入、生产基础设施 → 停止 build，转 `/pmai-design`；不得写 accepted delta；
   - 不改变产品基线和模块模型，只在已批准模块、任务与目标路径内形成 PM 明确接受的小范围行为或体验调整 → 可以记录 `kind=scoped-adjustment` 的 accepted delta；这里的“小范围”明确表示不改变对象、关系、业务规则、权限模型或关键任务路径；
   - 只是让实现重新符合当前 spec / active decisions，或修复 bug、样式、文案和局部交互偏差 → 直接修正实现，不写 delta；
   这四类依次映射为共享 Loop Contract 的 `route_proposal / route_design / retry_current(scoped adjustment) / retry_current(implementation correction)`；同一反馈同时命中多层时按共享路由优先级处理，不能选择更低层的方便路径；
3. 原型真实边缘能力由 design 明确批准，或由 design 把项目建造对象改为 product；不得在迭代中静默升级；
4. “还有什么问题”的检查只对账当前 spec、active decisions、accepted deltas 和批准路径，并应用当前实现深度合同；原型默认模拟的底层能力不算缺口，规格已经明确的行为也不得重新包装成 PM 开放问题；
5. 文案、布局、按钮和局部交互由当前会话直接修改；只有跨模块大型重构才重新确认并调用外部 builder；
6. 只跑 profile 的 `iteration_checks`：热更新、typecheck 和当前页面/受影响交互走查；不得运行 production build、全路径浏览器验收或重启仍健康的 dev server；
7. 提交该轮修改并用 `build-contract.py commit` 记录新实现 commit；`commit` 会再次校验 currentness，过期时失败关闭，不得绕过；
8. 用 `record-evidence --lane iteration` 绑定该 commit 记录快检，不得把 iteration evidence 冒充 final evidence；
9. 立即告诉 PM“已修改，可刷新查看”，继续复用同一个页面与浏览器连接；定稿请求前不准备 `review-ready`，也不在后台偷跑完整 `final_checks`。

每轮同时把阶段耗时写入合同固定的本轮验收目录。阶段至少覆盖 `prepare / implement / fast-check / preview`；反馈收到到 preview ready 的 time-to-preview 按改动标记为 `minor` 或 `interaction`：

```bash
TIMING_FILE="$BUILD_DIR/$AUDIT_DIR_REL/timing.json"
TIMING_JSON=$(python3 "$PMAI_HOME/scripts/build-timing.py" start \
  --audit-file "$TIMING_FILE" --phase preview --kind "<minor|interaction>" \
  --feedback-at "<收到本轮反馈的 ISO 时间>")
TIMING_ID=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])' <<<"$TIMING_JSON")

# 快改完成、PM 已可刷新时；超过目标只会 warning，不阻断回执
python3 "$PMAI_HOME/scripts/build-timing.py" finish \
  --audit-file "$TIMING_FILE" --id "$TIMING_ID" --preview-ready
```

`minor` 的 2–5 分钟、`interaction` 的 5–10 分钟是目标与超时预警，不是质量硬门。预警出现时先让 PM 刷新查看，再定位慢在准备、实现、快检还是 preview；不能为了补齐完整验收继续阻塞 PM。

只有反馈已经通过上述分流，被确认是“已批准模块内、不改变产品基线与模块模型的小范围行为或体验调整”时，才记录 accepted delta：

```bash
python3 "$PMAI_HOME/scripts/build-contract.py" add-delta \
  "$BUILD_DIR/docs/modules/<模块>" \
  --kind scoped-adjustment \
  --summary "<PM 接受的模块内小范围调整>" \
  --affected-surface "<受影响文档/页面>" \
  --scope-attestation approved-module-task-no-model-change \
  --approval-kind pm-confirmation \
  --approval-reference "<本轮 PM 明确接受该调整的原话或可定位会话证据>"
```

这会递增 `design_revision`、更新 source hash、清空旧证据和已有定稿请求，并回到 `iterating`。CLI 只允许新写入 `kind=scoped-adjustment`，且同时要求固定 scope attestation 和 PM / sealed 评审批次证据；裸调用或旧的宽泛 kind 会失败。对象、关系、权限、真相源、业务规则、关键任务路径等模块模型变化不走这里，必须先回 design；产品级变化必须先回 Proposal。正式文档仍等实现落到 main 后统一更新。

普通 build 反馈在规格尚未改变时使用上面的 PM 证据参数，CLI 会先校验 currentness。若本次调整沿用已经批准的术语或角色名称，可重复传 `--affects "term:<准确名称>"` / `--affects "role:<准确名称>"` 供 landed 后术语对账；这不是新增角色模型的通道。若 delta 来自 `/pmai-lark-review`，严格执行 lifecycle handoff 的同步、pack、checkpoint 顺序，并把审批证据改为 `--approval-kind lark-review-batch --approval-reference "<sealed batch ID>" --approval-artifact "<同批 remote-verification.json>"`；CLI 先核对验证产物、sealed plan、T 与当前 `spec.md` 的内容绑定，再从已验证 pack 写入 authority before/after、当前模块 `spec.md` 的精确 `authority_paths`、文件 SHA-256、Git blob 和当前 HEAD 绑定，禁止手填或扩大文档范围。checkpoint 必须承接上一权威提交并直接接在该 HEAD 后，且其中的 spec blob 与 `.work-meta.json` 必须分别等于绑定版本和当前合同。

实现修正不改变产品决定时，不递增 revision；但实现 commit 变化后，绑定旧 commit 的证据不能复用。

## 6. PM 请求定稿后，统一 runner 只执行缺失项

PM 明确说“定稿 / 可以提交 / 可以合并 / 这版可以了”之前，本节不得执行。收到后不二次询问，也不准备 candidate evidence；完整执行 `skills/build/references/finalization.md`，从 `iterating` 统一调用 `finalize-candidate.py` 绑定当前候选并启动可恢复 runner，不在 Skill 内手工拼接 Git HEAD、合同 commit 和 finalize 命令。

统一入口先按批准目标树、source hash 与 legacy recovery checkpoint 绑定正确候选，再用 `validate-final-currentness` 校验当前 design、accepted delta、批准路径和 project.yml。后续无关 HEAD 不得替换批准目标相同的已记录实现，也不要求人工修改 baseline。完全相同的 test/typecheck/build 命令只执行一次并在 artifact 中列出所覆盖检查；命令不同或无法证明相同就分别执行。所有命令在 detached validation worktree 的 `implementation.root` 下运行，production build 保持硬门。

Web 新 build 用一个 `browser-acceptance` 批次覆盖受影响流程的 smoke、visual 和 behavior；一次 gstack `chain`、一个持续会话，不按三个检查或多个复用页面串行重跑。旧 v1-v4 合同不升级版本：缺失的 `browser-smoke / visual / behavior` 由同一批次按合同实际要求的旧名称确定性派生，绑定同一 batch digest；coverage 仍单独证明，不从浏览器动作猜测。

final-validation 分项执行并保留每项 exit code/log；test/typecheck 失败后仍继续跑 build，production build 失败始终阻断。只有 tests/typecheck 可以由 PM 绑定当前 commit/source/results digest 的 artifact 明确接受为 limited，原始失败不得改写成 pass。runner 返回仍缺语义检查时，由当前主控完成规格覆盖、prototype boundary、迁移或安全判断并记录 evidence；有 checks-spec 和页面抓取时用统一 coverage 参数，机器 P0/P1 必须为零，`must_cover_states` 必须逐 check 确认。随后重跑同一入口。实现缺陷仍回 `iterating` 修复；PM 新反馈执行 `resume-iteration`。final-validation 或 browser 真实失败会在 `timing.json` 标记正常路径退出，不得继续报 10 分钟成功。

这里区分两种 `retry_current`：final checks 自己发现的实现缺口保留原定稿意图，修复后只重跑失效证据；PM 在 final checks 期间提出新的产品或体验反馈时先清除定稿请求，按共享合同重新分类。二者不得混成“都继续收尾”。

### prototype 完整检查

- 原型实现边界：候选 diff 只在批准目标内，且没有未经决定允许的真实系统建设；
- 可启动性和主动 browser smoke；
- 建造依据逐项覆盖；对原型来说，“覆盖”指用户可观察的行为、状态和结果能够交互演示，底层按 `delivery_policy.simulate_by_default` 模拟不算漏实现；
- 关键任务路径、页面、弹窗/抽屉；
- 空态、错误态、长内容、权限差异等相关状态；
- 对照 `DESIGN.md` 的视觉一致性；
- 实际交互行为。

先生成边界检查 artifact。第一次不带确认参数运行，用它列出候选 diff、批准范围外改动和生产建设信号；AI 对照 `delivery_policy` 与 active decisions 完成语义复核后，确认没有越界才重跑并写 `pass`：

```bash
BOUNDARY="$BUILD_DIR/$AUDIT_DIR_REL/prototype-boundary.json"
python3 "$PMAI_HOME/scripts/prototype-boundary.py" \
  "$BUILD_DIR/docs/modules/<模块>" \
  --output "$BOUNDARY"

# 完整查看 candidate diff，确认底层能力均为模拟后才允许追加：
python3 "$PMAI_HOME/scripts/prototype-boundary.py" \
  "$BUILD_DIR/docs/modules/<模块>" \
  --output "$BOUNDARY" \
  --confirm-no-real-system-changes \
  <逐项追加 --simulated-capability "<能力>"> \
  <仅当 active decision 明确批准时追加 --approved-real-edge "<category>=<decision reference>">

python3 "$PMAI_HOME/scripts/build-contract.py" record-evidence \
  "$BUILD_DIR/docs/modules/<模块>" \
  --name prototype-boundary --status pass --artifact "$BOUNDARY"
```

`prototype-boundary` 和新合同的 `browser-acceptance` 都是不可 exception 的硬检查；旧合同的 `browser-smoke` 也继续不接受 exception。artifact 出现批准范围外改动、未经决定允许的 database/auth/external side effect/infrastructure 信号，或 AI 尚未明确完成语义复核时保持 `iterating`；不得把 `blocked / needs-review` 手写成 `pass`。

优先使用已可用的主动 browser 适配器生成证据；工具选择不展示给 PM。

最终视觉验收前重新读取 `DESIGN.md` 并执行当前声明的项目级设计系统 Skill；其专属检查作为附加证据，不能替代 build 合同要求的浏览器验收。若 `DESIGN.md` 的视觉基线段未建，先以现有产品页面和组件为事实基线，并在可用时自动调用 gstack `/design-consultation` 补充检查依据；仍不足时视觉检查只能记为 `limited`，不能输出“视觉一致性通过”。这不是让 PM 选择工具或补工程配置的菜单。

### product 完整检查

- 规格范围覆盖；
- 仓库已有测试、typecheck、build；
- 接口与数据行为；
- 迁移、回滚、兼容读取（涉及时）；
- UI 浏览器检查（涉及时）；
- 权限、安全、越权和破坏性数据检查（涉及时）。

非浏览器检查受限时如实写 `limited / skipped / blocked`，只有合同允许的具名检查才可记录 exception；`browser-acceptance` 必须是 active pass，旧合同的 `browser-smoke` 和行为 `fail` 也不能例外放行。

完整检查失败时保持 `iterating`。若只是验收发现实现缺口，用当前会话修复并记录新 implementation commit；v4+ 会保留原定稿意图并把 `requested_commit` 自动重绑到修复提交，无需让 PM 再说一次“定稿”，但所有 final evidence 必须重跑。若 PM 在这期间又提出新的产品/体验反馈，则先运行 `resume-iteration` 清掉定稿请求，回到快速迭代车道；不得带着失败进入 close。

完整检查通过后重跑统一 runner；它自动形成 review-ready、记录 accept 并继续 landing。实现 commit、accepted delta 或任一 final evidence 变化都会使快照失效；runner 只补失效项，不在 build 阶段生成 doc impact 草案。

## 7. 验收就绪后自动进入 final_check

下列表达在 PM 已看到当前结果的语境中，视为对提交并合入 main 的明确授权：

- “可以提交”
- “定稿”
- “可以合并”
- “这版可以了”
- “提交吧 / 合进去吧”

该表达本身就是 one-way door 授权：直接按 §6 调统一 runner，不再二次问“是否收尾”，也不要求 PM 手动发 `/pmai-build-close`。runner 才负责 `request-finalization → review-ready → accept → validate-land` 的状态推进，Skill 不再手工拼这四步。

若快照缺失、过期或发现实现缺口，立即回 `iterating`；验收缺口保留定稿意图并在修复提交上重跑 final checks，PM 新反馈则用 `resume-iteration` 取消定稿请求。不 merge、不清理，也不在 close 内修代码。

## 8. 自动落地主线

统一 runner 在 final_check 自动调用 `close-work.sh`；中断后以同一命令续跑。

- 独立环境发生 merge 冲突：停止在可恢复的 `final_check`，保留分支和 worktree；
- 不清理或回退用户无关脏改动；
- 隔离环境仍被开发服务或缓存占用时，把 worktree/branch 记入安全待清理队列，继续文档同步，不让纯清理失败阻塞已经完成的落地；
- 实现落主线后进入 `landed + docs_pending`；
- `/pmai-build-close` 只作为兼容或恢复入口，正常链路无需 PM 再调用。

## 9. 基于 main 对账规格目标与产品现状

实现 landed 后，`land-work.sh` 才按准确 implementation diff 生成最小 doc impact map；每次恢复先 `ensure-current` 校验 work/module、implementation/landed commit、base/head、source hash、accepted deltas 与 candidate tree/binding digest，旧 schema 或任一绑定漂移就重建，不能因旧文件存在而复用。随后在 main 上完成：

1. 重新生成 context pack；
2. 读取 landed diff、build contract、accepted deltas 和 doc impact map；
3. 调用 spec-writing 的“落地主线后的目标对账”模式，按符合 / accepted delta / 漏实现 / 无依据实现分类；
4. 只更新地图中的 pending 文档；已在 landed diff 修改的真相源由脚本自动 covered；
5. 未受影响文件不进入地图，不打开、不写 no-change；
6. 对 pending 项执行 `doc-impact.py cover`；
7. `doc-impact.py validate` 通过后执行 `build-contract.py docs-complete`；
8. 再次调用统一 runner，单独提交文档同步、删除临时 `.work-meta.json` 并进入 `complete`。

`spec.md` / PRD 保留最终目标，只有 accepted delta 可以修改；`PRODUCT-STATE.md` 等现状文档只描述 main 已经存在的事实。`target.kind=prototype` 落地后只能记为“原型演示”，模拟的数据库、权限、集成或引擎不得写成“已落地产品能力”。不得在 merge 前把目标要求提前写成“已完成”。

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
已修改，可刷新查看。你直接说哪里还要改；我会继续改并只复查受影响部分。你明确说定稿后，我再对冻结版本统一跑一次完整验收。
```

完成后：

```text
✅ <模块> 已定稿：最终检查通过，改动已进入主线，正式文档也按主线事实更新完成。

▶ Next Up：继续 /pmai-design <下一个模块>，或 /pmai-status 看当前产品现状。
```

## Rules

- prototype / product 共用同一生命周期，只切换目标和验收适配器。
- 规格定义最终产品语义，`delivery_policy` 定义本轮实现深度；prototype 的完整度看用户可观察行为，不看底层是否生产化。
- 每次首次构建、反馈迭代和中断恢复都重新读取并优先传递 `target + delivery_policy`，不得依赖模型记住首轮原型边界。
- prototype 默认模拟底层能力；真实数据库、鉴权、外部副作用或生产基础设施必须有 active decision 明确批准，否则回 design，不得静默升级成 product。
- 项目类型、技术栈、入口和真实运行命令由 `.pm-workflow/project.yml` 定义；build 只读，不按本轮需求猜，也不在开工确认卡重复展示。
- build 开工前必须确认 design 依据仍有效，并严格复用 design 批准的目标路径；依据过期、范围缺失或目标路径有未提交改动时先停止处理，不创建工作环境。
- 验收方案按项目类型和风险后台生成默认值；不让 PM 选择，也不在开工确认卡展示。
- 新 build 开工前，AI 推荐工作环境和构建工具，PM 只确认这两项；调整后必须重显同一张确认卡。
- PM 不需要理解 worktree、合同、hash、证据 JSON 或手动 close；构建工具只以名称、模型和思考档展示。
- v5 验收档案分 `iteration_checks / final_checks`：迭代修改只跑快检并尽快给 PM 看；PM 请求定稿前不得写 final evidence 或形成验收就绪快照。
- active build 内的文案、布局、按钮和局部交互由当前会话直接处理；外部 builder 只用于首次实现或大型重构。
- dev server 与浏览器连接跨轮保留；production build 只在冻结 commit 的 validation worktree 运行，不污染 active worktree 的构建缓存。
- `timing.json` 记录阶段耗时与 time-to-preview；2–5 / 5–10 分钟只作预警，不阻断“已修改，可刷新查看”。
- 只有已批准模块内、不改变产品基线与模块模型的小范围调整进入 accepted deltas 并使旧证据失效；产品级变化回 Proposal，模块模型变化回 design；实现 commit 变化也使旧证据失效。
- PM 明确说“可以提交 / 定稿 / 可以合并”就是打开一次性 final checks 并落地主线的授权，不二次确认。
- final_check 只校验同一 source hash + implementation commit 的验收就绪快照，不首次跑完整验收、不修改业务代码；失败回 iterating。
- merge 冲突保留 final_check 和 worktree；纯清理失败进入待清理队列，不阻塞 landed 后文档同步。
- 实现先落 main，正式文档后更新；文档失败不重复 merge。
- skipped / limited / blocked 不能伪装 pass；证据必须绑定 source hash 和 implementation commit。
- UI final checks 缺主动浏览器能力时必须阻塞；`browser-smoke` 不接受 exception。
- v3+ prototype 的 `prototype-boundary` 必须有绑定当前 source hash 和 implementation commit 的 active pass artifact，不接受 exception。
- 正式文档无迭代流水账，历史只在 Git 与 decisions 中。
