---
name: pmai-task-execute
description: |
  六步第三步「建」的核心：在 prototype/ 用 Claude Code 栈内建（零录入），强制先读 DESIGN.md 再动手；建完自动跑三道审（覆盖审计 + 视觉门 + 行为审）合成一份给 PM；再走体验迭代（AI 主动批量 flag、PM 勾改），最后呈交验收闸门（PM 唯一决策点）。
---

# /pmai-task-execute

> **PM 视图（banner + 决策门 label）**：入口 banner（`status-view.py --banner-only --skill TASK-EXECUTE`）；验收呈交闸门 label 按 `_shared/pm-view/banner-rules.md` §3 三条硬规则（label=动作如「task-NNN 通过验收」/「打回 task-NNN 修改」/「范围改动」）；退出 Next Up 引导 `/pmai-close-task` 或继续修改。
>
> **PM 答题规则**：所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 四条硬规则走（空答 STOP / 没拿到答案禁止默认走通过分支 / runtime 退化保留 wait / 多决策拆开顺序问）。**历史教训**：PM 没答 AI 默认走通过 → task 跳过验收。**Runtime 兜底**：本 skill 各门写的都是 picker 形态；runtime 不支持时 AI 按 §1.3 自动退化为编号列表，仍 wait。

## 六步定位

这一步是「建」——把第二步（范围确认）拍板的范围清单，在 `prototype/` 主原型里用 Claude Code **栈内建出来（零录入，PM 不手敲代码）**。一个 task 是 PM 看 demo 确认方向的阶段单元。

每个 task 走完三段：

1. **建**：强制先读项目 `DESIGN.md`（视觉规范单一来源）→ 在 `prototype/` 里实现。
2. **建完自动三道审**（复用同一次 dev server 起停，合成一份给 PM）：
   - **覆盖审计**：`coverage-reviewer` agent 用范围清单对代码硬 diff，报「建了 / 丢了 / 降级占位」（白纸新鲜视角，非自审）。
   - **视觉门**：gstack `/design-review` 起 dev server 后**只截图审计、不自动改**，出口是 PM 一句话 pass / 打回。
   - **行为审**：task 自测说明派生的验收流程驱动 gstack `/browse` 走确定性路径（验证「跑得通不通」）。
3. **体验迭代**：AI 把三道审 + 自己看出来的问题**主动批量 flag** 给 PM，PM 勾哪些改；停止条件 = demo 成功标准达到 + PM 在呈交闸门拍板。

呈交验收闸门保留 —— **这是 PM 全程唯一的决策点**。

## When To Use

- 由 `/pmai-next` 在 build 推进里拉起，PM **不切窗口、不另起会话**；也可由执行器 adapter 进入同一流程。
- **谁来建 = PM 指定的独立执行器**：build 派发给 task 卡 `executor` 字段指定的执行器——`claude-code`（独立 Claude subagent）/ `codex` / `cursor-agent` / `gemini`（各自独立 CLI），留空走 settings 默认。**建的都是独立 AI、在 task 隔离副本沙盒里干；驱动自己不 inline 建**（保隔离 + 角色分离 + failable 沙盒、PM 窗口对话不被建码过程刷屏）。
- **驱动（PM 这一个窗口）只做编排**：定位 task / 解析执行器 / 派发 / 越界·零改动检查 / commit / 跑三道审 / 呈交 PM。这些命令显式带目录（git 用 `git -C "$TASK_WORKTREE"`；起 dev 用子 shell `( cd "$TASK_WORKTREE/prototype" && … )`，单次 Bash 调用内 cd 有效），**不依赖会话 cwd、不 `cd` 进隔离副本**。PM 无需 `claude --add-dir`、无需为每个 task 开新窗口。

## 单文件 typed contract 约定（必读）

本 skill 处理 task 的单文件 typed contract —— 一个物理文件 `task-NNN-<slug>.md`，内部由 region 标记分三区：

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

**旧双文件 task 兼容**：在飞旧 task 仍是「PM 视图主文件 `.md` + 工程合同 `.engineering.md`」双文件结构，不回迁；本 skill 保留双文件兼容读路径（见步骤 1）。

## Workflow

### 入口前置

#### 入口步骤 0：banner

agent 进入 skill 时**立刻** Bash echo 一行 banner（此时 task 隔离副本路径还没解析，不调 `status-view.py`；用字面值，见 `_shared/pm-view/banner-rules.md` §1）：

```bash
echo "━━━ PMAI ► TASK-EXECUTE ▸ 启动 task 执行 ━━━"
```

#### 入口步骤 1：定位 task 文件

支持三种参数模式：

