# 框架同步 SOP（手动操作手册）

**性质**：hotfix 阶段过渡用。等 `docs/归档/完成/设计-框架同步.md` §5 sync 脚本实施完成后，本文档撤销，改用脚本。

**适用对象**：PM 把 PM-AI-Workflow 生成器仓的 `scripts/` `skills/` 同步到下游消费项目（example-consumer-app / ExampleConsumerB 等）。

**关联文档**：
- `docs/归档/完成/设计-框架同步.md`（v1 定稿 2026-04-26，853 行）：完整 sync 机制设计（manifest + 脚本 + worktree 报告）
- `TODOS.md` §UP「框架同步方案」：实施跟踪（标"设计完成，待实施"）

---

## 1. 何时需要同步

| 触发 | 说明 |
|---|---|
| PM-AI-Workflow main 分支有新 commit | feat / fix / refactor 影响 `scripts/` 或 `skills/` |
| 下游消费项目要用新版 | 续 active req（如 req-003）或起新 req（基于 main fork） |
| 实战暴露 hotfix | 如 task-002 撞 I-CT8（2026-05-08 case） |

不需要同步的场景：

- PM-AI-Workflow 改动只在 `tests/` / `docs/归档/完成/设计-*.md` / `STATUS-*.md` / `TODOS.md` —— 这些不下发
- PM-AI-Workflow 在改 `INVARIANTS.md` / `README.md` / `CLAUDE.md` —— 这些是生成器自身文档，不同步

---

## 2. 同步范围

### 2.1 必同步路径（4 块缺一不可）

```
PM-AI-Workflow              example-consumer-app
─────────────────────       ───────────────────────
scripts/             →      .claude/scripts/
skills/              →      .claude/skills/
templates/           →      templates/
agents/              →      .claude/agents/
```

**4 块缺一不可**——只 sync `scripts/skills` 漏掉 `templates/` 会让模板源（如 `templates/CLAUDE.md.tmpl` / `templates/工程结构约束-*.md`）滞后；漏 `agents/` 会让自定义 subagent 不下发。判定"对齐"的唯一标准是 4 块的 `diff -rq` 全部零差异，参见 §4.8。

> 历史注：v0 SOP 只 cover `scripts/skills`，注"未来 manifest 扩展到 templates/agents"。2026-05-10 example-consumer-app sync 实战把 templates 漏掉了，本节扩展到 4 块。完整 manifest 设计仍见 `docs/归档/完成/设计-框架同步.md` §4.2。

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

### 步骤 0：前置检查 + 列消费仓 worktree 清单（**强制**）

**0a. 双方 working-dir clean 检查**

```bash
# 生成器侧
cd /path/to/PM-AI-Workflow
git status --short    # 必须空。有未 commit 改动 = sync 出去的是 unauthorized 内容，停手。

# 消费仓侧
cd /path/to/consumer
git status --short    # 必须空。有未 commit 改动 = rsync 会静默覆盖本地工作，停手。
```

任一不空 → 先 commit / stash 再回来。

**0b. 列消费仓所有 worktree 清单**

```bash
cd /path/to/consumer
git worktree list --porcelain | grep -E '^worktree |^branch '
```

记下输出，这是步骤 6（多分支应用）要遍历的 *完整* 目标清单。**不要假设 worktree 都在 `.worktrees/`**——conductor / superset / codex 路径下的 worktree 必须显式扫到，否则该 req 分支拿不到 sync。

> 例子：本仓 `git worktree list --porcelain` 可能输出 `worktree ~/.superset/worktrees/abc/req-003-foo`——这条必须出现在步骤 6 的目标清单里。

### 步骤 1：看上次同步时点

**1a. 优先读 lockfile**（精确，按 [`docs/归档/完成/设计-框架同步.md`](docs/归档/完成/设计-框架同步.md) §5.3 主锚点）

