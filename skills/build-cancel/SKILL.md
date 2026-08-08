---
name: pmai-build-cancel
description: |
  放弃已经进入 build 的模块工作：确认后不让本轮候选进入主线，清除进行中状态，相关工作环境由系统在安全时机自动清理。
---

# /pmai-build-cancel

## 入口护栏

执行本 skill 前先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止本 skill，只引导 PM 先发 `/pmai-init-project`。初始化或已有代码接入完成前，不要尝试取消 build、清理 worktree 或改项目状态。

> 本 skill 是 build 工作的退出口。它不判断需求是否“正确”，只在 PM 明确说这轮 build 不要继续时，把活跃状态清掉，避免后续 `/pmai-status` 继续把它当进行中工作。
>
> PM 视图规则按 `_shared/pm-view/banner-rules.md` 和 `_shared/pm-view/askuser-rules.md`：先确认，再执行；PM 未确认前不写文件、不 commit、不清理。

## When To Use

- PM 明确说当前 build 不要继续、废弃、取消、放弃。
- 当前模块已有 `.work-meta.json` 活跃状态，且已经进入 build / 隔离实现，需要清掉。
- 不用于完成收尾；PM 已验收时应回原 `/pmai-build` 续跑自动 finalize，只有兼容或恢复场景才用 `/pmai-build-close`；轻量记录走 `/pmai-record`。
- 不用于“设计讨论完先不实现”；这种情况不用取消 build，停住即可，若有稳定基线再走 `/pmai-record`。

## Preamble

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
echo "SKILL: build-cancel"

python3 "$PMAI_HOME/scripts/status-view.py" --banner-only --skill BUILD-CANCEL || true
```

## Workflow

### 步骤 1：确认放弃

先向 PM 确认：

```text
即将放弃当前 build：${ACTIVE_WORK}（当前阶段：${ACTIVE_WORK_STAGE_NAME}）

此操作会：
- 本轮候选不会进入主线
- 本轮尚未进入主线的实现改动会被放弃
- 已经在主线中的产品文档和历史决定会保留

确认放弃？（Y/N）
```

PM 犹豫或不确定时，建议先运行 `/pmai-status` 看清当前状态。

### 步骤 2：执行放弃

PM 确认后：

```bash
bash "$PMAI_HOME/scripts/cancel-work.sh" "$ACTIVE_WORK_DIR"
```

脚本真实行为：

1. 切回 main，并拒绝 main 上任何未提交改动，包括当前模块里未确认的 discussion / spec 修改。
2. 只暂存并提交当前模块 `.work-meta.json` 的删除（如果存在），清掉“正在做”的状态。
3. 把关联 worktree/branch 写入 `.runs/pending-cleanup.json`；后台确认没有会话仍停在该工作环境后再自动清理。

### 步骤 3：回执

```text
当前 build 已放弃。
本轮候选未进入主线，相关工作环境会在安全时机自动清理，不需要你运行清理命令。

▶ Next Up：
  新功能 / 重做模块：发 /pmai-design
```

## Rules

- 必须先问 PM 确认，不能静默放弃。
- 放弃不 merge 当前工作分支。
- cancel commit 只允许包含 `.work-meta.json` 删除，不顺带提交模块文档或其它 WIP。
- 不写 `status=cancelled`；新模型的语义是清掉活跃状态。
- 不手动删除 worktree/branch；只通过 `cancel-work.sh` 写 pending，再由后台清理机制在安全位置处理。
- PM 回执不得要求复制或运行清理命令，也不得让 PM 管理待清理队列。
- PM 面前说“当前 build / 模块工作”，不要再使用旧流程名。
