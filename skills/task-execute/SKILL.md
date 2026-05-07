---
name: task-execute
description: |
  在 task worktree 中实现代码、启动 dev server、写执行日志、填文档偏差、自审并记录。
---

# /task-execute

## When To Use

- PM 在新 Claude 会话中调用；也可由执行器 adapter 进入同一流程
- 启动 Claude 的方式（关键，否则下面的「自动 cd 到 task worktree」失效）：
  - 推荐：在 req worktree 目录用 `claude --add-dir <主仓根绝对路径>` 启动。launch dir = req worktree（PM 心智自然），`--add-dir` 把主仓根加进 Bash 沙盒，task worktree（位于 `.worktrees/` 下）也在沙盒内，cd 能持久化
  - 备选：在主仓根用 `claude` 启动。task worktree 是 launch dir 子目录，天然在沙盒内
  - **禁止**：在 req worktree 用裸 `claude`（不加 --add-dir）启动。task worktree 不在 launch dir 子树，cd 会被 Claude Code 沙盒 reset，整个流程失败

## 拆两文件约定（必读）

本 skill 处理拆两文件的 task 产物（PM-VIEW-RULES §二）：
- **PM 视图主文件**（`.md`）：📌 任务卡 / 🎯 关键产品决策 / 📐 产物预览 / 📋 功能清单 / 🚦 跨功能产品规则 / 📦 范围 / ✅ 验收清单 / 📁 历史档案（执行日志、PM 反馈）
- **工程合同**（`.engineering.md`）：§1 元信息扩展（executor / model）/ §2 状态转换说明 / §3 启动前必读（agent 必读文件清单）/ §4 功能清单工程版 / §5 实现指引 / §6 易错点 / §7 plan-review 沉淀 / §8 视觉细则 / §9 工程层验收清单 / §10 文档偏差 / §11 自审记录

execute 阶段 agent 启动时**必须把工程合同内容显式 inject 到执行 prompt**。不依赖 markdown 折叠语义、不依赖 PM 主动打开。

具体读写分工：
| 内容 | 读 / 写位置 |
|---|---|
| 任务描述 / 验收清单 / 用户场景 / 功能行为 | 读 PM 视图主文件 |
| 启动前必读清单 | 读工程合同 §3 |
| 实现指引 / 易错点 / V1-V26 review 沉淀 | 读工程合同 §5/§6/§7 |
| 视觉规范细则（像素 / 颜色） | 读工程合同 §8 |
| 工程层验收清单（grep / 单测） | 读工程合同 §9 |
| 写执行日志 | 写入 PM 视图主文件「📁 历史档案 → 执行日志」 |
| 写文档偏差（工程层） | 写入工程合同 §10 |
| 写自审记录 | 写入工程合同 §11 |
| 写 PM 反馈（task-submit 打回时）| 写入 PM 视图主文件「📁 历史档案 → PM 反馈」 |

## Workflow

### 入口前置（v4 修订）

#### 入口步骤 1：定位 task 文件

支持三种参数模式：

1. **完整路径**：参数是可读的 `*.md` 文件时，直接作为 `TASK_FILE`。
2. **短 ID**：参数匹配 `^task-[0-9]{3}$` 时，在所有 active req 下模糊匹配（含主仓 + 所有 `.worktrees/req-*/requirements/active`）：
   ```bash
   MATCHES=$(find requirements/active "$MAIN_REPO_ROOT"/.worktrees/req-*/requirements/active -name "${ARG}-*.md" -type f 2>/dev/null | sort -u)
   ```
   - 唯一匹配：使用该文件。
   - 0 个或多个匹配：报错退出，并提示 PM 传完整 task 文件路径（多 active req 并行时短 ID 可能在多个 req 里冲突）。
3. **无参数**：自动扫描主仓和 `.worktrees/req-*/requirements/active`，找出所有同时满足下列条件的 task：
   - 状态为「待确认」。
   - 对应 `.worktrees/<task-stem>` 已存在。

无参数模式：

- 唯一匹配：自动选定。
- 0 个匹配：报错，提示 PM 先在主窗口运行 `/task-confirm <task-file>`。
- 多个匹配：报错，列出候选短 ID，提示 PM 改跑 `/task-execute task-NNN`。

定位成功后第一时间输出进度反馈：

```bash
echo "🎯 自动选定: $TASK_FILE"
```

#### 入口步骤 2：自动 cd 到 task worktree（含沙盒边界自检）

从 task 文件 stem 推导 task worktree：

```bash
TASK_STEM=$(basename "$TASK_FILE" .md)
TASK_WORKTREE="$MAIN_REPO_ROOT/.worktrees/$TASK_STEM"
```

如 worktree 不存在，报错退出并提示 PM 回主窗口重跑 `/task-confirm $TASK_FILE`。

执行 cd 并立刻验证生效（避免 Claude Code 沙盒静默 reset 后续命令落到错误目录）。

**关键：必须分两次 Bash 工具调用做这件事，单次合并会失效。**

理由：单次 Bash 调用里 `cd` 在调用内永远生效（用 `pwd` 立刻看是切到的目标），Claude Code 的沙盒 reset 发生在**调用结束后**——所以单次 `cd && pwd && check` 永远 pass。要捕获 reset，必须独立第二次调用，让 reset 有机会落到 cwd 上再 pwd。

第 1 次调用（cd）：

```bash
cd "$TASK_WORKTREE"
```

观察这次调用的输出：如果出现 `Shell cwd was reset to <launch-dir>`，立即按下面 hard fail 路径报错。

第 2 次调用（独立验证）：

```bash
EXPECTED_CANONICAL=$(cd "$TASK_WORKTREE" 2>/dev/null && pwd -P)
ACTUAL=$(pwd -P)
if [ "$ACTUAL" != "$EXPECTED_CANONICAL" ]; then
  echo "❌ task-execute 启动失败：cd 后 cwd 是 $ACTUAL，期望 $EXPECTED_CANONICAL" >&2
  echo "" >&2
  echo "原因：当前 Claude 会话的 launch dir 不在主仓子树内，且启动时未带 --add-dir，cd 被沙盒 reset。" >&2
  echo "" >&2
  echo "修复：关闭本会话，在新终端窗口（保持在当前 req worktree 目录）用以下命令重启 Claude：" >&2
  echo "  claude --add-dir \"$MAIN_REPO_ROOT\"" >&2
  echo "" >&2
  echo "进新会话后再跑 /task-execute $(basename "$TASK_FILE" .md)。" >&2
  exit 1
fi
```