```bash
# 在消费仓根读 lockfile（git tracked，不会因 commit message 操作丢失）
cd /path/to/consumer
python3 -c "import json; print(json.load(open('.framework-sync-state.json'))['last_synced']['generator_sha'])"
# 输出例：76abc71
```

`.framework-sync-state.json` schema:
```json
{
  "schema_version": 1,
  "last_synced": {
    "generator_sha": "<生成器 commit sha>",
    "generator_repo": "PM-AI-Workflow",
    "synced_at": "<ISO 8601 时间戳>",
    "manifest_schema": 1
  }
}
```

每次 sync 完成后必须更新 `generator_sha` + `synced_at`（步骤 5 模板）。

**1a-fallback：trailer 查**（lockfile 缺失或损坏时用）

```bash
# 在消费仓里看（path 限定到 lockfile，避免 trailer 漂到无关 commit）
git log -1 --grep='^Generator-HEAD:' --format='%h %ai %s%n%b' .framework-sync-state.json
# 输出例最末一行：Generator-HEAD: 76abc71
```

trailer 是步骤 5 commit 模板辅锚点（人类可读副本）。

**1b. fallback：按 commit message 反推**（v0 旧仓兼容；lockfile + trailer 都没建立时用）

```bash
git log --format='%h %ai %s' .claude/scripts/ | grep '同步框架' | head -1
# 输出例：d9df3f8 2026-05-07 16:24:58 +0800 chore: 同步框架 — ...
```

记下 hash 跟时间。建议同时跑 1a-fallback 验证。

### 步骤 2：看 PM-AI-Workflow 主仓累积变更

```bash
cd /path/to/PM-AI-Workflow
# 用 path 限定，只列影响 sync 的 commit；hash..HEAD 用步骤 1 拿到的上次 generator HEAD
git log <上次 generator HEAD>..HEAD --format='%h %ai %s' -- scripts/ skills/
```

`-- scripts/ skills/` 限定路径直接过滤掉只动 `tests/` `docs/归档/完成/设计-*.md` 等不下发文件的 commit，**比 `--since=` 时间过滤更精确**——不会因为时区 / 时间戳跳变把无关 commit 带进来，也不会漏过去很久前但仍在 sync 范围的 commit。

> fallback：步骤 1 走 1b 没拿到精确 hash → 改用 `--since='<上次 sync 时间>' -- scripts/ skills/`，仍然记得加 path 限定。

### 步骤 3：rsync 同步内容

**3a. dry-run 先看变更清单**（**必跑、4 块都要**）

```bash
SRC=/path/to/PM-AI-Workflow
DST=/path/to/consumer  # 可以是消费仓主目录或 worktree

rsync -anc -iv --exclude='init-project/' "$SRC/skills/"    "$DST/.claude/skills/"
rsync -anc -iv --exclude='init-project.sh' "$SRC/scripts/" "$DST/.claude/scripts/"
rsync -anc -iv "$SRC/templates/"                           "$DST/templates/"
rsync -anc -iv "$SRC/agents/"                              "$DST/.claude/agents/"
```

`-c`（checksum）替代默认 mtime+size，避免"timestamp 不同但内容一致"的误报。

`-iv` 输出每个文件的变更标记：

- `>f.st....` = 文件内容会被覆盖
- `>f+++++++` = **新文件**（重点关注，对应坑 §4.7：跨文件依赖原子性）
- `cd+++++++` = **新目录**（对应坑 §4.3）
- 没有输出 = 无变更

PM 看一眼变更清单，跟步骤 2 列的 commits 对得上 → 进入 3b。**新文件 / 新目录数量异常高**（如步骤 2 只显示 3 commit 但 dry-run 列 50 个新文件）→ 停手排查，可能 path 配错或消费仓没初始化过 `.claude/`。

**3b. 实跑**（4 块都要）

```bash
rsync -ac --exclude='init-project/'    "$SRC/skills/"    "$DST/.claude/skills/"
rsync -ac --exclude='init-project.sh'  "$SRC/scripts/"   "$DST/.claude/scripts/"
rsync -ac                              "$SRC/templates/" "$DST/templates/"
rsync -ac                              "$SRC/agents/"    "$DST/.claude/agents/"
```