1. **完整路径**：参数是可读的 `*.md` 文件时，直接作为 `TASK_FILE`。
2. **短 ID**：参数匹配 `^task-[0-9]{3}$` 时，在所有 active req 下模糊匹配（含主仓 + 所有 `.worktrees/req-*/requirements/active` + **task-* worktree 独家区**）：
   ```bash
   MATCHES=$(find requirements/active \
       "$MAIN_REPO_ROOT"/.worktrees/req-*/requirements/active \
       "$MAIN_REPO_ROOT"/.worktrees/task-*/requirements/active \
       -name "${ARG}-*.md" -type f 2>/dev/null | sort -u)
   ```
   - 唯一匹配：使用该文件。
   - 0 个或多个匹配：报错退出，并提示 PM 传完整 task 文件路径（多 active req 并行时短 ID 可能在多个 req 里冲突）。

   > **注**：task-confirm 创建 task worktree 后会把 task md 从 req 分支删、只在 task 分支独家。短 ID 模式必须扫 `.worktrees/task-*/` 才找得到这类 task；否则跑 `/pmai-task-execute task-NNN` 会在已 confirm 的 task 上误报 "0 个匹配"。
3. **无参数**：自动扫描主仓 + `.worktrees/req-*/requirements/active` + **`.worktrees/task-*/requirements/active`**，找出所有同时满足下列条件的 task：
   - 状态为「待执行」。
   - 对应 `.worktrees/<task-stem>` 已存在。

无参数模式：

- 唯一匹配：自动选定。
- 0 个匹配：报错，提示 PM 先跑 `/pmai-task-confirm <task-file>` 把隔离副本备好。
- 多个匹配：报错，列出候选短 ID，提示 PM 改跑 `/pmai-task-execute task-NNN`。

定位成功后第一时间输出进度反馈：

```bash
echo "🎯 自动选定: $TASK_FILE"
```

#### 入口步骤 2：解析 task 隔离副本路径（不 cd）

单窗口模型不 `cd` 进隔离副本——解析出主仓根 + task 隔离副本的绝对路径，后续所有命令显式带目录。从任意位置（主仓 / req 隔离副本 / 当前 build 窗口）都能稳健解析：

```bash
MAIN_REPO_ROOT="$(cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." && pwd)"
TASK_STEM=$(basename "$TASK_FILE" .md)
TASK_WORKTREE="$MAIN_REPO_ROOT/.worktrees/$TASK_STEM"

if [ ! -d "$TASK_WORKTREE" ]; then
  echo "❌ task 隔离副本不存在：$TASK_WORKTREE" >&2
  echo "   先跑 /pmai-task-confirm $TASK_FILE 备好隔离副本再重试（task-confirm 正常由 build 推进自动跑，这里是异常兜底）。" >&2
  exit 1
fi
```

> **为什么不 cd**：task 隔离副本在 `.worktrees/` 下，可能不在当前会话 launch dir 子树内，`cd` 会被 Claude Code 沙盒在调用结束后 reset，后续命令落到错误目录。改用显式 `git -C` / 子 shell cd（单次 Bash 调用内有效）彻底回避——PM 也因此不必 `claude --add-dir`、不必切窗口。`MAIN_REPO_ROOT` 经 `git rev-parse --git-common-dir` 解析，不论会话起在主仓还是哪个隔离副本里都指向同一个主仓根。

#### 入口步骤 2.4：检测 req 文档 drift + PM 决定是否拉取

`scripts/check-req-doc-drift.sh` 列出 task worktree 与 req 分支之间「项目级 DESIGN.md / CLAUDE.md + requirements/active/<req-id>/」范围内 hash 不一致的文件。**纯只读** —— 不写 worktree 任何文件、不写 `.git/index.lock`。task own 的文件不在 drift 范围（task 自决）。

> 取代静默批量覆盖：旧机制会偷偷盖掉 worktree 上 task agent 已经做的合法本地改动；现机制让 PM 看 diff 后逐文件决定。新建的 task worktree 通常无 drift，PM 体验是 1 行「✓」直接通过。

```bash
DRIFT_SCRIPT="$PMAI_HOME/scripts/check-req-doc-drift.sh"
if [ ! -f "$DRIFT_SCRIPT" ]; then
  echo "❌ drift 检测脚本不在预期路径：$DRIFT_SCRIPT" >&2
  echo "这通常意味着消费仓的 PMAI 框架版本落后或同步状态有问题。" >&2
  echo "请回主仓跑框架同步流程后再重试 /pmai-task-execute。" >&2
  exit 1
fi
REQ_BRANCH=$(git -C "$MAIN_REPO_ROOT" branch --contains HEAD --format='%(refname:short)' | grep '^req-' | head -1)
DRIFT_JSON=$(bash "$DRIFT_SCRIPT" "$TASK_WORKTREE" "$REQ_BRANCH" "$TASK_FILE")
DRIFT_COUNT=$(echo "$DRIFT_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["drift_count"])')
```

**drift_count = 0**：直接通过，进步骤 2.5（无需打扰 PM）。

**drift_count > 0**：prose 头部 + AskUserQuestion picker：

prose 头部：
```
⚠️ 检测到 ${REQ_BRANCH} 上有 N 个文件比 task worktree 新：
  - <path 1>
  - <path 2>
  ...
```

