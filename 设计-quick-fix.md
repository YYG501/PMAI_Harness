<!-- /autoplan restore point: <LOCAL_GSTACK_HOME>/projects/PM-AI-Workflow/main-autoplan-restore-20260423-170828.md (Phase 3 + 3.5 only) -->
# /quick-fix 设计文档

> **状态**：v2 定稿，待实现
> **版本**：v2（经 autoplan Phase 3 Eng Review 修订）
> **更新时间**：2026-04-23
> **相关文档**：设计.md（框架主设计）、INVARIANTS.md（关键脚本不变式）

## 版本变更（v1 → v2）

v1 经 autoplan Phase 3 Eng Review（Claude subagent + Codex 独立审阅），识别出 3 个 critical + 4 个 high 级架构/安全问题。v2 修订内容：

1. **架构模型重换**：ff-only + amend QUICKFIX_LOG 自引用 hash → 两提交 ff-only 模型（§4、§7）
2. **放弃入库 LOG**：QUICKFIX_LOG.md 不入库，改用 `git log --grep` 反查 + `/quick-fix --history` 生成动态 view（§7）
3. **红线扩展**：整个 `tasks/*.md` + 整个 `.req-meta.json` 禁改，不仅状态/stage 字段（§3）
4. **并发 rebase 路径**：ff-only 失败自动 rebase + retry，手动回退（§4、§10.2）
5. **路径/分支名注入防护**：分支名完全脚本生成、描述 sanitize、realpath 校验 worktree 逃逸（§5、§10.3）
6. **实现清单扩展**：修改 `CLAUDE.md.tmpl` 声明例外、加 `--cancel` / `--cleanup` / `--history` / `--skip-tsc` 子命令（§9）
7. **tsc opt-out**：`--skip-tsc` flag 让大型 TS 项目可跳过（§6）
8. **命名一致**：worktree 目录名 = 分支名（`tmp-quick-<ts>-<pid>`）（§5）
9. **测试补全**：§11 从 6 场景扩到 17 场景

审阅详情见 §13。

---

## 1. 背景与动机

框架当前规定：任何改动都必须走 `/new-req` → stage 1-7 → task 流程。对实质性需求这是合理的，但对**小改动**（错别字、格式、常量值、单个样式等）成本过高：

- 建 req 目录 / worktree / 分支 / task 文件 / event log
- 跑 stage 1-4 确认门
- stage 5 写 task-plan
- stage 6 task 执行 + 自审
- close-task → close-req → merge

十几步操作换一个错别字修正，PM 体感很重。

**旁路 1（PM 手动改）**：绕过 hook 自己编辑 + git commit。可以做，但：
- AI 不参与，PM 要自己动手
- 破坏"AI 必须走流程"的约束边界
- 无结构化历史

**旁路 2（临时分支 hack）**：`git checkout -b tmp-xxx` → AI 改 → merge。可以做，但每次手工建/删分支，没有自动检查。

**方案**：加一条**不走 req 流程**的合法快捷路径，让 AI 可以在受约束的小范围内直接改 main 上的文件。

---

## 2. 定位

`/quick-fix` 是 **req 流程之外**的快捷路径。三条：

1. **不限文件类型**。docs、代码、配置、CLAUDE.md 都可走
2. **硬边界只守数据完整性红线**，不替 PM 判断"大小"
3. **大小判断交给 PM**

不是为"文档小改"设计的专用工具，是**"不需要完整 req 流程的改动"**的通用快捷路径。

---

## 3. 硬边界（红线）

skill 内部强制检查，命中任何一条直接拒绝执行：

| # | 红线 | 原因 |
|---|------|------|
| 1 | **不能修改 `requirements/active/*/tasks/*.md` 整个文件**（不仅状态字段） | Task 执行中的 acceptance criteria、执行日志、自审记录等都由 AI 在 task worktree 中维护，quick-fix 改动会静默分叉 |
| 2 | **不能修改 `requirements/active/*/.req-meta.json` 整个文件**（不仅 stage） | Req 元数据由 req-transition.py 独占维护，stage_history、status、branch 等字段一处错全流程错 |
| 3 | 不能修改 `.claude/scripts/` / `.claude/skills/` / `.claude/settings.json` | 框架层改动应回 PM-AI-Workflow 仓，而不是单个业务项目 |
| 4 | 当前有活跃 req 时**事前检测并 warn**，事后 ff-only 失败时**自动 rebase retry** | 活跃 req close 时会推进 main，可能跟 quick-fix 冲突。warn + rebase 路径处理（见 §4） |