注意：`pwd -P` 解析 macOS 上 `/tmp` ↔ `/private/tmp` 这类符号链接，避免 canonical 路径不一致导致误判。`EXPECTED_CANONICAL` 在子 shell 里算（子 shell 不受沙盒 reset 影响），代表 task worktree 的真实绝对路径。

#### 入口步骤 2.4：检测 req 文档 drift + PM 决定是否拉取（4.5f 改造）

`scripts/check-req-doc-drift.sh` 列出 task worktree 与 req 分支之间「项目级 DESIGN.md / CLAUDE.md + requirements/active/<req-id>/」范围内 hash 不一致的文件。**纯只读** —— 不写 worktree 任何文件、不写 `.git/index.lock`。task own 的两文件（PM 视图 + 工程合同）不在 drift 范围（task 自决）。

> 4.5f 取代 sync-req-docs.sh 静默批量覆盖：旧机制会偷偷盖掉 worktree 上 task agent 已经做的合法本地改动；新机制让 PM 看 diff 后逐文件决定。fresh fork 通常无 drift，PM 体验是 1 行「✓」直接通过。

```bash
REQ_BRANCH=$(git -C "$MAIN_REPO_ROOT" branch --contains HEAD --format='%(refname:short)' | grep '^req-' | head -1)
DRIFT_JSON=$(bash "$MAIN_REPO_ROOT/scripts/check-req-doc-drift.sh" \
  "$TASK_WORKTREE" "$REQ_BRANCH" "$TASK_FILE")
DRIFT_COUNT=$(echo "$DRIFT_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["drift_count"])')
```

**drift_count = 0**：直接通过，进步骤 2.5（无需打扰 PM）。

**drift_count > 0**：把候选清单呈交 PM，按下面交互处理：

```
⚠ ${REQ_BRANCH} 上有 N 个文件比 task worktree 新：
  - <path 1>
  - <path 2>
  ...

是否拉过来？[Y 逐文件看 diff / N 全部跳过 / A 全部采用 req 版本]
```

PM 选项处理：

| 选 | 行为 |
|---|---|
| `N` | 不动 worktree，task-execute 继续。task 内执行基于当前 worktree 文件。 |
| `A` | 对清单内每个 file 调 `apply-req-doc.sh`，跳过 diff 询问，全部覆盖。 |
| `Y` | 逐文件循环：先 `git diff --no-index <worktree path> <(git show <branch>:<path>)` 给 PM 看，再问 `[A 采用 req 版本 / B 保留 worktree 版本 / C 跳过这个文件]`。 |

逐文件 `Y` 流程伪码：

```bash
echo "$DRIFT_JSON" | python3 -c 'import json,sys;[print(f["path"]) for f in json.load(sys.stdin)["files"]]' | \
while IFS= read -r path; do
  # 让 PM 看 diff（worktree 现状 vs req 分支版本）
  git -C "$TASK_WORKTREE" diff --no-index --color=always \
    "$path" <(git -C "$TASK_WORKTREE" show "${REQ_BRANCH}:${path}") || true

  # 问 PM 三选项 [A / B / C]
  # A → bash $MAIN_REPO_ROOT/scripts/apply-req-doc.sh "$TASK_WORKTREE" "$REQ_BRANCH" "$path" "$TASK_FILE"
  # B → 不动
  # C → 不动，下一文件
done
```

**失败容忍**：drift 检测脚本异常 → 不阻断启动，task-execute 继续（同 sync-req-docs 历史 best-effort 行为）。check-task-scope.py 的 implicit deny 仍然兜底拦截 task 误 commit 项目级 / 兄弟 task 文件。

#### 入口步骤 2.5：依赖前置 gate（v4 兜底层）

这是防止 PM 手动用 `task-transition.py` 强改状态、绕过 `/task-confirm` 的兜底层。逻辑必须与 `/task-confirm` 的「步骤 4-pre：依赖前置检查」一致：

1. 解析 `## 依赖` section，只提取 `task-NNN` 模式。
2. 在同 req 下查找每个依赖 task。
3. 读取依赖 task 状态。
4. 任一依赖状态不是「已完成」时：
   - `exit 1`
   - 直接报错给 PM：
     ```text
     ❌ task-NNN 依赖未完成：task-MMM 当前状态为「<status>」。
     请先 close 依赖 task，再重新运行 /task-confirm <task-file>。
     ```
   - 不进入执行，不修改当前 task 状态。
5. 全部依赖均为「已完成」时，通过 gate。

依赖解析规则：

```bash
DEPENDENCIES=$(awk '
  /^## 依赖/{flag=1; next}
  /^## / && flag{flag=0}
  flag{print}
' "$TASK_FILE" | grep -Eo 'task-[0-9]{3}' | sort -u)
```

#### 入口步骤 3：检查状态 + transition

读取当前 task 状态：

```bash
CURRENT_STATUS=$(python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" --get-status 2>/dev/null || echo "")
```

状态处理：

- 「待确认」：转换为「执行中」后继续。
  ```bash
  # D7 后无 serial 阻塞；并行约束由依赖 gate 和 worktree 隔离承担。
  python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" --to 执行中
  ```
- 「执行中」：允许重试或打回后续跑，不重复 transition。
- 「已完成」：错误退出，提示 `该 task 已完成；如需收尾，请在本窗口运行 /close-task`。
- 「待验收」：错误退出，提示 `该 task 已待验收；请在本窗口验收并运行 /task-submit 或 /close-task`。
- 其他状态：错误退出，展示当前状态，并提示 PM 回主窗口用 `/task-status` 查看。

### 步骤 1：读取 task 两文件（成对校验）