AskUserQuestion（处理整体策略）：
- `question`: "怎么处理 req 文档 drift？"
- `options`:
  - `label`: `逐文件看 diff`
    `description`: `推荐，每个文件单独决定采用 req 版本 / 保留 worktree 版本 / 跳过`
  - `label`: `全部跳过`
    `description`: `不动 worktree，task 内执行基于当前 worktree 文件`
  - `label`: `全部采用 req 版本`
    `description`: `对清单内每个 file 调 apply-req-doc.sh 全部覆盖，无需逐个 diff`

**PM 答题处理**：
- 选 `全部跳过` / 输 `2` / 输 "全部跳过 / 不动 / 用现有的" → 不动 worktree，task-execute 继续
- 选 `全部采用 req 版本` / 输 `3` / 输 "全部采用 / 全部覆盖 / 用 req 版本" → 对清单内每个 file 调 `apply-req-doc.sh` 全部覆盖
- 选 `逐文件看 diff` / 输 `1` / 输 "逐个看 / 一个个来 / 逐文件" → 进入逐文件循环（每个文件单独 AskUserQuestion）

逐文件循环（按 `askuser-rules.md §1.4` 多决策拆开顺序问，每个文件单独 AskUserQuestion）：

```bash
echo "$DRIFT_JSON" | python3 -c 'import json,sys;[print(f["path"]) for f in json.load(sys.stdin)["files"]]' | \
while IFS= read -r path; do
  # 让 PM 看 diff（worktree 现状 vs req 分支版本）
  git -C "$TASK_WORKTREE" diff --no-index --color=always \
    "$path" <(git -C "$TASK_WORKTREE" show "${REQ_BRANCH}:${path}") || true
done
```

每个文件 AskUserQuestion：
- `question`: "<path> 怎么处理？"
- `options`:
  - `label`: `采用 req 版本`
    `description`: `调 apply-req-doc.sh 覆盖 worktree 版本`
  - `label`: `保留 worktree 版本`
    `description`: `不动 worktree`
  - `label`: `跳过此文件`
    `description`: `不动，进下一文件`

**失败容忍范围（区分两类异常，不要混淆）**：

- **脚本跑起来报错**（git show 失败、hash 算不出、JSON 解析异常等）→ 不阻断启动，task-execute 继续（同 sync-req-docs 历史 best-effort 行为）。check-task-scope.py 的 implicit deny 仍然兜底拦截 task 误 commit 项目级 / 兄弟 task 文件。
- **脚本文件不存在**（`bash: $PMAI_HOME/scripts/check-req-doc-drift.sh: No such file or directory`）→ **不属于失败容忍**，硬失败退出，明确报给 PM：
  ```
  ❌ drift 检测脚本不在预期路径：$PMAI_HOME/scripts/check-req-doc-drift.sh
  这通常意味着消费仓的 PMAI 框架版本落后或同步状态有问题。
  请回主仓跑框架同步流程后再重试 /pmai-task-execute。
  ```
  AI 在 PM 对话里**禁说「脚本未安装」**这种措辞 —— 脚本不是第三方依赖，是框架自带文件，「未安装」会误导 PM 去 `npm install` / `brew install`。正确措辞是「脚本不在预期路径」+ 把完整绝对路径报出来，PM 一眼能判定是 `.claude/` 丢了还是别的问题。

#### 入口步骤 2.5：依赖前置 gate（兜底层）

这是防止 PM 手动用 `task-transition.py` 强改状态、绕过 `/pmai-task-confirm` 的兜底层。逻辑必须与 `/pmai-task-confirm` 的「步骤 4-pre：依赖前置检查」一致：

1. 解析 `## 依赖` section，只提取 `task-NNN` 模式。
2. 在同 req 下查找每个依赖 task。
3. 读取依赖 task 状态。
4. 任一依赖状态不是「已完成」时：
   - `exit 1`
   - 直接报错给 PM：
     ```text
     ❌ task-NNN 依赖未完成：task-MMM 当前状态为「<status>」。
     请先 close 依赖 task，再重新运行 /pmai-task-confirm <task-file>。
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

#### 入口步骤 3：检查状态（不 transition；transition 由 §3b dispatch 物化绑定）

读取当前 task 状态：

```bash
CURRENT_STATUS=$(python3 "$PMAI_HOME/scripts/task-transition.py" "$TASK_FILE" --get-status 2>/dev/null || echo "")
```

状态处理：

- 「待执行」：继续走，进 §3b dispatch 时由 `task-transition --bound-to-execution-event` 物化绑定 dispatch 事件、原子完成 transition（堵"状态推到执行中但 dispatch 没真跑"的悬空态）。
- 「执行中」：允许重试或 PM 打回后续跑，不重复 transition。包括：commit 后已呈交但 PM 还没决策的场景（task 状态仍是「执行中」）— 此时如想重新看呈交块跑 `/pmai-task-submit`。dispatch §3b 进入时若已是「执行中」会单独 emit 一条 dispatch 事件作为重试审计标记，不再 transition state。
- 「已完成」：错误退出，提示 `该 task 已完成；如需收尾跑 /pmai-close-task task-NNN（AI 自动跑完收尾链：对齐 + 沉淀 + 并回 + 清理，不切窗口）`。
- 其他状态：错误退出，展示当前状态，并提示 PM 用 `/pmai-task-status` 查看。

### 步骤 1：读取 task 文件（三态格式分流）

1. 判别 task 格式（v1 老单文件 / v2 双文件 / v3 新单文件 typed contract）：
   ```bash
   TASK_FORMAT=$(python3 "$PMAI_HOME/scripts/_lib/state.py" detect_format "$TASK_FILE")
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

