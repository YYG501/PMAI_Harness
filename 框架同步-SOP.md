# 框架同步 SOP（手动操作手册）

**性质**：hotfix 阶段过渡用。等 `设计-框架同步.md` §5 sync 脚本实施完成后，本文档撤销，改用脚本。

**适用对象**：PM 把 PM-AI-Workflow 生成器仓的 `scripts/` `skills/` 同步到下游消费项目（example-consumer-app / ExampleConsumerB 等）。

**关联文档**：
- `设计-框架同步.md`（v1 定稿 2026-04-26，853 行）：完整 sync 机制设计（manifest + 脚本 + worktree 报告）
- `TODOS.md` §UP「框架同步方案」：实施跟踪（标"设计完成，待实施"）

---

## 1. 何时需要同步

| 触发 | 说明 |
|---|---|
| PM-AI-Workflow main 分支有新 commit | feat / fix / refactor 影响 `scripts/` 或 `skills/` |
| 下游消费项目要用新版 | 续 active req（如 req-003）或起新 req（基于 main fork） |
| 实战暴露 hotfix | 如 task-002 撞 I-CT8（2026-05-08 case） |

不需要同步的场景：

- PM-AI-Workflow 改动只在 `tests/` / `设计-*.md` / `STATUS-*.md` / `TODOS.md` —— 这些不下发
- PM-AI-Workflow 在改 `INVARIANTS.md` / `README.md` / `CLAUDE.md` —— 这些是生成器自身文档，不同步

---

## 2. 同步范围

### 2.1 必同步路径

```
PM-AI-Workflow              example-consumer-app
─────────────────────       ───────────────────────
scripts/             →      .claude/scripts/
skills/              →      .claude/skills/
```

> 未来 manifest（设计-框架同步.md §4.2）会扩展到 `templates/` `agents/`，本 SOP 暂不覆盖。

### 2.2 必同步分支

| 分支 | 何时同步 |
|---|---|
| **main** | 每次 sync。理由：下次起新 req 基于 main fork |
| 每个 active **req-NNN** 分支 | 每次 sync。理由：续 req 的 task close-task / close-req 用最新框架 |

不同步的分支：

- `backup/*`（历史快照）
- `closed/*` 状态的 req（已 merge 到 main，不再活跃）

---

## 3. 标准操作步骤

### 步骤 1：看上次同步时点

```bash
# 在消费仓里看
git log --format='%h %ai %s' .claude/scripts/ | grep '同步框架' | head -1
# 输出例：d9df3f8 2026-05-07 16:24:58 +0800 chore: 同步框架 — ...
```

记下 hash 跟时间。

### 步骤 2：看 PM-AI-Workflow 主仓累积变更

```bash
cd /path/to/PM-AI-Workflow
git log --since='<上次 sync 时间>' --format='%h %ai %s' main
```

筛掉只动 `tests/` `设计-*.md` 等不下发文件的 commit。剩下的就是这次要同步的 commits 清单。

### 步骤 3：rsync 同步内容

```bash
SRC=/path/to/PM-AI-Workflow
DST=/path/to/consumer  # 可以是消费仓主目录或 worktree

rsync -a "$SRC/scripts/" "$DST/.claude/scripts/"
rsync -a "$SRC/skills/"  "$DST/.claude/skills/"
```

`-a` 保留属性 + 递归。**不加** `--delete`：消费侧未来可能有 `.framework-overrides` 类本地配置，留余地。

### 步骤 4：diff verify 100% 一致

```bash
diff -rq "$SRC/scripts/" "$DST/.claude/scripts/" 2>&1 | grep -v 'Common'
diff -rq "$SRC/skills/"  "$DST/.claude/skills/"  2>&1 | grep -v 'Common'
```

**两条命令输出都为空** = 100% 一致 = sync 内容正确。

### 步骤 5：commit

```bash
cd "$DST"
git add .claude/scripts/ .claude/skills/
git status --short  # 检查改动文件数 + untracked 目录（如新增 references/）

git commit -m "chore: 同步框架 — <一行摘要>

涵盖 PM-AI-Workflow 主仓 commits（自上次 sync <hash>）:
- <hash 1> <subject>
- <hash 2> <subject>
- ...

涵盖文件:
- <主要文件 + 一行说明>
- ...

至此 .claude/scripts + .claude/skills 与 PM-AI-Workflow main 主仓内容 100% 一致。
"
```

### 步骤 6：多分支应用

main 分支同步完后，每个 active req 分支重复步骤 3-5：

**req 分支已有 worktree**（如 .superset / .codex 路径下）：直接在 worktree 里跑步骤 3-5。

