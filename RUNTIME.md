# RUNTIME

> 当前运行状态真相源。历史迁移流水账看 git history / `CHANGELOG.md` / `docs/归档/`，本文件只保留当前有效模型。

## 当前位置

- 日期：2026-06-23
- 分支：`main`
- 旧主分支备份：`codex/backup-main-before-task-cleanup-20260622-221253`
- 当前清理目标：移除旧 `req` / `task` / 阶段推进残留，不保留兼容层。

## 当前活跃模型

- 用户入口：`/pmai-init-project` → `/pmai-design` → `/pmai-build` → `/pmai-close`，旁路入口为 `/pmai-status`、`/pmai-cancel`、`/pmai-quick-fix`、`/pmai-prd-writing`。
- 不再使用：`/pmai-next`、`/pmai-new-req`、`/pmai-req-stage-gate`、旧 task 状态机。
- 模块真相源：`docs/modules/<模块>/discussion.md`、`decisions.md`、`spec.md`。
- 临时工作状态：`docs/modules/<模块>/.work-meta.json`。该文件只表示“正在做”，close/cancel 后删除，不留下 `closed` / `cancelled` 占位。
- 分支/worktree：实现隔离只认 `build-*`。不再创建 `req-*`，也不保留通用 `work-*` 兼容分支。
- stage 字段：只作状态展示提示，不再有单独 transition helper，不作为 close 硬门。

## 已完成清理

- 删除旧入口和脚本：`skills/next`、`create-req-*`、`req-transition.py`、`req-events.py`、旧迁移脚本、TTHW smoke、stage-source helper 测试。
- `cancel-req.sh` / `close-req.sh` 改名为 `cancel-work.sh` / `close-work.sh`，测试同步为 `test-cancel-work.sh` / `test-close-work.sh`。
- `status-view`、`skill-preamble`、`state.py` 改为扫描 `build-*`。
- `check-branch` 删除旧 stage 直改拦截，只保留 main 业务代码写保护。
- `close-work` 删除 stage=4 硬门，改为 PM 明确确认后收尾。
- `cleanup-pending-worktrees` pending 项改为 `kind=work` + `build-*` 安全校验。
- 删除活跃 `docs/设计/` 旧设计稿，避免把过期方案当当前真相源。

## 剩余验证

- 在一个真实业务模块上跑完整 `/pmai-design` → `/pmai-build` → `/pmai-close`，验证三道 build 审计、dev server 复用、worktree 创建/合并/清理闭环。

## 本轮验证

- `tests/run-all.sh`：278 passed / 0 failed。
