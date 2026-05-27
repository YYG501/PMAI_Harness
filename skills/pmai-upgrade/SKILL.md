---
name: pmai-upgrade
version: 1.1.0
description: |
  升级 PMAI 框架到最新版本：自动检测全局 vs --local 模式、拉远程 commit、re-sync 副本、
  AI 智能摘要 CHANGELOG。PM 主动调 /pmai-upgrade 用此 skill。
  Voice triggers: 升级 PMAI / 升级框架 / pmai upgrade / 更新 pmai。
triggers:
  - 升级 PMAI
  - 升级框架
  - pmai upgrade
  - 更新 pmai
  - upgrade pmai
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# /pmai-upgrade

升级 PMAI 框架到最新 main / git tag 版本。**Standalone 用法**：PM 主动调用，AI 内部跑 `bin/pmai-upgrade` + 升级后用自然语言 5-7 bullet 总结 What's New。

**两种模式自动适配**：
- **全局模式**：`~/.pmai/` 存在 → `pmai upgrade` 拉 git pull
- **`--local` 模式**：当前 cwd 是 `--local` 安装目录（含 `.claude/.pmai-version`）→ `pmai upgrade --local "$PWD"` 重克隆覆盖

> **Inline 触发未实现**：当其他 skill preamble 检测 `UPGRADE_AVAILABLE` 时不会自动 invoke 本 skill；PM 需自己跑 `/pmai-upgrade`。

## When To Use

- PM 主动想升级框架到最新版（"升级 pmai" / "拉最新框架" / "看看更新了什么"）
- 升级类型：默认拉 `main` 最新 commit；可选 `--stable` 跳最新 git tag；可选 `--to v0.x.0` 锁定版本
- **不要**用此 skill 来：
  - 在消费仓 init 新项目 → 走 `/pmai-init-project`
  - vendored 老消费仓迁 I-mini → 走 `bin/pmai-migrate <consumer>` CLI

## Workflow

### Step 0：检测安装模式 + 解析当前版本

**关键**：cwd 优先于全局 —— 团队仓里 cwd 命中 `--local` 副本时按 `--local` 升，避免把队友的项目副本和你的全局副本搞混。

```bash
PMAI_HOME="${PMAI_HOME:-$HOME/.pmai}"

if [ -f "$PWD/.claude/.pmai-version" ]; then
  PMAI_MODE=local
  LOCAL_DIR="$PWD"
  OLD_VER=$(cat "$LOCAL_DIR/.claude/.pmai-version")
  OLD_HEAD=""  # --local 模式没有本地 git HEAD（副本不是 git 仓）
  echo "→ 模式：--local（target: $LOCAL_DIR）"
  echo "→ 当前: v${OLD_VER}"
elif [ -d "$PMAI_HOME/.git" ]; then
  PMAI_MODE=global
  OLD_VER=$(cat "$PMAI_HOME/VERSION" 2>/dev/null || echo unknown)
  OLD_HEAD=$(git -C "$PMAI_HOME" rev-parse --short HEAD 2>/dev/null || echo unknown)
  echo "→ 模式：全局（$PMAI_HOME）"
  echo "→ 当前: v${OLD_VER} @ ${OLD_HEAD}"
else
  echo "❌ PMAI 未安装（cwd 无 .claude/.pmai-version，~/.pmai/ 也不存在）"
  echo "   全局装：curl -fsSL https://raw.githubusercontent.com/YYG501/PMAI_Workflow/main/install.sh | bash"
  echo "   项目装：上述命令末尾加  -s -- --local $PWD"
  exit 1
fi
```

### Step 1：探查远程新版本（决定升级模式）

**全局模式**（可改本地状态）：

```bash
if [ "$PMAI_MODE" = "global" ]; then
  pmai update-check --force 2>&1 || true
  git -C "$PMAI_HOME" fetch origin --tags 2>&1 | tail -5
  LATEST_MAIN=$(git -C "$PMAI_HOME" rev-parse --short origin/main 2>/dev/null)
  LATEST_TAG=$(git -C "$PMAI_HOME" tag -l 'v*' | sort -V | tail -1)
fi
```

**`--local` 模式**（不能 fetch — 副本不是 git 仓；用 `git ls-remote` 探远程）：