**v2 变更**：
- 红线 1/2 **范围扩到整个文件**（v1 只挡字段）。理由：改 task acceptance criteria 静默破坏运行中的 task；改 `.req-meta.json` 任何字段都可能破坏状态机。
- 红线 4 从"只 warn"升级为"warn + 自动 rebase 路径"（见 §4）。

> 红线 1/2 的字段级检查本来就被 `check-branch.sh` 的 Gate 1/2 强制。v2 扩到整个文件是 quick-fix 额外加的约束。

**其他一切都允许**：行数不限、文件数不限、可新增文件、可改代码、可改文档。

---

## 4. 工作流时序（v2 — 两提交 ff-only 模型）

```
PM: /quick-fix "<一句话描述>"

Skill 事前检查：
  - 校验当前在主仓根（不在 req/task worktree 中）
  - 扫描红线 3 路径（事前拒绝）
  - 活跃 req 检测 → warn "当前有 req-NNN 活跃，ff-only 可能失败需 rebase"
  - 记录 MAIN_HEAD = $(git rev-parse main)
  - 扫描 .worktrees/tmp-quick-* 残留，列出给 PM 决定清理

Skill sanitize 输入：
  - desc 剥离 | newline backtick $ ;  ...（见 §5.4）
  - 校验 sanitize 后非空

Skill 建隔离环境：
  - TS=$(date +%Y%m%d-%H%M%S)-$$   # 加 PID 后缀避免同秒碰撞
  - BRANCH=tmp-quick-$TS
  - WORKTREE=.worktrees/$BRANCH    # 目录名 == 分支名
  - git worktree add -b "$BRANCH" "$WORKTREE" main
  - 复用 create-task-worktree.sh 的 symlink 策略（抽成 _setup_deps.sh 工具函数被两者 source）
  - realpath "$WORKTREE" 必须以 "$REPO_ROOT/.worktrees/" 开头（防逃逸）

AI 执行改动（在 worktree 内）：
  - cd $WORKTREE
  - Edit/Write 改文件
  - （hook: 分支是 tmp-quick-*，不匹配任何 Gate，放行）
  - AI **不能**从 worktree 去写主仓路径（check-branch.sh 会把跨 worktree 写归到 main 分支拦截）

Skill 事后检查：
  - git diff --name-only 看改动路径
  - 命中红线 1/2/3 → deny + 清理环境
  - 改了 .ts / .tsx / .mts / .cts → tsc --noEmit（除非 PM 传 --skip-tsc）
    - 失败 → 输出错误，让 PM 选：重改 / 取消 / 强制通过（--force）

Skill 呈交 PM：
  - 输出完整 diff
  - 等 PM："通过" / "重做" / "取消"

PM 通过后（两提交 ff-only 模型）：
  a. 在 worktree 内提交改动
     git add -A
     git commit -m "[quick-fix] <sanitized desc>

     目标: <files>
     变更: +N -M 行
     临时分支: $BRANCH"
     CHANGE_SHA=$(git rev-parse --short HEAD)

  b. 追加一行到 worktree 内的 QUICKFIX_LOG.md（如果启用，见 §7）
     记录: 时间 / 目标 / 描述 / CHANGE_SHA（稳定，不自引用）
     git add QUICKFIX_LOG.md
     git commit -m "[quick-fix-log] $CHANGE_SHA <desc>"

  c. 切回主仓，尝试 ff-only merge
     cd $REPO_ROOT
     if git merge --ff-only "$BRANCH"; then
       MERGE_OK=true
     else
       # main 前进了（concurrent close-req、其他 quick-fix 等）
       # 回到 worktree 尝试 rebase main，然后 retry
       (cd "$WORKTREE" && git fetch . main:_tmp_main && git rebase _tmp_main && git branch -D _tmp_main)
       if git merge --ff-only "$BRANCH"; then
         MERGE_OK=true
       else
         # rebase 冲突或其他异常 → 保留 worktree 让 PM 手工处理
         echo "merge 失败。worktree 保留在 $WORKTREE，请手工 rebase/cherry-pick"
         exit 1
       fi
     fi

  d. MERGE_OK=true 后清理
     git worktree remove "$WORKTREE"
     git branch -d "$BRANCH"

PM 重做：保留 worktree 和分支，让 AI 按反馈重改
PM 取消：git worktree remove --force + git branch -D
```

