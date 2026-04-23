# /quick-fix 设计文档

> **状态**：已定稿，待实现
> **更新时间**：2026-04-23
> **相关文档**：设计.md（框架主设计）、INVARIANTS.md（关键脚本不变式）

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
- 破坏"AI 必须走流程"的约束边界（AI 会学到"小事可以绕"）
- 无结构化历史

**旁路 2（临时分支 hack）**：`git checkout -b tmp-xxx` → AI 改 → merge。可以做，但：
- 每次手工建/删分支
- 没有自动检查
- 没有统一历史

**方案**：加一条**不走 req 流程**的合法快捷路径，让 AI 可以在受约束的小范围内直接改 main 上的文件。

---

## 2. 定位

`/quick-fix` 是 **req 流程之外**的快捷路径。定位三条：

1. **不限文件类型**。docs、代码、配置、CLAUDE.md 都可走
2. **硬边界只守数据完整性红线**，不替 PM 判断"大小"
3. **大小判断交给 PM**。PM 觉得这事需要仪式感就走 `/new-req`，觉得没必要就 `/quick-fix`

不是为"文档小改"设计的专用工具。是**"不需要完整 req 流程的改动"**的通用快捷路径。

---

## 3. 硬边界（4 条红线）

skill 内部强制检查，命中任何一条直接拒绝执行并提示改走 `/new-req` 或 transition 脚本：

| # | 红线 | 原因 |
|---|------|------|
| 1 | 不能修改 `requirements/active/*/tasks/*.md` 里的 `**状态：**` 字段 | Task 状态必须经 `task-transition.py`，否则事件流会不一致 |
| 2 | 不能修改 `requirements/active/*/.req-meta.json` 里的 `stage` 字段 | Req stage 必须经 `req-transition.py`，否则 stage_history 会不一致 |
| 3 | 不能修改 `.claude/scripts/` / `.claude/skills/` / `.claude/settings.json` | 框架层改动应该回到 PM-AI-Workflow 仓做，而不是在单个业务项目改 |
| 4 | 当前有活跃 req 时发出警告（不拦截） | PM 可能在 req worktree 里做事，quick-fix 同时在 main 上改可能引入合并复杂度。warn 让 PM 自行判断 |

**其他一切都允许**：行数不限、文件数不限、可新增文件、可改代码、可改文档。

> 红线 1/2 本来就被 `check-branch.sh` 的 Gate 1/2 强制。quick-fix 的检查只是"早拦一步"给 PM 更友好的错误提示，不是新增约束。

---

## 4. 工作流时序

```
PM: /quick-fix "<一句话描述>"

Skill 事前检查：
  - 有活跃 req？→ warn（不拦）
  - （红线 3 路径在事后 diff 检查，此处无需事前判断）

Skill 建隔离环境：
  - 生成分支名 tmp-quick-<unix-ts>
  - git worktree add .worktrees/quick-fix-<ts> -b tmp-quick-<ts> main
  - 按项目根的包管理配置 symlink 依赖（复用 create-task-worktree.sh 逻辑）
  - cd 到 .worktrees/quick-fix-<ts>/ 提示 AI 在此工作

AI 执行改动：
  - Edit/Write 改文件（临时分支，hook 不拦）
  - （Claude 自己读 PM 原始请求，决定动哪些文件）

Skill 事后检查：
  - git diff 看改动路径
  - 命中红线 3 → deny，清理环境
  - 改了 .ts / .tsx → 在 worktree 内跑 `tsc --noEmit`
    - 失败 → deny，提示 PM 让 AI 重改或取消
  - （可选）改了 .md → 跑 markdownlint

Skill 呈交 PM：
  - 输出完整 diff
  - 等 PM："通过" / "重做" / "取消"

PM 决策后：
  - 通过：
    a. cd 主仓
    b. git merge --ff-only tmp-quick-<ts>
       - 失败（main 已前进）→ 提示 PM：主仓已变，请 rebase tmp-quick-<ts> 后重试
    c. 写入 commit message（见 §7）
    d. 追加一行到 QUICKFIX_LOG.md（见 §7）
    e. git add QUICKFIX_LOG.md + amend 进 merge commit
    f. git worktree remove .worktrees/quick-fix-<ts>
    g. git branch -d tmp-quick-<ts>
  - 重做：
    a. 保留 worktree 和分支
    b. 回到"AI 执行改动"，让 AI 按 PM 反馈重改
  - 取消：
    a. git worktree remove --force
    b. git branch -D tmp-quick-<ts>
    c. main 完全不变
```