1. 校验工程合同成对存在（兼容旧格式 task）：
   ```bash
   ENG_FILE="${TASK_FILE%.md}.engineering.md"
   if [ ! -f "$ENG_FILE" ]; then
     echo "⚠️  工程合同缺失（旧格式 task，按单文件兼容模式继续）：$ENG_FILE" >&2
     HAS_ENG=false
   else
     HAS_ENG=true
   fi
   ```
   - `HAS_ENG=true`：按下文 §2 / §3 分别从两文件读取
   - `HAS_ENG=false`：兼容模式——所有内容从主文件 (`$TASK_FILE`) 读取（旧模板的「启动前必读」/「实现指引」/「易错点」等都在主文件中）

2. 从 **PM 视图主文件**（`$TASK_FILE`）提取（业务行为层）：
   - 「📌 任务卡」→ 任务描述
   - 「🎯 关键产品决策」→ PM 已拍板的产品选择
   - 「📋 功能清单」→ 功能行为、数据规则、角色权限（**硬约束**）
   - 「🚦 跨功能产品规则」→ admin 视角的统一规则
   - 「📦 范围」→ 改 / 不改
   - 「✅ 验收清单」→ PM 走查主路径

3. 从 **工程合同**（`$ENG_FILE`，仅当 `HAS_ENG=true`）提取（实现细节层）：
   - 「§1 元信息扩展」→ executor / model / 推荐 review 工具
   - 「§3 启动前必读」→ 必读文件路径列表（步骤 2 用）
   - 「§4 功能清单工程版」→ 实现层细节（字段名 / props / reducer action）
   - 「§5 实现指引」→ 组件复用 / 关键算法 / vitest stub 限制 / dev console 信号规范
   - 「§6 易错点 / 禁止项」→ 反向约束清单
   - 「§7 plan-review 沉淀」→ V1-V26 决策（如有）
   - 「§8 视觉规范细则」→ 像素值 / 颜色码 / a11y 要求
   - 「§9 工程层验收清单」→ grep / 单测 / 引用稳定性等自审条目

   **兼容模式**（`HAS_ENG=false`）：跳过本步，从主文件读「启动前必读」/「实现指引」/「易错点」等旧 section（旧模板这些 section 都在主文件中）。

### 步骤 2：读取必读文档

#### 2.0 项目级 DESIGN.md 强制 echo（不依赖 §3 列表 / 不依赖 LLM 选择性 Read）

UI task 漏读 / 浅读 DESIGN.md 是 task-001 反复迭代踩坑的根因（Read tool 触发与否取决于 LLM 自觉，489 行内容进 context 后细节又会被冲淡）。本子步骤用 Bash `cat` 把 DESIGN.md 全文无条件 echo 到 transcript，**保证内容进入 working context**——比依赖 Read tool 自觉触发硬。冗余于 §3 启动前必读列表也无害。

```bash
DESIGN_MD="$TASK_WORKTREE/docs/DESIGN.md"
if [ -f "$DESIGN_MD" ]; then
  echo "════════════════════════════════════════════════════════════════"
  echo "项目级设计系统（docs/DESIGN.md）— task-execute 步骤 2.0 强制 echo"
  echo "（视觉规范单一来源；UI / 视觉类 task 必须遵循；非 UI task 可作为辅助参考）"
  echo "════════════════════════════════════════════════════════════════"
  cat "$DESIGN_MD"
  echo "════════════════════════════════════════════════════════════════"
  echo "END docs/DESIGN.md"
  echo "════════════════════════════════════════════════════════════════"
else
  echo "ℹ️  $TASK_WORKTREE/docs/DESIGN.md 不存在（项目尚未建立 DESIGN.md），跳过 echo"
  echo "    建议 PM 后续建立 DESIGN.md 作为项目级视觉规范单一来源（gstack /design-consultation 可生成）"
fi
```

不做 echo 后语义校验（grep token 命中 / 自检清单）——那是 task-execute 步骤 5 的事。本子步骤只保证内容到位。

#### 2.1 按 §3 启动前必读列表读其他文档

按工程合同「§3 启动前必读」列表，逐个读取文档内容。理解：
- 模块规格中的**功能清单（硬约束）**：功能行为、数据规则、角色权限必须严格遵循
- 模块规格中的**实现指引（软指引）**：推荐组件、DESIGN.md 对齐、交互状态覆盖，可在设计系统框架内自由发挥
- 设计系统规范（DESIGN.md）
- 项目背景（CONTEXT.md）
- 已发布的项目主 PRD（docs/prd.md）
- 参考源码（如列表中有已有页面/组件源码，理解其组件结构和布局模式）
- 同模块已完成 task 的 PM 视图 + 工程合同（**两文件都读**，复用经验、避免重复）

**硬软分离原则：** 功能清单定义"做什么"（不可偏离），实现指引建议"怎么做"（可灵活调整）。在满足功能行为和设计系统约束的前提下，追求最好的视觉效果和交互体验。

**两文件读完后**：agent 内部把 PM 视图（功能行为）+ 工程合同（实现约束）合并理解为完整的执行指令，开始步骤 3 实现。

### 步骤 3：实现代码（含 dispatch）

**步骤 3 的流程：状态 gate → dispatch → 越界保护 → 零改动检查。** 失败路径统一走 `--fail-execution` 回退 + 诊断文案。

#### 3.0 前置状态 gate（由入口前置完成）

入口前置已经完成「待确认 → 执行中」transition，或确认当前状态为「执行中」重试。进入实现阶段前仍保留轻量断言：状态必须是「执行中」。如果不是，说明入口前置没有成功完成，立即拒绝继续。

```bash
CURRENT_STATUS=$(python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" --get-status 2>/dev/null || echo "")
if [ "$CURRENT_STATUS" != "执行中" ]; then
  echo "❌ /task-execute 入口拒绝：task 状态为「${CURRENT_STATUS:-未知}」，不是「执行中」。" >&2
  echo "" >&2
  echo "请回到入口前置步骤处理状态，或在主窗口运行 /task-status 查看下一步。" >&2
  exit 1
fi
```