#### 2.0 项目级 DESIGN.md 强制 echo（建之前必读，六步③硬规则）

**六步「建」的硬规则：动手写代码前必须先把项目 `DESIGN.md` 读进 context。** DESIGN.md 是项目级视觉规范单一来源（一组正向视觉约束），栈内建出来的页面要落在这套约束里。

UI task 漏读 / 浅读 DESIGN.md 是早期原型反复迭代踩坑的根因（Read tool 触发与否取决于 LLM 自觉，长文进 context 后细节又会被冲淡）。本子步骤用 Bash `cat` 把 DESIGN.md 全文无条件 echo 到 transcript，**保证内容进入 working context**——比依赖 Read tool 自觉触发硬。冗余于「启动前必读」列表也无害。

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
- 项目背景（PROJECT.md）
- 已发布的模块规格（docs/modules/*.md）+ 模块索引（docs/modules/INDEX.md）
- 参考源码（如列表中有已有页面/组件源码，理解其组件结构和布局模式）
- 同模块已完成 task 文件（复用经验、避免重复；v3 单文件读全文，v2 旧 task 两文件都读）

> **prototype 读取例外**（`_shared/pm-view/input-flow.md` §9.3.1）：task-execute 步骤 2.1 读 prototype 是**实现参考**（写新页面"长一样"），需要全局结构感 → **保留全文 Read**，**不应用** §9.3.1 反向校验 grep 强约束。
> §9.3.1 仅适用于反向校验场景（task-plan / task-spec / prd-writing 读 prototype 时反向校验上游文档描述）。task-execute 是写代码，不是反向校验。

**硬软分离原则：** 功能清单定义"做什么"（不可偏离），实现指引建议"怎么做"（可灵活调整）。在满足功能行为和设计系统约束的前提下，追求最好的视觉效果和交互体验。

**读完后**：agent 内部把 task 文件执行区（实现规格 + 实现设计引用 + 约束与易错）理解为完整的执行指令，开始步骤 3 在 `prototype/` 里栈内建。

### 步骤 3：在 prototype/ 栈内建（含 dispatch）

这一步是六步「建」的动手处：用 PM 指定的执行器（默认 Claude Code，可换 codex / cursor-agent / gemini）在 `prototype/` 主原型里实现范围清单里的内容（**零录入** —— PM 不手敲代码，独立执行器在栈内建）。改动落在 task worktree 的 `prototype/`，确认后由 close-task / close-req merge 回主原型主线。

**步骤 3 的流程：状态 gate → dispatch → 越界保护 → 零改动检查。** 失败路径统一走 `--fail-execution` 回退 + 诊断文案。

> **task 边界硬规则**（避免任何"PRD §6.1 要求建立 X 规范"驱动的越界）：
>
> task worktree 内**任何 `docs/*` 改动**默认不属于 task 边界 —— 越界保护（§3c）按 task md 「执行范围」allowlist 放行，但 allowlist 应当**极少**含 `docs/*`。
>
> 涉及视觉规范 / 项目级规则 / 字段字典 / 权限矩阵等项目级文档产物——**即使 PRD 明文要求"建立 X 规范段"**——按以下路径处理，不在 task 主线代码 + commit 上：
> - **PM 反馈类**：留在 PM 视图 `## 📁 历史档案 → ### PM 反馈`，分类「视觉规范」/「产品规则」，由 close-task §1.5 / §1.6 沉淀（patch 到 `$MAIN_REPO_ROOT/docs/*`，不 commit）
> - **PRD 主线规范产物**：留草稿在 task PM 视图暂存区（或独立 .md 草稿），task close 后跑 `/pmai-doc-update` 走正规审定 + patch 到 req 分支
>
> 如果发现 task md 「执行范围」allowlist 写了 `docs/*` 项 → 高概率是 task-plan 拍 §4.1 反模式 A 时误判（应文档类不立 task / 走 doc-update，被错当成重构类合并进了业务 task）。当场停下来给 PM 一句话提示："task 执行范围含 docs/*，疑似 task-plan §4.1 反模式 A 文档类误判，建议先回 task-plan 调整再继续"，由 PM 拍。

#### 3.0 前置状态 gate（由入口前置完成）

入口前置已经完成「待执行 → 执行中」transition，或确认当前状态为「执行中」重试。进入实现阶段前仍保留轻量断言：状态必须是「执行中」。如果不是，说明入口前置没有成功完成，立即拒绝继续。

```bash
CURRENT_STATUS=$(python3 "$PMAI_HOME/scripts/task-transition.py" "$TASK_FILE" --get-status 2>/dev/null || echo "")
if [ "$CURRENT_STATUS" != "执行中" ]; then
  echo "❌ /pmai-task-execute 入口拒绝：task 状态为「${CURRENT_STATUS:-未知}」，不是「执行中」。" >&2
  echo "" >&2
  echo "请回到入口前置步骤处理状态，或运行 /pmai-task-status 查看下一步。" >&2
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

如果是 UI 类 task（dev server 在隔离副本里起，命令显式带目录，不 cd 会话）：
1. 在 `$TASK_WORKTREE/prototype` 里启动 dev server，绑定到 task 文件中指定的端口（子 shell：`( cd "$TASK_WORKTREE/prototype" && <dev 命令> )`，或用包管理器的 `--dir` / `--prefix`；用 Bash run_in_background 让它后台跑）
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

实现过程中发现与 `prd.md` / `implementation-design.md` / `docs/modules` / `docs/DESIGN.md` / `docs/PROJECT.md` 等任意文档不一致处，填进审计区「📋 文档偏差」表（四列：文档位置 / 文档原文 / 实际实现 / 建议改法）：

```markdown
| 文档位置 | 文档原文 | 实际实现 | 建议改法 |
|---|---|---|---|
| docs/modules/auth.md 第 15 行 | 使用 JWT 认证 | 改用 Session 认证（因 XX 原因） | 改写为 Session 认证 |
| prd.md §🎯 关键产品决策 #2 | 选用方案 A | 实证 demo 后用户路径走不通 | 改方案 B（理由：...）|
```

无偏差填「无」。close-task 收尾时把本段 promote 成 req `adjustment` 事件；close-req 步骤 1.5 聚合 → doc-update rewrite mode。

**v2 兼容 — 双文件两层分工**（旧 task）：工程层偏差（字段命名 / 接口签名 / 组件路径）写工程合同 §10 文档偏差表；业务层偏差（产品决策 / 需求描述 / 模块功能规格）写 PM 视图「📁 历史档案 → 业务层偏差」表。

**v1 兼容**：所有偏差写入主文件 `## 文档偏差` section（旧版）。

**默认值**：无偏差写「无」（多数 task 没偏差）。

### 步骤 7：写 commit 前 AI 自审 placeholder

实现完毕、执行日志和文档偏差填好后，**不再主动列推荐 review 工具区块**（步骤 11 收口：推荐 review 改作 验收信息块末尾的辅助提示，不当 commit 前必经步骤）。

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

**边界（I-RV1 / I-RV3）**：建完三道审里 AI **自动**跑的只有三道（覆盖审计 `coverage-reviewer` agent / 视觉门 `/design-review` 只截图不改 / 行为审 task-verify 驱动 `/browse`）—— 这三道是「建」的纪律，每 build 自动跑、出口都是给 PM 看的证据，不替 PM 拍板。**探索式 review 工具**（`/review` `/qa` `/qa-only`）仍是 PM 手动旁路，AI 不得自动调，即使是"机械检查"也不要伪装成跑了探索式 review。本 placeholder 只是声明"AI 阶段已结束、PM 可以接手"，不冒名探索式 review。

> **task-verify 不算 review skill**（参 `skills/task-verify/SKILL.md`「I-RV1 边界」表）：UAT 是验证 PM 拍板流程是否通（明确 pass/fail），review 是探索性质量审查（多元 finding）。task-verify 是 task lifecycle 内部 skill（同 task-spec / task-plan / close-task），AI 必须在步骤 7.5 自动调用。

### 步骤 7.3：建完三道审（覆盖审计 + 视觉门 + 行为审，合成一份给 PM）

六步「建」完，AI **自动**跑三道机器审。三道审抓三种不同的病，复用同一次 dev server 起停（别各起各的）。最后**合成一份给 PM 看**（不是三段堆给 PM）。

> **顺序与边界**：覆盖审计是静态读码 diff（不需要 dev server）→ 先跑；视觉门 + 行为审都需要 dev server（步骤 4 已起，没起则起一次复用）。三道审**只报不改**（除 task-verify fail 进反馈循环修代码外），是给 PM 看的证据，不替 PM 拍板。

**编排由 `build-audits.py` 固化**（防漏跑一道 / 各起 dev server / 不合成）。覆盖审计是 agent、视觉门是 gstack skill —— 这两道仍由本 skill 用 Agent / Skill 工具调起（脚本没法当子进程调 LLM）；脚本管「校验输入 + 收齐三道结果 + 合成 + 门禁」：

```bash
# 7.3 开头：校验输入（范围清单 / prototype / dev 端口），建 audits/，打印三道 manifest（每道把规范化结果写哪）
python3 "$PMAI_HOME/scripts/build-audits.py" resolve "$TASK_FILE"
# 缺输入会 fail-loud（如范围清单没产 → 覆盖审计无锚点）；按 manifest 跑 7.3a/b/c，各写 audits/<道>.json
```

#### 7.3a 覆盖审计（coverage-reviewer agent，白纸新鲜视角）

调 `coverage-reviewer` agent，喂它**范围清单**（第二步拍板的范围）+ 本 task 在 `prototype/` 的代码 diff。agent 用范围清单对代码逐项 diff，报每条范围：**建了 / 丢了 / 降级占位**。

- 这是**独立新鲜视角**审计（对标 `analysis-reviewer`），不是 AI 自审 —— 故意不让建代码的 AI 同时当审计员，避开自审盲区。
- 输出三类：✅ 建了 / ❌ 丢了（范围清单有、代码没建）/ ⚠️ 降级占位（建了但是空壳 / 假数据 / 交互没接）。
- **把 agent 结果规范化写** `audits/coverage.json`：`{"items":[{"name","status":"built|missing|degraded","note"}]}`（路径见 resolve manifest）。
- 「丢了」「降级占位」条目进步骤 7.3d 合成报告，由 PM 在体验迭代里决定是否补。

#### 7.3b 视觉门（gstack `/design-review`，只截图不改）

起 dev server 后用 Skill tool 调 gstack `/design-review`，对照项目 `DESIGN.md` 审视觉一致性。

- **只跑审计 + 截图，不自动跑修复 Loop** —— 出口是 PM 一句话 pass / 打回（保住 PM 拍板点）。AI 不替 PM 改视觉。
- 用 `/browse`（headless），禁 `mcp__claude-in-chrome__*`。
- 视觉门 finding（间距 / 层级 / 配色不一致 / AI slop 等）进合成报告；**规范化写** `audits/visual.json`：`{"findings":[{"severity":"P0|P1|P2","desc"}]}`（无不一致写 `{"findings":[]}`）。

#### 7.3c 行为审（验收流程驱动 `/browse`，确定性路径）= 步骤 7.5 task-verify

行为审 = task 自测说明派生的验收流程驱动 `/browse` 走确定性路径，验证「跑得通不通」。这一道由步骤 7.5 的 task-verify 承接（见下）：task-verify 内部就是「读自测说明 → 起/复用 dev server → 调 `/browse` 逐流程跑 → 出 pass/fail + 截图」。

- 区别于 `/qa` 的 AI 探索：行为审是**确定性**走 PM 拍板的流程（明确 pass/fail），每 build 自动跑。
- `/qa` 的 AI 探索式找 bug 是 PM **可选手动**跑的旁路（见附录），AI 不自动跑。
- `audits/behavior.json` 由 **task-verify 步骤 6.5 自己写**（确定性产物 `{"status":"pass|fail|skipped","passed":int,"total":int,"note"}`，本流程不再事后人工转换）；非 UI task = `skipped`。synthesize 缺它会 fail-loud。

#### 7.3d 合成一份给 PM + 体验迭代（AI 主动批量 flag、PM 勾改）

三道结果都规范化写进 `audits/` 后，**调脚本合成**（确定性校验三道齐全，漏跑会 fail-loud 把缺的那道点出来——挡住「漏跑一道还往下走」）：

```bash
python3 "$PMAI_HOME/scripts/build-audits.py" synthesize "$TASK_FILE"
# 产出 audits/synthesis.md（PM 一页报告：覆盖/视觉/行为 + 建议改的项 + gate=clean|needs-review）
# + stdout 机器 summary（各道计数 + gate）
```

AI 把 `synthesis.md` 用 PM 听得懂的话呈给 PM（可加一句 AI 自己看出来、三道审没覆盖的问题），**主动批量列出建议改的项**，让 PM 勾哪些改：

```
建完自查（task-NNN）：
覆盖：范围清单 8 项，建了 6 / 占位 1 / 漏 1
  ⚠️ 「导出 CSV」按钮建了但点了没反应（占位）
  ❌ 「批量删除」没建
视觉：2 处和 DESIGN.md 不一致
  • 卡片间距 12px，规范是 16px
  • 主按钮用了非规范的橙色
行为：验收流程 3/4 通过；失败：「提交后跳转结果页」没跳

要不要我现在一起改？（你勾哪些，我改哪些）
```

- **AI 主动 flag、PM 勾改** —— 不是 AI 静默全改，也不是 PM 自己逐个找问题。AI 把发现摊开，PM 拍哪些值得改。
- PM 勾的项 → AI 按 §反馈循环规则改 `prototype/` 代码（不动 task md 业务字段；步骤 5 写「文档对齐预告」）→ 重新跑三道审。
- **停止条件**：demo 成功标准达到 + PM 在步骤 12 呈交闸门拍板。磨不动（反复改不到位）→ 上抛回第二步重新收范围，别在 build 里死磕。
- **行为审 fail（task-verify exit 1）** 的处理见步骤 7.5（不 commit、进反馈循环、连续 3 次 fail 呈交 PM）。

### 步骤 7.5：调 task-verify 跑流程化 UAT（= 行为审；UI task 必经，非 UI task 跳过）

**触发条件**：task md 「🧪 自测说明」段非空且不是「无」。

**流程**：Claude 主端用 Skill tool 调 `task-verify`，参数为 `$TASK_FILE`。task-verify 内部读自测说明 + 复用 task-execute 步骤 4 起的 dev server（不在跑则自起）+ 调 `gstack-browse` 逐流程跑 + 写 `.pm-workflow/tasks/<task-stem>/verify/report.md`。

**结果分流**：

- **pass**（exit 0）→ **不停 / 不汇报 / 不写交接块**，把这一道结果并进步骤 7.3d 合成报告，自动接步骤 10 commit → 步骤 11 呈交 PM 验收**一气走完**；执行日志（步骤 5）append 一行「task-verify: ✅ N/N 流程通过」。**verify pass 不是 PM 节点**，PM 唯一的决策点是步骤 11 的呈交块；在此处停下来写 `STATUS: DONE` / `RECOMMENDATION: 回前面步骤继续走` 等于自说自话宣告 task 完成（task 还没 commit、PM 还没看过任何东西），是常见跑偏模式
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
# 收集改动摘要（从最近一条「执行报告」section 提取；$TASK_FILE 是绝对路径）
SUMMARY=$(awk '/^### 执行报告/{flag=1} flag && /^\*\*改动摘要/{sub(/\*\*改动摘要：\*\*\s*/,"");print;exit}' "$TASK_FILE")
[ -z "$SUMMARY" ] && SUMMARY="实现 $(basename "$TASK_FILE" .md)"