```bash
if [ "$PMAI_MODE" = "local" ]; then
  REMOTE="${PMAI_REMOTE:-git@github.com:YYG501/PMAI_Workflow.git}"
  LATEST_MAIN=$(git ls-remote "$REMOTE" main 2>/dev/null | awk '{print substr($1,1,7)}')
  LATEST_TAG=$(git ls-remote --tags --sort=-v:refname "$REMOTE" 'refs/tags/v*' 2>/dev/null \
    | head -1 | awk -F/ '{print $NF}' | sed 's/\^{}$//')
fi
echo "远程 main HEAD: ${LATEST_MAIN}"
echo "远程最新 tag:   ${LATEST_TAG:-(none)}"
```

**判断是否需要升级**：

- **全局模式**：`OLD_HEAD == LATEST_MAIN` 且无 `--stable`/`--to` 指令 → "已是最新 v${OLD_VER}"，**跳 Step 6**
- **`--local` 模式**：没有 OLD_HEAD 可对比 → 总是进 Step 2 让 PM 拍板（即使版本号相同，让 PM 决定是否强制 re-sync）

### Step 2：AskUser 确认升级模式

`AskUserQuestion` 问 PM（4 选项）：

```
PMAI 有新版本可用（当前 v{OLD_VER}，远程 main = {LATEST_MAIN}{有 tag 时显示 tag 信息}）。

A) 升级到 main 最新（推荐 — 跟主开发线）
B) 升级到最新 stable tag（仅当 tag 存在；保守路径）
C) 锁定指定 tag（输入版本号）
D) 暂缓 — 1 天 / 1 周 / 永远（写 snooze）
```

> **暂缓机制**（D 子流程）：
> - 1 天 → 写 `~/.pmai-state/update-snoozed` UTC `$(date +%s)` + 86400
> - 1 周 → `+ 604800`
> - 永远 → 写一个远超未来值（如 `9999999999`），PM 想恢复就 `rm ~/.pmai-state/update-snoozed`
> 后续 `pmai update-check` 在 snooze 期内 silent skip。

### Step 3：调 bin/pmai-upgrade（关键 — 接管 What's New）

按 Step 0 检测的模式 + Step 2 选择跑相应命令，**必须加 `--no-whats-new`**（skill 接管 What's New 智能摘要）：

**全局模式**：
```bash
# A 升级到 main 最新
pmai upgrade --no-whats-new

# B 升级到 latest tag
pmai upgrade --stable --no-whats-new

# C 锁定指定 tag
pmai upgrade --to v0.x.0 --no-whats-new
```

**`--local` 模式**（多个 `--local <dir>` 参数指向当前目录）：
```bash
# A
pmai upgrade --local "$LOCAL_DIR" --no-whats-new

# B
pmai upgrade --local "$LOCAL_DIR" --stable --no-whats-new

# C
pmai upgrade --local "$LOCAL_DIR" --to v0.x.0 --no-whats-new
```

bin/pmai-upgrade 跑完会：
- **全局**：拉远程 commit / checkout tag、re-sync `~/.claude/skills/pmai-*` symlink、写 marker、清 update-check 缓存
- **`--local`**：mktemp 重克隆 + checkout → 覆盖 `<LOCAL_DIR>/.claude/{scripts,skills,agents}/` 实体副本 + 拷 CHANGELOG.md + 更新 `.pmai-version` + 写 marker、末尾打印 commit / push 提示
- 共同：因 `--no-whats-new`，**不**调 `bin/pmai-whats-new`

### Step 4：读 CHANGELOG OLD..NEW 段 + AI 智能摘要

**根据模式定 CHANGELOG 路径**：

```bash
if [ "$PMAI_MODE" = "global" ]; then
  NEW_VER=$(cat "$PMAI_HOME/VERSION" 2>/dev/null || echo unknown)
  NEW_HEAD=$(git -C "$PMAI_HOME" rev-parse --short HEAD 2>/dev/null || echo unknown)
  CHANGELOG_PATH="$PMAI_HOME/CHANGELOG.md"
else
  NEW_VER=$(cat "$LOCAL_DIR/.claude/.pmai-version")
  NEW_HEAD=""  # local mode 没本地 HEAD
  CHANGELOG_PATH="$LOCAL_DIR/.claude/CHANGELOG.md"
fi
```

`Read $CHANGELOG_PATH` 文件。找以下两段：

1. **「未发布」段**（从 `## 未发布` 到下一个 `## v` 或 `## ` 之间所有 `### ` 子条目）
2. **`## v$OLD_VER` 到 `## v$NEW_VER` 之间的 tag 段**（若有，按 semver 排序）

**AI 智能摘要规则**（5-7 bullet，按主题归类）：