#### 3a. Lock + manual 幂等重入

```bash
TASK_ID=$(basename "$TASK_FILE" .md | sed -E 's/^(task-[0-9]+).*/\1/')
LOCK_DIR="$MAIN_REPO_ROOT/.runs/.lock-${TASK_ID}"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "❌ 另一个 /task-execute 正在运行 Task-${TASK_ID}。如确定没有，手动删除 $LOCK_DIR 后重试。" >&2
  exit 1
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

PENDING_FILE="$MAIN_REPO_ROOT/.runs/.pending-manual-${TASK_ID}.json"

if [ -f "$PENDING_FILE" ]; then
  BASELINE_SHA=$(jq -r .baseline_sha "$PENDING_FILE")
  STARTED_AT=$(jq -r .started_at "$PENDING_FILE")

  echo "✓ 检测到 Task-${TASK_ID} 的 manual 续跑标记（since $STARTED_AT）。"
  echo "  将保留 $TASK_WORKTREE 的现有改动，不会重新调用任何执行器。"
  echo "  先跑 preflight，通过后直接进入自审阶段（step 4）。"
  echo ""

  # Preflight：scope 越界校验由 _gate.sh adapter_postcheck 在 dispatch 路径承担；
  # manual resume 路径不经 adapter，scope 校验降级为「PM 自负责」+ 下面的执行日志检查兜底。

  # 检查执行日志和文档偏差 section 已填
  if ! grep -q '^### 执行报告' "$TASK_FILE"; then
    echo "⚠️ 请先在 task 文件「执行日志」section 记录你做了什么（见模板 ### 执行报告 格式），再重跑 /task-execute。"
    echo "  pending 标记保留。"
    exit 1
  fi

  # 通过 → 删标记，追加事件，进 step 4
  rm -f "$PENDING_FILE"
  python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
    --type execution_manual_completed
  # 跳到 step 4（不 exec adapter，不记 execution_started）
  MANUAL_RESUME=1
fi
```

若 `MANUAL_RESUME=1`，跳过 3b/3c/3d 直接进 step 4。

#### 3b. 正常 dispatch

```bash
if [ -z "${MANUAL_RESUME:-}" ]; then
  # I-AD5: Pre-dispatch checkpoint gate — task worktree 必须 clean
  # Why: codex / cursor-agent 的 stop 是软停，已派发的 sandbox shell 子进程会延迟落盘
  #      可能覆盖手改但没 commit 的文件；失败回滚基线是 HEAD，未 commit 改动会被 restore 清掉。
  # 故意不走 adapter 失败路径（不 rollback、不 --fail-execution），处理权交还 PM。
  DIRTY=$(git -C "$TASK_WORKTREE" status --porcelain 2>/dev/null)
  if [ -n "$DIRTY" ]; then
    echo "" >&2
    echo "❌ /task-execute 拒绝 dispatch：task worktree 有未 commit 改动（I-AD5）。" >&2
    echo "" >&2
    echo "原因：codex / cursor-agent 的 stop 是软停，已派发的 sandbox shell 子进程会延迟落盘，" >&2
    echo "可能覆盖你刚手改但没 commit 的文件。失败回滚基线是 HEAD，未 commit 的手改会被 restore 清掉。" >&2
    echo "" >&2
    echo "task worktree: $TASK_WORKTREE" >&2
    echo "现状：" >&2
    git -C "$TASK_WORKTREE" status --short >&2
    echo "" >&2
    echo "处理（任选一种后重跑 /task-execute）：" >&2
    echo "  保留改动：cd \"$TASK_WORKTREE\" && git add -A && git commit -m 'pre-execute checkpoint: <一句话>'" >&2
    echo "  丢弃改动：cd \"$TASK_WORKTREE\" && git restore . && git clean -fd" >&2
    echo "" >&2
    echo "注意：本次 task 状态保留为「执行中」，不回退、不 rollback worktree。" >&2
    exit 1
  fi

  # Resolve executor + model
  RESOLVED=$(python3 "$MAIN_REPO_ROOT/.claude/scripts/resolve-executor.py" "$TASK_FILE")
  EXECUTOR=$(echo "$RESOLVED" | jq -r .executor)
  EXECUTOR_MODEL=$(echo "$RESOLVED" | jq -r '.model // ""')

  # Build prompt
  PROMPT_FILE=$(mktemp)
  python3 "$MAIN_REPO_ROOT/.claude/scripts/build-execution-prompt.py" "$TASK_FILE" > "$PROMPT_FILE"

  # Baseline SHA（I-AD5 保证此时 working tree == HEAD）
  BASELINE_SHA=$(git -C "$TASK_WORKTREE" rev-parse HEAD)

  # Event
  python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
    --type execution_started \
    --payload "{\"executor\":\"$EXECUTOR\",\"model\":\"$EXECUTOR_MODEL\",\"baseline_sha\":\"$BASELINE_SHA\"}"

  LOG_PATH="$MAIN_REPO_ROOT/.runs/execution-${TASK_ID}-${EXECUTOR}.log"
  mkdir -p "$MAIN_REPO_ROOT/.runs"

  # Dispatch
  if [ "$EXECUTOR" = "claude-code" ]; then
    # 走下面「claude-code 执行者的主流程」——当前 Claude 实例自己实现
    # Prompt 已写到 $PROMPT_FILE，Claude 应读它理解执行边界
    echo "✓ executor=claude-code，当前 Claude 实例继续执行。Prompt: $PROMPT_FILE"
  elif [ "$EXECUTOR" = "manual" ]; then
    MAIN_REPO_ROOT="$MAIN_REPO_ROOT" \
    TASK_FILE="$TASK_FILE" \
    TASK_WORKTREE="$TASK_WORKTREE" \
    PROMPT_FILE="$PROMPT_FILE" \
    EXECUTOR_MODEL="$EXECUTOR_MODEL" \
      bash "$MAIN_REPO_ROOT/.claude/scripts/exec-adapters/manual.sh"
    exit 0  # manual 已写 pending，skill 结束
  else
    # codex / cursor-agent
    ADAPTER="$MAIN_REPO_ROOT/.claude/scripts/exec-adapters/${EXECUTOR}.sh"
    if [ ! -x "$ADAPTER" ]; then
      echo "❌ 找不到 adapter: $ADAPTER" >&2
      python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" \
        --fail-execution --reason "adapter_missing"
      exit 1
    fi
    MAIN_REPO_ROOT="$MAIN_REPO_ROOT" \
    TASK_FILE="$TASK_FILE" \
    TASK_WORKTREE="$TASK_WORKTREE" \
    PROMPT_FILE="$PROMPT_FILE" \
    EXECUTOR_MODEL="$EXECUTOR_MODEL" \
      bash "$ADAPTER" > "$LOG_PATH" 2>&1
    EXIT_CODE=$?
    # 超 10 分钟会被 Bash tool timeout。如果遇上，改用：
    #   bash .claude/scripts/run-bg.sh "$LOG_PATH" bash "$ADAPTER"
    # 然后 Claude 用 **Bash run_in_background**（不是 Monitor —— Monitor 默认 5min 超时
    # 会被静默 cut）起一个 waiter，同时兜「正常退」和「卡死」两条信号：
    #   until [ -f "$LOG_PATH.exit" ] || [ -f "$LOG_PATH.stall" ]; do sleep 60; done
    #   if [ -f "$LOG_PATH.stall" ]; then echo "STALLED at $(cat "$LOG_PATH.stall")"
    #   else echo "exit_code=$(cat "$LOG_PATH.exit")"; fi
    # run-bg.sh 自带 watchdog（默认 180s 无 log 增长 → 写 .stall，不杀子进程）。
    # waiter 输出 STALLED → 进程仍在跑，处理权交 PM（杀 / 等 / 转 manual）。
    # 这是逃生路径，不是默认模式。

    if [ "$EXIT_CODE" -ne 0 ]; then
      CLASSIFICATION=$(bash "$MAIN_REPO_ROOT/.claude/scripts/classify-failure.sh" "$EXIT_CODE" "$LOG_PATH")
      rollback_worktree "$BASELINE_SHA"  # 见 3c 回滚函数
      python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
        --type execution_failed \
        --payload "{\"executor\":\"$EXECUTOR\",\"model\":\"$EXECUTOR_MODEL\",\"exit_code\":$EXIT_CODE,\"classification\":\"$CLASSIFICATION\",\"log_path\":\"$LOG_PATH\"}"
      python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" \
        --fail-execution --reason "$CLASSIFICATION"
      output_diagnostic "$CLASSIFICATION" "$EXECUTOR" "$LOG_PATH" "$TASK_FILE"
      exit 0
    fi
  fi
fi
```