**v2 变更**：
- **删除 amend 步骤**：v1 的"merge 后 amend QUICKFIX_LOG 进 merge commit"会破坏 ff 关系和 commit hash 自引用。
- **两提交模型**：worktree 内先 commit 改动（拿到稳定 CHANGE_SHA），再 commit LOG（引用 CHANGE_SHA）。ff-only 一次性带两个 commit 进 main。
- **并发 rebase retry**：ff-only 失败时自动 rebase + retry。rebase 冲突才回退到 PM。
- **MAIN_HEAD 记录**：开始时记录，确保 diff 锚点不漂移。

---

## 5. 隔离机制（worktree）

### 5.1 为什么要隔离

PM 的 dev server 可能在主仓 main 分支上运行。用 worktree 做隔离：主仓 main 分支不动，dev server 不受影响。

### 5.2 目录与分支命名（v2 一致化）

- **目录**：`.worktrees/tmp-quick-<ts>-<pid>/`
- **分支**：`tmp-quick-<ts>-<pid>`
- **ts 格式**：`$(date +%Y%m%d-%H%M%S)`（ISO 风格，非 unix-ts）
- **pid 后缀**：`$$`（避免同秒并发碰撞）

目录名和分支名**完全一致**，避免 check-branch.sh 的 EFFECTIVE_BRANCH 推导歧义。

### 5.3 依赖 symlink

抽取 `scripts/_setup-deps.sh` 工具函数，被 `create-task-worktree.sh` 和 `quick-fix.sh` 共同 source：
- `package.json` → symlink `node_modules`（含 monorepo 递归）
- `Gemfile` → symlink `vendor/bundle`
- `go.mod` → symlink `vendor`

### 5.4 输入 sanitize（v2 新增）

分支名完全脚本生成，**不吃用户任何输入**。用户 desc 只进 commit message 和 QUICKFIX_LOG 摘要，进之前 sanitize：

```bash
sanitize_desc() {
  local raw="$1"
  # 剥离破坏 markdown 表格的字符
  local out="${raw//|/｜}"
  # 剥离可能 shell 注入的字符
  out="${out//\`/}"
  out="${out//\$/}"
  out="${out//;/,}"
  # 单行化（剥离 newline）
  out=$(echo "$out" | tr -d '\n\r')
  # 长度限制（防过长 commit message title）
  echo "${out:0:120}"
}
```

### 5.5 路径逃逸防护（v2 新增）

```bash
WORKTREE=$(realpath -m "$REPO_ROOT/.worktrees/$BRANCH")
case "$WORKTREE" in
  "$REPO_ROOT/.worktrees/"*) ;;
  *) echo "worktree 路径逃逸: $WORKTREE" >&2; exit 1 ;;
esac
```

### 5.6 清理

| 情况 | 操作 |
|------|------|
| 正常 merge 成功 | `git worktree remove` + `git branch -d` |
| PM 取消 | `git worktree remove --force` + `git branch -D` |
| merge 失败（rebase 冲突） | 保留 worktree 和分支，提示 PM 手工处理 |
| 前次崩溃残留 | 下次 `/quick-fix` 启动时扫 `.worktrees/tmp-quick-*`，列给 PM。也可 `/quick-fix --cleanup` 批量清 |

---

## 6. 自动检查：tsc 兜底

### 6.1 触发条件

改动涉及 `.ts` / `.tsx` / `.mts` / `.cts` 文件时自动触发。

### 6.2 命令（在 worktree 内）

```bash
bun tsc --noEmit   # 或 npx tsc --noEmit，按项目包管理
```

### 6.3 失败处理

- tsc 返回非零 → skill 拒绝 merge
- 输出 tsc 错误给 PM
- PM 选择：让 AI 重改 / 取消 / 强制通过（`--force`）

### 6.4 opt-out（v2 新增）

`/quick-fix --skip-tsc "<desc>"`：跳过 tsc 检查。适用于：
- 大型 Next.js / monorepo 项目 tsc 30 秒+
- PM 确信改动不影响类型（纯样式、纯 docs、纯常量）
- tsc 因 symlinked node_modules 偶发误报

### 6.5 为什么要这道护栏

眼看 diff 难发现类型错误（比如改 interface 字段名没改所有引用）。tsc 秒发现。

---

## 7. 历史记录（v2 重设计）

### 7.1 设计决策

v1 计划把 `QUICKFIX_LOG.md` 作为入库 append-only 文件。v2 **放弃**这个方案，因为：

- **冲突磁铁**：每次 quick-fix 都改同一文件，跟任何 req 分支都易冲突
- **自引用 hash 不可能**：想在 commit 里记录自己的 commit hash 物理上做不到