---

## 5. 隔离机制（worktree）

### 5.1 为什么要隔离

PM 的 dev server 可能在主仓 main 分支上运行。如果 quick-fix 只是 `git checkout -b` 切分支，dev server 看到的就是临时分支上的（未经审阅）改动——容易误导判断。

用 worktree 做隔离：
- 主仓 main 分支**完全不动**，dev server 不受影响
- 临时 worktree 独立目录，AI 在那里改
- merge 回 main 时是一个原子操作

### 5.2 目录约定

- 路径：`.worktrees/quick-fix-<unix-ts>/`
- 分支：`tmp-quick-<unix-ts>`
- 带 `tmp-` 前缀是故意的，hook Gate 4 只识别 `task-*` / `req-*`，`tmp-*` 不在任何 gate 的特殊规则里

### 5.3 依赖 symlink

复用 `create-task-worktree.sh` 的通用化策略：
- `package.json` → symlink `node_modules`
- `Gemfile` → symlink `vendor/bundle`
- `go.mod` → symlink `vendor`

这样 worktree 里能直接跑 tsc / 测试工具，不用重装依赖。

### 5.4 清理

- 正常 merge 后：`git worktree remove` + `git branch -d`
- 取消：`git worktree remove --force` + `git branch -D`
- merge 失败（冲突）：保留 worktree，提示 PM 手工处理（rebase 或放弃）

---

## 6. 自动检查：tsc 兜底

### 6.1 触发条件

改动涉及 `.ts` / `.tsx` / `.mts` / `.cts` 文件时自动触发。

### 6.2 命令

在 worktree 内：
```bash
bun tsc --noEmit
# 或 npx tsc --noEmit，根据项目包管理
```

### 6.3 失败处理

- tsc 返回非零 → skill 拒绝 merge
- 输出 tsc 的错误到 PM
- 让 PM 选择：让 AI 重改 / 取消 / 强制通过（加 `--force` flag）

### 6.4 为什么要这道护栏

PM 只靠眼看 diff，难以发现类型错误。比如改了一个 interface 字段名没改所有引用，diff 里看不出来，tsc 能秒发现。

---

## 7. 历史记录

**不建 req 目录、不建 task 文件、不建 event log**。历史靠两个机制：

### 7.1 commit message 规范

每个 quick-fix merge commit 的 message 格式：

```
[quick-fix] <一句话描述，来自 PM 请求>

目标: <改动的文件列表，逗号分隔>
变更: +N -M 行
临时分支: tmp-quick-<ts>（已合并并删除）
```

示例：
```
[quick-fix] INDEX.md 把 025 状态从执行中改为已实现

目标: docs/modules/INDEX.md
变更: +1 -1 行
临时分支: tmp-quick-1714543211（已合并并删除）
```

前缀 `[quick-fix]` 是唯一识别标志。

### 7.2 QUICKFIX_LOG.md（项目根，入库）

一份累积的摘要文件，每次 quick-fix 追加一行：

```markdown
# Quick-fix 历史

> 每次 `/quick-fix` 执行后自动追加。按时间倒序（最新在上）。

| 时间 | 目标 | 描述 | commit |
|------|------|------|--------|
| 2026-04-23 15:10 | prototypes/src/.../Button.tsx | padding 16→24 | def5678 |
| 2026-04-23 14:30 | docs/modules/INDEX.md | 更新 025 状态为已实现 | abc1234 |
```

入库方式：
- init-project.sh 创建空的 QUICKFIX_LOG.md
- 每次 merge 时 skill 追加一行
- 作为 merge commit 的一部分一并提交

### 7.3 查询

- 列最近：`git log --grep '^\[quick-fix\]' --oneline -20`
- 近 7 天：`git log --grep '^\[quick-fix\]' --since '7 days ago'`
- `/status` 增加"最近 5 条 quick-fix"section（调用 git log）

---

## 8. 与 /new-req 的分界

skill **不**替 PM 判断"该走哪边"。由 PM 自行判断：

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

这是指南，不是硬规则。PM 判断失误了（比如用 quick-fix 做了个大改，回头后悔没留下 req 记录），框架不帮他兜底。

---

## 9. 实现清单

### 9.1 新增

| 文件 | 功能 |
|------|------|
| `scripts/quick-fix.sh` | skill 主入口，串起 worktree 建立 / tsc 检查 / merge / 清理 |
| `skills/quick-fix/SKILL.md` | Claude Code skill 定义（preamble + 引导 AI 行为） |
| `templates/QUICKFIX_LOG.md.tmpl` | init 时写入的空日志文件 |