#### 3c. 越界写保护 + 回滚函数

```bash
# 回滚函数（失败路径或越界时调用）
rollback_worktree() {
  local baseline="$1"
  cd "$TASK_WORKTREE"
  # Tracked changes: restore from baseline
  git status --porcelain -z | \
    while IFS= read -r -d '' line; do
      local status="${line:0:2}"
      local path="${line:3}"
      case "$status" in
        "??")  rm -rf "$path" ;;                                   # untracked
        *)     git restore --source="$baseline" --worktree --staged -- "$path" ;;
      esac
    done
}

if [ -z "${MANUAL_RESUME:-}" ]; then
  # 越界检查：收集改动、分类、按 allowlist 过滤
  cd "$TASK_WORKTREE"
  BAD_FILES=""
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    # gitignore matched → skip (生成物)
    if git check-ignore -q "$path" 2>/dev/null; then continue; fi
    # Check against task allowlist (implementation detail: parse-task-scope.py or inline)
    # MVP: allow anything not under docs/ unless explicitly listed in task's 执行范围
    if [[ "$path" == docs/* ]]; then
      # docs/ must be explicitly in task allowlist
      if ! grep -qE "^\s*-\s*(新建|修改)：.*$path" "$TASK_FILE"; then
        BAD_FILES="$BAD_FILES $path"
      fi
    fi
  done < <(git status --porcelain | awk '{print $2}')

  if [ -n "$BAD_FILES" ]; then
    rollback_worktree "$BASELINE_SHA"
    python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
      --type execution_failed \
      --payload "{\"reason\":\"boundary_violation\",\"bad_files\":\"$BAD_FILES\"}"
    python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" \
      --fail-execution --reason "boundary_violation"
    output_diagnostic "boundary_violation" "$EXECUTOR" "$LOG_PATH" "$TASK_FILE"
    exit 0
  fi

  # 3d. 零改动检查
  CHANGE_COUNT=$(git status --porcelain | wc -l | tr -d ' ')
  if [ "$CHANGE_COUNT" -eq 0 ]; then
    python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
      --type execution_failed \
      --payload "{\"reason\":\"no_changes\"}"
    python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" \
      --fail-execution --reason "no_changes"
    output_diagnostic "no_changes" "$EXECUTOR" "$LOG_PATH" "$TASK_FILE"
    exit 0
  fi

  python3 "$MAIN_REPO_ROOT/.claude/scripts/task-events.py" append "$TASK_FILE" \
    --type execution_completed \
    --payload "{\"executor\":\"$EXECUTOR\",\"model\":\"$EXECUTOR_MODEL\"}"
fi
```

#### 3e. 诊断文案函数

```bash
output_diagnostic() {
  local classification="$1" executor="$2" log="$3" task="$4"
  local stage="adapter 启动"
  local suggest=""
  case "$classification" in
    sandbox_denied)
      stage="adapter 启动"
      suggest="检查 ~/.codex/config.toml 的 sandbox_mode（应为 workspace-write），或改用 executor=cursor-agent / manual"
      ;;
    model_not_found)
      stage="执行器启动"
      suggest="检查 task 文件 **executor_model：** 字段，或清空让 settings 默认生效"
      ;;
    network)
      stage="执行中"
      suggest="网络 / rate limit 问题，稍等重试，或换执行者"
      ;;
    boundary_violation)
      stage="执行后越界检查"
      suggest="检查 task 「执行范围」字段，确认允许写入清单是否漏列了合法路径"
      ;;
    no_changes)
      stage="执行完成"
      suggest="执行器退 0 但 worktree 无改动。可能 prompt 被误解为"只分析"——检查 build-execution-prompt 输出"
      ;;
    *)
      suggest="查看日志诊断"
      ;;
  esac

  cat <<EOM

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Task 执行失败，已回退到「待确认」。

执行者：$executor
失败阶段：$stage
分类：$classification
日志：$log

下一步可直接选一项：
1. 同执行者重试（修根因后）：
   $suggest
   /task-confirm $task

2. 改用其它执行者：
   编辑 $task，修改 **executor：** 字段后
   /task-confirm $task

3. 搁置：
   /task-status 查看其它待办
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOM
}
```