**req 分支没 worktree**：

```bash
cd /path/to/consumer
git worktree add .worktrees/<req-name>-temp-sync <req-branch>
# 在 .worktrees/<req-name>-temp-sync 里跑步骤 3-5
git worktree remove .worktrees/<req-name>-temp-sync
```

---

## 4. 常见坑（来自 2026-05-08 实战）

### 4.1 不要把 diff `+`/`-` 看反

`diff -rq` 显示 "Files X and Y differ"，看具体 diff 时：

- PM-AI-Workflow（source of truth）通常是**新版本**
- 消费侧（example-consumer-app 等）通常是**老版本**
- `+` 行（新增）= 从 PM-AI-Workflow 来的内容
- `-` 行（删除）= 消费侧老版本要被替换的内容

**不要把消费侧老版本误判为"独有内容"导致放弃 sync**。

验证方式：看两边的 git log + 文件行数。新版本通常行数更多 / 时间戳更新。

### 4.2 别漏 main 分支

PM 容易只同步当前 active 的 req 分支，忘了 main。但下次起新 req 是基于 main fork，main 滞后 = 新 req 一开始就是老版本。

每次都同步：main + 全部 active req。

### 4.3 别漏新增目录

PM-AI-Workflow 偶尔加新子目录（如 `skills/task-spec/references/`）。

`rsync -a` 自动 cover 新目录。但 `git status` 会显示 `??` 而不是 `M`，PM 容易忽略。**记得 `git add .claude/` 时把 untracked 一起加**。

### 4.4 worktree 在哪不固定

req 分支的 worktree 可能在：

- `<consumer>/.worktrees/<branch>/`（默认 `git worktree add` 路径）
- `~/.superset/worktrees/<uuid>/<branch>/`（Superset 模式）
- `~/.codex/worktrees/<id>/<branch>/`（Codex 模式）

用 `git worktree list` 查清单，别假设位置。

### 4.5 commit message 要列覆盖的 commits

后续 sync 要靠这个 commit message 反推上次 sync 时点。message 里**必须**列：

- 上次 sync 的 hash
- 这次涵盖的 PM-AI-Workflow commits（hash + subject）

否则下次 sync 时 PM 又得 grep 历史 commit message 反推。

### 4.6 临时 worktree 记得删

给 req 分支建的 `.worktrees/<req>-temp-sync` 临时 worktree，sync commit 完了一定要删（`git worktree remove`），否则 worktree list 越积越多。

---

## 5. 实战记录

### 5.1 2026-05-08 example-consumer-app sync

**触发**：example-consumer-app task-002 撞 I-CT8 卡 38min + 60k token，hotfix（A1 audit 豁免 + R1 半 close 闭环）+ 累积 12 commit 一次性 sync。

**范围**：
- 涵盖 PM-AI-Workflow main 自 2026-05-07 16:24 (`d9df3f8`) 之后 12 commits
- 同步分支：main + req-003-tenant-console-redesign-v2 + req-004-billing-redesign

**成果**：
- main: `3e17647` chore: 同步框架 — close-task A1 + R1 + PM-VIEW-RULES + 反馈循环 + ...
- req-003: 两 commit `e1f25d9` (4 文件 hotfix) + `1136edf` (补全 12 文件)
- req-004: 两 commit `86c31dc` + `09042bf`

**统计**：
- 改动文件：scripts 2 + skills 9 + task-spec/references/ 目录新增
- 改动行数：+717 -213（主体）+ +141 -8（hotfix）

**踩到的坑**：
- 第一次 cp 4 个文件后看 diff 把 `+`/`-` 看反，误判为"example-consumer-app 比 PM-AI-Workflow 更新"，差点放弃 sync。看 commit log 行数才纠正（见 §4.1）
- 第一次只 sync 4 个 hotfix 直接相关文件，漏了上次 sync 之后另外 11 个文件（见 §4.2 / §4.3）

### 5.2 2026-04-26 example-consumer-app sync（历史参考）

详见 `设计-框架同步.md` §1，6 痛点（P1-P6）当时由那次实战暴露。

---

## 6. 何时撤销本 SOP

`设计-框架同步.md` §5 `scripts/sync-to-consumer.sh` 实施完成后：

- 本 SOP 移到 `设计-框架同步.md` 末尾作为"附录：手动 SOP（已废弃）"
- TODOS.md 把"框架同步方案"标记为"已实施"
- 单独的 `框架同步-SOP.md` 可删

预计触发时点：v3.5 实施完成 + 框架结构稳定（最近一个月内 PM-AI-Workflow 主仓没有大改 scripts/ 顶层结构 / 没有 SKILL 重命名）。