### 9.2 修改

| 文件 | 修改点 |
|------|--------|
| `scripts/init-project.sh` | 复制 QUICKFIX_LOG.md.tmpl 到项目根 |
| `scripts/status-view.py` | 增加"最近 quick-fix"section（git log 查询） |
| `templates/gitignore.tmpl` | 不变（QUICKFIX_LOG.md 要入库，不 ignore） |

### 9.3 不需要改 hook

`tmp-quick-*` 分支不被 Gate 3/4 拦截（Gate 3 只拦 main/master，Gate 4 只拦 `task-*` / `req-*`）。hook 天然兼容。

---

## 10. 未决问题 / 边界情况

### 10.1 活跃 req 时的并发

quick-fix 在 main 上做一个 merge commit，同时 PM 在 req worktree 里做事。req close 时会 merge 回 main。如果 main 上 quick-fix 的 commit 和 req 的改动冲突，close-req 会遇到 merge 冲突。

**处理**：不在 quick-fix 侧加特殊逻辑，由 close-req 的正常冲突处理走。quick-fix 只 warn 一次"当前有活跃 req，quick-fix 的 merge 可能引入后续冲突"。

### 10.2 merge --ff-only 失败

main 在 quick-fix 期间前进了（极少发生，因为 PM 单线程）。

**处理**：保留 worktree 和分支，提示 PM：
```
主仓 main 已前进。可选：
1. 在 worktree 内 rebase：cd .worktrees/quick-fix-<ts> && git rebase main
2. 取消本次 quick-fix：/quick-fix --cancel <ts>
```

### 10.3 worktree 残留

如果 skill 中途崩溃或用户强杀，`.worktrees/quick-fix-<ts>/` 可能留下来。

**处理**：
- init-project 之后首次执行 quick-fix 时，扫描 `.worktrees/quick-fix-*`，列出残留让 PM 决定清理
- 也可以加一个 `/quick-fix --cleanup` 子命令

### 10.4 tsc 很慢

Next.js / 大型 TS 项目 tsc 可能要 30 秒+。quick-fix 每次等半分钟体感差。

**处理**：
- v1 接受这个成本
- v2 考虑 `--incremental` 或只对改动文件做类型检查
- 或者引入 `--skip-tsc` flag 让 PM 明确跳过

### 10.5 PM 在 worktree 里手工改完忘了让 skill merge

worktree 是 .gitignore 的，手工改完不做 merge，改动就丢了。

**处理**：SKILL.md 里明确写"改完必须通过 skill 收口"。v2 考虑加一个"未提交 worktree 告警"在 skill-preamble.sh 里。

---

## 11. 实现顺序

| 批次 | 内容 |
|------|------|
| 1 | `QUICKFIX_LOG.md.tmpl` 模板 |
| 2 | `scripts/quick-fix.sh` 主脚本（含 worktree 建立、tsc、merge、清理） |
| 3 | `skills/quick-fix/SKILL.md` |
| 4 | `scripts/init-project.sh` 追加 QUICKFIX_LOG.md 复制 |
| 5 | `scripts/status-view.py` 追加 quick-fix section |
| 6 | 测试：构造几个典型场景（纯文档、代码改、tsc 失败、活跃 req 冲突、取消） |

---

## 12. 决策记录

| # | 问题 | 决策 | 理由 |
|---|------|------|------|
| 1 | 走不走 req stage？ | 不走。独立快捷路径 | 避免每次小改都产生 req/task 目录，防止"目录爆炸" |
| 2 | 允许改哪些文件？ | 不限类型，只守红线 | PM 要灵活性，"文件类型"不是好边界，"数据完整性"才是 |
| 3 | 改动大小上限？ | 不设 | PM 自己判断"该走哪边"，skill 不替判断 |
| 4 | 代码改动要不要兜底？ | 要，跑 tsc --noEmit | 眼看 diff 难发现类型错，tsc 秒发现 |
| 5 | 要不要 worktree 隔离？ | 要 | 主仓 main 不动，dev server 不受影响 |
| 6 | 历史怎么留？ | commit message 前缀 + QUICKFIX_LOG.md 入库 | 不建新目录，用 git 本身做 authoritative 源 |
| 7 | 跟 /new-req 怎么分？ | 给指南表，不给硬规则 | 判断交给 PM，框架不替判 |
| 8 | 改 hook 吗？ | 不改 | `tmp-quick-*` 分支前缀天然不被任何 Gate 拦 |