---

**claude-code 执行者的主流程**（当 executor=claude-code 走这里，当前 Claude 实例执行）：

**实现前必做（UI 类 task）：**
- 读 `$PROMPT_FILE` 获取完整执行契约（允许/禁止写入、验收标准、写回职责）
- 用 Glob 扫描项目中的页面和组件目录，了解已有哪些组件和页面
- 如果要实现的功能与已有页面类似（如列表页、表单页），先读取该页面源码，复用其布局和组件
- 优先 import 已有组件，不要重写功能相同的组件
- 遵循已有代码的样式模式和目录约定

- 新建文件按执行范围创建
- 修改文件按执行范围修改
- 不动的文件不要碰
- **禁止 git add / git commit**（commit 由 step 10 统一做）

### PM 反馈分流策略（共享权威源）

> 本节是 task-execute 内的"本次打回"分流（行为修订 vs Bug 修复），与 `PM-VIEW-RULES §9.4` 的"历史 PM 反馈三类分流"（正向规则 / 反向约束 / 决策记录）是不同维度：
> - 本节 = 当前 task 被打回时，agent 怎么处理本次反馈
> - PM-VIEW-RULES §9.4 = task-spec 抽取**已完成 task** 的历史 PM 反馈用于新 task 时怎么分类

当 task-submit 打回后重新进入 task-execute，agent MUST：

1. Read the new PM feedback appended to **PM 视图主文件**「📁 历史档案 → PM 反馈」section（不是工程合同；PM 反馈一律写主文件）。
2. Classify feedback as ONE of:
   - **行为修订**（behavior/rule change）: PM wants different functionality, logic, or rules。
   - **Bug 修复**（bug/prototype deviation）: existing functionality is described correctly in PM 视图 / 工程合同 but implementation missed it。
3. Output exactly this one-liner BEFORE doing any work:
   `本次反馈识别为 [行为修订 / Bug 修复]，准备 [改 task PM 视图 / 工程合同 + 重做 / 只改代码]。如判断错误请回复 "wrong"`
4. Wait for PM to either proceed (any input other than `wrong`) or say `wrong`:
   - PM says `wrong`: flip the classification and output the updated one-liner, wait again。
   - PM proceeds: execute the classified path。
5. Paths:
   - **行为修订 path**: 按改动性质决定改哪个文件：
     - 业务功能 / 验收点 / 跨功能规则变化 → 改 PM 视图主文件的「📋 功能清单」/「🚦 跨功能产品规则」/「✅ 验收清单」
     - 实现细节 / 易错点 / 视觉规范变化 → 改工程合同的「§4 功能清单工程版」/「§6 易错点」/「§8 视觉细则」
     - 关键产品决策反转 → 改 PM 视图主文件的「🎯 关键产品决策」（备选方案列标注"已被 PM 反馈推翻"）
     → notify PM what changed → get PM 二次确认 → re-execute based on revised files。
   - **Bug 修复 path**: Fix code only. Do NOT modify either file. Proceed directly to fix。
6. Classification signal guide (non-exhaustive):
   - 行为修订 signals: `should`, `instead`, `add feature`, `change behavior`, `before/after`, `priority order`。
   - Bug 修复 signals: `missing`, `forgot`, `not showing`, `broken`, `step N didn't happen`。

### 步骤 4：启动 dev server（UI 类 task）

如果是 UI 类 task：
1. 启动 dev server，绑定到 task 文件中指定的端口
2. 确保 server 在后台运行，不阻塞后续步骤
3. 验证 server 可访问

非 UI 类 task 跳过此步骤。

### 步骤 5：写执行日志（PM 视图主文件）

**兼容模式（`HAS_ENG=false`，旧格式 task）**：写入主文件 `## 执行日志` section（旧版 section 名）。

**新格式（`HAS_ENG=true`）**：写入 **PM 视图主文件**（`$TASK_FILE`）的「📁 历史档案 → 执行日志」section：

```markdown
#### 执行报告 - [YYYY-MM-DD HH:MM]
**改动摘要：** [简述做了什么]
**新建文件：** [文件列表]
**修改文件：** [文件列表]
**验收标准完成情况：**
- [x] 条件 1 — 已实现
- [x] 条件 2 — 已实现
```

### 步骤 6：写文档偏差

**两层分工**（PM-VIEW-RULES 双文件原则）：

| 偏差类型 | 写入位置 | 处理路径 |
|---|---|---|
| **工程层偏差**（字段命名 / 接口签名 / 组件路径 / 模块依赖与文档不一致） | 工程合同 §10 文档偏差表 | close-task → /doc-update 对账模式 |
| **业务层偏差**（task 实证推翻或修订 req / 项目级文档的产品决策、需求描述、模块功能规格） | PM 视图「📁 历史档案 → 业务层偏差」表 | close-task → /doc-update 对账模式 |

**兼容模式（`HAS_ENG=false`，旧格式 task）**：所有偏差写入主文件 `## 文档偏差` section（旧版）。

**新格式（`HAS_ENG=true`）— 工程合同 §10**：

```markdown
| 文档位置 | 文档原文 | 实际实现 |
|----------|----------|----------|
| docs/modules/auth.md 第 15 行 | 使用 JWT 认证 | 改用 Session 认证（因 XX 原因） |
| solution.engineering.md §3.2 | 用户表 user_id 是 INTEGER | 改 BIGINT（兼容大型租户）|
```

