---
name: pmai-upgrade
version: 1.0.0
description: |
  升级 PMAI 框架到最新版本：拉远程 commit、re-sync skill symlink、AI 智能摘要
  CHANGELOG。PM 主动调 /pmai-upgrade 用此 skill。Voice triggers: 升级 PMAI / 升级框架 / pmai upgrade / 更新 pmai。
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

> **Inline 触发未实现**：当其他 skill preamble 检测 `UPGRADE_AVAILABLE` 时不会自动 invoke 本 skill；PM 需自己跑 `/pmai-upgrade`。未来如有"多人团队 / 升级强提醒"需求可扩 Inline 模式。

## When To Use

- PM 主动想升级框架到最新版（"升级 pmai" / "拉最新框架" / "看看更新了什么"）
- 升级类型：默认拉 `main` 最新 commit；可选 `--stable` 跳最新 git tag；可选 `--to v0.x.0` 锁定版本
- **不要**用此 skill 来：
  - 在消费仓 init 新项目 → 走 `/pmai-init-project`
  - vendored 老消费仓迁 I-mini → 走 `bin/pmai-migrate <consumer>` CLI

## Workflow

### Step 0：解析当前安装状态

```bash
PMAI_HOME="${PMAI_HOME:-$HOME/.pmai}"
if [ ! -d "$PMAI_HOME/.git" ]; then
  echo "❌ PMAI 未安装在 $PMAI_HOME。先跑 'pmai install'。"
  exit 1
fi
OLD_VER=$(cat "$PMAI_HOME/VERSION" 2>/dev/null || echo unknown)
OLD_HEAD=$(git -C "$PMAI_HOME" rev-parse --short HEAD 2>/dev/null || echo unknown)
echo "当前: v${OLD_VER} @ ${OLD_HEAD}"
```

### Step 1：探查远程新版本（决定升级模式）

```bash
"$PMAI_HOME/../Desktop/Projects/PM-AI-Workflow/bin/pmai-update-check" --force 2>&1 || true
# 或直接走 PATH: pmai update-check --force
git -C "$PMAI_HOME" fetch origin --tags 2>&1 | tail -5
LATEST_MAIN=$(git -C "$PMAI_HOME" rev-parse --short origin/main 2>/dev/null)
LATEST_TAG=$(git -C "$PMAI_HOME" tag -l 'v*' | sort -V | tail -1)
echo "远程 main HEAD: ${LATEST_MAIN}"
echo "远程最新 tag:    ${LATEST_TAG:-(none)}"
```

**判断是否需要升级**：

- 已是最新（`OLD_HEAD == LATEST_MAIN`，无 `--stable` 指令）→ 告诉 PM "已是最新 v${OLD_VER}"，**跳到 Step 6 继续 PM 原任务**
- 有更新 → 进 Step 2

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

按 Step 2 选择跑相应命令，**必须加 `--no-whats-new`**（skill 接管 What's New 智能摘要）：

```bash
# A 升级到 main 最新
pmai upgrade --no-whats-new

# B 升级到 latest tag
pmai upgrade --stable --no-whats-new

# C 锁定指定 tag
pmai upgrade --to v0.x.0 --no-whats-new
```

bin/pmai-upgrade 跑完会：
- 拉远程 commit / checkout tag
- 写 `~/.pmai-state/just-upgraded-from` 存 OLD_VER
- 清 `last-update-check` + `update-snoozed`
- re-sync `~/.claude/skills/pmai-*` symlink
- 因 `--no-whats-new`，**不**调 `bin/pmai-whats-new`

### Step 4：读 CHANGELOG OLD..NEW 段 + AI 智能摘要

```bash
NEW_VER=$(cat "$PMAI_HOME/VERSION" 2>/dev/null || echo unknown)
NEW_HEAD=$(git -C "$PMAI_HOME" rev-parse --short HEAD 2>/dev/null || echo unknown)
```

`Read $PMAI_HOME/CHANGELOG.md` 文件。找以下两段：

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
✅ PMAI 升级：v{OLD_VER} → v{NEW_VER}
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

完整 CHANGELOG: $PMAI_HOME/CHANGELOG.md
```

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

**已是最新场景**：
```
PM: /pmai-upgrade
AI: [Step 0/1] PMAI 已是最新（v0.2.2 @ {HEAD}）。无需升级。继续 PM 原任务。
```

**暂缓场景**：
```
PM: /pmai-upgrade
AI: [Step 2 AskUser]
PM: 选 D 暂缓 1 周
AI: [Step 2.D 子流程] 已写 snooze 到 1 周后。`pmai update-check` 1 周内静默退。
    要恢复升级提醒：rm ~/.pmai-state/update-snoozed
```