`-a` 保留属性 + 递归；`-c` 按 content checksum 比较（与 dry-run 对齐）。**不加** `--delete`：消费侧未来可能有 `.framework-overrides` 类本地配置，留余地。

`init-project` skill 和 `init-project.sh` 仅生成器仓使用，必须 `--exclude`。

仅在确认要清掉 dst 多余 framework 残留（如旧版本删除的废弃文件）时才加 `--delete`。

### 步骤 4：diff verify（**强制 + 方向校验**）

**4a. 内容一致性**（不可跳过、4 块都要）

```bash
diff -rq "$SRC/skills/"    "$DST/.claude/skills/"    2>&1 | grep -v -E "^(Common|Only.*: init-project)"
diff -rq "$SRC/scripts/"   "$DST/.claude/scripts/"   2>&1 | grep -v -E "^(Common|Only.*: init-project\.sh)"
diff -rq "$SRC/templates/" "$DST/templates/"         2>&1 | grep -v 'Common'
diff -rq "$SRC/agents/"    "$DST/.claude/agents/"    2>&1 | grep -v 'Common'
```

**4 条命令输出全为空** = 100% 一致 = sync 内容正确。**任一行有输出 → 立即停手排查**（参见 §4.8——只 diff 1-2 块就声称对齐是这次实战的主要踩坑）。

**4b. 方向 sanity check**（防 4.1 看反陷阱）

rsync 之前在消费仓里的文件如果**比 generator 还新**，要么消费侧有未上推的本地改动，要么 trade study 出错（消费仓应该是接收方，不是 source）。先比时间：

```bash
# 比对消费仓最近 .claude/scripts/ commit 时间 vs generator main 最近 scripts/ commit 时间
git -C "$DST" log -1 --format='%ai' -- .claude/scripts/
git -C "$SRC" log -1 --format='%ai' -- scripts/
```

generator 时间应**晚于或等于**消费仓时间。如果消费仓更晚 → 停手，先排查为什么消费侧有更新（4.1 实战教训：差点把消费仓老版本误判为"独有内容"放弃 sync）。

### 步骤 5：commit

```bash
cd "$DST"
git add .claude/scripts/ .claude/skills/ .claude/agents/ templates/
git status --short  # 检查改动文件数 + untracked 目录（如新增 references/）

# 5a. 更新 lockfile（主锚点，按设计 §5.3）
GEN_HEAD=$(git -C "$SRC" rev-parse --short HEAD)
SYNCED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > .framework-sync-state.json <<JSON
{
  "schema_version": 1,
  "last_synced": {
    "generator_sha": "$GEN_HEAD",
    "generator_repo": "PM-AI-Workflow",
    "synced_at": "$SYNCED_AT",
    "manifest_schema": 1
  }
}
JSON
git add .framework-sync-state.json

# 5b. commit 含 lockfile 改动 + trailer 副本
git commit -m "chore: 同步框架 — <一行摘要>

涵盖 PM-AI-Workflow 主仓 commits（自上次 sync <hash>）:
- <hash 1> <subject>
- <hash 2> <subject>
- ...

涵盖文件:
- <主要文件 + 一行说明>
- ...

至此 .claude/scripts + .claude/skills + templates + .claude/agents 与
PM-AI-Workflow main 主仓内容 100% 一致。

Generator-HEAD: $GEN_HEAD
"
```

> 双锚点机制（按设计 §5.3）：
> - **`.framework-sync-state.json` lockfile**（主）：git tracked，不会因 commit 操作丢失。**必更新**。
> - **`Generator-HEAD: $GEN_HEAD` trailer**（辅）：人类可读副本，让 PM 直接看 commit 就知道 anchor。**必填**。
>
> 单凭 trailer 不够：若 sync commit 没改 `.claude/` `templates/` `agents/`（如 empty commit / 锚点补丁），路径限定的 trailer grep 会漏掉它。lockfile path 限定能稳定命中。

