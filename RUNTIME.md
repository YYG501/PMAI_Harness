# RUNTIME

> 当前运行状态真相源。历史迁移流水账看 git history / `CHANGELOG.md` / `docs/归档/`，本文件只保留当前有效模型。

## 当前位置

- 日期：2026-06-28
- 分支：`main`
- 旧主分支备份：`codex/backup-main-before-task-cleanup-20260622-221253`
- 当前清理目标：移除旧 `req` / `task` / 阶段推进残留，不保留兼容层。

## 当前活跃模型

- 用户入口：`/pmai-init-project` → `/pmai-design` → `/pmai-build` → `/pmai-build-close`，旁路入口为 `/pmai-status`、`/pmai-direction`、`/pmai-record`、`/pmai-build-cancel`、`/pmai-quick-fix`、`/pmai-spec-writing`、`/pmai-doc-writing`、`/pmai-meta`（讨论换高度：升维 / 第一性原理，`/pmai-design` 段①②按需调）。
- 不再使用：`/pmai-next`、`/pmai-new-req`、`/pmai-req-stage-gate`、`/pmai-close`、`/pmai-strategy`、`/pmai-codebase-audit`、`/pmai-deposit`、`/pmai-cancel`、旧 task 状态机。
- 模块真相源：`docs/modules/<模块>/discussion.md`、`decisions.md`、`spec.md`。
- 临时工作状态：`docs/modules/<模块>/.work-meta.json`。该文件只表示“正在做”，build-close/build-cancel 后删除，不留下 `closed` / `cancelled` 占位。
- 分支/worktree：实现隔离只认 `build-*`。不再创建 `req-*`，也不保留通用 `work-*` 兼容分支。
- stage 字段：只作状态展示提示，不再有单独 transition helper，不作为 build-close 硬门。

## 已完成清理

- 删除旧入口和脚本：`skills/next`、`create-req-*`、`req-transition.py`、`req-events.py`、旧迁移脚本、TTHW smoke、stage-source helper 测试。
- `cancel-req.sh` / `close-req.sh` 改名为 `cancel-work.sh` / `close-work.sh`，测试同步为 `test-cancel-work.sh` / `test-close-work.sh`。
- `status-view`、`skill-preamble`、`state.py` 改为扫描 `build-*`。
- `check-branch` 删除旧 stage 直改拦截，只保留 main 业务代码写保护。
- `close-work` 删除 stage=4 硬门，改为 PM 明确确认后收尾。
- `cleanup-pending-worktrees` pending 项改为 `kind=work` + `build-*` 安全校验。
- 删除活跃 `docs/设计/` 旧设计稿，避免把过期方案当当前真相源。

## 剩余验证

- 在一个真实业务模块上跑完整 `/pmai-design` → `/pmai-build` → `/pmai-build-close`，验证三道 build 审计、dev server 复用、worktree 创建/合并/清理闭环。

## 本轮验证

- `/pmai-build` 已补构建前硬门：未提交规格 / mock / 文档先固定建造依据或停住；修改 `prototype/`、`Sources/` 或业务代码前必须拿到“执行方式”和“执行器”两道 PM 答案。
- `/pmai-build` / `/pmai-build-close` 已补 build 合同：build 在两道 PM 选择后写入 `.work-meta.json:build`，验收后记录实现提交和 PM 验收时间；build-close 只按合同收尾，缺合同 / 缺验收 / worktree 丢失时停止补上下文，不再把分支提交误报为已收口。
- `/pmai-status` 已改为 PM 行动视图：无 active 但有未提交改动时输出“有一轮改动还没收口”；多个进行中工作按编号列状态、当前步骤和下一步；禁止把内部诊断当现状汇报。
- 公开入口已收敛：`codebase-audit` 移入 `skills/_internal/`，不再暴露 `/pmai-codebase-audit`；`/pmai-deposit` 改为 `/pmai-record`；`/pmai-cancel` 改为 `/pmai-build-cancel`。
- `tests/test-doctor-skills.sh`：10 passed / 0 failed（含 `_internal` 不暴露回归）。
- `tests/test-brownfield-detect.sh`：6 passed / 0 failed（含 README 不暴露 `/pmai-codebase-audit` 回归）。
- `tests/test-banner-label.sh`：9 passed / 0 failed（核心入口改为 build-cancel）。
- `tests/test-check-branch.sh`：15 passed / 0 failed（record 不再依赖 marker 门控）。
- `tests/test-exec-adapters.sh`：8 passed / 0 failed（含 build 门禁回归）。
- `tests/test-status-view.sh`：7 passed / 0 failed（含 status PM 视图回归）。
- `tests/test-init-project-codex-compat.sh`：5 passed / 0 failed。
- `tests/test-private-onboarding.sh`：4 passed / 0 failed。
- `tests/test-mock-board.sh`：8 passed / 0 failed。
- `tests/run-all.sh`：324 passed / 0 failed。
- `git diff --check`：通过。
- 同类残留扫描：当前有效文件未再发现 `/pmai-close` / `pmai-close` / `skills/close` 的用户入口残留；仅保留历史 `requirements/pmai-closed` 路径名和内部 `close-work.sh` 实现脚本名。
