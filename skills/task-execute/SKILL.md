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

## 单文件 typed contract 约定（必读）

本 skill 处理 task 的单文件 typed contract（delta-3）—— 一个物理文件 `task-NNN-<slug>.md`，内部由 region 标记分三区：

- **PM 确认区**（`<!-- region: PM-CONFIRM begin/end -->`）：📌 任务卡（含 executor / executor_model / 审查工具 字段）/ 📦 范围 / ✅ 验收清单 / 📥 PM 反馈承接清单。
- **执行区**（`<!-- region: EXEC begin/end -->`）：🔁 状态转换说明 / 🚦 启动前必读 / 🔧 实现规格 / 🧩 实现设计引用 / ⚠️ 约束与易错 / 🧪 自测说明 / ✔️ 工程层验收。**执行区是 agent 的实现依据。**
- **审计区**（`<!-- region: AUDIT begin/end -->`）：📋 文档偏差 / 🔍 自审记录 / 📁 历史档案（执行日志、PM 反馈）。

agent 读 task 文件即可拿到全部执行所需内容（同一文件分区读，无需跨文件）。

具体读写分工：
| 内容 | 读 / 写位置 |
|---|---|
| 任务描述 / 范围 / 验收清单 | 读 PM 确认区（📌 任务卡 / 📦 范围 / ✅ 验收清单） |
| 启动前必读清单 | 读执行区「🚦 启动前必读」 |
| 实现规格 / 实现设计引用（HOW） | 读执行区「🔧 实现规格」/「🧩 实现设计引用」 |
| 约束与易错（含 a11y / 视觉细则） | 读执行区「⚠️ 约束与易错」 |
| 工程层验收清单（grep / 单测） | 读执行区「✔️ 工程层验收」 |
| 写执行日志 | 写入审计区「📁 历史档案 → 执行日志」 |
| 写文档偏差 | 写入审计区「📋 文档偏差」 |
| 写自审记录 | 写入审计区「🔍 自审记录」 |
| 写 PM 反馈（task-submit 打回时）| 写入审计区「📁 历史档案 → PM 反馈」 |

**旧 v2 双文件 task 兼容**：在飞旧 task 仍是「PM 视图主文件 `.md` + 工程合同 `.engineering.md`」双文件结构，不回迁；本 skill 保留 v2 兼容读路径（见步骤 1）。

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
   - 状态为「待执行」。
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
⚠️ 检测到 ${REQ_BRANCH} 上有 N 个文件比 task worktree 新：
  - <path 1>
  - <path 2>
  ...

请选择处理方式：
 - 逐文件看 diff（推荐，每个文件单独决定采用 req 版本 / 保留 worktree 版本 / 跳过）
 - 全部跳过（task 内执行基于当前 worktree 文件）
 - 全部采用 req 版本（无需逐个 diff）
```

PM 选项处理（按自然语言意图分流，不列字母）：

| PM 表达 | 行为 |
|---|---|
| 「全部跳过 / 不动 / 用现有的」 | 不动 worktree，task-execute 继续。task 内执行基于当前 worktree 文件。 |
| 「全部采用 / 全部覆盖 / 用 req 版本」 | 对清单内每个 file 调 `apply-req-doc.sh`，跳过 diff 询问，全部覆盖。 |
| 「逐个看 / 一个个来 / 逐文件」 | 逐文件循环：先 `git diff --no-index <worktree path> <(git show <branch>:<path>)` 给 PM 看，再问下面分流问。 |

逐文件循环流程伪码：

```bash
echo "$DRIFT_JSON" | python3 -c 'import json,sys;[print(f["path"]) for f in json.load(sys.stdin)["files"]]' | \
while IFS= read -r path; do
  # 让 PM 看 diff（worktree 现状 vs req 分支版本）
  git -C "$TASK_WORKTREE" diff --no-index --color=always \
    "$path" <(git -C "$TASK_WORKTREE" show "${REQ_BRANCH}:${path}") || true

  # 问 PM 三选项（按自然语言意图，不列字母）
  cat <<EOF
请选择此文件的处理方式：
 - 采用 req 版本
 - 保留 worktree 版本
 - 跳过此文件