### 步骤 5.5：sync 后冒烟（**强制**）

rsync + commit 完不代表 sync 成功。如果本次涵盖**新文件**（例如新 helper `_lib/xxx.sh` / `_lib/xxx.py` 或新 skill 子目录），其它脚本会 source / import 它——必须验脚本能 source / import 不崩，否则消费仓在下次 close-task / task-execute 才发现，已经晚了。

```bash
cd "$DST"

# 5.5a. skill-preamble（所有 skill 入口都 source 它，最敏感）
bash .claude/scripts/skill-preamble.sh </dev/null && echo OK || echo FAIL
# 期望：OK 或 preamble 输出（无 source / unbound variable / not found 错误）

# 5.5b. 关键写入端脚本 syntax check（不真跑，只验语法 + source 可达）
for s in close-task.sh close-req.sh cancel-req.sh create-task-worktree.sh create-req-worktree.sh quick-fix.sh; do
  bash -n .claude/scripts/$s && echo "✓ $s" || echo "✗ $s SYNTAX ERROR"
done

# 5.5b-py. 关键 Python 脚本 import 冒烟。bash -n 只验 shell 语法，验不出 Python
#          import 崩 —— §4.7 的 _lib/ 漏拷、或任何跨文件 import 断裂，shell 冒烟
#          抓不到，这段抓。exec_module 只跑 top-level imports + defs，不触发 main。
python3 -c "import sys; sys.path.insert(0,'.claude/scripts'); from _lib import state, events" \
  && echo "✓ _lib（state + events）import OK" \
  || echo "✗ _lib import FAIL —— 多半漏拷 scripts/_lib/，停手补全"
for s in task-transition.py audit-task-events.py; do
  python3 -c "import importlib.util,sys; sys.path.insert(0,'.claude/scripts'); _s=importlib.util.spec_from_file_location('_m','.claude/scripts/$s'); _m=importlib.util.module_from_spec(_s); _s.loader.exec_module(_m)" \
    && echo "✓ $s import OK" || echo "✗ $s IMPORT ERROR（见上方 traceback）"
done

# 5.5c. 配置文件 init 状态检查（lark-publish.json 等需 PM 手工 init 的）
echo "━━━ 配置文件 init 检查 ━━━"
if [ ! -f .claude/lark-publish.json ] && [ -f templates/lark-publish.json.tmpl ]; then
  echo "⚠️  .claude/lark-publish.json 不存在,publish-to-lark 会 fail。"
  echo "    init: cp templates/lark-publish.json.tmpl .claude/lark-publish.json"
  echo "    然后编辑 .claude/lark-publish.json 把 REPLACE_WITH_*_TOKEN 替换为真实 token。"
fi
# 未来若有别的需 init 的配置文件,继续加 if-not-exist 提示。
```

任一 FAIL / SYNTAX ERROR / IMPORT ERROR → **revert commit** 排查后再来：

```bash
git reset --hard HEAD~1   # 退回 sync 前
```

**5.5c 配置 init 不阻塞 sync 完成**（PM 可选择稍后 init），但 sync 时**必须提醒 PM** 哪些配置文件还要手工 init,避免 PM 真要发布时才发现配置缺失。

### 步骤 6：多分支应用

main 分支同步完后，遍历**步骤 0b 的 worktree 清单**，对每个 active req 分支重复步骤 3-5.5：

**req 分支已有 worktree**（步骤 0b 列出的——可能在 `.worktrees/`、`.superset/`、`.codex/` 或自定义路径）：cd 到那个具体路径跑步骤 3-5.5。**不要假设 `<consumer>/.worktrees/<req>`**。

**req 分支在 0b 清单里没出现**（可能历史 worktree 已删但分支还在）：

```bash
cd /path/to/consumer
git worktree add .worktrees/<req-name>-temp-sync <req-branch>
# 在 .worktrees/<req-name>-temp-sync 里跑步骤 3-5.5
git worktree remove .worktrees/<req-name>-temp-sync
```