文档位置可以指向 **任何文档**：`docs/modules/<module>.md` / `solution.engineering.md` / `docs/DESIGN.md` / `docs/CONTEXT.md` 等。doc-update 对账模式按行精确读原文 + 生成 Edit 操作 + PM 逐条确认。

**新格式（`HAS_ENG=true`）— PM 视图「📁 历史档案 → 业务层偏差」**：

实证发现 brief / analysis / solution（PM 视图）/ prd / module 规格 内容需修订时填这里：

```markdown
| 文档位置 | 文档原文 | 实证发现 | 建议改法 |
|---|---|---|---|
| solution.md §🎯 决策 #2 | 选用方案 A | 实证 demo 后用户路径走不通 | 改方案 B（理由：...）|
| brief.md「角色定义」段 | 三角色：admin/ops/user | 实证发现还有 readonly 角色 | 加 readonly 角色定义 |
| docs/modules/account.md ### 1.2 使用角色 | "管理员一类角色" | 实证发现要拆"超管"+"普通管" | 拆两类角色描述 |
```

**默认值**：两段都写「无偏差」/「无」（多数 task 没偏差）。

**判断口诀**：
- 改的是「字段名 / 接口 / 组件路径 / 文件结构」→ 工程层 § 10
- 改的是「业务规则 / 产品决策 / 需求描述 / 角色定义」→ 业务层 历史档案

### 步骤 7：输出"推荐 review 工具"区块（不自动调任何 review）

实现完毕、执行日志和文档偏差填好后，AI **不得自动调用任何 review skill**（I-RV1）—— 这是 PM 自跑的工具，AI 替跑容易"假执行"（尤其 `/qa` `/design-review` 依赖 browse 看真实页面，不是文档对照）。

输出推荐区块给 PM：

```
✅ 实现完毕：<改动文件数> 文件，dev server: http://localhost:<port>

可选 review（PM 自行选跑，跑完贴结论我帮你记自审记录 + append 事件）：
  /review              — 代码审查 task 分支 vs req 分支的 diff

  # 以下仅 UI task：
  /qa                  — 功能测试 dev server（需 browse）
  /design-review       — 对照 DESIGN.md 检查视觉一致性（需 browse）

跑哪几个由你决定，全跳也可以。跑完后进步骤 10 commit + 转待验收。
```

UI task 判定参考 task 文件「推荐 review 工具」字段（含 `/qa` 或 `/design-review`）或 task 描述涉及前端/页面/组件。

#### 7.1 PM 跑完 review 后：写自审记录 + append 事件（I-RV2）

PM 在 chat 里报告"跑了 /review，pass，发现 2 个 mechanical issue 已自动修"等结论后，AI：

1. 在 task 文件「自审记录」section 追加一条（保留 PM 原话或转写）：

   ```markdown
   ### 自审 N - [YYYY-MM-DD HH:MM]
   **工具：** /review
   **结果：** pass（2 个 mechanical issue 已修复）
   **详细发现：**
   - F-001: 变量命名不一致 → 已修复
   - F-002: 缺少 null check → 已修复
   **遗留问题：** 无
   ```

2. append `review_completed` 事件作为审计痕迹：

   ```bash
   python3 .claude/scripts/task-events.py append "<task-file>" \
     --type review_completed --tool "/review" --result "<pass|fail>"
   ```

**禁止**（I-RV3）：先 append 后跑、跳过 PM 直接 append、AI 替 PM 跑 review 然后伪造结论。append 必须发生在 PM 明确报告结果之后。

#### 7.2 修复 PM 跑 review 发现的问题（如有）

PM 跑 review 后反馈"还有 X 需要修"：
1. AI 在 task worktree 内修复（不 commit，commit 由步骤 10 统一做）
2. 提示 PM 是否重新跑对应 review → PM 重跑后再 append 一条事件
3. 更新自审记录

#### 7.3 不跑 review 直接进 commit

PM 决定全跳或不再跑 → 直接进步骤 10。事件流缺 `review_completed` 不阻止「执行中→待验收」转换（I-RV2，task-transition 不再 hard gate）。

### 步骤 8：（已合并入步骤 7.1，保留编号便于历史引用）

> 自审记录现在由步骤 7.1 在 PM 跑完 review 后机械填写。如 PM 全跳 review，自审记录至少需要一条 `**结果：** PM 选择不跑 review` 之类的 placeholder（task-transition 仍校验 section 非空）。

### 步骤 9：（已合并入步骤 7.2）

### 步骤 10：Commit + 提交待验收

**PM 跑完想跑的 review（或决定不跑）后，先 commit 再转状态。** Adapter 执行路径和 claude-code inline 路径在此处统一 commit。

```bash
cd "$TASK_WORKTREE"

# 收集改动摘要（从最近一条「执行报告」section 提取）
SUMMARY=$(awk '/^### 执行报告/{flag=1} flag && /^\*\*改动摘要/{sub(/\*\*改动摘要：\*\*\s*/,"");print;exit}' "$TASK_FILE")
[ -z "$SUMMARY" ] && SUMMARY="实现 $(basename "$TASK_FILE" .md)"

git add -A
git commit -m "task-${TASK_ID}: ${SUMMARY}"

# 转待验收
python3 .claude/scripts/task-transition.py "$TASK_FILE" --to 待验收
```

脚本会自动校验：
- 文档偏差 section 已填
- 自审记录 section 有内容（PM 不跑 review 时也需至少一条 placeholder 行）

Review 事件流不再做覆盖校验（I-RV2）。Dev server 保持运行（PM 验收时需要访问）。

**Commit 后不退出 skill** —— 直接进步骤 11 呈交验收（v4 单窗口 lifecycle 自动衔接，2026-05-07 合并 task-submit 步骤 3/3.5/4）。

### 步骤 11：呈交 PM 验收（合并自 task-submit）

> 默认路径：commit + 转「待验收」后**自动**呈交，PM 不需手动敲 `/task-submit`。
> 兜底入口：PM 在异常情况（窗口被关 / context 丢失 / 重启 IDE）下仍可手动跑 `/task-submit`，逻辑等价。