git -C "$TASK_WORKTREE" add -A
git -C "$TASK_WORKTREE" commit -m "task-${TASK_ID}: ${SUMMARY}"
```

Dev server 保持运行（PM 验收时需要访问）。

**Commit 后不退出 skill** —— 直接进步骤 11 呈交验收（单窗口走完建 → 审 → 呈交）。

### 步骤 11：呈交 PM 验收（合并自 task-submit）

> 默认路径：commit 后**自动**呈交，PM 不需手动敲 `/pmai-task-submit`。task 状态全程「执行中」，commit 不切状态。
> 兜底入口：PM 在异常情况（窗口被关 / context 丢失 / 重启 IDE）下仍可手动跑 `/pmai-task-submit`，逻辑等价。

详见 [`references/acceptance-handoff.md`](./references/acceptance-handoff.md)：
- 11.1 组装验收信息包（读 task 文件 + diff + review_completed 事件 + UI/非 UI 判定）
- 11.2 输出验收信息块（UI 类 / 非 UI 类两种模板，含可选深度审查辅助提示）
- 11.3 走查时引导 PM 反推上游文档偏差（reverse-flow 到「📁 历史档案 → 业务层偏差」表）

### 步骤 12：等待 PM 决策（AskUserQuestion picker）

呈交块（步骤 11 输出）后，AI 调 AskUserQuestion：
- `question`: "task-NNN 验收？"
- `options`:
  - `label`: `通过`
    `description`: `task 转「已完成」，进 /pmai-close-task`
  - `label`: `打回`
    `description`: `task 保持「执行中」，AI 基于反馈继续修；说哪里要改`

**PM 选 `通过`**（或输 `1` / 输 "OK / 通过 / 没问题"）：
```bash
python3 "$PMAI_HOME/scripts/task-transition.py" "$TASK_FILE" --to 已完成
```

`task-transition.py` 在「执行中→已完成」入口校验文档偏差 + 自审记录非空（I-TT3）；不通过会拒绝转换，PM 需先补齐再喊通过。

然后 **AI 自动接 `/pmai-close-task task-NNN` 收尾链**（验收通过即自动续跑，与 close-task「demo 验收通过后 AI 自动跑完整链、PM 不切窗口」一致）。输出按 [banner-rules §2.5 内容禁忌](../_shared/pm-view/banner-rules.md#25-内容禁忌pm-facing-输出禁工程黑话与内部原理) — 不写 Phase 1/2、不写 merge / worktree / auto-chain 等内部术语、不解释 AI 为啥这样安排：

```text
✅ task-NNN 通过验收，已转「已完成」。