EOF
  # 「采用 req 版本」  → bash $MAIN_REPO_ROOT/scripts/apply-req-doc.sh "$TASK_WORKTREE" "$REQ_BRANCH" "$path" "$TASK_FILE"
  # 「保留 worktree」 → 不动
  # 「跳过」          → 不动，下一文件
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

- 「待执行」：转换为「执行中」后继续。
  ```bash
  # D7 后无 serial 阻塞；并行约束由依赖 gate 和 worktree 隔离承担。
  python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" --to 执行中
  ```
- 「执行中」：允许重试或 PM 打回后续跑，不重复 transition。包括：commit 后已呈交但 PM 还没决策的场景（task 状态仍是「执行中」）— 此时如想重新看呈交块跑 `/task-submit`。
- 「已完成」：错误退出，提示 `该 task 已完成；如需收尾，在本（task）窗口运行 /close-task task-NNN 启动 Phase 1（对齐/偏差/commit/写 marker），完成后会引导切到 req 窗口跑 Phase 2`。
- 其他状态：错误退出，展示当前状态，并提示 PM 回主窗口用 `/task-status` 查看。

### 步骤 1：读取 task 文件（三态格式分流）

1. 判别 task 格式（v1 老单文件 / v2 双文件 / v3 新单文件 typed contract）：
   ```bash
   TASK_FORMAT=$(python3 "$MAIN_REPO_ROOT/.claude/scripts/_lib/state.py" detect_format "$TASK_FILE")
   ```

   按格式分流读取与兼容文案：

   - **`v3`（新单文件 typed contract）**：正常路径，**不报告警**。task 文件本身就是单文件，无 `.engineering.md` 属正常。按下文 step 2 单文件分区读。
   - **`v2`（旧双文件 task）**：在飞旧 task，按兼容模式继续：
     ```bash
     ENG_FILE="${TASK_FILE%.md}.engineering.md"
     echo "ℹ️  检测到旧格式 task（双文件），兼容模式继续：$ENG_FILE" >&2
     ```
     按下文 step 3 从两文件分别读取。
   - **`v1`（旧单文件，薄 PM 视图）**：历史 task，按兼容模式继续——所有内容从 `$TASK_FILE` 读取（旧模板的「启动前必读」/「实现指引」/「易错点」等都在主文件中）。

2. **v3 — 从 task 单文件分区读取**（执行区是实现依据）：
   - PM 确认区「📌 任务卡」→ 任务描述、executor / executor_model / 审查工具、依赖
   - PM 确认区「📦 范围」→ 改 / 不改
   - PM 确认区「✅ 验收清单」→ PM 走查主路径
   - 执行区「🚦 启动前必读」→ 必读文件路径列表（步骤 2 用）
   - 执行区「🔧 实现规格」→ 本 task 的可执行实现规格（字段名 / props / 函数签名 / 调用链）
   - 执行区「🧩 实现设计引用」→ HOW-ID 行 + task-scoped 占位值
   - 执行区「⚠️ 约束与易错」→ 反向约束清单 + a11y / 视口 / 视觉规范细则
   - 执行区「🧪 自测说明」→ task 级流程化 UAT（步骤 7.5 task-verify 读）
   - 执行区「✔️ 工程层验收」→ grep / 单测 / 引用稳定性等自审条目

3. **v2 — 从 task 两文件分别读取**（兼容路径）：
   - PM 视图主文件（`$TASK_FILE`）：「📌 任务卡」任务描述 / 「🎯 关键产品决策」/「📋 功能清单」/「🚦 跨功能产品规则」/「📦 范围」/「✅ 验收清单」
   - 工程合同（`$ENG_FILE`）：「§1 元信息扩展」executor / model / 「§3 启动前必读」/「§4 功能清单工程版」/「§5 实现指引」/「§6 易错点 / 禁止项」/「§7 plan-review 沉淀」/「§8 视觉规范细则」/「§9 工程层验收清单」

   **v1 兼容**：跳过 step 3，从主文件读「启动前必读」/「实现指引」/「易错点」等旧 section（旧模板这些 section 都在主文件中）。

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

#### 2.1 按「启动前必读」列表读其他文档