v2 改为 **git log + 动态 view** 方案：

### 7.2 commit message 规范

每个 quick-fix 在 main 上留下**两个 commit**：

**Commit A（改动）**：
```
[quick-fix] <sanitized desc>

目标: <改动文件列表>
变更: +N -M 行
临时分支: tmp-quick-<ts>-<pid>
```

**Commit B（日志）**：
```
[quick-fix-log] <commit-a-short-sha> <desc>
```

前缀 `[quick-fix]` 和 `[quick-fix-log]` 是识别标志。

### 7.3 动态 view

**`/quick-fix --history [N]`**：打印最近 N 条（默认 10）quick-fix 记录：
```bash
git log --grep '^\[quick-fix\]' --format='%h %ci %s' -$N
```

输出格式：
```
abc1234 2026-04-23 15:10 [quick-fix] INDEX.md 更新 025 状态
def5678 2026-04-23 14:30 [quick-fix] Button.tsx padding 16→24
```

**`/status` 增强**：无活跃 req 时显示"最近 3 条 quick-fix"；有活跃 req 时作为附加 section 显示。

### 7.4 入库 summary 文件（可选，默认关）

PM 如果坚持要一份 reviewable 入库文件，`/quick-fix --snapshot` 可以**按需生成** `QUICKFIX_LOG.md`：

```bash
/quick-fix --snapshot   # 调用 git log，生成 QUICKFIX_LOG.md，一次性 commit
```

这是**快照**（不是持续维护的），生成后可以 commit 进 main 作为"截至 X 时间的历史"。不参与 quick-fix 主流程，没有冲突磁铁问题。

**默认不启用这个命令**——git log 本身就是 authoritative 源，snapshot 只是 readable view。

---

## 8. 与 /new-req 的分界

skill **不**替 PM 判断，由 PM 自行判断：

| 场景 | 建议 |
|------|------|
| 错别字、标点、格式 | `/quick-fix` |
| 补一段说明、加一个链接 | `/quick-fix` |
| 改常量值、单个样式 | `/quick-fix` |
| 删少量死代码 | `/quick-fix` |
| 改 1-2 行逻辑（你确信） | `/quick-fix` |
| 跨多文件的功能改动 | `/new-req` |
| 新增一个完整模块 | `/new-req` |
| 实质性改架构决策 | `/new-req` |
| 需要自审（/qa、/review、/design-review）才放心 | `/new-req` |
| 需要 PM 仪式感地验收 | `/new-req` |

指南不是硬规则。PM 判断失误了，框架不兜底。

---

## 9. 实现清单（v2 扩展）

### 9.1 新增

| 文件 | 功能 |
|------|------|
| `scripts/quick-fix.sh` | skill 主入口，子命令：`<desc>` / `--skip-tsc` / `--force` / `--cancel <branch>` / `--cleanup` / `--history [N]` / `--snapshot` |
| `scripts/_setup-deps.sh` | symlink 工具函数（抽自 `create-task-worktree.sh`，被它和 quick-fix.sh 共同 source） |
| `skills/quick-fix/SKILL.md` | Claude Code skill 定义（preamble + 引导 AI 在 worktree 里工作 + 禁止写主仓路径） |

### 9.2 修改

| 文件 | 修改点 |
|------|--------|
| `scripts/create-task-worktree.sh` | 抽依赖 symlink 逻辑到 `_setup-deps.sh`，source 之 |
| `scripts/status-view.py` | 加 `render_quickfix_section()`，在**有/无活跃 req 两条路径都调用**（不能放在 early-return 后面） |
| `scripts/skill-preamble.sh` | 加残留 worktree 扫描:`.worktrees/tmp-quick-*` |
| `templates/CLAUDE.md.tmpl` | 在"分支结构"节声明 /quick-fix 是"唯一例外"；在"gstack"节或单独列出 /quick-fix 可用 |
| `scripts/init-project.sh` | 无需改——v2 不再入库 QUICKFIX_LOG.md |

### 9.3 不需要改

- `scripts/check-branch.sh`：`tmp-quick-*` 分支天然不匹配 Gate 3/4（已验证）。**但 AI 从 worktree 写主仓路径仍会被按 main 分支拦**，这是正确行为，不要动
- `templates/gitignore.tmpl`：QUICKFIX_LOG.md 不入库，不需要加白名单

---

## 10. 未决问题 / 边界情况

### 10.1 活跃 req 时的并发