> 每个分支跑完步骤 5.5 冒烟都要过；任一分支冒烟失败必须 revert 该分支的 sync commit。

---

## 4. 常见坑（来自 2026-05-08 实战）

### 4.1 不要把 diff `+`/`-` 看反（已硬卡入步骤 4b）

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

### 4.4 worktree 在哪不固定（已硬卡入步骤 0b）

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

### 4.7 跨文件依赖必须一起拷（原子性）

如果一次 sync 包含**新建的共享层**（例如 `scripts/_lib/xxx.sh` helper、`skills/_shared/yyy.md` 共享段），所有 source / import 它的脚本必须一起拷过去。**不能挑文件 sync**——挑了就崩。

识别方式：步骤 3a dry-run 输出里出现 `>f+++++++ scripts/_lib/...` 或 `cd+++++++ skills/_shared/...` → 把整个 `_lib/` `_shared/` 目录 + 所有调用方一起进。

**实战例子（2026-05-08 worktree 路径重构）**：

- 新文件 `scripts/_lib/worktree.sh`（helper 提供 `resolve_worktree_path` / `list_worktrees_by_branch_prefix`）
- 7 个调用方 `scripts/{close-task, close-req, cancel-req, create-task-worktree, create-req-worktree, quick-fix, skill-preamble}.sh`

如果 PM 心想"我只 sync 改动文件"漏拷 helper，consumer 下次 close-task 一跑 `source _lib/worktree.sh` 立即崩——步骤 5.5 冒烟就是为这个 case 设计。

**当前待同步项（2026-05-21 accept 闸门 / evidence-repair，generator commit `bd1f1a3` + `f37c83f`）**：

- 新文件 `scripts/_lib/events.py`（共享 `EXEC_EVENT_TYPES` / `has_execution_event` / `load_events_strict`）
- importers：`scripts/task-transition.py`（原本只 import `_lib.state`，现在多 import `_lib.events`）+ `scripts/audit-task-events.py`（**本次新成为 `_lib` 消费方**，之前完全不 import `_lib`）

下次 sync 必须把 `scripts/_lib/events.py` 一起带过去。漏了 → 消费仓 `task-transition.py`（验收转移 accept 闸门）和 `audit-task-events.py`（close-task I-CT7 审计）一 import 就 `ImportError` 崩。步骤 3a dry-run 会显示 `>f+++++++ scripts/_lib/events.py`——看见就确认整个 `_lib/` 都进了。

> 注：`scripts/_lib/` 是整目录 rsync 范围内（步骤 3 拷 `scripts/`），正常不会漏。本条是显式提醒：`audit-task-events.py` 这次从"非 `_lib` 消费方"变成"`_lib` 消费方"，是新耦合。

→ 步骤 3 默认是整目录 rsync，本节当作"看见新 helper 时多看一眼调用方都拷到了没"。

### 4.8 别只 diff `scripts/skills` 就声称对齐（已硬卡入步骤 4a）

判定"对齐"的唯一标准是 §2.1 4 块（scripts + skills + templates + agents）的 `diff -rq` **全部零差异**。只 diff 1-2 块就声称对齐是 2026-05-10 sync 的主要踩坑：

- 第二轮 sync 后只 diff 了 `scripts/skills`，得到"零差异"，声称"main 完全对齐"
- PM 让"复查"才发现 `templates/` 还差 5 个模板源文件（`CLAUDE.md.tmpl` / `module.md.tmpl` / `solution.md.tmpl` / `task-plan.md.tmpl` / `task.md.tmpl`）
- 这 5 个文件的内容差异跨多次主仓 commit 累积，但因为不在范围扫描内，从来没被注意到

固定改法：步骤 4a 的 4 条 `diff -rq` 命令一次性都跑，**任意一条非空就不算对齐**。

### 4.9 sync 工具 ≠ init-project.sh

