<!-- 状态：已消化（2026-06-28，待提交）；保留作历史档案 -->

# 公开入口命名反馈（2026-06-28）

## PM 反馈

1. `/pmai-codebase-audit` 不应该作为 PM 要记的单独 skill；已有代码接入应该由初始化自动分流。
2. `/pmai-deposit` 这个名字不好理解，需要改成更直观的轻量记录入口。
3. `/pmai-cancel` 应该收敛为 cancel build，避免和“设计讨论后先不实现”混淆。

## 消化结果

| # | 反馈类目 | 落地状态 | 落地位置 | 说明 |
|---|---|---|---|---|
| 1 | codebase-audit 公开入口 | 已落地 | `skills/_internal/codebase-audit/`、`bin/pmai-install`、`bin/pmai-upgrade`、`bin/pmai-doctor`、`bin/pmai-status` | 不再暴露 `/pmai-codebase-audit`；已有代码接入 / 恢复 / 重扫都回 `/pmai-init-project` 自动分流 |
| 2 | deposit 命名 | 已落地 | `skills/record/SKILL.md`、`skills/_shared/record-routing.md`、README / 模板 / 共享规则 | 公开命令改为 `/pmai-record`，语义为“轻量记录 / 写回稳定基线” |
| 3 | cancel 命名 | 已落地 | `skills/build-cancel/SKILL.md`、README / RUNTIME / PM-VIEW 共享规则 | 公开命令改为 `/pmai-build-cancel`，只表达“放弃已进入 build 的工作” |

## 设计口径

- 初始化是项目级入口；PM 不需要在“初始化 / 代码盘点”之间选命令。
- 只讨论清楚规格但暂时不 build，不需要 close，也不需要 cancel；可停住，或用 `/pmai-record` 写回稳定项目基线。
- build 已经开始但 PM 决定放弃，才使用 `/pmai-build-cancel`。