quick-fix 在 main 上推一个 merge，同时 PM 在 req worktree 里做事。close-req 会 merge req 回 main，可能跟 quick-fix 冲突。

**处理（v2）**：
- quick-fix 事前检测活跃 req，warn PM
- ff-only 失败时自动 rebase + retry
- rebase 仍冲突 → 保留 worktree，提示 PM 手工 rebase 或放弃
- close-req 侧**不加**特殊逻辑，由 close-req.sh 的正常冲突处理走

### 10.2 ff-only 失败的 rebase 路径

自动尝试 `git rebase main`，成功则 retry ff-only。rebase 冲突保留 worktree，提示：

```
merge 失败（rebase 冲突）。worktree 保留在 .worktrees/tmp-quick-<ts>-<pid>。
可选：
  1. 手工解决冲突：cd .worktrees/tmp-quick-<ts>-<pid> && git rebase --continue
  2. 放弃本次 quick-fix：/quick-fix --cancel tmp-quick-<ts>-<pid>
```

### 10.3 worktree 残留

触发：skill 中途崩溃、用户强杀、rebase 冲突未解决。

**处理**：
- `skill-preamble.sh` 启动时扫 `.worktrees/tmp-quick-*`，列给 PM
- 也可显式 `/quick-fix --cleanup`：批量清理所有 `tmp-quick-*` worktree（有未 commit 改动的 warn 再清）

### 10.4 tsc 性能

Next.js / 大型 TS 项目 tsc 可能 30 秒+。

**处理（v2）**：
- 加 `--skip-tsc` flag 让 PM 显式跳过
- 未来 v3 考虑 `--incremental` 或只检查改动文件

### 10.5 PM 在 worktree 里手工改完忘了让 skill merge

**处理**：SKILL.md 明确写"改完必须通过 skill 收口"。skill-preamble.sh 扫残留时会提醒。

### 10.6 `/quick-fix --cancel <branch>` 和 `--cleanup` 的 spec（v2 新增）

**`--cancel <branch>`**：
- 验证 `<branch>` 以 `tmp-quick-` 开头
- 确认 worktree 存在
- 未 commit 改动 warn 一下
- `git worktree remove --force` + `git branch -D`

**`--cleanup`**：
- 枚举所有 `tmp-quick-*` worktree
- 列表给 PM：每个 worktree 的 ts / pid / 未提交改动数量
- PM 确认后批量清理

---

## 11. 测试清单（v2 扩展到 17 场景）

**Happy path**：
1. 纯文档改（docs/xxx.md）→ 成功 merge
2. 纯代码改（.ts 文件）→ tsc 通过 → 成功 merge
3. 混合改（docs + 代码）→ 成功 merge

**tsc 路径**：
4. tsc 失败 → 拒绝 merge，worktree 保留
5. `--skip-tsc` → 跳过 tsc 检查
6. `--force` → tsc 失败也强制 merge

**边界情况**：
7. 活跃 req 时的 warn + ff-only 成功路径
8. 活跃 req + close-req 并发，ff-only 失败 → 自动 rebase → retry 成功
9. rebase 冲突 → 保留 worktree，提示 PM 手工处理
10. 同秒并发两次 `/quick-fix` → PID 后缀区分，两次独立跑通

**红线触发**：
11. 改 `requirements/active/*/tasks/*.md` → 拒绝
12. 改 `.req-meta.json` → 拒绝
13. 改 `.claude/scripts/xxx.sh` → 拒绝

**取消与清理**：
14. PM 取消（审阅时说"取消"）→ worktree 和分支清理干净，main 不变
15. `/quick-fix --cancel tmp-quick-xxx` → 指定 branch 清理
16. `/quick-fix --cleanup` → 批量清理残留

**安全与注入**：
17. desc 含 `| newline backtick $` 等 → sanitize 后进 commit，不破坏 markdown 表格或 shell 执行

### 每个场景的测试文件

`tests/quick-fix/`：
- `test-happy-path.sh`
- `test-tsc-gate.sh`
- `test-concurrent-req.sh`
- `test-redline-enforcement.sh`
- `test-cleanup.sh`
- `test-sanitize.sh`

---

## 12. 实现顺序