不要在已 init 的项目上跑 `init-project.sh`：

- `init-project.sh` 是 init 时一次性占位符替换 + 创建目录骨架（替换 `{{PROJECT_NAME}}` / `{{PROJECT_BACKGROUND}}` 等）
- 已 init 项目的 `CLAUDE.md` / `docs/CONTEXT.md` / `docs/DESIGN.md` / `docs/prd.md` 是落地业务实例，**PM 已经写了业务背景**——再跑 init 会被空模板覆盖

sync（本 SOP）只动 framework 资产（4 块），不动业务实例。

附带：`init-project.sh` 自身有 bug——line 182 `cp "$SKILL_DIR"*` 用 glob 不递归子目录，导致 `references/` 子文件漏拷。新项目 init 后通常需要手工补 `references/` 子目录。这个 bug 本身要修生成器，不是本 SOP 范围。

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

详见 `docs/归档/完成/设计-框架同步.md` §1，6 痛点（P1-P6）当时由那次实战暴露。

### 5.3 2026-05-10 example-consumer-app sync

**触发**：prd-writing skill 大改（二级=动作组 / 三级=动作子项 + reorg pass + lint 兜底）后同步给 example-consumer-app。

**范围**：
- 涵盖 PM-AI-Workflow main 自上次 sync 以来 7 个 commit（含 prd-writing 改造、PM-VIEW v2 闸门、bundle 中间层删除、quick-fix 复审、I-DC1 文档落盘 gate 等）
- 同步分支：暂时只 main（其他 4 个 worktree 待后续 merge）

**成果**：
- main: `e87b812` + `2395e7a` + `6f96e61` 三个 commit 累积同步
  - `e87b812`：本次 prd-writing 直接改动 8 个文件（第一轮）
  - `2395e7a`：补 28 个之前历史 commits 漏同步的 framework 文件（第二轮）
  - `6f96e61`：补 5 个 templates 模板文件（PM 复查时发现的漏网之鱼）

**统计**：
- 改动文件：skills 14 个 SKILL.md + scripts 11 个 + templates 5 个 = 30 个；新增 1 + 删除 2
- 改动行数：+860 -802（含 bundle 中间层删除）

**踩到的坑**：
- 一次同步只拷当前直接改动 8 个文件（漏掉 28 个累积），见 §4.5 反面教训
- 第二轮声称"对齐"但只 diff `scripts/skills`，漏 templates 5 个文件，见 §4.8（新增）
- 这次开了一段弯路：写了简化版 sync 工具 + 重复 SOP 文档，复查发现已有完整 SOP 设计未实施 + 旧 SOP 文档存在，最后撤回工具 + 把发现合并回本 SOP（§4.8 / §4.9 + §2.1 范围扩展 + §3 步骤 4 块化）
- 事后按本 SOP 复查，5 个 sync commit 漏写 `Generator-HEAD` trailer，下次 sync 步骤 1a grep 会拿到过时锚点 `edb7fc6`（5-09 那次 sync）。按设计 §5.3 主锚点机制，example-consumer-app main 补 commit `2b50d2e`：创建 `.framework-sync-state.json`（`generator_sha = 76abc71`） + 写 trailer。同时更新本 SOP §1a 改用 lockfile 优先 + §5 commit 模板加 lockfile 自动更新（双锚点机制：lockfile 主、trailer 辅）落地。

---

## 6. 何时撤销本 SOP

`docs/归档/完成/设计-框架同步.md` §5 `scripts/sync-to-consumer.sh` 实施完成后：

- 本 SOP 移到 `docs/归档/完成/设计-框架同步.md` 末尾作为"附录：手动 SOP（已废弃）"
- TODOS.md 把"框架同步方案"标记为"已实施"
- 单独的 `框架同步-SOP.md` 可删

预计触发时点：v3.5 实施完成 + 框架结构稳定（最近一个月内 PM-AI-Workflow 主仓没有大改 scripts/ 顶层结构 / 没有 SKILL 重命名）。