#### 11.1 组装验收信息包

读两文件：
- PM 视图主文件（`.md`）：「📌 任务卡」/「📐 产物预览」/「✅ 验收清单」/「📁 历史档案」最新执行日志 / 业务层偏差表
- 工程合同（`.engineering.md`）：§1 推荐 review 工具 / §9 工程层验收清单 / §10 文档偏差 / §11 自审记录

收集 diff：
```bash
REQ_BRANCH=$(jq -r '.req_branch // empty' .req-meta.json 2>/dev/null \
  || git symbolic-ref --short HEAD | sed -E 's/^task-[0-9]+-/req-/' \
  || echo "main")
git diff --stat "$REQ_BRANCH"..HEAD
```

PM 已跑的 review（事件流）：
```bash
python3 .claude/scripts/task-events.py list "$TASK_FILE" --type review_completed
```
- 有事件 → 列出工具及结论（如 `/review pass, /qa pass`）
- 无事件 → 写"（PM 选择不跑 review）"

判断 task 类型（UI / 非 UI），按 task-submit §步骤 2 同样信号判定（任一命中即 UI）：
- task 描述涉及前端/页面/组件/界面/UI/view/component
- 工程合同 §1「推荐 review 工具」字段含 `/design-review` 或 `/qa`
- PM 视图「📐 产物预览」section 含 ASCII 线框图

#### 11.2 输出验收信息块

**UI 类 task**（含 dev server 走查指引 + 多视角链接，AI 按 task 描述推断具体路径与 query params）：

```
═══════════════════════════════════════
📋 Task 验收：task-NNN-<slug>
═══════════════════════════════════════

🌐 走查链接（dev server 持续在 :<port>，PM 可在浏览器走查任意视角）：
  • <视角 1 描述>: http://localhost:<port>/<path>?<params>
  • <视角 2 描述>: http://localhost:<port>/<path>?<params>
  ...

📝 改动摘要：
[最新执行日志「**改动摘要：**」一行]

📊 Diff 摘要（vs <REQ_BRANCH>）：
[git diff --stat 输出]

🔍 review 已跑：
[/review pass, /qa pass / 或 "PM 选择不跑 review"]

🔍 自审结果：
[工程合同 §11 最新一条要点]

✅ 验收清单（PM 主路径走查）：
- [ ] 条件 1
- [ ] 条件 2
[逐条来自 PM 视图 §✅ 验收清单]

📄 文档偏差：
PM 视图：[历史档案中的偏差或"无"]
工程合同：[§10 内容或"无偏差"]

请走查后回复：通过 / 打回（附反馈）
═══════════════════════════════════════
```

**非 UI 类 task**：去掉「走查链接」段，加「📂 代码变更」段（关键 diff / 测试结果摘要），其余结构同上。

#### 11.3 走查时引导 PM 反推上游文档偏差

PM 看原型 / 看 diff 时若发现 brief / analysis / solution（PM 视图）/ prd / module 规格等上游文档写错，提醒 PM 在 task PM 视图「📁 历史档案 → 业务层偏差」表填一行（默认空，多数 task 不填）。close-task 调 `/doc-update` 时会扫这段 + 工程合同 §10，逐条确认改原文。

不要让 PM 只在对话里说偏差而不落表 —— 会丢。

### 步骤 12：等待 PM 决策

**PM 说"通过"**：
```bash
python3 .claude/scripts/task-transition.py "$TASK_FILE" --to 已完成
```

然后**直接调用** `/close-task`（在本窗口继续；不要让 PM 手动敲）。

**PM 说"打回"**：

1. 记录 PM 反馈到 PM 视图主文件「📁 历史档案 → PM 反馈」（**禁止**写入工程合同）：
   ```markdown
   ### 反馈 N - [YYYY-MM-DD]
   **问题描述：** [PM 原话]
   **要求修改：** [具体修改要求]
   **分类（PM-VIEW-RULES §9.4）**：[正向规则 / 反向约束 / 决策记录]
   **处理结果：** 待处理
   ```

   分类规则（参 PM-VIEW-RULES §9.4）：
   - 正向规则（"统一用 X" / "全文用 Y"）→ 后续 task 同步入「跨功能产品规则」
   - 反向约束（"禁用 X" / "不要 Y"）→ 后续 task 同步入工程合同 §6 易错点 / 禁止项
   - 决策记录（"二审改 X" / "重做为 Y"）→ 后续 task 同步入「关键产品决策」备选方案列

2. 转回执行中：
   ```bash
   python3 .claude/scripts/task-transition.py "$TASK_FILE" --to 执行中 --note "PM 打回：<反馈摘要>"
   ```

3. 应用 §PM 反馈分流策略（步骤 3 上方）判断"行为修订" vs "Bug 修复"，告知 PM 判断结果。判断错误 → PM 回复 "wrong" 切换分流。

4. 继续修复并重新走步骤 5-12（执行日志 / 自审 / commit / 呈交）。

## Rules

- task 文件用绝对路径读写（task worktree 中的路径和主仓路径不同）
- 代码改动在 task worktree 中进行
- 文档（docs/）不在 task worktree 中修改（hook 会拦截）
- 文档偏差记录到 task 文件，由 `/doc-update` 在 close-task 前处理
- AI 不得自动调任何 review 工具（`/review` `/qa` `/design-review` 等，I-RV1）；只在步骤 7 输出推荐清单
- PM 报告 review 结论后才 append `review_completed` 事件（I-RV3）；禁止 AI 替 PM 跑或凭记忆模拟
- 事件流缺 review_completed 不阻止「执行中→待验收」转换（I-RV2）
- dev server 在 task-execute 结束后保持运行，直到 close-task 时杀掉
- **commit + 转待验收 → 自动进步骤 11 呈交验收**（默认路径，PM 不手动敲 `/task-submit`）；PM 通过后 AI 在本窗口继续调 `/close-task`
- task-submit 仍存在但仅作 PM 手动兜底入口（重启窗口 / context 丢失 / 异常退出后重新呈交）