- ✅ 优先：用户面 / PM 直接感知的改动（如新 skill / 新 CLI 命令 / 升级体验改善 / 行为变更）
- ✅ 优先：bug 修（PM 关心是否影响他在飞工作）
- ❌ 跳过：纯重构 / commit message 修复 / 注释级改动 / 测试调整（除非有 user-visible 副作用）
- 按主题分类（如「新增能力」「修复」「升级体验」「架构变更」）

**输出格式**：

```
═══════════════════════════════════════
✅ PMAI 升级：v{OLD_VER} → v{NEW_VER}{模式后缀: 全局 / --local <dir>}
═══════════════════════════════════════

🆕 What's New（AI 摘要）：

新增能力:
- <bullet 1>
- <bullet 2>

修复:
- <bullet 3>

升级体验 / 架构:
- <bullet 4>

═══════════════════════════════════════

完整 CHANGELOG: {CHANGELOG_PATH}
```

**`--local` 模式额外**：bin/pmai-upgrade 末尾已自动打印 `git add .claude/ + commit + push` 提示，AI 把此提示原样保留（不要改 commit message，PM 想改自己改）。

### Step 5：清 just-upgraded-from marker

```bash
rm -f "$HOME/.pmai-state/just-upgraded-from" 2>/dev/null || true
```

（marker 已用完，让下次 `pmai whats-new` 不再误读到本次升级）

### Step 6：继续 PM 原任务

升级完成。如果 PM 原本想做别的事（如启 req / 跑 task），继续走那个流程。如果 PM 单纯只是 `/pmai-upgrade`，结束 skill。

## Rules

- **必须**用 `pmai upgrade --no-whats-new`（不是裸 `pmai upgrade`）—— skill 接管 What's New 智能摘要
- **必须**用自然语言摘要（不是 cat 整段 CHANGELOG）—— 这是 skill 比 bin/ 多出来的核心价值
- AskUser 选 D 暂缓时**禁止**继续跑 Step 3（PM 决议 = binding contract）
- 升级失败时**禁止**清 marker（PM 后续 `/pmai-whats-new` 仍能看到上次升级未完成上下文）
- **`--local` 模式**：检测在 Step 0 自动完成（cwd 含 `.claude/.pmai-version` → local），**禁止**让 PM 显式选模式；mode 不是 PM 决策点
- **`--local` 模式末尾提示**：bin/pmai-upgrade 自动输出 `git add/commit/push` 指南，**禁止** AI 替 PM 跑这三条命令（PM 决定 commit message + 何时 push）

## Examples

**典型 PM 调用**：
```
PM: /pmai-upgrade
AI: [Step 0/1 跑 update-check] PMAI 有新版本可用（v0.2.1 → main {HEAD}）。
    [AskUser 4 选项]
PM: A
AI: [Step 3 跑 pmai upgrade --no-whats-new]
    [Step 4 读 CHANGELOG + 摘要]
    
    ✅ PMAI 升级：v0.2.1 → v0.2.2
    
    🆕 What's New：
    
    新增能力:
    - skills/pmai-upgrade/SKILL.md — PM 在 Claude Code 内 /pmai-upgrade 升级，含 AI 智能摘要
    
    修复:
    - bin/pmai dispatcher 路由表加 whats-new + migrate
```

**已是最新场景**（全局模式）：
```
PM: /pmai-upgrade
AI: [Step 0/1] PMAI 已是最新（v0.2.2 @ {HEAD}）。无需升级。继续 PM 原任务。
```

**团队仓 `--local` 升级场景**：
```
PM: /pmai-upgrade   （cwd 在 team-repo 目录）
AI: [Step 0] 模式：--local（target: /Users/me/team-repo）
        当前: v0.2.1
    [Step 1 ls-remote] 远程 main HEAD: a3b9c2d
    [Step 2 AskUser]
PM: A
AI: [Step 3 pmai upgrade --local "$PWD" --no-whats-new]
    [Step 4 读 .claude/CHANGELOG.md + 摘要]

    ✅ PMAI 升级：v0.2.1 → v0.2.2 (--local: /Users/me/team-repo)

    🆕 What's New：...

    📋 team 仓需 commit + push 让队友拿到新版：
       cd /Users/me/team-repo
       git add .claude/
       git commit -m 'chore: upgrade PMAI to v0.2.2'
       git push
```

**暂缓场景**：
```
PM: /pmai-upgrade
AI: [Step 2 AskUser]
PM: 选 D 暂缓 1 周
AI: [Step 2.D 子流程] 已写 snooze 到 1 周后。`pmai update-check` 1 周内静默退。
    要恢复升级提醒：rm ~/.pmai-state/update-snoozed
```