▶ Next Up：正在自动收尾这个 task，完成后接着往下推进 —— 你不用动手。
```

> 异常兜底：若自动收尾没触发（窗口关了 / context 丢了），PM 手动跑 `/pmai-close-task task-NNN` 从断点续跑即可，无需切窗口。

**PM 选 `打回`**（或输 `2` / 提具体反馈 / 输 "打回 / 改一下 / 不对"）：

> 打回**不切状态** — task 全程是「执行中」，AI 直接基于反馈继续修，不再走 `task-transition --to 执行中` 的回退（该 transition 已删除，I-TT4 废弃）。

1. 记录 PM 反馈到 task 文件「📁 历史档案 → PM 反馈」（v3 在审计区；v2 写 PM 视图主文件、**禁止**写入工程合同）：
   ```markdown
   ### 反馈 N - [YYYY-MM-DD]
   **问题描述：** [PM 原话]
   **要求修改：** [具体修改要求]
   **处理结果：** 待处理
   ```

   PM 反馈留在本段不归类。后续同 req 的 task 由 task-spec 按 relevance 二分（适用 / 不适用）承接进新 task 的「PM 反馈承接清单」；视觉规范类 / 全项目跨功能产品规则由 close-task 收尾时按目标 promote（参 task 文件「📁 历史档案 → PM 反馈」段内的 close-task 说明）。

2. 应用 §反馈循环规则（实现前必做下方）：按规则只改原型代码，不动 task md 业务字段；步骤 5 执行报告里写「文档对齐预告」。文档对齐统一交给 close-task §0。

3. 修复完毕后**追加 fix commit**（保留主 commit + fix commit 的 diff 历史，close-task merge 时统一进 req 分支；commit message 模板：`task-NNN fixup: <一句话>`）。

4. 重新呈交（重新走步骤 11/12），等待 PM 通过/再打回。

### 附录：PM 验收阶段跑 review（旁路 — 非必经）

PM 在验收期间任意时刻可自跑 `/review` `/qa` `/design-review` 等 review 工具；AI 仍**不得**自行调用（I-RV1）。PM 报告结论后 AI 机械执行：在 task 文件「🔍 自审记录」段追加自审记录（v3 在审计区；v2 在工程合同 §11）+ append `review_completed` 事件（I-RV2）。详见 [`references/review-bypass.md`](./references/review-bypass.md)。

## Rules

- **build 由独立执行器干、驱动只编排**：build 派发给 PM 指定的执行器（`claude-code` = 独立 subagent / `codex` / `cursor-agent` / `gemini` = 独立 CLI），都在 task 隔离副本沙盒里独立建；驱动不 inline 建（隔离 + 角色分离）。取值见 task 卡 `executor` 字段 / settings 默认
- **单窗口 / 显式目录**：驱动的编排命令不 `cd` 进 task 隔离副本、不依赖会话 cwd；git 用 `git -C "$TASK_WORKTREE"`，构建 / dev 用子 shell `( cd "$TASK_WORKTREE/prototype" && … )`（单次 Bash 调用内 cd 有效）。PM 全程不切窗口、不开新会话、不必 `claude --add-dir`
- task 文件用绝对路径读写（task worktree 中的路径和主仓路径不同）
- 代码改动在 task worktree 中进行
- 文档（docs/）不在 task worktree 中修改（hook 会拦截）
- 文档偏差记录到 task 文件，由 `/pmai-doc-update` 在 close-task 前处理
- **建完三道审 AI 自动跑**（六步「建」纪律，I-RV1 不适用）：覆盖审计 `coverage-reviewer` agent（步骤 7.3a）/ 视觉门 `/design-review` 只截图不改（步骤 7.3b）/ 行为审 task-verify 驱动 `/browse`（步骤 7.5）。三道审只报不改、出口都是给 PM 看的证据
- AI 不得自动调**探索式** review 工具（`/review` `/qa` `/qa-only`，I-RV1）；这些仅作步骤 11 验收信息块末尾「⚙️ 可选深度审查」辅助提示，PM 自取所需
- **task-verify 例外**：UI task 在步骤 7.5 **必须**调 task-verify（流程化 UAT，行为审；不属于探索式 review 范畴，I-RV1 不适用）；fail → 反馈循环 + 不 commit；连续 3 次 fail 呈交 PM 人工接手
- PM 报告 review 结论后才 append `review_completed` 事件（I-RV3）；禁止 AI 替 PM 跑或凭记忆模拟
- 事件流缺 review_completed 不阻止「执行中→已完成」转换（I-RV2）
- dev server 在 task-execute 结束后保持运行，直到 close-task 时杀掉
- **commit 不切状态 → 自动进步骤 11 呈交验收**（task 状态全程「执行中」直到 PM 通过；默认路径，PM 不手动敲 `/pmai-task-submit`）；PM 通过后 AI 转「已完成」并**自动接 `/pmai-close-task task-NNN` 收尾链**（单窗口跑完对齐 + 沉淀 + 并回 + 清理，不切窗口、不分两阶段；close-task 异常恢复入口留给中断兜底）
- PM 打回不切状态：写反馈到 task 文件「📁 历史档案 → PM 反馈」（v3 审计区 / v2 PM 视图）→ AI 修代码 → 追加 fix commit → 重新呈交（不再走 `--to 执行中` transition）
- task-submit 仍存在但仅作 PM 手动兜底入口（重启窗口 / context 丢失 / 异常退出后重新呈交）