按 task 文件的「启动前必读」列表逐个读取文档内容（v3：执行区「🚦 启动前必读」；v2：工程合同「§3 启动前必读」；v1：主文件「启动前必读」）。理解：
- 模块规格中的**功能清单（硬约束）**：功能行为、数据规则、角色权限必须严格遵循
- 模块规格中的**实现指引（软指引）**：推荐组件、DESIGN.md 对齐、交互状态覆盖，可在设计系统框架内自由发挥
- 设计系统规范（DESIGN.md）
- 项目背景（CONTEXT.md）
- 已发布的模块规格（docs/modules/*.md）+ 模块索引（docs/modules/INDEX.md）
- 参考源码（如列表中有已有页面/组件源码，理解其组件结构和布局模式）
- 同模块已完成 task 文件（复用经验、避免重复；v3 单文件读全文，v2 旧 task 两文件都读）

> **prototype 读取例外**（`_shared/pm-view/input-flow.md` §9.3.1）：task-execute 步骤 2.1 读 prototype 是**实现参考**（写新页面"长一样"），需要全局结构感 → **保留全文 Read**，**不应用** §9.3.1 反向校验 grep 强约束。
> §9.3.1 仅适用于反向校验场景（task-plan / task-spec / prd-writing 读 prototype 时反向校验上游文档描述）。task-execute 是写代码，不是反向校验。

**硬软分离原则：** 功能清单定义"做什么"（不可偏离），实现指引建议"怎么做"（可灵活调整）。在满足功能行为和设计系统约束的前提下，追求最好的视觉效果和交互体验。

**读完后**：agent 内部把 task 文件执行区（实现规格 + 实现设计引用 + 约束与易错）理解为完整的执行指令，开始步骤 3 实现。

### 步骤 3：实现代码（含 dispatch）

**步骤 3 的流程：状态 gate → dispatch → 越界保护 → 零改动检查。** 失败路径统一走 `--fail-execution` 回退 + 诊断文案。

#### 3.0 前置状态 gate（由入口前置完成）

入口前置已经完成「待执行 → 执行中」transition，或确认当前状态为「执行中」重试。进入实现阶段前仍保留轻量断言：状态必须是「执行中」。如果不是，说明入口前置没有成功完成，立即拒绝继续。

```bash
CURRENT_STATUS=$(python3 "$MAIN_REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" --get-status 2>/dev/null || echo "")
if [ "$CURRENT_STATUS" != "执行中" ]; then
  echo "❌ /task-execute 入口拒绝：task 状态为「${CURRENT_STATUS:-未知}」，不是「执行中」。" >&2
  echo "" >&2
  echo "请回到入口前置步骤处理状态，或在主窗口运行 /task-status 查看下一步。" >&2
  exit 1
fi
```

#### 3a-3e + claude-code 主流程：详见 `references/executor-dispatch.md`

完整 dispatch / 越界保护 / 回滚函数 / 诊断文案 / claude-code 执行者主流程见 [`references/executor-dispatch.md`](./references/executor-dispatch.md)：

- 3a. Lock + manual 幂等重入
- 3b. 正常 dispatch（含 I-AD5 pre-dispatch checkpoint gate / executor 解析 / adapter 调用 / 失败分类 + 回滚）
- 3c. 越界写保护 + `rollback_worktree` 函数
- 3d. 零改动检查（`CHANGE_COUNT == 0` → fail-execution）
- 3e. `output_diagnostic` 诊断文案函数（按 classification 给修复指引）
- claude-code 执行者主流程（实现前必做：读 PROMPT_FILE / 扫已有组件 / 复用 / 禁 git commit）

### 反馈循环规则（task-submit 打回后重新进入）

> **设计原则**：反馈循环只动原型代码，task md 业务字段（§🎯/§📐/§📋/§🚦/§✅）和工程合同业务相关段的对齐**统一交给 close-task §0 batch 处理**。
>
> 理由：反馈循环里很多改动会被后续反馈推翻，每轮跟着改文档是空转；原型迭代要保留灵活性；close-task batch 模式 PM 一次决议 diff 比每轮二次确认效率高。

当 task-submit 打回后重新进入 task-execute，agent MUST：

1. **读最新反馈**：从 task 文件「📁 历史档案 → PM 反馈」section 读最新一条（v3 在审计区；v2 在 PM 视图主文件，不写工程合同）。

2. **明确执行参照系**（这是反馈循环里 AI 决策的依据）：
   - 当前原型代码（task worktree 实际状态）
   - 「📁 历史档案 → PM 反馈」按时间倒序（最新一条最权威）
   - **不**以 task md 的 §🎯/§📐/§📋/§🚦/§✅ 业务字段为参照——这些字段在反馈循环中**故意不跟**，等 close-task §0 统一对齐。

3. **多轮反馈冲突解决**：默认"后覆盖前"。新反馈与旧反馈矛盾时，按新的来；除非 PM 在新反馈中明确说"保留旧规则"或"回退到第 N 轮"。

4. **本轮 AI 只做这两件事**：
   - 改原型代码（按反馈实施）
   - 在步骤 5 执行报告里 append `**文档对齐预告：**` 字段，列出本轮原型改动可能影响 task md 哪些段（给 close-task §0 当对齐线索）

5. **本轮 AI 明确不做的事**：
   - **不改** task md 的 §🎯/§📐/§📋/§🚦/§✅ 业务字段
   - **不改** 工程合同的 §4/§6/§8 业务相关段
   - **不分类**反馈为"行为修订/Bug 修复"，不暴露内部分类标签给 PM
   - **不为**"我准备改哪些文件"做二次确认

6. **AI 何时主动问 PM**：仅当**实现歧义阻塞**时（PM 反馈描述模糊到无法实施，例如"两列怎么合"），用 AskUserQuestion 问澄清细节。**不问**"文档要怎么改"——文档对齐不是反馈循环的事。

7. **PM 反馈本身的记录**：依然按步骤 12「PM 说"打回"」path 把反馈记入「📁 历史档案 → PM 反馈」并按 `_shared/pm-view/input-flow.md` §9.4 三类分类（正向规则/反向约束/决策记录）。这是给后续 task-spec 抽取**已完成 task** 的历史反馈用的，跟本轮反馈处理是不同维度，保留。

### 步骤 4：启动 dev server（UI 类 task）

如果是 UI 类 task：
1. 启动 dev server，绑定到 task 文件中指定的端口
2. 确保 server 在后台运行，不阻塞后续步骤
3. 验证 server 可访问

非 UI 类 task 跳过此步骤。

### 步骤 5：写执行日志

**v1 兼容模式**：写入主文件 `## 执行日志` section（旧版 section 名）。

**v3 / v2**：写入 task 文件「📁 历史档案 → 执行日志」section（v3 在审计区；v2 在 PM 视图主文件历史档案）：

```markdown
#### 执行报告 - [YYYY-MM-DD HH:MM]
**改动摘要：** [简述做了什么]
**新建文件：** [文件列表]
**修改文件：** [文件列表]
**文档对齐预告：** [本轮原型改动可能影响 task md 哪些业务字段；首次实现 / 无影响填"无"]
- §📋 字段口径表 第 3-4 行 → 合并为 1 行（举例）
- §📐 产物预览 Tab 2 列结构 → 删 2 列加 1 列（举例）
- §🎯 决策 #N → 反转为方案 B（举例）
**验收标准完成情况：**
- [x] 条件 1 — 已实现
- [x] 条件 2 — 已实现
```

**「文档对齐预告」字段说明**：
- 反馈循环里 AI 改原型代码时同步写——成本低，给 close-task §0 当对齐线索
- 不要求精确，列段名 + 改动方向即可（PM 在 close-task 会看 diff 决议）
- 反馈循环规则禁止 AI 直接改 §🎯/§📐/§📋/§🚦/§✅ 正文，**只在这里预告**

### 步骤 6：写文档偏差

**v3 — 写审计区「📋 文档偏差」section**（单文件 typed contract 统一一处偏差表）：

实现过程中发现与 `prd.md` / `implementation-design.md` / `docs/modules` / `docs/DESIGN.md` / `docs/CONTEXT.md` 等任意文档不一致处，填进审计区「📋 文档偏差」表（四列：文档位置 / 文档原文 / 实际实现 / 建议改法）：

```markdown
| 文档位置 | 文档原文 | 实际实现 | 建议改法 |
|---|---|---|---|
| docs/modules/auth.md 第 15 行 | 使用 JWT 认证 | 改用 Session 认证（因 XX 原因） | 改写为 Session 认证 |
| prd.md §🎯 关键产品决策 #2 | 选用方案 A | 实证 demo 后用户路径走不通 | 改方案 B（理由：...）|
```

无偏差填「无」。close-task Phase 2 把本段 promote 成 req `adjustment` 事件；close-req 步骤 1.5 聚合 → doc-update rewrite mode（D13 final, 2026-05-16）。

**v2 兼容 — 双文件两层分工**（旧 task）：工程层偏差（字段命名 / 接口签名 / 组件路径）写工程合同 §10 文档偏差表；业务层偏差（产品决策 / 需求描述 / 模块功能规格）写 PM 视图「📁 历史档案 → 业务层偏差」表。

**v1 兼容**：所有偏差写入主文件 `## 文档偏差` section（旧版）。

**默认值**：无偏差写「无」（多数 task 没偏差）。

### 步骤 7：写 commit 前 AI 自审 placeholder

实现完毕、执行日志和文档偏差填好后，**不再主动列推荐 review 工具区块**（2026-05-08 收口：推荐 review 改作步骤 11 验收信息块末尾的辅助提示，不当 commit 前必经步骤）。

AI 在「自审记录」section 追加一条 commit 前 placeholder（提供 task-transition.py「执行中→已完成」校验所需的 has_meaningful_content 非空内容）：

```markdown
### 自审 1 - [YYYY-MM-DD HH:MM]
**工具：** AI 阶段自审（commit 前机械检查）
**结果：** pass
**详细发现：**
- 改动文件 N 个；执行日志已写；文档偏差已填；dev server 持续在 :PORT
- 验收阶段如需深度审查，PM 可自行调用 /review、/qa、/design-review（自审记录会追加条目）
**遗留问题：** 无
```

**关键约束**：「**详细发现：**」下面**必须有至少一行不带 `**xxx：**` 前缀的实质文字**（散文或 bullet 都行）。task-transition.py 的 has_meaningful_content 会过滤掉 `**工具：** **结果：** **详细发现：** **遗留问题：**` 等纯前缀行——只有不带这些前缀的行才会被算非空。

**仍然适用**（I-RV1 / I-RV3）：AI 不得自动调用任何 review skill（`/review` `/qa` `/qa-only` `/design-review`），即使是"机械检查"也不要伪装成跑了 review。本 placeholder 只是声明"AI 阶段已结束、PM 可以接手"，不冒名 review。

> **task-verify 不算 review skill**（参 `skills/task-verify/SKILL.md`「I-RV1 边界」表）：UAT 是验证 PM 拍板流程是否通（明确 pass/fail），review 是探索性质量审查（多元 finding）。task-verify 是 task lifecycle 内部 skill（同 task-spec / task-plan / close-task），AI 必须在步骤 7.5 自动调用。

### 步骤 7.5：调 task-verify 跑流程化 UAT（UI task 必经，非 UI task 跳过）

**触发条件**：task md 「🧪 自测说明」段非空且不是「无」。

**流程**：Claude 主端用 Skill tool 调 `task-verify`，参数为 `$TASK_FILE`。task-verify 内部读自测说明 + 复用 task-execute 步骤 4 起的 dev server（不在跑则自起）+ 调 `gstack-browse` 逐流程跑 + 写 `.pm-workflow/tasks/<task-stem>/verify/report.md`。

**结果分流**：

- **pass**（exit 0）→ 进步骤 10 commit；执行日志（步骤 5）append 一行「task-verify: ✅ N/N 流程通过」
- **fail**（exit 1）→ **不 commit**，进反馈循环：
  1. 把 verify/report.md 失败摘要写入 task 文件「📁 历史档案 → PM 反馈」（v3 在审计区；v2 写 PM 视图主文件。标记 `自动反馈 — task-verify`）：
     ```markdown
     ### 反馈 N - [YYYY-MM-DD] (task-verify 自动)
     **问题描述：** task-verify M/N 流程通过；失败：流程 X 步骤 Y「期望 Z」未满足
     **要求修改：** 详见 .pm-workflow/tasks/<task-stem>/verify/report.md
     **处理结果：** 待处理
     ```
  2. 按 §反馈循环规则 改代码（不动 task md 业务字段；步骤 5 执行报告写「文档对齐预告」）
  3. 修完重新跑步骤 3 → 7 → 7.5 task-verify
  4. **连续 3 次 task-verify fail**（防死循环）→ 把累积 report 呈交 PM 决定是否人工接手（PM 可手动通过 / 关 task / 改 task md 自测说明字面值）

**非 UI task / 自测说明为空**：task-verify 内部检测后直接返回 pass（写 `report.md` 标记 `skipped: 非 UI task`），本步骤无副作用。

**dev server 起不来**：task-verify 内部超时 30s 后 fail。task-execute 视作 task-verify fail，走反馈循环（"dev server 起不来"本身就是必须修的 bug）。

### 步骤 8：（保留编号便于历史引用 — 原"自审记录由步骤 7.1 写"逻辑已并入步骤 7 的 placeholder，PM 验收阶段后续追加条目走步骤 12 后的"附录：PM 验收阶段跑 review 旁路"）

### 步骤 9：（保留编号便于历史引用）

### 步骤 10：Commit（不切状态）

**实现完毕 + 文档偏差填好 + 自审 placeholder 写好 → 直接 commit。**

task 状态在 commit 前后**全程保持「执行中」**——不再转「待验收」。PM 验收期间 task 状态仍是「执行中」（I-CB10 写入豁免范围覆盖：PM 打回反馈后 AI 继续修代码不被拦截），PM 通过呈交块时再统一转「已完成」。

```bash
cd "$TASK_WORKTREE"

# 收集改动摘要（从最近一条「执行报告」section 提取）
SUMMARY=$(awk '/^### 执行报告/{flag=1} flag && /^\*\*改动摘要/{sub(/\*\*改动摘要：\*\*\s*/,"");print;exit}' "$TASK_FILE")
[ -z "$SUMMARY" ] && SUMMARY="实现 $(basename "$TASK_FILE" .md)"