| 批次 | 内容 |
|------|------|
| 1 | `scripts/_setup-deps.sh` 抽取依赖 symlink 逻辑，`create-task-worktree.sh` 切过去用，跑现有 task 测试确保无回归 |
| 2 | `scripts/quick-fix.sh` 主脚本（含 sanitize、两提交模型、rebase retry、所有子命令） |
| 3 | `skills/quick-fix/SKILL.md` |
| 4 | `scripts/status-view.py` 加 `render_quickfix_section()`，覆盖有/无活跃 req 两分支 |
| 5 | `scripts/skill-preamble.sh` 加残留 worktree 扫描 |
| 6 | `templates/CLAUDE.md.tmpl` 增声明 /quick-fix 例外 |
| 7 | 测试 17 场景（见 §11） |

---

## 13. Review 发现与决议（v2 新增）

autoplan Phase 3 Eng Review 结论：v1 架构有 3 个 critical + 4 个 high 级问题。逐条决议：

| # | v1 问题 | 严重度 | 发现者 | v2 决议 |
|---|---------|--------|--------|---------|
| 1 | ff-only + amend QUICKFIX_LOG 组合破坏 ff 关系 | Critical | Claude + Codex | §4 改两提交模型 |
| 2 | ff-only 在 concurrent close-req 时失败 | Critical | Claude + Codex | §4 加 rebase + retry 路径 |
| 3 | v1 §4 时序漏了"先 commit tmp-quick-*" | Critical | Codex | §4 明确 commit 步骤 |
| 4 | QUICKFIX_LOG.md 是冲突磁铁 | High | Claude | §7 放弃入库，改 git log 反查 + 动态 view |
| 5 | 红线只挡 task 状态字段、req stage 字段不够 | High | Claude | §3 扩到整个 tasks/*.md + 整个 .req-meta.json |
| 6 | CLAUDE.md.tmpl 必须更新声明例外 | High | Codex | §9 加入实现清单 |
| 7 | 路径/分支 ref 注入未防 | High | Codex | §5.4 sanitize + §5.5 realpath 逃逸防护 |
| 8 | timestamp 同秒碰撞 | Medium | Claude + Codex | §5.2 加 PID 后缀 |
| 9 | status-view.py 无活跃 req 时早退 | Medium | Codex | §9 明确独立函数、两分支都调 |
| 10 | tsc 在大项目慢 | High | Claude | §6.4 加 --skip-tsc opt-out |
| 11 | worktree 目录名 vs 分支名不一致 | Medium | 我 (scope challenge) | §5.2 统一 |
| 12 | --cancel / --cleanup 未 spec | Medium | Claude | §10.6 显式 spec |
| 13 | skill-preamble.sh 要扫残留 worktree | Medium | 我 (scope challenge) | §9 加入实现清单 |
| 14 | §11 测试覆盖 ~40% | High | Claude + Codex | §11 扩到 17 场景 |

**未决（未在 v2 处理，标记到 §10）**：
- tsc `--incremental` 或按文件粒度检查（v3）
- close-req 侧是否加 quick-fix 感知（暂不加，由 close-req 的通用冲突处理走）

---

## 14. 决策记录

| # | 问题 | 决策 | 理由 |
|---|------|------|------|
| 1 | 走不走 req stage？ | 不走。独立快捷路径 | 避免 req/task 目录爆炸 |
| 2 | 允许改哪些文件？ | 不限类型，只守红线 | "文件类型"不是好边界，"数据完整性"才是 |
| 3 | 改动大小上限？ | 不设 | PM 自己判断 |
| 4 | 代码改动要不要兜底？ | 要，tsc --noEmit（可 --skip-tsc opt-out） | 眼看 diff 难发现类型错 |
| 5 | 要不要 worktree 隔离？ | 要 | 主仓 main 不动，dev server 不受影响 |
| 6 | 历史怎么留？ | 两 commit + `[quick-fix]` 前缀 + git log 反查 + `/quick-fix --history` 动态 view | 不建新目录，git 本身是 authoritative 源。放弃入库 LOG（v1 方案）避免冲突磁铁和 hash 自引用 |
| 7 | 跟 /new-req 怎么分？ | 给指南表，不给硬规则 | 判断交给 PM |
| 8 | 改 hook 吗？ | 不改 | `tmp-quick-*` 天然不被任何 Gate 拦 |
| 9 | amend 还是两提交？ | **两提交**（v2） | amend 破坏 ff 关系，hash 自引用物理上不可能 |
| 10 | 并发冲突怎么办？ | **自动 rebase + retry**（v2） | PM 单线程不是硬保证（close-req 会推 main） |
| 11 | 分支名受用户输入影响吗？ | 不。完全脚本生成 | 防 ref 注入 |
| 12 | QUICKFIX_LOG.md 入库吗？ | **不入库，按需快照**（v2） | 避免冲突磁铁，git log 本身就够 |