git add -A
git commit -m "task-${TASK_ID}: ${SUMMARY}"
```

Dev server 保持运行（PM 验收时需要访问）。

**Commit 后不退出 skill** —— 直接进步骤 11 呈交验收（v4 单窗口 lifecycle）。

### 步骤 11：呈交 PM 验收（合并自 task-submit）

> 默认路径：commit 后**自动**呈交，PM 不需手动敲 `/task-submit`。task 状态全程「执行中」，commit 不切状态。
> 兜底入口：PM 在异常情况（窗口被关 / context 丢失 / 重启 IDE）下仍可手动跑 `/task-submit`，逻辑等价。

详见 [`references/acceptance-handoff.md`](./references/acceptance-handoff.md)：
- 11.1 组装验收信息包（读 task 文件 + diff + review_completed 事件 + UI/非 UI 判定）
- 11.2 输出验收信息块（UI 类 / 非 UI 类两种模板，含可选深度审查辅助提示）
- 11.3 走查时引导 PM 反推上游文档偏差（reverse-flow 到「📁 历史档案 → 业务层偏差」表）

### 步骤 12：等待 PM 决策

**PM 说"通过"**：
```bash
python3 .claude/scripts/task-transition.py "$TASK_FILE" --to 已完成
```

`task-transition.py` 在「执行中→已完成」入口校验文档偏差 + 自审记录非空（I-TT3）；不通过会拒绝转换，PM 需先补齐再喊通过。

然后输出（close-task 是两阶段调用：Phase 1 在本窗口跑，Phase 2 切到 req 窗口跑）：

```text
✅ task-NNN 状态已转「已完成」。

下一步：在本（task）窗口运行：
  /close-task task-NNN

AI 会走 Phase 1（task md ↔ 原型对齐 / 文档偏差校验 / 视觉规范沉淀 DESIGN.md / commit 到 task 分支 / 写 finalize marker），完成后会提示你切到 req 窗口再跑一次 /close-task 走 Phase 2（merge → req / 删 task worktree+branch / auto-chain）。

理由：Phase 1 必须在 task 窗口跑——agent 要直接读 task 改动的原型代码并把 task md 改动 commit 到 task 分支；跨 worktree 改会污染 req 分支历史。Phase 2 才切 req 窗口（删 task worktree 不能"删自己脚下"）。
```

**PM 说"打回"**：

> 打回**不切状态** — task 全程是「执行中」，AI 直接基于反馈继续修，不再走 `task-transition --to 执行中` 的回退（该 transition 在 2026-05-08 删除，I-TT4 废弃）。

1. 记录 PM 反馈到 task 文件「📁 历史档案 → PM 反馈」（v3 在审计区；v2 写 PM 视图主文件、**禁止**写入工程合同）：
   ```markdown
   ### 反馈 N - [YYYY-MM-DD]
   **问题描述：** [PM 原话]
   **要求修改：** [具体修改要求]
   **处理结果：** 待处理
   ```

   PM 反馈留在本段不归类。后续同 req 的 task 由 task-spec 按 relevance 二分（适用 / 不适用）承接进新 task 的「PM 反馈承接清单」（delta-3 §2.4）；视觉规范类 / 全项目跨功能产品规则由 close-task 收尾时按目标 promote（参 task 文件「📁 历史档案 → PM 反馈」段内的 close-task 说明）。

2. 应用 §反馈循环规则（实现前必做下方）：按规则只改原型代码，不动 task md 业务字段；步骤 5 执行报告里写「文档对齐预告」。文档对齐统一交给 close-task §0。

3. 修复完毕后**追加 fix commit**（保留主 commit + fix commit 的 diff 历史，close-task merge 时统一进 req 分支；commit message 模板：`task-NNN fixup: <一句话>`）。

4. 重新呈交（重新走步骤 11/12），等待 PM 通过/再打回。

### 附录：PM 验收阶段跑 review（旁路 — 非必经）

PM 在验收期间任意时刻可自跑 `/review` `/qa` `/design-review` 等 review 工具；AI 仍**不得**自行调用（I-RV1）。PM 报告结论后 AI 机械执行：在 task 文件「🔍 自审记录」段追加自审记录（v3 在审计区；v2 在工程合同 §11）+ append `review_completed` 事件（I-RV2）。详见 [`references/review-bypass.md`](./references/review-bypass.md)。

## Rules

- task 文件用绝对路径读写（task worktree 中的路径和主仓路径不同）
- 代码改动在 task worktree 中进行
- 文档（docs/）不在 task worktree 中修改（hook 会拦截）
- 文档偏差记录到 task 文件，由 `/doc-update` 在 close-task 前处理
- AI 不得自动调任何 review 工具（`/review` `/qa` `/qa-only` `/design-review` 等，I-RV1）；推荐 review 仅作步骤 11 验收信息块末尾「⚙️ 可选深度审查」辅助提示，PM 自取所需
- **task-verify 例外**：UI task 在步骤 7.5 **必须**调 task-verify（流程化 UAT，不属于 review skill 范畴，I-RV1 不适用）；fail → 反馈循环 + 不 commit；连续 3 次 fail 呈交 PM 人工接手
- PM 报告 review 结论后才 append `review_completed` 事件（I-RV3）；禁止 AI 替 PM 跑或凭记忆模拟
- 事件流缺 review_completed 不阻止「执行中→已完成」转换（I-RV2）
- dev server 在 task-execute 结束后保持运行，直到 close-task 时杀掉
- **commit 不切状态 → 自动进步骤 11 呈交验收**（task 状态全程「执行中」直到 PM 通过；默认路径，PM 不手动敲 `/task-submit`）；PM 通过后 AI 转「已完成」并提示 PM 在本（task）窗口跑 `/close-task task-NNN` 启动 Phase 1（close-task 是两阶段调用，Phase 1 在 task 窗口对齐 + commit，Phase 2 切到 req 窗口 merge + 清理）
- PM 打回不切状态：写反馈到 task 文件「📁 历史档案 → PM 反馈」（v3 审计区 / v2 PM 视图）→ AI 修代码 → 追加 fix commit → 重新呈交（不再走 `--to 执行中` transition）
- task-submit 仍存在但仅作 PM 手动兜底入口（重启窗口 / context 丢失 / 异常退出后重新呈交）
